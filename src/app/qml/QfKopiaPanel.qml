import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core
import Theme

/**
 * WorkField 24.08.2026 — panel „Kopia na nośnik".
 *
 * EWIDENCJA WYNIKA Z UŻYCIA, nie z konfiguracji (decyzja Piotra):
 * nie ma osobnego kroku „zarejestruj nośnik". Lista pokazuje to, co jest
 * PODPIĘTE w tej chwili. Nieznany dysk pyta o nazwę przy pierwszej kopii —
 * i to jest cała rejestracja. Od tej pory aplikacja go rozpoznaje, bo nazwa
 * leży na nim samym, w `WF_NOSNIK.json`, a nie w ustawieniach aplikacji.
 *
 * Ścieżka montowania nie jest tożsamością: `/media/piotr/WF_BACKUP` to
 * miejsce, w którym coś akurat stoi.
 */
QfPopup {
  id: kopiaPanel

  property string korzen: dashBoard.korzenMagazynu
  property var nosniki: []
  property int wybrany: -1
  property string zakres: "dane"
  property var rozpoznanie: null
  property var wynik: null
  property var listaMigawek: []
  property int zaznaczona: -1

  readonly property var nosnik: wybrany >= 0 && wybrany < nosniki.length ? nosniki[wybrany] : null
  readonly property var migawka: zaznaczona >= 0 && zaznaczona < listaMigawek.length
                                 ? listaMigawek[zaznaczona] : null

  /*
   * SZEROKOŚĆ DOSTĘPNA — liczona z tego, co człowiek wybrał i co mieści
   * ekran, a NIE z bieżącej szerokości okna.
   *
   * To nie jest drobiazg składniowy, tylko jedyny sposób, żeby uniknąć pętli:
   * `szeroko` decyduje, ile kolumn tabeli jest widocznych; liczba kolumn
   * decyduje o `implicitWidth`; `implicitWidth` decyduje o `width`. Gdyby
   * `szeroko` czytało `width`, koło by się zamknęło i Qt przerwałoby wiązanie,
   * zostawiając przypadkową wartość.
   */
  readonly property int dostepna: Math.min(Math.max(420, szerokoscWybrana), mainWindow.width - 32)

  //! Poniżej tej szerokości tabela gubi dwie kolumny zamiast się ścieśniać
  //! do nieczytelności. Zakres i tak siedzi w nazwie migawki.
  readonly property bool szeroko: dostepna >= 620

  /**
   * Podpis wiersza: data i godzina Z NAZWY KATALOGU.
   *
   * `snap_2026-08-24_0847_wszystko` → `2026-08-24  08:47`. To jest ta sama
   * godzina, którą widać w nazwie na dysku i w każdym skrypcie — a nie czas
   * zakończenia, pod którym Piotr 24.08.2026 szukał migawki i jej nie znalazł.
   */
  function etykietaMigawki(m) {
    if (!m || !m.nazwa)
      return "";
    const cz = String(m.nazwa).split("_");
    if (cz.length >= 3 && cz[2].length === 4)
      return cz[1] + "  " + cz[2].slice(0, 2) + ":" + cz[2].slice(2, 4);
    return m.nazwa;
  }

  /**
   * Do schowka — dane migawki albo cała tabela.
   *
   * Piotr, 24.08.2026: „Kopiuj powinno umożliwiać skopiowanie danych
   * i informacji o kopii". Przez cały dzień przepisywał mi te liczby ręcznie
   * albo wklejał zrzuty ekranu, z których musiałem je odczytywać. Program,
   * który sam je wyświetla, powinien umieć je oddać.
   *
   * Format: tabulatory. Wkleja się i do wiadomości, i do arkusza.
   */
  function doSchowka() {
    const l = [];
    if (migawka) {
      l.push(migawka.nazwa);
      l.push(qsTr("zakres\t%1").arg(migawka.zakres));
      l.push(qsTr("skończona\t%1").arg(migawka.data));
      l.push(qsTr("plików\t%1").arg(migawka.plikow));
      l.push(qsTr("danych\t%1").arg(FileUtils.representFileSize(migawka.bajtow)));
      l.push(qsTr("dowiązanych\t%1").arg(migawka.dowiazanych));
      l.push(qsTr("przerwana\t%1").arg(migawka.przerwane ? qsTr("tak") : qsTr("nie")));
      l.push(qsTr("błędów\t%1").arg(migawka.bledow));
      if (migawka.dowiazaniaPowod !== undefined && migawka.dowiazaniaPowod !== "")
        l.push(qsTr("dlaczego\t%1").arg(migawka.dowiazaniaPowod));
      l.push(qsTr("ścieżka\t%1").arg(migawka.sciezka));
      // Wynik sprawdzenia albo kopii idzie razem — to zwykle po to się kopiuje.
      if (wynik !== null && wynik.linie !== undefined) {
        l.push("");
        l.push(wynik.linie.join("\n"));
      }
    } else {
      l.push(qsTr("migawka\tzakres\tskończona\tplików\tdanych\tdowiązanych\tstan"));
      for (let i = 0; i < listaMigawek.length; i++) {
        const m = listaMigawek[i];
        l.push([m.nazwa, m.zakres, m.data, m.plikow,
                FileUtils.representFileSize(m.bajtow), m.dowiazanych,
                m.przerwane ? qsTr("przerwana") : (m.bledow > 0 ? qsTr("błędów: %1").arg(m.bledow) : "ok")
               ].join("\t"));
      }
    }
    platformUtilities.copyTextToClipboard(l.join("\n"));
    displayToast(migawka ? qsTr("Dane migawki skopiowane do schowka")
                         : qsTr("Tabela migawek skopiowana do schowka"));
  }

  function odswiez() {
    nosniki = KopieZapasowe.nosniki();
    if (wybrany >= nosniki.length)
      wybrany = -1;
    if (wybrany < 0 && nosniki.length === 1)
      wybrany = 0;
    zbadaj();
  }

  function zbadaj() {
    if (!nosnik) {
      rozpoznanie = null;
      return;
    }
    rozpoznanie = KopieZapasowe.zbadaj(korzen, zakres, nosnik.sciezka);
    listaMigawek = KopieZapasowe.migawki(nosnik.sciezka);
    // Zaznaczenie wskazuje POZYCJE w liscie, a lista wlasnie sie zmienila.
    // Gdyby zostalo, przycisk "Napraw czasy" dzialalby na inna migawke, niz
    // pokazuje podpis — a to jest dokladnie ten rodzaj bledu, ktory kosztuje
    // godziny i nie zostawia sladu.
    if (zaznaczona >= listaMigawek.length)
      zaznaczona = -1;
  }

  /**
   * SPRAWDZENIE MIGAWKI WOBEC JEJ WŁASNEGO SPISU.
   *
   * To jest ta czynność, dla której cały spis powstał. Migawka wiezie
   * w sobie listę tego, co do niej weszło; po pół roku pytamy nośnika,
   * czy nadal to ma — BEZ ORYGINAŁU, którego wtedy może już nie być.
   *
   * „Sprawdź" porównuje nazwy i rozmiary. „…z sumami" liczy sumy kontrolne:
   * wolno, ale to jedyne, co wykrywa ciche przekłamanie bitów na leżącym
   * w szufladzie dysku.
   */
  function sprawdzMigawke(m, zSumami) {
    if (!m.spis || m.spis === "") {
      displayToast(qsTr("Ta migawka nie ma spisu — powstała przed tym mechanizmem."), "warning");
      return;
    }
    const r = SpisPlikow.sprawdz(m.sciezka + "/" + m.spis, m.sciezka, zSumami === true);
    if (r.blad !== undefined) {
      displayToast(r.blad, "error");
      return;
    }

    const l = [];
    l.push(qsTr("Migawka %1").arg(m.nazwa));
    l.push(qsTr("w spisie: %1, znalezionych: %2").arg(r.wSpisie).arg(r.sprawdzonych));
    if (r.brakuje.length > 0) {
      l.push(qsTr("⚠ BRAKUJE: %1").arg(r.brakuje.length));
      for (let i = 0; i < Math.min(r.brakuje.length, 10); i++)
        l.push("   − " + r.brakuje[i].sciezka);
    }
    if (r.innyRozmiar.length > 0)
      l.push(qsTr("⚠ inny rozmiar: %1").arg(r.innyRozmiar.length));
    if (r.innaSuma.length > 0) {
      l.push(qsTr("⚠ inna treść przy tym samym rozmiarze: %1").arg(r.innaSuma.length));
      for (let k = 0; k < Math.min(r.innaSuma.length, 8); k++)
        l.push("   ! " + r.innaSuma[k].sciezka);
    }
    if (r.ok)
      l.push(zSumami ? qsTr("Wszystko na miejscu, sumy się zgadzają.")
                     : qsTr("Wszystko na miejscu (nazwy i rozmiary)."));
    kopiaPanel.wynik = {
      "sprawdzenie": true,
      "ok": r.ok,
      "linie": l
    };
  }

  /**
   * Naprawa czasów w gotowej migawce.
   *
   * DLACZEGO TO W OGÓLE ISTNIEJE: `QFile::copy` nie zachowuje czasu pliku,
   * więc migawki zrobione przed poprawką z 24.08.2026 mają czasy z chwili
   * kopiowania. Warunek dowiązania porównuje rozmiar I czas — przy złych
   * czasach nie zgadza się nigdy i następna migawka przepisuje całe drzewo
   * od nowa. Przy 88 GB to półtorej godziny i drugie 88 GB na dysku.
   *
   * Naprawa czyta tylko metadane, nie treść — trwa kilkanaście sekund.
   * Baz, projektów i JSON-ów nie rusza: te potrafią zmienić się w miejscu
   * bez zmiany rozmiaru, a zmyślony czas zamroziłby w kopii nieaktualną
   * treść na zawsze. To ta sama ostrożność, co PODEJRZANE w spisie.
   */
  function napraw(m) {
    const r = KopieZapasowe.naprawCzasy(m.sciezka, kopiaPanel.korzen);
    if (r.blad !== undefined) {
      kopiaPanel.wynik = { "sprawdzenie": true, "ok": false, "linie": [r.blad] };
      return;
    }
    kopiaPanel.wynik = {
      "sprawdzenie": true,
      "ok": true,
      "linie": [qsTr("Migawka %1").arg(m.nazwa), r.opis]
    };
    kopiaPanel.odswiez();
  }

  /**
   * Czy wybrany zakres zaczyna na tym nośniku NOWY łańcuch migawek.
   *
   * Dowiązania idą tylko do migawki TEGO SAMEGO zakresu — inaczej migawka
   * „wszystko" po migawce „nieodtwarzalne" nie znalazłaby w niej podkładów
   * i przepisała kilkadziesiąt gigabajtów. To jest słuszne, ale niewidoczne:
   * przełączenie zakresu jednym kliknięciem zamienia kopię przyrostową
   * w pełną i nic o tym nie mówi.
   *
   * Piotr 24.08.2026 miał na nośniku dwie migawki „wszystko" i wybrany
   * zakres „nieodtwarzalne". Bez tego ostrzeżenia kolejne 63 GB poszłoby
   * pełną kopią, a wyglądałoby to na powrót starego błędu.
   */
  function nowyLancuch() {
    if (!nosnik || listaMigawek.length === 0)
      return false;
    for (let i = 0; i < listaMigawek.length; i++) {
      const m = listaMigawek[i];
      if (m.zakres === zakres && !m.przerwane)
        return false;
    }
    return true;
  }

  function kopiuj() {
    if (!nosnik)
      return;

    // Nazwa PRZED kopiowaniem: migawka zapisuje w KOPIA.json, na którym
    // nośniku powstała, więc nośnik musi mieć wtedy tożsamość.
    if (!nosnik.znany) {
      const nazwa = poleNazwy.text.trim();
      if (nazwa === "") {
        displayToast(qsTr("Nadaj nazwę temu nośnikowi."), "warning");
        poleNazwy.forceActiveFocus();
        return;
      }
      const s = KopieZapasowe.ostempluj(nosnik.sciezka, nazwa);
      if (!s.ok) {
        displayToast(s.blad, "error");
        return;
      }
      odswiez();
    }

    wynik = null;
    KopieZapasowe.wykonaj(korzen, zakres, nosniki[wybrany].sciezka);
  }

  Connections {
    target: KopieZapasowe

    function onSkonczone(w) {
      kopiaPanel.wynik = w;
      kopiaPanel.odswiez();
    }
  }

  /*
   * ROZMIAR OKNA JEST WLASNOSCIA CZLOWIEKA, NIE PROGRAMU.
   *
   * Piotr, 24.08.2026: „na desktopie jest trochę za wąskie". Bylo 580 px na
   * sztywno, bo tak wypadlo przy pierwszym rysowaniu na telefonie. Na monitorze
   * to jest okienko z tabelka scisnieta do trzech kolumn.
   *
   * Wiec: uchwyt w prawym dolnym rogu, a wybrany rozmiar zapamietany
   * w ustawieniach. Zapamietany, bo inaczej trzeba go ustawiac za kazdym
   * otwarciem, a to jest ta sama praca domowa, co „porownaj sobie z oryginalem".
   *
   * Ograniczenia: nie mniej niz 420 px (ponizej tabelka przestaje byc tabelka)
   * i nie wiecej niz okno aplikacji.
   */
  property int szerokoscWybrana: settings.valueInt("/WorkField/KopiaPanel/szerokosc", 580)
  property int wysokoscWybrana: settings.valueInt("/WorkField/KopiaPanel/wysokosc", 0)

  parent: mainWindow.contentItem
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  /*
   * OKNO NIGDY WEZSZE, NIZ WYMAGA JEGO ZAWARTOSC.
   *
   * 24.08.2026: tabela ma wieksza szerokosc minimalna niz 580 px, wiec
   * `RowLayout` nie dal sie scisnac i wiersze wyszly BOKIEM poza okno —
   * naglowki KONIEC/PLIKOW/STAN i przyciski rysowaly sie na mapie obok.
   * Layout nie zmniejszy sie ponizej sumy swoich minimow; jesli okno jest
   * wezsze, zawartosc po prostu wystaje, bo nic jej nie przycina.
   *
   * Wiec szerokosc bierze wieksza z dwoch: wybranej przez czlowieka i tej,
   * ktorej zada uklad. Gorna granica to okno aplikacji.
   */
  width: Math.min(Math.max(dostepna, ramka.implicitWidth + 10), mainWindow.width - 32)
  height: wysokoscWybrana > 0
          ? Math.min(Math.max(320, wysokoscWybrana), mainWindow.height - 80)
          : Math.min(implicitHeight, mainWindow.height - 80)

  /**
   * WorkField 24.08.2026 — W TRAKCIE KOPIOWANIA OKNO NIE ZAMYKA SIĘ SAMO.
   *
   * Piotr: „chyba niechcący coś przerwałem… aplikacja stoi, tylko zamknęło
   * się okno". Nie przerwał niczego — kopiowanie chodzi w osobnym wątku
   * i szło dalej. Okno zniknęło od Esc albo kliknięcia poza nim, bo `Popup`
   * ma to domyślnie włączone.
   *
   * Skutek był gorszy niż samo zniknięcie: siedemdziesięciominutowa robota
   * biegła BEZ ŻADNEGO ŚLADU na ekranie. Człowiek ma prawo sądzić, że stanęła.
   *
   * Więc: żadnego zamykania przypadkiem, dopóki kopia trwa. Wyjścia są dwa
   * i oba wyraźne — „Przerwij" zatrzymuje, „Zamknij" schodzi z drogi
   * i mówi wprost, że kopia leci dalej.
   */
  closePolicy: KopieZapasowe.pracuje ? Popup.NoAutoClose
                                     : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

  onOpened: {
    wynik = null;
    zaznaczona = -1;
    odswiez();
  }

  /*
   * JEDNO DZIECKO, NIE DWOJE — i to nie jest kosmetyka.
   *
   * `Popup` z JEDNYM zadeklarowanym dzieckiem robi z niego swoj contentItem
   * i bierze z niego implicitHeight. Z DWOJGIEM opakowuje je we wlasny, goly
   * `Item`, ktorego implicitHeight wynosi ZERO — a wtedy wysokosc okna spada
   * do samych marginesow.
   *
   * Dokladnie to stalo sie 24.08.2026, kiedy dolozylem uchwyt do rozciagania
   * jako drugie dziecko: tlo skurczylo sie do czarnego paska u gory, a cala
   * zawartosc wylala sie poza nie i pojechala po bialym tle aplikacji.
   * Wygladalo to na zepsute kolory, a bylo zepsute WYSOKOSCI.
   *
   * Wiec: jedno dziecko — ta oto ramka — ktore przekazuje rozmiary z ukladu
   * w gore. Uchwyt siedzi w niej obok ukladu i niczego nie liczy.
   */
  Item {
    id: ramka

    /*
     * ANCHORS.FILL JEST KONIECZNE. Popup NIE zastepuje swojego contentItem
     * zadeklarowanym dzieckiem — on je do niego WSTAWIA. Dziecko, ktore samo
     * sie nie rozciagnie, bierze rozmiar wyliczony z zawartosci zamiast
     * rozmiaru okna. Zmierzone 24.08.2026 (skrypty/proba_ukladu): w podgladzie
     * stylizacji dawalo to ramke 841x84 w oknie 760x640 i Flickable o zerowej
     * wysokosci — cala tabela znikala, choc byla ulozona na 971 pikseli.
     */
    anchors.fill: parent
    implicitWidth: uklad.implicitWidth
    implicitHeight: uklad.implicitHeight

  ColumnLayout {
    id: uklad

    anchors.fill: parent
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Kopia na nośnik")
      font: Theme.strongFont
      color: Theme.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Kopia jedzie ze spisem swojej zawartości — po pół roku da się sprawdzić, czy nośnik nadal ma to, co dostał, bez oryginału.")
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    // ---------------------------------------------------------- nośniki
    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      text: kopiaPanel.nosniki.length === 0
            ? qsTr("Nie widzę żadnego podpiętego nośnika. Podłącz pendrive i naciśnij „Odśwież”.")
            : qsTr("Podpięte nośniki:")
      font: Theme.tipFont
      color: kopiaPanel.nosniki.length === 0 ? Theme.warningColor : Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: kopiaPanel.nosniki

      ItemDelegate {
        required property int index
        required property var modelData

        Layout.fillWidth: true
        height: 46
        highlighted: kopiaPanel.wybrany === index

        background: Rectangle {
          color: kopiaPanel.wybrany === index
                 ? Qt.rgba(Theme.mainColor.r, Theme.mainColor.g, Theme.mainColor.b, 0.45)
                 : "transparent"
          radius: 4
        }

        contentItem: ColumnLayout {
          spacing: 0

          Text {
            Layout.fillWidth: true
            text: modelData.znany
                  ? modelData.nazwa
                  : qsTr("nowy nośnik — %1").arg(modelData.etykieta)
            font: Theme.strongTipFont
            color: modelData.znany ? Theme.mainTextColor : Theme.warningColor
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: qsTr("%1 · wolne %2 z %3 · migawek: %4")
                  .arg(modelData.system)
                  .arg(FileUtils.representFileSize(modelData.wolne))
                  .arg(FileUtils.representFileSize(modelData.pojemnosc))
                  .arg(modelData.migawek)
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
            elide: Text.ElideRight
          }
        }

        onClicked: {
          kopiaPanel.wybrany = index;
          kopiaPanel.zbadaj();
        }
      }
    }

    // ------------------------------------------------- nazwa nowego nośnika
    RowLayout {
      Layout.fillWidth: true
      visible: kopiaPanel.nosnik !== null && !kopiaPanel.nosnik.znany
      spacing: 6

      Text {
        text: qsTr("Nazwij go:")
        font: Theme.tipFont
        color: Theme.mainTextColor
      }
      TextField {
        id: poleNazwy
        Layout.fillWidth: true
        font: Theme.tipFont
        placeholderText: qsTr("np. USB biuro czerwony")
      }
    }

    // ------------------------------------------------------------- zakres
    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        text: qsTr("Zakres:")
        font: Theme.tipFont
        color: Theme.secondaryTextColor
      }
      Button {
        text: qsTr("nieodtwarzalne")
        font: Theme.tinyFont
        flat: kopiaPanel.zakres !== "dane"
        highlighted: kopiaPanel.zakres === "dane"
        onClicked: {
          kopiaPanel.zakres = "dane";
          kopiaPanel.zbadaj();
        }
      }
      Button {
        text: qsTr("wszystko")
        font: Theme.tinyFont
        flat: kopiaPanel.zakres !== "wszystko"
        highlighted: kopiaPanel.zakres === "wszystko"
        onClicked: {
          kopiaPanel.zakres = "wszystko";
          kopiaPanel.zbadaj();
        }
      }
      Item {
        Layout.fillWidth: true
      }

      /*
       * „WYKONAJ KOPIĘ", A NIE „KOPIUJ" — I PRZY ZAKRESIE, NIE NA DOLE.
       *
       * Piotr, 24.08.2026: „Kopiuj powinno umożliwiać skopiowanie danych
       * i informacji o kopii". Ma rację i to jest ostrzejsze, niż wyglada:
       * w kazdym innym oknie tej aplikacji „Kopiuj" znaczy „do schowka".
       * Ten jeden przycisk znaczyl „przepisz 88 GB na dysk zewnetrzny" —
       * to samo slowo, zupelnie inna waga, i zadnego sygnalu o roznicy.
       *
       * Stad: czasownik mowi, co robi, i stoi TAM, gdzie sie podejmuje
       * decyzje — obok zakresu, ktory wlasnie sie wybralo. Jasne tlo, bo to
       * jedyny przycisk w tym oknie, ktory cos pisze na cudzym dysku.
       */
      Button {
        id: przyciskWykonaj

        text: qsTr("Wykonaj kopię")
        font: Theme.strongTipFont
        enabled: !KopieZapasowe.pracuje && kopiaPanel.nosnik !== null
        Layout.preferredHeight: 34

        background: Rectangle {
          radius: 4
          color: !przyciskWykonaj.enabled ? Theme.controlBackgroundDisabledColor
                 : przyciskWykonaj.pressed ? Qt.darker(Theme.mainColor, 1.2)
                 : Theme.mainColor
          border.width: 1
          border.color: przyciskWykonaj.enabled ? Qt.lighter(Theme.mainColor, 1.4) : "transparent"
        }
        contentItem: Text {
          text: przyciskWykonaj.text
          font: przyciskWykonaj.font
          color: przyciskWykonaj.enabled ? Theme.mainOverlayColor : Theme.mainTextDisabledColor
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          leftPadding: 10
          rightPadding: 10
        }

        onClicked: kopiaPanel.kopiuj()
      }

      Button {
        text: qsTr("Odśwież")
        font: Theme.tinyFont
        flat: true
        onClicked: kopiaPanel.odswiez()
      }
    }

    // -------------------------------------------------------- rozpoznanie
    Text {
      Layout.fillWidth: true
      visible: kopiaPanel.rozpoznanie !== null
      text: {
        const r = kopiaPanel.rozpoznanie;
        if (!r)
          return "";
        let s = qsTr("Do skopiowania: %1 plików, %2. Wolne na nośniku: %3.")
                .arg(r.plikow)
                .arg(FileUtils.representFileSize(r.bajtow))
                .arg(FileUtils.representFileSize(r.wolne));
        if (!r.zmiesciSie)
          s += "\n" + qsTr("⚠ To się nie zmieści.");
        // Dziennik obok bazy znaczy „ktoś ją ma otwartą”. Mówimy o tym PRZED
        // kopiowaniem, żeby dało się zamknąć QGIS-a, a nie po fakcie.
        if (r.otwarteBazy.length > 0)
          s += "\n" + qsTr("⚠ Otwarte bazy (zostaną pominięte): %1").arg(r.otwarteBazy.join(", "));
        // Tekst sklejany PLUSEM, a nie sąsiedztwem. W C++ dwa literały obok
        // siebie łączą się same; w JavaScripcie to błąd składni — i właśnie
        // tak wyłożył się tu build 24.08.2026. To samo miejsce w pliku .cpp
        // byłoby poprawne, więc odruch przenosi się niezauważony.
        if (kopiaPanel.nowyLancuch())
          s += "\n" + qsTr("⚠ Na tym nośniku nie ma jeszcze kompletnej migawki o zakresie „%1”. Ta kopia pójdzie w całości — dowiązywać się nie ma do czego. Migawki innego zakresu, które tu leżą, nie zostaną użyte.")
                        .arg(kopiaPanel.zakres === "dane" ? qsTr("nieodtwarzalne") : qsTr("wszystko"));
        return s;
      }
      font: Theme.tinyFont
      color: kopiaPanel.rozpoznanie && (!kopiaPanel.rozpoznanie.zmiesciSie
                                        || kopiaPanel.rozpoznanie.otwarteBazy.length > 0
                                        || kopiaPanel.nowyLancuch())
             ? Theme.warningColor
             : Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    // -------------------------------------------------- migawki na nośniku
    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      visible: kopiaPanel.listaMigawek.length > 0
      text: qsTr("Migawki na tym nośniku (%1) — zaznacz wiersz, żeby działać na nim przyciskami poniżej:").arg(kopiaPanel.listaMigawek.length)
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    /*
     * TABELA, A NIE LISTA AKAPITÓW — prośba Piotra: „lista kopii w postaci
     * takiej tabeli danych jak Warstwy: zakres, data, itp.".
     *
     * Ma to jeden konkretny skutek poza wyglądem: liczby stoją w kolumnach,
     * więc `dowiązanych: 0` w trzech wierszach z rzędu widać jako wzór,
     * a nie trzeba go szukać w trzech różnych zdaniach. To pytanie, które
     * zadawaliśmy sobie dziś przez pół dnia.
     *
     * Kolumna pierwsza to DATA I GODZINA Z NAZWY KATALOGU, nie czas
     * zakończenia. Migawka zaczęta o 8:47 skończyła się o 12:41 i nazywa się
     * snap_2026-08-24_0847_wszystko — Piotr szukał jej pod „12:41" i nie
     * znalazł. Godzina zakończenia ma własną kolumnę.
     *
     * Przy wąskim oknie kolumny „zakres" i „danych" znikają: zakres i tak
     * siedzi w nazwie, a nazwa jest w podglądzie pod tabelą.
     */
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: naglowekTabeli.height + listaMig.height + 2
      // Rectangle sam z siebie ma implicitWidth ZERO, wiec uklad nie wiedzialby,
      // ze mieszka w nim tabela o twardych minimach kolumn — i tabela wyszlaby
      // bokiem poza okno. Suma kolumn: 412 w trybie waskim, 582 w szerokim,
      // plus marginesy.
      Layout.minimumWidth: kopiaPanel.szeroko ? 600 : 430
      visible: kopiaPanel.listaMigawek.length > 0
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.12)
      radius: 4
      clip: true

      Column {
        anchors.fill: parent
        anchors.margins: 1

        Rectangle {
          id: naglowekTabeli

          width: parent.width
          height: 24
          color: Qt.rgba(1, 1, 1, 0.07)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Text {
              Layout.fillWidth: true
              Layout.minimumWidth: 110
              text: qsTr("MIGAWKA")
              font: Theme.tinyFont
              color: Theme.secondaryTextColor
            }
            Text {
              Layout.preferredWidth: 100
              visible: kopiaPanel.szeroko
              text: qsTr("ZAKRES")
              font: Theme.tinyFont
              color: Theme.secondaryTextColor
            }
            Text {
              Layout.preferredWidth: 48
              horizontalAlignment: Text.AlignRight
              text: qsTr("KONIEC")
              font: Theme.tinyFont
              color: Theme.secondaryTextColor
            }
            Text {
              Layout.preferredWidth: 58
              horizontalAlignment: Text.AlignRight
              text: qsTr("PLIKÓW")
              font: Theme.tinyFont
              color: Theme.secondaryTextColor
            }
            Text {
              Layout.preferredWidth: 78
              horizontalAlignment: Text.AlignRight
              text: qsTr("DOWIĄZANYCH")
              font: Theme.tinyFont
              color: Theme.secondaryTextColor
              elide: Text.ElideRight
            }
            Text {
              Layout.preferredWidth: 70
              visible: kopiaPanel.szeroko
              horizontalAlignment: Text.AlignRight
              text: qsTr("DANYCH")
              font: Theme.tinyFont
              color: Theme.secondaryTextColor
            }
            Text {
              Layout.preferredWidth: 70
              horizontalAlignment: Text.AlignRight
              text: qsTr("STAN")
              font: Theme.tinyFont
              color: Theme.secondaryTextColor
            }
          }
        }

        ListView {
          id: listaMig

          width: parent.width
          height: Math.min(contentHeight, kopiaPanel.wysokoscWybrana > 0 ? 8 * 26 : 4 * 26)
          clip: true
          model: kopiaPanel.listaMigawek

          delegate: ItemDelegate {
            required property int index
            required property var modelData

            width: listaMig.width
            height: 26

            background: Rectangle {
              color: kopiaPanel.zaznaczona === index
                     ? Qt.rgba(Theme.mainColor.r, Theme.mainColor.g, Theme.mainColor.b, 0.45)
                     : (index % 2 ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
            }

            contentItem: RowLayout {
              spacing: 8

              Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 110
                text: kopiaPanel.etykietaMigawki(modelData)
                font: Theme.tipFont
                color: modelData.przerwane ? Theme.warningColor : Theme.mainTextColor
                elide: Text.ElideRight
              }
              Text {
                Layout.preferredWidth: 100
                visible: kopiaPanel.szeroko
                text: modelData.zakres === "dane" ? qsTr("nieodtwarzalne") : qsTr("wszystko")
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
                elide: Text.ElideRight
              }
              Text {
                Layout.preferredWidth: 48
                horizontalAlignment: Text.AlignRight
                text: String(modelData.data).slice(11, 16)
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
              }
              Text {
                Layout.preferredWidth: 58
                horizontalAlignment: Text.AlignRight
                text: modelData.plikow
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
              }
              Text {
                Layout.preferredWidth: 78
                horizontalAlignment: Text.AlignRight
                text: modelData.dowiazanych
                font: Theme.tinyFont
                // Zero dowiązań w migawce, która MIAŁA do czego się dowiązać,
                // to jedyna liczba w tej tabeli warta koloru.
                color: modelData.dowiazanych === 0 && index < kopiaPanel.listaMigawek.length - 1
                       ? Theme.warningColor
                       : Theme.secondaryTextColor
              }
              Text {
                Layout.preferredWidth: 70
                visible: kopiaPanel.szeroko
                horizontalAlignment: Text.AlignRight
                text: FileUtils.representFileSize(modelData.bajtow)
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
              }
              Text {
                Layout.preferredWidth: 70
                horizontalAlignment: Text.AlignRight
                text: modelData.przerwane ? qsTr("przerwana")
                      : modelData.bledow > 0 ? qsTr("błędów: %1").arg(modelData.bledow)
                      : qsTr("ok")
                font: Theme.tinyFont
                color: modelData.przerwane || modelData.bledow > 0
                       ? Theme.warningColor
                       : Theme.secondaryTextColor
                elide: Text.ElideRight
              }
            }

            onClicked: kopiaPanel.zaznaczona = index
            onDoubleClicked: kopiaPanel.sprawdzMigawke(modelData, false)
          }
        }
      }
    }

    // ---------------------------------------- co można zrobić z zaznaczoną
    //
    // Przyciski zamiast dotknięcia i przytrzymania. Ukryta akcja to akcja,
    // której nie ma: „przytrzymaj, żeby policzyć sumy" stało w napisie nad
    // listą i nikt tego nie robił, bo nic na ekranie o tym nie przypominało.
    RowLayout {
      Layout.fillWidth: true
      visible: kopiaPanel.listaMigawek.length > 0
      spacing: 6

      Text {
        text: kopiaPanel.migawka ? kopiaPanel.migawka.nazwa : qsTr("nie zaznaczono migawki")
        font: Theme.tinyFont
        color: kopiaPanel.migawka ? Theme.mainTextColor : Theme.secondaryTextColor
        elide: Text.ElideMiddle
        Layout.fillWidth: true
        // Bez tego pelna szerokosc napisu staje sie minimum calego wiersza
        // i przyciski obok wyjezdzaja poza okno.
        Layout.minimumWidth: 0
      }
      Button {
        text: qsTr("Sprawdź")
        font: Theme.tinyFont
        flat: true
        enabled: kopiaPanel.migawka !== null && !KopieZapasowe.pracuje
        onClicked: kopiaPanel.sprawdzMigawke(kopiaPanel.migawka, false)
      }
      Button {
        text: qsTr("…z sumami")
        font: Theme.tinyFont
        flat: true
        enabled: kopiaPanel.migawka !== null && !KopieZapasowe.pracuje
        onClicked: kopiaPanel.sprawdzMigawke(kopiaPanel.migawka, true)
      }
      Button {
        text: qsTr("Napraw czasy")
        font: Theme.tinyFont
        flat: true
        enabled: kopiaPanel.migawka !== null && !KopieZapasowe.pracuje
                 && kopiaPanel.migawka.dowiazanych === 0
        onClicked: kopiaPanel.napraw(kopiaPanel.migawka)
      }
      Button {
        text: qsTr("Kopiuj")
        font: Theme.tinyFont
        flat: true
        onClicked: kopiaPanel.doSchowka()
      }
    }

    // ------------------------------------------------------------ postęp
    ColumnLayout {
      Layout.fillWidth: true
      visible: KopieZapasowe.pracuje
      spacing: 2

      ProgressBar {
        Layout.fillWidth: true
        from: 0
        to: 100
        value: KopieZapasowe.postep
      }
      Text {
        Layout.fillWidth: true
        text: KopieZapasowe.etap
        font: Theme.tinyFont
        color: Theme.secondaryTextColor
      }
    }

    // ------------------------------------------------------------- wynik
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: tekstWyniku.implicitHeight + 12
      Layout.maximumHeight: 180
      visible: kopiaPanel.wynik !== null
      color: Qt.rgba(0, 0, 0, 0.18)
      radius: 4
      clip: true

      ScrollView {
        anchors.fill: parent
        anchors.margins: 6
        clip: true

        Text {
          id: tekstWyniku
          width: parent.width
          font: Theme.tinyFont
          wrapMode: Text.WordWrap
          color: kopiaPanel.wynik && kopiaPanel.wynik.ok ? Theme.mainTextColor : Theme.warningColor
          text: {
            const w = kopiaPanel.wynik;
            if (!w)
              return "";
            if (w.sprawdzenie === true)
              return w.linie.join("\n");
            if (w.blad !== undefined)
              return w.blad;

            const l = [];
            l.push(w.przerwane
                   ? qsTr("PRZERWANE — migawka jest niepełna.")
                   : qsTr("Kopia na „%1”").arg(w.nazwaNosnika));
            l.push(qsTr("plików: %1, skopiowanych: %2, dowiązanych: %3, pominiętych: %4")
                   .arg(w.plikow).arg(w.skopiowanych).arg(w.dowiazanych).arg(w.pominietych));
            l.push(qsTr("baz sprawdzonych (quick_check): %1").arg(w.bazySprawdzone));
            l.push(qsTr("czas: %1").arg(w.czas));

            // Bez twardych dowiązań KAŻDA migawka jest pełną kopią. Przy
            // drzewie kilkudziesięciogigabajtowym to różnica między „dysk
            // starczy na rok” a „dysk starczy na tydzień” — i człowiek ma
            // prawo dowiedzieć się tego teraz, a nie gdy dysk się zapełni.
            // Zdanie po polsku, dlaczego dowiązań było tyle, ile było.
            // 24.08.2026 Piotr zobaczył trzy pełne migawki i musiał zgadywać,
            // co jest nie tak; silnik wie to dokładnie i teraz mówi.
            if (w.dowiazaniaPowod !== undefined && w.dowiazaniaPowod !== "") {
              l.push("");
              l.push(w.dowiazaniaPowod);
            } else if (!w.dowiazaniaDzialaja) {
              l.push(qsTr("⚠ Ten nośnik nie obsługuje twardych dowiązań — każda migawka będzie pełną kopią."));
            }

            if (w.bledy.length > 0) {
              l.push("");
              for (let i = 0; i < Math.min(w.bledy.length, 12); i++)
                l.push("⚠ " + w.bledy[i]);
              if (w.bledy.length > 12)
                l.push(qsTr("… i jeszcze %1").arg(w.bledy.length - 12));
            }
            l.push("");
            l.push(w.migawka);
            return l.join("\n");
          }
        }
      }
    }

    // ------------------------------------------------------------ przyciski
    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Button {
        text: qsTr("Przerwij")
        font: Theme.tinyFont
        flat: true
        visible: KopieZapasowe.pracuje
        onClicked: KopieZapasowe.przerwij()
      }
      Item {
        Layout.fillWidth: true
      }
      Button {
        flat: true
        // W trakcie kopiowania zamkniecie jest dozwolone, ale etykieta musi
        // powiedziec, co sie stanie. Przycisk, ktory nie mowi, czy zatrzymuje
        // robote, jest gorszy od przycisku wygaszonego.
        text: KopieZapasowe.pracuje ? qsTr("Zamknij (kopia leci dalej)") : qsTr("Zamknij")
        font: Theme.tipFont
        onClicked: kopiaPanel.close()
      }
    }
  }

  // ------------------------------------------------- uchwyt do rozciągania
  //
  // Leży NA zawartości, w rogu, poza układem — dlatego nie ma go w
  // ColumnLayout. Rysuje trzy kreski, bo nienarysowany uchwyt jest tym samym,
  // co jego brak: nikt nie zgadnie, że można ciągnąć za róg.
  Item {
    id: uchwyt

    width: 18
    height: 18
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 2

    Canvas {
      anchors.fill: parent
      onPaint: {
        const k = getContext("2d");
        k.clearRect(0, 0, width, height);
        k.strokeStyle = Theme.secondaryTextColor;
        k.lineWidth = 1.5;
        for (let i = 1; i <= 3; i++) {
          const d = i * 4;
          k.beginPath();
          k.moveTo(width - d, height - 1);
          k.lineTo(width - 1, height - d);
          k.stroke();
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.SizeFDiagCursor

      /*
       * MIERZYMY OD PUNKTU CHWYTU, W UKLADZIE SCENY — nie od biezacych
       * wspolrzednych uchwytu.
       *
       * Uchwyt jest przyklejony do rogu okna, wiec kiedy okno rosnie, uchwyt
       * ucieka spod myszy i jego lokalne `mysz.x` maleje. Liczenie przyrostu
       * z lokalnych wspolrzednych daje sprzezenie zwrotne: okno ciagnie samo
       * siebie. Dlatego zapamietujemy POZYCJE SCENY w chwili nacisniecia
       * i rozmiar wyjsciowy, a potem tylko dodajemy roznice.
       *
       * Razy dwa, bo okno jest wysrodkowane: przy wzroscie o D prawa krawedz
       * przesuwa sie tylko o D/2. Bez tej dwojki mysz ucieka przed rogiem.
       */
      property real odX: 0
      property real odY: 0
      property real odSzer: 0
      property real odWys: 0

      onPressed: mysz => {
        const p = mapToItem(kopiaPanel.parent, mysz.x, mysz.y);
        odX = p.x;
        odY = p.y;
        odSzer = kopiaPanel.width;
        odWys = kopiaPanel.height;
        // Wysokość do tej pory mogła być liczona automatycznie. Od pierwszego
        // chwytu jest już wybrana ręcznie, więc trzeba ją najpierw utrwalić —
        // inaczej okno skoczyłoby do implicitHeight w chwili złapania.
        if (kopiaPanel.wysokoscWybrana <= 0)
          kopiaPanel.wysokoscWybrana = kopiaPanel.height;
      }

      onPositionChanged: mysz => {
        if (!pressed)
          return;
        const p = mapToItem(kopiaPanel.parent, mysz.x, mysz.y);
        kopiaPanel.szerokoscWybrana = Math.max(420, odSzer + 2 * (p.x - odX));
        kopiaPanel.wysokoscWybrana = Math.max(320, odWys + 2 * (p.y - odY));
      }

      onReleased: {
        settings.setValue("/WorkField/KopiaPanel/szerokosc", kopiaPanel.szerokoscWybrana);
        settings.setValue("/WorkField/KopiaPanel/wysokosc", kopiaPanel.wysokoscWybrana);
      }

      // Dwuklik wraca do rozmiaru wyliczanego z zawartości — droga powrotna
      // dla kogoś, kto rozciągnął okno za daleko i nie umie trafić z powrotem.
      onDoubleClicked: {
        kopiaPanel.szerokoscWybrana = 580;
        kopiaPanel.wysokoscWybrana = 0;
        settings.setValue("/WorkField/KopiaPanel/szerokosc", 580);
        settings.setValue("/WorkField/KopiaPanel/wysokosc", 0);
      }
    }
  }
  }
}
