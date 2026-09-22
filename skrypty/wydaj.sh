#!/bin/bash
# WorkFieldGIS - WYDANIE: nota „Co nowego”, tag i release na GitHubie.
#
# =====================================================================
#  DWA LICZNIKI, NIE JEDEN
# =====================================================================
#
# FIX (trzecia pozycja) to LICZNIK BUILDÓW. Rośnie przy każdym budowaniu,
# bo `scripts/build.sh` woła `scripts/bump.sh` — decyzja z 22.09.2026:
# „przynajmniej wiemy, co i kiedy mamy na stole”. Nie trzeba go podbijać
# ręcznie i nie trzeba o nim myśleć.
#
# MINOR (druga pozycja) to WYDANIE. Przy nim — i tylko przy nim — zmienia
# się nazwa kodowa. Że to wypada mniej więcej co sto buildów, wynika samo:
# po 0.12.99 kolejny build daje 0.13.0.
#
# Stąd ten skrypt zwykle NIE PODAJE numeru. Wydanie to build, który
# postanowiłeś pobłogosławić — numer jest już w `build.sh`, wpisał go tam
# ostatni build, i ten sam numer siedzi w APK, który masz na telefonie.
#
# =====================================================================
#  NAZWA KODOWA
# =====================================================================
#
# Konwencja z 22.08.2026, doprecyzowana 22.09.2026: kolejna litera
# alfabetu, przymiotnik cyfrowy, rzeczownik botaniczny — JEDNA NAZWA NA
# MINOR.
#
#   A  0.9.2   Ancient Ash      (jesion)   } sprzed doprecyzowania:
#   B  0.9.3   Bumpy Birch      (brzoza)   } dwie litery na jeden minor
#   C  0.10.0  Cyber Cedar      (cedr)
#   D  0.11.0  Digital Dogwood  (dereń)
#   E  0.12.0  Electronic Elm   (wiąz)
#   F  0.13.0  ?                — litera F: Fiber Fir (jodła), Fractal Fir,
#                                 Flash Fir, Fluent Fig
#
# Przy wydaniu bez zmiany minor skrypt ODMAWIA zmiany nazwy. Przy zmianie
# minor ODMAWIA wydania bez `--nazwa=`. Nazwy nie zgaduje — to nie jest
# rzecz, którą powinien wymyślić skrypt.
#
# =====================================================================
#  CO NOWEGO W APLIKACJI CZYTA GITHUBA, NIE REPO
# =====================================================================
#
# `qfchangelogcontents.cpp` bierze treść z
# https://api.github.com/repos/ekolabynet/workfield/releases — czyli
# z WYDAŃ NA GITHUBIE. Nota w `docs/wydania/` jest dla nas, treść wydania
# jest dla użytkownika. Oba powstają tu z tego samego materiału.
#
# =====================================================================
#  UŻYCIE
# =====================================================================
#
#   bash skrypty/wydaj.sh
#       -> wydaje numer, który jest w build.sh (czyli ostatni zbudowany):
#          składa notę, POKAZUJE ją i staje
#
#   bash skrypty/wydaj.sh --wykonaj
#       -> to samo + commit, tag, push i wydanie na GitHubie
#
#   bash skrypty/wydaj.sh 0.13.0 --nazwa="Fiber Fir"
#       -> wydanie ze zmianą minor: podbija numer i wpisuje nową nazwę
#
#   bash skrypty/wydaj.sh --od=<sha>       punkt odniesienia dla noty
#   bash skrypty/wydaj.sh /ścieżka/repo
#
# Bez `--wykonaj` nic nie jest wypychane: tag i wydanie to rzeczy,
# których się nie cofa jednym poleceniem, a notę zwykle chce się
# najpierw przeczytać.
set -e

REPO="/DATA/SOFT/GIS/QFIELD_Pro/QField"
NOWA=""
NAZWA=""
ODNIESIENIE=""
WYKONAJ=0
PROGRAM="WorkFieldGIS"

for a in "$@"; do
  case "$a" in
    --wykonaj)  WYKONAJ=1 ;;
    --nazwa=*)  NAZWA="${a#--nazwa=}" ;;
    --od=*)     ODNIESIENIE="${a#--od=}" ;;
    --*)        echo "Nieznany przełącznik: $a"; exit 1 ;;
    [0-9]*.[0-9]*) NOWA="$a" ;;
    *)          REPO="$a" ;;
  esac
done

cd "$REPO"
[ -f scripts/build.sh ] || { echo "STOP: brak scripts/build.sh — to nie jest katalog ${PROGRAM}"; exit 1; }
echo "== repo: $(pwd)"

POPRZEDNIA=$(grep -oP 'APP_VERSION_NUM:-\K[0-9.]+' scripts/build.sh | head -1)
[ -n "$POPRZEDNIA" ] || { echo "STOP: nie umiem odczytać APP_VERSION_NUM"; exit 1; }
NAZWA_TERAZ=$(grep -oP 'APP_CODENAME:-\s*\K[^}\n]+' scripts/build.sh | head -1 | sed 's/[[:space:]]*$//')

# Bez numeru w argumencie wydajemy to, co jest — czyli ostatni build.
[ -n "$NOWA" ] || NOWA="$POPRZEDNIA"

KOD=$(echo "$NOWA" | awk -F. '{print $1*10000 + $2*100 + $3}')
KOD_STARY=$(echo "$POPRZEDNIA" | awk -F. '{print $1*10000 + $2*100 + $3}')
MINOR_STARY=$(echo "$POPRZEDNIA" | cut -d. -f1,2)
MINOR_NOWY=$(echo "$NOWA" | cut -d. -f1,2)

echo "== wersja: ${POPRZEDNIA}${NOWA:+$( [ "$NOWA" != "$POPRZEDNIA" ] && echo " -> ${NOWA}" )}  (kod ${KOD})"
echo "== nazwa kodowa: ${NAZWA_TERAZ}"

if [ "$NOWA" != "$POPRZEDNIA" ] && [ "$KOD" -le "$KOD_STARY" ]; then
  echo
  echo "STOP: ${NOWA} daje versionCode ${KOD}, a w repo jest już ${KOD_STARY}."
  echo "      Android nie zainstaluje wersji o niższym kodzie przez podmianę."
  exit 1
fi

# --- nazwa kodowa: jedna na minor ------------------------------------
if [ "$MINOR_STARY" = "$MINOR_NOWY" ]; then
  if [ -n "$NAZWA" ] && [ "$NAZWA" != "$NAZWA_TERAZ" ]; then
    echo
    echo "STOP: to wydanie nie zmienia minor (${MINOR_NOWY}), więc nazwa kodowa zostaje."
    echo "      Nazwa zmienia się RAZ NA MINOR — „${NAZWA_TERAZ}” obowiązuje do ${MINOR_NOWY}.99."
    echo "      Jeśli to ma być nowe wydanie z nazwą, podaj wyższy minor, np.:"
    echo "        bash skrypty/wydaj.sh $(echo "$MINOR_NOWY" | awk -F. '{print $1"."$2+1".0"}') --nazwa=\"${NAZWA}\""
    exit 1
  fi
  NAZWA=""   # nic do wpisania
else
  if [ -z "$NAZWA" ]; then
    echo
    echo "STOP: wydanie zmienia minor (${MINOR_STARY} -> ${MINOR_NOWY}), a nazwa kodowa zostaje stara."
    echo "      Konwencja: jedna nazwa na minor — kolejna litera, przymiotnik"
    echo "      cyfrowy, rzeczownik botaniczny. Po „${NAZWA_TERAZ}” wypada F:"
    echo "        Fiber Fir (jodła) · Fractal Fir · Flash Fir · Fluent Fig"
    echo "      Podaj wprost:  bash skrypty/wydaj.sh ${NOWA} --nazwa=\"Fiber Fir\""
    exit 1
  fi
fi

NAZWA_DOCELOWA="${NAZWA:-$NAZWA_TERAZ}"
NOTA="docs/wydania/WhatsNew_${NOWA//./-}.md"

# --- punkt odniesienia dla noty --------------------------------------
# Kolejność prób od najpewniejszej: tag poprzedniego wydania, potem commit,
# który wpisał poprzedni numer do build.sh, potem commit dodający jego notę.
# Przy wydawaniu bieżącego numeru „poprzednie” to ostatni TAG, bo numer
# w build.sh jest już ten sam.
if [ -z "$ODNIESIENIE" ]; then
  ODNIESIENIE=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
fi
if [ -z "$ODNIESIENIE" ] && [ "$NOWA" != "$POPRZEDNIA" ]; then
  ODNIESIENIE=$(git log -S"APP_VERSION_NUM:-${POPRZEDNIA}" --format=%H -- scripts/build.sh 2>/dev/null | tail -1)
fi
if [ -z "$ODNIESIENIE" ]; then
  ODNIESIENIE=$(git log --diff-filter=A --format=%H -- 'docs/wydania/WhatsNew_*.md' 2>/dev/null | tail -1)
fi
if [ -z "$ODNIESIENIE" ]; then
  echo "STOP: nie znalazłem punktu odniesienia dla noty."
  echo "      Podaj go sam:  bash skrypty/wydaj.sh --od=<sha>"
  echo "      Podpowiedź:    git log --oneline -- scripts/build.sh | head -20"
  exit 1
fi
echo "== punkt odniesienia: $(git log --format='%h %ad %s' --date=short -1 "$ODNIESIENIE" 2>/dev/null | cut -c1-70)"
echo "== commitów od tamtej pory: $(git rev-list --count "${ODNIESIENIE}..HEAD" 2>/dev/null || echo 0)"

mkdir -p docs/wydania

# --- nota -------------------------------------------------------------
python3 - "$ODNIESIENIE" "$NOWA" "$POPRZEDNIA" "$NOTA" "$PROGRAM" "$NAZWA_DOCELOWA" <<'PYEOF'
# -*- coding: utf-8 -*-
# Nota wydania z gita, pogrupowana po obszarach.
#
# Grupowanie po SLOWACH KLUCZOWYCH w temacie commita, a nie po katalogach:
# jeden commit dotyka zwykle i silnika, i QML-a, i skryptow, wiec podzial
# po plikach rozsypalby go na trzy grupy. Temat commita mowi, CZEGO
# dotyczyl - i to jest to, co czyta uzytkownik.
import subprocess, sys, datetime

od, nowa, poprzednia, nota, program, nazwa = sys.argv[1:7]


def git(*a):
    return subprocess.run(['git'] + list(a), capture_output=True, text=True).stdout


OBSZARY = [
    ('CAD i rysunki DXF', ['cad', 'dxf', 'rysun', 'blok', 'warstwice', 'rzedn', 'rzędn', 'pikiet']),
    ('Inwentaryzacja drzew', ['inwentaryz', 'drzew', 'krzew', 'gatun', 'ods', 'przyrost']),
    ('Podkłady, rastry i georeferencja', ['podklad', 'podkład', 'georefer', 'raster', 'nmt', 'nmpt', 'ortofoto', 'chm', 'probk', 'próbk']),
    ('Moduły i szuflady', ['modul', 'moduł', 'szuflad', 'uklad', 'układ', 'karta', 'zakladk', 'zakładk', 'menu', 'ikon', 'jak zacząć', 'jak zaczac']),
    ('Zdjęcia i załączniki', ['zdjec', 'zdjęc', 'foto', 'zalacz', 'załącz', 'galeri', 'aparat', 'multiodno']),
    ('Dane, kopie i obieg', ['gpkg', 'baza', 'kopia', 'zwrot', 'przyjmij', 'wydani', 'eksport', 'import', 'projekt', 'wyposaz', 'wyposaż']),
    ('Wtyczki', ['wtyczk', 'plugin', 'gugik', 'uldk', 'plantnet', 'konsola']),
]


def obszar(temat):
    t = temat.lower()
    for n, klucze in OBSZARY:
        if any(k in t for k in klucze):
            return n
    return 'Pozostałe'


wiersze = [w for w in git('log', '--format=%h\x1f%ad\x1f%s', '--date=short',
                          od + '..HEAD').splitlines() if w.strip()]
grupy = {}
for w in wiersze:
    czesci = w.split('\x1f')
    if len(czesci) != 3:
        continue
    sha, data, temat = czesci
    grupy.setdefault(obszar(temat), []).append((sha, data, temat))

kolejnosc = [n for n, _ in OBSZARY] + ['Pozostałe']
stan = [w for w in git('status', '--short').splitlines() if w.strip()]
pliki = git('diff', '--stat', od + '..HEAD').splitlines()
podsumowanie = pliki[-1].strip() if pliki else ''

with open(nota, 'w', encoding='utf-8') as f:
    f.write('# %s %s%s\n\n' % (program, nowa, ' „%s”' % nazwa if nazwa else ''))
    f.write('_%s · zmiany od %s_\n\n'
            % (datetime.datetime.now().strftime('%Y-%m-%d'), poprzednia))
    if podsumowanie:
        f.write('%s.\n\n' % podsumowanie)
    f.write('---\n\n')
    for n in kolejnosc:
        if n not in grupy:
            continue
        f.write('## %s\n\n' % n)
        for sha, data, temat in grupy[n]:
            f.write('- %s  ·  `%s`  %s\n' % (temat, sha, data))
        f.write('\n')
    if stan:
        f.write('## Niezłożone w chwili wydania\n\n')
        f.write('Tyle zmian siedziało w drzewie roboczym, gdy powstawało wydanie —\n')
        f.write('warto je złożyć PRZED tagiem, inaczej wydanie ich nie obejmie.\n\n')
        for s in stan[:60]:
            f.write('- `%s`\n' % s.strip())
        if len(stan) > 60:
            f.write('- … i %d więcej\n' % (len(stan) - 60))
        f.write('\n')

print('  %s — %d commitów w %d grupach' % (nota, len(wiersze), len(grupy)))
if stan:
    print('  UWAGA: %d niezłożonych zmian w drzewie roboczym' % len(stan))
PYEOF

# --- numer wersji (tylko przy zmianie minor) --------------------------
if [ "$POPRZEDNIA" != "$NOWA" ]; then
  sed -i "0,/APP_VERSION_NUM:-${POPRZEDNIA}/s//APP_VERSION_NUM:-${NOWA}/" scripts/build.sh
  echo "  scripts/build.sh — ${POPRZEDNIA} → ${NOWA}"
  echo "  UWAGA: następny build podbije to na $(echo "$NOWA" | awk -F. '{print $1"."$2"."$3+1}')."
  echo "         Buduj z BUMP=0, żeby APK niósł dokładnie ${NOWA}:"
  echo "           BUMP=0 triplet=arm64-android ./scripts/build.sh"
fi

# --- nazwa kodowa -----------------------------------------------------
if [ -n "$NAZWA" ]; then
  python3 - "$NAZWA" <<'PYEOF'
import re, sys
nazwa = sys.argv[1]
s = open('scripts/build.sh', encoding='utf-8').read()
# APP_CODENAME bywa zapisane na kilka sposobow. Podmieniam WARTOSC, nie caly
# wiersz - forma zostaje, jaka byla. Kolejnosc wzorcow od najwezszego.
for wzor in (r'APP_CODENAME:-\s*([^}\n]+)',
             r'APP_CODENAME=\s*"([^"\n]*)"',
             r"APP_CODENAME=\s*'([^'\n]*)'"):
    m = re.search(wzor, s)
    if m:
        break
if not m:
    print('  KOTWICA NIE PASUJE: APP_CODENAME w scripts/build.sh')
    sys.exit(1)
if m.group(1).strip() == nazwa:
    print('  scripts/build.sh — nazwa już „%s”' % nazwa)
else:
    print('  scripts/build.sh — nazwa „%s” → „%s”' % (m.group(1).strip(), nazwa))
    s = s[:m.start(1)] + nazwa + s[m.end(1):]
    open('scripts/build.sh', 'w', encoding='utf-8').write(s)
PYEOF
else
  echo "  nazwa kodowa bez zmian („${NAZWA_TERAZ}”) — zmienia się raz na minor"
fi

bash -c 'source <(grep -E "^export APP_|^export APK_" scripts/build.sh); echo "  ${APP_VERSION_STR}   kod ${APK_VERSION_CODE}"'

echo
echo "=============================================================="
sed -n '1,40p' "$NOTA"
echo "  …"
echo "=============================================================="
echo

TYTUL="${PROGRAM} ${NOWA} „${NAZWA_DOCELOWA}”"
[ -n "$NAZWA_DOCELOWA" ] || TYTUL="${PROGRAM} ${NOWA}"

if [ "$WYKONAJ" != "1" ]; then
  cat <<KONIEC
Nota złożona. NIC NIE WYPCHNIĘTE.

Przeczytaj ${NOTA}, popraw co trzeba, a potem albo puść ten skrypt
jeszcze raz z --wykonaj, albo zrób to ręcznie:

  git add -A
  git commit -m "${TYTUL}"
  git tag -a v${NOWA} -m "${TYTUL}"
  git push origin HEAD --tags
  gh release create v${NOWA} --title '${TYTUL}' --notes-file "${NOTA}"

Ostatnia linijka jest tą, która robi „Co nowego” W APLIKACJI —
okno czyta wydania z GitHuba, nie z repozytorium.
KONIEC
  exit 0
fi

echo "== składam, taguję i wydaję"
git add -A
git commit -q -m "${TYTUL}

Wydanie zbiorcze zmian od ${POPRZEDNIA}. Nota: ${NOTA}

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VeWM6rJN6RyoQt3umLcoDc" || echo "  (nie było co składać)"

git tag -a "v${NOWA}" -m "${TYTUL}" 2>/dev/null || echo "  (tag v${NOWA} już jest)"
git push origin HEAD --tags

if command -v gh >/dev/null; then
  gh release create "v${NOWA}" --title "${TYTUL}" --notes-file "$NOTA" \
    || gh release edit "v${NOWA}" --title "${TYTUL}" --notes-file "$NOTA"
  echo
  echo "Gotowe. Sprawdź, czy aplikacja to zobaczy:"
  echo "  curl -s https://api.github.com/repos/ekolabynet/workfield/releases | head -20"
else
  echo
  echo "BRAK gh — wydanie trzeba założyć ręcznie:"
  echo "  https://github.com/ekolabynet/workfield/releases/new?tag=v${NOWA}"
  echo "  treść: $NOTA"
fi

echo
echo "APK tego wydania doczepisz tak:"
echo "  bash skrypty/przygotuj_apk.sh --wyslij"
