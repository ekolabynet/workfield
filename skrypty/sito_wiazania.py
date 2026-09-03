#!/usr/bin/env python3
"""
SITO SIODME — wiazania QML oparte na WYWOLANIU FUNKCJI.

Dlaczego to sito powstalo (23.08.2026): trzeci raz tego samego dnia.

    highlighted: settings.valueInt("...")          -> maska elewacji nie do zdjecia
    readonly property string bazaProjektu:
        NarzedziaProjektu.plikDanych(qgisProject)  -> "Importuj do bazy" wygaszone
                                                      w projekcie, ktory ma dane

Wiazanie QML przelicza sie wtedy, gdy zmieni sie WLASCIWOSC, od ktorej zalezy.
Funkcja C++ wystawiona przez Q_INVOKABLE nie ma zadnego sygnalu zmiany, wiec
wynik jest liczony RAZ, w chwili tworzenia obiektu — czesto zanim cokolwiek
jest wczytane. Objawu nie ma: nic nie wybucha, po prostu wartosc jest
z przeszlosci. To jest ten sam gatunek awarii co "czynnosc w menu, ktora
milczy" — dokladnie ten, ktorego pilnujemy.

ROZSTRZYGA TO, CZY FUNKCJA JEST W QML, CZY W C++.

Sledzenie zaleznosci w QML jest DYNAMICZNE: przy liczeniu wiazania silnik
zapamietuje kazda wlasciwosc, ktora zostala PO DRODZE odczytana — takze
wewnatrz wolanych funkcji JavaScriptu. Dlatego:

  wTrybie: dataDrawer.trybAktywny("measure")   <- DOBRZE. Funkcja jest w QML
                                                  i czyta stateMachine.state,
                                                  wiec to ta wlasciwosc staje
                                                  sie zaleznoscia wiazania.

  bazaProjektu: NarzedziaProjektu.plikDanych(p) <- ZLE. Funkcja jest w C++,
                                                  odczyty w srodku sa dla
                                                  silnika niewidzialne, wiec
                                                  wiazanie nie ma zaleznosci
                                                  i nie przeliczy sie NIGDY.

Sito zbiera wiec nazwy wszystkich funkcji zadeklarowanych w naszych plikach
QML i pomija wolania do nich. Zostaja wolania do C++ — i te ogladamy.

Uzycie:  python3 skrypty/sito_wiazania.py
"""

import os
import re
import sys

KATALOGI = ["src/app/qml", "src/gui/qml"]

# funkcje, ktore sa czyste i licza sie z argumentow — nie interesuja nas
BEZPIECZNE = {
    "Math", "Qt", "JSON", "Number", "String", "Array", "Object", "Date",
    "parseInt", "parseFloat", "isNaN", "encodeURIComponent",
}

# nazwy metod, ktore prawie zawsze licza sie z argumentu, a nie ze stanu
BEZPIECZNE_METODY = {
    "arg", "toFixed", "toString", "toLowerCase", "toUpperCase", "trim",
    "replace", "split", "join", "indexOf", "includes", "startsWith",
    "endsWith", "slice", "substring", "charAt", "concat", "filter", "map",
    "rgba", "hsla", "lighter", "darker", "point", "size", "rect", "binding",
    "formatDateTime", "formatDate", "qsTr", "qsTranslate",
    # sciezka do ikony nie zalezy od stanu, ktory zmienia sie w locie
    "getThemeVectorIcon", "getThemeIcon",
    # metody obiektu Date licza sie z NIEGO — a on jest wlasciwoscia,
    # wiec zaleznosc wiazania jest poprawnie wykryta
    "getDate", "getDay", "getMonth", "getFullYear", "getHours", "getMinutes",
    "getTime", "toISOString", "toLocaleDateString", "toLocaleString",
}

# ---- wzorzec: [readonly] [property TYP] nazwa: obiekt.metoda(...)
WIAZANIE = re.compile(
    r"^\s*(?P<ro>readonly\s+)?(?P<dekl>property\s+\w+(?:<\w+>)?\s+)?"
    r"(?P<lewa>[A-Za-z_][\w.]*)\s*:\s*"
    r"(?P<prawa>[A-Za-z_][\w.]*)\s*\("
)


def funkcje_qml(pliki):
    """Nazwy WSZYSTKICH funkcji zadeklarowanych w naszych plikach QML."""
    nazwy = set()
    for tresc in pliki.values():
        nazwy |= set(re.findall(r"^\s*function\s+(\w+)\s*\(", tresc, re.M))
    return nazwy


def main():
    korzen = os.getcwd()
    podejrzane = []
    reszta = []

    pliki = {}
    for katalog in KATALOGI:
        sciezka = os.path.join(korzen, katalog)
        if not os.path.isdir(sciezka):
            continue
        for nazwa in sorted(os.listdir(sciezka)):
            if nazwa.endswith(".qml"):
                plik = os.path.join(katalog, nazwa)
                with open(os.path.join(korzen, plik), encoding="utf-8") as f:
                    pliki[plik] = f.read()

    wlasne = funkcje_qml(pliki)

    if True:
        if True:
            for plik, tresc in pliki.items():
              for numer, linia in enumerate(tresc.splitlines(), 1):
                  naga = linia.split("//")[0]
                  dop = WIAZANIE.match(naga)
                  if not dop:
                      continue

                  lewa = dop.group("lewa")
                  prawa = dop.group("prawa")

                  # deklaracje sygnalow, funkcji i obsluga zdarzen to nie wiazania
                  if lewa.startswith("on") and len(lewa) > 2 and lewa[2].isupper():
                      continue
                  if prawa.split(".")[0] in BEZPIECZNE:
                      continue
                  if prawa.split(".")[-1] in BEZPIECZNE_METODY:
                      continue
                  if prawa.split(".")[-1] in wlasne:
                      continue

                  wpis = "  %s:%d  ->  %s: %s(...)" % (plik, numer, lewa, prawa)

                  # ROZSTRZYGAJACE: `readonly` + wywolanie funkcji = zamrozone
                  # NA ZAWSZE. Zwykla wlasciwosc z takim samym prawym bokiem to
                  # najczesciej WARTOSC POCZATKOWA, ktora potem ktos nadpisuje
                  # imperatywnie — i to jest w porzadku (lekcja z 22.08: inne
                  # ustawienia inicjalne to nie blad). Roznica jest w tym, czy
                  # istnieje jakakolwiek droga do zmiany wartosci.
                  if dop.group("ro"):
                      podejrzane.append(wpis)
                  elif "." in prawa:
                      reszta.append(wpis)

    print("ZAMROZONE — `readonly` plus wywolanie funkcji.")
    print("Liczy sie RAZ, przy tworzeniu obiektu, i nie ma zadnej drogi do")
    print("zmiany: readonly zabrania zapisu, a funkcja nie zglasza zmian.")
    print("Jesli czytany stan pojawia sie pozniej (projekt, polaczenie,")
    print("urzadzenie) — wartosc bedzie pusta do konca zycia okna.\n")
    for w in podejrzane:
        print(w)

    print("\nWARTOSCI POCZATKOWE — wlasciwosc zapisywalna, wiazanie na funkcji.")
    print("Zwykle w porzadku: ktos nadpisuje ja imperatywnie. Do sprawdzenia")
    print("tylko wtedy, gdy NIKT jej nie nadpisuje.\n")
    for w in reszta:
        print(w)

    print("\nzamrozonych: %d, wartosci poczatkowych: %d" % (len(podejrzane), len(reszta)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
