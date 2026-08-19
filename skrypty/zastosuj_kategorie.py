#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 32 — ekran KATEGORIE: kolorowanie kategorii palcem, takze w terenie.

POWOD. Zycie Piotra z 19.08: "mozliwosc recznego wyboru z kola barw,
strasznie brakuje przy kolorowaniu kategorii obiektow". Do tej pory
zmiana koloru kategorii wymagala QGIS-a na komputerze — czyli powrotu
z terenu.

CZEGO NIE TRZEBA BYLO PISAC (sprawdzone w kodzie, nie zgadniete):

  LayerUtils ma juz komplet czasownikow, wszystkie Q_INVOKABLE:
    rendererCategories( layer )       -> [{ index, label, color, visible }]
    setCategoryColor( layer, i, kolor )
    setCategoryVisible( layer, i, bool )
    setCategorizedRenderer( layer, pole, rampa )
    hasCategorizedSymbology( layer )
  Kazdy z nich konczy sie triggerRepaint() + styleChanged(), wiec mapa
  odswieza sie sama.

  QfColorPicker istnieje od v0.8.13 (paleta Material 11x10, kanal alfa).
  Byl podpiety WYLACZNIE do kolorow kafli paska i podpowiedzi edytora —
  stad wrazenie, ze "palety gdzies zniknely". Nie zniknely; nie mialy
  polaczenia ze stylizacja warstw.

Ta latka jest wiec PRZEWODEM miedzy dwoma rzeczami, ktore juz byly.
Zero nowego C++.

CO DOKLADA:
  1. src/app/qml/QfKategorie.qml — NOWY, nasz. Lista kategorii aktywnej
     warstwy: kwadracik koloru (tap -> paleta), etykieta, oko widocznosci.
  2. QfMainDrawer.qml — pozycja "Kategorie" w sekcji Stylizacja, obok
     "Zapisz styl" / "Wczytaj styl".

WLASNY QfColorPicker W SRODKU, nie wspoldzielony z qgismobileapp.qml —
id z innego pliku nie jest widoczny przez granice komponentu, a
przewlekanie referencji przez trzy poziomy to dokladnie to, czego
unikalismy przy moscie naglowek -> pasek (decyzja z 16.08).

CZEGO TA LATKA NIE ROBI: nie zaklada kategorii tam, gdzie ich nie ma.
Gdy warstwa ma symbol pojedynczy, ekran mowi to wprost i nie udaje,
ze da sie cos pokolorowac. Zakladanie renderera z pola to osobna
decyzja (setCategorizedRenderer jest gotowe) — i osobna latka.

Uruchom w korzeniu repo:  python3 zastosuj_kategorie.py
Idempotentna. Kopia: QfMainDrawer.qml.przed_kategoriami
"""
import os
import shutil
import sys

DRAWER = "src/app/qml/QfMainDrawer.qml"
SCREEN = "src/app/qml/QfKategorie.qml"

MARKER = "QfKategorie"

# ------------------------------------------------------------- nowy komponent

SCREEN_SOURCE = '''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qgis
import org.qfield
import Theme

/**
 * WorkField: kolorowanie kategorii warstwy palcem — takze na telefonie.
 *
 * Caly silnik siedzi w LayerUtils (rendererCategories / setCategoryColor /
 * setCategoryVisible); ten plik jest wylacznie ekranem. Kazda zmiana
 * odswieza mape sama, bo czasowniki LayerUtils koncza sie triggerRepaint().
 *
 * Zmiany zyja w projekcie — zeby przetrwaly zamkniecie, projekt trzeba
 * zapisac. Ekran mowi o tym wprost zamiast zapisywac po cichu: zapis
 * projektu w terenie to decyzja, nie skutek uboczny zmiany koloru.
 */
Popup {
  id: categoriesScreen

  property var targetLayer: null
  property var categories: []
  property bool projectTouched: false

  function openFor(layer) {
    targetLayer = layer;
    projectTouched = false;
    reload();
    open();
  }

  function reload() {
    categories = targetLayer ? LayerUtils.rendererCategories(targetLayer) : [];
  }

  parent: mainWindow.contentItem
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  width: Math.min(mainWindow.width - 32, 420)
  height: Math.min(mainWindow.height - 80, 560)
  modal: true
  focus: true
  padding: 12

  background: Rectangle {
    color: Theme.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: Theme.controlBorderColor
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: categoriesScreen.targetLayer ? categoriesScreen.targetLayer.name : qsTr("Kategorie")
      font: Theme.strongTipFont
      color: Theme.mainTextColor
      elide: Text.ElideRight
    }

    Text {
      Layout.fillWidth: true
      visible: categoriesScreen.categories.length === 0
      wrapMode: Text.WordWrap
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      text: categoriesScreen.targetLayer
            ? qsTr("Ta warstwa nie ma stylu kategoryzowanego — nie ma czego kolorować. Kategorie zakłada się na komputerze albo wczytując styl.")
            : qsTr("Nie wybrano warstwy.")
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: categoriesScreen.categories.length > 0
      clip: true
      spacing: 2
      model: categoriesScreen.categories

      delegate: RowLayout {
        required property var modelData
        width: ListView.view ? ListView.view.width : 0
        spacing: 8

        // kwadracik koloru — cel wielkosci palca w rekawicy
        Rectangle {
          Layout.preferredWidth: 44
          Layout.preferredHeight: 44
          radius: 4
          color: modelData.color
          border.width: 1
          border.color: Theme.controlBorderColor

          MouseArea {
            anchors.fill: parent
            onClicked: {
              categoryPicker.editedIndex = modelData.index;
              categoryPicker.openFor(modelData.color);
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: modelData.label
          font: Theme.defaultFont
          color: Theme.mainTextColor
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
        }

        QfToolButton {
          Layout.preferredWidth: 44
          Layout.preferredHeight: 44
          iconSource: modelData.visible ? Theme.getThemeVectorIcon("ic_eye_black_24dp")
                                        : Theme.getThemeVectorIcon("ic_eye_off_black_24dp")
          iconColor: modelData.visible ? Theme.mainTextColor : Theme.mainTextDisabledColor
          bgcolor: "transparent"

          onClicked: {
            LayerUtils.setCategoryVisible(categoriesScreen.targetLayer, modelData.index, !modelData.visible);
            categoriesScreen.projectTouched = true;
            categoriesScreen.reload();
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: categoriesScreen.projectTouched
      wrapMode: Text.WordWrap
      font: Theme.tinyFont
      color: Theme.warningColor
      text: qsTr("Zmiany widać na mapie od razu. Żeby przetrwały zamknięcie projektu, zapisz projekt.")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Item {
        Layout.fillWidth: true
      }

      QfButton {
        text: qsTr("Zamknij")
        onClicked: categoriesScreen.close()
      }
    }
  }

  // Wlasna instancja pickera: id z qgismobileapp.qml nie siega przez
  // granice komponentu, a przewlekanie referencji przez kolejne pliki
  // kosztuje wiecej niz jeden Popup.
  QfColorPicker {
    id: categoryPicker

    property int editedIndex: -1

    t: Theme
    allowAlpha: true
    title: qsTr("Kolor kategorii")

    onColorPicked: chosen => {
      if (editedIndex < 0 || !categoriesScreen.targetLayer)
        return;
      LayerUtils.setCategoryColor(categoriesScreen.targetLayer, editedIndex, chosen);
      categoriesScreen.projectTouched = true;
      categoriesScreen.reload();
    }
  }
}
'''

# ---------------------------------------------------------------- wpiecie

DRAWER_ANCHOR = '''          QfPozycjaMenu {
            text: qsTr("Wczytaj styl")
            ikona: "wfg_otworz"
            enabled: dashBoard.activeLayer !== null
            onClicked: dialogStylu.open()
          }'''

DRAWER_NEW = DRAWER_ANCHOR + '''
          // WorkField 19.08.2026: kolory kategorii palcem, bez QGIS-a.
          // Silnik byl w LayerUtils od dawna, paleta w QfColorPicker od
          // v0.8.13 — brakowalo wylacznie polaczenia miedzy nimi.
          QfPozycjaMenu {
            text: qsTr("Kategorie")
            ikona: "wfg_stylizacja"
            enabled: dashBoard.activeLayer !== null
            onClicked: ekranKategorii.openFor(dashBoard.activeLayer)
          }'''

DRAWER_INSTANCE_ANCHOR = '''        ProcesyStudio {
          id: procesyStylu
        }'''

DRAWER_INSTANCE_NEW = '''        QfKategorie {
          id: ekranKategorii
        }
        ProcesyStudio {
          id: procesyStylu
        }'''

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


def main():
    drawer = read(DRAWER)

    if MARKER in drawer and os.path.exists(SCREEN):
        print("Latka 32 juz jest — nic do zrobienia.")
        return
    if MARKER in drawer or os.path.exists(SCREEN):
        sys.exit("STOP: latka nalozona polowicznie (ekran %s, wpiecie %s). "
                 "Przywroc kopie .przed_kategoriami i usun QfKategorie.qml."
                 % (os.path.exists(SCREEN), MARKER in drawer))

    once(drawer, DRAWER_ANCHOR, DRAWER)
    once(drawer, DRAWER_INSTANCE_ANCHOR, DRAWER)

    print("Kotwice policzone (2/2), nakladam:")

    with open(SCREEN, "w", encoding="utf-8") as f:
        f.write(SCREEN_SOURCE)
    print("  utworzono %s" % SCREEN)

    backup = DRAWER + ".przed_kategoriami"
    if not os.path.exists(backup):
        shutil.copy2(DRAWER, backup)
    drawer = drawer.replace(DRAWER_ANCHOR, DRAWER_NEW, 1)
    drawer = drawer.replace(DRAWER_INSTANCE_ANCHOR, DRAWER_INSTANCE_NEW, 1)
    with open(DRAWER, "w", encoding="utf-8") as f:
        f.write(drawer)
    print("  zapisano %s (kopia: %s)" % (DRAWER, os.path.basename(backup)))

    print("\nUWAGA: nowy plik QML musi trafic do zasobow.")
    print("Sprawdz, czy lista zasobow app_qml wciaga katalog globem:")
    print("  grep -n 'QfMainDrawer.qml' src/app/CMakeLists.txt")
    print("Jesli pliki sa wyliczane po jednym — dopisz QfKategorie.qml obok.")
    print("\nBuild:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | tail -20")
    print("W logu MUSI byc 'Running rcc for resource app_qml'.")


if __name__ == "__main__":
    main()
