#!/bin/bash
# WorkFieldGIS 22.09.2026 - ZALACZNIKI N:1 ("MULTIODNOSNIKI") W TERENIE.
#
# CO TO ZMIENIA
# -------------
# Do dzis obiekt niosl JEDNO zdjecie w polu FOTO/ZDJECIE. Modul "zalaczniki"
# byl w katalogu wyposazenia od 21.09, mial opis, wersje, stempel i przycisk
# w oknie Wyposazenia — ale przycisk byl NIECZYNNY, bo modul mial
# `"gdzie": ["biuro"]`. Aplikacja uczciwie odmawiala:
#
#     krok "tabele_gpkg" wykonuje tylko biuro
#
# Powod byl konkretny: `Wyposazenie::wykonajKrok()` obslugiwal trzy typy
# krokow z siedmiu, a ten modul ma jeden krok typu `tabele_gpkg` — pisanie
# do wnetrza `dane.gpkg`. Ta latka jest tym krokiem.
#
# Przepis nie jest nowy: `skrypty/zaloz_zalaczniki.py` robi to samo w biurze,
# w konsoli QGIS-a, od 21.09. Nowy jest tylko SPOSOB WYKONANIA — w C++, bez
# PyQGIS, czyli takze na telefonie. Nazwy tabel, pol, relacji i identyfikatorow
# sa CELOWO identyczne, wiec uruchomienie jednej drogi na projekcie zrobionym
# druga NICZEGO NIE DUBLUJE.
#
# CO WCHODZI
# ----------
#   NOWE:
#     src/core/moduly/zalaczniki.{h,cpp}  czasownik: tabela ZAL_<WARSTWA>,
#                                         relacja o sile kompozycji, galeria
#                                         w formularzu, konwencja nazw plikow
#     docs/ZALACZNIKI.md                  plik, na ktory powolywaly sie trzy
#                                         miejsca w kodzie, a ktorego nie bylo
#   ZMIENIONE:
#     wyposazenie/moduly/zalaczniki/modul.json   "gdzie": +"teren"
#     src/core/wyposazenie.{h,cpp}               wszczepienie kroku, kopia BAZY,
#                                                przyczyna niepowodzenia kroku
#     src/core/CMakeLists.txt                    rejestracja nowych plikow
#     skrypty/zaloz_zalaczniki.py                ta sama regula nazw co w C++
#     src/app/qml/QgisMobileapp.qml              „Poligony (hatch)" -> „Poligony"
#     src/app/qml/QfProjektZCAD.qml              to samo w opisie kreatora
#
# DWIE RZECZY ZNALEZIONE PRZEZ PROBY, NIE PRZEZ CZYTANIE
# ------------------------------------------------------
# 1. Stara regula nazw robila z warstwy „Poligony (hatch)" tabele
#    `ZAL_POLIGONY (HATCH)` — ze spacja i nawiasami w nazwie tabeli
#    GeoPackage. Dziala, bo SQLite przelyka cudzyslowy, ale gryzloby przy
#    kazdym recznym SQL-u. Nazwy sa teraz sprowadzane do [A-Z0-9_],
#    w C++ I w skrypcie biurowym. Kreator nazywa te warstwe po prostu
#    „Poligony" — klopot usuniety u zrodla (uwaga Piotra, 22.09).
#
# 2. `QFile::copy` ODMAWIA, gdy plik docelowy juz istnieje, a znacznik kopii
#    ma rozdzielczosc jednej sekundy. Dwa moduly zalozone w tej samej
#    sekundzie — albo ten sam dwa razy — konczyly sie komunikatem
#    "Nie udalo sie zrobic kopii projektu", ktory brzmi jak awaria dysku,
#    a znaczy "kopia juz jest". Bylo tak w `zaloz()` I w `zdejmij()`.
#
# SPRAWDZONE PRZED WYSLANIEM (piaskownica, QGIS 3.34.4, 65 sprawdzen)
# -------------------------------------------------------------------
#   - projekt zapisany, WCZYTANY OD NOWA i zapytany przez
#     `ZalacznikiUtils::relacjaZalacznikow` — te sama funkcje, ktora pasek
#     nawigacji pyta, czy pokazac aparat;
#   - idempotencja: drugie uruchomienie = zero nowych tabel, zero relacji;
#   - nazwy tabel bez spacji, nawiasow i ogonkow;
#   - pole ZDJECIE nietkniete;
#   - cala droga przez `Wyposazenie::zaloz()`: odmowa przed latka, zgoda po,
#     kopia projektu I bazy na dysku, stempel zgodny, odmowa przy otwartej
#     edycji z nazwa warstwy w komunikacie.
#
# CZEGO NIE ROBI: nie rusza pol FOTO/ZDJECIE i nie migruje starych zdjec
# do tabel — to osobna operacja magazynowa.
#
# Uruchom w katalogu repo. Idempotentny; sprawdza WSZYSTKIE kotwice przed
# jakimkolwiek zapisem.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64
import json
import os
import sys
import zlib

NOWE = {}

NOWE['src/core/moduly/zalaczniki.h'] = """\
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
yG7nlcxjteZZz9yA/wPa8rlg"""
NOWE['src/core/moduly/zalaczniki.cpp'] = """\
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
nosnd3FdWUO1luF/Afup4lc="""
NOWE['docs/ZALACZNIKI.md'] = """\
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
7ujTYPEVDrd7YC1PFrh256qtMtd/XQv+BwC0ZCc="""


# ==========================================================================
# ZMIANY W ISTNIEJACYCH PLIKACH — (plik, stare, nowe, opis)
# ==========================================================================
ZAMIANY = []

# --- CMakeLists: rejestracja nowych plikow -------------------------------
ZAMIANY.append((
    'src/core/CMakeLists.txt',
    '    moduly/dxfinwentaryzacja.cpp\n    moduly/inwentaryzacjadrzew.cpp\n',
    '    moduly/dxfinwentaryzacja.cpp\n    moduly/inwentaryzacjadrzew.cpp\n    moduly/zalaczniki.cpp\n',
    'CMakeLists: zalaczniki.cpp'))
ZAMIANY.append((
    'src/core/CMakeLists.txt',
    '    moduly/dxfinwentaryzacja.h\n    moduly/inwentaryzacjadrzew.h\n',
    '    moduly/dxfinwentaryzacja.h\n    moduly/inwentaryzacjadrzew.h\n    moduly/zalaczniki.h\n',
    'CMakeLists: zalaczniki.h'))

# --- wyposazenie.h: przyczyna niepowodzenia kroku wychodzi na zewnatrz ---
ZAMIANY.append((
    'src/core/wyposazenie.h',
    '    QString wykonajKrok( QgsProject *projekt, const QJsonObject &krok ) const;',
    '    //! \\a powod (gdy podany) dostaje przyczyne niepowodzenia — bez tego\n'
    '    //! awaria kroku wyglada tak samo jak kazda inna i nie da sie jej\n'
    '    //! zdiagnozowac z telefonu.\n'
    '    QString wykonajKrok( QgsProject *projekt, const QJsonObject &krok,\n'
    '                         QString *powod = nullptr ) const;',
    'wyposazenie.h: wykonajKrok z powodem'))

# --- wyposazenie.cpp: include -------------------------------------------
ZAMIANY.append((
    'src/core/wyposazenie.cpp',
    '#include "wyposazenie.h"\n',
    '#include "wyposazenie.h"\n\n#include "moduly/zalaczniki.h"\n',
    'wyposazenie.cpp: include'))

# --- wyposazenie.cpp: umiemyKrok ----------------------------------------
ZAMIANY.append((
    'src/core/wyposazenie.cpp',
    '//! Typy krokow, ktore da sie COFNAC. Reszta = modul nieodwracalny.\n'
    'static const QStringList COFAMY = {\n'
    '  QStringLiteral( "wlasciwosc" ),\n'
    '  QStringLiteral( "wlasciwosc_warstwy" )\n'
    '};\n',
    '//! Typy krokow, ktore da sie COFNAC. Reszta = modul nieodwracalny.\n'
    'static const QStringList COFAMY = {\n'
    '  QStringLiteral( "wlasciwosc" ),\n'
    '  QStringLiteral( "wlasciwosc_warstwy" )\n'
    '};\n'
    '\n'
    '/**\n'
    ' * Czy aplikacja umie wykonac TEN krok — po tresci, nie po samym typie.\n'
    ' *\n'
    ' * `tabele_gpkg` to nie jeden krok, tylko RODZINA krokow: po jednym na\n'
    ' * rodzaj tabel, rozroznianych wzorcem nazwy. Wpisanie calego typu do\n'
    ' * `UMIEMY` byloby obietnica, ze umiemy zalozyc kazde tabele, jakie\n'
    ' * katalog kiedykolwiek wymysli — a umiemy dokladnie jedne.\n'
    ' */\n'
    'static bool umiemyKrok( const QJsonObject &krok )\n'
    '{\n'
    '  const QString typ = krok.value( QStringLiteral( "typ" ) ).toString();\n'
    '  if ( UMIEMY.contains( typ ) )\n'
    '    return true;\n'
    '  if ( typ == QLatin1String( "tabele_gpkg" ) )\n'
    '    return krok.value( QStringLiteral( "wzorzec" ) ).toString() == QLatin1String( "ZAL_%" );\n'
    '  return false;\n'
    '}\n',
    'wyposazenie.cpp: umiemyKrok'))

# --- wyposazenie.cpp: mozeZalozyc pyta o tresc kroku --------------------
ZAMIANY.append((
    'src/core/wyposazenie.cpp',
    '    if ( !UMIEMY.contains( typ ) )\n'
    '      return tr( "krok \\"%1\\" wykonuje tylko biuro" ).arg( typ );',
    '    if ( !umiemyKrok( k.toObject() ) )\n'
    '      return tr( "krok \\"%1\\" wykonuje tylko biuro" ).arg( typ );',
    'wyposazenie.cpp: mozeZalozyc'))

# --- wyposazenie.cpp: wykonajKrok — sygnatura i obsluga kroku ----------
ZAMIANY.append((
    'src/core/wyposazenie.cpp',
    'QString Wyposazenie::wykonajKrok( QgsProject *projekt, const QJsonObject &krok ) const\n'
    '{\n'
    '  const QString typ = krok.value( QStringLiteral( "typ" ) ).toString();\n'
    '  const QString grupa = krok.value( QStringLiteral( "grupa" ) ).toString();\n'
    '  const QString klucz = krok.value( QStringLiteral( "klucz" ) ).toString();\n',
    'QString Wyposazenie::wykonajKrok( QgsProject *projekt, const QJsonObject &krok,\n'
    '                                  QString *powod ) const\n'
    '{\n'
    '  const QString typ = krok.value( QStringLiteral( "typ" ) ).toString();\n'
    '  const QString grupa = krok.value( QStringLiteral( "grupa" ) ).toString();\n'
    '  const QString klucz = krok.value( QStringLiteral( "klucz" ) ).toString();\n'
    '\n'
    '  if ( typ == QLatin1String( "tabele_gpkg" ) )\n'
    '  {\n'
    '    if ( krok.value( QStringLiteral( "wzorzec" ) ).toString() != QLatin1String( "ZAL_%" ) )\n'
    '    {\n'
    '      if ( powod )\n'
    '        *powod = tr( "nie umiem zakladac tabel \\"%1\\"" )\n'
    '                   .arg( krok.value( QStringLiteral( "wzorzec" ) ).toString() );\n'
    '      return QString();\n'
    '    }\n'
    '    const ModulZalacznikow::Wynik z = ModulZalacznikow::zaloz( projekt );\n'
    '    if ( !z.ok )\n'
    '    {\n'
    '      if ( powod )\n'
    '        *powod = z.opis;\n'
    '      return QString();\n'
    '    }\n'
    '    return z.opis;\n'
    '  }\n',
    'wyposazenie.cpp: wykonajKrok obsluguje tabele_gpkg'))

# --- wyposazenie.cpp: kopia BAZY + przyczyna niepowodzenia --------------
ZAMIANY.append((
    'src/core/wyposazenie.cpp',
    '  const QJsonObject m = opisModulu( modul );\n'
    '  QStringList zrobione;\n'
    '  for ( const QJsonValue &k : m.value( QStringLiteral( "kroki" ) ).toArray() )\n'
    '  {\n'
    '    const QString opis = wykonajKrok( projekt, k.toObject() );\n'
    '    if ( opis.isEmpty() )\n'
    '    {\n'
    '      w[QStringLiteral( "opis" )] =\n'
    '        tr( "Krok sie nie powiodl — projekt NIE zapisany, kopia: %1" ).arg( kopia );\n'
    '      return w;\n'
    '    }',
    '  const QJsonObject m = opisModulu( modul );\n'
    '\n'
    '  // KOPIA BAZY, nie tylko projektu. Do 22.09.2026 kopiowalismy sam\n'
    '  // `projekt.qgs` — i bylo to wystarczajace, bo wszystkie umiane kroki\n'
    '  // dotykaly wylacznie ustawien projektu. `tabele_gpkg` pisze do\n'
    '  // `dane.gpkg`, w ktorym leza dane z terenu, a modul jest NIEODWRACALNY.\n'
    '  // Bez tej kopii slowo "nieodwracalny" znaczyloby naprawde nieodwracalny.\n'
    '  QStringList doKopii;\n'
    '  for ( const QJsonValue &k : m.value( QStringLiteral( "kroki" ) ).toArray() )\n'
    '  {\n'
    '    if ( k.toObject().value( QStringLiteral( "typ" ) ).toString() != QLatin1String( "tabele_gpkg" ) )\n'
    '      continue;\n'
    '    const QStringList b = ModulZalacznikow::bazy( projekt );\n'
    '    for ( const QString &p : b )\n'
    '    {\n'
    '      if ( !doKopii.contains( p ) )\n'
    '        doKopii << p;\n'
    '    }\n'
    '  }\n'
    '  QStringList kopieBaz;\n'
    '  for ( const QString &p : doKopii )\n'
    '  {\n'
    '    const QString cel = p + QStringLiteral( ".przed_" ) + znacznik;\n'
    '    if ( !QFile::exists( cel ) && !QFile::copy( p, cel ) )\n'
    '    {\n'
    '      w[QStringLiteral( "opis" )] =\n'
    '        tr( "Nie udalo sie zrobic kopii bazy %1 — nic nie zmieniam." ).arg( QFileInfo( p ).fileName() );\n'
    '      return w;\n'
    '    }\n'
    '    kopieBaz << cel;\n'
    '  }\n'
    '  if ( !kopieBaz.isEmpty() )\n'
    '    w[QStringLiteral( "kopiaBazy" )] = kopieBaz.join( QStringLiteral( ", " ) );\n'
    '\n'
    '  QStringList zrobione;\n'
    '  for ( const QJsonValue &k : m.value( QStringLiteral( "kroki" ) ).toArray() )\n'
    '  {\n'
    '    QString powod;\n'
    '    const QString opis = wykonajKrok( projekt, k.toObject(), &powod );\n'
    '    if ( opis.isEmpty() )\n'
    '    {\n'
    '      // Przyczyna, a nie sama porazka: "nie ma czego pokazac" i "nie udalo\n'
    '      // sie zrobic" to dwa rozne komunikaty (zasada z modulu CAD).\n'
    '      w[QStringLiteral( "opis" )] =\n'
    '        powod.isEmpty()\n'
    '          ? tr( "Krok sie nie powiodl — projekt NIE zapisany, kopia: %1" ).arg( kopia )\n'
    '          : tr( "%1 Projekt NIE zapisany, kopia: %2" ).arg( powod, kopia );\n'
    '      return w;\n'
    '    }',
    'wyposazenie.cpp: kopia bazy i przyczyna niepowodzenia'))

# --- QML: nazwa warstwy poligonow ---------------------------------------
ZAMIANY.append((
    'src/app/qml/QgisMobileapp.qml',
    '   * Nazwy po polsku i po CADowemu — "Poligony (hatch)", bo projektant\n'
    '   * tak nazywa obszary, a nie "powierzchnie".\n',
    '   * Nazwy po polsku i po CADowemu. „Poligony" bez dopisku "(hatch)":\n'
    '   * nawiasy w nazwie warstwy wchodza potem w nazwe tabeli zalacznikow\n'
    '   * (ZAL_<WARSTWA>), a tabela GeoPackage ze spacja i nawiasami gryzie\n'
    '   * przy kazdym recznym SQL-u. Uwaga Piotra, 22.09.2026.\n',
    'QgisMobileapp: komentarz o nazwach warstw'))
ZAMIANY.append((
    'src/app/qml/QgisMobileapp.qml',
    '      { "nazwa": qsTr("Poligony (hatch)"), "typ": "Polygon" }',
    '      { "nazwa": qsTr("Poligony"), "typ": "Polygon" }',
    'QgisMobileapp: warstwa „Poligony"'))
ZAMIANY.append((
    'src/app/qml/QfProjektZCAD.qml',
    'punkty, linie i poligony (hatch) — każda z opisem',
    'punkty, linie i poligony — każda z opisem',
    'QfProjektZCAD: opis kreatora'))

# --- skrypt biurowy: ta sama regula nazw co w C++ -----------------------
ZAMIANY.append((
    'skrypty/zaloz_zalaczniki.py',
    "def bez_ogonkow(tekst):\n    return tekst.translate(ASCII)\n",
    "def bez_ogonkow(tekst):\n    return tekst.translate(ASCII)\n"
    "\n"
    "\n"
    "def czyste_miano(tekst):\n"
    "    \"\"\"Nazwa warstwy sprowadzona do tego, co wolno wpisac w nazwe tabeli.\n"
    "\n"
    "    ZNALEZIONE 22.09.2026: kreator „Projekt z DXF\" zakladal warstwe nazwana\n"
    "    „Poligony (hatch)\", a stara regula (sam `bez_ogonkow` i `.upper()`)\n"
    "    robila z niej tabele `ZAL_POLIGONY (HATCH)` — ze spacja i nawiasami.\n"
    "    SQLite to przelyka w cudzyslowach i wszystko dziala, ale taka nazwa\n"
    "    gryzie przy kazdym recznym SQL-u, przy eksporcie i w cudzych\n"
    "    narzedziach, a indeks nazywa sie wtedy `idx_ZAL_POLIGONY (HATCH)_rodzic`.\n"
    "\n"
    "    Ta sama regula siedzi w `src/core/moduly/zalaczniki.cpp` (czysteMiano).\n"
    "    Zmieniajac tu, zmienic tam — rozjazd nie objawi sie bledem, tylko\n"
    "    druga tabela obok pelnej zdjec.\n"
    "    \"\"\"\n"
    "    out = []\n"
    "    for z in bez_ogonkow(tekst):\n"
    "        if z.isascii() and z.isalnum():\n"
    "            out.append(z)\n"
    "        elif out and out[-1] != '_':\n"
    "            out.append('_')\n"
    "    return ''.join(out).strip('_') or 'WARSTWA'\n",
    'zaloz_zalaczniki.py: czyste_miano'))
ZAMIANY.append((
    'skrypty/zaloz_zalaczniki.py',
    "        tabela = PREFIKS_TABELI + bez_ogonkow(nazwa).upper()\n",
    "        tabela = PREFIKS_TABELI + czyste_miano(nazwa).upper()\n"
    "        # ZGODNOSC WSTECZ: projekt wyposazony starsza regula ma tabele pod\n"
    "        # nazwa nieoczyszczona. Jesli taka jest, uzywamy JEJ — inaczej\n"
    "        # powstalaby druga tabela obok pelnej zdjec.\n"
    "        tabela_stara = PREFIKS_TABELI + bez_ogonkow(nazwa).upper()\n"
    "        if (tabela_stara != tabela and not _tabela_istnieje(gpkg, tabela)\n"
    "                and _tabela_istnieje(gpkg, tabela_stara)):\n"
    "            tabela = tabela_stara\n",
    'zaloz_zalaczniki.py: nazwa tabeli'))
ZAMIANY.append((
    'skrypty/zaloz_zalaczniki.py',
    "        rel_id = 'zal_' + nazwa\n",
    "        rel_id = 'zal_' + czyste_miano(nazwa)\n"
    "        rel_id_stary = 'zal_' + nazwa\n"
    "        if rel_id_stary != rel_id:\n"
    "            _stara = proj.relationManager().relation(rel_id_stary)\n"
    "            _nowa = proj.relationManager().relation(rel_id)\n"
    "            if (_stara is not None and _stara.isValid()\n"
    "                    and (_nowa is None or not _nowa.isValid())):\n"
    "                rel_id = rel_id_stary\n",
    'zaloz_zalaczniki.py: identyfikator relacji'))

MODUL = 'wyposazenie/moduly/zalaczniki/modul.json'


def czytaj(p):
    return open(p, encoding='utf-8').read()


bledy = []
tresci = {}
doZrobienia = []
juzZrobione = []

# --- WSZYSTKO sprawdzone PRZED jakimkolwiek zapisem --------------------
for plik, stare, nowe, opis in ZAMIANY:
    if not os.path.exists(plik):
        bledy.append('brak pliku %s (%s)' % (plik, opis))
        continue
    if plik not in tresci:
        tresci[plik] = czytaj(plik)
    t = tresci[plik]
    # „Juz zrobione” poznajemy po NOWYM tekscie, nie po braku starego.
    # Polowa tych zamian DOPISUJE po kotwicy, wiec kotwica zostaje w pliku
    # takze po udanym zapisie — pytanie „czy stare zniknelo” dawalo wtedy
    # odpowiedz „nie” i drugie uruchomienie dokladalo wszystko jeszcze raz.
    # Zlapane proba idempotencji 22.09.2026: `umiemyKrok` wyszedl
    # zdefiniowany dwa razy, czyli kod, ktory by sie nie skompilowal.
    if t.count(nowe) >= 1:
        juzZrobione.append(opis)
        continue
    if t.count(stare) != 1:
        bledy.append('%s: kotwica „%s...” wystepuje %d x (oczekiwano 1) — %s'
                     % (plik, stare.strip()[:50], t.count(stare), opis))
        continue
    doZrobienia.append((plik, stare, nowe, opis))

# --- modul.json: sprawdzenie ------------------------------------------
modulDoZmiany = False
if not os.path.exists(MODUL):
    bledy.append('brak %s' % MODUL)
else:
    try:
        opisModulu = json.loads(czytaj(MODUL))
    except ValueError as e:
        opisModulu = None
        bledy.append('%s nie jest poprawnym JSON-em: %s' % (MODUL, e))
    if opisModulu is not None:
        if 'teren' in opisModulu.get('gdzie', []):
            juzZrobione.append('modul.json: „teren” juz jest')
        else:
            modulDoZmiany = True

# --- nowe pliki: sprawdzenie katalogow ---------------------------------
nowePliki = []
for cel in NOWE:
    kat = os.path.dirname(cel)
    if kat and not os.path.isdir(kat):
        bledy.append('nie ma katalogu %s (dla %s)' % (kat, cel))
        continue
    nowePliki.append(cel)

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

for opis in juzZrobione:
    print('  juz zrobione:', opis)

# --- ZAPIS -------------------------------------------------------------
for cel in nowePliki:
    tresc = zlib.decompress(base64.b64decode(''.join(NOWE[cel].split())))
    stara = open(cel, 'rb').read() if os.path.exists(cel) else None
    if stara == tresc:
        print('  bez zmian:   %s' % cel)
        continue
    open(cel, 'wb').write(tresc)
    print('  %-42s %s' % (cel, 'nadpisany' if stara is not None else 'NOWY'))

for plik, stare, nowe, opis in doZrobienia:
    tresci[plik] = tresci[plik].replace(stare, nowe, 1)
for plik in sorted({p for p, _, _, _ in doZrobienia}):
    open(plik, 'w', encoding='utf-8').write(tresci[plik])
for plik, stare, nowe, opis in doZrobienia:
    print('  %-42s %s' % (opis, 'OK'))

if modulDoZmiany:
    opisModulu['gdzie'] = ['biuro', 'teren']
    opisModulu['grunt'] = (
        'docs/ZALACZNIKI.md; w terenie wykonuje to `ModulZalacznikow::zaloz` '
        '(src/core/moduly/zalaczniki.cpp), w biurze `skrypty/zaloz_zalaczniki.py` '
        '— jedna konwencja, dwie drogi. Idempotentny; nie rusza istniejących pól FOTO.')
    open(MODUL, 'w', encoding='utf-8').write(
        json.dumps(opisModulu, ensure_ascii=False, indent=2) + '\n')
    print('  %-42s %s' % ('modul.json: „gdzie” = biuro + teren', 'OK'))

print()
print('  zmienionych plikow: %d' % (len({p for p, _, _, _ in doZrobienia})
                                    + (1 if modulDoZmiany else 0)))
KONIEC_PY

echo
echo "Sprawdzenie na oko:"
echo "  grep -n 'teren' wyposazenie/moduly/zalaczniki/modul.json"
echo "  grep -n 'zalaczniki' src/core/CMakeLists.txt"
echo "  grep -n 'tabele_gpkg' src/core/wyposazenie.cpp"
echo "  grep -n 'Poligony' src/app/qml/QgisMobileapp.qml"
echo
echo "Build i instalacja:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 3"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh"
echo
echo "NA TELEFONIE — na projekcie, ktorego NIE SZKODA (albo po kopii):"
echo "  1. lewa szuflada -> Wyposazenie -> „Zalaczniki N:1 (multiodnosniki)”"
echo "     Przycisk „Zaloz” ma byc CZYNNY (do dzis byl szary z napisem"
echo "     „tylko w biurze”)."
echo "  2. Po zalozeniu: otworz obiekt -> w formularzu galeria „Zalaczniki”"
echo "     z aparatem. Zrob dwa zdjecia temu samemu obiektowi."
echo "  3. Sprawdz, ze pliki leza w DCIM/<warstwa>_<fid>/ — podkatalog na obiekt."
echo "  4. Obok projektu maja lezec DWIE kopie: projekt.qgs.przed_* ORAZ"
echo "     dane.gpkg.przed_* (ta druga jest nowa)."
