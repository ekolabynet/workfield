/***************************************************************************
  layerutils.cpp - LayerUtils

 ---------------------
 begin                : 01.03.2021
 copyright            : (C) 2020 by Mathieu Pellerin
 email                : mathieu@opengis.ch
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#include "layerutils.h"
#include <qgscoordinatetransform.h>
#include <qgsproviderregistry.h>
#include <qgsprovidersublayerdetails.h>
#include <qgsfillsymbollayer.h>
#include <qgslinesymbollayer.h>
#include <qgsmarkersymbollayer.h>
#include <qgssymbollayer.h>
#include <qgsfillsymbol.h>
#include <qgslinesymbol.h>
#include <qgsmarkersymbol.h>
#include <qgscategorizedsymbolrenderer.h>
#include <qgsclassificationquantile.h>
#include <qgscolorramp.h>
#include <qgsstyle.h>
#include <qgsgraduatedsymbolrenderer.h>
#include <qgssinglesymbolrenderer.h>
#include <qgssymbol.h>

#include <QQmlEngine>
#include <QScopeGuard>
#include <qgsfillsymbol.h>
#include <qgsfillsymbollayer.h>
#include <qgshuesaturationfilter.h>
#include <qgsjsonutils.h>
#include <qgslabelobstaclesettings.h>
#include <qgslayoutatlas.h>
#include <qgslayoutmanager.h>
#include <qgslinesymbol.h>
#include <qgslinesymbollayer.h>
#include <qgsmaplayerelevationproperties.h>
#include <qgsmarkersymbol.h>
#include <qgsmarkersymbollayer.h>
#include <qgsmemoryproviderutils.h>
#include <qgsmessagelog.h>
#include <qgspallabeling.h>
#include <qgsprintlayout.h>
#include <qgsproject.h>
#include <qgsprojectstylesettings.h>
#include <qgsrasterlayer.h>
#include <qgsrasterlayerelevationproperties.h>
#include <qgssinglesymbolrenderer.h>
#include <qgsstringutils.h>
#include <qgssymbol.h>
#include <qgssymbollayer.h>
#include <qgstextbuffersettings.h>
#include <qgsvectorfilewriter.h>
#include <qgsvectorlayer.h>
#include <qgsvectorlayerlabeling.h>
#include <qgsvectorlayerutils.h>
#include <qgswkbtypes.h>

LayerUtils::LayerUtils( QObject *parent )
  : QObject( parent )
{
}

void LayerUtils::setDefaultRenderer( QgsVectorLayer *layer, QgsProject *project, const QString &attachmentField, const QString &colorField )
{
  if ( !layer )
    return;

  bool hasSymbol = true;
  Qgis::SymbolType symbolType = Qgis::SymbolType::Marker;
  switch ( layer->geometryType() )
  {
    case Qgis::GeometryType::Point:
      symbolType = Qgis::SymbolType::Marker;
      break;
    case Qgis::GeometryType::Line:
      symbolType = Qgis::SymbolType::Line;
      break;
    case Qgis::GeometryType::Polygon:
      symbolType = Qgis::SymbolType::Fill;
      break;
    case Qgis::GeometryType::Unknown:
    case Qgis::GeometryType::Null:
    default:
      hasSymbol = false;
      break;
  }

  if ( !hasSymbol )
  {
    return;
  }

  QgsSymbol *symbol = project ? project->styleSettings()->defaultSymbol( symbolType ) : nullptr;
  if ( !symbol )
  {
    symbol = LayerUtils::defaultSymbol( layer, attachmentField, colorField );
  }

  QgsSingleSymbolRenderer *renderer = new QgsSingleSymbolRenderer( symbol );
  layer->setRenderer( renderer );
}

QgsSymbol *LayerUtils::defaultSymbol( QgsVectorLayer *layer, const QString &attachmentField, const QString &colorField )
{
  QgsSymbol *symbol = nullptr;

  if ( !layer )
  {
    return symbol;
  }

  QgsSymbolLayerList symbolLayers;
  switch ( layer->geometryType() )
  {
    case Qgis::GeometryType::Point:
    {
      if ( !attachmentField.isEmpty() )
      {
        QgsSymbolLayerList subSymbolLayers;
        QgsRasterMarkerSymbolLayer *rasterMarkerSymbolLayer = new QgsRasterMarkerSymbolLayer( QString(), 2.6, 0.0 );
        rasterMarkerSymbolLayer->setSize( 6.0 );
        rasterMarkerSymbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::Size, QgsProperty::fromExpression( QStringLiteral( "scale_linear( @map_scale, 1000, 5000, @value * 5.5, @value )" ), true ) );
        rasterMarkerSymbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::Name, QgsProperty::fromExpression( QStringLiteral( "with_variable('attachment', %1, if(@map_scale < 5000, @project_folder || '/' || @attachment, ''))" ).arg( attachmentField ), true ) );
        subSymbolLayers << rasterMarkerSymbolLayer;

        QgsCentroidFillSymbolLayer *centroidFillSymbolLayer = new QgsCentroidFillSymbolLayer();
        centroidFillSymbolLayer->setClipPoints( true );
        centroidFillSymbolLayer->setSubSymbol( new QgsMarkerSymbol( subSymbolLayers ) );
        subSymbolLayers.clear();
        subSymbolLayers << centroidFillSymbolLayer;

        QgsFilledMarkerSymbolLayer *fillSymbolLayer = new QgsFilledMarkerSymbolLayer( Qgis::MarkerShape::Circle, 2.6, 0.0 );
        fillSymbolLayer->setSize( 2.4 );
        if ( !colorField.isEmpty() )
        {
          fillSymbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::StrokeColor, QgsProperty::fromExpression( QStringLiteral( "if(\"%1\" is not null and \"%1\" != '', \"%1\", @value)" ).arg( colorField ), true ) );
        }
        fillSymbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::Size, QgsProperty::fromExpression( QStringLiteral( "with_variable('attachment', %1, if(@map_scale < 5000 and @attachment is not null and @attachment != '', scale_linear( @map_scale, 1000, 5000, @value * 5.5, @value ), @value))" ).arg( attachmentField ), true ) );
        fillSymbolLayer->setSubSymbol( new QgsFillSymbol( subSymbolLayers ) );
        symbolLayers << fillSymbolLayer;

        QgsSimpleMarkerSymbolLayer *symbolLayer = new QgsSimpleMarkerSymbolLayer( Qgis::MarkerShape::Circle, 2.6, 0.0, DEFAULT_SCALE_METHOD, QColor( 55, 126, 184, 100 ), QColor( 55, 126, 184 ) );
        symbolLayer->setSize( 2.4 );
        symbolLayer->setStrokeWidth( 0.6 );
        if ( !colorField.isEmpty() )
        {
          symbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::FillColor, QgsProperty::fromExpression( QStringLiteral( "with_variable('attachment', %1, if(@map_scale < 5000 and @attachment is not null and @attachment != '', '255,0,0,0', if(\"%2\" is not null and \"%2\" != '', set_color_part(\"%2\", 'alpha', 100), @value)))" ).arg( attachmentField, colorField ), true ) );
          symbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::StrokeColor, QgsProperty::fromExpression( QStringLiteral( "if(\"%1\" is not null and \"%1\" != '', \"%1\", @value)" ).arg( colorField ), true ) );
        }
        else
        {
          symbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::FillColor, QgsProperty::fromExpression( QStringLiteral( "with_variable('attachment', %1, if(@map_scale < 5000 and @attachment is not null and @attachment != '', '255,0,0,0', @value)))" ).arg( attachmentField ), true ) );
        }
        symbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::Size, QgsProperty::fromExpression( QStringLiteral( "with_variable('attachment', %1, if(@map_scale < 5000 and @attachment is not null and @attachment != '', scale_linear( @map_scale, 1000, 5000, @value * 5.5, @value ), @value))" ).arg( attachmentField ), true ) );
        symbolLayers << symbolLayer;
      }
      else
      {
        QgsSimpleMarkerSymbolLayer *symbolLayer = new QgsSimpleMarkerSymbolLayer( Qgis::MarkerShape::Circle, 2.6, 0.0, DEFAULT_SCALE_METHOD, QColor( 55, 126, 184, 100 ), QColor( 55, 126, 184 ) );
        symbolLayer->setStrokeWidth( 0.6 );
        if ( !colorField.isEmpty() )
        {
          symbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::FillColor, QgsProperty::fromExpression( QStringLiteral( "if(\"%1\" is not null and \"%1\" != '', set_color_part(\"%1\", 'alpha', 100), @value)" ).arg( colorField ), true ) );
        }
        symbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::StrokeColor, QgsProperty::fromExpression( QStringLiteral( "if(\"%1\" is not null and \"%1\" != '', \"%1\", @value)" ).arg( colorField ), true ) );
        symbolLayers << symbolLayer;
      }
      symbol = new QgsMarkerSymbol( symbolLayers );
      break;
    }

    case Qgis::GeometryType::Line:
    {
      QgsSimpleLineSymbolLayer *symbolLayer = new QgsSimpleLineSymbolLayer( QColor( 55, 126, 184 ), 0.6 ); // cppcheck-suppress constVariablePointer
      if ( !colorField.isEmpty() )
      {
        symbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::StrokeColor, QgsProperty::fromExpression( QStringLiteral( "if(\"%1\" is not null and \"%1\" != '', \"%1\", @value)" ).arg( colorField ), true ) );
      }
      symbolLayers << symbolLayer;
      symbol = new QgsLineSymbol( symbolLayers );
      break;
    }

    case Qgis::GeometryType::Polygon:
    {
      QgsSimpleFillSymbolLayer *symbolLayer = new QgsSimpleFillSymbolLayer( QColor( 55, 126, 184, 100 ), DEFAULT_SIMPLEFILL_STYLE, QColor( 55, 126, 184 ), DEFAULT_SIMPLEFILL_BORDERSTYLE, 0.6 ); // cppcheck-suppress constVariablePointer
      if ( !colorField.isEmpty() )
      {
        symbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::FillColor, QgsProperty::fromExpression( QStringLiteral( "if(\"%1\" is not null and \"%1\" != '', set_color_part(\"%1\", 'alpha', 100), @value)" ).arg( colorField ), true ) );
        symbolLayer->setDataDefinedProperty( QgsSymbolLayer::Property::StrokeColor, QgsProperty::fromExpression( QStringLiteral( "if(\"%1\" is not null and \"%1\" != '', \"%1\", @value)" ).arg( colorField ), true ) );
      }
      symbolLayers << symbolLayer;
      symbol = new QgsFillSymbol( symbolLayers );
      break;
    }

    case Qgis::GeometryType::Unknown:
    case Qgis::GeometryType::Null:
      break;
  }
  return symbol;
}

void LayerUtils::setDefaultLabeling( QgsVectorLayer *layer, QgsProject *project )
{
  QgsTextFormat textFormat = project ? project->styleSettings()->defaultTextFormat() : QgsTextFormat();
  textFormat.setSize( 8 );
  textFormat.setSizeUnit( Qgis::RenderUnit::Points );
  textFormat.buffer().setEnabled( true );
  textFormat.buffer().setSize( 0.5 );
  textFormat.buffer().setSizeUnit( Qgis::RenderUnit::Millimeters );
  textFormat.buffer().setColor( QColor( 255, 255, 255, 150 ) );
  QgsAbstractVectorLayerLabeling *labeling = LayerUtils::defaultLabeling( layer, textFormat );
  if ( labeling )
  {
    layer->setLabeling( labeling );
    layer->setLabelsEnabled( layer->geometryType() == Qgis::GeometryType::Point );
  }
}

QgsAbstractVectorLayerLabeling *LayerUtils::defaultLabeling( QgsVectorLayer *layer, QgsTextFormat textFormat )
{
  QgsAbstractVectorLayerLabeling *labeling = nullptr;

  if ( !layer )
  {
    return labeling;
  }

  bool foundFriendlyIdentifier = true;
  QString fieldName = QgsVectorLayerUtils::guessFriendlyIdentifierField( layer->fields(), &foundFriendlyIdentifier );
  if ( !foundFriendlyIdentifier )
  {
    return labeling;
  }

  QgsPalLayerSettings settings;
  settings.fieldName = fieldName;
  settings.obstacleSettings().setIsObstacle( true );
  switch ( layer->geometryType() )
  {
    case Qgis::GeometryType::Point:
    {
      settings.placement = Qgis::LabelPlacement::OrderedPositionsAroundPoint;
      settings.offsetType = Qgis::LabelOffsetType::FromSymbolBounds;
      break;
    }

    case Qgis::GeometryType::Line:
    {
      settings.placement = Qgis::LabelPlacement::Curved;
      break;
    }

    case Qgis::GeometryType::Polygon:
    {
      settings.placement = Qgis::LabelPlacement::AroundPoint;
      settings.obstacleSettings().setType( QgsLabelObstacleSettings::ObstacleType::PolygonBoundary );
      break;
    }

    case Qgis::GeometryType::Unknown:
    case Qgis::GeometryType::Null:
      break;
  }

  if ( !textFormat.isValid() )
  {
    textFormat.setSize( 9 );
    textFormat.setSizeUnit( Qgis::RenderUnit::Points );
    textFormat.setColor( QColor( 0, 0, 0 ) );

    QgsTextBufferSettings bufferSettings;
    bufferSettings.setEnabled( true );
    bufferSettings.setColor( QColor( 255, 255, 255 ) );
    bufferSettings.setSize( 1 );
    bufferSettings.setSizeUnit( Qgis::RenderUnit::Millimeters );
    textFormat.setBuffer( bufferSettings );
  }
  settings.setFormat( textFormat );

  labeling = new QgsVectorLayerSimpleLabeling( settings );

  return labeling;
}

QgsRasterLayer *LayerUtils::createOnlineElevationLayer()
{
  QgsRasterLayer *layer = new QgsRasterLayer( QStringLiteral( "interpretation=terrariumterrain&type=xyz&url=https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%7Bz%7D/%7Bx%7D/%7By%7D.png&zmax=15&zmin=0" ),
                                              QStringLiteral( "elevation" ), QStringLiteral( "wms" ) );
  QgsRasterLayerElevationProperties *elevationProperties = static_cast<QgsRasterLayerElevationProperties *>( layer->elevationProperties() );
  elevationProperties->setEnabled( true );
  elevationProperties->setProfileSymbology( Qgis::ProfileSurfaceSymbology::FillBelow );
  elevationProperties->profileFillSymbol()->setColor( QColor( 130, 130, 130 ) );
  return layer;
}

QgsMapLayer *LayerUtils::createBasemap( const QString &style )
{
  QgsRasterLayer *layer = nullptr;
  if ( style.compare( QStringLiteral( "lightgray" ) ) == 0 )
  {
    layer = new QgsRasterLayer( OPENSTREETMAP_URL, QStringLiteral( "OpenStreetMap" ), QLatin1String( "wms" ) );
    layer->hueSaturationFilter()->setGrayscaleMode( QgsHueSaturationFilter::GrayscaleLightness );
  }
  else if ( style.compare( QStringLiteral( "darkgray" ) ) == 0 )
  {
    layer = new QgsRasterLayer( OPENSTREETMAP_URL, QStringLiteral( "OpenStreetMap" ), QLatin1String( "wms" ) );
    layer->hueSaturationFilter()->setGrayscaleMode( QgsHueSaturationFilter::GrayscaleLightness );
    layer->hueSaturationFilter()->setInvertColors( true );
  }
  else
  {
    layer = new QgsRasterLayer( OPENSTREETMAP_URL, QStringLiteral( "OpenStreetMap" ), QLatin1String( "wms" ) );
  }
  return layer;
}

bool LayerUtils::isAtlasCoverageLayer( QgsVectorLayer *layer )
{
  if ( !layer || !QgsProject::instance()->layoutManager() )
    return false;

  const QList<QgsPrintLayout *> printLayouts = QgsProject::instance()->layoutManager()->printLayouts();
  for ( QgsPrintLayout *printLayout : printLayouts )
  {
    if ( printLayout->atlas() )
    {
      if ( printLayout->atlas()->coverageLayer() == layer )
        return true;
    }
  }

  return false;
}

bool LayerUtils::isFeatureAdditionLocked( QgsMapLayer *layer )
{
  return layer ? ( ( layer->customProperty( QStringLiteral( "QFieldSync/is_geometry_locked" ), false ).toBool() && !layer->customProperty( QStringLiteral( "QFieldSync/is_geometry_locked" ), false ).toBool() ) || ( layer->customProperty( QStringLiteral( "QFieldSync/is_feature_addition_locked" ), false ).toBool() && !layer->customProperty( QStringLiteral( "QFieldSync/is_feature_addition_locked" ), false ).toBool() ) ) : false;
}

void LayerUtils::selectFeaturesInLayer( QgsVectorLayer *layer, const QList<int> &fids, Qgis::SelectBehavior behavior )
{
  if ( !layer )
    return;

  QgsFeatureIds qgsFids;
  for ( const int &fid : fids )
    qgsFids << fid;
  layer->selectByIds( qgsFids, behavior );
}

QString LayerUtils::fieldType( const QgsField &field )
{
  return QVariant( QMetaType( field.type() ) ).typeName();
}

bool LayerUtils::addFeature( QgsVectorLayer *layer, QgsFeature feature )
{
  if ( layer )
  {
    return layer->addFeature( feature );
  }
  return false;
}

bool LayerUtils::deleteFeature( QgsProject *project, QgsVectorLayer *layer, const QgsFeatureId fid, bool flushBuffer )
{
  if ( !project )
  {
    return false;
  }

  if ( !layer )
  {
    QgsMessageLog::logMessage( tr( "Cannot start editing, no layer" ), "QField", Qgis::Warning );
    return false;
  }

  const bool wasEditing = layer->editBuffer();
  if ( !wasEditing && !layer->startEditing() )
  {
    QgsMessageLog::logMessage( tr( "Cannot start editing" ), "QField", Qgis::Warning );
    return false;
  }
  flushBuffer = flushBuffer || !wasEditing;

  bool isSuccess = true;

  // delete parent and related features
  QgsVectorLayer::DeleteContext deleteContext( true, project );
  if ( layer->deleteFeature( fid, &deleteContext ) )
  {
    if ( flushBuffer )
    {
      // commit changes
      if ( !layer->commitChanges( !wasEditing ) )
      {
        const QString msgs = layer->commitErrors().join( QStringLiteral( "\n" ) );
        QgsMessageLog::logMessage( tr( "Cannot commit deletion of feature %2 in layer \"%1\". Reason:\n%3" ).arg( layer->name() ).arg( fid ).arg( msgs ), QStringLiteral( "QField" ), Qgis::Warning );
        isSuccess = false;
      }
    }

    if ( isSuccess )
    {
      // loop and commit referenced layers in reverse
      QList<QgsVectorLayer *> constHandledLayers = deleteContext.handledLayers();

      for ( QList<QgsVectorLayer *>::reverse_iterator it = constHandledLayers.rbegin(); it != constHandledLayers.rend(); ++it )
      {
        QgsVectorLayer *vl = *it;

        if ( vl == layer )
        {
          continue;
        }

        if ( !vl->commitChanges() )
        {
          const QString msgs = vl->commitErrors().join( QStringLiteral( "\n" ) );
          QgsMessageLog::logMessage( tr( "Cannot commit deletion in layer \"%1\". Reason:\n%3" ).arg( vl->name() ).arg( msgs ), QStringLiteral( "QField" ), Qgis::Warning );
          isSuccess = false;
          break;
        }
      }
    }
  }
  else
  {
    QgsMessageLog::logMessage( tr( "Cannot delete feature %1" ).arg( fid ), "QField", Qgis::Warning );
    isSuccess = false;
  }

  if ( !flushBuffer && !isSuccess )
  {
    const QList<QgsVectorLayer *> constHandledLayers = deleteContext.handledLayers();
    for ( QgsVectorLayer *vl : constHandledLayers )
      if ( vl != layer )
      {
        if ( !vl->rollBack() )
        {
          QgsMessageLog::logMessage( tr( "Cannot rollback layer changes in layer %1" ).arg( vl->name() ), "QField", Qgis::Critical );
        }
      }

    if ( !layer->rollBack() )
    {
      QgsMessageLog::logMessage( tr( "Cannot rollback layer changes in layer %1" ).arg( layer->name() ), "QField", Qgis::Critical );
    }
  }

  return isSuccess;
}

QgsFeature LayerUtils::duplicateFeature( QgsVectorLayer *layer, QgsFeature feature )
{
  if ( !layer )
  {
    QgsMessageLog::logMessage( tr( "Cannot start editing, no layer" ), "QField", Qgis::Warning );
    return QgsFeature();
  }

  if ( !feature.isValid() )
  {
    QgsMessageLog::logMessage( tr( "Cannot copy invalid feature" ), "QField", Qgis::Warning );
    return QgsFeature();
  }

  const bool wasEditing = layer->editBuffer();
  if ( !wasEditing && !layer->startEditing() )
  {
    QgsMessageLog::logMessage( tr( "Cannot start editing" ), "QField", Qgis::Warning );
    return QgsFeature();
  }

  // When duplicating a feature, insure the source primary ID is correctly set to null (i.e. new feature within the source dataset)
  QString sourcePrimaryKeys = layer->customProperty( QStringLiteral( "QFieldSync/sourceDataPrimaryKeys" ) ).toString();
  if ( layer->fields().lookupField( sourcePrimaryKeys ) >= 0 )
  {
    const int sourcePrimaryKeysIndex = layer->fields().lookupField( sourcePrimaryKeys );
    if ( !layer->fields().at( sourcePrimaryKeysIndex ).defaultValueDefinition().isValid() )
    {
      feature.setAttribute( sourcePrimaryKeysIndex, QVariant() );
    }
  }

  QgsFeature duplicatedFeature;
  QMetaObject::Connection connection = connect( layer, &QgsVectorLayer::featureAdded, [layer, &duplicatedFeature]( QgsFeatureId fid ) {
    duplicatedFeature = layer->getFeature( fid );
  } );
  auto sweaper = qScopeGuard( [layer, connection] { layer->disconnect( connection ); } );

  QgsVectorLayerUtils::QgsDuplicateFeatureContext duplicateFeatureContext;
  duplicatedFeature = QgsVectorLayerUtils::duplicateFeature( layer, feature, QgsProject::instance(), duplicateFeatureContext );
  const auto duplicateFeatureContextLayers = duplicateFeatureContext.layers();

  // commit changes
  if ( !layer->commitChanges( !wasEditing ) )
  {
    const QString msgs = layer->commitErrors().join( QStringLiteral( "\n" ) );
    QgsMessageLog::logMessage( tr( "Cannot add new feature in layer \"%1\". Reason:\n%2" ).arg( layer->name(), msgs ), "QField", Qgis::Warning );

    for ( QgsVectorLayer *chl : duplicateFeatureContextLayers )
    {
      chl->rollBack();
    }

    return QgsFeature();
  }

  // we have to re-apply referenced feature attribute value to take into account value changes form the
  // data provider (e.g. autogenerated fid)
  const QList<QgsRelation> relations = QgsProject::instance()->relationManager()->referencedRelations( layer );
  for ( QgsVectorLayer *chl : duplicateFeatureContextLayers )
  {
    const QgsFeatureIds fids = duplicateFeatureContext.duplicatedFeatures( chl );
    for ( const auto &relation : relations )
    {
      if ( relation.referencingLayer() == chl )
      {
        const QList<QgsRelation::FieldPair> fieldPairs = relation.fieldPairs();
        for ( const auto &fieldPair : fieldPairs )
        {
          for ( auto fid : fids )
          {
            chl->changeAttributeValue( fid, chl->fields().indexOf( fieldPair.referencingField() ), duplicatedFeature.attribute( fieldPair.referencedField() ) );
          }
        }
      }
    }

    // Insure the source primary ID of a duplicated child feature is correctly set to null (i.e. new feature within the source dataset)
    sourcePrimaryKeys = chl->customProperty( QStringLiteral( "QFieldSync/sourceDataPrimaryKeys" ) ).toString();
    if ( !sourcePrimaryKeys.isEmpty() && chl->fields().lookupField( sourcePrimaryKeys ) >= 0 )
    {
      const int sourcePrimaryKeysIndex = chl->fields().lookupField( sourcePrimaryKeys );
      if ( !chl->fields().at( sourcePrimaryKeysIndex ).defaultValueDefinition().isValid() )
      {
        for ( auto fid : fids )
        {
          chl->changeAttributeValue( fid, sourcePrimaryKeysIndex, QVariant() );
        }
      }
    }

    chl->commitChanges();
  }

  return duplicatedFeature;
}

bool LayerUtils::hasMValue( QgsVectorLayer *layer )
{
  if ( !layer )
    return false;

  return QgsWkbTypes::hasM( layer->wkbType() );
}

QString LayerUtils::guessFriendlyHeightField( QgsVectorLayer *layer )
{
  if ( !layer )
  {
    return QString();
  }

  const QgsFields fields = layer->fields();
  if ( fields.isEmpty() )
  {
    return QString();
  }

  static const QStringList sCandidates {
    QStringLiteral( "extrusion" ),
    QStringLiteral( "height" ),
    QStringLiteral( "hauteur" ), // French (height)
    QStringLiteral( "hohe" ),    // German (height)
  };

  for ( const QString &candidate : sCandidates )
  {
    for ( const QgsField &field : fields )
    {
      if ( !field.isNumeric() )
      {
        continue;
      }

      const QString fieldName = field.name();
      if ( QgsStringUtils::unaccent( fieldName ).contains( candidate, Qt::CaseInsensitive ) )
      {
        return fieldName;
      }
    }
  }

  return QString();
}

QSet<QVariant> LayerUtils::uniqueValuesForVectorLayerFieldIndex( QgsVectorLayer *layer, int fieldIndex )
{
  if ( !layer )
  {
    return QSet<QVariant>();
  }

  return layer->uniqueValues( fieldIndex );
}

QgsVectorLayer *LayerUtils::loadVectorLayer( const QString &uri, const QString &name, const QString &provider )
{
  QgsVectorLayer *layer = new QgsVectorLayer( uri, name, provider );
  QQmlEngine::setObjectOwnership( layer, QQmlEngine::CppOwnership );
  return layer;
}

QgsRasterLayer *LayerUtils::loadRasterLayer( const QString &uri, const QString &name, const QString &provider )
{
  QgsRasterLayer *layer = new QgsRasterLayer( uri, name, provider );
  QQmlEngine::setObjectOwnership( layer, QQmlEngine::CppOwnership );
  return layer;
}

QgsVectorLayer *LayerUtils::memoryLayerFromJsonString( const QString &name, const QString &string, const QgsCoordinateReferenceSystem &crs )
{
  const QgsFields fields = QgsJsonUtils::stringToFields( string );
  QgsFeatureList features = QgsJsonUtils::stringToFeatureList( string, fields );
  if ( features.isEmpty() )
  {
    return nullptr;
  }

  QgsVectorLayer *layer = LayerUtils::createMemoryLayer( name, fields, features[0].geometry().wkbType(), crs );
  if ( QgsVectorDataProvider *dataProvider = layer->dataProvider() )
  {
    dataProvider->addFeatures( features );
  }
  return layer;
}

QgsVectorLayer *LayerUtils::createMemoryLayer( const QString &name, const QgsFields &fields, Qgis::WkbType geometryType, const QgsCoordinateReferenceSystem &crs )
{
  QgsVectorLayer *layer = QgsMemoryProviderUtils::createMemoryLayer( name, fields, geometryType, crs );
  QQmlEngine::setObjectOwnership( layer, QQmlEngine::CppOwnership );
  LayerUtils::setDefaultRenderer( layer );
  return layer;
}

FeatureIterator LayerUtils::createFeatureIterator( QgsVectorLayer *layer )
{
  return FeatureIterator( layer );
}

FeatureIterator LayerUtils::createFeatureIteratorFromExpression( QgsVectorLayer *layer, const QString &expression )
{
  QgsFeatureRequest request = QgsFeatureRequest( QgsExpression( expression ) );
  if ( layer )
  {
    request.setExpressionContext( layer->createExpressionContext() );
  }
  return FeatureIterator( layer, request );
}

FeatureIterator LayerUtils::createFeatureIteratorFromRectangle( QgsVectorLayer *layer, const QgsRectangle &rectangle )
{
  const QgsFeatureRequest request = QgsFeatureRequest( rectangle );
  return FeatureIterator( layer, request );
}

QString LayerUtils::saveVectorLayerAs( QgsVectorLayer *layer, const QString &filePath, const QString &driverName, const QString &filterExpression )
{
  if ( !layer || filePath.isEmpty() )
  {
    return QString();
  }

  QFileInfo fileInfo( filePath );
  const QString finalDriverName = driverName.isEmpty() ? QgsVectorFileWriter::driverForExtension( fileInfo.suffix() ) : driverName;
  if ( finalDriverName.isEmpty() )
  {
    return QString();
  }
  QDir dir;
  if ( !dir.mkpath( fileInfo.absolutePath() ) )
  {
    return QString();
  }

  QStringList datasetOptions = QgsVectorFileWriter::defaultDatasetOptions( finalDriverName );
  if ( finalDriverName == QStringLiteral( "GPX" ) )
  {
    datasetOptions.removeAll( QStringLiteral( "GPX_USE_EXTENSIONS=NO" ) );
    datasetOptions << QStringLiteral( "GPX_USE_EXTENSIONS=YES" );
  }

  QString finalFileName;
  QString finalLayerName;
  QgsVectorFileWriter::SaveVectorOptions saveOptions;
  saveOptions.fileEncoding = QStringLiteral( "UTF8" );
  saveOptions.layerName = fileInfo.completeBaseName();
  saveOptions.driverName = finalDriverName;
  saveOptions.datasourceOptions = datasetOptions;
  saveOptions.layerOptions = QgsVectorFileWriter::defaultLayerOptions( finalDriverName );
  saveOptions.symbologyExport = Qgis::FeatureSymbologyExport::NoSymbology;
  saveOptions.actionOnExistingFile = QgsVectorFileWriter::CreateOrOverwriteFile;

  std::unique_ptr<QgsVectorFileWriter> writer( QgsVectorFileWriter::create( filePath, layer->fields(), layer->wkbType(), layer->crs(), QgsProject::instance()->transformContext(), saveOptions, QgsFeatureSink::RegeneratePrimaryKey, &finalFileName, &finalLayerName ) );
  if ( writer->hasError() )
  {
    qInfo() << QStringLiteral( "Vector layer file writer error: %1" ).arg( writer->errorMessage() );
    return QString();
  }

  QgsFeatureRequest request;
  if ( !filterExpression.isEmpty() )
  {
    request.setFilterExpression( filterExpression );
    request.setExpressionContext( layer->createExpressionContext() );
  }

  QgsFeatureIterator it = layer->getFeatures( request );
  QgsFeature feature;
  while ( it.nextFeature( feature ) )
  {
    writer->addFeature( feature, QgsFeatureSink::FastInsert );
  }

  return finalFileName;
}

static QgsSymbol *singleSymbolOf( QgsVectorLayer *layer )
{
  if ( !layer )
    return nullptr;
  QgsSingleSymbolRenderer *renderer = dynamic_cast<QgsSingleSymbolRenderer *>( layer->renderer() );
  return renderer ? renderer->symbol() : nullptr;
}

bool LayerUtils::hasSimpleSymbology( QgsVectorLayer *layer )
{
  return singleSymbolOf( layer ) != nullptr;
}

QColor LayerUtils::symbolColor( QgsVectorLayer *layer )
{
  QgsSymbol *symbol = singleSymbolOf( layer );
  return symbol ? symbol->color() : QColor();
}

void LayerUtils::setSymbolColor( QgsVectorLayer *layer, const QColor &color )
{
  QgsSymbol *symbol = singleSymbolOf( layer );
  if ( !symbol || !color.isValid() )
    return;

  symbol->setColor( color );
  layer->triggerRepaint();
  emit layer->styleChanged();
}

double LayerUtils::symbolSize( QgsVectorLayer *layer )
{
  QgsSymbol *symbol = singleSymbolOf( layer );
  if ( !symbol )
    return -1;

  switch ( symbol->type() )
  {
    case Qgis::SymbolType::Marker:
      return static_cast<QgsMarkerSymbol *>( symbol )->size();
    case Qgis::SymbolType::Line:
      return static_cast<QgsLineSymbol *>( symbol )->width();
    default:
      return -1;
  }
}

void LayerUtils::setSymbolSize( QgsVectorLayer *layer, double size )
{
  QgsSymbol *symbol = singleSymbolOf( layer );
  if ( !symbol || size <= 0 )
    return;

  switch ( symbol->type() )
  {
    case Qgis::SymbolType::Marker:
      static_cast<QgsMarkerSymbol *>( symbol )->setSize( size );
      break;
    case Qgis::SymbolType::Line:
      static_cast<QgsLineSymbol *>( symbol )->setWidth( size );
      break;
    default:
      return;
  }

  layer->triggerRepaint();
  emit layer->styleChanged();
}

static QgsSymbolLayer *firstSymbolLayerOf( QgsVectorLayer *layer )
{
  QgsSymbol *symbol = singleSymbolOf( layer );
  return ( symbol && symbol->symbolLayerCount() > 0 ) ? symbol->symbolLayer( 0 ) : nullptr;
}

static void refreshLayer( QgsVectorLayer *layer )
{
  layer->triggerRepaint();
  emit layer->styleChanged();
}

int LayerUtils::symbolType( QgsVectorLayer *layer )
{
  QgsSymbol *symbol = singleSymbolOf( layer );
  if ( !symbol )
    return -1;

  switch ( symbol->type() )
  {
    case Qgis::SymbolType::Marker:
      return 0;
    case Qgis::SymbolType::Line:
      return 1;
    case Qgis::SymbolType::Fill:
      return 2;
    default:
      return -1;
  }
}

QColor LayerUtils::fillColor( QgsVectorLayer *layer )
{
  QgsSymbolLayer *sl = firstSymbolLayerOf( layer );
  return sl ? sl->fillColor() : QColor();
}

void LayerUtils::setFillColor( QgsVectorLayer *layer, const QColor &color )
{
  QgsSymbolLayer *sl = firstSymbolLayerOf( layer );
  if ( !sl || !color.isValid() )
    return;

  sl->setFillColor( color );
  refreshLayer( layer );
}

QColor LayerUtils::strokeColor( QgsVectorLayer *layer )
{
  QgsSymbolLayer *sl = firstSymbolLayerOf( layer );
  return sl ? sl->strokeColor() : QColor();
}

void LayerUtils::setStrokeColor( QgsVectorLayer *layer, const QColor &color )
{
  QgsSymbolLayer *sl = firstSymbolLayerOf( layer );
  if ( !sl || !color.isValid() )
    return;

  sl->setStrokeColor( color );
  refreshLayer( layer );
}

double LayerUtils::strokeWidth( QgsVectorLayer *layer )
{
  QgsSymbolLayer *sl = firstSymbolLayerOf( layer );
  if ( !sl )
    return -1;

  if ( QgsSimpleFillSymbolLayer *fill = dynamic_cast<QgsSimpleFillSymbolLayer *>( sl ) )
    return fill->strokeWidth();
  if ( QgsSimpleLineSymbolLayer *line = dynamic_cast<QgsSimpleLineSymbolLayer *>( sl ) )
    return line->width();
  if ( QgsSimpleMarkerSymbolLayer *marker = dynamic_cast<QgsSimpleMarkerSymbolLayer *>( sl ) )
    return marker->strokeWidth();

  return -1;
}

void LayerUtils::setStrokeWidth( QgsVectorLayer *layer, double width )
{
  QgsSymbolLayer *sl = firstSymbolLayerOf( layer );
  if ( !sl || width < 0 )
    return;

  if ( QgsSimpleFillSymbolLayer *fill = dynamic_cast<QgsSimpleFillSymbolLayer *>( sl ) )
    fill->setStrokeWidth( width );
  else if ( QgsSimpleLineSymbolLayer *line = dynamic_cast<QgsSimpleLineSymbolLayer *>( sl ) )
    line->setWidth( width );
  else if ( QgsSimpleMarkerSymbolLayer *marker = dynamic_cast<QgsSimpleMarkerSymbolLayer *>( sl ) )
    marker->setStrokeWidth( width );
  else
    return;

  refreshLayer( layer );
}

int LayerUtils::strokeStyle( QgsVectorLayer *layer )
{
  QgsSymbolLayer *sl = firstSymbolLayerOf( layer );
  if ( !sl )
    return -1;

  if ( QgsSimpleFillSymbolLayer *fill = dynamic_cast<QgsSimpleFillSymbolLayer *>( sl ) )
    return static_cast<int>( fill->strokeStyle() );
  if ( QgsSimpleLineSymbolLayer *line = dynamic_cast<QgsSimpleLineSymbolLayer *>( sl ) )
    return static_cast<int>( line->penStyle() );
  if ( QgsSimpleMarkerSymbolLayer *marker = dynamic_cast<QgsSimpleMarkerSymbolLayer *>( sl ) )
    return static_cast<int>( marker->strokeStyle() );

  return -1;
}

void LayerUtils::setStrokeStyle( QgsVectorLayer *layer, int style )
{
  QgsSymbolLayer *sl = firstSymbolLayerOf( layer );
  if ( !sl )
    return;

  const Qt::PenStyle penStyle = static_cast<Qt::PenStyle>( style );

  if ( QgsSimpleFillSymbolLayer *fill = dynamic_cast<QgsSimpleFillSymbolLayer *>( sl ) )
    fill->setStrokeStyle( penStyle );
  else if ( QgsSimpleLineSymbolLayer *line = dynamic_cast<QgsSimpleLineSymbolLayer *>( sl ) )
    line->setPenStyle( penStyle );
  else if ( QgsSimpleMarkerSymbolLayer *marker = dynamic_cast<QgsSimpleMarkerSymbolLayer *>( sl ) )
    marker->setStrokeStyle( penStyle );
  else
    return;

  refreshLayer( layer );
}

int LayerUtils::markerShape( QgsVectorLayer *layer )
{
  QgsSimpleMarkerSymbolLayer *marker = dynamic_cast<QgsSimpleMarkerSymbolLayer *>( firstSymbolLayerOf( layer ) );
  return marker ? static_cast<int>( marker->shape() ) : -1;
}

void LayerUtils::setMarkerShape( QgsVectorLayer *layer, int shape )
{
  QgsSimpleMarkerSymbolLayer *marker = dynamic_cast<QgsSimpleMarkerSymbolLayer *>( firstSymbolLayerOf( layer ) );
  if ( !marker )
    return;

  marker->setShape( static_cast<Qgis::MarkerShape>( shape ) );
  refreshLayer( layer );
}

QString LayerUtils::exportVectorLayer( QgsVectorLayer *layer, const QString &filePath, const QString &destinationCrsAuthId, const QString &fileEncoding )
{
  if ( !layer || !layer->isValid() )
    return QString();

  const QFileInfo fileInfo( filePath );
  const QString driverName = QgsVectorFileWriter::driverForExtension( fileInfo.suffix() );
  if ( driverName.isEmpty() )
    return QString();

  QgsCoordinateReferenceSystem destinationCrs = layer->crs();
  if ( !destinationCrsAuthId.isEmpty() )
  {
    const QgsCoordinateReferenceSystem requested( destinationCrsAuthId );
    if ( requested.isValid() )
      destinationCrs = requested;
  }

  QgsVectorFileWriter::SaveVectorOptions saveOptions;
  saveOptions.fileEncoding = fileEncoding.isEmpty() ? QStringLiteral( "UTF-8" ) : fileEncoding;
  saveOptions.layerName = fileInfo.completeBaseName();
  saveOptions.driverName = driverName;
  saveOptions.datasourceOptions = QgsVectorFileWriter::defaultDatasetOptions( driverName );
  saveOptions.layerOptions = QgsVectorFileWriter::defaultLayerOptions( driverName );
  saveOptions.symbologyExport = Qgis::FeatureSymbologyExport::NoSymbology;
  saveOptions.actionOnExistingFile = QgsVectorFileWriter::CreateOrOverwriteFile;

  QString finalFileName;
  QString finalLayerName;
  std::unique_ptr<QgsVectorFileWriter> writer( QgsVectorFileWriter::create( filePath, layer->fields(), layer->wkbType(), destinationCrs, QgsProject::instance()->transformContext(), saveOptions, QgsFeatureSink::RegeneratePrimaryKey, &finalFileName, &finalLayerName ) );

  if ( !writer || writer->hasError() )
  {
    qInfo() << QStringLiteral( "Vector layer export error: %1" ).arg( writer ? writer->errorMessage() : QStringLiteral( "writer creation failed" ) );
    return QString();
  }

  const bool needsTransform = destinationCrs != layer->crs();
  QgsCoordinateTransform transform;
  if ( needsTransform )
  {
    transform = QgsCoordinateTransform( layer->crs(), destinationCrs, QgsProject::instance()->transformContext() );
    qInfo() << QStringLiteral( "Export: %1 -> %2, transform valid: %3" ).arg( layer->crs().authid(), destinationCrs.authid() ).arg( transform.isValid() );
  }

  QgsFeatureIterator it = layer->getFeatures();
  QgsFeature feature;
  while ( it.nextFeature( feature ) )
  {
    if ( needsTransform && feature.hasGeometry() )
    {
      QgsGeometry geometry = feature.geometry();
      if ( geometry.transform( transform ) == Qgis::GeometryOperationResult::Success )
        feature.setGeometry( geometry );
      else
        qInfo() << QStringLiteral( "Export: geometry transform failed for feature %1" ).arg( feature.id() );
    }
    writer->addFeature( feature, QgsFeatureSink::FastInsert );
  }

  return finalFileName;
}

QVariantList LayerUtils::vectorSubLayers( const QString &filePath )
{
  QVariantList result;

  QgsVectorLayer probe( filePath, QString(), QStringLiteral( "ogr" ) );
  if ( !probe.isValid() && probe.dataProvider() == nullptr )
    return result;

  const QList<QgsProviderSublayerDetails> details = QgsProviderRegistry::instance()->querySublayers( filePath, Qgis::SublayerQueryFlag::ResolveGeometryType );

  for ( const QgsProviderSublayerDetails &detail : details )
  {
    if ( detail.type() != Qgis::LayerType::Vector )
      continue;

    QVariantMap entry;
    entry.insert( QStringLiteral( "name" ), detail.name() );
    entry.insert( QStringLiteral( "geometry" ), QgsWkbTypes::displayString( detail.wkbType() ) );
    entry.insert( QStringLiteral( "featureCount" ), static_cast<qlonglong>( detail.featureCount() ) );
    entry.insert( QStringLiteral( "uri" ), detail.uri() );
    entry.insert( QStringLiteral( "provider" ), detail.providerKey() );
    result.append( entry );
  }

  return result;
}

bool LayerUtils::hasCategorizedSymbology( QgsVectorLayer *layer )
{
  if ( !layer )
    return false;

  return dynamic_cast<QgsCategorizedSymbolRenderer *>( layer->renderer() ) != nullptr
         || dynamic_cast<QgsGraduatedSymbolRenderer *>( layer->renderer() ) != nullptr;
}

QVariantList LayerUtils::rendererCategories( QgsVectorLayer *layer )
{
  QVariantList result;
  if ( !layer )
    return result;

  if ( QgsCategorizedSymbolRenderer *renderer = dynamic_cast<QgsCategorizedSymbolRenderer *>( layer->renderer() ) )
  {
    const QgsCategoryList categories = renderer->categories();
    int i = 0;
    for ( const QgsRendererCategory &category : categories )
    {
      QVariantMap entry;
      entry.insert( QStringLiteral( "index" ), i );
      entry.insert( QStringLiteral( "label" ), category.label().isEmpty() ? category.value().toString() : category.label() );
      entry.insert( QStringLiteral( "color" ), category.symbol() ? category.symbol()->color() : QColor() );
      entry.insert( QStringLiteral( "visible" ), category.renderState() );
      result.append( entry );
      ++i;
    }
    return result;
  }

  if ( QgsGraduatedSymbolRenderer *renderer = dynamic_cast<QgsGraduatedSymbolRenderer *>( layer->renderer() ) )
  {
    const QgsRangeList ranges = renderer->ranges();
    int i = 0;
    for ( const QgsRendererRange &range : ranges )
    {
      QVariantMap entry;
      entry.insert( QStringLiteral( "index" ), i );
      entry.insert( QStringLiteral( "label" ), range.label() );
      entry.insert( QStringLiteral( "color" ), range.symbol() ? range.symbol()->color() : QColor() );
      entry.insert( QStringLiteral( "visible" ), range.renderState() );
      result.append( entry );
      ++i;
    }
  }

  return result;
}

void LayerUtils::setCategoryColor( QgsVectorLayer *layer, int categoryIndex, const QColor &color )
{
  if ( !layer || !color.isValid() || categoryIndex < 0 )
    return;

  if ( QgsCategorizedSymbolRenderer *renderer = dynamic_cast<QgsCategorizedSymbolRenderer *>( layer->renderer() ) )
  {
    if ( categoryIndex >= renderer->categories().size() )
      return;

    std::unique_ptr<QgsSymbol> symbol( renderer->categories().at( categoryIndex ).symbol()->clone() );
    symbol->setColor( color );
    renderer->updateCategorySymbol( categoryIndex, symbol.release() );
  }
  else if ( QgsGraduatedSymbolRenderer *renderer = dynamic_cast<QgsGraduatedSymbolRenderer *>( layer->renderer() ) )
  {
    if ( categoryIndex >= renderer->ranges().size() )
      return;

    std::unique_ptr<QgsSymbol> symbol( renderer->ranges().at( categoryIndex ).symbol()->clone() );
    symbol->setColor( color );
    renderer->updateRangeSymbol( categoryIndex, symbol.release() );
  }
  else
  {
    return;
  }

  layer->triggerRepaint();
  emit layer->styleChanged();
}

void LayerUtils::setCategoryVisible( QgsVectorLayer *layer, int categoryIndex, bool visible )
{
  if ( !layer || categoryIndex < 0 )
    return;

  if ( QgsCategorizedSymbolRenderer *renderer = dynamic_cast<QgsCategorizedSymbolRenderer *>( layer->renderer() ) )
  {
    if ( categoryIndex >= renderer->categories().size() )
      return;
    renderer->updateCategoryRenderState( categoryIndex, visible );
  }
  else if ( QgsGraduatedSymbolRenderer *renderer = dynamic_cast<QgsGraduatedSymbolRenderer *>( layer->renderer() ) )
  {
    if ( categoryIndex >= renderer->ranges().size() )
      return;
    renderer->updateRangeRenderState( categoryIndex, visible );
  }
  else
  {
    return;
  }

  layer->triggerRepaint();
  emit layer->styleChanged();
}

static QgsColorRamp *rampByName( const QString &rampName )
{
  QgsStyle *style = QgsStyle::defaultStyle();
  if ( style && style->colorRampNames().contains( rampName ) )
    return style->colorRamp( rampName );

  if ( style && !style->colorRampNames().isEmpty() )
    return style->colorRamp( style->colorRampNames().first() );

  return nullptr;
}

QVariantList LayerUtils::layerFields( QgsVectorLayer *layer )
{
  QVariantList result;
  if ( !layer )
    return result;

  const QgsFields fields = layer->fields();
  for ( const QgsField &field : fields )
  {
    QVariantMap entry;
    entry.insert( QStringLiteral( "name" ), field.name() );
    entry.insert( QStringLiteral( "type" ), field.typeName() );
    entry.insert( QStringLiteral( "numeric" ), field.isNumeric() );
    result.append( entry );
  }

  return result;
}

void LayerUtils::setSingleSymbolRenderer( QgsVectorLayer *layer )
{
  if ( !layer )
    return;

  std::unique_ptr<QgsSymbol> symbol( QgsSymbol::defaultSymbol( layer->geometryType() ) );
  if ( !symbol )
    return;

  layer->setRenderer( new QgsSingleSymbolRenderer( symbol.release() ) );
  layer->triggerRepaint();
  emit layer->styleChanged();
}

bool LayerUtils::setCategorizedRenderer( QgsVectorLayer *layer, const QString &fieldName, const QString &rampName )
{
  if ( !layer || fieldName.isEmpty() )
    return false;

  const int fieldIndex = layer->fields().lookupField( fieldName );
  if ( fieldIndex < 0 )
    return false;

  const QSet<QVariant> uniqueValues = layer->uniqueValues( fieldIndex, 200 );
  if ( uniqueValues.isEmpty() )
    return false;

  QList<QVariant> sortedValues = uniqueValues.values();
  std::sort( sortedValues.begin(), sortedValues.end(), []( const QVariant &a, const QVariant &b ) {
    return a.toString().localeAwareCompare( b.toString() ) < 0;
  } );

  std::unique_ptr<QgsColorRamp> ramp( rampByName( rampName ) );

  QgsCategoryList categories;
  const int count = sortedValues.size();
  int i = 0;
  for ( const QVariant &value : std::as_const( sortedValues ) )
  {
    std::unique_ptr<QgsSymbol> symbol( QgsSymbol::defaultSymbol( layer->geometryType() ) );
    if ( !symbol )
      continue;

    if ( ramp )
      symbol->setColor( ramp->color( count > 1 ? static_cast<double>( i ) / ( count - 1 ) : 0.0 ) );

    categories.append( QgsRendererCategory( value, symbol.release(), value.toString() ) );
    ++i;
  }

  if ( categories.isEmpty() )
    return false;

  layer->setRenderer( new QgsCategorizedSymbolRenderer( fieldName, categories ) );
  layer->triggerRepaint();
  emit layer->styleChanged();
  return true;
}

bool LayerUtils::setGraduatedRenderer( QgsVectorLayer *layer, const QString &fieldName, int classCount, const QString &rampName )
{
  if ( !layer || fieldName.isEmpty() || classCount < 2 )
    return false;

  const int fieldIndex = layer->fields().lookupField( fieldName );
  if ( fieldIndex < 0 || !layer->fields().at( fieldIndex ).isNumeric() )
    return false;

  std::unique_ptr<QgsGraduatedSymbolRenderer> renderer( new QgsGraduatedSymbolRenderer( fieldName ) );

  std::unique_ptr<QgsSymbol> symbol( QgsSymbol::defaultSymbol( layer->geometryType() ) );
  if ( !symbol )
    return false;
  renderer->setSourceSymbol( symbol.release() );

  std::unique_ptr<QgsColorRamp> ramp( rampByName( rampName ) );
  if ( ramp )
    renderer->setSourceColorRamp( ramp.release() );

  renderer->setClassificationMethod( new QgsClassificationQuantile() );
  QString classificationError;
  renderer->updateClasses( layer, classCount, classificationError );
  if ( !classificationError.isEmpty() )
    qInfo() << QStringLiteral( "Graduated renderer: %1" ).arg( classificationError );

  if ( renderer->ranges().isEmpty() )
    return false;

  layer->setRenderer( renderer.release() );
  layer->triggerRepaint();
  emit layer->styleChanged();
  return true;
}

