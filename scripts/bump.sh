#!/bin/bash
# WorkField — podbicie numeru buildu przed kazdym budowaniem.
#
# Trzecia pozycja numeru JEST licznikiem buildow: 0.11.50 -> 0.11.51.
# `versionCode` liczy sie z niej sama (major*10000 + minor*100 + patch),
# wiec rosnie bez osobnego pilnowania — a musi rosnac, bo inaczej Android
# widzi te sama wersje i `install -r` zachowuje sie nieprzewidywalnie.
#
# Po 0.11.99 kolejny build da 0.12.0. Kod rosnie, ale numer wyglada jak
# wydanie, ktorym nie jest. Sto buildow to okolo dwoch tygodni.
set -e
cd "$(dirname "$0")/.."
N=$(grep -oP 'APP_VERSION_NUM:-\d+\.\d+\.\K\d+' scripts/build.sh)
[ -z "$N" ] && { echo "STOP: nie znalazlem trzeciej pozycji numeru"; exit 1; }
sed -i "0,/\(APP_VERSION_NUM:-[0-9]\+\.[0-9]\+\.\)$N/s//\1$((N + 1))/" scripts/build.sh
NUM=$(grep -oP 'APP_VERSION_NUM:-\K[0-9.]+' scripts/build.sh)
NOTA="docs/wydania/WhatsNew_${NUM//./-}.md"
# Katalog zaklada sie sam: `git rm` ostatniej noty kasuje go razem
# z plikami, a wtedy bump pada na przekierowaniu.
mkdir -p docs/wydania

# Notatka POWSTAJE SAMA, bo o notatce pisanej osobno zawsze sie zapomina.
# Pusty szkielet jest sygnalem: jesli zostanie niewypelniony, widac to
# w repo od razu.
# Nota tylko NA ZADANIE. Przy dwudziestu buildach dziennie repo zapelnia
# sie plikami, z ktorych kazdy opisuje jedno przekompilowanie — a opis
# ma sens przy WYDANIU, nie przy kazdej probie.
#
#     NOTA=1 ./scripts/bump.sh
if [ -n "${NOTA_WYDANIA}" ] && [ ! -f "$NOTA" ]; then
  # Nota WYPELNIA SIE SAMA tym, co juz zapisane: commity od poprzedniego
  # bumpa i pliki tkniete od tamtej pory. Pusty szkielet bylby gorszy od
  # braku noty — udawalby, ze cos dokumentuje.
  # Punkt odniesienia trzymamy w PLIKU, nie zgadujemy po tresci commitow:
  # `--grep` nic nie znajdowal (nasze commity nie zaczynaja sie od
  # "WorkField"), wiec nota brala dwadziescia commitow wstecz i opisywala
  # tydzien zamiast jednego builda.
  ZNACZNIK="docs/wydania/.ostatni_bump"
  POPRZ=$(cat "$ZNACZNIK" 2>/dev/null)
  git cat-file -e "$POPRZ" 2>/dev/null || POPRZ=$(git log --format=%H -3 2>/dev/null | tail -1)
  {
    echo "# WorkField $NUM"
    echo
    echo "_$(date '+%Y-%m-%d %H:%M')_"
    echo
    echo "## Commity"
    echo
    git log --format='- %s' "${POPRZ}..HEAD" 2>/dev/null | head -20
    echo
    echo "## Niezłożone zmiany w chwili budowania"
    echo
    git status --short 2>/dev/null | sed 's/^/- /' | head -20
    echo
    echo "## Do sprawdzenia po instalacji"
    echo
    echo "- "
  } > "$NOTA"
  git rev-parse HEAD > "$ZNACZNIK" 2>/dev/null
  echo "  nota: $NOTA  (DO WYPELNIENIA)"
elif [ -f "$NOTA" ]; then
  echo "  nota: $NOTA  (juz jest)"
fi

bash -c 'source <(sed -n "1,20p" scripts/build.sh); echo "  $APP_VERSION_STR   kod $APK_VERSION_CODE"'
