#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-CRS-BLANK] pusty projekt zawsze z układem współrzędnych.

Źródło usterki SOŁTYKA CZWARTEK (claude/DIAGNOZA_SOLTYKA_CZWARTEK_pusty_CRS_2026-11-24.md).
QfAppInterface::createBlankProject() robiło QgsProject::clear() i od razu zapis. clear()
zeruje układ projektu, więc projekt bez szablonu z okien „Nowe zlecenie” (QfNoweZadanie) i
„Nowy projekt w zleceniu” (QfNowyProjekt) zapisywał się z pustym <projectCrs>. Tylko okno
„Nowy projekt” w szufladzie ustawiało układ po wczytaniu. Teraz pusty projekt dostaje układ
domyślny (Ustawienia → workfield/domyslnyUklad, inaczej EPSG:2178) jeszcze przed zapisem.

Użycie (z katalogu repozytorium):
  python3 instaluj_crs_pusty_projekt.py            # próba, nic nie zapisuje
  python3 instaluj_crs_pusty_projekt.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_crs_pusty_projekt.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/qfappinterface.cpp'
MD5_PRZED = '8e57325700f242621701093324a9fcfb'  # GitHub development 9f2ab088b
MD5_PO = 'd04e8a8d2b351a31d82bcddd2ba71276'

ZMIANY = [
    ('bool QfAppInterface::createBlankProject( const QString &path )\n{\n  QgsProject::instance()->clear();\n  return QgsProject::instance()->write( path );\n}\n',
     'bool QfAppInterface::createBlankProject( const QString &path )\n{\n  QgsProject::instance()->clear();\n  // WorkFieldGIS 24.11.2026 — [WF-CRS-BLANK] clear() zostawia projekt BEZ układu współrzędnych\n  // (QgsProject::clear: mCrs = pusty). Tak powstał projekt SOŁTYKA CZWARTEK: pozycje GNSS nie\n  // były przeliczane i do warstwy EPSG:2178 trafiły stopnie WGS84\n  // (claude/DIAGNOZA_SOLTYKA_CZWARTEK_pusty_CRS_2026-11-24.md). Pusty projekt dostaje układ\n  // domyślny (Ustawienia, inaczej EPSG:2178). Okno „Nowy projekt” z szuflady i tak ustawia\n  // potem układ wybrany przez człowieka.\n  const QgsCoordinateReferenceSystem crs( domyslnyUklad() );\n  QgsProject::instance()->setCrs( crs );\n  qInfo() << "WorkField [WF-CRS-BLANK]: nowy pusty projekt" << path << "układ" << crs.authid();\n  return QgsProject::instance()->write( path );\n}\n'),
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
