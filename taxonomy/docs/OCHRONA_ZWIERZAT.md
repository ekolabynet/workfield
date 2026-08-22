# Ochrona gatunkowa zwierząt — z oryginału Dz.U. do CSV

Źródło: **rozporządzenie Ministra Środowiska z 16.12.2016 r. w sprawie ochrony
gatunkowej zwierząt (Dz.U. 2016 poz. 2183)**, PDF z Dziennika Ustaw, 46 stron,
w życie od 1.01.2017. Poprzednik (Dz.U. 2014 poz. 1348) stracił moc.
Czy było nowelizowane po 2016 — **niesprawdzone [?]**.

To pierwsza warstwa prawna w projekcie, która nie dotyczy roślin. Dokłada się
do `prawo_gatunki_*.csv`, nie zastępuje go: inne królestwo, inny akt, inne
kolumny.

## Co wyszło

| Plik | Zawartość | Wierszy |
|---|---|---|
| `ochrona_zwierzat_2016-2183.csv` | zał. 1 (ochrona ścisła), zał. 2 (częściowa), zał. 3 (pozyskiwane) | **592 + 211 + 2 = 805** |
| `strefy_ochrony_2016-2183.csv` | zał. 4 — strefy ochrony ostoi, miejsc rozrodu i regularnego przebywania | 30 pozycji (32 wiersze, bo dwie mają po dwie strefy okresowe) |
| `parsuj_ochrona_zwierzat.py` | skrypt, który to wyciąga; `pdfplumber` jako jedyna zależność | — |

Numeracja zgadza się z aktem co do pozycji: zał. 1 kończy się na 592, zał. 2
na 211, bez luk. 139 gatunków ma znacznik **ochrony czynnej**.

## Jak to zostało odczytane — i dlaczego akurat tak

**Gromady rozpoznajemy po kroju pisma, nie po liście nazw.** Tak mówi sam akt
w objaśnieniach: gromady wielkimi literami pogrubione, rzędy wielkimi
literami zwykłe. Pierwsza wersja skryptu miała listę nazw gromad — i zaliczyła
piekielnicę do płazów, a pijawkę lekarską do owadów, bo nie znała nagłówków
„RYBY PROMIENIOPŁETWE ACTINOPTERYGII" i „SIODEŁKOWCE CLITELLATA".
`pdfplumber` podaje `fontname` przy każdym słowie, więc reguła z aktu daje
się wykonać dosłownie. **Lista nazw byłaby zgadywaniem; krój pisma jest
faktem w pliku.**

Pięć pozycji łamie się w PDF-ie na kilka linii — pozycje zbiorcze (lp. 13
walenie, lp. 479 pozostałe ptaki, lp. 211 gatunki z dyrektywy siedliskowej)
i nazwy z synonimami (modraszek nausitous, brzanka). Są przepisane ręcznie,
każda z adnotacją w kolumnie `WERYFIKACJA`. Skrypt wypisuje osobno, czego nie
odczytał — dziesięć linii, w tym te pięć; reszta to fragmenty ciągnące się
z poprzedniego wiersza.

Zachowane wprost z aktu, bez „poprawiania": pisownia synonimu brzanki
(`B. carpthicus`), znaczniki `(1)`, `(2)`, `(3)`, `(4)` w kolumnie
`ADNOTACJE`. Ich znaczenie: (1) zakaz z § 6 ust. 2 — umyślne płoszenie;
(2) zakaz z § 6 ust. 3 — płoszenie w miejscach noclegu i lęgów; (4)
odstępstwo z § 9 pkt 6.

## Co z tego naprawdę dotyka inwentaryzacji drzew

Trzy rzeczy, i warto je znać przed wejściem w teren, nie po:

1. **Zakaz niszczenia, usuwania i uszkadzania gniazd** (§ 6 ust. 1 pkt 8) —
   dotyczy gatunków objętych ochroną ścisłą i częściową, czyli praktycznie
   każdego ptaka gniazdującego w drzewie.
2. **Okno na usuwanie gniazd: od 16 października do końca lutego** (§ 9 pkt 1
   i 2) — i to tylko z budek albo z obiektów budowlanych i terenów zieleni,
   **jeżeli wymagają tego względy bezpieczeństwa lub sanitarne**. Poza tym
   oknem i poza tymi przypadkami — nie wolno. To jest dokładnie ten sam
   kalendarz, który rozstrzyga o terminie cięć.
3. **Strefy ochrony** (zał. 4) — 17 pozycji to strefy liczone **od gniazda**:
   całoroczna 50, 100 albo 200 m, okresowa zwykle 500 m, z terminem. Bielik:
   200 m całorocznie, 500 m okresowo od 1.01 do 31.07. Sóweczka i włochatka:
   50 m całorocznie, bez okresowej. Dla pracy przy drzewostanie to jest
   promień, w którym nie ma się czego szukać w sezonie.

## Model danych

Wiersze tych CSV to **Animalia** — czyli pierwsze potwierdzenie decyzji
z 22.08, że kluczem jest para `(GATUNEK, KROLESTWO)`. W tych plikach siedzą
m.in. *Prunella* (płochacz), *Morus* (głuptak) i *Oenanthe* (białorzytka) —
rodzaje, które w słowniku roślin znaczą coś zupełnie innego. Gdyby obie
warstwy wpadły do jednej tabeli po samej nazwie, sklejenie byłoby cichą
awarią, nie błędem widocznym na ekranie.

Strefy ochrony mają dodatkowo wymiar przestrzenny: `STREFA_CALOROCZNA`
i `STREFA_OKRESOWA` to promienie, więc naturalny użytek w aplikacji to bufor
wokół punktu, nie kolumna w formularzu. To jest kandydat na warstwę
`REF_strefy` w `support.gpkg` — odtwarzalną, generowaną w biurze ze
stwierdzonych stanowisk, nie wożoną w danych roboczych.

## Do zrobienia

1. **Sprawdzić nowelizacje** rozporządzenia po 2016 r. **[?]**
2. Rozstrzygnąć, czy tabela zwierząt jedzie w projekcie terenowym, czy tylko
   w biurze. Argument za terenem: kalendarz gniazd i strefy są potrzebne przy
   decyzji na miejscu. Argument przeciw: 805 wierszy o gatunkach, których
   dendrolog nie oznacza.
3. Nazwy naukowe z tego aktu przepuścić przez to samo dopasowanie co rośliny
   (`kingdom=Animalia`) i zapisać klucze w `TAKSONY_XREF` — akt z 2016 r.
   miejscami używa nazw, które w kręgosłupach są już synonimami
   (np. *Pseudepidalea viridis*, dziś zwykle *Bufotes viridis*).
4. Pisownia `Mergus serrator` w zał. 4 — do sprawdzenia wzrokiem w PDF.
