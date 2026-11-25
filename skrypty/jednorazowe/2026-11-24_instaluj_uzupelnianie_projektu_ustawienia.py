#!/usr/bin/env python3
"""Instalator łatki [WF-AUTO-EQUIP] 24.11.2026 — identyfikatory (uuid) i wyposażenie
uzupełniane przy otwarciu projektu, z pytaniem przy danych; wyłącznik w Ustawieniach → Teren.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfSettingsTeren.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_uzupelnianie_projektu_ustawienia.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfSettingsTeren.qml'
MD5_PRZED = '08fd758b583332203df5270d046cd3c5'  # po instaluj_osm_wektor_wszedzie_ustawienia
MD5_PO = '23a1a43e992a7ca1249ee67d83ad275a'

ZMIANY = [
    ('    // [WF-SOUNDS] Dźwięki i ostrzeżenia RTK — Piotr 23.10: dźwięk (głośność,\n',
     '    // [WF-AUTO-EQUIP] WorkFieldGIS 24.11.2026 — Piotr: identyfikatory\n    // i wyposażenie uzupełniane przy otwarciu projektu; tu się to wyłącza.\n    Text {\n      Layout.fillWidth: true\n      Layout.topMargin: 6\n      text: qsTr("Uzupełnianie projektu")\n      color: Theme.secondaryTextColor\n      font: Theme.strongTipFont\n    }\n\n    RowLayout {\n      Layout.fillWidth: true\n      spacing: 8\n\n      Switch {\n        id: autoEquipSwitch\n        checked: settings.valueBool(\'WorkField/autoEquipProject\', true)\n        onToggled: settings.setValue(\'WorkField/autoEquipProject\', checked)\n      }\n\n      Text {\n        Layout.fillWidth: true\n        text: qsTr("Identyfikatory obiektów (uuid) i wyposażenie przy otwarciu projektu")\n        color: Theme.mainTextColor\n        font: Theme.tipFont\n        wrapMode: Text.Wrap\n      }\n    }\n\n    Text {\n      Layout.fillWidth: true\n      text: qsTr("Warstwy bez obiektów — od razu. Warstwy z danymi i moduły — po pytaniu, z kopią bazy i projektu w katalogu „kopie”. Wyłączone: zostaje samo ostrzeżenie i przycisk w oknie „Co jest nie tak”.")\n      color: Theme.secondaryTextColor\n      font: Theme.tinyFont\n      wrapMode: Text.Wrap\n    }\n\n    // [WF-SOUNDS] Dźwięki i ostrzeżenia RTK — Piotr 23.10: dźwięk (głośność,\n'),
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
