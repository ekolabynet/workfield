#!/bin/bash
# WorkFieldGIS 22.09.2026 - POPRAWKA NUMERU QFIELDA W AKAPICIE O POCHODZENIU.
#
# CO POSZLO ZLE: instaluj_jak_zaczac_3.sh liczyl wersje tak:
#     git describe --tags --abbrev=0 $(git merge-base HEAD upstream/master)
# i wyszlo „v2.0.12". To jest prawdziwy tag QFielda, tylko sprzed lat.
#
# DLACZEGO: `merge-base` daje najstarszego WSPOLNEGO przodka obu galezi.
# Gdyby fork po prostu szedl za upstreamem, ten przodek bylby swiezy. U nas
# historia byla po drodze przestawiana (przeniesienie struktury, scalenie
# 22.08), wiec wspolny przodek siedzi gleboko - a `describe` uczciwie podal
# tag, ktory przy TYM commicie obowiazywal. Narzedzie nie sklamalo; pytanie
# bylo zle postawione.
#
# WLASCIWE PYTANIE: „ktore wydanie QFielda jest w calosci zawarte w naszej
# historii". Odpowiada na nie:
#     git tag --merged HEAD        (tagi, ktorych commity sa naszymi przodkami)
#   przeciete z
#     git tag --merged upstream/master   (tagi upstreamu, nie nasze v0.x)
#   posortowane malejaco po numerze - pierwszy z brzegu.
#
# Skrypt POKAZUJE kandydatow, zanim cokolwiek wpisze, zeby dalo sie
# zobaczyc, na czym opiera sie liczba. Mozna tez podac wprost:
#     bash popraw_wersje_qfielda.sh . v4.3.2
#
# Uruchom w katalogu repo. Idempotentny.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
PLIK="src/app/qml/QfPochodzenie.qml"
echo "== repo: $(pwd)"

[ -f "$PLIK" ] || { echo "STOP: nie ma $PLIK — najpierw instaluj_jak_zaczac_3.sh"; exit 1; }

WERSJA="${2:-}"

if [ -z "$WERSJA" ]; then
  git rev-parse --verify -q upstream/master >/dev/null 2>&1 || {
    echo "STOP: nie ma zdalnego 'upstream'. Albo:"
    echo "  git remote add upstream https://github.com/opengisch/QField.git"
    echo "  git fetch upstream --tags"
    echo "albo podaj numer wprost:  bash $(basename "$0") . v4.3.2"
    exit 1
  }

  UP=$(mktemp); HD=$(mktemp)
  trap 'rm -f "$UP" "$HD"' EXIT
  git tag --merged upstream/master 2>/dev/null | sort > "$UP"
  git tag --merged HEAD --sort=-v:refname 2>/dev/null > "$HD"

  echo "== wydania QFielda zawarte w naszej historii (malejaco):"
  KANDYDACI=$(grep -F -x -f "$UP" "$HD" || true)
  if [ -z "$KANDYDACI" ]; then
    echo "   ZADNE. Historia forka nie zawiera zadnego taga upstreamu —"
    echo "   to znaczy, ze kod byl przenoszony plikami, nie scalany."
    echo "   Podaj numer wprost, np.:  bash $(basename "$0") . v4.3.2"
    echo "   (na czym stoisz, najlepiej widac po dacie ostatniego scalenia)"
    exit 1
  fi
  echo "$KANDYDACI" | head -5 | sed 's/^/   /'
  WERSJA=$(echo "$KANDYDACI" | head -1)

  echo "== dla porownania, ostatnie wydania upstreamu:"
  git tag --merged upstream/master --sort=-v:refname 2>/dev/null | head -3 | sed 's/^/   /'
fi

echo "== wpisuje: $WERSJA"

python3 - "$PLIK" "$WERSJA" <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import re
import sys

plik, wersja = sys.argv[1], sys.argv[2]
tresc = open(plik, encoding='utf-8').read()

wzor = r'property string wersjaQField: "[^"]*"'
if len(re.findall(wzor, tresc)) != 1:
    print('NIC NIE ZAPISANO: w %s jest %d deklaracji wersjaQField (oczekiwano 1)'
          % (plik, len(re.findall(wzor, tresc))))
    sys.exit(1)

stara = re.search(r'property string wersjaQField: "([^"]*)"', tresc).group(1)
if stara == wersja:
    print('  juz jest %s — nic do roboty' % wersja)
    sys.exit(0)

nowa = re.sub(wzor, 'property string wersjaQField: "%s"' % wersja.replace('"', ''), tresc, count=1)
open(plik, 'w', encoding='utf-8').write(nowa)
print('  %s: "%s" -> "%s"' % (plik, stara, wersja))
KONIEC_PY

echo
echo "Sprawdzenie:"
echo "  grep -n 'wersjaQField' $PLIK"
