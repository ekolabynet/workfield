#!/usr/bin/env bash
# Ikony aplikacji: brand/ jest ŹRÓDŁEM, platform/android/res/ tylko celem.
#
# Powód istnienia tego skryptu: 1.08.2026 okazało się, że w buildzie siedziała
# inna wersja ikony niż w katalogu marki — wypełniająca 96% kwadratu, bez
# marginesu. Android nakłada na ikony maskę, więc taki kształt jest przycinany
# na rogach i wygląda na spuchnięty. Ręczne kopiowanie plików między katalogami
# prędzej czy później się rozjeżdża; skrypt tego pilnuje.
#
# UZYCIE:  scripts/sync-brand-icons.sh [--sprawdz]
set -euo pipefail

KORZEN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZRODLO="$KORZEN/brand/android"
CEL="$KORZEN/platform/android/res"
GESTOSCI="mdpi hdpi xhdpi xxhdpi xxxhdpi"
TYLKO_SPRAWDZ=0
[ "${1:-}" = "--sprawdz" ] && TYLKO_SPRAWDZ=1

roznice=0
for g in $GESTOSCI; do
  z="$ZRODLO/drawable-$g/workfieldgis.png"
  c="$CEL/drawable-$g/workfieldgis.png"

  if [ ! -f "$z" ]; then
    echo "  !! brak w brand: drawable-$g"
    roznice=$((roznice + 1))
    continue
  fi

  if [ -f "$c" ] && cmp -s "$z" "$c"; then
    echo "  ✓ drawable-$g"
    continue
  fi

  roznice=$((roznice + 1))
  if [ "$TYLKO_SPRAWDZ" = 1 ]; then
    echo "  ! RÓŻNI SIĘ: drawable-$g"
  else
    mkdir -p "$(dirname "$c")"
    cp "$z" "$c"
    echo "  → zaktualizowano: drawable-$g"
  fi
done

echo
if [ "$roznice" = 0 ]; then
  echo "Ikony zgodne ze źródłem."
elif [ "$TYLKO_SPRAWDZ" = 1 ]; then
  echo "Rozbieżności: $roznice — uruchom bez --sprawdz, żeby naprawić."
  exit 1
else
  echo "Zaktualizowano $roznice plików. Zbuduj APK, żeby zobaczyć efekt."
fi
