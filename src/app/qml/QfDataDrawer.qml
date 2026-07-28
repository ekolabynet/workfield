import QtQuick
import Qt.labs.folderlistmodel
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
  dragMargin: 10
  interactive: opened || !overlayFeatureFormDrawer.opened


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
        text: qsTr("Narzędzia")
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

    StackLayout {
      id: drawerStack

      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: drawerTabs.currentIndex


      // ── Narzędzia ───────────────────────────────────────────
      ColumnLayout {
        spacing: 0

        ListView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: 0

          model: [
            { "label": qsTr("Pomiar odległości i powierzchni"), "action": "measurement" },
            { "label": qsTr("Widok 3D"), "action": "view3d" },
            { "label": qsTr("Wydruki map"), "action": "print" },
            { "label": qsTr("Zakładki przestrzenne"), "action": "bookmarks" },
            { "label": qsTr("Wtyczki"), "action": "plugins" },
            { "label": qsTr("Zablokuj ekran"), "action": "lockScreen" },
            { "label": qsTr("Policz CHM (NMPT \u2212 NMT)"), "action": "chm" }
          ]

          delegate: MenuItem {
            width: ListView.view.width
            font: Theme.defaultFont
            text: modelData.label

            onClicked: {
              switch (modelData.action) {
              case "measurement":
                dashBoard.toggleMeasurementTool();
                break;
              case "view3d":
                dashBoard.toggle3DView();
                break;
              case "print":
                dashBoard.showPrintLayouts(mapToItem(null, 0, height));
                break;
              case "bookmarks":
                dashBoard.showBookmarks();
                dataDrawer.close();
                break;
              case "plugins":
                dashBoard.showPluginManager();
                dataDrawer.close();
                break;
              case "lockScreen":
                dashBoard.lockScreen();
                dataDrawer.close();
                break;
              }
            }
          }
        }
      }

      // ── Algorytmy ───────────────────────────────────────────
      ColumnLayout {
        spacing: 0

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
      Layout.leftMargin: 8
      Layout.rightMargin: 8
      spacing: 8

      Label {
        Layout.fillWidth: true
        text: dataDrawer.activeLayer ? qsTr("Warstwa robocza: %1").arg(dataDrawer.activeLayer.name) : qsTr("Nie wybrano warstwy roboczej")
        font: t.defaultFont
        color: t.mainTextColor
        elide: Text.ElideMiddle
      }

      Button {
        text: qsTr("Zmień…")
        font.pointSize: t.tinyFont.pointSize
        onClicked: layerPickerDialog.open()
      }
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

      // ── System ──────────────────────────────────────────────
      ColumnLayout {
        spacing: 0

        MenuItem {
          Layout.fillWidth: true
          font: Theme.defaultFont
          text: qsTr("Ustawienia aplikacji")
          onClicked: {
            dashBoard.showSettings();
            dataDrawer.close();
          }
        }

        MenuItem {
          Layout.fillWidth: true
          font: Theme.defaultFont
          text: qsTr("O aplikacji WorkField")
          onClicked: {
            dashBoard.showAbout();
            dataDrawer.close();
          }
        }

        MenuItem {
          Layout.fillWidth: true
          font: Theme.defaultFont
          text: qsTr("Dziennik komunikatów")
          onClicked: {
            dashBoard.showMessageLog();
            dataDrawer.close();
          }
        }

        MenuItem {
          Layout.fillWidth: true
          font: Theme.defaultFont
          text: qsTr("Udostępnij dziennik (debug)")
          onClicked: {
            const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss");
            const path = iface.dataRoot() + "logs/workfield_log_" + stamp + ".txt";
            if (iface.writeTextFile(path, messageLogModel.toPlainText())) {
              displayToast(qsTr("Dziennik zapisany: %1").arg(path));
              platformUtilities.sendDatasetTo(path);
            } else {
              displayToast(qsTr("Nie udało się zapisać dziennika"), "error");
            }
            dataDrawer.close();
          }
        }

        Item {
          Layout.fillHeight: true
        }
      }
    }

    TabBar {
      id: drawerTabs

      Layout.fillWidth: true
      currentIndex: 0

      TabButton {
        text: qsTr("Narzędzia")
        font: t.tipFont
      }
      TabButton {
        text: qsTr("Algorytmy")
        font: t.tipFont
      }
      TabButton {
        text: qsTr("System")
        font: t.tipFont
      }
    }
  }

  Dialog {
    id: layerPickerDialog

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 420)
    height: Math.min(mainWindow.height - 120, 520)
    modal: true
    title: qsTr("Wybierz warstwę roboczą")

    ListView {
      anchors.fill: parent
      clip: true
      model: dataDrawer.layerTree

      delegate: ItemDelegate {
        width: ListView.view.width
        visible: model.LayerType === "vectorlayer" && model.VectorLayerPointer && !model.VectorLayerPointer.readOnly
        height: visible ? implicitHeight : 0
        font: t.defaultFont
        text: model.Name !== undefined ? model.Name : ""

        onClicked: {
          dataDrawer.layerActivated(model.VectorLayerPointer);
          layerPickerDialog.close();
        }
      }
    }
  }
}
