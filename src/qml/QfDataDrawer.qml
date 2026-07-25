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

  onOpenedChanged: {
    if (opened)
      projectSection.refresh();
  }

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

    ColumnLayout {
      id: projectSection

      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 4

      property bool dirty: false
      property string filePath: ""

      function refresh() {
        dirty = ProjectUtils.isProjectDirty(qgisProject);
        filePath = qgisProject ? ProjectUtils.projectFilePath(qgisProject) : "";
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: qsTr("Projekt")
          font: t.strongTipFont
          color: t.mainTextColor
        }

        Text {
          text: projectSection.dirty ? qsTr("niezapisane zmiany") : ""
          font: t.tinyFont
          color: t.warningColor
        }
      }

      Text {
        Layout.fillWidth: true
        text: projectSection.filePath !== "" ? FileUtils.fileName(projectSection.filePath) : qsTr("projekt niezapisany")
        font: t.tinyFont
        color: t.secondaryTextColor
        elide: Text.ElideMiddle
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Zapisz projekt")
        font.pointSize: t.tinyFont.pointSize
        enabled: projectSection.filePath !== ""

        onClicked: {
          if (ProjectUtils.saveProject(qgisProject)) {
            displayToast(qsTr("Projekt zapisany"));
            projectSection.refresh();
          } else {
            displayToast(qsTr("Nie udało się zapisać projektu"));
          }
        }
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
        id: addBasemapButton
        Layout.fillWidth: true
        text: qsTr("Podkład")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dataDrawer.close();
          basemapScreen.open();
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
            iconSource: t.getThemeVectorIcon("ic_create_white_24dp")
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

          QfToolButton {
            width: 30
            height: 30
            padding: 0
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_edit_attributes_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor

            onClicked: {
              dataDrawer.close();
              layerFieldsScreen.openFor(model.VectorLayerPointer);
            }
          }

          QfToolButton {
            Layout.rightMargin: 4
            width: 30
            height: 30
            padding: 0
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_delete_forever_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor

            onClicked: {
              removeLayerConfirm.targetLayer = model.VectorLayerPointer;
              removeLayerConfirm.targetName = model.Name;
              removeLayerConfirm.open();
            }
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

  Popup {
    id: removeLayerConfirm

    property var targetLayer: null
    property string targetName: ""

    parent: mainWindow.contentItem
    width: Math.min(380, mainWindow.width - 32)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    modal: true
    closePolicy: Popup.CloseOnEscape

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Usunąć warstwę z projektu?")
        font: t.strongFont
        color: t.mainTextColor
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: removeLayerConfirm.targetName
        font: t.tipFont
        color: t.secondaryTextColor
        elide: Text.ElideMiddle
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Plik z danymi pozostanie na dysku.")
        font: t.tinyFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 8

        Button {
          Layout.fillWidth: true
          text: qsTr("Anuluj")
          onClicked: removeLayerConfirm.close()
        }

        Button {
          Layout.fillWidth: true
          text: qsTr("Usuń")
          highlighted: true

          onClicked: {
            if (removeLayerConfirm.targetLayer) {
              ProjectUtils.removeMapLayer(qgisProject, removeLayerConfirm.targetLayer);
              displayToast(qsTr("Usunięto warstwę %1").arg(removeLayerConfirm.targetName));
            }
            removeLayerConfirm.close();
          }
        }
      }
    }
  }
}
