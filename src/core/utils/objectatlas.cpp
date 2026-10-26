/***************************************************************************
  objectatlas.cpp - ObjectAtlas
 ---------------------
 WorkField 25.10.2026 [WF-OBJECT-ATLAS]. See objectatlas.h.
 ***************************************************************************/

#include "objectatlas.h"

#include "featureidentity.h"
#include "zalacznikiutils.h"

#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QStandardPaths>
#include <QUrl>
#include <QtMath>
#include <qgsapplication.h>
#include <qgscategorizedsymbolrenderer.h>
#include <qgsclassificationquantile.h>
#include <qgscolorramp.h>
#include <qgseditformconfig.h>
#include <qgsgraduatedsymbolrenderer.h>
#include <qgsmaplayerstylemanager.h>
#include <qgspallabeling.h>
#include <qgsstyle.h>
#include <qgssymbol.h>
#include <qgstextbuffersettings.h>
#include <qgstextformat.h>
#include <qgslegendsymbolitem.h>
#include <qgsrenderer.h>
#include <qgsvectordataprovider.h>
#include <qgsvectorlayerlabeling.h>
#include <QTimer>
#include <sqlite3.h>
#include <qgscoordinatetransform.h>
#include <qgscurve.h>
#include <qgscurvepolygon.h>
#include <qgsdistancearea.h>
#include <qgseditorwidgetsetup.h>
#include <qgsexception.h>
#include <qgsexpression.h>
#include <qgsexpressioncontext.h>
#include <qgsexpressioncontextutils.h>
#include <qgsfeatureiterator.h>
#include <qgsfeaturerequest.h>
#include <qgsfieldformatter.h>
#include <qgsfieldformatterregistry.h>
#include <qgslayertree.h>
#include <qgslayertreelayer.h>
#include <qgsmaprendererparalleljob.h>
#include <qgsmapsettings.h>
#include <qgspoint.h>
#include <qgsproject.h>
#include <qgsproviderregistry.h>
#include <qgsvariantutils.h>
#include <qgsvectorlayer.h>
#include <qgslinestring.h>
#include <qgsmultilinestring.h>
#include <qgsmultipoint.h>
#include <qgsmultipolygon.h>
#include <qgspolygon.h>
#include <qgswkbtypes.h>

#include <algorithm>
#include <cmath>
#include <memory>

namespace
{
  const QString kConesTable = QStringLiteral( "WF_VIEW_CONES" );
  const int kMaxObjects = 20000;
  const int kMaxVertices = 4000;

  //! Attachment tables, WF_ tables and basemaps are not atlas layers.
  bool isAtlasLayer( const QgsVectorLayer *layer )
  {
    if ( !layer || !layer->isValid() )
      return false;
    const Qgis::GeometryType type = static_cast<Qgis::GeometryType>( layer->geometryType() );
    if ( type == Qgis::GeometryType::Null || type == Qgis::GeometryType::Unknown )
      return false;
    const QString name = layer->name();
    for ( const QString &prefix : { QStringLiteral( "zal_" ), QStringLiteral( "WF_" ), QStringLiteral( "REF_" ), QStringLiteral( "ref_" ), QStringLiteral( "podklad_" ) } )
    {
      if ( name.startsWith( prefix, Qt::CaseInsensitive ) )
        return false;
    }
    const QString source = layer->source();
    return !source.contains( QLatin1String( "layername=ZAL_" ), Qt::CaseInsensitive )
           && !source.contains( QLatin1String( "layername=WF_" ), Qt::CaseInsensitive );
  }

  QVariantList point( double x, double y )
  {
    return QVariantList { x, y };
  }

  QVariantList rect( const QgsRectangle &r )
  {
    return QVariantList { r.xMinimum(), r.yMinimum(), r.xMaximum(), r.yMaximum() };
  }

  QgsRectangle rectFrom( const QVariantList &list )
  {
    if ( list.size() != 4 )
      return QgsRectangle();
    return QgsRectangle( list.at( 0 ).toDouble(), list.at( 1 ).toDouble(), list.at( 2 ).toDouble(), list.at( 3 ).toDouble() );
  }

  //! Vertices of a curve, thinned so that one object never sends more
  //! than kMaxVertices to the window.
  QVariantList curvePoints( const QgsCurve *curve, int budget )
  {
    QVariantList out;
    if ( !curve )
      return out;
    QgsPointSequence points;
    curve->points( points );
    const int step = std::max( 1, static_cast<int>( points.size() ) / std::max( 8, budget ) );
    for ( int i = 0; i < points.size(); i += step )
      out << QVariant( point( points.at( i ).x(), points.at( i ).y() ) );
    if ( step > 1 && !points.isEmpty() )
      out << QVariant( point( points.last().x(), points.last().y() ) );
    return out;
  }

  //! The geometry as a list of parts: polygon rings, lines, or one-vertex points.
  QVariantList partsOf( const QgsGeometry &geometry )
  {
    QVariantList parts;
    if ( geometry.isNull() || geometry.isEmpty() )
      return parts;
    const int budget = std::max( 8, kMaxVertices / std::max( 1, geometry.constGet()->partCount() ) );
    for ( auto it = geometry.const_parts_begin(); it != geometry.const_parts_end(); ++it )
    {
      const QgsAbstractGeometry *part = *it;
      if ( const QgsCurvePolygon *polygon = qgsgeometry_cast<const QgsCurvePolygon *>( part ) )
      {
        parts << QVariant( curvePoints( polygon->exteriorRing(), budget ) );
        for ( int r = 0; r < polygon->numInteriorRings(); ++r )
          parts << QVariant( curvePoints( polygon->interiorRing( r ), budget / 4 ) );
      }
      else if ( const QgsCurve *curve = qgsgeometry_cast<const QgsCurve *>( part ) )
      {
        parts << QVariant( curvePoints( curve, budget ) );
      }
      else if ( const QgsPoint *p = qgsgeometry_cast<const QgsPoint *>( part ) )
      {
        parts << QVariant( QVariantList { QVariant( point( p->x(), p->y() ) ) } );
      }
    }
    return parts;
  }

  QString geometryKind( const QgsVectorLayer *layer )
  {
    switch ( static_cast<Qgis::GeometryType>( layer->geometryType() ) )
    {
      case Qgis::GeometryType::Point:
        return QStringLiteral( "point" );
      case Qgis::GeometryType::Line:
        return QStringLiteral( "line" );
      default:
        return QStringLiteral( "polygon" );
    }
  }

  QString formatNumber( double value, int decimals )
  {
    return QLocale().toString( value, 'f', decimals );
  }

  QString areaText( double squareMetres )
  {
    if ( squareMetres >= 10000.0 )
      return QObject::tr( "%1 ha" ).arg( formatNumber( squareMetres / 10000.0, 4 ) );
    return QObject::tr( "%1 m²" ).arg( formatNumber( squareMetres, squareMetres < 10 ? 2 : 1 ) );
  }

  QString lengthText( double metres )
  {
    if ( metres >= 10000.0 )
      return QObject::tr( "%1 km" ).arg( formatNumber( metres / 1000.0, 3 ) );
    return QObject::tr( "%1 m" ).arg( formatNumber( metres, metres < 10 ? 2 : 1 ) );
  }

  QString normalisedPath( QString path )
  {
    path = path.trimmed();
    path.replace( QLatin1Char( '\\' ), QLatin1Char( '/' ) );
    while ( path.startsWith( QLatin1String( "./" ) ) )
      path = path.mid( 2 );
    return path;
  }

  QString gpkgOf( const QgsVectorLayer *layer )
  {
    if ( !layer || layer->providerType() != QLatin1String( "ogr" ) )
      return QString();
    const QString path = QgsProviderRegistry::instance()->decodeUri( layer->providerType(), layer->source() ).value( QStringLiteral( "path" ) ).toString();
    return path.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive ) ? path : QString();
  }

  //! [WF-OBJECT-ATLAS] the value map of a field: [{ label, value }]
  QVariantList valueMapOptions( const QgsEditorWidgetSetup &setup )
  {
    QVariantList out;
    const QVariant map = setup.config().value( QStringLiteral( "map" ) );
    auto add = [&out]( const QString &label, const QVariant &value ) {
      if ( value.toString() == QLatin1String( "{2839923C-8B7D-419E-B84B-CA2FE9B80EC7}" ) )
        return; // the NULL placeholder of QGIS
      QVariantMap o;
      o.insert( QStringLiteral( "label" ), label );
      o.insert( QStringLiteral( "value" ), value.toString() );
      out << o;
    };
    if ( map.userType() == QMetaType::QVariantList )
    {
      for ( const QVariant &entry : map.toList() )
      {
        const QVariantMap m = entry.toMap();
        for ( auto it = m.constBegin(); it != m.constEnd(); ++it )
          add( it.key(), it.value() );
      }
    }
    else
    {
      const QVariantMap m = map.toMap();
      for ( auto it = m.constBegin(); it != m.constEnd(); ++it )
        add( it.key(), it.value() );
    }
    return out;
  }

  QString kindOf( const QgsField &field, const QgsEditorWidgetSetup &setup )
  {
    if ( setup.type() == QLatin1String( "ValueMap" ) )
      return QStringLiteral( "valuemap" );
    if ( field.type() == QMetaType::Bool || setup.type() == QLatin1String( "CheckBox" ) )
      return QStringLiteral( "bool" );
    if ( field.type() == QMetaType::QDate )
      return QStringLiteral( "date" );
    if ( field.type() == QMetaType::QDateTime )
      return QStringLiteral( "datetime" );
    if ( field.isNumeric() )
      return QStringLiteral( "number" );
    return QStringLiteral( "text" );
  }

  const QString kAtlasStyleProperty = QStringLiteral( "workfield/atlasStyle" );
  const QString kPreviousStyleProperty = QStringLiteral( "workfield/atlasPreviousStyle" );

  /**
   * Colour by \a colorBy (numbers: 5 quantile classes; anything else: one
   * colour per value, at most 40) and labels from \a labelBy (a value map
   * shows its labels). The rest of the look stays as it was.
   */
  void applyAtlasStyle( QgsVectorLayer *layer, const QString &colorBy, const QString &labelBy )
  {
    const int colorIndex = colorBy.isEmpty() ? -1 : layer->fields().lookupField( colorBy );
    if ( colorIndex >= 0 )
    {
      const QgsEditorWidgetSetup setup = layer->editorWidgetSetup( colorIndex );
      const bool numeric = layer->fields().at( colorIndex ).isNumeric() && setup.type() != QLatin1String( "ValueMap" );
      std::unique_ptr<QgsSymbol> symbol( QgsSymbol::defaultSymbol( static_cast<Qgis::GeometryType>( layer->geometryType() ) ) );
      std::unique_ptr<QgsColorRamp> ramp( QgsStyle::defaultStyle()->colorRamp( QStringLiteral( "Spectral" ) ) );
      if ( symbol )
      {
        if ( numeric )
        {
          QgsGraduatedSymbolRenderer *renderer = new QgsGraduatedSymbolRenderer( colorBy );
          renderer->setSourceSymbol( symbol->clone() );
          if ( ramp )
            renderer->setSourceColorRamp( ramp->clone() );
          renderer->setClassificationMethod( new QgsClassificationQuantile() );
#if _QGIS_VERSION_INT >= 33600
          QString classError; // newer QGIS reports the error, older does not
          renderer->updateClasses( layer, 5, classError );
#else
          renderer->updateClasses( layer, 5 );
#endif
          layer->setRenderer( renderer );
        }
        else
        {
          QList<QVariant> values = qgis::setToList( layer->uniqueValues( colorIndex, 40 ) );
          std::sort( values.begin(), values.end(), []( const QVariant &a, const QVariant &b ) { return a.toString().localeAwareCompare( b.toString() ) < 0; } );
          QgsFieldFormatter *formatter = QgsApplication::fieldFormatterRegistry()->fieldFormatter( setup.type() );
          const QVariant cache = formatter->createCache( layer, colorIndex, setup.config() );
          QgsCategoryList categories;
          const int n = values.size();
          for ( int i = 0; i < n; ++i )
          {
            QgsSymbol *s = symbol->clone();
            s->setColor( ramp ? ramp->color( n > 1 ? static_cast<double>( i ) / ( n - 1 ) : 0.5 ) : QColor::fromHsv( ( i * 47 ) % 360, 180, 220 ) );
            const QString label = QgsVariantUtils::isNull( values.at( i ) ) ? QObject::tr( "(puste)" ) : formatter->representValue( layer, colorIndex, setup.config(), cache, values.at( i ) );
            categories << QgsRendererCategory( values.at( i ), s, label );
          }
          layer->setRenderer( new QgsCategorizedSymbolRenderer( colorBy, categories ) );
        }
      }
    }

    const int labelIndex = labelBy.isEmpty() ? -1 : layer->fields().lookupField( labelBy );
    if ( labelIndex >= 0 )
    {
      QgsPalLayerSettings settings;
      const bool valueMap = layer->editorWidgetSetup( labelIndex ).type() == QLatin1String( "ValueMap" );
      settings.fieldName = valueMap ? QStringLiteral( "represent_value(%1)" ).arg( QgsExpression::quotedColumnRef( labelBy ) ) : labelBy;
      settings.isExpression = valueMap;
      QgsTextFormat format;
      format.setSize( 9 );
      format.setColor( QColor( 20, 20, 20 ) );
      QgsTextBufferSettings buffer;
      buffer.setEnabled( true );
      buffer.setSize( 1.0 );
      buffer.setColor( Qt::white );
      format.setBuffer( buffer );
      settings.setFormat( format );
      switch ( static_cast<Qgis::GeometryType>( layer->geometryType() ) )
      {
        case Qgis::GeometryType::Point:
          settings.placement = Qgis::LabelPlacement::AroundPoint;
          break;
        case Qgis::GeometryType::Line:
          settings.placement = Qgis::LabelPlacement::Line;
          break;
        default:
          settings.placement = Qgis::LabelPlacement::OverPoint;
          break;
      }
      layer->setLabeling( new QgsVectorLayerSimpleLabeling( settings ) );
      layer->setLabelsEnabled( true );
    }
  }

  // [WF-ATLAS-SHAPE] 26.10.2026
  const int kMaxEditVertices = 2000;
  const int kMaxSnapTargets = 8000;

  bool canChangeGeometries( const QgsVectorLayer *layer )
  {
    if ( !layer || layer->readOnly() || !layer->dataProvider() )
      return false;
#if _QGIS_VERSION_INT >= 33800
    return layer->dataProvider()->capabilities() & Qgis::VectorProviderCapability::ChangeGeometries;
#else
    return layer->dataProvider()->capabilities() & QgsVectorDataProvider::ChangeGeometries;
#endif
  }

  QgsDistanceArea distanceArea( const QgsProject *project, const QgsVectorLayer *layer )
  {
    QgsDistanceArea da;
    da.setSourceCrs( layer->crs(), project->transformContext() );
    if ( !project->ellipsoid().isEmpty() )
      da.setEllipsoid( project->ellipsoid() );
    return da;
  }

  //! the measure that tells most about a change of shape: area / length / none
  void shapeMeasure( const QgsDistanceArea &da, const QgsGeometry &g, Qgis::GeometryType type, QString &name, double &value, QString &text )
  {
    value = 0;
    if ( type == Qgis::GeometryType::Polygon )
    {
      name = QObject::tr( "Pole" );
      value = da.convertAreaMeasurement( da.measureArea( g ), Qgis::AreaUnit::SquareMeters );
      text = areaText( value );
    }
    else if ( type == Qgis::GeometryType::Line )
    {
      name = QObject::tr( "Długość" );
      value = da.convertLengthMeasurement( da.measureLength( g ), Qgis::DistanceUnit::Meters );
      text = lengthText( value );
    }
    else
    {
      name.clear();
      text.clear();
    }
  }

  //! Grows a too small extent to \a minimum around its centre.
  QgsRectangle atLeast( QgsRectangle r, double minimum )
  {
    if ( r.isNull() )
      return r;
    const QgsPointXY c = r.center();
    const double w = std::max( r.width(), minimum );
    const double h = std::max( r.height(), minimum );
    return QgsRectangle( c.x() - w / 2, c.y() - h / 2, c.x() + w / 2, c.y() + h / 2 );
  }
} // namespace

ObjectAtlas::ObjectAtlas( QObject *parent )
  : QObject( parent )
{
}

ObjectAtlas::~ObjectAtlas()
{
  for ( auto it = mJobs.begin(); it != mJobs.end(); ++it )
  {
    if ( it->job )
    {
      it->job->disconnect( this );
      it->job->cancel();
      delete it->job;
    }
  }
  delete mStyled;
}

QVariantList ObjectAtlas::layers( QgsProject *project ) const
{
  QVariantList out;
  if ( !project || !project->layerTreeRoot() )
    return out;
  const QList<QgsLayerTreeLayer *> nodes = project->layerTreeRoot()->findLayers();
  for ( QgsLayerTreeLayer *node : nodes )
  {
    QgsVectorLayer *layer = qobject_cast<QgsVectorLayer *>( node->layer() );
    if ( !isAtlasLayer( layer ) )
      continue;
    QVariantMap entry;
    entry.insert( QStringLiteral( "id" ), layer->id() );
    entry.insert( QStringLiteral( "name" ), layer->name() );
    entry.insert( QStringLiteral( "layer" ), QVariant::fromValue( static_cast<QObject *>( layer ) ) );
    // [WF-OBJECT-ATLAS] an empty layer is listed, but the atlas does not start on it
    entry.insert( QStringLiteral( "count" ), static_cast<qlonglong>( layer->featureCount() ) );
    out << entry;
  }
  return out;
}

QVariantList ObjectAtlas::objects( QgsVectorLayer *layer ) const
{
  QVariantList out;
  if ( !layer || !layer->isValid() )
    return out;

  QgsExpressionContext context( QgsExpressionContextUtils::globalProjectLayerScopes( layer ) );
  QgsExpression expression( layer->displayExpression() );
  expression.prepare( &context );

  QgsFeatureRequest request;
  if ( !expression.needsGeometry() )
#if _QGIS_VERSION_INT >= 33600
    request.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
#else
    request.setFlags( QgsFeatureRequest::NoGeometry );
#endif
  request.setLimit( kMaxObjects );

  QList<QPair<qlonglong, QString>> list;
  QgsFeatureIterator it = layer->getFeatures( request );
  QgsFeature feature;
  while ( it.nextFeature( feature ) )
  {
    context.setFeature( feature );
    QString label = expression.isValid() ? expression.evaluate( &context ).toString().trimmed() : QString();
    if ( label.isEmpty() )
      label = QObject::tr( "obiekt %1" ).arg( feature.id() );
    list << qMakePair( static_cast<qlonglong>( feature.id() ), label );
  }
  std::sort( list.begin(), list.end(), []( const QPair<qlonglong, QString> &a, const QPair<qlonglong, QString> &b ) { return a.first < b.first; } );
  for ( const auto &entry : std::as_const( list ) )
  {
    QVariantMap m;
    m.insert( QStringLiteral( "fid" ), entry.first );
    m.insert( QStringLiteral( "label" ), entry.second );
    out << m;
  }
  return out;
}

QVariantMap ObjectAtlas::describe( QgsProject *project, QgsVectorLayer *layer, qlonglong fid ) const
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !project || !layer || !layer->isValid() )
    return result;

  const QgsFeature feature = layer->getFeature( fid );
  if ( !feature.isValid() )
    return result;

  const QgsCoordinateReferenceSystem mapCrs = project->crs().isValid() ? project->crs() : layer->crs();
  const QgsCoordinateTransform toMap( layer->crs(), mapCrs, project->transformContext() );
  const bool geographic = mapCrs.mapUnits() == Qgis::DistanceUnit::Degrees;

  // --- title -------------------------------------------------------------
  QgsExpressionContext context( QgsExpressionContextUtils::globalProjectLayerScopes( layer ) );
  context.setFeature( feature );
  QgsExpression display( layer->displayExpression() );
  QString title = display.isValid() ? display.evaluate( &context ).toString().trimmed() : QString();
  if ( title.isEmpty() )
    title = QObject::tr( "obiekt %1" ).arg( fid );
  result.insert( QStringLiteral( "title" ), title );
  result.insert( QStringLiteral( "layerName" ), layer->name() );
  result.insert( QStringLiteral( "fid" ), fid );
  result.insert( QStringLiteral( "mapCrs" ), mapCrs.authid() );
  result.insert( QStringLiteral( "geometryType" ), geometryKind( layer ) );

  // --- attributes, formatted as in the form --------------------------------
  QVariantList attributes;
  const QgsFields fields = layer->fields();
  for ( int i = 0; i < fields.count(); ++i )
  {
    const QString name = fields.at( i ).name();
    if ( FeatureIdentity::isIdentityField( name ) || name.compare( QLatin1String( "fid" ), Qt::CaseInsensitive ) == 0 )
      continue;
    const QgsEditorWidgetSetup setup = layer->editorWidgetSetup( i );
    if ( setup.type() == QLatin1String( "Hidden" ) )
      continue;
    const QVariant raw = feature.attribute( i );
    QString text;
    if ( QgsVariantUtils::isNull( raw ) )
    {
      text = QStringLiteral( "—" );
    }
    else
    {
      QgsFieldFormatter *formatter = QgsApplication::fieldFormatterRegistry()->fieldFormatter( setup.type() );
      const QVariant cache = formatter->createCache( layer, i, setup.config() );
      text = formatter->representValue( layer, i, setup.config(), cache, raw );
    }
    QVariantMap a;
    a.insert( QStringLiteral( "name" ), layer->attributeDisplayName( i ) );
    a.insert( QStringLiteral( "field" ), name );
    a.insert( QStringLiteral( "value" ), text );
    // [WF-OBJECT-ATLAS] what the pencil needs: may it be edited, and how
    const QgsField &field = fields.at( i );
    const QString kind = kindOf( field, setup );
#if _QGIS_VERSION_INT >= 33800
    const bool canChange = layer->dataProvider() && ( layer->dataProvider()->capabilities() & Qgis::VectorProviderCapability::ChangeAttributeValues );
    const bool fromProvider = fields.fieldOrigin( i ) == Qgis::FieldOrigin::Provider;
#else
    const bool canChange = layer->dataProvider() && ( layer->dataProvider()->capabilities() & QgsVectorDataProvider::ChangeAttributeValues );
    const bool fromProvider = fields.fieldOrigin( i ) == QgsFields::OriginProvider;
#endif
    const bool editable = !layer->readOnly() && canChange && fromProvider && !layer->editFormConfig().readOnly( i );
    a.insert( QStringLiteral( "editable" ), editable );
    a.insert( QStringLiteral( "kind" ), kind );
    a.insert( QStringLiteral( "numeric" ), kind == QLatin1String( "number" ) );
    if ( kind == QLatin1String( "valuemap" ) )
      a.insert( QStringLiteral( "options" ), valueMapOptions( setup ) );
    QString rawText;
    if ( !QgsVariantUtils::isNull( raw ) )
    {
      if ( kind == QLatin1String( "date" ) )
        rawText = raw.toDate().toString( Qt::ISODate );
      else if ( kind == QLatin1String( "datetime" ) )
        rawText = raw.toDateTime().toString( QStringLiteral( "yyyy-MM-dd HH:mm" ) );
      else if ( kind == QLatin1String( "bool" ) )
        rawText = raw.toBool() ? QStringLiteral( "1" ) : QStringLiteral( "0" );
      else
        rawText = raw.toString();
    }
    a.insert( QStringLiteral( "raw" ), rawText );
    attributes << a;
  }
  result.insert( QStringLiteral( "attributes" ), attributes );

  // --- measures ------------------------------------------------------------
  const QgsGeometry geometry = feature.geometry();
  QVariantList measures;
  if ( !geometry.isNull() )
  {
    QgsDistanceArea da;
    da.setSourceCrs( layer->crs(), project->transformContext() );
    if ( !project->ellipsoid().isEmpty() )
      da.setEllipsoid( project->ellipsoid() );
    auto measure = [&measures]( const QString &name, const QString &value ) {
      QVariantMap m;
      m.insert( QStringLiteral( "name" ), name );
      m.insert( QStringLiteral( "value" ), value );
      measures << m;
    };
    switch ( static_cast<Qgis::GeometryType>( layer->geometryType() ) )
    {
      case Qgis::GeometryType::Polygon:
        measure( QObject::tr( "Pole" ), areaText( da.convertAreaMeasurement( da.measureArea( geometry ), Qgis::AreaUnit::SquareMeters ) ) );
        measure( QObject::tr( "Obwód" ), lengthText( da.convertLengthMeasurement( da.measurePerimeter( geometry ), Qgis::DistanceUnit::Meters ) ) );
        break;
      case Qgis::GeometryType::Line:
        measure( QObject::tr( "Długość" ), lengthText( da.convertLengthMeasurement( da.measureLength( geometry ), Qgis::DistanceUnit::Meters ) ) );
        break;
      default:
      {
        const QgsPointXY p = geometry.asPoint();
        const bool degrees = layer->crs().mapUnits() == Qgis::DistanceUnit::Degrees;
        measure( QStringLiteral( "X" ), formatNumber( p.x(), degrees ? 6 : 2 ) );
        measure( QStringLiteral( "Y" ), formatNumber( p.y(), degrees ? 6 : 2 ) );
        break;
      }
    }
  }
  result.insert( QStringLiteral( "measures" ), measures );

  // --- the object in the map CRS -------------------------------------------
  QgsGeometry onMap = geometry;
  if ( !onMap.isNull() )
  {
    try
    {
      onMap.transform( toMap );
    }
    catch ( QgsCsException & )
    {
      onMap = QgsGeometry();
    }
  }
  result.insert( QStringLiteral( "parts" ), partsOf( onMap ) );

  // --- photos (attachment table of the layer) ------------------------------
  QVariantList photos;
  const int uuidIndex = FeatureIdentity::uuidFieldIndex( layer->fields() );
  const QString parentUuid = uuidIndex >= 0 ? feature.attribute( uuidIndex ).toString() : QString();
  const QString home = project->homePath();
  {
    ZalacznikiUtils attachments;
    const QVariantMap relation = attachments.relacjaZalacznikow( layer );
    QgsVectorLayer *child = relation.value( QStringLiteral( "istnieje" ) ).toBool()
                              ? qobject_cast<QgsVectorLayer *>( relation.value( QStringLiteral( "warstwa" ) ).value<QObject *>() )
                              : nullptr;
    if ( child && child->isValid() )
    {
      const int pathIndex = child->fields().lookupField( relation.value( QStringLiteral( "poleSciezki" ) ).toString() );
      const int keyIndex = child->fields().lookupField( relation.value( QStringLiteral( "poleObce" ) ).toString() );
      const int parentUuidIndex = child->fields().lookupField( FeatureIdentity::parentUuidFieldName() );
      const int photoUuidIndex = FeatureIdentity::uuidFieldIndex( child->fields() );
      const QVariant key = attachments.kluczRodzica( layer, feature );
      if ( pathIndex >= 0 )
      {
        QgsFeatureRequest request;
#if _QGIS_VERSION_INT >= 33600
        request.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
#else
        request.setFlags( QgsFeatureRequest::NoGeometry );
#endif
        QList<QgsFeature> found;
        QgsFeatureIterator it = child->getFeatures( request );
        QgsFeature row;
        while ( it.nextFeature( row ) )
        {
          const bool byUuid = parentUuidIndex >= 0 && !parentUuid.isEmpty() && row.attribute( parentUuidIndex ).toString() == parentUuid;
          const bool byKey = keyIndex >= 0 && !QgsVariantUtils::isNull( key ) && row.attribute( keyIndex ).toString() == key.toString();
          if ( byUuid || byKey )
            found << row;
        }
        std::sort( found.begin(), found.end(), []( const QgsFeature &a, const QgsFeature &b ) { return a.id() < b.id(); } );
        for ( const QgsFeature &photo : std::as_const( found ) )
        {
          const QString path = normalisedPath( photo.attribute( pathIndex ).toString() );
          if ( path.isEmpty() )
            continue;
          QVariantMap p;
          p.insert( QStringLiteral( "number" ), photos.size() + 1 );
          p.insert( QStringLiteral( "path" ), path );
          p.insert( QStringLiteral( "name" ), QFileInfo( path ).fileName() );
          p.insert( QStringLiteral( "absolutePath" ), QFileInfo( path ).isAbsolute() ? path : QDir( home ).filePath( path ) );
          p.insert( QStringLiteral( "uuid" ), photoUuidIndex >= 0 ? photo.attribute( photoUuidIndex ).toString() : QString() );
          p.insert( QStringLiteral( "cone" ), QVariant() );
          photos << p;
        }
      }
    }
  }

  // --- view cones of those photos ------------------------------------------
  QgsRectangle conesBox;
  const QString gpkg = gpkgOf( layer );
  if ( !photos.isEmpty() && !gpkg.isEmpty() )
  {
    QgsVectorLayer *cones = nullptr;
    std::unique_ptr<QgsVectorLayer> temporary;
    const auto all = project->mapLayers();
    for ( QgsMapLayer *candidate : all )
    {
      QgsVectorLayer *v = qobject_cast<QgsVectorLayer *>( candidate );
      if ( !v || v->providerType() != QLatin1String( "ogr" ) )
        continue;
      const QVariantMap parts = QgsProviderRegistry::instance()->decodeUri( v->providerType(), v->source() );
      if ( parts.value( QStringLiteral( "layerName" ) ).toString() == kConesTable && QFileInfo( parts.value( QStringLiteral( "path" ) ).toString() ) == QFileInfo( gpkg ) )
      {
        cones = v;
        break;
      }
    }
    if ( !cones )
    {
      temporary = std::make_unique<QgsVectorLayer>( QStringLiteral( "%1|layername=%2" ).arg( gpkg, kConesTable ), kConesTable, QStringLiteral( "ogr" ) );
      if ( temporary->isValid() )
        cones = temporary.get();
    }

    if ( cones )
    {
      const QgsCoordinateTransform conesToMap( cones->crs(), mapCrs, project->transformContext() );
      const QgsFields cf = cones->fields();
      auto value = [&cf]( const QgsFeature &f, const char *name ) { const int i = cf.lookupField( QString::fromLatin1( name ) ); return i >= 0 ? f.attribute( i ) : QVariant(); };

      // the best cone for each photo: confirmed first, then the newest
      QHash<int, QgsFeature> best;
      QgsFeatureIterator it = cones->getFeatures();
      QgsFeature cone;
      while ( it.nextFeature( cone ) )
      {
        const QString photoUuid = value( cone, "PHOTO_UUID" ).toString();
        const QString photoPath = normalisedPath( value( cone, "PHOTO_PATH" ).toString() );
        for ( int i = 0; i < photos.size(); ++i )
        {
          const QVariantMap p = photos.at( i ).toMap();
          const bool same = ( !photoUuid.isEmpty() && photoUuid == p.value( QStringLiteral( "uuid" ) ).toString() )
                            || ( !photoPath.isEmpty() && photoPath == p.value( QStringLiteral( "path" ) ).toString() );
          if ( !same )
            continue;
          if ( best.contains( i ) )
          {
            const QgsFeature &old = best[i];
            const int oldConfirmed = value( old, "CONFIRMED" ).toInt();
            const int newConfirmed = value( cone, "CONFIRMED" ).toInt();
            if ( oldConfirmed > newConfirmed )
              break;
            if ( oldConfirmed == newConfirmed && value( old, "CREATED" ).toString() > value( cone, "CREATED" ).toString() )
              break;
          }
          best[i] = cone;
          break;
        }
      }

      for ( auto b = best.constBegin(); b != best.constEnd(); ++b )
      {
        QgsGeometry polygon = b.value().geometry();
        QgsPointXY stand( value( b.value(), "STAND_X" ).toDouble(), value( b.value(), "STAND_Y" ).toDouble() );
        try
        {
          polygon.transform( conesToMap );
          stand = conesToMap.transform( stand );
        }
        catch ( QgsCsException & )
        {
          continue;
        }
        const QVariantList rings = partsOf( polygon );

        // [WF-VIEW-CONE] 25.10.2026 (Piotr 10:20) — the cone is a CIRCULAR
        // SECTOR: apex at the stand, the camera's field of view, radius = the
        // far edge of the frame (the farthest vertex of the stored footprint,
        // so older footprint-shaped cones become sectors too), at most RANGE_M.
        const double azimuth = value( b.value(), "AZIMUTH" ).toDouble();
        double fovH = value( b.value(), "FOV_H" ).toDouble();
        if ( fovH <= 0 || fovH >= 360 )
          fovH = 60.0;
        double radius = 0.0;
        for ( auto v = polygon.vertices_begin(); v != polygon.vertices_end(); ++v )
          radius = std::max( radius, std::hypot( ( *v ).x() - stand.x(), ( *v ).y() - stand.y() ) );
        const double rangeLimit = value( b.value(), "RANGE_M" ).toDouble();
        if ( radius <= 0 )
          radius = rangeLimit > 0 ? rangeLimit : 8.0;
        else if ( rangeLimit > 0 )
          radius = std::min( radius, rangeLimit );
        QVariantList sector;
        sector << QVariant( point( stand.x(), stand.y() ) );
        const int steps = 24;
        for ( int i = 0; i <= steps; ++i )
        {
          const double a = qDegreesToRadians( azimuth - fovH / 2.0 + fovH * i / steps );
          sector << QVariant( point( stand.x() + radius * std::sin( a ), stand.y() + radius * std::cos( a ) ) );
        }
        sector << QVariant( point( stand.x(), stand.y() ) );
        conesBox.combineExtentWith( QgsRectangle( stand.x() - radius, stand.y() - radius, stand.x() + radius, stand.y() + radius ) );

        QVariantMap c;
        c.insert( QStringLiteral( "sector" ), sector );
        c.insert( QStringLiteral( "radius" ), radius );
        c.insert( QStringLiteral( "uuid" ), value( b.value(), "uuid" ).toString() );
        c.insert( QStringLiteral( "polygon" ), rings.isEmpty() ? QVariantList() : rings.first().toList() );
        c.insert( QStringLiteral( "stand" ), point( stand.x(), stand.y() ) );
        c.insert( QStringLiteral( "azimuth" ), value( b.value(), "AZIMUTH" ).toDouble() );
        c.insert( QStringLiteral( "range" ), value( b.value(), "RANGE_M" ).toDouble() );
        c.insert( QStringLiteral( "fovH" ), value( b.value(), "FOV_H" ).toDouble() );
        c.insert( QStringLiteral( "source" ), value( b.value(), "SOURCE" ).toString() );
        c.insert( QStringLiteral( "confirmed" ), value( b.value(), "CONFIRMED" ).toInt() == 1 );
        QVariantMap p = photos.at( b.key() ).toMap();
        p.insert( QStringLiteral( "cone" ), c );
        photos[b.key()] = p;
      }
    }
  }
  result.insert( QStringLiteral( "photos" ), photos );

  // --- extents ---------------------------------------------------------------
  const double minimum = geographic ? 0.0002 : 20.0;
  QgsRectangle objectBox = onMap.isNull() ? QgsRectangle() : onMap.boundingBox();
  if ( !conesBox.isNull() )
  {
    if ( objectBox.isNull() )
      objectBox = conesBox;
    else
      objectBox.combineExtentWith( conesBox );
  }
  objectBox = atLeast( objectBox, minimum );
  if ( !objectBox.isNull() )
    objectBox.scale( 1.2 );

  QgsRectangle overview;
  try
  {
    overview = toMap.transformBoundingBox( layer->extent() );
  }
  catch ( QgsCsException & )
  {
    overview = QgsRectangle();
  }
  if ( overview.isNull() || overview.isEmpty() )
    overview = objectBox;
  else
    overview.combineExtentWith( objectBox );
  // a single object (or a tight cluster): the overview must still show
  // the surroundings, otherwise it is the object map once more
  if ( !overview.isNull() && overview.width() < objectBox.width() * 3 && overview.height() < objectBox.height() * 3 )
  {
    const QgsPointXY c = objectBox.center();
    overview = QgsRectangle( c.x() - objectBox.width() * 2.5, c.y() - objectBox.height() * 2.5, c.x() + objectBox.width() * 2.5, c.y() + objectBox.height() * 2.5 );
  }
  else if ( !overview.isNull() )
  {
    overview.scale( 1.1 );
  }
  result.insert( QStringLiteral( "objectExtent" ), objectBox.isNull() ? QVariantList() : rect( objectBox ) );
  result.insert( QStringLiteral( "overviewExtent" ), overview.isNull() ? QVariantList() : rect( overview ) );
  result.insert( QStringLiteral( "ok" ), true );
  return result;
}

int ObjectAtlas::renderMap( QgsProject *project, QgsVectorLayer *layer, const QVariantList &extent, int width, int height, double dpr, const QString &slot, const QVariantMap &style )
{
  const int request = ++mLastRequest;
  const QgsRectangle r = rectFrom( extent );
  if ( !project || r.isNull() || width < 8 || height < 8 )
  {
    QVariantMap failed;
    failed.insert( QStringLiteral( "request" ), request );
    failed.insert( QStringLiteral( "slot" ), slot );
    failed.insert( QStringLiteral( "ok" ), false );
    QMetaObject::invokeMethod( this, [this, failed]() { emit mapRendered( failed ); }, Qt::QueuedConnection );
    return request;
  }

  // the older request of this slot is no longer wanted
  if ( mJobs.contains( slot ) && mJobs[slot].job )
  {
    QgsMapRendererParallelJob *old = mJobs[slot].job;
    old->disconnect( this );
    old->cancelWithoutBlocking();
    connect( old, &QgsMapRendererJob::finished, old, &QObject::deleteLater );
    mJobs.remove( slot );
  }

  const double ratio = dpr > 0.5 ? dpr : 1.0;
  QgsMapSettings settings;
  settings.setDestinationCrs( project->crs().isValid() ? project->crs() : ( layer ? layer->crs() : QgsCoordinateReferenceSystem() ) );
  settings.setTransformContext( project->transformContext() );
  settings.setEllipsoid( project->ellipsoid() );
  settings.setOutputSize( QSize( static_cast<int>( width * ratio ), static_cast<int>( height * ratio ) ) );
  settings.setOutputDpi( 96.0 * ratio );
  settings.setBackgroundColor( project->backgroundColor().isValid() ? project->backgroundColor() : QColor( Qt::white ) );
  settings.setFlag( Qgis::MapSettingsFlag::Antialiasing, true );
  settings.setFlag( Qgis::MapSettingsFlag::DrawLabeling, true );
  settings.setExtent( r );

  // what the user sees on the map: the visible layers, in legend order
  QList<QgsMapLayer *> visible;
  if ( project->layerTreeRoot() )
  {
    const QList<QgsMapLayer *> order = project->layerTreeRoot()->layerOrder();
    for ( QgsMapLayer *l : order )
    {
      QgsLayerTreeLayer *node = project->layerTreeRoot()->findLayer( l );
      if ( node && node->isVisible() )
        visible << l;
    }
  }
  if ( layer && !visible.contains( layer ) )
    visible.prepend( layer );
  // [WF-OBJECT-ATLAS] the atlas colouring / labels: a styled clone in place
  // of the layer, the project untouched
  QgsVectorLayer *drawn = layer ? styledLayer( layer, style ) : nullptr;
  if ( drawn && drawn != layer )
    visible.replace( visible.indexOf( layer ), drawn );
  settings.setLayers( visible );

  QgsExpressionContext context;
  context << QgsExpressionContextUtils::globalScope() << QgsExpressionContextUtils::projectScope( project ) << QgsExpressionContextUtils::mapSettingsScope( settings );
  settings.setExpressionContext( context );

  Job job;
  job.request = request;
  job.slot = slot;
  job.width = width;
  job.height = height;
  job.extent = rect( settings.visibleExtent() );
  if ( drawn && !style.value( QStringLiteral( "colorBy" ) ).toString().isEmpty() )
    job.legend = legendOf( drawn );
  job.job = new QgsMapRendererParallelJob( settings );
  mJobs.insert( slot, job );

  QgsMapRendererParallelJob *running = job.job;
  connect( running, &QgsMapRendererJob::finished, this, [this, running, slot]() {
    if ( !mJobs.contains( slot ) || mJobs[slot].job != running )
    {
      running->deleteLater();
      return;
    }
    const Job done = mJobs.take( slot );
    const QImage image = running->renderedImage();
    running->deleteLater();

    const QString dir = QStandardPaths::writableLocation( QStandardPaths::CacheLocation ) + QStringLiteral( "/atlas" );
    QDir().mkpath( dir );
    const QString file = QStringLiteral( "%1/%2_%3.png" ).arg( dir, slot ).arg( ++mFileCounter );
    // the previous picture of this slot is not needed once the new one is there
    const QStringList old = QDir( dir ).entryList( { slot + QStringLiteral( "_*.png" ) }, QDir::Files );
    const bool saved = image.save( file, "PNG" );
    for ( const QString &o : old )
    {
      if ( QDir( dir ).filePath( o ) != file )
        QFile::remove( QDir( dir ).filePath( o ) );
    }

    QVariantMap result;
    result.insert( QStringLiteral( "request" ), done.request );
    result.insert( QStringLiteral( "slot" ), slot );
    result.insert( QStringLiteral( "ok" ), saved );
    result.insert( QStringLiteral( "image" ), QUrl::fromLocalFile( file ).toString() );
    result.insert( QStringLiteral( "path" ), file );
    result.insert( QStringLiteral( "extent" ), done.extent );
    result.insert( QStringLiteral( "legend" ), done.legend );
    result.insert( QStringLiteral( "width" ), done.width );
    result.insert( QStringLiteral( "height" ), done.height );
    emit mapRendered( result );
  } );
  running->start();
  return request;
}

// ==========================================================================
// [WF-OBJECT-ATLAS] 25.10.2026 — editing in place, colouring, labels
// ==========================================================================

QgsVectorLayer *ObjectAtlas::styledLayer( QgsVectorLayer *layer, const QVariantMap &style )
{
  const QString colorBy = style.value( QStringLiteral( "colorBy" ) ).toString();
  const QString labelBy = style.value( QStringLiteral( "labelBy" ) ).toString();
  if ( colorBy.isEmpty() && labelBy.isEmpty() )
    return layer;
  const QString key = QStringLiteral( "%1|%2|%3|%4" ).arg( layer->id(), colorBy, labelBy ).arg( mStyleGeneration );
  if ( mStyled && key == mStyledKey )
    return mStyled;
  if ( mStyled )
  {
    // a render started a moment ago may still hold it: away a bit later
    QgsVectorLayer *old = mStyled;
    QTimer::singleShot( 15000, old, &QObject::deleteLater );
  }
  mStyled = layer->clone();
  mStyledKey = key;
  if ( mStyled )
    applyAtlasStyle( mStyled, colorBy, labelBy );
  return mStyled ? mStyled : layer;
}

QVariantList ObjectAtlas::legendOf( QgsVectorLayer *layer ) const
{
  QVariantList out;
  if ( !layer || !layer->renderer() )
    return out;
  const QgsLegendSymbolList items = layer->renderer()->legendSymbolItems();
  for ( const QgsLegendSymbolItem &item : items )
  {
    if ( !item.symbol() )
      continue;
    QVariantMap m;
    m.insert( QStringLiteral( "label" ), item.label() );
    m.insert( QStringLiteral( "color" ), item.symbol()->color().name() );
    out << m;
    if ( out.size() >= 16 )
      break;
  }
  return out;
}

QVariantMap ObjectAtlas::setValue( QgsVectorLayer *layer, qlonglong fid, const QString &field, const QVariant &value )
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !layer || !layer->isValid() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Nie ma warstwy." ) );
    return result;
  }
  const int index = layer->fields().lookupField( field );
  if ( index < 0 )
  {
    result.insert( QStringLiteral( "message" ), tr( "Warstwa nie ma pola %1." ).arg( field ) );
    return result;
  }
  const QgsField target = layer->fields().at( index );
  QVariant converted = value;
  if ( value.toString().isEmpty() && target.type() != QMetaType::QString )
    converted = QVariant();
  QString error;
  if ( !target.convertCompatible( converted, &error ) )
  {
    result.insert( QStringLiteral( "message" ), tr( "„%1” nie pasuje do pola %2: %3" ).arg( value.toString(), field, error ) );
    return result;
  }

  bool started = false;
  if ( !layer->isEditable() )
  {
    if ( !layer->startEditing() )
    {
      result.insert( QStringLiteral( "message" ), tr( "Warstwy nie da się edytować." ) );
      return result;
    }
    started = true;
  }
  bool ok = layer->changeAttributeValue( fid, index, converted );
  QString message;
  if ( started )
  {
    if ( ok )
    {
      ok = layer->commitChanges();
      if ( !ok )
      {
        message = layer->commitErrors().join( QStringLiteral( "; " ) );
        layer->rollBack();
      }
    }
    else
    {
      layer->rollBack();
    }
  }
  if ( ok )
  {
    mStyleGeneration++; // colours and labels may depend on this value
    message = started ? tr( "Zapisano: %1." ).arg( layer->attributeDisplayName( index ) )
                      : tr( "Zmieniono %1 — warstwa jest w edycji, zapisz ją." ).arg( layer->attributeDisplayName( index ) );
  }
  else if ( message.isEmpty() )
  {
    message = tr( "Nie udało się zapisać %1." ).arg( layer->attributeDisplayName( index ) );
  }
  result.insert( QStringLiteral( "ok" ), ok );
  result.insert( QStringLiteral( "message" ), message );
  return result;
}

QVariantMap ObjectAtlas::applyToLayer( QgsProject *project, QgsVectorLayer *layer, const QVariantMap &style )
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !project || !layer || !layer->isValid() )
    return result;

  const QString atlasStyle = tr( "Atlas obiektów" );
  const QString colorBy = style.value( QStringLiteral( "colorBy" ) ).toString();
  const QString labelBy = style.value( QStringLiteral( "labelBy" ) ).toString();
  QgsMapLayerStyleManager *manager = layer->styleManager();
  QString previous = layer->customProperty( kPreviousStyleProperty ).toString();

  if ( colorBy.isEmpty() && labelBy.isEmpty() )
  {
    // back to the style the layer had before the atlas
    if ( manager->currentStyle() == atlasStyle )
    {
      if ( previous.isEmpty() || !manager->styles().contains( previous ) )
      {
        previous.clear();
        for ( const QString &name : manager->styles() )
        {
          if ( name != atlasStyle )
          {
            previous = name;
            break;
          }
        }
      }
      if ( !previous.isEmpty() )
        manager->setCurrentStyle( previous );
    }
    if ( manager->styles().contains( atlasStyle ) && manager->currentStyle() != atlasStyle )
      manager->removeStyle( atlasStyle );
    layer->removeCustomProperty( kAtlasStyleProperty );
    layer->removeCustomProperty( kPreviousStyleProperty );
    result.insert( QStringLiteral( "message" ), tr( "Warstwa „%1” wróciła do swojego stylu." ).arg( layer->name() ) );
  }
  else
  {
    if ( manager->currentStyle() != atlasStyle )
    {
      previous = manager->currentStyle();
      layer->setCustomProperty( kPreviousStyleProperty, previous );
      if ( !manager->styles().contains( atlasStyle ) )
        manager->addStyleFromLayer( atlasStyle );
      manager->setCurrentStyle( atlasStyle );
    }
    // start from the look the layer had, then colour / label on top
    if ( !previous.isEmpty() && manager->styles().contains( previous ) )
      manager->style( previous ).writeToLayer( layer );
    applyAtlasStyle( layer, colorBy, labelBy );
    layer->setCustomProperty( kAtlasStyleProperty, colorBy + QLatin1Char( '|' ) + labelBy );
    result.insert( QStringLiteral( "message" ), tr( "Kolory i etykiety atlasu są teraz stylem warstwy „%1” (styl „%2”; poprzedni zostaje)." ).arg( layer->name(), atlasStyle ) );
  }
  layer->triggerRepaint();
  layer->emitStyleChanged();
  const bool saved = !project->fileName().isEmpty() && project->write();
  if ( !saved )
    result.insert( QStringLiteral( "message" ), result.value( QStringLiteral( "message" ) ).toString() + QStringLiteral( " " ) + tr( "Projektu NIE zapisano." ) );
  result.insert( QStringLiteral( "ok" ), true );
  return result;
}

QVariantMap ObjectAtlas::keptStyle( QgsProject *project, QgsVectorLayer *layer ) const
{
  Q_UNUSED( project )
  QVariantMap out;
  if ( !layer )
    return out;
  const QString kept = layer->customProperty( kAtlasStyleProperty ).toString();
  if ( kept.isEmpty() )
    return out;
  out.insert( QStringLiteral( "colorBy" ), kept.section( QLatin1Char( '|' ), 0, 0 ) );
  out.insert( QStringLiteral( "labelBy" ), kept.section( QLatin1Char( '|' ), 1, 1 ) );
  return out;
}

QVariantMap ObjectAtlas::lastEdited( QgsProject *project ) const
{
  QVariantMap result;
  if ( !project )
    return result;

  // atlas layers by "<file>|<table>"; the files to read
  QHash<QString, QgsVectorLayer *> byTable;
  QSet<QString> files;
  for ( const QVariant &v : layers( project ) )
  {
    QgsVectorLayer *layer = qobject_cast<QgsVectorLayer *>( v.toMap().value( QStringLiteral( "layer" ) ).value<QObject *>() );
    const QString file = gpkgOf( layer );
    if ( file.isEmpty() )
      continue;
    const QVariantMap parts = QgsProviderRegistry::instance()->decodeUri( layer->providerType(), layer->source() );
    const QString canonical = QFileInfo( file ).canonicalFilePath();
    byTable.insert( canonical + QLatin1Char( '|' ) + parts.value( QStringLiteral( "layerName" ) ).toString().toLower(), layer );
    files.insert( canonical );
  }

  QString bestTime;
  for ( const QString &file : std::as_const( files ) )
  {
    sqlite3 *db = nullptr;
    if ( sqlite3_open_v2( file.toUtf8().constData(), &db, SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
    {
      if ( db )
        sqlite3_close( db );
      continue;
    }
    sqlite3_stmt *statement = nullptr;
    const char *sql = "SELECT TABLE_NAME, FID, TIME_UTC FROM WF_JOURNAL WHERE EVENT <> 'deleted' AND FID IS NOT NULL ORDER BY SEQ DESC LIMIT 200";
    if ( sqlite3_prepare_v2( db, sql, -1, &statement, nullptr ) == SQLITE_OK )
    {
      while ( sqlite3_step( statement ) == SQLITE_ROW )
      {
        const QString table = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( statement, 0 ) ) );
        const qlonglong fid = sqlite3_column_int64( statement, 1 );
        const QString time = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( statement, 2 ) ) );
        QgsVectorLayer *layer = byTable.value( file + QLatin1Char( '|' ) + table.toLower(), nullptr );
        if ( !layer )
          continue; // photos, journal tables, layers outside the atlas
        if ( !layer->getFeature( fid ).isValid() )
          continue; // deleted since, or written under another fid
        if ( time > bestTime )
        {
          bestTime = time;
          result.insert( QStringLiteral( "layerId" ), layer->id() );
          result.insert( QStringLiteral( "fid" ), fid );
          result.insert( QStringLiteral( "time" ), time );
        }
        break; // the newest usable row of this file
      }
    }
    if ( statement )
      sqlite3_finalize( statement );
    sqlite3_close( db );
  }
  return result;
}

// ==========================================================================
// [WF-ATLAS-SHAPE] 26.10.2026 — micro editing of the shape
// ==========================================================================

QVariantMap ObjectAtlas::editableGeometry( QgsProject *project, QgsVectorLayer *layer, qlonglong fid ) const
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !project || !layer || !layer->isValid() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Nie ma warstwy." ) );
    return result;
  }
  if ( !canChangeGeometries( layer ) )
  {
    result.insert( QStringLiteral( "message" ), tr( "Warstwa „%1” nie pozwala zmieniać kształtów." ).arg( layer->name() ) );
    return result;
  }
  const QgsFeature feature = layer->getFeature( fid );
  const QgsGeometry geometry = feature.isValid() ? feature.geometry() : QgsGeometry();
  if ( geometry.isNull() || geometry.isEmpty() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Obiekt nie ma geometrii — nie ma czego poprawiać." ) );
    return result;
  }
  if ( QgsWkbTypes::isCurvedType( geometry.wkbType() ) )
  {
    result.insert( QStringLiteral( "message" ), tr( "Obiekt ma łuki — mikro-edycja zna tylko odcinki." ) );
    return result;
  }

  const QgsCoordinateReferenceSystem mapCrs = project->crs().isValid() ? project->crs() : layer->crs();
  const QgsCoordinateTransform toMap( layer->crs(), mapCrs, project->transformContext() );
  const bool hasZ = QgsWkbTypes::hasZ( geometry.wkbType() );
  const bool hasM = QgsWkbTypes::hasM( geometry.wkbType() );

  QVariantList rings;
  int count = 0;
  bool failed = false;
  auto ringOf = [&]( const QgsCurve *curve, int part, int ring, bool closed ) {
    QgsPointSequence points;
    if ( curve )
      curve->points( points );
    if ( closed && points.size() > 1 && points.first() == points.last() )
      points.removeLast();
    QVariantList vertices;
    for ( const QgsPoint &p : std::as_const( points ) )
    {
      QgsPointXY m;
      try
      {
        m = toMap.transform( QgsPointXY( p.x(), p.y() ) );
      }
      catch ( QgsCsException & )
      {
        failed = true;
        return;
      }
      vertices << QVariant( QVariantList { m.x(), m.y(), p.x(), p.y(), hasZ ? p.z() : 0.0, hasM ? p.m() : 0.0 } );
    }
    count += vertices.size();
    QVariantMap r;
    r.insert( QStringLiteral( "part" ), part );
    r.insert( QStringLiteral( "ring" ), ring );
    r.insert( QStringLiteral( "closed" ), closed );
    r.insert( QStringLiteral( "vertices" ), vertices );
    rings << r;
  };

  int part = 0;
  for ( auto it = geometry.const_parts_begin(); it != geometry.const_parts_end(); ++it, ++part )
  {
    const QgsAbstractGeometry *g = *it;
    if ( const QgsCurvePolygon *polygon = qgsgeometry_cast<const QgsCurvePolygon *>( g ) )
    {
      ringOf( polygon->exteriorRing(), part, 0, true );
      for ( int r = 0; r < polygon->numInteriorRings(); ++r )
        ringOf( polygon->interiorRing( r ), part, r + 1, true );
    }
    else if ( const QgsCurve *curve = qgsgeometry_cast<const QgsCurve *>( g ) )
    {
      ringOf( curve, part, 0, false );
    }
    else if ( const QgsPoint *p = qgsgeometry_cast<const QgsPoint *>( g ) )
    {
      QgsLineString one;
      one.addVertex( *p );
      ringOf( &one, part, 0, false );
    }
  }
  if ( failed )
  {
    result.insert( QStringLiteral( "message" ), tr( "Nie umiem przeliczyć obiektu do układu mapy." ) );
    return result;
  }
  if ( count > kMaxEditVertices )
  {
    result.insert( QStringLiteral( "message" ), tr( "Obiekt ma %1 wierzchołków — za dużo na mikro-edycję (najwyżej %2)." ).arg( count ).arg( kMaxEditVertices ) );
    return result;
  }
  result.insert( QStringLiteral( "ok" ), true );
  result.insert( QStringLiteral( "kind" ), geometryKind( layer ) );
  result.insert( QStringLiteral( "hasZ" ), hasZ );
  result.insert( QStringLiteral( "hasM" ), hasM );
  result.insert( QStringLiteral( "vertexCount" ), count );
  result.insert( QStringLiteral( "rings" ), rings );
  return result;
}

QgsGeometry ObjectAtlas::geometryFromRings( QgsProject *project, QgsVectorLayer *layer, const QVariantList &rings, QString &error, double *shift ) const
{
  error.clear();
  if ( shift )
    *shift = 0;
  if ( !project || !layer || rings.isEmpty() )
  {
    error = tr( "Nie ma kształtu do zapisania." );
    return QgsGeometry();
  }
  const Qgis::WkbType layerType = layer->wkbType();
  const bool hasZ = QgsWkbTypes::hasZ( layerType );
  const bool hasM = QgsWkbTypes::hasM( layerType );
  const bool multi = QgsWkbTypes::isMultiType( layerType );
  const Qgis::GeometryType type = static_cast<Qgis::GeometryType>( layer->geometryType() );
  const QgsCoordinateReferenceSystem mapCrs = project->crs().isValid() ? project->crs() : layer->crs();
  const QgsCoordinateTransform toLayer( mapCrs, layer->crs(), project->transformContext() );
  const QgsDistanceArea da = distanceArea( project, layer );

  // part -> rings in order (exterior first)
  std::map<int, std::map<int, std::unique_ptr<QgsLineString>>> parts;
  for ( const QVariant &rv : rings )
  {
    const QVariantMap r = rv.toMap();
    const QVariantList vertices = r.value( QStringLiteral( "vertices" ) ).toList();
    QVector<double> xs, ys, zs, ms;
    for ( const QVariant &vv : vertices )
    {
      const QVariantList v = vv.toList();
      if ( v.size() < 2 )
        continue;
      // a new vertex comes with null in place of the original coordinates
      auto present = []( const QVariant &x ) { return x.isValid() && !x.isNull() && x.userType() != QMetaType::Nullptr; };
      const bool hasOriginal = v.size() >= 4 && present( v.at( 2 ) ) && present( v.at( 3 ) );
      const bool moved = !hasOriginal || ( v.size() >= 7 && v.at( 6 ).toBool() );
      double x, y;
      if ( moved )
      {
        try
        {
          const QgsPointXY p = toLayer.transform( QgsPointXY( v.at( 0 ).toDouble(), v.at( 1 ).toDouble() ) );
          x = p.x();
          y = p.y();
        }
        catch ( QgsCsException & )
        {
          error = tr( "Nie umiem przeliczyć wierzchołka do układu warstwy." );
          return QgsGeometry();
        }
        if ( shift && hasOriginal )
          *shift = std::max( *shift, da.convertLengthMeasurement( da.measureLine( QgsPointXY( v.at( 2 ).toDouble(), v.at( 3 ).toDouble() ), QgsPointXY( x, y ) ), Qgis::DistanceUnit::Meters ) );
      }
      else
      {
        x = v.at( 2 ).toDouble();
        y = v.at( 3 ).toDouble();
      }
      xs << x;
      ys << y;
      zs << ( v.size() >= 5 ? v.at( 4 ).toDouble() : 0.0 );
      ms << ( v.size() >= 6 ? v.at( 5 ).toDouble() : 0.0 );
    }
    const bool closed = r.value( QStringLiteral( "closed" ) ).toBool();
    if ( type == Qgis::GeometryType::Polygon )
    {
      if ( xs.size() < 3 )
      {
        error = tr( "Wielokąt musi mieć co najmniej 3 wierzchołki." );
        return QgsGeometry();
      }
      if ( closed )
      {
        xs << xs.first();
        ys << ys.first();
        zs << zs.first();
        ms << ms.first();
      }
    }
    else if ( type == Qgis::GeometryType::Line && xs.size() < 2 )
    {
      error = tr( "Linia musi mieć co najmniej 2 wierzchołki." );
      return QgsGeometry();
    }
    else if ( type == Qgis::GeometryType::Point && xs.size() != 1 )
    {
      error = tr( "Punkt ma dokładnie jeden wierzchołek." );
      return QgsGeometry();
    }
    parts[r.value( QStringLiteral( "part" ) ).toInt()][r.value( QStringLiteral( "ring" ) ).toInt()] = std::make_unique<QgsLineString>( xs, ys, hasZ ? zs : QVector<double>(), hasM ? ms : QVector<double>() );
  }
  if ( parts.empty() )
  {
    error = tr( "Nie ma kształtu do zapisania." );
    return QgsGeometry();
  }
  if ( !multi && parts.size() > 1 )
  {
    error = tr( "Warstwa jednoczęściowa, a kształt ma %1 części." ).arg( parts.size() );
    return QgsGeometry();
  }

  std::vector<std::unique_ptr<QgsAbstractGeometry>> built;
  for ( auto &p : parts )
  {
    auto &ringsOfPart = p.second;
    if ( type == Qgis::GeometryType::Polygon )
    {
      auto polygon = std::make_unique<QgsPolygon>();
      auto exterior = ringsOfPart.find( 0 );
      if ( exterior == ringsOfPart.end() )
      {
        error = tr( "Część %1 nie ma obrysu zewnętrznego." ).arg( p.first + 1 );
        return QgsGeometry();
      }
      polygon->setExteriorRing( exterior->second.release() );
      for ( auto &ring : ringsOfPart )
      {
        if ( ring.first != 0 && ring.second )
          polygon->addInteriorRing( ring.second.release() );
      }
      built.push_back( std::move( polygon ) );
    }
    else if ( type == Qgis::GeometryType::Line )
    {
      built.push_back( std::move( ringsOfPart.begin()->second ) );
    }
    else
    {
      const QgsLineString *one = ringsOfPart.begin()->second.get();
      built.push_back( std::make_unique<QgsPoint>( one->pointN( 0 ) ) );
    }
  }

  if ( !multi )
    return QgsGeometry( built.front().release() );
  std::unique_ptr<QgsGeometryCollection> collection;
  if ( type == Qgis::GeometryType::Polygon )
    collection = std::make_unique<QgsMultiPolygon>();
  else if ( type == Qgis::GeometryType::Line )
    collection = std::make_unique<QgsMultiLineString>();
  else
    collection = std::make_unique<QgsMultiPoint>();
  for ( auto &g : built )
    collection->addGeometry( g.release() );
  return QgsGeometry( collection.release() );
}

QVariantMap ObjectAtlas::checkGeometry( QgsProject *project, QgsVectorLayer *layer, qlonglong fid, const QVariantList &rings ) const
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !project || !layer || !layer->isValid() )
    return result;
  QString error;
  double shift = 0;
  const QgsGeometry after = geometryFromRings( project, layer, rings, error, &shift );
  result.insert( QStringLiteral( "ok" ), true );
  if ( after.isNull() )
  {
    result.insert( QStringLiteral( "valid" ), false );
    result.insert( QStringLiteral( "problem" ), error );
    return result;
  }
  QVector<QgsGeometry::Error> errors;
  after.validateGeometry( errors, Qgis::GeometryValidationEngine::Geos );
  QString problem;
  if ( !errors.isEmpty() )
    problem = tr( "Kształt jest wadliwy: %1" ).arg( errors.first().what() );
  result.insert( QStringLiteral( "valid" ), problem.isEmpty() );
  result.insert( QStringLiteral( "problem" ), problem );

  const Qgis::GeometryType type = static_cast<Qgis::GeometryType>( layer->geometryType() );
  const QgsDistanceArea da = distanceArea( project, layer );
  QString name, beforeText, afterText;
  double beforeValue = 0, afterValue = 0;
  shapeMeasure( da, layer->getFeature( fid ).geometry(), type, name, beforeValue, beforeText );
  shapeMeasure( da, after, type, name, afterValue, afterText );
  result.insert( QStringLiteral( "measureName" ), name );
  result.insert( QStringLiteral( "before" ), beforeText );
  result.insert( QStringLiteral( "after" ), afterText );
  result.insert( QStringLiteral( "beforeValue" ), beforeValue );
  result.insert( QStringLiteral( "afterValue" ), afterValue );
  result.insert( QStringLiteral( "shift" ), shift );
  result.insert( QStringLiteral( "shiftText" ), lengthText( shift ) );
  return result;
}

QVariantMap ObjectAtlas::saveGeometry( QgsProject *project, QgsVectorLayer *layer, qlonglong fid, const QVariantList &rings )
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !project || !layer || !layer->isValid() || !canChangeGeometries( layer ) )
  {
    result.insert( QStringLiteral( "message" ), tr( "Tej warstwy nie da się edytować." ) );
    return result;
  }
  QString error;
  const QgsGeometry geometry = geometryFromRings( project, layer, rings, error );
  if ( geometry.isNull() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Nie zapisuję: %1" ).arg( error ) );
    return result;
  }
  QVector<QgsGeometry::Error> errors;
  geometry.validateGeometry( errors, Qgis::GeometryValidationEngine::Geos );
  if ( !errors.isEmpty() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Nie zapisuję — kształt jest wadliwy: %1" ).arg( errors.first().what() ) );
    return result;
  }

  bool started = false;
  if ( !layer->isEditable() )
  {
    if ( !layer->startEditing() )
    {
      result.insert( QStringLiteral( "message" ), tr( "Warstwy nie da się edytować." ) );
      return result;
    }
    started = true;
  }
  QgsGeometry toWrite = geometry;
  bool ok = layer->changeGeometry( fid, toWrite );
  QString message;
  if ( started )
  {
    if ( ok )
    {
      ok = layer->commitChanges();
      if ( !ok )
      {
        message = layer->commitErrors().join( QStringLiteral( "; " ) );
        layer->rollBack();
      }
    }
    else
    {
      layer->rollBack();
    }
  }
  if ( ok )
  {
    mStyleGeneration++; // the styled clone must read the new shape
    layer->triggerRepaint();
    message = started ? tr( "Zapisano nowy kształt obiektu." ) : tr( "Kształt zmieniony — warstwa jest w edycji, zapisz ją." );
  }
  else if ( message.isEmpty() )
  {
    message = tr( "Nie udało się zapisać kształtu." );
  }
  result.insert( QStringLiteral( "ok" ), ok );
  result.insert( QStringLiteral( "message" ), message );
  return result;
}

QVariantList ObjectAtlas::snapTargets( QgsProject *project, QgsVectorLayer *layer, qlonglong fid, const QVariantList &extent ) const
{
  QVariantList out;
  const QgsRectangle area = rectFrom( extent );
  if ( !project || area.isNull() || !project->layerTreeRoot() )
    return out;
  const QgsCoordinateReferenceSystem mapCrs = project->crs().isValid() ? project->crs() : ( layer ? layer->crs() : QgsCoordinateReferenceSystem() );
  for ( const QVariant &entry : layers( project ) )
  {
    QgsVectorLayer *candidate = qobject_cast<QgsVectorLayer *>( entry.toMap().value( QStringLiteral( "layer" ) ).value<QObject *>() );
    if ( !candidate )
      continue;
    QgsLayerTreeLayer *node = project->layerTreeRoot()->findLayer( candidate );
    if ( candidate != layer && ( !node || !node->isVisible() ) )
      continue;
    const QgsCoordinateTransform toMap( candidate->crs(), mapCrs, project->transformContext() );
    QgsRectangle inLayer;
    try
    {
      inLayer = toMap.transformBoundingBox( area, Qgis::TransformDirection::Reverse );
    }
    catch ( QgsCsException & )
    {
      continue;
    }
    QgsFeatureRequest request( inLayer );
    request.setNoAttributes();
    QgsFeatureIterator it = candidate->getFeatures( request );
    QgsFeature f;
    while ( it.nextFeature( f ) )
    {
      if ( candidate == layer && f.id() == fid )
        continue;
      const QgsGeometry g = f.geometry();
      for ( auto v = g.vertices_begin(); v != g.vertices_end(); ++v )
      {
        try
        {
          const QgsPointXY p = toMap.transform( QgsPointXY( ( *v ).x(), ( *v ).y() ) );
          if ( area.contains( p ) )
            out << QVariant( point( p.x(), p.y() ) );
        }
        catch ( QgsCsException & )
        {
        }
        if ( out.size() >= kMaxSnapTargets )
          return out;
      }
    }
  }
  return out;
}

QVariantList ObjectAtlas::fromWgs84( QgsProject *project, double longitude, double latitude ) const
{
  if ( !project || !std::isfinite( longitude ) || !std::isfinite( latitude ) )
    return QVariantList();
  const QgsCoordinateReferenceSystem mapCrs = project->crs();
  if ( !mapCrs.isValid() )
    return QVariantList();
  try
  {
    const QgsCoordinateTransform t( QgsCoordinateReferenceSystem( QStringLiteral( "EPSG:4326" ) ), mapCrs, project->transformContext() );
    const QgsPointXY p = t.transform( QgsPointXY( longitude, latitude ) );
    return point( p.x(), p.y() );
  }
  catch ( QgsCsException & )
  {
    return QVariantList();
  }
}
