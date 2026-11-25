#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-CRS-STATE] bez ostrzeżenia o układzie dla pustego projektu.

Log z 24.11 20:20: przy starcie aplikacji (nic nie wczytane) stanProjektu() pisało „projekt bez
układu współrzędnych; propozycja  z warstwy ”. Pusty QgsProject nie ma układu z natury. Teraz
ostrzeżenie tylko dla projektu z plikiem i z warstwami.

Użycie (z katalogu repozytorium):
  python3 instaluj_crs_pusty_bez_ostrzezenia.py            # próba, nic nie zapisuje
  python3 instaluj_crs_pusty_bez_ostrzezenia.py --zapisz   # zapis (z kopią .przed_*)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp'
MD5_PRZED = 'f256befa55d2c0c5efd7878724deb5b5'  # po 2026-11-24_instaluj_crs_przelicz_cpp_popr.py
MD5_PO = 'df7d53cce7630a52039e643ec306e999'

ZMIANY = [
    ('  const bool projectCrsInvalid = !projectCrs.isValid();\n',
     '  // Pusty projekt (start aplikacji, nic nie wczytane) też nie ma układu — to nie\n  // usterka i nie ma czego mierzyć. Ostrzegamy tylko projekt z pliku i z warstwami.\n  const bool projectCrsInvalid = !projectCrs.isValid() && !projekt->fileName().isEmpty() && !projekt->mapLayers().isEmpty();\n'),
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
