#!/usr/bin/env python3
"""Instalator łatki [WF-OSM-VECTOR] 24.11.2026 — podkład wektorowy OSM w każdym
projekcie, przełącznik w Ustawieniach → Teren, ortofoto Esri zgaszone, bez rastrowego OSM.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfSettingsTeren.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_osm_wektor_wszedzie_ustawienia.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfSettingsTeren.qml'
MD5_PRZED = '86bbe39e517d0a430986345c655512b9'  # origin/development
MD5_PO = '08fd758b583332203df5270d046cd3c5'

ZMIANY = [
    ('\n    // [WF-SOUNDS] Dźwięki i ostrzeżenia RTK — Piotr 23.10: dźwięk (głośność,\n',
     '\n    // [WF-OSM-VECTOR] WorkFieldGIS 24.11.2026 — Piotr: podkład wektorowy OSM\n    // dokładany do każdego projektu; tu się go wyłącza.\n    Text {\n      Layout.fillWidth: true\n      Layout.topMargin: 6\n      text: qsTr("Podkład mapy")\n      color: Theme.secondaryTextColor\n      font: Theme.strongTipFont\n    }\n\n    RowLayout {\n      Layout.fillWidth: true\n      spacing: 8\n\n      Switch {\n        id: osmBasemapSwitch\n        checked: settings.valueBool(\'WorkField/osmVectorBasemap\', true)\n        onToggled: settings.setValue(\'WorkField/osmVectorBasemap\', checked)\n      }\n\n      Text {\n        Layout.fillWidth: true\n        text: qsTr("Podkład wektorowy OpenStreetMap w każdym projekcie")\n        color: Theme.mainTextColor\n        font: Theme.tipFont\n        wrapMode: Text.Wrap\n      }\n    }\n\n    Text {\n      Layout.fillWidth: true\n      text: qsTr("Dokładany przy otwarciu, zapisie i zakładaniu projektu, zawsze na dole legendy. Kafle z OpenFreeMap, potrzebna sieć. Wyłączenie nie usuwa podkładu z projektów, które już go mają.")\n      color: Theme.secondaryTextColor\n      font: Theme.tinyFont\n      wrapMode: Text.Wrap\n    }\n\n    // [WF-SOUNDS] Dźwięki i ostrzeżenia RTK — Piotr 23.10: dźwięk (głośność,\n'),
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
