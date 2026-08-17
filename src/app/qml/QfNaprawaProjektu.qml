/***************************************************************************
  QfNaprawaProjektu.qml - naprawa braków wykrytych przy otwarciu projektu

 ---------------------
 WorkField: pokazuje listę braków z QfKontrolaProjektu i pozwala je usunąć.

 DWA CZASOWNIKI, NIE JEDEN — bo braki są dwóch rodzajów:

   ZAŁÓŻ        struktura. Aplikacja ma jej opis, więc umie ją odtworzyć.
                Plik kafli powstaje z warstw, które w projekcie są.
   POBIERZ      treść. Słownika gatunków żaden kod nie wymyśli — musi
                przyjechać. Przycisk „Załóż" byłby tu kłamstwem: założyłby
                pusty plik i wszystko wyglądałoby na naprawione.

 PODZIAŁ PO RYZYKU. Ten ekran robi wyłącznie rzeczy, które zapisują pliki
 OBOK projektu. Nic nie pisze do wnętrza dane.gpkg, w którym siedzą dane
 z terenu — zakładanie warstw i tabel ZAL_ to osobny, ostrożniejszy krok
 (docs/WERSJONOWANIE.md, „trzy czasowniki, nie jeden").

 Każda zmiana wymaga potwierdzenia, które mówi WPROST, co i gdzie powstanie.
 Bez ogólników „czy na pewno".
 ***************************************************************************/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import org.qfield
import Theme

Popup {
  id: naprawa

  //! instancja QfKontrolaProjektu
  property var kontrola: null

  property string _potwierdzenieRzecz: ""
  property string _potwierdzenieOpis: ""
  property string _potwierdzenieCel: ""

  parent: mainWindow.contentItem
  x: Math.round((mainWindow.width - width) / 2)
  y: Math.round((mainWindow.height - height) / 2)
  width: Math.min(mainWindow.width - 32, 480)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape

  Settings {
    id: ustawieniaChmury
    category: "WFGChmura"
    //! Publiczny udział NextCloud z plikami wspólnymi (słowniki, wyposażenie)
    property string udzialUrl: "https://ekolaby.net/cloud/index.php/s/tNFYcZP9zKyFxeM"
    //! Podkatalog w udziale; pusty = korzeń udziału
    property string podkatalog: ""
  }

  function katalog() {
    return qgisProject ? qgisProject.homePath : "";
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

  // ----------------------------------------------------------- czasowniki

  /**
   * Kafle paska z warstw, które w projekcie SĄ. Warstwy punktowe dostają
   * kafel ze zdjęciem, poligonowe i liniowe bez — obrys rysuje się dłużej
   * niż trwa zdjęcie. Ostatni kafel to tyczenie, jeśli warstwa istnieje.
   *
   * PUŁAPKA: klucz to `etykieta`, NIE `nazwa`. QfQuickCaptureBar.loadDefinitions()
   * przy złym kluczu wypisuje „definicje z pliku, 0 klawiszy" i pasek wstaje pusty.
   */
  function zbudujKlawisze() {
    const warstwy = NarzedziaProjektu.warstwyRobocze(qgisProject);
    const kolory = ["#2E7D32", "#00897B", "#F9A825", "#6A1B9A", "#C62828", "#1565C0"];
    const kafle = [];
    for (let i = 0; i < warstwy.length && kafle.length < 6; i++) {
      const w = warstwy[i];
      if (w.nazwa === "tyczenie")
        continue;
      kafle.push({
        "etykieta": w.nazwa.substring(0, 1).toUpperCase(),
        "warstwa": w.nazwa,
        "kolor": kolory[kafle.length % kolory.length],
        "zdjecie": w.punktowa === true
      });
    }
    if (NarzedziaProjektu.warstwaPoNazwie(qgisProject, "tyczenie")) {
      kafle.push({ "etykieta": "T", "warstwa": "tyczenie", "kolor": "#546E7A", "zdjecie": false });
    }
    return { "odleglosci": [25, 50, 100, 200], "klawisze": kafle };
  }

  function opisDzialania(rzecz) {
    if (rzecz === "klawisze") {
      const tresc = zbudujKlawisze();
      if (tresc.klawisze.length === 0)
        return { "mozliwe": false, "opis": qsTr("Projekt nie ma warstw roboczych — nie ma z czego zrobić kafli.") };
      const etykiety = tresc.klawisze.map(k => k.etykieta + " → " + k.warstwa).join("\n   ");
      return {
        "mozliwe": true,
        "przycisk": qsTr("Załóż"),
        "cel": katalog() + "/workfield_klawisze.json",
        "opis": qsTr("Powstanie plik:\n   %1\n\nz kaflami:\n   %2").arg(katalog() + "/workfield_klawisze.json").arg(etykiety)
      };
    }
    if (rzecz === "wskazniki") {
      return {
        "mozliwe": true,
        "przycisk": qsTr("Pobierz z sieci"),
        "cel": katalog() + "/wf_wskazniki.gpkg",
        "opis": qsTr("Zostanie pobrany plik:\n   %1\n\ndo:\n   %2\n\nPotrzebny internet.").arg(adresPliku("wf_wskazniki.gpkg")).arg(katalog() + "/wf_wskazniki.gpkg")
      };
    }
    return { "mozliwe": false, "opis": qsTr("Ten brak usuwa się zakładaniem warstwy w GeoPackage — osobny krok, jeszcze niedostępny.") };
  }

  function wykonaj(rzecz) {
    if (rzecz === "klawisze") {
      const tresc = JSON.stringify(zbudujKlawisze(), null, 2);
      if (NarzedziaProjektu.zapiszTekst(katalog() + "/workfield_klawisze.json", tresc)) {
        displayToast(qsTr("Kafle paska założone"));
        kontrola.sprawdz();
      } else {
        displayToast(qsTr("Nie udało się zapisać pliku kafli"), "error");
      }
      return;
    }
    if (rzecz === "wskazniki") {
      displayToast(qsTr("Pobieram słownik gatunków…"));
      iface.downloadFile(adresPliku("wf_wskazniki.gpkg"), katalog() + "/wf_wskazniki.gpkg");
      return;
    }
  }

  Connections {
    target: iface

    function onDownloadFinished(path) {
      if (path.indexOf("wf_wskazniki.gpkg") === -1)
        return;
      displayToast(qsTr("Słownik gatunków pobrany"));
      if (naprawa.kontrola)
        naprawa.kontrola.sprawdz();
    }
  }

  // --------------------------------------------------------------- widok

  ColumnLayout {
    width: parent.width
    spacing: 10

    Text {
      Layout.fillWidth: true
      text: qsTr("Czego brakuje temu projektowi")
      font: Theme.strongTipFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: naprawa.kontrola ? naprawa.kontrola.braki : []

      delegate: RowLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: (modelData.waga === "brak" ? "✗  " : "•  ") + modelData.opis
          font: Theme.tipFont
          color: modelData.waga === "brak" ? Theme.errorColor : Theme.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        Button {
          readonly property var dzialanie: naprawa.opisDzialania(modelData.rzecz)
          visible: modelData.waga === "brak" && dzialanie.mozliwe === true
          text: dzialanie.przycisk !== undefined ? dzialanie.przycisk : ""
          onClicked: {
            naprawa._potwierdzenieRzecz = modelData.rzecz;
            naprawa._potwierdzenieOpis = dzialanie.opis;
            naprawa._potwierdzenieCel = dzialanie.cel;
            potwierdzenie.open();
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: naprawa.kontrola && naprawa.kontrola.braki.length === 0
      text: qsTr("Nic nie brakuje.")
      font: Theme.tipFont
      color: Theme.secondaryTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Ten ekran zapisuje wyłącznie pliki obok projektu. Nie zmienia danych w dane.gpkg.")
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      Item { Layout.fillWidth: true }
      Button {
        text: qsTr("Zamknij")
        flat: true
        onClicked: naprawa.close()
      }
    }
  }

  // -------------------------------------------------- potwierdzenie zmiany

  Popup {
    id: potwierdzenie

    parent: mainWindow.contentItem
    x: Math.round((mainWindow.width - width) / 2)
    y: Math.round((mainWindow.height - height) / 2)
    width: Math.min(mainWindow.width - 32, 480)
    modal: true

    ColumnLayout {
      width: parent.width
      spacing: 10

      Text {
        Layout.fillWidth: true
        text: qsTr("Potwierdź")
        font: Theme.strongTipFont
        color: Theme.mainTextColor
      }

      Text {
        Layout.fillWidth: true
        text: naprawa._potwierdzenieOpis
        font: Theme.tinyFont
        color: Theme.mainTextColor
        wrapMode: Text.Wrap
      }

      RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        Button {
          text: qsTr("Anuluj")
          flat: true
          onClicked: potwierdzenie.close()
        }
        Button {
          text: qsTr("Zrób to")
          onClicked: {
            potwierdzenie.close();
            naprawa.wykonaj(naprawa._potwierdzenieRzecz);
          }
        }
      }
    }
  }
}
