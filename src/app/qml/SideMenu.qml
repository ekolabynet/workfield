import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import Theme

/**
 * Pionowe menu boczne: ikona + podpis.
 */
Column {
  id: sideMenu

  signal actionTriggered(string action, point origin)

  property var t

  spacing: 0

  Repeater {
    model: ListModel {
      ListElement {
        actionId: "measurement"
        iconName: "ic_measurement_black_24dp"
      }
      ListElement {
        actionId: "view3d"
        iconName: "ic_3d_white_24dp"
      }
      ListElement {
        actionId: "print"
        iconName: "ic_print_black_24dp"
      }
      ListElement {
        actionId: "projectFolder"
        iconName: "ic_project_folder_black_24dp"
      }
      ListElement {
        actionId: "mainMenu"
        iconName: "ic_dot_menu_black_24dp"
      }
    }

    delegate: ItemDelegate {
      id: entry
      width: sideMenu.width
      height: 52

      required property string actionId
      required property string iconName

      contentItem: RowLayout {
        spacing: 16

        ColorImage {
          Layout.preferredWidth: 28
          Layout.preferredHeight: 28
          Layout.leftMargin: 8
          source: t.getThemeVectorIcon(entry.iconName)
          sourceSize.width: 28
          sourceSize.height: 28
          color: sideMenu.t.mainTextColor
        }

        Text {
          Layout.fillWidth: true
          text: {
            switch (entry.actionId) {
            case "measurement":
              return qsTr("Pomiar");
            case "view3d":
              return qsTr("Widok 3D");
            case "print":
              return qsTr("Wydruki");
            case "projectFolder":
              return qsTr("Folder projektu");
            case "mainMenu":
              return qsTr("Menu główne");
            }
            return "";
          }
          font: t.defaultFont
          color: t.mainTextColor
          elide: Text.ElideRight
        }
      }

      onClicked: {
        const p = entry.mapToItem(mainWindow.contentItem, entry.width, 0);
        sideMenu.actionTriggered(entry.actionId, p);
      }
    }
  }
}
