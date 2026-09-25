/***************************************************************************
  QfNaprawaProjektu.qml - co jest nie tak i co z tym zrobic

 ---------------------
 WorkField: zrzut ustawień wczytanego projektu, czytany na miejscu.

 ======================================================================
 TO JUŻ NIE JEST EKRAN NAPRAWY — 23.09.2026
 ======================================================================
 Do dziś ten ekran robił dwie rzeczy naraz: pokazywał stan projektu I
 naprawiał braki („Załóż" dla kafli, „Pobierz z sieci" dla słownika).
 Obie wyprowadziły się do Wyposażenia, bo tam siedzą wszystkie czasowniki,
 tam jest kopia zapasowa i tam stempel zapisuje, co zrobiono.

 Powód nie był porządkowy, tylko konkretny. `zbudujKlawisze()` brało
 `nazwa.substring(0, 1)` bez sprawdzania kolizji — kreator „Projekt z DXF"
 zakłada „Punkty" i „Poligony", więc OBA dostawały „P" i pasek wstawał
 z dwoma identycznymi klawiszami. Do tego pisało CAŁY plik od nowa, więc
 kafel dopisany ręcznie znikał przy następnym tapnięciu. `ModulKafli`
 (src/core/moduly/kafle.cpp) dobiera etykiety i SCALA plik.

 Nazwa pliku zostaje, żeby nie ruszać czterech miejsc w QgisMobileapp.qml
 dla samej kosmetyki. Nazwa OKNA mówi już, czym ono jest.

 ======================================================================
 PO CO TEN EKRAN ZOSTAŁ
 ======================================================================
 25.08.2026: punkty nie siadały na miejscu przy małych płatach, a przyczynę
 (`type=3`, edycja topologiczna) znaleźliśmy dopiero wieczorem, grepując
 XML. W terenie nie było jak sprawdzić, co jest ustawione. To jedyny ekran,
 który na to odpowiada — i dlatego nie zniknął razem z czasownikami.

 ======================================================================
 OD 23.09.2026 TO NIE JEST JUŻ TYLKO CZYTELNIA
 ======================================================================
 „Po co nam okno błędów, skoro nie mamy czasowników do ich poprawy?
 To zostawia użytkowników z poczuciem bezsensu" (uwaga Piotra).

 Racja — i to ta sama, przez którą rano `tyczenie` przestało tylko patrzeć.
 Okno mówiące „przyciąganie łapie segment przy obiektach 0.1 m" i kończące
 zdaniem „popraw w biurze" jest dokładnie tak samo bezużyteczne jak tamto
 „w projekcie nie ma warstwy tyczenie".

 Każde ostrzeżenie niesie teraz NAZWĘ CZASOWNIKA (`czasownik`), a to okno
 stawia przy nim przycisk. Czasownik pusty = naprawdę nie ma co zrobić
 w terenie; wtedy zostaje notatka i to jest uczciwe.

 CZEGO TU NIE MA: KASOWANIA. Przybliżenie do zlepionego wierzchołka
 i zaznaczenie go prowadzi do edytora geometrii, który QField ma od zawsze.
 Kasowanie obiektu z terenu to pierwsza nieodwracalna czynność w tej
 aplikacji i czeka na osobną decyzję.
 ***************************************************************************/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import Theme

Popup {
  id: naprawa

  /**
   * Instancja QfKontrolaProjektu.
   *
   * Nieużywana od 23.09.2026 — lista braków przeniosła się do Wyposażenia.
   * Własność zostaje zadeklarowana, bo QgisMobileapp.qml ją podpina;
   * usunięcie jej dałoby błąd wiązania, a nie oszczędność.
   */
  property var kontrola: null

  //! Wynik ostatniego czasownika — zostaje na ekranie, bo dymek gaśnie,
  //! a „zrobione" trzeba przeczytać przy okazji patrzenia na listę.
  property string komunikat: ""
  property bool blad: false

  //! Katalog modułów: to on przestawia ustawienia, robi kopię projektu
  //! i zapisuje. Okno tylko pyta i pokazuje wynik.
  Wyposazenie {
    id: wyposazenie
  }

  /**
   * Wykonuje czasownik przy ostrzeżeniu.
   *
   * Przybliżenia mapy ZAMYKAJĄ okno — inaczej człowiek przybliża mapę
   * i patrzy na popup, który ją zasłania. Zmiany ustawień okna NIE
   * zamykają: po nich lista się odświeża i widać, że ostrzeżenie zniknęło.
   */
  function wykonaj(co, o) {
    if (co === "pokaz_obiekt" || co === "pokaz_warstwe") {
      const warstwy = qgisProject ? qgisProject.mapLayersByName(o.warstwa) : [];
      if (warstwy.length === 0) {
        naprawa.komunikat = qsTr("W projekcie nie ma już warstwy „%1”.").arg(o.warstwa);
        naprawa.blad = true;
        return;
      }
      if (typeof dashBoard === "undefined" || !dashBoard.mapSettings) {
        naprawa.komunikat = qsTr("Nie mam dostępu do mapy.");
        naprawa.blad = true;
        return;
      }
      const udalo = co === "pokaz_obiekt"
                      ? iface.zoomToFeature(warstwy[0], o.fid, dashBoard.mapSettings)
                      : iface.zoomToLayer(warstwy[0], dashBoard.mapSettings);
      if (!udalo) {
        // Obiekt z PUSTĄ geometrią nie ma dokąd przybliżyć — i to jest
        // dokładnie ten błąd, o którym mówi wpis. Milczenie wyglądałoby
        // jak niedziałający przycisk.
        naprawa.komunikat = qsTr("Nie ma do czego przybliżyć — ten obiekt nie ma geometrii.");
        naprawa.blad = true;
        return;
      }
      naprawa.close();
      return;
    }

    let w = null;
    if (co === "przyc_wierzcholek")
      w = wyposazenie.ustawPrzyciaganie(qgisProject, 0, false);
    else if (co === "przyc_prog")
      w = wyposazenie.ustawPrzyciaganie(qgisProject,
                                        o.parametr !== undefined ? o.parametr : 0.05, true);
    else if (co === "topologia")
      w = wyposazenie.ustawEdycjeTopologiczna(qgisProject, false);
    else if (co === "slownik") {
      naprawa.close();
      if (typeof ekranWyposazenia !== "undefined")
        ekranWyposazenia.otworz();
      return;
    }

    if (w === null)
      return;
    naprawa.komunikat = w.opis;
    naprawa.blad = !w.ok;
    stanProjektu.odswiez();
  }

  parent: mainWindow.contentItem
  x: Math.round((mainWindow.width - width) / 2)
  y: Math.round((mainWindow.height - height) / 2)
  // WorkField 26.08.2026 — szerzej, bo doszla sekcja stanu projektu:
  // przy 480 px tekst lamal sie po dwa slowa. Procent szerokosci okna
  // z ograniczeniem: na biurku szeroko, na telefonie miesci sie w ekranie.
  width: Math.min(mainWindow.width - 32, Math.max(480, mainWindow.width * 0.5))
  // Bez wysokosci `Popup` rysowal tlo na wysokosci bliskiej zeru, a tresc
  // lezala wprost na mapie — stad "jasne tlo" i przycisk zamykania poza
  // ekranem.
  height: Math.min(mainWindow.height - 48, 900)
  // Bez marginesu wewnetrznego tresc dotyka krawedzi okna i przycisk
  // na dole jest przyciety.
  padding: 12
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

  // --------------------------------------------------------------- widok

  Text {
    id: naglowek

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    text: qsTr("Co jest nie tak i co z tym zrobić")
    font: Theme.strongTipFont
    color: Theme.mainTextColor
    elide: Text.ElideRight
  }

  Flickable {
    id: przewijacz

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: naglowek.bottom
    anchors.bottom: stopka.top
    anchors.topMargin: 10
    anchors.bottomMargin: 8
    contentHeight: tresc.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ScrollBar.vertical: ScrollBar {
      policy: przewijacz.contentHeight > przewijacz.height ? ScrollBar.AlwaysOn
                                                           : ScrollBar.AlwaysOff
    }

  ColumnLayout {
    id: tresc

    width: przewijacz.width
    spacing: 10

    Text {
      Layout.fillWidth: true
      visible: naprawa.komunikat !== ""
      text: naprawa.komunikat
      font: Theme.tipFont
      color: naprawa.blad ? Theme.errorColor : "#9CCC65"
      wrapMode: Text.WordWrap
    }

    // Kolejność ODWROTNA wobec tego, co zwraca czasownik: najpierw
    // ostrzeżenia, bo to one mówią, czy coś jest nie tak. Warstwy na końcu
    // i zwinięte — najdłuższe i najrzadziej potrzebne.

    Item {
      id: stanProjektu

      property var dane: ({})

      function odswiez() {
        dane = qgisProject ? NarzedziaProjektu.stanProjektu(qgisProject) : ({});
      }

      // ==================================================================
      // BŁĘDY W DANYCH ODDZIELNIE OD USTAWIEŃ — 23.09.2026
      // ==================================================================
      // Jedna lista mieszała dwie rzeczy wymagające dwóch różnych czynności:
      // „przyciąganie łapie segment przy obiektach 0.1 m" naprawia się
      // przestawieniem ustawienia, a „obiekt o obwiedni 0.09 m (fid 2253)"
      // — poprawieniem geometrii TEGO obiektu. Wymieszane wyglądały jak
      // jedna kupa usterek projektu.
      //
      // `rodzaj` przychodzi z `NarzedziaProjektu::stanProjektu`. Starsza
      // aplikacja bez tego pola wrzuci wszystko do ustawień — pokaże
      // za dużo, ale nie zgubi niczego.
      function wedlugRodzaju(czyDane) {
        const wszystkie = dane.ostrzezenia !== undefined ? dane.ostrzezenia : [];
        const out = [];
        for (let i = 0; i < wszystkie.length; i++) {
          if ((wszystkie[i].rodzaj === "dane") === czyDane)
            out.push(wszystkie[i]);
        }
        return out;
      }

      /**
       * Przyciski przy ostrzeżeniu. Lista, bo przy przyciąganiu są DWA
       * wyjścia i żadne nie jest oczywiście lepsze: albo schodzimy z progu,
       * albo zostawiamy sam wierzchołek. Wybór należy do człowieka.
       */
      function czasowniki(o) {
        switch (o.czasownik) {
        case "pokaz_obiekt":
          return [{ "etykieta": qsTr("Pokaż na mapie"), "co": "pokaz_obiekt" }];
        case "pokaz_warstwe":
          return [{ "etykieta": qsTr("Pokaż warstwę"), "co": "pokaz_warstwe" }];
        case "przyciaganie":
          return [{ "etykieta": qsTr("Tylko wierzchołek"), "co": "przyc_wierzcholek" },
                  { "etykieta": qsTr("Próg %1 m").arg(
                      (o.parametr !== undefined ? o.parametr : 0.05).toFixed(2)),
                    "co": "przyc_prog" }];
        case "topologia":
          return [{ "etykieta": qsTr("Wyłącz"), "co": "topologia" }];
        case "slownik":
          return [{ "etykieta": qsTr("Pobierz"), "co": "slownik" }];
        }
        return [];
      }

      //! Adres obiektu pod komunikatem — pod przyszłe „Pokaż na mapie".
      function adres(o) {
        if (o.warstwa === undefined || o.warstwa === "")
          return "";
        return o.fid !== undefined && o.fid >= 0
                 ? qsTr("%1 · fid %2").arg(o.warstwa).arg(o.fid)
                 : o.warstwa;
      }

      // Odświeżamy przy każdym otwarciu ekranu, nie raz przy starcie:
      // ustawienia zmieniają się w trakcie pracy, a nieaktualny zrzut
      // jest gorszy niż jego brak.
      Connections {
        target: naprawa
        function onOpened() {
          stanProjektu.odswiez();
        }
      }

      Component.onCompleted: odswiez()
    }

    // --- BŁĘDY W DANYCH: pierwsze, bo mówią o pracy, która może być stracona

    Text {
      Layout.fillWidth: true
      visible: stanProjektu.wedlugRodzaju(true).length > 0
      text: qsTr("Błędy w danych")
      font: Theme.strongTipFont
      color: Theme.errorColor
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: stanProjektu.wedlugRodzaju(true)

      delegate: ColumnLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: 0

        Text {
          Layout.fillWidth: true
          text: "×  " + modelData.opis
          font: Theme.tipFont
          color: Theme.errorColor
          wrapMode: Text.WordWrap
        }

        // Adres obiektu osobno od zdania: zdanie tłumaczy, adres pozwala
        // znaleźć. Stąd wyrośnie „Pokaż na mapie" — bez tych dwóch pól
        // nie było z czego.
        Text {
          Layout.fillWidth: true
          Layout.leftMargin: 18
          visible: text !== ""
          text: stanProjektu.adres(modelData)
          font: Theme.tinyFont
          color: Theme.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        // CO Z TYM ZROBIĆ. Opis mówi, co się stało; rada mówi, co zrobić.
        // Bez niej człowiek dowiadywał się o usterce i zostawał z nią sam.
        Text {
          Layout.fillWidth: true
          Layout.leftMargin: 18
          Layout.topMargin: 2
          visible: modelData.rada !== undefined && modelData.rada !== ""
          text: "→ " + (modelData.rada !== undefined ? modelData.rada : "")
          font: Theme.tipFont
          color: Theme.mainTextColor
          wrapMode: Text.WordWrap
        }

        // Czasownik przy ostrzeżeniu. Pusta lista = naprawdę nie ma co
        // zrobić w terenie; wtedy zostaje sama rada i to jest uczciwe.
        Flow {
          Layout.fillWidth: true
          Layout.leftMargin: 18
          Layout.topMargin: 4
          spacing: 8

          Repeater {
            model: stanProjektu.czasowniki(modelData)

            QfButton {
              required property var modelData
              property var wpis: parent.parent.modelData
              text: modelData.etykieta
              topPadding: 6
              bottomPadding: 6
              leftPadding: 12
              rightPadding: 12
              onClicked: naprawa.wykonaj(modelData.co, wpis)
            }
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: stanProjektu.wedlugRodzaju(true).length > 0
      text: qsTr("„Pokaż na mapie” przybliża i ZAZNACZA obiekt — dalej poprawiasz go edytorem wierzchołków, tym samym co zawsze. Kasowania tu nie ma i nie będzie bez osobnej decyzji.")
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      visible: stanProjektu.wedlugRodzaju(true).length > 0
      color: Theme.controlBorderColor
      opacity: 0.4
    }

    // --- USTAWIENIA I SKŁAD PROJEKTU: prewencja, da się przestawić teraz

    Repeater {
      model: stanProjektu.wedlugRodzaju(false)

      delegate: ColumnLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: 0

        Text {
          Layout.fillWidth: true
          text: (modelData.waga === "brak" ? "×  " : "!  ") + modelData.opis
          font: Theme.tipFont
          color: modelData.waga === "brak" ? Theme.errorColor : Theme.warningColor
          wrapMode: Text.WordWrap
        }

        Text {
          Layout.fillWidth: true
          Layout.leftMargin: 18
          Layout.topMargin: 2
          visible: modelData.rada !== undefined && modelData.rada !== ""
          text: "→ " + (modelData.rada !== undefined ? modelData.rada : "")
          font: Theme.tipFont
          color: Theme.mainTextColor
          wrapMode: Text.WordWrap
        }

        // Czasownik przy ostrzeżeniu. Pusta lista = naprawdę nie ma co
        // zrobić w terenie; wtedy zostaje sama rada i to jest uczciwe.
        Flow {
          Layout.fillWidth: true
          Layout.leftMargin: 18
          Layout.topMargin: 4
          spacing: 8

          Repeater {
            model: stanProjektu.czasowniki(modelData)

            QfButton {
              required property var modelData
              property var wpis: parent.parent.modelData
              text: modelData.etykieta
              topPadding: 6
              bottomPadding: 6
              leftPadding: 12
              rightPadding: 12
              onClicked: naprawa.wykonaj(modelData.co, wpis)
            }
          }
        }

        Item { Layout.preferredHeight: 4 }
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
               .arg(d.wskazniki ? qsTr("jest") : qsTr("BRAK — pobierzesz w Wyposażeniu")));
        return w.join("\n");
      }
    }

    // --- warstwy: zwinięte, bo to najdłuższa i najrzadziej potrzebna część

    // QfButton, nie Button: ten pierwszy ma motyw, efekt naciśnięcia
    // i obsługę stanu wyłączonego. Button bierze wygląd ze stylu
    // systemowego i na ciemnym tle widać sam tekst.
    QfButton {
      id: przyciskWarstw
      Layout.fillWidth: true
      visible: stanProjektu.dane.warstwy !== undefined
      topPadding: 8
      bottomPadding: 8
      leftPadding: 10
      rightPadding: 10
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
      text: qsTr("Zmiany ustawień robią kopię projektu obok, zanim cokolwiek ruszą. Zakładanie modułów siedzi w Wyposażeniu — tam dochodzi jeszcze stempel w bazie.")
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

  }
  }

  // Pasek przyciskow PRZYKLEJONY do dolu. Przy dziesieciu ostrzezeniach
  // przycisk na koncu przewijanej listy uciekalby poza ekran — a wlasnie
  // wtedy czlowiek go szuka.
  RowLayout {
    id: stopka

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: 8

    Item { Layout.fillWidth: true }

    QfButton {
      text: qsTr("Zamknij")
      topPadding: 8
      bottomPadding: 8
      leftPadding: 10
      rightPadding: 10
      onClicked: naprawa.close()
    }
  }
}
