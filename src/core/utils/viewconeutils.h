/***************************************************************************
  viewconeutils.h - ViewConeUtils

 ---------------------
 WorkField 24.10.2026 [WF-VIEW-CONE] — the view cone of a photo, right
 after it is taken: where the camera stood and looked, which objects the
 footprint of the frame hits. Shown on the map; the user confirms it,
 corrects the direction or skips; saved to the layer WF_VIEW_CONES in the
 GeoPackage of the object (polygon + stand point, azimuth, pitch, source).

 Decisions: claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md, section 7
 ("Stożek widoku po zdjęciu"). The cone parameters (field 60x45°, range
 8 m, camera 1.5 m, declination) are those of StozkiWidzenia — measured
 09.09.2026, one source of truth.
 ***************************************************************************/

#ifndef VIEWCONEUTILS_H
#define VIEWCONEUTILS_H

#include <QObject>
#include <QVariantMap>
#include <qgscoordinatereferencesystem.h>
#include <qgsfeature.h>
#include <qgsvectorlayer.h>

#include <limits>

/**
 * \ingroup core
 */
class ViewConeUtils : public QObject
{
    Q_OBJECT

  public:
    explicit ViewConeUtils( QObject *parent = nullptr );

    /**
     * Asks the app to show (and, with \a ask, to confirm) the cone of a photo
     * just attached to \a parent of \a parentLayer. \a photo: { path (relative
     * to the project), uuid (of the attachment row), parentUuid }. \a sensor:
     * what the phone knows now — { lat, lon, elevation, heading, pitch } —
     * used when the file has no pose. Emits coneRequested() on the next turn
     * of the event loop.
     */
    Q_INVOKABLE void requestCone( QgsVectorLayer *parentLayer, const QgsFeature &parent, const QVariantMap &photo, const QVariantMap &sensor, bool ask );

    /**
     * The cone of the photo at \a absolutePath. The pose comes from the file
     * (EXIF/XMP written by our camera or OpenCamera); what is missing comes
     * from \a sensor. \a azimuthOverride (true north, degrees) replaces the
     * direction — the user corrected it. Returns:
     *   ok, reason, source ("photo" | "sensor" | "manual"),
     *   azimuth (true north), declination, pitch, roll,
     *   standX, standY (layer CRS), stand (QgsPoint in \a mapCrs),
     *   geometry (QgsGeometry in \a mapCrs), layerGeometryWkt (layer CRS),
     *   hits: [{ fid, uuid, share (% of the cone) }] in \a parentLayer.
     */
    Q_INVOKABLE QVariantMap buildCone( QgsVectorLayer *parentLayer, const QString &absolutePath, const QVariantMap &sensor, const QgsCoordinateReferenceSystem &mapCrs, double azimuthOverride = std::numeric_limits<double>::quiet_NaN() ) const;

    /**
     * Saves \a cone (from buildCone) for \a photo ({ path, uuid, parentUuid,
     * parentFid }) into WF_VIEW_CONES in the GeoPackage of \a parentLayer;
     * creates the table and adds it to the project (hidden) when missing.
     * Returns { ok, message }.
     */
    Q_INVOKABLE QVariantMap saveCone( QgsVectorLayer *parentLayer, const QVariantMap &cone, const QVariantMap &photo, bool confirmed );

  signals:
    void coneRequested( QgsVectorLayer *parentLayer, const QVariantMap &photo, const QVariantMap &sensor, bool ask );
};

#endif // VIEWCONEUTILS_H
