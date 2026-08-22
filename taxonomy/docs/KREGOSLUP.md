# Kręgosłup taksonomiczny — co możemy mieć, co powinniśmy, co gdzie leży

Rozpoznanie 22.08.2026, czat wydzielony z „Pl@ntNet i metadane gatunków".
Siostry: `claude_PLANTNET_handoff_2026-08-22.md` (wejścia), `claude/SZABLON_DENDRO.md`
(pusta tabela `TAKSONY`), `WorkField_handoff_2026-08-21.md` (pasek podpowiedzi,
parser kodów).

Wszystko poniżej sprawdzone w źródłach albo na żywo w API. Rzeczy niesprawdzone
są oznaczone **[?]** — nie zgadujemy ich, tylko wiemy, gdzie sprawdzić.

---

## 0. Jedno zdanie, gdyby reszta się nie doczytała

**Kluczem łączenia zostaje nazwa kanoniczna (łacina jako tekst), a nie
identyfikator kręgosłupa** — bo identyfikatory kręgosłupów przestały być
stabilne. Kręgosłup daje pisownię, synonimy i rodzinę; identyfikatory wozimy
jako kolumny eksportowe, nie jako klucz główny.

---

## 1. Co się zmieniło w świecie, zanim zdążyliśmy wejść

**GBIF przestał budować własny kręgosłup.** Ostatnia aktualizacja: sierpień
2023. Od 2025/2026 domyślną taksonomią GBIF.org jest **Catalogue of Life
eXtended Release** (`checklistKey=7ddf754f-d193-4cc9-b351-99906754a03b`);
stary backbone (`d7dddbf4-…`) jest oznaczony jako *legacy, no longer updated*.

I druga rzecz, ważniejsza dla nas: **identyfikatory COL XR zmieniają się między
wydaniami**. Na forum GBIF opisany przypadek: takson pod `gbif.org/taxon/DMT`
po nowym wydaniu rozwiązuje się jako `KT8B2`, a stary adres zwraca 404.
Publicznego API do rozwiązywania wycofanych identyfikatorów **nie ma**.

Stąd decyzja z sekcji 0. Gdybyśmy oparli `WF_CECHY`, `wskazniki_polaczone`
i `SLOWNIK_GATUNKOW` na `gbif_key`, po najbliższym wydaniu XR część relacji
rozjechałaby się cicho — a to jest dokładnie ten rodzaj awarii, którego
uczyliśmy się unikać 20 i 21 sierpnia. **Objaw niemy jest gorszy od błędu.**

Dobra wiadomość: klucz, którego już używamy (`takson` ↔ `GATUNEK`, kanoniczna
łacina), jest odporny na tę zmianę. Nie trzeba nic przebudowywać.

---

## 2. Co możemy mieć — źródła, licencje, przydatność

| Źródło | Licencja | Wolno w repo? | Do czego u nas |
|---|---|---|---|
| **WFO Plant List** (World Flora Online) | **CC0** — „unrestricted for use" | **tak, bez warunków** | **kręgosłup offline**: rośliny‑only, ID `wfo-…`, wydania 21.06 i 21.12 |
| **Catalogue of Life / COL XR** | CC BY 4.0 | tak, z atrybucją + DOI wydania | dopasowanie w biurze, nazwy polskie (dziurawe), crosswalk do GBIF |
| GBIF backbone (legacy) | CC BY 4.0 | tak, z atrybucją | tylko jako `gbif_key` w eksporcie; **zamrożony 2023** |
| WCVP / POWO / IPNI (Kew) | CC BY + wymóg disclaimera | tak, ostrożnie | nomenklatura naczyniowych; źródło WFO |
| **Wikidata** | **CC0** | **tak** | **nazwy polskie** (P225 / P846 / P1843 + etykieta `@pl`), kultywary jako byty |
| **Akty prawne (Dz.U.)** | **domena publiczna** — art. 4 upapp | **tak, bez warunków** | progi, stawki, pomniki, IGO, ochrona |
| Digital Catalogue of Biodiversity of Poland (KSIB, GBIF) | **CC BY‑NC 4.0** | **NIE** | NC wyklucza repo pod GPL — nie dotykamy |
| Mirek i in. 2020 „Adnotowany wykaz…" | prawa zastrzeżone, tylko druk | **NIE** | wyłącznie do sprawdzania okiem |
| atlas‑roslin.pl | © Marek Snowarski, zgoda indywidualna | **NIE** | wyłącznie **link** 🌐 — tak jak zdecydowaliśmy |

Trzy wnioski, które warto wypowiedzieć wprost:

1. **Nazwy polskie nie mają otwartego, kompletnego źródła.** Sprawdzone na
   żywo: GBIF nie ma polskiej nazwy dla *Quercus robur* (zero wpisów `pol`),
   ma za to „Sosna Zwyczajna" z błędnymi wersalikami. Wikidata jest szersza
   i CC0, ale bez walidacji nomenklaturowej. **Nasza tabela nazw polskich
   będzie własnym opracowaniem** — tak jak macierz cech. To nie jest porażka,
   to jest ta sama sytuacja co przy `WF_CECHY`.
2. **Kultywarów nie ma w żadnym kręgosłupie.** Ani WFO, ani COL, ani IPNI
   (nomenklator ICN, nie ICNCP). Otwartego rejestru ICNCP po prostu nie ma.
   W dendrologii miejskiej kultywary to spora część inwentarza — więc to
   pole musi być NASZE, obok kręgosłupa, nie w nim.
3. **Akty prawne są najlepiej dostępnym źródłem, jakie mamy.** Art. 4 ustawy
   o prawie autorskim: akty normatywne nie stanowią przedmiotu prawa
   autorskiego. Załączniki z listami gatunków wolno przepisać co do znaku
   i opublikować. Kosztem pokrycia: kilkaset taksonów, nie 5761.

---

## 3. Sprawdzone na żywo: jak kręgosłup gubi kultywar

```
GET https://api.gbif.org/v2/species/match
    ?scientificName=Tilia cordata 'Greenspire'&kingdom=Plantae&verbose=true

"usage":       {"canonicalName": "Tilia cordata", "rank": "SPECIES"}
"diagnostics": {"matchType": "EXACT", "confidence": 85,
                "note": "name=110; authorship=0; classification=4;
                         rank=-30; status=1; score=85"}
```

**`matchType: EXACT`, pewność 85, a `'Greenspire'` zniknęło bez jednego
ostrzeżenia.** Jedynym śladem jest `rank=-30` w polu `note` — kara za
niezgodność rangi, której nikt nie czyta.

To jest wzorcowy objaw niemy. Stąd twarda zasada implementacji:

> **Kultywar odcinamy PRZED dopasowaniem i wozimy w osobnej kolumnie.
> Do kręgosłupa jedzie sama część gatunkowa.**

Druga pułapka z tej samej rodziny: przy `matchType: NONE` GBIF potrafi zwrócić
`confidence: 100` (znany błąd, `gbif/checklistbank#253`). Czyli:
**czytamy `matchType` PRZED `confidence`**, nigdy odwrotnie.

Trzecia: bez `kingdom=Plantae` rodzaj `Betula` trafia na błonkówkę
*Betula* Ashmead, 1902. Homonimy międzykrólestwowe (*Prunella*, *Oenanthe*,
*Betula*) to nie ciekawostka, tylko realny błąd danych.

---

## 4. Co jako tabela, co jako link, co jako API — podział

Granica jest jedna i wynika z terenu, nie z architektury: **w terenie nie ma
sieci.** Wszystko, co jest potrzebne przy wpisywaniu rekordu, musi leżeć
w pliku, który pojechał ze zleceniem.

### 4a. TABELE — jadą w projekcie, wracają ze zwrotem

| Tabela | Co niesie | Gdzie |
|---|---|---|
| **`TAKSONY`** | nazwa, kanoniczna łacina, kultywar, nazwa polska, **skrót**, ranga, progi prawne, IGO | `dane.gpkg` — **nieodtwarzalne** (człowiek dopisuje w terenie) |
| `WF_CECHY` | macierz rozróżniania (klucz `GATUNEK`) | `wf_wskazniki.gpkg` albo `dane.gpkg` |
| `wskazniki_polaczone` | EIV Tichý + Midolo (klucz `takson`) | `wf_wskazniki.gpkg` — **odtwarzalne** |
| `SLOWNIK_GATUNKOW` | Zarzycki, syntaksony, statusy, `ETYKIETA` (2824) | `wf_wskazniki.gpkg`, kanał prywatny (licencja!) |
| częstość lokalna (GBIF/iNat) | co faktycznie rośnie w okolicy | **`support.gpkg`** — odtwarzalne, raz na zlecenie |

Rozróżnienie robocze/podkład jest to samo co przy imporcie z 21.08:
**nieodtwarzalne → `dane.gpkg`, odtwarzalne → `support.gpkg`.**
Kręgosłup jako taki jest odtwarzalny — więc **pełne 1,6 mln nazw WFO nigdy nie
jedzie na telefon**. Na telefon jedzie słownik zlecenia: kilkaset pozycji,
poniżej megabajta.

### 4b. LINKI — jeden przycisk, zero danych u nas

- 🌐 **atlas‑roslin.pl** — już jest, decyzja licencyjna zapadła.
- 🌐 **GBIF / POWO** — strona taksonu, gdy w rekordzie jest `GBIF_KEY`.
- Link wychodzący nie jest publikacją cudzych danych. Wbudowanie treści — jest.

### 4c. API — wyłącznie w biurze, wyłącznie przy budowie słownika

| Usługa | Endpoint | Do czego |
|---|---|---|
| GBIF match | `api.gbif.org/v2/species/match` (`kingdom=Plantae`, `verbose=true`) | dopasowanie nazw przy budowie `TAKSONY` |
| GBIF parser | `api.gbif.org/v1/parser/name` | zapas, gdy nasz rozbiór polegnie |
| WFO matching | `list.worldfloraonline.org/matching_rest.php` | drugi głos przy spornych |
| GBIF vernacular | `api.gbif.org/v1/species/{key}/vernacularNames` | zaczyn nazw polskich |
| Wikidata SPARQL | `query.wikidata.org/sparql` | nazwy polskie hurtem (CC0) |

Żadne z nich nie jest wołane z telefonu. Limitów GBIF nie publikuje — obowiązuje
`User-Agent` z adresem, 4–8 połączeń, ponowienie przy 429. Przy 2824 wpisach
po deduplikacji zostaje kilkaset zapytań, czyli minuty.

---

## 5. Trzy tabele (zbudowane, nie proponowane)

### `TAKSONY` — słownik

**Tożsamość (nasza, stabilna):**
`NAZWA` (do wyświetlenia) · `GATUNEK` (kanoniczna łacina) · **`KROLESTWO`** ·
`ODMIANA` (kultywar dosłownie) · `NAZWA_PL` · `SKROT` · `SKROT_ZRODLO` ·
`RODZAJ` · `RANGA` · `HYBRYDA` · `KWALIFIKATOR` (cf/aff) ·
**`NAZWA_ZRODLOWA`** (co było w źródle — zostaje na zawsze)

**Klucz łączenia to PARA `(GATUNEK, KROLESTWO)`**, nie sama nazwa. Powód
w sekcji 10 — gdy dojdą zwierzęta i grzyby, *Iris* jest i kosaćcem,
i modliszką.

**Ślad dopasowania:** `STATUS` · `AKCEPTOWANA` · `RODZINA` · `DOPASOWANIE`
(matchType) · `PEWNOSC` · `DECYZJA`

**Prawo (po gatunku, ale nie jedną kolumną — patrz niżej):**
`PROG_CM` · `GRUPA_STAWKI` · `GRUPA_KRZEWY` · `POMNIK_CM` · `ZWOLN_CM` ·
`OWOCOWE` · `IGO` · `OCHRONA` · `ZRODLO_PRAWO` · **`WERSJA_PRAWA`** ·
`WERYFIKACJA` · `AKTUALIZACJA`

### `TAKSONY_XREF` — klucze obce

`GATUNEK` · `KROLESTWO` · `ZRODLO` (GBIF / COLXR / WFO / INAT / NCBI) ·
`ID_OBCE` · `WERSJA_ZRODLA` · `TYP_DOPASOWANIA` · `PEWNOSC` · `DATA`

Osobna tabela, nie kolumny w słowniku — bo źródeł będzie przybywać,
a kolumn nie chcemy dokładać przy każdym nowym serwisie. Każdy klucz obcy
niesie **wersję źródła i datę rozstrzygnięcia**, bo klucze obce wygasają.

### `WF_ZRODLA` — z czego to zbudowano

`KLUCZ` · `WERSJA` · `DATA` · `LICENCJA` · `UWAGA`

Pięć wierszy: warstwa prawna, kręgosłup, nazwy polskie, skróty, wersja
skryptu. To jest odpowiedź na pytanie zadane za rok: „skąd wzięła się ta
liczba w tym rekordzie".

### Dlaczego prawo to pięć kolumn, a nie jedna „grupa gatunkowa"

Bo cztery akty dzielą gatunki **na cztery różne sposoby**, i mierzą **na dwóch
różnych wysokościach**:

| Kolumna | Akt | Wysokość pomiaru | Wartości |
|---|---|---|---|
| `PROG_CM` | art. 83f ust. 1 pkt 3 u.o.p. | **5 cm** | 80 / 65 / 50 |
| `GRUPA_STAWKI` | Dz.U. 2017 poz. 1330 zał. 1 | 130 cm | 1–5 |
| `POMNIK_CM` | Dz.U. 2017 poz. 2300 zał. | 130 cm | 50 … 350 |
| `ZWOLN_CM` | art. 86 ust. 1 pkt 7 | 130 cm | 120 / 80 |

Przykład, dlaczego to nie jest przesada: **kasztanowiec zwyczajny** ma próg
83f **65 cm** (razem z robinią i platanem), ale w art. 86 siedzi w grupie
**120 cm** razem z topolami i wierzbami. Jedna kolumna „grupa" skleiłaby dwa
różne przepisy i dałaby złą odpowiedź w połowie przypadków.

Rozstrzyganie jest **kolumna po kolumnie**: gatunek → rodzaj → domyślne
(50 cm, grupa 5, zwolnienie 80 cm). Ustawa mówi „topoli, wierzb" — czyli
całymi rodzajami — więc poziom rodzaju musi być pierwszą klasą, nie wyjątkiem.

---

## 6. Co zbudowane (pliki obok tego dokumentu)

**`taksony_normalizacja.py`** — rozbiór nazwy z terenu, sama biblioteka
standardowa. Uruchomiony bez argumentów pokazuje autotest na 20 realnych
przypadkach. Radzi sobie z: autorstwem (`Mill.`, `Mill. ex Münchh.`),
kultywarem w apostrofach prostych, typograficznych i po `cv.`, `®`/`™`,
mieszańcem (`x`, `X`, `×` — ale `Buxus` zostaje *Buxus*), `sp.`/`spp.`,
`cf.`/`aff.`, `ssp.`→`subsp.`, NBSP z Worda i spacją doklejaną przez Gboard.

Nic nie ginie: kultywar, kwalifikator i hybryda mają własne pola, surowy ciąg
zostaje. Ta sama zasada co przy parserze kodów gatunków — **wiersze są
WYPROWADZANE z tego, co wpisał człowiek.**

**`prawo_gatunki_2026-08-22.csv`** — warstwa prawna, 142 wiersze, poziom
gatunku i rodzaju. Domena publiczna (art. 4 upapp). **Data w nazwie pliku
jest wersją** i trafia do kolumny `WERSJA_PRAWA` każdego wiersza słownika;
skrypt bierze automatycznie najnowszy plik `prawo_gatunki_*.csv`.

Stan weryfikacji po rundzie z aktami:

| Akt | Co niesie | Stan |
|---|---|---|
| Dz.U. 2017 poz. 1330 | grupy stawek 1–5 + krzewy | **z oryginalnego PDF-a Dziennika Ustaw** — grupy zgodne co do pozycji, dodane stawki krzewów (gr. 1 = 10 zł/m²: dereń rozłogowy, róża pomarszczona, sumak, tawuła kutnerowata, świdośliwa kłosowa) |
| art. 83f, 85, 86 u.o.p. | progi 80/65/50 i 120/80, 25 m², 50 m² | **potwierdzone w trzech niezależnych serwisach**, brzmienie identyczne |
| Dz.U. 2022 poz. 2649 | listy IGO | **z wiernej kopii PDF-a**, pozycje z numerami lp., w tym odroczenie *Celastrus orbiculatus* do 2.08.2027 |
| Dz.U. 2017 poz. 2300 | pomniki, obwody 50–350 | **źródła wtórne, zgodne co do słowa** — do zderzenia z PDF-em |
| Dz.U. 2014 poz. 1409 | ochrona gatunkowa | zał. 1 (ścisła) — wtórne, numery pozycji niepewne; **zał. 2 (częściowa) w ogóle nie do odczytania** — cis, kosodrzewina, wawrzynek wilczełyko itd. mają w CSV adnotację „źródło wtórne, sprawdzić" |

Nazwy łacińskie w całym pliku są **moim mapowaniem** nazw polskich
z załączników — akty posługują się wyłącznie polskimi, często rodzajowymi.

**`zbuduj_taksony.py`** — buduje trzy tabele w GPKG. Bez QGIS‑a, bez GDAL‑a,
bez `pip install`: sam `sqlite3`. Kopia zapasowa robi się sama (domyślnie do
`/tmp`, nie obok projektu — cztery `dane.gpkg.bak_*` w katalogu jadącym
w teren pamiętamy z 21.08). Tryb `--sucho` niczego nie zapisuje.

Skróty: `--skroty` wczytuje **istniejący słownik Gboarda** (format
`fraza⇥skrót⇥język`) albo zwykły CSV. Skróty stamtąd zostają dosłownie
(`SKROT_ZRODLO = gboard`), brakujące generują się **małymi literami**
(`SKROT_ZRODLO = auto`) — żeby na pierwszy rzut oka było widać, czego jeszcze
nikt nie używał w terenie. Kolizja rozstrzyga się na korzyść Gboarda:
`Tilia cordata` bierze Twoje `Lp2`, kultywar dostaje własne `tcgr`.

**`pobierz_nazwy_pl.py`** — nazwy polskie z Wikidata (CC0) partiami po 200
przez SPARQL, z odsianiem etykiet, które są tylko łaciną, i z GBIF
`vernacularNames` jako drugim głosem dla braków. Wynik wpina się przez
`--nazwy-pl`.

**`wepnij_taksony_w_formularz.py`** — konsola QGIS: ograniczenie miękkie na
`GATUNEK` (ostrzega, nie blokuje) plus pola wirtualne `_PROG`, `_PROG_INFO`,
`_IGO`, `_OCHRONA` liczone z `TAKSONY`. Pola wirtualne **nie zapisują się do
bazy** — celowo: prawo się zmienia, a wyliczona wartość sprzed roku byłaby
gorsza niż jej brak. **Nieuruchomione u mnie** (brak QGIS-a w sesji) — start
z `SUCHO = True`.

**`NOTICE_zrodla_danych.md`** — gotowy fragment do `NOTICE.md`.

Sprawdzone u mnie na próbce 16 wpisów: deduplikacja (`Festuca rubra` ×3 → 1),
kultywary rozbite poprawnie, import skrótów z Gboarda, trzy tabele
zarejestrowane w `gpkg_contents` jako `attributes` (bez tego QGIS ich nie
widzi), eksport słownika Gboarda działa.

---

## 7. Droga wdrożenia — cztery kroki, każdy sprawdzalny osobno

1. **Sucha próba na prawdziwym słowniku** (nic nie zapisuje):

       python3 zbuduj_taksony.py --sucho \
         --zrodlo /DATA/WorkField/szablony/wskazniki/slownik_gatunkow.csv \
         --kolumna GATUNEK

   Patrzymy na listę „do obejrzenia okiem" — to ona powie, ile naprawdę jest
   duplikatów i wpisów rodzajowych.

2. **Dopasowanie do kręgosłupa** (biuro, sieć, kilka minut):

       python3 zbuduj_taksony.py --sucho --gbif --mail twoj@adres.pl \
         --zrodlo … --kolumna GATUNEK

   Wynik odkłada się w `gbif_cache.json` — drugi przebieg jest darmowy.

3. **Zapis do szablonu:**

       python3 zbuduj_taksony.py --zrodlo … --kolumna GATUNEK \
         --gpkg /DATA/WorkField/szablony/szablon_inw_zzw/dane.gpkg \
         --gboard /DATA/WorkField/szablony/gboard_taksony.csv

4. **Kontrola miękka w formularzu** — `GATUNEK` zostaje tekstem (decyzja
   z 16.08), a `TAKSONY` daje podpowiadanie i ostrzeżenie. Warunek wyrażenia:
   `"GATUNEK" IN (SELECT NAZWA FROM TAKSONY)` — **ostrzega, nie blokuje**.

Krok 4 to zarazem wejście dla **paska podpowiedzi** z 21.08: `SKROT` → `NAZWA`
jest dokładnie tym, czego pasek potrzebuje, a eksport do Gboarda jest z tego
wyprowadzany, nie odwrotnie. **`TAKSONY` są źródłem prawdy, Gboard kopią.**

---

## 8. Pułapki (do zapamiętania, nie do odkrywania drugi raz)

1. **Kultywar ginie w kręgosłupie bez ostrzeżenia** — sprawdzone wyżej. Odcinać
   przed dopasowaniem.
2. **`matchType` przed `confidence`** — `NONE` z pewnością 100 jest realne.
3. **Zawsze `kingdom=Plantae`** — inaczej *Betula* to błonkówka.
4. **Nie dopasowywać fuzzy przez granicę rodzaju** — *Acer* i *Alnus* dzieli
   odległość edycyjna 3, a to zupełnie inne drzewa. Blokowanie po rodzaju
   załatwia to strukturalnie.
5. **Kultywarów nie wolno poprawiać fuzzy** — `'Fastigiata'` i `'Fastigiate'`
   to RÓŻNE kultywary. Literówki terenowe (`'Szmaragd'` vs `'Smaragd'`) czyści
   się osobno, w obrębie jednego gatunku.
6. **Deduplikacja skleja `Quercus cf. robur` z `Quercus robur`** — celowo, ale
   trzeba o tym wiedzieć: kwalifikator należy do obserwacji, nie do słownika.
7. **CC BY‑NC to nie jest licencja otwarta** — cały KSIB/DCBP odpada z repo,
   choćby był najwygodniejszy.
8. **Identyfikatory kręgosłupa wygasają** (COL XR: `DMT` → `KT8B2` → 404).
   Nie robić z nich klucza głównego.
9. **Rodzaj bywa jednostką prawa** („topoli, wierzb") — poziom rodzaju musi być
   pierwszą klasą w warstwie prawnej.

---

## 10. Serwisy zewnętrzne i wejście poza rośliny (decyzja 22.08)

Pytanie Piotra: skoro dojdą GloBI, FungalRoot i iNaturalist — a z nimi
zwierzęta, grzyby i bakterie — rozstrzygamy synonimy na żywo, czy wozimy
gotowe klucze?

**Odpowiedź: gotowe klucze, dla wszystkiego, z wersją i datą.**

Trzy powody, każdy sprawdzony:

1. **Serwisy i tak nie rozstrzygają na żywo.** GloBI dopasowuje nazwy
   u siebie przy indeksowaniu (silnikiem `nomer`) i pisze wprost: „only
   explicit name mappings are accepted, fuzzy matches are not included".
   Zapytanie synonimem `Quercus pedunculata` wróciło bez identyfikatora;
   `Quercus robur` wróciło z `NCBI:38942` albo `GBIF:7586523` — zależnie od
   tego, o jaką przestrzeń kluczy poprosisz (`taxonIdPrefix`).
2. **Sama nazwa przestaje być kluczem.** Homonimy międzykrólestwowe:
   *Iris* (kosaciec / modliszka), *Alsophila* (paproć / miernikowiec),
   *Morus* (morwa / głuptak), *Prunella*, *Oenanthe*, *Arenaria*, *Pieris*,
   *Dryas*, *Ficus*, *Chloris*. Wikipedia szacuje ~5000 nazw rodzajowych
   dzielonych między królestwa. Stąd `KROLESTWO` w kluczu.
   Ułatwienie: grzyby są pod tym samym kodem co rośliny (ICNafp), więc
   homonim roślina–grzyb jest nielegalny. Kolizje są tylko ICN ↔ ICZN ↔ ICNP.
3. **Klucz obcy też wygasa.** Najlepszy dowód: GBIF unieważnił własne
   `taxonKey`. Więc nie „zamroź raz", tylko **rozstrzygnij raz, zapisz
   z wersją, przelicz przy odświeżeniu kręgosłupa** — czyli przy bumpie.

Per serwis:

- **GloBI** — nie potrzebuje naszych identyfikatorów, ale lepiej wysyłać
  `GBIF:…`. Zrzuty na Zenodo są **CC0**, w tym gotowe `taxonMap.tsv.gz`
  (127 MB) i `taxonCache.tsv.gz` (358 MB) — crosswalk do zaciągnięcia raz.
- **FungalRoot** — dane są **rodzajowe** (typ mikoryzy przypisany całemu
  rodzajowi przy zgodności >67% obserwacji). Join po rodzaju, zero
  synonimów. Ale licencja **CC BY-NC** → kanał prywatny, nie repo.
  Wersja v2 niesprawdzona **[?]**.
- **iNaturalist** — własna taksonomia, a identyfikator po splicie potrafi
  zmienić znaczenie. Nie dotykamy jej wprost: rekordy iNat w GBIF niosą
  **oba** klucze naraz (`taxonID` iNat + `taxonKey` GBIF), więc ciągnąc iNat
  przez GBIF dostajemy crosswalk gratis. Koszt: tylko research-grade
  i ok. tydzień opóźnienia.
- **Bakterie** — nazwa jest najgorszym możliwym kluczem (GTDB: brak
  przekładu na NCBI, sufiksy niegwarantowane między wydaniami). Jeśli
  kiedyś wejdą — `NCBI:taxid`.

Narzędzie do rozstrzygania wsadowego: **`nomer`** (GPL-3, offline, 50+
matcherów, wejście TSV, wyjście TSV/JSON). Nie API per rekord.

---

## 11. Wersjonowanie — zasada (uwaga Piotra, 22.08)

Prawo i kręgosłup zmieniają się szybciej niż wydania aplikacji, więc
**każda z tych warstw wychodzi z datą albo numerem wersji**:

| Warstwa | Nośnik wersji | Kadencja |
|---|---|---|
| warstwa prawna | data w nazwie pliku `prawo_gatunki_RRRR-MM-DD.csv` → `WERSJA_PRAWA` | gdy zmieni się akt |
| kręgosłup | `WF_ZRODLA.kregoslup` | WFO: 21.06 i 21.12; odświeżenie przy bumpie |
| klucze obce | `TAKSONY_XREF.WERSJA_ZRODLA` + `DATA` | przeliczane razem z kręgosłupem |
| nazwy polskie | `WF_ZRODLA.nazwy_pl` | gdy przejdzie kolejna korekta |
| skrypt | `WF_ZRODLA.skrypt` | przy zmianie logiki budowy |

Reguła: **nie odświeżamy kręgosłupa „przy okazji"**. Odświeżenie to osobna,
świadoma operacja przy bumpie — jak rebase z upstreamem.

---

## 12. Decyzje zapadłe 22.08 i co zostało otwarte

**Zapadło:**

- **Nazwy polskie jadą do repo** jako własne opracowanie — z zastrzeżeniem
  i podaniem źródeł (Wikidata CC0, COL/GBIF CC BY). Treść zastrzeżenia jest
  w `NOTICE_zrodla_danych.md`: pokrycie niepełne, korekta ręczna, brak statusu
  nomenklatury urzędowej.
- **Rdestowce zostają na liście krajowej** (`PL_szeroka`) do czasu, aż
  wyjaśni się nowelizacja Dz.U. 2022 poz. 2649. Stan faktyczny: rozporządzenie
  2025/1422 dodało je do listy unijnej od 7.08.2025, GDOŚ potwierdza
  przeniesienie, ale tekst krajowy nadal je wymienia i **nowelizacji nie
  znaleziono** — jest tylko projekt w wykazie prac RM. **[?]**
- **Skróty:** importujemy istniejące z Gboarda dosłownie, nowe generują się
  małymi literami. Zrobione.
- **Odświeżenie kręgosłupa przy bumpie**, nie „przy okazji". Zapisane
  w sekcji 11.
- **Klucze obce trzymamy gotowe**, nie rozstrzygamy na żywo. Sekcja 10.

**Otwarte:**

1. **Załącznik nr 2 do Dz.U. 2014 poz. 1409 (ochrona częściowa)** — nie
   udało się odczytać z żadnego źródła. Cis, kosodrzewina, wawrzynek
   wilczełyko, bagno i reszta krzewinek siedzą w CSV z adnotacją „źródło
   wtórne, sprawdzić". To jest najpoważniejsza luka w warstwie prawnej.
2. **Numery pozycji w załączniku nr 1** (ochrona ścisła) nie układają się
   w ciąg — nazwy są pewne, numery nie.
3. **Dz.U. 2017 poz. 2300** — tabela pomnikowa zgodna w źródłach wtórnych,
   ale nie z PDF-a. Do zderzenia przy okazji.
4. **W UI dać „(rob.)"** przy wartościach, których `WERYFIKACJA` jeszcze nie
   przeszła — tak jak przy macierzy traw.
5. **`nomer` albo `taxonMap` GloBI** — zdecydować, którą drogą budujemy
   `TAKSONY_XREF`, gdy dojdą pierwsze zwierzęta i grzyby.
6. **Import skrótów z realnego słownika Gboarda** — u mnie przeszedł na
   próbce trzech haseł; Twój plik może mieć inny format eksportu.
