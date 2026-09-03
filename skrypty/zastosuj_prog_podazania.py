#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — PROG ODSWIEZANIA MAPY przy podazaniu za pozycja.

==========================================================================
OBJAW
==========================================================================
Piotr, 03.09.2026: *„Kiedy jest wlaczone podazanie mapy za pozycja, to ona
NIE PODAZA. Przesuwa sie wskaznik. Zmieniaja sie wspolrzedne."*

Po ponownym wlaczeniu podazania mapa **skacze** do biezacej pozycji —
i znowu staje.

==========================================================================
PRZYCZYNA — zmierzona, nie zgadnieta
==========================================================================
`followLocation` (`QgisMobileapp.qml:3680`) wola `setCenter` przy KAZDEJ
nowej pozycji, wiec mapa logicznie podaza. Ale przerysowanie kafli
nastepuje dopiero, gdy:

    triggerRecenter = |skala - 1| > 0.25
                   || |wrapper.x| > szerokosc/2
                   || |wrapper.y| > wysokosc/2

Czyli **po przesunieciu o POL EKRANU**. Plotno jest przy tym zamrozone
(`freeze('follow')` przy wlaczaniu podazania), wiec nie odswieza sie samo.

Stad trzy objawy naraz:
  * wskaznik sie rusza — rysuje sie osobno, poza plotnem,
  * wspolrzedne rosna — pochodza wprost z odbiornika,
  * podklad stoi — czeka na przekroczenie progu.

Rozstrzygnal dwutapnieciowy sprawdzian: po wylaczeniu i wlaczeniu podazania
mapa SKACZE we wlasciwe miejsce. Czyli `setCenter` dziala — problem byl
wylacznie w progu przerysowania.

W upstreamie to oszczednosc: mniej rysowania przy powolnym ruchu. Ale przy
inwentaryzacji pol ekranu to kilkadziesiat metrow — czlowiek przechodzi
caly plat, zanim mapa drgnie.

==========================================================================
CO ROBI
==========================================================================
Prog z polowy ekranu na **10%**, z wartoscia w ustawieniach pozycjonowania.

Dziesiec procent to okolo 80 px na telefonie w pionie — mapa nadaza za
chodzeniem, a nie przerysowuje sie przy kazdym drgnieciu pozycji RTK,
ktore przy dokladnosci centymetrowej zdarza sie co sekunde.

**Koszt: czestsze rysowanie, wiec wiecej baterii.** Stad ustawienie —
przy pomiarach stacjonarnych mozna podniesc z powrotem.

Wartosc jest OGRANICZANA do 2-50 przy uzyciu, wiec nawet zla wartosc
w ustawieniach nie zatrzyma mapy na dobre.

Uruchom w korzeniu repo:  python3 zastosuj_prog_podazania.py
Idempotentna. Kopie: <plik>.przed_progiem
"""
import os
import shutil
import sys

Q = "src/app/qml/QgisMobileapp.qml"
S = "src/app/qml/QfPositioningSettings.qml"

Q_KOTWICA = """          const triggerRecenter = Math.abs(Math.abs(mapCanvasMap.mapCanvasWrapper.scale) - 1) > 0.25 || Math.abs(mapCanvasMap.mapCanvasWrapper.x) > (mainWindow.width / 2) || Math.abs(mapCanvasMap.mapCanvasWrapper.y) > (mainWindow.height / 2);"""

Q_NOWE = """          // WorkField 03.09.2026 — PROG ODSWIEZANIA.
          //
          // Bylo `/ 2`, czyli mapa przerysowywala sie dopiero po przesunieciu
          // o POL EKRANU. Plotno jest przy podazaniu zamrozone
          // (`freeze('follow')`), wiec nie odswieza sie samo — i wygladalo to
          // jak stanie w miejscu: wskaznik sie ruszal, wspolrzedne rosly,
          // podklad stal.
          //
          // Przy inwentaryzacji pol ekranu to kilkadziesiat metrow — czlowiek
          // przechodzi caly plat, zanim mapa drgnie.
          //
          // Domyslnie 10%. Wyzej = rzadsze rysowanie i dluzsza bateria,
          // nizej = mapa nadaza scislej. Ograniczenie 2-50 chroni przed
          // wartoscia, ktora zatrzymalaby mape na dobre.
          const udzialProgu = Math.min(50, Math.max(2, positioningSettings.progOdswiezaniaMapy || 10)) / 100;
          const triggerRecenter = Math.abs(Math.abs(mapCanvasMap.mapCanvasWrapper.scale) - 1) > 0.25 || Math.abs(mapCanvasMap.mapCanvasWrapper.x) > (mainWindow.width * udzialProgu) || Math.abs(mapCanvasMap.mapCanvasWrapper.y) > (mainWindow.height * udzialProgu);"""

S_KOTWICA = "  property bool accuracyIndicator: false"

S_NOWE = '''  //! Prog odswiezania mapy przy podazaniu za pozycja, w procentach ekranu.
  //!
  //! Bylo 50 na sztywno (pol ekranu) i przy inwentaryzacji wygladalo jak
  //! stanie w miejscu — czlowiek przechodzil caly plat, zanim mapa drgnela.
  //!
  //! Nizej = mapa nadaza scislej, wyzej = rzadsze rysowanie i dluzsza
  //! bateria. Zakres uzyteczny 2-50.
  property int progOdswiezaniaMapy: 10

  property bool accuracyIndicator: false'''


def main():
    for p in (Q, S):
        if not os.path.exists(p):
            sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)

    q = open(Q, encoding="utf-8").read()
    s = open(S, encoding="utf-8").read()

    if "progOdswiezaniaMapy" in q and "progOdswiezaniaMapy" in s:
        print("Latka juz jest — nic do zrobienia.")
        return

    n = q.count(Q_KOTWICA)
    if n != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1"
                 % (os.path.basename(Q), n))
    m = s.count(S_KOTWICA)
    if m != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1"
                 % (os.path.basename(S), m))

    print("Kotwice policzone (2/2), nakladam:")

    kopia = S + ".przed_progiem"
    if not os.path.exists(kopia):
        shutil.copy2(S, kopia)
    open(S, "w", encoding="utf-8").write(s.replace(S_KOTWICA, S_NOWE, 1))
    print("   wlasciwosc progOdswiezaniaMapy    %s" % os.path.basename(S))

    kopia = Q + ".przed_progiem"
    if not os.path.exists(kopia):
        shutil.copy2(Q, kopia)
    open(Q, "w", encoding="utf-8").write(q.replace(Q_KOTWICA, Q_NOWE, 1))
    print("   prog 10 procent zamiast polowy    %s" % os.path.basename(Q))

    print("""
Kolejnosc ma znaczenie: wlasciwosc dodana PRZED uzyciem, wiec nie ma
chwili, w ktorej wyrazenie odwoluje sie do nieistniejacej wartosci.
Dodatkowo `|| 10` w wyrazeniu — na wypadek, gdyby ustawienia jeszcze
sie nie wczytaly.

ZOSTAJE suwak na karcie „Teren" (QfTerenSettings.qml), zakres 2-50 —
bez niego wartosc zmienia sie tylko w kodzie.

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head -3

Sprawdzian w terenie: wlacz podazanie i idz. Mapa ma nadazac po
kilkunastu metrach, nie po polowie ekranu.

Do sprzatniecia przy okazji: wypisania `console.log("PODAZANIE...")`
w QgisMobileapp.qml — dwa miejsca, dodane do diagnozy.
""")


if __name__ == "__main__":
    main()
