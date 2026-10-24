/***************************************************************************
  journalutils.h - JournalUtils

 ---------------------
 WorkField 24.10.2026 [WF-JOURNAL] — the change journal of a GeoPackage.

 Decisions: claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md, section 4.
 Like the journal of a file system: not the full history, but what is needed
 to restore and to trace where an object came from.

 - Table WF_JOURNAL in the same GeoPackage as the data, filled by SQLite
   triggers AFTER INSERT / UPDATE / DELETE on every working table (layers and
   ZAL_*), in the same transaction as the change, whatever tool writes:
   this app, QGIS on the computer, scripts. Only plain SQL (json_quote,
   randomblob) — no Spatialite functions.
 - Entry: time (UTC), table, fid, uuid of the object, event (created /
   updated / deleted), changed fields with their OLD values (JSON), the old
   geometry when it changed or the object was deleted, and from WF_SESSION:
   operation and origin (split / merge / duplicate + source uuid), device,
   app version.
 - Not registered in gpkg_contents: no layer, no form.

 The triggers name the columns, so SQLite refuses to drop a column a
 trigger uses (tried 24.10 on a copy of Pasymska: "error in trigger
 wf_journal_…"). Piotr's choice: full journal + workaround — the app drops
 the triggers of a table around deleting a field and installs them again;
 on the computer skrypty/dziennik.py --zdejmij before such work in QGIS; the
 next opening of the project in the app puts them back.
 ***************************************************************************/

#ifndef JOURNALUTILS_H
#define JOURNALUTILS_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

class QgsProject;
class QgsVectorLayer;

/**
 * \ingroup core
 */
class JournalUtils : public QObject
{
    Q_OBJECT

  public:
    explicit JournalUtils( QObject *parent = nullptr );

    /**
     * Installs (or refreshes, when the columns of a table changed) the
     * journal in every GeoPackage of \a project, and writes the device and
     * the app version to WF_SESSION. Returns { files, tables, refreshed,
     * errors }. Cheap when nothing changed: the trigger SQL is compared first.
     */
    Q_INVOKABLE QVariantMap installForProject( QgsProject *project );

    //! The GeoPackage file of \a layer, or empty when it is not one.
    static QString gpkgPath( const QgsVectorLayer *layer );

    //! Installs the journal in \a gpkg (all working tables, or only \a table).
    static bool install( const QString &gpkg, const QString &table = QString(), QString *error = nullptr, int *tables = nullptr, int *refreshed = nullptr );

    //! Drops the journal triggers of \a table in \a gpkg (all tables when empty).
    static bool dropTriggers( const QString &gpkg, const QString &table = QString(), QString *error = nullptr );

    /**
     * Operation scope: while it lives, every journal entry written to the
     * GeoPackage of \a layer carries \a operation ("split", "merge",
     * "duplicate", …) and \a origin (uuid of the source object or objects).
     */
    class OperationScope
    {
      public:
        OperationScope( const QgsVectorLayer *layer, const QString &operation, const QString &origin );
        ~OperationScope();

      private:
        QString mGpkg;
    };

    //! Sets one WF_SESSION value (empty \a value clears it).
    static bool setSessionValue( const QString &gpkg, const QString &key, const QString &value );
};

#endif // JOURNALUTILS_H
