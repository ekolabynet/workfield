import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import Theme

ListView {
  id: settingsIndex

  signal categorySelected(string categoryId)

  property var t

  clip: true
  boundsBehavior: Flickable.StopAtBounds

  model: ListModel {
    ListElement {
      categoryId: "positioning"
      iconName: "ic_location_white_24dp"
    }
    ListElement {
      categoryId: "digitizing"
      iconName: "ic_add_vertex_white_24dp"
    }
    ListElement {
      categoryId: "mapCanvas"
      iconName: "ic_map_white_24dp"
    }
    ListElement {
      categoryId: "interface"
      iconName: "ic_3x3_grid_white_24dp"
    }
    ListElement {
      categoryId: "network"
      iconName: "ic_cloud_white_24dp"
    }
    ListElement {
      categoryId: "workfieldCloud"
      iconName: "ic_cloud_active_24dp"
    }
    ListElement {
      categoryId: "advanced"
      iconName: "ic_settings_white_24dp"
    }
    ListElement {
      categoryId: "variables"
      iconName: "ic_ellipsis_black_24dp"
    }
  }

  delegate: ItemDelegate {
    id: entry
    width: settingsIndex.width
    height: 48

    required property string categoryId
    required property string iconName

    // WorkField 22.08: jeden wiersz. Nazwa ma niesc znaczenie sama — opis
    // w drugim wierszu byl proteza slabej nazwy ("Interfejs: wyglad, czcionki").
    readonly property var labels: ({
        "positioning": qsTr("Pozycja"),
        "digitizing": qsTr("Rysowanie"),
        "mapCanvas": qsTr("Mapa"),
        "interface": qsTr("Wygląd"),
        "workfieldCloud": qsTr("Chmura"),
        "network": qsTr("Sieć"),
        "variables": qsTr("Zmienne projektu"),
        "advanced": qsTr("Zaawansowane")
      })

    contentItem: RowLayout {
      spacing: 16

      ColorImage {
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        Layout.leftMargin: 12
        source: t.getThemeVectorIcon(entry.iconName)
        sourceSize.width: 30
        sourceSize.height: 30
        color: t.mainTextColor
      }

      Text {
        Layout.fillWidth: true
        text: entry.labels[entry.categoryId]
        font: t.strongFont
        color: t.mainTextColor
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }
    }

    onClicked: settingsIndex.categorySelected(entry.categoryId)
  }
}
