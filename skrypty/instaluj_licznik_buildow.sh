#!/bin/bash
# WorkFieldGIS 22.09.2026 - LICZNIK BUILDOW I WYDANIA.
#
# DWIE DECYZJE PIOTRA Z 22.09.2026
# --------------------------------
#   1. FIX rosnie PRZY KAZDYM BUILDZIE — „przynajmniej wiemy, co i kiedy
#      mamy na stole”. Pierwszy build po tej latce da 0.12.1.
#   2. NAZWA KODOWA zmienia sie RAZ NA MINOR (0.11 -> 0.12), a nie przy
#      kazdym wydaniu. „Mozemy spokojnie robic 100 buildow na jedno
#      wydanie kodowe” — i to sie sklada samo, bo po 0.12.99 kolejny
#      build daje 0.13.0.
#
# CO WCHODZI
# ----------
#   scripts/build.sh          - wola bump.sh i PRZELADOWUJE sie (exec)
#   scripts/bump.sh           - odporne wczytanie naglowka build.sh
#   skrypty/wydaj.sh          - NOWY: wydanie biezacego numeru albo minor
#   skrypty/przygotuj_apk.sh  - nazwa pliku APK: WorkFieldGIS
#   skrypty/wydaj_0_12_0.sh   - ta sama poprawka wczytania (jesli jest)
#
# DLACZEGO `exec`, A NIE SAMO WOLANIE bump.sh
# -------------------------------------------
# Numer jest LITERALEM w `build.sh`, a `bump.sh` podmienia go przez
# `sed -i`, czyli przez ZMIANE NAZWY PLIKU. Dzialajacy bash trzyma otwarty
# stary plik i czyta z niego dalej — wzialby numer SPRZED podbicia.
# Wyszedlby APK z numerem N przy `build.sh` mowiacym N+1, a
# `przygotuj_apk.sh` sluszne by na to nakrzyczal. `exec` uruchamia plik
# od nowa, juz z dysku.
#
# PULAPKA ZLAPANA PROBA
# ---------------------
# `bump.sh` konczy sie `source <(sed -n "1,20p" scripts/build.sh)`, zeby
# pokazac nowy numer. Moj blok wstawia wiersze PRZED eksportami, wiec
# wypchnalby je poza okno 20 wierszy — a przy wczytaniu przez `source`
# `BASH_SOURCE` wskazuje `/dev/fd/NN` i blok probowal wolac bump.sh ze
# sciezki `/dev/fd/../scripts/bump.sh`. Stad DWA zabezpieczenia:
#   - blok dziala tylko gdy `BASH_SOURCE = $0`, czyli przy URUCHOMIENIU,
#   - wczytanie naglowka idzie `grep -E "^export APP_"`, nie po wierszach.
#
# PRZEBUDOWA BEZ PODBICIA: `BUMP=0 triplet=arm64-android ./scripts/build.sh`
#
# Uruchom w katalogu repo. Idempotentny; sprawdza kotwice przed zapisem.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64
import os
import sys
import zlib

NOWE = {}

NOWE['skrypty/wydaj.sh'] = """\
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
7jHHvtcrWf8HsDEWeA=="""


HAK = '''
# --- NUMER BUILDU ROSNIE PRZY KAZDYM BUILDZIE ------------------------
# Decyzja Piotra 22.09.2026: „jestem za bumpowaniem fix przy buildach,
# przynajmniej wiemy, co i kiedy mamy na stole”. Trzecia pozycja numeru
# jest licznikiem buildow; `versionCode` liczy sie z niej sam, wiec rosnie
# bez pilnowania — a musi rosnac, bo inaczej Android widzi te sama wersje
# i `install -r` zachowuje sie nieprzewidywalnie.
#
# WARUNEK `BASH_SOURCE = $0` znaczy: TYLKO gdy ten plik jest URUCHAMIANY.
# Przy `source <(...)` — a tak czyta ten naglowek `bump.sh` i skrypt
# wydania — BASH_SOURCE wskazuje /dev/fd/NN i blok musi byc martwy,
# inaczej wola bump.sh ze sciezki `/dev/fd/../scripts/bump.sh`.
#
# PRZELADOWANIE (`exec`) jest konieczne, nie ozdobne: numer jest LITERALEM
# nizej, a `sed -i` podmienia plik przez zmiane nazwy — dzialajacy bash
# czyta dalej STARA zawartosc i wzialby numer sprzed podbicia.
#
# Przebudowa tego samego numeru:  BUMP=0 ./scripts/build.sh
if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${BUMP:-1}" = "1" ] && [ -z "${WFG_PO_BUMPIE:-}" ]; then
  bash "$SRC_DIR/scripts/bump.sh"
  export WFG_PO_BUMPIE=1
  exec bash "$0" "$@"
fi

'''

KOTWICA_BUILD = (
    'SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"/..\n'
    '\n'
    '# Numer i nazwa kodowa rozdzielone SWIADOMIE:')

ZAMIANY = [
    # --- hak w build.sh -------------------------------------------------
    ('scripts/build.sh',
     KOTWICA_BUILD,
     'SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"/..\n'
     + HAK
     + '# Numer i nazwa kodowa rozdzielone SWIADOMIE:',
     'build.sh: podbicie numeru przy kazdym buildzie',
     False),

    # --- odporne wczytanie naglowka w bump.sh ---------------------------
    ('scripts/bump.sh',
     'bash -c \'source <(sed -n "1,20p" scripts/build.sh); echo "  $APP_VERSION_STR   kod $APK_VERSION_CODE"\'',
     'bash -c \'source <(grep -E "^export APP_|^export APK_" scripts/build.sh); echo "  $APP_VERSION_STR   kod $APK_VERSION_CODE"\'',
     'bump.sh: wczytanie naglowka po nazwach, nie po wierszach',
     False),

    # --- to samo w historycznym skrypcie wydania (jesli jest) -----------
    ('skrypty/wydaj_0_12_0.sh',
     'bash -c \'source <(sed -n "1,20p" scripts/build.sh); echo "  ${APP_VERSION_STR}   kod ${APK_VERSION_CODE}"\'',
     'bash -c \'source <(grep -E "^export APP_|^export APK_" scripts/build.sh); echo "  ${APP_VERSION_STR}   kod ${APK_VERSION_CODE}"\'',
     'wydaj_0_12_0.sh: to samo wczytanie',
     True),

    # --- nazwa pliku APK ------------------------------------------------
    ('skrypty/przygotuj_apk.sh',
     'PODSTAWA="WorkField-${WERSJA}-${KOD}-${ARCH}-${DZIEN}"',
     'PODSTAWA="WorkFieldGIS-${WERSJA}-${KOD}-${ARCH}-${DZIEN}"',
     'przygotuj_apk: nazwa pliku APK',
     False),
    ('skrypty/przygotuj_apk.sh',
     '#     WorkField-0.12.0-1200-arm64-20260921.apk',
     '#     WorkFieldGIS-0.12.1-1201-arm64-20260922.apk',
     'przygotuj_apk: przyklad w naglowku',
     False),
    ('skrypty/przygotuj_apk.sh',
     '  echo "WorkField ${WERSJA}${NAZWA_KODOWA:+ „${NAZWA_KODOWA}”}  (build ${KOD}, ${ARCH}, $(date \'+%Y-%m-%d\'))"',
     '  echo "WorkFieldGIS ${WERSJA}${NAZWA_KODOWA:+ „${NAZWA_KODOWA}”}  (build ${KOD}, ${ARCH}, $(date \'+%Y-%m-%d\'))"',
     'przygotuj_apk: naglowek notatki',
     False),
    ('skrypty/przygotuj_apk.sh',
     '  echo "     w pamięci telefonu zostają — WorkField trzyma je poza aplikacją."',
     '  echo "     w pamięci telefonu zostają — WorkFieldGIS trzyma je poza aplikacją."',
     'przygotuj_apk: zdanie o danych',
     False),
    ('skrypty/przygotuj_apk.sh',
     'echo "STOP: brak scripts/build.sh — to nie jest katalog WorkFielda"',
     'echo "STOP: brak scripts/build.sh — to nie jest katalog WorkFieldGIS"',
     'przygotuj_apk: komunikat o katalogu',
     False),
]


def czytaj(p):
    return open(p, encoding='utf-8').read()


bledy = []
tresci = {}
doZrobienia = []
juzZrobione = []
pominiete = []

for plik, stare, nowe, opis, wolno_brak in ZAMIANY:
    if not os.path.exists(plik):
        if wolno_brak:
            pominiete.append('%s — nie ma tego pliku, pomijam' % opis)
        else:
            bledy.append('brak pliku %s (%s)' % (plik, opis))
        continue
    if plik not in tresci:
        tresci[plik] = czytaj(plik)
    t = tresci[plik]
    # „Juz zrobione” poznajemy po NOWYM tekscie, nie po braku starego:
    # polowa tych zamian DOPISUJE przy kotwicy, wiec kotwica zostaje
    # w pliku takze po udanym zapisie.
    if t.count(nowe) >= 1:
        juzZrobione.append(opis)
        continue
    if t.count(stare) != 1:
        bledy.append('%s: kotwica „%s…” wystepuje %d x (oczekiwano 1) — %s'
                     % (plik, stare.strip()[:50], t.count(stare), opis))
        continue
    doZrobienia.append((plik, stare, nowe, opis))

for cel in NOWE:
    kat = os.path.dirname(cel)
    if kat and not os.path.isdir(kat):
        bledy.append('nie ma katalogu %s (dla %s)' % (kat, cel))

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

for o in pominiete:
    print('  pomijam:     ', o)
for o in juzZrobione:
    print('  juz zrobione:', o)

for cel, dane in NOWE.items():
    tresc = zlib.decompress(base64.b64decode(''.join(dane.split())))
    stara = open(cel, 'rb').read() if os.path.exists(cel) else None
    if stara == tresc:
        print('  bez zmian:   %s' % cel)
        continue
    open(cel, 'wb').write(tresc)
    os.chmod(cel, 0o755)
    print('  %-44s %s' % (cel, 'nadpisany' if stara is not None else 'NOWY'))

for plik, stare, nowe, opis in doZrobienia:
    tresci[plik] = tresci[plik].replace(stare, nowe, 1)
for plik in sorted({p for p, _, _, _ in doZrobienia}):
    open(plik, 'w', encoding='utf-8').write(tresci[plik])
for plik, stare, nowe, opis in doZrobienia:
    print('  %-44s %s' % (opis, 'OK'))

print()
print('  zmienionych plikow: %d' % len({p for p, _, _, _ in doZrobienia}))
KONIEC_PY

echo
echo "Sprawdzenie na sucho — NIE buduje, tylko pokazuje, co zrobi bump:"
echo "  grep -n 'WFG_PO_BUMPIE' scripts/build.sh"
echo
echo "=============================================================="
echo "OD TERAZ"
echo "=============================================================="
echo
echo "Kazdy build podbija fix sam. Pierwszy build po tej latce da 0.12.1:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 3"
echo "  bash skrypty/przygotuj_apk.sh"
echo
echo "Przebudowa tego samego numeru (gdy build padl i poprawiasz drobiazg):"
echo "  BUMP=0 triplet=arm64-android ./scripts/build.sh"
echo
echo "Wydanie = build, ktory blogoslawisz. Numer jest juz w build.sh:"
echo "  bash skrypty/wydaj.sh                 # zloz note, pokaz, stan"
echo "  bash skrypty/wydaj.sh --wykonaj       # tag + release na GitHubie"
echo
echo "Nowa nazwa kodowa dopiero przy zmianie minor:"
echo "  bash skrypty/wydaj.sh 0.13.0 --nazwa=\"Fiber Fir\""
echo "  (skrypt odmowi zmiany nazwy bez zmiany minor i odmowi zmiany"
echo "   minor bez nazwy — zeby jedno nie uciekalo drugiemu)"
