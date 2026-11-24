#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-SCAN-SCOPE] skan geometrii tylko w pliku danych projektu.

Puste i zwinięte geometrie są szukane już tylko w pliku danych projektu
(data.gpkg / dane.gpkg / GeoPackage z największą liczbą warstw — jak
plikDanych()). Wyniki analiz z biura i podkłady wypadają ze skanu. Zgoda
Piotra 24.11.2026 13:09. Linijka [WF-PERF] podaje teraz też, ile warstw
poligonowych pominięto. Projekt bez pliku danych: skan wszystkiego, jak dotąd.

Użycie (z katalogu repozytorium):
  python3 instaluj_skan_tylko_dane.py            # próba, nic nie zapisuje
  python3 instaluj_skan_tylko_dane.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_skan_tylko_dane.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp"
MD5_PRZED = "0128b9492ad364400e03c7eb4e8428da"  # po łatce A (instaluj_skan_bez_atrybutow.py)
MD5_PO = "048288804022368ec36ff6f31b9a2cda"

ZMIANY = [
    ('  qlonglong collapsedFid = -1;\n\n  const auto mapaWarstw = projekt->mapLayers();\n',
     '  qlonglong collapsedFid = -1;\n\n  // WorkFieldGIS 24.11.2026 — [WF-SCAN-SCOPE] puste i zwinięte geometrie\n  // szukamy tylko w pliku danych projektu (ten sam, który wskazuje\n  // plikDanych(): data.gpkg, dane.gpkg, inaczej GeoPackage z największą\n  // liczbą warstw). Pomiar 24.11 na projekcie ZZW (laptop): 29 432 obiektów,\n  // ok. 127 ms przy KAŻDYM otwarciu menu, z czego ok. 75% to wyniki analiz\n  // z biura (korony, klasy wysokości PGRS_0.4) — w nich nic nie powstaje\n  // w terenie. Projekt bez pliku danych: skan jak dotąd, wszystkich warstw.\n  // Najmniejszy obiekt (próg przyciągania) liczy się teraz z danych terenowych.\n  const QString scanFile = [&]() {\n    const QString path = plikDanych( projekt );\n    if ( path.isEmpty() )\n      return QString();\n    const QFileInfo info( path );\n    return info.exists() ? info.canonicalFilePath() : info.absoluteFilePath();\n  }();\n  int skippedLayers = 0;\n\n  const auto mapaWarstw = projekt->mapLayers();\n'),
    ('\n    if ( wektor->geometryType() == Qgis::GeometryType::Polygon )\n    {\n      int puste = 0;\n',
     '\n    const bool scanThisLayer = scanFile.isEmpty() || identityFilePath( wektor ) == scanFile; // [WF-SCAN-SCOPE]\n    if ( wektor->geometryType() == Qgis::GeometryType::Polygon && !scanThisLayer )\n    {\n      ++skippedLayers;\n      qCDebug( wfgPerformance, "WorkField/Wydajnosc: stanProjektu pominieta (poza plikiem danych) %s", qPrintable( wektor->name() ) );\n    }\n    if ( wektor->geometryType() == Qgis::GeometryType::Polygon && scanThisLayer )\n    {\n      int puste = 0;\n'),
    ('"identyfikatory %5 ms, reszta %6 ms%7" )',
     '"identyfikatory %5 ms, reszta %6 ms, pominięte warstwy poza plikiem danych: %7%8" )'),
    ('\n                           .arg( totalMs - polygonScanMs - identityMs )\n',
     '\n                           .arg( totalMs - polygonScanMs - identityMs )\n                           .arg( skippedLayers )\n'),
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
