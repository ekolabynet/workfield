#!/bin/bash
# WorkField 21.09.2026 - MODUŁY NA PIERWSZĄ ZAKŁADKĘ PRAWEJ SZUFLADY.
#
# Moduły weszły 20.09 jako ZAKŁADKA CZWARTA - świadomie, na końcu, żeby nie
# ruszać numerów 0-2, bo numer zakładki jest w tym kodzie liczbą, a liczby
# siedzą w kilku miejscach naraz. Dziś to była dobra decyzja; dziś jest
# powód, żeby ją odwrócić: moduł to najkonkretniejsza rzecz w tej szufladzie
# - wchodzi się tam po to, żeby coś zrobić, a nie żeby coś obejrzeć.
#
# CAŁE RYZYKO TEJ ZMIANY TO NUMERY. Zakładka jest identyfikowana liczbą
# w co najmniej trzech miejscach:
#   - kolejność TabButtonów w QfDataDrawer.qml,
#   - kolejność stron w StackLayout tamże,
#   - tablica pozycji paska na komputerze w QfDesktopChrome.qml ("zakladka": n).
# ...a poza tym może być wołana skądkolwiek (`dataDrawer.otworz(2)`).
#
# Dlatego ten skrypt DOMYŚLNIE NIC NIE ZAPISUJE. Najpierw pokazuje:
#   1. jaką kolejność zakładek widzi teraz,
#   2. jaką zrobi,
#   3. KAŻDE miejsce w src/, gdzie widzi liczbę przy prawej szufladzie
#      - do przejrzenia okiem, bo tego nie da się rozstrzygnąć regułą.
#
# Numery w QfDesktopChrome przepisuje PO NAZWIE zakładki, nie po liczbie -
# czyli „Ustawienia" trafiają tam, gdzie po przestawieniu są Ustawienia,
# niezależnie od tego, jak się przesunęły.
#
#   bash zakladka_moduly_pierwsza.sh [katalog repo]              - pokaż
#   bash zakladka_moduly_pierwsza.sh [katalog repo] --wykonaj    - zapisz
set -e

REPO="/DATA/SOFT/GIS/QFIELD_Pro/QField"
WYKONAJ=0
for a in "$@"; do
  case "$a" in
    --wykonaj) WYKONAJ=1 ;;
    --*) echo "Nieznany przełącznik: $a"; exit 1 ;;
    *) REPO="$a" ;;
  esac
done
cd "$REPO"
[ -f src/app/qml/QfDataDrawer.qml ] || { echo "STOP: brak src/app/qml/QfDataDrawer.qml"; exit 1; }

WYKONAJ=$WYKONAJ python3 - <<'PYEOF'
#!/usr/bin/env python3
import os, re, sys, subprocess

wykonaj = os.environ.get('WYKONAJ') == '1'
QD = 'src/app/qml/QfDataDrawer.qml'
QC = 'src/app/qml/QfDesktopChrome.qml'
ZNACZNIK = 'QfSekcjaModulow'


def czytaj(p):
    return open(p, encoding='utf-8').read()


def za_klamra(s, p):
    """Koniec bloku (za zamykajaca klamra), z pominieciem napisow i komentarzy."""
    j = s.index('{', p) + 1
    gl, instr = 1, None
    while gl:
        ch = s[j]
        if instr:
            if ch == '\\':
                j += 2
                continue
            if ch == instr:
                instr = None
        elif ch in '"\'':
            instr = ch
        elif ch == '/' and s[j + 1] == '/':
            j = s.index('\n', j)
            continue
        elif ch == '{':
            gl += 1
        elif ch == '}':
            gl -= 1
        j += 1
    return j


def poczatek_wiersza(s, p):
    return s.rfind('\n', 0, p) + 1


def z_komentarzem(s, p):
    """Cofa sie nad przylegajace wiersze komentarza - naleza do bloku."""
    p = poczatek_wiersza(s, p)
    while True:
        poprz = s.rfind('\n', 0, p - 1) + 1
        if poprz >= p:
            break
        wiersz = s[poprz:p].strip()
        if wiersz.startswith('//'):
            p = poprz
        else:
            break
    return p


qd = czytaj(QD)

# === 1. pasek zakladek ===============================================
blok = None
for m in re.finditer(r'\bTabBar\s*\{', qd):
    k = za_klamra(qd, m.start())
    if ZNACZNIK in qd[m.start():k] or 'Moduły' in qd[m.start():k]:
        blok = (m.start(), k)
        break
if not blok:
    print('KOTWICA NIE PASUJE: nie widzę TabBara z zakładką Modułów')
    sys.exit(1)

guziki = []
i = blok[0]
while True:
    m = re.compile(r'\bTabButton\s*\{').search(qd, i, blok[1])
    if not m:
        break
    k = za_klamra(qd, m.start())
    a = z_komentarzem(qd, m.start())
    b = qd.index('\n', k) + 1
    tekst = re.search(r'text:\s*qsTr\("([^"]+)"\)', qd[m.start():k])
    guziki.append((a, b, tekst.group(1) if tekst else '?'))
    i = k

nazwy = [g[2] for g in guziki]
print('== zakładki prawej szuflady, jak są teraz:')
for n, nazwa in enumerate(nazwy):
    print('   %d. %s' % (n, nazwa))

gdzie = next((n for n, x in enumerate(nazwy) if 'Modu' in x), None)
if gdzie is None:
    print('STOP: nie znalazłem zakładki „Moduły" w pasku')
    sys.exit(1)
if gdzie == 0:
    print('\nModuły już są pierwsze. Nic do roboty.')
    sys.exit(0)

nowe_nazwy = [nazwy[gdzie]] + [x for n, x in enumerate(nazwy) if n != gdzie]
print('\n== po zmianie:')
for n, nazwa in enumerate(nowe_nazwy):
    print('   %d. %s' % (n, nazwa))

a, b, _ = guziki[gdzie]
kawalek = qd[a:b]
nowy_qd = qd[:a] + qd[b:]
przesun = guziki[0][0]
nowy_qd = nowy_qd[:przesun] + kawalek + nowy_qd[przesun:]

# === 2. strony StackLayoutu ==========================================
blokS = None
for m in re.finditer(r'\bStackLayout\s*\{', nowy_qd):
    k = za_klamra(nowy_qd, m.start())
    if ZNACZNIK in nowy_qd[m.start():k]:
        blokS = (m.start(), k)
        break
if not blokS:
    print('KOTWICA NIE PASUJE: nie widzę StackLayoutu ze stroną modułów')
    sys.exit(1)

# Dzieci StackLayoutu: pierwszy poziom zagniezdzenia, tylko te, ktore
# zaczynaja sie od nazwy komponentu (wielka litera) - wlasciwosci
# (`id:`, `Layout.`) odpadaja same.
ciało_od = nowy_qd.index('{', blokS[0]) + 1
strony = []
i = ciało_od
while i < blokS[1] - 1:
    m = re.compile(r'\n(\s*)([A-Z]\w*)\s*\{').search(nowy_qd, i, blokS[1])
    if not m:
        break
    k = za_klamra(nowy_qd, m.start(2))
    a2 = z_komentarzem(nowy_qd, m.start(2))
    b2 = nowy_qd.index('\n', k) + 1
    strony.append((a2, b2, m.group(2)))
    i = k

print('\n== strony w StackLayoucie: %s' % ', '.join(s[2] for s in strony))
if len(strony) != len(nazwy):
    print('   UWAGA: %d stron przy %d zakładkach — przejrzyj plik ręcznie,'
          % (len(strony), len(nazwy)))
    print('   bo dopasowanie zakładka↔strona idzie po kolejności.')

gdzieS = next((n for n, s in enumerate(strony) if s[2] == ZNACZNIK), None)
if gdzieS is None:
    print('STOP: nie widzę strony %s' % ZNACZNIK)
    sys.exit(1)

a2, b2, _ = strony[gdzieS]
kawalek2 = nowy_qd[a2:b2]
nowy_qd = nowy_qd[:a2] + nowy_qd[b2:]
przesun2 = strony[0][0]
nowy_qd = nowy_qd[:przesun2] + kawalek2 + nowy_qd[przesun2:]

# Numerki w komentarzach `// ── Nazwa (n) ──` na nowo, zeby plik nie klamal.
licznik = [0]


def przenumeruj(m):
    n = licznik[0]
    licznik[0] += 1
    return '%s(%d)%s' % (m.group(1), n, m.group(3))


nowy_qd = re.sub(r'(// ── [^\n(]*)\((\d+)\)([^\n]*──)', przenumeruj, nowy_qd)

# === 3. pasek na komputerze ==========================================
zmiany_qc = None
if os.path.exists(QC):
    qc = czytaj(QC)
    mapa = {n: i for i, n in enumerate(nowe_nazwy)}

    def popraw(m):
        nazwa, reszta, stary = m.group(1), m.group(2), int(m.group(3))
        nowy = mapa.get(nazwa)
        if nowy is None:
            print('   ! „%s" w pasku komputera nie pasuje do żadnej zakładki '
                  '— zostawiam %d' % (nazwa, stary))
            return m.group(0)
        if nowy != stary:
            print('   %-14s %d → %d' % (nazwa, stary, nowy))
        return '"nazwa": qsTr("%s")%s"zakladka": %d' % (nazwa, reszta, nowy)

    print('\n== pasek na komputerze (%s):' % QC)
    nowy_qc, ile = re.subn(
        r'"nazwa":\s*qsTr\("([^"]+)"\)(.*?)"zakladka":\s*(\d+)', popraw, qc, flags=re.S)
    if ile == 0:
        print('   (nie widzę wpisów "zakladka" — pomijam)')
    else:
        zmiany_qc = nowy_qc

# === 4. co jeszcze może liczyć na numerach ===========================
print('\n== miejsca, które mogą trzymać numer zakładki — do przejrzenia:')
try:
    out = subprocess.run(
        ['grep', '-rn', '-E', r'(dataDrawer|drawerStack).*[0-9]',
         'src/app/qml', 'src/core'],
        capture_output=True, text=True).stdout.strip()
except Exception:
    out = ''
linie = [w for w in out.splitlines()
         if not w.startswith(QD + ':')
         and ('currentIndex' in w or 'otworz' in w
              or re.search(r'(dataDrawer|drawerStack)\w*\s*[=(]\s*\d', w))]
if linie:
    for w in linie[:40]:
        print('   ' + w[:150])
    print('   — jeśli któraś z tych liczb znaczy „która zakładka", popraw ją ręcznie.')
else:
    print('   (nic podejrzanego)')

# === zapis ===========================================================
if not wykonaj:
    print('\nNIC NIE ZAPISANE. Jeśli powyższe się zgadza, uruchom z --wykonaj.')
    sys.exit(0)

open(QD, 'w', encoding='utf-8').write(nowy_qd)
print('\n%s OK' % QD)
if zmiany_qc:
    open(QC, 'w', encoding='utf-8').write(zmiany_qc)
    print('%s OK' % QC)
print('Gotowe: Moduły pierwsze. Zbuduj i sprawdź, którą zakładkę otwiera')
print('szuflada po starcie — jeśli otwiera Moduły, a wolisz co innego,')
print('to jest `currentIndex` TabBara, jedna linia.')
PYEOF
