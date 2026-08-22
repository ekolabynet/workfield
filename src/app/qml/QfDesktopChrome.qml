import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import QfTheme

/**
 * \ingroup qml
 *
 * WorkField Studio — CHROM DESKTOPOWY (nagłówek okna na komputerze).
 *
 * Belka: nazwy grup menu po lewej, stan pracy po prawej (nazwa projektu,
 * aktywna warstwa, RTCM). QfMenu rysuje QtQuick.Controls — natywne menu
 * systemowe wymaga demona globalnego menu, którego w Plasmie zwykle nie ma.
 *
 * Pionowego paska ikon już nie ma: jego rolę przejął poziomy przełącznik
 * widoków w dokowanym lewym panelu (QfMainDrawer) oraz pasek menu.
 */
ToolBar {
  id: chrom

  property var akcje: wfAkcje

  //! WorkField 18.08.2026: płaska lista wszystkich czynności z nagłówkami grup,
  //! do menu „⋯". Trzymamy je dostępne, dopóki nie mają miejsca w szufladzie.
  readonly property var pozycjeWiecej: {
    const wynik = [];
    const grupy = akcje ? akcje.grupy : [];
    for (const g of grupy) {
      const lista = akcje.wGrupie(g.id);
      if (!lista || lista.length === 0)
        continue;
      wynik.push({ "naglowek": true, "nazwa": g.nazwa, "akcja": null });
      for (const a of lista)
        wynik.push({ "naglowek": false, "nazwa": "", "akcja": a });
    }
    return wynik;
  }

  //! zachowane dla zgodności wywołania; chrom nie zmienia się na starcie
  property bool ekranStartowy: false

  height: 30
  padding: 0

  background: Rectangle {
    color: QfTheme.mainColor
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 4
    anchors.rightMargin: 10
    spacing: 0

    // WorkField 18.08.2026: bliźniak przełącznika widoków z lewej szuflady —
    // te same cztery zakładki, ikona + etykieta, podświetlenie aktywnej.
    Repeater {
      model: [{ "nazwa": qsTr("Zlecenia"), "ikona": "wfg_magazyn", "sekcja": 0 }, { "nazwa": qsTr("Projekt"), "ikona": "wfg_nowe", "sekcja": 1 }, { "nazwa": qsTr("Warstwy"), "ikona": "wfg_warstwy", "sekcja": 2 }, { "nazwa": qsTr("Stylizacja"), "ikona": "wfg_stylizacja", "sekcja": 3 }]

      delegate: Item {
        id: zakladkaBelki

        required property var modelData

        readonly property bool aktywna: dashBoard.sekcjaAktywna === modelData.sekcja

        Layout.preferredWidth: trescZakladki.implicitWidth + 22
        Layout.fillHeight: true

        Rectangle {
          anchors.fill: parent
          color: "white"
          opacity: zakladkaBelki.aktywna ? 0.22 : (obszarZakladki.containsMouse ? 0.12 : 0)
        }

        RowLayout {
          id: trescZakladki
          anchors.centerIn: parent
          spacing: 6

          Image {
            id: ikonaZakladki
            Layout.preferredWidth: 15
            Layout.preferredHeight: 15
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 15
            sourceSize.height: 15
            source: QfTheme.getThemeVectorIcon(zakladkaBelki.modelData.ikona)
            visible: false
          }
          ColorOverlay {
            // Belka ma ciemnozielone tło, ikony Breeze są ciemne — bez
            // przemalowania na biało byłyby nieczytelne.
            Layout.preferredWidth: 15
            Layout.preferredHeight: 15
            source: ikonaZakladki
            visible: ikonaZakladki.status === Image.Ready
            color: "white"
          }
          Text {
            text: zakladkaBelki.modelData.nazwa
            font: QfTheme.tipFont
            color: "white"
          }
        }

        MouseArea {
          id: obszarZakladki
          anchors.fill: parent
          hoverEnabled: true
          onClicked: dashBoard.otworzSekcje(zakladkaBelki.modelData.sekcja)
        }
      }
    }

    // WorkField 18.08.2026: czynności z grup Zarządzanie/Pomoc nie mają
    // (jeszcze) miejsca w szufladzie — Sprzęt, Kto co robił, Ustawienia
    // terenowe i aplikacji byłyby bez tego menu NIEDOSTĘPNE. Chowamy je,
    // nie kasujemy. Do usunięcia dopiero, gdy trafią do szuflady.
    Item {
      Layout.preferredWidth: 34
      Layout.fillHeight: true

      Rectangle {
        anchors.fill: parent
        color: "white"
        opacity: obszarWiecej.containsMouse || menuWiecej.opened ? 0.12 : 0
      }

      Text {
        anchors.centerIn: parent
        text: "\u22ef"
        font: QfTheme.strongTipFont
        color: "white"
      }

      MouseArea {
        id: obszarWiecej
        anchors.fill: parent
        hoverEnabled: true
        onClicked: menuWiecej.opened ? menuWiecej.close() : menuWiecej.open()
      }

      QfMenu {
        id: menuWiecej
        y: parent.height

        Repeater {
          model: chrom.pozycjeWiecej

          delegate: MenuItem {
            required property var modelData

            text: modelData.naglowek ? "— " + modelData.nazwa + " —" : modelData.akcja.nazwa
            enabled: modelData.naglowek ? false
                                        : (chrom.akcje ? chrom.akcje.dostepna(modelData.akcja) : false)
            icon.source: modelData.naglowek ? "" : QfTheme.getThemeVectorIcon(modelData.akcja.ikona)
            icon.width: 18
            icon.height: 18
            onTriggered: {
              if (!modelData.naglowek)
                modelData.akcja.wykonaj();
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
      font: QfTheme.tinyFont
      color: "white"
      opacity: 0.8
      elide: Text.ElideMiddle
      Layout.maximumWidth: 420
    }

    Text {
      Layout.leftMargin: 12
      visible: positionSource.active && positionSource.enableNtrip
      text: "RTCM"
      font: QfTheme.tinyFont
      color: "white"
      opacity: 0.8
    }
  }
}
