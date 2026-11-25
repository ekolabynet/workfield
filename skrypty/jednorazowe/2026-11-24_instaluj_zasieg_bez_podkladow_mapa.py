#!/usr/bin/env python3
"""Instalator łatki [WF-EXTENT-BASEMAP] 24.11.2026 — podkłady (OSM wektorowy, XYZ, WMS)
nie wyznaczają pełnego zasięgu mapy; projekt z DXF otwiera się na rysunku.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/qgsquick/qgsquickmapcanvasmap.cpp
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_zasieg_bez_podkladow_mapa.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/qgsquick/qgsquickmapcanvasmap.cpp'
MD5_PRZED = '28e170fea5abf51f1e244138660c7e84'  # origin/development
MD5_PO = '548022ae09c6524dc55e953909e821ba'

ZMIANY = [
    ('void QgsQuickMapCanvasMap::zoomToFullExtent()\n{\n  QgsRectangle extent;\n  const QList<QgsMapLayer *> layers = mMapSettings->layers();\n  for ( QgsMapLayer *layer : layers )\n  {\n',
     'void QgsQuickMapCanvasMap::zoomToFullExtent()\n{\n  QgsRectangle extent;\n  const QList<QgsMapLayer *> layers = mMapSettings->layers();\n  for ( QgsMapLayer *layer : layers )\n  {\n    // WorkFieldGIS 24.11.2026 [WF-EXTENT-BASEMAP] — podkłady (kafle wektorowe,\n    // XYZ/WMS) mają zasięg całego świata. W projekcie z DXF podkład OSM wstawał\n    // pierwszy, mapa skakała do „świata” w EPSG:2178 (skala 5000 km) i rysunek\n    // dołożony chwilę później już jej nie przesuwał. Zasięg liczymy z danych.\n    if ( layer->type() == Qgis::LayerType::VectorTile || layer->providerType() == QLatin1String( "wms" ) )\n      continue;\n'),
    ('  mMapSettings->setExtent( extent );\n\n  refresh();\n}\n',
     '  // [WF-EXTENT-BASEMAP] same podkłady: zasięg zostaje pusty, więc pierwsza\n  // warstwa z danymi (np. rysunek CAD) ustawi widok przy następnej zmianie warstw.\n  if ( extent.isEmpty() )\n  {\n    refresh();\n    return;\n  }\n  mMapSettings->setExtent( extent );\n\n  refresh();\n}\n'),
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
