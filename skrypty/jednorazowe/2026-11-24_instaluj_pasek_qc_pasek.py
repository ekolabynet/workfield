#!/usr/bin/env python3
"""Instalator łatki [WF-QC-FIT]/[WF-QC-OPTIONS] 24.11.2026 — pasek szybkiego zapisu mieści się
między górną belką a przyciskami mapy (druga kolumna, przewijanie), ma zębatkę i okno ustawień
(Narzędzia → Pasek szybkiego zapisu).
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfQuickCaptureBar.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_pasek_qc_pasek.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfQuickCaptureBar.qml'
MD5_PRZED = '30c3b5a07a49092bab97e2a96b41b603'  # origin/development
MD5_PO = 'eff252796ca3bddd5c50b4064d25bc37'

ZMIANY = [
    ('  readonly property bool zwinieteEfektywne: qcSekcja === "zwijana" && ustawieniaZwiniete\n',
     '  readonly property bool zwinieteEfektywne: qcSekcja === "zwijana" && ustawieniaZwiniete\n\n  // [WF-QC-FIT] WorkFieldGIS 24.11.2026 — Piotr 22:48: pasek bywa wyższy niż\n  // wolne miejsce, zasłania inne przyciski, a strzałka zwijania ginie (na\n  // telefonie mapa biegnie pod górną belką, a pasek zaczynał się na y = 8).\n  // Okno główne podaje wysokość wolnego pasa (0 = bez limitu). Kafle idą wtedy\n  // do drugiej kolumny, a gdy i dwie nie wystarczą — przewijają się palcem.\n  // Strzałka i zębatka zostają zawsze na górze paska.\n  property real maxWysokosc: 0\n\n  // [WF-QC-OPTIONS] ustawienia TEGO urządzenia z okna „Pasek szybkiego zapisu”;\n  // "" / 0 = jak w sekcji „ustawienia” pliku workfield_klawisze.json projektu.\n  property string userEdge: settings.value("WorkField/qcUserEdge", "")\n  property int userTileSize: settings.valueInt("WorkField/qcUserTileSize", 0)\n  property string projectEdge: "prawa"\n  readonly property int tileSizeOverride: userTileSize >= 40 && userTileSize <= 120 ? userTileSize : 0\n\n  onUserEdgeChanged: applyUserOptions()\n\n  function applyUserOptions() {\n    qcKrawedz = userEdge === "lewa" || userEdge === "prawa" ? userEdge : projectEdge;\n  }\n\n  function tileSize(entry) {\n    if (tileSizeOverride > 0)\n      return tileSizeOverride;\n    return entry && entry.rozmiar ? entry.rozmiar : qcRozmiarDomyslny;\n  }\n\n  //! Rows of the tile grid: one column when everything fits, otherwise two\n  //! balanced columns (scrolling, when two are not enough either).\n  function tileRows(available) {\n    const n = resolvedLayers.length;\n    if (n === 0)\n      return 1;\n    let biggest = 0;\n    for (let i = 0; i < n; i++)\n      biggest = Math.max(biggest, tileSize(resolvedLayers[i]));\n    const perColumn = Math.max(1, Math.floor((available + qcOdstep) / (biggest + qcOdstep)));\n    return n <= perColumn ? n : Math.ceil(n / 2);\n  }\n'),
    ('    qcKrawedz = u.krawedz === "lewa" ? "lewa" : "prawa";\n',
     '    projectEdge = u.krawedz === "lewa" ? "lewa" : "prawa"; // [WF-QC-OPTIONS]\n    applyUserOptions();\n'),
    ('  Rectangle {\n    id: przyciskZwijania\n',
     '  // [WF-QC-OPTIONS] 24.11.2026 — strzałka i zębatka w jednym wierszu na górze\n  // paska; zębatka otwiera okno ustawień paska (to samo co Narzędzia →\n  // Pasek szybkiego zapisu).\n  Row {\n    id: naglowekPaska\n    spacing: 6\n    x: quickCaptureBar.qcWyrownanie === "lewo" ? 0 : quickCaptureBar.qcWyrownanie === "prawo" ? parent.width - width : (parent.width - width) / 2\n\n  Rectangle {\n    id: przyciskZwijania\n'),
    ('    visible: quickCaptureBar.qcSekcja === "zwijana"\n    x: quickCaptureBar.qcWyrownanie === "lewo" ? 0 : quickCaptureBar.qcWyrownanie === "prawo" ? parent.width - width : (parent.width - width) / 2\n\n    color: Theme.mainColor',
     '    visible: quickCaptureBar.qcSekcja === "zwijana"\n\n    color: Theme.mainColor'),
    ('  QfToolButton {\n    id: fastModeButton\n',
     '  Rectangle {\n    id: przyciskOpcji\n\n    width: 40\n    height: 40\n    radius: width / 2\n    color: "#455A64"\n    border.color: "white"\n    border.width: 2\n\n    Image {\n      anchors.centerIn: parent\n      width: 24\n      height: 24\n      source: Theme.getThemeVectorIcon("ic_settings_white_24dp")\n      sourceSize.width: 48\n      sourceSize.height: 48\n    }\n\n    MouseArea {\n      anchors.fill: parent\n      anchors.margins: -4\n      onClicked: {\n        quickCaptureBar.haptyka(20);\n        quickCaptureOptions.openOptions();\n      }\n      onPressAndHold: displayToast(qsTr("Zębatka: ustawienia paska — pokaż/ukryj, krawędź, rozmiar kafli, tryby, edycja kafli."))\n    }\n  }\n  } // naglowekPaska\n\n  QfToolButton {\n    id: fastModeButton\n'),
    ('  Repeater {\n    model: quickCaptureBar.resolvedLayers\n\n    delegate: Rectangle {\n',
     '  // [WF-QC-FIT] 24.11.2026 — kafle w siatce: jedna kolumna, gdy się mieszczą,\n  // dwie, gdy nie; przewijanie, gdy i dwie nie wystarczą.\n  Flickable {\n    id: kafleFlick\n\n    readonly property real available: quickCaptureBar.maxWysokosc > 0 ? Math.max(quickCaptureBar.qcRozmiarDomyslny, quickCaptureBar.maxWysokosc - kafleFlick.y) : 100000\n\n    width: kafleSiatka.width\n    height: Math.min(kafleSiatka.height, available)\n    x: quickCaptureBar.qcWyrownanie === "lewo" ? 0 : quickCaptureBar.qcWyrownanie === "prawo" ? parent.width - width : (parent.width - width) / 2\n    contentWidth: kafleSiatka.width\n    contentHeight: kafleSiatka.height\n    clip: kafleSiatka.height > height\n    interactive: kafleSiatka.height > height\n    boundsBehavior: Flickable.StopAtBounds\n    flickableDirection: Flickable.VerticalFlick\n\n    ScrollIndicator.vertical: ScrollIndicator {\n      active: kafleFlick.interactive\n    }\n\n  Grid {\n    id: kafleSiatka\n\n    flow: Grid.TopToBottom\n    rows: quickCaptureBar.tileRows(kafleFlick.available)\n    spacing: quickCaptureBar.qcOdstep\n    horizontalItemAlignment: quickCaptureBar.qcWyrownanie === "lewo" ? Grid.AlignLeft : quickCaptureBar.qcWyrownanie === "prawo" ? Grid.AlignRight : Grid.AlignHCenter\n\n  Repeater {\n    model: quickCaptureBar.resolvedLayers\n\n    delegate: Rectangle {\n'),
    ('      width: modelData.rozmiar ? modelData.rozmiar : quickCaptureBar.qcRozmiarDomyslny\n      height: width\n      x: quickCaptureBar.qcWyrownanie === "lewo" ? 0 : quickCaptureBar.qcWyrownanie === "prawo" ? parent.width - width : (parent.width - width) / 2\n      radius: modelData.shape',
     '      width: quickCaptureBar.tileSize(modelData) // [WF-QC-OPTIONS]\n      height: width\n      radius: modelData.shape'),
    ('  }\n\n  // WorkField: ile stad do obiektu?',
     '  }\n  } // kafleSiatka\n  } // kafleFlick\n\n  // WorkField: ile stad do obiektu?'),
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
