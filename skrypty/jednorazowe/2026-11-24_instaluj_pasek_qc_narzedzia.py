#!/usr/bin/env python3
"""Instalator łatki [WF-QC-FIT]/[WF-QC-OPTIONS] 24.11.2026 — pasek szybkiego zapisu mieści się
między górną belką a przyciskami mapy (druga kolumna, przewijanie), ma zębatkę i okno ustawień
(Narzędzia → Pasek szybkiego zapisu).
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfDataDrawer.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_pasek_qc_narzedzia.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfDataDrawer.qml'
MD5_PRZED = 'd41b3ab26c3cad587d9d11e2e377a2c7'  # origin/development
MD5_PO = '1b68bcc086650b71e6a400d0943fc12e'

ZMIANY = [
    ('        // ── Wtyczki ─────────────────────────────────────────────\n        Item {\n          id: sekcjaWtyczek\n',
     '        // [WF-QC-OPTIONS] WorkFieldGIS 24.11.2026 — Piotr 22:48: „wyraźne\n        // ustawienie w panelu Narzędzia — jako osobny duży punkt”. Karta nad\n        // listą, nie wiersz w niej; to samo okno otwiera zębatka na pasku.\n        Rectangle {\n          Layout.fillWidth: true\n          Layout.margins: 6\n          Layout.preferredHeight: 64\n          radius: 8\n          color: kartaPaskaMysz.pressed ? Qt.darker(t.mainColor, 1.3) : t.mainColor\n          border.color: "white"\n          border.width: 1\n\n          RowLayout {\n            anchors.fill: parent\n            anchors.leftMargin: 12\n            anchors.rightMargin: 12\n            spacing: 12\n\n            Image {\n              Layout.preferredWidth: 32\n              Layout.preferredHeight: 32\n              source: t.getThemeVectorIcon("ic_settings_white_24dp")\n              sourceSize.width: 64\n              sourceSize.height: 64\n            }\n\n            ColumnLayout {\n              Layout.fillWidth: true\n              spacing: 2\n\n              Text {\n                Layout.fillWidth: true\n                text: qsTr("Pasek szybkiego zapisu")\n                color: "white"\n                font: t.strongFont\n                elide: Text.ElideRight\n              }\n\n              Text {\n                Layout.fillWidth: true\n                text: qsTr("%1 · krawędź: %2 · kafli: %3")\n                        .arg(quickCaptureOptions.barShown ? qsTr("włączony") : qsTr("wyłączony"))\n                        .arg(quickCaptureBar.qcKrawedz === "lewa" ? qsTr("lewa") : qsTr("prawa"))\n                        .arg(quickCaptureBar.resolvedLayers.length)\n                color: "#E0F2F1"\n                font: t.tinyFont\n                elide: Text.ElideRight\n              }\n            }\n          }\n\n          MouseArea {\n            id: kartaPaskaMysz\n            anchors.fill: parent\n            onClicked: dataDrawer.wykonajNarzedzie("pasekSzybkiegoZapisu")\n          }\n        }\n\n        // ── Wtyczki ─────────────────────────────────────────────\n        Item {\n          id: sekcjaWtyczek\n'),
    ('    case "klawisze":\n      dataDrawer.close();\n      captureSettings.openDialog();\n      return;\n',
     '    case "pasekSzybkiegoZapisu": // [WF-QC-OPTIONS] 24.11.2026\n      dataDrawer.close();\n      quickCaptureOptions.openOptions();\n      return;\n    case "klawisze":\n      dataDrawer.close();\n      captureSettings.openDialog();\n      return;\n'),
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
