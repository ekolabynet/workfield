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
 *   grupa     — projekt | magazyn | zarzadzanie | warstwy | zdjecia | pomoc
 *   desktop   — czy widoczna na komputerze
 *   telefon   — czy widoczna na telefonie
 *   wymagaProjektu — nieaktywna, dopóki nie ma wczytanego projektu
 *   wykonaj   — funkcja wywoływana po kliknięciu
 */
QtObject {
  id: akcje

  //! nazwy grup w kolejności prezentacji
  readonly property var grupy: [
    { id: "projekt", nazwa: qsTr("Projekt") },
    { id: "magazyn", nazwa: qsTr("Magazyn") },
    { id: "zarzadzanie", nazwa: qsTr("Zarządzanie") },
    { id: "warstwy", nazwa: qsTr("Warstwy") },
    { id: "zdjecia", nazwa: qsTr("Zdjęcia") },
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
  property var zglosUwage: function () {}
  property var oProgramie: function () {}

  readonly property bool projektWczytany: typeof qgisProject !== "undefined"
                                          && qgisProject
                                          && qgisProject.homePath !== ""

  readonly property var lista: [
    { id: "otworz", nazwa: qsTr("Otwórz projekt"), ikona: "wfg_otworz",
      grupa: "projekt", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.otworzProjekt(); } },
    { id: "nowe_zadanie", nazwa: qsTr("Nowe zadanie"), ikona: "wfg_nowe",
      grupa: "projekt", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.noweZadanie(); } },

    { id: "otworz_magazyn", nazwa: qsTr("Otwórz z magazynu"), ikona: "wfg_magazyn",
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
    { id: "odbierz", nazwa: qsTr("Odbierz zwrot"), ikona: "wfg_odbierz",
      grupa: "magazyn", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.odbierzZwrot(); } },
    { id: "katalog_magazynu", nazwa: qsTr("Ustaw katalog magazynu"), ikona: "wfg_ustawienia",
      grupa: "magazyn", desktop: true, telefon: false, wymagaProjektu: false,
      wykonaj: function () { akcje.ustawKatalogMagazynu(); } },

    { id: "przeglad", nazwa: qsTr("Przegląd projektów"), ikona: "wfg_przeglad",
      grupa: "zarzadzanie", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.przegladProjektow(); } },
    { id: "sprzet", nazwa: qsTr("Sprzęt"), ikona: "wfg_sprzet",
      grupa: "zarzadzanie", desktop: true, telefon: false, wymagaProjektu: false,
      wykonaj: function () { akcje.rejestrSprzetu(); } },
    { id: "kto_co_robil", nazwa: qsTr("Kto co robił"), ikona: "wfg_ludzie",
      grupa: "zarzadzanie", desktop: true, telefon: false, wymagaProjektu: false,
      wykonaj: function () { akcje.ktoCoRobil(); } },

    { id: "warstwy", nazwa: qsTr("Warstwy projektu"), ikona: "wfg_warstwy",
      grupa: "warstwy", desktop: true, telefon: true, wymagaProjektu: true,
      wykonaj: function () { akcje.panelWarstw(); } },
    { id: "stylizacja", nazwa: qsTr("Stylizacja"), ikona: "wfg_stylizacja",
      grupa: "warstwy", desktop: true, telefon: true, wymagaProjektu: true,
      wykonaj: function () { akcje.stylizacja(); } },

    { id: "galeria", nazwa: qsTr("Galeria zdjęć"), ikona: "wfg_zdjecia",
      grupa: "zdjecia", desktop: true, telefon: true, wymagaProjektu: true,
      wykonaj: function () { akcje.galeriaZdjec(); } },
    { id: "przypisania", nazwa: qsTr("Kontrola przypisań"), ikona: "wfg_sprawdz",
      grupa: "zdjecia", desktop: true, telefon: true, wymagaProjektu: true,
      wykonaj: function () { akcje.kontrolaPrzypisan(); } },

    { id: "zglos", nazwa: qsTr("Zgłoś uwagę"), ikona: "wfg_pomoc",
      grupa: "pomoc", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.zglosUwage(); } },
    { id: "o_programie", nazwa: qsTr("O programie"), ikona: "wfg_info",
      grupa: "pomoc", desktop: true, telefon: true, wymagaProjektu: false,
      wykonaj: function () { akcje.oProgramie(); } }
  ]

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
