# -*- coding: utf-8 -*-
"""
Poprawka: zbyt ostre kontrole w dopnijZalacznik() blokowały zapis.

Diagnostyka pokazała, że łańcuch dochodzi do "klucz rodzica: 135", a linia
"zapis wiersza zalacznika" już nie pada — czyli funkcja wychodzi w jednej
z trzech kontrol dołożonych po przeglądzie kodu:

    if (!dziecko || dziecko.valid !== true) return false;
    if (!dziecko.setAttribute(opis.poleObce, klucz)) return false;
    if (!dziecko.setAttribute(opis.poleSciezki, sciezka)) return false;

Obie są podejrzane z tego samego powodu: QgsFeature jest w QML typem
WARTOŚCIOWYM (Q_GADGET). Świeżo zbudowany obiekt nie musi mieć ustawionej
flagi "valid" (nadaje ją zwykle dopiero provider przy odczycie), a wywołanie
metody na gadgecie potrafi nie zwrócić wartości logicznej — wtedy `!wynik`
jest prawdą mimo poprawnego przypisania. Znamienne, że NIGDZIE indziej w tym
pliku nikt nie sprawdza wyniku setAttribute (linie 396-401, 608-626,
792-805) — i te ścieżki działają od miesięcy.

Wracamy więc do sprawdzania stanu FAKTYCZNEGO zamiast wartości zwracanych:
obiekt musi mieć pola, a po przypisaniu klucz obcy i ścieżka muszą być
w atrybutach. To jest kontrola mocniejsza niż poprzednia, a nie słabsza —
sprawdza wynik, nie deklarację.

Dokłada też diagnostykę tego odcinka, żeby ewentualna kolejna niespodzianka
była widoczna od razu.

URUCHOMIENIE (z katalogu repozytorium):
    python3 skrypty/latka_zalaczniki_kontrole.py

Idempotentna.
"""
import os
import sys

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASEK = 'src/app/qml/QfQuickCaptureBar.qml'

KOTWICA = """    const dziecko = FeatureUtils.createFeature(opis.warstwa);
    // obiekt jest typem wartosciowym — "!dziecko" nigdy nie bylby prawda
    if (!dziecko || dziecko.valid !== true) {
      return false;
    }
    const nazwy = dziecko.fields.names;
    // bez klucza obcego i bez sciezki wiersz jest smieciem — lepiej zglosic
    // porazke i pozwolic zadzialac zapasowi awaryjnemu
    if (!dziecko.setAttribute(opis.poleObce, klucz)) {
      return false;
    }
    if (!dziecko.setAttribute(opis.poleSciezki, sciezka)) {
      return false;
    }
"""

NOWE = """    const dziecko = FeatureUtils.createFeature(opis.warstwa);
    // QgsFeature jest w QML typem wartosciowym: "!dziecko" nigdy nie bedzie
    // prawda, a flaga "valid" bywa nieustawiona w obiekcie jeszcze niezapisanym.
    // Sprawdzamy wiec to, co realnie musi byc: pola warstwy.
    const nazwy = dziecko && dziecko.fields ? dziecko.fields.names : [];
    if (nazwy.length === 0) {
      console.log("ZAL: dopnijZalacznik — obiekt dziecka bez pol, przerywam");
      return false;
    }
    dziecko.setAttribute(opis.poleObce, klucz);
    dziecko.setAttribute(opis.poleSciezki, sciezka);
    // kontrola po fakcie, nie po deklaracji: wynik setAttribute na gadgecie
    // bywa nieuzyteczny, ale zapisana wartosc klamac nie moze
    const kluczPo = dziecko.attribute(opis.poleObce);
    const sciezkaPo = dziecko.attribute(opis.poleSciezki);
    console.log("ZAL: po przypisaniu — klucz:", kluczPo, "| sciezka:", sciezkaPo);
    if (kluczPo === undefined || kluczPo === null || kluczPo === "") {
      console.log("ZAL: dopnijZalacznik — klucz obcy nie zostal przypisany, przerywam");
      return false;
    }
    if (!sciezkaPo || sciezkaPo === "") {
      console.log("ZAL: dopnijZalacznik — sciezka nie zostala przypisana, przerywam");
      return false;
    }
"""

ZNACZNIK = 'ZAL: po przypisaniu — klucz:'

ZMIANY = [
    (PASEK, KOTWICA, NOWE, ZNACZNIK,
     'dopnijZalacznik: kontrola stanu zamiast wartości zwracanych'),
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
        return 1

    for sciezka, tresc in plany.items():
        with open(sciezka, 'w', encoding='utf-8') as f:
            f.write(tresc)

    for _plik, _k, _n, _z, opis in ZMIANY:
        print('  %s %s' % ('. już było:' if opis in pominiete else '+ zrobione:',
                           opis))
    print('\nDalej:')
    print('  cmake --build build-sys -j$(nproc)')
    print('  ./build-sys/output/bin/qfield 2>&1 | grep "ZAL:"')
    return 0


if __name__ == '__main__':
    sys.exit(main())
