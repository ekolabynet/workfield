#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-PERF] łatka pomiarowa NarzedziaProjektu::stanProjektu().

Po co: tester zgłosił, że WFG jest wolny na starszym telefonie. stanProjektu()
czyta wszystkie obiekty warstw poligonowych (z geometrią) i przechodzi
identyfikatory — na wątku interfejsu, przy każdym otwarciu menu bocznego.
Ta łatka NICZEGO nie przyspiesza. Tylko mierzy i pisze jedną linijkę do
dziennika komunikatów aplikacji:

  WorkField [WF-PERF]: stanProjektu 1234 ms — poligony 1100 ms (45000 obiektów,
  6 warstw), identyfikatory 90 ms, reszta 44 ms; najdłużej: EGiB działki: ...

Poziom Info, a od 300 ms Warning. Szczegóły per warstwa: kategoria
workfield.performance (domyślnie milczy, QT_LOGGING_RULES="workfield.performance=true").

Użycie (z katalogu repozytorium):
  python3 instaluj_pomiar_stanu_projektu.py            # próba, nic nie zapisuje
  python3 instaluj_pomiar_stanu_projektu.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_pomiar_stanu_projektu.py --plik X   # inny plik (test)
"""
import hashlib
import shutil
import sys
from datetime import datetime

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp"
MD5_PRZED = "e2e8fae4a42e1b189c006d3f75fe7c94"  # GitHub development, 0853e6da7 (25.10.2026)
MD5_PO = "9b592a956b3a2ac8cd5df7c5eeefb85c"

ZMIANY = [
    # 1. nagłówki
    ("\n#include <QHash>\n",
     "\n#include <QHash>\n"
     "#include <QElapsedTimer>   // [WF-PERF]\n"
     "#include <QLoggingCategory> // [WF-PERF]\n"
     "#include <algorithm>        // [WF-PERF]\n"
     "#include <qgsmessagelog.h>  // [WF-PERF]\n"),
    # 2. kategoria logowania i próg
    ("\n#include <ogr_api.h>\n\nNarzedziaProjektu::NarzedziaProjektu( QObject *parent )\n",
     "\n#include <ogr_api.h>\n"
     "\n"
     "// WorkFieldGIS 24.11.2026 — [WF-PERF] pomiar stanProjektu().\n"
     "// Tester zgłosił, że WFG jest wolny na starszym telefonie. stanProjektu()\n"
     "// czyta WSZYSTKIE obiekty warstw poligonowych (z geometrią) i przechodzi\n"
     "// identyfikatory — na wątku interfejsu, przy każdym otwarciu menu.\n"
     "// Zanim to przeniesiemy, mierzymy: ile trwa i ile obiektów czyta.\n"
     "// Podsumowanie idzie zawsze do dziennika komunikatów (Info; od\n"
     "// kSlowStatusMs — Warning). Szczegóły per warstwa domyślnie milczą:\n"
     "//\n"
     "//     QT_LOGGING_RULES=\"workfield.performance=true\"\n"
     "//\n"
     "// Punkt pomiarowy zostaje w kodzie (ZASADY_LATEK.md).\n"
     "Q_LOGGING_CATEGORY( wfgPerformance, \"workfield.performance\", QtWarningMsg )\n"
     "static constexpr qint64 kSlowStatusMs = 300; // [WF-PERF]\n"
     "\n"
     "NarzedziaProjektu::NarzedziaProjektu( QObject *parent )\n"),
    # 3. początek stanProjektu: zegary
    ("  if ( !projekt )\n    return wynik;\n\n  QVariantList warstwy;\n  QVariantList ostrzezenia;\n",
     "  if ( !projekt )\n    return wynik;\n"
     "\n"
     "  // [WF-PERF] 24.11.2026 — czas całości, skanu poligonów i identyfikatorów\n"
     "  QElapsedTimer totalTimer;\n"
     "  totalTimer.start();\n"
     "  qint64 polygonScanMs = 0;\n"
     "  qlonglong polygonScanFeatures = 0;\n"
     "  qint64 identityMs = 0;\n"
     "  QList<QPair<qint64, QString>> layerTimings;\n"
     "\n"
     "  QVariantList warstwy;\n  QVariantList ostrzezenia;\n"),
    # 4. zegar warstwy poligonowej
    ("\n      int puste = 0;\n",
     "\n      int puste = 0;\n"
     "      QElapsedTimer layerTimer; // [WF-PERF]\n"
     "      layerTimer.start();\n"
     "      qlonglong readFeatures = 0;\n"),
    # 5. licznik obiektów
    ("      while ( iterator.nextFeature( obiekt ) )\n      {\n        const QgsGeometry geom = obiekt.geometry();\n",
     "      while ( iterator.nextFeature( obiekt ) )\n      {\n"
     "        ++readFeatures; // [WF-PERF]\n"
     "        const QgsGeometry geom = obiekt.geometry();\n"),
    # 6. wynik warstwy
    ("\n      if ( puste > 0 )\n",
     "\n"
     "      // [WF-PERF] czas i liczba obiektów tej warstwy\n"
     "      const qint64 layerMs = layerTimer.elapsed();\n"
     "      polygonScanMs += layerMs;\n"
     "      polygonScanFeatures += readFeatures;\n"
     "      layerTimings.append( qMakePair( layerMs, QStringLiteral( \"%1: %2 ms / %3 obiektów\" )\n"
     "                                                 .arg( wektor->name() )\n"
     "                                                 .arg( layerMs )\n"
     "                                                 .arg( readFeatures ) ) );\n"
     "      qCDebug( wfgPerformance, \"WorkField/Wydajnosc: stanProjektu poligony %s: %lld ms, %lld obiektow\",\n"
     "               qPrintable( wektor->name() ), static_cast<long long>( layerMs ), static_cast<long long>( readFeatures ) );\n"
     "      if ( puste > 0 )\n"),
    # 7. identyfikatory
    ("    const QVariantList identity = identityIssues( projekt );\n    QStringList missingIn;\n",
     "    QElapsedTimer identityTimer; // [WF-PERF]\n"
     "    identityTimer.start();\n"
     "    const QVariantList identity = identityIssues( projekt );\n"
     "    identityMs = identityTimer.elapsed();\n"
     "    QStringList missingIn;\n"),
    # 8. podsumowanie
    ("\n  wynik.insert( QStringLiteral( \"warstwy\" ), warstwy );\n",
     "\n"
     "  // [WF-PERF] podsumowanie — zawsze jedna linijka w dzienniku komunikatów\n"
     "  {\n"
     "    const qint64 totalMs = totalTimer.elapsed();\n"
     "    std::sort( layerTimings.begin(), layerTimings.end(), []( const QPair<qint64, QString> &a, const QPair<qint64, QString> &b ) {\n"
     "      return a.first > b.first;\n"
     "    } );\n"
     "    QStringList slowest;\n"
     "    for ( int i = 0; i < layerTimings.size() && i < 3; ++i )\n"
     "      slowest << layerTimings.at( i ).second;\n"
     "    const QString text = QStringLiteral( \"WorkField [WF-PERF]: stanProjektu %1 ms — poligony %2 ms (%3 obiektów, %4 warstw), \"\n"
     "                                         \"identyfikatory %5 ms, reszta %6 ms%7\" )\n"
     "                           .arg( totalMs )\n"
     "                           .arg( polygonScanMs )\n"
     "                           .arg( polygonScanFeatures )\n"
     "                           .arg( layerTimings.size() )\n"
     "                           .arg( identityMs )\n"
     "                           .arg( totalMs - polygonScanMs - identityMs )\n"
     "                           .arg( slowest.isEmpty() ? QString() : QStringLiteral( \"; najdłużej: \" ) + slowest.join( QStringLiteral( \", \" ) ) );\n"
     "    QgsMessageLog::logMessage( text, QStringLiteral( \"WorkField\" ), totalMs >= kSlowStatusMs ? Qgis::Warning : Qgis::Info );\n"
     "    qCDebug( wfgPerformance, \"%s\", qPrintable( text ) );\n"
     "  }\n"
     "\n"
     "  wynik.insert( QStringLiteral( \"warstwy\" ), warstwy );\n"),
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
    shutil.copy2(plik, kopia)
    with open(plik, "wb") as f:
        f.write(nowe_bajty)
    print("ZAPISANO. Kopia:", kopia)
    return 0


if __name__ == "__main__":
    sys.exit(main())
