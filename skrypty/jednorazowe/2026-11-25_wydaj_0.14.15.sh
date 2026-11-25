#!/usr/bin/env bash
# WorkFieldGIS 25.11.2026 — wydanie 0.14.15 „Fractal Fir” (kod 1415).
#
# Zamiast `skrypty/wydaj.sh --wykonaj`, bo tamten robi `git add -A`, a w drzewie leży
# ponad 100 nieśledzonych plików (qgis/, brand/, ~95 skryptów) — weszłyby do wydania.
# Ten skrypt dodaje TYLKO scripts/build.sh i notę. Nota pisana dla użytkownika (to ją
# widać w „Co nowego” w aplikacji) i obejmuje tylko zmiany od v0.14.13 (= 9f2ab088b).
# 0.14.14 to buildy testowe z 24.11 (kod 1414) — nie wydane.
#
#   bash skrypty/jednorazowe/2026-11-25_wydaj_0.14.15.sh            # próba: sprawdza wszystko, pokazuje notę, nic nie zmienia
#   bash skrypty/jednorazowe/2026-11-25_wydaj_0.14.15.sh --zapisz   # commit, tag, push, wydanie na GitHubie z APK
set -u
REPO=${WF_REPO:-/DATA/SOFT/GIS/QFIELD_Pro/QField}
WERSJA=0.14.15
KOD=1415
TYTUL="WorkFieldGIS ${WERSJA} „Fractal Fir”"
APK=wydania/apk/WorkFieldGIS-0.14.15-1415-arm64-20261125.apk
APK_MD5=40ee297ed31136ad13df0a371be635c7
NOTA=docs/wydania/WhatsNew_0-14-15.md
POPRZEDNI_TAG=v0.14.13
POPRZEDNI_SHA=9f2ab088b
ZAPISZ=0; [ "${1:-}" = "--zapisz" ] && ZAPISZ=1

stop() { echo "STOP: $*"; exit 1; }
cd "$REPO" || stop "nie ma $REPO"

echo "== gałąź: $(git rev-parse --abbrev-ref HEAD)   HEAD: $(git log -1 --format='%h %s')"
[ "$(git rev-parse --abbrev-ref HEAD)" = development ] || stop "nie jestem na gałęzi development"
[ -n "$(git diff --cached --name-only)" ] && stop "w indeksie już coś czeka — najpierw: git status"

# 1. tylko scripts/build.sh zmieniony (podbita wersja), z właściwym numerem
ZMIENIONE=$(git diff --name-only HEAD)
[ "$ZMIENIONE" = "scripts/build.sh" ] || stop "zmienione pliki inne niż scripts/build.sh: $(echo $ZMIENIONE)"
grep -q "APP_VERSION_NUM:-${WERSJA}}" scripts/build.sh || stop "scripts/build.sh nie ma wersji ${WERSJA}"

# 2. APK — ta sama suma co z przygotuj_apk.sh
[ -f "$APK" ] || stop "brak $APK"
[ "$(md5sum "$APK" | cut -d' ' -f1)" = "$APK_MD5" ] || stop "md5 APK inne niż $APK_MD5"

# 3. tagi z GitHuba: poprzedni na miejscu, nowego jeszcze nie ma
git fetch -q origin --tags || stop "git fetch --tags nie przeszedł (sieć?)"
[ "$(git rev-parse --short=9 "${POPRZEDNI_TAG}^{commit}" 2>/dev/null)" = "$POPRZEDNI_SHA" ] \
  || stop "${POPRZEDNI_TAG} nie wskazuje na ${POPRZEDNI_SHA}"
git rev-parse -q --verify "refs/tags/v${WERSJA}" >/dev/null && stop "tag v${WERSJA} już jest lokalnie"
git ls-remote --exit-code --tags origin "refs/tags/v${WERSJA}" >/dev/null 2>&1 && stop "tag v${WERSJA} już jest na GitHubie"
if gh release view "v${WERSJA}" >/dev/null 2>&1; then stop "wydanie v${WERSJA} już jest na GitHubie — dołącz APK: bash skrypty/przygotuj_apk.sh --wyslij"; fi

echo "== commity w wydaniu (od ${POPRZEDNI_TAG}):"
git log --oneline "${POPRZEDNI_TAG}..HEAD"
[ "$(git rev-list --count "${POPRZEDNI_TAG}..HEAD")" = 3 ] || stop "oczekiwałem 3 commitów od ${POPRZEDNI_TAG}"

TRESC=$(cat <<KONIEC_NOTY
# ${TYTUL}

Wydanie z 25.11.2026 — zmiany od 0.14.13. Numer 0.14.14 nosiły wewnętrzne buildy testowe; takiego wydania nie było.

## Układ współrzędnych rozpoznawany z samych liczb

Aplikacja patrzy na wartości współrzędnych warstwy i rozpoznaje, w jakim są układzie: PL-2000 (strefy 5–8), PL-1992, stopnie WGS84 albo Web Mercator. Rozpoznaje też zamienione osie X i Y oraz współrzędne lokalne rysunku (blisko punktu 0,0). Sprawdzenie odbywa się po dodaniu pliku, przy otwarciu projektu i na żądanie: **Narzędzia → „Układy warstw — sprawdź”**.

- Gdy zapisany układ nie pasuje do liczb, pojawia się okno z wyborem: **„W locie”** (warstwa dostaje właściwy układ, plik się nie zmienia), **„Konwertuj do bazy projektu”** (obiekty przeliczone do układu projektu trafiają do bazy projektu, a przedtem powstaje kopia bazy) albo **„Pomiń”**. Przy zamienionych osiach pomaga tylko konwersja.
- Rysunek CAD zachowuje po konwersji swoje kolory i grubości linii.
- Rysunek DXF bez zapisanego układu, którego liczby pasują do układu projektu, dostaje ten układ sam, bez pytania.
- Obiekty leżące przy punkcie 0,0, częste w rysunkach CAD, nie rozciągają już widoku. Po wczytaniu rysunku mapa pokazuje jego właściwą część, a aplikacja mówi, ile obiektów leży poza obszarem układu.

## Podkład OpenStreetMap

- Każdy projekt ma wektorowy podkład OpenStreetMap na dole listy warstw. Ortofotomapa Esri jest w projekcie, ale zgaszona; włącza się ją na liście warstw.
- Naprawiono zamykanie się aplikacji przy otwieraniu projektu z rysunkiem DXF.
- „Powiększ do całości” pomija podkłady i pokazuje dane.

## Projekt

- Nowy pusty projekt zawsze ma układ współrzędnych (domyślnie PL-2000 strefa 7).
- Okno naprawy projektu proponuje „Ustaw EPSG:…” dla projektu bez układu i przelicza warstwę zapisaną w stopniach.
- Przy otwarciu projektu brakujące identyfikatory obiektów i wyposażenie uzupełniają się same; w projekcie z danymi aplikacja najpierw pyta. Wyłącznik: Ustawienia → Teren.
- „Zapisz jako” zapisuje kopię z obiektami i zdjęciami albo pusty wzór projektu.
- Kreator „Projekt z rysunku CAD” mówi wprost, że projekt o podanej nazwie już istnieje.
- Z katalogu wyposażenia usunięto moduły przyciągania.

## Pasek szybkiego zapisu

- Nowe okno opcji paska, dostępne także z karty w Narzędziach.
- Kafle mieszczą się na ekranie.

## Szybszy start

Część okien powstaje dopiero przy pierwszym użyciu, więc aplikacja startuje szybciej. Czas startu zapisuje się w dzienniku komunikatów.

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

mkdir -p docs/wydania
printf '%s\n' "$TRESC" > "$NOTA"
git add scripts/build.sh "$NOTA" skrypty/jednorazowe/2026-11-25_wydaj_0.14.15.sh || stop "git add"
git commit -q -F - <<KONIEC || stop "commit"
Wersja ${WERSJA} (versionCode ${KOD})

Wydanie: układ warstw rozpoznawany z wartości współrzędnych, podkład OSM
wektorowy, uzupełnianie projektu, pasek szybkiego zapisu, szybszy start,
kreator CAD. Nota: ${NOTA}

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wt9ypZBE7Lqfns3UXekYQE
KONIEC
git tag -a "v${WERSJA}" -m "${TYTUL}" || stop "tag"
echo "== push development…"
git push origin development || stop "push development nie przeszedł — wydania NIE zakładam (tag v${WERSJA} jest tylko lokalnie)"
git push origin "v${WERSJA}" || stop "push tagu nie przeszedł — wydania NIE zakładam"
echo "== wydanie na GitHubie…"
gh release create "v${WERSJA}" "$APK" --verify-tag --title "${TYTUL}" --notes-file "$NOTA" || stop "gh release create nie przeszedł — commit i tag są na GitHubie; powtórz samo: gh release create v${WERSJA} $APK --verify-tag --title '${TYTUL}' --notes-file $NOTA"
echo "== gotowe:"
git log --oneline -1
gh release view "v${WERSJA}" --json url,assets --jq '.url, (.assets[] | "  " + .name)'
