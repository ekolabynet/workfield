#!/usr/bin/env python3
"""Instalator łatki [WF-OSM-VECTOR] 24.11.2026 — podkład wektorowy OSM w każdym
projekcie, przełącznik w Ustawieniach → Teren, ortofoto Esri zgaszone, bez rastrowego OSM.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfMainDrawer.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_osm_wektor_wszedzie_szuflada.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfMainDrawer.qml'
MD5_PRZED = 'a5e3e558420866be3e96352c3836f24b'  # po instaluj_osm_wektor_qml
MD5_PO = '8ca241c63faed018016b8cd76ae4d2cb'

ZMIANY = [
    ('      iface.addXyzBasemap("Esri World Imagery", "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", 19);\n      // WorkField 6.10.2026 [WF-NOWY-PODKLADY] — OSM POD ESRI: addXyzBasemap\n      // dokłada na sam dół legendy, więc drugi dodany ląduje pod pierwszym.\n      iface.addXyzBasemap("OpenStreetMap", "https://tile.openstreetmap.org/{z}/{x}/{y}.png", 19);\n      NarzedziaProjektu.ensureOsmVectorBasemap(qgisProject); // [WF-OSM-VECTOR] zawsze na dole\n',
     '      iface.addXyzBasemap("Esri World Imagery", "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", 19);\n      // WorkFieldGIS 24.11.2026 [WF-ESRI-HIDDEN] — Piotr: ortofoto Esri jest\n      // w projekcie, ale zgaszone (włącza się je w legendzie). Rastrowego OSM\n      // z tile.openstreetmap.org już nie dokładamy (było [WF-NOWY-PODKLADY]\n      // 6.10): zasady OSMF nie pozwalają na ciężkie użycie w rozpowszechnianej\n      // aplikacji, a jego miejsce zajął podkład wektorowy [WF-OSM-VECTOR].\n      NarzedziaProjektu.setLayerVisibleByName(qgisProject, "Esri World Imagery", false);\n      mainWindow.ensureOsmBasemap("new", true); // [WF-OSM-VECTOR] zawsze na dole\n'),
    ('            // [WF-OSM-VECTOR] obowiązkowy podkład OSM na dole legendy, przed zapisem\n            const podklad = NarzedziaProjektu.ensureOsmVectorBasemap(qgisProject);\n            if (ProjectUtils.saveProject(qgisProject)) {\n              displayToast(podklad.dodano || !podklad.ok ? qsTr("Projekt zapisany. %1").arg(podklad.opis) : qsTr("Projekt zapisany"));\n',
     '            // [WF-OSM-VECTOR] podkład OSM na dole legendy, przed zapisem\n            // (24.11: przez mainWindow.ensureOsmBasemap — szanuje ustawienie)\n            const podklad = mainWindow.ensureOsmBasemap("save", false);\n            if (ProjectUtils.saveProject(qgisProject)) {\n              displayToast(podklad.dodano ? qsTr("Projekt zapisany. %1").arg(mainWindow.osmBasemapAddedText())\n                                          : (!podklad.ok && podklad.opis !== "" ? qsTr("Projekt zapisany. %1").arg(podklad.opis) : qsTr("Projekt zapisany")));\n'),
    ('            NarzedziaProjektu.ensureOsmVectorBasemap(qgisProject); // [WF-OSM-VECTOR]\n',
     '            mainWindow.ensureOsmBasemap("saveas", true); // [WF-OSM-VECTOR]\n'),
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
