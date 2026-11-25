#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-CRS-REPROJECT] przeliczenie warstwy ze stopni WGS84 na jej układ (funkcja).

Decyzja Piotra 24.11: naprawa dostępna na telefonie, żeby złe dane nie szły dalej. Trzy
instalatory razem: narzedziaprojektu.h (deklaracja), narzedziaprojektu.cpp (funkcja
reprojectDegreesLayer i czasownik „przelicz_stopnie” przy ostrzeżeniu o stopniach),
QfNaprawaProjektu.qml (przycisk „Przelicz na EPSG:xxxx”, dwa naciśnięcia). Wszystko albo nic,
migawka bazy w „kopie” przed zmianą, jedna sesja edycji z dziennikiem WF_JOURNAL.

Użycie (z katalogu repozytorium):
  python3 instaluj_crs_przelicz_cpp.py            # próba, nic nie zapisuje
  python3 instaluj_crs_przelicz_cpp.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_crs_przelicz_cpp.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp'
MD5_PRZED = '3e99f07fadb6df53f207dd8ca3d897c3'  # po 2026-11-24_instaluj_crs_stan.py
MD5_PO = '45da26ad54c3d936af886cc7630db6ad'

ZMIANY = [
    ('             tr( "Nie dodawaj obiektów do tej warstwy. Dane trzeba przeliczyć w biurze — "\n                 "na telefonie ich nie poprawiamy. Oddaj projekt do biura w takim stanie, w jakim jest." ),\n             QString(), 0.0, QString(), layer->name() );\n',
     '             tr( "Nie dodawaj obiektów do tej warstwy, dopóki jej nie przeliczysz. Naciśnij „Przelicz na %1”: "\n                 "obiekty zostaną przeliczone ze stopni WGS84, a przedtem powstanie kopia bazy w katalogu „kopie”. "\n                 "Jeśli projekt nie ma układu, najpierw ustaw układ (pierwsze ostrzeżenie)." )\n               .arg( layerCrs.authid() ),\n             QStringLiteral( "przelicz_stopnie" ), 0.0, QString(), layer->name() );\n    {\n      // [WF-CRS-REPROJECT] układ warstwy jedzie przy wpisie — na przycisk\n      QVariantMap degreesWarning = ostrzezenia.takeLast().toMap();\n      degreesWarning.insert( QStringLiteral( "uklad" ), layerCrs.authid() );\n      ostrzezenia.append( degreesWarning );\n    }\n'),
    ('QString NarzedziaProjektu::kopiaZapasowa( const QString &sciezka ) const\n',
     '// WorkFieldGIS 24.11.2026 — [WF-CRS-REPROJECT] przeliczenie warstwy ze stopni WGS84\n// na jej układ metryczny (claude/DIAGNOZA_SOLTYKA_CZWARTEK_pusty_CRS_2026-11-24.md).\n// Decyzja Piotra 24.11: czasownik ma być na telefonie, żeby złe dane nie szły dalej\n// (kopie, eksport CAD, zwrot). Bezpieczniki: wszystko albo nic, migawka bazy przed\n// zmianą, jedna sesja edycji z dziennikiem, sprawdzenie obszaru układu po przeliczeniu.\nQVariantMap NarzedziaProjektu::reprojectDegreesLayer( QgsProject *project, const QString &layerName )\n{\n  QVariantMap result;\n  result.insert( QStringLiteral( "ok" ), false );\n  const auto fail = [&result]( const QString &text ) {\n    result.insert( QStringLiteral( "opis" ), text );\n    qCWarning( wfgCrs, "WorkField [WF-CRS-REPROJECT]: %s", qPrintable( text ) );\n    return result;\n  };\n\n  if ( !project )\n    return fail( tr( "Nie ma otwartego projektu." ) );\n  if ( !project->crs().isValid() )\n    return fail( tr( "Najpierw ustaw układ projektu (przycisk przy pierwszym ostrzeżeniu). "\n                     "Bez niego nowe punkty dalej trafiałyby w stopniach." ) );\n  QgsVectorLayer *layer = znajdzWarstwe( project, layerName );\n  if ( !layer || !layer->isSpatial() )\n    return fail( tr( "Nie ma w projekcie warstwy „%1”." ).arg( layerName ) );\n  const QgsCoordinateReferenceSystem layerCrs = layer->crs();\n  if ( !layerCrs.isValid() || layerCrs.isGeographic() )\n    return fail( tr( "Warstwa „%1” nie jest w układzie metrycznym — nie ma czego przeliczać." ).arg( layer->name() ) );\n  if ( layer->isEditable() && layer->isModified() )\n    return fail( tr( "Warstwa „%1” ma niezapisane zmiany. Zapisz je albo odrzuć i spróbuj jeszcze raz." ).arg( layer->name() ) );\n  const QString gpkg = JournalUtils::gpkgPath( layer );\n  if ( gpkg.isEmpty() )\n    return fail( tr( "Warstwa „%1” nie leży w GeoPackage — tego nie przeliczam." ).arg( layer->name() ) );\n\n  // 1. Wszystko albo nic: najpierw liczymy w pamięci i sprawdzamy KAŻDY obiekt.\n  QgsCoordinateTransform toLayer;\n  QgsRectangle area;\n  try\n  {\n    toLayer = QgsCoordinateTransform( QgsCoordinateReferenceSystem( QStringLiteral( "EPSG:4326" ) ), layerCrs, project->transformContext() );\n    area = toLayer.transformBoundingBox( layerCrs.bounds() );\n  }\n  catch ( QgsCsException & )\n  {\n    area = QgsRectangle();\n  }\n  if ( area.isNull() )\n    return fail( tr( "Nie znam obszaru układu %1, więc nie umiem sprawdzić wyniku. Nic nie zmieniłem." ).arg( layerCrs.authid() ) );\n\n  QHash<QgsFeatureId, QgsGeometry> converted;\n  int skipped = 0;\n  QgsFeatureRequest request;\n  request.setNoAttributes();\n  QgsFeatureIterator iterator = layer->getFeatures( request );\n  QgsFeature feature;\n  while ( iterator.nextFeature( feature ) )\n  {\n    QgsGeometry geometry = feature.geometry();\n    if ( geometry.isNull() || geometry.isEmpty() )\n    {\n      ++skipped;\n      continue;\n    }\n    const QgsRectangle box = geometry.boundingBox();\n    if ( std::fabs( box.xMinimum() ) > 180.0 || std::fabs( box.xMaximum() ) > 180.0\n         || std::fabs( box.yMinimum() ) > 90.0 || std::fabs( box.yMaximum() ) > 90.0 )\n      return fail( tr( "Obiekt fid %1 w warstwie „%2” nie jest w stopniach — warstwa jest mieszana. "\n                       "Nic nie zmieniłem; to trzeba rozdzielić w biurze." )\n                     .arg( feature.id() )\n                     .arg( layer->name() ) );\n    try\n    {\n      if ( geometry.transform( toLayer ) != Qgis::GeometryOperationResult::Success )\n        return fail( tr( "Nie udało się przeliczyć obiektu fid %1. Nic nie zmieniłem." ).arg( feature.id() ) );\n    }\n    catch ( QgsCsException & )\n    {\n      return fail( tr( "Nie udało się przeliczyć obiektu fid %1. Nic nie zmieniłem." ).arg( feature.id() ) );\n    }\n    if ( !area.contains( geometry.boundingBox().center() ) )\n      return fail( tr( "Obiekt fid %1 po przeliczeniu wypada poza obszar układu %2. Nic nie zmieniłem." )\n                     .arg( feature.id() )\n                     .arg( layerCrs.authid() ) );\n    converted.insert( feature.id(), geometry );\n  }\n  if ( converted.isEmpty() )\n    return fail( tr( "W warstwie „%1” nie ma czego przeliczać." ).arg( layer->name() ) );\n\n  // 2. Migawka bazy PRZED zmianą: dziennik WAL do pliku, kopia, quick_check na kopii.\n  const QVariantMap snapshot = migawkaBazy( gpkg, QFileInfo( gpkg ).absolutePath() + QStringLiteral( "/kopie" ) );\n  if ( !snapshot.value( QStringLiteral( "ok" ) ).toBool() )\n    return fail( tr( "Nie udało się zrobić kopii bazy przed przeliczeniem (%1). Nic nie zmieniłem." )\n                   .arg( snapshot.value( QStringLiteral( "blad" ) ).toString() ) );\n\n  // 3. Jedna sesja edycji: wyzwalacze WF_JOURNAL zapisują stare geometrie, a\n  //    zasięg w gpkg_contents i indeks przestrzenny odświeża dostawca (sprawdzone\n  //    24.11 na QGIS 3.34 / GDAL 3.8).\n  const bool wasEditable = layer->isEditable();\n  if ( !wasEditable && !layer->startEditing() )\n    return fail( tr( "Warstwy „%1” nie da się edytować. Nic nie zmieniłem." ).arg( layer->name() ) );\n  {\n    JournalUtils::OperationScope journalScope( layer, QStringLiteral( "reproject_degrees" ), layerCrs.authid() );\n    for ( auto it = converted.constBegin(); it != converted.constEnd(); ++it )\n    {\n      if ( !layer->changeGeometry( it.key(), it.value() ) )\n      {\n        layer->rollBack( !wasEditable );\n        return fail( tr( "Nie udało się zmienić obiektu fid %1. Nic nie zapisałem." ).arg( it.key() ) );\n      }\n    }\n    if ( !layer->commitChanges( !wasEditable ) )\n    {\n      const QString errors = layer->commitErrors().join( QStringLiteral( "; " ) );\n      layer->rollBack( !wasEditable );\n      return fail( tr( "Zapis się nie udał: %1. Kopia bazy sprzed próby: %2" )\n                     .arg( errors, snapshot.value( QStringLiteral( "sciezka" ) ).toString() ) );\n    }\n  }\n  layer->updateExtents( true );\n  layer->triggerRepaint();\n\n  QString text = tr( "Przeliczyłem %1 obiektów warstwy „%2” ze stopni WGS84 na %3. Kopia bazy sprzed zmiany: kopie/%4." )\n                   .arg( converted.size() )\n                   .arg( layer->name(), layerCrs.authid(), snapshot.value( QStringLiteral( "nazwa" ) ).toString() );\n  if ( skipped > 0 )\n    text += QLatin1Char( \' \' ) + tr( "Bez geometrii, pominięte: %1." ).arg( skipped );\n  result.insert( QStringLiteral( "ok" ), true );\n  result.insert( QStringLiteral( "opis" ), text );\n  result.insert( QStringLiteral( "przeliczone" ), converted.size() );\n  result.insert( QStringLiteral( "kopia" ), snapshot.value( QStringLiteral( "sciezka" ) ) );\n  qCWarning( wfgCrs, "WorkField [WF-CRS-REPROJECT]: %s", qPrintable( text ) );\n  return result;\n}\n\nQString NarzedziaProjektu::kopiaZapasowa( const QString &sciezka ) const\n'),
]


def md5(dane):
    return hashlib.md5(dane).hexdigest()


def main():
    argv = sys.argv[1:]
    zapisz = "--zapisz" in argv
    plik = PLIK
    if "--plik" in argv:
        plik = argv[argv.index("--plik") + 1]

    with open(plik, "rb") as f:
        surowe = f.read()
    teraz = md5(surowe)
    print("plik:", plik)
    print("md5 :", teraz)

    if teraz == MD5_PO:
        print("JUŻ ZAINSTALOWANE — nic nie zmieniam.")
        return 0
    if teraz != MD5_PRZED:
        print("STOP: md5 inne niż oczekiwane", MD5_PRZED)
        print("Plik różni się od wersji, na której zbudowano łatkę. Nie nadpisuję cudzej pracy.")
        print("Przyślij ten plik, zbuduję instalator na jego bajtach.")
        return 1

    tekst = surowe.decode("utf-8")
    for nr, (stare, _nowe) in enumerate(ZMIANY, 1):
        ile = tekst.count(stare)
        if ile != 1:
            print("STOP: kotwica %d występuje %d razy (ma być 1). Nic nie zapisano." % (nr, ile))
            return 1
    for stare, nowe in ZMIANY:
        tekst = tekst.replace(stare, nowe, 1)

    nowe_bajty = tekst.encode("utf-8")
    print("po zmianie md5:", md5(nowe_bajty))
    linie_przed = surowe.count(b"\n")
    linie_po = nowe_bajty.count(b"\n")
    print("linie: %d -> %d (+%d)" % (linie_przed, linie_po, linie_po - linie_przed))

    if not zapisz:
        print("PRÓBA — nic nie zapisano. Zapis: dopisz --zapisz")
        return 0

    kopia = plik + ".przed_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    nr = 1
    while os.path.exists(kopia):  # dwie łatki w tej samej sekundzie
        nr += 1
        kopia = plik + ".przed_" + datetime.now().strftime("%Y%m%d_%H%M%S") + "_%d" % nr
    shutil.copy2(plik, kopia)
    with open(plik, "wb") as f:
        f.write(nowe_bajty)
    print("ZAPISANO. Kopia:", kopia)
    return 0


if __name__ == "__main__":
    sys.exit(main())
