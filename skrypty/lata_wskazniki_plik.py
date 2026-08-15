#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# WorkField: speciesMeta preferuje wolnostojacy plik wf_wskazniki.gpkg
# w katalogu projektu + odporna drabinka zapytan SQL.
import io, os, sys
REPO = os.environ.get('WF_REPO', '/DATA/SOFT/GIS/QFIELD_Pro/QField')
os.chdir(REPO)
p = 'src/core/phototagstore.cpp'
s = io.open(p, encoding='utf-8').read()
if 'wf_wskazniki.gpkg' in s:
    sys.exit("Juz jest - nic do zrobienia.")
stare = """    mMetaSearched = true;
    const QStringList gpkgs = QDir( mProjectDir ).entryList( QStringList() << QStringLiteral( "*.gpkg" ), QDir::Files );"""
nowe = """    mMetaSearched = true;
    // najpierw samodzielny plik wskaznikow (dystrybucja np. przez NextCloud:
    // wystarczy polozyc go w katalogu projektu, bez zmian w dane.gpkg)
    const QString wolny = QDir( mProjectDir ).filePath( QStringLiteral( "wf_wskazniki.gpkg" ) );
    if ( QFileInfo::exists( wolny ) )
      mMetaGpkg = wolny;
    const QStringList gpkgs = QDir( mProjectDir ).entryList( QStringList() << QStringLiteral( "*.gpkg" ), QDir::Files );"""
if s.count(stare) != 1:
    sys.exit("STOP: kotwica 1 != 1 - NIC nie zmieniono")
s = s.replace(stare, nowe)
stare2 = """    for ( const QString &name : gpkgs )
    {
      if ( name == QLatin1String( "foto_tagi.gpkg" ) )
        continue;"""
nowe2 = """    for ( const QString &name : gpkgs )
    {
      if ( !mMetaGpkg.isEmpty() )
        break;
      if ( name == QLatin1String( "foto_tagi.gpkg" ) )
        continue;"""
if s.count(stare2) != 1:
    sys.exit("STOP: kotwica 2 != 1 - NIC nie zmieniono")
s = s.replace(stare2, nowe2)
stare3 = """  sqlite3_stmt *st = nullptr;
  if ( sqlite3_prepare_v2( db, maWsk ? sqlPelny : sqlProsty, -1, &st, nullptr ) != SQLITE_OK )
  {
    // zapasowo (np. slownik bez kolumny ETYKIETA)
    if ( st )
      sqlite3_finalize( st );
    st = nullptr;
    if ( sqlite3_prepare_v2( db, sqlProsty, -1, &st, nullptr ) != SQLITE_OK )
    {
      if ( st )
        sqlite3_finalize( st );
      sqlite3_close( db );
      return meta;
    }
  }"""
nowe3 = """  const char *sqlPelnyBezEtykiety = "SELECT s.*, w.zrodlo_eiv AS EIV_ZRODLO, w.L AS EIV_L, w.T AS EIV_T, w.M AS EIV_M, w.R AS EIV_R, w.N AS EIV_N, w.S AS EIV_S,"
                                    " w.zrodlo_zab AS ZAB_ZRODLO, w.\\"Disturbance.Severity\\" AS ZAB_SEVERITY, w.\\"Disturbance.Frequency\\" AS ZAB_FREQUENCY,"
                                    " w.\\"Mowing.Frequency\\" AS ZAB_MOWING, w.\\"Grazing.Pressure\\" AS ZAB_GRAZING, w.\\"Soil.Disturbance\\" AS ZAB_SOIL"
                                    " FROM SLOWNIK_GATUNKOW s LEFT JOIN wskazniki_polaczone w ON lower(trim(w.takson)) = lower(trim(s.GATUNEK))"
                                    " WHERE lower(trim(s.GATUNEK)) = ?1 LIMIT 1";
  sqlite3_stmt *st = nullptr;
  const char *drabinka[3] = { maWsk ? sqlPelny : sqlProsty, maWsk ? sqlPelnyBezEtykiety : sqlProsty, sqlProsty };
  for ( int i = 0; i < 3; i++ )
  {
    if ( sqlite3_prepare_v2( db, drabinka[i], -1, &st, nullptr ) == SQLITE_OK )
      break;
    if ( st )
      sqlite3_finalize( st );
    st = nullptr;
  }
  if ( !st )
  {
    sqlite3_close( db );
    return meta;
  }"""
if s.count(stare3) != 1:
    sys.exit("STOP: kotwica 3 != 1 - NIC nie zmieniono")
s = s.replace(stare3, nowe3)
assert s.count('{') == s.count('}')
io.open(p, 'w', encoding='utf-8').write(s)
print("OK: wf_wskazniki.gpkg preferowany + drabinka zapytan")
