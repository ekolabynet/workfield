# -*- coding: utf-8 -*-
"""
Zdejmuje diagnostykę załączników — usuwa linie console.log("ZAL: ...").

Zostawia całą logikę nietkniętą: kontrole stanu, try/catch przy wołaniu
pomocnika C++ i wszystkie ścieżki zapisu zostają. Znika wyłącznie gadanie
do logu, które było potrzebne na czas szukania przyczyny.

Gdyby kiedyś trzeba było wrócić do diagnozowania tej drogi, wystarczy
ponownie nałożyć skrypty/latka_zalaczniki_diag.py.

URUCHOMIENIE (z katalogu repozytorium):
    python3 skrypty/latka_zalaczniki_bez_diag.py

Idempotentna: gdy nie ma czego usuwać, mówi o tym i nie rusza pliku.
"""
import os
import sys

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLIKI = ['src/app/qml/QfQuickCaptureBar.qml']

ZNACZNIK = 'console.log("ZAL:'


def main():
    lacznie = 0
    for wzgledna in PLIKI:
        sciezka = os.path.join(KATALOG, wzgledna)
        if not os.path.exists(sciezka):
            print('STOP — nie ma pliku:', wzgledna)
            return 1

        with open(sciezka, encoding='utf-8') as f:
            linie = f.readlines()

        zostaja = [l for l in linie if ZNACZNIK not in l]
        usuniete = len(linie) - len(zostaja)

        if usuniete == 0:
            print('  . już czyste:', wzgledna)
            continue

        # Kontrola bezpieczenstwa: usuniecie logu nie moze OPROZNIC zadnego
        # bloku. Liczymy puste bloki przed i po — sam plik ma ich kilka od
        # zawsze (np. "ScrollBar.vertical: ScrollBar {}"), wiec liczy sie
        # wylacznie PRZYROST.
        def puste_bloki(wiersze):
            ile = 0
            poprzednia = ''
            for linia in wiersze:
                if poprzednia.rstrip().endswith('{') and linia.strip() == '}':
                    ile += 1
                poprzednia = linia
            return ile

        przyrost = puste_bloki(zostaja) - puste_bloki(linie)
        if przyrost > 0:
            print('STOP — usunięcie opróżniłoby %d blok(i). Nic nie zapisano.'
                  % przyrost)
            return 1

        tresc = ''.join(zostaja)

        with open(sciezka, 'w', encoding='utf-8') as f:
            f.write(tresc)
        print('  + usunięto %d linii diagnostyki: %s' % (usuniete, wzgledna))
        lacznie += usuniete

    print('\nRazem usuniętych linii:', lacznie)
    print('Dalej: cmake --build build-sys -j$(nproc)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
