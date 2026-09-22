#!/bin/bash
# WorkFieldGIS 22.09.2026 - NAZWA WIDOCZNA: WorkField -> WorkFieldGIS.
#
# W repo slowo „WorkField" wystepuje 543 razy i NIE WOLNO zamienic go
# wszedzie jednym `sed`. Trzy czwarte tych miejsc to nie nazwa programu,
# tylko IDENTYFIKATOR albo SCIEZKA - zamiana kazdego z nich to utrata
# danych albo ustawien u testerow. Podzial jest taki:
#
# ZMIENIAM (to, co uzytkownik CZYTA):
#   - naglowek lewej szuflady,
#   - „O aplikacji…", „Konto chmury…", „Teren — ustawienia…",
#   - opis OpenCamery w ustawieniach,
#   - temat maila w „Zglos uwage",
#   - `app_name` i ekran rozpakowywania w zasobach Androida — tam wciaz
#     stalo „QField", czyli nazwa CUDZEGO programu.
#
# NIE ZMIENIAM i to jest swiadome:
#   - 84 klucze ustawien `WorkField/...` oraz `WorkFieldPlantNet/...` —
#     zmiana = wyzerowanie WSZYSTKICH ustawien na kazdym telefonie;
#   - katalogi danych: `~/WorkField`, `Documents/WorkField`,
#     `WorkField/przychodzace`, `WorkField/Kopie` na chmurze,
#     `WorkField_kopie` na nosniku — projekty i kopie przestaly by byc
#     widoczne, a to sa czyjes dane z terenu;
#   - wpisy w plikach projektow (`readDoubleEntry("WorkField", …)`) i
#     metadane w bazach/ODS/spisach — czytaja je ISTNIEJACE pliki;
#   - napisy, ktore nazywaja te katalogi („Folder Documents/WorkField…") —
#     maja sie zgadzac z tym, co uzytkownik zobaczy w menedzerze plikow;
#   - 354 komentarze `// WorkField dd.mm.rrrr` — czysta kosmetyka, za to
#     ogromny diff, ktory zaciemnia `git blame`;
#   - `ch.opengis.qfield_home`, motyw `workfield`, prefiks ikon `wfg_`,
#     klucz podpisu `workfield` — zmiana identyfikatora pakietu zainstaluje
#     aplikacje OBOK starej, jako druga, i rozdzieli ustawienia.
#
# Nazwa w pasku aplikacji i pod ikona JUZ jest WorkFieldGIS: bierze sie
# z `APP_NAME` w CMakeLists.txt (`android:label="@APP_NAME@"`).
#
# Uruchom w katalogu repo. Idempotentny.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import os
import sys

# (plik, stare, nowe, opis)
ZAMIANY = [
    ('src/app/qml/QfMainDrawer.qml',
     '          text: qsTr("WorkField")\n',
     '          text: qsTr("WorkFieldGIS")\n',
     'naglowek lewej szuflady'),

    ('src/app/qml/QfMainDrawer.qml',
     'const temat = "WorkField " + appVersionStr',
     'const temat = "WorkFieldGIS " + appVersionStr',
     'temat maila w „Zglos uwage"'),

    ('src/app/qml/QfDataDrawer.qml',
     'qsTr("O aplikacji WorkField")',
     'qsTr("O aplikacji WorkFieldGIS")',
     'pozycja „O aplikacji"'),

    ('src/app/qml/QfCloudSettings.qml',
     'qsTr("Konto chmury WorkField")',
     'qsTr("Konto chmury WorkFieldGIS")',
     'ustawienia chmury'),

    ('src/app/qml/QfTerenSettings.qml',
     'qsTr("Teren — ustawienia WorkField")',
     'qsTr("Teren — ustawienia WorkFieldGIS")',
     'naglowek ustawien Terenu'),

    ('src/app/qml/QfSettings.qml',
     '— WorkField użyje OpenCamera',
     '— WorkFieldGIS użyje OpenCamera',
     'opis aparatu systemowego'),

    ('platform/android/res/values/strings.xml',
     '<string name="app_name" translatable="false">QField</string>',
     '<string name="app_name" translatable="false">WorkFieldGIS</string>',
     'app_name w zasobach Androida (stalo „QField")'),

    ('platform/android/res/values/strings.xml',
     '<string name="unpacking_title">QField is getting ready</string>',
     '<string name="unpacking_title">WorkFieldGIS is getting ready</string>',
     'ekran rozpakowywania, angielski'),

    ('platform/android/res/values-pl/strings.xml',
     '<string name="unpacking_title">QField za chwilę będzie gotowy</string>',
     '<string name="unpacking_title">WorkFieldGIS za chwilę będzie gotowy</string>',
     'ekran rozpakowywania, polski'),
]


def czytaj(p):
    return open(p, encoding='utf-8').read()


bledy = []
tresci = {}
doZrobienia = []
juzZrobione = []

# --- WSZYSTKO sprawdzone PRZED jakimkolwiek zapisem ------------------
for plik, stare, nowe, opis in ZAMIANY:
    if not os.path.exists(plik):
        bledy.append('brak pliku %s (%s)' % (plik, opis))
        continue
    if plik not in tresci:
        tresci[plik] = czytaj(plik)
    t = tresci[plik]
    ileStare = t.count(stare)
    ileNowe = t.count(nowe)
    if ileStare == 0 and ileNowe >= 1:
        juzZrobione.append(opis)
        continue
    if ileStare != 1:
        bledy.append('%s: „%s” wystepuje %d x (oczekiwano 1) — %s'
                     % (plik, stare.strip()[:60], ileStare, opis))
        continue
    doZrobienia.append((plik, stare, nowe, opis))

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

for opis in juzZrobione:
    print('  juz zmienione:', opis)

if not doZrobienia:
    print('  nic do roboty')
    sys.exit(0)

# --- zapis ------------------------------------------------------------
for plik, stare, nowe, opis in doZrobienia:
    tresci[plik] = tresci[plik].replace(stare, nowe, 1)

for plik in sorted({p for p, _, _, _ in doZrobienia}):
    open(plik, 'w', encoding='utf-8').write(tresci[plik])

for plik, stare, nowe, opis in doZrobienia:
    print('  %-52s %s' % (opis, 'OK'))

print()
print('  zmienione pliki: %d' % len({p for p, _, _, _ in doZrobienia}))
KONIEC_PY

echo
echo "Co ZOSTAJE ze slowem „WorkField” i dlaczego — do sprawdzenia na oko:"
echo "  klucze ustawien:   grep -rn 'WorkField/' --include=*.qml --include=*.cpp src/ | wc -l"
echo "  katalogi danych:   grep -rn '\"/WorkField\\|Documents/WorkField\\|WorkField_kopie' --include=*.qml --include=*.cpp src/"
echo "  komentarze:        grep -rn '// WorkField' --include=*.qml --include=*.cpp src/ | wc -l"
echo
echo "Osobno, poza aplikacja (do rozwazenia przy nastepnym wydaniu):"
echo "  - README.md i NOTICE.md — tam nazwa jest wizytowka repozytorium,"
echo "  - scripts/workfield-release.sh — tytul wydania „WorkField X.Y.Z”,"
echo "  - skrypty/przygotuj_apk.sh — nazwa pliku APK „WorkField-…apk”,"
echo "  - nazwa repozytorium na GitHubie (uwaga: adres wydan jest wpisany"
echo "    w qfchangelogcontents.cpp i w pozycji „Aktualizacja aplikacji”)."
