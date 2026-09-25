# Czasowniki terenowe: warstwa robocza i kafle

WorkFieldGIS, 23.09.2026. Dwa moduły wyposażenia, które do dziś tylko
PATRZYŁY, od dziś ZAKŁADAJĄ — po zapytaniu człowieka.

## Co było nie tak

Moduł `tyczenie` od 15.09 miał jeden krok: `warstwa_istnieje`. W terenie
kończyło się to zdaniem

> w projekcie nie ma warstwy „tyczenie”. Ten moduł tylko SPRAWDZA, czy jest
> — warstwę zakłada się w biurze albo w zakładce Warstwy.

Zdanie prawdziwe i bezużyteczne: warstwę zakłada się w biurze, czyli jutro,
a tyczyć trzeba dziś. Tak samo `klawisze`: „nie ma pliku
workfield_klawisze.json obok projektu” — i nie ma w czym go napisać.

A `tyczenie` to warstwa **techniczna**: dwa pola, żadnej branży, żadnej
decyzji, której nie da się podjąć na miejscu. Kafle też nie wymagają biura —
wymagają tylko wskazania, którym warstwom mają przybyć.

## Co robią teraz

| moduł | wersja | krok | co robi |
|---|---|---|---|
| `tyczenie` | 1 → **2** | `warstwa_robocza` | zakłada warstwę **i jej kafel** |
| `klawisze` | 1 → **2** | `kafle_warstw` | dokłada kafle dla wskazanych warstw, potem sprawdza cały plik |

Oba **pytają, zanim cokolwiek zrobią**. Warstwa dołożona do cudzego projektu
bez pytania to zmiana, której nikt nie zamawiał; kafle dla warstw wybranych
za człowieka to pasek, którego nie rozpoznaje.

Pytanie deklaruje `modul.json` przez pole `pyta`, a okno wyposażenia
(`QfWyposazenie.qml`) otwiera odpowiednie okienko:

- `potwierdzenie` — zapowiedź z wypisanymi polami i kaflem, [Załóż] / [Nie teraz];
- `warstwy_kafli` — lista warstw, z góry zaznaczone te BEZ kafla.

## Schemat warstwy siedzi w `modul.json`, nie w C++

```json
{ "typ": "warstwa_robocza", "nazwa": "tyczenie", "geometria": "punkt",
  "pola": [ { "nazwa": "opis", "typ": "tekst" },
            { "nazwa": "data_czas", "typ": "tekst",
              "domyslnie": "format_date(now(),'yyyy-MM-dd HH:mm:ss')" } ],
  "wyswietlaj": "coalesce(\"opis\", \"data_czas\", 'tyczenie')",
  "kafel": { "etykieta": "TY", "kolor": "#546E7A", "zdjecie": false } }
```

Następna warstwa techniczna nie wymaga ani linijki C++, a schemat pól widać
tam, gdzie się go szuka.

**Dwa pola, nie trzy.** Wykonawcę zna projekt (zmienna `@wykonawca`), więc
osobna rubryka „WYKONAWCA” z szablonu dendro bywała pusta. Małe litery —
`opis`, `data_czas` — zgodnie z otwartą decyzją z `claude/NAZEWNICTWO.md`
(pola techniczne schodzą do małych). Warstwa jest świeża, więc zmiana była
darmowa dziś.

**`fid` nie jest ozdobą.** Bez niego załączniki N:1 nie mają do czego przypiąć
klucza obcego — warstwa robocza nie dostałaby galerii.

## Kafel razem z warstwą

Warstwa tyczenia bez kafla jest bezużyteczna. Kafel z `"zdjecie": false` na
warstwie punktowej odblokowuje trzy tryby naraz: punkt bez aparatu, serię
wierzchołków pod długim przytrzymaniem i dokładanie wierzchołków z GNSS do
rysowanej geometrii. Założenie samej warstwy było więc połową roboty, po
której i tak trzeba wracać do biura.

## Etykiety się nie zderzają

`QfNaprawaProjektu.zbudujKlawisze()` bierze `nazwa.substring(0, 1)` i nie
sprawdza niczego. Kreator „Projekt z DXF” zakłada „Punkty” i „Poligony” —
**oba dostają „P”**. Pasek wstaje z dwoma takimi samymi klawiszami i w terenie
nie wiadomo, w który się stuka.

`ModulKafli` etykietę **dobiera**: pierwsza litera, potem dwie pierwsze
(„PO” dla „Poligony”), potem pierwsza z kolejną, na końcu pierwsza z cyfrą.
Zajęte są także te, które w pliku już są.

## Scala, nie nadpisuje

`QfNaprawaProjektu` robi kafle przez **nadpisanie całego pliku** — kto dołożył
sobie kafel ręcznie, traci go przy następnym uruchomieniu naprawy. Ten moduł
czyta plik, **dokłada** brakujące kafle i zapisuje całość: obce klucze,
kolejność i ręczne kafle zostają. Stary plik dostaje kopię `.przed_<data>`.

Plik, którego nie da się sparsować, **nie jest nadpisywany wcale** — zepsuty
JSON to zwykle literówka w ręcznie dopisanym kaflu, a nadpisanie skasowałoby
całą resztę, która była dobra.

## Idempotencja

| sytuacja | co się dzieje |
|---|---|
| warstwa jest w projekcie | nie ruszamy jej |
| tabela jest w bazie, warstwy nie ma w projekcie | wczytujemy **istniejącą** — w tamtej mogą już leżeć punkty z terenu |
| kafel dla tej warstwy już jest | zostaje, także gdy ma inną etykietę |

**Kafel rozpoznajemy po NAZWIE WARSTWY, nie po etykiecie.** Projekty dendro
mają kafel tyczenia pod etykietą „T” od 20.09 — sprawdzanie po etykiecie
dołożyłoby drugi kafel na tę samą warstwę.

## Kopie zapasowe

`warstwa_robocza` pisze do `dane.gpkg` (zakłada w nim tabelę), więc
`Wyposazenie::zaloz()` kopiuje **projekt i bazę**, tak samo jak przy
załącznikach. Bez tego słowo „nieodwracalny” w opisie modułu znaczyłoby
naprawdę nieodwracalny.

## Co sprawdzono

Piaskownica, QGIS 3.34.4, cztery próby:

- **`proba4`, 11 sekcji, 45 sprawdzeń** — warstwa powstaje naprawdę (tabela
  w pliku, trzy pola, geometria punktowa, układ z projektu), **projekt
  wczytany od nowa z dysku** ją widzi, drugie uruchomienie niczego nie
  dubluje, stara etykieta „T” zostaje nietknięta, „Punkty” i „Poligony”
  dostają różne etykiety, obcy klucz `_uwaga` i ręczny kafel przeżywają
  scalanie, zepsuty plik nie jest nadpisywany, kafel na nieistniejącą
  warstwę to odmowa z nazwą warstwy, a tabela z punktem „z terenu” zostaje
  wczytana zamiast nadpisana;
- **`proba3`, 11 sekcji** — każda odmowa nadal mówi, dlaczego; moduł
  nieodwracalny zostawia OBIE kopie; flagi `pyta` i `powtarzalny` docierają
  do QML;
- **`proba` i `proba2`** — załączniki N:1 bez zmian.

## Czego to NIE robi

- **Nie rusza `QfNaprawaProjektu.zbudujKlawisze()`.** Tamta funkcja nadal
  nadpisuje cały plik kafli i nadal daje „P” dwóm warstwom. Dopóki obie
  drogi istnieją, naprawa projektu potrafi skasować kafle dołożone tutaj.
  **To jest następna łatka, nie ta.**
- **Nie zakłada warstwy w projekcie bez `dane.gpkg`** — mówi o tym wprost
  i odsyła do biura.
- **Nie zgaduje treści paska.** Wskazuje ją człowiek; aplikacja dobiera
  tylko etykietę i kolor.
