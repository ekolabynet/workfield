import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import org.qfield.gui // [WF-BUTTONS] QfDecisionButton
import Theme

// [WF-WINDOW-FRAME] 24.10.2026 — common frame: ✕/✓ in the title bar, scrolling body
QfWindowFrame {
  id: subLayerPicker

  title: qsTr("Wybierz warstwy")
  confirmText: qsTr("Dodaj")
  onConfirmed: confirm()

  property var t
  property string sourcePath: ""
  property var entries: []

  signal layersChosen(var uris)

  function openFor(path) {
    sourcePath = path;
    entries = LayerUtils.vectorSubLayers(path);
    if (entries.length === 0) {
      displayToast(qsTr("Nie znaleziono warstw wektorowych"));
      return;
    }
    if (entries.length === 1) {
      layersChosen([entries[0]]);
      return;
    }
    open();
  }

  // [WF-WINDOW-FRAME] ✓ in the title bar (was the „Dodaj” button below)
  function confirm() {
    let chosen = [];
    for (let i = 0; i < subLayerPicker.entries.length; i++) {
      if (entryList.selection[i] === true)
        chosen.push(subLayerPicker.entries[i]);
    }
    if (chosen.length > 0)
      subLayerPicker.layersChosen(chosen);
    subLayerPicker.close();
  }

  Text {
    Layout.fillWidth: true
    text: FileUtils.fileName(subLayerPicker.sourcePath)
    font: t.tipFont
    color: t.secondaryTextColor
    elide: Text.ElideMiddle
  }

  ListView {
    id: entryList

    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(contentHeight, 320)
    clip: true
    model: subLayerPicker.entries

    property var selection: ({})

    delegate: ItemDelegate {
      required property int index
      required property var modelData

      width: entryList.width
      height: 56

      contentItem: RowLayout {
        spacing: 8

        CheckBox {
          checked: entryList.selection[index] === true
          onToggled: {
            let sel = entryList.selection;
            sel[index] = checked;
            entryList.selection = sel;
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          Text {
            Layout.fillWidth: true
            text: modelData.name
            font: t.strongTipFont
            color: t.mainTextColor
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            // WorkField 23.08.2026 — druga polowa naprawy "-2 obiektów".
            // Nawet po dolozeniu liczenia w querySublayers czesc zrodel
            // policzyc sie nie da. Wtedy mowimy, ze nie wiemy, zamiast
            // pokazywac ujemna liczbe obiektow.
            text: modelData.featureCount < 0
                  ? modelData.geometry + " · " + qsTr("liczba obiektów nieznana")
                  : modelData.geometry + " · " + qsTr("obiektów: %1").arg(modelData.featureCount)
            font: t.tinyFont
            color: t.secondaryTextColor
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
