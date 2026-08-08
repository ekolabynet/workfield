import QtQuick
import QtQuick.Effects
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
 * aktywna warstwa, RTCM) — zastępuje dotykową belkę QFielda, która na
 * komputerze dublowała te same informacje i zabierała wysokość ekranu.
 *
 * Pasek narzędzi jest PIONOWY, przy lewej krawędzi mapy (jak w QGIS czy
 * Inkscape) — nie zabiera wysokości, zostawia miejsce na przyszłe panele
 * boczne. Kończy się wysoko nad przyciskiem lokalizacji.
 *
 * Menu rysuje QtQuick.Controls: natywne menu systemowe wymaga demona
 * globalnego menu, którego w Plasmie zwykle nie ma.
 */
ToolBar {
  id: chrom

  property var akcje: wfAkcje
  //! ekran startowy: pasek pionowy chowa się, menu zostaje
  property bool ekranStartowy: false

  //! ikony na pasku: codzienne czasowniki, reszta zostaje w menu
  readonly property var naPasku: ["otworz", "otworz_magazyn", "wyslij", "odbierz", "warstwy", "galeria"]

  height: 30
  padding: 0

  // tło jawnym prostokątem — bez zależności od stylu Material
  background: Rectangle {
    color: Theme.mainColor
  }

  function znajdz(idAkcji) {
    if (!akcje)
      return null;
    for (let i = 0; i < akcje.lista.length; i++) {
      if (akcje.lista[i].id === idAkcji)
        return akcje.lista[i];
    }
    return null;
  }

  // ── belka: menu po lewej, stan po prawej ────────────────────────
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

  // ── pionowy pasek narzędzi przy lewej krawędzi mapy ─────────────
  Rectangle {
    id: pasekPionowy

    parent: mainWindow.contentItem
    x: 6
    y: 8
    width: 32
    height: kolumnaIkon.implicitHeight + 8
    radius: 6
    color: Theme.mainColor
    opacity: 0.92
    z: 900
    visible: chrom.akcje !== null && !chrom.ekranStartowy

    ColumnLayout {
      id: kolumnaIkon

      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 4
      spacing: 2

      Repeater {
        model: chrom.naPasku

        delegate: ToolButton {
          required property string modelData

          readonly property var akcja: chrom.znajdz(modelData)

          implicitWidth: 26
          implicitHeight: 26
          enabled: akcja && chrom.akcje ? chrom.akcje.dostepna(akcja) : false
          opacity: enabled ? 1.0 : 0.35
          ToolTip.visible: hovered && akcja !== null
          ToolTip.text: akcja ? akcja.nazwa : ""
          ToolTip.delay: 400

          contentItem: Item {
            // ikony Breeze to ciemna kreska — na zielonym tle rozjaśniamy
            Image {
              id: rysunek
              anchors.centerIn: parent
              width: 18
              height: 18
              fillMode: Image.PreserveAspectFit
              sourceSize.width: 18
              sourceSize.height: 18
              source: akcja ? Theme.getThemeVectorIcon(akcja.ikona) : ""
              visible: false
            }

            MultiEffect {
              anchors.fill: rysunek
              source: rysunek
              colorization: 1.0
              colorizationColor: "white"
              brightness: 0.35
            }
          }

          background: Rectangle {
            color: "white"
            opacity: parent.hovered ? 0.18 : 0
            radius: 4
          }

          onClicked: {
            if (akcja)
              akcja.wykonaj();
          }
        }
      }
    }
  }
}
