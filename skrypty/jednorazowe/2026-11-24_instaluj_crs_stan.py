#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-CRS-STATE] stan projektu: brak układu i stopnie w warstwie metrycznej.

NarzedziaProjektu::stanProjektu() dostaje dwa sprawdzenia (claude/WSKAZOWKA_crs_projektu_
zabezpieczenia_2026-11-24.md, punkt 2): projekt bez układu współrzędnych oraz warstwa z pliku
danych w układzie metrycznym, której zasięg leży w zakresie stopni i poza obszarem układu.
Oba jako ostrzeżenia rodzaju „dane” (plakietka kontroli przy wczytaniu, okno naprawy). Brak
układu idzie na początek listy z czasownikiem „ustaw_uklad” i układem z pierwszej metrycznej
warstwy danych. Tylko odczyt: układ projektu i extent() dostawcy, bez czytania obiektów.
Para z 2026-11-24_instaluj_crs_naprawa.py (QfNaprawaProjektu.qml).

Użycie (z katalogu repozytorium):
  python3 instaluj_crs_stan.py            # próba, nic nie zapisuje
  python3 instaluj_crs_stan.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_crs_stan.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp'
MD5_PRZED = '048288804022368ec36ff6f31b9a2cda'  # commit c5ad7a491 (łatki A i B)
MD5_PO = '3e99f07fadb6df53f207dd8ca3d897c3'

ZMIANY = [
    ('#include <qgsmessagelog.h>  // [WF-PERF]\n',
     '#include <qgsmessagelog.h>  // [WF-PERF]\n#include <cmath>                     // [WF-CRS-STATE]\n#include <qgscoordinatetransform.h>  // [WF-CRS-STATE]\n#include <qgsexception.h>            // [WF-CRS-STATE]\n'),
    ('Q_LOGGING_CATEGORY( wfgPerformance, "workfield.performance", QtWarningMsg )\n',
     'Q_LOGGING_CATEGORY( wfgPerformance, "workfield.performance", QtWarningMsg )\nQ_LOGGING_CATEGORY( wfgCrs, "workfield.crs", QtWarningMsg ) // [WF-CRS-STATE]\n'),
    ('\n  // --------------------------------------------------------------- pomiar\n',
     '\n  // ---------------------------------------------------- układ współrzędnych\n  // WorkFieldGIS 24.11.2026 — [WF-CRS-STATE] projekt bez układu i stopnie\n  // w warstwie metrycznej (claude/DIAGNOZA_SOLTYKA_CZWARTEK_pusty_CRS_2026-11-24.md).\n  // Projekt SOŁTYKA CZWARTEK miał pusty <projectCrs>: pozycja GNSS nie była\n  // przeliczana i do warstwy EPSG:2178 trafiły stopnie WGS84, bez żadnego\n  // ostrzeżenia. Oba sprawdzenia są tanie: układ projektu i extent() dostawcy\n  // (bez czytania obiektów), tylko warstwy z pliku danych jak skan wyżej.\n  // Rodzaj "dane": wpis trafia do plakietki kontroli przy wczytaniu projektu.\n  const QgsCoordinateReferenceSystem projectCrs = projekt->crs();\n  const bool projectCrsInvalid = !projectCrs.isValid();\n  QString suggestedCrs;\n  QString suggestedFrom;\n  QStringList degreesLayers;\n  for ( auto it = mapaWarstw.constBegin(); it != mapaWarstw.constEnd(); ++it )\n  {\n    QgsVectorLayer *layer = qobject_cast<QgsVectorLayer *>( it.value() );\n    if ( !layer || !layer->isSpatial() || !layer->crs().isValid() )\n      continue;\n    if ( !scanFile.isEmpty() && identityFilePath( layer ) != scanFile )\n      continue;\n    const QgsCoordinateReferenceSystem layerCrs = layer->crs();\n    if ( layerCrs.isGeographic() )\n      continue;\n    if ( suggestedCrs.isEmpty() )\n    {\n      suggestedCrs = layerCrs.authid();\n      suggestedFrom = layer->name();\n    }\n    const QgsRectangle extent = layer->extent();\n    if ( extent.isNull() )\n      continue;\n    const bool degreeRange = std::fabs( extent.xMinimum() ) <= 180.0 && std::fabs( extent.xMaximum() ) <= 180.0\n                             && std::fabs( extent.yMinimum() ) <= 90.0 && std::fabs( extent.yMaximum() ) <= 90.0;\n    if ( !degreeRange )\n      continue;\n    // Tylko gdy takie liczby leżą POZA obszarem stosowania układu: lokalna\n    // siatka metryczna może mieć współrzędne bliskie zera i jest w porządku.\n    const QgsRectangle bounds = layerCrs.bounds();\n    if ( bounds.isNull() )\n      continue;\n    bool outsideArea = true;\n    try\n    {\n      const QgsCoordinateTransform toLayer( QgsCoordinateReferenceSystem( QStringLiteral( "EPSG:4326" ) ), layerCrs, projekt->transformContext() );\n      outsideArea = !toLayer.transformBoundingBox( bounds ).contains( extent.center() );\n    }\n    catch ( QgsCsException & )\n    {\n      outsideArea = true;\n    }\n    if ( !outsideArea )\n      continue;\n    degreesLayers << layer->name();\n    ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),\n             tr( "„%1”: współrzędne wyglądają na stopnie (x %2…%3, y %4…%5), a warstwa jest w układzie metrycznym %6 — obiekty leżą w złym miejscu" )\n               .arg( layer->name() )\n               .arg( extent.xMinimum(), 0, \'f\', 4 )\n               .arg( extent.xMaximum(), 0, \'f\', 4 )\n               .arg( extent.yMinimum(), 0, \'f\', 4 )\n               .arg( extent.yMaximum(), 0, \'f\', 4 )\n               .arg( layerCrs.authid() ),\n             tr( "Nie dodawaj obiektów do tej warstwy. Dane trzeba przeliczyć w biurze — "\n                 "na telefonie ich nie poprawiamy. Oddaj projekt do biura w takim stanie, w jakim jest." ),\n             QString(), 0.0, QString(), layer->name() );\n    qCWarning( wfgCrs, "WorkField [WF-CRS-STATE]: stopnie w warstwie metrycznej %s (%s)",\n               qPrintable( layer->name() ), qPrintable( layerCrs.authid() ) );\n  }\n  if ( projectCrsInvalid )\n  {\n    ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),\n             tr( "Projekt nie ma układu współrzędnych — pozycja GNSS nie jest przeliczana i do warstw trafiają stopnie zamiast metrów" ),\n             suggestedCrs.isEmpty()\n               ? tr( "Ustaw układ projektu w zakładce Projekt (Układ współrzędnych) i otwórz projekt ponownie. Do tego czasu nie mierz." )\n               : tr( "Naciśnij „Ustaw %1”: układ zostanie wzięty z warstwy „%2”, a projekt zapisany. "\n                     "Potem otwórz projekt ponownie. Do tego czasu nie mierz." )\n                   .arg( suggestedCrs, suggestedFrom ),\n             suggestedCrs.isEmpty() ? QString() : QStringLiteral( "ustaw_uklad" ),\n             0.0, QString(), suggestedFrom );\n    // Układ do ustawienia jedzie przy wpisie; wpis idzie na początek listy,\n    // bo bez układu reszta ostrzeżeń jest drugorzędna.\n    QVariantMap crsWarning = ostrzezenia.takeLast().toMap();\n    if ( !suggestedCrs.isEmpty() )\n      crsWarning.insert( QStringLiteral( "uklad" ), suggestedCrs );\n    ostrzezenia.prepend( crsWarning );\n    qCWarning( wfgCrs, "WorkField [WF-CRS-STATE]: projekt bez układu współrzędnych; propozycja %s z warstwy %s",\n               qPrintable( suggestedCrs ), qPrintable( suggestedFrom ) );\n  }\n  wynik.insert( QStringLiteral( "projectCrs" ), projectCrs.authid() );\n  wynik.insert( QStringLiteral( "projectCrsInvalid" ), projectCrsInvalid );\n  wynik.insert( QStringLiteral( "degreesInProjectedLayer" ), degreesLayers );\n\n  // --------------------------------------------------------------- pomiar\n'),
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
