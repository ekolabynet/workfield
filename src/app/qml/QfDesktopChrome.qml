import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * WorkField Studio — CHROM DESKTOPOWY (nagłówek okna na komputerze).
 *
 * Belka: nazwy grup menu po lewej, stan pracy po prawej (nazwa projektu,
 * aktywna warstwa, RTCM). Menu rysuje QtQuick.Controls — natywne menu
 * systemowe wymaga demona globalnego menu, którego w Plasmie zwykle nie ma.
 *
 * Pionowego paska ikon już nie ma: jego rolę przejął poziomy przełącznik
 * widoków w dokowanym lewym panelu (QfMainDrawer) oraz pasek menu.
 */
ToolBar {
  id: chrom

  property var akcje: wfAkcje
  //! zachowane dla zgodności wywołania; chrom nie zmienia się na starcie
  property bool ekranStartowy: false

  height: 30
  padding: 0

  background: Rectangle {
    color: Theme.mainColor
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 4
    anchors.rightMargin: 10
    spacing: 0

    Repeater {
      model: chrom.akcje ? chrom.akcje.grupy : []

      delegate: Item {
        required property var modelData

        Layout.preferredWidth: etykieta.implicitWidth + 20
        Layout.fillHeight: true

        Rectangle {
          anchors.fill: parent
          color: "white"
          opacity: obszar.containsMouse || menuGrupy.opened ? 0.15 : 0
        }

        Text {
          id: etykieta
          anchors.centerIn: parent
          text: modelData.nazwa
          font: Theme.tipFont
          color: "white"
        }

        MouseArea {
          id: obszar
          anchors.fill: parent
          hoverEnabled: true
          onClicked: menuGrupy.opened ? menuGrupy.close() : menuGrupy.open()
        }

        Menu {
          id: menuGrupy
          y: parent.height

          Repeater {
            model: chrom.akcje ? chrom.akcje.wGrupie(modelData.id) : []

            delegate: MenuItem {
              required property var modelData

              text: modelData.nazwa
              enabled: chrom.akcje ? chrom.akcje.dostepna(modelData) : false
              icon.source: Theme.getThemeVectorIcon(modelData.ikona)
              icon.width: 18
              icon.height: 18
              onTriggered: modelData.wykonaj()
            }
          }
        }
      }
    }

    Item {
      Layout.fillWidth: true
    }

    Text {
      text: {
        const czesci = [];
        if (mainWindow.projectTitle !== "")
          czesci.push(mainWindow.projectTitle);
        if (dashBoard.activeLayer)
          czesci.push(dashBoard.activeLayer.name);
        else
          czesci.push(qsTr("brak aktywnej warstwy"));
        return czesci.join("  ·  ");
      }
      font: Theme.tinyFont
      color: "white"
      opacity: 0.8
      elide: Text.ElideMiddle
      Layout.maximumWidth: 420
    }

    Text {
      Layout.leftMargin: 12
      visible: positionSource.active && positionSource.enableNtrip
      text: "RTCM"
      font: Theme.tinyFont
      color: "white"
      opacity: 0.8
    }
  }
}
