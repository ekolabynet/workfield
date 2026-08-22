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

 ETAP 1 — TYLKO CZYTA. Niczego nie zakłada i niczego nie zmienia.
 Wykrywanie musi być sprawdzone, zanim naprawa zacznie działać sama;
 pomyłka w czytaniu kosztuje mylący komunikat, pomyłka w zapisie kosztuje
 dane z terenu. Zakładanie brakującej struktury przy otwarciu (decyzja
 Piotra z 17.08) wchodzi etapem 2, na tych samych sprawdzeniach.

 Świadomie NIE sprawdzamy tu ustawień, które operator ma prawo przestawić
 w robocie — wyłączone przyciąganie w środku rysowania nie jest usterką.
 Sprawdzamy je tylko jako informację, nie jako brak.

 Patrz docs/WYPOSAZENIE.md i docs/WERSJONOWANIE.md.
 ***************************************************************************/

import QtQuick
import org.qfield
import org.qgis

Item {
  id: kontrola

  //! Czego brakuje — lista map { rzecz, opis, waga: "brak" | "uwaga" }
  property var braki: []
  //! instancja QfNaprawaProjektu — komunikat dostaje wtedy przycisk „Pokaż"
  property var ekranNaprawy: null
  //! Czy ostatnia kontrola cokolwiek znalazła
  readonly property bool czysto: braki.length === 0

  signal sprawdzono(var braki)

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
      return [];
    }

    // ── warstwa robocza tyczenia ────────────────────────────────
    // Kafel bez zdjęcia na warstwie punktowej odblokowuje trzy tryby naraz
    // (QfQuickCaptureBar captureInto) — bez niej nie obejdziesz obrysu pieszo.
    if (!NarzedziaProjektu.warstwaPoNazwie(qgisProject, "tyczenie")) {
      znalezione.push({
        "rzecz": "tyczenie",
        "opis": qsTr("brak warstwy tyczenia"),
        "waga": "brak"
      });
    }

    // ── kafle paska szybkiego przechwytu ───────────────────────
    if (!QfFileUtils.fileExists(katalog + "/workfield_klawisze.json")) {
      znalezione.push({
        "rzecz": "klawisze",
        "opis": qsTr("brak definicji kafli paska"),
        "waga": "brak"
      });
    }

    // ── słownik gatunków i wskaźniki ───────────────────────────
    // Tego aplikacja NIE wymyśli — to wiedza, nie struktura. Bez pliku
    // panel metatagów wygląda normalnie i nic nie podpowiada
    // (phototagstore.cpp: szuka wf_wskazniki.gpkg obok projektu).
    if (!QfFileUtils.fileExists(katalog + "/wf_wskazniki.gpkg")) {
      znalezione.push({
        "rzecz": "wskazniki",
        "opis": qsTr("brak słownika gatunków — podpowiadanie nie zadziała"),
        "waga": "brak"
      });
    }

    // ── ustawienia: informacja, nie brak ───────────────────────
    // Operator ma prawo je przestawić w terenie; nie ścigamy go za to.
    const trybNakladania = NarzedziaProjektu.czytajWlasciwosc(qgisProject, "Digitizing", "AvoidIntersectionsMode");
    if (String(trybNakladania) !== "2") {
      znalezione.push({
        "rzecz": "bez_nakladania",
        "opis": qsTr("unikanie nakładania poligonów jest wyłączone"),
        "waga": "uwaga"
      });
    }

    kontrola.braki = znalezione;
    kontrola.sprawdzono(znalezione);
    return znalezione;
  }

  function podsumowanie() {
    const brakujace = braki.filter(b => b.waga === "brak");
    if (brakujace.length === 0)
      return "";
    if (brakujace.length === 1)
      return brakujace[0].opis;
    return qsTr("Temu projektowi brakuje %1 rzeczy: %2")
             .arg(brakujace.length)
             .arg(brakujace.map(b => b.rzecz).join(", "));
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

  Timer {
    id: opozniona
    interval: 1500
    repeat: false
    onTriggered: {
      kontrola.sprawdz();
      const tekst = kontrola.podsumowanie();
      if (tekst === "")
        return;

      // Komunikat, którego da się posłuchać: od razu prowadzi do naprawy.
      if (kontrola.ekranNaprawy)
        displayToast(tekst, "warning", qsTr("Pokaż"), function () { kontrola.ekranNaprawy.open(); });
      else
        displayToast(tekst, "warning");
    }
  }
}
