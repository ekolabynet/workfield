#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 34 — WYBOR RAMPY KOLOROW w panelu warstwy.

STAN ZASTANY (sprawdzony w kodzie):
  LayerUtils.setCategorizedRenderer( layer, pole, rampa = "Turbo" ) juz
  koloruje kategorie rampa z biblioteki QGIS-a (QgsStyle::defaultStyle()),
  a LayerTreeItemProperties.qml:338 wola to BEZ nazwy rampy — czyli zawsze
  Turbo. Rampy wiec dzialaja, tylko nie da sie wybrac innej ani przemalowac
  raz zalozonych kategorii.

CO DOKLADA (trzy czasowniki + jeden rzad w panelu):

  colorRampNames()                 -> lista nazw z biblioteki QGIS-a
  colorRampPreview( nazwa, ile )   -> kolory do narysowania paska gradientu
  applyColorRamp( layer, nazwa )   -> PRZEMALOWANIE istniejacej klasyfikacji

Trzeci jest tu najwazniejszy. Bez niego zmiana rampy musialaby przechodzic
przez setCategorizedRenderer, czyli odtwarzac klasyfikacje od zera — i
kasowac wszystkie kolory poprawione recznie. `updateColorRamp()` istnieje
w obu rendererach (potwierdzone w naglowkach QGIS), wiec przemalowanie
nie rusza ani podzialu na kategorie, ani ich widocznosci.

Rampa jest AUTOMATEM (decyzja Piotra 19.08): daje sensowny start przy
84 kategoriach, a paleta Materialize (latka 33) sluzy do poprawiania
pojedynczych kategorii, ktore sie zlewaja.

PLIKI:
  src/core/utils/layerutils.{h,cpp}      — nasza rozszerzona czesc
  src/gui/qml/LayerTreeItemProperties.qml — UPSTREAMOWY, delta rosnie

Uruchom w korzeniu repo:  python3 zastosuj_rampy.py
Idempotentna. Kopie: <plik>.przed_rampami
"""
import os
import shutil
import sys

H = "src/core/utils/layerutils.h"
C = "src/core/utils/layerutils.cpp"
Q = "src/gui/qml/LayerTreeItemProperties.qml"

MARKER = "colorRampNames"

# ------------------------------------------------------------------ naglowek

H_ANCHOR = "    static Q_INVOKABLE QVariantList rendererCategories( QgsVectorLayer *layer );"

H_NEW = '''    //! Nazwy ramp kolorow z biblioteki QGIS-a (Turbo, Viridis, Spectral...).
    static Q_INVOKABLE QVariantList colorRampNames();

    //! \\a count kolorow rozlozonych rowno na rampie — do paska podgladu w QML.
    static Q_INVOKABLE QVariantList colorRampPreview( const QString &rampName, int count = 12 );

    /**
     * Przemalowuje ISTNIEJACA klasyfikacje rampa, bez odtwarzania jej od zera.
     * Podzial na kategorie, etykiety i widocznosc zostaja nietkniete — inaczej
     * zmiana rampy kasowalaby kolory poprawione recznie.
     */
    static Q_INVOKABLE bool applyColorRamp( QgsVectorLayer *layer, const QString &rampName );

'''

# --------------------------------------------------------------- implementacja

C_ANCHOR = "QVariantList LayerUtils::rendererCategories( QgsVectorLayer *layer )"

C_NEW = '''QVariantList LayerUtils::colorRampNames()
{
  QVariantList result;
  QgsStyle *style = QgsStyle::defaultStyle();
  if ( !style )
    return result;

  const QStringList names = style->colorRampNames();
  for ( const QString &name : names )
    result.append( name );
  return result;
}

QVariantList LayerUtils::colorRampPreview( const QString &rampName, int count )
{
  QVariantList result;
  std::unique_ptr<QgsColorRamp> ramp( rampByName( rampName ) );
  if ( !ramp || count < 2 )
    return result;

  for ( int i = 0; i < count; ++i )
    result.append( ramp->color( static_cast<double>( i ) / ( count - 1 ) ) );
  return result;
}

bool LayerUtils::applyColorRamp( QgsVectorLayer *layer, const QString &rampName )
{
  if ( !layer )
    return false;

  std::unique_ptr<QgsColorRamp> ramp( rampByName( rampName ) );
  if ( !ramp )
    return false;

  if ( QgsCategorizedSymbolRenderer *renderer = dynamic_cast<QgsCategorizedSymbolRenderer *>( layer->renderer() ) )
  {
    renderer->updateColorRamp( ramp.release() );
  }
  else if ( QgsGraduatedSymbolRenderer *renderer = dynamic_cast<QgsGraduatedSymbolRenderer *>( layer->renderer() ) )
  {
    renderer->updateColorRamp( ramp.release() );
  }
  else
  {
    return false;
  }

  layer->triggerRepaint();
  emit layer->styleChanged();
  return true;
}

'''

# ------------------------------------------------------------------------ QML

Q_MODE_OLD = """              LayerUtils.setCategorizedRenderer(vl, pendingField);"""
Q_MODE_NEW = """              LayerUtils.setCategorizedRenderer(vl, pendingField, pendingRamp);"""

Q_GRAD_OLD = """              LayerUtils.setGraduatedRenderer(vl, pendingField, pendingClassCount);"""
Q_GRAD_NEW = """              LayerUtils.setGraduatedRenderer(vl, pendingField, pendingClassCount, pendingRamp);"""

Q_ROW_ANCHOR = """            SpinBox {
              Layout.preferredWidth: 96
              visible: fieldCombo.currentNumeric
              from: 2
              to: 12
              value: pendingClassCount
              font: Theme.defaultFont
              onValueChanged: pendingClassCount = value
            }
          }"""

Q_ROW_NEW = Q_ROW_ANCHOR + """

          // WorkField 19.08.2026: wybor rampy kolorow. Rampa jest AUTOMATEM —
          // daje sensowny start przy kilkudziesieciu kategoriach; pojedyncze
          // kategorie poprawia sie potem paleta Materialize.
          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 4
            spacing: 6
            visible: categoriesVisible || fieldCombo.currentNumeric

            Text {
              text: qsTr("Rampa")
              font: Theme.defaultFont
              color: Theme.mainTextColor
            }

            ComboBox {
              id: rampCombo

              Layout.fillWidth: true
              font: Theme.defaultFont
              model: LayerUtils.colorRampNames()
              currentIndex: Math.max(0, model.indexOf(pendingRamp))

              onActivated: {
                pendingRamp = currentText;
                const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                if (!vl)
                  return;
                // Przemalowanie, nie odtworzenie klasyfikacji: recznie
                // poprawione kategorie przezywaja zmiane rampy tylko wtedy,
                // gdy nie przechodzimy przez setCategorizedRenderer.
                if (LayerUtils.applyColorRamp(vl, pendingRamp)) {
                  categoryEntries = LayerUtils.rendererCategories(vl);
                  projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                }
              }
            }
          }

          // pasek podgladu wybranej rampy
          Row {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            visible: rampCombo.visible
            spacing: 0

            Repeater {
              model: LayerUtils.colorRampPreview(pendingRamp, 24)

              delegate: Rectangle {
                required property var modelData
                width: (rampCombo.width) / 24
                height: 10
                color: modelData
              }
            }
          }"""

Q_PROP_ANCHOR = "  property int pendingClassCount: 5"
Q_PROP_NEW = """  property int pendingClassCount: 5
  //! WorkField: rampa uzywana przy zakladaniu i przemalowywaniu klasyfikacji
  property string pendingRamp: "Turbo\""""

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
    backup = path + ".przed_rampami"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("  zapisano %s (kopia: %s)" % (path, os.path.basename(backup)))


def main():
    h, c, q = read(H), read(C), read(Q)

    # UWAGA: w .cpp sam ciag colorRampNames wystepuje juz w rampByName,
    # wiec znacznikiem musi byc DEFINICJA metody, nie sama nazwa.
    applied = [MARKER in h, "LayerUtils::colorRampNames" in c, "pendingRamp" in q]
    if all(applied):
        print("Latka 34 juz jest — nic do zrobienia.")
        return
    if any(applied):
        sys.exit("STOP: latka nalozona polowicznie %s. Przywroc kopie .przed_rampami." % applied)

    once(h, H_ANCHOR, H)
    once(c, C_ANCHOR, C)
    for anchor in (Q_MODE_OLD, Q_GRAD_OLD, Q_ROW_ANCHOR, Q_PROP_ANCHOR):
        once(q, anchor, Q)

    print("Kotwice policzone (6/6), nakladam:")

    h = h.replace(H_ANCHOR, H_NEW + H_ANCHOR, 1)
    save(H, h)

    c = c.replace(C_ANCHOR, C_NEW + C_ANCHOR, 1)
    save(C, c)

    q = q.replace(Q_PROP_ANCHOR, Q_PROP_NEW, 1)
    q = q.replace(Q_MODE_OLD, Q_MODE_NEW, 1)
    q = q.replace(Q_GRAD_OLD, Q_GRAD_NEW, 1)
    q = q.replace(Q_ROW_ANCHOR, Q_ROW_NEW, 1)
    save(Q, q)

    print("\nGotowe. Build:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'rcc|error' | head -20")
    print("W logu MUSI byc 'Running rcc for resource gui_qml'.")
    print("\nUWAGA: LayerTreeItemProperties.qml jest UPSTREAMOWY — do NOTICE.md.")


if __name__ == "__main__":
    main()
