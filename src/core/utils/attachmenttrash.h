/***************************************************************************
  attachmenttrash.h - AttachmentTrash

 ---------------------
 WorkField 24.10.2026 [WF-ATTACHMENT-TRASH] — photos of a deleted object go
 to the trash of the project instead of staying in DCIM without a row.

 Before: deleting an object deleted its rows in the ZAL_ table (composition
 relation) and the files stayed in DCIM, linked to nothing — a "loose photo"
 nobody could explain later. Now, after the deletion is committed, every
 file no other row points at moves to <project>/kosz/ under the name
 "<yyyyMMdd_HHmmss>__<path with / as __>" — the same trash and the same
 naming as the file browser of the gallery, which can restore it
 ("Przywróć"). When the deletion is undone (the row comes back), the file
 comes back too. The journal (WF_JOURNAL) keeps the deleted rows.

 Decisions: claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md, section 6 E.
 ***************************************************************************/

#ifndef ATTACHMENTTRASH_H
#define ATTACHMENTTRASH_H

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QStringList>

class QgsProject;
class QgsVectorLayer;

/**
 * \ingroup core
 */
class AttachmentTrash : public QObject
{
    Q_OBJECT

  public:
    explicit AttachmentTrash( QObject *parent = nullptr );

    /**
     * Watches every attachment table of \a project (child layers of
     * composition relations with a file field) and those added later.
     * Returns how many tables are watched.
     */
    Q_INVOKABLE int watchProject( QgsProject *project );

    //! Moves \a absolutePath into the trash of the project; returns the new path or empty.
    static QString moveToTrash( const QString &projectHome, const QString &absolutePath );

    //! Brings back the newest trashed copy of \a relativePath; true when restored.
    static bool restoreFromTrash( const QString &projectHome, const QString &relativePath );

  signals:
    //! \a count files of deleted attachments went to the trash.
    void filesTrashed( int count );

    //! \a count files came back because their rows came back (undo).
    void filesRestored( int count );

  private:
    void watchLayer( QgsVectorLayer *layer, const QString &pathField );
    void collectDeleted( QgsVectorLayer *layer );
    void trashCollected( QgsVectorLayer *layer );

    QPointer<QgsProject> mProject;
    QSet<QString> mWatched;
    QHash<QString, QString> mPathField;   // layer id → field with the path
    QHash<QString, QStringList> mPending; // layer id → paths of rows being deleted
};

#endif // ATTACHMENTTRASH_H
