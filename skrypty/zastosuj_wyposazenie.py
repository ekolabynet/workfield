#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Łatka: wpina wyposażenie (NarzedziaProjektu + QfPrzepis) w build forka.

Robi pięć wpięć, każde po jednej linijce, wszystkie na kotwicach
sprawdzonych jako UNIKALNE w repo:

  1. src/core/CMakeLists.txt              — narzedziaprojektu.cpp
  2. src/core/CMakeLists.txt              — narzedziaprojektu.h
  3. src/core/qfieldcoreqmlregistration.cpp — #include + REGISTER_SINGLETON
  4. src/app/CMakeLists.txt               — qml/QfPrzepis.qml
  5. src/app/qml/qgismobileapp.qml        — instancja QfPrzepis
                                          + przechwyt „nowe zadanie z przepisu"

BEZPIECZEŃSTWO
  Najpierw sprawdza WSZYSTKO, dopiero potem zapisuje cokolwiek. Niezgodność
  na którymkolwiek kroku = koniec BEZ zmian w żadnym pliku. Idempotentna:
  to, co już wpięte, jest pomijane.

UŻYCIE
  cd /DATA/SOFT/GIS/QFIELD_Pro/QField
  python3 skrypty/zastosuj_wyposazenie.py            # wpina
  python3 skrypty/zastosuj_wyposazenie.py --sucho    # tylko mówi, co zrobi
"""

import os
import sys

REPO = os.environ.get('WF_REPO', os.getcwd())

# --------------------------------------------------------------------- wpięcia
# (plik, kotwica, co wstawić, gdzie: 'po' albo 'przed')

WPIECIA = [
    (
        'src/core/CMakeLists.txt',
        '    utils/zalacznikiutils.cpp\n',
        '    utils/narzedziaprojektu.cpp\n',
        'przed',
    ),
    (
        'src/core/CMakeLists.txt',
        '    utils/zalacznikiutils.h\n',
        '    utils/narzedziaprojektu.h\n',
        'przed',
    ),
    (
        'src/core/qfieldcoreqmlregistration.cpp',
        '#include "utils/zalacznikiutils.h"\n',
        '#include "utils/narzedziaprojektu.h"\n',
        'przed',
    ),
    (
        'src/core/qfieldcoreqmlregistration.cpp',
        '    REGISTER_SINGLETON( "org.qfield", ZalacznikiUtils, "ZalacznikiUtils" );\n',
        '    REGISTER_SINGLETON( "org.qfield", NarzedziaProjektu, "NarzedziaProjektu" );\n',
        'przed',
    ),
    (
        'src/app/CMakeLists.txt',
        '    qml/QfNoweZadanie.qml\n',
        '    qml/QfPrzepis.qml\n',
        'po',
    ),
    (
        'src/app/qml/qgismobileapp.qml',
        '  OverlayFeatureFormDrawer {\n',
        '''  // WorkField: interpreter przepisow — buduje zadanie z przepisu zamiast
  // kopiowac katalog szablonu. Patrz docs/WYPOSAZENIE.md.
  QfPrzepis {
    id: qfPrzepis

    onZbudowano: function (sciezka, nazwa) {
      displayToast(qsTr("Zadanie %1 gotowe").arg(nazwa));
    }
    onPotknieto: function (komunikat) {
      displayToast(komunikat, "error");
    }
  }

''',
        'przed',
    ),
]

# ------------------------------------------------------------------- podmiany
# (plik, stara tresc, nowa tresc)

PODMIANY = [
    (
        'src/app/qml/qgismobileapp.qml',
        '      welcomeScreen.createProjectFromTemplate(dir, templateName + " Projekt " + new Date().toISOString().slice(0, 10));\n',
        '''      const nazwa = templateName + " Projekt " + new Date().toISOString().slice(0, 10);

      // WorkField: szablon z przepisem budujemy od zera z aktualnego
      // wyposazenia. Kopia katalogu (createProjectFromTemplate) byla dotad
      // jedynym mechanizmem — i jedynym zrodlem dryfu (17.08.2026).
      if (FileUtils.fileExists(dir + "/przepis.json")) {
        qfPrzepis.noweZadanie(dir + "/przepis.json", iface.dataRoot() + "Imported Projects", nazwa);
      } else {
        welcomeScreen.createProjectFromTemplate(dir, nazwa);
      }
''',
    ),
]

# ----------------------------------------------------------- pliki, ktore musza byc

WYMAGANE = [
    'src/core/utils/narzedziaprojektu.h',
    'src/core/utils/narzedziaprojektu.cpp',
    'src/app/qml/QfPrzepis.qml',
]


def czytaj(wzgledna):
    sciezka = os.path.join(REPO, wzgledna)
    if not os.path.exists(sciezka):
        return None
    with open(sciezka, encoding='utf-8') as f:
        return f.read()


def main():
    sucho = '--sucho' in sys.argv

    if not os.path.isdir(os.path.join(REPO, 'src', 'core')):
        sys.exit('To nie wyglada na repo QField/WorkField: %s\n'
                 '(ustaw WF_REPO albo uruchom z korzenia repo)' % REPO)

    print('Repo: %s\n' % REPO)

    brakujace = [p for p in WYMAGANE if not os.path.exists(os.path.join(REPO, p))]
    if brakujace:
        sys.exit('Najpierw rozpakuj paczke — brakuje:\n  ' + '\n  '.join(brakujace))

    # ---------------------------------------------------- faza 1: tylko sprawdzanie
    plan = {}      # plik -> nowa tresc
    opisy = []
    pominiete = []

    tresci = {}
    for plik in {w[0] for w in WPIECIA} | {p[0] for p in PODMIANY}:
        t = czytaj(plik)
        if t is None:
            sys.exit('Brak pliku: %s' % plik)
        tresci[plik] = t

    for plik, kotwica, wstawka, gdzie in WPIECIA:
        tresc = plan.get(plik, tresci[plik])

        if wstawka.strip() and wstawka.strip().splitlines()[0] in tresc:
            pominiete.append('%s: juz wpiete (%s)' % (plik, wstawka.strip().splitlines()[0][:60]))
            continue

        licznik = tresc.count(kotwica)
        if licznik != 1:
            sys.exit('KONIEC BEZ ZMIAN.\n'
                     'W %s kotwica wystepuje %d razy (oczekiwano 1):\n  %s\n'
                     'Plik rozjechal sie z tym, co widzialem. Przyslij mi go, nie poprawiaj recznie.'
                     % (plik, licznik, kotwica.strip()))

        nowa = (tresc.replace(kotwica, wstawka + kotwica)
                if gdzie == 'przed'
                else tresc.replace(kotwica, kotwica + wstawka))
        plan[plik] = nowa
        opisy.append('%s: + %s' % (plik, wstawka.strip().splitlines()[0][:70]))

    for plik, stare, nowe in PODMIANY:
        tresc = plan.get(plik, tresci[plik])

        if nowe.strip().splitlines()[0] in tresc:
            pominiete.append('%s: podmiana juz zrobiona' % plik)
            continue

        licznik = tresc.count(stare)
        if licznik != 1:
            sys.exit('KONIEC BEZ ZMIAN.\n'
                     'W %s linia do podmiany wystepuje %d razy (oczekiwano 1):\n  %s'
                     % (plik, licznik, stare.strip()))

        plan[plik] = tresc.replace(stare, nowe)
        opisy.append('%s: podmiana wywolania createProjectFromTemplate' % plik)

    # ------------------------------------------------------------ faza 2: raport
    for o in opisy:
        print('  ZROBIE   %s' % o)
    for o in pominiete:
        print('  pomijam  %s' % o)

    if not opisy:
        print('\nNic do zrobienia — wszystko juz wpiete.')
        return 0

    if sucho:
        print('\n--sucho: niczego nie zapisalem.')
        return 0

    # ------------------------------------------------------------- faza 3: zapis
    for plik, nowa in plan.items():
        sciezka = os.path.join(REPO, plik)
        kopia = sciezka + '.przed_wyposazeniem'
        if not os.path.exists(kopia):
            with open(kopia, 'w', encoding='utf-8') as f:
                f.write(tresci[plik])
        with open(sciezka, 'w', encoding='utf-8') as f:
            f.write(nowa)
        print('\nzapisano %s (kopia: %s)' % (plik, os.path.basename(kopia)))

    print('\nGotowe. Teraz:')
    print('  python3 skrypty/sprawdz_przepis.py wyposazenie/przepisy/*.json')
    print('  cmake -S . -B build-sys -Wno-dev && cmake --build build-sys -j$(nproc)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
