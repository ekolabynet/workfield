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
        actionId: "legend"
        iconName: "ic_baseline-list_white_24dp"
      }
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
        actionId: "newLayer"
        iconName: "ic_add_white_24dp"
      }
      ListElement {
        actionId: "projectFolder"
        iconName: "ic_project_folder_black_24dp"
      }
      ListElement {
        actionId: "bookmarks"
        iconName: "ic_bookmark_black_24dp"
      }
      ListElement {
        actionId: "plugins"
        iconName: "ic_dot_menu_black_24dp"
      }
      ListElement {
        actionId: "settings"
        iconName: "ic_settings_white_24dp"
      }
      ListElement {
        actionId: "messageLog"
        iconName: "ic_alert_black_24dp"
      }
      ListElement {
        actionId: "lockScreen"
        iconName: "ic_lock_black_24dp"
      }
      ListElement {
        actionId: "about"
        iconName: "ic_book_white_24dp"
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
            case "legend":
              return qsTr("Warstwy");
            case "measurement":
              return qsTr("Pomiar");
            case "view3d":
              return qsTr("Widok 3D");
            case "print":
              return qsTr("Wydruki");
            case "newLayer":
              return qsTr("Nowa warstwa");
            case "projectFolder":
              return qsTr("Folder projektu");
            case "bookmarks":
              return qsTr("Zakładki");
            case "plugins":
              return qsTr("Wtyczki");
            case "settings":
              return qsTr("Ustawienia");
            case "messageLog":
              return qsTr("Dziennik");
            case "lockScreen":
              return qsTr("Zablokuj ekran");
            case "about":
              return qsTr("O programie");
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
