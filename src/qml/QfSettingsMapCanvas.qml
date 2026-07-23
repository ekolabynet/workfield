import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

ColumnLayout {
  property var settingsPage
  property var settingsRegistry
  property var settingsModel
  property Component rowDelegate

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20

    columns: 2
    columnSpacing: 0
    rowSpacing: 5

    Label {
      text: qsTr('Map Canvas')
      font: Theme.strongFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.topMargin: 5
      Layout.columnSpan: 2
    }
  }

  ListView {
    Layout.fillWidth: true
    Layout.preferredHeight: contentHeight
    interactive: false

    model: settingsModel

    delegate: rowDelegate
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20

    columns: 2
    columnSpacing: 0
    rowSpacing: 5

    Label {
      Layout.fillWidth: true
      Layout.columnSpan: 2
      text: qsTr("Map canvas rendering quality:")
      font: Theme.defaultFont
      color: Theme.mainTextColor

      wrapMode: Text.WordWrap
    }

    QfComboBox {
      id: renderingQualityComboBox
      enabled: true
      Layout.fillWidth: true
      Layout.columnSpan: 2
      Layout.alignment: Qt.AlignVCenter
      font: Theme.defaultFont

      popup.font: Theme.defaultFont
      popup.topMargin: mainWindow.sceneTopMargin
      popup.bottomMargin: mainWindow.sceneTopMargin

      model: ListModel {
        ListElement {
          name: qsTr('Best quality')
          value: 1.0
        }
        ListElement {
          name: qsTr('Lower quality')
          value: 0.75
        }
        ListElement {
          name: qsTr('Lowest quality')
          value: 0.5
        }
      }
      textRole: "name"
      valueRole: "value"

      property bool initialized: false

      onCurrentValueChanged: {
        if (initialized) {
          quality = currentValue;
        }
      }

      Component.onCompleted: {
        currentIndex = indexOfValue(quality);
        initialized = true;
      }
    }

    Label {
      text: qsTr("A lower quality trades rendering precision in favor of lower memory usage and rendering time.")
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      textFormat: Qt.RichText
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.columnSpan: 2

      onLinkActivated: link => {
        Qt.openUrlExternally(link);
      }
    }
  }
}
