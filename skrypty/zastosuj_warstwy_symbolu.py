#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 37 — WARSTWY SYMBOLU: znacznik stanu i znaczniki na wierzcholkach.

Domyka dwa watki z tej sesji naraz.

WATEK 1: wtyczka „Zrobione" dziala, ale stan widac wylacznie w toascie.
Na mapie nie widac NIC — a caly sens odhaczania polega na tym, zeby jednym
spojrzeniem wiedziec, co zostalo. Znacznik w srodku poligonu, kolorowany
wartoscia pola, zalatwia to bez ruszania wypelnienia: kategoria roslinnosci
zostaje w swoim kolorze, stan siedzi obok.

WATEK 2: samoprzeciecia („osemki") sa niewidoczne, bo nie widac, GDZIE
naprawde siedza wierzcholki. Znaczniki na wierzcholkach pokazuja to wprost —
jedna warstwa symbolu, dwa problemy.

DLACZEGO WARSTWY SYMBOLU, A NIE DRUGA WARSTWA MAPY
--------------------------------------------------
Ustalone w rozmowie 19.08: „dodanie warstwy do symbolu", „centroid",
„obrys z wierzcholkow" i „raster jako symbol punktu" to NIE sa cztery
funkcje. To jeden byt — warstwa symbolu — w czterech wariantach. QGIS ma
je wszystkie w rdzeniu; my dokladamy tylko czasowniki.

Znacznik w srodku to `QgsCentroidFillSymbolLayer` z markerem w srodku,
a nie osobna warstwa punktowa: brak drugiej tabeli, brak synchronizacji,
brak czegokolwiek do zepsucia przy zwrocie z terenu.

`setPointOnSurface(true)` — swiadomie. Geometryczny centroid platu w ksztalcie
litery C wypada POZA platem; punkt-na-powierzchni zawsze jest w srodku.
W terenie znacznik obok obiektu, do ktorego nalezy, jest gorszy niz brak.

TRZY CZASOWNIKI (angielskie, konwencja od 19.08):
  addStatusMarker( layer, field )   — znacznik kolorowany wartoscia pola
  addVertexMarkers( layer, color )  — znaczniki na wierzcholkach
  removeExtraSymbolLayers( layer )  — zdejmuje dolozone, zostawia pierwsza

Wszystkie trzy dzialaja na KAZDYM rendererze (pojedynczy, kategorie,
przedzialy), bo ida przez `renderer->symbols()` — wiec znacznik stanu dziala
razem z kolorowaniem kategorii, nie zamiast niego.

Uruchom w korzeniu repo:  python3 zastosuj_warstwy_symbolu.py
Idempotentna. Kopie: <plik>.przed_symbolami
"""
import os
import shutil
import sys

H = "src/core/utils/layerutils.h"
C = "src/core/utils/layerutils.cpp"
Q = "src/gui/qml/LayerTreeItemProperties.qml"

MARKER = "addStatusMarker"

# ------------------------------------------------------------------ naglowek

H_ANCHOR = "    static Q_INVOKABLE QVariantList colorRampNames();"

H_NEW = '''    /**
     * Dokłada znacznik w środku każdego poligonu, kolorowany wartością pola
     * \\a fieldName (NIE / CZĘŚCIOWO / KOMPLET). Wypełnienie warstwy zostaje
     * nietknięte, więc stan jest widoczny RAZEM z kategorią, nie zamiast niej.
     */
    static Q_INVOKABLE bool addStatusMarker( QgsVectorLayer *layer, const QString &fieldName );

    /**
     * Dokłada znaczniki na wierzchołkach geometrii (poligony i linie).
     * Pokazuje, gdzie naprawdę siedzą wierzchołki — przypadkowe samoprzecięcie
     * przestaje być niewidzialne.
     */
    static Q_INVOKABLE bool addVertexMarkers( QgsVectorLayer *layer, const QColor &color = QColor( 255, 255, 255 ), double size = 1.6 );

    //! Zdejmuje dołożone warstwy symbolu, zostawiając pierwszą (podstawową).
    static Q_INVOKABLE bool removeExtraSymbolLayers( QgsVectorLayer *layer );

'''

# --------------------------------------------------------------- implementacja

C_INCLUDE_OLD = "#include <qgscolorramp.h>"
C_INCLUDE_NEW = """#include <qgscentroidfillsymbollayer.h>
#include <qgscolorramp.h>"""

C_ANCHOR = "QVariantList LayerUtils::colorRampNames()"

C_NEW = r'''namespace
{
  /**
   * Wszystkie symbole renderera — jeden dla symbolu pojedynczego, po jednym
   * na kategorię przy kategoriach. Dzięki temu znacznik stanu dokłada się
   * RAZEM z kolorowaniem kategorii, a nie zamiast niego.
   */
  QgsSymbolList symbolsOf( QgsVectorLayer *layer )
  {
    if ( !layer || !layer->renderer() )
      return QgsSymbolList();

    QgsRenderContext context;
    return layer->renderer()->symbols( context );
  }

  void repaintStyle( QgsVectorLayer *layer )
  {
    layer->triggerRepaint();
    emit layer->styleChanged();
  }
}

bool LayerUtils::addStatusMarker( QgsVectorLayer *layer, const QString &fieldName )
{
  if ( !layer || fieldName.isEmpty() )
    return false;

  if ( layer->geometryType() != Qgis::GeometryType::Polygon )
    return false;

  if ( layer->fields().lookupField( fieldName ) < 0 )
    return false;

  const QgsSymbolList symbols = symbolsOf( layer );
  if ( symbols.isEmpty() )
    return false;

  // Kolor z wartości pola. Wszystko, co nie jest znanym stanem — także pusta
  // wartość — czyta się jako "nie zrobione": brak informacji to nie to samo
  // co informacja o gotowości.
  const QString expression = QStringLiteral(
                               "CASE WHEN \"%1\" = 'KOMPLET' THEN '#66bb6a' "
                               "WHEN \"%1\" = 'CZĘŚCIOWO' THEN '#ffa726' "
                               "ELSE '#ef5350' END" )
                               .arg( fieldName );

  for ( QgsSymbol *symbol : symbols )
  {
    if ( !symbol || symbol->type() != Qgis::SymbolType::Fill )
      continue;

    std::unique_ptr<QgsSimpleMarkerSymbolLayer> marker(
      new QgsSimpleMarkerSymbolLayer( Qgis::MarkerShape::Circle, 3.6 ) );
    marker->setColor( QColor( 239, 83, 80 ) );
    marker->setStrokeColor( QColor( 255, 255, 255 ) );
    marker->setStrokeWidth( 0.4 );
    marker->setDataDefinedProperty( QgsSymbolLayer::Property::FillColor,
                                    QgsProperty::fromExpression( expression ) );

    QgsSymbolLayerList lista;
    lista << marker.release();
    std::unique_ptr<QgsMarkerSymbol> markerSymbol( new QgsMarkerSymbol( lista ) );

    std::unique_ptr<QgsCentroidFillSymbolLayer> centroid( new QgsCentroidFillSymbolLayer() );
    // Centroid geometryczny płatu w kształcie litery C wypada POZA płatem.
    // Punkt na powierzchni zawsze jest w środku — znacznik obok obiektu,
    // do którego należy, byłby gorszy niż brak znacznika.
    centroid->setPointOnSurface( true );
    centroid->setPointOnAllParts( false );
    centroid->setSubSymbol( markerSymbol.release() );

    symbol->appendSymbolLayer( centroid.release() );
  }

  repaintStyle( layer );
  return true;
}

bool LayerUtils::addVertexMarkers( QgsVectorLayer *layer, const QColor &color, double size )
{
  if ( !layer )
    return false;

  const Qgis::GeometryType type = layer->geometryType();
  if ( type != Qgis::GeometryType::Polygon && type != Qgis::GeometryType::Line )
    return false;

  const QgsSymbolList symbols = symbolsOf( layer );
  if ( symbols.isEmpty() )
    return false;

  for ( QgsSymbol *symbol : symbols )
  {
    if ( !symbol )
      continue;

    std::unique_ptr<QgsSimpleMarkerSymbolLayer> marker(
      new QgsSimpleMarkerSymbolLayer( Qgis::MarkerShape::Square, size ) );
    marker->setColor( color );
    marker->setStrokeColor( QColor( 0, 0, 0 ) );
    marker->setStrokeWidth( 0.2 );

    QgsSymbolLayerList lista;
    lista << marker.release();
    std::unique_ptr<QgsMarkerSymbol> markerSymbol( new QgsMarkerSymbol( lista ) );

    std::unique_ptr<QgsMarkerLineSymbolLayer> linia( new QgsMarkerLineSymbolLayer() );
    linia->setPlacements( Qgis::MarkerLinePlacement::Vertex );
    linia->setSubSymbol( markerSymbol.release() );

    symbol->appendSymbolLayer( linia.release() );
  }

  repaintStyle( layer );
  return true;
}

bool LayerUtils::removeExtraSymbolLayers( QgsVectorLayer *layer )
{
  const QgsSymbolList symbols = symbolsOf( layer );
  if ( symbols.isEmpty() )
    return false;

  bool zdjete = false;
  for ( QgsSymbol *symbol : symbols )
  {
    if ( !symbol )
      continue;
    while ( symbol->symbolLayerCount() > 1 )
    {
      symbol->deleteSymbolLayer( symbol->symbolLayerCount() - 1 );
      zdjete = true;
    }
  }

  if ( zdjete )
    repaintStyle( layer );
  return zdjete;
}

'''

# ------------------------------------------------------------------------ QML

Q_ANCHOR = """          // pasek podgladu wybranej rampy"""

Q_NEW = '''          // WorkField 19.08.2026: warstwy symbolu. Znacznik stanu i wierzchołki
          // to jeden byt w dwóch wariantach — dokładane DO symbolu warstwy,
          // więc kolorowanie kategorii zostaje nietknięte.
          ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 6
            spacing: 4
            visible: index !== undefined && layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer) ? true : false

            Text {
              Layout.fillWidth: true
              text: qsTr("Znaczniki")
              font: Theme.strongTipFont
              color: Theme.mainTextColor
            }

            Flow {
              Layout.fillWidth: true
              spacing: 6

              QfButton {
                text: qsTr("Stan w środku")
                font.pointSize: Theme.tinyFont.pointSize
                bgcolor: Theme.controlBackgroundAlternateColor
                color: Theme.mainTextColor
                onClicked: {
                  const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  if (!vl)
                    return;
                  if (LayerUtils.addStatusMarker(vl, "ZROBIONE")) {
                    projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                    displayToast(qsTr("Znacznik stanu dodany."));
                  } else {
                    // Uczciwie: najczęstsza przyczyna to brak pola, a nie awaria.
                    displayToast(qsTr("Nie dodano — warstwa musi być poligonowa i mieć pole ZROBIONE."), 'warning');
                  }
                }
              }

              QfButton {
                text: qsTr("Wierzchołki")
                font.pointSize: Theme.tinyFont.pointSize
                bgcolor: Theme.controlBackgroundAlternateColor
                color: Theme.mainTextColor
                onClicked: {
                  const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  if (!vl)
                    return;
                  if (LayerUtils.addVertexMarkers(vl)) {
                    projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                    displayToast(qsTr("Znaczniki wierzchołków dodane."));
                  } else {
                    displayToast(qsTr("Nie dodano — to działa na poligonach i liniach."), 'warning');
                  }
                }
              }

              QfButton {
                text: qsTr("Zdejmij dodatki")
                font.pointSize: Theme.tinyFont.pointSize
                bgcolor: Theme.controlBackgroundAlternateColor
                color: Theme.mainTextColor
                onClicked: {
                  const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  if (!vl)
                    return;
                  displayToast(LayerUtils.removeExtraSymbolLayers(vl)
                               ? qsTr("Zdjęte.")
                               : qsTr("Nie było czego zdejmować."));
                  projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                }
              }
            }

            Text {
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              font: Theme.tipFont
              color: Theme.secondaryTextColor
              text: qsTr("Znaczniki dokładają się do symbolu warstwy — kolory kategorii zostają. „Zdejmij dodatki” zostawia sam symbol podstawowy.")
            }
          }

          // pasek podgladu wybranej rampy'''

# ------------------------------------------------------------------ mechanika


def read(path):
    if not os.path.exists(path):
        sys.exit("STOP: brak pliku %s (uruchom w korzeniu repo)" % path)
    with open(path, encoding="utf-8") as f:
        return f.read()


def once(text, anchor, path):
    n = text.count(anchor)
    if n != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1:\n  %s"
                 % (path, n, anchor.strip().splitlines()[0]))


def save(path, text):
    backup = path + ".przed_symbolami"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("  zapisano %s (kopia: %s)" % (path, os.path.basename(backup)))


def main():
    h, c, q = read(H), read(C), read(Q)

    if "LayerUtils::colorRampNames" not in c:
        sys.exit("STOP: brak latki 34 (rampy). Naloz ja najpierw.")

    applied = [MARKER in h, "LayerUtils::addStatusMarker" in c, MARKER in q]
    if all(applied):
        print("Latka 37 juz jest — nic do zrobienia.")
        return
    if any(applied):
        sys.exit("STOP: latka nalozona polowicznie %s. Przywroc kopie .przed_symbolami." % applied)

    once(h, H_ANCHOR, H)
    once(c, C_INCLUDE_OLD, C)
    once(c, C_ANCHOR, C)
    once(q, Q_ANCHOR, Q)

    print("Kotwice policzone (4/4), nakladam:")

    h = h.replace(H_ANCHOR, H_NEW + H_ANCHOR, 1)
    save(H, h)

    c = c.replace(C_INCLUDE_OLD, C_INCLUDE_NEW, 1)
    c = c.replace(C_ANCHOR, C_NEW + C_ANCHOR, 1)
    save(C, c)

    q = q.replace(Q_ANCHOR, Q_NEW, 1)
    save(Q, q)

    print("\nGotowe. W panelu warstwy dochodzi sekcja „Znaczniki”:")
    print("  Stan w środku · Wierzchołki · Zdejmij dodatki")
    print("\nBuild:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'rcc|error' | head -20")


if __name__ == "__main__":
    main()
