#!/usr/bin/env python3
"""Instalator łatki [WF-AUTO-EQUIP] 24.11.2026 22:3x — moduły przed identyfikatorami, bez modułów
z pytaniem, projekt z DXF sprawdzany dopiero po złożeniu.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_uzupelnianie_poprawki.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml'
MD5_PRZED = '9723c93b12991538cd97ee72fe405d07'  # po instaluj_uzupelnianie_projektu_app
MD5_PO = 'a554aa96b8ff6961f6bb4463572a14c4'

ZMIANY = [
    ('      if (autoEquipCatalog.mozeZalozyc(m.modul) !== "" || autoEquipCatalog.zapowiedzModulu(m.modul) !== "")\n        continue;',
     '      // 24.11 22:28 — „klawisze” pyta o warstwy (pole `pyta`), a bez odpowiedzi\n      // kończył się błędem przy każdym otwarciu. Moduły z pytaniem — tylko w oknie.\n      if (autoEquipCatalog.mozeZalozyc(m.modul) !== "" || autoEquipCatalog.zapowiedzModulu(m.modul) !== "" || (m.pyta !== undefined && m.pyta !== ""))\n        continue;'),
    ('    let done = [];\n    let failed = [];\n    if (plan.identity.layers.length > 0) {\n      const w = NarzedziaProjektu.repairIdentityWithBackup(qgisProject);\n      (w.ok ? done : failed).push(w.opis);\n    }\n    for (const m of plan.modules) {\n      const w = autoEquipCatalog.zaloz(qgisProject, m.modul);\n      (w.ok ? done : failed).push(m.nazwa + ": " + w.opis);\n    }',
     '    let done = [];\n    let failed = [];\n    // Moduły NAJPIERW: „załączniki” zakłada nowe tabele zdjęć (24.11 22:28 zostały\n    // bez uuid, bo identyfikatory szły przed nimi). Identyfikatory potem, z planem\n    // policzonym od nowa.\n    for (const m of plan.modules) {\n      const w = autoEquipCatalog.zaloz(qgisProject, m.modul);\n      (w.ok ? done : failed).push(m.nazwa + ": " + w.opis);\n    }\n    let identityNow = plan.identity;\n    try {\n      identityNow = NarzedziaProjektu.identityFieldsPlan(qgisProject);\n    } catch (e) {\n      console.log("WorkField [WF-AUTO-EQUIP]: plan failed: " + e);\n    }\n    if (identityNow.layers.length > 0) {\n      const w = NarzedziaProjektu.repairIdentityWithBackup(qgisProject);\n      (w.ok ? done : failed).push(w.opis);\n    }'),
    ('      if (path.indexOf("/templates/") === -1 && path.indexOf("/szablony/") === -1) {\n        Qt.callLater(function () {\n          const written = NarzedziaProjektu.fillMissingIdentity(qgisProject);',
     '      if (path.indexOf("/templates/") === -1 && path.indexOf("/szablony/") === -1) {\n        // [WF-AUTO-EQUIP] 24.11 22:28 — projekt z DXF: warstwy robocze i baza\n        // powstają chwilę później (zlozProjektZCAD), stempel modułu nie miał\n        // gdzie się zapisać. Sprawdzenie robi wtedy zlozProjektZCAD.\n        const cadComing = mainWindow.cadRysunek !== "";\n        Qt.callLater(function () {\n          const written = NarzedziaProjektu.fillMissingIdentity(qgisProject);'),
    ('          try {\n            mainWindow.autoEquipCheck();\n          } catch (e) {',
     '          try {\n            if (!cadComing)\n              mainWindow.autoEquipCheck();\n          } catch (e) {'),
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
