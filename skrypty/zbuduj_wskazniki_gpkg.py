#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Buduje wolnostojacy plik wf_wskazniki.gpkg (SLOWNIK_GATUNKOW + taksony +
wskazniki_polaczone) z szablonu ZZW — do dystrybucji np. przez NextCloud.
Plik kladzie sie w katalogu projektu; WorkField czyta go automatycznie.

UZYCIE:  python3 zbuduj_wskazniki_gpkg.py [WYJSCIE.gpkg]
Domyslne wyjscie: ./wf_wskazniki.gpkg
Szablon: /DATA/WorkField/szablony/szablon_inw_zzw/dane.gpkg (SZABLON_GPKG)
"""
import os, sys, shutil, sqlite3

SZABLON = os.environ.get('SZABLON_GPKG',
                         '/DATA/WorkField/szablony/szablon_inw_zzw/dane.gpkg')
WY = sys.argv[1] if len(sys.argv) > 1 else 'wf_wskazniki.gpkg'
KEEP = {'SLOWNIK_GATUNKOW', 'taksony', 'wskazniki_polaczone'}
GPKG_CORE = {'gpkg_contents', 'gpkg_spatial_ref_sys', 'gpkg_geometry_columns',
             'gpkg_extensions', 'gpkg_tile_matrix', 'gpkg_tile_matrix_set',
             'gpkg_ogr_contents', 'sqlite_sequence'}

if not os.path.exists(SZABLON):
    sys.exit('Brak szablonu: %s' % SZABLON)
shutil.copy(SZABLON, WY)
con = sqlite3.connect(WY)
tab = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")]
for t in KEEP:
    if t not in tab:
        sys.exit('Szablon nie ma tabeli %s' % t)
# widoki precz (moga zalezec od usuwanych tabel)
for (v,) in con.execute("SELECT name FROM sqlite_master WHERE type='view'").fetchall():
    con.execute('DROP VIEW IF EXISTS "%s"' % v)
for t in tab:
    if t in KEEP or t in GPKG_CORE:
        continue
    con.execute('DROP TABLE IF EXISTS "%s"' % t)
for reg in ['gpkg_contents', 'gpkg_geometry_columns', 'gpkg_ogr_contents']:
    try:
        con.execute('DELETE FROM %s WHERE table_name NOT IN (%s)'
                    % (reg, ','.join('?' * len(KEEP))), tuple(KEEP))
    except sqlite3.OperationalError:
        pass
try:
    con.execute("DELETE FROM gpkg_extensions WHERE table_name IS NOT NULL "
                "AND table_name NOT IN (%s)" % ','.join('?' * len(KEEP)), tuple(KEEP))
except sqlite3.OperationalError:
    pass
for t in KEEP:
    con.execute(
        "INSERT OR REPLACE INTO gpkg_contents "
        "(table_name, data_type, identifier, description, last_change) "
        "VALUES (?, 'attributes', ?, 'WorkField: wskazniki gatunkow', "
        "strftime('%Y-%m-%dT%H:%M:%fZ','now'))", (t, t))
con.commit()
con.execute('VACUUM')
for t in sorted(KEEP):
    print('%-22s %d wierszy' % (t, con.execute('SELECT count(*) FROM "%s"' % t).fetchone()[0]))
con.close()
print('Zapisano: %s (%.1f MB)' % (WY, os.path.getsize(WY) / 1048576))
