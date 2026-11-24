#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — zgodność z QGIS 4.4 (build desktopowy build-sys).

Po co: 21.11.2026 system podniósł libqgis-dev z 4.2.3 do 4.4.0. W QGIS 4.4
około 260 funkcji zwraca std::unique_ptr zamiast zwykłego wskaźnika i build
desktopowy przestał się kompilować (10 błędów w 4 plikach). Android buduje się
z QGIS 4.2.1 z vcpkg — po tej łatce kompiluje się tak samo jak przed nią.

Dwa sposoby, oba działają z QGIS 4.2 i 4.4:
- qfgeofencer.cpp i QfLayerUtils::setDefaultRenderer: DOKŁADNIE ten tekst,
  który ma upstream QField (fb95e5eed, aa3f81694 — #if _QGIS_VERSION_INT >= 40300),
  żeby przyszłe scalenie z upstreamem nie dało konfliktu;
- pozostałe miejsca: std::unique_ptr<T>( wywołanie ) — konstruktor przyjmuje
  i zwykły wskaźnik (4.2), i unique_ptr (4.4), więc bez #if.

Wszystkie pliki są sprawdzane (md5 i kotwice), zanim cokolwiek zostanie
zapisane. Albo zmieniają się wszystkie, albo żaden.

Użycie (z katalogu repozytorium):
  python3 instaluj_zgodnosc_qgis44.py            # próba
  python3 instaluj_zgodnosc_qgis44.py --zapisz   # zapis (kopie .przed_*)
  python3 instaluj_zgodnosc_qgis44.py --katalog X  # inny korzeń repo (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

KATALOG = "/DATA/SOFT/GIS/QFIELD_Pro/QField"

UWAGA = "// WorkFieldGIS 24.11.2026 — QGIS 4.4 zwraca tu std::unique_ptr; ten zapis działa z 4.2 (Android) i z 4.4 (desktop)."

PLIKI = {
    "src/core/moduly/inwentaryzacjadrzew.cpp": {
        "przed": "36c492b1826201b83fafdeaacb36e8a3",
        "po": "3532a3326b74b26584fa852c7cfbf7fa",
        "zmiany": [
            ("\n      QgsSymbolLayer *generator = QgsGeometryGeneratorSymbolLayer::create( w );\n",
             "\n      " + UWAGA + "\n"
             "      QgsSymbolLayer *generator = std::unique_ptr<QgsSymbolLayer>( QgsGeometryGeneratorSymbolLayer::create( w ) ).release();\n"),
        ],
    },
    "src/core/positioning/qfgeofencer.cpp": {
        "przed": "8924f2132fbfb93dc31b01de258081ea",
        "po": "134dced980844b533120b26d13bf8a71",
        "zmiany": [
            # tekst upstreamu QField, fb95e5eed
            ("\n    std::unique_ptr<QgsGeometryEngine> geometryEngine;\n"
             "    geometryEngine.reset( QgsGeometry::createGeometryEngine( &mPosition ) );\n",
             "\n    std::unique_ptr<QgsGeometryEngine> geometryEngine;\n"
             "#if _QGIS_VERSION_INT >= 40300\n"
             "    geometryEngine = QgsGeometry::createGeometryEngine( &mPosition );\n"
             "#else\n"
             "    geometryEngine.reset( QgsGeometry::createGeometryEngine( &mPosition ) );\n"
             "#endif\n"),
        ],
    },
    "src/core/utils/qflayerutils.cpp": {
        "przed": "5da9eb3e8d058cc238788a4a2b4a4651",
        "po": "047a3027cb606adf942f54b4550d22a3",
        "zmiany": [
            # tekst upstreamu QField, aa3f81694 / 536e51848
            ("\n  QgsSymbol *symbol = project ? project->styleSettings()->defaultSymbol( symbolType ) : nullptr;\n"
             "  if ( !symbol )\n"
             "  {\n"
             "    symbol = QfLayerUtils::defaultSymbol( layer, attachmentField, colorField );\n"
             "  }\n"
             "\n"
             "  QgsSingleSymbolRenderer *renderer = new QgsSingleSymbolRenderer( symbol );\n",
             "\n  std::unique_ptr<QgsSymbol> symbol;\n"
             "  if ( project )\n"
             "  {\n"
             "#if _QGIS_VERSION_INT >= 40300\n"
             "    symbol = project->styleSettings()->defaultSymbol( symbolType );\n"
             "#else\n"
             "    symbol.reset( project->styleSettings()->defaultSymbol( symbolType ) );\n"
             "#endif\n"
             "  }\n"
             "\n"
             "  if ( !symbol )\n"
             "  {\n"
             "    symbol.reset( QfLayerUtils::defaultSymbol( layer, attachmentField, colorField ) );\n"
             "  }\n"
             "\n"
             "  QgsSingleSymbolRenderer *renderer = new QgsSingleSymbolRenderer( symbol.release() );\n"),
            ("\nstatic QgsColorRamp *rampByName( const QString &rampName )\n{\n"
             "  QgsStyle *style = QgsStyle::defaultStyle();\n"
             "  if ( style && style->colorRampNames().contains( rampName ) )\n"
             "    return style->colorRamp( rampName );\n"
             "\n"
             "  if ( style && !style->colorRampNames().isEmpty() )\n"
             "    return style->colorRamp( style->colorRampNames().first() );\n",
             "\nstatic QgsColorRamp *rampByName( const QString &rampName )\n{\n"
             "  " + UWAGA + "\n"
             "  QgsStyle *style = QgsStyle::defaultStyle();\n"
             "  if ( style && style->colorRampNames().contains( rampName ) )\n"
             "    return std::unique_ptr<QgsColorRamp>( style->colorRamp( rampName ) ).release();\n"
             "\n"
             "  if ( style && !style->colorRampNames().isEmpty() )\n"
             "    return std::unique_ptr<QgsColorRamp>( style->colorRamp( style->colorRampNames().first() ) ).release();\n"),
        ],
    },
    "src/core/utils/qfprojectutils.cpp": {
        "przed": "dac3695dddb6c61e4d804df866e5e6a4",
        "po": "9227bdb49aa85187d06e1e4b132e7691",
        "zmiany": [
            ("\n    QgsVectorFileWriter *writer = QgsVectorFileWriter::create( notesFilepath, notesFields, Qgis::WkbType::PointZ, QgsCoordinateReferenceSystem( \"EPSG:4326\" ), createdProject->transformContext(), writerOptions );\n"
             "    delete writer;\n",
             "\n    " + UWAGA + "\n"
             "    std::unique_ptr<QgsVectorFileWriter> writer( QgsVectorFileWriter::create( notesFilepath, notesFields, Qgis::WkbType::PointZ, QgsCoordinateReferenceSystem( \"EPSG:4326\" ), createdProject->transformContext(), writerOptions ) );\n"
             "    writer.reset();\n"),
            ("\n      writer = QgsVectorFileWriter::create( notesFilepath, notesFields, Qgis::WkbType::LineStringZ, QgsCoordinateReferenceSystem( \"EPSG:4326\" ), createdProject->transformContext(), writerOptions );\n"
             "      delete writer;\n",
             "\n      writer = std::unique_ptr<QgsVectorFileWriter>( QgsVectorFileWriter::create( notesFilepath, notesFields, Qgis::WkbType::LineStringZ, QgsCoordinateReferenceSystem( \"EPSG:4326\" ), createdProject->transformContext(), writerOptions ) );\n"
             "      writer.reset();\n"),
            ("\n      writer = QgsVectorFileWriter::create( notesFilepath, notesFields, Qgis::WkbType::PolygonZ, QgsCoordinateReferenceSystem( \"EPSG:4326\" ), createdProject->transformContext(), writerOptions );\n"
             "      delete writer;\n",
             "\n      writer = std::unique_ptr<QgsVectorFileWriter>( QgsVectorFileWriter::create( notesFilepath, notesFields, Qgis::WkbType::PolygonZ, QgsCoordinateReferenceSystem( \"EPSG:4326\" ), createdProject->transformContext(), writerOptions ) );\n"
             "      writer.reset();\n"),
            ("\n      QgsVectorFileWriter *attachWriter = QgsVectorFileWriter::create( notesFilepath, attachFields, Qgis::WkbType::NoGeometry, QgsCoordinateReferenceSystem(), createdProject->transformContext(), writerOptions );\n"
             "      delete attachWriter;\n",
             "\n      std::unique_ptr<QgsVectorFileWriter> attachWriter( QgsVectorFileWriter::create( notesFilepath, attachFields, Qgis::WkbType::NoGeometry, QgsCoordinateReferenceSystem(), createdProject->transformContext(), writerOptions ) );\n"
             "      attachWriter.reset();\n"),
            ("\n    QgsVectorFileWriter *writer = QgsVectorFileWriter::create( tracksFilepath, fields, Qgis::WkbType::LineStringZM, QgsCoordinateReferenceSystem( \"EPSG:4326\" ), createdProject->transformContext(), writerOptions );\n"
             "    delete writer;\n",
             "\n    " + UWAGA + "\n"
             "    std::unique_ptr<QgsVectorFileWriter> writer( QgsVectorFileWriter::create( tracksFilepath, fields, Qgis::WkbType::LineStringZM, QgsCoordinateReferenceSystem( \"EPSG:4326\" ), createdProject->transformContext(), writerOptions ) );\n"
             "    writer.reset();\n"),
        ],
    },
}


def md5(dane):
    return hashlib.md5(dane).hexdigest()


def main():
    argv = sys.argv[1:]
    zapisz = "--zapisz" in argv
    katalog = KATALOG
    if "--katalog" in argv:
        katalog = argv[argv.index("--katalog") + 1]

    plan = []
    gotowe = 0
    blad = False
    for sciezka, opis in PLIKI.items():
        plik = os.path.join(katalog, sciezka)
        with open(plik, "rb") as f:
            surowe = f.read()
        teraz = md5(surowe)
        if teraz == opis["po"]:
            print("JUŻ ZAINSTALOWANE:", sciezka)
            gotowe += 1
            continue
        if teraz != opis["przed"]:
            print("STOP:", sciezka, "md5", teraz, "zamiast", opis["przed"])
            blad = True
            continue
        tekst = surowe.decode("utf-8")
        for nr, (stare, _nowe) in enumerate(opis["zmiany"], 1):
            ile = tekst.count(stare)
            if ile != 1:
                print("STOP:", sciezka, "kotwica %d występuje %d razy (ma być 1)" % (nr, ile))
                blad = True
        if blad:
            continue
        for stare, nowe in opis["zmiany"]:
            tekst = tekst.replace(stare, nowe, 1)
        nowe_bajty = tekst.encode("utf-8")
        print("%-45s %s -> %s  (+%d linii)" % (sciezka, teraz, md5(nowe_bajty),
                                               nowe_bajty.count(b"\n") - surowe.count(b"\n")))
        plan.append((plik, nowe_bajty))

    if blad:
        print("Któryś plik różni się od wersji, na której zbudowano łatkę. Nic nie zapisano. "
              "Nie nadpisuję cudzej pracy — przyślij te pliki.")
        return 1
    if gotowe == len(PLIKI):
        print("Wszystko już zainstalowane — nic nie zmieniam.")
        return 0
    if gotowe:
        print("STOP: część plików już zmieniona, część nie. Nic nie zapisano — przyślij wynik.")
        return 1
    if not zapisz:
        print("PRÓBA — nic nie zapisano. Zapis: dopisz --zapisz")
        return 0

    znacznik = datetime.now().strftime("%Y%m%d_%H%M%S")
    for plik, nowe_bajty in plan:
        shutil.copy2(plik, plik + ".przed_" + znacznik)
        with open(plik, "wb") as f:
            f.write(nowe_bajty)
        print("ZAPISANO:", plik)
    print("Kopie: *.przed_" + znacznik)
    return 0


if __name__ == "__main__":
    sys.exit(main())
