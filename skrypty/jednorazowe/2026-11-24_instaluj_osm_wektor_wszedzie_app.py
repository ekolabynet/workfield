#!/usr/bin/env python3
"""Instalator łatki [WF-OSM-VECTOR] 24.11.2026 — podkład wektorowy OSM w każdym
projekcie, przełącznik w Ustawieniach → Teren, ortofoto Esri zgaszone, bez rastrowego OSM.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_osm_wektor_wszedzie_app.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml'
MD5_PRZED = '9c3e636fdcd4da2d21a5fcc1494bb22d'  # po commicie ddbecaa1b
MD5_PO = '98b1cb0552d0ad48d4358709cc37b002'

ZMIANY = [
    ('\n  property string projectTitle: ""\n  function refreshProjectTitle() {',
     '\n  // [WF-OSM-VECTOR] WorkFieldGIS 24.11.2026 — Piotr: podkład wektorowy OSM\n  // (OpenFreeMap) w każdym projekcie: nowym, otwieranym, zapisywanym,\n  // zapisywanym jako; zawsze na dole legendy. Jedna droga dla wszystkich\n  // wywołań, żeby przełącznik w Ustawieniach → Teren działał wszędzie.\n  readonly property string osmBasemapSettingKey: "WorkField/osmVectorBasemap"\n  function osmBasemapAddedText() {\n    return qsTr("Dodano podkład wektorowy OpenStreetMap. Możesz to wyłączyć w Ustawieniach → Teren.");\n  }\n  function ensureOsmBasemap(trigger, announce) {\n    if (!settings.valueBool(osmBasemapSettingKey, true)) {\n      console.log("WorkField [WF-OSM-VECTOR]: " + trigger + " — wyłączone w ustawieniach");\n      return { "ok": true, "dodano": false, "przeniesiono": false, "opis": "", "disabled": true };\n    }\n    let result;\n    try {\n      result = NarzedziaProjektu.ensureOsmVectorBasemap(qgisProject);\n    } catch (e) {\n      console.log("WorkField [WF-OSM-VECTOR]: " + trigger + " failed: " + e);\n      return { "ok": false, "dodano": false, "przeniesiono": false, "opis": "", "disabled": false };\n    }\n    console.log("WorkField [WF-OSM-VECTOR]: " + trigger + " ok=" + result.ok + " dodano=" + result.dodano + " przeniesiono=" + result.przeniesiono + (result.ok ? "" : " (" + result.opis + ")"));\n    if (announce && result.dodano)\n      displayToast(osmBasemapAddedText());\n    return result;\n  }\n\n  property string projectTitle: ""\n  function refreshProjectTitle() {'),
    ('\n            console.log("WorkField [WF-ATTACHMENT-TRASH]: watch failed: " + e);\n          }\n',
     '\n            console.log("WorkField [WF-ATTACHMENT-TRASH]: watch failed: " + e);\n          }\n          // [WF-OSM-VECTOR] 24.11.2026 — podkład także w projekcie otwieranym.\n          // Gdy go dodaliśmy, a projekt nie miał niezapisanych zmian, zapisujemy\n          // od razu — inaczej wracałby (z komunikatem) przy każdym otwarciu.\n          const wasDirty = ProjectUtils.isProjectDirty(qgisProject);\n          const basemap = mainWindow.ensureOsmBasemap("load", true);\n          if (basemap.dodano && !wasDirty) {\n            const saved = ProjectUtils.saveProject(qgisProject);\n            console.log("WorkField [WF-OSM-VECTOR]: load — projekt zapisany z podkładem: " + saved);\n          } else if (basemap.dodano) {\n            console.log("WorkField [WF-OSM-VECTOR]: load — projekt miał niezapisane zmiany, nie zapisuję");\n          }\n'),
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
