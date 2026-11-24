#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-QML-PROFILE] TYMCZASOWE — poprawka połączenia z qmlprofiler (druga łatka, po instaluj_profil_qml.py).

Do jednorazowego pomiaru qmlprofiler na desktopie. NIE DO COMMITA I NIE DO APK.
Debugowanie włącza się tylko przy zmiennej WF_QML_PROFILE=1. Po pomiarze:
  git checkout -- src/app/main.cpp

Użycie (z katalogu repozytorium):
  python3 instaluj_profil_qml_polaczenie.py            # próba, nic nie zapisuje
  python3 instaluj_profil_qml_polaczenie.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_profil_qml_polaczenie.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/main.cpp"
MD5_PRZED = "29ad6546b6fcee850f40de139acdd595"  # po instaluj_profil_qml.py (24.11.2026)
MD5_PO = "e2ea659e5dce6f027efa6fa79278a73f"

ZMIANY = [
    ('  if ( qEnvironmentVariableIsSet( "WF_QML_PROFILE" ) )\n    QQmlDebuggingEnabler::enableDebugging( true );\n',
     '  // [WF-QML-PROFILE] Atrapa QCoreApplication niżej usuwa z argv „-qmljsdebugger=”, więc\n'
     '  // gniazdo qmlprofilera zapamiętujemy tu i łączymy się ręcznie po utworzeniu QgsApplication.\n'
     '  QString wfQmlProfileSocket;\n'
     '  if ( qEnvironmentVariableIsSet( "WF_QML_PROFILE" ) )\n'
     '  {\n'
     '    QQmlDebuggingEnabler::enableDebugging( true );\n'
     '    for ( int i = 1; i < argc; ++i )\n'
     '    {\n'
     '      const QByteArray argument( argv[i] );\n'
     '      if ( argument.startsWith( "-qmljsdebugger=file:" ) )\n'
     '        wfQmlProfileSocket = QString::fromLocal8Bit( argument.mid( 20 ) ).section( \',\', 0, 0 );\n'
     '    }\n'
     '  }\n'),
    ('\n  QgsApplication app( argc, argv, true, profilePath, QStringLiteral( "mobile" ) );\n',
     '\n  QgsApplication app( argc, argv, true, profilePath, QStringLiteral( "mobile" ) );\n'
     '  if ( !wfQmlProfileSocket.isEmpty() ) // [WF-QML-PROFILE] TYMCZASOWE\n'
     '    qInfo() << "WF-QML-PROFILE: łączę z qmlprofiler" << wfQmlProfileSocket\n'
     '            << QQmlDebuggingEnabler::connectToLocalDebugger( wfQmlProfileSocket, QQmlDebuggingEnabler::WaitForClient );\n'),
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
