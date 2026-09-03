#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 33 — pelna paleta Materialize CSS w QfColorPicker.

POWOD (Piotr, 19.08): "do recznego hand-pickingu chce miec dokladnie to
Materialize CSS — zawiera bardzo duzo odcieni, ktore mi sa potrzebne".
Przy 84 kategoriach platow rzadek dwunastu kolorow nie wystarcza: sasiednie
kategorie zlewaja sie na mapie i nie ma z czego wybrac odcienia obok.

CO BYLO: 11 wierszy x 10 odcieni = 110 kolorow. Dziesiec barw + szarosci,
odcienie 50..900. BEZ AKCENTOW i bez polowy barw.

CO JEST: pelny zestaw Materialize CSS — 19 barw x maks. 14 wariantow
(50..900 + A100/A200/A400/A700) + wiersz biel/czern = 256 kolorow.
Dolozone barwy, ktorych w ogole nie bylo: deep-purple, indigo, light-blue,
cyan, teal, light-green, lime, amber, deep-orange, blue-grey.
Akcenty (A100..A700) to te jaskrawe odcienie, ktorych brakowalo najbardziej
przy odrozanianiu sasiednich kategorii.

SIATKA PRZEWIJANA w obie strony (decyzja Piotra), bo 14 kolumn po 28 px
nie miesci sie w oknie na telefonie. Kafelek ma staly rozmiar zamiast
kurczyc sie do szerokosci okna — przy 19 wierszach kurczenie zrobiloby
z tego mozaike nie do trafienia palcem.

CZEGO NIE RUSZA: sygnal colorPicked, kanal alfa, opcje obrysu, wszyscy
dotychczasowi uzytkownicy pickera (kafle paska, edytor klawiszy,
podpowiedzi). To wymiana danych i kontenera, nie API.

Uruchom w korzeniu repo:  python3 zastosuj_palete.py
Idempotentna. Kopia: QfColorPicker.qml.przed_paleta
"""
import os
import shutil
import sys

PLIK = "src/app/qml/QfColorPicker.qml"
MARKER = "materializeCss"

# --------------------------------------------------------------------- dane
# Materialize CSS / Material Design: 50..900 + A100, A200, A400, A700.
# brown / grey / blue-grey nie maja akcentow — wiersze sa krotsze i tak
# maja zostac (dopychanie ich pustymi polami klamaloby, ze cos tam jest).

PALETA = [
    ("red", ["#ffebee", "#ffcdd2", "#ef9a9a", "#e57373", "#ef5350", "#f44336",
             "#e53935", "#d32f2f", "#c62828", "#b71c1c",
             "#ff8a80", "#ff5252", "#ff1744", "#d50000"]),
    ("pink", ["#fce4ec", "#f8bbd0", "#f48fb1", "#f06292", "#ec407a", "#e91e63",
              "#d81b60", "#c2185b", "#ad1457", "#880e4f",
              "#ff80ab", "#ff4081", "#f50057", "#c51162"]),
    ("purple", ["#f3e5f5", "#e1bee7", "#ce93d8", "#ba68c8", "#ab47bc", "#9c27b0",
                "#8e24aa", "#7b1fa2", "#6a1b9a", "#4a148c",
                "#ea80fc", "#e040fb", "#d500f9", "#aa00ff"]),
    ("deep-purple", ["#ede7f6", "#d1c4e9", "#b39ddb", "#9575cd", "#7e57c2", "#673ab7",
                     "#5e35b1", "#512da8", "#4527a0", "#311b92",
                     "#b388ff", "#7c4dff", "#651fff", "#6200ea"]),
    ("indigo", ["#e8eaf6", "#c5cae9", "#9fa8da", "#7986cb", "#5c6bc0", "#3f51b5",
                "#3949ab", "#303f9f", "#283593", "#1a237e",
                "#8c9eff", "#536dfe", "#3d5afe", "#304ffe"]),
    ("blue", ["#e3f2fd", "#bbdefb", "#90caf9", "#64b5f6", "#42a5f5", "#2196f3",
              "#1e88e5", "#1976d2", "#1565c0", "#0d47a1",
              "#82b1ff", "#448aff", "#2979ff", "#2962ff"]),
    ("light-blue", ["#e1f5fe", "#b3e5fc", "#81d4fa", "#4fc3f7", "#29b6f6", "#03a9f4",
                    "#039be5", "#0288d1", "#0277bd", "#01579b",
                    "#80d8ff", "#40c4ff", "#00b0ff", "#0091ea"]),
    ("cyan", ["#e0f7fa", "#b2ebf2", "#80deea", "#4dd0e1", "#26c6da", "#00bcd4",
              "#00acc1", "#0097a7", "#00838f", "#006064",
              "#84ffff", "#18ffff", "#00e5ff", "#00b8d4"]),
    ("teal", ["#e0f2f1", "#b2dfdb", "#80cbc4", "#4db6ac", "#26a69a", "#009688",
              "#00897b", "#00796b", "#00695c", "#004d40",
              "#a7ffeb", "#64ffda", "#1de9b6", "#00bfa5"]),
    ("green", ["#e8f5e9", "#c8e6c9", "#a5d6a7", "#81c784", "#66bb6a", "#4caf50",
               "#43a047", "#388e3c", "#2e7d32", "#1b5e20",
               "#b9f6ca", "#69f0ae", "#00e676", "#00c853"]),
    ("light-green", ["#f1f8e9", "#dcedc8", "#c5e1a5", "#aed581", "#9ccc65", "#8bc34a",
                     "#7cb342", "#689f38", "#558b2f", "#33691e",
                     "#ccff90", "#b2ff59", "#76ff03", "#64dd17"]),
    ("lime", ["#f9fbe7", "#f0f4c3", "#e6ee9c", "#dce775", "#d4e157", "#cddc39",
              "#c0ca33", "#afb42b", "#9e9d24", "#827717",
              "#f4ff81", "#eeff41", "#c6ff00", "#aeea00"]),
    ("yellow", ["#fffde7", "#fff9c4", "#fff59d", "#fff176", "#ffee58", "#ffeb3b",
                "#fdd835", "#fbc02d", "#f9a825", "#f57f17",
                "#ffff8d", "#ffff00", "#ffea00", "#ffd600"]),
    ("amber", ["#fff8e1", "#ffecb3", "#ffe082", "#ffd54f", "#ffca28", "#ffc107",
               "#ffb300", "#ffa000", "#ff8f00", "#ff6f00",
               "#ffe57f", "#ffd740", "#ffc400", "#ffab00"]),
    ("orange", ["#fff3e0", "#ffe0b2", "#ffcc80", "#ffb74d", "#ffa726", "#ff9800",
                "#fb8c00", "#f57c00", "#ef6c00", "#e65100",
                "#ffd180", "#ffab40", "#ff9100", "#ff6d00"]),
    ("deep-orange", ["#fbe9e7", "#ffccbc", "#ffab91", "#ff8a65", "#ff7043", "#ff5722",
                     "#f4511e", "#e64a19", "#d84315", "#bf360c",
                     "#ff9e80", "#ff6e40", "#ff3d00", "#dd2c00"]),
    ("brown", ["#efebe9", "#d7ccc8", "#bcaaa4", "#a1887f", "#8d6e63", "#795548",
               "#6d4c41", "#5d4037", "#4e342e", "#3e2723"]),
    ("grey", ["#fafafa", "#f5f5f5", "#eeeeee", "#e0e0e0", "#bdbdbd", "#9e9e9e",
              "#757575", "#616161", "#424242", "#212121"]),
    ("blue-grey", ["#eceff1", "#cfd8dc", "#b0bec5", "#90a4ae", "#78909c", "#607d8b",
                   "#546e7a", "#455a64", "#37474f", "#263238"]),
    ("mono", ["#ffffff", "#000000"]),
]


def paleta_qml():
    linie = ["  // Materialize CSS: 50..900 + akcenty A100/A200/A400/A700.",
             "  // brown / grey / blue-grey nie maja akcentow — wiersze sa krotsze.",
             "  readonly property bool materializeCss: true",
             "",
             "  readonly property var palette: ["]
    for i, (nazwa, kolory) in enumerate(PALETA):
        przecinek = "," if i < len(PALETA) - 1 else ""
        wpis = ", ".join('"%s"' % k for k in kolory)
        linie.append("    [%s]%s  // %s" % (wpis, przecinek, nazwa))
    linie.append("  ]")
    return "\n".join(linie) + "\n"


# ------------------------------------------------------------------- siatka

SIATKA_STARA = '''    Column {
      Layout.fillWidth: true
      spacing: 3

      Repeater {
        model: colorPicker.palette

        delegate: Row {
          required property var modelData

          spacing: 3

          Repeater {
            model: parent.modelData

            delegate: Rectangle {
              required property string modelData

              width: (colorPicker.width - 24 - 27) / 10
              height: width
              radius: 3
              color: modelData
              border.width: Qt.colorEqual(colorPicker.currentColor, modelData) ? 2 : 0
              border.color: t.mainTextColor

              MouseArea {
                anchors.fill: parent
                onClicked: colorPicker.currentColor = parent.modelData
              }
            }
          }
        }
      }
    }'''

SIATKA_NOWA = '''    // WorkField 19.08.2026: pelna paleta Materialize CSS (19 barw x maks. 14
    // wariantow). Kafelek ma STALY rozmiar, a siatka przewija sie w obie
    // strony — kurczenie kafelkow do szerokosci okna zrobiloby z 19 wierszy
    // mozaike nie do trafienia palcem w rekawicy.
    Flickable {
      id: paletteView

      readonly property int cellSize: 28
      readonly property int cellSpacing: 3
      readonly property int maxColumns: {
        let n = 0;
        for (let i = 0; i < colorPicker.palette.length; ++i)
          n = Math.max(n, colorPicker.palette[i].length);
        return n;
      }

      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(paletteGrid.height, mainWindow.height * 0.45)

      contentWidth: paletteGrid.width
      contentHeight: paletteGrid.height
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.HorizontalAndVerticalFlick

      ScrollBar.vertical: ScrollBar {
        policy: paletteView.contentHeight > paletteView.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
      }
      ScrollBar.horizontal: ScrollBar {
        policy: paletteView.contentWidth > paletteView.width ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
      }

      Column {
        id: paletteGrid

        width: paletteView.maxColumns * (paletteView.cellSize + paletteView.cellSpacing)
        spacing: paletteView.cellSpacing

        Repeater {
          model: colorPicker.palette

          delegate: Row {
            required property var modelData

            spacing: paletteView.cellSpacing

            Repeater {
              model: parent.modelData

              delegate: Rectangle {
                required property string modelData

                width: paletteView.cellSize
                height: paletteView.cellSize
                radius: 3
                color: modelData
                border.width: Qt.colorEqual(colorPicker.currentColor, modelData) ? 2 : 1
                border.color: Qt.colorEqual(colorPicker.currentColor, modelData) ? t.mainTextColor : t.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: colorPicker.currentColor = parent.modelData
                }
              }
            }
          }
        }
      }
    }'''

# ----------------------------------------------------------------- mechanika


def main():
    if not os.path.exists(PLIK):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % PLIK)

    t = open(PLIK, encoding="utf-8").read()

    if MARKER in t:
        print("Latka 33 juz jest — nic do zrobienia.")
        return

    start = t.find("  readonly property var palette: [")
    if start < 0:
        sys.exit("STOP: nie znalazlem tablicy palette")
    koniec = t.find("\n  ]\n", start)
    if koniec < 0:
        sys.exit("STOP: nie znalazlem konca tablicy palette")
    koniec += len("\n  ]\n")

    if t.count(SIATKA_STARA) != 1:
        sys.exit("STOP: kotwica siatki wystepuje %d razy, oczekiwano 1"
                 % t.count(SIATKA_STARA))

    ile = sum(len(k) for _, k in PALETA)
    print("Kotwice policzone (2/2). Paleta: %d wierszy, %d kolorow."
          % (len(PALETA), ile))

    nowy = t[:start] + paleta_qml() + t[koniec:]
    nowy = nowy.replace(SIATKA_STARA, SIATKA_NOWA, 1)

    kopia = PLIK + ".przed_paleta"
    if not os.path.exists(kopia):
        shutil.copy2(PLIK, kopia)
    open(PLIK, "w", encoding="utf-8").write(nowy)
    print("  zapisano %s (kopia: %s)" % (PLIK, os.path.basename(kopia)))

    print("\nGotowe. Build:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'rcc|error'")
    print("W logu MUSI byc 'Running rcc for resource app_qml'.")
    print("\nSprawdz w kazdym miejscu, gdzie picker juz byl:")
    print("  ustawienia kafli paska, edytor klawiszy, wypelnienie warstwy.")


if __name__ == "__main__":
    main()
