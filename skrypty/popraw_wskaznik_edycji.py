#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Poprawka wskaznika edycji — WSPOLNY KOMPONENT w obu belkach.

==========================================================================
CO BYLO ZLE
==========================================================================
Pierwsza latka wstawila plakietke do `QgisMobileapp.qml`. Na desktopie nie
pokazalo sie NIC — nawet wypisania z console.log.

Powod: **belek jest dwie i to inne pliki.** Ta widoczna na biurku to
`QfDesktopChrome.qml:269-288`, ktora sklejа tytul projektu i nazwe warstwy
w jeden ciag przez `czesci.join("  ·  ")` — stad kropka na zrzucie, ktorej
w naszym kodzie nie bylo. Belka z `QgisMobileapp.qml` na desktopie w ogole
nie powstaje.

Zamiast wklejac to samo dwa razy, plakietka staje sie osobnym komponentem
`QfZnacznikEdycji.qml`. Przy trzeciej belce nie bedzie trzeba tego
powtarzac po raz trzeci.

==========================================================================
DRUGA POPRAWKA: KOLOR
==========================================================================
Pierwsza wersja dawala tlo ostrzegawcze **tylko przy niezapisanych
zmianach**, a przy pustej sesji spokojne. To bylo odwrocenie priorytetu.

**Otwarta sesja jest zawsze stanem wymagajacym uwagi** — 20.08.2026 sesja
wisiala otwarta BEZ zmian i wlasnie dlatego nic nie wygladalo podejrzanie,
a kazdy kolejny zapis sie odbijal. To ten stan kosztowal dzien, nie ten
ze zmianami.

Wiec: tlo ostrzegawcze ZAWSZE, gdy sesja otwarta; przy niezapisanych
zmianach mocniejszy odcien i liczba.

Uruchom w korzeniu repo:  python3 popraw_wskaznik_edycji.py
Idempotentna. Kopie: <plik>.przed_wspolnym
"""
import os
import shutil
import sys

KOMPONENT = "src/gui/qml/QfZnacznikEdycji.qml"
CMAKE = "src/gui/qml/CMakeLists.txt"
MOBIL = "src/app/qml/QgisMobileapp.qml"
DESKTOP = "src/app/qml/QfDesktopChrome.qml"

TRESC_KOMPONENTU = '''import QtQuick
import QtQuick.Controls

import org.qfield
import Theme

/**
 * Plakietka OTWARTEJ SESJI EDYCJI.
 *
 * 20.08.2026 wtyczka zostawiła warstwę w otwartej sesji: nowe obiekty
 * przestały się dodawać, edycja była odrzucana bez słowa, kafel znikał
 * z paska. Diagnoza zajęła cały dzień — bo otwarta sesja wygląda dokładnie
 * tak samo jak zamknięta.
 *
 * TRZY STANY, nie dwa:
 *   zamknięta                 — plakietki nie ma
 *   otwarta sesja, bez zmian  — „EDYCJA"
 *   otwarta ze zmianami       — „EDYCJA N", mocniejszy odcień
 *
 * Środkowy stan jest tym, który kosztował dzień: sesja wisiała otwarta,
 * zmian nie było, więc nic nie wyglądało podejrzanie.
 *
 * Plakietka tekstowa, nie kolorowa kropka: w rękawicach i w słońcu kolor
 * bywa nieczytelny. Kolor jest tu wzmocnieniem, nie nośnikiem treści.
 *
 * Osobny komponent, bo belek jest dwie — mobilna (QgisMobileapp) i biurkowa
 * (QfDesktopChrome) — a przy trzeciej nie chcemy wklejać tego po raz trzeci.
 */
Rectangle {
  id: znacznik

  //! Warstwa do obserwowania; zwykle dashBoard.activeLayer
  property var warstwa: null

  property var stan: ({ wEdycji: false, zmian: 0 })

  function odswiez() {
    stan = warstwa ? LayerUtils.stanEdycji(warstwa) : ({ wEdycji: false, zmian: 0 });
  }

  visible: stan.wEdycji
  implicitWidth: etykieta.implicitWidth + 14
  implicitHeight: etykieta.implicitHeight + 5
  radius: 3

  // Otwarta sesja to ZAWSZE stan wymagający uwagi — stąd kolor ostrzegawczy
  // także wtedy, gdy bufor jest pusty. Niezapisane zmiany dokładają mocniejszy
  // odcień, bo tam da się stracić dane.
  color: stan.zmian > 0 ? Theme.errorColor : Theme.warningColor

  Text {
    id: etykieta
    anchors.centerIn: parent
    text: znacznik.stan.zmian > 0
          ? qsTr("EDYCJA %1").arg(znacznik.stan.zmian)
          : qsTr("EDYCJA")
    color: "white"
    font.pointSize: Theme.tinyFont.pointSize
    font.bold: true
  }

  // Sygnały mieszkają w QgsMapLayer i SĄ widoczne z QML — inaczej niż
  // isEditable(), które jest zwykłą metodą publiczną. Bez nich plakietka
  // odświeżałaby się dopiero przy przełączeniu warstwy, czyli nie wtedy,
  // kiedy trzeba.
  Connections {
    target: znacznik.warstwa
    ignoreUnknownSignals: true
    function onEditingStarted() { znacznik.odswiez(); }
    function onEditingStopped() { znacznik.odswiez(); }
    function onLayerModified() { znacznik.odswiez(); }
  }

  onWarstwaChanged: odswiez()
  Component.onCompleted: odswiez()
}
'''

# --------------------------------------------------- cofniecie pierwszej latki

MOBIL_STARE_POCZATEK = "        // WorkField 25.08.2026 — wskaźnik OTWARTEJ SESJI EDYCJI."
MOBIL_STARE_KONIEC = "          Component.onCompleted: odswiez()\n        }"

MOBIL_NOWE = '''        // Wskaźnik otwartej sesji edycji — wspólny komponent, bo ta sama
        // plakietka jest też na belce biurkowej (QfDesktopChrome).
        QfZnacznikEdycji {
          Layout.alignment: Qt.AlignVCenter
          warstwa: dashBoard.activeLayer
        }'''

# ------------------------------------------------------------------- desktop

DESKTOP_KOTWICA = '''  Text {
    anchors.centerIn: parent
    width: Math.min(implicitWidth, chrom.width - 720)
    visible: width > 60
    horizontalAlignment: Text.AlignHCenter
    text: {
      const czesci = [];
      if (mainWindow.projectTitle !== "")
        czesci.push(mainWindow.projectTitle);
      if (dashBoard.activeLayer)
        czesci.push(dashBoard.activeLayer.name);
      else
        czesci.push(qsTr("brak aktywnej warstwy"));
      return czesci.join("  ·  ");
    }
    font: Theme.tipFont
    color: "white"
    opacity: 0.85
    elide: Text.ElideMiddle
  }'''

DESKTOP_NOWE = '''  // Tytul + plakietka edycji w jednym rzedzie na srodku belki. Plakietka
  // MUSI stac obok tytulu, a nie w rogu: w rogu nikt na nia nie patrzy,
  // a to jest informacja, ktorej przeoczenie kosztowalo dzien pracy.
  Row {
    anchors.centerIn: parent
    spacing: 8

    Text {
      id: tytulBelki
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, chrom.width - 760)
      visible: width > 60
      horizontalAlignment: Text.AlignHCenter
      text: {
        const czesci = [];
        if (mainWindow.projectTitle !== "")
          czesci.push(mainWindow.projectTitle);
        if (dashBoard.activeLayer)
          czesci.push(dashBoard.activeLayer.name);
        else
          czesci.push(qsTr("brak aktywnej warstwy"));
        return czesci.join("  ·  ");
      }
      font: Theme.tipFont
      color: "white"
      opacity: 0.85
      elide: Text.ElideMiddle
    }

    QfZnacznikEdycji {
      anchors.verticalCenter: parent.verticalCenter
      warstwa: dashBoard.activeLayer
    }
  }'''


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def zapisz(p, t):
    kopia = p + ".przed_wspolnym"
    if not os.path.exists(kopia):
        shutil.copy2(p, kopia)
    open(p, "w", encoding="utf-8").write(t)
    print("   %s" % os.path.basename(p))


def main():
    if os.path.exists(KOMPONENT):
        print("Poprawka juz jest — nic do zrobienia.")
        return

    m = czytaj(MOBIL)
    d = czytaj(DESKTOP)

    # --- cofniecie plakietki wklejonej do belki mobilnej
    i = m.find(MOBIL_STARE_POCZATEK)
    if i < 0:
        sys.exit("STOP: nie znalazlem plakietki w %s — czy pierwsza latka byla "
                 "nalozona?" % MOBIL)
    j = m.find(MOBIL_STARE_KONIEC, i)
    if j < 0:
        sys.exit("STOP: nie znalazlem konca bloku plakietki")
    j += len(MOBIL_STARE_KONIEC)

    if d.count(DESKTOP_KOTWICA) != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1"
                 % (DESKTOP, d.count(DESKTOP_KOTWICA)))

    print("Kotwice policzone, nakladam:")

    m = m[:i] + MOBIL_NOWE + m[j:]
    d = d.replace(DESKTOP_KOTWICA, DESKTOP_NOWE, 1)

    os.makedirs(os.path.dirname(KOMPONENT), exist_ok=True)
    open(KOMPONENT, "w", encoding="utf-8").write(TRESC_KOMPONENTU)
    print("   %s (nowy)" % os.path.basename(KOMPONENT))
    zapisz(MOBIL, m)
    zapisz(DESKTOP, d)

    # --- wpis w CMakeLists modulu QML
    if os.path.exists(CMAKE):
        c = czytaj(CMAKE)
        if "QfZnacznikEdycji.qml" not in c:
            # Lista jest ALFABETYCZNA, z czterema spacjami wciecia — wstawiamy
            # we wlasciwe miejsce, zeby nie psuc porzadku przy nastepnym diffie.
            linie = c.splitlines(keepends=True)
            wstawiono = False
            for nr, linia in enumerate(linie):
                nazwa = linia.strip()
                # Tylko wpisy z KORZENIA (bez ukosnika) — podkatalogi
                # sortuja sie inaczej, bo male litery ida po wielkich w ASCII
                # i wpis wladowalby sie miedzy processingparameterwidgets/.
                if nazwa.startswith("Qf") and nazwa.endswith(".qml") \
                        and "/" not in nazwa \
                        and nazwa.rstrip(")") > "QfZnacznikEdycji.qml":
                    linie.insert(nr, "    QfZnacznikEdycji.qml\n")
                    wstawiono = True
                    break
            if not wstawiono:
                # QfZnacznikEdycji jest niemal ostatnie alfabetycznie wsrod Qf*,
                # wiec zwykle nic po nim nie nastepuje. Wtedy wstawiamy po
                # OSTATNIM wpisie z korzenia — a nie na koncu calej listy,
                # gdzie sa juz podkatalogi.
                for nr in range(len(linie) - 1, -1, -1):
                    nazwa = linie[nr].strip().rstrip(")")
                    if nazwa.startswith("Qf") and nazwa.endswith(".qml") \
                            and "/" not in nazwa:
                        linie.insert(nr + 1, "    QfZnacznikEdycji.qml\n")
                        wstawiono = True
                        break
            if wstawiono:
                zapisz(CMAKE, "".join(linie))
                print("      dopisany do CMakeLists (alfabetycznie)")
            else:
                print("      UWAGA: dopisz QfZnacznikEdycji.qml do %s RECZNIE" % CMAKE)

    print("""
NOWY PLIK QML WYMAGA WPISU W CMakeLists — bez tego kompilacja przejdzie,
a komponent nie bedzie znany i dostaniesz „QfZnacznikEdycji is not a type".
Sprawdz powyzej, czy wpis sie dopisal.

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head

W logu MUSI byc 'Running rcc for resource'.

Sprawdzian na desktopie: otworz warstwe do edycji — plakietka ma sie pojawic
OBOK TYTULU na srodku gornej belki.
""")


if __name__ == "__main__":
    main()
