import QtQuick

/**
 * \ingroup qml
 *
 * WorkField — WARSTWA AKCJI. Jedno źródło prawdy dla czasowników aplikacji.
 *
 * Akcja jest definiowana RAZ (nazwa, ikona, grupa, warunek dostępności,
 * wykonanie), a platformy renderują ją po swojemu: na komputerze jako
 * pozycję paska menu (QfDesktopChrome), na telefonie jako wiersz albo
 * kafel w szufladzie (QfPanelAkcji). Dzięki temu nowa funkcja to jedna
 * pozycja tutaj — i pojawia się od razu wszędzie, z właściwą geometrią.
 *
 * Pola pozycji:
 *   id        — klucz techniczny (stały, nie tłumaczony)
 *   nazwa     — etykieta dla człowieka
 *   ikona     — nazwa pliku z motywu (bez ścieżki)
 *   grupa     — magazyn | warstwy | zarzadzanie | pomoc
 *   desktop   — czy widoczna na komputerze
 *   telefon   — czy widoczna na telefonie
 *   wymagaProjektu — nieaktywna, dopóki nie ma wczytanego projektu
 *   wykonaj   — funkcja wywoływana po kliknięciu
 */
QtObject {
  id: akcje

  //! nazwy grup w kolejności prezentacji (decyzja 2026-08-09:
  //! bez grupy "Projekt" — życie projektu toczy się w Magazynie;
  //! zdjęcia to zawartość projektu, więc weszły do grupy Warstwy)
  readonly property var grupy: [
    { id: "magazyn", nazwa: qsTr("Magazyn") },
    { id: "warstwy", nazwa: qsTr("Warstwy") },
    { id: "zarzadzanie", nazwa: qsTr("Zarządzanie") },
    { id: "pomoc", nazwa: qsTr("Pomoc") }
  ]

  //! wywoływane przez okno, które osadza warstwę akcji — patrz QfDesktopChrome
  property var otworzProjekt: function () {}
  property var noweZadanie: function () {}
  property var otworzZMagazynu: function () {}
  property var nowyZSzablonu: function () {}
  property var zbudujProjekt: function () {}
  property var wyslijWTeren: function () {}
  property var odbierzZwrot: function () {}
  property var ustawKatalogMagazynu: function () {}
  property var przegladProjektow: function () {}
  property var rejestrSprzetu: function () {}
  property var ktoCoRobil: function () {}
  property var panelWarstw: function () {}
  property var stylizacja: function () {}
  property var galeriaZdjec: function () {}
  property var kontrolaPrzypisan: function () {}
  property var panelDanych: function () {}
  property var ustawieniaTerenowe: function () {}
  property var ustawieniaAplikacji: function () {}
  property var zglosUwage: function () {}
  property var oProgramie: function () {}

  readonly property bool projektWczytany: typeof qgisProject !== "undefined"
                                          && qgisProject
                                          && qgisProject.homePath !== ""

  readonly property var lista: [
    // —— Magazyn: cykl życia zadania (docs/MAGAZYN.md) ——
    { id: "otworz_magazyn", nazwa: qsTr("Otwórz magazyn"), ikona: "wfg_magazyn",
      grupa: "magazyn", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.otworzZMagazynu(); } },
    { id: "nowy_z_szablonu", nazwa: qsTr("Nowy z szablonu"), ikona: "wfg_nowe",
      grupa: "magazyn", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.nowyZSzablonu(); } },
    { id: "zbuduj", nazwa: qsTr("Zbuduj projekt"), ikona: "wfg_zbuduj",
      grupa: "magazyn", desktop: true, telefon: false, wymagaProjektu: false,
      wykonaj: function () { akcje.zbudujProjekt(); } },
    { id: "wyslij", nazwa: qsTr("Wyślij w teren"), ikona: "wfg_wyslij",
      grupa: "magazyn", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.wyslijWTeren(); } },
    { id: "odbierz", nazwa: qsTr("Przyjmij zwrot"), ikona: "wfg_odbierz",
      grupa: "magazyn", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.odbierzZwrot(); } },
    { id: "otworz", nazwa: qsTr("Otwórz z dysku…"), ikona: "wfg_otworz",
      grupa: "magazyn", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.otworzProjekt(); } },

    // —— Warstwy: zawartość wczytanego projektu ——
    { id: "warstwy", nazwa: qsTr("Warstwy projektu"), ikona: "wfg_warstwy",
      grupa: "warstwy", desktop: true, telefon: true, wymagaProjektu: true,
      wykonaj: function () { akcje.panelWarstw(); } },
    { id: "stylizacja", nazwa: qsTr("Stylizacja"), ikona: "wfg_stylizacja",
      grupa: "warstwy", desktop: true, telefon: true, wymagaProjektu: true,
      wykonaj: function () { akcje.stylizacja(); } },
    { id: "galeria", nazwa: qsTr("Galeria zdjęć"), ikona: "wfg_zdjecia",
      grupa: "warstwy", desktop: true, telefon: true, wymagaProjektu: true,
      wykonaj: function () { akcje.galeriaZdjec(); } },
    { id: "panel_danych", nazwa: qsTr("Panel danych"), ikona: "wfg_wymiana",
      grupa: "warstwy", desktop: true, telefon: false, wymagaProjektu: true,
      wykonaj: function () { akcje.panelDanych(); } },

    // —— Zarządzanie ——
    { id: "sprzet", nazwa: qsTr("Sprzęt"), ikona: "wfg_sprzet",
      grupa: "zarzadzanie", desktop: true, telefon: false, wymagaProjektu: false,
      wykonaj: function () { akcje.rejestrSprzetu(); } },
    { id: "kto_co_robil", nazwa: qsTr("Kto co robił"), ikona: "wfg_ludzie",
      grupa: "zarzadzanie", desktop: true, telefon: false, wymagaProjektu: false,
      wykonaj: function () { akcje.ktoCoRobil(); } },

    { id: "teren", nazwa: qsTr("Ustawienia terenowe"), ikona: "wfg_teren",
      grupa: "zarzadzanie", desktop: true, telefon: false, wymagaProjektu: false,
      wykonaj: function () { akcje.ustawieniaTerenowe(); } },
    { id: "ustawienia", nazwa: qsTr("Ustawienia aplikacji"), ikona: "wfg_ustawienia",
      grupa: "zarzadzanie", desktop: true, telefon: false, wymagaProjektu: false,
      wykonaj: function () { akcje.ustawieniaAplikacji(); } },

    // —— Pomoc ——
    { id: "zglos", nazwa: qsTr("Zgłoś uwagę"), ikona: "wfg_pomoc",
      grupa: "pomoc", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.zglosUwage(); } },
    { id: "o_programie", nazwa: qsTr("O programie"), ikona: "wfg_info",
      grupa: "pomoc", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.oProgramie(); } }
  ]

  // Wycięte z menu decyzją z tabeli czasowników (2026-08-09):
  //  - "Nowe zadanie" — scalone z "Nowy z szablonu" (jedno wejście);
  //    dialog noweZadanie zostaje dla szuflady telefonu.
  //  - "Przegląd projektów" — zastąpiony drzewem magazynu.
  //  - "Kontrola przypisań" — atrapa; wróci z treścią przy tagowaniu.
  //  - "Ustaw katalog magazynu" — jest w nagłówku panelu Magazyn ("Zmień…").
  // Uchwyty tych akcji celowo zostają — qgismobileapp je przypisuje.

  //! akcje danej grupy dla bieżącej platformy
  function wGrupie(idGrupy) {
    const naDesktopie = Qt.platform.os !== "android" && Qt.platform.os !== "ios";
    const wynik = [];
    for (let i = 0; i < lista.length; i++) {
      const a = lista[i];
      if (a.grupa !== idGrupy)
        continue;
      if (naDesktopie ? !a.desktop : !a.telefon)
        continue;
      wynik.push(a);
    }
    return wynik;
  }

  //! czy akcja jest teraz dostępna (warunek + brak projektu)
  function dostepna(akcja) {
    return !akcja.wymagaProjektu || projektWczytany;
  }
}
