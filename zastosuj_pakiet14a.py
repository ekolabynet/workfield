#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pakiet 14a — ŚCINANIE ZAMIAST OBROTU + LISTA GATUNKÓW W TRYBIE MASOWYM
(po pakiecie 14). Odporny na powtórzenia.

  1. Suwak "Pochył" (dawny Obrót) robi teraz prawdziwe ŚCINANIE:
     poziome linie siatki ZOSTAJĄ poziome, piony się kładą — jak
     pochylona kamera, nie jak obrócona kartka. Klik, malowanie
     i środki komórek liczone tą samą macierzą (odwracalność
     udowodniona numerycznie).
  2. W trybie masowego wskazywania pod paskiem pędzla pojawia się
     przewijana LISTA GATUNKÓW z licznikami (te same sugestie, co
     w podglądzie) — klik ustawia pędzel, bez otwierania zdjęcia.
"""
import io
import sys

EDYCJE = [
    # ── 1a. Canvas: macierz ścinania ───────────────────────────────
    ('src/app/qml/QfPhotoGallery.qml',
     '''              ctx.save();
              ctx.translate(width / 2, height / 2);
              ctx.rotate(viewer.obrot * Math.PI / 180);
              ctx.translate(-width / 2, -height / 2);
''',
     '''              ctx.save();
              // ścinanie: x' = x + s*(y - H/2); poziome linie zostają poziome
              const pochyl = Math.tan(viewer.obrot * Math.PI / 180);
              ctx.transform(1, 0, pochyl, 1, -pochyl * height / 2, 0);
'''),
    # ── 1b. klik: odwrotność ścinania ──────────────────────────────
    ('src/app/qml/QfPhotoGallery.qml',
     '''                // najpierw odkręcamy punkt o obrót siatki (wokół środka kadru)
                const kat = -viewer.obrot * Math.PI / 180;
                const rx = fullImage.width / 2 + (ps.x - fullImage.width / 2) * Math.cos(kat) - (ps.y - fullImage.height / 2) * Math.sin(kat);
                const ry = fullImage.height / 2 + (ps.x - fullImage.width / 2) * Math.sin(kat) + (ps.y - fullImage.height / 2) * Math.cos(kat);
''',
     '''                // odwrotność ścinania: x = x' - s*(y - H/2), y bez zmian
                const sc = Math.tan(viewer.obrot * Math.PI / 180);
                const rx = ps.x - sc * (ps.y - fullImage.height / 2);
                const ry = ps.y;
'''),
    # ── 1c. malowanie: ta sama odwrotność ──────────────────────────
    ('src/app/qml/QfPhotoGallery.qml',
     '''                const katM = -viewer.obrot * Math.PI / 180;
                const rxM = fullImage.width / 2 + (pm.x - fullImage.width / 2) * Math.cos(katM) - (pm.y - fullImage.height / 2) * Math.sin(katM);
                const ryM = fullImage.height / 2 + (pm.x - fullImage.width / 2) * Math.sin(katM) + (pm.y - fullImage.height / 2) * Math.cos(katM);
''',
     '''                const scM = Math.tan(viewer.obrot * Math.PI / 180);
                const rxM = pm.x - scM * (pm.y - fullImage.height / 2);
                const ryM = pm.y;
'''),
    # ── 1d. środek komórki: ścinanie w przód ───────────────────────
    ('src/app/qml/QfPhotoGallery.qml',
     '''      const katS = obrot * Math.PI / 180;
      const ox = fullImage.width / 2 + (px - fullImage.width / 2) * Math.cos(katS) - (py - fullImage.height / 2) * Math.sin(katS);
      const oy = fullImage.height / 2 + (px - fullImage.width / 2) * Math.sin(katS) + (py - fullImage.height / 2) * Math.cos(katS);
''',
     '''      const scS = Math.tan(obrot * Math.PI / 180);
      const ox = px + scS * (py - fullImage.height / 2);
      const oy = py;
'''),
    # ── 1e. etykieta ───────────────────────────────────────────────
    ('src/app/qml/QfPhotoGallery.qml',
     '''            text: qsTr("Obrót:")
''',
     '''            text: qsTr("Pochył:")
'''),
    # ── 2. lista gatunków w trybie masowym ─────────────────────────
    ('src/app/qml/QfPhotoGallery.qml',
     '''        onTextEdited: tagInput.text = text
      }
    }
''',
     '''        onTextEdited: tagInput.text = text
      }
    }

    // WorkField: podręczna lista gatunków dla trybu masowego —
    // klik ustawia pędzel, bez otwierania zdjęcia
    ListView {
      id: masowaLista

      Layout.fillWidth: true
      Layout.preferredHeight: visible ? 140 : 0
      visible: photoGallery.trybMasowy && galleryTabs.currentIndex === 0
      clip: true
      model: tagPanel.suggestions

      onVisibleChanged: {
        if (visible)
          tagPanel.updateSuggestions();
      }

      ScrollBar.vertical: ScrollBar {
      }

      delegate: ItemDelegate {
        required property var modelData

        width: masowaLista.width
        height: 30

        background: Rectangle {
          color: tagInput.text.trim() === modelData.name ? photoGallery.t.mainColor : "transparent"
          radius: 4
        }

        contentItem: RowLayout {
          spacing: 6

          Rectangle {
            Layout.leftMargin: 6
            width: 10
            height: 10
            radius: 5
            color: photoGallery.tagColor(modelData.name)
            border.color: "white"
            border.width: 1
          }

          Text {
            Layout.fillWidth: true
            text: modelData.name
            font: photoGallery.t.tipFont
            color: tagInput.text.trim() === modelData.name ? "white" : photoGallery.t.mainTextColor
            elide: Text.ElideRight
          }

          Text {
            Layout.rightMargin: 8
            text: modelData.n > 0 ? modelData.n : ""
            font: photoGallery.t.tinyFont
            color: photoGallery.t.secondaryTextColor
          }
        }

        onClicked: tagInput.text = modelData.name
      }
    }
'''),
]


def main():
    with io.open('src/app/qml/QfPhotoGallery.qml', encoding='utf-8') as f:
        if 'masowaLista' in f.read():
            print('pakiet 14a już wpięty — pomijam')
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
    print('\nPakiet 14a wpięty: ścinanie + lista gatunków.')


if __name__ == '__main__':
    main()
