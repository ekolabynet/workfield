#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-OSM-VECTOR] obowiązkowy podkład OSM z kafli wektorowych, zawsze na dole (deklaracja).

Decyzja Piotra 24.11 (20:35): podkład OpenStreetMap z kafli wektorowych dodawany przy każdym
„Nowy projekt”, „Zapisz” i „Zapisz jako”, zawsze na dole legendy. Źródło i styl jak we wtyczce
WFG Urban Environment: OpenFreeMap (schemat OpenMapTiles), styl „WFG Jasny” wbudowany w aplikację.
Trzy instalatory razem: narzedziaprojektu.h, narzedziaprojektu.cpp, QfMainDrawer.qml.

Użycie (z katalogu repozytorium):
  python3 instaluj_osm_wektor_h.py            # próba, nic nie zapisuje
  python3 instaluj_osm_wektor_h.py --zapisz   # zapis (z kopią .przed_*)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.h'
MD5_PRZED = '71238bab9ee817bace9371260a5f2592'  # po 2026-11-24_instaluj_crs_przelicz_h.py
MD5_PO = 'ff32d50f3cd5460325f64361ea719e86'

ZMIANY = [
    ('    Q_INVOKABLE QVariantMap reprojectDegreesLayer( QgsProject *project, const QString &layerName );\n',
     '    Q_INVOKABLE QVariantMap reprojectDegreesLayer( QgsProject *project, const QString &layerName );\n\n    /**\n     * WorkFieldGIS 24.11.2026 — [WF-OSM-VECTOR] obowiązkowy podkład: kafle wektorowe\n     * OpenStreetMap (OpenFreeMap, schemat OpenMapTiles) w stylu „WFG Jasny” z wtyczki\n     * WFG Urban Environment. Dodaje warstwę, jeśli jej nie ma (rozpoznaje ją po\n     * własności „wfg/basemap” = „osm_vector”), i zawsze stawia ją na samym dole\n     * legendy. Wołane przy „Nowy projekt”, „Zapisz” i „Zapisz jako”. Adres kafli\n     * z TileJSON OpenFreeMap (jedno zapytanie na sesję, limit 4 s); bez sieci\n     * warstwa nie powstaje i zostanie dodana przy następnym zapisie.\n     * Zwraca { ok, opis, dodano, przeniesiono }.\n     */\n    Q_INVOKABLE QVariantMap ensureOsmVectorBasemap( QgsProject *project );\n'),
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
