import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

Column {
  property var page
  property var registry
  property var settingsModel
  property Component listItem

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20

    columns: 2
    columnSpacing: 0
    rowSpacing: 5

    Label {
      text: qsTr('Advanced')
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
    Layout.preferredHeight: childrenRect.height
    interactive: false

    model: settingsModel

    delegate: listItem
  }
}
