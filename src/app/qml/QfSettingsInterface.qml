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

  signal openLocatorSettings()
  signal openPluginManager()

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20
    Layout.bottomMargin: 0

    columns: 2
    columnSpacing: 0
    rowSpacing: 0

    Label {
      text: qsTr('User Interface')
      font: Theme.strongFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.topMargin: 5
      Layout.columnSpan: 2
    }

    Label {
      text: qsTr("Customize search bar")
      font: Theme.defaultFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.topMargin: 5

      MouseArea {
        anchors.fill: parent
        onClicked: showSearchBarSettings.clicked()
      }
    }

    QfToolButton {
      id: showSearchBarSettings
      Layout.preferredWidth: Theme.toolButtonSize
      Layout.preferredHeight: Theme.toolButtonSize
      Layout.alignment: Qt.AlignVCenter
      clip: true

      iconSource: Theme.getThemeVectorIcon("ic_ellipsis_black_24dp")
      iconColor: Theme.mainColor
      bgcolor: "transparent"

      onClicked: {
        openLocatorSettings();
        
      }
    }

    Label {
      text: qsTr("Manage plugins")
      font: Theme.defaultFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true

      MouseArea {
        anchors.fill: parent
        onClicked: showPluginManagerSettings.clicked()
      }
    }

    QfToolButton {
      id: showPluginManagerSettings
      Layout.preferredWidth: Theme.toolButtonSize
      Layout.preferredHeight: Theme.toolButtonSize
      Layout.alignment: Qt.AlignVCenter
      clip: true

      iconSource: Theme.getThemeVectorIcon("ic_ellipsis_black_24dp")
      iconColor: Theme.mainColor
      bgcolor: "transparent"

      onClicked: {
        openPluginManager();
      }
    }
  }

  ListView {
    Layout.fillWidth: true
    Layout.preferredHeight: contentHeight
    interactive: false

    model: settingsModel

    delegate: rowDelegate
  }
}
