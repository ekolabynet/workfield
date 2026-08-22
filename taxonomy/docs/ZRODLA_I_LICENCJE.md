# Źródła danych taksonomicznych — fragment do `NOTICE.md`

Do wklejenia w `NOTICE.md` repozytorium. Wersje datowane, bo i prawo,
i kręgosłupy taksonomiczne zmieniają się w trakcie życia wydania.

---

## Dane taksonomiczne i słownikowe

Aplikacja rozprowadza słownik taksonów (`TAKSONY`) zbudowany ze źródeł
otwartych. Wersje użytych źródeł zapisuje tabela `WF_ZRODLA` w każdym
pliku bazy — to jest odpowiedź na pytanie „z czego to policzono".

### Kręgosłup nazw

- **WFO Plant List** (World Flora Online Consortium) — licencja **CC0 1.0**.
  Wydania co pół roku: 21 czerwca i 21 grudnia. Wersja użyta do budowy
  wpisana w `WF_ZRODLA` (klucz `kregoslup`).
  <https://wfoplantlist.org/>
- **Catalogue of Life eXtended Release** (COL Foundation) — **CC BY 4.0**,
  używany do dopasowania nazw i jako przestrzeń kluczy eksportowych.
  Cytowanie wymaga DOI konkretnego wydania.
  <https://www.catalogueoflife.org/>
- **GBIF** — usługa dopasowania nazw (`api.gbif.org`), dane kręgosłupa
  **CC BY 4.0**. Uwaga historyczna: własny kręgosłup GBIF nie jest
  aktualizowany od 2023 r.; identyfikatory z niego traktujemy jako
  eksportowe, nie jako klucz główny.

### Nazwy polskie

Tabela nazw polskich jest **własnym opracowaniem** zespołu WorkField,
zbudowanym na źródłach otwartych i skorygowanym ręcznie:

- **Wikidata** — dane strukturalne na licencji **CC0 1.0**
  (właściwości P225, P846, P1843 oraz etykiety `@pl`). <https://www.wikidata.org/>
- **Catalogue of Life / GBIF** — nazwy wernakularne `pol`, **CC BY 4.0**.

**Zastrzeżenie:** pokrycie nazw polskich w źródłach otwartych jest niepełne
i niejednolite (dla części pospolitych gatunków nazwy polskiej po prostu
brak, zdarza się też błędna kapitalizacja). Nazwy skorygowane ręcznie nie
mają statusu nomenklatury urzędowej ani naukowej; przy rozstrzygnięciach
formalnych obowiązuje piśmiennictwo, nie ten plik. Kolumna `WERYFIKACJA`
w słowniku mówi, czy wpis przeszedł przez ludzkie oko.

Do budowy tej tabeli **nie użyto** i nie rozprowadza się treści z publikacji
oraz serwisów o prawach zastrzeżonych — w szczególności „Rośliny naczyniowe
Polski. Adnotowany wykaz gatunków" (Mirek i in. 2020) oraz atlas-roslin.pl,
do którego aplikacja jedynie **linkuje**.

### Warstwa prawna (progi, stawki, pomniki, IGO, ochrona)

Dane pochodzą z aktów normatywnych, które zgodnie z art. 4 ustawy
o prawie autorskim i prawach pokrewnych **nie stanowią przedmiotu prawa
autorskiego**:

- ustawa z 16.04.2004 r. o ochronie przyrody (art. 83f, art. 85, art. 86),
- rozporządzenie MŚ z 3.07.2017 r. — stawki opłat (Dz.U. 2017 poz. 1330),
- rozporządzenie MŚ z 4.12.2017 r. — kryteria pomników przyrody
  (Dz.U. 2017 poz. 2300),
- rozporządzenie MŚ z 9.10.2014 r. — ochrona gatunkowa roślin
  (Dz.U. 2014 poz. 1409),
- rozporządzenie RM z 9.12.2022 r. — lista IGO (Dz.U. 2022 poz. 2649),
  wraz z rozporządzeniem wykonawczym Komisji (UE) 2025/1422.

**Zastrzeżenie:** akty prawne posługują się wyłącznie nazwami polskimi,
często rodzajowymi („topoli", „wierzb"). Przypisanie im nazw łacińskich
jest opracowaniem zespołu WorkField, a nie treścią aktu. Plik warstwy
prawnej nosi datę w nazwie (`prawo_gatunki_RRRR-MM-DD.csv`) i **nie jest
poradą prawną** — rozstrzyga tekst aktu, nie ten plik.

### Czego tu nie ma (świadomie)

- **Digital Catalogue of Biodiversity of Poland** (KSIB) — CC BY-**NC**;
  klauzula niekomercyjna wyklucza rozprowadzanie z tą aplikacją.
- **FungalRoot** — CC BY-**NC**; jeśli kiedyś wejdzie, to kanałem prywatnym,
  nie przez repozytorium.
- Liczby wskaźnikowe Zarzyckiego i afiliacje fitosocjologiczne — prawa
  zastrzeżone, kanał prywatny.
