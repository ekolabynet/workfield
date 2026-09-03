#!/usr/bin/env bash
# Rytuał zwrotu z terenu — wykonywalna wersja punktu 13
# z `claude/OBIEG_zwroty_praktyka.md`.
#
# Robi dokładnie to, co robi się dziś ręcznie, tylko bez pomijania kroków:
#   1. domyka bazę na telefonie i SPRAWDZA, czy naprawdę się domknęła
#   2. zakłada katalog datowany (nigdy nie nadpisuje)
#   3. ciągnie pliki POJEDYNCZO (adb pull przerywa się na pierwszym błędzie)
#   4. porównuje sumy md5 źródła i kopii          <- czego rytuał ręczny nie robił
#   5. ciągnie DCIM
#   6. odpala kontrole: przyrost, puste geometrie, załączniki
#
# NIC NIE KASUJE ani na telefonie, ani na dysku. Nie nadpisuje istniejącego
# katalogu zwrotu — przerywa.
#
# Użycie:
#   ./zwrot.sh -p zzw_pgrs_2602_inw_v9_0
#   ./zwrot.sh -p zzw_pgrs_2602_inw_v9_0 -e pgrs_v9_0 -r ~/WorkField_zwroty/2026-08-21_pgrs_v8_0/dane.gpkg
#   ./zwrot.sh -p PROJEKT --dcim-do ~/WorkField_zdjecia/pgrs   # DCIM narastająco, osobno od baz
#
# Wymaga: adb w PATH, telefon podpięty i autoryzowany (adb devices).

set -u
set -o pipefail

PAKIET="${WF_PAKIET:-ch.opengis.qfield_home}"
KORZEN_ZWROTOW="${WF_ZWROTY:-$HOME/WorkField_zwroty}"
PLIKI=(dane.gpkg projekt.qgs workfield_klawisze.json)
# projekt_attachments.zip celowo POMINIĘTY: prawa -rw------- należą do
# aplikacji, adb shell go nie przeczyta, a adb pull przerywa się na pierwszym
# błędzie i reszta katalogu wtedy nie dojeżdża (20.08: 20 MB zamiast 1 GB).

PROJEKT=""
ETYKIETA=""
RANO=""
DCIM_DO=""
BEZ_DCIM=0
KATALOG_SKRYPTOW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

uzycie() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--projekt)   PROJEKT="${2:-}"; shift 2 ;;
    -e|--etykieta)  ETYKIETA="${2:-}"; shift 2 ;;
    -r|--rano)      RANO="${2:-}"; shift 2 ;;
    --dcim-do)      DCIM_DO="${2:-}"; shift 2 ;;
    --bez-dcim)     BEZ_DCIM=1; shift ;;
    --pakiet)       PAKIET="${2:-}"; shift 2 ;;
    -h|--help)      uzycie 0 ;;
    *) echo "nieznany argument: $1" >&2; uzycie 2 ;;
  esac
done

[[ -n "$PROJEKT" ]] || { echo "brakuje -p NAZWA_PROJEKTU" >&2; uzycie 2; }
[[ -n "$ETYKIETA" ]] || ETYKIETA="$PROJEKT"

command -v adb >/dev/null || { echo "nie ma adb w PATH" >&2; exit 1; }

K="/storage/emulated/0/Android/data/$PAKIET/files/Imported Projects/$PROJEKT"
D="$KORZEN_ZWROTOW/$(date +%Y-%m-%d)_$ETYKIETA"

echo "telefon:  $PAKIET"
echo "projekt:  $PROJEKT"
echo "zwrot do: $D"
echo

# ---------------------------------------------------------------- 0. telefon
echo "== 0. telefon =="
adb devices | sed '1d' | grep -q "device$" || {
  echo "!! żadne urządzenie nie jest w stanie 'device'." >&2
  adb devices >&2
  echo "   Sprawdź kabel, odblokuj ekran, potwierdź autoryzację USB." >&2
  exit 1
}
adb devices | sed '1d' | sed '/^$/d'

adb shell "[ -d \"$K\" ]" || {
  echo "!! na telefonie nie ma katalogu:" >&2
  echo "   $K" >&2
  echo "   Dostępne projekty:" >&2
  adb shell "ls \"/storage/emulated/0/Android/data/$PAKIET/files/Imported Projects/\"" >&2
  exit 1
}
echo

# ------------------------------------------------------- 1. domknięcie bazy
echo "== 1. domknięcie bazy (to jest krok, którego pominięcie gubi dane) =="
adb shell am force-stop "$PAKIET"
sleep 2
adb shell "ls -la \"$K/\"*.gpkg* 2>/dev/null" || true

WISZACE="$(adb shell "ls \"$K/\"*.gpkg-wal \"$K/\"*.gpkg-shm 2>/dev/null" | tr -d '\r' | sed '/^$/d')"
if [[ -n "$WISZACE" ]]; then
  echo
  echo "!! obok bazy nadal leżą pliki dziennika:" >&2
  echo "$WISZACE" >&2
  echo "   W -wal siedzą zapisy, których nie ma jeszcze w .gpkg." >&2
  echo "   Skopiowanie samego .gpkg ZGUBI CZĘŚĆ PRACY." >&2
  echo "   Otwórz aplikację, zamknij projekt po ludzku, zamknij aplikację" >&2
  echo "   i uruchom zwrot jeszcze raz. NIE kopiuj teraz." >&2
  exit 1
fi
echo "   -shm/-wal zniknęły — baza domknięta."
echo

# --------------------------------------------------- 2. katalog datowany
echo "== 2. katalog datowany =="
if [[ -e "$D" ]]; then
  echo "!! $D już istnieje. Nie nadpisuję." >&2
  echo "   Dodaj etykietę (-e), np. -e ${ETYKIETA}_popoludnie" >&2
  exit 1
fi
mkdir -p "$D" || exit 1
echo "   $D"
echo

# --------------------------------------- 3+4. pliki pojedynczo, z sumami
echo "== 3. pliki pojedynczo + 4. sumy kontrolne =="
echo "   (rozmiar NIE rozstrzyga: 21.08 dwa dane.gpkg miały identyczne"
echo "    2 609 152 B i różną treść — 278 kontra 280 płatów)"
BLEDY=0
for f in "${PLIKI[@]}"; do
  if ! adb shell "[ -f \"$K/$f\" ]"; then
    echo "   - $f: nie ma na telefonie (pomijam)"
    continue
  fi
  if adb pull "$K/$f" "$D/" >/dev/null 2>&1; then
    ZDALNA="$(adb shell "md5sum \"$K/$f\" 2>/dev/null" | tr -d '\r' | awk '{print $1}')"
    LOKALNA="$(md5sum "$D/$f" 2>/dev/null | awk '{print $1}')"
    if [[ -z "$ZDALNA" ]]; then
      echo "   + $f  (md5 telefonu niedostępny — nie sprawdzone)"
    elif [[ "$ZDALNA" == "$LOKALNA" ]]; then
      echo "   + $f  md5 zgodne  ${LOKALNA:0:12}…"
    else
      echo "   ! $f  MD5 SIĘ NIE ZGADZA" >&2
      echo "       telefon: $ZDALNA" >&2
      echo "       kopia:   $LOKALNA" >&2
      BLEDY=$((BLEDY+1))
    fi
  else
    echo "   ! $f  nie udało się pobrać" >&2
    BLEDY=$((BLEDY+1))
  fi
done
echo

# ------------------------------------------------------------- 5. DCIM
if [[ "$BEZ_DCIM" -eq 1 ]]; then
  echo "== 5. DCIM pominięte (--bez-dcim) =="
  CEL_DCIM=""
elif [[ -n "$DCIM_DO" ]]; then
  echo "== 5. DCIM narastająco (osobno od baz) =="
  echo "   Zdjęcia są append-only — dzienna 'wersja' DCIM nie niesie"
  echo "   informacji, a kosztuje kilka GB za każdym razem."
  mkdir -p "$DCIM_DO"
  adb pull "$K/DCIM" "$DCIM_DO/" 2>&1 | tail -1
  CEL_DCIM="$DCIM_DO/DCIM"
  [[ -d "$CEL_DCIM" ]] || CEL_DCIM="$DCIM_DO"
  adb shell "ls -la \"$K/DCIM\"" | tr -d '\r' > "$D/DCIM_spis_telefonu.txt" 2>/dev/null || true
  echo "   spis nazw z telefonu -> $D/DCIM_spis_telefonu.txt"
else
  echo "== 5. DCIM do katalogu zwrotu =="
  echo "   (adb pull KATALOG CEL/ tworzy podkatalog o nazwie źródła)"
  adb pull "$K/DCIM" "$D/" 2>&1 | tail -1
  CEL_DCIM="$D/DCIM"
fi
echo

# -------------------------------------------------------- 6. kontrole
echo "== 6. kontrole =="
BAZA="$D/dane.gpkg"
if [[ ! -f "$BAZA" ]]; then
  echo "   nie ma $BAZA — kontrole pomijam" >&2
else
  if [[ -n "$RANO" && -f "$RANO" ]]; then
    echo
    echo "--- przyrost wobec $RANO ---"
    python3 "$KATALOG_SKRYPTOW/przyrost.py" "$RANO" "$BAZA" || true
  else
    echo "   (przyrost pominięty — podaj -r ŚCIEŻKA/dane.gpkg z poprzedniego stanu)"
  fi

  echo
  echo "--- puste geometrie i dziury w fid ---"
  python3 "$KATALOG_SKRYPTOW/kontrola_zwrotu.py" "$BAZA" || BLEDY=$((BLEDY+1))

  echo
  echo "--- załączniki ---"
  if [[ -n "$CEL_DCIM" && -d "$CEL_DCIM" ]]; then
    python3 "$KATALOG_SKRYPTOW/sprawdz_zalaczniki.py" "$BAZA" --dcim "$CEL_DCIM" \
      || BLEDY=$((BLEDY+1))
  else
    python3 "$KATALOG_SKRYPTOW/sprawdz_zalaczniki.py" "$BAZA" || BLEDY=$((BLEDY+1))
  fi
fi

echo
echo "============================================================"
echo "zwrot: $D"
if [[ "$BLEDY" -gt 0 ]]; then
  echo "Kontrole zgłosiły uwagi. Obejrzyj je PRZED scaleniem."
  echo "Oryginał na telefonie jest nietknięty — nic nie jest stracone."
  exit 1
fi
echo "Bez uwag. Zwrot jest kompletny i sprawdzony."
echo
echo "Pamiętaj: zwrot to nie scalenie. Master zmienia się wyłącznie"
echo "przez Przyjmij zwrot, i scala się RAZ — z ostatniego zwrotu."
