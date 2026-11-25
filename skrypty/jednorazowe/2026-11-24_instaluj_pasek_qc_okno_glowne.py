#!/usr/bin/env python3
"""Instalator łatki [WF-QC-FIT]/[WF-QC-OPTIONS] 24.11.2026 — pasek szybkiego zapisu mieści się
między górną belką a przyciskami mapy (druga kolumna, przewijanie), ma zębatkę i okno ustawień
(Narzędzia → Pasek szybkiego zapisu).
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_pasek_qc_okno_glowne.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml'
MD5_PRZED = 'a554aa96b8ff6961f6bb4463572a14c4'  # po instaluj_uzupelnianie_poprawki
MD5_PO = '073f2b5f369050abc2e0db3e71a4a4a8'

ZMIANY = [
    ('    visible: (Qt.platform.os === "android" || Qt.platform.os === "ios" || naKomputerze)\n             && !(featureListForm.visible && featureListForm.isFullscreen)\n',
     '    // [WF-QC-OPTIONS] 24.11.2026 — na telefonie też da się pasek ukryć\n    // (Narzędzia → Pasek szybkiego zapisu); domyślnie widoczny jak dotąd.\n    property bool naTelefonie: settings.valueBool(\'WorkField/quickCaptureNaTelefonie\', true)\n    visible: ((Qt.platform.os === "android" || Qt.platform.os === "ios") ? naTelefonie : naKomputerze)\n             && !(featureListForm.visible && featureListForm.isFullscreen)\n'),
    ('    x: quickCaptureBar.qcKrawedz === "lewa" ? 8 : wolnaSzerokosc - quickCaptureBar.width - 8\n    y: Math.max(8, (wolnaWysokosc - quickCaptureBar.height) / 2)\n',
     '    // [WF-QC-FIT] 24.11.2026 — Piotr 22:48: pasek zasłaniał inne przyciski,\n    // a strzałka zwijania ginęła pod górną belką (na telefonie mapa biegnie pod\n    // nią, a pasek zaczynał się na y = 8). Wolny pas przy krawędzi paska: od\n    // dolnej krawędzi górnej belki (mainWindow.dolBelki) do dołu wolnego\n    // obszaru, w największej przerwie między przyciskami mapy, które stoją przy\n    // tej samej krawędzi — znanymi z nazwy (szukaj, powiększanie, GNSS,\n    // rysowanie) i każdym małym elementem nakładki. Sprawdzane co 0,7 s, póki\n    // pasek jest widoczny; zmiana pasa idzie do dziennika z listą przeszkód.\n    property real wolnaGora: 8\n    property real wolnyDol: wolnaWysokosc - 8\n    maxWysokosc: Math.max(0, wolnyDol - wolnaGora)\n\n    function przeliczWolnyPas() {\n      const p = quickCaptureBar.parent;\n      if (!p)\n        return;\n      const gora0 = (mainWindow.dolBelkiZmiana >= 0 ? mainWindow.dolBelki(p) : 0) + 8;\n      const dol0 = wolnaWysokosc - mainWindow.sceneBottomMargin - 8;\n      const szer = Math.max(quickCaptureBar.width, quickCaptureBar.qcRozmiarDomyslny);\n      const lewo = quickCaptureBar.qcKrawedz === "lewa" ? 8 : wolnaSzerokosc - szer - 8;\n      const prawo = lewo + szer;\n      let kandydaci = [locatorItem, zoomToolbar, locationToolbar, digitizingToolbarContainer];\n      for (let i = 0; i < p.children.length; i++)\n        kandydaci.push(p.children[i]);\n      for (let i = 0; i < mapCanvasOverlays.children.length; i++)\n        kandydaci.push(mapCanvasOverlays.children[i]);\n      let zajete = [];\n      let opis = [];\n      for (const o of kandydaci) {\n        if (!o || o === quickCaptureBar || !o.visible || o.opacity <= 0 || !(o.width > 0) || !(o.height > 0))\n          continue;\n        if (o.width > p.width * 0.4 || o.height > p.height * 0.6)\n          continue; // the map, panels, full-screen layers — not buttons\n        const r = o.mapToItem(p, 0, 0);\n        if (r.x + o.width < lewo || r.x > prawo || r.y + o.height < gora0 || r.y > dol0)\n          continue;\n        zajete.push([r.y - 8, r.y + o.height + 8]);\n        opis.push(String(o).split("(")[0] + "@" + Math.round(r.y));\n      }\n      zajete.sort((a, b) => a[0] - b[0]);\n      let pas = [gora0, gora0];\n      let start = gora0;\n      for (const z of zajete) {\n        if (z[0] - start > pas[1] - pas[0])\n          pas = [start, z[0]];\n        start = Math.max(start, z[1]);\n      }\n      if (dol0 - start > pas[1] - pas[0])\n        pas = [start, dol0];\n      if (pas[1] - pas[0] < 120)\n        pas = [gora0, dol0]; // no sensible gap: at least stay under the top bar\n      if (Math.abs(wolnaGora - pas[0]) > 1 || Math.abs(wolnyDol - pas[1]) > 1) {\n        wolnaGora = pas[0];\n        wolnyDol = pas[1];\n        console.log("WorkField [WF-QC-FIT]: wolny pas " + Math.round(pas[0]) + "–" + Math.round(pas[1]) + " px, przeszkody: " + (opis.length ? opis.join(", ") : "brak"));\n      }\n    }\n\n    Timer {\n      interval: 700\n      repeat: true\n      running: quickCaptureBar.visible\n      triggeredOnStart: true\n      onTriggered: quickCaptureBar.przeliczWolnyPas()\n    }\n\n    x: quickCaptureBar.qcKrawedz === "lewa" ? 8 : wolnaSzerokosc - quickCaptureBar.width - 8\n    y: Math.max(wolnaGora, Math.min(wolnyDol - quickCaptureBar.height, (wolnaGora + wolnyDol - quickCaptureBar.height) / 2))\n'),
    ('  QfCaptureSettings {\n    id: captureSettings\n    t: Theme\n  }\n',
     '  QfCaptureSettings {\n    id: captureSettings\n    t: Theme\n  }\n\n  // [WF-QC-OPTIONS] 24.11.2026 — okno ustawień paska szybkiego zapisu\n  // (Narzędzia → Pasek szybkiego zapisu i zębatka na pasku).\n  QfQuickCaptureOptions {\n    id: quickCaptureOptions\n  }\n'),
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
