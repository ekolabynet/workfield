#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — UCHWYT ZMIANY ROZMIARU dla okien (Popup).

==========================================================================
PO CO
==========================================================================
Okna maja staly rozmiar wpisany w kod. Ekran „Stan projektu" po dolozeniu
sekcji przestal sie miescic — tekst lamal sie po dwa slowa przy 480 px.
Doraznie zmienilismy na polowe szerokosci okna, ale to samo dotyczy galerii,
panelu danych i reszty: **kazde okno ma wlasna wartosc wpisana na sztywno.**

Piotr, 26.08.2026: zmiana rozmiaru za rog, i to dla wszystkich okien.

Zamiast dopisywac uchwyt do kazdego z osobna — JEDEN komponent wstawiany
tam, gdzie potrzeba. Ten sam wzorzec, co `dashBoard.przelaczRysowanie()`
i rejestr akcji: jedno miejsce z zachowaniem, nie trzy kopie.

==========================================================================
TRZY DECYZJE
==========================================================================

**1. Tylko na biurku.** Na telefonie uchwyt w rogu jest bezuzyteczny —
palcem nie trafisz w 16 px, a miejsce zajmuje. `visible` zalezne od
platformy, tak samo jak `desktop: true` w rejestrze akcji.

**2. Granice.** Bez nich da sie zwinac okno do zera (i juz go nie zlapiesz)
albo rozciagnac poza ekran. Minimum 320x200, maksimum — rozmiar okna
glownego minus margines.

**3. Zapamietywanie PER OKNO.** Bez tego przy kazdym otwarciu wracasz do
domyslnego i uchwyt traci sens. Klucz zawiera nazwe okna, bo galeria zdjec
i ekran stanu maja rozne potrzeby — jeden wspolny rozmiar bylby gorszy
niz brak zapamietywania.

Aplikacja ma juz `Settings` do takich rzeczy (`mainWindowSettings` pamieta
polozenie okna glownego), wiec wzorzec istnieje.

==========================================================================
UZYCIE
==========================================================================
W dowolnym Popup, jako ostatni element:

    QfUchwytRozmiaru {
      okno: nazwaOkna
      klucz: "stanProjektu"
    }

Uruchom w korzeniu repo:  python3 zastosuj_uchwyt_rozmiaru.py
Idempotentna. Kopie: <plik>.przed_uchwytem
"""
import os
import shutil
import sys

KOMPONENT = "src/gui/qml/QfUchwytRozmiaru.qml"
CMAKE = "src/gui/qml/CMakeLists.txt"
EKRAN = "src/app/qml/QfNaprawaProjektu.qml"

TRESC = '''import QtQuick
import QtQuick.Controls
import Theme

/**
 * Uchwyt zmiany rozmiaru w prawym dolnym rogu okna.
 *
 * Okna mają rozmiar wpisany w kod. Przy zmianie zawartości trzeba go
 * poprawiać w źródle — a to, co mieści się na biurku, nie mieści się
 * na telefonie i odwrotnie.
 *
 * TYLKO NA BIURKU: palcem nie trafisz w uchwyt 16 px, a miejsce zajmuje.
 *
 * Rozmiar jest ZAPAMIĘTYWANY per okno (klucz w nazwie), bo galeria zdjęć
 * i ekran stanu mają różne potrzeby — jeden wspólny rozmiar byłby gorszy
 * niż brak zapamiętywania.
 *
 * Użycie — jako ostatni element w Popup:
 *
 *     QfUchwytRozmiaru {
 *       okno: nazwaOkna
 *       klucz: "stanProjektu"
 *     }
 */
Item {
  id: uchwyt

  //! Okno do zmiany rozmiaru; zwykle rodzic-Popup
  property var okno: null

  //! Nazwa pod jaką zapamiętać rozmiar. Pusta = bez zapamiętywania.
  property string klucz: ""

  property int minSzerokosc: 320
  property int minWysokosc: 200

  // Palcem nie trafisz, a na małym ekranie i tak nie ma czego powiększać.
  readonly property bool naBiurku: Qt.platform.os !== "android"
                                   && Qt.platform.os !== "ios"

  visible: naBiurku && okno !== null
  width: 18
  height: 18
  anchors.right: parent ? parent.right : undefined
  anchors.bottom: parent ? parent.bottom : undefined
  anchors.margins: 2

  Settings {
    id: zapamietane
  }

  function wczytaj() {
    if (klucz === "" || !okno)
      return;
    const w = zapamietane.valueInt("WorkField/okno_" + klucz + "_szerokosc", 0);
    const h = zapamietane.valueInt("WorkField/okno_" + klucz + "_wysokosc", 0);
    // Zero znaczy „nigdy nie zapisano" — zostawiamy rozmiar z kodu.
    if (w >= minSzerokosc)
      okno.width = Math.min(w, mainWindow.width - 20);
    if (h >= minWysokosc)
      okno.height = Math.min(h, mainWindow.height - 20);
  }

  function zapisz() {
    if (klucz === "" || !okno)
      return;
    zapamietane.setValue("WorkField/okno_" + klucz + "_szerokosc", Math.round(okno.width));
    zapamietane.setValue("WorkField/okno_" + klucz + "_wysokosc", Math.round(okno.height));
  }

  Component.onCompleted: wczytaj()

  // Trzy kreski pod kątem — ten sam znak, co w oknach systemowych.
  Canvas {
    anchors.fill: parent
    opacity: obszar.containsMouse || obszar.drag.active ? 0.9 : 0.4

    onPaint: {
      const ctx = getContext("2d");
      ctx.reset();
      ctx.strokeStyle = Theme.secondaryTextColor;
      ctx.lineWidth = 1.5;
      for (let i = 0; i < 3; i++) {
        const p = 5 + i * 5;
        ctx.beginPath();
        ctx.moveTo(width - p, height - 2);
        ctx.lineTo(width - 2, height - p);
        ctx.stroke();
      }
    }
  }

  MouseArea {
    id: obszar
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.SizeFDiagCursor

    property real startX: 0
    property real startY: 0
    property real startW: 0
    property real startH: 0

    onPressed: function (mouse) {
      startX = mouse.x;
      startY = mouse.y;
      startW = uchwyt.okno.width;
      startH = uchwyt.okno.height;
    }

    onPositionChanged: function (mouse) {
      if (!pressed || !uchwyt.okno)
        return;
      // Granice: bez nich da się zwinąć okno do zera — i już go nie złapiesz,
      // bo uchwyt zniknie razem z oknem.
      uchwyt.okno.width = Math.max(uchwyt.minSzerokosc,
                                   Math.min(mainWindow.width - 20,
                                            startW + (mouse.x - startX)));
      uchwyt.okno.height = Math.max(uchwyt.minWysokosc,
                                    Math.min(mainWindow.height - 20,
                                             startH + (mouse.y - startY)));
    }

    onReleased: uchwyt.zapisz()
  }
}
'''

# ----------------------------------------------------- wstawienie do ekranu

E_KOTWICA = '''  background: Rectangle {
    color: Theme.mainBackgroundColor
    radius: 6
    border.width: 1
    border.color: Theme.controlBorderColor
  }'''

E_NOWE = E_KOTWICA + '''

  // Zmiana rozmiaru za róg — wspólny komponent, bo to samo dotyczy galerii,
  // panelu danych i reszty okien. Na telefonie niewidoczny.
  QfUchwytRozmiaru {
    okno: naprawa
    klucz: "stanProjektu"
  }'''


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def main():
    if os.path.exists(KOMPONENT):
        print("Komponent juz jest — nic do zrobienia.")
        return

    e = czytaj(EKRAN)
    if e.count(E_KOTWICA) != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy — czy tlo jest juz "
                 "poprawione?" % (os.path.basename(EKRAN), e.count(E_KOTWICA)))

    print("Kotwica policzona, nakladam:")

    os.makedirs(os.path.dirname(KOMPONENT), exist_ok=True)
    open(KOMPONENT, "w", encoding="utf-8").write(TRESC)
    print("   %s (nowy)" % os.path.basename(KOMPONENT))

    kopia = EKRAN + ".przed_uchwytem"
    if not os.path.exists(kopia):
        shutil.copy2(EKRAN, kopia)
    open(EKRAN, "w", encoding="utf-8").write(e.replace(E_KOTWICA, E_NOWE, 1))
    print("   uchwyt w ekranie stanu")

    # --- wpis w CMakeLists, alfabetycznie wsrod wpisow z KORZENIA
    if os.path.exists(CMAKE):
        c = czytaj(CMAKE)
        if "QfUchwytRozmiaru.qml" not in c:
            linie = c.splitlines(keepends=True)
            gdzie = -1
            for nr, linia in enumerate(linie):
                nazwa = linia.strip().rstrip(")")
                if nazwa.startswith("Qf") and nazwa.endswith(".qml") \
                        and "/" not in nazwa and nazwa > "QfUchwytRozmiaru.qml":
                    gdzie = nr
                    break
            if gdzie < 0:
                for nr in range(len(linie) - 1, -1, -1):
                    nazwa = linie[nr].strip().rstrip(")")
                    if nazwa.startswith("Qf") and nazwa.endswith(".qml") and "/" not in nazwa:
                        gdzie = nr + 1
                        break
            if gdzie >= 0:
                linie.insert(gdzie, "    QfUchwytRozmiaru.qml\n")
                kopia = CMAKE + ".przed_uchwytem"
                if not os.path.exists(kopia):
                    shutil.copy2(CMAKE, kopia)
                open(CMAKE, "w", encoding="utf-8").write("".join(linie))
                print("   dopisany do CMakeLists")
            else:
                print("   UWAGA: dopisz QfUchwytRozmiaru.qml do %s RECZNIE" % CMAKE)

    print("""
NOWY PLIK QML WYMAGA WPISU W CMakeLists — bez tego kompilacja przejdzie,
a dostaniesz „QfUchwytRozmiaru is not a type". Sprawdz powyzej.

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head

Sprawdzian:
  1. otworz „Stan projektu" -> w prawym dolnym rogu trzy ukosne kreski
  2. przeciagnij -> okno zmienia rozmiar, nie da sie zwinac do zera
  3. zamknij i otworz ponownie -> rozmiar zapamietany
  4. na telefonie uchwytu NIE MA

Do dolozenia w innych oknach — jedna linijka na okno:
  QfUchwytRozmiaru { okno: <id okna>; klucz: "<nazwa>" }
""")


if __name__ == "__main__":
    main()
