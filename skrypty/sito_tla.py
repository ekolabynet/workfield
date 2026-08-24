#!/usr/bin/env python3
"""
SITO OSME — kontrolki, ktore rysuja tlo ZE STYLU.

Dlaczego to sito powstalo (24.08.2026): piaty raz.

    23.08  szuflady i listy        -> Material.background zwiazane na oknie
    23.08  panele w QfPopup        -> Page rysowal wlasne tlo NAD tlem popupu
    23.08  Material.theme          -> liczony z nazwy motywu, nie z jasnosci tla
    23.08  ekran wyboru pliku      -> "okna nie da sie zamknac", bialy na bialym
    24.08  panel spisu             -> ten sam blad w SWIEZO NAPISANYM pliku

Za kazdym razem inny objaw, za kazdym razem ta sama przyczyna:

    Popup, Page, Pane, ToolBar i Dialog RYSUJA WLASNE TLO. Bez podanego
    `background` biora je ze stylu. Na komputerze styl to org.kde.desktop
    i tlo jest JASNE, a nasze napisy sa w barwie motywu, czyli jasne.
    Bialy tekst na bialym tle. Nic nie wybucha, nic nie trafia do logu —
    po prostu nie widac przycisku, ktory tam jest.

Sito wypisuje nasze pliki QML, ktorych KORZEN jest jednym z tych typow
i ktore nie deklaruja `background`. Nie jest wyrocznia: swiadoma
przezroczystosc (`background: null`) tez jest deklaracja i sito ja uzna.

Lekarstwo w wiekszosci wypadkow: dziedziczyc po QfPopup zamiast po Popup,
albo dopisac wprost:

    background: Rectangle {
      color: QfTheme.mainBackgroundColor
    }

Uzycie:  python3 skrypty/sito_tla.py
"""

import os
import re
import sys

KATALOGI = ["src/app/qml", "src/gui/qml"]

# Typy QQC2, ktore maluja wlasne tlo z palety stylu.
MALUJA = {"Popup", "Page", "Pane", "ToolBar", "Dialog", "Drawer", "Frame", "Menu"}

# Nasze opakowania, ktore tlo juz ustawiaja — dziedziczenie po nich jest OK.
BEZPIECZNE_KORZENIE = {"QfPopup", "QfDialog", "QfPage"}

KORZEN = re.compile(r"^([A-Z][\w.]*)\s*\{\s*$")


def korzen_pliku(tresc):
    """Typ elementu korzenia — pierwsza linia po importach i komentarzach."""
    w_komentarzu = False
    for linia in tresc.splitlines():
        naga = linia.strip()
        if not naga:
            continue
        if w_komentarzu:
            if "*/" in naga:
                w_komentarzu = False
            continue
        if naga.startswith("/*"):
            if "*/" not in naga:
                w_komentarzu = True
            continue
        if naga.startswith("//") or naga.startswith("import") or naga.startswith("pragma"):
            continue
        dop = KORZEN.match(naga)
        return dop.group(1) if dop else None
    return None


def main():
    korzen_repo = os.getcwd()
    braki = []
    sprawdzonych = 0

    for katalog in KATALOGI:
        sciezka = os.path.join(korzen_repo, katalog)
        if not os.path.isdir(sciezka):
            continue
        for nazwa in sorted(os.listdir(sciezka)):
            if not nazwa.endswith(".qml"):
                continue
            plik = os.path.join(katalog, nazwa)
            with open(os.path.join(korzen_repo, plik), encoding="utf-8") as f:
                tresc = f.read()

            typ = korzen_pliku(tresc)
            if typ is None:
                continue
            sprawdzonych += 1

            if typ in BEZPIECZNE_KORZENIE:
                continue
            if typ not in MALUJA:
                continue

            # `background:` gdziekolwiek w pliku wystarczy: zagniezdzone
            # kontrolki tez maluja, a my chcemy wiedziec o BRAKU deklaracji.
            if re.search(r"^\s*background\s*:", tresc, re.M):
                continue

            braki.append("  %-46s korzen: %s" % (plik, typ))

    print("BEZ WLASNEGO TLA — kontrolka wezmie je ze stylu.")
    print("Na komputerze (org.kde.desktop) tlo bedzie JASNE, a napisy sa")
    print("w barwie motywu. Bialy tekst na bialym tle; brak objawu w logu.\n")
    for b in braki:
        print(b)

    print("\nsprawdzonych korzeni: %d, bez tla: %d" % (sprawdzonych, len(braki)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
