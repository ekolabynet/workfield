#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — akcja „STAN PROJEKTU" w rejestrze, zeby ekran byl dostepny ZAWSZE.

==========================================================================
PROBLEM
==========================================================================
Sekcja „Jak ten projekt jest ustawiony" jest juz w `QfNaprawaProjektu`
i dziala. **Ale ekran otwiera sie WYLACZNIE z toastu po wykryciu brakow**
(`QfKontrolaProjektu` -> przycisk „Pokaz").

Jesli projekt jest kompletny, toast nie wyskakuje — i nie ma jak zobaczyc,
co jest ustawione. A to pytanie zadaje sie wtedy, gdy cos zachowuje sie
dziwnie, nie wtedy, gdy aplikacja sama zglosi brak.

25.08.2026 dokladnie tak bylo: punkty nie sialy na miejscu, projekt byl
„kompletny", zadnego toastu — a przyczyne (edycja topologiczna) znalezlismy
wieczorem, grepujac XML.

==========================================================================
DLACZEGO REJESTR, A NIE DWIE POZYCJE MENU
==========================================================================
`QfAkcje.qml` to gotowy rejestr: akcja definiowana RAZ, z `grupa`,
`desktop`, `telefon`, `wymagaProjektu`. Menu na belce biurkowej
(`QfDesktopChrome`) i szuflada mobilna czytaja z niego.

Dopisanie pozycji do obu menu z osobna byloby dwoma miejscami do
utrzymania — a rejestr istnieje wlasnie po to, zeby tego nie robic.
To ten sam wzorzec, co `dashBoard.przelaczRysowanie()` z 25.08.

Podzial obowiazkow zostaje nietkniety:
  * `QfAkcje.qml`      — CO jest akcja (nazwa, ikona, grupa, dostepnosc)
  * `QgisMobileapp.qml` — JAK ja wykonac

==========================================================================
DECYZJE
==========================================================================
**Grupa `zarzadzanie`**, nie `warstwy` — to nie jest zawartosc projektu,
tylko jego ustawienia; sasiaduje ze „Sprzet" i „Ustawienia terenowe".

**`telefon: true`** — w terenie ten ekran jest potrzebny BARDZIEJ niz na
biurku. Przy komputerze mozna zgrepowac XML; w rekawicach nie.

**`wymagaProjektu: true`** — bez wczytanego projektu nie ma czego pokazac,
a pozycja aktywna i prowadzaca do pustego ekranu to trzeci stan
(zasada z 17.08).

Nazwa **„Stan projektu"**, a nie „Naprawa" — bo ekran odpowiada teraz na
pytanie „jak to jest ustawione", a nie tylko „co naprawic". Samego ekranu
nie przemianowujemy: dziala i ma swoje wejscie z toastu.

Uruchom w korzeniu repo:  python3 zastosuj_akcje_stan.py
Idempotentna. Kopie: <plik>.przed_akcja_stan
"""
import os
import shutil
import sys

A = "src/app/qml/QfAkcje.qml"
Q = "src/app/qml/QgisMobileapp.qml"
MARKER = "stan_projektu"

# ---------------------------------------------------------------- rejestr

A_DEKLARACJA_KOTWICA = "  property var ustawieniaTerenowe: function () {}"
A_DEKLARACJA_NOWE = ("  property var stanProjektu: function () {}\n"
                     "  property var ustawieniaTerenowe: function () {}")

A_KOTWICA = '''    { id: "teren", nazwa: qsTr("Ustawienia terenowe"), ikona: "wfg_teren",'''

A_NOWE = '''    // Ekran „jak ten projekt jest ustawiony". Dotad dostepny WYLACZNIE
    // z toastu po wykryciu brakow — czyli nie wtedy, kiedy jest potrzebny.
    // 25.08.2026: projekt byl „kompletny", toastu nie bylo, a przyczyne
    // znikajacych obrysow znalezlismy wieczorem, grepujac XML.
    { id: "stan_projektu", nazwa: qsTr("Stan projektu"), ikona: "wfg_lupa",
      grupa: "zarzadzanie", desktop: true, telefon: true, wymagaProjektu: true,
      wykonaj: function () { akcje.stanProjektu(); } },
    { id: "teren", nazwa: qsTr("Ustawienia terenowe"), ikona: "wfg_teren",'''

# ------------------------------------------------------------ wykonanie

Q_KOTWICA = '''    ustawieniaTerenowe: function () { terenSettings.open(); }'''

Q_NOWE = '''    stanProjektu: function () {
      // Kontrola najpierw — zrzut ma pokazywac stan BIEZACY, a nie ten
      // sprzed wczytania projektu. Sama sprawdz() tylko czyta.
      if (typeof kontrolaProjektu !== 'undefined')
        kontrolaProjektu.sprawdz();
      naprawaProjektu.open();
    }
    ustawieniaTerenowe: function () { terenSettings.open(); }'''


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def main():
    a, q = czytaj(A), czytaj(Q)

    stan = [MARKER in a, "stanProjektu: function" in q]
    if all(stan):
        print("Latka juz jest — nic do zrobienia.")
        return
    if any(stan):
        sys.exit("STOP: latka polowiczna %s. Przywroc kopie .przed_akcja_stan." % stan)

    for nazwa, tresc, kotwica, plik in (("rejestr", a, A_KOTWICA, A),
                                        ("wykonanie", q, Q_KOTWICA, Q)):
        n = tresc.count(kotwica)
        if n != 1:
            sys.exit("STOP: kotwica '%s' w %s wystepuje %d razy, oczekiwano 1"
                     % (nazwa, os.path.basename(plik), n))

    print("Kotwice policzone (2/2), nakladam:")

    a = a.replace(A_DEKLARACJA_KOTWICA, A_DEKLARACJA_NOWE, 1)
    a = a.replace(A_KOTWICA, A_NOWE, 1)
    q = q.replace(Q_KOTWICA, Q_NOWE, 1)

    for p, tresc, opis in ((A, a, "wpis w rejestrze akcji"),
                           (Q, q, "wykonanie akcji")):
        kopia = p + ".przed_akcja_stan"
        if not os.path.exists(kopia):
            shutil.copy2(p, kopia)
        open(p, "w", encoding="utf-8").write(tresc)
        print("   %-26s %s" % (opis, os.path.basename(p)))

    print("""
UWAGA — ikona `wfg_lupa`:
  ls -la images/themes/workfield/wfg_lupa.svg

Ta ikona byla w spisie plikow 25.08. Jesli jej nie ma, wpis zadziala,
ale pozycja bedzie bez ikony — podmien nazwe w QfAkcje.qml na istniejaca.

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head

Sprawdzian:
  1. menu „⋯" na gornej belce -> grupa Zarzadzanie -> „Stan projektu"
  2. ekran ma sie otworzyc TAKZE przy projekcie bez brakow
  3. na telefonie: ta sama pozycja w szufladzie
""")


if __name__ == "__main__":
    main()
