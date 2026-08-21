# Wydania WorkField

## Jak numerujemy

- **Numer** `major.minor.patch` — jedno źródło: `APP_VERSION_NUM` w
  `scripts/build.sh`. Z niego liczy się wszystko inne:
  - `APP_VERSION` = `v` + numer (CPack, link do wydania w oknie „O programie"),
  - `APK_VERSION_CODE` = `major*10000 + minor*100 + patch` — rośnie także
    przy 0.10.x i 1.0.0, więc Android nigdy nie uzna nowszego za starsze,
  - `APP_VERSION_STR` = `numer - Nazwa Kodowa`, i to widzi człowiek.
- `platform/android/AndroidManifest.xml` **generuje się** z `.in`
  (`cmake/Package.cmake`) — nie edytuje się go ręcznie. Plik w drzewie jest
  wynikiem ostatniego builda; bywa własnością `root`, bo build Androida
  chodzi w Dockerze.
- To numer **aplikacji**, nie standardu projektu. Standard formatu żyje
  osobno w `wyposazenie/standardy.json` — patrz `docs/WERSJONOWANIE.md`.

## Nazwy kodowe

Botaniczne, po angielsku, wzorem Ubuntu: **przymiotnik + roślina**,
aliteracja, kolejne litery alfabetu. Upstream QField używa nazw gór
(„1.0.0 - Homerun", „0.9.1 - Jungfrau"), więc nie wchodzimy mu w drogę.

Litera nie wraca, dopóki nie skończy się alfabet. Zajęte litery odhacza
tabela niżej — to jedyny powód, dla którego ten plik istnieje.

Kandydatki na dalej: **C**oastal Cedar, **D**usky Dogwood,
**E**merald Elm, **F**rosted Fern, **G**olden Gorse, **H**azy Hawthorn,
**I**vory Ivy, **J**agged Juniper, **K**een Kale, **L**anky Larch,
**M**ellow Maple, **N**imble Nettle, **O**paque Oak, **P**ale Poplar,
**Q**uiet Quince, **R**ugged Rowan, **S**ilver Spruce, **T**awny Thistle,
**U**pright Umbel, **V**elvet Vetch, **W**iry Willow, **Y**oung Yew,
**Z**esty Zinnia.

## Rejestr

| Wersja | Kod | Nazwa | Data | Co przyniosło |
|---|---|---|---|---|
| 0.9.3 | 903 | **Bumpy Birch** | 2026-08-21 | Kolory kategorii przez wspólny picker (256 odcieni Materialize), naprawiony martwy przycisk widoczności kategorii, usunięty nieużywany ColorGrid |
| 0.9.2 | 902 | **Ancient Ash** | 2026-08-19 | Wyjście z geometrii wieloczęściowej (scal / rozdziel), czasowniki geometrii, kursor nad klawiaturą, paleta Materialize CSS (256 odcieni), wybór rampy z miniaturami, rampy syntetyczne (złoty kąt, losowe z lokalnym kontrastem), znaczniki stanu i wierzchołków, wtyczka „Zrobione" |
| 0.9.0 | 900 | — | 2026-08 | Ikony panelu barwione kolorem tekstu motywu (czytelne w ciemnym motywie) |
| 0.8.13 | 813 | — | 2026-08 | QC 3.0: sekcja ustawień, paleta kolorów kafli paska |

Wydania sprzed 0.9.2 nie mają nazw kodowych — schemat zaczyna się tutaj.
Wstecz nie dopisujemy: nazwa ma odsyłać do konkretnego APK, a tamte już
pojechały w teren bez niej.

## Rytuał wydania

1. `APP_VERSION_NUM` i `APP_CODENAME` w `scripts/build.sh`.
2. Wiersz w tabeli wyżej.
3. `git commit`, `git tag -a vX.Y.Z -m "X.Y.Z - Nazwa"`,
   `git push origin vX.Y.Z` — **nie** `git push --tags`, bo to wypycha
   także tagi upstreamu (`v4.2.x`) i miesza dwie numeracje w jednym repo.
4. `triplet=arm64-android ./scripts/build.sh`, potem
   `find build-arm64-android -name "*.apk"` i `adb install -r`.
5. Kopia APK na Nextcloud, nazwa z datą i hashem commita.
6. Sprawdzić `wymaga_aplikacji` w `wyposazenie/standardy.json` — czy
   wydanie zmienia minimalny versionCode dla standardu projektu.
