#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — WSKAZNIK STANU EDYCJI na gornej belce.

==========================================================================
PO CO
==========================================================================
20.08.2026 wtyczka „Zrobione" v0.2 zostawila warstwe w OTWARTEJ SESJI EDYCJI.
Skutek w terenie: nowe obiekty przestaly sie dodawac, edycja byla odrzucana
bez slowa, kafel znikal z paska. Diagnoza zajela caly dzien.

Przyczyna dlaczego tak dlugo: **otwarta sesja wyglada dokladnie tak samo jak
zamknieta.** Gorna belka pokazuje nazwe warstwy i nic wiecej.

25.08 Piotr poprosil o wskaznik. Ta latka go dodaje.

==========================================================================
TRZY STANY, NIE DWA
==========================================================================
  zamknieta                   — plakietki nie ma
  otwarta sesja, bez zmian    — „EDYCJA"
  otwarta sesja ze zmianami   — „EDYCJA N" (N = liczba zmian w buforze)

**Srodkowy stan jest tym, ktory kosztowal dzien.** Sesja wisiala otwarta,
zmian nie bylo, wiec nic nie wygladalo podejrzanie — a kazdy nastepny zapis
sie odbijal.

DLACZEGO PLAKIETKA TEKSTOWA, A NIE KOLOROWA KROPKA

W rekawicach i w slonecznym swietle kolor bywa nieczytelny, a przy
odblaskach ekranu — niewidoczny. To jest informacja, ktorej przeoczenie
kosztowalo dzien pracy; ma byc czytelna, nie elegancka.

==========================================================================
DLACZEGO POTRZEBNY CZASOWNIK W C++
==========================================================================
`QgsVectorLayer::isEditable()` (qgsvectorlayer.h:1635) i `isModified()`
(:1641) sa **zwyklymi metodami publicznymi** — ani `Q_PROPERTY`, ani
`Q_INVOKABLE`. Z QML ich nie widac; potwierdzone 22.08 przy wtyczce
Zrobione, sprawdzone ponownie 25.08.

Za to SYGNALY sa dostepne, bo mieszkaja w `QgsMapLayer`:
`editingStarted()` (:2198), `editingStopped()` (:2204), `layerModified()`
(:2210). QML moze sie na nie podpiac przez `Connections`.

Czyli: **C++ odpowiada „jaki jest stan", QML sluchа „kiedy sie zmienil".**
Bez sygnalow plakietka odswiezalaby sie dopiero przy przelaczeniu warstwy —
czyli nie wtedy, kiedy trzeba.

Uruchom w korzeniu repo:  python3 zastosuj_wskaznik_edycji.py
Idempotentna. Kopie: <plik>.przed_wskaznikiem
"""
import os
import shutil
import sys

H = "src/core/utils/qflayerutils.h"
C = "src/core/utils/qflayerutils.cpp"
Q = "src/app/qml/QgisMobileapp.qml"
MARKER = "stanEdycji"

# ------------------------------------------------------------------ naglowek

H_KOTWICA = "    static Q_INVOKABLE QColor symbolColor( QgsVectorLayer *layer );"

H_NOWE = '''    /**
     * Stan sesji edycji warstwy — dla wskaźnika na górnej belce.
     *
     * Zwraca mapę: `wEdycji` (bool), `zmian` (int), `edytowalna` (bool).
     *
     * W C++, bo `QgsVectorLayer::isEditable()` i `isModified()` są zwykłymi
     * metodami publicznymi — z QML ich nie widać. Sygnały `editingStarted`,
     * `editingStopped` i `layerModified` są za to dostępne, więc QML słucha
     * ich i pyta o stan przez ten czasownik.
     */
    static Q_INVOKABLE QVariantMap stanEdycji( QgsVectorLayer *layer );

'''

# --------------------------------------------------------------- implementacja

C_KOTWICA = "QColor QfLayerUtils::symbolColor( QgsVectorLayer *layer )"

C_NOWE = r'''QVariantMap QfLayerUtils::stanEdycji( QgsVectorLayer *layer )
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "wEdycji" ), false );
  wynik.insert( QStringLiteral( "zmian" ), 0 );
  wynik.insert( QStringLiteral( "edytowalna" ), false );

  if ( !layer )
    return wynik;

  wynik.insert( QStringLiteral( "edytowalna" ), layer->supportsEditing() );

  const bool wEdycji = layer->isEditable();
  wynik.insert( QStringLiteral( "wEdycji" ), wEdycji );
  if ( !wEdycji )
    return wynik;

  // Liczba zmian w buforze. Rozróżnienie „sesja otwarta, ale pusta" od
  // „sesja otwarta ze zmianami" jest tu istotą: 20.08.2026 sesja wisiała
  // otwarta BEZ zmian i właśnie dlatego nic nie wyglądało podejrzanie,
  // a każdy kolejny zapis się odbijał.
  int zmian = 0;
  if ( QgsVectorLayerEditBuffer *bufor = layer->editBuffer() )
  {
    zmian = bufor->addedFeatures().count()
            + bufor->changedGeometries().count()
            + bufor->changedAttributeValues().count()
            + bufor->deletedFeatureIds().count();
  }
  wynik.insert( QStringLiteral( "zmian" ), zmian );
  return wynik;
}

'''

C_INCLUDE_KOTWICA = '#include "qflayerutils.h"'
C_INCLUDE_NOWE = '''#include "qflayerutils.h"

#include <qgsvectorlayereditbuffer.h>'''

# ------------------------------------------------------------------- belka

Q_KOTWICA = '''        Text {
          Layout.fillWidth: true
          text: dashBoard.activeLayer ? dashBoard.activeLayer.name : qsTr("Brak aktywnej warstwy")
          color: Theme.mainOverlayColor
          font.pointSize: Theme.tipFont.pointSize
          font.bold: true
          elide: Text.ElideRight
        }'''

Q_NOWE = '''        Text {
          Layout.fillWidth: true
          text: dashBoard.activeLayer ? dashBoard.activeLayer.name : qsTr("Brak aktywnej warstwy")
          color: Theme.mainOverlayColor
          font.pointSize: Theme.tipFont.pointSize
          font.bold: true
          elide: Text.ElideRight
        }

        // WorkField 25.08.2026 — wskaźnik OTWARTEJ SESJI EDYCJI.
        //
        // 20.08 wtyczka zostawiła warstwę w otwartej sesji: nowe obiekty
        // przestały się dodawać, edycja była odrzucana bez słowa, kafel
        // znikał z paska. Diagnoza zajęła cały dzień — bo otwarta sesja
        // wygląda dokładnie tak samo jak zamknięta.
        //
        // Plakietka tekstowa, nie kolorowa kropka: w rękawicach i w słońcu
        // kolor bywa nieczytelny, a to informacja, której przeoczenie
        // kosztowało dzień pracy.
        Rectangle {
          id: znacznikEdycji

          property var stan: ({ wEdycji: false, zmian: 0 })

          function odswiez() {
            stan = dashBoard.activeLayer
                 ? LayerUtils.stanEdycji(dashBoard.activeLayer)
                 : ({ wEdycji: false, zmian: 0 });
          }

          visible: stan.wEdycji
          Layout.preferredWidth: tekstEdycji.implicitWidth + 12
          Layout.preferredHeight: tekstEdycji.implicitHeight + 4
          radius: 3
          // Zmiany w buforze to stan, w którym WOLNO stracić dane —
          // stąd mocniejszy kolor niż przy pustej sesji.
          color: stan.zmian > 0 ? Theme.warningColor : Theme.mainColor

          Text {
            id: tekstEdycji
            anchors.centerIn: parent
            text: znacznikEdycji.stan.zmian > 0
                  ? qsTr("EDYCJA %1").arg(znacznikEdycji.stan.zmian)
                  : qsTr("EDYCJA")
            color: "white"
            font.pointSize: Theme.tinyFont.pointSize
            font.bold: true
          }

          // Sygnały mieszkają w QgsMapLayer i SĄ widoczne z QML — inaczej
          // niż isEditable(). Bez nich plakietka odświeżałaby się dopiero
          // przy przełączeniu warstwy, czyli nie wtedy, kiedy trzeba.
          Connections {
            target: dashBoard.activeLayer
            ignoreUnknownSignals: true
            function onEditingStarted() { znacznikEdycji.odswiez(); }
            function onEditingStopped() { znacznikEdycji.odswiez(); }
            function onLayerModified() { znacznikEdycji.odswiez(); }
          }

          Connections {
            target: dashBoard
            function onActiveLayerChanged() { znacznikEdycji.odswiez(); }
          }

          Component.onCompleted: odswiez()
        }'''


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def raz(t, kotwica, p):
    n = t.count(kotwica)
    if n != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1:\n  %s"
                 % (p, n, kotwica.strip().splitlines()[0][:60]))


def main():
    h, c, q = czytaj(H), czytaj(C), czytaj(Q)

    if MARKER in h and MARKER in c and MARKER in q:
        print("Latka juz jest — nic do zrobienia.")
        return
    if MARKER in h or MARKER in c or MARKER in q:
        sys.exit("STOP: latka polowiczna. Przywroc kopie .przed_wskaznikiem.")

    raz(h, H_KOTWICA, H)
    raz(c, C_KOTWICA, C)
    raz(q, Q_KOTWICA, Q)
    raz(c, C_INCLUDE_KOTWICA, C)

    print("Kotwice policzone (4/4), nakladam:")

    h = h.replace(H_KOTWICA, H_NOWE + H_KOTWICA, 1)
    c = c.replace(C_INCLUDE_KOTWICA, C_INCLUDE_NOWE, 1)
    c = c.replace(C_KOTWICA, C_NOWE + C_KOTWICA, 1)
    q = q.replace(Q_KOTWICA, Q_NOWE, 1)

    for p, tresc, opis in ((H, h, "czasownik stanEdycji"),
                           (C, c, "implementacja + include"),
                           (Q, q, "plakietka na belce")):
        kopia = p + ".przed_wskaznikiem"
        if not os.path.exists(kopia):
            shutil.copy2(p, kopia)
        open(p, "w", encoding="utf-8").write(tresc)
        print("   %-26s %s" % (opis, os.path.basename(p)))

    print("""
Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head

W logu MUSI być 'Running rcc for resource' — inaczej QML poszedł ze starego
zasobu i plakietki nie zobaczysz mimo poprawnej kompilacji.

Sprawdzian na desktopie:
  1. wybierz warstwę wektorową jako aktywną
  2. zacznij edycję (dodaj obiekt) -> plakietka „EDYCJA"
  3. nanieś zmianę bez zapisu     -> „EDYCJA 1", kolor ostrzegawczy
  4. zapisz albo cofnij           -> plakietka znika
""")


if __name__ == "__main__":
    main()
