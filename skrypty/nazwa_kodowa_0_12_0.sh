#!/bin/bash
# WorkField 21.09.2026 - NAZWA KODOWA 0.12.0: „Electronic Elm".
#
# Konwencja z 22.08.2026 (claude/SCALENIE_2026-08-22.md): kolejna litera
# alfabetu, przymiotnik cyfrowy, rzeczownik botaniczny.
#
#   A  0.9.2   Ancient Ash        (jesion)
#   B  0.9.3   Bumpy Birch        (brzoza)
#   C  0.10.0  Cyber Cedar        (cedr)
#   D  0.11.0  Digital Dogwood    (dereń)
#   E  0.12.0  Electronic Elm     (wiąz)   <- to wydanie
#
# Wiąz jest z tych drzew, które pamięta się z inwentaryzacji: twardy,
# długowieczny, a od holenderskiej choroby wiązów rzadki na tyle, że przy
# każdym robi się notatkę. Pasuje do wydania, które jest w dużej części
# o CAD-zie i o tym, żeby dane z terenu dało się komuś przekazać.
#
# Gdyby jednak ta nazwa miała nie pasować, litera E daje jeszcze:
#   Electric Elder (bez czarny) · Elastic Elm · Encrypted Elder
# Podmień NAZWA= niżej i uruchom to samo.
#
# CO RUSZA:
#   1. scripts/build.sh          - APP_CODENAME (źródło napisu w „O programie")
#   2. docs/wydania/WhatsNew_0-12-0.md - nagłówek noty
#   3. tytuł wydania na GitHubie - bo to ono jest „What's new" w aplikacji
#
# CZEGO NIE RUSZA: taga v0.12.0. Tag jest już wypchnięty, a przesuwanie
# wypchniętego taga to jedna z tych rzeczy, po których ludziom psują się
# klony. Nazwa mieszka w tytule wydania i w APK — to wystarczy.
#
# UWAGA: żeby nazwa pojawiła się W APLIKACJI, trzeba APK zbudować PONOWNIE.
# Ten, który leży zbudowany teraz, ma w środku starą nazwę.
#
#   bash nazwa_kodowa_0_12_0.sh [katalog repo]              - pokaż, co zrobi
#   bash nazwa_kodowa_0_12_0.sh [katalog repo] --wykonaj    - zapisz i wypchnij
set -e

REPO="/DATA/SOFT/GIS/QFIELD_Pro/QField"
WYKONAJ=0
NAZWA="Electronic Elm"
for a in "$@"; do
  case "$a" in
    --wykonaj)  WYKONAJ=1 ;;
    --nazwa=*)  NAZWA="${a#--nazwa=}" ;;
    --*)        echo "Nieznany przełącznik: $a"; exit 1 ;;
    *)          REPO="$a" ;;
  esac
done

cd "$REPO"
[ -f scripts/build.sh ] || { echo "STOP: brak scripts/build.sh"; exit 1; }
WERSJA=$(grep -oP 'APP_VERSION_NUM:-\K[0-9.]+' scripts/build.sh | head -1)
NOTA="docs/wydania/WhatsNew_${WERSJA//./-}.md"

echo "== repo:   $(pwd)"
echo "== wersja: ${WERSJA}"
echo "== nazwa:  ${NAZWA}"
echo

STARA=$(grep -n 'APP_CODENAME' scripts/build.sh | head -3)
if [ -z "$STARA" ]; then
  echo "STOP: nie widzę APP_CODENAME w scripts/build.sh — sprawdź, jak tam teraz"
  echo "      jest zapisana nazwa:  grep -n CODENAME scripts/build.sh"
  exit 1
fi
echo "-- teraz w build.sh:"
echo "$STARA" | sed 's/^/   /'
echo

if [ "$WYKONAJ" != "1" ]; then
  cat <<KONIEC
NIC NIE ZMIENIONE. Z --wykonaj zrobię:

  1. scripts/build.sh          APP_CODENAME -> "${NAZWA}"
  2. ${NOTA}   nagłówek -> # WorkField ${WERSJA} „${NAZWA}"
  3. git commit + push
  4. gh release edit v${WERSJA} --title 'WorkField ${WERSJA} „${NAZWA}"'
     (to jest ten napis, który widać w oknie „Co nowego" w aplikacji)

Potem APK trzeba zbudować od nowa — nazwa siedzi w binarce.
KONIEC
  exit 0
fi

# --- 1. build.sh ------------------------------------------------------
python3 - "$NAZWA" <<'PYEOF'
import re, sys
nazwa = sys.argv[1]
s = open('scripts/build.sh', encoding='utf-8').read()
# APP_CODENAME bywa zapisane na kilka sposobow. Podmieniam WARTOSC, nie caly
# wiersz - forma zostaje, jaka byla. Kolejnosc wzorcow od najwezszego:
# w srodku ${...:-...}, w cudzyslowie, goly wyraz.
for wzor in (r'APP_CODENAME:-\s*([^}\n]+)',
             r'APP_CODENAME=\s*"([^"\n]*)"',
             r"APP_CODENAME=\s*'([^'\n]*)'"):
    m = re.search(wzor, s)
    if m:
        break
if not m:
    print('KOTWICA NIE PASUJE: APP_CODENAME w scripts/build.sh')
    sys.exit(1)
if m.group(1).strip() == nazwa:
    print('  scripts/build.sh - juz "%s"' % nazwa)
else:
    print('  scripts/build.sh - "%s" -> "%s"' % (m.group(1).strip(), nazwa))
    s = s[:m.start(1)] + nazwa + s[m.end(1):]
    open('scripts/build.sh', 'w', encoding='utf-8').write(s)
PYEOF

# --- 2. nagłówek noty -------------------------------------------------
if [ -f "$NOTA" ]; then
  if head -1 "$NOTA" | grep -q "$NAZWA"; then
    echo "  ${NOTA} - nagłówek już z nazwą"
  else
    sed -i "1s|.*|# WorkField ${WERSJA} „${NAZWA}”|" "$NOTA"
    echo "  ${NOTA} - nagłówek OK"
  fi
else
  echo "  UWAGA: nie ma ${NOTA}"
fi

# --- 3. commit i wydanie ---------------------------------------------
if [ -n "$(git status --short scripts/build.sh "$NOTA" 2>/dev/null)" ]; then
  git add scripts/build.sh "$NOTA" 2>/dev/null || git add scripts/build.sh
  git commit -q -m "WorkField ${WERSJA} — nazwa kodowa „${NAZWA}”

Litera E w konwencji z 22.08.2026: przymiotnik cyfrowy + rzeczownik
botaniczny (A: Ancient Ash, B: Bumpy Birch, C: Cyber Cedar,
D: Digital Dogwood).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VeWM6rJN6RyoQt3umLcoDc"
  git push
  echo "  commit + push OK"
else
  echo "  (nie było co składać)"
fi

if command -v gh >/dev/null; then
  if [ -f "$NOTA" ]; then
    gh release edit "v${WERSJA}" --title "WorkField ${WERSJA} „${NAZWA}”" --notes-file "$NOTA"
  else
    gh release edit "v${WERSJA}" --title "WorkField ${WERSJA} „${NAZWA}”"
  fi
  echo "  wydanie OK: https://github.com/ekolabynet/workfield/releases/tag/v${WERSJA}"
else
  echo "  BRAK gh — tytuł wydania zmień ręcznie:"
  echo "  https://github.com/ekolabynet/workfield/releases/edit/v${WERSJA}"
fi

echo
echo "Zostało: zbudować APK od nowa, żeby nazwa weszła do binarki."
echo "  triplet=arm64-android ./scripts/build.sh && bash przygotuj_apk.sh"
