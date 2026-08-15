#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Dosypuje tabele `taksony` i `wskazniki_polaczone` z szablonu ZZW do
istniejacego projektu (dane.gpkg). Przed zmiana robi kopie zapasowa.

UZYCIE:
    python3 uzupelnij_wskazniki.py /sciezka/do/katalogu/projektu [nastepny ...]

Szablon: /DATA/WorkField/szablony/szablon_inw_zzw/dane.gpkg
(mozna nadpisac zmienna SZABLON_GPKG)
"""
import io, os, sys, shutil, sqlite3, datetime, glob

SZABLON = os.environ.get('SZABLON_GPKG',
                         '/DATA/WorkField/szablony/szablon_inw_zzw/dane.gpkg')
TABELE = ['SLOWNIK_GATUNKOW', 'taksony', 'wskazniki_polaczone']

if len(sys.argv) < 2:
    sys.exit(__doc__)
if not os.path.exists(SZABLON):
    sys.exit('Brak szablonu: %s' % SZABLON)

# kontrola: szablon musi miec obie tabele
tpl = sqlite3.connect('file:%s?mode=ro' % SZABLON, uri=True)
ma = {r[0] for r in tpl.execute(
    "SELECT name FROM sqlite_master WHERE type='table'")}
tpl.close()
for t in TABELE:
    if t not in ma:
        sys.exit('Szablon nie ma tabeli %s — zly plik?' % t)

for katalog in sys.argv[1:]:
    gpkgi = sorted(glob.glob(os.path.join(katalog, '*.gpkg')))
    cel, braki = None, []
    for g in gpkgi:
        if os.path.basename(g) == 'foto_tagi.gpkg' or '.bak_' in g:
            continue
        con = sqlite3.connect('file:%s?mode=ro' % g, uri=True)
        tab = {r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        con.close()
        if 'SLOWNIK_GATUNKOW' in tab:
            cel = g
            braki = [t for t in TABELE if t not in tab]
            break
    if cel is None:
        # projekt bez slownika w ogole: celem jest dane.gpkg
        kandydat = os.path.join(katalog, 'dane.gpkg')
        if os.path.exists(kandydat):
            cel, braki = kandydat, list(TABELE)
        else:
            print('%s: brak dane.gpkg — pomijam' % katalog)
            continue
    if not braki:
        print('%s: %s ma juz komplet tabel — nic do zrobienia'
              % (katalog, os.path.basename(cel)))
        continue

    znacznik = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    kopia = cel + '.bak_' + znacznik
    shutil.copy2(cel, kopia)
    print('%s: kopia zapasowa -> %s' % (katalog, os.path.basename(kopia)))

    con = sqlite3.connect(cel)
    con.execute("ATTACH DATABASE ? AS tpl", (SZABLON,))
    for t in braki:
        con.execute('CREATE TABLE "%s" AS SELECT * FROM tpl."%s"' % (t, t))
        n = con.execute('SELECT count(*) FROM "%s"' % t).fetchone()[0]
        # rejestracja w gpkg_contents (tabela atrybutowa, bez geometrii)
        con.execute(
            "INSERT OR REPLACE INTO gpkg_contents "
            "(table_name, data_type, identifier, description, last_change) "
            "VALUES (?, 'attributes', ?, 'WorkField: wskazniki gatunkow', "
            "strftime('%Y-%m-%dT%H:%M:%fZ','now'))", (t, t))
        print('   + %s (%d wierszy)' % (t, n))
    con.commit()
    con.execute("DETACH DATABASE tpl")
    con.close()
    print('%s: GOTOWE' % katalog)
