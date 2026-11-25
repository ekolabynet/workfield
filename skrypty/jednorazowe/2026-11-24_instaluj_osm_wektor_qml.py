#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-OSM-VECTOR] obowiązkowy podkład OSM z kafli wektorowych, zawsze na dole (Nowy / Zapisz / Zapisz jako).

Decyzja Piotra 24.11 (20:35): podkład OpenStreetMap z kafli wektorowych dodawany przy każdym
„Nowy projekt”, „Zapisz” i „Zapisz jako”, zawsze na dole legendy. Źródło i styl jak we wtyczce
WFG Urban Environment: OpenFreeMap (schemat OpenMapTiles), styl „WFG Jasny” wbudowany w aplikację.
Trzy instalatory razem: narzedziaprojektu.h, narzedziaprojektu.cpp, QfMainDrawer.qml.

Użycie (z katalogu repozytorium):
  python3 instaluj_osm_wektor_qml.py            # próba, nic nie zapisuje
  python3 instaluj_osm_wektor_qml.py --zapisz   # zapis (z kopią .przed_*)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfMainDrawer.qml'
MD5_PRZED = '1f15e8b18bb2a05218f99832b703d0d4'  # po 2026-11-24_instaluj_zapisz_jako_z_danymi.py
MD5_PO = 'a5e3e558420866be3e96352c3836f24b'

ZMIANY = [
    ('      iface.addXyzBasemap("OpenStreetMap", "https://tile.openstreetmap.org/{z}/{x}/{y}.png", 19);\n      dashBoard.urzadzNowyProjekt(path, name);\n',
     '      iface.addXyzBasemap("OpenStreetMap", "https://tile.openstreetmap.org/{z}/{x}/{y}.png", 19);\n      NarzedziaProjektu.ensureOsmVectorBasemap(qgisProject); // [WF-OSM-VECTOR] zawsze na dole\n      dashBoard.urzadzNowyProjekt(path, name);\n'),
    ('          onClicked: {\n            if (ProjectUtils.saveProject(qgisProject)) {\n              displayToast(qsTr("Projekt zapisany"));\n',
     '          onClicked: {\n            // [WF-OSM-VECTOR] obowiązkowy podkład OSM na dole legendy, przed zapisem\n            const podklad = NarzedziaProjektu.ensureOsmVectorBasemap(qgisProject);\n            if (ProjectUtils.saveProject(qgisProject)) {\n              displayToast(podklad.dodano || !podklad.ok ? qsTr("Projekt zapisany. %1").arg(podklad.opis) : qsTr("Projekt zapisany"));\n'),
    ('            iface.setProjectTitle(nazwa);\n            ProjectUtils.saveProject(qgisProject);\n',
     '            iface.setProjectTitle(nazwa);\n            NarzedziaProjektu.ensureOsmVectorBasemap(qgisProject); // [WF-OSM-VECTOR]\n            ProjectUtils.saveProject(qgisProject);\n'),
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
