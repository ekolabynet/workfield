#!/bin/bash
# WorkFieldGIS 23.09.2026 - STARE POLE ZDJECIE WEDRUJE DO ZALACZNIKOW.
#
# "Warstwy, dla ktorych sa zakladane multizalaczniki, zachowuja stare pole
#  zdjecie. I w sumie wyglada to dziwnie" (uwaga Piotra).
#
# Wygladalo. W formularzu byly DWA APARATY pod soba: „ZDJECIE" i „Zalaczniki".
#
# MOJA DECYZJA SPRZED DOBY, POPRAWIONA
# -------------------------------------
# 22.09 zapisalem w docs/ZALACZNIKI.md, ze modul CELOWO nie rusza pola
# ZDJECIE: skasowanie go skasowaloby sciezki do plikow lezacych juz w DCIM.
# Rozumowanie bylo poprawne, wniosek za szeroki - "nie kasuj" nie znaczy
# "pokazuj obok".
#
# CO ROBI TERAZ (modul zalaczniki: wersja 1 -> 2)
# ------------------------------------------------
#   1. Sciezka z pola ZDJECIE/FOTO staje sie PIERWSZYM ZALACZNIKIEM obiektu,
#      z TYP = "foto" i adnotacja w UWAGI, skad przyszla.
#   2. Samo pole ZOSTAJE W BAZIE - dostaje tylko widget `Hidden`, wiec znika
#      z formularza. Odwracalne jedna zmiana widgetu.
#
# NIC NIE GINIE. Gdyby przenoszenie sie nie udalo, pole NIE JEST ukrywane
# i modul mowi o tym wprost - ukryte i nieprzeniesione zdjecia znikalyby
# bez sladu. Plus `Wyposazenie` robi przedtem kopie `dane.gpkg`.
#
# IDEMPOTENCJA PO PARZE (rodzic, sciezka), nie po samym rodzicu: obiekt ma
# miec wiele zalacznikow, o to w tym wszystkim chodzi. Drugie uruchomienie
# nie robi drugiego wiersza z tym samym zdjeciem.
#
# ZAPIS PRZEZ API WARSTWY, nie przez sqlite3: warstwa-dziecko jest wczytana
# i trzyma wlasna pamiec podreczna. Dopisanie wierszy za jej plecami dawaloby
# galerie, ktora ich nie widzi az do przeladowania projektu.
#
# PROJEKTY JUZ WYPOSAZONE pokaza sie jako „starszy" (wersja 1 wobec 2)
# i dostana to jednym tapnieciem „Zaloz".
#
# SPRAWDZONE: proba6, 4 sekcje, 14 sprawdzen - dwie sciezki wedruja co do
# znaku, TYP i UWAGI ustawione, pole zostaje w bazie z wartosciami i dostaje
# Hidden, drugie uruchomienie nie dubluje, a wszystko PRZEZYWA ZAPIS
# I ODCZYT Z DYSKU. proba2..proba5 bez zmian.
#
# Uruchom w katalogu repo. Idempotentny; sprawdza sumy PRZED zapisem.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64, hashlib, json, os, sys, zlib
CALE = {}

CALE['src/core/moduly/zalaczniki.cpp'] = (['cf284d9eb9dfc31aa18483823e96102d'], '0d2fd11ef13991f741de291c34e3a9a7', """\
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""")

OPIS = json.loads(r"""
{
 "id": "zalaczniki",
 "nazwa": "Załączniki N:1 (multiodnośniki)",
 "wersja": 2,
 "rodzaj": "struktura",
 "gdzie": [
  "biuro",
  "teren"
 ],
 "odwracalny": false,
 "opis": "Tabele ZAL_<WARSTWA> w GeoPackage, relacje o sile kompozycji (ID_RODZICA → fid), galeria w formularzu i konwencja nazw plików zgodna z Mapit Spatial. Od wersji 2 stare pole ZDJECIE/FOTO jest PRZENOSZONE do tabeli jako pierwszy załącznik i znika z formularza — dwa aparaty pod sobą myliły.",
 "grunt": "docs/ZALACZNIKI.md; w terenie wykonuje to `ModulZalacznikow::zaloz` (src/core/moduly/zalaczniki.cpp), w biurze `skrypty/zaloz_zalaczniki.py` — jedna konwencja, dwie drogi. Idempotentny po parze (rodzic, ścieżka), więc drugie uruchomienie nie dubluje przeniesionych zdjęć. Pole ZDJECIE zostaje w bazie, dostaje tylko widget Hidden.",
 "skrypt": "skrypty/zaloz_zalaczniki.py",
 "kroki": [
  {
   "typ": "tabele_gpkg",
   "wzorzec": "ZAL_%"
  }
 ],
 "podpowiedz": "przeniesione zdjęcia mają w UWAGI adnotację, skąd przyszły; samo pole ZDJECIE zostaje w bazie i da się je odsłonić, zmieniając widget"
}
""")

KATALOG = 'wyposazenie/katalog.json'
MODUL = 'wyposazenie/moduly/zalaczniki/modul.json'

def czytaj(p):
    return open(p, encoding='utf-8').read()

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
        bledy.append('%s ma sume %s, a latka oczekuje: %s.\n'
                     '       NIE nadpisuje. Przyslij go PELNA SCIEZKA.'
                     % (cel, suma, ', '.join(przed)))
        continue
    doZapisu.append(cel)

# --- opis modulu: SCALAMY kluczami, zeby wlasne pola przezyly ----------
modulNowy = None
if not os.path.exists(MODUL):
    bledy.append('brak %s' % MODUL)
else:
    try:
        stary = json.loads(czytaj(MODUL))
    except ValueError as e:
        stary = None
        bledy.append('%s nie jest poprawnym JSON-em: %s' % (MODUL, e))
    if stary is not None:
        if stary.get('wersja') == OPIS['wersja']:
            juzZrobione.append('%s juz na wersji %d' % (MODUL, OPIS['wersja']))
        else:
            scalony = dict(stary)
            scalony.update(OPIS)
            modulNowy = scalony

katalogNowy = None
if not os.path.exists(KATALOG):
    bledy.append('brak %s' % KATALOG)
else:
    try:
        kat = json.loads(czytaj(KATALOG))
    except ValueError as e:
        kat = None
        bledy.append('%s nie jest poprawnym JSON-em: %s' % (KATALOG, e))
    if kat is not None:
        znaleziony = False
        zmiana = False
        for wpis in kat.get('moduly', []):
            if wpis.get('id') == 'zalaczniki':
                znaleziony = True
                if wpis.get('wersja') != OPIS['wersja']:
                    wpis['wersja'] = OPIS['wersja']
                    zmiana = True
        if not znaleziony:
            bledy.append('%s nie wymienia modulu „zalaczniki"' % KATALOG)
        elif zmiana:
            katalogNowy = kat
        else:
            juzZrobione.append('%s juz ma zalaczniki w wersji %d' % (KATALOG, OPIS['wersja']))

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

for opis in juzZrobione:
    print('  juz zrobione:', opis)

zmienione = 0
for cel in doZapisu:
    open(cel, 'wb').write(zlib.decompress(base64.b64decode(''.join(CALE[cel][2].split()))))
    print('  %-46s %s' % (cel, 'PODMIENIONY'))
    zmienione += 1
if modulNowy is not None:
    open(MODUL, 'w', encoding='utf-8').write(json.dumps(modulNowy, ensure_ascii=False, indent=2) + '\n')
    print('  %-46s %s' % (MODUL, 'wersja %d' % modulNowy['wersja']))
    zmienione += 1
if katalogNowy is not None:
    open(KATALOG, 'w', encoding='utf-8').write(json.dumps(katalogNowy, ensure_ascii=False, indent=2) + '\n')
    print('  %-46s %s' % (KATALOG, 'zalaczniki -> wersja 2'))
    zmienione += 1

print()
print('  zmienionych plikow: %d' % zmienione)
KONIEC_PY

echo
echo "Sprawdzenie na oko:"
echo "  grep -n 'przeniesStareZdjecia' src/core/moduly/zalaczniki.cpp | head -2"
echo "  grep -n 'wersja' wyposazenie/moduly/zalaczniki/modul.json"
echo
echo "Build:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 40"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh"
echo
echo "NA TELEFONIE - projekt Z ISTNIEJACYMI ZDJECIAMI w polu ZDJECIE:"
echo "  1. Wyposazenie: „Zalaczniki N:1” ma byc ZOLTY (wersja 1 wobec 2)."
echo "  2. Tapnij „Zaloz”. Komunikat ma podac LICZBE przeniesionych zdjec."
echo "  3. Otworz obiekt, ktory mial zdjecie: w formularzu NIE MA juz pola"
echo "     „ZDJECIE”, a w galerii „Zalaczniki” jest to zdjecie."
echo "  4. Obiekt bez zdjecia: galeria pusta, pola ZDJECIE tez nie ma."
