/***************************************************************************
  splitheirutils.cpp - SplitHeirUtils

 ---------------------
 WorkField 24.10.2026 [WF-SPLIT-HEIR]. See splitheirutils.h.
 ***************************************************************************/

#include "splitheirutils.h"

#include "featureidentity.h"

#include <QDir>
#include <QLocale>
#include <QTimer>
#include <qgscoordinatetransform.h>
#include <qgsdistancearea.h>
#include <qgseditorwidgetsetup.h>
#include <qgsexception.h>
#include <qgsexpression.h>
#include <qgsfeatureiterator.h>
#include <qgsfeaturerequest.h>
#include <qgsmessagelog.h>
#include <qgsproject.h>
#include <qgsrelation.h>
#include <qgsrelationmanager.h>
#include <qgsvariantutils.h>

#include <algorithm>

QPointer<SplitHeirUtils> SplitHeirUtils::sInstance;

namespace
{
  //! Composition relations in which \a layer is the parent (photo tables).
  QList<QgsRelation> compositionRelations( QgsVectorLayer *layer )
  {
    QList<QgsRelation> result;
    if ( !layer )
      return result;
    const QList<QgsRelation> relations = QgsProject::instance()->relationManager()->referencedRelations( layer );
    for ( const QgsRelation &relation : relations )
    {
      if ( relation.isValid() && relation.strength() == Qgis::RelationshipStrength::Composition && relation.referencingLayer() )
        result << relation;
    }
    return result;
  }

  //! The field with the file path in a photo table, or -1.
  int pathFieldIndex( const QgsVectorLayer *layer )
  {
    const QgsFields fields = layer->fields();
    for ( int i = 0; i < fields.count(); ++i )
    {
      if ( layer->editorWidgetSetup( i ).type() == QLatin1String( "ExternalResource" ) )
        return i;
    }
    for ( const QString &name : { QStringLiteral( "SCIEZKA" ), QStringLiteral( "path" ), QStringLiteral( "foto" ) } )
    {
      const int index = FeatureIdentity::fieldIndex( fields, name );
      if ( index >= 0 )
        return index;
    }
    return -1;
  }

  //! Area for polygons (m²), length for lines (m), 0 for points.
  double partSize( QgsVectorLayer *layer, const QgsGeometry &geometry )
  {
    QgsDistanceArea distanceArea;
    distanceArea.setSourceCrs( layer->crs(), QgsProject::instance()->transformContext() );
    distanceArea.setEllipsoid( QgsProject::instance()->ellipsoid() );
    switch ( geometry.type() )
    {
      case Qgis::GeometryType::Polygon:
        return distanceArea.measureArea( geometry );
      case Qgis::GeometryType::Line:
        return distanceArea.measureLength( geometry );
      default:
        return 0;
    }
  }

  //! [WF-SPLIT-HEIR] where the map shows the number of a part: inside it
  QgsPoint labelPoint( QgsVectorLayer *layer, const QgsGeometry &geometry, const QgsCoordinateReferenceSystem &mapCrs )
  {
    QgsGeometry point = geometry.pointOnSurface();
    if ( point.isNull() )
      point = geometry.centroid();
    if ( mapCrs.isValid() && mapCrs != layer->crs() )
    {
      try
      {
        point.transform( QgsCoordinateTransform( layer->crs(), mapCrs, QgsProject::instance()->transformContext() ) );
      }
      catch ( const QgsCsException & )
      {
        return QgsPoint();
      }
    }
    return point.isNull() ? QgsPoint() : QgsPoint( point.asPoint() );
  }

  QString sizeText( Qgis::GeometryType type, double size )
  {
    const QLocale locale;
    if ( type == Qgis::GeometryType::Polygon )
      return size >= 10000 ? QStringLiteral( "%1 ha" ).arg( locale.toString( size / 10000, 'f', 2 ) ) : QStringLiteral( "%1 m²" ).arg( locale.toString( size, 'f', 1 ) );
    if ( type == Qgis::GeometryType::Line )
      return QStringLiteral( "%1 m" ).arg( locale.toString( size, 'f', 1 ) );
    return QString();
  }

  //! Puts a child under \a parent: relation keys and PARENT_UUID.
  bool moveChild( const QgsRelation &relation, QgsFeatureId childFid, const QgsFeature &parent )
  {
    QgsVectorLayer *child = relation.referencingLayer();
    bool ok = true;
    const QList<QgsRelation::FieldPair> pairs = relation.fieldPairs();
    for ( const QgsRelation::FieldPair &pair : pairs )
    {
      const int childIndex = child->fields().lookupField( pair.referencingField() );
      const int parentIndex = parent.fields().lookupField( pair.referencedField() );
      if ( childIndex < 0 || parentIndex < 0 )
        return false;
      QVariant value = parent.attribute( parentIndex );
      // the GeoPackage fid is the feature id, not always among the attributes
      if ( QgsVariantUtils::isNull( value ) && pair.referencedField().compare( QLatin1String( "fid" ), Qt::CaseInsensitive ) == 0 )
        value = parent.id();
      ok = child->changeAttributeValue( childFid, childIndex, value ) && ok;
    }
    const int parentUuidIndex = FeatureIdentity::fieldIndex( child->fields(), FeatureIdentity::parentUuidFieldName() );
    const int uuidIndex = FeatureIdentity::uuidFieldIndex( parent.fields() );
    if ( parentUuidIndex >= 0 && uuidIndex >= 0 )
      ok = child->changeAttributeValue( childFid, parentUuidIndex, parent.attribute( uuidIndex ) ) && ok;
    return ok;
  }
} // namespace

SplitHeirUtils::SplitHeirUtils( QObject *parent )
  : QObject( parent )
{
  sInstance = this;
}

SplitHeirUtils::~SplitHeirUtils()
{
  if ( sInstance == this )
    sInstance = nullptr;
}

void SplitHeirUtils::announceSplit( QgsVectorLayer *layer, QgsFeatureId originalFid, const QStringList &newUuids )
{
  if ( !layer || newUuids.isEmpty() )
  {
    QgsMessageLog::logMessage( QStringLiteral( "WorkField [WF-SPLIT-HEIR]: no new uuids — no heir dialog (layer without the uuid field?)" ), QStringLiteral( "WorkField" ), Qgis::Info );
    return;
  }
  if ( !sInstance )
    return;
  QPointer<QgsVectorLayer> guardedLayer( layer );
  QPointer<SplitHeirUtils> instance = sInstance;
  QTimer::singleShot( 0, instance, [instance, guardedLayer, originalFid, newUuids]() {
    if ( instance && guardedLayer )
      emit instance->choiceRequested( guardedLayer, static_cast<qlonglong>( originalFid ), newUuids );
  } );
}

QVariantMap SplitHeirUtils::partsInfo( QgsVectorLayer *layer, qlonglong originalFid, const QStringList &newUuids, const QgsCoordinateReferenceSystem &mapCrs ) const
{
  QVariantMap result;
  if ( !layer )
    return result;

  const int uuidIndex = FeatureIdentity::uuidFieldIndex( layer->fields() );
  QVariantList parts;
  QVariantList newParts;

  const QgsFeature original = layer->getFeature( originalFid );
  if ( original.isValid() )
  {
    const double size = partSize( layer, original.geometry() );
    QVariantMap part;
    part.insert( QStringLiteral( "fid" ), static_cast<qlonglong>( original.id() ) );
    part.insert( QStringLiteral( "uuid" ), uuidIndex >= 0 ? original.attribute( uuidIndex ).toString() : QString() );
    part.insert( QStringLiteral( "original" ), true );
    part.insert( QStringLiteral( "size" ), size );
    part.insert( QStringLiteral( "sizeText" ), sizeText( original.geometry().type(), size ) );
    part.insert( QStringLiteral( "geometry" ), QVariant::fromValue( original.geometry() ) );
    part.insert( QStringLiteral( "labelPoint" ), QVariant::fromValue( labelPoint( layer, original.geometry(), mapCrs ) ) );
    parts << part;
  }

  if ( uuidIndex >= 0 && !newUuids.isEmpty() )
  {
    QStringList quoted;
    for ( const QString &uuid : newUuids )
      quoted << QgsExpression::quotedString( uuid );
    QgsFeatureRequest request;
    request.setFilterExpression( QStringLiteral( "%1 IN (%2)" ).arg( QgsExpression::quotedColumnRef( layer->fields().at( uuidIndex ).name() ), quoted.join( QLatin1Char( ',' ) ) ) );
    QgsFeatureIterator it = layer->getFeatures( request );
    QgsFeature feature;
    while ( it.nextFeature( feature ) )
    {
      const double size = partSize( layer, feature.geometry() );
      QVariantMap part;
      part.insert( QStringLiteral( "fid" ), static_cast<qlonglong>( feature.id() ) );
      part.insert( QStringLiteral( "uuid" ), feature.attribute( uuidIndex ).toString() );
      part.insert( QStringLiteral( "original" ), false );
      part.insert( QStringLiteral( "size" ), size );
      part.insert( QStringLiteral( "sizeText" ), sizeText( feature.geometry().type(), size ) );
      part.insert( QStringLiteral( "geometry" ), QVariant::fromValue( feature.geometry() ) );
      part.insert( QStringLiteral( "labelPoint" ), QVariant::fromValue( labelPoint( layer, feature.geometry(), mapCrs ) ) );
      newParts << part;
    }
  }
  std::sort( newParts.begin(), newParts.end(), []( const QVariant &a, const QVariant &b ) { return a.toMap().value( QStringLiteral( "size" ) ).toDouble() > b.toMap().value( QStringLiteral( "size" ) ).toDouble(); } );
  parts << newParts;

  QVariantList photos;
  if ( original.isValid() )
  {
    const QString home = QgsProject::instance()->homePath();
    for ( const QgsRelation &relation : compositionRelations( layer ) )
    {
      QgsVectorLayer *child = relation.referencingLayer();
      const int pathIndex = pathFieldIndex( child );
      QgsFeatureIterator it = relation.getRelatedFeatures( original );
      QgsFeature feature;
      while ( it.nextFeature( feature ) )
      {
        const QString path = pathIndex >= 0 ? feature.attribute( pathIndex ).toString() : QString();
        QVariantMap photo;
        photo.insert( QStringLiteral( "layerId" ), child->id() );
        photo.insert( QStringLiteral( "layerName" ), child->name() );
        photo.insert( QStringLiteral( "fid" ), static_cast<qlonglong>( feature.id() ) );
        photo.insert( QStringLiteral( "path" ), path );
        photo.insert( QStringLiteral( "absolutePath" ), path.isEmpty() || QDir::isAbsolutePath( path ) ? path : home + QLatin1Char( '/' ) + path );
        photos << photo;
      }
    }
  }

  result.insert( QStringLiteral( "parts" ), parts );
  result.insert( QStringLiteral( "photos" ), photos );
  result.insert( QStringLiteral( "crs" ), QVariant::fromValue( layer->crs() ) );
  QgsMessageLog::logMessage( QStringLiteral( "WorkField [WF-SPLIT-HEIR]: %1 — %2 parts, %3 photos" ).arg( layer->name() ).arg( parts.size() ).arg( photos.size() ), QStringLiteral( "WorkField" ), Qgis::Info );
  return result;
}

QVariantMap SplitHeirUtils::applyChoice( QgsVectorLayer *layer, qlonglong originalFid, qlonglong heirFid, const QVariantList &photoTargets )
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !layer )
    return result;

  // 1. The old record takes the chosen part: swap geometry and attributes,
  //    except what makes the record itself (primary key, uuid).
  const bool swap = heirFid != originalFid;
  if ( swap )
  {
    const QgsFeature original = layer->getFeature( originalFid );
    const QgsFeature heir = layer->getFeature( heirFid );
    if ( !original.isValid() || !heir.isValid() )
    {
      result.insert( QStringLiteral( "message" ), tr( "Nie znalazłem kawałków po podziale — nic nie zmieniono." ) );
      return result;
    }
    const QgsAttributeList keys = layer->primaryKeyAttributes();
    const int uuidIndex = FeatureIdentity::uuidFieldIndex( layer->fields() );
    QgsAttributeMap toOriginal;
    QgsAttributeMap toHeir;
    QgsAttributeMap fromOriginal;
    QgsAttributeMap fromHeir;
    for ( int i = 0; i < layer->fields().count(); ++i )
    {
      if ( keys.contains( i ) || i == uuidIndex || layer->fields().fieldOrigin( i ) != Qgis::FieldOrigin::Provider )
        continue;
      if ( layer->fields().at( i ).name().compare( QLatin1String( "fid" ), Qt::CaseInsensitive ) == 0 )
        continue;
      if ( original.attribute( i ) == heir.attribute( i ) )
        continue;
      toOriginal.insert( i, heir.attribute( i ) );
      fromOriginal.insert( i, original.attribute( i ) );
      toHeir.insert( i, original.attribute( i ) );
      fromHeir.insert( i, heir.attribute( i ) );
    }

    const bool wasEditing = layer->isEditable();
    if ( !wasEditing && !layer->startEditing() )
    {
      result.insert( QStringLiteral( "message" ), tr( "Nie udało się otworzyć warstwy do edycji." ) );
      return result;
    }
    QgsGeometry heirGeometry = heir.geometry();
    QgsGeometry originalGeometry = original.geometry();
    bool ok = layer->changeGeometry( originalFid, heirGeometry ) && layer->changeGeometry( heirFid, originalGeometry );
    ok = ok && ( toOriginal.isEmpty() || layer->changeAttributeValues( originalFid, toOriginal, fromOriginal ) );
    ok = ok && ( toHeir.isEmpty() || layer->changeAttributeValues( heirFid, toHeir, fromHeir ) );
    if ( !ok || !layer->commitChanges( !wasEditing ) )
    {
      const QString errors = layer->commitErrors().join( QStringLiteral( "; " ) );
      layer->rollBack( !wasEditing );
      result.insert( QStringLiteral( "message" ), tr( "Zamiana kawałków nie powiodła się: %1" ).arg( errors ) );
      return result;
    }
  }

  // 2. Photos: all of them are on the old record; move those meant for
  //    another part. A target is a part as listed — after the swap the
  //    chosen part lives in the old record and the old geometry in heirFid.
  auto recordOf = [&]( qlonglong part ) -> qlonglong {
    if ( !swap )
      return part;
    if ( part == heirFid )
      return originalFid;
    if ( part == originalFid )
      return heirFid;
    return part;
  };

  int moved = 0;
  QStringList failures;
  QHash<QString, QgsRelation> relationOfChild;
  for ( const QgsRelation &relation : compositionRelations( layer ) )
    relationOfChild.insert( relation.referencingLayer()->id(), relation );

  QSet<QgsVectorLayer *> touched;
  QHash<QgsVectorLayer *, bool> wasEditingChild;
  for ( const QVariant &value : photoTargets )
  {
    const QVariantMap target = value.toMap();
    const qlonglong record = recordOf( target.value( QStringLiteral( "target" ) ).toLongLong() );
    if ( record == originalFid )
      continue;
    const QString layerId = target.value( QStringLiteral( "layerId" ) ).toString();
    if ( !relationOfChild.contains( layerId ) )
      continue;
    const QgsRelation relation = relationOfChild.value( layerId );
    QgsVectorLayer *child = relation.referencingLayer();
    const QgsFeature parent = layer->getFeature( record );
    if ( !parent.isValid() )
      continue;
    if ( !touched.contains( child ) )
    {
      wasEditingChild.insert( child, child->isEditable() );
      if ( !child->isEditable() && !child->startEditing() )
      {
        failures << child->name();
        continue;
      }
      touched.insert( child );
    }
    if ( moveChild( relation, target.value( QStringLiteral( "fid" ) ).toLongLong(), parent ) )
      ++moved;
    else
      failures << child->name();
  }
  for ( QgsVectorLayer *child : std::as_const( touched ) )
  {
    if ( !child->commitChanges( !wasEditingChild.value( child ) ) )
    {
      failures << child->name() + QStringLiteral( ": " ) + child->commitErrors().join( QStringLiteral( "; " ) );
      child->rollBack( !wasEditingChild.value( child ) );
    }
  }

  const bool ok = failures.isEmpty();
  result.insert( QStringLiteral( "ok" ), ok );
  result.insert( QStringLiteral( "swapped" ), swap );
  result.insert( QStringLiteral( "movedPhotos" ), moved );
  QString message = swap ? tr( "Dawny obiekt dostał wybrany kawałek." ) : tr( "Dawny obiekt zostaje przy swoim kawałku." );
  if ( moved > 0 )
    message += QLatin1Char( ' ' ) + tr( "Przeniesione zdjęcia: %1." ).arg( moved );
  if ( !ok )
    message += QLatin1Char( ' ' ) + tr( "Błąd przy zdjęciach: %1" ).arg( failures.join( QStringLiteral( ", " ) ) );
  result.insert( QStringLiteral( "message" ), message );
  QgsMessageLog::logMessage( QStringLiteral( "WorkField [WF-SPLIT-HEIR]: %1 original %2 heir %3 swapped %4 moved photos %5%6" ).arg( layer->name() ).arg( originalFid ).arg( heirFid ).arg( swap ).arg( moved ).arg( ok ? QString() : QStringLiteral( " ERRORS " ) + failures.join( QStringLiteral( ", " ) ) ), QStringLiteral( "WorkField" ), Qgis::Info );
  return result;
}

int SplitHeirUtils::childCount( QgsVectorLayer *layer, const QgsFeature &feature ) const
{
  int count = 0;
  for ( const QgsRelation &relation : compositionRelations( layer ) )
  {
    QgsFeatureIterator it = relation.getRelatedFeatures( feature );
    QgsFeature child;
    while ( it.nextFeature( child ) )
      ++count;
  }
  return count;
}
