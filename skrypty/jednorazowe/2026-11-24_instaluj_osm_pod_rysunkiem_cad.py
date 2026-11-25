#!/usr/bin/env python3
"""Instalator łatki [WF-OSM-VECTOR] 24.11.2026 — podkład OSM wraca na dół legendy po dołożeniu
rysunku CAD (projekt z DXF, import DXF).
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_osm_pod_rysunkiem_cad.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml'
MD5_PRZED = '98b1cb0552d0ad48d4358709cc37b002'  # po instaluj_osm_wektor_wszedzie_app
MD5_PO = '290009b89bf7f12927a4e15c4fcb38cb'

ZMIANY = [
    ('      displayToast(qsTr("Nie udało się wczytać rysunku — projekt bez podkładu"),\n                   "warning");\n\n    return podkladow;',
     '      displayToast(qsTr("Nie udało się wczytać rysunku — projekt bez podkładu"),\n                   "warning");\n\n    // [WF-OSM-VECTOR] 24.11.2026 — grupa „Rysunek CAD” wchodzi na dół legendy,\n    // POD podkład OSM dodany przy otwarciu. Przesuwamy podkład z powrotem na dół\n    // (obie drogi: kreator „Projekt z DXF” i „Import z rysunku DXF”).\n    if (podkladow > 0)\n      mainWindow.ensureOsmBasemap("cad", false);\n\n    return podkladow;'),
    ('    // Podklad dokladamy nie tutaj, tylko WSKAZUJEMY, gdzie jest: zakladka\n    // Warstwy ma "Dodaj podkład" i CADowiec wybierze sobie ortofoto albo\n    // OSM jednym tapnieciem. Narzucanie podkladu w kreatorze zabieraloby\n    // mu ten wybor i wydluzalo pierwszy start.\n    if (zalozone === robocze.length)\n      displayToast(qsTr("Projekt gotowy. Podkład dodasz w zakładce Warstwy."),',
     '    // Podklad OSM (wektorowy) jest juz w projekcie [WF-OSM-VECTOR, 24.11];\n    // ortofoto i inne podklady CADowiec doklada sam w zakladce Warstwy\n    // ("Dodaj podkład") — wskazujemy, gdzie to jest.\n    if (zalozone === robocze.length)\n      displayToast(qsTr("Projekt gotowy. Ortofotomapę i inne podkłady dodasz w zakładce Warstwy."),'),
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
