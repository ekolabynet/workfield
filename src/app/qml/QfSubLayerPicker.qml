import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import QfTheme

QfPopup {
  id: subLayerPicker

  property var t
  property string sourcePath: ""
  property var entries: []

  signal layersChosen(var uris)

  parent: mainWindow.contentItem
  width: Math.min(420, mainWindow.width - 32)
  height: Math.min(implicitHeight, mainWindow.height - 64)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: QfPopup.CloseOnEscape | QfPopup.CloseOnPressOutside

  function openFor(path) {
    sourcePath = path;
    entries = QfLayerUtils.vectorSubLayers(path);
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

  ColumnLayout {
    anchors.fill: parent
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Wybierz warstwy")
      font: t.strongFont
      color: t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: QfFileUtils.fileName(subLayerPicker.sourcePath)
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
              text: modelData.geometry + " · " + modelData.featureCount + " " + qsTr("obiektów")
              font: t.tinyFont
              color: t.secondaryTextColor
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      spacing: 8

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        onClicked: subLayerPicker.close()
      }

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Dodaj")
        highlighted: true

        onClicked: {
          let chosen = [];
          for (let i = 0; i < subLayerPicker.entries.length; i++) {
            if (entryList.selection[i] === true)
              chosen.push(subLayerPicker.entries[i]);
          }
          if (chosen.length > 0)
            subLayerPicker.layersChosen(chosen);
          subLayerPicker.close();
        }
      }
    }
  }
}
