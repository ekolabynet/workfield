#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — OSTRZEZENIE przy wlaczaniu edycji topologicznej.

==========================================================================
DLACZEGO
==========================================================================
24.08.2026 Piotr wlaczyl edycje topologiczna jednym tapnieciem na pasku
rysowania. Komunikat brzmial: **„Topological editing turned on"** — po
angielsku, bez slowa o tym, co to znaczy.

25.08 w terenie punkty przestaly siadac na miejscu przy malych platach.
W danych zostalo: dwa platy 0,00 x 0,00 m, dwa po 10 cm, jeden 40 cm i trzy
nowe puste geometrie. Przyczyne znalezlismy wieczorem, grepujac XML projektu.

**Mechanizm**, `qffeaturemodel.cpp:1489-1494`:

    matches = loc.verticesInRect( originalPoint, searchTolerance );
    for ( int i = 0; i < matches.size(); i++ )
      vectorLayer->moveVertex( change.vertex.point, ... );

Wszystkie wierzcholki znalezione w promieniu laduja w JEDNYM punkcie. Przy
duzym placie w promieniu jest jeden i wyglada to jak dociaganie sasiada.
Przy malym jest ich kilka — i obrys zwija sie do zera.

==========================================================================
DWIE RZECZY, KTORE WPROWADZILY W BLAD — obie sa w tresci ostrzezenia
==========================================================================
**Nazwa.** „Edycja topologiczna" brzmi jak pilnowanie wspolnych granic.
Przy tej sciezce funkcja robi cos innego, niz sugeruje nazwa.

**Zakres.** Piotr zalozyl, ze dziala **tylko przy poprawianiu geometrii**.
Dziala takze **przy tworzeniu** — i to jest zdanie, ktore musi paść wprost.

==========================================================================
CZEGO TA LATKA NIE ROBI
==========================================================================
Nie blokuje wlaczenia. Edycja topologiczna jest przydatna przy duzych
poligonach ze wspolnymi granicami i czasem naprawde jej chcesz — ostrzezenie
ma **poinformowac**, nie zabronic.

Nie rusza komunikatu przy WYLACZANIU: tam nie ma o czym ostrzegac.

Nie tlumaczy angielskiego napisu w kodzie — zgodnie z `claude/MENU_reguly.md`
etykiety upstreamu poprawia sie w `i18n/qfield_pl.ts`, nie w `.qml`, zeby
delta nie rosla. Nasze ostrzezenie to NOWY tekst, wiec moze byc po polsku.

Uruchom w korzeniu repo:  python3 zastosuj_ostrzezenie_topologia.py
Idempotentna. Kopia: QgisMobileapp.qml.przed_ostrzezeniem_topo
"""
import os
import shutil
import sys

Q = "src/app/qml/QgisMobileapp.qml"
MARKER = "zlepia sąsiednie wierzchołki"

KOTWICA = '''          onClicked: {
            qgisProject.topologicalEditing = !qgisProject.topologicalEditing;
            displayToast(qgisProject.topologicalEditing ? qsTr("Topological editing turned on") : qsTr("Topological editing turned off"));
          }'''

NOWE = '''          onClicked: {
            qgisProject.topologicalEditing = !qgisProject.topologicalEditing;
            if (qgisProject.topologicalEditing) {
              // WorkField 26.08.2026 — samo „turned on" kosztowało dzień terenu.
              //
              // 24.08 przełącznik wciśnięty jednym tapnięciem, 25.08 zniszczone
              // obrysy pięciu płatów: przy VertexMove wszystkie wierzchołki
              // znalezione w promieniu lądują w JEDNYM punkcie
              // (qffeaturemodel.cpp:1489), więc mały obiekt zwija się do zera.
              //
              // Dwie rzeczy, które wprowadziły w błąd, mówimy WPROST: nazwa
              // sugeruje pilnowanie wspólnych granic, a zakres — że działa
              // tylko przy poprawianiu. Ani jedno, ani drugie.
              // QML nie skleja sasiednich literalow jak C++ — jeden napis.
              displayToast(qsTr("Edycja topologiczna WŁĄCZONA — przy małych obiektach zlepia sąsiednie wierzchołki w jeden punkt. Działa też przy TWORZENIU, nie tylko przy poprawianiu."), "warning");
            } else {
              displayToast(qsTr("Edycja topologiczna wyłączona"));
            }
          }'''


def main():
    if not os.path.exists(Q):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % Q)

    t = open(Q, encoding="utf-8").read()

    if MARKER in t:
        print("Latka juz jest — nic do zrobienia.")
        return

    n = t.count(KOTWICA)
    if n != 1:
        sys.exit("STOP: kotwica wystepuje %d razy, oczekiwano 1" % n)

    print("Kotwica policzona, nakladam:")
    t = t.replace(KOTWICA, NOWE, 1)
    print("   ostrzezenie przy wlaczaniu edycji topologicznej")

    kopia = Q + ".przed_ostrzezeniem_topo"
    if not os.path.exists(kopia):
        shutil.copy2(Q, kopia)
    open(Q, "w", encoding="utf-8").write(t)
    print("  zapisano %s" % os.path.basename(Q))

    print("""
Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head -3

Sprawdzian: pasek rysowania -> przycisk topologii.
  wlaczenie  -> ostrzezenie na pomaranczowo, z wyjasnieniem
  wylaczenie -> zwykly komunikat
""")


if __name__ == "__main__":
    main()
