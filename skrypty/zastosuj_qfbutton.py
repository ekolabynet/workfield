#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — przyciski w ekranie stanu na ISTNIEJACY `QfButton`.

==========================================================================
NAJPIERW SPRAWDZILEM, POTEM PISALEM — i dobrze
==========================================================================
Zaczalem pisac wlasny komponent `QfPrzycisk`, bo `Button` z QtQuick.Controls
bierze wyglad ze stylu systemowego i na ciemnym tle widac sam tekst.

**Ale `QfButton` juz istnieje** (`src/gui/qml/QfButton.qml`) — z motywem,
efektem nacisniecia (Ripple), obsluga stanu wylaczonego, wskaznikiem
postepu i rozwijaniem. Uzywa go m.in. `QfWelcomeScreen`.

To bylby **szosty raz 26.08.2026**, gdy pisze cos, co w projekcie juz jest.
Wlasny komponent skasowany, zostaje podmiana nazwy.

==========================================================================
LEKCJA DNIA, wpisana tutaj, zeby nie zginela
==========================================================================
Piec potkniec tego samego rodzaju w jednej sesji:

  * `settings`     — w kontekscie z C++, nie jako element `Settings`
  * `onWarning`    — nalezal do polaczenia z chmura, nie do modelu obiektu
  * `stanProjektu` — przypisanie bez wczesniejszej DEKLARACJI w typie
  * `Settings`     — z `QtCore`, nie z `org.qfield`
  * `Settings`     — nie ma `valueInt`; to metoda `QfSettings`, INNEGO typu
                     o podobnej nazwie

Za kazdym razem pisalem z pamieci i naprawialem po fakcie. Zasada:
**zanim napiszesz komponent, sprawdz w repo, czy go nie ma; zanim uzyjesz
typu, sprawdz, jak uzywa go reszta drzewa.**

Piotr, 26.08: „a nie powinienes sprawdzic tych kwestii w kodzie na GitHubie?"

==========================================================================
CO ROBI
==========================================================================
Dwa przyciski w ekranie „Stan projektu":

  * „Pokaz/Ukryj warstwy" — traci wklejone recznie `background`
    i `contentItem` (osiem linijek, ktore QfButton ma u siebie),
  * „Zamknij" — traci `flat: true`, ktory usuwal nawet to tlo,
    ktore dalby styl.

Paddingi wg wzorca z `QfWelcomeScreen.qml:226-229`.

Uruchom w korzeniu repo:  python3 zastosuj_qfbutton.py
Idempotentna. Kopia: QfNaprawaProjektu.qml.przed_qfbutton
"""
import os
import shutil
import sys

EKRAN = "src/app/qml/QfNaprawaProjektu.qml"

WARSTWY_STARE = '''    Button {
      id: przyciskWarstw
      Layout.fillWidth: true
      visible: stanProjektu.dane.warstwy !== undefined

      // Bez własnego tła przycisk gubi się na ciemnym tle okna: widać sam
      // tekst, więc nie wygląda na coś, co da się nacisnąć.
      background: Rectangle {
        color: przyciskWarstw.down ? Theme.mainColor
                                   : przyciskWarstw.hovered ? Theme.controlBackgroundColor
                                                            : "transparent"
        border.width: 1
        border.color: Theme.controlBorderColor
        radius: 4
      }
      contentItem: Text {
        text: przyciskWarstw.text
        font: Theme.tipFont
        color: Theme.mainTextColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }'''

WARSTWY_NOWE = '''    // QfButton, nie Button: ten pierwszy ma motyw, efekt naciśnięcia
    // i obsługę stanu wyłączonego. Button bierze wygląd ze stylu
    // systemowego i na ciemnym tle widać sam tekst.
    QfButton {
      id: przyciskWarstw
      Layout.fillWidth: true
      visible: stanProjektu.dane.warstwy !== undefined
      topPadding: 8
      bottomPadding: 8
      leftPadding: 10
      rightPadding: 10'''

ZAMKNIJ_STARE = '''      Button {
        text: qsTr("Zamknij")
        flat: true
        onClicked: naprawa.close()
      }'''

ZAMKNIJ_NOWE = '''      QfButton {
        text: qsTr("Zamknij")
        topPadding: 8
        bottomPadding: 8
        leftPadding: 10
        rightPadding: 10
        onClicked: naprawa.close()
      }'''


def main():
    if not os.path.exists(EKRAN):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % EKRAN)

    t = open(EKRAN, encoding="utf-8").read()

    if "QfButton {" in t:
        print("Latka juz jest — nic do zrobienia.")
        return

    for nazwa, kotwica in (("przycisk warstw", WARSTWY_STARE),
                           ("Zamknij", ZAMKNIJ_STARE)):
        n = t.count(kotwica)
        if n != 1:
            sys.exit("STOP: kotwica '%s' wystepuje %d razy, oczekiwano 1.\n"
                     "Czy poprzednie latki sa nalozone?" % (nazwa, n))

    print("Kotwice policzone (2/2), nakladam:")
    t = t.replace(WARSTWY_STARE, WARSTWY_NOWE, 1)
    print("   przycisk warstw -> QfButton (minus 8 linijek wklejonych recznie)")
    t = t.replace(ZAMKNIJ_STARE, ZAMKNIJ_NOWE, 1)
    print("   Zamknij -> QfButton (minus flat: true)")

    kopia = EKRAN + ".przed_qfbutton"
    if not os.path.exists(kopia):
        shutil.copy2(EKRAN, kopia)
    open(EKRAN, "w", encoding="utf-8").write(t)
    print("  zapisano %s" % os.path.basename(EKRAN))

    print("""
QfButton mieszka w org.qfield.gui, a ekran importuje `org.qfield` — jesli
kompilator zglosi „QfButton is not a type", dopisz do importow:

  import org.qfield.gui

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head -3
""")


if __name__ == "__main__":
    main()
