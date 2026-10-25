/***************************************************************************
  objectatlas.h - ObjectAtlas
 ---------------------
 WorkField 25.10.2026 [WF-OBJECT-ATLAS] — the object atlas: one page per
 object, like a QGIS atlas. For each object: an overview map (the whole
 layer, the object marked, the frame of the object map), the object map
 (the object + 20%), its attributes as text, its photos with numbers and
 their view cones.

 The maps are rendered by the QGIS engine (the visible layers of the
 project, with their styles, labels and diagrams), WITHOUT overlays: the
 object outline and the view cones come back as coordinates in the map
 CRS and are drawn on top by the window. Tapping a photo then lights its
 cone at once, without rendering the map again — and the same coordinates
 will serve dragging the cone and the PDF.
 ***************************************************************************/

#ifndef OBJECTATLAS_H
#define OBJECTATLAS_H

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QVariantMap>

class QgsProject;
class QgsVectorLayer;
class QgsMapRendererParallelJob;

/**
 * \ingroup core
 */
class ObjectAtlas : public QObject
{
    Q_OBJECT

  public:
    explicit ObjectAtlas( QObject *parent = nullptr );
    ~ObjectAtlas() override;

    /**
     * Layers that can have an atlas: valid vector layers with geometry,
     * without attachment tables, WF_ tables and basemaps.
     * [{ id, name, layer (QgsVectorLayer*) }], in the order of the legend.
     */
    Q_INVOKABLE QVariantList layers( QgsProject *project ) const;

    /**
     * Objects of \a layer: [{ fid, label }] — label from the display
     * expression of the layer (the same as in the feature list), sorted
     * by fid. At most 20 000.
     */
    Q_INVOKABLE QVariantList objects( QgsVectorLayer *layer ) const;

    /**
     * Everything about one object except the rendered maps:
     *   ok, title, layerName, fid, mapCrs,
     *   attributes: [{ name, value, field }] — formatted as in the form
     *     (value maps, dates), hidden fields left out,
     *   measures:   [{ name, value }] — area / perimeter / length / X, Y,
     *   geometryType: "point" | "line" | "polygon",
     *   parts: [[[x, y], …], …] — the object in the map CRS (rings or
     *     lines; points as one-vertex parts),
     *   photos: [{ number, name, path, absolutePath, uuid, cone }] where
     *     cone is null or { uuid, polygon: [[x, y], …], stand: [x, y],
     *     azimuth, range, fovH, source, confirmed },
     *   objectExtent:   [xmin, ymin, xmax, ymax] — the object (and its cones) + 20%,
     *   overviewExtent: [xmin, ymin, xmax, ymax] — the layer, the object map inside.
     */
    Q_INVOKABLE QVariantMap describe( QgsProject *project, QgsVectorLayer *layer, qlonglong fid ) const;

    /**
     * Renders one map in the background: \a extent ([xmin, ymin, xmax,
     * ymax] in the map CRS) into \a width x \a height pixels at \a dpr
     * (device pixel ratio). Returns a request number; mapRendered()
     * brings { request, ok, image (file URL), extent (the visible extent,
     * fitted to the image proportions), width, height }.
     * A new request with the same \a slot ("object", "overview") cancels
     * the older one still rendering.
     */
    Q_INVOKABLE int renderMap( QgsProject *project, QgsVectorLayer *layer, const QVariantList &extent, int width, int height, double dpr, const QString &slot, const QVariantMap &style = QVariantMap() );

    // ======================================================================
    // [WF-OBJECT-ATLAS] 25.10.2026 (Piotr 10:43) — working comparison of the
    // object against the others: colour by a field, show a field as labels;
    // values edited in place.
    // ======================================================================

    /**
     * Writes \a value into \a field of the object \a fid (converted to the
     * field type; for a value map the stored value, not the label) and
     * commits — unless the layer was already in editing, then the change
     * stays in its edit buffer like any other. Returns { ok, message }.
     */
    Q_INVOKABLE QVariantMap setValue( QgsVectorLayer *layer, qlonglong fid, const QString &field, const QVariant &value );

    /**
     * \a style: { colorBy: field or "", labelBy: field or "" }.
     * Applies it to the layer ITSELF (the main map, the legend) as the named
     * style "Atlas obiektów" — the style the layer had is kept and comes back
     * with an empty \a style. Remembered in the project, which is saved.
     * Returns { ok, message }.
     */
    Q_INVOKABLE QVariantMap applyToLayer( QgsProject *project, QgsVectorLayer *layer, const QVariantMap &style );

    //! The style kept "for good" for \a layer: { colorBy, labelBy } or empty.
    Q_INVOKABLE QVariantMap keptStyle( QgsProject *project, QgsVectorLayer *layer ) const;

  signals:
    void mapRendered( const QVariantMap &result );

  private:
    //! the layer drawn with the atlas colouring / labels (a clone, cached)
    QgsVectorLayer *styledLayer( QgsVectorLayer *layer, const QVariantMap &style );
    QVariantList legendOf( QgsVectorLayer *layer ) const;

    QgsVectorLayer *mStyled = nullptr;
    QString mStyledKey;
    int mStyleGeneration = 0;

    struct Job
    {
        int request = 0;
        QString slot;
        QgsMapRendererParallelJob *job = nullptr;
        QVariantList extent;
        QVariantList legend;
        int width = 0;
        int height = 0;
    };

    QHash<QString, Job> mJobs;
    int mLastRequest = 0;
    int mFileCounter = 0;
};

#endif // OBJECTATLAS_H
