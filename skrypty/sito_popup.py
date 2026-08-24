#!/usr/bin/env python3
# WorkField 24.08.2026 — dziesiate sito: ILE WIDOCZNYCH DZIECI MA POPUP.
#
# CO SIE STALO
#
# Dolozylem do QfKopiaPanel.qml uchwyt do rozciagania jako DRUGIE dziecko
# korzenia. Okno natychmiast sie rozsypalo: tlo skurczylo sie do czarnego
# paska u gory, a cala zawartosc wylala sie poza nie i pojechala po bialym
# tle aplikacji. Wygladalo to na zepsute kolory — a byly zepsute WYSOKOSCI.
#
# DLACZEGO
#
# `Popup` z JEDNYM widocznym dzieckiem robi z niego swoj `contentItem`
# i dziedziczy po nim `implicitHeight`. Z DWOJGIEM opakowuje je we wlasny,
# goly `Item`, ktorego `implicitHeight` wynosi ZERO. Okno, ktorego wysokosc
# opiera sie na `implicitHeight`, kurczy sie wtedy do samych marginesow,
# a dzieci rysuja sie dalej — bo nic ich nie przycina.
#
# Zadne z tego nie jest bledem skladni. qmllint (sito dziewiate) przepusci
# taki plik bez slowa, kompilacja przejdzie, a zobaczy sie to dopiero na
# ekranie i wyglada na zupelnie inny problem.
#
# CO Z TYM ZROBIC
#
# Opakowac zawartosc w jeden `Item`, ktory przekazuje rozmiary w gore:
#
#     Item {
#       implicitWidth: uklad.implicitWidth
#       implicitHeight: uklad.implicitHeight
#       ColumnLayout { id: uklad; anchors.fill: parent; ... }
#       Item { id: uchwyt; anchors.right: parent.right; ... }
#     }
#
# Elementy NIEWIDOCZNE (Connections, Timer, QtObject, Component…) sie nie
# licza — moga byc obok do woli.
#
# UZYCIE
#     python3 skrypty/sito_popup.py                 # cale repo
#     python3 skrypty/sito_popup.py plik.qml …      # wskazane pliki

import os
import re
import sys

WERSJA = "2026-08-24"

# Korzenie, ktore zachowuja sie jak Popup pod wzgledem contentItem.
KORZENIE = ("Popup", "QfPopup", "Dialog", "Drawer", "Menu", "ToolTip")

# Te elementy nie sa Itemami, wiec nie licza sie do zawartosci.
NIEWIDOCZNE = {
    "Connections", "Timer", "QtObject", "Component", "Binding", "Instantiator",
    "Settings", "Shortcut", "FontLoader", "SystemPalette", "Repeater",
    "ListModel", "ListElement", "Action", "ActionGroup", "ButtonGroup",
    "StateGroup", "State", "Transition", "SequentialAnimation",
    "ParallelAnimation", "NumberAnimation", "PropertyAnimation",
    "PropertyChanges", "Behavior", "Loader",
}


def bez_komentarzy_i_napisow(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    t = re.sub(r"//[^\n]*", "", t)
    t = re.sub(r'"(\\.|[^"\\])*"', '""', t)
    t = re.sub(r"'(\\.|[^'\\])*'", "''", t)
    return t


def liczy_z_zawartosci(t, poczatek):
    """Czy to okno w ogole opiera wysokosc na implicitHeight.

    ZAWEZENIE, KTORE ROBI ROZNICE MIEDZY SITEM A HALASEM. Blad gryzie tylko
    tam, gdzie wysokosc bierze sie z zawartosci. Okno z twardym `height:`
    albo rozciagniete na cala aplikacje nie zauwazy niczego. Pierwsza wersja
    tego sita zglaszala 21 okien z 53 i przez to nie mowila nic.
    """
    naglowek = t[poczatek:poczatek + 1500]
    if re.search(r"(?m)^\s*(height|implicitHeight)\s*:.*implicit", naglowek):
        return True
    if re.search(r"(?m)^\s*height\s*:", naglowek):
        return False
    return True   # brak wlasnej wysokosci = liczona z zawartosci


def dzieci_korzenia(sciezka):
    """Zwraca (typ korzenia, lista dzieci) albo (None, []) gdy to nie Popup."""
    surowy = open(sciezka, encoding="utf-8", errors="replace").read()
    t = bez_komentarzy_i_napisow(surowy)

    korzen = None
    poczatek = None
    for nazwa in KORZENIE:
        m = re.search(r"(?m)^\s*" + nazwa + r"\s*\{", t)
        if m:
            korzen = nazwa
            poczatek = t.index("{", m.start())
            break
    if korzen is None:
        return None, []

    if not liczy_z_zawartosci(t, poczatek):
        return None, []

    glebokosc = 0
    start = None
    dzieci = []
    for j in range(poczatek, len(t)):
        c = t[j]
        if c == "{":
            glebokosc += 1
            if glebokosc == 2:
                start = j
        elif c == "}":
            if glebokosc == 2 and start is not None:
                przed = t[max(0, start - 60):start]
                m = re.search(r"([A-Za-z_][A-Za-z0-9_.]*)\s*$", przed)
                if m and m.group(1)[0].isupper():
                    typ = m.group(1)
                    if typ.split(".")[-1] not in NIEWIDOCZNE:
                        dzieci.append((typ, t[:start].count("\n") + 1))
                start = None
            glebokosc -= 1
            if glebokosc == 0:
                break
    return korzen, dzieci


def main(argv):
    if len(argv) > 1:
        pliki = argv[1:]
    else:
        pliki = []
        for katalog in ("src", "plugins"):
            for korzen, _, nazwy in os.walk(katalog):
                if "build" in korzen:
                    continue
                for n in sorted(nazwy):
                    if n.endswith(".qml"):
                        pliki.append(os.path.join(korzen, n))

    print("sito_popup %s" % WERSJA)
    zle = 0
    popupow = 0
    for plik in pliki:
        if not os.path.isfile(plik):
            continue
        try:
            korzen, dzieci = dzieci_korzenia(plik)
        except Exception as e:
            print("  %s — nie da sie przeczytac (%s)" % (plik, e))
            continue
        if korzen is None:
            continue
        popupow += 1
        if len(dzieci) > 1:
            zle += 1
            print("=== %s  (%s)" % (plik, korzen))
            for typ, linia in dzieci:
                print("    %s w linii %d" % (typ, linia))
            print("    %d widoczne dzieci — Popup opakuje je w Item o zerowej"
                  " wysokosci." % len(dzieci))

    print()
    print("Sprawdzonych okien: %d, podejrzanych: %d" % (popupow, zle))
    if zle == 0:
        print("Kazde ma jedno widoczne dziecko. Wysokosc bedzie liczona z zawartosci.")
    return 1 if zle else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
