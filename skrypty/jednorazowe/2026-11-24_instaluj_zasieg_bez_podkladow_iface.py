#!/usr/bin/env python3
"""Instalator łatki [WF-EXTENT-BASEMAP] 24.11.2026 — podkłady (OSM wektorowy, XYZ, WMS)
nie wyznaczają pełnego zasięgu mapy; projekt z DXF otwiera się na rysunku.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/qfappinterface.cpp
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_zasieg_bez_podkladow_iface.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/qfappinterface.cpp'
MD5_PRZED = 'd04e8a8d2b351a31d82bcddd2ba71276'  # po instaluj_crs_pusty_projekt
MD5_PO = '1f341733be52b268e975b36e390f4709'

ZMIANY = [
    ('    if ( layer->providerType() == QStringLiteral( "wms" ) )\n      continue;\n    QgsRectangle extent = layer->extent();',
     '    if ( layer->providerType() == QStringLiteral( "wms" ) )\n      continue;\n    // [WF-EXTENT-BASEMAP] 24.11.2026 — kafle wektorowe (podkład OSM) też są podkładem\n    if ( layer->type() == Qgis::LayerType::VectorTile )\n      continue;\n    QgsRectangle extent = layer->extent();'),
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
