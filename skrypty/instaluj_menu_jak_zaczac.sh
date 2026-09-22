#!/bin/bash
# WorkField 22.09.2026 - „JAK ZACZAC?" Z MENU, A NIE TYLKO RAZ NA STARCIE.
#
# UWAGA Z TELEFONU: „Okno zamyka sie nieodwracalnie po pierwszym klikniecu.
# Cale to okno powinno byc wywolywalne jakims widocznym wpisem w menu albo
# na ekranie." Slusznie: ekran pokazywal sie raz, zapisywal `jakZaczacPokazane2`
# i nie bylo do niego zadnej drogi powrotnej. Po tej latce sa dwie:
#
#   1. PRZYCISK W NAGLOWKU LEWEJ SZUFLADY, obok strzalki zamkniecia.
#      Stoi ponad zakladkami, wiec jest widoczny w kazdej sekcji.
#   2. POZYCJA „Jak zaczac?" na poczatku sekcji „Aplikacja” w menu
#      (nad „Folder aplikacji”), tam gdzie juz mieszka „Zglos uwage".
#
# Obie wolaja ten sam nowy sygnal `pokazJakZaczac`, ktory QgisMobileapp.qml
# zamienia na `oknoJakZaczac.open()`. Jedna droga, dwa wejscia.
#
# DLACZEGO NIE `SideMenu.qml`: ten plik jest w naszym forku MARTWY. Jedyne
# jego uzycie siedzi w `QfDashBoard.qml`, a `QfDashBoard` nie jest nigdzie
# tworzony — lewa szuflada to `QfMainDrawer` (QgisMobileapp.qml:4373).
# Wpis dodany do SideMenu nie pokazalby sie nigdzie.
#
# DLACZEGO NIE WTYCZKA (pomysl z wiadomosci): wtyczki dostaja `iface`, a nie
# id-ki okien aplikacji — nie otworzyly by `oknoImportuCAD` ani `welcomeScreen`,
# czyli wlasnie tego, po co ten ekran jest. Wtyczka domyslna byla by tez
# jeszcze jednym miejscem, ktore moze sie nie zaladowac po cichu.
#
# WYMAGA: wczesniej `instaluj_jak_zaczac.sh` (+ `popraw_jak_zaczac.sh`,
# `jak_zaczac_2.sh`). Bez `id: oknoJakZaczac` skrypt nic nie zapisze.
#
# Uruchom w katalogu repo. Idempotentny.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import os
import sys

SZUFLADA = 'src/app/qml/QfMainDrawer.qml'
APP = 'src/app/qml/QgisMobileapp.qml'
EKRAN = 'src/app/qml/QfJakZaczac.qml'
IKONA = 'images/themes/workfield/wfg_info.svg'

ZNACZNIK_PRZYCISK = 'WFG-JAK-ZACZAC-PRZYCISK'
ZNACZNIK_POZYCJA = 'WFG-JAK-ZACZAC-POZYCJA'

# --- kotwice ---------------------------------------------------------
K_SYGNAL = '  signal showPluginManager\n'

K_ZAMKNIJ = (
    '      QfToolButton {\n'
    '        width: 36\n'
    '        height: 36\n'
    '        padding: 0\n'
    '        bgcolor: "transparent"\n'
    '        iconSource: Theme.getThemeVectorIcon("ic_arrow_left_black_24dp")\n'
)

K_FOLDER = (
    '        QfPozycjaMenu {\n'
    '          text: qsTr("Folder aplikacji")\n'
)

K_WTYCZKI = '    onShowPluginManager: pluginManagerSettings.open()\n'

# --- wstawki ---------------------------------------------------------
W_SYGNAL = (
    '  //! WorkField 22.09.2026 — ekran „Jak zacząć?”. Sygnał, a nie\n'
    '  //! bezpośrednie wołanie okna: szuflada nie zna id-ków z QgisMobileapp.qml.\n'
    '  signal pokazJakZaczac\n'
)

W_PRZYCISK = (
    '      // ' + ZNACZNIK_PRZYCISK + ' — WorkField 22.09.2026.\n'
    '      // Ekran „Jak zacząć?” pokazywał się raz, przy pierwszym uruchomieniu,\n'
    '      // i po pierwszym kliknięciu nie było do niego powrotu (uwaga\n'
    '      // z telefonu, 22.09). Przycisk stoi w nagłówku szuflady, czyli\n'
    '      // ponad zakładkami — widać go w każdej sekcji.\n'
    '      QfToolButton {\n'
    '        width: 36\n'
    '        height: 36\n'
    '        padding: 0\n'
    '        bgcolor: "transparent"\n'
    '        iconSource: Theme.getThemeVectorIcon("wfg_info")\n'
    '        iconColor: Theme.mainTextColor\n'
    '        ToolTip.text: qsTr("Jak zacząć?")\n'
    '        ToolTip.delay: 400\n'
    '        ToolTip.visible: hovered && ToolTip.text !== ""\n'
    '        onClicked: {\n'
    '          dashBoard.close();\n'
    '          dashBoard.pokazJakZaczac();\n'
    '        }\n'
    '      }\n'
    '\n'
)

W_POZYCJA = (
    '        // ' + ZNACZNIK_POZYCJA + ' — WorkField 22.09.2026.\n'
    '        // Druga droga do ekranu: wpis w menu, tam gdzie już stoi\n'
    '        // „Zgłoś uwagę”. Pierwszy w sekcji, bo dotyczy pierwszego dnia.\n'
    '        QfPozycjaMenu {\n'
    '          text: qsTr("Jak zacząć?")\n'
    '          ikona: "wfg_info"\n'
    '          onClicked: {\n'
    '            dashBoard.close();\n'
    '            dashBoard.pokazJakZaczac();\n'
    '          }\n'
    '        }\n'
)

W_OBSLUGA = (
    '    onPokazJakZaczac: oknoJakZaczac.open()\n'
)


def czytaj(p):
    return open(p, encoding='utf-8').read()


try:
    szuflada = czytaj(SZUFLADA)
    app = czytaj(APP)
except FileNotFoundError as e:
    print('BRAK pliku:', e)
    sys.exit(1)

bledy = []

# --- warunki wstepne -------------------------------------------------
if not os.path.exists(EKRAN):
    bledy.append('nie ma %s — najpierw instaluj_jak_zaczac.sh' % EKRAN)
if 'id: oknoJakZaczac' not in app:
    bledy.append('QgisMobileapp.qml: nie ma `id: oknoJakZaczac`')
if not os.path.exists(IKONA):
    bledy.append('nie ma ikony %s' % IKONA)

# --- co juz zrobione -------------------------------------------------
maSygnal = 'signal pokazJakZaczac' in szuflada
maPrzycisk = ZNACZNIK_PRZYCISK in szuflada
maPozycje = ZNACZNIK_POZYCJA in szuflada
maObsluge = 'onPokazJakZaczac' in app

if maSygnal and maPrzycisk and maPozycje and maObsluge:
    print('  wszystko juz jest — nic do roboty')
    sys.exit(0)

# --- WSZYSTKIE kotwice sprawdzone PRZED jakimkolwiek zapisem ---------
def sprawdz(tresc, kotwica, opis, plik):
    n = tresc.count(kotwica)
    if n != 1:
        bledy.append('%s: kotwica %s wystepuje %d x (oczekiwano 1)' % (plik, opis, n))
        return False
    return True


okSygnal = maSygnal or sprawdz(szuflada, K_SYGNAL, '"signal showPluginManager"', SZUFLADA)
okPrzycisk = maPrzycisk or sprawdz(szuflada, K_ZAMKNIJ, '"QfToolButton … ic_arrow_left"', SZUFLADA)
okPozycja = maPozycje or sprawdz(szuflada, K_FOLDER, '"QfPozycjaMenu … Folder aplikacji"', SZUFLADA)
okObsluga = maObsluge or sprawdz(app, K_WTYCZKI, '"onShowPluginManager"', APP)

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

# --- dopiero teraz zapis --------------------------------------------
if not maSygnal:
    szuflada = szuflada.replace(K_SYGNAL, K_SYGNAL + W_SYGNAL, 1)
    print('  %s — sygnal pokazJakZaczac' % SZUFLADA)
if not maPrzycisk:
    szuflada = szuflada.replace(K_ZAMKNIJ, W_PRZYCISK + K_ZAMKNIJ, 1)
    print('  %s — przycisk w naglowku' % SZUFLADA)
if not maPozycje:
    szuflada = szuflada.replace(K_FOLDER, W_POZYCJA + K_FOLDER, 1)
    print('  %s — pozycja w menu (sekcja „Aplikacja”)' % SZUFLADA)
if not maObsluge:
    app = app.replace(K_WTYCZKI, K_WTYCZKI + W_OBSLUGA, 1)
    print('  %s — onPokazJakZaczac -> oknoJakZaczac.open()' % APP)

open(SZUFLADA, 'w', encoding='utf-8').write(szuflada)
open(APP, 'w', encoding='utf-8').write(app)

# --- kontrola po zapisie --------------------------------------------
kontrola = czytaj(SZUFLADA)
if kontrola.count('pokazJakZaczac') != 3:
    print('! UWAGA: w %s jest %d wystapien pokazJakZaczac (oczekiwano 3:'
          ' sygnal + przycisk + pozycja)' % (SZUFLADA, kontrola.count('pokazJakZaczac')))
print('  OK')
KONIEC_PY

echo
echo "Sprawdzenie na oko:"
echo "  grep -n 'pokazJakZaczac' src/app/qml/QfMainDrawer.qml src/app/qml/QgisMobileapp.qml"
echo
echo "Build i instalacja (razem z jak_zaczac_2.sh, jeden build wystarczy):"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 5"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh --log"
echo
echo "Na telefonie: lewa szuflada -> ikona „i” obok strzalki zamkniecia,"
echo "oraz sekcja „Aplikacja” -> „Jak zaczac?”."
