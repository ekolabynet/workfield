# `dane/prywatne/` — warstwy, których nie wolno rozprowadzać z repo

Ten katalog jest w `.gitignore`. Leżą tu warstwy na licencjach niezgodnych
z GPL — przede wszystkim **CC BY-NC** (klauzula niekomercyjna jest sprzeczna
z GPL, bo GPL zabrania dyskryminacji pola zastosowania).

Co tu wkładamy:

| Plik | Źródło | Licencja |
|---|---|---|
| `fungalroot_*.csv` | FungalRoot (typy mikoryzy, poziom RODZAJU) | CC BY-NC 4.0 |
| `dcbp_*.csv` | Digital Catalogue of Biodiversity of Poland (KSIB) | CC BY-NC 4.0 |
| `try_*.csv` | TRY — cechy funkcjonalne | warunkowa, zależna od dawcy |
| `fitosocjologia_*.csv` | afiliacje syntaksonomiczne z atlas-roslin.pl | prawa zastrzeżone |

Skrypty budujące mają działać **bez tego katalogu** — brak nakładki ma dawać
uboższy słownik, nie błąd. Dystrybucja plików: NextCloud, tak jak
`wf_wskazniki.gpkg`.

Pełny rozbiór w `../../docs/LICENCJE_audyt.md`.
