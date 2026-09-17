#!/bin/bash
# Wydanie wtyczki: nota, paczka, QR — jednym poleceniem.
#
# PO CO. Do 17.09.2026 wydanie wtyczki to bylo: spakuj, wrzuc na galaz,
# poczekaj, sprawdz curl-em, wygeneruj QR, a note napisz z pamieci albo
# wcale. Piec krokow, z ktorych dwa ostatnie zawsze wypadaly.
#
# Nota powstaje Z GITA — z commitow dotyczacych tej wtyczki — a nie
# z pamieci. Pusty szkielet bylby gorszy od braku noty: udawalby, ze
# cos dokumentuje.
#
#   ./wydaj_wtyczke.sh gugik 0.3 /tmp/gugik
#
set -e

NAZWA="$1"          # gugik | konsola | plantnet | zrobione
WERSJA="$2"
ZRODLO="${3:-/tmp/$NAZWA}"
REPO="${REPO:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
PLIK="workfield-${NAZWA}-v${WERSJA}.zip"
ADRES="https://raw.githubusercontent.com/ekolabynet/workfield/plugins/${PLIK}"

[ -z "$NAZWA" ] || [ -z "$WERSJA" ] && {
  echo "uzycie: $0 <nazwa> <wersja> [katalog-zrodla]"; exit 1; }
[ -d "$ZRODLO" ] || { echo "STOP: nie ma katalogu $ZRODLO"; exit 1; }

# --- paczka ----------------------------------------------------------
cd "$ZRODLO"
rm -f ~/Pobrane/"$PLIK"
zip -q ~/Pobrane/"$PLIK" metadata.txt main.qml icon.svg
echo "paczka: ~/Pobrane/$PLIK  ($(stat -c%s ~/Pobrane/"$PLIK") B)"

# --- nota ------------------------------------------------------------
cd "$REPO"
mkdir -p docs/wtyczki
NOTA="docs/wtyczki/WhatsNew_${NAZWA}_${WERSJA//./-}.md"
{
  echo "# ${NAZWA} v${WERSJA}"
  echo
  echo "_$(date '+%Y-%m-%d %H:%M')_"
  echo
  echo "Instalacja: **Ustawienia → Wtyczki → Install plugin from URL**"
  echo
  echo '```'
  echo "$ADRES"
  echo '```'
  echo
  echo "## Co się zmieniło"
  echo
  git log --format='- %s' -8 --grep="$NAZWA" -i 2>/dev/null || true
  echo
  echo "## Do sprawdzenia po instalacji"
  echo
  echo "- "
} > "$NOTA"
echo "nota:   $NOTA"

# --- QR --------------------------------------------------------------
python3 - "$ADRES" "$REPO/docs/wtyczki/qr_${NAZWA}_${WERSJA//./-}.png" <<'PY'
import sys
try:
    import qrcode
except ImportError:
    sys.exit("QR pominiety — pip install qrcode pillow --break-system-packages")
q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,
                  box_size=12, border=4)
q.add_data(sys.argv[1]); q.make(fit=True)
q.make_image(fill_color="black", back_color="white").save(sys.argv[2])
print("QR:     " + sys.argv[2])
PY

echo
echo "Teraz: wrzuc paczke na galaz plugins, potem sprawdz adres."
