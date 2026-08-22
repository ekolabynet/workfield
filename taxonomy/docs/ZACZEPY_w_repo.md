# Jak wstawić `taxonomy/` do repo, żeby się nie zgubiło

Katalog wrzucony i zapomniany jest gorszy niż jego brak — zajmuje miejsce
i myli. Poniżej: droga wstawienia i **cztery zaczepy**, po których da się do
niego trafić, nie pamiętając, że istnieje.

## 1. Wstawienie — komendy do wklejenia

Gałąź robocza to `development` (wg `docs/REPO.md`); `master` rusza się tylko
przy bumpie.

```bash
cd /DATA/SOFT/GIS/QFIELD_Pro/QField
git status && git log --oneline -3
git checkout development && git pull --ff-only origin development

# rozpakowanie w korzeniu repo
unzip -o ~/Pobrane/taxonomy.zip -d .

# kontrola PRZED dodaniem: co właściwie wchodzi i czy nic dużego się nie wkradło
find taxonomy -type f | sort
find taxonomy -type f -size +1M
git add -n taxonomy | head -40
```

Dopiero gdy lista się zgadza:

```bash
git add taxonomy
git status --short
git commit -m "taxonomy: słownik taksonów, warstwy prawne i łańcuch budowy

Katalog na wszystko, co dotyczy nazw gatunków i przypisanego im prawa.
Dane jako CSV (źródło prawdy, diffowalne), GPKG jako wydruk przy wydaniu.
Warstwy CC BY-NC poza repo, w dane/prywatne/ (gitignore).

- warstwa prawna roślin: 142 wiersze (83f, stawki, pomniki, IGO, ochrona)
- ochrona gatunkowa zwierząt: 805 gatunków z oryginału Dz.U. 2016/2183
- strefy ochrony: 30 pozycji z załącznika 4
- pięć skryptów łańcucha budowy + README jako mapa katalogu"
git push origin development
```

Sprawdzenie, że nakładka prywatna jest naprawdę ignorowana:

```bash
touch taxonomy/dane/prywatne/test.csv
git status --short taxonomy/dane/prywatne/   # ma nie pokazać test.csv
rm taxonomy/dane/prywatne/test.csv
```

## 2. Cztery zaczepy — bez nich katalog zniknie z pola widzenia

### a) `docs/REPO.md` — źródło prawdy o strukturze

Dopisać wiersz do tabeli katalogów:

> `taxonomy/` — nazwy gatunków i przypisane im prawo: warstwy prawne jako CSV,
> skrypty budujące słownik `TAKSONY`, rejestr wersji. Wejście: `taxonomy/README.md`.

### b) `NOTICE.md` — źródła i licencje

Wkleić treść z `taxonomy/docs/ZRODLA_I_LICENCJE.md` (jest napisana jako
gotowy fragment). Pełny rozbiór, łącznie z tym, czego świadomie nie bierzemy,
zostaje w `taxonomy/docs/LICENCJE_audyt.md`.

### c) `MasterScript_WorkField.md` — zasady współpracy

Dopisać do sekcji o środowisku jedno zdanie, żeby każdy następny czat wiedział,
gdzie szukać, zamiast projektować to od nowa:

> **Taksonomia i prawo gatunkowe:** wszystko żyje w `taxonomy/` w repo —
> dane jako CSV, GPKG tylko jako wydruk przy wydaniu. Kluczem jest para
> `(nazwa kanoniczna, królestwo)`, nie identyfikator zewnętrznej bazy.
> Przed projektowaniem czegokolwiek wokół gatunków: `taxonomy/README.md`.

### d) `docs/WYDANIA.md` — rytuał bumpu

Dopisać krok, bo to jedyny moment, w którym słownik ma prawo się zmienić:

> **Odświeżenie słownika taksonów** — sprawdzić, czy nie zmieniła się warstwa
> prawna ani wydanie kręgosłupa (WFO: 21.06 i 21.12). Jeśli tak: nowy plik
> `prawo_gatunki_RRRR-MM-DD.csv`, przebudowa słownika, wiersz w
> `taxonomy/WERSJE.md`, przeliczenie `TAKSONY_XREF`.
> **Nie odświeżamy „przy okazji".**

## 3. Które kopie są prawdziwe

Te same dokumenty leżą teraz w dwóch miejscach: w repo (`taxonomy/docs/`)
i w projekcie Claude (`claude/*.md`, `taxonomy/*`). Żeby się nie rozjechały:

- **Repo jest źródłem prawdy.** Zmiany robimy tam.
- **Projekt Claude jest archiwum sesji** — tak jak mówi `TABLICA.md`
  o `claude/*.md`. Czyta się go, żeby zrozumieć, *dlaczego* coś jest tak
  zrobione, nie *jak jest teraz*.

## 4. Pierwsze uruchomienie po wstawieniu

```bash
cd /DATA/SOFT/GIS/QFIELD_Pro/QField/taxonomy

# autotest rozbioru nazw — nic nie zapisuje
python3 skrypty/taksony_normalizacja.py

# sucha próba na prawdziwym słowniku
python3 skrypty/zbuduj_taksony.py --sucho \
    --zrodlo /DATA/WorkField/szablony/wskazniki/slownik_gatunkow.csv \
    --kolumna GATUNEK
```

Gdy wynik wygląda sensownie — budowa z zapisem CSV do repo:

```bash
python3 skrypty/zbuduj_taksony.py \
    --zrodlo /DATA/WorkField/szablony/wskazniki/slownik_gatunkow.csv \
    --kolumna GATUNEK \
    --skroty /DATA/WorkField/szablony/gboard_taksony.csv \
    --csv-out dane/baza/taksony_baza_$(date +%F).csv \
    --gpkg /DATA/WorkField/szablony/szablon_inw_zzw/dane.gpkg

git add dane/baza && git commit -m "taxonomy: pierwszy zbudowany słownik" \
    && git push origin development
```

**To ten commit jest właściwym początkiem** — dopiero wtedy w repo leży
wynik pracy, a nie same narzędzia.
