import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import QfTheme

ListView {
  id: settingsIndex

  signal categorySelected(string categoryId)

  property var t

  clip: true
  boundsBehavior: Flickable.StopAtBounds

  model: ListModel {
    ListElement {
      categoryId: "mapCanvas"
      iconName: "ic_map_white_24dp"
    }
    ListElement {
      categoryId: "digitizing"
      iconName: "ic_add_vertex_white_24dp"
    }
    ListElement {
      categoryId: "interface"
      iconName: "ic_3x3_grid_white_24dp"
    }
    ListElement {
      categoryId: "positioning"
      iconName: "ic_location_white_24dp"
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
    height: 68

    required property string categoryId
    required property string iconName

    readonly property var labels: ({
        "mapCanvas": [qsTr("Obszar mapy"), qsTr("Podziałka, zakładki, jakość rysowania")],
        "digitizing": [qsTr("Digitalizacja i edycja"), qsTr("Wierzchołki, przyciąganie, zapis")],
        "interface": [qsTr("Interfejs"), qsTr("Wygląd, czcionki, język, wtyczki")],
        "positioning": [qsTr("Lokalizacja"), qsTr("GNSS, dokładność, NTRIP")],
        "network": [qsTr("Sieć"), qsTr("Proxy i uwierzytelnianie")],
        "workfieldCloud": [qsTr("Chmura WorkField"), qsTr("Konto zespołowe, zwroty projektów")],
        "advanced": [qsTr("Zaawansowane"), qsTr("Renderowanie podglądu, autozapis")],
        "variables": [qsTr("Zmienne"), qsTr("Zmienne wyrażeń projektu")]
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

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
          Layout.fillWidth: true
          text: entry.labels[entry.categoryId][0]
          font: t.strongFont
          color: t.mainTextColor
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: entry.labels[entry.categoryId][1]
          font: t.tipFont
          color: t.secondaryTextColor
          elide: Text.ElideRight
        }
      }
    }

    onClicked: settingsIndex.categorySelected(entry.categoryId)
  }
}
