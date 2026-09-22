import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * WorkField 22.09.2026 — „Jak zacząć?"
 *
 * Ekran pierwszego kontaktu. Pokazuje się RAZ, po instalacji, i jest
 * spisem CZYNNOŚCI, nie opisem programu: każda pozycja otwiera to miejsce,
 * o którym mówi. Wiersz, który tylko opowiada, nie ma tu czego szukać —
 * od opowiadania jest dokumentacja.
 *
 * Nie zna żadnych identyfikatorów z QgisMobileapp.qml. Miejsca, które ma
 * otwierać, dostaje we właściwościach — tak jak QfSekcjaModulow dostaje
 * `szuflada: dataDrawer`. Dzięki temu da się go obejrzeć osobno i nie
 * wywraca się, gdy któregoś okna w danym wydaniu nie ma.
 */
Popup {
  id: jakZaczac

  //! Lewa szuflada (dashBoard): otworzSekcje(0 Zlecenia, 1 Projekt, 2 Warstwy, 3 Stylizacja)
  property var szufladaLewa: null
  //! Prawa szuflada (dataDrawer): otworzZakladke(0 Moduły, 1 Narzędzia, 2 Algorytmy, 3 Ustawienia)
  property var szufladaPrawa: null
  //! Okna, każde z open(): menedżer wtyczek, okno podkładów i danych wysokościowych
  property var oknoWtyczek: null
  property var podklady: null
  //! Napis wersji do stopki — tym numerem posługuje się tester w zgłoszeniu
  property string wersja: ""

  //! Ustawienie „pokazuj przy starcie"; puste = nie zapisuj (podgląd osobny)
  property string kluczUstawienia: "WorkField/jakZaczacPokazuj"

  signal poproszonoOProjektPrzykladowy

  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape
  padding: 0

  readonly property color barwaTla: Theme.mainBackgroundColor !== undefined ? Theme.mainBackgroundColor : "#ffffff"
  readonly property color barwaTekstu: Theme.mainTextColor !== undefined ? Theme.mainTextColor : "#1f1f1f"
  readonly property color barwaSzara: Theme.secondaryTextColor !== undefined ? Theme.secondaryTextColor : "#6b6b6b"
  readonly property color barwaGlowna: Theme.mainColor !== undefined ? Theme.mainColor : "#80cc28"

  parent: Overlay.overlay
  x: Math.round((parent.width - width) / 2)
  y: Math.round((parent.height - height) / 2)
  width: Math.min(parent.width - 24, 560)
  height: Math.min(parent.height - 24, 720)

  background: Rectangle {
    color: jakZaczac.barwaTla
    radius: 8
    border.width: 1
    border.color: Qt.rgba(jakZaczac.barwaSzara.r, jakZaczac.barwaSzara.g, jakZaczac.barwaSzara.b, 0.25)
  }

  /**
   * Czynność wiersza: najpierw zamknij ekran, POTEM otwórz miejsce.
   * Odwrotna kolejność zostawia modalną nakładkę nad szufladą, którą
   * własnie otworzyliśmy - widać szufladę i nie da sie jej dotknąć.
   */
  function wykonaj(co) {
    jakZaczac.close();
    Qt.callLater(co);
  }

  function otworzSekcje(numer) {
    wykonaj(function () {
      if (szufladaLewa && typeof szufladaLewa.otworzSekcje === "function")
        szufladaLewa.otworzSekcje(numer);
      else
        console.warn("WFG JakZaczac: brak lewej szuflady dla sekcji", numer);
    });
  }

  function otworzZakladke(numer) {
    wykonaj(function () {
      if (szufladaPrawa && typeof szufladaPrawa.otworzZakladke === "function")
        szufladaPrawa.otworzZakladke(numer);
      else
        console.warn("WFG JakZaczac: brak prawej szuflady dla zakładki", numer);
    });
  }

  function otworzOkno(okno, nazwa) {
    wykonaj(function () {
      if (okno && typeof okno.open === "function")
        okno.open();
      else
        console.warn("WFG JakZaczac: nie ma okna", nazwa);
    });
  }

  //! Wiersz, który coś robi. Bez ikon: nazwa ikony, której nie ma w motywie,
  //! daje pusty kwadrat, a zgadywanie nazw kosztowało nas już jeden przycisk.
  component Czynnosc: ItemDelegate {
    id: wiersz
    property string opis: ""
    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(48, tresc.implicitHeight + 16)
    contentItem: RowLayout {
      spacing: 8
      ColumnLayout {
        id: tresc
        Layout.fillWidth: true
        spacing: 1
        Text {
          Layout.fillWidth: true
          text: wiersz.text
          color: jakZaczac.barwaTekstu
          font: Theme.defaultFont !== undefined ? Theme.defaultFont : Qt.font({
              "pointSize": 12
            })
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          visible: wiersz.opis !== ""
          text: wiersz.opis
          color: jakZaczac.barwaSzara
          font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) - 2
          wrapMode: Text.WordWrap
        }
      }
      Text {
        text: "›"
        color: jakZaczac.barwaGlowna
        font.pointSize: 18
        font.bold: true
      }
    }
  }

  component Naglowek: Text {
    Layout.fillWidth: true
    Layout.topMargin: 12
    Layout.bottomMargin: 2
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    color: jakZaczac.barwaSzara
    font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) - 1
    font.bold: true
  }

  contentItem: ColumnLayout {
    spacing: 0

    // --- tytuł ---------------------------------------------------------
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: tytul.implicitHeight + 24
      color: Qt.rgba(jakZaczac.barwaGlowna.r, jakZaczac.barwaGlowna.g, jakZaczac.barwaGlowna.b, 0.12)
      ColumnLayout {
        id: tytul
        anchors.fill: parent
        anchors.margins: 12
        spacing: 2
        Text {
          Layout.fillWidth: true
          text: qsTr("Witaj w WorkFieldzie")
          color: jakZaczac.barwaTekstu
          font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) + 4
          font.bold: true
        }
        Text {
          Layout.fillWidth: true
          text: qsTr("Mapa, formularze i zdjęcia w terenie — dane wracają do biura w jednym pliku.")
          color: jakZaczac.barwaSzara
          font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) - 1
          wrapMode: Text.WordWrap
        }
      }
    }

    // --- lista czynności -------------------------------------------------
    ScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentWidth: availableWidth

      ColumnLayout {
        width: parent.width
        spacing: 0

        Naglowek {
          text: qsTr("ZACZNIJ OD JEDNEGO Z TRZECH")
        }
        Czynnosc {
          text: qsTr("Otwórz projekt")
          opis: qsTr("Z karty pamięci albo z katalogu zleceń")
          onClicked: jakZaczac.otworzSekcje(1)
        }
        Czynnosc {
          text: qsTr("Złóż projekt z modułu")
          opis: qsTr("CAD, Inwentaryzacja drzew — warstwy i style powstaną same")
          onClicked: jakZaczac.otworzZakladke(0)
        }
        Czynnosc {
          text: qsTr("Zlecenia i Magazyn")
          opis: qsTr("Praca podzielona na zlecenia, kopie i zwroty z terenu")
          onClicked: jakZaczac.otworzSekcje(0)
        }

        Naglowek {
          text: qsTr("GDZIE CO JEST")
        }
        Czynnosc {
          text: qsTr("Warstwy")
          opis: qsTr("Lewa szuflada — dodawanie danych, kolejność, widoczność")
          onClicked: jakZaczac.otworzSekcje(2)
        }
        Czynnosc {
          text: qsTr("Stylizacja")
          opis: qsTr("Lewa szuflada — kolory, etykiety, symbole")
          onClicked: jakZaczac.otworzSekcje(3)
        }
        Czynnosc {
          text: qsTr("Moduły")
          opis: qsTr("Prawa szuflada, pierwsza zakładka — narzędzia dziedzinowe")
          onClicked: jakZaczac.otworzZakladke(0)
        }
        Czynnosc {
          text: qsTr("Narzędzia i Algorytmy")
          opis: qsTr("Prawa szuflada — pomiary, przeliczenia, operacje na warstwach")
          onClicked: jakZaczac.otworzZakladke(1)
        }
        Czynnosc {
          text: qsTr("Podkłady i dane wysokościowe")
          opis: qsTr("Ortofotomapa i NMT na obszar pracy, do użycia bez zasięgu")
          visible: jakZaczac.podklady !== null
          onClicked: jakZaczac.otworzOkno(jakZaczac.podklady, "podkłady")
        }
        Czynnosc {
          text: qsTr("Wtyczki")
          opis: qsTr("Instalacja z adresu, lista zainstalowanych")
          visible: jakZaczac.oknoWtyczek !== null
          onClicked: jakZaczac.otworzOkno(jakZaczac.oknoWtyczek, "wtyczki")
        }

        Naglowek {
          text: qsTr("GDY COŚ PÓJDZIE NIE TAK")
        }
        Text {
          Layout.fillWidth: true
          Layout.margins: 12
          Layout.topMargin: 4
          text: qsTr("Numer wersji jest w nagłówku lewej szuflady — podaj go w zgłoszeniu. Tam też otwiera się „Co nowego” z listą zmian.")
          color: jakZaczac.barwaSzara
          font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) - 1
          wrapMode: Text.WordWrap
        }

        Item {
          Layout.preferredHeight: 8
        }
      }
    }

    // --- stopka -----------------------------------------------------------
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Qt.rgba(jakZaczac.barwaSzara.r, jakZaczac.barwaSzara.g, jakZaczac.barwaSzara.b, 0.2)
    }
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: stopka.implicitHeight + 16
      color: "transparent"
      RowLayout {
        id: stopka
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8
        CheckBox {
          id: pokazujZawsze
          text: qsTr("Pokazuj przy starcie")
          font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) - 1
          checked: jakZaczac.kluczUstawienia !== "" && typeof settings !== "undefined" ? settings.valueBool(jakZaczac.kluczUstawienia, false) : false
          onToggled: {
            if (jakZaczac.kluczUstawienia !== "" && typeof settings !== "undefined")
              settings.setValue(jakZaczac.kluczUstawienia, checked);
          }
        }
        Item {
          Layout.fillWidth: true
        }
        Text {
          visible: jakZaczac.wersja !== ""
          text: jakZaczac.wersja
          color: jakZaczac.barwaSzara
          font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) - 2
        }
        Button {
          text: qsTr("Zamknij")
          onClicked: jakZaczac.close()
        }
      }
    }
  }
}
