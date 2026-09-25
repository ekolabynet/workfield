#!/bin/bash
# =====================================================================
#  WorkFieldGIS — build desktopowy
# =====================================================================
#  PO CO. Wersja androidowa idzie przez scripts/build.sh z tripletem
#  i od latki „licznik buildow" PODBIJA NUMER przy kazdym przebiegu.
#  Desktop nie ma z tym nic wspolnego: buduje ten sam kod w build-sys,
#  NIE rusza wersji i NIE tworzy APK.  Sluzy do dwoch rzeczy —
#  ogladania zmian bez cyklu Docker/adb oraz do konsoli, ktora na
#  komputerze ma pelna klawiature i widoczny stdout.
#
#  UZYCIE
#      bash skrypty/zbuduj_desktop.sh            # zbuduj
#      bash skrypty/zbuduj_desktop.sh --uruchom  # zbuduj i odpal
#      bash skrypty/zbuduj_desktop.sh --od-zera  # skonfiguruj na nowo
#
#  Kod wyjscia: 0 zbudowane, 1 blad budowania, 2 zly katalog.
# =====================================================================
set -u
KATALOG="${KATALOG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUD="${BUD:-build-sys}"
cd "$KATALOG" || exit 2

[ -f CMakeLists.txt ] || { echo "To nie jest korzen repozytorium: $KATALOG" >&2; exit 2; }
echo "== repo: $KATALOG"
echo "== katalog budowania: $BUD"

ODZERA=0; URUCHOM=0
for a in "$@"; do
  case "$a" in
    --od-zera) ODZERA=1 ;;
    --uruchom) URUCHOM=1 ;;
    *) echo "nieznany przelacznik: $a" >&2; exit 2 ;;
  esac
done

# --- konfiguracja tylko wtedy, gdy trzeba ---------------------------
if [ "$ODZERA" = 1 ] || [ ! -f "$BUD/CMakeCache.txt" ]; then
  echo "== konfiguruje ($([ "$ODZERA" = 1 ] && echo 'wymuszone' || echo 'brak CMakeCache.txt'))"
  [ "$ODZERA" = 1 ] && rm -rf "$BUD"
  PRESET=""
  if [ -f CMakePresets.json ]; then
    for p in linux-release linux x64-linux desktop default; do
      grep -q "\"$p\"" CMakePresets.json && { PRESET="$p"; break; }
    done
  fi
  if [ -n "$PRESET" ]; then
    echo "   preset: $PRESET"
    cmake --preset "$PRESET" -B "$BUD" || exit 1
  else
    echo "   bez presetu — konfiguracja recznie"
    cmake -S . -B "$BUD" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$PWD/$BUD/output/bin" \
      || exit 1
  fi
fi

# --- budowanie -------------------------------------------------------
RDZ="$(nproc 2>/dev/null || echo 4)"
echo "== buduje na $RDZ rdzeniach (wersja NIE jest podbijana)"
CZAS_START=$(date +%s)
cmake --build "$BUD" -j"$RDZ" 2>&1 | tail -n 15
WYNIK=${PIPESTATUS[0]}
CZAS=$(( $(date +%s) - CZAS_START ))
[ "$WYNIK" = 0 ] || { echo "== BUILD PADL (kod $WYNIK, $CZAS s)" >&2; exit 1; }

# --- gdzie wyladowal plik wykonywalny --------------------------------
BIN=""
for k in "$BUD/output/bin/qfield" "$BUD/output/bin/workfieldgis" \
         "$BUD/src/app/qfield" "$BUD/bin/qfield"; do
  [ -x "$k" ] && { BIN="$k"; break; }
done
[ -n "$BIN" ] || BIN="$(find "$BUD" -maxdepth 5 -type f -perm -u+x \
                        \( -name qfield -o -name workfieldgis \) 2>/dev/null | head -1)"

echo "== gotowe w ${CZAS}s"
if [ -n "$BIN" ]; then
  echo "   plik:      $BIN"
  echo "   zbudowany: $(date -r "$BIN" '+%Y-%m-%d %H:%M')"
  # Ta sama kontrola, ktorej zabraklo w przygotuj_apk.sh: czy plik jest
  # MLODSZY od ostatniego commita.  Milczaca praca na starym binarium
  # kosztowala juz jedno wydanie.
  if [ -d .git ]; then
    C=$(git log -1 --format=%ct 2>/dev/null || echo 0)
    B=$(date -r "$BIN" +%s)
    if [ "$B" -lt "$C" ]; then
      echo "   ! UWAGA: plik jest STARSZY od ostatniego commita" >&2
      echo "     $(git log -1 --format='%h %s' 2>/dev/null)" >&2
    fi
  fi
else
  echo "   ! nie znalazlem pliku wykonywalnego w $BUD" >&2
fi

echo
echo "Uruchomienie:"
echo "  ${BIN:-$BUD/output/bin/qfield}"
echo
echo "Konsola (wtyczka WorkField): szuflada -> Wtyczki -> Konsola."
echo "Na desktopie stdout ida do terminala, wiec console.log() widac tutaj."

if [ "$URUCHOM" = 1 ] && [ -n "$BIN" ]; then
  echo "== uruchamiam"
  exec "$BIN"
fi
