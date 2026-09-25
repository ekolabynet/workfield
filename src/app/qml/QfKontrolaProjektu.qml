/***************************************************************************
  QfKontrolaProjektu.qml - kontrola projektu przy otwarciu

 ---------------------
 WorkField: przy każdym otwarciu projektu sprawdza, czego mu brakuje,
 i mówi o tym GŁOŚNO — zanim ktokolwiek tego potrzebuje.

 Powód. 17.08.2026 wyjazd w teren skończył się powrotem do biura, bo żaden
 szablon nie miał kompletu ulepszeń. Wniosek Piotra: „niezrealizowane
 funkcjonalności są niebezpieczne — myślimy, że są, a ich nie ma".
 Brakująca warstwa albo brakujący plik słownika nie dają żadnego objawu:
 panel wygląda normalnie i milczy. Ten komponent zamienia ciszę w zdanie.

 ======================================================================
 JEDNO ŹRÓDŁO PRAWDY — 23.09.2026
 ======================================================================
 Do dziś ten plik miał WŁASNĄ listę braków: sprawdzał warstwę tyczenia
 i plik kafli po swojemu, ręcznie. Obok tego istniał katalog wyposażenia
 ze stemplem w bazie — i dwie listy zaczęły się rozjeżdżać. Kontrola mówiła
 „brak definicji kafli paska" przy pliku, który Wyposażenie uznawało za
 dobry, bo patrzyły na co innego: jedna na obecność pliku, druga na jego
 zawartość i wersję modułu.

 Od dziś strukturę zna WYŁĄCZNIE katalog. Ten komponent go pyta i tłumaczy
 odpowiedź na jedno zdanie do dymka. Nowy moduł w katalogu pojawia się tu
 sam, bez dopisywania czegokolwiek.

 ZOSTAJE JEDEN WŁASNY SPRAWDZIAN: słownik gatunków. To nie struktura, tylko
 TREŚĆ — żaden katalog jej nie opisze i żaden kod nie wymyśli. Musi
 przyjechać z sieci.

 ETAP 1 — TYLKO CZYTA. Niczego nie zakłada i niczego nie zmienia.
 Zakładanie mieszka w Wyposażeniu, gdzie jest kopia zapasowa i widać wynik.

 Patrz docs/WYPOSAZENIE.md i docs/CZASOWNIKI_TERENOWE.md.
 ***************************************************************************/

import QtQuick
import org.qfield
import org.qfield.core
import org.qgis
// PLAKIETKA KONTROLI (25.09.2026) — kolor ostrzeżenia i rozmiar
// przycisku biorą się z motywu, żeby plakietka była tej samej
// wielkości co reszta ikon i bladła razem z ciemnym motywem.
import Theme

Item {
  id: kontrola

  //! Czego brakuje — lista map { rzecz, opis, waga: "brak" | "uwaga" }
  property var braki: []

  /**
   * Okno, do którego prowadzi przycisk w dymku.
   *
   * Do 23.09.2026 prowadził do QfNaprawaProjektu — ekranu, który robił
   * kafle po swojemu (nadpisując cały plik i dając dwóm warstwom tę samą
   * etykietę). Dziś prowadzi do Wyposażenia, bo tam siedzą czasowniki.
   *
   * Wołamy `otworz()`, jeżeli okno je ma: Wyposażenie musi odświeżyć listę
   * PRZED pokazaniem się, inaczej wstaje puste.
   */
  property var ekranDocelowy: null

  //! Błędy w DANYCH — inna kategoria i inne okno niż braki wyposażenia.
  //! Liczone z `NarzedziaProjektu.stanProjektu()`, filtr `rodzaj === "dane"`.
  property var bledyDanych: []

  //! Czy ostatnia kontrola cokolwiek znalazła
  readonly property bool czysto: braki.length === 0 && bledyDanych.length === 0

  signal sprawdzono(var braki)

  //! Ten sam katalog modułów, który widzi okno Wyposażenia.
  Wyposazenie {
    id: wyposazenie
  }

  function katalogProjektu() {
    return qgisProject ? qgisProject.homePath : "";
  }

  /**
   * Sprawdza aktualnie wczytany projekt. Same odczyty — bezpieczne
   * do wywołania kiedykolwiek i ile razy się chce.
   */
  function sprawdz() {

    const katalog = katalogProjektu();
    const znalezione = [];

    if (katalog === "") {
      kontrola.braki = [];
      kontrola.bledyDanych = [];
      return [];
    }

    // Błędy w danych: osobna lista, bo prowadzą do osobnego okna.
    let bd = [];
    try {
      const st = NarzedziaProjektu.stanProjektu(qgisProject);
      const wszystkie = (st && st.ostrzezenia) ? st.ostrzezenia : [];
      for (let k = 0; k < wszystkie.length; k++)
        if (wszystkie[k].rodzaj === "dane")
          bd.push(wszystkie[k]);
    } catch (e) {
      bd = [];
    }
    kontrola.bledyDanych = bd;

    // ── struktura: pytamy KATALOG, nie własną listę ─────────────
    const stan = wyposazenie.sprawdz(qgisProject);
    for (let i = 0; i < stan.length; i++) {
      const m = stan[i];
      if (m.stan === "brak") {
        znalezione.push({ "rzecz": m.modul, "opis": m.nazwa, "waga": "brak" });
      } else if (m.stan === "starszy") {
        znalezione.push({
          "rzecz": m.modul,
          "opis": qsTr("%1 — starsza wersja").arg(m.nazwa),
          "waga": "brak"
        });
      } else if (m.stan === "nowszy") {
        // Znaczy coś ODWROTNEGO niż reszta: projekt zrobiono nowszą
        // aplikacją. „Dołóż moduł" byłoby tu radą złą.
        znalezione.push({
          "rzecz": m.modul,
          "opis": qsTr("%1 — TO APLIKACJA JEST STARSZA niż projekt").arg(m.nazwa),
          "waga": "uwaga"
        });
      }
    }

    // ── słownik gatunków i wskaźniki ───────────────────────────
    // Tego aplikacja NIE wymyśli — to wiedza, nie struktura. Bez pliku
    // panel metatagów wygląda normalnie i nic nie podpowiada
    // (phototagstore.cpp: szuka wf_wskazniki.gpkg obok projektu).
    // Pobieranie siedzi w Wyposażeniu, żeby dymek miał JEDEN cel.
    if (!FileUtils.fileExists(katalog + "/wf_wskazniki.gpkg")) {
      znalezione.push({
        "rzecz": "wskazniki",
        "opis": qsTr("słownik gatunków — podpowiadanie nie zadziała"),
        "waga": "brak"
      });
    }

    kontrola.braki = znalezione;
    kontrola.sprawdzono(znalezione);
    return znalezione;
  }

  /**
   * Treść dymka: nagłówek, ciało z NAGŁÓWKAMI SEKCJI i odsyłacze.
   *
   * Do 23.09.2026 było to jedno zdanie ciągiem. Ale dymek mówi o dwóch
   * różnych rzeczach — czego projektowi brakuje i co jest zepsute
   * w danych — które naprawia się w dwóch różnych oknach. Jedno zdanie
   * z jednym przyciskiem musiało zgadywać, do którego prowadzić.
   *
   * Zwraca `null`, gdy nie ma o czym mówić.
   */
  function trescDymka() {
    const brakujace = braki.filter(b => b.waga === "brak");
    const uwagi = braki.filter(b => b.waga === "uwaga");
    const bledy = bledyDanych;

    if (brakujace.length === 0 && uwagi.length === 0 && bledy.length === 0)
      return null;

    const linie = [];
    // Kolejność: najpierw to, co mówi o STRACONEJ pracy, potem o pracy,
    // która się nie uda.
    if (bledy.length > 0) {
      linie.push(qsTr("BŁĘDY W DANYCH · %1").arg(bledy.length));
      linie.push("   " + bledy[0].opis);
      if (bledy.length > 1)
        linie.push(qsTr("   …i jeszcze %1").arg(bledy.length - 1));
    }
    if (brakujace.length > 0) {
      linie.push(qsTr("USTAWIENIA · %1").arg(brakujace.length));
      linie.push("   " + brakujace.map(b => b.opis).join(", "));
    }
    // „Aplikacja starsza niż projekt" znaczy coś odwrotnego niż reszta
    // i nie prowadzi do żadnego z tych dwóch okien — sama linijka.
    for (let i = 0; i < uwagi.length; i++)
      linie.push("· " + uwagi[i].opis);

    return {
      "naglowek": bledy.length > 0
                    ? qsTr("Ten projekt ma błędy w danych")
                    : qsTr("Ten projekt nie jest gotowy do pracy"),
      "tekst": linie.join("\n"),
      "maUstawienia": brakujace.length > 0,
      "maBledy": bledy.length > 0
    };
  }

  //! Zostaje dla zgodności — pyta o to samo, zwraca jedno zdanie.
  function podsumowanie() {
    const tr2 = trescDymka();
    return tr2 === null ? "" : tr2.tekst.replace(/\n/g, " ");
  }

  Connections {
    target: iface

    function onLoadProjectEnded(path, name) {
      // Wzorzec szablonu pomijamy — on z założenia bywa niekompletny.
      if (path.indexOf("/templates/") !== -1 || path.indexOf("/szablony/") !== -1)
        return;

      // Po wczytaniu warstwy dochodzą jeszcze przez chwilę; pytamy po nich.
      opozniona.restart();
    }
  }

  // ── PLAKIETKA W PRAWYM GÓRNYM ROGU (25.09.2026) ─────────────────
  //
  // Komunikat mówi swoje raz; potem zostaje ślad, który nie zasłania
  // mapy i nie wymaga zamykania. Kliknięcie pokazuje to samo zdanie
  // na żądanie — także wtedy, gdy odcisk jest już znany.
  //
  // Ta klasa była dotąd niewidoczna (`Item` bez rozmiaru). Rozciąga
  // się na rodzica WYŁĄCZNIE po to, żeby mieć do czego przyczepić
  // plakietkę; nic nie rysuje i nie łapie myszy poza nią samą.
  anchors.fill: parent

  //! Ustawiane na czas pokazania komunikatu z kliknięcia plakietki.
  property bool naZadanie: false

  //! Odcisk treści — po nim poznajemy, czy to JUŻ BYŁO powiedziane.
  function odcisk(tresc) {
    return tresc === null ? "" : (tresc.naglowek + "|" + tresc.tekst);
  }

  Rectangle {
    id: plakietka

    // ── ODSTĘP OD GÓRNEJ BELKI (poprawka 25.09.2026) ──────────────
    //
    // Zgłoszenie Piotra z telefonu: plakietka „chowa się za paskiem
    // stanu (pod zębatką)”. Było `8 + mainWindow.sceneTopMargin`.
    //
    // Podejrzewałem najpierw, że `mainWindow` jest w tym pliku
    // niewidoczne i że strażnik `typeof` po cichu bierze zero.
    // SPRAWDZONE W qmltestrunner I NIEPRAWDA: komponent z osobnego
    // pliku widzi identyfikator dokumentu, w którym go osadzono —
    // nazwy schodzą w dół przez łańcuch kontekstów. Dlatego 103 pliki
    // QML w tym drzewie mogą pisać `mainWindow.` i to działa.
    //
    // Prawdziwy powód: `sceneTopMargin` to ZŁA liczba. Na Androidzie
    // okno ma `ExpandedClientAreaHint`, więc mapa sięga POD górną
    // belkę — `sceneTopMargin` mówi o wcięciu na pasek stanu, a nie
    // o wysokości tego, co nad mapą naprawdę leży.
    //
    // ── W JEDNYM RZĘDZIE Z LUPĄ (25.09.2026, druga runda) ─────────
    //
    // Formuła jest ta sama, co w `QfLocatorItem` i `mainMenuBar`;
    // różni je tylko odstęp, czyli RZĄD:
    //
    //   +4  — pierwszy rząd, tuż pod belką: `mainMenuBar` (hamburger)
    //   +40 — drugi rząd: `QfLocatorItem` (lupa)
    //
    // Plakietka dostała najpierw +4 i dotykała dolnej krawędzi belki
    // (zgłoszenie Piotra: „zawadza o dolną belkę (...) Jak ikona
    // wyszukiwania”). Idzie więc do drugiego rzędu — dokładnie na
    // wysokość lupy, tylko przy prawej krawędzi.
    //
    // Równanie do czegoś, co już jest na ekranie, bije dobieranie
    // liczby na oko: gdy belka urośnie o wiersz, oba przesuną się
    // razem.
    anchors.top: parent ? parent.top : undefined
    anchors.right: parent ? parent.right : undefined
    anchors.topMargin: (mainWindow.header ? mainWindow.header.height
                                          : mainWindow.sceneTopMargin) + 40
    anchors.rightMargin: mainWindow.sceneRightMargin + 4

    width: Theme.toolButtonSize
    height: Theme.toolButtonSize
    radius: width / 2
    color: Theme.warningColor
    visible: !kontrola.czysto
    opacity: obszarPlakietki.pressed ? 0.7 : 1.0

    Image {
      id: znakPlakietki
      anchors.centerIn: parent
      width: parent.width * 0.55
      height: width
      fillMode: Image.PreserveAspectFit
      sourceSize.width: width
      sourceSize.height: width
      source: Theme.getThemeVectorIcon("ic_alert_black_24dp")
    }

    // Gdyby ikony zabrakło, plakietka nie może zostać pustym kółkiem.
    Text {
      anchors.centerIn: parent
      visible: znakPlakietki.status !== Image.Ready
      text: "!"
      color: "black"
      font.bold: true
      font.pixelSize: parent.height * 0.6
    }

    MouseArea {
      id: obszarPlakietki
      anchors.fill: parent
      onClicked: {
        kontrola.naZadanie = true;
        opozniona.triggered();
      }
    }
  }

  Timer {
    id: opozniona
    interval: 1500
    repeat: false
    onTriggered: {
      kontrola.sprawdz();
      const tresc = kontrola.trescDymka();
      if (tresc === null)
        return;

      // ── TYLKO ZA PIERWSZYM RAZEM (25.09.2026) ─────────────────
      //
      // Uwaga Piotra: „ostrzeżenie jest IRYTUJĄCE, bo pojawia się za
      // każdym razem”. Trwały dymek witał człowieka przy KAŻDYM
      // otwarciu tego samego projektu — a szum uczy przeklikiwać bez
      // czytania, czyli odbiera tej kontroli jedyny powód istnienia.
      //
      // Pamiętamy ODCISK treści, nie sam fakt pokazania. Gdyby pamiętać
      // fakt, to projekt, któremu w międzyczasie UBYŁO czegoś jeszcze,
      // milczałby dalej — a to jest dokładnie ta sytuacja, dla której
      // ta kontrola powstała.
      //
      // Odcisk jest osobny dla każdego projektu (klucz zawiera jego
      // katalog), więc nowy projekt zawsze przedstawia się w całości.
      const odcisk = kontrola.odcisk(tresc);
      const kluczOdcisku = 'WorkField/kontrolaOdcisk/' + kontrola.katalogProjektu();
      if (!kontrola.naZadanie && settings.value(kluczOdcisku, '') === odcisk)
        return;
      kontrola.naZadanie = false;
      settings.setValue(kluczOdcisku, odcisk);

      // Komunikat, którego da się posłuchać: od razu prowadzi tam, gdzie
      // są czasowniki.
      //
      // DYMEK TRWAŁY, nie zwykły. Ten jeden wymienia po nazwie wszystko,
      // czego projektowi brakuje — bywa, że trzy rzeczy. Pięć sekund nie
      // wystarcza, żeby to przeczytać w rękawicach i w słońcu, a drugi raz
      // komunikat nie przyjdzie: leci raz, półtorej sekundy po wczytaniu.
      // Zwykłe dymki gasną dalej same — patrz QfToast.pokazTrwaly().
      const akcje = [];
      if (tresc.maUstawienia && kontrola.ekranDocelowy) {
        akcje.push({
          "etykieta": qsTr("USTAWIENIA"),
          "akcja": function () {
            if (typeof kontrola.ekranDocelowy.otworz === "function")
              kontrola.ekranDocelowy.otworz();
            else
              kontrola.ekranDocelowy.open();
          }
        });
      }
      if (tresc.maBledy) {
        // Ten sam czasownik, którego używa szuflada („Stan projektu”).
        // Identyfikatory z QgisMobileapp.qml nie są tu widoczne, więc
        // pytamy o rejestr akcji i sprawdzamy, czy jest.
        akcje.push({
          "etykieta": qsTr("BŁĘDY"),
          "akcja": function () {
            if (typeof wfAkcje !== 'undefined' && wfAkcje.stanProjektu)
              wfAkcje.stanProjektu();
          }
        });
      }

      // Zapasowe wywołanie na wypadek starszej aplikacji bez `pokazTrwaly`:
      // lepszy dymek gasnący niż brak dymka i błąd w dzienniku.
      if (typeof displayToastTrwaly === "function") {
        displayToastTrwaly(tresc.naglowek, tresc.tekst, "warning", akcje);
      } else {
        displayToast(tresc.naglowek + " — " + tresc.tekst.replace(/\n/g, " "),
                     "warning");
      }
    }
  }
}
