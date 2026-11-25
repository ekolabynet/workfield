#!/usr/bin/env python3
"""Instalator łatki 24.11.2026 — przyciąganie i unikanie nakładania wyjęte z wyposażenia
(sprawdzanie, okno Wyposażenia, automat, nowy projekt). Decyzja Piotra 22:43.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/wyposazenie/przepisy/platy_roslinnosci.json
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_bez_modulow_przyciagania_przepis.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/wyposazenie/przepisy/platy_roslinnosci.json'
MD5_PRZED = 'f899cc1e667383f8513d3df1aa015f23'  # origin/development
MD5_PO = '3e069ef28ce599c84b6ec58eba432bb9'

ZMIANY = [
    ('  "wyposazenie": [\n    {\n      "modul": "przyciaganie",\n      "wersja": 1\n    },\n    {\n      "modul": "bez_nakladania",\n      "wersja": 1\n    },\n    {\n      "modul": "klawisze",',
     '  "wyposazenie": [\n    {\n      "modul": "klawisze",'),
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
