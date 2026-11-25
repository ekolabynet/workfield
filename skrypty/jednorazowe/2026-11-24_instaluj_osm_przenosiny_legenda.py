#!/usr/bin/env python3
"""Instalator łatki [WF-OSM-MOVE] (24.11.2026): po przeniesieniu podkładu OSM płaska lista warstw
budowana od nowa; po przeniesieniu przy otwarciu projekt zapisywany.
Miejsce w repozytorium: skrypty/jednorazowe/2026-11-24_instaluj_osm_przenosiny_legenda.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml'
MD5_PRZED = '073f2b5f369050abc2e0db3e71a4a4a8'  # po instaluj_pasek_qc_okno_glowne
MD5_PO = '9de7ef3cac863d789033f90f2119cfd0'

ZMIANY = [
    ('    let result;\n    try {\n      result = NarzedziaProjektu.ensureOsmVectorBasemap(qgisProject);\n    } catch (e) {\n      console.log("WorkField [WF-OSM-VECTOR]: " + trigger + " failed: " + e);\n      return { "ok": false, "dodano": false, "przeniesiono": false, "opis": "", "disabled": false };\n    }\n',
     '    // [WF-OSM-MOVE] WorkFieldGIS 24.11.2026 — wywrotka SEGV w\n    // QfFlatLayerTreeModelBase::data (QMetaObject::cast). Trzy pomiary Piotra:\n    // wywraca się tylko przy otwarciu z „przeniesiono=true”. Płaska lista\n    // warstw trzyma zwykłe indeksy modelu, a przenosiny kasują węzeł legendy —\n    // dlatego na czas przenosin lista jest zamrożona, a po nich budowana od\n    // nowa. Cudzego zamrożenia (wczytywanie projektu) nie ruszamy.\n    const tree = dashBoard.layerTree;\n    const ownFreeze = tree && !tree.isFrozen;\n    if (ownFreeze)\n      tree.freeze();\n    let result;\n    try {\n      result = NarzedziaProjektu.ensureOsmVectorBasemap(qgisProject);\n    } catch (e) {\n      console.log("WorkField [WF-OSM-VECTOR]: " + trigger + " failed: " + e);\n      if (ownFreeze)\n        tree.unfreeze(true);\n      return { "ok": false, "dodano": false, "przeniesiono": false, "opis": "", "disabled": false };\n    }\n    if (ownFreeze) {\n      const rebuild = result.dodano || result.przeniesiono;\n      tree.unfreeze(rebuild);\n      if (rebuild)\n        console.log("WorkField [WF-OSM-MOVE]: " + trigger + " — lista warstw zbudowana od nowa");\n    } else if (result.dodano || result.przeniesiono) {\n      console.log("WorkField [WF-OSM-MOVE]: " + trigger + " — lista warstw była już zamrożona, przebuduje ją właściciel");\n    }\n'),
    ('          if (basemap.dodano && !wasDirty) {\n            const saved = ProjectUtils.saveProject(qgisProject);\n            console.log("WorkField [WF-OSM-VECTOR]: load — projekt zapisany z podkładem: " + saved);\n          } else if (basemap.dodano) {',
     '          // [WF-OSM-MOVE] 24.11.2026 — po przeniesieniu też zapisujemy:\n          // inaczej przenosiny (i ryzyko) powtarzały się przy każdym otwarciu.\n          const basemapChanged = basemap.dodano || basemap.przeniesiono;\n          if (basemapChanged && !wasDirty) {\n            const saved = ProjectUtils.saveProject(qgisProject);\n            console.log("WorkField [WF-OSM-VECTOR]: load — projekt zapisany z podkładem: " + saved);\n          } else if (basemapChanged) {'),
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
