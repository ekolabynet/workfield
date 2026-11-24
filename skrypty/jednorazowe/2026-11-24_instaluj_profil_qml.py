#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-QML-PROFILE] TYMCZASOWE włączenie debugowania QML do profilowania startu.

Do jednorazowego pomiaru qmlprofiler na desktopie. NIE DO COMMITA I NIE DO APK.
Debugowanie włącza się tylko przy zmiennej WF_QML_PROFILE=1. Po pomiarze:
  git checkout -- src/app/main.cpp

Użycie (z katalogu repozytorium):
  python3 instaluj_profil_qml.py            # próba, nic nie zapisuje
  python3 instaluj_profil_qml.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_profil_qml.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/main.cpp"
MD5_PRZED = "ff11fcd6027286ad792ab290d4160dbe"  # GitHub development (plik bez zmian od 13.08.2026)
MD5_PO = "29ad6546b6fcee850f40de139acdd595"

ZMIANY = [
    ('\n#include <QApplication>\n',
     '\n#include <QApplication>\n#include <QtQml/qqmldebug.h> // [WF-QML-PROFILE] TYMCZASOWE\n'),
    ('int main( int argc, char **argv )\n{\n  qputenv( "QT_ANDROID_DISABLE_ACCESSIBILITY", "1" );\n',
     'int main( int argc, char **argv )\n{\n  // WorkFieldGIS 24.11.2026 — [WF-QML-PROFILE] TYMCZASOWE, NIE DO COMMITA: debugowanie QML\n  // dla qmlprofiler (pomiar startu). Tylko przy WF_QML_PROFILE=1. Cofnięcie:\n  //   git checkout -- src/app/main.cpp\n  if ( qEnvironmentVariableIsSet( "WF_QML_PROFILE" ) )\n    QQmlDebuggingEnabler::enableDebugging( true );\n\n  qputenv( "QT_ANDROID_DISABLE_ACCESSIBILITY", "1" );\n'),
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
