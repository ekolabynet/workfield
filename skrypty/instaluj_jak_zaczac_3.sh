#!/bin/bash
# WorkFieldGIS 22.09.2026 - EKRAN „JAK ZACZAC?" WERSJA 3 + IKONA ZE ZNAKIEM
# ZAPYTANIA + AKAPIT O POCHODZENIU.
#
# CO SIE ZMIENIA I DLACZEGO:
#
# 1. IKONA. Przycisk w naglowku szuflady dostal `wfg_info` - i to byl blad,
#    ktorego nie widac w kodzie. `wfg_info.svg` to PELNY kwadrat z biala
#    litera "i" wycieta w srodku. Ikony w menu sa przebarwiane
#    (ColorOverlay / icon.color), a przebarwienie zamienia KAZDY nieprzezroczysty
#    piksel na jeden kolor - biala litera znika i zostaje jednolita placka.
#    Nowa `wfg_pytanie.svg` jest rysowana samymi kreskami (dymek + znak
#    zapytania), wiec przebarwienie jej nie zjada. Tego prosil autor:
#    „znak zapytania w dymku".
#
# 2. EKRAN, WERSJA 3. Dochodzi to, o co prosil autor:
#      - OSTRZEZENIE o wczesnym etapie rozwoju, na samej gorze, w ramce;
#      - „CO TO JEST": czym jest PROJEKT i czym jest ZLECENIE (grupa projektow,
#        w ktorej pilnujemy unifikacji oraz rozdawania i odbierania pracy);
#      - „NA CZYM TO STOI": fork QFielda, silnik QGIS, z odsylaczami;
#      - wiersze „Zlecenia" i „Projekt" w spisie miejsc (byly tylko Warstwy
#        i Stylizacja - dwie z czterech sekcji lewej szuflady).
#
# 3. AKAPIT O POCHODZENIU jest JEDNYM plikiem (`QfPochodzenie.qml`) uzytym
#    w DWOCH miejscach: na ekranie powitalnym i w oknie „Co nowego". Dwie
#    kopie tego samego zdania rozjezdzaja sie przy pierwszej poprawce.
#
# 4. OKNO „CO NOWEGO" mialo naglowek „What's new in QField" - czyli po
#    klikniecu w nazwe NASZEGO programu wyskakiwala nazwa cudzego. Teraz
#    „Co nowego w WorkFieldGIS", a nad trescia stoi akapit o pochodzeniu.
#
# WERSJA QFIELDA, na ktorej stoi fork, jest LICZONA Z GITA przy instalacji:
#   git describe --tags --abbrev=0 $(git merge-base HEAD upstream/master)
# Jak sie nie uda (brak zdalnego `upstream`), pole zostaje puste i zdanie
# mowi po prostu „fork QFielda", bez numeru. Lepiej bez liczby niz z liczba
# zmyslona. Mozna tez podac ja recznie:
#   bash instaluj_jak_zaczac_3.sh . v4.3.2
#
# WERSJA QGIS-a jest czytana Z DZIALAJACEJ APLIKACJI (`Qfield.qgisVersion`),
# wiec nie da sie jej przeterminowac.
#
# WYMAGA: wczesniej instaluj_jak_zaczac.sh, popraw_jak_zaczac.sh,
# jak_zaczac_2.sh i instaluj_menu_jak_zaczac.sh.
#
# Uruchom w katalogu repo. Idempotentny.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

# --- wersja upstreamowego QFielda ------------------------------------
WERSJA_QF="${2:-}"
if [ -z "$WERSJA_QF" ]; then
  BAZA=$(git merge-base HEAD upstream/master 2>/dev/null || true)
  [ -n "$BAZA" ] && WERSJA_QF=$(git describe --tags --abbrev=0 "$BAZA" 2>/dev/null || true)
  [ -n "$WERSJA_QF" ] || WERSJA_QF=$(git describe --tags --abbrev=0 upstream/master 2>/dev/null || true)
fi
if [ -n "$WERSJA_QF" ]; then
  echo "== wersja QFielda z gita: $WERSJA_QF"
else
  echo "== wersji QFielda nie da sie policzyc (brak zdalnego 'upstream')."
  echo "   Zdanie bedzie bez numeru. Zeby go miec:"
  echo "     git remote add upstream https://github.com/opengisch/QField.git"
  echo "     git fetch upstream --tags"
  echo "     bash $(basename "$0")"
  echo "   albo podaj recznie:  bash $(basename "$0") . v4.3.2"
fi
export WERSJA_QF

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64
import os
import sys
import zlib

EKRAN = 'src/app/qml/QfJakZaczac.qml'
POCH = 'src/app/qml/QfPochodzenie.qml'
APP = 'src/app/qml/QgisMobileapp.qml'
SZUFLADA = 'src/app/qml/QfMainDrawer.qml'
ZMIANY = 'src/app/qml/QfChangelog.qml'
CMAKE = 'src/app/qml/CMakeLists.txt'
QRC = 'images/images.qrc'
IKONA = 'images/themes/workfield/wfg_pytanie.svg'

WERSJA_QF = os.environ.get('WERSJA_QF', '')

P_POCH = """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
hInXzibL/yBznUXwsvWy9S8lpaQs"""
P_EKRAN = """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
fZSlqYwWZwP6hN7VFMwcb1sI1PTzeuX/ALZsd2Y="""
P_IKONA = """eNp9ks9PgzAUx+/+FS/1TEuLZWOCiXLxoCeNB2+m66CTwQJVthj/d1/fmHHJYkLKJ9/3u3358FnB
btO0Q8Fq77cLIcZx5GPCu74SKo5jgR4MPp0d77pdwWKIQSn8GIxu6euCBaytq2pPfHMBkC/tagC3
LBiCa51ZW9LRMvh9Y8Hvt7Zg3u68MMPAyNV89L1tfWS6puujwdR2c4wC4GVQn0iMnjEOviYLAAUs
LlWiUpVdT/L3oZygetSTCE0RVbByTVOwtmstg8H33bv9rU+FjmrUuNauO9cWrO8+2uWJbt62R3ka
bvvm66PHdDuSawY43aPmGhI+03AvU8RbFZiOcKUSZMaVhmB6keqsQ7BJHbzuZYz8kAajnFPIQdfn
Agkp58vZyr+dvTLx3yDZYZA5T2HGMygDpPwKMj6nHFJyqYlKqkYaJiYnglmoUhJmXIaeEo2UhtAZ
0FAlIorIGWVM6FR/ONWHNnNR0c+43uBKGVxO8mFg9ogJBjHoQ+OSTQ9+8sSYJA/LfXPxAzxOxR8="""


def rozpak(b):
    return zlib.decompress(base64.b64decode(''.join(b.split()))).decode('utf-8')


def czytaj(p):
    return open(p, encoding='utf-8').read()


bledy = []
for p in (EKRAN, APP, SZUFLADA, ZMIANY, CMAKE, QRC):
    if not os.path.exists(p):
        bledy.append('brak pliku %s' % p)
if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

app = czytaj(APP)
szuflada = czytaj(SZUFLADA)
zmiany = czytaj(ZMIANY)
cmake = czytaj(CMAKE)
qrc = czytaj(QRC)

if 'id: oknoJakZaczac' not in app:
    bledy.append('QgisMobileapp.qml: brak `id: oknoJakZaczac` - najpierw instaluj_jak_zaczac.sh')
if 'QfJakZaczac.qml' not in cmake:
    bledy.append('CMakeLists.txt: QfJakZaczac.qml nie jest na liscie QML - cos poszlo nie tak wczesniej')

# --- kotwice ---------------------------------------------------------
K_CMAKE = '    QfPluginManagerSettings.qml\n'
W_CMAKE = '    QfPochodzenie.qml\n'

K_QRC = '        <file>themes/workfield/wfg_info.svg</file>\n'
W_QRC = '        <file>themes/workfield/wfg_pytanie.svg</file>\n'

K_IKONA_PRZYCISK = 'iconSource: Theme.getThemeVectorIcon("wfg_info")\n'
W_IKONA_PRZYCISK = 'iconSource: Theme.getThemeVectorIcon("wfg_pytanie")\n'

K_IKONA_POZYCJA = '          ikona: "wfg_info"\n'
W_IKONA_POZYCJA = '          ikona: "wfg_pytanie"\n'

K_TYTUL = '      title: qsTr("What\'s new in QField")\n'
W_TYTUL = '      title: qsTr("Co nowego w WorkFieldGIS")\n'

K_TRESC_ZMIAN = (
    '          Text {\n'
    '            id: changelogBody\n'
)
W_TRESC_ZMIAN = (
    '          // WFG-POCHODZENIE — WorkFieldGIS 22.09.2026.\n'
    '          // Do 22.09 to okno mialo naglowek „What\'s new in QField”: klikniecie\n'
    '          // w nazwe NASZEGO programu wyswietlalo nazwe cudzego. Naglowek\n'
    '          // poprawiony, a nad lista zmian stoi zdanie, skad ten program jest.\n'
    '          QfPochodzenie {\n'
    '            Layout.fillWidth: true\n'
    '            Layout.bottomMargin: 10\n'
    '            wersjaQGIS: String(Qfield.qgisVersion).split("-")[0]\n'
    '            barwaTekstu: QfTheme.secondaryTextColor\n'
    '            barwaLinku: QfTheme.mainColor\n'
    '            rozmiar: QfTheme.tipFont.pointSize\n'
    '          }\n'
    '\n'
)

K_ID_EKRANU = '    id: oknoJakZaczac\n'
W_ID_EKRANU = '    wersjaQGIS: String(Qfield.qgisVersion).split("-")[0]\n'

# --- co juz zrobione -------------------------------------------------
maCmake = 'QfPochodzenie.qml' in cmake
maQrc = 'wfg_pytanie.svg' in qrc
maIkone = os.path.exists(IKONA)
maPoch = os.path.exists(POCH)
maPrzycisk = 'wfg_pytanie' in szuflada
maTytul = 'Co nowego w WorkFieldGIS' in zmiany
maTresc = 'WFG-POCHODZENIE' in zmiany
maWersje = 'wersjaQGIS' in app

def sprawdz(tresc, kotwica, opis, plik):
    n = tresc.count(kotwica)
    if n != 1:
        bledy.append('%s: kotwica %s wystepuje %d x (oczekiwano 1)' % (plik, opis, n))


if not maCmake:
    sprawdz(cmake, K_CMAKE, 'QfPluginManagerSettings.qml', CMAKE)
if not maQrc:
    sprawdz(qrc, K_QRC, 'wfg_info.svg', QRC)
if not maPrzycisk:
    sprawdz(szuflada, K_IKONA_PRZYCISK, 'iconSource wfg_info', SZUFLADA)
    sprawdz(szuflada, K_IKONA_POZYCJA, 'ikona: "wfg_info"', SZUFLADA)
if not maTytul:
    sprawdz(zmiany, K_TYTUL, "What's new in QField", ZMIANY)
if not maTresc:
    sprawdz(zmiany, K_TRESC_ZMIAN, 'Text { id: changelogBody', ZMIANY)
if not maWersje:
    sprawdz(app, K_ID_EKRANU, 'id: oknoJakZaczac', APP)

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

# --- zapis -----------------------------------------------------------
zrobione = []

os.makedirs(os.path.dirname(IKONA), exist_ok=True)
tresc = rozpak(P_IKONA)
if not maIkone or czytaj(IKONA) != tresc:
    open(IKONA, 'w', encoding='utf-8').write(tresc)
    zrobione.append(IKONA)

tresc = rozpak(P_POCH).replace('@@WERSJA_QF@@', WERSJA_QF)
if not maPoch or czytaj(POCH) != tresc:
    open(POCH, 'w', encoding='utf-8').write(tresc)
    zrobione.append(POCH + (' (QField %s)' % WERSJA_QF if WERSJA_QF else ' (bez numeru QFielda)'))

tresc = rozpak(P_EKRAN)
if czytaj(EKRAN) != tresc:
    open(EKRAN, 'w', encoding='utf-8').write(tresc)
    zrobione.append(EKRAN + ' (wersja 3)')

if not maCmake:
    open(CMAKE, 'w', encoding='utf-8').write(cmake.replace(K_CMAKE, K_CMAKE + W_CMAKE, 1))
    zrobione.append(CMAKE)

if not maQrc:
    open(QRC, 'w', encoding='utf-8').write(qrc.replace(K_QRC, K_QRC + W_QRC, 1))
    zrobione.append(QRC)

if not maPrzycisk:
    s = szuflada.replace(K_IKONA_PRZYCISK, W_IKONA_PRZYCISK, 1)
    s = s.replace(K_IKONA_POZYCJA, W_IKONA_POZYCJA, 1)
    open(SZUFLADA, 'w', encoding='utf-8').write(s)
    zrobione.append(SZUFLADA + ' (ikona)')

if not maTytul or not maTresc:
    z = zmiany
    if not maTytul:
        z = z.replace(K_TYTUL, W_TYTUL, 1)
    if not maTresc:
        z = z.replace(K_TRESC_ZMIAN, W_TRESC_ZMIAN + K_TRESC_ZMIAN, 1)
    open(ZMIANY, 'w', encoding='utf-8').write(z)
    zrobione.append(ZMIANY)

if not maWersje:
    open(APP, 'w', encoding='utf-8').write(app.replace(K_ID_EKRANU, K_ID_EKRANU + W_ID_EKRANU, 1))
    zrobione.append(APP)

if not zrobione:
    print('  nic do roboty - wszystko juz jest')
else:
    for z in zrobione:
        print(' ', z, 'OK')
KONIEC_PY

echo
echo "Sprawdzenie:"
echo "  grep -n 'wfg_pytanie' src/app/qml/QfMainDrawer.qml images/images.qrc"
echo "  grep -n 'wersjaQField' src/app/qml/QfPochodzenie.qml"
echo "  grep -n 'Co nowego w WorkFieldGIS' src/app/qml/QfChangelog.qml"
echo
echo "Build i telefon:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 5"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh --log"
