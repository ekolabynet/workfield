#!/usr/bin/env bash
# WorkFieldGIS 24.11.2026 — wydanie 0.14.13 „Fractal Fir” (kod 1413).
#
# Zamiast `skrypty/wydaj.sh --wykonaj`, bo tamten robi `git add -A`, a w drzewie leży
# ponad 100 nieśledzonych plików (qgis/, brand/, ~95 skryptów) — weszłyby do wydania.
# Ten skrypt dodaje TYLKO scripts/build.sh i notę. Nota pisana dla użytkownika (to ją
# widać w „Co nowego” w aplikacji) i obejmuje tylko zmiany od v0.14.12 (= 6220dacd5).
#
#   bash wydaj_0.14.13.sh            # próba: sprawdza wszystko, pokazuje notę, nic nie zmienia
#   bash wydaj_0.14.13.sh --zapisz   # commit, tag, push, wydanie na GitHubie z APK
set -u
REPO=/DATA/SOFT/GIS/QFIELD_Pro/QField
WERSJA=0.14.13
KOD=1413
TYTUL="WorkFieldGIS ${WERSJA} „Fractal Fir”"
APK=wydania/apk/WorkFieldGIS-0.14.13-1413-arm64-20261124.apk
APK_MD5=510d722d338d15205ca57c258845c392
NOTA=docs/wydania/WhatsNew_0-14-13.md
POPRZEDNI_TAG=v0.14.12
POPRZEDNI_SHA=6220dacd5
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
[ "$(git rev-list --count "${POPRZEDNI_TAG}..HEAD")" = 4 ] || stop "oczekiwałem 4 commitów od ${POPRZEDNI_TAG}"

TRESC=$(cat <<KONIEC_NOTY
# ${TYTUL}

Wydanie z 24.11.2026 — zmiany od 0.14.12.

## Szybsze menu w dużych projektach

Przy każdym otwarciu menu aplikacja sprawdza projekt: czy w danych nie ma obiektów o pustym albo zwiniętym kształcie. Dotąd przeglądała przy tym **wszystkie** warstwy poligonowe projektu — także wyniki analiz z biura (korony, klasy wysokości, budynki 3D) i podkłady, w których w terenie nic nie powstaje. Na starszych telefonach mogło to zatrzymywać ekran przy każdym otwarciu menu.

Teraz sprawdzane są tylko warstwy z pliku danych projektu (\`dane.gpkg\`) i tylko ich kształty. Na laptopie, w projekcie z 29 tys. obiektów, sprawdzenie skróciło się ze 127 ms do 3 ms; w projekcie ze 142 warstwami poligonowymi sprawdzane są 4, z danymi terenowymi.

Ostrzeżenia o pustych i zwiniętych kształtach dotyczą teraz danych terenowych. Próg przyciągania jest porównywany z najmniejszym obiektem w tych danych.

## Pomiar w dzienniku komunikatów

Po każdym sprawdzeniu projektu w dzienniku komunikatów pojawia się linijka \`WorkField [WF-PERF]\` z czasem sprawdzenia i liczbą przejrzanych obiektów (od 300 ms jako ostrzeżenie). **Jeśli aplikacja wydaje się wolna — prześlij tę linijkę razem z modelem telefonu.**

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
git add scripts/build.sh "$NOTA" || stop "git add"
git commit -q -F - <<KONIEC || stop "commit"
Wersja ${WERSJA} (versionCode ${KOD})

Wydanie: szybsze menu w dużych projektach (skan geometrii tylko w pliku
danych), pomiar [WF-PERF] w dzienniku. Nota: ${NOTA}

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
