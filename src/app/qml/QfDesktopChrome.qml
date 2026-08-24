import QtQuick
import Qt5Compat.GraphicalEffects
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
    color: Theme.mainColor
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
            source: Theme.getThemeVectorIcon(zakladkaBelki.modelData.ikona)
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
            font: Theme.tipFont
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
        font: Theme.strongTipFont
        color: "white"
      }

      MouseArea {
        id: obszarWiecej
        anchors.fill: parent
        hoverEnabled: true
        onClicked: menuWiecej.opened ? menuWiecej.close() : menuWiecej.open()
      }

      Menu {
        id: menuWiecej
        y: parent.height

        Repeater {
          model: chrom.pozycjeWiecej

          delegate: MenuItem {
            required property var modelData

            text: modelData.naglowek ? "— " + modelData.nazwa + " —" : modelData.akcja.nazwa
            enabled: modelData.naglowek ? false
                                        : (chrom.akcje ? chrom.akcje.dostepna(modelData.akcja) : false)
            icon.source: modelData.naglowek ? "" : Theme.getThemeVectorIcon(modelData.akcja.ikona)
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

    // WorkField 23.08.2026 — zakladki PRAWEJ szuflady, po prawej stronie
    // belki. Bliznaczo do zakladek lewej szuflady po lewej: ta sama forma,
    // to samo podswietlenie. Belka staje sie mapa obu szuflad naraz.
    Repeater {
      model: [
        {
          "nazwa": qsTr("Narzędzia"),
          "ikona": "wfg_sprzet",
          "zakladka": 0
        },
        {
          "nazwa": qsTr("Algorytmy"),
          "ikona": "wfg_zbuduj",
          "zakladka": 1
        },
        {
          "nazwa": qsTr("Ustawienia"),
          "ikona": "wfg_ustawienia",
          "zakladka": 2
        }
      ]

      delegate: Item {
        id: zakladkaPrawa

        required property var modelData

        readonly property bool aktywna: dataDrawer.opened && dataDrawer.zakladkaAktywna === modelData.zakladka

        Layout.preferredWidth: trescPrawej.implicitWidth + 22
        Layout.fillHeight: true

        Rectangle {
          anchors.fill: parent
          color: "white"
          opacity: zakladkaPrawa.aktywna ? 0.22 : (obszarPrawej.containsMouse ? 0.12 : 0)
        }

        RowLayout {
          id: trescPrawej
          anchors.centerIn: parent
          spacing: 6

          Image {
            id: ikonaPrawej
            Layout.preferredWidth: 15
            Layout.preferredHeight: 15
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 15
            sourceSize.height: 15
            source: Theme.getThemeVectorIcon(zakladkaPrawa.modelData.ikona)
            visible: false
          }
          ColorOverlay {
            Layout.preferredWidth: 15
            Layout.preferredHeight: 15
            source: ikonaPrawej
            visible: ikonaPrawej.status === Image.Ready
            color: "white"
          }
          Text {
            text: zakladkaPrawa.modelData.nazwa
            font: Theme.tipFont
            color: "white"
          }
        }

        MouseArea {
          id: obszarPrawej
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            if (zakladkaPrawa.aktywna)
              dataDrawer.close();
            else
              dataDrawer.otworzZakladke(zakladkaPrawa.modelData.zakladka);
          }
        }
      }
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

  // Tytul projektu NA SRODKU belki — poza RowLayoutem, bo srodek belki to
  // srodek belki, a nie miejsce, ktore zostalo po zakladkach. Tekst nie lapie
  // klikniec, wiec nie zaslania niczego funkcjonalnie; przy waskim oknie
  // chowa sie sam, zamiast wchodzic pod zakladki.
  Text {
    anchors.centerIn: parent
    width: Math.min(implicitWidth, chrom.width - 720)
    visible: width > 60
    horizontalAlignment: Text.AlignHCenter
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
    font: Theme.tipFont
    color: "white"
    opacity: 0.85
    elide: Text.ElideMiddle
  }
}
