/***************************************************************************
  splitheirutils.h - SplitHeirUtils

 ---------------------
 WorkField 24.10.2026 [WF-SPLIT-HEIR] — after a split, the user says which
 part is the old object (keeps its fid, uuid and number) and where each
 photo of the old object goes. Merge asks a similar question in its own
 dialog (which object stays) — see QfFeatureListForm.qml.

 Decisions: claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md, section 7.
 ***************************************************************************/

#ifndef SPLITHEIRUTILS_H
#define SPLITHEIRUTILS_H

#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <qgscoordinatereferencesystem.h>
#include <qgsfeature.h>
#include <qgsvectorlayer.h>

/**
 * \ingroup core
 */
class SplitHeirUtils : public QObject
{
    Q_OBJECT

  public:
    explicit SplitHeirUtils( QObject *parent = nullptr );
    ~SplitHeirUtils() override;

    /**
     * Called by the split tools once a split is committed: \a originalFid
     * keeps the identity for now, \a newUuids are the uuids of the new parts.
     * Emits choiceRequested() on the next turn of the event loop, so the tool
     * finishes its own work first. Nothing happens without new uuids (a layer
     * without the uuid field: the new parts cannot be found again).
     */
    static void announceSplit( QgsVectorLayer *layer, QgsFeatureId originalFid, const QStringList &newUuids );

    /**
     * The parts and photos for the dialog. Returns:
     *   parts:  [{ fid, uuid, original (bool), size (number), sizeText, geometry,
     *             labelPoint }] the original first, then the new parts,
     *           largest first; labelPoint — a point inside the part, in
     *           \a mapCrs, where the map shows the number of the part;
     *   photos: [{ layerId, layerName, fid, path, absolutePath }] — children
     *           of the original object in composition relations;
     *   crs:    the layer CRS (for highlighting a part on the map).
     */
    Q_INVOKABLE QVariantMap partsInfo( QgsVectorLayer *layer, qlonglong originalFid, const QStringList &newUuids, const QgsCoordinateReferenceSystem &mapCrs = QgsCoordinateReferenceSystem() ) const;

    /**
     * Applies the choice. \a heirFid is the part that is the old object (as
     * listed by partsInfo); when it is not the original record, the geometry
     * and the attributes of the two records are swapped, so the old record —
     * its fid, uuid and photos — now holds the chosen part. \a photoTargets:
     * [{ layerId, fid, target }] with target = the fid of a part as listed.
     * Returns { ok, message, swapped, movedPhotos }.
     */
    Q_INVOKABLE QVariantMap applyChoice( QgsVectorLayer *layer, qlonglong originalFid, qlonglong heirFid, const QVariantList &photoTargets );

    //! How many children \a feature has in composition relations (photos).
    Q_INVOKABLE int childCount( QgsVectorLayer *layer, const QgsFeature &feature ) const;

  signals:
    //! A split was done; the app shows the dialog.
    void choiceRequested( QgsVectorLayer *layer, qlonglong originalFid, const QStringList &newUuids );

  private:
    static QPointer<SplitHeirUtils> sInstance;
};

#endif // SPLITHEIRUTILS_H
