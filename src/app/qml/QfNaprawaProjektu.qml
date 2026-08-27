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
  // WorkField 26.08.2026 — szerzej, bo doszla sekcja stanu projektu:
  // przy 480 px tekst lamal sie po dwa slowa. Procent szerokosci okna
  // z ograniczeniem: na biurku szeroko, na telefonie miesci sie w ekranie.
  width: Math.min(mainWindow.width - 32, Math.max(480, mainWindow.width * 0.5))
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape

  // Popup bez wlasnego tla bierze JASNE tlo z QtQuick.Controls, a wszystkie
  // teksty uzywaja kolorow Theme dobranych pod CIEMNE. Efekt: szarosc na
  // szarym, nieczytelna w slonecznym swietle — czyli tam, gdzie ten ekran
  // jest potrzebny.
  background: Rectangle {
    color: Theme.mainBackgroundColor
    radius: 6
    border.width: 1
    border.color: Theme.controlBorderColor
  }

  // Zmiana rozmiaru za róg — wspólny komponent, bo to samo dotyczy galerii,
  // panelu danych i reszty okien. Na telefonie niewidoczny.
  QfUchwytRozmiaru {
    okno: naprawa
    klucz: "stanProjektu"
  }

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

    // ------------------------------------------------------ stan projektu
    //
    // 25.08.2026: punkty nie siadały na miejscu przy małych płatach,
    // a przyczynę (`type=3`, edycja topologiczna) znaleźliśmy dopiero
    // wieczorem, grepując XML. W terenie nie było jak sprawdzić, co jest
    // ustawione. Ta sekcja odpowiada na to pytanie na miejscu.
    //
    // Kolejność ODWROTNA wobec tego, co zwraca czasownik: najpierw
    // ostrzeżenia, bo to one mówią, czy coś jest nie tak. Warstwy na końcu
    // i zwinięte — najdłuższe i najrzadziej potrzebne.

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
      opacity: 0.4
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Jak ten projekt jest ustawiony")
      font: Theme.strongTipFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
    }

    Item {
      id: stanProjektu

      property var dane: ({})

      function odswiez() {
        dane = qgisProject ? NarzedziaProjektu.stanProjektu(qgisProject) : ({});
      }

      // Odświeżamy przy każdym otwarciu ekranu, nie raz przy starcie:
      // ustawienia zmieniają się w trakcie pracy, a nieaktualny zrzut
      // jest gorszy niż jego brak.
      Connections {
        target: naprawa
        function onOpened() { stanProjektu.odswiez(); }
      }

      Component.onCompleted: odswiez()
    }

    // --- ostrzeżenia: liczone z DANYCH, nie z ustawień

    Repeater {
      model: stanProjektu.dane.ostrzezenia !== undefined
             ? stanProjektu.dane.ostrzezenia : []

      delegate: Text {
        required property var modelData
        Layout.fillWidth: true
        text: (modelData.waga === "brak" ? "✗  " : "!  ") + modelData.opis
        font: Theme.tipFont
        color: modelData.waga === "brak" ? Theme.errorColor : Theme.warningColor
        wrapMode: Text.WordWrap
      }
    }

    Text {
      Layout.fillWidth: true
      visible: stanProjektu.dane.ostrzezenia !== undefined
               && stanProjektu.dane.ostrzezenia.length === 0
      text: qsTr("Nic nie budzi wątpliwości.")
      font: Theme.tipFont
      color: Theme.secondaryTextColor
    }

    // --- pomiar: słownie, bo `type=3` nic nie mówi człowiekowi
    //     (a to właśnie ta liczba kosztowała dzień terenu)

    Text {
      Layout.fillWidth: true
      visible: stanProjektu.dane.pomiar !== undefined
      font: Theme.tipFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      text: {
        const p = stanProjektu.dane.pomiar;
        if (p === undefined)
          return "";
        const w = [];
        if (p.przyciaganieWlaczone) {
          const typ = p.typObowiazujacy !== undefined ? p.typObowiazujacy : p.typ;
          w.push(qsTr("Przyciąganie: %1, tolerancja %2 %3")
                 .arg(typ).arg(p.tolerancja).arg(p.jednostka));
          if (p.tryb !== undefined)
            w.push(qsTr("   tryb: %1").arg(p.tryb));
          if (p.przeciecia)
            w.push(qsTr("   także do przecięć"));
        } else {
          w.push(qsTr("Przyciąganie: wyłączone"));
        }
        if (p.unikanieNakladania)
          w.push(qsTr("Unikanie nakładania: %1")
                 .arg(p.warstwyNakladania.length > 0
                      ? p.warstwyNakladania.join(", ")
                      : qsTr("bez warstw")));
        else
          w.push(qsTr("Unikanie nakładania: wyłączone"));
        if (p.edycjaTopologiczna)
          w.push(qsTr("Edycja topologiczna: WŁĄCZONA"));
        return w.join("\n");
      }
    }

    // --- dane: gdzie zapisuje i czy jest słownik

    Text {
      Layout.fillWidth: true
      visible: stanProjektu.dane.dane !== undefined
      font: Theme.tipFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      text: {
        const d = stanProjektu.dane.dane;
        if (d === undefined)
          return "";
        const w = [];
        w.push(qsTr("Zapisuje do: %1")
               .arg(d.plikDanych !== "" ? d.plikDanych : qsTr("— brak pliku danych!")));
        w.push(qsTr("Słownik gatunków: %1")
               .arg(d.wskazniki ? qsTr("jest") : qsTr("BRAK")));
        return w.join("\n");
      }
    }

    // --- warstwy: zwinięte, bo to najdłuższa i najrzadziej potrzebna część

    Button {
      id: przyciskWarstw
      Layout.fillWidth: true
      visible: stanProjektu.dane.warstwy !== undefined

      // Bez własnego tła przycisk gubi się na ciemnym tle okna: widać sam
      // tekst, więc nie wygląda na coś, co da się nacisnąć.
      background: Rectangle {
        color: przyciskWarstw.down ? Theme.mainColor
                                   : przyciskWarstw.hovered ? Theme.controlBackgroundColor
                                                            : "transparent"
        border.width: 1
        border.color: Theme.controlBorderColor
        radius: 4
      }
      contentItem: Text {
        text: przyciskWarstw.text
        font: Theme.tipFont
        color: Theme.mainTextColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
      text: listaWarstw.visible
            ? qsTr("Ukryj warstwy")
            : qsTr("Pokaż warstwy (%1)").arg(stanProjektu.dane.warstwy !== undefined
                                             ? stanProjektu.dane.warstwy.length : 0)
      onClicked: listaWarstw.visible = !listaWarstw.visible
    }

    ColumnLayout {
      id: listaWarstw
      Layout.fillWidth: true
      spacing: 2
      visible: false

      Repeater {
        model: stanProjektu.dane.warstwy !== undefined ? stanProjektu.dane.warstwy : []

        delegate: Text {
          required property var modelData
          Layout.fillWidth: true
          font: Theme.tinyFont
          wrapMode: Text.WordWrap
          // Warstwa wskazująca poza katalog projektu nie pojedzie w teren —
          // na telefonie będzie pusta i nikt tego nie zauważy przed wyjazdem.
          color: modelData.wKatalogu ? Theme.secondaryTextColor : Theme.warningColor
          text: {
            let s = modelData.nazwa + "  ·  " + modelData.geometria
                  + "  ·  " + modelData.obiektow;
            if (modelData.plik !== "")
              s += "  ·  " + modelData.plik;
            if (modelData.wEdycji)
              s += qsTr("  ·  W EDYCJI");
            if (!modelData.wKatalogu)
              s += qsTr("  ·  POZA KATALOGIEM");
            return s;
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
      opacity: 0.4
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
