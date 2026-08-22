# Rejestr wersji warstw

Prawo i kręgosłupy taksonomiczne zmieniają się szybciej niż wydania
aplikacji, więc **każda warstwa wychodzi z datą**. Ten plik jest jedynym
miejscem, gdzie widać wszystkie naraz.

Reguła: **nie odświeżamy warstwy „przy okazji"**. Odświeżenie to osobna,
świadoma operacja przy bumpie — jak rebase z upstreamem. Po każdym
odświeżeniu dopisujemy wiersz tutaj i przeliczamy `TAKSONY_XREF`.

## Warstwa prawna — rośliny

| Wersja | Data | Zakres | Stan weryfikacji |
|---|---|---|---|
| `prawo_gatunki_2026-08-22.csv` | 2026-08-22 | 142 wiersze; progi 83f, grupy stawek (drzewa i krzewy), pomniki, zwolnienia art. 86, IGO, ochrona gatunkowa | stawki Dz.U. 2017/1330 **z oryginalnego PDF**; progi 83f/86 potwierdzone w 3 serwisach; IGO Dz.U. 2022/2649 z wiernej kopii PDF; pomniki Dz.U. 2017/2300 **źródła wtórne**; ochrona Dz.U. 2014/1409 zał. 1 wtórne, **zał. 2 nieodczytany** |

Otwarte przy tej wersji: załącznik 2 rozporządzenia o ochronie gatunkowej
roślin (ochrona częściowa — cis, kosodrzewina, wawrzynek wilczełyko) siedzi
w pliku z adnotacją „źródło wtórne, sprawdzić". Rdestowce **zostają na
liście krajowej** decyzją Piotra, mimo że rozporządzenie 2025/1422 przeniosło
je na listę unijną — nowelizacji krajowej nie znaleziono.

## Warstwa prawna — zwierzęta

| Wersja | Data | Zakres | Stan weryfikacji |
|---|---|---|---|
| `ochrona_zwierzat_2016-2183.csv` | 2026-08-22 | 805 wierszy: zał. 1 (592 ścisła), zał. 2 (211 częściowa), zał. 3 (2 pozyskiwane) | **z oryginalnego PDF Dziennika Ustaw**, numeracja bez luk; 5 pozycji przepisanych ręcznie (wiersze łamane) |
| `strefy_ochrony_2016-2183.csv` | 2026-08-22 | 30 pozycji zał. 4, promienie stref i terminy | **z oryginalnego PDF**, przepisane wzrokowo; `Mergus serrator` do sprawdzenia |

Otwarte: czy rozporządzenie było nowelizowane po 2016 r. — niesprawdzone.

## Kręgosłup

| Wersja | Data | Uwagi |
|---|---|---|
| — | — | jeszcze nie zaciągnięty; dopasowanie robione doraźnie przez `api.gbif.org/v2/species/match` |

Docelowo: **WFO Plant List** (CC0, wydania 21.06 i 21.12) jako kręgosłup
offline dla roślin, **COL XR** jako przestrzeń kluczy eksportowych.
Uwaga historyczna: własny kręgosłup GBIF nie jest aktualizowany od 2023 r.,
a identyfikatory COL XR zmieniają się między wydaniami — stąd zasada, że
klucz obcy nie jest kluczem głównym.

## Nazwy polskie

| Wersja | Data | Źródło | Uwagi |
|---|---|---|---|
| — | — | Wikidata (CC0) + GBIF vernacular (CC BY) | do zbudowania `pobierz_nazwy_pl.py`; potem korekta ręczna |

Decyzja: **jedzie do repo** jako własne opracowanie, z zastrzeżeniem
i podaniem źródeł (treść w `docs/ZRODLA_I_LICENCJE.md`).

## Skrypty

| Plik | Wersja | Zmiana |
|---|---|---|
| `zbuduj_taksony.py` | 2026-08-22 | trzy tabele wyjściowe, `KROLESTWO` w kluczu, import skrótów z Gboarda, `WERSJA_PRAWA` w każdym wierszu |
| `taksony_normalizacja.py` | 2026-08-22 | pierwsza wersja; autotest na 20 przypadkach |
| `pobierz_nazwy_pl.py` | 2026-08-22 | pierwsza wersja; nieuruchomiona na pełnym słowniku |
| `parsuj_ochrona_zwierzat.py` | 2026-08-22 | rozpoznawanie gromad po kroju pisma, nie po liście nazw |
| `wepnij_taksony_w_formularz.py` | 2026-08-22 | pierwsza wersja; **nieuruchomiona w QGIS** |

## Jak dopisać nową wersję warstwy prawnej

1. Nowy plik `dane/prawo/prawo_gatunki_RRRR-MM-DD.csv` — **stary zostaje**.
   Skrypt bierze najnowszy sam; stary jest potrzebny, żeby odtworzyć, na
   jakiej podstawie policzono zbiór sprzed pół roku.
2. Wiersz w tabeli wyżej: co się zmieniło i skąd to wiadomo.
3. Przebudowa słownika w szablonie — `WERSJA_PRAWA` w `TAKSONY` zmieni się
   sama, bo bierze się z nazwy pliku.
