#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — COFNIJ i PRZYWROC na gornej belce.

==========================================================================
DLACZEGO TO W OGOLE POTRZEBNE
==========================================================================
20.08.2026 wtyczka „Zrobione" v0.2 zmienila 261 obiektow i zostawila warstwe
w otwartej sesji. Ratunkiem byl **eksport warstwy do osobnego pliku
i import z powrotem** — pol dnia terenu plus wieczor przy komputerze.

**A cofanie w aplikacji BYLO.** `QfFeatureHistory` istnieje, dziala, ma
`undo()`, `redo()`, `isUndoAvailable`, `undoMessage()`. Podpiete
w `QgisMobileapp.qml:4245-4290`.

Tylko siedzi w **menu kontekstowym mapy**, po dlugim przytrzymaniu,
z etykietami **po angielsku** („Undo", „Redo") — kod z upstreamu, ktorego
nikt nie tlumaczyl. Piotr, zapytany 26.08: „nic mi nie wiadomo na temat
cofania. Moze jest schowane."

To jest **odwrotnosc zasady z 17.08**: nie „widoczne i prowadzace donikad",
tylko **dzialajace i niewidoczne**. Rownie kosztowne.

==========================================================================
GDZIE — decyzja Piotra 26.08
==========================================================================
NIE na pasku `digitizingDrawer` (gdzie sa przyciski przyciagania
i topologii), bo ten jest widoczny **tylko w trybie rysowania**
(`stateMachine.state === "digitize"`). Cofanie byloby wtedy niedostepne
dokladnie wtedy, gdy jest najbardziej potrzebne: PO zapisaniu, gdy czlowiek
orientuje sie, ze cos poszlo zle.

Gorna belka, obok olowka i wskaznika sesji — bo **cofanie dotyczy edycji
w ogole, nie samej geometrii**. Tam zebralo sie juz wszystko o biezacej
pracy z warstwa.

==========================================================================
CZEGO NIE RUSZAMY — swiadomie
==========================================================================
**Historia zostaje w PAMIECI.** `QfFeatureHistory` nie zapisuje nic na dysk
(sprawdzone: zero `QSqlDatabase`, `sqlite`, `QFile`), wiec ginie przy
zamknieciu aplikacji. To zalozenie upstreamu; zmiana dotykalaby zapisu
danych, a te dzialaja.

Skutek uboczny warto znac: **20.08 cofanie i tak by nie pomoglo**, bo
restart byl pierwsza rzecza, ktora Piotr zrobil. Trwala historia
(`WF_JOURNAL`) zostaje na liscie jako osobna, wieksza robota.

**Wyszarzony przycisk MOWI, czemu nie dziala.** Sam `enabled: false` w
terenie nie odroznia „nie ma czego cofnac" od „zepsulo sie" — stad
komunikat po tapnieciu.

Uruchom w korzeniu repo:  python3 zastosuj_cofanie_belka.py
Idempotentna. Kopie: <plik>.przed_cofaniem
"""
import os
import shutil
import sys

KOMPONENT = "src/gui/qml/QfCofnijPrzywroc.qml"
CMAKE = "src/gui/qml/CMakeLists.txt"
DESKTOP = "src/app/qml/QfDesktopChrome.qml"
MOBIL = "src/app/qml/QgisMobileapp.qml"

TRESC = '''import QtQuick
import QtQuick.Controls

import org.qfield
import Theme

/**
 * Cofnij i przywróć — para przycisków na górną belkę.
 *
 * Mechanizm (`QfFeatureHistory`) istnieje w upstreamie i działa, ale siedzi
 * w menu kontekstowym mapy, po angielsku. 20.08.2026 ratunkiem po awarii
 * był eksport warstwy i import z powrotem — pół dnia terenu — mimo że
 * cofanie było pod ręką.
 *
 * HISTORIA ŻYJE DO ZAMKNIĘCIA APLIKACJI: QfFeatureHistory nie zapisuje nic
 * na dysk. Po restarcie nie ma czego cofać. To założenie upstreamu, którego
 * świadomie nie ruszamy.
 *
 * Rozmiar przycisków zależny od platformy: w rękawicy mniejszy niż 40 px
 * jest nietrafialny.
 */
Row {
  id: para

  readonly property bool naTelefonie: Qt.platform.os === "android"
                                      || Qt.platform.os === "ios"
  readonly property int bok: naTelefonie ? 40 : 26

  spacing: 2

  QfToolButton {
    id: przyciskCofnij
    width: para.bok
    height: para.bok
    padding: 0
    round: true

    readonly property bool mozna: featureHistory && featureHistory.isUndoAvailable

    iconSource: Theme.getThemeVectorIcon("ic_undo_black_24dp")
    iconColor: "white"
    bgcolor: "transparent"
    opacity: mozna ? 0.85 : 0.3

    onClicked: {
      // Wyszarzony przycisk, który milczy, nie odróżnia „nie ma czego
      // cofnąć" od „zepsuło się". W terenie to różnica między spokojem
      // a szukaniem awarii.
      if (!mozna) {
        displayToast(qsTr("Nie ma czego cofnąć"), "warning");
        return;
      }
      const opis = featureHistory.undoMessage();
      if (featureHistory.undo())
        displayToast(opis !== "" ? qsTr("Cofnięto: %1").arg(opis) : qsTr("Cofnięto"));
      else
        displayToast(qsTr("Nie udało się cofnąć"), "warning");
    }
  }

  QfToolButton {
    id: przyciskPrzywroc
    width: para.bok
    height: para.bok
    padding: 0
    round: true

    readonly property bool mozna: featureHistory && featureHistory.isRedoAvailable

    iconSource: Theme.getThemeVectorIcon("ic_redo_black_24dp")
    iconColor: "white"
    bgcolor: "transparent"
    opacity: mozna ? 0.85 : 0.3

    onClicked: {
      if (!mozna) {
        displayToast(qsTr("Nie ma czego przywrócić"), "warning");
        return;
      }
      const opis = featureHistory.redoMessage();
      if (featureHistory.redo())
        displayToast(opis !== "" ? qsTr("Przywrócono: %1").arg(opis) : qsTr("Przywrócono"));
      else
        displayToast(qsTr("Nie udało się przywrócić"), "warning");
    }
  }
}
'''

# --------------------------------------------------------------- biurkowa

D_KOTWICA = '''    QfZnacznikEdycji {
      anchors.verticalCenter: parent.verticalCenter
      warstwa: dashBoard.activeLayer
    }'''

D_NOWE = '''    QfZnacznikEdycji {
      anchors.verticalCenter: parent.verticalCenter
      warstwa: dashBoard.activeLayer
    }

    // Cofnij / przywróć. Na belce, nie na pasku rysowania: tamten jest
    // widoczny tylko w trybie digitize, a cofanie potrzebne jest PO zapisie.
    QfCofnijPrzywroc {
      anchors.verticalCenter: parent.verticalCenter
    }'''

# ----------------------------------------------------------------- mobilna

M_KOTWICA = '''        // Wskaźnik otwartej sesji edycji — wspólny komponent, bo ta sama
        // plakietka jest też na belce biurkowej (QfDesktopChrome).
        QfZnacznikEdycji {
          Layout.alignment: Qt.AlignVCenter
          warstwa: dashBoard.activeLayer
        }'''

M_NOWE = '''        // Wskaźnik otwartej sesji edycji — wspólny komponent, bo ta sama
        // plakietka jest też na belce biurkowej (QfDesktopChrome).
        QfZnacznikEdycji {
          Layout.alignment: Qt.AlignVCenter
          warstwa: dashBoard.activeLayer
        }

        // Cofnij / przywróć — w terenie potrzebne bardziej niż na biurku,
        // bo tam awaria kosztuje dzień, a nie pięć minut.
        QfCofnijPrzywroc {
          Layout.alignment: Qt.AlignVCenter
        }'''


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def main():
    if os.path.exists(KOMPONENT):
        print("Komponent juz jest — nic do zrobienia.")
        return

    d, m = czytaj(DESKTOP), czytaj(MOBIL)

    for nazwa, tresc, kotwica, plik in (("belka biurkowa", d, D_KOTWICA, DESKTOP),
                                        ("belka mobilna", m, M_KOTWICA, MOBIL)):
        n = tresc.count(kotwica)
        if n != 1:
            sys.exit("STOP: kotwica '%s' w %s wystepuje %d razy, oczekiwano 1.\n"
                     "Czy latka wskaznika edycji jest nalozona?"
                     % (nazwa, os.path.basename(plik), n))

    print("Kotwice policzone (2/2), nakladam:")

    os.makedirs(os.path.dirname(KOMPONENT), exist_ok=True)
    open(KOMPONENT, "w", encoding="utf-8").write(TRESC)
    print("   %s (nowy)" % os.path.basename(KOMPONENT))

    for p, tresc, kotwica, nowe, opis in (
            (DESKTOP, d, D_KOTWICA, D_NOWE, "belka biurkowa"),
            (MOBIL, m, M_KOTWICA, M_NOWE, "belka mobilna")):
        kopia = p + ".przed_cofaniem"
        if not os.path.exists(kopia):
            shutil.copy2(p, kopia)
        open(p, "w", encoding="utf-8").write(tresc.replace(kotwica, nowe, 1))
        print("   %-18s %s" % (opis, os.path.basename(p)))

    # --- CMakeLists, alfabetycznie wsrod wpisow z KORZENIA
    if os.path.exists(CMAKE):
        c = czytaj(CMAKE)
        if "QfCofnijPrzywroc.qml" not in c:
            linie = c.splitlines(keepends=True)
            gdzie = -1
            for nr, linia in enumerate(linie):
                nazwa = linia.strip().rstrip(")")
                if nazwa.startswith("Qf") and nazwa.endswith(".qml") \
                        and "/" not in nazwa and nazwa > "QfCofnijPrzywroc.qml":
                    gdzie = nr
                    break
            if gdzie < 0:
                for nr in range(len(linie) - 1, -1, -1):
                    nazwa = linie[nr].strip().rstrip(")")
                    if nazwa.startswith("Qf") and nazwa.endswith(".qml") and "/" not in nazwa:
                        gdzie = nr + 1
                        break
            if gdzie >= 0:
                linie.insert(gdzie, "    QfCofnijPrzywroc.qml\n")
                kopia = CMAKE + ".przed_cofaniem"
                if not os.path.exists(kopia):
                    shutil.copy2(CMAKE, kopia)
                open(CMAKE, "w", encoding="utf-8").write("".join(linie))
                print("   dopisany do CMakeLists")
            else:
                print("   UWAGA: dopisz QfCofnijPrzywroc.qml do %s RECZNIE" % CMAKE)

    print("""
Ikony `ic_undo_black_24dp` i `ic_redo_black_24dp` sa juz uzywane przez menu
kontekstowe (QgisMobileapp.qml:4252, :4272), wiec istnieja.

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head -3

Sprawdzian:
  1. bez zmian: oba przyciski przygaszone, tapniecie -> „Nie ma czego cofnac"
  2. dodaj obiekt i zapisz -> „Cofnij" sie rozjasnia
  3. tapnij -> obiekt znika, komunikat z opisem operacji
  4. „Przywroc" sie rozjasnia, tapniecie wraca obiekt
  5. PO RESTARCIE aplikacji historia jest pusta — tak dziala upstream
""")


if __name__ == "__main__":
    main()
