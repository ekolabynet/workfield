#!/usr/bin/env bash
# WorkFieldGIS 25.11.2026 — commit poprawki kreatora „Projekt z rysunku CAD”
# [WF-CAD-NAME-TAKEN]. Domyślnie PRÓBA; commit: --zapisz.
# Miejsce w repo: skrypty/jednorazowe/2026-11-25_commit_kreator_cad.sh
# scripts/build.sh NIE wchodzi (wersja — commit wydania).
set -u
REPO=${WF_REPO:-/DATA/SOFT/GIS/QFIELD_Pro/QField}
cd "$REPO" || { echo "STOP: brak $REPO"; exit 1; }

ZAPISZ=0
[ "${1:-}" = "--zapisz" ] && ZAPISZ=1

# Pliki śledzone, które MAJĄ być zmienione (bez scripts/build.sh).
OCZEKIWANE="src/app/qml/QfProjektZCAD.qml"
POMIJANE="scripts/build.sh"

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

# Instalator i ten skrypt, jeszcze nieśledzone.
INSTALATORY=$(git ls-files --others --exclude-standard -- 'skrypty/jednorazowe/2026-11-25_instaluj_kreator_cad_nazwa.py' 'skrypty/jednorazowe/2026-11-25_commit_kreator_cad.sh' | sort)

echo "Wejdą pliki zmienione: $(echo "$OCZEKIWANE" | wc -l)"
echo "Wejdą skrypty jednorazowe ($(echo "$INSTALATORY" | grep -c .)):"
echo "$INSTALATORY" | sed 's/^/  /'
echo

if [ "$ZAPISZ" -ne 1 ]; then
  echo "PRÓBA — nic nie zapisano. Commit: bash $0 --zapisz"
  exit 0
fi

# shellcheck disable=SC2086
git add -- $OCZEKIWANE || { echo "STOP: git add nie przeszedł"; git reset -q; exit 1; }
while IFS= read -r plik; do
  [ -n "$plik" ] && { git add -- "$plik" || { echo "STOP: git add $plik"; git reset -q; exit 1; }; }
done <<< "$INSTALATORY"

git commit -F - <<'KONIEC'
Kreator „Projekt z rysunku CAD”: komunikat o zajętej nazwie [WF-CAD-NAME-TAKEN]

- sprawdzenie „Projekt o tej nazwie już istnieje” nigdy nie działało:
  FileUtils.fileExists() zwraca prawdę tylko dla pliku, a projekt to katalog;
  teraz pytamy o projekt.qgs / projekt.qgz / dane.gpkg w katalogu
- gdy projekt mimo to nie powstanie, komunikat mówi, gdzie szukać katalogu
  o tej nazwie
- czerwony komunikat znika przy zmianie nazwy

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
