# WorkField — do zrobienia

Stan na **09.09.2026, 02:00**.

## Jak z tego korzystać

Pozycja wchodzi tu tylko wtedy, gdy da się powiedzieć **co**, **gdzie w kodzie**
i **po czym poznam, że zrobione**. „Poprawić stylizację" nie jest pozycją.
„Ekran stylizacji nie wypełnia listy atrybutów — `LayerTreeItemProperties.qml`"
jest.

Pozycja znika dopiero po **sprawdzeniu na telefonie**. Jeśli okaże się, że
problemu nie było — przenosimy ją do „Obalone" z datą i powodem, nie kasujemy.
Dziś dwie pozycje zniknęły przez pomiar, nie przez naprawę, i to też jest wiedza.

**Nie piszemy „ODŁOŻONE".** To słowo brzmi jak stan przejściowy, a opisuje
trwały. Commit `d5066311c` mówił „ODBIORNIK ODŁOŻONY" i sygnał emitował
w próżnię przez trzy tygodnie. W kodzie: `NIEPODŁĄCZONE` albo `TODO`.

---

## A. Utrata danych

Rzeczy, przez które praca z terenu przepada albo staje się nieodnajdywalna.

### A1. 17 duchów w PZE — wyjaśnić i odzyskać
`zzw_pze_2605_inw_v8_0`, `fid` 135–154. Płaty z `KOMPLET` i zapisem
gatunkowym do 1500 znaków, **`geom` puste**. Nie widać ich na mapie.

- To **nie jest podział** — sprawdzone 09.09: żaden duch nie ma żywego
  bliźniaka o tej samej nazwie.
- `fid` tworzą ciasny blok → podejrzenie **jednej sesji terenowej**, w której
  zapis geometrii nie działał wcale.
- Do sprawdzenia: `DATA_WIZJI_LOKALNEJ` i `WYKONAWCA` w tym bloku.
- Rosną między wydaniami: v6_0 → 3, v7_0 → 4, v8_0 → 17.

**Zrobione, gdy:** wiadomo, skąd się wzięły, a te z pracą mają odtworzoną
geometrię (zdjęcia dają pozycję z EXIF — patrz D3).

### A2. Rozbicie multipoligonu i scalanie nie przepinają załączników
`NarzedziaProjektu::splitParts()` (`narzedziaprojektu.cpp:1397`),
wołane z `QgisMobileapp.qml:6683`.

Po rozbiciu stary `fid` znika, nowe powstają, a wiersze `ZAL_*` zostają
z martwym `ID_RODZICA` — **po cichu**. 08.09 osierociło to 4 zdjęcia przy
płacie 316 (PTR); naprawione ręcznie 09.09 przez stożki widzenia.

- `splitParts` zwraca `QVariantMap` — sprawdzić, czy niesie nowe `fid`.
- `ZalacznikiUtils` wie, która tabela należy do której warstwy.
- Aplikacja ma **zapytać**, do której części przypiąć załączniki, a nie milczeć.
- Drugi krok: sama proponuje odpowiedź po pozycji zdjęcia (D3).

**Zrobione, gdy:** po rozbiciu płatu z załącznikami pada pytanie i żaden
wiersz nie zostaje bez rodzica.

### A3. Kopie na nośnik — wznowić nawyk
`QfKopiaPanel.qml` działa, ale „trochę zapomniana rzecz" (cytat z 09.09).

Dziś cały dzień pracy istniał w jednym egzemplarzu w `Android/data`,
a scalona `v6_0` jest jedyną kopią na dysku laptopa.

**Zrobione, gdy:** jest zapisana zasada, kiedy robimy kopię na USB.

---

## B. Aplikacja milczy

Mechanizm działa i nie mówi, że działa — albo że nie działa.

### B1. Znaczek zapisu w formularzu, trzy stany
Zgłoszenie z terenu 09.09: formularz przyjmuje wpisy przy zamkniętym oknie
i nie ma wtedy jak zapisać.

- Na sztywno w nagłówku formularza (tam już jest ikona aparatu z 16.08).
- **Trzy stany**, nie dwa: aktywny / nieaktywny / **są niezapisane zmiany**.
- Nieaktywny po tapnięciu **mówi dlaczego**: „nic do zapisania" /
  „warstwa tylko do odczytu" / „brak geometrii".
- To poprawka **widoczności**; osobno zostaje pytanie, czy formularz
  w trybie podglądu ma w ogóle przyjmować tekst.

**Zrobione, gdy:** widać stan bufora bez czytania, a wyszarzony znaczek
podaje powód.

### B2. Trzeci przycisk w dialogu geometrii — przyciąganie
Dialog `dialogGeometrii` (`QgisMobileapp.qml`) ma od 09.09 dwie akcje:
wyłącz unikanie nakładania, wyłącz edycję topologiczną. Brakuje trzeciej.

**Przyciąganie jest przyczyną, edycja topologiczna tylko ją wzmacnia** —
przy tolerancji 20 px i płacie kilkumetrowym wierzchołki doskakują do siebie
i obrys ściąga się w punkt.

- `qgisProject.snappingConfig` jest dostępne z QML — wzorzec
  kopiuj-zmień-przypisz w `QfMainDrawer.qml:130–133`.
- `NarzedziaProjektu::stanProjektu()` **już czyta tolerancję** (komentarz:
  „ta liczba kosztowała dzień terenu 25.08").
- Komunikat ma podać liczbę: „obwiednia 0,3 m, przyciąganie 20 px ≈ 4 m
  przy tej skali".

**Zrobione, gdy:** dialog dla „zlepka" proponuje wyłączenie przyciągania
i pokazuje obie liczby.

### B3. Tłumik na dialog geometrii
Kontrola „zlepka" siedzi w miejscu, przez które przechodzi **każda** zmiana
geometrii. Przy rysowaniu małego obiektu dialog może odpalić się kilka razy.

**Zrobione, gdy:** przy rysowaniu płatu pada najwyżej raz.

### B4. Kontrola „w bazie, a nie w indeksie" jako stały punkt zwrotu
Jedno zapytanie wykrywa całą rodzinę duchów:

```sql
SELECT count(*) FROM FITO_PLATY
 WHERE fid NOT IN (SELECT id FROM rtree_FITO_PLATY_geom);
```

09.09 złapało pusty płat 470 w PTR i 17 duchów w PZE — przypadkiem, przy
okazji indeksów.

**Zrobione, gdy:** `obieg.py pobierz` wypisuje tę liczbę razem z licznościami tabel.

### B5. `representFileSize(undefined)` zwraca „0 B"
`FileUtils`. Brak pomiaru udający pomiar — 09.09 o krok od ogłoszenia,
że kopia bazy jest pusta, gdy była zdrowa (miała 3,3 MB, a pole nazywa się
`fileSize`, nie `size`).

**Zrobione, gdy:** przy `undefined` mówi „brak danych".

---

## C. Narzędzia

### C1. Numeracja `0.11.40` zamiast `0.11.0.b40` — **pierwsza na jutro**
`scripts/build.sh` ma dziś **trzy warstwy obejść**:
sufiks `.bN` doklejany do `APP_VERSION_STR`, `APK_VERSION_CODE` wpisany
na sztywno, martwa zmienna `APK_VERSION_CODE_STARE`.

Pomysł Piotra (09.09): trzecia pozycja numeru **jest** licznikiem buildów.
Wtedy `awk -F.` liczy kod sam (`0*10000 + 11*100 + 40 = 1140`), litera znika,
a `bump.sh` podbija jedną liczbę.

- Uwaga: po `0.11.99` kolejny build da `0.12.0` — kod rośnie, ale numer
  wygląda jak wydanie. Sto buildów to około dwóch tygodni.

**Zrobione, gdy:** `build.sh` nie ma żadnego z trzech obejść, a APK nazywa się
`workfield-0.11.41-kod1141-arm64.apk`.

### C2. Konsola v0.4
Wtyczka, więc **bez builda APK**.

- historia **przeżywa zamknięcie aplikacji** (`QSettings`,
  `WorkField/konsolaHistoria`),
- **przypinanie** wpisów — inaczej rotacja zje gotowce,
- komentarz pierwszą linią robi z historii **bibliotekę poleceń**
  („quasi funkcjonalne code chunks" — Piotr, 08.09),
- przycisk **„Kopiuj"** — `platformUtilities.copyTextToClipboard` istnieje,
- znak zachęty **`SQL>` / `JS>`** — pomyłka zakładki kosztuje przebieg,
- **pole czyści się po wykonaniu** (dziś teksty nakładają się na siebie),
- przycisk **„Wykonaj" przy prawej krawędzi** pola, żeby nie chować klawiatury.

### C3. `obieg.py`
- **DCIM kopiowane rekurencyjnie.** 09.09 dwa razy zgubiło podkatalog
  (`platy_473`, `zdjecia_fito_2`) — `cp` bez `-r`.
- **Kontrola sierot przy wysyłce**, nie jako ręczne zapytanie, o którym
  trzeba pamiętać. Zero sierot = warunek wydania.
- **Pomijać `.kosz/` przy zwrocie** — inaczej wykasowane pliki wrócą do biura
  i odżyją przy scalaniu.
- Wysyłka **pojedynczego pliku** (dziś `projekt.qgs` trzeba pchać `adb push`).

### C4. Skrypty leżą w dwóch miejscach
`~/WorkField/skrypty` i `QField/skrypty`. 09.09 szukaliśmy
`gpkg_wyzwalacze.py` w złym. Przy dwudziestu kilku skryptach to będzie wracać.

### C5. Menedżer plików — reszta
Ekran działa od 09.09 (`QfMenedzerPlikow.qml`). Zostaje:

- **korzeń w ustawieniach** — `settings.value("WorkField/korzenPlikow")`
  jest czytane, ale nie ma gdzie go ustawić,
- **karta SD** — `appDataDirs()` zwraca dwa katalogi, widać tylko pierwszy,
- **wiersze katalogów niższe** (54 px marnowane, brak drugiej linii),
- **pasek się zagęszcza** — sześć przycisków, przy dłuższych napisach
  rozbić na dwa rzędy.

### C6. `.przed_*` w repo kodu
`qffeaturemodel.cpp.przed_plantnet`, `.przed_kopiami` i podobne. Łapie je
każdy `grep` i mylą przy analizie. Teraz jest kosz, więc jest gdzie je odłożyć.

Do tego `duplikaty.csv` i `spis_zdjec_2026-08-31.tsv` weszły do commita
`eb71d9014` przypadkiem — dane robocze w repo kodu, do `.gitignore`.

---

## D. Teren i dane

### D1. Widżet spisu gatunkowego
Pomysł z 08.09. Pole tekstowe + pasek podpowiedzi + lista rozpoznanych
wierszy, Enter = jedna pozycja. Wzorzec: galeria załączników (widżet
w formularzu rodzica piszący do tabeli-dziecka przez relację).

- **Enter jako separator już działa** — `_rozdziel_pozycje` tnie po nowej
  linii. 09.09 wróciło 18 płatów z łamaniami.
- Rozstrzygnięcie: **przenosi się źródło prawdy** — z pola płatu na linię
  w wierszu. Dwa kierunki naraz = katastrofa; rozstrzyga `ZRODLO_WIERSZA`.
- Kolumny kontraktu do dołożenia **zanim to pojedzie**: `SKROT_UZYTY`,
  `POZYCJA`, `ZRODLO_WIERSZA`, `WERSJA_SLOWNIKA`.
- Pułapka: **nie ustawiać `ImhNoPredictiveText`** — Gboard przestanie
  rozwijać skróty i metoda padnie.

### D2. Panel porównawczy zdjęć — kalibracja obserwatora
Ciąg zdjęć z płatów tego samego typu obok siebie, z wpisanymi wartościami
pokrycia. Powtarzalne płaty są atutem: jeśli w dwudziestu podobnych ten sam
gatunek dostał raz C60, raz C20, panel pokaże to na jednym ekranie.

Zysk drugi, strategiczny: **każda poprawka to oznaczony przykład** — zbiór,
na którym da się kiedykolwiek ocenić automat.

### D3. Przypisywanie zdjęć do płatów po EXIF
Odkryte 09.09: **OpenCamera zapisuje `Yaw`, `Pitch`, `Roll` w `UserComment`**,
plus GPS i `GPSImgDirection`. Każde zdjęcie wie, gdzie i w którą stronę
zostało zrobione.

Skrypt `/tmp/stozki.py` rysuje stożki widzenia i liczy udział płatów w kadrze.
Parametry, które się sprawdziły: **pole 60×45°, zasięg 8 m**, deklinacja 6°,
aparat 1,5 m. Przy pełnym polu i 25 m stożki zachodzą na trzy–cztery płaty;
przy tych węższych każdy trafia w jeden.

- Do zastosowania: **58 zdjęć luzem** w PTR (są na dysku, nie ma ich w bazie),
- **54 wiersze `FITO_ZDJECIA` bez `ID_PŁATU`** — mają własną geometrię, więc
  wystarczy punkt w poligonie,
- `pitch` mówi, czy ujęcie jest z nadiru — filtr do D2.

### D4. `ID_PŁATU` nie jest wypełniane automatycznie
Pole istnieje, bywa puste po obu stronach relacji. Aplikacja mogłaby ustalić
je z pozycji przy zakładaniu zdjęcia w obrębie płatu.

### D5. `ID_OBIEKTU` w PTR ma wartość `2605`
To numer zlecenia **PZE**. Szablon przeniósł stałą z poprzedniego zlecenia
i nikt jej nie podmienił. Nieszkodliwe, dopóki nikt na niej nie polega —
groźne, gdy trafi do eksportu.

### D6. `POWIERZCHNIA_M2` trzyma stopnie kwadratowe
`3,66e-07` przy płacie 2779 m². Wartość zależy od tego, kto ostatnio dotknął
obiektu: otwarcie formularza przelicza ją poprawnie. W bazie mieszają się dwie
jednostki różniące się o dziewięć rzędów wielkości.

Decyzja Piotra 09.09: **przeliczy się samo**, jedno `UPDATE` z geometrii
na koniec zlecenia. Ale zestawienie zrobione wcześniej będzie mieszanką.

### D7. Ekran stylizacji nie pozwala wybrać atrybutu
Kategoryzacja jest w projekcie (`attr="ZROBIONE"` po obu stronach), więc mapa
się koloruje — psuje się sam ekran edycji stylu.

Pierwszy podejrzany: `LayerTreeItemProperties.qml`. Ten plik **już raz wypadł
ze wspólnej poprawki** (łatka 39 — kategorie miały własną, skopiowaną listę
13 kolorów i jako jedyne nie wołały wspólnego pickera).

Obejście na dziś: styl ustawiany w QGIS i przenoszony w `projekt.qgs`, albo
`loadNamedStyle` z konsoli.

### D8. Puste linie na końcu zapisu surowego
Płat 19 kończy się czterema pustymi pozycjami — Enter na końcu zostawia
puste linie. Parser je pomija, ale lepiej, żeby nie powstawały.

---

## E. Dług i decyzje

### E1. „Zamień na szablon" — lista zakazana zamiast dozwolonej
Decyzja Piotra 09.09: **czyścić wszystkie tabele, zmienne i załączniki**.
Odwrotnie niż dziś (`FITO_%`, `ZAL_%`).

Uzasadnienie: błąd idzie wtedy w stronę **pustego szablonu**, a nie cudzych
danych u następnego klienta. Dowód z tego samego dnia — `ZAL_ZDJECIA_FITO`
istniało w bazie i nikt o nim nie pamiętał przy planowaniu scalenia.

Wyłączyć jawnie: tabele systemowe GPKG (`gpkg_*`, `rtree_*`, `sqlite_*`),
**słowniki** (`TAKSONY` i wszystko z katalogu — to wyposażenie, nie dane
klienta), **stemple wersji** (inaczej `verify` powie `BRAK` na wszystkim).

Do tego: ekran z **prawdziwymi liczbami wierszy** przed czyszczeniem
(jest od 23.08) i **kontrola po fakcie** wypisująca, co zostało.

Wtedy czynność wolno wypuścić w teren — zarzut o „niedoczyszczenie po cichu"
przestaje istnieć jako klasa błędu.

### E2. UUID — drugi etap
`UUID_WIERSZA` dołożone 09.09 do sześciu tabel w `v6_0` (1207 wierszy),
wartość domyślna `uuid()` z `applyOnUpdate="0"` w `projekt.qgs`.

- **Do sprawdzenia w terenie:** czy wartość domyślna odpala się przy zapisie
  z paska szybkiego przechwytu i z kolejki odroczeń, nie tylko z formularza.
  Kontrola: `SELECT count(*) FROM FITO_PLATY WHERE UUID_WIERSZA IS NULL`.
- **Później:** przepiąć relacje z `fid` na UUID. Dopiero gdy będzie wszędzie —
  przebudowa modelu w środku sezonu to proszenie się o kłopoty.

### E3. Ile jest wejść do ekranu
Czwarta odsłona tego samego w trzy tygodnie: „Teren" w obu szufladach, trzy
kopie `QfPozycjaMenu`, „Manage plugins" duplikowane, edytor plików w trzech
miejscach (09.09 usunięte dwa).

Nawyk: przy każdym nowym ekranie policzyć wejścia.

```bash
grep -rn "ekran.open()\|ekran.otworz()" src/app/qml/ | wc -l
```

Więcej niż jedno to sygnał do **decyzji**, nie automatycznie błąd.

### E4. Sygnał bez odbiornika jest długiem
W tym samym duchu co „czasownik bez ekranu jest długiem" (kontrakt czasowników).

09.09 padło **siedem** hipotez o brakującej funkcji i za każdym razem rzecz
już była, tylko niepodłączona: `zapytanieSql`, `kopiaBazy`, czasowniki
plikowe, `geometriaZniszczona`, `unikajNakladania`, `stanProjektu`,
`snappingConfig`.

Kandydat na kontrolę: czy każdy `emit` ma w QML kogoś, kto słucha.

---

## Obalone pomiarem

Nie kasujemy — to też wiedza, i chroni przed powtórnym wchodzeniem w to samo.

| Data | Hipoteza | Czym obalona |
|---|---|---|
| 09.09 | `commit()` nie woła `kopiaBazy` | `adb logcat` — wpis „Kopia bazy: …/dane_20260909_2118.gpkg". Kod jest w `qffeaturemodel.cpp:1447` i działa. Katalog `kopie/` był pusty, bo tego dnia nic jeszcze nie zapisano formularzem. |
| 09.09 | Brak listy kopii | `QfKopiaPanel.qml` ma `listaMigawek` od 24.08 — ale to **kopie na USB**, nie migawki w telefonie. Te drugie widać teraz w menedżerze plików. |
| 09.09 | `v5_0` straciła kategoryzację na telefonie | `grep` — `attr="ZROBIONE"` po obu stronach. Podmiana projektu cofnęła za to `workfield/selectable` ustawione w terenie. |
| 09.09 | Zdjęcia OpenCamery nie mają GPS | `-p` gubiło współrzędne przez ostrzeżenie o MakerNotes na stderr. Są, razem z yaw/pitch/roll. |
| 09.09 | Kopia bazy jest pusta („0 B") | Pole nazywa się `fileSize`, nie `size`. Kopia ma 3 330 048 B. |
| 09.09 | 17 duchów PZE to skutek podziału | Żaden nie ma żywego bliźniaka o tej samej nazwie. Przyczyna wciąż nieznana — patrz A1. |

---

## Zasady, które z tego wyrosły

- **Objaw niemy jest gorszy od błędu.** Mechanizm ma odmawiać, nie milczeć.
- **Komunikat prawdziwy i bezużyteczny nie liczy się jako komunikat.**
- **Brak pomiaru to nie wynik pomiaru.** „0 B", pusty `grep`, cisza w logu —
  za każdym razem trzeba sprawdzić, czy narzędzie w ogóle mierzyło.
- **Sprawdzać wolno wszędzie, naprawiać nie wszędzie.** Stąd podział
  teren/biuro — po odwracalności, nie po platformie.
- **Sprawdź, co już jest, zanim napiszesz.** Jedno `grep` po `src/app/qml/`
  i `src/core/`.
- **Zgadywanie API kosztuje build.** Sonda w konsoli kosztuje sekundę.

---

# Zaległości z sierpnia — dopisane 09.09 po przeglądzie notatek

Wszystko poniżej wisi w handoffach i notatkach, nie w tej liście. Kolejność
w obrębie grup: od najstarszego.

## F. Wisi najdłużej — z 17.08 i 20.08

### F1. Cofanie zmian — brak kosztował pół dnia terenu
Na liście od **20.08**. `KONTEKST_GATUNKU.md` wymienia to jako pierwszą
z dwóch rzeczy, które przegapiliśmy, robiąc „piąty przyjemny temat".

### F2. Centrum wyposażenia — trzy przełączniki
Też od **20.08**. Brak kosztował kolejne pół dnia: **unikanie nakładania,
typ przyciągania, widget pola**. Dwa pierwsze wróciły dziś jako B2 i przyciski
w dialogu geometrii — ale ekranu, z którego dałoby się je ustawić przed
wyjazdem, nadal nie ma.

### F3. „Magazyn" i „Nowy z szablonu" prowadzą donikąd na telefonie
`QfMainDrawer.qml:730` — `Loader { active: Qt.platform.os !== "android" }`.
Pozycje są widoczne, klikalne i otwierają pustkę.

Łamie zasadę z 17.08 wprost: **czynność widoczna w menu musi działać albo nie
może być widoczna.** Trzeci stan jest gorszy od braku, bo człowiek planuje
pracę wokół funkcji, której nie ma.

Do tego: `QfNoweZadanie.qml` jest **napisany dla telefonu** (mówi to komentarz
w `QfAkcje.qml:124`) i wołany wyłącznie z menu komputera.

### F4. Magazyn zawiesza aplikację
Punkt 1 listy Piotra z 17.08 wieczór. Brak danych do diagnozy.

### F5. „Ustawienia terenowe" i „Ustawienia aplikacji" ukryte na telefonie
Audyt 17.08 oznaczył je jako **podejrzane**: dlaczego akurat te nie są dostępne
tam, gdzie się ich używa?

## G. Czasowniki bez ekranu (kontrakt z 22.08)

`CZASOWNIKI_kontrakt.md`: **czasownik bez ekranu jest długiem — albo dostaje
ekran, albo znika.**

### G1. `validateFile` — pierwszy do zbudowania
Dziś kontrolę robi `sprawdz_przepis.py`, czyli Python, czyli **nigdy telefon**.
Stąd komunikat „Klawisze: plik definicji nieczytelny" w `zzw_pze_2605`, który
nie mówi, co jest nie tak.

### G2. `verify` przy otwarciu projektu
Ostrzeżenie o złym wyposażeniu ma paść **w biurze, zanim wyjedziesz**.

### G3. `stamp`, `unstamp`, `addTables`, `mergeFeatures` — istnieją, brak ekranów

### G4. MAJOR nazewniczy: `WF_WYPOSAZENIE` → `WF_PROJECT_TOOLS`
Z regułą: gdy istnieją obie tabele, `equip` **odmawia i mówi dlaczego**.
Stara nazwa wypada z kodu **po sezonie 2026** — warstwa zgodności bez daty
ważności zostaje na pięć lat.

### G5. `kopiaZapasowa` odkłada `.bak_*` obok oryginału
Czyli **w katalogu jadącym w teren**. Drugie takie miejsce jest
w `wyposazenie.py`. Do tego bez checkpointu WAL — kopia z leżącym obok
`-wal` otworzy się i skłamie (lekcja z 21.08).

## H. Zwrot i wymiana (z 24.08)

`RYTUAL_ZWROTU.md`: **transport jest w ośmiu dziesiątych zbudowany**, brakuje
pieczęci i liczb.

### H1. Panel „Przyjmij zwrot" na desktopie
Oceniony jako **najtańszy i zdejmujący najwięcej powtarzalnej roboty**.
Wzorzec UI gotowy (`QfKopiaPanel.qml`), build desktopowy w minuty.

### H2. Checkpoint WAL + md5 przy pakowaniu
`QfWymianaLokalna`. Do zrobienia **razem z czymkolwiek**, co i tak wymaga APK.

### H3. Liczniki na telefonie — `ZWROT.json` przed paczką
Liczby liczy telefon, bo ma otwartą bazę. Zysk: wiadomo w biurze, czy dzień
się udał, **zanim cokolwiek dojedzie**; zepsuty zwrot nie rusza z miejsca.

### H4. `kopiezapasowe.{h,cpp}` i `SpisPlikow` — praca z 24.08 niewypchnięta
Sprawdzić, czy nadal (stan na 24.08: nie ma na `master` ani `development`).

### H5. Skrypty zwrotu nie sprawdzone na prawdziwych danych
Przepuszczone przez sztuczny GeoPackage. Do zweryfikowania w pierwszej
kolejności: zgadywanie rodzica w `sprawdz_zalaczniki.py` —
`ZAL_GATUNKI` → `FITO_SPIS_GATUNKOWY` **nie dopasuje się po sufiksie**.

## I. Pl@ntNet i taksonomia (kolejka z 22.08)

### I1. Duplikaty tagów — czeka na wyraźne „tak"
„Calluna vulgaris" ×2 plus wariant z etykietą liczone osobno — psuje statystyki
siatki. Normalizacja na **każdej** drodze dodania plus jednorazowe „Scal
duplikaty" z kopią bazy tagów. Operacja hurtowa na danych, więc bez zgody nie ruszamy.
Otwarte: skąd weszły krótkie warianty.

### I2. Konsolidacja trzech kopii logiki Pl@ntNet
Wtyczka / galeria / widżet. Po okrzepnięciu — **prezent dla społeczności QFielda**.

### I3. Macierz cech: partia 2 i 3
Partia 1 (36 gatunków traw) jest ROBOCZA, kolumna `WERYFIKACJA` pusta, w UI
widnieje „(rob.)". Partia 2 = turzyce i sity (**inne kolumny**), partia 3 =
kostrzewy górskie.

### I4. Mail: beta survey Pl@ntNet
Multi-species, kwadraty 0,25–1 m² — pasuje do siatki point-intercept i do D2.
**Szkic obiecany 22.08.**

### I5. Backbone taksonomiczny — wątek wydzielony
Duplikaty i synonimy w słowniku (Agrostis canina ×2, Festuca rubra ×3), wpisy
rodzajowe, synonimy atlasu przy linkach.

### I6. Kontekst gatunku — profilowany, czeka na backbone
Pięć pomysłów zwiniętych w jedną pozycję (Crossref, OpenAlex, BHL, POWO/IPNI,
profile słów kluczowych). Świadomie **za** F1 i F2 w kolejce.

## J. Dług techniczny i porządki

### J1. `scripts/bump-version.sh` rozjechał się z `build.sh`
Szuka wzorców sprzed przepisania na `APP_VERSION_NUM` + `APP_CODENAME`.
Uruchomiony dziś **skasowałby nazwę kodową i nie ruszył `versionCode`**.
NIE UŻYWAĆ. Do skasowania albo przepisania — razem z C1.

### J2. `git rm --cached` na `*.przed_*`
11 plików, ~24 tys. linii, **pojechały też na master**. Punkt 5 kolejki z 22.08,
rozszerza C6.

### J3. Skasować gałąź `wyposazenie`
Termin był ~29.08. Komendy w `docs/REPO.md`.

### J4. `NOTICE.md` — sekcja o źródłach danych
Delta urosła (ExternalResource).

### J5. `demProcessing()` nadal bez żadnego wywołania w QML
Z 23.08. Czasownik bez ekranu.

### J6. `QfSettingsIndex.qml` przestał być używany

### J7. `QfTerenSettings.qml` i `QfTextEditor.qml` mają własne palety hex poza motywem
Czyli nie reagują na „Podgląd stylizacji" z 24.08 ani na zmianę barw motywu.

### J8. Cztery drobiazgi UI z 23.08, niezrobione
Pasek kategorii ustawień zasłania treść na wąskim ekranie; wyrównanie kolumny
ikon w pionie; operacje na zleceniach i projektach z menu „⋯" do zakładek;
zębatka w lewym dolnym rogu jako kompromis.

### J9. Odsyłacz do nieistniejącego pliku
Handoff 24.08 wskazuje `claude/DANE_obieg.md` — **takiego pliku nie ma**.
Są `DANE_workflow.md`, `DANE_workflow_2.md`, `OBIEG_zwroty_praktyka.md`.
Do poprawienia, żeby następna sesja nie szukała.

### J10. `/DATA` na 97 % (39 GB wolnego, stan 23.08)
Sprawdzić dziś — doszły zwroty i wydania z września.

---

## Reguła, która wynika z tego przeglądu

Ta lista powstała **09.09**, a najstarsza pozycja na niej jest z **17.08**.
Trzy tygodnie rzeczy, które były zapisane w handoffach i nikt do nich nie wrócił,
bo handoff jest **relacją z dnia**, nie listą zobowiązań.

> Notatka opisuje, co się wydarzyło. Lista mówi, co jest winne.
> To dwa różne dokumenty i jeden nie zastąpi drugiego.

---

# Dopisane 11.09.2026

## K. Zdjęcia i obiekty

### K1. Wiązanie zdjęć z obiektami po stożkach widzenia
Wynika z 09.09: **OpenCamera zapisuje `Yaw`, `Pitch`, `Roll` w `UserComment`**,
obok GPS i `GPSImgDirection`. Każde zdjęcie wie, gdzie i w którą stronę
zostało zrobione — więc przypisanie do płatu da się **wyliczyć**, a nie tylko
zapamiętać.

**Zasada, na której to stoi (rozstrzygnięcie Piotra 11.09):**

> Przeliczenie **PROPONUJE i prosi o zatwierdzenie**. Nie dodaje wierszy,
> nie kasuje, nie oznacza. Propozycja żyje na ekranie do czasu decyzji.

Odrzucone świadomie: wariant „dodaje i oznacza". Produkowałby wiersze,
których nikt nie zamawiał, i po miesiącu `ZAL_*` byłoby pełne śmieci ze
znacznikami. *„Nie kumulujmy nadmiaru nadmiarowości, bo się nią udusimy."*

**Kształt:**

- **Właściwość warstwy** włącza mechanizm — nie wszystkie warstwy chcą zdjęć
  przypisywanych z EXIF.
- **Stożki widoczne domyślnie** dla zdjęć leżących w obrębie warstwy i dla już
  powiązanych. Widać wszystko, zanim cokolwiek trafi do bazy.
- **Zapis do `ZAL_*` na żądanie**, z potwierdzeniem obiektu.
- **Po zapisie warstwy** przeliczenie proponuje zmiany. Nic samo.
- **Wiązanie po `UUID_WIERSZA`, nie po `fid`** — przeżyje przenumerowanie
  i rozbicie. To pierwsze realne zastosowanie UUID-ów dołożonych 09.09.

**Parametry sprawdzone 09.09** (skrypt stożków, cztery sieroty płatu 316):
pole **60×45°**, zasięg **8 m**, deklinacja **+6°** (Warszawa), aparat **1,5 m**.
Przy pełnym polu 97° i zasięgu 25 m stożki zachodzą na trzy–cztery płaty naraz;
przy tych węższych każdy trafia w jeden.

Rzecz, dla której cała ta robota ma sens: **punkt stania to nie punkt
fotografowany.** Przy pitchu −41° i aparacie na 1,5 m środek kadru pada ~1,7 m
przed nogami. Zdjęcie robione z krawędzi płatu do środka ma GPS **poza** płatem
— dopasowanie po samym punkcie odrzuciłoby je jako „nie w tym płacie".
Tak było z `zal 34` 09.09: punkt w płacie 467, stożek w 476.

**Zaległość na start: 37 zdjęć luzem** w PTR (bez `plantnet_*`, które są
plikami roboczymi wtyczki i nie mają mieć wierszy). Rozkład: większość z 7.09,
czyli z dnia dwóch telefonów i kolizji numerów — wiersze przepadły przy
scalaniu, pliki jechały z nami przez cztery wydania.

**Zrobione, gdy:** da się otworzyć płat, zobaczyć stożki, zatwierdzić
przypisanie, a po zmianie geometrii dostać propozycję zamiast cichej zmiany.

### K2. Atlas warstwy
Panel w lewej szufladzie: **jeden obiekt na ekranie** — miniatura mapy,
formularz, klikalne miniatury zdjęć, diagramy na żądanie.

Osobna pozycja od K1 celowo: atlas może powstać bez stożków, a stożki bez
atlasu. Łączenie ich w jedno zadanie zwiększa ryzyko bez żadnego zysku.

### K3. Kasowanie i scalanie płatów zostawia pliki bez wierszy
Druga strona wady A2. Tam: wiersz `ZAL_` wskazuje na nieistniejącego rodzica.
Tu: plik leży w `DCIM`, a wiersz zniknął razem z płatem.

Oba objawy ciche, oba wykrywalne dopiero porównaniem bazy z katalogiem.

## L. Kontrola przed wydaniem

### L1. Lista tabel `ZAL_*` wpisana ręcznie w trzech miejscach
I wszędzie niepełna. 11.09 kontrola sierot pominęła `ZAL_GATUNKI` i pokazała
84 pliki „luzem" zamiast 57 — czyli **fałszywy alarm na 27 zdjęciach**.

Ten sam mechanizm 09.09 kazał przeoczyć `ZAL_ZDJECIA_FITO` przy planowaniu
scalenia; tabela wypłynęła dopiero w trakcie.

**Reguła:** tabele `ZAL_*` czytać z `sqlite_master`, nigdy nie wymieniać
z nazwy.

```sql
SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'ZAL\_%' ESCAPE '\';
```

### L2. `plantnet_*` wykluczyć z kontroli sierot
To pliki robocze wtyczki — zdjęcie idzie do API, wiersz nie powstaje i nie ma
powstawać. Bez wykluczenia zaciemniają obraz przy każdym wydaniu (9 sztuk
z samego 11.09).

### L3. Kontrola sierot jako część `obieg.py`
Dziś liczy się ją ręcznie i trzeba o niej pamiętać. Zero sierot to warunek
wydania, więc miejsce tego sprawdzenia jest w skrypcie, nie w głowie.
