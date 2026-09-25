#!/bin/bash
# WorkFieldGIS 23.09.2026 - EKRAN POWITALNY: ZNAK I NAZWA.
#
# BYLO: sama ikona 192 dp, wysrodkowana, na tle okna. Bez nazwy aplikacji
# i bez wlasnego tla - wiec pierwsza rzecz po tapnieciu zalezala od motywu
# systemu.
#
# JEST: ciemne tlo (#0F1A17) i znak z napisem „WorkFieldGIS" pod spodem.
#
# NAPIS JEST KRZYWYMI, NIE TEKSTEM
# ---------------------------------
# VectorDrawable nie umie tekstu, a nawet gdyby umial - Faustiny nie ma
# na zadnym telefonie. Napis zlozony z Google Fonts i przelozony na krzywe:
#
#   „WorkField"  Faustina 400        szeryfowa, ciepla
#   „GIS"        Roboto Flex w. 700  bezszeryfowa, w akcencie #F60054
#
# Szeryf i bezszeryf w jednym napisie to nie ozdoba: nazwa sklada sie
# z dwoch czlonow o roznej wadze - „WorkField" mowi, gdzie sie pracuje,
# „GIS" czym. Wiec czytaja sie inaczej.
#
# JEDEN UKLAD WSPOLRZEDNYCH, ZERO GRUP
# -------------------------------------
# Viewport 108 x 150: pierwsze 108 jednostek to DOKLADNIE ikona adaptacyjna,
# ze sciezkami przepisanymi bez zmian. Napis dostal te same jednostki,
# z przeksztalceniem wpisanym w liczby. Grupy z ujemnym `scaleY` (os Y
# czcionki idzie w gore, ekranu w dol) to najczestsze zrodlo niespodzianek
# przy skalowaniu VectorDrawable - wiec ich tu nie ma.
#
# CZEGO NIE MA: NUMERU WERSJI ANI ANIMACJI
# -----------------------------------------
# Ten obrazek rysuje sie ZANIM Qt wstanie. O wersji nie ma skad wiedziec,
# a wpisana na sztywno zaczelaby klamac przy pierwszym buildzie. Wersja
# i ruch naleza do nakladki QML nad mapa - osobna rzecz, osobna latka.
#
# ZALEZNOSC: pusc najpierw `instaluj_ikona_prosta.sh`. Znak w splashu jest
# przepisany z ikony PO usunieciu pierscienia; inaczej ekran powitalny
# pokazywalby stara ikone obok nowej na pulpicie.
#
# Uruchom w katalogu repo. Idempotentny; sprawdza sumy PRZED zapisem.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64, hashlib, os, sys, zlib
NOWE = {}
CALE = {}

NOWE['platform/android/res/drawable/splash_wfg.xml'] = """\
eNrFnNlyXMeRhu/1FGcwN54I8LD2RWHZoZFIQXaTdlMWFeKN3QRaZBNLI7AYBq7mIeZ6Hm6eZL6/6kgm0YciJ2SHaQVIdGfX
qcrlzz+zsv3r3/7t9GT46/ricrM9+2zPjmZvWJ8dbo82Z68+27u++uFB2fvtbz759b89ePDJMDw6vlidDefbm83V6uTsdvhu
e3H8eLM+Ofrq628+He7OVsfDZjhbnW8ux08Q/92jLx89Hb79/eLzL4fvvvnjHxbPXjz68un3XxzsDy8ePfvD8NWzb/84Ds83
65vz7cXVYE0Z/jbYaIb//a//Hs4364uby7s16+iNN+ujs+3l1fp4uNoOR9vjk9XR2WY9bI63Z6thdbQ6v1od3r45W+0Pd+vh
8nCzvjtenW6G84u7NdtZnd2ebljpPx+9GF48+frzp8PdsDn888nq+uzw9frizz9sL9avLrbXZ0cj+hiHpzoDj7nknMMVC65O
1z9u4Xizz0p3benjyzskDtds5XS4mR403Awnm8O7l7fj8NXF9fktsn+5PFydrL//y3D9Zn0qkV+93A7by+F7Vjq8O0T3x5th
c3THiW6GV2xmf1gNa2n7mheOtif/oWOfrd4c3q0vr9DKcHexPTrhpc368nzLB1dn62MWY1O3w+Xx6mR7szrbXA/P14dX24sv
L1Y3q5cn66bYm836kMO/Hq6u9fHhdNWM9fTzP379DSb75k/D75+9+P677598vd/eR+fo/XS8v5beuz79UeBaOz5b3ayvWOvV
0e3LW72J9vTIx6vry6sNDtOfh9xwh/3Qw9X6ZP3DlpfH4cXJ9m6LjPOjqaMzLjU1f7XdvuJpj7dnV5efstr//OR0ez+uuxqC
McOvUMvF7Q8c/D/2JYdP7g3Pti+3aO7xyfpvrHaDX2BNPnCzOkKJWR97ub77+yfZBrs+W3UvRvm3p6tXq2ZrtoedV5iHlZA4
RtU362F7NJzxye6zq6uLO9R/cXt+dfvwjk/8+fL8ZHX5ejy/bUqW/z399smjZ98O3z169s3vvh6HP63Phu3LixXONFzcXuIg
wyVaevH506+fDMur4QYfRD/73W7b4YZYfSNfnnSJsY/0npznUEbobtiUjHfe3pxtUTZ+c7LCJsTN6eqwu8kUYbenLPbyenOi
FcbhO62/Io55KqJvtNDJ+m6FF/IvxR2uunyymJzj+mr1ZvzkwQMw4q/NPwYC6Ozy09XZ0cV2c/TZ3uurq/NPHz68JM5OV5fj
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"""
CALE['platform/android/res/drawable/splash.xml.in'] = (['c3471d17383eb75d6327e35c69a459c5'], 'c9258d8f02b9d082aa9f91d6345d14f2', """\
eNpdks9y0zAQxu95ikVcYCa2kzBD20zcNkDbKRRySJgemY29jRXLkkdSKuwTD8GZh+NJ2NgpoRw8kvbP9/208uzie6XgkayT
RqdiHI8EkM5MLvUmFTv/EJ2Ki/PB7EUUDQCuSosaahOkR6WbGD4YmLyJR2fxZDR5C+tGIfgdLOef53D7afFlDuOzCeQ1aI4r
AlPy5vePnyy1ppajbWgAayVLzLYSZBf1LBIUOk0bM4QgKYNakg2uRbAtZe0QtlgiZK1iECpZLMi8laiYDDzWmlvkbggtKuIP
weRQGd+EHbjGeap28YCbVmSxnR6sIJNU8eKVYYxWYwl7vlo6qpj4172x5bUkld/cLgW8cjV3Fd/Cwybm+b3u9e4W8PFquYLV
V3h/dbe4X8Twbn9LyReBvgPWljHXaMNxGPvhbJmhqXpKSSzWg5rAQWtaE0zUsrvRTc/mJPU35t41J+SQx7G30bL0e0eordlS
6U1AFQ+iiJ9QYUM2UtJ5YGbtpqhza2SeisL7epokLiuoQhcf4nFmqgTrMrHkkkNMnDMbwEwyXL/tjq7AmuBQM+1OqbCUedQb
ReJY2VcbJfO/1ZlRxqbi5eh6PB+fCEj+0U06qYNncjTt/Lvdkwr/Ab5IxWQ0ymvxLFOQ3BSeUyen/6dyiwHXilkv56vLp1Ny
fNzn5RuLj9I3qchIe7Id6iw5jvV88AeUdBTZ""")


def rozpakuj(b):
    return zlib.decompress(base64.b64decode(''.join(b.split())))

bledy, juzZrobione, doZapisu = [], [], []

for cel, (przed, po, _b) in CALE.items():
    if not os.path.exists(cel):
        bledy.append('brak pliku %s' % cel)
        continue
    suma = hashlib.md5(open(cel, 'rb').read()).hexdigest()
    if suma == po:
        juzZrobione.append('%s juz podmieniony' % cel)
        continue
    if suma not in przed:
        bledy.append('%s ma sume %s, a latka oczekuje jednej z: %s.\n'
                     '       NIE nadpisuje. Przyslij go PELNA SCIEZKA.'
                     % (cel, suma, ', '.join(przed)))
        continue
    doZapisu.append(cel)

for cel in NOWE:
    kat = os.path.dirname(cel)
    if kat and not os.path.isdir(kat):
        bledy.append('nie ma katalogu %s (dla %s)' % (kat, cel))

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

for opis in juzZrobione:
    print('  juz zrobione:', opis)

zmienione = 0
for cel in NOWE:
    tresc = rozpakuj(NOWE[cel])
    stara = open(cel, 'rb').read() if os.path.exists(cel) else None
    if stara == tresc:
        print('  bez zmian:   %s' % cel)
        continue
    open(cel, 'wb').write(tresc)
    print('  %-52s %s' % (cel, 'nadpisany' if stara is not None else 'NOWY'))
    zmienione += 1

for cel in doZapisu:
    open(cel, 'wb').write(rozpakuj(CALE[cel][2]))
    print('  %-52s %s' % (cel, 'PODMIENIONY'))
    zmienione += 1

print()
print('  zmienionych plikow: %d' % zmienione)
KONIEC_PY

echo
echo "Sprawdzenie na oko:"
echo "  ls -l platform/android/res/drawable/splash_wfg.xml"
echo "  grep -n 'splash_wfg\|0F1A17' platform/android/res/drawable/splash.xml.in"
echo
echo "Build i instalacja:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 3"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh"
echo
echo "NA TELEFONIE: po tapnieciu ikony, ZANIM wstanie mapa, ma mrugnac"
echo "ciemny ekran ze znakiem i napisem WorkFieldGIS. Splash trwa tyle,"
echo "ile start Qt - na szybkim telefonie ulamek sekundy."
