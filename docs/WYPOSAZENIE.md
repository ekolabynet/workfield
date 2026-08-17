# Wyposażenie WorkField — umowa

Jedna strona prawdy o tym, co projekt terenowy ma mieć założone i skąd o tym
wie. Siostra `docs/MAGAZYN.md`: magazyn mówi, **gdzie** projekt leży i w jakim
jest stanie cyklu życia, wyposażenie mówi, **co ma w środku**.

## Skąd to się wzięło

17.08.2026 wyjazd w teren skończył się powrotem do biura: żaden z pięciu
szablonów nie miał kompletu ulepszeń. Jedne miały warstwy, ale nie miały
`tyczenia`. Inne miały `tyczenie`, ale nie miały `workfield_klawisze.json`.
Jeszcze inne nie miały multiodnośników ani „unikaj nakładania". Przegląd
szablonów z repo potwierdził gorsze: **`AvoidIntersectionsMode` = 0 i
przyciąganie wyłączone we wszystkich pięciu**, łącznie z najświeższym.

Przyczyna nie jest przypadkiem ani niedopatrzeniem, tylko wadą konstrukcji:
**ulepszenia rodzą się w projektach, a szablon jest zdjęciem jednego projektu
z jednego dnia.** Nic nie wraca w górę. Pięć szablonów to pięć różnych dni.

## Słownik

| Pojęcie      | Co to jest                                                       |
|--------------|------------------------------------------------------------------|
| **moduł**    | jedno ulepszenie jako osobna, wersjonowana rzecz z opisem, sprawdzaczem i instalatorem |
| **stempel**  | tabela `WF_WYPOSAZENIE` w GeoPackage projektu — co ma założone i w jakiej wersji |
| **katalog**  | spis dostępnych modułów z wersjami (`wyposazenie/katalog.json`)   |
| **przepis**  | opis szablonu: warstwy branżowe + lista modułów, z którego szablon się **regeneruje** |
| **rozjazd**  | stempel mówi „mam", a stan projektu mówi „nie mam"                |

Moduł jest **idempotentny**: da się go założyć wielokrotnie bez szkody,
sprawdzić bez zmieniania czegokolwiek i — jeśli deklaruje `odwracalny` — zdjąć.

## Rodzaje modułów i gdzie wolno je stosować

| Rodzaj        | Co robi                                     | Biuro | Teren |
|---------------|---------------------------------------------|:-----:|:-----:|
| `ustawienie`  | wpisuje wartości w plik projektu            |  tak  |  tak  |
| `kontrola`    | tylko sprawdza; naprawa wymaga decyzji      |  tak  |  tak  |
| `struktura`   | zmienia schemat: warstwy, tabele, relacje, formularze | tak (PyQGIS) | nie |
| `wyrazenie`   | *(planowane)* logika w wyrażeniach QGIS     |  tak  |  tak  |

Podział nie jest kaprysem, tylko konsekwencją faktu sprawdzonego w kodzie:
**WorkField jest budowany bez Pythona** (`vcpkg/ports/qgis/portfile.cmake`,
`-DWITH_PYTHON:BOOL=OFF`, oraz brak cechy `bindings`) — na Androidzie **i na
desktopie**. Operacje na strukturze robi więc PyQGIS w QGIS Desktop, w biurze;
aplikacja umie go odpalić przez `ProcesyStudio::uruchomPyQgis()`.

Sprawdzanie natomiast to czyste czytanie pliku projektu i GeoPackage, bez
QGIS-a — dlatego to samo sprawdzenie może wykonać sama aplikacja, także na
telefonie. **Sprawdzać wolno wszędzie, naprawiać nie wszędzie.**

## Stany modułu w projekcie

| Stan       | Znaczenie                                                    |
|------------|---------------------------------------------------------------|
| `OK`       | stempel i stan zgodne, wersja aktualna                        |
| `STAR`     | starsza wersja **albo** stan zgodny bez stempla (zrobione ręcznie) |
| `BRAK`     | nie ma                                                        |
| `!ROZJ`    | **rozjazd** — stempel mówi „mam", a stanu nie ma              |
| `-`        | moduł nie ma tu zastosowania                                  |

`!ROZJ` to jedyny stan, który wymaga uwagi natychmiast: ktoś odkręcił rzecz,
o której projekt myśli, że ją ma. Bez stempla ten stan jest niewykrywalny —
i to jest cała odpowiedź na pytanie, po co stempel.

## Niezmienniki

1. **Sprawdzenie nigdy nie zmienia projektu.** `sprawdz` da się puścić na
   cudzych danych, na masterze, na czymkolwiek.
2. **Każdy zapis poprzedza kopia zapasowa** pliku projektu i GeoPackage
   (`.bak_RRRRMMDD_GGMMSS`). Kopiujemy, nie przenosimy — jak w magazynie.
3. **Stempel mieszka w GeoPackage, nie w pliku projektu**, bo GPKG jedzie
   w teren razem z danymi i wraca ze zwrotem. Tabela `WF_WYPOSAZENIE` nie
   jest zarejestrowana w `gpkg_contents`, więc nie pokazuje się jako warstwa.
4. **Moduł deklaratywny nie jest kodem.** Nowy moduł to plik `modul.json`,
   nie wydanie aplikacji. To jest cały sens podziału na rodzaje.
5. **Szablon jest wynikiem przepisu, nie plikiem trzymanym ręcznie.**
   Kto poprawia szablon w QGIS-ie i zapisuje, ten zaczyna dryf od nowa.
6. **Moduł ma `grunt`** — pole mówiące, skąd wiadomo, że tak ma być
   (plik i linia w kodzie, decyzja, dokument). Moduł bez gruntu to zgadywanie.

## Dwa źródła katalogu

- **GitHub** (`ekolabynet/workfield`, katalog `wyposazenie/`) — źródło główne,
  publiczne, wersjonowane razem z kodem. Tu mieszka wyposażenie uniwersalne.
- **NextCloud** — źródło prywatne, dla rzeczy, które nie mają być publiczne:
  słowniki zleceniodawców, podkłady, ustawienia specyficzne dla zamówienia.

Katalogi są równorzędne i mają rozłączne przestrzenie nazw: moduł prywatny
nosi przedrostek zleceniodawcy (`zzw_slownik_gatunkow`). Przy kolizji
identyfikatorów wygrywa GitHub, a silnik mówi o tym głośno — nigdy po cichu.

## Regeneracja szablonu

Szablon = `przepis.json`: warstwy branżowe + lista modułów + treści branżowe
(kafle paska, słowniki). „Regeneruj" buduje szablon od zera z **aktualnego**
katalogu, więc dryf przestaje być możliwy — nie ma czego ręcznie utrzymywać.

    przepis.json + katalog wyposażenia  ->  regeneruj  ->  szablon
    szablon + zlecenie                  ->  nowe zadanie
    zadanie stare                       ->  doposaz    ->  zadanie aktualne

Ten sam mechanizm obsługuje oba kierunki: nowy szablon i stary projekt
wracający z terenu przechodzą przez tę samą listę modułów.

## Czasowniki

    python3 skrypty/wyposazenie.py spis
    python3 skrypty/wyposazenie.py sprawdz ~/WorkField [--glosno]
    python3 skrypty/wyposazenie.py sprawdz <projekt>
    python3 skrypty/wyposazenie.py doposaz <projekt> [--moduly a,b] [--wszystko]
    python3 skrypty/wyposazenie.py zdejmij <projekt> --moduly a

Zwykły `python3`, bez QGIS-a. Moduły strukturalne wypisują się jako
„WYMAGA BIURA" wraz ze skryptem do uruchomienia w konsoli Pythona QGIS-a.

## Pułapki udokumentowane (sprawdzone w źródłach, nie zgadnięte)

1. **Dwa zapisy właściwości projektu.** QGIS pisze
   `<properties name="AvoidIntersectionsMode" type="int">`, ale czyta też stary
   `<AvoidIntersectionsMode type="int">`. Przy powtórzeniu **wygrywa ostatnie
   napotkane** (`qgsprojectproperty.cpp`, `QgsProjectPropertyKey::readXml` —
   `delete take()` + `insert` w pętli po dzieciach). W `szablon_obs_roslinnosc`
   występują oba naraz i wygrywa stary. Silnik zawsze kasuje stary zapis.
2. **`AvoidIntersectionsMode` ma trzy wartości**, nie dwie: 0 = wolno się
   nakładać, 1 = nie wolno w obrębie warstwy aktywnej, 2 = nie wolno wobec
   wskazanej listy warstw. Sama „dwójka" bez wypełnionej `AvoidIntersectionsList`
   nie robi nic — dlatego to jeden moduł, a nie dwa ustawienia.
3. **`workfield_klawisze.json` czyta klucz `etykieta`, nie `nazwa`.** Zły klucz
   daje w logu „definicje z pliku, 0 klawiszy" — pasek wstaje pusty i dowiadujesz
   się o tym w terenie. Moduł `klawisze` sprawdza też, czy każdy kafel wskazuje
   na warstwę, która w projekcie **istnieje**.
4. **Projekt `.qgz` to zip.** Zapis musi zachować wszystkie wpisy archiwum,
   nie tylko `.qgs` — obok bywa baza stylów.

## Czego jeszcze nie ma

1. **`skrypty/zaloz_tyczenie.py`** — moduł `tyczenie` na razie tylko wykrywa
   brak. Instalator do napisania (wzorzec: `DEN_TYCZENIE` z szablonu dendro 1.1).
2. **`regeneruj`** — przepisy szablonów i budowanie od zera.
3. **Pobieranie katalogu z sieci** — dziś katalog jest lokalny (kopia repo).
4. **Centrum w aplikacji** — ekran nad magazynem (`QfStudioSection.qml`):
   projekt × wyposażenie, przyciski Doposaż / Zdejmij / Regeneruj, oraz
   **ostrzeżenie przy otwarciu projektu ze złym wyposażeniem** — to jest ta
   jedna rzecz, która zawróciłaby z drogi w biurze, a nie w terenie.
5. **Moduły rodzaju `wyrazenie`** i sprawdzenie hipotezy, czy WorkField
   potrafi wczytać moduł w QML/JavaScripcie z karty w czasie działania.
