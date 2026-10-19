#!/usr/bin/env bash
# WorkFieldGIS — wersja terenowa projektu na telefon, kablem (adb).
#
#   bash wyslij_na_telefon.sh "KATALOG_TERENOWY"            # PRÓBA
#   bash wyslij_na_telefon.sh "KATALOG_TERENOWY" --zapisz   # wysyłka
#   opcja: --nazwa "NAZWA"   katalog na telefonie (domyślnie z TEREN.txt)
#
# KATALOG_TERENOWY to wynik `projekt_na_teren.py`: pliki + TEREN.md5 + TEREN.txt.
# Wysyła DOKŁADNIE pliki wymienione w TEREN.md5 — nic więcej.
#
# Do:  Android/data/ch.opengis.qfield_home/files/Imported Projects/<NAZWA>
#
#  - sprawdza md5 KAŻDEGO pliku przed wysyłką i PO wysyłce, już na telefonie,
#  - odmawia, gdy obok bazy leży -wal/-shm,
#  - sprawdza wolne miejsce na telefonie,
#  - NIE nadpisuje: katalog na telefonie nie może istnieć. Starego wydania nie
#    rusza — zostaje na telefonie, dopóki nowe nie jest potwierdzone.

set -u
set -o pipefail
PAKIET="${WF_PAKIET:-ch.opengis.qfield_home}"

KAT=""; NAZWA=""; ZAPISZ=0
while [ $# -gt 0 ]; do
  case "$1" in
    --zapisz) ZAPISZ=1; shift ;;
    --nazwa)  NAZWA="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) KAT="$1"; shift ;;
  esac
done
[ -n "$KAT" ] || { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
KAT="${KAT%/}"
[ -f "$KAT/TEREN.md5" ] || { echo "STOP: w $KAT nie ma TEREN.md5 — to nie jest katalog z projekt_na_teren.py"; exit 1; }
if [ -z "$NAZWA" ]; then
  NAZWA=$(sed -n 's/^telefon: //p' "$KAT/TEREN.txt" 2>/dev/null | head -1)
fi
[ -n "$NAZWA" ] || { echo "STOP: nie znam nazwy katalogu na telefonie — podaj --nazwa"; exit 1; }
CEL="/storage/emulated/0/Android/data/$PAKIET/files/Imported Projects/$NAZWA"

echo "== na komputerze: $KAT"
for g in "$KAT"/*.gpkg; do
  [ -e "$g" ] || continue
  for d in -wal -shm; do
    if [ -e "$g$d" ]; then
      echo "STOP: obok $(basename "$g") leży $(basename "$g")$d — baza jest otwarta. Zamknij QGIS / WorkFieldGIS."
      exit 1
    fi
  done
done
mapfile -t WIERSZE < "$KAT/TEREN.md5"
RAZEM=0
for w in "${WIERSZE[@]}"; do
  [ -n "$w" ] || continue
  sum="${w%%  *}"; f="${w#*  }"
  if [ ! -f "$KAT/$f" ]; then echo "STOP: brak pliku $f"; exit 1; fi
  m=$(md5sum "$KAT/$f" | cut -d' ' -f1)
  rozm=$(stat -c %s "$KAT/$f"); RAZEM=$((RAZEM + rozm))
  printf '   %-52s %8s\n' "$f" "$(du -h "$KAT/$f" | cut -f1)"
  if [ "$m" != "$sum" ]; then
    echo "STOP: $f zmienił się od przygotowania (md5 $m, w TEREN.md5 $sum). Nie wysyłam."
    exit 1
  fi
done
echo "   razem: $((RAZEM / 1048576)) MB, sumy md5 zgodne z TEREN.md5"

echo "== telefon"
command -v adb >/dev/null || { echo "STOP: nie ma adb"; exit 1; }
N=$(adb devices | sed -n '2,$p' | grep -c "device$" || true)
if [ "$N" != "1" ]; then
  echo "STOP: podpiętych telefonów: $N (ma być 1)."
  adb devices | sed 's/^/   /'
  echo "   kabel z transmisją danych, debugowanie USB, „Zezwól” na telefonie."
  exit 1
fi
echo "   $(adb shell getprop ro.product.model | tr -d '\r')"
WOLNE_KB=$(adb shell "df -k /storage/emulated/0 | tail -1" | tr -s ' ' | cut -d' ' -f4 | tr -d '\r')
echo "   wolne: $((WOLNE_KB / 1024)) MB, potrzeba: $((RAZEM / 1048576)) MB"
if [ "$WOLNE_KB" -lt $((RAZEM / 1024 + 200 * 1024)) ]; then
  echo "STOP: za mało miejsca na telefonie."
  exit 1
fi
if adb shell "[ -e '$CEL' ]"; then
  echo "STOP: na telefonie już jest katalog:"
  echo "   $CEL"
  echo "   Nie nadpisuję. Stara wersja zostaje, dopóki nowa nie jest potwierdzona."
  echo "   Wyślij pod inną nazwą:  --nazwa \"$NAZWA $(date +%Y-%m-%d)\""
  adb shell "ls -la '$CEL'" | sed 's/^/   /'
  exit 1
fi
echo "   cel: Imported Projects/$NAZWA  (jeszcze nie istnieje — dobrze)"

if [ "$ZAPISZ" != "1" ]; then
  echo
  echo "PRÓBA — nic nie wysłano. Wysyłka: dodaj --zapisz"
  exit 0
fi

echo
echo "== wysyłam"
adb shell "mkdir -p '$CEL'" || { echo "STOP: nie udało się założyć katalogu"; exit 1; }
for w in "${WIERSZE[@]}"; do
  [ -n "$w" ] || continue
  f="${w#*  }"
  echo "   -> $f"
  adb push "$KAT/$f" "$CEL/" | tail -1 | sed 's/^/      /' || { echo "STOP: nie wysłał się $f"; exit 1; }
done

echo "== sprawdzam na telefonie"
BLAD=0
for w in "${WIERSZE[@]}"; do
  [ -n "$w" ] || continue
  sum="${w%%  *}"; f="${w#*  }"
  m=$(adb shell "md5sum '$CEL/$f'" | cut -d' ' -f1 | tr -d '\r')
  if [ "$m" = "$sum" ]; then echo "   OK    $f"; else echo "   BŁĄD  $f  (na telefonie: ${m:-brak})"; BLAD=1; fi
done
adb shell "ls -la '$CEL'" | sed 's/^/   /'
if [ "$BLAD" = "1" ]; then
  echo "STOP: nie wszystko dojechało w całości. Nie otwieraj projektu — wklej ten wynik."
  exit 1
fi
echo
echo "GOTOWE. W WorkFieldGIS: Otwórz projekty → „$NAZWA”."
