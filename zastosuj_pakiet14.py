#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pakiet 14 — WSKAZYWANIE NA WIELU ZDJĘCIACH NARAZ (po 13f).
Odporny na powtórzenia.

W siatce Zdjęcia pojawia się przełącznik "Wskazuj na miniaturach"
z polem gatunku (to ten sam pędzel, co w podglądzie — dzielony).
W trybie masowym:
  * miniatury przechodzą z kadrowania na DOPASOWANIE (czarne pasy) —
    tylko wtedy klik daje prawdziwe współrzędne na zdjęciu;
  * klik w miniaturę dodaje wskazanie gatunku w klikniętym punkcie
    (żadnego otwierania podglądu), znaczniki widać od razu na kafelku;
  * klik w istniejący znacznik usuwa to wskazanie;
  * podwójny klik otwiera pełny podgląd, jak dotąd.
Wyłączenie trybu przywraca kadrowanie i zwykłe otwieranie.
"""
import io
import sys

EDYCJE = [
    # ── stan trybu masowego ────────────────────────────────────────
    ('src/app/qml/QfPhotoGallery.qml',
     '''  //! podbijany przy każdej zmianie tagów — odświeża kropki na miniaturach
  property int wersjaTagow: 0
''',
     '''  //! podbijany przy każdej zmianie tagów — odświeża kropki na miniaturach
  property int wersjaTagow: 0

  //! wskazywanie gatunków wprost na miniaturach (siatka Zdjęcia)
  property bool trybMasowy: false
'''),
    # ── pasek trybu pod zakładkami ─────────────────────────────────
    ('src/app/qml/QfPhotoGallery.qml',
     '''      TabButton {
        text: qsTr("Tagi")
        width: implicitWidth
      }
    }
''',
     '''      TabButton {
        text: qsTr("Tagi")
        width: implicitWidth
      }
    }

    // WorkField: masowe wskazywanie gatunków na miniaturach
    RowLayout {
      Layout.fillWidth: true
      visible: galleryTabs.currentIndex === 0
      spacing: 8

      Button {
        checkable: true
        checked: photoGallery.trybMasowy
        text: checked ? qsTr("Wskazywanie na miniaturach — klikaj w zdjęcia") : qsTr("Wskazuj na miniaturach")
        font: photoGallery.t.tinyFont
        Material.background: checked ? "#00695C" : undefined
        onToggled: photoGallery.trybMasowy = checked
      }

      Rectangle {
        visible: photoGallery.trybMasowy && tagInput.text.trim() !== ""
        width: 12
        height: 12
        radius: 6
        color: photoGallery.tagColor(tagInput.text.trim())
        border.color: "white"
        border.width: 1
      }

      TextField {
        Layout.fillWidth: true
        visible: photoGallery.trybMasowy
        placeholderText: qsTr("Gatunek pędzla…")
        text: tagInput.text
        font: photoGallery.t.tipFont
        onTextEdited: tagInput.text = text
      }
    }
'''),
    # ── miniatury: dopasowanie w trybie + wskazania kliknięciem ────
    ('src/app/qml/QfPhotoGallery.qml',
     '''            Image {
              anchors.fill: parent
              anchors.margins: 2
              source: "file://" + modelData.path
              asynchronous: true
              autoTransform: true
              fillMode: Image.PreserveAspectCrop
              // klucz wydajnosci: dekodujemy miniature, nie 12 Mpix
              sourceSize.width: 256
              sourceSize.height: 256
            }
''',
     '''            Image {
              id: miniatura

              anchors.fill: parent
              anchors.margins: 2
              source: "file://" + modelData.path
              asynchronous: true
              autoTransform: true
              // w trybie masowym dopasowanie: kadrowana miniatura
              // kłamałaby o współrzędnych kliknięcia
              fillMode: photoGallery.trybMasowy ? Image.PreserveAspectFit : Image.PreserveAspectCrop
              // klucz wydajnosci: dekodujemy miniature, nie 12 Mpix
              sourceSize.width: 256
              sourceSize.height: 256

              readonly property string wzglednaSciezka: modelData.path.substring(photoGallery.projectDir.length + 1)
              readonly property real kadrX: (width - paintedWidth) / 2
              readonly property real kadrY: (height - paintedHeight) / 2

              // znaczniki wskazań na miniaturze (tryb masowy)
              Repeater {
                model: {
                  if (!photoGallery.trybMasowy)
                    return [];
                  const wersja = photoGallery.wersjaTagow;
                  return tagStore.tagsForPhoto(miniatura.wzglednaSciezka).filter(t => t.x !== undefined && t.x !== null && t.x >= 0);
                }

                delegate: Rectangle {
                  required property var modelData

                  x: miniatura.kadrX + modelData.x * miniatura.paintedWidth - 5
                  y: miniatura.kadrY + modelData.y * miniatura.paintedHeight - 5
                  width: 10
                  height: 10
                  radius: 5
                  color: photoGallery.tagColor(modelData.tag)
                  border.color: "white"
                  border.width: 1.5

                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      tagStore.removeTag(parent.modelData.fid);
                      photoGallery.wersjaTagow++;
                    }
                  }
                }
              }
            }
'''),
    ('src/app/qml/QfPhotoGallery.qml',
     '''            MouseArea {
              anchors.fill: parent
              onClicked: viewer.openList(photoGallery.photos, index)
            }
''',
     '''            MouseArea {
              anchors.fill: parent
              z: -1
              cursorShape: photoGallery.trybMasowy && tagInput.text.trim() !== "" ? Qt.CrossCursor : Qt.ArrowCursor

              onClicked: mouse => {
                if (!photoGallery.trybMasowy) {
                  viewer.openList(photoGallery.photos, index);
                  return;
                }
                // wskazanie w punkcie kliknięcia, przez prostokąt kadru
                const gat = tagInput.text.trim();
                if (gat === "" || miniatura.paintedWidth <= 0)
                  return;
                const p = miniatura.mapFromItem(parent, mouse.x, mouse.y);
                const nx = (p.x - miniatura.kadrX) / miniatura.paintedWidth;
                const ny = (p.y - miniatura.kadrY) / miniatura.paintedHeight;
                if (nx < 0 || nx > 1 || ny < 0 || ny > 1)
                  return;
                if (tagStore.addTag(miniatura.wzglednaSciezka, gat, -1, "", nx, ny) >= 0) {
                  photoGallery.wersjaTagow++;
                  tagPanel.updateSuggestions();
                }
              }

              onDoubleClicked: {
                if (photoGallery.trybMasowy)
                  viewer.openList(photoGallery.photos, index);
              }
            }
'''),
]


def main():
    with io.open('src/app/qml/QfPhotoGallery.qml', encoding='utf-8') as f:
        if 'trybMasowy' in f.read():
            print('pakiet 14 już wpięty — pomijam')
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

    for plik, s in tresci.items():
        with io.open(plik, 'w', encoding='utf-8') as f:
            f.write(s)
        print('zapisano:', plik)
    print('\nPakiet 14 wpięty: wskazywanie na wielu zdjęciach.')


if __name__ == '__main__':
    main()
