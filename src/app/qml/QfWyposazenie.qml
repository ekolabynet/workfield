import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import org.qgis
import org.qfield
import org.qfield.core
import Theme

/**
 * \ingroup qml
 *
 * WorkField 15.09.2026 — CZY PROJEKT NADĄŻA ZA APLIKACJĄ.
 *
 * ======================================================================
 * PO CO
 * ======================================================================
 * Mechanizm porównywania stempla z katalogiem działa od 13.09 i przez dwa
 * dni MILCZAŁ — dało się go zapytać wyłącznie z konsoli. To jest dokładnie
 * ta klasa długu, którą nazwaliśmy przy sygnale `geometriaZniszczona`:
 * kod wykrywa, nikt się nie dowiaduje.
 *
 * ======================================================================
 * CO WOLNO Z TEGO EKRANU
 * ======================================================================
 * Zakładanie modułów TERENOWYCH. Do 23.09.2026 znaczyło to wyłącznie
 * „tych, które zmieniają ustawienia projektu" — struktura zostawała
 * w biurze. Dziś aplikacja zakłada też warstwę techniczną `tyczenie`
 * i kafle paska, bo ani jedno, ani drugie nie wymaga decyzji, której
 * nie da się podjąć w terenie: warstwa ma dwa pola i żadnej branży,
 * a kafle wskazuje człowiek, jednym tapnięciem na warstwę.
 *
 * Zasada z 09.09 zostaje w mocy tam, gdzie miała sens: **naprawiać wolno
 * to, co widać na miejscu.** Przed każdą zmianą powstaje kopia projektu,
 * a gdy moduł rusza bazę — także kopia `dane.gpkg`.
 *
 * ======================================================================
 * MODUŁ, KTÓRY PYTA
 * ======================================================================
 * Warstwa dołożona do cudzego projektu bez pytania to zmiana, której nikt
 * nie zamawiał. Kafle dla warstw wybranych za człowieka to pasek, którego
 * nie rozpoznaje. Dlatego moduł niesie w `modul.json` pole `pyta`, a to
 * okno otwiera przed założeniem okienko: potwierdzenie z wypisanymi polami
 * i kaflem albo listę warstw do zaznaczenia.
 *
 * Przycisk przy module biurowym jest NIECZYNNY I PODAJE POWÓD. Przycisk
 * widoczny i milczący jest gorszy od braku przycisku — to zasada z 17.08,
 * ta sama, przez którą zniknęły „Magazyn" i „Nowy z szablonu" z telefonu.
 */
Popup {
  id: ekranWyposazenia

  parent: mainWindow.contentItem
  width: Math.min(720, mainWindow.width - 16)
  height: Math.min(860, mainWindow.height - 24)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: Popup.CloseOnEscape

  property var pozycje: []
  property string komunikat: ""
  property bool blad: false

  /**
   * Ekran „Jak ten projekt jest ustawiony" (QfNaprawaProjektu).
   *
   * Podpinany w QgisMobileapp.qml, bo identyfikatory z tamtego pliku nie
   * są widoczne tutaj — to osobny komponent, z własnym zakresem nazw.
   */
  property var ekranUstawien: null

  //! Czy słownik gatunków leży obok projektu. Liczone w `odswiez()`.
  property bool slownikJest: false

  //! Ostatni błąd pobierania — zostaje na ekranie, bo dymek znika,
  //! a przyczyna jest potrzebna dłużej niż dwie sekundy.
  property string bladPobierania: ""

  Wyposazenie {
    id: wyposazenie
  }

  // ======================================================================
  // SŁOWNIK GATUNKÓW — treść, nie struktura
  // ======================================================================
  // Przeniesione 23.09.2026 z QfNaprawaProjektu. Powód jest jeden: dymek
  // startowy ma prowadzić do JEDNEGO okna. Dopóki pobieranie siedziało
  // gdzie indziej, komunikat „brakuje słownika gatunków" prowadził albo
  // donikąd, albo do drugiego okna — i trzeba było wiedzieć, do którego.
  //
  // Katalog wyposażenia o tym pliku nie wie i wiedzieć nie może: to WIEDZA
  // (nazwy gatunków, wskaźniki), a nie struktura, którą da się odtworzyć
  // z opisu. Dlatego to osobny wiersz pod listą modułów, a nie moduł.

  Settings {
    id: ustawieniaChmury
    category: "WFGChmura"
    //! Publiczny udział NextCloud z plikami wspólnymi (słowniki, wyposażenie)
    property string udzialUrl: "https://ekolaby.net/cloud/index.php/s/tNFYcZP9zKyFxeM"
    //! Podkatalog w udziale; pusty = korzeń udziału
    property string podkatalog: ""
  }

  /**
   * Adres pobrania pojedynczego pliku z publicznego udziału NextCloud.
   * Postać `.../s/<token>/download?path=/<podkatalog>&files=<nazwa>` działa
   * bez logowania i bez listowania — a nazwy plików wspólnych znamy z góry.
   */
  function adresPliku(nazwa) {
    const baza = ustawieniaChmury.udzialUrl.replace(/\/+$/, "");
    const sciezka = ustawieniaChmury.podkatalog === "" ? "/" : "/" + ustawieniaChmury.podkatalog;
    return baza + "/download?path=" + encodeURIComponent(sciezka) + "&files=" + encodeURIComponent(nazwa);
  }

  function pobierzSlownik() {
    if (!qgisProject || qgisProject.homePath === "") {
      komunikat = qsTr("Nie ma otwartego projektu.");
      blad = true;
      return;
    }
    bladPobierania = "";
    komunikat = qsTr("Pobieram słownik gatunków…");
    blad = false;
    iface.downloadFile(adresPliku("wf_wskazniki.gpkg"),
                       qgisProject.homePath + "/wf_wskazniki.gpkg");
  }

  Connections {
    target: iface

    function onDownloadFinished(path) {
      if (path.indexOf("wf_wskazniki.gpkg") === -1)
        return;
      ekranWyposazenia.bladPobierania = "";
      ekranWyposazenia.komunikat = qsTr("Słownik gatunków pobrany.");
      ekranWyposazenia.blad = false;
      ekranWyposazenia.odswiez();
    }

    // `downloadFile` emituje `downloadFailed` z treścią błędu — a ekran
    // słuchał kiedyś tylko powodzenia. Pobieranie zawodziło W CISZY:
    // przycisk tapnięty, komunikat „Pobieram…", i nic więcej do końca świata.
    function onDownloadFailed(error, path) {
      if (path.indexOf("wf_wskazniki.gpkg") === -1)
        return;
      ekranWyposazenia.bladPobierania = error;
      ekranWyposazenia.komunikat = qsTr("Nie pobrano słownika: %1").arg(error);
      ekranWyposazenia.blad = true;
    }
  }

  function odswiez() {
    pozycje = wyposazenie.sprawdz(qgisProject);
    slownikJest = qgisProject && qgisProject.homePath !== ""
                    ? FileUtils.fileExists(qgisProject.homePath + "/wf_wskazniki.gpkg")
                    : false;
  }

  function otworz() {
    komunikat = "";
    blad = false;
    odswiez();
    open();
  }

  //! Barwa stanu. `nowszy` celowo INNA niż `brak` — znaczy coś
  //! odwrotnego: to aplikacja jest przestarzała, nie projekt.
  function barwa(stan) {
    if (stan === "zgodny")
      return "#81C784";
    if (stan === "nowszy")
      return "#CE93D8";
    if (stan === "starszy")
      return "#FFC107";
    return "#EF5350";
  }

  /**
   * Moduł, który PYTA, zanim cokolwiek założy.
   *
   * WorkFieldGIS 23.09.2026. Warstwa dołożona do cudzego projektu bez
   * pytania to zmiana, której nikt nie zamawiał; kafle dla warstw wybranych
   * za człowieka to pasek, którego nie rozpoznaje. `pyta` przychodzi
   * z `modul.json` przez `Wyposazenie::sprawdz()` i mówi, które okienko
   * otworzyć — dopiero jego wynik jedzie do `zaloz()` jako `wybor`.
   */
  function uruchom(m) {
    if (m.pyta === "warstwy_kafli") {
      wyborKafli.otworz(m.modul);
      return;
    }
    if (m.pyta === "potwierdzenie") {
      potwierdzenie.zapytaj(m.modul, m.nazwa, wyposazenie.zapowiedzModulu(m.modul));
      return;
    }
    zaloz(m.modul, {});
  }

  function zaloz(modul, wybor) {
    const w = wyposazenie.zaloz(qgisProject, modul, wybor);
    komunikat = w.opis;
    blad = !w.ok;
    odswiez();
  }

  //! Napis na przycisku. „Sprawdź” przy module, który niczego nie zakłada;
  //! „Dołóż…” przy module powtarzalnym, który już raz przeszedł — kafle
  //! dokładasz przy każdej nowej warstwie, a stempel mówi tylko, że plik
  //! jest poprawny, nie że jest kompletny.
  function napisPrzycisku(m) {
    if (m.tylkoSprawdza)
      return qsTr("Sprawdź");
    if (m.stan === "zgodny")
      return qsTr("Dołóż…");
    return m.pyta !== "" ? qsTr("Załóż…") : qsTr("Załóż");
  }

  function opisStanu(m) {
    if (m.stan === "zgodny")
      return qsTr("wersja %1 — zgodna").arg(m.wAplikacji);
    if (m.stan === "nowszy")
      return qsTr("projekt ma %1, aplikacja oczekuje %2 — TO APLIKACJA JEST STARSZA")
               .arg(m.wProjekcie).arg(m.wAplikacji);
    if (m.stan === "starszy")
      return qsTr("projekt ma %1, aplikacja oczekuje %2").arg(m.wProjekcie).arg(m.wAplikacji);
    return qsTr("nie ma — aplikacja oczekuje wersji %1").arg(m.wAplikacji);
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Wyposażenie projektu")
        color: "#80CBC4"
        font: Theme.strongFont
        elide: Text.ElideRight
      }

      // Zrzut ustawień projektu — przyciąganie, tolerancja, edycja
      // topologiczna, warstwy. Jedyny ekran, który na to odpowiada;
      // od 23.09.2026 dymek startowy już tam nie prowadzi, więc wejście
      // musi być stąd.
      ToolButton {
        text: qsTr("Ustawienia")
        font: Theme.tinyFont
        visible: ekranWyposazenia.ekranUstawien !== null
        onClicked: ekranWyposazenia.ekranUstawien.open()
      }

      ToolButton {
        text: qsTr("Odśwież")
        font: Theme.tinyFont
        onClicked: ekranWyposazenia.odswiez()
      }

      ToolButton {
        text: qsTr("Zamknij")
        font: Theme.tinyFont
        onClicked: ekranWyposazenia.close()
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Katalog modułów jedzie w aplikacji, więc nie może się z nią rozjechać. Stempel siedzi w tabeli WF_WYPOSAZENIE w bazie projektu.")
      color: "#B0BEC5"
      font: Theme.tipFont
      wrapMode: Text.Wrap
    }

    Text {
      Layout.fillWidth: true
      visible: ekranWyposazenia.komunikat !== ""
      text: ekranWyposazenia.komunikat
      color: ekranWyposazenia.blad ? "#EF5350" : "#9CCC65"
      font: Theme.tipFont
      wrapMode: Text.Wrap
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: 6
      model: ekranWyposazenia.pozycje

      delegate: Rectangle {
        width: ListView.view.width
        height: tresc.implicitHeight + 16
        radius: 4
        color: "#14FFFFFF"

        readonly property string powodOdmowy: wyposazenie.mozeZalozyc(modelData.modul)

        ColumnLayout {
          id: tresc

          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: 8
          spacing: 3

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
              width: 10
              height: 10
              radius: 5
              color: ekranWyposazenia.barwa(modelData.stan)
            }

            Text {
              Layout.fillWidth: true
              text: modelData.nazwa
              color: "white"
              font: Theme.defaultFont
              elide: Text.ElideRight
            }

            Button {
              // Napis mówi, CO SIĘ STANIE: „Załóż…” z wielokropkiem, gdy
              // przedtem będzie pytanie; „Sprawdź” przy module, który niczego
              // nie zakłada; „Dołóż…” przy kaflach, które wolno uzupełniać
              // także po założeniu. Napis obiecujący czynność, której kod nie
              // wykonuje, kończył się do 23.09.2026 zdaniem „Krok się nie
              // powiódł” — i to była cała odpowiedź.
              text: ekranWyposazenia.napisPrzycisku(modelData)
              font: Theme.tinyFont
              // Sprawdzenie wolno powtórzyć ZAWSZE — nic nie zapisuje, nie robi
              // kopii i nic nie kosztuje. Poprawiasz plik kafli i pytasz znowu.
              // Moduł POWTARZALNY (kafle) zostaje czynny także po założeniu:
              // każda nowa warstwa to nowy kafel, a stempel mówi tylko, że
              // plik jest poprawny — nie że jest kompletny.
              visible: modelData.stan !== "nowszy"
                       && (modelData.tylkoSprawdza || modelData.powtarzalny
                           || modelData.stan !== "zgodny")
              enabled: powodOdmowy === ""
              onClicked: ekranWyposazenia.uruchom(modelData)
            }
          }

          Text {
            Layout.fillWidth: true
            text: ekranWyposazenia.opisStanu(modelData)
            color: ekranWyposazenia.barwa(modelData.stan)
            font: Theme.tinyFont
            wrapMode: Text.Wrap
          }

          // Powód odmowy PRZY przycisku, nie w osobnym okienku: człowiek
          // w rękawicach nie będzie szukał, czemu nie da się kliknąć.
          Text {
            Layout.fillWidth: true
            visible: powodOdmowy !== "" && modelData.stan !== "zgodny"
            text: qsTr("nie założę tego z telefonu — %1").arg(powodOdmowy)
            color: "#90A4AE"
            font: Theme.tinyFont
            wrapMode: Text.Wrap
          }

          Text {
            Layout.fillWidth: true
            visible: modelData.opis !== ""
            text: modelData.opis
            color: "#78909C"
            font: Theme.tipFont
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: modelData.data !== undefined && String(modelData.data) !== ""
            text: qsTr("ostatnio: %1").arg(String(modelData.data).replace("T", " "))
            color: "#607D8B"
            font: Theme.tinyFont
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: parent.count === 0
        text: qsTr("Nie udało się odczytać katalogu wyposażenia.")
        color: "#EF5350"
        font: Theme.tipFont
      }
    }

    // ------------------------------------------------ pliki wspólne
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: wierszSlownika.implicitHeight + 16
      radius: 4
      color: "#14FFFFFF"

      ColumnLayout {
        id: wierszSlownika

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 8
        spacing: 3

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Rectangle {
            width: 10
            height: 10
            radius: 5
            color: ekranWyposazenia.slownikJest ? "#81C784" : "#EF5350"
          }

          Text {
            Layout.fillWidth: true
            text: qsTr("Słownik gatunków")
            color: "white"
            font: Theme.defaultFont
            elide: Text.ElideRight
          }

          Button {
            text: qsTr("Pobierz z sieci")
            font: Theme.tinyFont
            visible: !ekranWyposazenia.slownikJest
            onClicked: ekranWyposazenia.pobierzSlownik()
          }
        }

        Text {
          Layout.fillWidth: true
          text: ekranWyposazenia.slownikJest
                  ? qsTr("wf_wskazniki.gpkg leży obok projektu")
                  : qsTr("nie ma wf_wskazniki.gpkg — podpowiadanie gatunków nie zadziała")
          color: ekranWyposazenia.slownikJest ? "#81C784" : "#EF5350"
          font: Theme.tinyFont
          wrapMode: Text.Wrap
        }

        Text {
          Layout.fillWidth: true
          text: qsTr("To nie struktura, tylko wiedza — żaden kod jej nie wymyśli, musi przyjechać. Potrzebny internet.")
          color: "#78909C"
          font: Theme.tipFont
          wrapMode: Text.Wrap
        }

        Text {
          Layout.fillWidth: true
          visible: ekranWyposazenia.bladPobierania !== ""
          text: qsTr("Ostatni błąd pobierania: %1").arg(ekranWyposazenia.bladPobierania)
          color: "#EF5350"
          font: Theme.tinyFont
          wrapMode: Text.Wrap
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Przed każdym założeniem powstaje kopia projektu, a gdy moduł rusza bazę — także kopia dane.gpkg. Moduły, których aplikacja nie umie wykonać, zostają w biurze i mówią o tym przy przycisku.")
      color: "#78909C"
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }
  }

  // ======================================================================
  // PYTANIE PRZED ZAŁOŻENIEM — warstwa robocza
  // ======================================================================
  // „TO TECHNICZNA WARSTWA” (uwaga Piotra, 23.09.2026). Właśnie dlatego
  // aplikacja umie ją założyć sama — i właśnie dlatego pyta: dwa pola
  // i kafel to zmiana mała, ale w CUDZYM projekcie.
  Popup {
    id: potwierdzenie

    parent: mainWindow.contentItem
    width: Math.min(560, mainWindow.width - 24)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    modal: true
    closePolicy: Popup.CloseOnEscape
    padding: 14

    property string modul: ""
    property string tytul: ""
    property string tresc: ""

    function zapytaj(m, nazwa, zapowiedz) {
      modul = m;
      tytul = nazwa;
      tresc = zapowiedz;
      open();
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 10

      Text {
        Layout.fillWidth: true
        text: potwierdzenie.tytul
        color: "#80CBC4"
        font: Theme.strongFont
        wrapMode: Text.Wrap
      }

      Text {
        Layout.fillWidth: true
        text: potwierdzenie.tresc
        color: "white"
        font: Theme.tipFont
        wrapMode: Text.Wrap
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Kopia projektu i kopia dane.gpkg powstaną obok, przed zmianą.")
        color: "#78909C"
        font: Theme.tinyFont
        wrapMode: Text.Wrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Item { Layout.fillWidth: true }

        ToolButton {
          text: qsTr("Nie teraz")
          font: Theme.tinyFont
          onClicked: potwierdzenie.close()
        }

        Button {
          text: qsTr("Załóż")
          font: Theme.tinyFont
          onClicked: {
            potwierdzenie.close();
            ekranWyposazenia.zaloz(potwierdzenie.modul, {});
          }
        }
      }
    }
  }

  // ======================================================================
  // PYTANIE PRZED ZAŁOŻENIEM — którym warstwom kafel
  // ======================================================================
  // Treść paska jest BRANŻOWA (D/G/U/T w dendro, inna w płatach), więc
  // moduł jej nie zgaduje. Wskazuje ją człowiek, jednym tapnięciem na
  // warstwę — a etykiety dobiera kod, żeby się nie zderzały.
  Popup {
    id: wyborKafli

    parent: mainWindow.contentItem
    width: Math.min(620, mainWindow.width - 16)
    height: Math.min(720, mainWindow.height - 24)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    modal: true
    closePolicy: Popup.CloseOnEscape
    padding: 12

    property string modul: ""
    property var lista: []
    property var zaznaczone: ({})

    function otworz(m) {
      modul = m;
      lista = wyposazenie.kandydaciKafli(qgisProject);
      // Z GÓRY ZAZNACZONE te, które kafla NIE MAJĄ — po to jest to okno.
      // Warstwy z kaflem zostają widoczne, żeby było widać CAŁY pasek,
      // a nie tylko dziurę w nim.
      var z = {};
      for (var i = 0; i < lista.length; ++i)
        z[lista[i].warstwa] = !lista[i].maKafel;
      zaznaczone = z;
      open();
    }

    function przelacz(nazwa) {
      var z = {};
      for (var k in zaznaczone)
        z[k] = zaznaczone[k];
      z[nazwa] = !z[nazwa];
      zaznaczone = z;
    }

    function wybrane() {
      var w = [];
      for (var i = 0; i < lista.length; ++i) {
        var n = lista[i].warstwa;
        if (zaznaczone[n] && !lista[i].maKafel)
          w.push(n);
      }
      return w;
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Którym warstwom kafel?")
        color: "#80CBC4"
        font: Theme.strongFont
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Kafel zakłada obiekt jednym tapnięciem, bez chodzenia po menu warstw. Etykietę dobiera aplikacja tak, żeby dwa kafle nie wyszły takie same. Plik jest SCALANY — kafle dopisane ręcznie zostają.")
        color: "#B0BEC5"
        font: Theme.tipFont
        wrapMode: Text.Wrap
      }

      ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 4
        model: wyborKafli.lista

        delegate: Rectangle {
          id: wiersz

          width: ListView.view.width
          height: 46
          radius: 4
          color: modelData.maKafel ? "#0AFFFFFF" : "#14FFFFFF"

          readonly property bool wybrany: wyborKafli.zaznaczone[modelData.warstwa] === true

          MouseArea {
            anchors.fill: parent
            enabled: !modelData.maKafel
            onClicked: wyborKafli.przelacz(modelData.warstwa)
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 10

            // Kwadrat zamiast CheckBoksa: duży cel dla palca w rękawicy
            // i wygląd, który nie zależy od stylu kontrolek.
            Rectangle {
              width: 24
              height: 24
              radius: 3
              color: "transparent"
              border.width: 2
              border.color: modelData.maKafel ? "#546E7A"
                                              : (wiersz.wybrany ? "#81C784" : "#90A4AE")

              Text {
                anchors.centerIn: parent
                text: modelData.maKafel ? "·" : (wiersz.wybrany ? "✓" : "")
                color: modelData.maKafel ? "#546E7A" : "#81C784"
                font: Theme.defaultFont
              }
            }

            // Etykieta tak, jak wyjdzie na pasku — żeby nie była
            // niespodzianką dopiero w terenie.
            Rectangle {
              width: 34
              height: 26
              radius: 3
              color: modelData.maKafel ? "#37474F" : (wiersz.wybrany ? "#2E7D32" : "#37474F")

              Text {
                anchors.centerIn: parent
                text: modelData.etykieta
                color: "white"
                font: Theme.tinyFont
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              Text {
                Layout.fillWidth: true
                text: modelData.warstwa
                color: modelData.maKafel ? "#90A4AE" : "white"
                font: Theme.defaultFont
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                text: modelData.maKafel
                        ? qsTr("%1 — kafel już jest").arg(modelData.geometria)
                        : modelData.geometria
                color: "#78909C"
                font: Theme.tinyFont
                elide: Text.ElideRight
              }
            }
          }
        }

        Text {
          anchors.centerIn: parent
          anchors.margins: 12
          width: parent.width - 24
          visible: parent.count === 0
          text: qsTr("Projekt nie ma warstwy, której można dać kafel. Podkłady, słowniki i tabele załączników się nie liczą — kafel zakłada obiekt, więc warstwa musi mieć geometrię.")
          color: "#EF5350"
          font: Theme.tipFont
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: qsTr("zaznaczonych: %1").arg(wyborKafli.wybrane().length)
          color: "#B0BEC5"
          font: Theme.tinyFont
        }

        ToolButton {
          text: qsTr("Anuluj")
          font: Theme.tinyFont
          onClicked: wyborKafli.close()
        }

        Button {
          // Pusty wybór też wolno zatwierdzić: krok wykonuje wtedy samą
          // KONTROLĘ pliku — dokładnie to, co moduł robił do 23.09.2026.
          text: wyborKafli.wybrane().length > 0 ? qsTr("Załóż kafle") : qsTr("Tylko sprawdź")
          font: Theme.tinyFont
          onClicked: {
            const w = wyborKafli.wybrane();
            wyborKafli.close();
            ekranWyposazenia.zaloz(wyborKafli.modul, { "warstwy": w });
          }
        }
      }
    }
  }
}
