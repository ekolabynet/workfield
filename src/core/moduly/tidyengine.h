/***************************************************************************
  tidyengine.h - TidyEngine (WorkFieldGIS)

  Moduł „Porządkowanie danych” — silnik. Etap 1, łatka 1: TYLKO CZYTA.
  Decyzje i plan: claude/MODUL_porzadkowanie_plan.md (Piotr, 24.10.2026).

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef TIDYENGINE_H
#define TIDYENGINE_H

#include <QObject>
#include <QVariantMap>

class QgsProject;

/**
 * Engine of the "data tidying" tool module. QML singleton "TidyEngine".
 *
 * WHY (claude/MODUL_porzadkowanie_plan.md): a purely automatic assignment of
 * photos failed on 23.10.2026 — not because of the code, but because the GPS
 * error was larger than the plots, and because the wrong database was
 * measured (a return instead of the release). The tool proposes, a person
 * decides, the application writes through a decision journal.
 *
 * THIS PATCH ONLY READS. Nothing is written to any database or moved on disk.
 * The only file it creates is the report in <project>/export/porzadki_<time>/.
 * Decisions (WF_DECISIONS), the decision card and "Apply" come in the next
 * patches.
 *
 * What it answers (each rule comes from a loss written down in the notes):
 *  - which GeoPackages lie in the project folder, with counters and md5 —
 *    "size and date do not decide; counters and checksums do";
 *  - which database has a leftover -wal next to it (its counters are low);
 *  - attachment rows whose file is missing ("dead"), split from those whose
 *    file exists with different letter case (.JPG / .jpg — twice a false
 *    alarm on 23.10) and from Android/Mapit URIs that are never local paths;
 *  - photo files no attachment row knows ("orphans");
 *  - identical files in several places, by content (size, first 64 kB, md5) —
 *    a duplicate is NOT "to delete", it is reported, nothing more.
 */
class TidyEngine : public QObject
{
    Q_OBJECT

  public:
    explicit TidyEngine( QObject *parent = nullptr );

    //! Module description (the modul.json equivalent) for the "Moduły" panel.
    Q_INVOKABLE QVariantMap opis() const;

    /**
     * Cheap recognition for the module card: layers with attachment tables,
     * attachment rows, databases in the project folder. Never an error while
     * a project is open — the tool works on every project.
     * Returns {obiekty, warstwa, opisWarstw, opisBaz} or {blad}.
     */
    Q_INVOKABLE QVariantMap recognize( QgsProject *project ) const;

    /**
     * Full read-only review: databases, dead links, orphans, duplicates.
     * Writes a text report and a TSV of findings into
     * <project>/export/porzadki_<yyyyMMdd_HHmmss>/ and returns
     * {bazy, martwe, wielkoscLiter, obce, sieroty, grupyDuplikatow,
     *  zdjec, wpisow, pliki, katalog, raport} or {blad}.
     */
    Q_INVOKABLE QVariantMap scan( QgsProject *project ) const;

    /**
     * Databases (*.gpkg) under \a folder, at most \a depth levels deep:
     * [{sciezka, nazwa, bajty, md5, wal, kopiaPrzegladarki, tabele: {name: rows},
     *   obiektow, zalacznikow, tabelZal, blad}]. Read-only SQLite access.
     * Public for the test and for the "source database" gate (next patch).
     */
    Q_INVOKABLE QVariantList sourceDatabases( const QString &folder, int depth = 3 ) const;

    /**
     * Compares attachment rows (\a index: path relative to \a projectDir ->
     * anything, as from ZalacznikiUtils::photoIndex) with photo files under
     * \a projectDir/DCIM. Pure file logic, no QGIS — tested on its own.
     * Returns {zdjec, wpisow, martwe[], wielkoscLiter[], obce[], sieroty[],
     *  grupyDuplikatow[], czesciowychMd5, pelnychMd5}.
     */
    Q_INVOKABLE QVariantMap compareWithDisk( const QString &projectDir, const QVariantMap &index ) const;
};

#endif // TIDYENGINE_H
