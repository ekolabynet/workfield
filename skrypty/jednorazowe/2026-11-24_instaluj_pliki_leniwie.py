#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-LAZY-FILE-BROWSER] okno „Pliki” tworzone przy pierwszym użyciu.

Refaktoryzacja okna głównego, krok R2.2. QfFileBrowser (1 301 linii QML) trafia do
Loadera. W oknie głównym zostaje obiekt o tym samym id `fileBrowser` z czterema
funkcjami (openPlace, openAt, pickFile, pickFolder), które tworzą okno przy pierwszym
wywołaniu i przekazują mu wywołanie. Wywołujący (okno główne i 9 plików QML) bez zmian.
Zachowanie aplikacji bez zmian; pierwsze otwarcie okna „Pliki” odrobinę dłuższe.

Użycie (z katalogu repozytorium):
  python3 instaluj_pliki_leniwie.py            # próba, nic nie zapisuje
  python3 instaluj_pliki_leniwie.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_pliki_leniwie.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml"
MD5_PRZED = "300fa4295e42ccbbca48d14ffb2c66cc"  # po łatce R2.1 (2026-11-24_instaluj_kreator_leniwie.py)
MD5_PO = "60550e49d019713abbcf31084a0db7ec"

ZMIANY = [
    ('\n  QfFileBrowser {\n    id: fileBrowser\n  }\n',
     '\n  // WorkFieldGIS 24.11.2026 — [WF-LAZY-FILE-BROWSER] okno „Pliki” (QfFileBrowser,\n  // 1 301 linii QML) powstaje przy pierwszym użyciu, nie przy starcie. Wołają je okno\n  // główne i 9 innych plików QML, zawsze tymi czterema funkcjami — ten obiekt ma te same\n  // funkcje i to samo id, więc wywołujący zostają bez zmian. Krok R2.2 refaktoryzacji\n  // (claude/REFAKTOR_okno_glowne_plan_2026-11-24.md).\n  QtObject {\n    id: fileBrowser\n\n    function browser() {\n      fileBrowserLoader.active = true;\n      return fileBrowserLoader.item;\n    }\n    function openPlace(key) {\n      return browser().openPlace(key);\n    }\n    function openAt(path) {\n      return browser().openAt(path);\n    }\n    function pickFile(opts) {\n      return browser().pickFile(opts);\n    }\n    function pickFolder(opts) {\n      return browser().pickFolder(opts);\n    }\n  }\n\n  Loader {\n    id: fileBrowserLoader\n    active: false\n    sourceComponent: Component {\n      QfFileBrowser {}\n    }\n  }\n'),
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
