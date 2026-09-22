import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Theme

/**
 * WorkFieldGIS 22.09.2026 — „Jak zacząć?" (wersja 3)
 *
 * Ekran pierwszego kontaktu. Pokazuje się RAZ, po instalacji, i wraca
 * z nagłówka lewej szuflady albo z menu („Aplikacja → Jak zacząć?").
 *
 * Trzon to spis CZYNNOŚCI: każda pozycja otwiera to miejsce, o którym mówi.
 * Od wersji 3 przed spisem stoją dwie rzeczy, o które prosił autor:
 *   - OSTRZEŻENIE o wczesnym etapie rozwoju — pierwsze, co widać, bo
 *     tester ma je zobaczyć zanim zacznie na tym pracować, a nie po fakcie;
 *   - „CO TO JEST” — czym jest projekt i czym jest zlecenie. Bez tego
 *     dwa najważniejsze słowa w programie znaczą dla nowego tyle,
 *     ile zgadnie z kontekstu.
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
  //! Okna, każde z open() — wiersz ma otwierać OKNO POLECENIA, nie szufladę,
  //! w której polecenie się chowa (uwaga z telefonu, 22.09).
  property var oknoWtyczek: null
  property var podklady: null
  property var daneWysokosciowe: null
  property var importCAD: null
  property var georeferencja: null
  //! Ekran powitalny z listą projektów — pokazuje się przez `visible`, nie open()
  property var ekranPowitalny: null
  //! Napis wersji do stopki — tym numerem posługuje się tester w zgłoszeniu
  property string wersja: ""
  //! Wersja silnika QGIS do akapitu o pochodzeniu — z `Qfield.qgisVersion`
  property string wersjaQGIS: ""

  //! Ustawienie „pokazuj przy starcie"; puste = nie zapisuj (podgląd osobny)
  property string kluczUstawienia: "WorkField/jakZaczacPokazuj"

  signal poproszonoOProjektPrzykladowy

  /**
   * Numer wersji do stopki. NIE wiazanie `wersja: appVersionStr` w miejscu
   * uzycia: ta nazwa jest wlasciwoscia kontekstu i bywa jeszcze nieustawiona,
   * gdy komponent sie buduje - QfMainDrawer przerabial to 17.09 i skonczyl
   * na tym samym `Component.onCompleted` z osłoną.
   */
  Component.onCompleted: {
    if (jakZaczac.wersja === "") {
      try {
        jakZaczac.wersja = appVersionStr;
      } catch (e) {
        jakZaczac.wersja = "";
      }
    }
  }

  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape
  padding: 0

  /**
   * WLASNA SKORA, nie motyw aplikacji. Powitanie ma wygladac inaczej niz
   * okna robocze - po to, zeby bylo widac, ze to jest powitanie, a nie
   * kolejne okno do wypelnienia. Ciemny teal + jasna zielen, kontrasty
   * policzone: zielen na tle 11,9:1, tekst 13,6:1, opis 7,4:1 (WCAG AA
   * wymaga 4,5:1 dla tekstu). Bursztyn ostrzezenia: 10,4:1.
   */
  readonly property color barwaTla: "#0B3B39"
  readonly property color barwaTekstu: "#EAF7EF"
  readonly property color barwaSzara: "#9FC3BE"
  readonly property color barwaGlowna: "#A8E86A"
  readonly property color barwaUwagi: "#F5C542"

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

  function pokazEkranPowitalny() {
    wykonaj(function () {
      if (ekranPowitalny)
        ekranPowitalny.visible = true;
      else
        console.warn("WFG JakZaczac: brak ekranu powitalnego");
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

    /**
     * WLASNE TLO. ItemDelegate ze stylu rysuje BIALY prostokat - na jasnym
     * motywie niewidoczny, na ciemnym tealu bialy pas, na ktorym ginie jasny
     * tytul. Zmierzone: piksel tla wiersza (255,255,255) przy tle okna
     * (11,59,57). Stad przezroczyste tlo + delikatna kreska rozdzielajaca
     * i rozjasnienie pod palcem, zeby dotkniecie bylo widac.
     */
    background: Rectangle {
      color: wiersz.pressed ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
      Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        height: 1
        color: Qt.rgba(1, 1, 1, 0.08)
      }
    }
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

  /**
   * Blok, ktory TLUMACZY i niczego nie otwiera. Celowo NIE jest wierszem
   * z szewronem: szewron obiecuje, ze cos sie po dotknieciu stanie, a tu
   * sie nie stanie. Dwa rozne ksztalty dla dwoch roznych obietnic.
   */
  component Wyjasnienie: ColumnLayout {
    property string haslo: ""
    property string tresc: ""
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.topMargin: 6
    Layout.bottomMargin: 6
    spacing: 2
    Text {
      Layout.fillWidth: true
      text: parent.haslo
      color: jakZaczac.barwaTekstu
      font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12)
      font.bold: true
      wrapMode: Text.WordWrap
    }
    Text {
      Layout.fillWidth: true
      text: parent.tresc
      color: jakZaczac.barwaSzara
      font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) - 1
      wrapMode: Text.WordWrap
      lineHeight: 1.15
    }
  }

  component Naglowek: Text {
    Layout.fillWidth: true
    Layout.topMargin: 12
    Layout.bottomMargin: 2
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    color: jakZaczac.barwaGlowna
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
          text: qsTr("Witaj w WorkFieldGIS")
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

        // --- ostrzeżenie ---------------------------------------------
        // PIERWSZE, co widać po otwarciu. Na dole ekranu byłoby uczciwe
        // formalnie i bezużyteczne w praktyce — tester dowiaduje się
        // o stanie programu ZANIM na nim popracuje.
        Rectangle {
          Layout.fillWidth: true
          Layout.margins: 12
          Layout.preferredHeight: uwaga.implicitHeight + 20
          radius: 6
          color: Qt.rgba(jakZaczac.barwaUwagi.r, jakZaczac.barwaUwagi.g, jakZaczac.barwaUwagi.b, 0.12)
          border.width: 1
          border.color: Qt.rgba(jakZaczac.barwaUwagi.r, jakZaczac.barwaUwagi.g, jakZaczac.barwaUwagi.b, 0.45)

          ColumnLayout {
            id: uwaga
            anchors.fill: parent
            anchors.margins: 10
            spacing: 3
            Text {
              Layout.fillWidth: true
              text: qsTr("Wczesny etap rozwoju")
              color: jakZaczac.barwaUwagi
              font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12)
              font.bold: true
            }
            Text {
              Layout.fillWidth: true
              text: qsTr("Program jest w budowie i zmienia się z tygodnia na tydzień. Używaj go z dużą ostrożnością tam, gdzie wynik ma znaczenie: sprawdzaj dane po każdym etapie, rób kopie zapasowe i nie opieraj na nim pracy, której nie dałoby się powtórzyć. Przy operatach, odbiorach i dokumentacji, za którą się odpowiada, traktuj go jako narzędzie pomocnicze — nie jako jedyne źródło.")
              color: jakZaczac.barwaTekstu
              font.pointSize: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) - 1
              wrapMode: Text.WordWrap
              lineHeight: 1.15
            }
          }
        }

        // --- co to jest ------------------------------------------------
        Naglowek {
          text: qsTr("CO TO JEST")
        }
        Wyjasnienie {
          haslo: qsTr("Projekt")
          tresc: qsTr("Jedna praca, zamknięta w jednym folderze: plik QGIS, warstwy, formularze, słowniki, stylizacja i zdjęcia. Wszystko, czego ten plik potrzebuje, leży obok niego — dlatego projekt da się przenieść, spakować i oddać w całości, bez zbierania danych po katalogach. To, co założysz w biurze, w terenie działa bez zasięgu; to, co zbierzesz w terenie, wraca tą samą paczką. Projekt zakładasz od zera, z modułu albo z gotowego rysunku DXF.")
        }
        Wyjasnienie {
          haslo: qsTr("Zlecenie")
          tresc: qsTr("Grupa projektów, które mają być robione tak samo. W obrębie zlecenia pilnujemy dwóch rzeczy. Pierwsza to unifikacja: te same warstwy, te same formularze i słowniki, ta sama stylizacja w każdym projekcie — po to, żeby dane z kilkunastu projektów dały się złożyć w jedno opracowanie. Druga to obieg pracy: rozdanie projektów ludziom w terenie i odebranie ich z powrotem — kto co dostał, co już wróciło i czy wróciło kompletne.")
        }

        Naglowek {
          text: qsTr("NA CZYM TO STOI")
        }
        QfPochodzenie {
          Layout.fillWidth: true
          Layout.leftMargin: 12
          Layout.rightMargin: 12
          Layout.topMargin: 2
          Layout.bottomMargin: 4
          wersjaQGIS: jakZaczac.wersjaQGIS
          barwaTekstu: jakZaczac.barwaSzara
          barwaLinku: jakZaczac.barwaGlowna
          rozmiar: (Theme.defaultFont !== undefined ? Theme.defaultFont.pointSize : 12) - 1
        }

        Naglowek {
          text: qsTr("OTWÓRZ PROJEKT")
        }
        Czynnosc {
          text: qsTr("Moje projekty")
          opis: qsTr("Ekran powitalny z listą ostatnich i z kartą pamięci")
          onClicked: jakZaczac.pokazEkranPowitalny()
        }
        Czynnosc {
          text: qsTr("Złóż projekt z modułu")
          opis: qsTr("Prawa szuflada, zakładka Moduły — karty CAD i Inwentaryzacji")
          onClicked: jakZaczac.otworzZakladke(0)
        }

        Naglowek {
          text: qsTr("WCZYTAJ DANE")
        }
        Czynnosc {
          text: qsTr("Import z rysunku DXF")
          opis: qsTr("Warstwy, bloki, opisy i warstwice — za jednym razem")
          visible: jakZaczac.importCAD !== null
          onClicked: jakZaczac.otworzOkno(jakZaczac.importCAD, "import DXF")
        }
        Czynnosc {
          text: qsTr("Podkłady")
          opis: qsTr("Ortofotomapa i mapy na obszar pracy, do użycia bez zasięgu")
          visible: jakZaczac.podklady !== null
          onClicked: jakZaczac.otworzOkno(jakZaczac.podklady, "podkłady")
        }
        Czynnosc {
          text: qsTr("Dane wysokościowe")
          opis: qsTr("NMT i NMPT, z nich liczy się CHM")
          visible: jakZaczac.daneWysokosciowe !== null
          onClicked: jakZaczac.otworzOkno(jakZaczac.daneWysokosciowe, "dane wysokościowe")
        }
        Czynnosc {
          text: qsTr("Georeferencja obrazu")
          opis: qsTr("Zdjęcie mapy albo szkic — wpasowanie w układ współrzędnych")
          visible: jakZaczac.georeferencja !== null
          onClicked: jakZaczac.otworzOkno(jakZaczac.georeferencja, "georeferencja")
        }

        Naglowek {
          text: qsTr("GDZIE CO JEST")
        }
        Czynnosc {
          text: qsTr("Zlecenia")
          opis: qsTr("Lewa szuflada — drzewo zleceń i projektów, stan pracy")
          onClicked: jakZaczac.otworzSekcje(0)
        }
        Czynnosc {
          text: qsTr("Projekt")
          opis: qsTr("Lewa szuflada — zakładanie, zapis, szablony, pliki projektu")
          onClicked: jakZaczac.otworzSekcje(1)
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
          text: qsTr("Numer wersji jest w nagłówku lewej szuflady — podaj go w zgłoszeniu. Tam też otwiera się „Co nowego” z listą zmian, a obok strzałki zamknięcia stoi znak zapytania, którym wrócisz na ten ekran. Uwagę wysyłasz z menu: Aplikacja → „Zgłoś uwagę”.")
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
