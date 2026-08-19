#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 38 — regulacja znacznikow wierzcholkow (kolor, rozmiar, ksztalt).

Latka 37 dokladala wierzcholki w jednej, sztywnej postaci: biale kwadraty
1,6 mm. Na gestej geometrii platow wychodzi z tego lancuch kafelkow
zaslaniajacy sama geometrie — czyli dokladnie odwrotnie, niz mialo byc.
Piotr: „przydalaby sie prosta stylizacja taka, jak dla warstwy punktowej".

Panel ma juz komplet regulacji dla symbolu pojedynczego (wypelnienie,
kontur, grubosc, ksztalt). Ta latka daje to samo dla znacznikow wierzcholka:
probnik koloru (ten sam wspolny picker), suwak rozmiaru, wybor ksztaltu.

CZASOWNIKI (angielskie):
  vertexMarkerConfig( layer )                  -> { present, color, size, shape }
  setVertexMarker( layer, color, size, shape ) -> zmienia istniejace znaczniki

`setVertexMarker` NIE zaklada znacznikow, gdy ich nie ma — od tego jest
`addVertexMarkers`. Czasownik, ktory po cichu robi dwie rozne rzeczy zaleznie
od stanu, jest gorszy od dwoch jawnych: przy „zmien kolor" nikt nie spodziewa
sie, ze cos przybedzie na mapie.

Odczyt idzie po tej samej sciezce co zapis (MarkerLine -> subSymbol ->
warstwa 0), wiec panel pokazuje stan RZECZYWISTY, a nie zapamietany —
gdyby ktos zmienil styl skadinad, suwak to odzwierciedli.

Uruchom w korzeniu repo:  python3 zastosuj_regulacje_wierzcholkow.py
Wymaga latki 37. Idempotentna. Kopie: <plik>.przed_regulacja
"""
import os
import shutil
import sys

H = "src/core/utils/layerutils.h"
C = "src/core/utils/layerutils.cpp"
Q = "src/gui/qml/LayerTreeItemProperties.qml"

MARKER = "vertexMarkerConfig"

# ------------------------------------------------------------------ naglowek

H_ANCHOR = "    //! Zdejmuje dołożone warstwy symbolu, zostawiając pierwszą (podstawową)."

H_NEW = '''    //! Stan znaczników wierzchołka: { present, color, size, shape }.
    static Q_INVOKABLE QVariantMap vertexMarkerConfig( QgsVectorLayer *layer );

    /**
     * Zmienia wygląd ISTNIEJĄCYCH znaczników wierzchołka. Nie zakłada ich,
     * gdy ich nie ma — od tego jest addVertexMarkers().
     */
    static Q_INVOKABLE bool setVertexMarker( QgsVectorLayer *layer, const QColor &color, double size, const QString &shape );

'''

# --------------------------------------------------------------- implementacja

C_ANCHOR = "bool LayerUtils::removeExtraSymbolLayers( QgsVectorLayer *layer )"

C_NEW = r'''namespace
{
  Qgis::MarkerShape shapeFromName( const QString &name )
  {
    if ( name == QLatin1String( "square" ) )
      return Qgis::MarkerShape::Square;
    if ( name == QLatin1String( "diamond" ) )
      return Qgis::MarkerShape::Diamond;
    if ( name == QLatin1String( "triangle" ) )
      return Qgis::MarkerShape::Triangle;
    if ( name == QLatin1String( "cross" ) )
      return Qgis::MarkerShape::Cross2;
    return Qgis::MarkerShape::Circle;
  }

  QString nameFromShape( Qgis::MarkerShape shape )
  {
    switch ( shape )
    {
      case Qgis::MarkerShape::Square:
        return QStringLiteral( "square" );
      case Qgis::MarkerShape::Diamond:
        return QStringLiteral( "diamond" );
      case Qgis::MarkerShape::Triangle:
        return QStringLiteral( "triangle" );
      case Qgis::MarkerShape::Cross2:
        return QStringLiteral( "cross" );
      default:
        return QStringLiteral( "circle" );
    }
  }

  //! Znacznik siedzący w warstwie MarkerLine — jedna droga dla odczytu i zapisu.
  QgsSimpleMarkerSymbolLayer *vertexMarkerOf( QgsSymbol *symbol )
  {
    if ( !symbol )
      return nullptr;

    for ( int i = 0; i < symbol->symbolLayerCount(); ++i )
    {
      QgsMarkerLineSymbolLayer *linia = dynamic_cast<QgsMarkerLineSymbolLayer *>( symbol->symbolLayer( i ) );
      if ( !linia || !linia->subSymbol() )
        continue;

      QgsSymbol *pod = linia->subSymbol();
      if ( pod->symbolLayerCount() < 1 )
        continue;

      if ( QgsSimpleMarkerSymbolLayer *marker = dynamic_cast<QgsSimpleMarkerSymbolLayer *>( pod->symbolLayer( 0 ) ) )
        return marker;
    }
    return nullptr;
  }
}

QVariantMap LayerUtils::vertexMarkerConfig( QgsVectorLayer *layer )
{
  QVariantMap result;
  result.insert( QStringLiteral( "present" ), false );
  result.insert( QStringLiteral( "color" ), QColor( 255, 255, 255 ) );
  result.insert( QStringLiteral( "size" ), 1.6 );
  result.insert( QStringLiteral( "shape" ), QStringLiteral( "square" ) );

  const QgsSymbolList symbols = symbolsOf( layer );
  for ( QgsSymbol *symbol : symbols )
  {
    QgsSimpleMarkerSymbolLayer *marker = vertexMarkerOf( symbol );
    if ( !marker )
      continue;

    result.insert( QStringLiteral( "present" ), true );
    result.insert( QStringLiteral( "color" ), marker->fillColor() );
    result.insert( QStringLiteral( "size" ), marker->size() );
    result.insert( QStringLiteral( "shape" ), nameFromShape( marker->shape() ) );
    break;
  }
  return result;
}

bool LayerUtils::setVertexMarker( QgsVectorLayer *layer, const QColor &color, double size, const QString &shape )
{
  const QgsSymbolList symbols = symbolsOf( layer );
  if ( symbols.isEmpty() )
    return false;

  bool zmienione = false;
  for ( QgsSymbol *symbol : symbols )
  {
    QgsSimpleMarkerSymbolLayer *marker = vertexMarkerOf( symbol );
    if ( !marker )
      continue;

    if ( color.isValid() )
    {
      marker->setColor( color );
      marker->setFillColor( color );
    }
    if ( size > 0 )
      marker->setSize( size );
    if ( !shape.isEmpty() )
      marker->setShape( shapeFromName( shape ) );

    zmienione = true;
  }

  if ( zmienione )
  {
    layer->triggerRepaint();
    emit layer->styleChanged();
  }
  return zmienione;
}

'''

# ------------------------------------------------------------------------ QML

Q_PROP_ANCHOR = '  property string pendingRamp: "Turbo"'
Q_PROP_NEW = '''  property string pendingRamp: "Turbo"
  //! WorkField: stan znaczników wierzchołka, odświeżany po każdej zmianie.
  property var vertexCfg: ({
      "present": false,
      "color": "#ffffff",
      "size": 1.6,
      "shape": "square"
    })'''

Q_ADD_OLD = """                  if (LayerUtils.addVertexMarkers(vl)) {
                    projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                    displayToast(qsTr("Znaczniki wierzchołków dodane."));"""

Q_ADD_NEW = """                  if (LayerUtils.addVertexMarkers(vl)) {
                    vertexCfg = LayerUtils.vertexMarkerConfig(vl);
                    projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                    displayToast(qsTr("Znaczniki wierzchołków dodane."));"""

Q_DEL_OLD = """                  displayToast(LayerUtils.removeExtraSymbolLayers(vl)
                               ? qsTr("Zdjęte.")
                               : qsTr("Nie było czego zdejmować."));"""

Q_DEL_NEW = """                  displayToast(LayerUtils.removeExtraSymbolLayers(vl)
                               ? qsTr("Zdjęte.")
                               : qsTr("Nie było czego zdejmować."));
                  vertexCfg = LayerUtils.vertexMarkerConfig(vl);"""

Q_ROW_ANCHOR = """            Text {
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              font: Theme.tipFont
              color: Theme.secondaryTextColor
              text: qsTr("Znaczniki dokładają się do symbolu warstwy — kolory kategorii zostają. „Zdejmij dodatki” zostawia sam symbol podstawowy.")
            }"""

Q_ROW_NEW = '''            // Regulacja wierzchołków — te same trzy pokrętła, co dla symbolu
            // pojedynczego. Widoczne dopiero, gdy jest co regulować.
            RowLayout {
              Layout.fillWidth: true
              Layout.topMargin: 2
              spacing: 8
              visible: vertexCfg.present

              function zapisz(kolor, rozmiar, ksztalt) {
                const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                if (!vl)
                  return;
                LayerUtils.setVertexMarker(vl, kolor, rozmiar, ksztalt);
                vertexCfg = LayerUtils.vertexMarkerConfig(vl);
                projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
              }

              Rectangle {
                width: 44
                height: 30
                radius: 4
                color: vertexCfg.color
                border.width: 1
                border.color: Theme.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: openColorPicker(qsTr("Wierzchołki"), vertexCfg.color, function (chosen) {
                    parent.parent.zapisz(chosen, vertexCfg.size, vertexCfg.shape);
                  })
                }
              }

              ComboBox {
                Layout.preferredWidth: 116
                font: Theme.defaultFont
                model: [qsTr("kwadrat"), qsTr("kółko"), qsTr("romb"), qsTr("krzyżyk")]
                readonly property var klucze: ["square", "circle", "diamond", "cross"]
                currentIndex: Math.max(0, klucze.indexOf(vertexCfg.shape))
                onActivated: parent.zapisz(vertexCfg.color, vertexCfg.size, klucze[currentIndex])
              }

              Slider {
                Layout.fillWidth: true
                from: 0.4
                to: 5.0
                stepSize: 0.2
                value: vertexCfg.size
                // dopiero po puszczeniu: przy każdym drgnięciu przebudowa
                // symbolu na kilkuset wierzchołkach zamula płótno
                onPressedChanged: {
                  if (!pressed)
                    parent.zapisz(vertexCfg.color, value, vertexCfg.shape);
                }
              }

              Text {
                text: vertexCfg.size.toFixed(1) + " mm"
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
              }
            }

''' + Q_ROW_ANCHOR

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
    backup = path + ".przed_regulacja"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("  zapisano %s (kopia: %s)" % (path, os.path.basename(backup)))


def main():
    h, c, q = read(H), read(C), read(Q)

    if "LayerUtils::addVertexMarkers" not in c:
        sys.exit("STOP: brak latki 37 (warstwy symbolu). Naloz ja najpierw.")

    applied = [MARKER in h, "LayerUtils::vertexMarkerConfig" in c, "vertexCfg" in q]
    if all(applied):
        print("Latka 38 juz jest — nic do zrobienia.")
        return
    if any(applied):
        sys.exit("STOP: latka nalozona polowicznie %s. Przywroc kopie .przed_regulacja." % applied)

    once(h, H_ANCHOR, H)
    once(c, C_ANCHOR, C)
    for anchor in (Q_PROP_ANCHOR, Q_ADD_OLD, Q_DEL_OLD, Q_ROW_ANCHOR):
        once(q, anchor, Q)

    print("Kotwice policzone (6/6), nakladam:")

    h = h.replace(H_ANCHOR, H_NEW + H_ANCHOR, 1)
    save(H, h)

    c = c.replace(C_ANCHOR, C_NEW + C_ANCHOR, 1)
    save(C, c)

    q = q.replace(Q_PROP_ANCHOR, Q_PROP_NEW, 1)
    q = q.replace(Q_ADD_OLD, Q_ADD_NEW, 1)
    q = q.replace(Q_DEL_OLD, Q_DEL_NEW, 1)
    q = q.replace(Q_ROW_ANCHOR, Q_ROW_NEW, 1)
    save(Q, q)

    print("\nGotowe. Pod przyciskami znacznikow: probnik koloru, ksztalt, rozmiar.")
    print("\nBuild:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'rcc|error' | head -20")


if __name__ == "__main__":
    main()
