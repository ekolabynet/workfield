#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-PERF-START] pomiar startu aplikacji (do utworzenia okna QML).

Refaktoryzacja okna głównego ma skrócić tworzenie QML przy starcie, ale `am start -W`
mierzy tylko pierwszą klatkę (~0,4 s). Ta łatka pisze przy każdym starcie jedną
linijkę do dziennika komunikatów i do logcat: wiek procesu, gdy okno jest gotowe,
w tym czas przed konstruktorem (Qt, QGIS), konstruktor do QML i samo tworzenie
okna QML. Niczego nie przyspiesza.

Użycie (z katalogu repozytorium):
  python3 instaluj_pomiar_startu.py            # próba, nic nie zapisuje
  python3 instaluj_pomiar_startu.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_pomiar_startu.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qgismobileapp.cpp"
MD5_PRZED = "5b926227929948fcd2364b21aa64a67a"  # GitHub development, v0.14.12 = v0.14.13 (plik bez zmian)
MD5_PO = "03e7e0ed521a0f8a6da8b453f4f052c8"

ZMIANY = [
    ('\n#include <QDateTime>\n',
     '\n#include <QDateTime>\n#include <QElapsedTimer> // [WF-PERF-START]\n#include <QFile>         // [WF-PERF-START]\n'),
    ('\nQgisMobileapp::QgisMobileapp( QgsApplication *app, QObject *parent )\n',
     '\n// WorkFieldGIS 24.11.2026 — [WF-PERF-START] pomiar startu. `am start -W` na telefonie\n// mierzy tylko pierwszą klatkę (ekran powitalny, ~0,4 s), a nie utworzenie okna QML —\n// a to właśnie skraca refaktoryzacja okna głównego. Wiek procesu z /proc (Linux,\n// Android; dokładność ~10 ms), gdzie indziej -1. Punkt pomiarowy zostaje w kodzie.\nstatic qint64 wfProcessAgeMs()\n{\n#if defined( Q_OS_LINUX ) || defined( Q_OS_ANDROID )\n  QFile stat( QStringLiteral( "/proc/self/stat" ) );\n  QFile uptime( QStringLiteral( "/proc/uptime" ) );\n  if ( !stat.open( QIODevice::ReadOnly ) || !uptime.open( QIODevice::ReadOnly ) )\n    return -1;\n  const QByteArray statLine = stat.readAll();\n  const int closing = statLine.lastIndexOf( \')\' );\n  if ( closing < 0 )\n    return -1;\n  // after "pid (name) " the fields start at no. 3 (state); starttime is no. 22\n  const QList<QByteArray> fields = statLine.mid( closing + 2 ).split( \' \' );\n  if ( fields.size() < 20 )\n    return -1;\n  const long ticksPerSecond = sysconf( _SC_CLK_TCK );\n  if ( ticksPerSecond <= 0 )\n    return -1;\n  const double startedAfterBoot = fields.at( 19 ).toDouble() / static_cast<double>( ticksPerSecond );\n  const double sinceBoot = uptime.readAll().split( \' \' ).value( 0 ).toDouble();\n  return static_cast<qint64>( ( sinceBoot - startedAfterBoot ) * 1000.0 );\n#else\n  return -1;\n#endif\n}\n\nQgisMobileapp::QgisMobileapp( QgsApplication *app, QObject *parent )\n'),
    ('  , mApp( app )\n{\n  // Set QGIS-specific core settings\n',
     '  , mApp( app )\n{\n  QElapsedTimer startupTimer; // [WF-PERF-START]\n  startupTimer.start();\n  const qint64 processAgeAtStart = wfProcessAgeMs();\n\n  // Set QGIS-specific core settings\n'),
    ('\n  loadFromModule( "org.qfield.app", "QgisMobileapp" );\n',
     '\n  const qint64 beforeQmlMs = startupTimer.elapsed(); // [WF-PERF-START]\n  loadFromModule( "org.qfield.app", "QgisMobileapp" );\n  {\n    const qint64 qmlMs = startupTimer.elapsed() - beforeQmlMs;\n    const qint64 processAgeNow = wfProcessAgeMs();\n    const QString text = QStringLiteral( "WorkField [WF-PERF-START]: okno gotowe %1 ms od startu procesu — przed konstruktorem %2 ms, "\n                                         "konstruktor do QML %3 ms, tworzenie okna QML %4 ms" )\n                           .arg( processAgeNow )\n                           .arg( processAgeAtStart )\n                           .arg( beforeQmlMs )\n                           .arg( qmlMs );\n    QgsMessageLog::logMessage( text, QStringLiteral( "WorkField" ), Qgis::Info );\n    qInfo( "%s", qPrintable( text ) ); // logcat\n  }\n'),
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
