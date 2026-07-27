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
            { "label": qsTr("Pobierz NMT (obszar mapy)"), "action": "nmt" },
            { "label": qsTr("Pobierz NMPT (obszar mapy)"), "action": "nmpt" },
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
              case "nmt":
                dashBoard.requestDem("NMT");
                dataDrawer.close();
                break;
              case "nmpt":
                dashBoard.requestDem("NMPT");
                dataDrawer.close();
                break;
              case "chm":
                dashBoard.computeChmAction();
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
            elide: Text.ElideMiddle
          }

          Text {
            text: isVector ? model.VectorLayerPointer.crs.authid : ""
            font: t.tinyFont
            color: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: 0.7
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
}
