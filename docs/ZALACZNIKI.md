# Załączniki N:1 — „multiodnośniki"

WorkFieldGIS, 22.09.2026. Plik, na który powoływały się trzy miejsca w kodzie
(`zalacznikiutils.h`, `zalacznikiutils.cpp`, `wyposazenie/moduly/zalaczniki/modul.json`),
a którego nie było.

## Po co to jest

Bez tego modułu obiekt niesie **jedno zdjęcie** w polu tekstowym `FOTO`
(w projektach z kreatora: `ZDJECIE`). Drzewo ma awers i rewers, szkodę widać
z dwóch stron, studzienka ma tabliczkę i wnętrze. Jedno pole na ścieżkę pliku
wystarcza do pierwszego zdjęcia i do niczego więcej.

Po założeniu modułu obiekt ma **tabelę-dziecko** i galerię w formularzu:
dowolnie wiele zdjęć, szkiców, nagrań i notatek, każde z typem, czasem
i autorem.

## Jak to jest zbudowane

| element | wartość |
|---|---|
| tabela | `ZAL_<WARSTWA>` w tym samym GeoPackage co rodzic |
| klucz obcy | `ID_RODZICA` → `fid` rodzica |
| siła relacji | **kompozycja** — skasowanie obiektu kasuje jego załączniki |
| pola | `ID_RODZICA`, `TYP`, `SCIEZKA`, `UJECIE`, `CZAS`, `AUTOR`, `UWAGI` |
| widget ścieżki | `ExternalResource` (ścieżka względna, podgląd obrazu) |
| grupa w legendzie | „Załączniki", zwinięta, wyłączona na mapie |

**Galeria bierze się z widgetu, nie z osobnego kodu.** Formularz podmienia
edytor relacji na galerię wtedy i tylko wtedy, gdy warstwa-dziecko ma pole
z widgetem `ExternalResource` (`qfattributeformmodelbase.cpp`). Dlatego
`SCIEZKA` musi ten widget dostać — bez niego powstaje zwykła tabelka relacji
i aparat się nie pokazuje.

**Żadne pole nie może mieć `NOT NULL`.** Przy nowym, jeszcze niezapisanym
obiekcie rodzica QField wpisuje klucz obcy dopiero po zatwierdzeniu
(`featuremodel.cpp`), a `NOT NULL` na `ID_RODZICA` wyłączyłoby wtedy galerię
(`referencingfeaturelistmodel.cpp`: `checkParentPrimaries`).

**Indeks po `ID_RODZICA` jest obowiązkowy**, nie ozdobny: galeria pyta
o dzieci przy każdym otwarciu formularza.

## Konwencja nazw plików

```
DCIM/<warstwa>_<klucz>/<warstwa>_<klucz>_RRRRMMDD_GGMMSS_mmm.<rozszerzenie>
```

Podkatalog na obiekt, a w nazwie pliku klucz obiektu między nazwą warstwy
a datą — zgodnie z tym, czego oczekują programy branżowe (Mapit Spatial).
Zapisane jako `QFieldSync/attachment_naming` na warstwie-dziecku.

Klucz podaje aplikacja w zmiennej `@rodzic_fid`. **Aplikacja bez tej zmiennej
dostaje NULL** — wtedy wyrażenie schodzi do starej, płaskiej nazwy zamiast
robić katalog o nazwie „NULL":

```
DCIM/<warstwa>_RRRRMMDD_GGMMSS_mmm.<rozszerzenie>
```

Dzięki temu ten sam projekt działa na starym i nowym APK, a konwencja włącza
się sama, gdy w telefonie wyląduje nowsza wersja. Nazwa warstwy jest
sprowadzana do ASCII — polskie znaki w nazwie pliku to proszenie się
o kłopoty na karcie SD, w zipie i przy transliteracji w chmurze.

## Nazwa tabeli — reguła poprawiona 22.09.2026

Nazwa warstwy jest sprowadzana do `[A-Z0-9_]`: ogonki na gołe litery, reszta
znaków na `_`, powtórzenia sklejone, podkreślenia z brzegów ucięte.

Powód wyszedł z próby, nie z rozumowania. Kreator „Projekt z DXF" zakładał
warstwę nazwaną „Poligony (hatch)", a poprzednia reguła (sam zapis bez
ogonków i wielkie litery) robiła z niej tabelę **`ZAL_POLIGONY (HATCH)`** —
ze spacją i nawiasami. SQLite to przełyka w cudzysłowach i wszystko działa,
ale taka nazwa gryzie przy każdym ręcznym SQL-u, przy eksporcie i w cudzych
narzędziach, a indeks nazywa się wtedy `idx_ZAL_POLIGONY (HATCH)_rodzic`.

Skrypt biurowy miał tę samą wadę i nigdy się nie objawiła, bo puszczano go
na warstwach dendro (`drzewa`, `grupy`, `uwagi`). Reguła jest poprawiona
w obu miejscach naraz. Przy okazji kreator nazywa tę warstwę po prostu
**„Poligony"** — kłopot usunięty u źródła, a nie obchodzony.

**Zgodność wstecz:** jeśli w bazie jest już tabela pod starą, nieoczyszczoną
nazwą, używana jest ONA. Inaczej powstałaby druga tabela obok pełnej zdjęć.
Tak samo z identyfikatorem relacji.

## Dwie drogi, jedna konwencja

| gdzie | czym | kiedy |
|---|---|---|
| biuro | `skrypty/zaloz_zalaczniki.py` (PyQGIS, konsola QGIS) | przy składaniu projektu |
| teren | Wyposażenie → „Załączniki N:1" → **Załóż** | gdy projekt przyjechał bez modułu |

Obie drogi liczą nazwy tą samą regułą i dają ten sam wynik, więc **uruchomienie
jednej na projekcie zrobionym drugą niczego nie dubluje** — tabela jest
rozpoznawana po nazwie, relacja po identyfikatorze.

**Zmieniając cokolwiek w jednej, zmienić w drugiej.** Rozjazd nie objawi się
błędem kompilacji, tylko drugą zakładką „Załączniki" w formularzu.

Kod terenowy: `src/core/moduly/zalaczniki.cpp`, wywoływany z
`Wyposazenie::wykonajKrok()` dla kroku `{"typ": "tabele_gpkg", "wzorzec": "ZAL_%"}`.

## Czego ten moduł NIE robi

- **Nie rusza pól `FOTO`/`ZDJECIE`.** Zostają jako awaryjny zapis pojedynczego
  zdjęcia. Skasowanie pola skasowałoby ścieżki do plików, które już leżą
  w DCIM. Migracja starych zdjęć do tabel jest osobną operacją magazynową
  i świadomie nie ma jej tutaj.
- **Nie jest odwracalny.** `"odwracalny": false` w opisie modułu to nie
  ostrożność, tylko fakt: skasowanie tabeli kasuje dane. Dlatego zakładanie
  robi kopię `projekt.qgs` **i** `dane.gpkg` z sufiksem `.przed_<data_godzina>`.
- **Nie zakłada niczego przy otwartej edycji.** Jeśli którakolwiek warstwa ma
  włączony bufor edycji, moduł odmawia w całości i mówi, która to warstwa.
  Dopisywanie tabel do pliku, w którym ktoś ma otwartą sesję, kończy się
  w najlepszym razie utraconą sesją.
- **Nie dotyka słowników, podkładów ani warstw `REF_`.** Kandydatem jest
  warstwa wektorowa, prawidłowa, zapisywalna, leżąca w GeoPackage i mająca
  pole `fid`.

## Co sprawdzono

Piaskownica, QGIS 3.34.4, dwie próby, 65 sprawdzeń:

- **droga pełna** — projekt zapisany, **wczytany od nowa z dysku** i zapytany
  przez `ZalacznikiUtils::relacjaZalacznikow` (tę samą funkcję, którą pasek
  nawigacji pyta, czy pokazać aparat): cztery warstwy, komplet pól rozpoznany,
  relacje o sile kompozycji;
- **idempotencja** — drugie uruchomienie: zero nowych tabel, zero nowych
  relacji, cztery relacje w projekcie, nie osiem;
- **nazwy tabel** — bez spacji, nawiasów i ogonków; „Poligony (hatch)" →
  `ZAL_POLIGONY_HATCH`, „Złącza" → `ZAL_ZLACZA`;
- **pole `ZDJECIE`** nietknięte na każdej warstwie;
- **droga przez `Wyposazenie::zaloz()`** — odmowa przed łatką, zgoda po,
  obie kopie zapasowe na dysku, stempel `WF_WYPOSAZENIE` zgodny, odmowa przy
  otwartej edycji z nazwą warstwy w komunikacie.

## Pułapka przy okazji znaleziona

`QFile::copy` **odmawia, gdy plik docelowy już istnieje**, a znacznik kopii ma
rozdzielczość jednej sekundy. Dwa moduły założone w tej samej sekundzie — albo
ten sam dwa razy — kończyły się komunikatem „Nie udało się zrobić kopii
projektu", który brzmi jak awaria dysku, a znaczy „kopia już jest". Było tak
w `Wyposazenie::zaloz()` **i** w `zdejmij()`; poprawione 22.09.2026.
