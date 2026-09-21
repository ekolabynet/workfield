# WorkField 0.12.0 „Electronic Elm”

_2026-09-21 · zmiany od wersji 0.11.84_

77 files changed, 8241 insertions(+), 148 deletions(-).

---

## CAD i rysunki DXF

- Eksport inwentaryzacji: grupy krzewow, zakres prac i bufor jako obrysy DXF (GRUPY, ZAKRES, ZAKRES_BUFOR) + arkusz ODS Grupy krzewow  ·  `75680416d`  2026-09-21
- Inwentaryzacja drzew: styl na zywo (korona, SOD +1,5 m, pien w metrach), eksport DXF (osobny + do kopii rysunku, MULTILEADER) i tabela ODS (kolumny arkusza, zestawienia); wybor warstwy z danymi zamiast memory; odmowa eksportu bez ukladu metrycznego. Sprawdzone na telefonie (Bruzdowa, 156 drzew)  ·  `382af27dd`  2026-09-19
- Eksport DXF: dopracowanie pod CAD - kolor przy warstwie (ByLayer), teksty ACI 7, Arial zamiast Roboto, HATCH z 230=1.0 (QGIS pisze zerowy wektor wyciagniecia); ezdxf: 0 bledow, 0 napraw  ·  `3b52a2ce7`  2026-09-19
- Eksport projektu do DXF: QgsDxfExport z ustawieniami jak okno QGIS (dxf/last*, lastDxfOutputAttribute), przekodowanie CP1250 (Qt6 pisal UTF-8 mimo ANSI_1250), nazwa pliku z tytulu/katalogu, komunikat po zamknieciu szuflady, przycisk akcji w komunikacie na #39ff14; etykiety OPIS na warstwach roboczych kreatora  ·  `eed9bceea`  2026-09-19
- Kreator DXF: warstwy robocze zakladane z geometria (typ jako tekst Point/LineString/Polygon zamiast liczby Qgis.GeometryType - powstawaly tabele bez geometrii, formularz zamiast rysowania); ikona legendy dla renderera osadzonego (symbol pierwszego obiektu zamiast bialego kwadratu); zdjete sondy  ·  `a9b943e11`  2026-09-19
- Kreator DXF: punkty i etykiety w jednostkach mapy z progiem widocznosci, grupa 'Rysunek CAD' w drzewie warstw; doprawCAD i proba DXF_INLINE_BLOCKS (bloki nadal jako punkty wstawienia)  ·  `76b2b647c`  2026-09-18
- Kreator DXF: rysunek przez warstwyZPliku — querySublayers z ResolveGeometryType i loadDefaultStyle, czyli ta sama droga, ktora QField idzie przy otwieraniu pliku z menedzera; warstwy rozdzielone na typy, styl ze zrodla, uklad od dostawcy  ·  `4dc3005ec`  2026-09-18
- docs: jak QField wczytuje DXF — querySublayers z ResolveGeometryType i loadDefaultStyle; piec probaz ich powodami  ·  `0395f955c`  2026-09-18
- docs: import DXF i kreator projektu — co dziala, co kosztowalo i czego nie ma  ·  `e21afb857`  2026-09-18
- Projekt z DXF: kreator dla projektanta CAD — systemowe okno wyboru pliku, uklad PL-2000, kopia rysunku do projektu i trzy warstwy robocze (punkty, linie, poligony hatch) z opisem, data i zdjeciem; QfFileUtils.kopiujPlik dopisane, bo bylo tylko copyRecursively na katalogi  ·  `404a12c31`  2026-09-18
- DXF na liscie formatow wektorowych — sterownik AutoCAD DXF jest w binarce, brakowalo wpisu w SUPPORTED_VECTOR_EXTENSIONS; toast w menedzerze plikow mowi prawde zamiast 'Dodano warstwe' bezwarunkowo  ·  `14d610a8f`  2026-09-18
- Ekran powitalny z nowym rysunkiem: ten sam co ikona, z tlem i bez zmniejszania do bezpiecznego pola; siatka usunieta, bo przy 192 dp dawala brud  ·  `f0bcaff44`  2026-09-18
- Ikona adaptacyjna: tlo i rysunek osobno (mipmap-anydpi-v26), przycinana przez launcher do jego ksztaltu; bez siatki i kreskowanej linii, ktore przy 48 px tylko brudzily  ·  `ce4ae1865`  2026-09-17

## Inwentaryzacja drzew

- Moduly w prawej szufladzie (zakres inwentaryzacji z buforem, Wyczysc dane, grupa warstw modulu); Powieksz do warstwy w Warstwach  ·  `486ee4e04`  2026-09-20
- Zakladka Moduly w szufladzie: karty modulow projektu (sterowane opisem modulu z silnika) + lista zainstalowanych; inwentaryzacja przeniesiona z ogolnej czesci szuflady; sprawdzone na telefonie  ·  `71a502a17`  2026-09-19
- Inwentaryzacja drzew: ODS z formatowaniem arkusza pracowni (Barlow, kolory Grupy, formuly, zamrozony naglowek)  ·  `1d02a872a`  2026-09-19
- Strzalki gora/dol w legendzie (przesunWarstwe z wylaczonym mostem, clone+remove, odswiezenie kolejnosci mapy); QfTheme/QfFlatLayerTreeModel zamiast starych nazw w QfLegend  ·  `832a6ef09`  2026-09-19
- wydaj_wtyczke.sh: odswieza spis przy kazdym wydaniu  ·  `d9fa934e6`  2026-09-17

## Moduły i szuflady

- Ikona adaptacyjna trafia do APK: android-template/res budowany od zera z wyliczonych plikow, wiec warstwy i mipmap trzeba kopiowac jawnie; nowe logo 2.0 z pelnym tlem  ·  `05a9e6a4f`  2026-09-18
- Gorny pasek: hamburger i zebatka zamiast nazwy projektu (byla ucieta i nie niosla informacji); stare przyciski usuniete z lewej kolumny, lupa przekotwiczona do belki bo mainMenuBar skurczyl sie do zera  ·  `11f2fd30e`  2026-09-17
- docs: noty i QR dla wtyczek po zmianie koloru ikon na jasnoszary  ·  `4a875f162`  2026-09-17
- Wersja w naglowku lewej szuflady, tapniecie otwiera note wydania; appVersionStr wystawione do QML (bylo uzywane w dwoch miejscach i konczylo sie ReferenceError); changelog czyta wydania WorkField zamiast upstreamu  ·  `815777664`  2026-09-17
- Modul przyciaganie v2: metry zamiast pikseli (12 px przy oddalonej mapie to kilkanascie metrow — stad 28 zlepionych platow w PTR), prog 2 m, tylko warstwa aktywna  ·  `10eafad25`  2026-09-17
- docs: noty i QR po zmianie koloru ikon  ·  `bd284f207`  2026-09-17
- Wtyczki: pomaranczowa ikona na pasku (Theme.mainColor byl ciemna zielenia, niewidoczna na ciemnym tle); stany uzbrojenia bez zmian  ·  `fca49e1f0`  2026-09-17
- docs: noty i QR dla wtyczek po przepakowaniu ikon  ·  `794f4d809`  2026-09-17

## Dane, kopie i obieg

- ProjectUtils.saveProject: wynik sprawdzany w obu miejscach — toast mowil 'Zapisano' bezwarunkowo, a kopiowanie projektu robilo kopie ze stara trescia przy nieudanym zapisie  ·  `442b7c6b0`  2026-09-18
- Histereza przyciagania: lapie z progu projektu, puszcza po dwukrotnym — wierzcholek nie drga na granicy zasiegu; mnoznik jako wlasciwosc QfSnappingUtils, domyslnie 1.0 czyli bez zmiany  ·  `a2001cc1e`  2026-09-17

## Wtyczki

- Cofniecie: paczki wtyczek trafily na development zamiast na plugins (nieudany checkout, a polecenia poszly dalej)  ·  `a712ac001`  2026-09-17

## Pozostałe

- przesunWarstwe w C++ (jeszcze bez interfejsu — clone+remove duplikuje warstwe i wywala aplikacje, do poprawy)  ·  `3f6863908`  2026-09-18
- Skrypty obiegu do repo — szesc narzedzi uzywanych stale zylo tylko w katalogu roboczym, bez kopii i bez historii  ·  `a2fb53d74`  2026-09-17
- Edytor kafli: srednica i ukrywanie okiem; zapis nie gubi sekcji ustawien paska; RTCM otwiera diagnostyke GNSS, FIX ustawienia odbiornika  ·  `a107979bc`  2026-09-17
- Unikanie nakladania jako przycisk paska edycji obok topologii; stan wlaczony swieci jasnozielono zamiast ciemnym tealem (mainColor byl niewidoczny na ciemnym tle) — poprawione we wszystkich siedmiu przyciskach paska  ·  `06804aeaf`  2026-09-17
- Pasek wtyczek przewijany — Column bez ograniczenia wysokosci wychodzil poza ekran przy kilkunastu przyciskach; sufit 45% okna, gest przechodzi do mapy gdy nie ma czego przewijac  ·  `e938201b8`  2026-09-17
- Menedzer wtyczek: przycisk aktualizacji z visible (mial samo enabled, wiec byl nie do znalezienia)  ·  `947ddd312`  2026-09-17

## Niezłożone w chwili wydania

Tyle zmian siedziało w drzewie roboczym, gdy powstawało wydanie —
warto je złożyć PRZED tagiem, inaczej wydanie ich nie obejmie.

- `M brand/workfieldgis.svg`
- `M images/images.qrc`
- `M platform/android/res/drawable/ic_launcher_foreground.xml`
- `M scripts/build.sh`
- `M skrypty/sito_popup.py`
- `M src/app/qml/CMakeLists.txt`
- `M src/app/qml/QfBasemapScreen.qml`
- `M src/app/qml/QfDataDrawer.qml`
- `M src/app/qml/QfMainDrawer.qml`
- `M src/app/qml/QfPozycjaMenu.qml`
- `M src/app/qml/QfSekcjaModulow.qml`
- `M src/app/qml/QfStudioSection.qml`
- `M src/app/qml/QgisMobileapp.qml`
- `M src/core/CMakeLists.txt`
- `M src/core/moduly/inwentaryzacjadrzew.cpp`
- `M src/core/qfappinterface.cpp`
- `M src/core/qfappinterface.h`
- `M src/core/qfcore.cpp`
- `M src/core/utils/kodowaniedxf.h`
- `M src/core/utils/narzedziaprojektu.cpp`
- `M src/core/utils/narzedziaprojektu.h`
- `?? docs/wydania/WhatsNew_0-12-0.md`
- `?? images/themes/workfield/wfg_uklad_dwie.svg`
- `?? images/themes/workfield/wfg_uklad_ikony.svg`
- `?? images/themes/workfield/wfg_uklad_kafelki.svg`
- `?? images/themes/workfield/wfg_uklad_lista.svg`
- `?? src/app/qml/QfBlokiCAD.qml`
- `?? src/app/qml/QfDaneWysokosciowe.qml`
- `?? src/app/qml/QfGeoreferencja.qml`
- `?? src/app/qml/QfImportCAD.qml`
- `?? src/app/qml/QfOpisyCAD.qml`
- `?? src/app/qml/QfPodklady.qml`
- `?? src/app/qml/QfPrzelacznikUkladu.qml`
- `?? src/app/qml/QfSiatkaMenu.qml`
- `?? src/app/qml/QfWarstwiceCAD.qml`
- `?? src/app/qml/QfWarstwyRysunku.qml`
- `?? src/core/moduly/cad.cpp`
- `?? src/core/moduly/cad.h`
- `?? src/core/utils/georeferencja.h`
- `?? src/core/utils/warstwice.h`

