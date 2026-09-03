# -*- coding: utf-8 -*-
"""
Poprawka do latka_zalaczniki_formularz.py — nasłuchiwaliśmy złego sygnału.

FeatureForm przy zapisie rozróżnia dwie sytuacje (src/gui/qml/FeatureForm.qml,
funkcja save()):

    NOWY obiekt      -> model.create()  -> sygnał created()
    ISTNIEJĄCY obiekt-> model.save()    -> sygnał saved()

Pasek zawsze tworzy obiekty NOWE, więc nasłuch na saved() nie odpalał się
nigdy, a załącznik oczekujący czekał aż do zamknięcia szuflady i ginął jako
"formularz porzucony". Objaw z terenu: zdjęcie jest w DCIM i w galerii,
a zakładka Załączniki pokazuje 0 obiektów.

Ta łatka dokłada nasłuch na created() i zostawia saved() — dzięki temu
mechanizm zadziała też, gdyby kiedyś zdjęcie dopinało się do obiektu
istniejącego (np. z ikony w nagłówku formularza).

URUCHOMIENIE (z katalogu repozytorium):
    python3 skrypty/latka_zalaczniki_created.py

Idempotentna. Kotwica musi trafić dokładnie raz — inaczej STOP.
"""
import os
import sys

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASEK = 'src/app/qml/QfQuickCaptureBar.qml'

KOTWICA = """    function onSaved() {
      quickCaptureBar.dopnijZalacznikPoFormularzu();
    }
  }
"""

NOWE = """    // FeatureForm.save(): NOWY obiekt konczy sie sygnalem created(),
    // istniejacy — saved(). Pasek tworzy zawsze nowe, wiec bez created()
    // zalacznik oczekujacy nigdy by sie nie dopial.
    function onCreated() {
      quickCaptureBar.dopnijZalacznikPoFormularzu();
    }

    function onSaved() {
      quickCaptureBar.dopnijZalacznikPoFormularzu();
    }
  }
"""

ZNACZNIK = 'function onCreated()'

ZMIANY = [
    (PASEK, KOTWICA, NOWE, ZNACZNIK,
     'nasłuch na created() obok saved()'),
]


def main():
    plany = {}
    pominiete = []
    bledy = []

    for plik, kotwica, nowe, znacznik, opis in ZMIANY:
        sciezka = os.path.join(KATALOG, plik)
        if not os.path.exists(sciezka):
            bledy.append('%s: nie ma pliku %s' % (opis, plik))
            continue
        tresc = plany.get(sciezka)
        if tresc is None:
            with open(sciezka, encoding='utf-8') as f:
                tresc = f.read()
        if znacznik in tresc:
            pominiete.append(opis)
            plany[sciezka] = tresc
            continue
        ile = tresc.count(kotwica)
        if ile != 1:
            bledy.append('%s: kotwica trafia %d razy (oczekiwano 1) w %s'
                         % (opis, ile, plik))
            continue
        plany[sciezka] = tresc.replace(kotwica, nowe, 1)

    if bledy:
        print('STOP — nic nie zapisano:')
        for b in bledy:
            print('  !', b)
        print('\nCzy nałożona jest latka_zalaczniki_formularz.py?')
        return 1

    for sciezka, tresc in plany.items():
        with open(sciezka, 'w', encoding='utf-8') as f:
            f.write(tresc)

    for _plik, _k, _n, _z, opis in ZMIANY:
        print('  %s %s' % ('. już było:' if opis in pominiete else '+ zrobione:',
                           opis))
    print('\nDalej: cmake --build build-sys -j$(nproc)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
