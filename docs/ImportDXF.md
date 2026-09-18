# Import DXF i kreator „Projekt z DXF"

WorkField, 18.09.2026.

## Po co

Tester jest CADowcem. Ma rysunek, chce z nim chodzić po terenie, dopinać
obserwacje ze zdjęciami i wywieźć wynik z powrotem do DXF. Nie zna QGIS-a
i nie będzie wczytywał rysunku w biurze, uruchamiał wtyczek ani składał
projektu ręcznie.

Z czterech rzeczy, których potrzebuje, **trzy były gotowe**: obserwacje
z dokumentacją, eksport do DXF (`QfLayerExportDialog`) i kopia zapasowa.
Brakowało tylko drogi wejścia.

## Co działa

**Wczytanie DXF.** Sterownik `AutoCAD DXF` jest w binarce — sprawdzone przez
`strings` na `libqfield_arm64-v8a.so`. Brakowało jedynie wpisu `dxf`
w `SUPPORTED_VECTOR_EXTENSIONS` (`src/core/qfield.h.in`). Kolory z rysunku
są zachowane; nie trzeba nic stylizować.

**Kreator** (`QfProjektZCAD.qml`): wskaż plik → układ → nazwa. Zakłada
projekt w `Imported Projects`, kopiuje do niego rysunek i dokłada trzy
warstwy robocze: `Punkty`, `Linie`, `Poligony (hatch)` — każda z polami
`OPIS`, `DATA`, `ZDJECIE` (załącznik).

Wejście: lewa szuflada → Projekt → **Projekt z DXF**.

## Pułapki, które to kosztowało

### `iface.loadFile` zastępuje CAŁY projekt

Nazwa sugeruje „wczytaj plik", ale w środku jest `loadProjectFile`, które
otwiera plik **jako projekt** — także dla warstw. Wywołane w środku funkcji
przerywa jej wykonanie, bo handler `onLoadProjectEnded` startuje od nowa.

Objawy były trzy i wyglądały na niezwiązane: projekt „z niezapisanymi
zmianami", martwe przyciski w zakładce Projekt, brak komunikatu o gotowości.
Jedna przyczyna.

**Do dołożenia warstwy służy `LayerUtils.loadVectorLayer(uri, nazwa, "ogr")`**
(`qflayerutils.h:455`).

### `createBlankProject` narzuca EPSG:3857

Rysunek w PL-2000 rozciągał się na tysiące kilometrów. Właściwy czasownik to
`NarzedziaProjektu.nowyProjekt(korzen, nazwa, crsAuthId)` — zakłada katalog
i projekt z podanym układem, domyślnie `EPSG:2178`. Komentarz w kodzie
mówi o tym wprost od dawna.

### Nowy plik QML trzeba dopisać do listy

`src/app/qml/CMakeLists.txt`. Bez wpisu kompiluje się bez błędu, a w aplikacji
nie istnieje: `QfProjektZCAD is not a type`.

### Android: czytać wolno, pisać nie

Projekt nie może powstać obok rysunku w `Download`:

E MediaProvider: Creating or writing to a non-default top level directory
is not allowed!


Odczyt z `Download` działa, zapis nie. Stąd projekt w `Imported Projects`,
a rysunek **kopiowany** do niego — inaczej nie pojechałby ani w wydaniu,
ani w kopii na nośnik.

`QfFileUtils` nie miało kopiowania pojedynczego pliku (tylko
`copyRecursively` na katalogi) — dopisane jako `kopiujPlik`.

### Systemowe okno filtruje po MIME, nie po rozszerzeniu

`nameFilters: ["*.dxf"]` chowało wszystko poza obrazkami, bo DXF nie ma
zarejestrowanego typu MIME. Filtr musi być `*`, a rozszerzenie sprawdzane
**po** wybraniu — wtedy też widać, dlaczego plik się nie nadaje.

Do tego `currentFolder` na `Download`, bo bez niego Qt otwiera okno
w przestrzeni aplikacji, gdzie projektanta jego pliku nie ma.

### `FolderListModel` nie zadziałał

Pierwsza wersja kreatora sama przeglądała katalogi. Nie widziała `Download`
i była obca człowiekowi, który zna swój telefon lepiej niż naszą listę.
Systemowe okno jest właściwą drogą.

## Czego NIE ma

**Warstwy CAD są w jednym worku.** GDAL zwraca punkty, linie i poligony;
warstwy rysunku siedzą w atrybucie `Layer`. Nie da się zgasić uzbrojenia
i zostawić granic — a CADowiec myśli warstwami. Do zrobienia: lista wartości
z pola `Layer` i filtr na warstwie.

**Układ nie jest zgadywany.** DXF go nie niesie. Można by go wyczytać
z zakresu rysunku (strefy PL-2000 nie nachodzą na siebie, więc pierwsza cyfra
współrzędnej X mówi wszystko), ale `czytajTekst` wczytuje cały plik do
pamięci, a rysunki mapy zasadniczej mają kilkanaście megabajtów.

**DWG nie działa i nie będzie.** ODA File Converter jest zamknięty
i desktopowy; nie wolno go redystrybuować. LibreDWG wymagałaby kompilacji na
Androida, a wynik i tak byłby DXF-em bez warstw. Droga przez biuro zostaje
właściwa.

## Podkład

Nie dokładamy go w kreatorze — zakładka Warstwy ma **Dodaj podkład**
i projektant wybierze sobie ortofoto albo OSM jednym tapnięciem. Toast po
utworzeniu projektu prowadzi tam przyciskiem.
