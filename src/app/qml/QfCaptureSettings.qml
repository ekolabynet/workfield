import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qgis
import org.qfield
import QfTheme

/**
 * \ingroup qml
 *
 * WorkField: konfiguracja klawiszy paska szybkiego zapisu.
 * Definicje mieszkaja w pliku workfield_klawisze.json w katalogu projektu,
 * wiec wedruja razem z nim (takze przez QFieldSync) i sa czytelne w edytorze.
 */
QfPopup {
  id: captureSettings

  property var t

  property var wpisy: []
  property string odleglosci: "25, 50, 100, 200"

  readonly property var paleta: ["#69F0AE", "#AB47BC", "#FF9800", "#18FFFF", "#C6FF00", "#B0BEC5", "#FFAB91", "#F48FB1"]

  parent: mainWindow.contentItem
  width: Math.min(520, mainWindow.width - 24)
  height: Math.min(640, mainWindow.height - 48)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: QfPopup.CloseOnEscape

  background: Rectangle {
    color: "#EE263238"
    radius: 8
    border.color: "#455A64"
    border.width: 1
  }

  function openDialog() {
    const zapisane = quickCaptureBar.loadDefinitions();
    if (zapisane && zapisane.klawisze) {
      wpisy = zapisane.klawisze.slice();
      odleglosci = (zapisane.odleglosci || [25, 50, 100, 200]).join(", ");
    } else {
      // brak pliku: zaczynamy od tego, co pasek rozpoznal sam
      const z_paska = [];
      for (let i = 0; i < quickCaptureBar.resolvedLayers.length; i++) {
        const r = quickCaptureBar.resolvedLayers[i];
        z_paska.push({
            "warstwa": r.layer ? String(r.layer.name) : "",
            "etykieta": r.letter,
            "kolor": String(r.color),
            "zdjecie": r.mode !== "digitize"
          });
      }
      wpisy = z_paska;
      odleglosci = "25, 50, 100, 200";
    }
    visible = true;
  }

  function przesun(i, o) {
    const j = i + o;
    if (j < 0 || j >= wpisy.length) {
      return;
    }
    const kopia = wpisy.slice();
    const x = kopia[i];
    kopia[i] = kopia[j];
    kopia[j] = x;
    wpisy = kopia;
  }

  function usun(i) {
    const kopia = wpisy.slice();
    kopia.splice(i, 1);
    wpisy = kopia;
  }

  function zmienPole(i, pole, wartosc) {
    const kopia = wpisy.slice();
    kopia[i][pole] = wartosc;
    wpisy = kopia;
  }

  function nastepnyKolor(biezacy) {
    const i = paleta.indexOf(biezacy);
    return paleta[(i + 1) % paleta.length];
  }

  // przytrzymanie koloru = pelny picker (tap = karuzela jak dotad)
  property int kolorDlaIndeksu: -1

  Connections {
    target: colorPicker
    enabled: captureSettings.kolorDlaIndeksu >= 0

    function onColorPicked(chosen) {
      let hex = String(chosen);
      if (hex.length === 9) {
        hex = "#" + hex.substring(3);
      }
      captureSettings.zmienPole(captureSettings.kolorDlaIndeksu, "kolor", hex.toUpperCase());
    }

    function onClosed() {
      captureSettings.kolorDlaIndeksu = -1;
      colorPicker.allowAlpha = true;
    }
  }

  function dodaj(layer) {
    if (!layer) {
      return;
    }
    const nazwa = String(layer.name);
    for (let i = 0; i < wpisy.length; i++) {
      if (wpisy[i].warstwa === nazwa) {
        displayToast(qsTr("Ta warstwa już ma klawisz"), "warning");
        return;
      }
    }
    const kopia = wpisy.slice();
    kopia.push({
        "warstwa": nazwa,
        "etykieta": nazwa.substring(0, 2).toUpperCase(),
        "kolor": paleta[kopia.length % paleta.length],
        "zdjecie": true
      });
    wpisy = kopia;
  }

  function zapisz() {
    const dyst = odleglosci.split(",").map(x => parseInt(String(x).trim())).filter(x => !isNaN(x) && x > 0);
    const ok = quickCaptureBar.saveDefinitions({
        "wersja": 1,
        "klawisze": wpisy,
        "odleglosci": dyst.length > 0 ? dyst : [25, 50, 100, 200]
      });
    if (ok) {
      displayToast(qsTr("Zapisano klawisze projektu"));
      captureSettings.close();
    } else {
      displayToast(qsTr("Nie udało się zapisać (brak katalogu projektu?)"), "error");
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Klawisze szybkiego zapisu")
      color: "#80CBC4"
      font: QfTheme.strongFont
      wrapMode: Text.Wrap
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Ustawienia zapisują się do pliku w katalogu projektu, więc jadą razem z nim do zespołu.")
      color: "#B0BEC5"
      font: QfTheme.tinyFont
      wrapMode: Text.Wrap
    }

    ListView {
      id: lista
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: 4
      model: captureSettings.wpisy

      QfScrollBar.vertical: QfScrollBar {
      }

      delegate: Rectangle {
        width: lista.width
        height: 46
        radius: 4
        color: "#22FFFFFF"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 6
          anchors.rightMargin: 6
          spacing: 6

          Rectangle {
            width: 26
            height: 26
            radius: 13
            color: modelData.kolor
            border.color: "#003D33"
            border.width: 1

            MouseArea {
              anchors.fill: parent
              onClicked: captureSettings.zmienPole(index, "kolor", captureSettings.nastepnyKolor(modelData.kolor))
              onPressAndHold: {
                captureSettings.kolorDlaIndeksu = index;
                colorPicker.allowAlpha = false;
                colorPicker.openFor(modelData.kolor);
              }
            }
          }

          QfTextField {
            Layout.preferredWidth: 52
            text: modelData.etykieta
            color: "white"
            font: QfTheme.tipFont
            maximumLength: 3
            onEditingFinished: captureSettings.zmienPole(index, "etykieta", text)
          }

          Text {
            Layout.fillWidth: true
            text: modelData.warstwa
            color: "white"
            font: QfTheme.tinyFont
            elide: Text.ElideMiddle
          }

          QfToolButton {
            text: modelData.zdjecie ? "📷" : "✏"
            onClicked: captureSettings.zmienPole(index, "zdjecie", !modelData.zdjecie)
          }

          QfToolButton {
            text: "▲"
            onClicked: captureSettings.przesun(index, -1)
          }

          QfToolButton {
            text: "▼"
            onClicked: captureSettings.przesun(index, 1)
          }

          QfToolButton {
            text: "✕"
            onClicked: captureSettings.usun(index)
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        text: qsTr("Dodaj warstwę:")
        color: "#B0BEC5"
        font: QfTheme.tinyFont
      }

      QfComboBox {
        id: wyborWarstwy
        Layout.fillWidth: true
        textRole: "Name"
        valueRole: "LayerPointer"
        font: QfTheme.tipFont

        model: QfMapLayerModel {
          project: qgisProject
        }
      }

      QfButton {
        text: qsTr("Dodaj")
        onClicked: captureSettings.dodaj(wyborWarstwy.currentValue)
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        text: qsTr("Odległości (m):")
        color: "#B0BEC5"
        font: QfTheme.tinyFont
      }

      QfTextField {
        Layout.fillWidth: true
        text: captureSettings.odleglosci
        color: "white"
        font: QfTheme.tipFont
        onEditingFinished: captureSettings.odleglosci = text
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        onClicked: captureSettings.close()
      }

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Zapisz")
        onClicked: captureSettings.zapisz()
      }
    }
  }
}
