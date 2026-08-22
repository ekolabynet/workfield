import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

Page {
  id: legendScreen

  property var t
  property alias layerTree: legendView.model
  property alias activeLayer: legendView.activeLayer
  property alias allowActiveLayerChange: legendView.allowActiveLayerChange
  property var mapSettings

  signal finished

  visible: false

  header: QfPageHeader {
    title: qsTr("Warstwy")
    showBackButton: true
    showApplyButton: false
    showCancelButton: false
    topMargin: mainWindow.sceneTopMargin
    onFinished: legendScreen.finished()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 4
    anchors.bottomMargin: 4 + mainWindow.sceneBottomMargin
    spacing: 4

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: 6
      Layout.rightMargin: 6
      spacing: 8
      visible: qgisProject && qgisProject.mapThemeCollection && qgisProject.mapThemeCollection.mapThemes.length > 1

      Text {
        text: qsTr("Motyw mapy")
        font: t.defaultFont
        color: t.mainTextColor
      }

      ComboBox {
        id: themeCombo

        Layout.fillWidth: true
        font: t.defaultFont
        model: qgisProject && qgisProject.mapThemeCollection ? qgisProject.mapThemeCollection.mapThemes : []
        onActivated: flatLayerTree.mapTheme = currentText
      }
    }

    QfButton {
      Layout.fillWidth: true
      Layout.leftMargin: 6
      Layout.rightMargin: 6
      visible: legendView.model && legendView.model.hasCollapsibleItems
      text: legendView.model && legendView.model.isCollapsed ? qsTr("Rozwiń wszystko") : qsTr("Zwiń wszystko")
      font.pointSize: t.tinyFont.pointSize
      bgcolor: t.controlBackgroundAlternateColor
      color: t.mainTextColor

      onClicked: {
        legendView.model.setAllCollapsed(!legendView.model.isCollapsed);
        projectInfo.saveLayerTreeState();
      }
    }

    Legend {
      id: legendView

      Layout.fillWidth: true
      Layout.fillHeight: true
      isVisible: legendScreen.visible
    }
  }

  Keys.onReleased: event => {
    if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
      event.accepted = true;
      legendScreen.finished();
    }
  }
}
