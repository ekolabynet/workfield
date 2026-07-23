import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

Drawer {
  id: dataDrawer

  property var t
  property var layerTree
  property var activeLayer

  signal layerActivated(var layer)
  signal modeToggled(bool digitize)
  signal addExistingRequested

  edge: Qt.RightEdge
  width: Math.min(360, mainWindow.width * 0.85)
  height: parent.height
  dragMargin: 0
  interactive: opened

  background: Rectangle {
    color: t.mainBackgroundColor
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.topMargin: mainWindow.sceneTopMargin
    anchors.bottomMargin: mainWindow.sceneBottomMargin
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Dane")
        font: t.strongFont
        color: t.mainTextColor
      }

      QfToolButton {
        width: 36
        height: 36
        padding: 0
        bgcolor: "transparent"
        iconSource: t.getThemeVectorIcon("ic_arrow_right_black_24dp")
        iconColor: t.mainTextColor
        onClicked: dataDrawer.close()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text {
          text: qsTr("Tryb pracy")
          font: t.strongTipFont
          color: t.mainTextColor
        }

        Text {
          text: modeToggle.checked ? qsTr("Digitalizacja") : qsTr("Przeglądanie")
          font: t.tipFont
          color: modeToggle.checked ? t.mainColor : t.secondaryTextColor
        }
      }

      Switch {
        id: modeToggle
        checked: stateMachine.state === "digitize"
        onToggled: dataDrawer.modeToggled(checked)
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      Button {
        id: newLayerButton
        Layout.fillWidth: true
        text: qsTr("Nowa warstwa")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dataDrawer.close();
          newLayerDialog.openDialog();
        }
      }

      Button {
        id: addLayerButton
        Layout.fillWidth: true
        text: qsTr("Dodaj z pliku")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dataDrawer.close();
          dataDrawer.addExistingRequested();
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.margins: 8
      text: qsTr("Warstwa robocza")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    ListView {
      id: editableLayers

      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(contentHeight, 240)
      clip: true
      model: dataDrawer.layerTree

      delegate: ItemDelegate {
        required property int index
        required property var model

        readonly property bool isVector: model.LayerType === "vectorlayer" && model.VectorLayerPointer
        readonly property bool isWritable: isVector && !model.VectorLayerPointer.readOnly
        readonly property bool isCurrent: isVector && model.VectorLayerPointer === dataDrawer.activeLayer

        width: editableLayers.width
        height: isWritable ? 44 : 0
        visible: isWritable

        background: Rectangle {
          color: isCurrent ? t.mainColor : "transparent"
        }

        contentItem: RowLayout {
          spacing: 8

          QfToolButton {
            Layout.leftMargin: 4
            width: 22
            height: 22
            padding: 0
            enabled: false
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("NAZWA_Z_DRUGIEJ_LISTY")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: isCurrent ? 1.0 : 0.3
          }

          Text {
            Layout.fillWidth: true
            text: model.Name
            font: t.defaultFont
            color: isCurrent ? t.mainOverlayColor : t.mainTextColor
            elide: Text.ElideRight
          }
        }

        onClicked: {
          if (isWritable)
            dataDrawer.layerActivated(model.VectorLayerPointer);
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    Text {
      Layout.fillWidth: true
      Layout.margins: 8
      text: qsTr("Algorytmy")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: 8
      Layout.rightMargin: 8
      visible: !dataDrawer.activeLayer
      text: qsTr("Wybierz warstwę roboczą, aby zobaczyć dostępne algorytmy.")
      font: t.tipFont
      color: t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    ProcessingAlgorithmsList {
      id: algorithmsList

      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: dataDrawer.activeLayer !== null && dataDrawer.activeLayer !== undefined
      inPlaceLayer: dataDrawer.activeLayer
    }
  }
}
