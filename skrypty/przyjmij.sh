#!/usr/bin/env bash
# Przyjmij zwrot z PACZKI — bez adb, bez telefonu, bez znaczenia jakim kanałem
# paczka przyjechała.
#
# Bierze to, co zostawiła aplikacja („Wymiana lokalna" → „wyślij jako spakowaną
# paczkę"), i robi z tym wszystko, co robi `zwrot.sh`, minus transport:
#
#   1. sprawdza, CZY PACZKA JEST ZAPIECZĘTOWANA (patrz niżej — to jest sedno)
#   2. weryfikuje md5, jeśli paczka je niesie
#   3. rozpakowuje do katalogu datowanego (nigdy nie nadpisuje)
#   4. odpala kontrole: przyrost, puste geometrie, załączniki
#
# Kanał jest obojętny: kabel USB (telefon jako dysk MTP), karta w czytniku,
# NextCloud, katalog wymiany — po zapieczętowaniu paczka to plik martwy,
# a nie żywa baza.
#
# Użycie:
#   ./przyjmij.sh paczka.zip
#   ./przyjmij.sh paczka.zip -e pgrs_v9_0 -r ~/WorkField_zwroty/2026-08-21_pgrs_v8_0/dane.gpkg
#   ./przyjmij.sh /run/user/1000/gvfs/mtp:host=*/Documents/WorkField/paczka.zip
#   ./przyjmij.sh KATALOG_JUZ_ROZPAKOWANY/
#
# ------------------------------------------------------------------------
# O CO CHODZI Z `-wal`
#
# Niebezpieczna jest paczka, w której jest sam `.gpkg`, a dziennik `-wal`
# został na telefonie: zapisy z dziennika przepadają, a plik po drugiej
# stronie OTWIERA SIĘ I KŁAMIE — awaria bez objawu.
#
# Paczka z `.gpkg` RAZEM z `-wal` i `-shm` jest bezpieczniejsza, nie gorsza:
# dziennik pojechał z bazą i SQLite odtworzy go przy otwarciu. Skrypt mówi,
# z którym przypadkiem masz do czynienia, i nie zgaduje.
#
# Najlepszy przypadek: sam `.gpkg`, bo baza była domknięta przed pakowaniem.
# Żeby go dostać, ZAMKNIJ PROJEKT W APLIKACJI (wróć do listy projektów)
# przed „wyślij jako spakowaną paczkę". To jest czyste zamknięcie przez samą
# aplikację — nie to samo co zabicie procesu przez `am force-stop`.
# ------------------------------------------------------------------------

set -u
set -o pipefail

KORZEN_ZWROTOW="${WF_ZWROTY:-$HOME/WorkField_zwroty}"
KATALOG_SKRYPTOW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ZRODLO=""
ETYKIETA=""
RANO=""

uzycie() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--etykieta) ETYKIETA="${2:-}"; shift 2 ;;
    -r|--rano)     RANO="${2:-}"; shift 2 ;;
    -h|--help)     uzycie 0 ;;
    -*)            echo "nieznany argument: $1" >&2; uzycie 2 ;;
    *)             ZRODLO="$1"; shift ;;
  esac
done

[[ -n "$ZRODLO" ]] || { echo "podaj paczkę .zip albo katalog" >&2; uzycie 2; }
[[ -e "$ZRODLO" ]] || { echo "nie ma: $ZRODLO" >&2; exit 1; }

if [[ -z "$ETYKIETA" ]]; then
  ETYKIETA="$(basename "$ZRODLO")"
  ETYKIETA="${ETYKIETA%.zip}"
  ETYKIETA="$(echo "$ETYKIETA" | tr -c 'A-Za-z0-9_.-' '_' | sed 's/_\{2,\}/_/g; s/^_//; s/_$//')"
fi

D="$KORZEN_ZWROTOW/$(date +%Y-%m-%d)_$ETYKIETA"
BLEDY=0

echo "źródło: $ZRODLO"
echo "zwrot:  $D"
echo

# ---------------------------------------------- 1. czy paczka zapieczętowana
echo "== 1. czy paczka jest zapieczętowana =="
if [[ -f "$ZRODLO" ]]; then
  command -v unzip >/dev/null || { echo "!! nie ma unzip w PATH" >&2; exit 1; }
  unzip -tq "$ZRODLO" >/dev/null 2>&1 || {
    echo "!! archiwum jest uszkodzone — przerywam." >&2
    echo "   Skopiuj paczkę jeszcze raz; oryginał na telefonie jest nietknięty." >&2
    exit 1
  }
  SPIS="$(unzip -Z1 "$ZRODLO")"
else
  SPIS="$(cd "$ZRODLO" && find . -type f | sed 's|^\./||')"
fi

MA_GPKG="$(echo "$SPIS" | grep -c '\.gpkg$' || true)"
MA_WAL="$(echo "$SPIS"  | grep -c '\.gpkg-wal$' || true)"
MA_SHM="$(echo "$SPIS"  | grep -c '\.gpkg-shm$' || true)"

echo "   baz .gpkg: $MA_GPKG,  plików -wal: $MA_WAL,  -shm: $MA_SHM"
if [[ "$MA_GPKG" -eq 0 ]]; then
  echo "!! w paczce nie ma ani jednego .gpkg — to nie jest zwrot." >&2
  exit 1
elif [[ "$MA_WAL" -gt 0 ]]; then
  echo "   UWAGA: dziennik -wal jest w paczce."
  echo "   To NIE jest strata — dziennik pojechał z bazą i SQLite go odtworzy."
  echo "   Znaczy tylko, że projekt był otwarty przy pakowaniu."
  echo "   Następnym razem zamknij projekt w aplikacji przed wysyłką."
else
  echo "   Sam .gpkg, bez dziennika — baza była domknięta. Tak ma być."
fi
echo

# ------------------------------------------------------------ 2. suma md5
echo "== 2. suma kontrolna =="
MD5_OBOK=""
for k in "$ZRODLO.md5" "${ZRODLO%.zip}.md5"; do
  [[ -f "$k" ]] && MD5_OBOK="$k" && break
done
if [[ -n "$MD5_OBOK" ]]; then
  OCZEKIWANA="$(awk '{print $1}' "$MD5_OBOK" | head -1)"
  POLICZONA="$(md5sum "$ZRODLO" | awk '{print $1}')"
  if [[ "$OCZEKIWANA" == "$POLICZONA" ]]; then
    echo "   md5 zgodne z $(basename "$MD5_OBOK"):  ${POLICZONA:0:12}…"
  else
    echo "!! MD5 SIĘ NIE ZGADZA — paczka dojechała uszkodzona." >&2
    echo "   w pliku:  $OCZEKIWANA" >&2
    echo "   policzone: $POLICZONA" >&2
    echo "   Skopiuj jeszcze raz. Nie scalaj tego." >&2
    exit 1
  fi
elif [[ -f "$ZRODLO" ]]; then
  echo "   Paczka nie niesie sumy md5 (aplikacja jeszcze jej nie dokłada)."
  echo "   Liczę własną i zapiszę obok kopii — do porównania przy następnym razem."
else
  echo "   (katalog, nie paczka — sumy nie ma czego sprawdzać)"
fi
echo

# ------------------------------------------------- 3. katalog datowany
echo "== 3. katalog datowany =="
if [[ -e "$D" ]]; then
  echo "!! $D już istnieje. Nie nadpisuję." >&2
  echo "   Dodaj etykietę: -e ${ETYKIETA}_popoludnie" >&2
  exit 1
fi
mkdir -p "$D" || exit 1
if [[ -f "$ZRODLO" ]]; then
  unzip -q "$ZRODLO" -d "$D" || { echo "!! nie udało się rozpakować" >&2; exit 1; }
  md5sum "$ZRODLO" > "$D/PACZKA.md5"
  echo "   rozpakowane; suma paczki w $D/PACZKA.md5"
else
  cp -a "$ZRODLO/." "$D/" || { echo "!! nie udało się skopiować" >&2; exit 1; }
  echo "   skopiowane"
fi
echo "   $D"
echo

# ------------------------------------------------------------ 4. kontrole
BAZA="$(find "$D" -maxdepth 3 -name 'dane.gpkg' -o -maxdepth 3 -name 'data.gpkg' | head -1)"
KAT_DCIM="$(find "$D" -maxdepth 3 -type d -name DCIM | head -1)"

# Trzecia kategoria plików (decyzja z 24.08): BAZY NARZĘDZIOWE.
# Struktura odtwarzalna, treść NIEODTWARZALNA — tagi zdjęć i punkty KTW to
# praca merytoryczna, której nikt nie odtworzy, choć nie należy do zlecenia.
# Docelowe nazwy `tool_*` wchodzą razem ze `zrzucPrzepis()`; dziś to jeszcze
# `tyczenie.gpkg` i `foto_tagi.gpkg`, więc rozpoznajemy oba nazewnictwa.
# Podkłady (`support`, `wf_wskazniki`, `gugik`) są odtwarzalne — pomijamy.
NARZEDZIOWE=()
while IFS= read -r p; do
  [[ -n "$p" ]] && NARZEDZIOWE+=("$p")
done < <(find "$D" -maxdepth 3 -name 'tool_*.gpkg' -o -maxdepth 3 -name 'tyczenie.gpkg' \
                -o -maxdepth 3 -name 'foto_tagi.gpkg' | sort)

echo "== 4. kontrole =="
echo "   baza zlecenia:    ${BAZA:-nie znaleziono}"
echo "   bazy narzędziowe: ${NARZEDZIOWE[*]:-brak w paczce}"
echo "   DCIM:             ${KAT_DCIM:-nie ma w paczce}"
echo

if [[ -z "$BAZA" ]]; then
  echo "!! nie znalazłem bazy zlecenia w rozpakowanej paczce — kontrole pomijam" >&2
  exit 1
fi

if [[ -n "$RANO" && -f "$RANO" ]]; then
  echo "--- przyrost wobec $RANO ---"
  python3 "$KATALOG_SKRYPTOW/przyrost.py" "$RANO" "$BAZA" \
    ${KAT_DCIM:+--dcim "$(dirname "$RANO")/DCIM" "$KAT_DCIM"} || true
  echo
else
  echo "   (przyrost pominięty — podaj -r ŚCIEŻKA/dane.gpkg z poprzedniego zwrotu)"
  echo
fi

echo "--- puste geometrie i dziury w fid ---"
python3 "$KATALOG_SKRYPTOW/kontrola_zwrotu.py" "$BAZA" || BLEDY=$((BLEDY+1))
for tb in "${NARZEDZIOWE[@]:-}"; do
  [[ -n "$tb" ]] || continue
  echo
  echo "    (baza narzędziowa: $(basename "$tb"))"
  python3 "$KATALOG_SKRYPTOW/kontrola_zwrotu.py" "$tb" || BLEDY=$((BLEDY+1))
done
echo

echo "--- załączniki ---"
if [[ -n "$KAT_DCIM" ]]; then
  python3 "$KATALOG_SKRYPTOW/sprawdz_zalaczniki.py" "$BAZA" --dcim "$KAT_DCIM" \
    || BLEDY=$((BLEDY+1))
else
  python3 "$KATALOG_SKRYPTOW/sprawdz_zalaczniki.py" "$BAZA" || BLEDY=$((BLEDY+1))
fi

echo
echo "============================================================"
echo "zwrot: $D"
if [[ "$BLEDY" -gt 0 ]]; then
  echo "Kontrole zgłosiły uwagi. Obejrzyj je PRZED scaleniem."
  exit 1
fi
echo "Bez uwag. Zwrot jest kompletny i sprawdzony."
echo
echo "Zwrot to nie scalenie. Scala się RAZ, z ostatniego zwrotu."
