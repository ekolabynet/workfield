#!/usr/bin/env bash
# Wydanie WorkField: jednolita nazwa APK, tag i publikacja na GitHubie.
#
#   ./scripts/workfield-release.sh "Opis zmian dla ekipy"
#
# Wersje bierze z scripts/build.sh (APP_VERSION_STR) - jedno zrodlo prawdy.
set -euo pipefail

cd "$(dirname "$0")/.."

WERSJA=$(sed -n 's/^export APP_VERSION_STR=${APP_VERSION_STR:-\(.*\)}$/\1/p' scripts/build.sh)
if [ -z "$WERSJA" ]; then
  echo "Nie umiem odczytac wersji z scripts/build.sh" >&2
  exit 1
fi

APK=$(find build-arm64-android -name "android-build-release.apk" -print -quit)
if [ -z "$APK" ]; then
  echo "Brak podpisanego APK - zbuduj: triplet=arm64-android ./scripts/build.sh" >&2
  exit 1
fi

NAZWA="WorkField-${WERSJA}-arm64.apk"
# Druga kopia pod NIEZMIENNA nazwa: dzieki niej dziala staly adres
#   .../releases/latest/download/WorkField-arm64.apk
# ktory mozna dac wspolpracownikom raz i nie zmieniac przy kazdym wydaniu.
STALA="WorkField-arm64.apk"
cp "$APK" "/tmp/${NAZWA}"
cp "$APK" "/tmp/${STALA}"

echo "Wersja:  ${WERSJA}"
echo "Pakiet:  ${NAZWA}  ($(du -h "/tmp/${NAZWA}" | cut -f1))"
echo "Kod:     $(grep -o '"versionCode": [0-9]*' "$(dirname "$APK")/output-metadata.json" | head -1)"
echo

OPIS="${1:-}"
if [ -z "$OPIS" ]; then
  echo "Podaj opis zmian jako argument." >&2
  exit 1
fi

git tag "v${WERSJA}" 2>/dev/null || echo "Tag v${WERSJA} juz istnieje - uzywam go."
git push origin "v${WERSJA}"

# wydanie moze juz istniec (wersje podbija sie czasem wczesniej niz wydaje) —
# wtedy dogrywamy pliki zamiast przerywac
if gh release view "v${WERSJA}" >/dev/null 2>&1; then
  gh release upload "v${WERSJA}" "/tmp/${NAZWA}" "/tmp/${STALA}" --clobber
  echo "Podmieniono pliki w istniejacym wydaniu v${WERSJA}."
  echo "https://github.com/ekolabynet/workfield/releases/tag/v${WERSJA}"
  echo
  echo "Link dla wspolpracownikow (zawsze najnowsza wersja):"
  echo "  https://github.com/ekolabynet/workfield/releases/latest/download/${STALA}"
  exit 0
fi

gh release create "v${WERSJA}" "/tmp/${NAZWA}" "/tmp/${STALA}" \
  --title "WorkField ${WERSJA}" \
  --notes "${OPIS}

Nieoficjalny fork QField - szczegoly w NOTICE.md. / Unofficial QField fork, see NOTICE.md."

echo "Gotowe: https://github.com/ekolabynet/workfield/releases/tag/v${WERSJA}"
echo
echo "Link dla wspolpracownikow (zawsze najnowsza wersja):"
echo "  https://github.com/ekolabynet/workfield/releases/latest/download/${STALA}"
