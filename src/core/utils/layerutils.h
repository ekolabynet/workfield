/***************************************************************************
  layerutils.h - LayerUtils

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

#ifndef LAYERUTILS_H
#define LAYERUTILS_H

#include <QColor>
#include <QObject>
#include <qgis.h>
#include <qgstextformat.h>
#include <qgsvectorlayer.h>

class FeatureModel;
class QgsVectorLayer;
class QgsRasterLayer;
class QgsSymbol;

#define OPENSTREETMAP_URL QStringLiteral( "type=xyz&tilePixelRatio=1&url=https://tile.openstreetmap.org/%7Bz%7D/%7Bx%7D/%7By%7D.png&zmax=19&zmin=0&crs=EPSG3857" )

/**
 * A class providing a feature iterator interface to be used within QML/javascript environment.
 *
 * Users of this class must manually call its close() once feature iteration is finished.
 *
 * \ingroup core
 */
class FeatureIterator
{
    Q_GADGET

  public:
    FeatureIterator( QgsVectorLayer *layer = nullptr, const QgsFeatureRequest &request = QgsFeatureRequest() )
    {
      if ( layer )
      {
        mFeatureIterator = layer->getFeatures( request );
      }
    }

    Q_INVOKABLE bool hasNext()
    {
      if ( !mHasNextChecked )
      {
        mHasNext = mFeatureIterator.nextFeature( mCurrentFeature );
        mHasNextChecked = true;
      }
      return mHasNext;
    }

    Q_INVOKABLE QgsFeature next()
    {
      if ( !mHasNextChecked )
      {
        mFeatureIterator.nextFeature( mCurrentFeature );
      }
      else
      {
        mHasNextChecked = false;
      }
      return mCurrentFeature;
    }

    Q_INVOKABLE void close()
    {
      mFeatureIterator.close();
    }

  private:
    QgsFeatureIterator mFeatureIterator;
    QgsFeature mCurrentFeature;

    bool mHasNext = false;
    bool mHasNextChecked = false;
};

/**
 * \ingroup core
 */
class LayerUtils : public QObject
{
    Q_OBJECT

  public:
    explicit LayerUtils( QObject *parent = nullptr );

    /**
    * Returns the default symbol for a given layer.
    * \param layer the vector layer used to create the default symbol
    */
    static QgsSymbol *defaultSymbol( QgsVectorLayer *layer, const QString &attachmentField = QString(), const QString &colorField = QString() );

    /**
     * Sets the default symbology render for a given \a layer.
     */
    static void setDefaultRenderer( QgsVectorLayer *layer, QgsProject *project = nullptr, const QString &attachmentField = QString(), const QString &colorField = QString() );

    /**
     * Returns the default vector layer labeling for a given \a layer and \a textFormat.
     */
    static QgsAbstractVectorLayerLabeling *defaultLabeling( QgsVectorLayer *layer, QgsTextFormat textFormat = QgsTextFormat() );

    /**
     * Sets the default labeling for a given \a layer.
     */
    static void setDefaultLabeling( QgsVectorLayer *layer, QgsProject *project = nullptr );

    /**
     * Creats an online raster elevation layer.
     */
    static QgsRasterLayer *createOnlineElevationLayer();

    /**
     * Creates an online basemap layer.
     */
    static QgsMapLayer *createBasemap( const QString &style = QString() );

    /**
    * Returns TRUE if the vector layer is used as an atlas coverage layer in
    * any of the print layouts of the currently opened project.
    * \param layer the vector layer to check against print layouts
    */
    /**
     * Returns the fill/marker color of a single-symbol renderer, or an invalid
     * color if the layer uses a different renderer type.
     */
    static Q_INVOKABLE QColor symbolColor( QgsVectorLayer *layer );

    /**
     * Sets the color of a single-symbol renderer and repaints the layer.
     */
    static Q_INVOKABLE void setSymbolColor( QgsVectorLayer *layer, const QColor &color );

    /**
     * Returns the size (markers) or width (lines/outlines) of a single-symbol
     * renderer in millimeters, or -1 if unavailable.
     */
    static Q_INVOKABLE double symbolSize( QgsVectorLayer *layer );

    /**
     * Sets the size (markers) or width (lines/outlines) of a single-symbol renderer.
     */
    static Q_INVOKABLE void setSymbolSize( QgsVectorLayer *layer, double size );

    /**
     * Returns TRUE if the layer uses a single-symbol renderer and can be styled
     * through the methods above.
     */
    static Q_INVOKABLE bool hasSimpleSymbology( QgsVectorLayer *layer );

    /**
     * Returns 0 for marker, 1 for line, 2 for fill, -1 if unavailable.
     */
    /**
     * Returns TRUE when the layer uses a categorized or graduated renderer.
     */
    static Q_INVOKABLE bool hasCategorizedSymbology( QgsVectorLayer *layer );

    /**
     * Returns the current label configuration as a map with "enabled", "field",
     * "size", "color", "bufferEnabled" and "bufferColor" keys.
     */
    static Q_INVOKABLE QVariantMap labelSettings( QgsVectorLayer *layer );

    /**
     * Enables or disables labels on \a layer, creating a default configuration
     * on \a fieldName when none exists yet.
     */
    static Q_INVOKABLE bool setLabelsEnabled( QgsVectorLayer *layer, bool enabled, const QString &fieldName = QString() );

    //! Sets the field used for labels.
    static Q_INVOKABLE bool setLabelField( QgsVectorLayer *layer, const QString &fieldName );

    //! Sets the label text size in points.
    static Q_INVOKABLE bool setLabelSize( QgsVectorLayer *layer, double size );

    //! Sets the label text color.
    static Q_INVOKABLE bool setLabelColor( QgsVectorLayer *layer, const QColor &color );

    //! Enables the label halo and sets its color.
    static Q_INVOKABLE bool setLabelBuffer( QgsVectorLayer *layer, bool enabled, const QColor &color = QColor( 255, 255, 255 ) );

    /**
     * Returns the layer fields as a list of maps with "name", "type" and
     * "numeric" keys.
     */
    static Q_INVOKABLE QVariantList layerFields( QgsVectorLayer *layer );

    /**
     * Creates an empty vector layer at \a filePath.
     *
     * \a geometryType accepts "Point", "LineString", "Polygon", "MultiPoint",
     * "MultiLineString", "MultiPolygon" or "NoGeometry".
     * \a fields is a list of maps with "name" and "type" keys, where type is one
     * of "text", "multiline", "integer", "real", "date", "datetime" or "bool".
     * When the target is an existing GeoPackage the layer is appended to it.
     *
     * Returns the created layer, or NULLPTR on failure.
     */
    /**
     * Configures \a fieldName of \a layer as a photo attachment field storing
     * files under <project>/DCIM/<layer>/<uuid>/ and marks \a uuidFieldName as a
     * hidden field with a UUID default value.
     */
    static Q_INVOKABLE bool setAttachmentField( QgsVectorLayer *layer, const QString &fieldName, const QString &uuidFieldName = QStringLiteral( "uuid" ) );

    static Q_INVOKABLE QgsVectorLayer *createEmptyLayer( const QString &filePath, const QString &layerName, const QString &geometryType, const QString &crsAuthId, const QVariantList &fields );

    //! Switches the layer to a single symbol renderer.
    static Q_INVOKABLE void setSingleSymbolRenderer( QgsVectorLayer *layer );

    //! Switches the layer to a categorized renderer on \a fieldName.
    static Q_INVOKABLE bool setCategorizedRenderer( QgsVectorLayer *layer, const QString &fieldName, const QString &rampName = QStringLiteral( "Turbo" ) );

    //! Switches the layer to a graduated renderer on \a fieldName with \a classCount classes.
    static Q_INVOKABLE bool setGraduatedRenderer( QgsVectorLayer *layer, const QString &fieldName, int classCount = 5, const QString &rampName = QStringLiteral( "Turbo" ) );

    /**
     * Returns the categories of a categorized/graduated renderer as a list of maps
     * with "index", "label", "color" and "visible" keys.
     */
    static Q_INVOKABLE QVariantList rendererCategories( QgsVectorLayer *layer );

    //! Sets the color of the category at \a categoryIndex.
    static Q_INVOKABLE void setCategoryColor( QgsVectorLayer *layer, int categoryIndex, const QColor &color );

    //! Toggles rendering of the category at \a categoryIndex.
    static Q_INVOKABLE void setCategoryVisible( QgsVectorLayer *layer, int categoryIndex, bool visible );

    static Q_INVOKABLE int symbolType( QgsVectorLayer *layer );

    //! Fill color of the first symbol layer.
    static Q_INVOKABLE QColor fillColor( QgsVectorLayer *layer );
    static Q_INVOKABLE void setFillColor( QgsVectorLayer *layer, const QColor &color );

    //! Stroke color of the first symbol layer.
    static Q_INVOKABLE QColor strokeColor( QgsVectorLayer *layer );
    static Q_INVOKABLE void setStrokeColor( QgsVectorLayer *layer, const QColor &color );

    //! Stroke width in millimeters, -1 if unavailable.
    static Q_INVOKABLE double strokeWidth( QgsVectorLayer *layer );
    static Q_INVOKABLE void setStrokeWidth( QgsVectorLayer *layer, double width );

    //! Stroke style as Qt::PenStyle (1 solid, 2 dash, 3 dot, 4 dash-dot, 5 dash-dot-dot).
    static Q_INVOKABLE int strokeStyle( QgsVectorLayer *layer );
    static Q_INVOKABLE void setStrokeStyle( QgsVectorLayer *layer, int style );

    //! Marker shape as Qgis::MarkerShape, -1 if not a marker symbol.
    static Q_INVOKABLE int markerShape( QgsVectorLayer *layer );
    static Q_INVOKABLE void setMarkerShape( QgsVectorLayer *layer, int shape );

    static Q_INVOKABLE bool isAtlasCoverageLayer( QgsVectorLayer *layer );

    /**
     * Returns TRUE if the \a layer permission state prevents feature addition.
     */
    static Q_INVOKABLE bool isFeatureAdditionLocked( QgsMapLayer *layer );

    /**
     * Selects features in a layer
     * This method is required since QML cannot perform the conversion of a feature ID to a QgsFeatureId
     * \param layer the vector layer
     * \param fids the list of feature IDs
     * \param behavior the selection behavior
     */
    static Q_INVOKABLE void selectFeaturesInLayer( QgsVectorLayer *layer, const QList<int> &fids, Qgis::SelectBehavior behavior = Qgis::SelectBehavior::SetSelection );

    /**
     * Deletes a vector layer feature, including related features tied to relationships.
     * \param project the project holding information on relationships
     * \param layer the layer from which the feature will be deleted
     * \param fid the feature ID to be deleted
     * \param flushBuffer set to TRUE to immediately save the edit buffer
     */
    static Q_INVOKABLE bool deleteFeature( QgsProject *project, QgsVectorLayer *layer, const QgsFeatureId fid, bool flushBuffer = true );

    /**
     * Duplicates a given \a feature within the provided vector \a layer. If successful, the function will
     * return the duplicated feature with attribute values saved updated to match what was saved
     * into the layer dataset.
     */
    static Q_INVOKABLE QgsFeature duplicateFeature( QgsVectorLayer *layer, QgsFeature feature );

    /**
     * Adds a \a feature into the \a layer.
     * \note The function will not call startEditing() and commitChanges()
     */
    Q_INVOKABLE static bool addFeature( QgsVectorLayer *layer, QgsFeature feature );

    /**
     * Returns the QVariant typeName of a \a field.
     * This is a stable identifier (compared to the provider field name).
     */
    Q_INVOKABLE static QString fieldType( const QgsField &field );

    /**
     * Returns TRUE if the vector \a layer geometry has an M value.
     */
    Q_INVOKABLE static bool hasMValue( QgsVectorLayer *layer );

    /**
     * Guesses the name of the field in \a layer most likely to carry a per-feature
     * height/extrusion value, or an empty string when no suitable field is found.
     */
    Q_INVOKABLE static QString guessFriendlyHeightField( QgsVectorLayer *layer );

    /**
     * Returns a list of unique values for a given \a fieldIndex from the \a layer.
     */
    Q_INVOKABLE QSet<QVariant> uniqueValuesForVectorLayerFieldIndex( QgsVectorLayer *layer, int fieldIndex );

    /**
     * Loads a vector layer.
     * \param uri the data source uri
     * \param name the layer name
     * \param provider the data provider name
     */
    Q_INVOKABLE static QgsVectorLayer *loadVectorLayer( const QString &uri, const QString &name = QString(), const QString &provider = QStringLiteral( "ogr" ) );

    /**
     * Loads a raster layer.
     * \param uri the data source uri
     * \param name the layer name
     * \param provider the data provider name
     */
    Q_INVOKABLE static QgsRasterLayer *loadRasterLayer( const QString &uri, const QString &name = QString(), const QString &provider = QStringLiteral( "gdal" ) );

    /**
     * Attempts to parse a GeoJSON string to a memory vector layer containing the collection of
     * features. The geometry type will be taken from the first parsed feature.
     * \param name layer name
     * \param string the GeoJSON string
     * \param crs optional layer CRS for layers with geometry
     */
    Q_INVOKABLE static QgsVectorLayer *memoryLayerFromJsonString( const QString &name, const QString &string, const QgsCoordinateReferenceSystem &crs = QgsCoordinateReferenceSystem() );

    /**
     * Creates a new memory layer using the specified parameters.
     * \param name layer name
     * \param fields fields for layer
     * \param geometryType optional layer geometry type
     * \param crs optional layer CRS for layers with geometry
     */
    Q_INVOKABLE static QgsVectorLayer *createMemoryLayer( const QString &name,
                                                          const QgsFields &fields = QgsFields(),
                                                          Qgis::WkbType geometryType = Qgis::WkbType::NoGeometry,
                                                          const QgsCoordinateReferenceSystem &crs = QgsCoordinateReferenceSystem() );

    /**
     * Returns a feature iterator to get all features within the provided \a layer.
     */
    Q_INVOKABLE static FeatureIterator createFeatureIterator( QgsVectorLayer *layer );

    /**
     * Returns a feature iterator to get features matching a given \a expression within the provided \a layer.
     */
    Q_INVOKABLE static FeatureIterator createFeatureIteratorFromExpression( QgsVectorLayer *layer, const QString &expression );

    /**
     * Returns a feature iterator to get features overlapping a given \a rectangle within the provided \a layer.
     */
    Q_INVOKABLE static FeatureIterator createFeatureIteratorFromRectangle( QgsVectorLayer *layer, const QgsRectangle &rectangle );

    /**
     * Saves a vector layer into an on-disk dataset a given path using the OGR provider.
     * \param layer the vector layer to save features from
     * \param filePath the file path where the dataset will be writen
     * \param driverName an optional OGR driver name (if left empty, the file path extension will drive the OGR driver)
     * \param filterExpression an optional filter expression used to save a subset of features from the layer (note that only the global, project, and layer expression context scopes are used)
     * \returns If successful, finalized file path will be returned, otherwise an empty string will be returned
     */
    /**
     * Exports a vector layer to \a filePath, reprojecting to \a destinationCrsAuthId
     * (e.g. "EPSG:4326") when provided. Returns the written file name, or an empty
     * string on failure.
     */
    /**
     * Returns the vector sub-layers available in \a filePath as a list of maps
     * with "name", "geometry", "featureCount" and "uri" keys.
     */
    Q_INVOKABLE static QVariantList vectorSubLayers( const QString &filePath );

    Q_INVOKABLE static QString exportVectorLayer( QgsVectorLayer *layer, const QString &filePath, const QString &destinationCrsAuthId = QString(), const QString &fileEncoding = QStringLiteral( "UTF-8" ) );

    Q_INVOKABLE static QString saveVectorLayerAs( QgsVectorLayer *layer, const QString &filePath, const QString &driverName = QString(), const QString &filterExpression = QString() );
};

#endif // LAYERUTILS_H
