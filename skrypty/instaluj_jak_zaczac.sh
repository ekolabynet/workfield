#!/bin/bash
# WorkField 22.09.2026 - EKRAN „JAK ZACZAC?" PRZY PIERWSZYM URUCHOMIENIU.
#
# =====================================================================
#  CO TO JEST
# =====================================================================
#
# Tester dostaje APK na komunikator, instaluje, otwiera - i widzi puste
# okno oraz cztery zakladki. Wie, ze ma "sprawdzic CAD", ale nie wie,
# od czego zaczac. Ten ekran jest odpowiedzia na to jedno pytanie.
#
# To NIE jest instrukcja obslugi. To SPIS CZYNNOSCI: kazdy wiersz otwiera
# to miejsce, o ktorym mowi. "Warstwy" otwieraja szuflade warstw, a nie
# akapit o warstwach. Wiersz, ktory tylko opowiada, nie ma tu czego
# szukac - od opowiadania jest dokumentacja.
#
# =====================================================================
#  CO RUSZA (trzy pliki)
# =====================================================================
#
#   src/app/qml/QfJakZaczac.qml     - NOWY ekran
#   src/app/qml/CMakeLists.txt      - spis plikow QML
#   src/app/qml/QgisMobileapp.qml   - deklaracja + wyzwalacz pierwszego
#                                     uruchomienia
#
# Ekran NIE ZNA zadnych identyfikatorow z QgisMobileapp.qml - miejsca
# dostaje we wlasciwosciach, tak jak QfSekcjaModulow dostaje
# `szuflada: dataDrawer`. Dzieki temu da sie go obejrzec osobno - i zostal
# obejrzany, zanim tu trafil: piaskownia Qt, zrzut ekranu i syntetyczne
# tapniecia w trzy wiersze, kazde wywolalo swoja czynnosc.
#
# CZYNNOSCI SA PRAWDZIWE, nie zgadniete - wziete z kodu 22.09:
#   dashBoard.otworzSekcje(0 Zlecenia, 1 Projekt, 2 Warstwy, 3 Stylizacja)
#   dataDrawer.otworzZakladke(0 Moduly, 1 Narzedzia, 2 Algorytmy, 3 Ustawienia)
#   pluginManagerSettings.open(), oknoPodkladow.open()
#
# IKON NIE MA, swiadomie: nazwa ikony, ktorej nie ma w motywie, daje pusty
# kwadrat - a zgadywanie nazw kosztowalo nas juz jeden martwy przycisk
# (kategorie kolorow, sierpien).
#
# =====================================================================
#  KIEDY SIE POKAZUJE
# =====================================================================
#
#   - raz, przy pierwszym uruchomieniu po instalacji
#     (ustawienie `WorkField/jakZaczacPokazane`),
#   - pozniej tylko wtedy, gdy uzytkownik sam zaznaczy "Pokazuj przy
#     starcie" (`WorkField/jakZaczacPokazuj`).
#
# Pozycja w menu do ponownego otwarcia PRZYJDZIE OSOBNO - na koncu ten
# skrypt wypisuje kawalek QfMainDrawer.qml wokol "showPluginManager",
# zeby dolozyc ja tam, gdzie mieszkaja pozostale pozycje menu.
#
# Uruchom w katalogu repo (albo podaj go argumentem). Idempotentny.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
#!/usr/bin/env python3
# WorkField 22.09.2026 - ekran "Jak zaczac?".
#
# ZASADA, ktora ten skrypt respektuje (lekcja z 20.09, instaluj_cad_import.sh
# v1): NAJPIERW sprawdz WSZYSTKIE kotwice, POTEM zapisz. Instalator, ktory
# zapisal trzy pliki i wywrocil sie na czwartej kotwicy, zostawia repo
# w stanie, z ktorego nie ma wyjscia bez gita.
import base64, sys, zlib

QML = 'src/app/qml/QfJakZaczac.qml'
CMAKE = 'src/app/qml/CMakeLists.txt'
APP = 'src/app/qml/QgisMobileapp.qml'

EKRAN_B64 = """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"""


def czytaj(p):
    return open(p, encoding='utf-8').read()


try:
    cmake, app = czytaj(CMAKE), czytaj(APP)
except FileNotFoundError as e:
    print('BRAK pliku:', e)
    sys.exit(1)

if 'QfJakZaczac' in app:
    print('ekran "Jak zaczac?" juz jest')
    sys.exit(0)

bledy = []

# --- kotwica 1: spis plikow QML -------------------------------------
# Kotwica na QfImportCAD.qml, bo to najswiezszy wpis i wiadomo, ze jest
# (okno importu DXF dziala od 21.09).
k1 = '    QfImportCAD.qml\n'
if cmake.count(k1) != 1:
    bledy.append('CMakeLists: kotwica "QfImportCAD.qml" %d x (oczekiwano 1)' % cmake.count(k1))

# --- kotwica 2: miejsce deklaracji ----------------------------------
# Przed QfMainDrawer. Kolejnosc deklaracji w QML nie ma znaczenia dla
# wiazan po ID, wiec wystarczy ten sam zakres.
k2 = '  QfMainDrawer {\n    id: dashBoard\n'
if app.count(k2) != 1:
    bledy.append('QgisMobileapp: kotwica "QfMainDrawer/dashBoard" %d x (oczekiwano 1)' % app.count(k2))

# --- kotwica 3: czym zapisac ustawienie -----------------------------
# Checkbox "Pokazuj przy starcie" wola settings.setValue(). Gdyby tego
# czasownika tu nie bylo, ekran bylby klikalny i nieskuteczny - czyli
# dokladnie ten trzeci stan, ktorego w tym projekcie nie chcemy.
if 'settings.setValue(' not in app:
    bledy.append('QgisMobileapp: nie widze settings.setValue( - czym zapisac "Pokazuj przy starcie"?')

# --- kotwica 4: okna, ktore ekran otwiera ---------------------------
for ident, opis in (('id: dashBoard', 'lewa szuflada'),
                    ('id: dataDrawer', 'prawa szuflada'),
                    ('id: pluginManagerSettings', 'menedzer wtyczek'),
                    ('id: oknoPodkladow', 'okno podkladow')):
    if ident not in app:
        bledy.append('QgisMobileapp: brak "%s" (%s)' % (ident, opis))

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

# === liczymy w pamieci, zapisujemy na koncu =========================
doZapisu = {}
doZapisu[QML] = zlib.decompress(base64.b64decode(EKRAN_B64)).decode('utf-8')
doZapisu[CMAKE] = cmake.replace(k1, k1 + '    QfJakZaczac.qml\n', 1)

wstawka = '''  /**
   * WorkField 22.09.2026 - ekran pierwszego kontaktu.
   *
   * Miejsca, ktore otwiera, dostaje we wlasciwosciach, bo sam nie zna
   * zadnego z tych identyfikatorow - ma sie dac obejrzec osobno, bez
   * calej aplikacji.
   */
  QfJakZaczac {
    id: oknoJakZaczac
    szufladaLewa: dashBoard
    szufladaPrawa: dataDrawer
    oknoWtyczek: pluginManagerSettings
    podklady: oknoPodkladow
  }

  /**
   * Wyzwalacz pierwszego uruchomienia. Zwloka 1,2 s, zeby ekran powitalny
   * zdazyl sie ulozyc: okno modalne rzucone w trakcie skladania sceny
   * laduje pod nia albo miga.
   */
  Timer {
    id: wyzwalaczJakZaczac
    interval: 1200
    running: true
    repeat: false
    onTriggered: {
      const pokazane = settings.valueBool('WorkField/jakZaczacPokazane', false);
      const zawsze = settings.valueBool('WorkField/jakZaczacPokazuj', false);
      if (!pokazane || zawsze) {
        settings.setValue('WorkField/jakZaczacPokazane', true);
        oknoJakZaczac.open();
      }
    }
  }

'''
doZapisu[APP] = app.replace(k2, wstawka + k2, 1)

for sciezka, tresc in doZapisu.items():
    open(sciezka, 'w', encoding='utf-8').write(tresc)
    print(' ', sciezka, 'OK')

print()
print('Gotowe. Ekran pokaze sie przy najblizszym uruchomieniu aplikacji.')
print('Zeby zobaczyc go jeszcze raz: zaznacz "Pokazuj przy starcie" w jego stopce.')
KONIEC_PY

echo
echo "=============================================================="
echo "Do nastepnego kroku - pozycja w menu lewej szuflady."
echo "Kontekst wokol showPluginManager w QfMainDrawer.qml:"
echo "=============================================================="
grep -n "showPluginManager" src/app/qml/QfMainDrawer.qml | head -5
echo "---"
grep -n -B10 -A3 "showPluginManager()" src/app/qml/QfMainDrawer.qml | head -40
echo
echo "Przed budowaniem warto puscic sito:  bash skrypty/sito_qml.sh"
