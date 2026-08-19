#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 35 — miniatury ramp przy nazwach na liscie wyboru.

Latka 34 dala pasek podgladu POD lista, czyli widac bylo tylko rampe juz
wybrana. Wybor odbywal sie po nazwach: "Inferno", "Mako", "PuBuGn", "RdYlBu"
— napisy nic nie mowia o tym, jak rzecz wyglada, wiec zeby zobaczyc rampe,
trzeba bylo ja wybrac. To ta sama wada co menu, ktore nie mowi, dokad
prowadzi: dowiadujesz sie po fakcie.

Teraz kazda pozycja listy niesie wlasny gradient obok nazwy, a zwiniete
pole pokazuje gradient wybranej rampy zamiast samego napisu.

Zrodlem kolorow jest LayerUtils.colorRampPreview( nazwa, ile ) z latki 34 —
nowego C++ nie trzeba.

KOSZT: gradient liczy sie na pozycje listy dopiero, gdy delegat powstaje
(ComboBox tworzy je leniwie), po 12 kolorow. Przy kilkudziesieciu rampach
to kilkaset wywolan rozlozonych na przewijanie, nie na otwarcie.

Uruchom w korzeniu repo:  python3 zastosuj_miniatury_ramp.py
Wymaga latki 34. Idempotentna. Kopia: LayerTreeItemProperties.qml.przed_miniaturami
"""
import os
import shutil
import sys

Q = "src/gui/qml/LayerTreeItemProperties.qml"
MARKER = "rampSwatch"

STARE = """            ComboBox {
              id: rampCombo

              Layout.fillWidth: true
              font: Theme.defaultFont
              model: LayerUtils.colorRampNames()
              currentIndex: Math.max(0, model.indexOf(pendingRamp))
"""

NOWE = """            ComboBox {
              id: rampCombo

              Layout.fillWidth: true
              font: Theme.defaultFont
              model: LayerUtils.colorRampNames()
              currentIndex: Math.max(0, model.indexOf(pendingRamp))

              // WorkField 19.08.2026: nazwa rampy nic nie mowi o tym, jak
              // rampa wyglada ("Mako", "PuBuGn", "RdYlBu"). Kazda pozycja
              // niesie wiec wlasny gradient — wybiera sie okiem, nie pamiecia.
              component RampSwatch: Row {
                id: rampSwatch

                property string rampName: ""
                property int cells: 12
                property real cellWidth: 5
                property real cellHeight: 14

                spacing: 0

                Repeater {
                  model: LayerUtils.colorRampPreview(rampSwatch.rampName, rampSwatch.cells)

                  delegate: Rectangle {
                    required property var modelData
                    width: rampSwatch.cellWidth
                    height: rampSwatch.cellHeight
                    color: modelData
                  }
                }
              }

              delegate: ItemDelegate {
                id: rampItem

                required property var modelData
                required property int index

                width: rampCombo.width
                highlighted: rampCombo.highlightedIndex === index

                contentItem: RowLayout {
                  spacing: 8

                  RampSwatch {
                    rampName: rampItem.modelData
                  }

                  Text {
                    Layout.fillWidth: true
                    text: rampItem.modelData
                    font: Theme.defaultFont
                    color: Theme.mainTextColor
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }

              // zwiniete pole: gradient wybranej rampy zamiast samego napisu
              contentItem: RowLayout {
                spacing: 8

                RampSwatch {
                  Layout.leftMargin: 8
                  rampName: rampCombo.currentText
                }

                Text {
                  Layout.fillWidth: true
                  text: rampCombo.currentText
                  font: Theme.defaultFont
                  color: Theme.mainTextColor
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }
              }
"""


def main():
    if not os.path.exists(Q):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % Q)

    t = open(Q, encoding="utf-8").read()

    if "pendingRamp" not in t:
        sys.exit("STOP: brak latki 34 (wybor rampy). Naloz ja najpierw.")

    if MARKER in t:
        print("Latka 35 juz jest — nic do zrobienia.")
        return

    n = t.count(STARE)
    if n != 1:
        sys.exit("STOP: kotwica wystepuje %d razy, oczekiwano 1" % n)

    print("Kotwica policzona (1/1), nakladam:")

    kopia = Q + ".przed_miniaturami"
    if not os.path.exists(kopia):
        shutil.copy2(Q, kopia)
    open(Q, "w", encoding="utf-8").write(t.replace(STARE, NOWE, 1))
    print("  zapisano %s (kopia: %s)" % (Q, os.path.basename(kopia)))

    print("\nGotowe. Build:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'rcc|error' | head")
    print("W logu MUSI byc 'Running rcc for resource gui_qml'.")
    print("\nPasek podgladu POD lista z latki 34 zostaje — pokazuje wybrana")
    print("rampe szerzej niz miniatura. Jesli przeszkadza, powiedz, zdejme.")


if __name__ == "__main__":
    main()
