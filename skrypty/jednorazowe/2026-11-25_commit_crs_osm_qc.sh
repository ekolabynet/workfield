#!/usr/bin/env bash
# WorkFieldGIS 25.11.2026 — commit łatek z 24–25.11: układ warstw z wartości
# współrzędnych, podkład OSM wektorowy, uzupełnianie projektu, pasek szybkiego zapisu.
#
# Domyślnie PRÓBA: pokazuje, co wejdzie, i nic nie zmienia. Commit: --zapisz.
# Miejsce w repo: skrypty/jednorazowe/2026-11-25_commit_crs_osm_qc.sh
#
# scripts/build.sh (0.14.13 → 0.14.14) NIE wchodzi: podbicie wersji należy do
# commitu wydania (wydaj_<wersja>.sh).
set -u
REPO=${WF_REPO:-/DATA/SOFT/GIS/QFIELD_Pro/QField}
cd "$REPO" || { echo "STOP: brak $REPO"; exit 1; }

ZAPISZ=0
[ "${1:-}" = "--zapisz" ] && ZAPISZ=1

# Pliki śledzone, które MAJĄ być zmienione (bez scripts/build.sh).
OCZEKIWANE="src/app/qml/CMakeLists.txt
src/app/qml/QfDataDrawer.qml
src/app/qml/QfMainDrawer.qml
src/app/qml/QfNaprawaProjektu.qml
src/app/qml/QfQuickCaptureBar.qml
src/app/qml/QfSettingsTeren.qml
src/app/qml/QgisMobileapp.qml
src/core/qfappinterface.cpp
src/core/qgsquick/qgsquickmapcanvasmap.cpp
src/core/utils/narzedziaprojektu.cpp
src/core/utils/narzedziaprojektu.h
wyposazenie/katalog.json
wyposazenie/przepisy/platy_roslinnosci.json"
POMIJANE="scripts/build.sh"
NOWY_QML="src/app/qml/QfQuickCaptureOptions.qml"

echo "Gałąź: $(git rev-parse --abbrev-ref HEAD)"
echo "Ostatni commit: $(git log --oneline -1)"
echo
git diff --stat HEAD
echo

if ! git diff --cached --quiet; then
  echo "STOP: w poczekalni (git add) już coś jest — nie mieszam z cudzym wyborem."
  git diff --cached --name-only
  exit 1
fi

ZMIENIONE=$(git diff --name-only HEAD | grep -v -x -F "$POMIJANE" | sort)
if [ "$ZMIENIONE" != "$(echo "$OCZEKIWANE" | sort)" ]; then
  echo "STOP: zmienione pliki śledzone różnią się od oczekiwanych."
  echo "--- oczekiwane / +++ zmienione:"
  diff <(echo "$OCZEKIWANE" | sort) <(echo "$ZMIENIONE")
  exit 1
fi
if git diff --name-only HEAD | grep -q -x -F "$POMIJANE"; then
  echo "Pomijam $POMIJANE (podbita wersja — wejdzie z commitem wydania)."
fi

if [ ! -f "$NOWY_QML" ]; then
  echo "STOP: brak $NOWY_QML — CMakeLists.txt go wymaga."
  exit 1
fi

# Instalatory i skrypty jednorazowe z 24–25.11, jeszcze nieśledzone.
INSTALATORY=$(git ls-files --others --exclude-standard -- 'skrypty/jednorazowe/2026-11-24_*' 'skrypty/jednorazowe/2026-11-25_*' | sort)

echo "Wejdą pliki zmienione: $(echo "$OCZEKIWANE" | wc -l)"
echo "Wejdzie nowy plik: $NOWY_QML"
echo "Wejdą skrypty jednorazowe ($(echo "$INSTALATORY" | grep -c .)):"
echo "$INSTALATORY" | sed 's/^/  /'
echo

if [ "$ZAPISZ" -ne 1 ]; then
  echo "PRÓBA — nic nie zapisano. Commit: bash $0 --zapisz"
  exit 0
fi

# shellcheck disable=SC2086
git add -- $OCZEKIWANE "$NOWY_QML" || { echo "STOP: git add nie przeszedł"; git reset -q; exit 1; }
while IFS= read -r plik; do
  [ -n "$plik" ] && { git add -- "$plik" || { echo "STOP: git add $plik"; git reset -q; exit 1; }; }
done <<< "$INSTALATORY"

git commit -F - <<'KONIEC'
Układ warstw z wartości współrzędnych, podkład OSM wektorowy, uzupełnianie projektu, opcje paska szybkiego zapisu

Układ warstwy rozpoznawany po wartościach współrzędnych [WF-CRS-DETECT]:
- okna dla EPSG:4326, 3857, 2180 i 2176–2179, także z zamienionymi osiami;
  współrzędne lokalne rysunku i obiekty przy 0,0 liczone osobno
- sprawdzanie przy dodaniu pliku, przy otwarciu projektu i z Narzędzi
  („Układy warstw — sprawdź”)
- kolizja układu: okno „W locie” / „Konwertuj do bazy projektu” / „Pomiń”
  [WF-CRS-FIX]; zamienione osie tylko przez konwersję
- konwersja do nowej tabeli w dane.gpkg, z migawką bazy, kontrolą liczników
  i pominięciem obiektów spoza obszaru układu [WF-CRS-CONVERT]
- rysunek CAD zachowuje kolory i grubości po konwersji: styl encji w polu
  cad_style i styl kategoryzowany [WF-CRS-CONVERT-STYLE]
- warstwa bez układu, której liczby pasują do układu projektu (DXF), dostaje
  go w locie bez pytania [WF-CRS-AUTO]
- po wczytaniu DXF widok na główną część rysunku, bez śmieci przy 0,0

Układ projektu:
- pusty projekt zawsze z układem (domyślnie EPSG:2178) [WF-CRS-BLANK]
- okno naprawy: „Ustaw EPSG:xxxx” dla projektu bez układu [WF-CRS-STATE]
  i przeliczenie warstwy ze stopni WGS84 [WF-CRS-REPROJECT]

Podkłady:
- wektorowy podkład OpenStreetMap w każdym projekcie, na dole legendy
  [WF-OSM-VECTOR]; rastrowego OSM z tile.openstreetmap.org już nie dokładamy,
  ortofoto Esri zgaszone [WF-ESRI-HIDDEN]
- przenoszenie podkładu przy zamrożonej liście warstw i z jej przebudową —
  usuwa wywrotkę (SIGSEGV) legendy po otwarciu projektu z DXF [WF-OSM-MOVE]
- „Powiększ do całości” bez samych podkładów [WF-EXTENT-BASEMAP]

Projekt:
- uzupełnianie identyfikatorów i wyposażenia przy otwarciu, z pytaniem przy
  projekcie z danymi; wyłącznik w Ustawieniach → Teren [WF-AUTO-EQUIP]
- „Zapisz jako” z obiektami i zdjęciami albo jako pusty wzór [WF-SAVE-AS-DATA]
- katalog wyposażenia bez modułów przyciągania

Pasek szybkiego zapisu:
- okno opcji (nowy QfQuickCaptureOptions.qml) i karta w Narzędziach
  [WF-QC-OPTIONS]
- kafle mieszczą się na ekranie [WF-QC-FIT]

Instalatory łatek w skrypty/jednorazowe/ (24–25.11).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wt9ypZBE7Lqfns3UXekYQE
KONIEC
RC=$?
if [ $RC -ne 0 ]; then
  echo "STOP: commit nie przeszedł (RC=$RC). Cofam git add."
  git reset -q
  exit 1
fi
echo
git log --stat --format='%h %s' -1 | head -60
echo
echo "Zostało zmienione poza commitem:"
git status --short --untracked-files=no
