#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Poprawka ostrzezen w `stanProjektu` — po diagnozie z 25.08.2026 wieczorem.

==========================================================================
CO BYLO ZLE
==========================================================================

**1. Falszywy alarm o przyciaganiu.**

Ostrzezenie czytalo `snap.typeFlag()` — wartosc GLOBALNA. Ale projekt ma
tryb `AdvancedConfiguration` ("ustawienia per warstwa"), w ktorym liczy sie
`individualLayerSettings()`, a globalna jest IGNOROWANA.

W projekcie 10_0 globalnie stalo `type="3"` (wierzcholek + segment), a przy
warstwach `type="1"` (sam wierzcholek). Ostrzezenie krzyczalo o segmencie,
ktorego nie bylo. **Narzedzie, ktore straszy bez powodu, uczy ludzi je
ignorowac** — a wtedy przestaje dzialac takze wtedy, gdy ma racje.

Przy okazji: poranna poprawka `type="1"` w naglowku `<snapping-settings>`
byla bezuzyteczna z tego samego powodu. Zmienialem wartosc, ktorej nikt
nie czyta.

**2. Prawdziwa przyczyna byla gdzie indziej: EDYCJA TOPOLOGICZNA.**

`qffeaturemodel.cpp:1489-1494`, obsluga `VertexMove`:

    matches = loc.verticesInRect( change.vertex.originalPoint, searchTolerance );
    for ( int i = 0; i < matches.size(); i++ )
      vectorLayer->moveVertex( change.vertex.point, ... );

**Wszystkie wierzcholki znalezione w promieniu laduja w JEDNYM punkcie.**
Przy duzym placie w promieniu jest jeden, wiec wyglada to jak dociaganie
sasiada. Przy malym jest ich kilka — i obrys zwija sie do zera.

Stad w danych z 25.08: dwa platy 0,0 x 0,0 m, dwa po 10 cm, jeden 40 cm
i trzy nowe puste geometrie.

Nazwa myli: "edycja topologiczna" brzmi jak pilnowanie wspolnych granic,
a przy tej sciezce **funkcja robi cos innego, niz sugeruje nazwa**. Piotr
wlaczyl ja 24.08 zakladajac, ze dziala tylko przy poprawianiu geometrii —
dziala takze przy tworzeniu.

**3. Promienia nie da sie ustawic z projektu.**

`QgsTolerance::vertexSearchRadius` (jedyne wywolanie w calym kodzie,
qffeaturemodel.cpp:1479) czyta GLOBALNE ustawienia QGIS-a
(`/qgis/digitizing/search_radius_vertex_edit`), a nie tolerancje
przyciagania z projektu. Zmiana tolerancji w projekcie na to nie wplywa —
warto o tym powiedziec wprost w ostrzezeniu, zeby nikt nie szukal tam,
gdzie nie ma czego znalezc.

==========================================================================
CO ROBI TA POPRAWKA
==========================================================================

- ostrzezenie o przyciaganiu czyta **ustawienia per warstwa**, gdy tryb
  jest `AdvancedConfiguration`; globalne tylko wtedy, gdy naprawde obowiazuja,
- dochodzi **ostrzezenie o edycji topologicznej** przy malych obiektach —
  to ono odpowiedzialoby dzis w sekunde,
- stan edycji topologicznej wchodzi do sekcji `pomiar` jako fakt,
  niezaleznie od ostrzezen.

Uruchom w korzeniu repo:  python3 popraw_stan_ostrzezenia.py
Idempotentna. Kopia: narzedziaprojektu.cpp.przed_ostrzezeniami
"""
import os
import shutil
import sys

C = "src/core/utils/narzedziaprojektu.cpp"
MARKER = "edycja topologiczna"

# --------------------------------------------------- typ przyciagania: per warstwa

STARE_POMIAR = '''  pomiar.insert( QStringLiteral( "przeciecia" ), snap.intersectionSnapping() );
  pomiar.insert( QStringLiteral( "wlasnyObiekt" ), snap.selfSnapping() );'''

NOWE_POMIAR = '''  pomiar.insert( QStringLiteral( "przeciecia" ), snap.intersectionSnapping() );
  pomiar.insert( QStringLiteral( "wlasnyObiekt" ), snap.selfSnapping() );
  pomiar.insert( QStringLiteral( "edycjaTopologiczna" ), projekt->topologicalEditing() );

  // W trybie "ustawienia per warstwa" wartosc GLOBALNA jest ignorowana.
  // Ostrzezenie czytajace ja przy tym trybie krzyczy o czyms, czego nie ma —
  // a narzedzie, ktore straszy bez powodu, uczy ludzi je ignorowac.
  Qgis::SnappingTypes typyObowiazujace = snap.typeFlag();
  if ( snap.mode() == Qgis::SnappingMode::AdvancedConfiguration )
  {
    typyObowiazujace = Qgis::SnappingTypes();
    const auto ustawieniaWarstw = snap.individualLayerSettings();
    for ( auto it = ustawieniaWarstw.constBegin(); it != ustawieniaWarstw.constEnd(); ++it )
    {
      if ( it.value().enabled() )
        typyObowiazujace |= it.value().typeFlag();
    }
    pomiar.insert( QStringLiteral( "typObowiazujacy" ), typySlownie( typyObowiazujace ) );
  }'''

# ----------------------------------------------------------- ostrzezenia

STARE_OSTRZ = '''  if ( ( snap.typeFlag() & Qgis::SnappingType::Segment ) && najmniejszaObwiednia >= 0
       && najmniejszaObwiednia < 2.0 )
    ostrzez( QStringLiteral( "uwaga" ),
             tr( "przyciąganie łapie segment, a najmniejszy obiekt ma %1 m (%2) — "
                 "przy takich rozmiarach wierzchołki zlepiają się w jeden punkt" )
               .arg( najmniejszaObwiednia, 0, 'f', 1 ).arg( najmniejszyObiekt ) );'''

NOWE_OSTRZ = '''  if ( snap.enabled() && ( typyObowiazujace & Qgis::SnappingType::Segment )
       && najmniejszaObwiednia >= 0 && najmniejszaObwiednia < 2.0 )
    ostrzez( QStringLiteral( "uwaga" ),
             tr( "przyciąganie łapie segment, a najmniejszy obiekt ma %1 m (%2) — "
                 "przy takich rozmiarach wierzchołki zlepiają się w jeden punkt" )
               .arg( najmniejszaObwiednia, 0, 'f', 1 ).arg( najmniejszyObiekt ) );

  // Edycja topologiczna przy malych obiektach. TO odpowiedzialoby na pytanie
  // z 25.08 w sekunde: przy VertexMove wszystkie wierzcholki znalezione
  // w promieniu laduja w JEDNYM punkcie (qffeaturemodel.cpp:1489-1494),
  // wiec przy malym placie obrys zwija sie do zera.
  //
  // Promien bierze sie z GLOBALNYCH ustawien QGIS-a, nie z tolerancji
  // przyciagania w projekcie — mowimy o tym wprost, zeby nikt nie szukal
  // tam, gdzie nie ma czego znalezc.
  if ( projekt->topologicalEditing() && najmniejszaObwiednia >= 0
       && najmniejszaObwiednia < 5.0 )
    ostrzez( QStringLiteral( "uwaga" ),
             tr( "edycja topologiczna WŁĄCZONA, a najmniejszy obiekt ma %1 m (%2). "
                 "Przy przesuwaniu wierzchołka wszystkie sąsiednie w promieniu "
                 "trafiają w ten sam punkt — obrys małego obiektu zwija się do zera. "
                 "Działa też przy TWORZENIU, nie tylko przy poprawianiu. "
                 "Promień jest ustawieniem aplikacji, nie projektu." )
               .arg( najmniejszaObwiednia, 0, 'f', 1 ).arg( najmniejszyObiekt ) );'''


def main():
    if not os.path.exists(C):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % C)

    t = open(C, encoding="utf-8").read()

    if MARKER in t:
        print("Poprawka juz jest — nic do zrobienia.")
        return

    for nazwa, stare in (("sekcja pomiar", STARE_POMIAR), ("ostrzezenie", STARE_OSTRZ)):
        n = t.count(stare)
        if n != 1:
            sys.exit("STOP: kotwica '%s' wystepuje %d razy, oczekiwano 1" % (nazwa, n))

    print("Kotwice policzone (2/2), nakladam:")
    t = t.replace(STARE_POMIAR, NOWE_POMIAR, 1)
    print("   typ przyciagania czytany per warstwa")
    t = t.replace(STARE_OSTRZ, NOWE_OSTRZ, 1)
    print("   ostrzezenie o edycji topologicznej")

    kopia = C + ".przed_ostrzezeniami"
    if not os.path.exists(kopia):
        shutil.copy2(C, kopia)
    open(C, "w", encoding="utf-8").write(t)
    print("  zapisano %s (kopia: %s)" % (C, os.path.basename(kopia)))

    print("""
Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error' | head

Sprawdzian: na projekcie 10_0 ostrzezenie o SEGMENCIE ma ZNIKNAC
(bo warstwy maja type=1), a pojawic sie o EDYCJI TOPOLOGICZNEJ —
o ile jest jeszcze wlaczona.
""")


if __name__ == "__main__":
    main()
