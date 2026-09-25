#!/bin/bash
# WorkFieldGIS 23.09.2026 - DYMEK STARTOWY PROWADZI DO WYPOSAZENIA.
#
# CO TO ZMIENIA
# -------------
# Dymek przy otwarciu projektu ("Temu projektowi brakuje...") mial przycisk
# "Pokaz", ktory prowadzil do QfNaprawaProjektu - okna starszego od
# Wyposazenia i robiacego to samo gorzej. Od tej latki prowadzi tam, gdzie
# siedza czasowniki.
#
# DLACZEGO NIE SKASOWALISMY TAMTEGO OKNA
# ---------------------------------------
# Bo robilo TRZY rzeczy, nie jedna, i dwie z nich nie mialy odpowiednika:
#
#   kafle paska            -> Wyposazenie umie to od dzis rana, i lepiej
#   warstwa tyczenia       -> j.w.
#   POBIERZ SLOWNIK        -> nie bylo tego nigdzie indziej
#   "JAK TEN PROJEKT JEST  -> nie bylo tego nigdzie indziej; ten ekran
#    USTAWIONY"               powstal po dniu terenu straconym na `type=3`
#
# Wiec zamiast kasowac - wypatroszylismy. Slownik przeniosl sie do
# Wyposazenia, zrzut ustawien zostal na miejscu pod nowa nazwa, a czasowniki
# z niego wylecialy.
#
# CO WYLECIALO Z QfNaprawaProjektu (~200 linii)
# ----------------------------------------------
#   zbudujKlawisze()  - bralo `nazwa.substring(0, 1)` bez sprawdzania
#                       kolizji. Kreator "Projekt z DXF" zaklada "Punkty"
#                       i "Poligony" - OBA dostawaly "P". Do tego pisalo
#                       CALY plik od nowa, wiec kafel dopisany recznie
#                       znikal przy nastepnym tapnieciu.
#   opisDzialania(), wykonaj(), okno potwierdzenia, pobieranie slownika
#
# JEDNO ZRODLO PRAWDY W KONTROLI
# -------------------------------
# QfKontrolaProjektu miala WLASNA liste brakow obok katalogu wyposazenia
# i obie juz sie rozjezdzaly: Kontrola mowila "brak definicji kafli paska"
# przy pliku, ktory Wyposazenie uznawalo za dobry - bo jedna patrzyla na
# obecnosc pliku, druga na jego zawartosc i wersje modulu.
# Od dzis Kontrola pyta katalog. Nowy modul pojawia sie w dymku sam.
#
# ZOSTAJE JEJ JEDEN WLASNY SPRAWDZIAN: slownik gatunkow. To nie struktura,
# tylko TRESC - zaden katalog jej nie opisze i zaden kod nie wymysli.
#
# CO WCHODZI
# ----------
#   src/app/qml/QfKontrolaProjektu.qml   pyta katalog; dymek -> Wyposazenie
#   src/app/qml/QfNaprawaProjektu.qml    czysty zrzut ustawien, zero zapisow
#   src/app/qml/QfWyposazenie.qml        wiersz "Slownik gatunkow" z
#                                        pobieraniem + przycisk "Ustawienia"
#   src/app/qml/QgisMobileapp.qml        dwa wiazania + displayToastTrwaly
#   src/gui/qml/QfToast.qml              dymek trwaly (wlaczany osobno)
#
# DYMEK STARTOWY CZEKA NA TAPNIECIE
# ----------------------------------
# Jest SZERSZY (margines 54 -> 12 px), ma MNIEJSZA czcionke (defaultFont ->
# tipFont), przycisk POD tekstem zamiast obok, i NIE GASNIE SAM.
#
# Powod: ten jeden dymek wymienia po nazwie wszystko, czego projektowi
# brakuje - bywa, ze trzy rzeczy. Piec sekund nie wystarcza, zeby to
# przeczytac w rekawicach i w sloncu, a drugi raz komunikat nie przyjdzie:
# leci RAZ, poltorej sekundy po wczytaniu projektu.
#
# WLACZANE OSOBNO, przez nowa funkcje `pokazTrwaly()` / `displayToastTrwaly()`.
# "Przegladanie", "Autozapis projektu" i reszta gasna dalej po trzech
# sekundach - dymek wiszacy po kazdej drobnej czynnosci bylby gorszy od zbyt
# krotkiego. Osobna funkcja, a nie siodmy argument `displayToast`: ta ma ich
# juz szesc i siodmy latwo wpisac przez pomylke.
#
# UWAGA: `src/gui/qml/QfToast.qml` to plik WSPOLNY, z modulu GUI QFielda.
# Zmiana jest dopisaniem, nie przerobka: bez `trwaly` wszystko liczy sie
# dokladnie tak jak dotad.
#
# TA LATKA ZASTEPUJE `instaluj_dymek.sh`. Wchodzi niezaleznie od tego, czy
# tamta byla puszczona - sprawdza oba punkty wyjscia.
#
# Uruchom w katalogu repo. Idempotentny; sprawdza WSZYSTKIE kotwice i sumy
# kontrolne PRZED jakimkolwiek zapisem.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64
import hashlib
import os
import sys
import zlib

CALE = {}

CALE['src/app/qml/QfKontrolaProjektu.qml'] = (['fa56d7eeda47e4dce0deacface867195', 'c33469f72f67530bc3f9817f44089d91'], '145f8fd51265e85d71942baf17fc6fbf', """\
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""")
CALE['src/app/qml/QfNaprawaProjektu.qml'] = (['9cd3ec6ab72f4fad2c6126a57dc675b5'], 'f790fccf7bd7b4b7c022b42eeb96e58c', """\
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""")
CALE['src/app/qml/QfWyposazenie.qml'] = (['b8579b7c8f56c5d283edc3f15dee075a'], '4ba0a2998a9b47b2d70c02d09c681dda', """\
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
Dw==""")
CALE['src/gui/qml/QfToast.qml'] = (['53c2e711e23cee5faec7a6b0e7b14e3b'], '03762a35467a8b33717fbf7fc6addc47', """\
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
OyDn+/Hs/wzJfiWc+m9Q6Kp31fs35WmOdg==""")


# ==========================================================================
# ZMIANY W ISTNIEJACYCH PLIKACH - (plik, stare, nowe, opis)
# ==========================================================================
ZAMIANY = []

# Dymek prowadzi do Wyposazenia. Wiazanie musi byc TUTAJ, a nie w srodku
# QfKontrolaProjektu: identyfikatory z QgisMobileapp.qml nie sa widoczne
# w osobnym komponencie - kazdy plik .qml ma wlasny zakres nazw.
ZAMIANY.append((
    'src/app/qml/QgisMobileapp.qml',
    '    ekranNaprawy: naprawaProjektu\n',
    '    ekranDocelowy: ekranWyposazenia\n',
    'QgisMobileapp: dymek -> Wyposazenie'))

# Droga powrotna: z Wyposazenia do zrzutu ustawien. Bez tego ten ekran
# zostalby dostepny juz tylko z szuflady.
ZAMIANY.append((
    'src/app/qml/QgisMobileapp.qml',
    '  QfWyposazenie {\n    id: ekranWyposazenia\n  }\n',
    '  QfWyposazenie {\n    id: ekranWyposazenia\n    ekranUstawien: naprawaProjektu\n  }\n',
    'QgisMobileapp: Wyposazenie -> ustawienia projektu'))

# Dymek trwaly. Osobna funkcja, a nie siodmy argument `displayToast` —
# ta ma ich juz szesc i siodmy latwo wpisac przez pomylke w zwyklym
# wywolaniu. Tu trzeba napisac inna nazwe, zeby dostac inne zachowanie.
ZAMIANY.append((
    'src/app/qml/QgisMobileapp.qml',
    '  function displayToast(message, type, action_text, action_function, stop_function, is_animation_enabled) {\n'
    '    toast.show(message, type, action_text, action_function, stop_function, is_animation_enabled);\n'
    '  }\n',
    '  function displayToast(message, type, action_text, action_function, stop_function, is_animation_enabled) {\n'
    '    toast.show(message, type, action_text, action_function, stop_function, is_animation_enabled);\n'
    '  }\n'
    '\n'
    '  //! Dymek, ktory NIE GASNIE SAM — czeka na tapniecie. Uzywa go dymek\n'
    '  //! startowy „Temu projektowi brakuje…”, bo wymienia po nazwie kilka\n'
    '  //! rzeczy naraz, a leci RAZ. Reszta dymkow gasnie dalej sama.\n'
    '  function displayToastTrwaly(message, type, action_text, action_function) {\n'
    '    toast.pokazTrwaly(message, type, action_text, action_function);\n'
    '  }\n',
    'QgisMobileapp: displayToastTrwaly'))


def czytaj(p):
    return open(p, encoding='utf-8').read()


def rozpakuj(b):
    return zlib.decompress(base64.b64decode(''.join(b.split())))


bledy = []
tresci = {}
doZrobienia = []
juzZrobione = []

for plik, stare, nowe, opis in ZAMIANY:
    if not os.path.exists(plik):
        bledy.append('brak pliku %s (%s)' % (plik, opis))
        continue
    if plik not in tresci:
        tresci[plik] = czytaj(plik)
    t = tresci[plik]
    if t.count(nowe) >= 1:
        juzZrobione.append(opis)
        continue
    if t.count(stare) != 1:
        bledy.append('%s: kotwica „%s..." wystepuje %d x (oczekiwano 1) - %s'
                     % (plik, stare.strip()[:50], t.count(stare), opis))
        continue
    doZrobienia.append((plik, stare, nowe, opis))

caleDoZapisu = []
for cel, (przed, po, _b) in CALE.items():
    if not os.path.exists(cel):
        bledy.append('brak pliku %s' % cel)
        continue
    suma = hashlib.md5(open(cel, 'rb').read()).hexdigest()
    if suma == po:
        juzZrobione.append('%s juz podmieniony' % cel)
        continue
    if suma not in przed:
        bledy.append(
            '%s ma sume %s, a latka oczekuje jednej z: %s.\n'
            '       Ten plik zostal w miedzyczasie zmieniony. NIE nadpisuje go.\n'
            '       Przyslij go, zlozymy latke na tym, co jest.'
            % (cel, suma, ', '.join(przed)))
        continue
    caleDoZapisu.append(cel)

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

for opis in juzZrobione:
    print('  juz zrobione:', opis)

zmienione = 0
for cel in caleDoZapisu:
    open(cel, 'wb').write(rozpakuj(CALE[cel][2]))
    print('  %-42s %s' % (cel, 'PODMIENIONY W CALOSCI'))
    zmienione += 1

for plik, stare, nowe, opis in doZrobienia:
    tresci[plik] = tresci[plik].replace(stare, nowe, 1)
for plik in sorted({p for p, _, _, _ in doZrobienia}):
    open(plik, 'w', encoding='utf-8').write(tresci[plik])
    zmienione += 1
for plik, stare, nowe, opis in doZrobienia:
    print('  %-42s %s' % (opis, 'OK'))

print()
print('  zmienionych plikow: %d' % zmienione)
KONIEC_PY

echo
echo "Sprawdzenie na oko:"
echo "  grep -n 'ekranDocelowy\|ekranUstawien' src/app/qml/QgisMobileapp.qml"
echo "  grep -n 'zbudujKlawisze' src/app/qml/QfNaprawaProjektu.qml   # ma nic nie znalezc"
echo "  grep -n 'wf_wskazniki' src/app/qml/QfWyposazenie.qml"
echo "  grep -n 'pokazTrwaly' src/gui/qml/QfToast.qml src/app/qml/QgisMobileapp.qml"
echo
echo "Build i instalacja:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 3"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh"
echo
echo "NA TELEFONIE:"
echo "  1. Otworz projekt, ktoremu czegos brakuje. Dymek ma powiedziec,"
echo "     CZEGO brakuje NAZWAMI MODULOW z katalogu, a przycisk „Pokaz”"
echo "     ma otworzyc WYPOSAZENIE - z wypelniona lista, nie pusta."
echo "  2. W Wyposazeniu, pod lista modulow, ma byc wiersz „Slownik"
echo "     gatunkow”. Gdy pliku nie ma - przycisk „Pobierz z sieci”."
echo "     Tapnij; po pobraniu kropka ma zzieleniec bez zamykania okna."
echo "  3. W naglowku Wyposazenia przycisk „Ustawienia” ma otworzyc"
echo "     „Jak ten projekt jest ustawiony” - bez przyciskow „Zaloz”."
echo "  4. Szuflada -> „Stan projektu” ma otwierac to samo okno co w p. 3."
echo "  5. DYMEK STARTOWY: szerszy, mniejsza czcionka, przycisk „Pokaz” POD"
echo "     tekstem — i MA NIE ZGASNAC sam. Znika dopiero po tapnieciu."
echo "  6. KONTROLA, ze reszta dymkow bez zmian: przelacz tryb na"
echo "     przegladanie („Przegladanie”) — ten ma zgasnac po ~3 sekundach,"
echo "     waski i wiekszą czcionka, jak dotad."
