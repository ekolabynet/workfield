#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pakiet 9 — DOKOWANY LEWY PANEL (uruchom w korzeniu repo, stan 719ff0117).
Odporny na powtórzenia. Telefon: szuflada bez zmian.

Co robi (komputer):
  1. Panel przestaje być modalny: nie przyciemnia mapy, nie zamyka się
     od kliknięcia w mapę — otwarty ZOSTAJE (zamknięcie: strzałka
     w nagłówku albo Esc). MAPA ZWĘŻA SIĘ o szerokość panelu (płynnie,
     wraz z animacją otwierania).
  2. U góry panelu POZIOMY przełącznik widoków (ikona + nazwa):
     Projekt · Warstwy · Stylizacja · Magazyn. Pionowy pasek ikon na
     mapie znika — jego rolę przejmuje przełącznik i pasek menu.
     (Zdjęcia i Tagowanie dojdą jako widoki przy osadzaniu galerii;
     Projekt zniknie, gdy jego rolę przejmie dashboard startowy.)
  3. Panel PAMIĘTA stan: po wczytaniu projektu wraca otwarty/zamknięty
     z ostatnią sekcją (klucze WorkField/lewyPanelOtwarty, ...Sekcja).
     Pierwsze uruchomienie: zamknięty.
"""
import io
import sys

D = 'Qt.platform.os !== "android" && Qt.platform.os !== "ios"'

EDYCJE = [
    # ── panel: tryb dokowany na komputerze ─────────────────────────
    ('src/app/qml/QfMainDrawer.qml',
     '''  edge: Qt.LeftEdge
  dragMargin: 10
  interactive: allowInteractive
''',
     '''  edge: Qt.LeftEdge
  // WorkField: na komputerze panel jest DOKOWANY — nie przyciemnia mapy,
  // nie zamyka się od kliknięcia poza nim i zostaje otwarty; mapa zwęża
  // się o jego szerokość (patrz mapCanvas w qgismobileapp.qml)
  modal: Qt.platform.os === "android" || Qt.platform.os === "ios"
  dim: modal
  closePolicy: modal ? Popup.CloseOnEscape | Popup.CloseOnPressOutside : Popup.CloseOnEscape
  dragMargin: modal ? 10 : 0
  interactive: allowInteractive && modal

  onOpenedChanged: {
    if (!modal) {
      settings.setValue('WorkField/lewyPanelOtwarty', opened);
    }
  }
  onSekcjaWymuszonaChanged: {
    if (!modal && sekcjaWymuszona >= 0) {
      settings.setValue('WorkField/lewyPanelSekcja', sekcjaWymuszona);
    }
  }
'''),
    # ── poziomy przełącznik widoków nad stosem sekcji ──────────────
    ('src/app/qml/QfMainDrawer.qml',
     '''    TabBar {
      id: dashTabs
''',
     '''    // WorkField: poziomy przełącznik widoków panelu (komputer);
    // ikona + nazwa, bo etykieta bije zgadywanie
    RowLayout {
      visible: Qt.platform.os !== "android" && Qt.platform.os !== "ios"
      Layout.fillWidth: true
      Layout.leftMargin: 4
      Layout.rightMargin: 4
      spacing: 2

      Repeater {
        model: [{ "nazwa": qsTr("Projekt"), "ikona": "wfg_nowe", "sekcja": 0 }, { "nazwa": qsTr("Warstwy"), "ikona": "wfg_warstwy", "sekcja": 1 }, { "nazwa": qsTr("Stylizacja"), "ikona": "wfg_stylizacja", "sekcja": 2 }, { "nazwa": qsTr("Magazyn"), "ikona": "wfg_magazyn", "sekcja": 3 }]

        delegate: ItemDelegate {
          id: przelacznikWidoku

          required property var modelData

          readonly property bool aktywny: dashStack.currentIndex === modelData.sekcja

          Layout.fillWidth: true
          Layout.preferredHeight: 34
          padding: 0

          background: Rectangle {
            color: przelacznikWidoku.aktywny ? Theme.mainColor : "transparent"
            radius: 5
          }

          contentItem: RowLayout {
            spacing: 5

            Item {
              Layout.fillWidth: true
            }

            Image {
              id: ikonaWidoku
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16
              fillMode: Image.PreserveAspectFit
              sourceSize.width: 16
              sourceSize.height: 16
              source: Theme.getThemeVectorIcon(przelacznikWidoku.modelData.ikona)
              visible: false
            }

            MultiEffect {
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16
              source: ikonaWidoku
              colorization: 1.0
              colorizationColor: przelacznikWidoku.aktywny ? "white" : Theme.mainTextColor
              brightness: 0.2
            }

            Text {
              text: przelacznikWidoku.modelData.nazwa
              font: Theme.tinyFont
              color: przelacznikWidoku.aktywny ? "white" : Theme.mainTextColor
            }

            Item {
              Layout.fillWidth: true
            }
          }

          onClicked: dashBoard.sekcjaWymuszona = modelData.sekcja
        }
      }
    }

    TabBar {
      id: dashTabs
'''),
    # ── mapa zwęża się o panel ─────────────────────────────────────
    ('src/app/qml/qgismobileapp.qml',
     '''    /* Placement and size. Share right anchor with featureForm */
    anchors.top: parent.top
    anchors.left: parent.left
''',
     '''    /* Placement and size. Share right anchor with featureForm */
    anchors.top: parent.top
    anchors.left: parent.left
    // WorkField: dokowany panel zsuwa mapę (płynnie, wraz z animacją)
    anchors.leftMargin: %s ? dashBoard.width * dashBoard.position : 0
''' % D),
    # ── przywrócenie stanu panelu po wczytaniu projektu ────────────
    ('src/app/qml/qgismobileapp.qml',
     '''  onSceneLoadedChanged: {
    // This requires the scene to be fully loaded not to crash due to possibility of
    // a thread blocking permission request being thrown
''',
     '''  onSceneLoadedChanged: {
    // WorkField: dokowany panel wraca w stanie z poprzedniej sesji
    if (sceneLoaded && %s && settings.valueBool('WorkField/lewyPanelOtwarty', false)) {
      dashBoard.otworzSekcje(settings.valueInt('WorkField/lewyPanelSekcja', 1));
    }
    // This requires the scene to be fully loaded not to crash due to possibility of
    // a thread blocking permission request being thrown
''' % D),
]


def main():
    with io.open('src/app/qml/QfMainDrawer.qml', encoding='utf-8') as f:
        if 'lewyPanelOtwarty' in f.read():
            print('pakiet 9 już wpięty — pomijam')
            return

    tresci = {}
    for plik, stary, nowy in EDYCJE:
        s = tresci.get(plik)
        if s is None:
            with io.open(plik, encoding='utf-8') as f:
                s = f.read()
        if s.count(stary) != 1:
            sys.exit('KOTWICA nie pasuje (wystąpień: %d) w %s:\n%r\nNic nie zapisano.'
                     % (s.count(stary), plik, stary[:70]))
        tresci[plik] = s.replace(stary, nowy, 1)

    # przełącznik używa MultiEffect — dopilnuj importu
    s = tresci['src/app/qml/QfMainDrawer.qml']
    if 'import QtQuick.Effects' not in s:
        s = s.replace('import QtQuick\n', 'import QtQuick\nimport QtQuick.Effects\n', 1)
        tresci['src/app/qml/QfMainDrawer.qml'] = s

    for plik, s in tresci.items():
        with io.open(plik, 'w', encoding='utf-8') as f:
            f.write(s)
        print('zapisano:', plik)
    print('\nPakiet 9 wpięty: dokowany lewy panel.')


if __name__ == '__main__':
    main()
