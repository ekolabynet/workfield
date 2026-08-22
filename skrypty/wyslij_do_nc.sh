#!/usr/bin/env bash
# wyslij_do_nc.sh — publikacja migawek na NextCloud (kanał prywatny).
#
# Realizuje zasadę z claude/DANE_workflow.md: NextCloud wozi ZAPIECZĘTOWANE
# migawki, nie żywe pliki. Wysyłka jest jednokierunkowa (w górę), nazwa niesie
# datę, nic nie jest nadpisywane, a obok pliku ląduje suma kontrolna.
#
# Wymaga rclone ze skonfigurowanym zdalnym WebDAV — patrz taxonomy/docs/
# ZACZEPY_w_repo.md albo `rclone config`. Nazwa zdalnego w zmiennej WF_NC_REMOTE.
#
#   export WF_NC_REMOTE=nc            # nazwa z rclone config
#   bash skrypty/wyslij_do_nc.sh wf_wskazniki.gpkg
#   bash skrypty/wyslij_do_nc.sh --sucho --katalog slowniki *.gpkg
#
# Bezpiecznik, którego nie wolno wyłączać: skrypt ODMAWIA wysłania GPKG,
# obok którego leży `-wal` albo `-shm`. To znaczy, że ktoś ma bazę otwartą —
# wysłany plik otworzyłby się po drugiej stronie i SKŁAMAŁ (lekcja z 21.08:
# dwa pliki o identycznym rozmiarze i różnej treści).

set -euo pipefail

REMOTE="${WF_NC_REMOTE:-nc}"
KATALOG="WF_nc_data"
SUCHO=0
PLIKI=()

while [ $# -gt 0 ]; do
  case "$1" in
    --sucho)   SUCHO=1; shift ;;
    --katalog) KATALOG="$2"; shift 2 ;;
    --remote)  REMOTE="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *)         PLIKI+=("$1"); shift ;;
  esac
done

if [ ${#PLIKI[@]} -eq 0 ]; then
  echo "Podaj pliki do wysłania. -h pokaże przykłady." >&2
  exit 1
fi

command -v rclone >/dev/null 2>&1 || {
  echo "Nie ma rclone. Instalacja: sudo apt install rclone" >&2
  echo "Konfiguracja zdalnego: rclone config  (typ: webdav, vendor: nextcloud)" >&2
  exit 1
}

rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:" || {
  echo "Nie ma zdalnego '${REMOTE}:' w konfiguracji rclone." >&2
  echo "Dostępne: $(rclone listremotes 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
}

DZIS=$(date +%F_%H%M)
BLEDY=0

for f in "${PLIKI[@]}"; do
  if [ ! -f "$f" ]; then
    echo "POMINIĘTE (nie ma pliku): $f" >&2; BLEDY=1; continue
  fi

  # bezpiecznik: otwarta baza
  case "$f" in
    *.gpkg|*.sqlite|*.db)
      if [ -e "${f}-wal" ] || [ -e "${f}-shm" ]; then
        echo "ODMOWA: obok $f leży -wal/-shm — ktoś ma bazę otwartą." >&2
        echo "        Zamknij QGIS/aplikację i powtórz." >&2
        BLEDY=1; continue
      fi ;;
  esac

  baza=$(basename "$f")
  trzon="${baza%.*}"; rozsz="${baza##*.}"
  [ "$trzon" = "$baza" ] && cel="${baza}_${DZIS}" || cel="${trzon}_${DZIS}.${rozsz}"
  suma=$(md5sum "$f" | cut -d' ' -f1)

  if rclone lsf "${REMOTE}:${KATALOG}/${cel}" >/dev/null 2>&1; then
    echo "POMINIĘTE (już jest): ${KATALOG}/${cel}"; continue
  fi

  rozmiar=$(du -h "$f" | cut -f1)
  echo "→ ${KATALOG}/${cel}  (${rozmiar}, md5 ${suma:0:8}…)"
  if [ "$SUCHO" -eq 1 ]; then continue; fi

  rclone copyto "$f" "${REMOTE}:${KATALOG}/${cel}" --progress
  printf '%s  %s\n' "$suma" "$cel" | \
    rclone rcat "${REMOTE}:${KATALOG}/${cel}.md5"
done

[ "$SUCHO" -eq 1 ] && echo "SUCHA PRÓBA — nic nie wysłano."
exit $BLEDY
