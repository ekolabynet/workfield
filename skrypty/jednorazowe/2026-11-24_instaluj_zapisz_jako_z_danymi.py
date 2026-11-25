#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-SAVE-AS-DATA] „Zapisz jako” z danymi, osobno „Zapisz jako nowy pusty projekt”.

Decyzja Piotra 24.11 (20:29), wariant c. Dotąd „Zapisz jako” domyślnie opróżniało warstwy
robocze (pole „Zachowaj obiekty z warstw” odznaczone, decyzja z 19.10) — test SOŁTYKI dał
kopię z 0 obiektów. Teraz w menu dwie pozycje, to samo okno:
  „Zapisz jako…”                    — zaznaczone „Zachowaj obiekty” i „Kopiuj załączniki”,
  „Zapisz jako nowy pusty projekt…” — oba odznaczone (dawne zachowanie).
Ortofotomapy i podkłady bez zmian (domyślnie wspólne z oryginałem, decyzja 19.10).

Użycie (z katalogu repozytorium):
  python3 instaluj_zapisz_jako_z_danymi.py            # próba, nic nie zapisuje
  python3 instaluj_zapisz_jako_z_danymi.py --zapisz   # zapis (z kopią .przed_*)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfMainDrawer.qml'
MD5_PRZED = '0d62e60400e5e81fd50ee83f0e36a21d'  # GitHub development 9f2ab088b
MD5_PO = '1f15e8b18bb2a05218f99832b703d0d4'

ZMIANY = [
    ('          onClicked: projectNameDialog.openFor("saveas")\n        }\n',
     '          onClicked: projectNameDialog.openFor("saveas", true)\n        }\n        // WorkFieldGIS 24.11.2026 — [WF-SAVE-AS-DATA] decyzja Piotra: „Zapisz jako”\n        // kopiuje projekt RAZEM z danymi, a pusty wzór na nowy teren to osobna pozycja.\n        // Dotąd „Zapisz jako” domyślnie opróżniało warstwy — zaskoczyło nawet autora.\n        QfPozycjaMenu {\n          text: qsTr("Zapisz jako nowy pusty projekt…")\n          ikona: "wfg_zapisz_jako"\n          enabled: projectSection.filePath !== ""\n          onClicked: projectNameDialog.openFor("saveas", false)\n        }\n'),
    ('         : qsTr("Zapisz jako nowy projekt")\n',
     '         : keepObjects ? qsTr("Zapisz jako") : qsTr("Zapisz jako nowy pusty projekt") // [WF-SAVE-AS-DATA]\n'),
    ('    property string nazwaKopii: ""\n',
     '    property string nazwaKopii: ""\n    //! [WF-SAVE-AS-DATA] true: kopia z obiektami i zdjęciami; false: pusty wzór\n    property bool keepObjects: true\n'),
    ('    function openFor(newMode) {\n      mode = newMode;\n',
     '    function openFor(newMode, keepData) {\n      mode = newMode;\n      keepObjects = keepData !== false; // [WF-SAVE-AS-DATA]\n'),
    ('        kopiujZalaczniki.checked = false;\n        zachowajObiekty.checked = false;\n',
     '        // [WF-SAVE-AS-DATA] „Zapisz jako” = obiekty i zdjęcia razem (inaczej wiersze\n        // załączników wskazywałyby na brakujące pliki); „pusty projekt” = bez nich.\n        // Oba pola zostają widoczne — człowiek może zmienić zdanie w oknie.\n        kopiujZalaczniki.checked = keepObjects;\n        zachowajObiekty.checked = keepObjects;\n'),
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
