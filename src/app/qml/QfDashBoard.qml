import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qgis
import org.qfield.core
import org.qfield.gui
import QfTheme

/**
 * \ingroup qml
 */
Drawer {
  id: dashBoard
  objectName: "dashBoard"

  signal showMainMenu(point p)
  signal showBookmarks
  signal showPluginManager
  signal showSettings
  signal showMessageLog
  signal lockScreen
  signal showAbout
  signal showPrintLayouts(point p)
  signal showCloudPopup
  signal showProjectFolder
  signal toggleMeasurementTool
  signal toggle3DView
  signal returnHome

  property bool preventFromOpening: overlayFeatureFormDrawer.visible
  property bool allowInteractive: true
  /// type:bool
  property alias allowActiveLayerChange: legend.allowActiveLayerChange
  /// type:QgsVectorLayer
  property alias activeLayer: legend.activeLayer
  /// type:QfFlatLayerTreeModel
  property alias layerTree: legend.model
  /// type:QgsQuickMapSettings
  property MapSettings mapSettings

  Component.onCompleted: {
    if (Material.roundedScale) {
      Material.roundedScale = Material.NotRounded;
    }
  }

  width: Math.min(Math.max(330, mainWindow.width * 0.8), mainWindow.width)
  height: parent.height
  edge: Qt.LeftEdge
  dragMargin: 10
  interactive: allowInteractive

  topPadding: 0
  leftPadding: 0
  rightPadding: 0
  bottomPadding: 0

  position: 0
  focus: visible
  clip: true

  onActiveLayerChanged: {
    if (activeLayer && activeLayer.readOnly && stateMachine.state === "digitize") {
      displayToast(qsTr("The layer %1 is read only.").arg(activeLayer.name));
    }
  }

  background: Rectangle {
    anchors.fill: parent
    color: QfTheme.mainBackgroundColor
  Connections {
    target: stateMachine

    function onStateChanged() {
      if (stateMachine.state === "measure") {
        return;
      }
      modeSwitch.checked = stateMachine.state === "digitize";
    }
  }

  background: Rectangle {
    anchors.fill: parent
    color: QfTheme.mainBackgroundColor
  }

  ColumnLayout {
    anchors.fill: parent



    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: mainWindow.sceneTopMargin + 44
      color: "transparent"

      QfToolButton {
        id: closeButton
        anchors.left: parent.left
        anchors.leftMargin: mainWindow.sceneLeftMargin
        anchors.bottom: parent.bottom
        iconSource: QfTheme.getThemeVectorIcon('ic_arrow_left_white_24dp')
        iconColor: QfTheme.mainTextColor
        bgcolor: "transparent"
        onClicked: close()
      }
    }

    SideMenu {
      id: sideMenu
      Layout.fillWidth: true
      Layout.leftMargin: mainWindow.sceneLeftMargin
      t: QfTheme

      onActionTriggered: (action, origin) => {
        switch (action) {
        case "legend":
          legendScreen.visible = true;
          close();
          break;
        case "measurement":
          toggleMeasurementTool();
          break;
        case "view3d":
          toggle3DView();
          break;
        case "print":
          showPrintLayouts(origin);
          break;
        case "projectFolder":
          showProjectFolder();
          break;
        case "newLayer":
          newLayerDialog.openDialog();
          close();
          break;
        case "bookmarks":
          showBookmarks();
          close();
          break;
        case "plugins":
          showPluginManager();
          close();
          break;
        case "settings":
          showSettings();
          close();
          break;
        case "messageLog":
          showMessageLog();
          close();
          break;
        case "lockScreen":
          lockScreen();
          close();
          break;
        case "about":
          showAbout();
          close();
          break;
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: QfTheme.controlBorderColor
    }
    RowLayout {
      id: projectInformationLayout
      height: 0
      implicitHeight: 0
      Layout.maximumHeight: 0
      Layout.minimumHeight: 0
      Layout.preferredHeight: 0
      Layout.margins: 0
      visible: false
      Layout.fillWidth: true
      Layout.leftMargin: mainWindow.sceneLeftMargin + 10
      Layout.rightMargin: 6
      Layout.bottomMargin: 5

      Text {
        id: projectTitleText
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: {
          if (qgisProject) {
            if (qgisProject.title !== "") {
              return qgisProject.title;
            } else if (cloudProjectsModel.currentProject) {
              return cloudProjectsModel.currentProject.name;
            } else {
              return QfFileUtils.fileName(qgisProject.fileName, false);
            }
          }
          return "";
        }
        font: QfTheme.strongFont
        color: QfTheme.mainTextColor
        elide: Text.ElideRight
      }

      QfToolButton {
        id: temporalButton
        Layout.alignment: Qt.AlignVCenter
        width: 36
        height: 36
        padding: 0
        visible: flatLayerTree.isTemporal
        iconSource: QfTheme.getThemeVectorIcon('ic_temporal_black_24dp')
        iconColor: mapSettings.isTemporal ? QfTheme.mainColor : QfTheme.mainTextColor
        bgcolor: "transparent"
        onClicked: temporalProperties.open()
      }

      QfToolButton {
        id: projectInformationButton

        property string projectDescription: {
          if (qgisProject) {
            if (qgisProject.metadata.abstract !== "") {
              return qgisProject.metadata.abstract;
            } else if (cloudProjectsModel.currentProject && cloudProjectsModel.currentProject.description !== "") {
              return cloudProjectsModel.currentProject.description;
            }
          }
          return "";
        }

        property string projectAuthor: {
          if (qgisProject) {
            if (qgisProject.metadata.author !== "" && qgisProject.metadata.author !== "Not available" && qgisProject.metadata.author !== "root") {
              return qgisProject.metadata.author;
            } else if (cloudProjectsModel.currentProject) {
              return cloudProjectsModel.currentProject.owner;
            }
          }
          return "";
        }

        Layout.alignment: Qt.AlignVCenter
        visible: projectDescription != "" || projectAuthor != ""
        width: 36
        height: 36
        padding: 0
        iconSource: QfTheme.getThemeVectorIcon('ic_info_white_24dp')
        iconColor: QfTheme.mainTextColor
        bgcolor: "transparent"
        onClicked: {
          informationPopup.header = qsTr("Project Information");
          informationPopup.title = projectTitleText.text;

          informationPopup.descriptionFormat = Text.MarkdownText;
          informationPopup.description = projectDescription;
          informationPopup.author = projectAuthor;

          informationPopup.open();
        }
      }
    }

    GroupBox {
      id: mapThemeContainer
      height: 0
      implicitHeight: 0
      Layout.maximumHeight: 0
      Layout.minimumHeight: 0
      Layout.preferredHeight: 0
      Layout.margins: 0
      visible: false
      objectName: "mapThemeContainer"
      Layout.fillWidth: true
      title: qsTr("Map QfTheme")
      leftPadding: 10
      rightPadding: 10
      topPadding: label.height + 5
      bottomPadding: 5

      property bool isLoading: false

      label: Label {
        x: parent.leftPadding
        height: 25
        width: parent.availableWidth
        leftPadding: mainWindow.sceneLeftMargin
        text: parent.title
        color: QfTheme.mainTextColor
        font: QfTheme.strongTipFont
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }

      background: Rectangle {
        color: "transparent"
      }

      RowLayout {
        width: parent.width

        QfComboBox {
          id: mapThemeComboBox
          Layout.fillWidth: true
          Layout.leftMargin: mainWindow.sceneLeftMargin
          font: QfTheme.defaultFont

          popup.font: QfTheme.defaultFont
          popup.topMargin: mainWindow.sceneTopMargin
          popup.bottomMargin: mainWindow.sceneTopMargin

          Connections {
            target: iface

            function onLoadProjectTriggered() {
              mapThemeContainer.isLoading = true;
            }

            function onLoadProjectEnded() {
              var themes = qgisProject.mapThemeCollection.mapThemes;
              mapThemeComboBox.model = themes;
              mapThemeComboBox.enabled = themes.length > 1;
              mapThemeComboBox.opacity = themes.length > 1 ? 1 : 0.25;
              mapThemeContainer.visible = themes.length > 1;
              flatLayerTree.updateCurrentMapTheme();
              mapThemeComboBox.currentIndex = flatLayerTree.mapTheme != '' ? mapThemeComboBox.find(flatLayerTree.mapTheme) : -1;
              mapThemeContainer.isLoading = false;
            }
          }

          Connections {
            target: flatLayerTree

            function onMapThemeChanged() {
              if (!mapThemeContainer.isLoading && mapThemeComboBox.currentText !== flatLayerTree.mapTheme) {
                mapThemeContainer.isLoading = true;
                mapThemeComboBox.currentIndex = flatLayerTree.mapTheme != '' ? mapThemeComboBox.find(flatLayerTree.mapTheme) : -1;
                mapThemeContainer.isLoading = false;
              }
            }
          }

          onCurrentTextChanged: {
            if (!mapThemeContainer.isLoading && qgisProject.mapThemeCollection.mapThemes.length > 1) {
              flatLayerTree.mapTheme = mapThemeComboBox.currentText;
            }
          }

          delegate: ItemDelegate {
            width: mapThemeComboBox.width
            height: 36
            text: modelData
            font.weight: mapThemeComboBox.currentIndex === index ? Font.DemiBold : Font.Normal
            font.pointSize: QfTheme.tipFont.pointSize
            highlighted: mapThemeComboBox.highlightedIndex == index
          }
        }
      }
    }

    GroupBox {
      id: legendContainer
      height: 0
      implicitHeight: 0
      Layout.maximumHeight: 0
      Layout.minimumHeight: 0
      Layout.preferredHeight: 0
      Layout.margins: 0
      visible: false
      objectName: "legendContainer"
      Layout.fillWidth: true
      Layout.fillHeight: true
      title: qsTr("QfLegend")
      leftPadding: 5
      rightPadding: 5
      topPadding: label.height + 5
      bottomPadding: 5

      background: Rectangle {
        color: "transparent"
      }

      label: Label {
        x: mapThemeContainer.leftPadding
        height: 25
        width: parent.availableWidth
        leftPadding: mainWindow.sceneLeftMargin
        text: parent.title
        color: QfTheme.mainTextColor
        font: QfTheme.strongTipFont
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        clip: true

        QfButton {
          id: toggleAllButton

          anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
            rightMargin: 10
          }
          visible: legend.model.hasCollapsibleItems

          text: legend.model.isCollapsed ? qsTr('Expand All') : qsTr('Collapse All')
          bgcolor: QfTheme.darkTheme ? QfTheme.mainBackgroundColorSemiOpaque : QfTheme.lightestGraySemiOpaque
          color: QfTheme.mainTextColor
          icon.source: legend.model.isCollapsed ? QfTheme.getThemeVectorIcon('ic_expand_all_24dp') : QfTheme.getThemeVectorIcon('ic_collapse_all_24dp')
          icon.width: 14
          icon.height: 14
          font.pointSize: QfTheme.tinyFont.pointSize - 2

          onClicked: {
            legend.model.setAllCollapsed(!legend.model.isCollapsed);
            projectInfo.saveLayerTreeState();
          }
        }
      }

      QfLegend {
        id: legend
        objectName: "legend"
        isVisible: dashBoard.position > 0
        anchors.fill: parent
        anchors.leftMargin: mainWindow.sceneLeftMargin + 5
        anchors.rightMargin: 5
        bottomMargin: bottomRow.height + 4
        informationPopup: informationPopup
      }
    }
  }

  Rectangle {
    id: bottomRow
    height: QfTheme.toolButtonSize + mainWindow.sceneBottomMargin
    width: parent.width
    anchors.bottom: parent.bottom
    color: QfTheme.darkTheme ? QfTheme.mainBackgroundColorSemiOpaque : QfTheme.lightestGraySemiOpaque

    Item {
      height: QfTheme.toolButtonSize
      anchors.bottom: parent.bottom
      anchors.bottomMargin: mainWindow.sceneBottomMargin
      anchors.left: parent.left
      anchors.leftMargin: mainWindow.sceneLeftMargin
      anchors.right: parent.right

      MenuItem {
        id: homeButton
        // WorkField: przelacznika trybu nie ma - warstwe do edycji wybiera sie
        // olowkiem w liscie warstw, a rysowanie zaczynaja kafle paska zapisu.
        width: parent.width
        height: QfTheme.toolButtonSize
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: QfTheme.menuItemLeftPadding

        font: QfTheme.defaultFont
        icon.source: QfTheme.getThemeVectorIcon("ic_home_black_24dp")

        text: qsTr("Home")

        onClicked: returnHome()
      }
    }
  }

  QfTemporalProperties {
    id: temporalProperties
    mapSettings: dashBoard.mapSettings
  }

  QfInformationPopup {
    id: informationPopup
  }
}
