#!/bin/bash
# WorkField 22.09.2026 - POPRAWKA EKRANU „JAK ZACZAC?": BRAKUJACY IMPORT.
#
# OBJAW (telefon, 13:22): ekran sie otworzyl i byl NIEWIDOCZNY, a przy
# nastepnym starcie nie pokazal sie wcale.
#
# PRZYCZYNA, wprost z logcata, trzydziesci razy:
#   qrc:/qt/qml/org/qfield/app/QfJakZaczac.qml:41: ReferenceError:
#   Theme is not defined
# Wszystkie kolory i czcionki licza sie z `Theme.*`. Bez importu kazde
# takie wiazanie rzucilo wyjatkiem i zostalo NIEUSTAWIONE - okno bylo,
# tylko cale przezroczyste. Drugiego razu nie bylo, bo pierwsze otwarcie
# zdazylo zapisac `WorkField/jakZaczacPokazane = true`.
#
# DLACZEGO NIE ZLAPALA TEGO PIASKOWNICA: mialem tam wlasny singleton
# `Theme` w katalogu glownym, widoczny BEZ importu. Mock udawal dokladnie
# to, czego brakowalo. Poprawione: w piaskowni Theme jest teraz osobnym
# MODULEM i wymaga takiego samego `import Theme` jak w repo.
#
# CO ROBI:
#   1. dokłada `import Theme` do QfJakZaczac.qml (jak w QfDataDrawer.qml),
#   2. zmienia klucz `jakZaczacPokazane` na `jakZaczacPokazane2`, zeby ekran
#      pokazal sie jeszcze raz mimo starego wpisu na telefonie - inaczej
#      poprawka byla by nie do sprawdzenia bez odinstalowania aplikacji.
#
# Uruchom w katalogu repo. Idempotentny.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
import sys

QML = 'src/app/qml/QfJakZaczac.qml'
APP = 'src/app/qml/QgisMobileapp.qml'


def czytaj(p):
    return open(p, encoding='utf-8').read()


try:
    qml, app = czytaj(QML), czytaj(APP)
except FileNotFoundError as e:
    print('BRAK pliku:', e, '- najpierw instaluj_jak_zaczac.sh')
    sys.exit(1)

bledy = []
doZapisu = {}

# --- 1. import Theme -------------------------------------------------
if 'import Theme' in qml:
    print('  QfJakZaczac.qml - import Theme juz jest')
else:
    k = 'import QtQuick.Layouts\n'
    if qml.count(k) != 1:
        bledy.append('QfJakZaczac: kotwica "import QtQuick.Layouts" %d x' % qml.count(k))
    else:
        doZapisu[QML] = qml.replace(k, k + 'import Theme\n', 1)

# --- 2. nowy klucz ustawienia ----------------------------------------
stary = "WorkField/jakZaczacPokazane'"
if "jakZaczacPokazane2'" in app:
    print('  QgisMobileapp.qml - klucz juz podbity')
elif app.count(stary) != 2:
    bledy.append('QgisMobileapp: klucz jakZaczacPokazane %d x (oczekiwano 2)' % app.count(stary))
else:
    doZapisu[APP] = app.replace(stary, "WorkField/jakZaczacPokazane2'")

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

if not doZapisu:
    print('nic do poprawienia')
    sys.exit(0)

for sciezka, tresc in doZapisu.items():
    open(sciezka, 'w', encoding='utf-8').write(tresc)
    print(' ', sciezka, 'OK')
KONIEC_PY

echo
echo "Teraz build i instalacja:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 5"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh --log"
echo
echo "W logcacie NIE powinno juz byc 'ReferenceError: Theme is not defined'."
