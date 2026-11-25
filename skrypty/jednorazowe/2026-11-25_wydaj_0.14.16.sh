#!/usr/bin/env bash
# WorkFieldGIS 25.11.2026 — wydanie 0.14.16 „Fractal Fir” (kod 1416): poprawka
# do 0.14.15 — pliki z okna systemowego Androida (content://) [WF-CONTENT-COPY].
#
# Dwa commity: (1) poprawka QfFileBrowser.qml + instalator + ten skrypt,
# (2) wersja: scripts/build.sh + nota. Potem tag, push i wydanie z APK.
# Nic poza tymi plikami nie wchodzi (w drzewie leżą nieśledzone pliki Piotra).
#
#   bash skrypty/jednorazowe/2026-11-25_wydaj_0.14.16.sh            # próba
#   bash skrypty/jednorazowe/2026-11-25_wydaj_0.14.16.sh --zapisz   # commity, tag, push, wydanie
set -u
REPO=${WF_REPO:-/DATA/SOFT/GIS/QFIELD_Pro/QField}
WERSJA=0.14.16
KOD=1416
TYTUL="WorkFieldGIS ${WERSJA} „Fractal Fir”"
NOTA=docs/wydania/WhatsNew_0-14-16.md
POPRZEDNI_TAG=v0.14.15
POPRZEDNI_SHA=f28f76e7d
POPRAWKA=src/app/qml/QfFileBrowser.qml
POPRAWKA_MD5=687a3f6ef4dda20b864518fb8c744f3e
INSTALATOR=skrypty/jednorazowe/2026-11-25_instaluj_pliki_content_kopia.py
TEN_SKRYPT=skrypty/jednorazowe/2026-11-25_wydaj_0.14.16.sh
ZAPISZ=0; [ "${1:-}" = "--zapisz" ] && ZAPISZ=1

stop() { echo "STOP: $*"; exit 1; }
cd "$REPO" || stop "nie ma $REPO"

echo "== gałąź: $(git rev-parse --abbrev-ref HEAD)   HEAD: $(git log -1 --format='%h %s')"
[ "$(git rev-parse --abbrev-ref HEAD)" = development ] || stop "nie jestem na gałęzi development"
[ -n "$(git diff --cached --name-only)" ] && stop "w indeksie już coś czeka — najpierw: git status"

# 1. zmienione dokładnie: wersja i poprawka
ZMIENIONE=$(git diff --name-only HEAD | LC_ALL=C sort | tr '\n' ' ')
[ "$ZMIENIONE" = "scripts/build.sh $POPRAWKA " ] || stop "zmienione pliki inne niż oczekiwane: $ZMIENIONE"
grep -q "APP_VERSION_NUM:-${WERSJA}}" scripts/build.sh || stop "scripts/build.sh nie ma wersji ${WERSJA}"
[ "$(md5sum "$POPRAWKA" | cut -d' ' -f1)" = "$POPRAWKA_MD5" ] || stop "$POPRAWKA ma inne md5 niż $POPRAWKA_MD5"
[ -f "$INSTALATOR" ] || stop "brak $INSTALATOR"
[ -f "$TEN_SKRYPT" ] || stop "ten skrypt ma leżeć w $TEN_SKRYPT"

# 2. APK — dokładnie jeden plik tej wersji, md5 zgodne z notatką przygotuj_apk.sh
mapfile -t APKI < <(ls wydania/apk/WorkFieldGIS-${WERSJA}-${KOD}-arm64-*.apk 2>/dev/null)
[ "${#APKI[@]}" -eq 1 ] || stop "oczekiwałem jednego APK ${WERSJA}, jest ${#APKI[@]}: ${APKI[*]:-brak} — uruchom skrypty/przygotuj_apk.sh"
APK=${APKI[0]}
APK_MD5=$(md5sum "$APK" | cut -d' ' -f1)
grep -q "$APK_MD5" "${APK%.apk}.txt" 2>/dev/null || stop "md5 $APK_MD5 nie zgadza się z notatką ${APK%.apk}.txt"
echo "== APK: $APK   md5 $APK_MD5"

# 3. tagi: poprzedni na miejscu, HEAD = poprzednie wydanie, nowego jeszcze nie ma
git fetch -q origin --tags || stop "git fetch --tags nie przeszedł (sieć?)"
[ "$(git rev-parse --short=9 "${POPRZEDNI_TAG}^{commit}" 2>/dev/null)" = "$POPRZEDNI_SHA" ] || stop "${POPRZEDNI_TAG} nie wskazuje na ${POPRZEDNI_SHA}"
[ "$(git rev-list --count "${POPRZEDNI_TAG}..HEAD")" = 0 ] || stop "od ${POPRZEDNI_TAG} są już commity — ten skrypt ich nie opisuje"
git rev-parse -q --verify "refs/tags/v${WERSJA}" >/dev/null && stop "tag v${WERSJA} już jest lokalnie"
git ls-remote --exit-code --tags origin "refs/tags/v${WERSJA}" >/dev/null 2>&1 && stop "tag v${WERSJA} już jest na GitHubie"
if gh release view "v${WERSJA}" >/dev/null 2>&1; then stop "wydanie v${WERSJA} już jest na GitHubie"; fi

TRESC=$(cat <<KONIEC_NOTY
# ${TYTUL}

Wydanie z 25.11.2026 — poprawka do 0.14.15.

## Pliki z pamięci telefonu

- Pliki GPKG, GeoJSON i inne dane wybrane w oknie systemowym Androida („Pamięć telefonu…”) dają się dodać do projektu. Dotąd aplikacja dostawała od systemu odnośnik zamiast ścieżki i nie umiała pliku otworzyć.
- Taki plik jest najpierw kopiowany do folderu aplikacji „Imported Datasets” (w oknie „Pliki”: Dane), a dalej aplikacja pracuje na kopii. Oryginał zostaje tam, gdzie był.
- To samo dotyczy zakresu inwentaryzacji wskazanego plikiem, georeferencji i importu rysunku DXF.
- Pliki SHP z okna systemowego nadal nie zadziałają: system oddaje sam plik .shp, bez plików towarzyszących. Skopiuj komplet do folderu projektu i wskaż go stamtąd.

---
APK: arm64-v8a · versionCode ${KOD} · md5 \`${APK_MD5}\`
KONIEC_NOTY
)

echo "== nota (${NOTA}):"
echo "$TRESC"

if [ $ZAPISZ -eq 0 ]; then
  echo
  echo "PRÓBA — nic nie zmieniono. Wydanie: dopisz --zapisz"
  exit 0
fi

git add "$POPRAWKA" "$INSTALATOR" "$TEN_SKRYPT" || stop "git add poprawki"
git commit -q -F - <<KONIEC || { git reset -q; stop "commit poprawki"; }
Okno „Pliki”: plik z okna systemowego Androida kopiowany przed otwarciem [WF-CONTENT-COPY]

- okno systemowe („Pamięć telefonu…”) oddaje odnośnik content://, którego
  GDAL/OGR nie otwiera („OGR: Cannot open content://…”, test 25.11 10:56:
  „Dodaj z pliku” GPKG/GeoJSON na telefonie)
- plik idzie najpierw do „Imported Datasets” w katalogu aplikacji (nazwa
  z systemu, przy zajętej _2, _3…), dalej kopia; dotyczy wszystkich miejsc
  wyboru pliku i przeglądania pamięci telefonu
- na komputerze bez zmian (zwykłe ścieżki)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wt9ypZBE7Lqfns3UXekYQE
KONIEC

mkdir -p docs/wydania
printf '%s\n' "$TRESC" > "$NOTA"
git add scripts/build.sh "$NOTA" || stop "git add wersji"
git commit -q -F - <<KONIEC || stop "commit wersji"
Wersja ${WERSJA} (versionCode ${KOD})

Wydanie: pliki z okna systemowego Androida (content://) kopiowane przed
otwarciem. Nota: ${NOTA}

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wt9ypZBE7Lqfns3UXekYQE
KONIEC
git tag -a "v${WERSJA}" -m "${TYTUL}" || stop "tag"
echo "== push development…"
git push origin development || stop "push development nie przeszedł — wydania NIE zakładam (tag v${WERSJA} jest tylko lokalnie)"
git push origin "v${WERSJA}" || stop "push tagu nie przeszedł — wydania NIE zakładam"
echo "== wydanie na GitHubie…"
gh release create "v${WERSJA}" "$APK" --verify-tag --title "${TYTUL}" --notes-file "$NOTA" || stop "gh release create nie przeszedł — commity i tag są na GitHubie; powtórz samo: gh release create v${WERSJA} $APK --verify-tag --title '${TYTUL}' --notes-file $NOTA"
echo "== gotowe:"
git --no-pager log --oneline -3
gh release view "v${WERSJA}" --json url,assets --jq '.url, (.assets[] | "  " + .name)'
