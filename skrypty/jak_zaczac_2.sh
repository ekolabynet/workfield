#!/bin/bash
# WorkField 22.09.2026 - EKRAN „JAK ZACZAC?" WERSJA DRUGA (uwagi z telefonu).
#
# =====================================================================
#  CO SIE ZMIENIA I DLACZEGO
# =====================================================================
#
# 1. WLASNA SKORA: ciemny teal (#0B3B39), jasnozielone naglowki (#A8E86A),
#    jasny tekst (#EAF7EF). Ekran przestaje brac barwy z Theme - powitanie
#    ma wygladac inaczej niz okna robocze, zeby bylo widac, ze to
#    powitanie, a nie kolejne okno do wypelnienia.
#
#    PRZY OKAZJI ZNALEZIONE POMIAREM: ItemDelegate ze stylu rysuje BIALE
#    tlo wiersza. Na jasnym motywie niewidoczne, na ciemnym - bialy pas,
#    na ktorym ginie jasny tytul (zmierzone: piksel tla (255,255,255)
#    przy tle okna (11,59,57)). Wiersz dostaje wiec wlasne, przezroczyste
#    tlo z kreska rozdzielajaca i rozjasnieniem pod palcem.
#
# 2. WIERSZE PROWADZA DO OKIEN, nie do szuflad, w ktorych polecenie sie
#    chowa. Nowe czynnosci:
#       Moje projekty        -> welcomeScreen.visible = true
#       Import z rysunku DXF -> oknoImportuCAD.open()
#       Podklady             -> oknoPodkladow.open()
#       Dane wysokosciowe    -> oknoDaneWysokosciowe.open()
#       Georeferencja obrazu -> oknoGeoreferencji.open()
#       Wtyczki              -> pluginManagerSettings.open()
#
#    TRZY WIERSZE ZOSTAJA SZUFLADAMI, bo wlasnego okna po prostu nie maja:
#    „Zloz projekt z modulu" (QfSekcjaModulow to sama zakladka - ma
#    `nacisnij()` i `wykonaj()`, nie okno), „Warstwy" i „Stylizacja"
#    (sekcje lewej szuflady). Ich opisy mowia to wprost, zeby wiersz nie
#    obiecywal okna, ktorego nie ma.
#
# 3. Wersja nie zmienia sposobu zamykania: ekran znika po klikniecu, bo
#    jest modalny i musi zejsc z drogi szufladzie. Droga POWROTNA - pozycja
#    „Jak zaczac?" w menu bocznym - idzie osobnym skryptem, po sprawdzeniu,
#    kto naprawde wstawia SideMenu.
#
# Ekran obejrzany w piaskowni Qt PO poprawce (tlo wiersza zmierzone
# ponownie: (11,59,57), tytul (234,247,239)).
#
# Wymaga instaluj_jak_zaczac.sh. Idempotentny.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
import base64, sys, zlib

QML = 'src/app/qml/QfJakZaczac.qml'
APP = 'src/app/qml/QgisMobileapp.qml'

EKRAN_B64 = """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
IA=="""


def czytaj(p):
    return open(p, encoding='utf-8').read()


try:
    app = czytaj(APP)
    czytaj(QML)
except FileNotFoundError as e:
    print('BRAK pliku:', e, '- najpierw instaluj_jak_zaczac.sh')
    sys.exit(1)

bledy = []

# --- kotwica: deklaracja ekranu --------------------------------------
stara = '''    oknoWtyczek: pluginManagerSettings
    podklady: oknoPodkladow
  }
'''
nowa = '''    oknoWtyczek: pluginManagerSettings
    podklady: oknoPodkladow
    daneWysokosciowe: oknoDaneWysokosciowe
    importCAD: oknoImportuCAD
    georeferencja: oknoGeoreferencji
    ekranPowitalny: welcomeScreen
  }
'''
juz = 'ekranPowitalny: welcomeScreen' in app
if not juz and app.count(stara) != 1:
    bledy.append('QgisMobileapp: kotwica deklaracji %d x (oczekiwano 1)' % app.count(stara))

# --- kotwica: okna, do ktorych teraz prowadza wiersze ----------------
for ident in ('id: oknoDaneWysokosciowe', 'id: oknoImportuCAD',
              'id: oknoGeoreferencji', 'id: welcomeScreen'):
    if ident not in app:
        bledy.append('QgisMobileapp: brak "%s"' % ident)

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

doZapisu = {QML: zlib.decompress(base64.b64decode(EKRAN_B64)).decode('utf-8')}
if not juz:
    doZapisu[APP] = app.replace(stara, nowa, 1)

for sciezka, tresc in doZapisu.items():
    if czytaj(sciezka) == tresc:
        print(' ', sciezka, '- bez zmian')
        continue
    open(sciezka, 'w', encoding='utf-8').write(tresc)
    print(' ', sciezka, 'OK')
KONIEC_PY

echo
echo "Build i telefon:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 5"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh"
echo
echo "Ekran pokaze sie sam tylko RAZ. Zeby zobaczyc go teraz ponownie,"
echo "zaznacz w jego stopce „Pokazuj przy starcie” przed zamknieciem."
