#!/usr/bin/env python3
# WorkFieldGIS 24.10.2026 — DZIENNIK ZMIAN (WF_JOURNAL) NA KOMPUTERZE [WF-JOURNAL]
#
# Aplikacja zakłada dziennik w każdym pliku .gpkg projektu przy otwarciu
# (wyzwalacze SQLite na warstwach roboczych i ZAL_*). Wyzwalacze wymieniają
# kolumny po nazwie, więc SQLite NIE pozwala usunąć pola, którego używają —
# QGIS pokaże wtedy błąd „error in trigger wf_journal_…”.
#
#   python3 dziennik.py dane.gpkg                 # stan: ile wpisów, ostatnie
#   python3 dziennik.py dane.gpkg --ostatnie 30   # więcej ostatnich wpisów
#   python3 dziennik.py dane.gpkg --obiekt UUID   # historia jednego obiektu
#   python3 dziennik.py dane.gpkg --zdejmij       # zdejmuje wyzwalacze (wpisy zostają)
#
# Po „--zdejmij” zmiany robione w QGIS NIE trafiają do dziennika. Następne
# otwarcie projektu w aplikacji zakłada wyzwalacze z powrotem, już z nowym
# układem pól. Plik otwieramy bez rozszerzeń przestrzennych: sam odczyt
# i zdejmowanie wyzwalaczy ich nie potrzebują.
import sqlite3, sys


def main():
    a = sys.argv[1:]
    if not a or a[0].startswith('-'):
        print(__doc__ or open(__file__, encoding='utf-8').read().split('import sqlite3')[0])
        return 1
    path = a[0]
    import os
    if not os.path.isfile(path):
        print('Nie ma takiego pliku: %s' % path)
        print('Podaj pełną ścieżkę do pliku .gpkg w cudzysłowie, np.:')
        print('  python3 dziennik.py "/DATA/APPL/APPL MM Pasymska/DATA/Projekt Pasymska 2026-10-23_nowy/dane.gpkg"')
        return 1
    # mode=rw: never creates an empty file by mistake
    c = sqlite3.connect('file:%s?mode=rw' % path.replace('?', '%3f').replace('#', '%23'), uri=True)
    c.execute('PRAGMA busy_timeout = 5000')
    triggers = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'wf\\_journal\\_%' ESCAPE '\\' ORDER BY name")]
    has_journal = c.execute("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='WF_JOURNAL'").fetchone()[0] == 1

    if '--zdejmij' in a:
        for name in triggers:
            c.execute('DROP TRIGGER IF EXISTS "%s"' % name.replace('"', '""'))
        c.commit()
        print('Zdjęto wyzwalaczy dziennika: %d. Wpisy w WF_JOURNAL zostały.' % len(triggers))
        print('Zmiany w QGIS nie trafią teraz do dziennika. Aplikacja założy go z powrotem przy następnym otwarciu projektu.')
        return 0

    if not has_journal:
        print('Ten plik nie ma dziennika (WF_JOURNAL). Aplikacja zakłada go przy otwarciu projektu.')
        return 0

    tables = sorted({n.split('_', 3)[3].rsplit('_', 1)[0] for n in triggers})
    n = c.execute('SELECT count(*) FROM WF_JOURNAL').fetchone()[0]
    print('Wyzwalacze dziennika: %d (tabel: %d)%s' % (len(triggers), len(tables), '' if triggers else ' — ZDJĘTE, zmiany nie są zapisywane'))
    print('Wpisów w dzienniku: %d' % n)
    for event, count in c.execute('SELECT EVENT, count(*) FROM WF_JOURNAL GROUP BY EVENT ORDER BY 2 DESC'):
        print('   %-10s %d' % (event, count))

    cols = 'SEQ, TIME_UTC, TABLE_NAME, FID, EVENT, OPERATION, ORIGIN, CHANGED, DEVICE'
    if '--obiekt' in a:
        uuid = a[a.index('--obiekt') + 1]
        rows = c.execute('SELECT %s FROM WF_JOURNAL WHERE OBJECT_UUID = ? OR ORIGIN LIKE ? ORDER BY SEQ' % cols, (uuid, '%' + uuid + '%')).fetchall()
        print('\nHistoria obiektu %s (także jako źródło podziału/scalenia/duplikatu): %d wpisów' % (uuid, len(rows)))
    else:
        k = int(a[a.index('--ostatnie') + 1]) if '--ostatnie' in a else 10
        rows = c.execute('SELECT %s FROM WF_JOURNAL ORDER BY SEQ DESC LIMIT ?' % cols, (k,)).fetchall()[::-1]
        print('\nOstatnie wpisy:')
    for r in rows:
        seq, time, table, fid, event, op, origin, changed, device = r
        extra = ''
        if op:
            extra += ' [%s z %s]' % (op, origin or '?')
        if changed:
            extra += ' ' + (changed if len(changed) < 120 else changed[:117] + '...')
        print('  %5d %s %-28s fid %-6s %-8s%s' % (seq, time[:19], table[:28], fid, event, extra))
    return 0


if __name__ == '__main__':
    sys.exit(main())
