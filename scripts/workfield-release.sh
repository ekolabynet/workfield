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
cp "$APK" "/tmp/${NAZWA}"

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

gh release create "v${WERSJA}" "/tmp/${NAZWA}" \
  --title "WorkField ${WERSJA}" \
  --notes "${OPIS}

Nieoficjalny fork QField - szczegoly w NOTICE.md. / Unofficial QField fork, see NOTICE.md."

echo "Gotowe: https://github.com/ekolabynet/workfield/releases/tag/v${WERSJA}"
