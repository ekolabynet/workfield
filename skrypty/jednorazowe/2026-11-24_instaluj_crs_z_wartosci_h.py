#!/usr/bin/env python3
"""Instalator łatki [WF-CRS-DETECT] / [WF-CRS-CONVERT] (24.11.2026): rozpoznanie układu warstwy z wartości
współrzędnych, transformacja w locie i konwersja do dane.gpkg (silnik C++, bez QML).
Miejsce w repozytorium: skrypty/jednorazowe/2026-11-24_instaluj_crs_z_wartosci_h.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.h'
MD5_PRZED = 'ccd0fe458f883209a65c2fd4d67fb2a5'  # po instaluj_uzupelnianie (auto)
MD5_PO = 'a3ce537c9361790d6c48ded658c8da41'

ZMIANY = [
    ('    Q_INVOKABLE int setLayerVisibleByName( QgsProject *project, const QString &layerName, bool visible );\n',
     '    Q_INVOKABLE int setLayerVisibleByName( QgsProject *project, const QString &layerName, bool visible );\n\n    /**\n     * [WF-CRS-DETECT] WorkFieldGIS 24.11.2026 — układ warstwy rozpoznany z wartości\n     * współrzędnych (Polska: EPSG 4326, 3857, 2180, 2176–2179; też zamienione osie\n     * i współrzędne lokalne rysunku przy 0,0). Tylko warstwy z plików lokalnych.\n     * Zwykle wystarcza extent(); obiekty liczone są tylko przy rozjeździe w zasięgu\n     * (np. rysunek z częścią obiektów przy 0,0), do 200 000 obiektów. Zwraca\n     * { layerId, name, declared, detected, swapped, kind: ok|collision|outliers|\n     * swapped|local|unknown|skip, total, inside, outside, local, zakres, extent\n     * (główna część w układzie projektu, do przybliżenia), canConvert, opis }.\n     */\n    Q_INVOKABLE QVariantMap detectLayerCrs( QgsProject *project, const QString &layerId ) const;\n\n    /**\n     * [WF-CRS-DETECT] wszystkie warstwy z plików lokalnych. Zwraca { checked, ms,\n     * entries: [ wynik detectLayerCrs dla rodzajów innych niż ok i skip ] }.\n     */\n    Q_INVOKABLE QVariantMap checkProjectCrs( QgsProject *project ) const;\n\n    /**\n     * [WF-CRS-DETECT] „transformacja w locie”: warstwa dostaje układ authid, dane\n     * na dysku bez zmian (zostaje po zapisie projektu). Zwraca { ok, opis }.\n     */\n    Q_INVOKABLE QVariantMap assignLayerCrs( QgsProject *project, const QString &layerId, const QString &authid );\n\n    /**\n     * [WF-CRS-CONVERT] „konwersja”: kopia warstwy w nowej tabeli bazy projektu\n     * (dane.gpkg), przeliczona z sourceAuthid do układu projektu, opcjonalnie\n     * z zamianą osi. Obiekty poza obszarem układu źródłowego (np. przy 0,0) są\n     * pomijane. Przed zapisem migawka bazy; liczniki rozstrzygają — niezgodność\n     * zostawia warstwę w projekcie bez zmian. Nowa warstwa wchodzi w miejsce\n     * starej (styl i widoczność przeniesione), oryginał zostaje na dysku.\n     * Zwraca { ok, opis, tabela, zapisane, pominiete, layerId }.\n     */\n    Q_INVOKABLE QVariantMap convertLayerToProjectDb( QgsProject *project, const QString &layerId, const QString &sourceAuthid, bool swapAxes );\n'),
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
