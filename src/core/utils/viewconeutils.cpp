/***************************************************************************
  viewconeutils.cpp - ViewConeUtils

 ---------------------
 WorkField 24.10.2026 [WF-VIEW-CONE]. See viewconeutils.h.
 ***************************************************************************/

#include "viewconeutils.h"

#include "featureidentity.h"
#include "stozkiwidzenia.h"

#include <QDateTime>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTimer>
#include <QtMath>
#include <qgscoordinatetransform.h>
#include <qgsexception.h>
#include <qgsexiftools.h>
#include <qgsfeatureiterator.h>
#include <qgsfeaturerequest.h>
#include <qgslayertree.h>
#include <qgslayertreelayer.h>
#include <qgsmessagelog.h>
#include <qgsproject.h>
#include <qgsproviderregistry.h>
#include <qgsvectorfilewriter.h>

#include <algorithm>
#include <cmath>

namespace
{
  const QString kTable = QStringLiteral( "WF_VIEW_CONES" );

  double number( const QVariant &value )
  {
    bool ok = false;
    const double result = value.toDouble( &ok );
    return ok && std::isfinite( result ) ? result : std::numeric_limits<double>::quiet_NaN();
  }

  //! "key": number, "key_deg": number or "Key:number" anywhere in \a text.
  double numberAfter( const QString &text, const QString &key )
  {
    const QRegularExpression pattern( QStringLiteral( "\"?%1(?:_deg)?\"?\\s*[:=]\\s*\"?(-?[0-9]+(?:\\.[0-9]+)?)" ).arg( QRegularExpression::escape( key ) ), QRegularExpression::CaseInsensitiveOption );
    const QRegularExpressionMatch match = pattern.match( text );
    return match.hasMatch() ? match.captured( 1 ).toDouble() : std::numeric_limits<double>::quiet_NaN();
  }

  /**
   * The pose stored in the photo: our camera writes Xmp.GPano.Pose* and JSON
   * {azymut_deg, pitch_deg, roll_deg} in UserComment; OpenCamera writes
   * "Yaw:..,Pitch:..,Roll:.."; the geotag may carry GPSImgDirection.
   */
  QVariantMap readPose( const QString &path )
  {
    QVariantMap pose;
    if ( !QFileInfo::exists( path ) )
      return pose;

    bool hasGeoTag = false;
    const QgsPoint position = QgsExifTools::getGeoTag( path, hasGeoTag );
    if ( hasGeoTag )
    {
      pose.insert( QStringLiteral( "lon" ), position.x() );
      pose.insert( QStringLiteral( "lat" ), position.y() );
    }

    const QVariant rawComment = QgsExifTools::readTag( path, QStringLiteral( "Exif.Photo.UserComment" ) );
    QString comment = rawComment.toString();
    if ( comment.isEmpty() )
    {
      QByteArray bytes = rawComment.toByteArray();
      if ( bytes.size() > 8 && ( bytes.startsWith( "ASCII" ) || bytes.startsWith( "UNICODE" ) || bytes.startsWith( "JIS" ) ) )
        bytes = bytes.mid( 8 );
      comment = QString::fromUtf8( bytes ).trimmed();
    }

    double heading = number( QgsExifTools::readTag( path, QStringLiteral( "Xmp.GPano.PoseHeadingDegrees" ) ) );
    if ( std::isnan( heading ) )
      heading = numberAfter( comment, QStringLiteral( "azymut" ) );
    if ( std::isnan( heading ) )
      heading = numberAfter( comment, QStringLiteral( "Yaw" ) );
    if ( std::isnan( heading ) )
      heading = number( QgsExifTools::readTag( path, QStringLiteral( "Exif.GPSInfo.GPSImgDirection" ) ) );

    double pitch = number( QgsExifTools::readTag( path, QStringLiteral( "Xmp.GPano.PosePitchDegrees" ) ) );
    if ( std::isnan( pitch ) )
      pitch = numberAfter( comment, QStringLiteral( "pitch" ) );
    double roll = number( QgsExifTools::readTag( path, QStringLiteral( "Xmp.GPano.PoseRollDegrees" ) ) );
    if ( std::isnan( roll ) )
      roll = numberAfter( comment, QStringLiteral( "roll" ) );

    pose.insert( QStringLiteral( "heading" ), heading );
    pose.insert( QStringLiteral( "pitch" ), pitch );
    pose.insert( QStringLiteral( "roll" ), roll );
    return pose;
  }

  //! Same shape as StozkiWidzenia::stozekWkt: near and far edge, field arc.
  QgsGeometry conePolygon( const QgsPointXY &stand, double azimuthTrue, double pitch, const StozkiWidzenia &parameters )
  {
    const double fieldH = parameters.property( "poleH" ).toDouble();
    const double range = parameters.property( "zasieg" ).toDouble();
    const double height = parameters.property( "wysokoscAparatu" ).toDouble();

    const double tangent = std::tan( qDegreesToRadians( std::abs( pitch ) ) );
    const double toCentre = tangent > 0.05 ? height / tangent : range;
    const double farEdge = std::min( range, std::max( toCentre * 2.0, 2.0 ) );
    const double half = qDegreesToRadians( fieldH / 2.0 );
    const double direction = qDegreesToRadians( azimuthTrue );

    // [WF-VIEW-CONE] 25.10.2026 (Piotr 10:20) — a CIRCULAR SECTOR: apex at
    // the stand, the field of view of the camera, radius = the far edge of
    // the frame (from the pitch), at most the range. Was a ring sector from
    // the near edge of the frame (where its bottom meets the ground).
    QVector<QgsPointXY> vertices;
    vertices << stand;
    const int steps = 24;
    for ( int i = 0; i <= steps; ++i )
    {
      const double a = direction - half + 2 * half * i / steps;
      vertices << QgsPointXY( stand.x() + farEdge * std::sin( a ), stand.y() + farEdge * std::cos( a ) );
    }
    vertices << stand;

    QgsGeometry polygon = QgsGeometry::fromPolygonXY( QVector<QVector<QgsPointXY>>() << vertices );
    if ( !polygon.isGeosValid() )
      polygon = polygon.makeValid();
    return polygon;
  }

  QString gpkgPath( QgsVectorLayer *layer )
  {
    if ( !layer || layer->providerType() != QLatin1String( "ogr" ) )
      return QString();
    const QVariantMap parts = QgsProviderRegistry::instance()->decodeUri( QStringLiteral( "ogr" ), layer->source() );
    const QString path = parts.value( QStringLiteral( "path" ) ).toString();
    return path.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive ) ? path : QString();
  }

  QgsFields coneFields()
  {
    QgsFields fields;
    auto add = [&fields]( const QString &name, QMetaType::Type type ) { fields.append( QgsField( name, type ) ); };
    add( QStringLiteral( "uuid" ), QMetaType::Type::QString );
    add( QStringLiteral( "PHOTO_UUID" ), QMetaType::Type::QString );
    add( QStringLiteral( "PHOTO_PATH" ), QMetaType::Type::QString );
    add( QStringLiteral( "PARENT_LAYER" ), QMetaType::Type::QString );
    add( QStringLiteral( "PARENT_UUID" ), QMetaType::Type::QString );
    add( QStringLiteral( "PARENT_FID" ), QMetaType::Type::LongLong );
    add( QStringLiteral( "STAND_X" ), QMetaType::Type::Double );
    add( QStringLiteral( "STAND_Y" ), QMetaType::Type::Double );
    add( QStringLiteral( "AZIMUTH" ), QMetaType::Type::Double );
    add( QStringLiteral( "DECLINATION" ), QMetaType::Type::Double );
    add( QStringLiteral( "PITCH" ), QMetaType::Type::Double );
    add( QStringLiteral( "ROLL" ), QMetaType::Type::Double );
    add( QStringLiteral( "FOV_H" ), QMetaType::Type::Double );
    add( QStringLiteral( "FOV_V" ), QMetaType::Type::Double );
    add( QStringLiteral( "RANGE_M" ), QMetaType::Type::Double );
    add( QStringLiteral( "SOURCE" ), QMetaType::Type::QString );
    add( QStringLiteral( "CONFIRMED" ), QMetaType::Type::Int );
    add( QStringLiteral( "HITS" ), QMetaType::Type::QString );
    add( QStringLiteral( "CREATED" ), QMetaType::Type::QString );
    return fields;
  }

  //! WF_VIEW_CONES of the GeoPackage \a path: from the project, else loaded
  //! (and created first when the file has no such table).
  QgsVectorLayer *conesLayer( const QString &path, const QgsCoordinateReferenceSystem &crs, QString &error )
  {
    QgsProject *project = QgsProject::instance();
    const QMap<QString, QgsMapLayer *> layers = project->mapLayers();
    for ( QgsMapLayer *mapLayer : layers )
    {
      QgsVectorLayer *layer = qobject_cast<QgsVectorLayer *>( mapLayer );
      if ( !layer || layer->providerType() != QLatin1String( "ogr" ) )
        continue;
      const QVariantMap parts = QgsProviderRegistry::instance()->decodeUri( QStringLiteral( "ogr" ), layer->source() );
      if ( QFileInfo( parts.value( QStringLiteral( "path" ) ).toString() ) == QFileInfo( path ) && parts.value( QStringLiteral( "layerName" ) ).toString().compare( kTable, Qt::CaseInsensitive ) == 0 )
        return layer;
    }

    const QString uri = QStringLiteral( "%1|layername=%2" ).arg( path, kTable );
    auto layer = std::make_unique<QgsVectorLayer>( uri, kTable, QStringLiteral( "ogr" ) );
    if ( !layer->isValid() )
    {
      QgsVectorFileWriter::SaveVectorOptions options;
      options.driverName = QStringLiteral( "GPKG" );
      options.layerName = kTable;
      options.actionOnExistingFile = QgsVectorFileWriter::CreateOrOverwriteLayer;
      std::unique_ptr<QgsVectorFileWriter> writer( QgsVectorFileWriter::create( path, coneFields(), Qgis::WkbType::Polygon, crs, project->transformContext(), options ) );
      if ( !writer || writer->hasError() != QgsVectorFileWriter::NoError )
      {
        error = writer ? writer->errorMessage() : QObject::tr( "nie udało się utworzyć tabeli" );
        return nullptr;
      }
      writer.reset();
      layer = std::make_unique<QgsVectorLayer>( uri, kTable, QStringLiteral( "ogr" ) );
      if ( !layer->isValid() )
      {
        error = QObject::tr( "tabela utworzona, ale nie da się jej otworzyć" );
        return nullptr;
      }
      QgsMessageLog::logMessage( QStringLiteral( "WorkField [WF-VIEW-CONE]: table %1 created in %2" ).arg( kTable, path ), QStringLiteral( "WorkField" ), Qgis::Info );
    }

    // in the project, at the bottom of the legend, switched off: QGIS on the
    // computer shows the cones without any setup; in the field they do not clutter the map
    QgsVectorLayer *added = qobject_cast<QgsVectorLayer *>( project->addMapLayer( layer.release(), false ) );
    if ( added )
    {
      QgsLayerTreeLayer *node = project->layerTreeRoot()->addLayer( added );
      if ( node )
        node->setItemVisibilityChecked( false );
    }
    return added;
  }
} // namespace

ViewConeUtils::ViewConeUtils( QObject *parent )
  : QObject( parent )
{
}

void ViewConeUtils::requestCone( QgsVectorLayer *parentLayer, const QgsFeature &parent, const QVariantMap &photo, const QVariantMap &sensor, bool ask )
{
  if ( !parentLayer )
    return;
  QVariantMap request = photo;
  request.insert( QStringLiteral( "parentFid" ), static_cast<qlonglong>( parent.id() ) );
  const int uuidIndex = FeatureIdentity::uuidFieldIndex( parent.fields() );
  if ( uuidIndex >= 0 && !request.contains( QStringLiteral( "parentUuid" ) ) )
    request.insert( QStringLiteral( "parentUuid" ), parent.attribute( uuidIndex ).toString() );
  QPointer<QgsVectorLayer> guardedLayer( parentLayer );
  QPointer<ViewConeUtils> self( this );
  QTimer::singleShot( 0, this, [self, guardedLayer, request, sensor, ask]() {
    if ( self && guardedLayer )
      emit self->coneRequested( guardedLayer, request, sensor, ask );
  } );
}

QVariantMap ViewConeUtils::buildCone( QgsVectorLayer *parentLayer, const QString &absolutePath, const QVariantMap &sensor, const QgsCoordinateReferenceSystem &mapCrs, double azimuthOverride ) const
{
  QVariantMap cone;
  cone.insert( QStringLiteral( "ok" ), false );
  if ( !parentLayer )
    return cone;

  const StozkiWidzenia parameters;
  const double declination = parameters.property( "deklinacja" ).toDouble();
  const QVariantMap pose = readPose( absolutePath );

  QString source = QStringLiteral( "photo" );
  double lat = number( pose.value( QStringLiteral( "lat" ) ) );
  double lon = number( pose.value( QStringLiteral( "lon" ) ) );
  if ( std::isnan( lat ) || std::isnan( lon ) )
  {
    lat = number( sensor.value( QStringLiteral( "lat" ) ) );
    lon = number( sensor.value( QStringLiteral( "lon" ) ) );
  }
  double heading = number( pose.value( QStringLiteral( "heading" ) ) );
  if ( std::isnan( heading ) )
  {
    heading = number( sensor.value( QStringLiteral( "heading" ) ) );
    source = QStringLiteral( "sensor" );
  }
  double pitch = number( pose.value( QStringLiteral( "pitch" ) ) );
  if ( std::isnan( pitch ) )
    pitch = number( sensor.value( QStringLiteral( "pitch" ) ) );
  if ( std::isnan( pitch ) )
    pitch = -45.0; // no pose at all: the typical shot of the ground
  else if ( pitch > 0 )
    pitch = 0.0; // looking up: the cone on the ground is the level one (2.4–8 m)
  const double roll = number( pose.value( QStringLiteral( "roll" ) ) );

  if ( std::isnan( lat ) || std::isnan( lon ) )
  {
    cone.insert( QStringLiteral( "reason" ), tr( "brak pozycji" ) );
    return cone;
  }

  double azimuth = std::isnan( heading ) ? 0.0 : std::fmod( heading + declination + 360.0, 360.0 );
  if ( std::isfinite( azimuthOverride ) )
  {
    azimuth = std::fmod( azimuthOverride + 360.0, 360.0 );
    source = QStringLiteral( "manual" );
  }
  else if ( std::isnan( heading ) )
  {
    // no direction at all: a cone pointing north, to be corrected by hand
    source = QStringLiteral( "none" );
  }

  QgsPointXY stand;
  try
  {
    const QgsCoordinateTransform toLayer( QgsCoordinateReferenceSystem( QStringLiteral( "EPSG:4326" ) ), parentLayer->crs(), QgsProject::instance()->transformContext() );
    stand = toLayer.transform( QgsPointXY( lon, lat ) );
  }
  catch ( const QgsCsException & )
  {
    cone.insert( QStringLiteral( "reason" ), tr( "nie da się przeliczyć pozycji" ) );
    return cone;
  }

  const QgsGeometry polygon = conePolygon( stand, azimuth, pitch, parameters );

  // which objects of the layer the cone hits, by share of the cone area
  QVariantList hits;
  const double coneArea = polygon.area();
  if ( coneArea > 0 )
  {
    QgsFeatureRequest request( polygon.boundingBox() );
    QgsFeatureIterator it = parentLayer->getFeatures( request );
    QgsFeature feature;
    const int uuidIndex = FeatureIdentity::uuidFieldIndex( parentLayer->fields() );
    while ( it.nextFeature( feature ) )
    {
      if ( !feature.hasGeometry() )
        continue;
      double share = 0;
      if ( feature.geometry().type() == Qgis::GeometryType::Polygon )
        share = polygon.intersection( feature.geometry() ).area() / coneArea * 100.0;
      else if ( polygon.intersects( feature.geometry() ) )
        share = 100.0; // a point or a line inside the cone
      if ( share < 1.0 )
        continue;
      QVariantMap hit;
      hit.insert( QStringLiteral( "fid" ), static_cast<qlonglong>( feature.id() ) );
      hit.insert( QStringLiteral( "uuid" ), uuidIndex >= 0 ? feature.attribute( uuidIndex ).toString() : QString() );
      hit.insert( QStringLiteral( "share" ), std::round( share ) );
      hits << hit;
    }
    std::sort( hits.begin(), hits.end(), []( const QVariant &a, const QVariant &b ) { return a.toMap().value( QStringLiteral( "share" ) ).toDouble() > b.toMap().value( QStringLiteral( "share" ) ).toDouble(); } );
  }

  QgsGeometry display = polygon;
  QgsPoint standDisplay( stand );
  if ( mapCrs.isValid() && mapCrs != parentLayer->crs() )
  {
    try
    {
      const QgsCoordinateTransform toMap( parentLayer->crs(), mapCrs, QgsProject::instance()->transformContext() );
      display.transform( toMap );
      const QgsPointXY transformed = toMap.transform( stand );
      standDisplay = QgsPoint( transformed );
    }
    catch ( const QgsCsException & )
    {
    }
  }

  cone.insert( QStringLiteral( "ok" ), true );
  cone.insert( QStringLiteral( "source" ), source );
  cone.insert( QStringLiteral( "azimuth" ), azimuth );
  cone.insert( QStringLiteral( "declination" ), std::isnan( heading ) || std::isfinite( azimuthOverride ) ? QVariant() : QVariant( declination ) );
  cone.insert( QStringLiteral( "pitch" ), pitch );
  cone.insert( QStringLiteral( "roll" ), std::isnan( roll ) ? QVariant() : QVariant( roll ) );
  cone.insert( QStringLiteral( "standX" ), stand.x() );
  cone.insert( QStringLiteral( "standY" ), stand.y() );
  cone.insert( QStringLiteral( "stand" ), QVariant::fromValue( standDisplay ) );
  cone.insert( QStringLiteral( "geometry" ), QVariant::fromValue( display ) );
  cone.insert( QStringLiteral( "layerGeometryWkt" ), polygon.asWkt( 3 ) );
  cone.insert( QStringLiteral( "hits" ), hits );
  cone.insert( QStringLiteral( "fovH" ), parameters.property( "poleH" ) );
  cone.insert( QStringLiteral( "fovV" ), parameters.property( "poleV" ) );
  cone.insert( QStringLiteral( "range" ), parameters.property( "zasieg" ) );
  QgsMessageLog::logMessage( QStringLiteral( "WorkField [WF-VIEW-CONE]: %1 azimuth %2 (%3) pitch %4 hits %5" ).arg( QFileInfo( absolutePath ).fileName() ).arg( azimuth, 0, 'f', 1 ).arg( source ).arg( pitch, 0, 'f', 1 ).arg( hits.size() ), QStringLiteral( "WorkField" ), Qgis::Info );
  return cone;
}

QVariantMap ViewConeUtils::saveCone( QgsVectorLayer *parentLayer, const QVariantMap &cone, const QVariantMap &photo, bool confirmed )
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !parentLayer || !cone.value( QStringLiteral( "ok" ) ).toBool() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Stożek: brak danych do zapisu." ) );
    return result;
  }
  const QString path = gpkgPath( parentLayer );
  if ( path.isEmpty() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Stożek: warstwa nie jest w GeoPackage — nie zapisano." ) );
    return result;
  }
  QString error;
  QgsVectorLayer *cones = conesLayer( path, parentLayer->crs(), error );
  if ( !cones )
  {
    result.insert( QStringLiteral( "message" ), tr( "Stożek nie zapisany: %1" ).arg( error ) );
    return result;
  }

  QgsGeometry geometry = QgsGeometry::fromWkt( cone.value( QStringLiteral( "layerGeometryWkt" ) ).toString() );
  if ( cones->crs() != parentLayer->crs() )
  {
    try
    {
      geometry.transform( QgsCoordinateTransform( parentLayer->crs(), cones->crs(), QgsProject::instance()->transformContext() ) );
    }
    catch ( const QgsCsException & )
    {
    }
  }

  QgsFeature feature( cones->fields() );
  feature.setGeometry( geometry );
  auto set = [&]( const QString &name, const QVariant &value ) {
    const int index = cones->fields().lookupField( name );
    if ( index >= 0 )
      feature.setAttribute( index, value );
  };
  set( QStringLiteral( "uuid" ), FeatureIdentity::newUuid() );
  set( QStringLiteral( "PHOTO_UUID" ), photo.value( QStringLiteral( "uuid" ) ) );
  set( QStringLiteral( "PHOTO_PATH" ), photo.value( QStringLiteral( "path" ) ) );
  set( QStringLiteral( "PARENT_LAYER" ), parentLayer->name() );
  set( QStringLiteral( "PARENT_UUID" ), photo.value( QStringLiteral( "parentUuid" ) ) );
  set( QStringLiteral( "PARENT_FID" ), photo.value( QStringLiteral( "parentFid" ) ) );
  set( QStringLiteral( "STAND_X" ), cone.value( QStringLiteral( "standX" ) ) );
  set( QStringLiteral( "STAND_Y" ), cone.value( QStringLiteral( "standY" ) ) );
  set( QStringLiteral( "AZIMUTH" ), cone.value( QStringLiteral( "azimuth" ) ) );
  set( QStringLiteral( "DECLINATION" ), cone.value( QStringLiteral( "declination" ) ) );
  set( QStringLiteral( "PITCH" ), cone.value( QStringLiteral( "pitch" ) ) );
  set( QStringLiteral( "ROLL" ), cone.value( QStringLiteral( "roll" ) ) );
  set( QStringLiteral( "FOV_H" ), cone.value( QStringLiteral( "fovH" ) ) );
  set( QStringLiteral( "FOV_V" ), cone.value( QStringLiteral( "fovV" ) ) );
  set( QStringLiteral( "RANGE_M" ), cone.value( QStringLiteral( "range" ) ) );
  set( QStringLiteral( "SOURCE" ), cone.value( QStringLiteral( "source" ) ) );
  set( QStringLiteral( "CONFIRMED" ), confirmed ? 1 : 0 );
  set( QStringLiteral( "HITS" ), QString::fromUtf8( QJsonDocument( QJsonArray::fromVariantList( cone.value( QStringLiteral( "hits" ) ).toList() ) ).toJson( QJsonDocument::Compact ) ) );
  set( QStringLiteral( "CREATED" ), QDateTime::currentDateTime().toString( Qt::ISODate ) );

  const bool wasEditing = cones->isEditable();
  if ( !wasEditing && !cones->startEditing() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Stożek nie zapisany: warstwa tylko do odczytu." ) );
    return result;
  }
  if ( !cones->addFeature( feature ) || !cones->commitChanges( !wasEditing ) )
  {
    const QString errors = cones->commitErrors().join( QStringLiteral( "; " ) );
    cones->rollBack( !wasEditing );
    result.insert( QStringLiteral( "message" ), tr( "Stożek nie zapisany: %1" ).arg( errors ) );
    return result;
  }
  result.insert( QStringLiteral( "ok" ), true );
  result.insert( QStringLiteral( "message" ), confirmed ? tr( "Stożek widoku zapisany." ) : tr( "Stożek widoku zapisany (niepotwierdzony)." ) );
  QgsMessageLog::logMessage( QStringLiteral( "WorkField [WF-VIEW-CONE]: saved for %1, confirmed %2, source %3" ).arg( photo.value( QStringLiteral( "path" ) ).toString() ).arg( confirmed ).arg( cone.value( QStringLiteral( "source" ) ).toString() ), QStringLiteral( "WorkField" ), Qgis::Info );
  return result;
}
