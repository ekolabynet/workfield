#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-SCAN-GEOMETRY] stanProjektu() czyta same geometrie.

Skan pustych i zwiniętych geometrii w stanProjektu() czytał wszystkie atrybuty
każdego obiektu, choć potrzebuje tylko kształtu. Teraz żądanie ma
setNoAttributes(). Wynik i ostrzeżenia bez zmian. Pierwsza z trzech łatek
(A: bez atrybutów, B: tylko plik danych, C: liczenie raz, nie przy każdym menu).

Użycie (z katalogu repozytorium):
  python3 instaluj_skan_bez_atrybutow.py            # próba, nic nie zapisuje
  python3 instaluj_skan_bez_atrybutow.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_skan_bez_atrybutow.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp"
MD5_PRZED = "9b592a956b3a2ac8cd5df7c5eeefb85c"  # po łatce [WF-PERF] (2026-11-24_instaluj_pomiar_stanu_projektu.py)
MD5_PO = "0128b9492ad364400e03c7eb4e8428da"

ZMIANY = [
    ('      QgsFeature obiekt;\n      QgsFeatureIterator iterator = wektor->getFeatures();\n',
     '      QgsFeature obiekt;\n      // WorkFieldGIS 24.11.2026 — [WF-SCAN-GEOMETRY] tylko geometria: skan szuka\n      // pustych i zwiniętych kształtów, żadnego atrybutu nie potrzebuje.\n      QgsFeatureRequest geometryOnly;\n      geometryOnly.setNoAttributes();\n      QgsFeatureIterator iterator = wektor->getFeatures( geometryOnly );\n'),
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
