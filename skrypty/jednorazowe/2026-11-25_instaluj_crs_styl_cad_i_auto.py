#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[WF-CRS-CONVERT-STYLE] + [WF-CRS-AUTO] 25.11.2026 — poprawki po teście Piotra (7:22).

1. narzedziaprojektu.cpp: konwersja rysunku CAD zachowuje kolory i grubości.
   DXF podaje styl każdej encji w locie (renderer „embeddedSymbol”), GeoPackage
   tego nie umie — po konwersji wszystko miało jeden domyślny kolor. Teraz styl
   encji idzie do pola cad_style, a warstwa dostaje styl kategoryzowany.
2. QgisMobileapp.qml: warstwa bez układu (DXF), której liczby pasują do układu
   projektu, dostaje układ w locie bez pytania — to nie kolizja, tylko brak
   metryczki. Okno zostaje dla prawdziwych kolizji i zamienionych osi.

Domyślnie próba. Zapis: --zapisz. Test na kopii: --plik-cpp X --plik-okna Y.
Miejsce w repo: skrypty/jednorazowe/2026-11-25_instaluj_crs_styl_cad_i_auto.py
"""
import hashlib
import shutil
import sys
import time

REPO = "/DATA/SOFT/GIS/QFIELD_Pro/QField"
PLIK_CPP = REPO + "/src/core/utils/narzedziaprojektu.cpp"
PLIK_OKNA = REPO + "/src/app/qml/QgisMobileapp.qml"

CPP_MD5_PRZED = "42e5693236568b2a3e3530c4fcbe5657"
CPP_MD5_PO = "9cadd6c3c733379f7b92c0b2a739bdc5"
OKNO_MD5_PRZED = "9846623324b94e91e83fba9b661bb78f"
OKNO_MD5_PO = "f431553b6728caa04e391f412468ff17"

# ── narzedziaprojektu.cpp ─────────────────────────────────────────────────────
INC_STARE = "#include <qgsvectorfilewriter.h>        // [WF-CRS-DETECT]\n"
INC_NOWE = INC_STARE + (
    "#include <qgscategorizedsymbolrenderer.h> // [WF-CRS-CONVERT-STYLE]\n"
    "#include <qgsembeddedsymbolrenderer.h>    // [WF-CRS-CONVERT-STYLE]\n"
    "#include <qgssymbol.h>                    // [WF-CRS-CONVERT-STYLE]\n"
    "#include <qgssymbollayerutils.h>          // [WF-CRS-CONVERT-STYLE]\n")

Z1_STARE = """  QString newFile;
  QString newLayerName;
  std::unique_ptr<QgsVectorFileWriter> writer( QgsVectorFileWriter::create( gpkg, layer->fields(), layer->wkbType(), target, project->transformContext(), options,
"""
Z1_NOWE = """  // [WF-CRS-CONVERT-STYLE] 25.11.2026 — rysunek CAD (DXF) nie ma stylu warstwy:
  // kolor i grubość każdej encji podaje sterownik w locie (renderer
  // „embeddedSymbol”). GeoPackage tego nie umie, więc po konwersji całość
  // dostawała jeden domyślny kolor (Piotr 7:22, zmierzone na QGIS 3.34).
  // Styl encji zapisujemy w polu cad_style, a warstwa dostaje styl
  // kategoryzowany z tymi samymi symbolami.
  const bool embeddedStyle = layer->renderer() && layer->renderer()->type() == QLatin1String( "embeddedSymbol" );
  QgsFields outFields = layer->fields();
  QString styleField;
  if ( embeddedStyle )
  {
    styleField = QStringLiteral( "cad_style" );
    for ( int n = 2; outFields.lookupField( styleField ) >= 0; ++n )
      styleField = QStringLiteral( "cad_style_%1" ).arg( n );
#if _QGIS_VERSION_INT >= 33800
    outFields.append( QgsField( styleField, QMetaType::Type::QString ) );
#else
    outFields.append( QgsField( styleField, QVariant::String ) );
#endif
  }
  QHash<QString, QString> styleIds;
  std::vector<std::pair<QString, std::unique_ptr<QgsSymbol>>> styleSymbols;

  QString newFile;
  QString newLayerName;
  std::unique_ptr<QgsVectorFileWriter> writer( QgsVectorFileWriter::create( gpkg, outFields, layer->wkbType(), target, project->transformContext(), options,
"""

Z2_STARE = """  QgsFeatureIterator iterator = layer->getFeatures();
  QgsFeature feature;
  while ( iterator.nextFeature( feature ) )
  {
    if ( feature.hasGeometry() )
    {
      QgsGeometry geometry = feature.geometry();
      if ( swapAxes )"""
Z2_NOWE = """  QgsFeatureRequest request;
  if ( embeddedStyle )
#if _QGIS_VERSION_INT >= 33600
    request.setFlags( Qgis::FeatureRequestFlag::EmbeddedSymbols );
#else
    request.setFlags( QgsFeatureRequest::EmbeddedSymbols );
#endif
  QgsFeatureIterator iterator = layer->getFeatures( request );
  QgsFeature feature;
  while ( iterator.nextFeature( feature ) )
  {
    if ( feature.hasGeometry() )
    {
      QgsGeometry geometry = feature.geometry();
      if ( swapAxes )"""

Z3_STARE = """  fresh->importNamedStyle( style, message );
"""
Z3_NOWE = """  fresh->importNamedStyle( style, message );
  int styleCount = 0;
  if ( embeddedStyle && !styleSymbols.empty() )
  {
    QgsCategoryList categories;
    for ( auto &entry : styleSymbols )
    {
      const QString label = entry.second->color().name();
      categories << QgsRendererCategory( entry.first, entry.second.release(), label );
    }
    // Obiekty bez stylu w rysunku — symbol domyślny rysunku.
    if ( const QgsEmbeddedSymbolRenderer *embedded = dynamic_cast<const QgsEmbeddedSymbolRenderer *>( layer->renderer() ) )
      if ( embedded->defaultSymbol() )
        categories << QgsRendererCategory( QVariant(), embedded->defaultSymbol()->clone(), tr( "bez stylu w rysunku" ) );
    styleCount = static_cast<int>( styleSymbols.size() );
    fresh->setRenderer( new QgsCategorizedSymbolRenderer( styleField, categories ) );
  }
"""

Z4_STARE = """  if ( skipped > 0 )
    text += QLatin1Char( ' ' ) + tr( "Pominięte poza obszarem układu (np. przy punkcie 0,0): %1." ).arg( skipped );
"""
Z4_NOWE = Z4_STARE + """  if ( styleCount > 0 )
    text += QLatin1Char( ' ' ) + tr( "Kolory i grubości z rysunku zachowane (stylów: %1, pole %2)." ).arg( styleCount ).arg( styleField );
"""

Z2B_STARE = """    if ( writer->addFeature( feature ) )
      ++written;
"""
Z2B_NOWE = """    if ( embeddedStyle )
    {
      QString styleId;
      if ( const QgsSymbol *symbol = feature.embeddedSymbol() )
      {
        const QString key = QgsSymbolLayerUtils::symbolProperties( const_cast<QgsSymbol *>( symbol ) );
        styleId = styleIds.value( key );
        if ( styleId.isEmpty() )
        {
          styleId = QStringLiteral( "s%1" ).arg( styleIds.size() + 1 );
          styleIds.insert( key, styleId );
          styleSymbols.emplace_back( styleId, std::unique_ptr<QgsSymbol>( symbol->clone() ) );
        }
      }
      QgsAttributes attributes = feature.attributes();
      attributes.append( styleId.isEmpty() ? QVariant() : QVariant( styleId ) );
      feature.setFields( outFields, false );
      feature.setAttributes( attributes );
    }
""" + Z2B_STARE

ZMIANY_WSPOLNE = [(Z1_STARE, Z1_NOWE), (Z2_STARE, Z2_NOWE), (Z2B_STARE, Z2B_NOWE), (Z3_STARE, Z3_NOWE), (Z4_STARE, Z4_NOWE)]
ZMIANY_CPP = [(INC_STARE, INC_NOWE)] + ZMIANY_WSPOLNE

# ── QgisMobileapp.qml ─────────────────────────────────────────────────────────

Q1_STARE = "    let notes = [];\n    let zoomEntry = null;\n"
Q1_NOWE = Q1_STARE + (
    "    // [WF-CRS-AUTO] 25.11.2026 — do cichego ustawienia układu (niżej)\n"
    "    const projectAuthid = qgisProject && qgisProject.crs ? qgisProject.crs.authid : \"\";\n"
    "    const wasDirty = ProjectUtils.isProjectDirty(qgisProject);\n"
    "    let autoAssigned = 0;\n")

Q2_STARE = "      if (e.kind === \"collision\" || e.kind === \"swapped\") {\n        if (mainWindow.crsQueue.some(q => q.layerId === e.layerId))\n"
Q2_NOWE = (
    "      // [WF-CRS-AUTO] 25.11.2026 — warstwa BEZ układu (DXF go nie niesie),\n"
    "      // a liczby pasują do układu projektu: to nie kolizja rzędów wielkości,\n"
    "      // tylko brak metryczki. Ustawiamy w locie bez pytania, plik bez zmian.\n"
    "      // Piotr 7:22: okno przy każdym rysunku prowadziło do zbędnej konwersji.\n"
    "      if (e.kind === \"collision\" && !e.declared && e.detected === projectAuthid) {\n"
    "        const a = NarzedziaProjektu.assignLayerCrs(qgisProject, e.layerId, e.detected);\n"
    "        console.log(\"WorkField [WF-CRS-AUTO]: \" + trigger + \" — \" + (a.ok ? \"ok\" : \"BŁĄD\") + \": \" + a.opis);\n"
    "        if (a.ok) {\n"
    "          autoAssigned++;\n"
    "          if (e.outside > 0)\n"
    "            notes.push(qsTr(\"„%1”: %2 z %3 obiektów leży poza obszarem układu %4 (np. przy punkcie 0,0) — widok ich nie obejmuje.\").arg(e.name).arg(e.outside).arg(e.total).arg(e.detected));\n"
    "          if (zoom && e.extent && (!zoomEntry || e.inside > zoomEntry.inside))\n"
    "            zoomEntry = e;\n"
    "          continue;\n"
    "        }\n"
    "      }\n") + Q2_STARE

Q3_STARE = "    if (zoomEntry)\n      crsZoomTo(zoomEntry.extent);\n"
Q3_NOWE = (
    "    // Przy otwarciu i z Narzędzi zapisujemy od razu (jak podkład OSM), żeby\n"
    "    // nie powtarzało się przy każdym otwarciu. Rysunek z kreatora zapisuje\n"
    "    // zlozProjektZCAD, a import do projektu i tak go zmienia.\n"
    "    if (autoAssigned > 0 && !wasDirty && trigger !== \"cad\") {\n"
    "      const saved = ProjectUtils.saveProject(qgisProject);\n"
    "      console.log(\"WorkField [WF-CRS-AUTO]: projekt zapisany: \" + saved);\n"
    "    }\n") + Q3_STARE

ZMIANY = [(Q1_STARE, Q1_NOWE), (Q2_STARE, Q2_NOWE), (Q3_STARE, Q3_NOWE)]


def md5(dane):
    return hashlib.md5(dane).hexdigest()


def przygotuj(sciezka, przed, po, zmiany, nazwa):
    """Zwraca (stan, nowe_bajty). stan: 'gotowe', 'juz', 'stop'."""
    try:
        bajty = open(sciezka, "rb").read()
    except OSError as e:
        print("STOP: nie mogę odczytać " + sciezka + ": " + str(e))
        return "stop", None
    m = md5(bajty)
    if m == po:
        print(nazwa + ": JUŻ ZAINSTALOWANE (" + m + ")")
        return "juz", None
    if m != przed:
        print("STOP: " + nazwa + " ma md5 " + m + ", oczekiwane " + przed + ". Nie nadpisuję cudzej pracy.")
        return "stop", None
    tekst = bajty.decode("utf-8")
    for stare, _ in zmiany:
        n = tekst.count(stare)
        if n != 1:
            print("STOP: " + nazwa + ": kotwica występuje " + str(n) + " razy: " + repr(stare[:70]))
            return "stop", None
    for stare, nowe in zmiany:
        tekst = tekst.replace(stare, nowe, 1)
    nowe_bajty = tekst.encode("utf-8")
    linii = tekst.count("\n")
    print(nazwa + ": md5 po zmianie " + md5(nowe_bajty) + ", linii " + str(linii) + " (oczekiwane " + po + ")")
    return "gotowe", nowe_bajty


def main():
    arg = sys.argv[1:]
    zapisz = "--zapisz" in arg
    cpp = PLIK_CPP
    okno = PLIK_OKNA
    if "--plik-cpp" in arg:
        cpp = arg[arg.index("--plik-cpp") + 1]
    if "--plik-okna" in arg:
        okno = arg[arg.index("--plik-okna") + 1]

    s1, b1 = przygotuj(cpp, CPP_MD5_PRZED, CPP_MD5_PO, ZMIANY_CPP, "narzedziaprojektu.cpp")
    s2, b2 = przygotuj(okno, OKNO_MD5_PRZED, OKNO_MD5_PO, ZMIANY, "QgisMobileapp.qml")
    if "stop" in (s1, s2):
        return 1
    if s1 == "juz" and s2 == "juz":
        return 0
    if b1 is not None and md5(b1) != CPP_MD5_PO:
        print("STOP: wynik narzedziaprojektu.cpp różni się od oczekiwanego — nie zapisuję.")
        return 1
    if b2 is not None and md5(b2) != OKNO_MD5_PO:
        print("STOP: wynik QgisMobileapp.qml różni się od oczekiwanego — nie zapisuję.")
        return 1
    if not zapisz:
        print("PRÓBA — nic nie zapisano. Zapis: --zapisz")
        return 0
    znacznik = time.strftime("%Y%m%d_%H%M%S")
    for sciezka, bajty in ((cpp, b1), (okno, b2)):
        if bajty is None:
            continue
        kopia = sciezka + ".przed_" + znacznik
        shutil.copy2(sciezka, kopia)
        with open(sciezka, "wb") as f:
            f.write(bajty)
        print("ZAPISANO " + sciezka + " (kopia: " + kopia + ")")
    return 0


if __name__ == "__main__":
    sys.exit(main())
