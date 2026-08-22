/***************************************************************************
  QfPrzepis.qml - interpreter przepisów WorkField

 ---------------------
 Czyta plik przepisu (JSON) i składa z czasowników NarzedziaProjektu gotowy
 projekt — warstwy, pola, formularze, relacje, ustawienia, pliki obok
 projektu i stempel wyposażenia.

 Sens podziału: C++ daje czasowniki i nic o nich nie wie, przepis daje
 kolejność i treść. Dzięki temu nowe narzędzie jest plikiem na karcie,
 a nie kolejnym buildem Androida.

 Rusztowanie powstaje pusto (NarzedziaProjektu.nowyProjekt), potem aplikacja
 je wczytuje, a przepis dokłada resztę dopiero po sygnale loadProjectEnded —
 wcześniej nie ma projektu, do którego można cokolwiek dołożyć.

 Patrz docs/WYPOSAZENIE.md.
 ***************************************************************************/

import QtQuick
import org.qfield
import org.qgis

Item {
  id: przepisy

  //! Projekt zbudowany i zapisany
  signal zbudowano(string sciezka, string nazwa)
  //! Coś nie wyszło — komunikat jest przeznaczony dla człowieka w rękawicach
  signal potknieto(string komunikat)
  //! Postęp: krok po kroku, do wypisania w oknie budowania
  signal krok(string opis)

  property var _czekajacyPrzepis: null
  property string _czekajacaSciezka: ""

  // ------------------------------------------------------------------ wejście

  function wczytajPrzepis(sciezkaPrzepisu) {
    const tekst = NarzedziaProjektu.czytajTekst(sciezkaPrzepisu);
    if (tekst === "") {
      potknieto(qsTr("Nie mogę przeczytać przepisu: %1").arg(sciezkaPrzepisu));
      return null;
    }
    try {
      return JSON.parse(tekst);
    } catch (e) {
      potknieto(qsTr("Przepis jest uszkodzony: %1").arg(e.message));
      return null;
    }
  }

  /**
   * Nowe zadanie z przepisu. Buduje pusty projekt w <korzen>/<nazwaZadania>,
   * wczytuje go i po wczytaniu dokłada wszystko, co przepis opisuje.
   */
  function noweZadanie(sciezkaPrzepisu, korzen, nazwaZadania) {
    const przepis = wczytajPrzepis(sciezkaPrzepisu);
    if (!przepis)
      return false;

    const uklad = przepis.uklad || "EPSG:2178";
    const sciezkaProjektu = NarzedziaProjektu.nowyProjekt(korzen, nazwaZadania, uklad);
    if (sciezkaProjektu === "") {
      potknieto(qsTr("Nie mogę założyć zadania '%1' — katalog już istnieje albo nie ma gdzie pisać").arg(nazwaZadania));
      return false;
    }

    przepisy._czekajacyPrzepis = przepis;
    przepisy._czekajacaSciezka = sciezkaProjektu;
    krok(qsTr("Zakładam zadanie %1").arg(nazwaZadania));
    iface.loadFile(sciezkaProjektu, nazwaZadania);
    return true;
  }

  Connections {
    target: iface

    function onLoadProjectEnded(path, name) {
      if (!przepisy._czekajacyPrzepis || path !== przepisy._czekajacaSciezka)
        return;

      const przepis = przepisy._czekajacyPrzepis;
      przepisy._czekajacyPrzepis = null;
      przepisy._czekajacaSciezka = "";

      if (przepisy.zastosuj(przepis, path))
        przepisy.zbudowano(path, name);
    }
  }

  // ------------------------------------------------------------- wykonanie

  function _katalogProjektu(sciezkaProjektu) {
    return sciezkaProjektu.substring(0, sciezkaProjektu.lastIndexOf("/"));
  }

  /**
   * Nakłada przepis na AKTUALNIE wczytany projekt. Używane i przy budowie
   * nowego zadania, i przy doposażaniu istniejącego — to ta sama droga,
   * bo czasowniki są idempotentne.
   */
  function zastosuj(przepis, sciezkaProjektu) {
    const katalog = _katalogProjektu(sciezkaProjektu);
    const gpkg = katalog + "/" + (przepis.dane || "dane.gpkg");
    const uklad = przepis.uklad || "EPSG:2178";

    // 1. Warstwy i tabele
    const warstwy = przepis.warstwy || [];
    for (let i = 0; i < warstwy.length; i++) {
      const opis = warstwy[i];
      if (NarzedziaProjektu.warstwaPoNazwie(qgisProject, opis.nazwa)) {
        krok(qsTr("warstwa %1 już jest").arg(opis.nazwa));
        continue;
      }

      const warstwa = LayerUtils.createEmptyLayer(gpkg, opis.nazwa, opis.geometria || "NoGeometry", uklad, opis.pola || []);
      if (!warstwa) {
        potknieto(qsTr("Nie udało się założyć warstwy %1").arg(opis.nazwa));
        return false;
      }
      if (!ProjectUtils.addMapLayer(qgisProject, warstwa)) {
        potknieto(qsTr("Warstwa %1 powstała, ale nie weszła do projektu").arg(opis.nazwa));
        return false;
      }
      krok(qsTr("warstwa %1").arg(opis.nazwa));
    }

    // 2. Konfiguracja warstw — po założeniu WSZYSTKICH, bo zakładki relacji
    //    potrzebują warstw, których relacje jeszcze nie istnieją.
    //    Relacje idą krokiem 3, konfiguracja formularzy krokiem 4.
    for (let i = 0; i < warstwy.length; i++)
      _skonfigurujWarstwe(warstwy[i]);

    // 3. Relacje
    const relacje = przepis.relacje || [];
    for (let i = 0; i < relacje.length; i++) {
      const id = NarzedziaProjektu.relacja(qgisProject, relacje[i]);
      if (id === "") {
        potknieto(qsTr("Nie udało się założyć relacji %1").arg(relacje[i].id || "?"));
        return false;
      }
      krok(qsTr("relacja %1").arg(id));
    }

    // 4. Formularze — dopiero teraz, bo zakładka relacji wskazuje na jej id
    for (let i = 0; i < warstwy.length; i++) {
      const opis = warstwy[i];
      if (!opis.zakladki)
        continue;
      const warstwa = NarzedziaProjektu.warstwaPoNazwie(qgisProject, opis.nazwa);
      if (warstwa)
        NarzedziaProjektu.ukladFormularza(warstwa, opis.zakladki);
    }

    // 5. Ustawienia projektu
    _ustawProjekt(przepis.projekt || {});

    // 6. Pliki obok projektu (workfield_klawisze.json i podobne)
    const pliki = przepis.pliki || [];
    for (let i = 0; i < pliki.length; i++) {
      const tresc = typeof pliki[i].tresc === "string" ? pliki[i].tresc : JSON.stringify(pliki[i].tresc, null, 2);
      if (!NarzedziaProjektu.zapiszTekst(katalog + "/" + pliki[i].nazwa, tresc)) {
        potknieto(qsTr("Nie mogę zapisać pliku %1").arg(pliki[i].nazwa));
        return false;
      }
      krok(pliki[i].nazwa);
    }

    // 7. Zapis projektu, a dopiero potem stempel — stempel ma opisywać stan,
    //    który naprawdę wylądował na dysku, nie ten, który zamierzaliśmy.
    if (!NarzedziaProjektu.zapiszProjekt(qgisProject)) {
      potknieto(qsTr("Nie udało się zapisać projektu"));
      return false;
    }

    const wyposazenie = przepis.wyposazenie || [];
    for (let i = 0; i < wyposazenie.length; i++) {
      NarzedziaProjektu.stempluj(gpkg, wyposazenie[i].modul, wyposazenie[i].wersja, przepis.zrodlo || "przepis", "teren");
    }

    krok(qsTr("gotowe"));
    return true;
  }

  function _skonfigurujWarstwe(opis) {
    const warstwa = NarzedziaProjektu.warstwaPoNazwie(qgisProject, opis.nazwa);
    if (!warstwa)
      return;

    const aliasy = opis.aliasy || {};
    for (const pole in aliasy)
      NarzedziaProjektu.alias(warstwa, pole, aliasy[pole]);

    const widgety = opis.widgety || {};
    for (const pole in widgety)
      NarzedziaProjektu.widget(warstwa, pole, widgety[pole].typ, widgety[pole].opcje || {});

    const domyslne = opis.domyslne || {};
    for (const pole in domyslne) {
      const d = domyslne[pole];
      if (typeof d === "string")
        NarzedziaProjektu.wartoscDomyslna(warstwa, pole, d, false);
      else
        NarzedziaProjektu.wartoscDomyslna(warstwa, pole, d.wyrazenie, d.przyAktualizacji === true);
    }

    const ograniczenia = opis.ograniczenia || {};
    for (const pole in ograniczenia)
      NarzedziaProjektu.ograniczenieMiekkie(warstwa, pole, ograniczenia[pole].wyrazenie, ograniczenia[pole].opis || "");

    if (opis.wyswietlanie)
      NarzedziaProjektu.wyrazenieWyswietlania(warstwa, opis.wyswietlanie);

    if (opis.bezPotwierdzenia === true)
      NarzedziaProjektu.bezPotwierdzenia(warstwa);

    const wlasciwosci = opis.wlasciwosci || {};
    for (const klucz in wlasciwosci)
      NarzedziaProjektu.wlasciwoscWarstwy(warstwa, klucz, wlasciwosci[klucz]);

    if (opis.grupa)
      NarzedziaProjektu.doGrupy(qgisProject, warstwa, opis.grupa, true, opis.widoczna === true);
  }

  function _ustawProjekt(ustawienia) {
    const wlasciwosci = ustawienia.wlasciwosci || {};
    for (const grupa in wlasciwosci) {
      const klucze = wlasciwosci[grupa];
      for (const klucz in klucze)
        NarzedziaProjektu.wlasciwosc(qgisProject, grupa, klucz, klucze[klucz]);
    }

    const zmienne = ustawienia.zmienne || {};
    for (const nazwa in zmienne)
      NarzedziaProjektu.zmiennaProjektu(qgisProject, nazwa, zmienne[nazwa]);

    if (ustawienia.przyciaganie) {
      NarzedziaProjektu.przyciaganie(qgisProject, ustawienia.przyciaganie);
      krok(qsTr("przyciąganie"));
    }

    if (ustawienia.unikajNakladania) {
      NarzedziaProjektu.unikajNakladania(qgisProject, ustawienia.unikajNakladania.tryb, ustawienia.unikajNakladania.warstwy || []);
      krok(qsTr("unikaj nakładania"));
    }
  }
}
