# Obieg słownika: biuro wzbogaca, telefon czyta i wnioskuje

Decyzja z 22.08.2026. Odpowiada na pytanie Piotra: „chcę mieć bazę 2800
taksonów z metadanymi na telefonie, na desktopie robimy modyfikacje
i wzbogacenia, a na telefonie automatycznie generują się wnioski
o gatunku, o płacie, o obiekcie".

## Rozmiar przesądza pierwsze pytanie

Zmierzone na syntetycznym zbiorze o realnej strukturze — 2800 taksonów,
trzy tabele (`TAKSONY` 30 kolumn, wskaźniki 12 liczb, `WF_CECHY` 20 kolumn),
cztery indeksy:

| Co | Rozmiar |
|---|---|
| słownik z indeksami | **2,8 MB** |
| + indeks pełnotekstowy FTS5 (podpowiedzi) | **3,0 MB** |
| jedno zapytanie podpowiedzi (`ab*`, 10 wyników) | **0,03 ms** |

Czyli: **cały słownik jedzie na telefon, bez filtrowania na podzbiór
zlecenia.** Trzy megabajty przy zdjęciach liczonych w setkach megabajtów to
nic, a każdy filtr to nowa decyzja („które taksony są potrzebne w tym
zleceniu?"), która kiedyś okaże się zła w terenie. Dopiero gdyby doszły
zwierzęta i grzyby w komplecie, wróciłbym do tego pytania.

## Dwie tabele, nie jedna

To nie jest niuans, tylko ta sama zasada, którą trzymamy od 18.08:
**odtwarzalne osobno od nieodtwarzalnych, na telefonie wolno tworzyć,
nie konsolidować.**

| Tabela | Gdzie | Kto pisze | Los |
|---|---|---|---|
| `TAKSONY` | **`support.gpkg`** | wyłącznie biuro | **odtwarzalna** — podmieniana w całości przy wydaniu |
| `TAKSONY_LOKALNE` | **`data.gpkg`** | teren | **nieodtwarzalna** — wraca ze zwrotem, biuro scala do mastera |

Terenowy dopisek nigdy nie wchodzi do snapshotu. Gdyby wchodził, to samo
zlecenie wydane dwa razy dawałoby dwa różne słowniki, a scalenie do mastera
przestałoby być operacją odwracalną.

W podpowiedziach **lokalne ma pierwszeństwo** — człowiek, który przed chwilą
dopisał gatunek, musi go zobaczyć od razu. Ale przy zwrocie to biuro
decyduje, czy dopisek wchodzi do mastera, i dopiero tam przechodzi przez
normalizację i dopasowanie do kręgosłupa.

## Gdzie żyje master

Poza zleceniami. Jeden plik, wersjonowany datą, budowany skryptami z
`taxonomy/skrypty/`:

    taxonomy/dane/slownik/wf_taksony_master_RRRR-MM-DD.gpkg

Wydanie zlecenia kopiuje z niego snapshot do `support.gpkg`. Zwrot wnosi
`TAKSONY_LOKALNE` z powrotem. **Żadnego nowego mechanizmu — to są te same
szyny Wydaj/Przyjmij, którymi jeżdżą dane.**

### Co jedzie do repo (poprawka z 22.08 wieczorem)

Pierwsza wersja tego dokumentu mówiła „master nie jedzie do repo, bo są
w nim liczby Zarzyckiego". **To było zlanie dwóch różnych rzeczy w jedną:**
licencji i formy pliku. Poprawka:

| Co | Gdzie | Dlaczego |
|---|---|---|
| **CSV wszystkich warstw** — baza taksonów, prawo, nazwy polskie, klucze obce | **repo**, `taxonomy/dane/` | to jest **wynik pracy**, nie półprodukt. Diffowalny, do przejrzenia w PR, do poprawienia jedną linijką |
| **skrypty budujące** | **repo**, `taxonomy/skrypty/` | żeby dało się odtworzyć — nie żeby trzeba było |
| **GPKG** (master i snapshot) | **wydanie**, nie historia gita | to **wydruk** z CSV, powstaje w sekundy; binarka w gicie puchnie przy każdej zmianie |
| **warstwy CC BY-NC** (FungalRoot, KSIB, TRY) | **poza repo**, nakładka prywatna | NC jest sprzeczne z GPL — szczegóły w `LICENCJE_audyt.md` |

Zasada: **CSV jest źródłem prawdy, GPKG jest wydrukiem.** Kosztowna jest
kuratela — sprawdzone nazwy, zweryfikowane progi, poprawione literówki
w transkrypcji. Tego się nie generuje od nowa i to siedzi w repo jako tekst.
Zbudowanie z tego GPKG trwa kilka sekund, więc plik binarny nie musi mieć
historii — wystarczy, że jest przypięty do wydania z sumą kontrolną.

`zbuduj_taksony.py --csv-out` zapisuje zbudowany słownik z powrotem do CSV
(plus osobny plik `_xref.csv`) — to jest ta wersja, która ląduje w repo.

Transkrypcja Zarzyckiego zostaje **publicznie**, decyzją Piotra i z mocniejszą
podstawą, niż się wydawało: ochrona sui generis wydania z 2002 wygasła
31.12.2017. Nakładka prywatna zostaje tylko dla tego, co ma klauzulę NC.

## Wnioski: trzy poziomy, trzy różne mechanizmy

To jest sedno pytania i tu najłatwiej o pomyłkę, bo „wniosek" znaczy trzy
różne rzeczy.

### 1. Wniosek o gatunku — to jest odczyt, nie liczenie

„*Ailanthus altissima* — IGO, lista unijna, rozprzestrzeniony na szeroką
skalę". „*Taxus baccata* — ochrona częściowa". „Topola — próg 80 cm na 5 cm".

Nic się tu nie liczy: to wyszukanie w słowniku. **Wyliczone w biurze,
zapisane jako kolumny, telefon tylko czyta.** Konsekwencja: zmiana prawa nie
jest przeliczaniem na telefonie, tylko **nowym wydaniem słownika** — i stąd
`WERSJA_PRAWA` w każdym wierszu.

### 2. Wniosek o obiekcie — funkcja (gatunek × pomiar), liczona na żywo

„Obwód 74 cm przy progu 50 — wymaga zezwolenia". „Dąb 310 cm — spełnia
kryterium pomnikowe (300)". „Stawka: grupa 3".

Zależy od tego, co człowiek właśnie wpisał, więc **musi się przeliczać
natychmiast i nie wolno tego zapisywać do bazy**. Mechanizm już jest:
pola wirtualne z `wepnij_taksony_w_formularz.py` (`_PROG`, `_PROG_INFO`,
`_IGO`, `_OCHRONA`). Wyliczona wartość sprzed roku w rekordzie byłaby gorsza
niż jej brak — bo wygląda jak pomiar, a jest interpretacją nieaktualnego
przepisu.

### 3. Wniosek o płacie — agregat po spisie, na żądanie

Profil siedliska ze średnich ważonych pokryciem (EIV), udział gatunków
ektomykoryzowych, obecność gatunków chronionych i IGO, najbliższy syntakson.

Trzy warunki, żeby to nie zaszkodziło:

- **Liczony na żądanie, nie przy każdej literze.** Przycisk „przelicz płat",
  nie przeliczanie przy każdym zdarzeniu edycji.
- **Pokazywany ze śladem** — z ilu gatunków, jakim pokryciem ważony, którą
  wersją słownika. Wniosek bez śladu jest nie do sprawdzenia, a za pół roku
  nie do obrony przed zamawiającym.
- **Zapisywany tylko wtedy, gdy człowiek go zatwierdzi** — i wtedy jako
  interpretacja z datą i wersją słownika, nie jako pomiar.

## Twarda zasada, wspólna dla wszystkich trzech

> **Wniosek pokazuje, z czego wynika, i nigdy nie udaje obserwacji.**

To jest ta sama linia, na której 22.08 odrzuciliśmy pomoc AI przy
rozpoznawaniu w terenie („nie leczymy dżumy niepewności cholerą
konfabulacji") i na której stoi macierz cech: **narzędzie ma podawać fakty
i ich źródło, a nie orzekać za człowieka.** Lista kandydatów do sprawdzenia
okiem — tak. Wpisanie wniosku do pola jako fakt — nie.

Praktycznie: każdy wniosek ma widoczne „skąd to" (`ZRODLO_PRAWO`,
`WERSJA_PRAWA`, liczba wierszy w agregacie), a jego wartość albo nie jest
zapisywana wcale (poziom 1 i 2), albo jest zapisywana z podpisem człowieka
i wersją słownika (poziom 3).

## Co trzeba zbudować, w kolejności

1. **`zbuduj_taksony.py --master`** — budowa mastera z pełnym kompletem
   metadanych (wskaźniki, cechy, prawo, nazwy polskie) zamiast tabeli
   w szablonie zlecenia. Dziś skrypt umie już wszystko poza rozdzieleniem
   „master vs snapshot".
2. **`TAKSONY_LOKALNE` w szablonie** — pusta tabela plus reguła
   pierwszeństwa w podpowiedziach.
3. **Scalanie dopisków przy zwrocie** — operacja biurowa, przez
   normalizację. **Nigdy na telefonie** (zasada z 18.08).
4. **Indeks FTS5 na snapshotcie** — 0,2 MB, daje podpowiedzi w 0,03 ms.
   Warunek paska podpowiedzi z 21.08.
5. **Przycisk „przelicz płat"** — dopiero gdy 1–4 stoją.

## Czego ten dokument nie rozstrzyga

- **Czy tabela zwierząt (805 gatunków) jedzie na telefon.** Osobne pytanie
  z `OCHRONA_ZWIERZAT.md`; rozmiarowo bez znaczenia, sensownie — zależy od
  rodzaju zlecenia.
- **Jak często odświeżamy master.** Propozycja stoi w `WERSJE.md`: przy
  bumpie, nie „przy okazji".
- **Czy snapshot ma być ten sam dla wszystkich zleceń** — na razie tak.
  Filtrowanie po zleceniu wraca dopiero, gdy plik przestanie się mieścić.
