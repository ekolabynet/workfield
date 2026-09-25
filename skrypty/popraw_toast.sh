#!/bin/bash
# WorkFieldGIS 23.09.2026 - POPRAWKA: BUILD SIE NIE KOMPILOWAL.
#
#     QfToast.qml:222:9: error: Property value set multiple times
#
# MOJ BLAD, KONKRETNY. W `instaluj_rady.sh` dopisalem `toastAction`
# warunek `visible: !toast.trwaly && text != ''`, a ORYGINALNY
# `visible: text != ''` zostal cztery linijki wyzej. QML nie pozwala
# przypisac tej samej wlasnosci dwa razy w jednym bloku.
#
# DLACZEGO NIE WYSZLO W PIASKOWNICY
# ----------------------------------
# `qmllint` przepuszcza to bez slowa: podwojne przypisanie jest bledem
# SEMANTYCZNYM, nie skladniowym, a lint sprawdza tylko skladnie. Zobaczyl
# to dopiero `qmlcachegen` przy budowaniu.
#
# Dopisalem sobie do sprawdzania wlasnego straznika: w kazdym bloku `{...}`
# zadna nazwa wlasnosci nie moze paść dwa razy. Przepuscilem przez niego
# wszystkie szesc plikow QML ruszonych dzisiaj - reszta czysta.
#
# CO SIE DZIEJE PO TEJ POPRAWCE
# ------------------------------
# Zostaje JEDEN `visible`, ten warunkowy. Przy trwalym dymku odsylacze
# rysuje `toastAkcje` nizej, wiec stary pojedynczy przycisk ma zniknac -
# inaczej wyszlyby dwa rzedy, jeden pusty.
#
# PRZY OKAZJI, DO BUDOWANIA: `tail -n 3` gubi bledy. Zostalo z porady,
# ktora miala chronic przed `head` (SIGPIPE ubija build). Przy budowie,
# ktora PADA, potrzeba wiecej:
#
#     triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 40
#
# Uruchom w katalogu repo. Idempotentny; sprawdza sume PRZED zapisem.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64, hashlib, os, sys, zlib
CALE = {}

CALE['src/gui/qml/QfToast.qml'] = (['c5368fadbd77ab127881103faab4185b'], '32ce52c806b84e3ad78b0c2c73f77144', """\
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""")


bledy, juzZrobione, doZapisu = [], [], []
for cel, (przed, po, _b) in CALE.items():
    if not os.path.exists(cel):
        bledy.append('brak pliku %s' % cel)
        continue
    suma = hashlib.md5(open(cel, 'rb').read()).hexdigest()
    if suma == po:
        juzZrobione.append('%s juz poprawiony' % cel)
        continue
    if suma not in przed:
        bledy.append('%s ma sume %s, a latka oczekuje: %s.\n'
                     '       NIE nadpisuje. Przyslij go PELNA SCIEZKA.'
                     % (cel, suma, ', '.join(przed)))
        continue
    doZapisu.append(cel)

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

for opis in juzZrobione:
    print('  juz zrobione:', opis)

for cel in doZapisu:
    open(cel, 'wb').write(zlib.decompress(base64.b64decode(''.join(CALE[cel][2].split()))))
    print('  %-42s %s' % (cel, 'POPRAWIONY'))

print()
print('  zmienionych plikow: %d' % len(doZapisu))
KONIEC_PY

echo
echo "Sprawdzenie na oko (ma byc 1, nie 2):"
echo "  grep -c 'visible:.*text != ' src/gui/qml/QfToast.qml"
echo
echo "Build — TYM RAZEM Z WIEKSZYM OGONEM, zeby bledow nie ucialo:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 40"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh"
