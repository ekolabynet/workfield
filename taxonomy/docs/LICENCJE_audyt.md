# Audyt licencyjny — co wolno trzymać w publicznym repo

Stan na 22.08.2026. **To nie jest opinia prawna** — to zebrane fakty
i przepisy do decyzji, którą podejmuje Piotr. Przy każdej pozycji jest
podstawa, żeby dało się ją sprawdzić, a nie tylko uwierzyć.

Kontekst: repo jest **publiczne i pod GPL**. To ma jedną konsekwencję, którą
łatwo przeoczyć: **GPL nie znosi klauzuli niekomercyjnej**. Licencja GPL
zabrania dyskryminacji pola zastosowania, więc dane na CC BY-**NC** nie tylko
naruszają warunki źródła — są też sprzeczne z licencją samej aplikacji.
Dlatego „NC" pojawia się niżej jako twarda blokada, nie jako ostrożność.

---

## Zarzycki — decyzja Piotra ma mocniejszą podstawę, niż wyglądała

Piotr przepisał liczby z publikacji drukowanej i sam przekonwertował
nazwy oraz format liczb. Decyzja: trzymamy publicznie.

**Argument „przepisałem sam" akurat nie broni.** TSUE, sprawa **C-304/07
(Directmedia)**: przeniesienie treści bazy na inny nośnik jest „pobraniem"
niezależnie od metody — wprost wymieniono „**even a manual recopying**".
Ręczne przepisanie z książki to to samo, co skan, tylko wolniejsze.

**Ale broni co innego, i to mocno — termin ochrony wygasł.** Ustawa
z 27.07.2001 o ochronie baz danych, art. 10 ust. 2:

> „Jeżeli w okresie, o którym mowa w ust. 1, baza danych została w jakikolwiek
> sposób udostępniona publicznie, okres jej ochrony wygasa z upływem
> **piętnastu lat** następujących po roku, w którym doszło do jej udostępnienia
> po raz pierwszy."

Wydanie II ukazało się w **2002** → prawo sui generis do tej edycji wygasło
**31 grudnia 2017 r.** Ust. 3 restartuje termin tylko dla nowej, istotnie
zmienionej wersji („mających znamiona nowego istotnego (…) nakładu") —
wydań po 2002 nie znaleziono.

**Drugi argument, niezależny.** TSUE **C-203/02 (British Horseracing Board)**,
par. 31 i 38: prawo sui generis chroni nakład na **zebranie** istniejących
danych, nie na ich **wytworzenie**. Liczby wskaźnikowe są oceną ekspercką
autorów, czyli danymi wytworzonymi — to klasyczny przypadek „spin-off",
w którym ochrona w ogóle nie powstaje. Polskiego orzecznictwa na tym tle
nie znalazłem, więc traktuję to jako argument, nie pewnik.

**Co zostaje mimo wszystko:** prawo autorskie do **struktury, przedmowy,
opisów metody i autorskich komentarzy** trwa 70 lat i wygasłe nie jest.
Surowe liczby nie są utworem. Praktyczna reguła: **przepisujemy liczby,
nie tekst, nie układ tabel, nie komentarze.**

### I rzecz najbardziej praktyczna: część tych danych jest już otwarta

**EIVE 1.0** (Dengler, Jansen i in. 2023), Zenodo DOI
**10.5281/zenodo.7534792**, licencja **CC BY 4.0**. Plik
`EIVE_Paper_1.0_SM_02.xlsx` zawiera 31 systemów wskaźnikowych z wartościami
**oryginalnymi i przeskalowanymi**, a wśród nich system o kodzie **PL** —
opisany w tabeli źródeł wprost jako „Zarzycki (1984), Zarzycki et al. (2002)",
**2209 taksonów roślin naczyniowych**.

Czyli M, N, R, L i T z Zarzyckiego są dostępne legalnie, z atrybucją i z DOI.
Nie ma tam wymiarów, których EIVE nie obejmuje — kontynentalizmu, granulometrii,
próchnicy, formy życiowej. Te zostają z transkrypcji Piotra.

**Zastosowanie, które warto rozważyć niezależnie od licencji:** przepuścić
własną transkrypcję przez EIVE jako **drugi głos**. Rozbieżność wskaże
literówkę w przepisywaniu szybciej niż jakikolwiek przegląd ręczny.
(Zawartości pliku nie obejrzałem — Zenodo blokuje pobranie z tej sesji. **[?]**)

---

## Co jest twardo poza repo

### IUCN Red List — **nie**, i to z dwóch niezależnych powodów

Terms of Use IUCN:

> „All forms of **reposting**, and any sub-licensing, reselling, or other forms
> of **redistribution of IUCN Red List Data in their original format, either
> whole or in part** (…) are **strictly prohibited** without the prior written
> permission of IUCN."

> „Neither (a) IUCN Red List Data nor (b) any work derived from or based upon
> IUCN Red List Data (…) may be put to **Commercial Use** without the prior
> written permission of IUCN."

Plik ze statusami w publicznym repo to wprost „reposting". Do tego zakaz
użycia komercyjnego zderza się z GPL. Dwie blokady, każda wystarczająca.

**Uwaga praktyczna, bo to nas dotyczy bezpośrednio:** GBIF `/v2/species/match`
zwraca pole `additionalStatus` z kategorią IUCN. `zbuduj_taksony.py` **go nie
czyta i nie zapisuje** — i to ma zostać świadomą decyzją, nie przypadkiem.
Gdyby kiedyś status zagrożenia był potrzebny, zamiennikiem jest polska lista
z rozporządzenia (akt normatywny → domena publiczna).

### CC BY-NC — cała rodzina odpada

- **FungalRoot** (typy mikoryzy) — CC BY-NC 4.0.
- **Digital Catalogue of Biodiversity of Poland / KSIB** — CC BY-NC 4.0.
- **TRY** (cechy funkcjonalne) — licencja warunkowa, zależna od dawcy danych.

Wszystkie do kanału prywatnego, nigdy do repo. To nie jest ostrożność —
NC i GPL są sprzeczne.

### Prawa zastrzeżone

- **Mirek i in. 2020**, „Rośliny naczyniowe Polski. Adnotowany wykaz gatunków"
  — tylko druk, brak licencji otwartej. Wolno z niej **sprawdzać**, nie wolno
  jej **przepisywać** — różnica jest realna: weryfikacja faktu to nie
  pobranie zestawienia.
- **atlas-roslin.pl** — © Marek Snowarski, zgoda indywidualna, „zwykle" tylko
  do użytku niekomercyjnego. Wyłącznie **link** 🌐, zero treści u nas.

### Pl@ntNet — dwie różne rzeczy, dwie różne odpowiedzi

- **Metadane obserwacji** (nazwa gatunku, lokalizacja, data) — **CC BY**.
  Zapis własnego wyniku oznaczenia w bazie użytkownika jest w porządku.
- **Zdjęcia** — **CC BY-SA**. Share-alike jest wirusowy i **niekompatybilny
  z GPL w obrębie jednego utworu**. Miniatury nie pakujemy do drzewa kodu;
  gdyby kiedykolwiek miały gdzieś trafić, to z własną, wyraźnie oznaczoną
  licencją i poza repo.
- **[?]** Klauzul o retencji wyników nie ma w publicznych ToS. Jest osobny
  „API Access Agreement v4.2" (PDF), którego nie udało się otworzyć —
  **do pobrania ręcznie**, bo najpewniej to on reguluje przechowywanie wyników.
  Osobno: powyżej **500 zapytań dziennie** użycie komercyjne jest płatne.

### Dane miejskie — zależy od miasta

- **Szczecin, „Drzewa w Szczecinie"** — CC BY 4.0, „może być ponownie
  wykorzystywany bez ograniczeń". Wolno.
- **Kołobrzeg, inwentaryzacje dendrologiczne** — CC BY 4.0. Wolno.
- **Gdańsk (GeoGdańsk)** — brak wskazanej licencji otwartej, do tego
  zastrzeżenie o charakterze „roboczym, poglądowym". Nie brać do repo.
- **Warszawa** — warunki ponownego wykorzystania niesprawdzone. **[?]**

---

## Czego wolno bez zastrzeżeń

| Źródło | Licencja | Warunek |
|---|---|---|
| **Akty prawne (Dz.U.)** | domena publiczna, art. 4 pr.aut. | żaden |
| **WFO Plant List** | CC0 | żaden |
| **Wikidata** | CC0 | żaden |
| **EIVE 1.0**, **Tichý i in. 2023**, **Midolo i in. 2023** | CC BY 4.0 | cytowanie z DOI |
| **Catalogue of Life / COL XR** | CC BY 4.0 | atrybucja + DOI wydania |
| **GBIF backbone** (legacy) | CC BY 4.0 | atrybucja |
| **WCVP / POWO / IPNI** (Kew) | CC BY | atrybucja **+ disclaimer**: „RBG, Kew cannot warrant the quality or accuracy of the data" |
| **Twoje własne opracowania** — macierz cech, skróty, nazwy polskie po korekcie, transkrypcja Zarzyckiego | Twoje | Ty decydujesz; warto nadać jawną licencję, żeby nie było wątpliwości |

---

## Rzecz, o której nie rozmawialiśmy, a jest realna

**Zdjęcia terenowe od wolontariuszy.** Telefony ochotników robią zdjęcia,
które trafiają do `ZAL_*` i mogą kiedyś pójść dalej — do raportu, na stronę,
do zbioru treningowego. Prawa autorskie ma **autor zdjęcia**, czyli
wolontariusz, a nie właściciel bazy.

To nie jest problem dopóki dane zostają u zleceniodawcy. Staje się nim
w momencie publikacji. Tanie rozwiązanie: jedno zdanie w umowie albo
w regulaminie akcji, na jakiej licencji zdjęcia są przekazywane — najlepiej
CC BY albo CC0. **Wcześniej jest to formalność; później bywa nie do
odkręcenia**, bo trzeba wracać do każdej osoby z osobna.

---

## Do domknięcia

1. **Pl@ntNet API Access Agreement v4.2** — pobrać ręcznie, przeczytać
   klauzule o retencji i własności wyników.
2. **`EIVE_Paper_1.0_SM_02.xlsx`** — obejrzeć kolumnę systemu PL i porównać
   z transkrypcją Zarzyckiego.
3. **Warunki ponownego wykorzystania danych Warszawy** — jeśli kiedyś
   sięgniemy po Bazę Zieleni.
4. **Własna licencja na nasze opracowania** — dziś domyślnie „wszystkie prawa
   zastrzeżone", co przy publicznym repo jest sprzeczne z intencją.
   Kandydat: **CC BY 4.0** na dane, GPL na kod.
