#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Usuwa sieroty z tabel zdjęć ZAL_ [WF-ORPHAN-CLEANUP] (24.10.2026).

Sierota = wiersz ZAL_, którego ID_RODZICA wskazuje obiekt, którego już nie ma
(kontrola A w sprawdz_zalaczniki.py). Do 24.10.2026 powstawały przy każdym
usunięciu obiektu ze zdjęciem — błąd naprawiony w [WF-CASCADE-COMMIT].

Co robi przy --zapisz:
  1. kopia bazy: <projekt>/kopie/<nazwa>_<czas>_przed_sierotami.gpkg
  2. usuwa wiersze-sieroty (dziennik WF_JOURNAL zapisze je jako „deleted”,
     operacja orphan_cleanup)
  3. ich pliki przenosi do kosza projektu: kosz/<czas>__<ścieżka z / jako __>
     — ten sam kosz co w aplikacji (galeria → Pliki → Przywróć). Plik, na
     który wskazuje jeszcze jakikolwiek inny wiersz ZAL_, zostaje na miejscu.

Bez --zapisz tylko pokazuje, co by zrobił. ZAMKNIJ APLIKACJĘ przed zapisem.

    python3 skrypty/usun_sieroty.py "<projekt>/dane.gpkg"
    python3 skrypty/usun_sieroty.py "<projekt>/dane.gpkg" --zapisz
    python3 skrypty/usun_sieroty.py dane.gpkg --tabela ZAL_SKRZYNKI_ELEKTROZAWORY --zapisz
"""

import argparse
import datetime
import os
import shutil
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sprawdz_zalaczniki as sz  # noqa: E402

SESSION_KEYS = ("operation", "origin")


def find_orphans(con, forced, only_table, file_column):
    candidates = sz.wszystkie_tabele(con)
    result = []
    for table in sz.tabele_zal(con):
        if only_table and table != only_table:
            continue
        columns = [n for n, _ in sz.kolumny(con, table)]
        if sz.KOL_RODZICA not in columns:
            continue
        parent = forced.get(table) or sz.zgadnij_rodzica(table, candidates)
        if not parent:
            print("%s: rodzic NIE ROZPOZNANY — pomijam (podaj --rodzic %s=TABELA)" % (table, table))
            continue
        key = sz.kolumna_klucza(con, table)
        parent_key = sz.kolumna_klucza(con, parent)
        path_col = file_column or sz.zgadnij_kolumne_pliku(con, table)
        existing = {r for (r,) in con.execute('SELECT "%s" FROM "%s"' % (parent_key, parent))}
        sel = '"%s", "%s", %s' % (key, sz.KOL_RODZICA, ('"%s"' % path_col) if path_col else "NULL")
        for fid, parent_id, path in con.execute(
                'SELECT %s FROM "%s" WHERE "%s" IS NOT NULL' % (sel, table, sz.KOL_RODZICA)):
            if parent_id not in existing:
                result.append((table, key, parent, fid, parent_id, path))
    return result


def all_referenced_paths(con, file_column, skip):
    """Every file path still referenced by a row of any ZAL_ table, minus the
    rows about to be deleted (skip = {(table, fid)})."""
    used = set()
    for table in sz.tabele_zal(con):
        col = file_column or sz.zgadnij_kolumne_pliku(con, table)
        if not col:
            continue
        key = sz.kolumna_klucza(con, table)
        for fid, path in con.execute('SELECT "%s", "%s" FROM "%s"' % (key, col, table)):
            if path and (table, fid) not in skip:
                used.add(sz.znormalizuj(path))
    return used


def trash_name(relative, stamp):
    return "%s__%s" % (stamp, relative.replace("\\", "/").strip("/").replace("/", "__"))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gpkg")
    ap.add_argument("--zapisz", action="store_true", help="naprawdę usuń (domyślnie tylko pokazuje)")
    ap.add_argument("--tabela", help="tylko ta tabela ZAL_")
    ap.add_argument("--rodzic", action="append", default=[], metavar="ZAL_X=TABELA")
    ap.add_argument("--kolumna-pliku", dest="kolumna_pliku")
    a = ap.parse_args()

    if not os.path.isfile(a.gpkg):
        print("nie ma pliku: %s" % a.gpkg, file=sys.stderr)
        return 2
    forced = dict(p.split("=", 1) for p in a.rodzic if "=" in p)
    root = os.path.dirname(os.path.abspath(a.gpkg))

    con = sqlite3.connect(a.gpkg, timeout=3)
    orphans = find_orphans(con, forced, a.tabela, a.kolumna_pliku)
    if not orphans:
        print("Sierot nie ma. Nic do zrobienia.")
        return 0

    skip = {(t, f) for t, _, _, f, _, _ in orphans}
    used = all_referenced_paths(con, a.kolumna_pliku, skip)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

    plan = []
    print("Sieroty: %d" % len(orphans))
    for table, key, parent, fid, parent_id, path in orphans:
        action = "brak pliku w wierszu"
        move = None
        if path:
            rel = str(path).strip()
            full = rel if os.path.isabs(rel) else os.path.join(root, rel)
            if sz.znormalizuj(rel) in used:
                action = "plik zostaje (używa go inny wiersz): %s" % rel
            elif not os.path.exists(full):
                action = "pliku już nie ma na dysku: %s" % rel
            else:
                target = os.path.join(root, "kosz", trash_name(os.path.relpath(full, root), stamp))
                action = "plik → %s" % os.path.relpath(target, root)
                move = (full, target)
        print("  %s %s=%s (rodzic %s=%s nie istnieje)\n      %s" % (table, key, fid, parent, parent_id, action))
        plan.append((table, key, fid, move))

    if not a.zapisz:
        print("\nPRÓBA — nic nie zmieniono. Zamknij aplikację i dodaj --zapisz.")
        return 0

    try:
        con.execute("BEGIN IMMEDIATE")
        con.rollback()
    except sqlite3.OperationalError:
        print("STOP: baza jest zajęta — zamknij aplikację WorkField/QGIS i spróbuj znowu.")
        return 1

    backup_dir = os.path.join(root, "kopie")
    os.makedirs(backup_dir, exist_ok=True)
    backup = os.path.join(backup_dir, "%s_%s_przed_sierotami.gpkg"
                          % (os.path.splitext(os.path.basename(a.gpkg))[0], stamp))
    dst = sqlite3.connect(backup)
    con.backup(dst)
    dst.close()
    print("\nKopia bazy: %s" % backup)

    has_session = con.execute("SELECT count(*) FROM sqlite_master WHERE name='WF_SESSION'").fetchone()[0]
    previous = {}
    with con:
        if has_session:
            for k in SESSION_KEYS:
                row = con.execute("SELECT VALUE FROM WF_SESSION WHERE KEY=?", (k,)).fetchone()
                previous[k] = row[0] if row else None
            con.execute("INSERT OR REPLACE INTO WF_SESSION (KEY, VALUE) VALUES ('operation', 'orphan_cleanup')")
            con.execute("INSERT OR REPLACE INTO WF_SESSION (KEY, VALUE) VALUES ('origin', 'desktop:usun_sieroty.py')")
        for table, key, fid, _ in plan:
            con.execute('DELETE FROM "%s" WHERE "%s"=?' % (table, key), (fid,))
        if has_session:
            for k, v in previous.items():
                if v is None:
                    con.execute("DELETE FROM WF_SESSION WHERE KEY=?", (k,))
                else:
                    con.execute("INSERT OR REPLACE INTO WF_SESSION (KEY, VALUE) VALUES (?, ?)", (k, v))
    con.close()
    print("Usunięto wierszy: %d" % len(plan))

    moved = 0
    for _, _, _, move in plan:
        if move:
            os.makedirs(os.path.dirname(move[1]), exist_ok=True)
            shutil.move(move[0], move[1])
            moved += 1
            folder = os.path.dirname(move[0])
            if os.path.isdir(folder) and not os.listdir(folder) and os.path.basename(os.path.dirname(folder)) == "DCIM":
                os.rmdir(folder)  # empty per-object folder DCIM/<layer>_<nr>/
    print("Plików do kosza: %d" % moved)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
