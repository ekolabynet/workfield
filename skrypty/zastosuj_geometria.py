#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 29 — czasowniki GEOMETRII w NarzedziaProjektu.

Powod. Edytor geometrii odmawia rozpoczecia pracy, gdy obiekt ma
samoprzeciecie (przypadkowo przeciagniety wierzcholek). Naprawa takiej
"osemki" daje DWIE rozlaczne petle, czyli MULTIPOLYGON — a warstwa
zadeklarowana jako POLYGON takiego obiektu nie przyjmie. W terenie
wyglada to jak "aplikacja sie zacina", a jest to niewazna geometria.

GeometryUtils (upstream) nie ma ani isGeosValid, ani makeValid, ani
combine. Dokladamy je po NASZEJ stronie — NarzedziaProjektu — zeby nie
powiekszac delty w plikach QFielda.

Trzy czasowniki:
  sprawdzGeometrie( warstwa, fid )        -> co jest nie tak i GDZIE
  naprawGeometrie( warstwa, fid, zapisz ) -> makeValid, uczciwie o skutkach
  polaczObiekty( warstwa, [fid...] )      -> zlaczenie poligonow w jeden

Trzy decyzje wpisane w kod, warte przeczytania:

1. NIE ZAMYKAMY CUDZEJ SESJI EDYCJI. Gdy warstwa juz jest w edycji
   (otwarty formularz), zapisujemy do jej bufora i NIE wolamy
   commitChanges. Otwieranie wlasnej sesji obok istniejacej to droga
   do "unable to open database file" z notatki 16.08.

2. NIE ZAPISUJEMY PO CICHU ZMIANY LICZBY OBIEKTOW. Gdy naprawa rozbija
   obiekt na czesci, ktorych warstwa nie przyjmie (coerceToType zwraca
   wiecej niz jedna geometrie) — nic nie zapisujemy i mowimy to wprost.
   Decyzja "z jednego platu robia sie dwa" nalezy do czlowieka.

3. STAN SPRAWDZAMY PO FAKCIE. Wynik changeGeometry nie wystarcza
   (pulapka 5 z 16.08) — po zapisie odczytujemy geometrie z powrotem.

Uruchom w korzeniu repo:  python3 zastosuj_geometria.py
Idempotentna. Kopie zapasowe: <plik>.przed_geometria
"""
import os
import shutil
import sys

H = "src/core/utils/narzedziaprojektu.h"
C = "src/core/utils/narzedziaprojektu.cpp"

# ----------------------------------------------------------------- deklaracje

DEKLARACJE = '''    // -------------------------------------------------------------- geometria

    /**
     * Diagnoza geometrii obiektu. Zwraca mape:
     *   ok              bool   udalo sie sprawdzic (obiekt istnieje, ma geometrie)
     *   wazna           bool   geometria poprawna wg GEOS
     *   wieloczesciowa  bool
     *   czesci          int
     *   bledy           lista map { opis, maMiejsce, x, y }
     *   opis            QString  zdanie do pokazania czlowiekowi
     *
     * Miejsce bledu (x, y w ukladzie warstwy) jest tu najwazniejsze:
     * pozwala pokazac, GDZIE geometria sie przecina, zamiast informowac,
     * ze cos jest nie tak. Osemki na malym ekranie nie widac.
     */
    Q_INVOKABLE QVariantMap sprawdzGeometrie( QgsVectorLayer *warstwa, QgsFeatureId fid ) const;

    /**
     * Naprawa geometrii obiektu (makeValid). Zwraca mape:
     *   ok             bool   naprawiono i zapisano
     *   bylaWazna      bool   nie bylo czego naprawiac
     *   czesciPrzed    int
     *   czesciPo       int
     *   wymagaPodzialu bool   naprawa daje wiecej czesci, niz warstwa przyjmie
     *   opis           QString
     *
     * \\a zapisz = false liczy skutek bez dotykania danych — do pokazania
     * w pytaniu "naprawic?" zanim czlowiek sie zgodzi.
     */
    Q_INVOKABLE QVariantMap naprawGeometrie( QgsVectorLayer *warstwa, QgsFeatureId fid, bool zapisz = true ) const;

    /**
     * Zlaczenie obiektow w jeden. Geometrie sumuje (combine), atrybuty
     * zostaja z PIERWSZEGO fid na liscie, pozostale obiekty sa kasowane.
     * Zwraca mape:
     *   ok        bool
     *   fid       QgsFeatureId  obiekt, ktory zostal
     *   zlaczono  int           ile obiektow weszlo
     *   czesci    int           ile czesci ma wynik
     *   opis      QString
     *
     * Gdy obiekty sie nie stykaja, a warstwa jest jednoczesciowa —
     * nie zapisujemy nic i mowimy dlaczego.
     */
    Q_INVOKABLE QVariantMap polaczObiekty( QgsVectorLayer *warstwa, const QVariantList &fidy, bool zapisz = true ) const;

'''

# ------------------------------------------------------------- implementacje

IMPLEMENTACJE = r'''
// ------------------------------------------------------------------ geometria

QVariantMap NarzedziaProjektu::sprawdzGeometrie( QgsVectorLayer *warstwa, QgsFeatureId fid ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );
  wynik.insert( QStringLiteral( "wazna" ), false );
  wynik.insert( QStringLiteral( "wieloczesciowa" ), false );
  wynik.insert( QStringLiteral( "czesci" ), 0 );
  wynik.insert( QStringLiteral( "bledy" ), QVariantList() );
  wynik.insert( QStringLiteral( "opis" ), QString() );

  if ( !warstwa )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Brak warstwy." ) );
    return wynik;
  }

  const QgsFeature obiekt = warstwa->getFeature( fid );
  const QgsGeometry geom = obiekt.geometry();
  if ( geom.isNull() || geom.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Obiekt nie ma geometrii." ) );
    return wynik;
  }

  const bool wazna = geom.isGeosValid();
  const bool wielo = geom.isMultipart();
  const int czesci = geom.constGet() ? geom.constGet()->partCount() : 0;

  QVector<QgsGeometry::Error> bledy;
  geom.validateGeometry( bledy, Qgis::GeometryValidationEngine::QgisInternal );

  QVariantList listaBledow;
  for ( int i = 0; i < bledy.size(); ++i )
  {
    const QgsGeometry::Error &blad = bledy.at( i );
    QVariantMap m;
    m.insert( QStringLiteral( "opis" ), blad.what() );
    m.insert( QStringLiteral( "maMiejsce" ), blad.hasWhere() );
    if ( blad.hasWhere() )
    {
      m.insert( QStringLiteral( "x" ), blad.where().x() );
      m.insert( QStringLiteral( "y" ), blad.where().y() );
    }
    listaBledow << m;
  }

  QString opis;
  if ( wazna && !wielo )
    opis = tr( "Geometria poprawna." );
  else if ( wazna && wielo )
    opis = tr( "Geometria poprawna, ale obiekt ma %1 części." ).arg( czesci );
  else if ( !bledy.isEmpty() )
    opis = tr( "Geometria niepoprawna: %1" ).arg( bledy.at( 0 ).what() );
  else
    opis = tr( "Geometria niepoprawna." );

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "wazna" ), wazna );
  wynik.insert( QStringLiteral( "wieloczesciowa" ), wielo );
  wynik.insert( QStringLiteral( "czesci" ), czesci );
  wynik.insert( QStringLiteral( "bledy" ), listaBledow );
  wynik.insert( QStringLiteral( "opis" ), opis );
  return wynik;
}

QVariantMap NarzedziaProjektu::naprawGeometrie( QgsVectorLayer *warstwa, QgsFeatureId fid, bool zapisz ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );
  wynik.insert( QStringLiteral( "bylaWazna" ), false );
  wynik.insert( QStringLiteral( "czesciPrzed" ), 0 );
  wynik.insert( QStringLiteral( "czesciPo" ), 0 );
  wynik.insert( QStringLiteral( "wymagaPodzialu" ), false );
  wynik.insert( QStringLiteral( "opis" ), QString() );

  if ( !warstwa )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Brak warstwy." ) );
    return wynik;
  }

  const QgsFeature obiekt = warstwa->getFeature( fid );
  const QgsGeometry geom = obiekt.geometry();
  if ( geom.isNull() || geom.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Obiekt nie ma geometrii." ) );
    return wynik;
  }

  const int czesciPrzed = geom.constGet() ? geom.constGet()->partCount() : 0;
  wynik.insert( QStringLiteral( "czesciPrzed" ), czesciPrzed );

  if ( geom.isGeosValid() )
  {
    wynik.insert( QStringLiteral( "ok" ), true );
    wynik.insert( QStringLiteral( "bylaWazna" ), true );
    wynik.insert( QStringLiteral( "czesciPo" ), czesciPrzed );
    wynik.insert( QStringLiteral( "opis" ), tr( "Geometria była poprawna — nic nie zmieniono." ) );
    return wynik;
  }

  const QgsGeometry naprawiona = geom.makeValid();
  if ( naprawiona.isNull() || naprawiona.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Nie udało się naprawić geometrii." ) );
    return wynik;
  }

  // Czy warstwa w ogole przyjmie taki ksztalt? coerceToType tnie wynik na
  // tyle geometrii, ile potrzeba, zeby zmiescic go w typie warstwy.
  const QVector<QgsGeometry> dopasowane = naprawiona.coerceToType( warstwa->wkbType() );
  if ( dopasowane.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Naprawiona geometria nie pasuje do typu warstwy." ) );
    return wynik;
  }

  if ( dopasowane.size() > 1 )
  {
    // Swiadomie nie zapisujemy: to zmiana LICZBY obiektow, nie ksztaltu.
    wynik.insert( QStringLiteral( "wymagaPodzialu" ), true );
    wynik.insert( QStringLiteral( "czesciPo" ), dopasowane.size() );
    wynik.insert( QStringLiteral( "opis" ),
                  tr( "Naprawa rozdziela obiekt na %1 osobne obiekty, a warstwa przyjmuje pojedyncze. "
                      "Popraw wierzchołki ręcznie albo rozdziel obiekt świadomie." )
                    .arg( dopasowane.size() ) );
    return wynik;
  }

  QgsGeometry docelowa = dopasowane.at( 0 );
  const int czesciPo = docelowa.constGet() ? docelowa.constGet()->partCount() : 0;
  wynik.insert( QStringLiteral( "czesciPo" ), czesciPo );

  if ( !zapisz )
  {
    wynik.insert( QStringLiteral( "ok" ), true );
    wynik.insert( QStringLiteral( "opis" ), czesciPo > czesciPrzed
                                              ? tr( "Naprawa da obiekt z %1 częściami." ).arg( czesciPo )
                                              : tr( "Naprawa da poprawną geometrię." ) );
    return wynik;
  }

  // Cudzej sesji edycji nie zamykamy — piszemy do jej bufora.
  const bool bylaEdycja = warstwa->isEditable();
  if ( !bylaEdycja && !warstwa->startEditing() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Nie udało się otworzyć warstwy do edycji." ) );
    return wynik;
  }

  warstwa->changeGeometry( fid, docelowa );

  if ( !bylaEdycja && !warstwa->commitChanges() )
  {
    warstwa->rollBack();
    wynik.insert( QStringLiteral( "opis" ), tr( "Zapis naprawionej geometrii nie powiódł się." ) );
    return wynik;
  }

  // Stan sprawdzamy PO fakcie, nie z wartosci zwracanej.
  const QgsGeometry poZapisie = warstwa->getFeature( fid ).geometry();
  const bool udalo = !poZapisie.isNull() && poZapisie.isGeosValid();

  wynik.insert( QStringLiteral( "ok" ), udalo );
  wynik.insert( QStringLiteral( "opis" ), udalo
                                            ? ( czesciPo > czesciPrzed
                                                  ? tr( "Naprawiono — obiekt ma teraz %1 części." ).arg( czesciPo )
                                                  : tr( "Naprawiono." ) )
                                            : tr( "Po zapisie geometria nadal jest niepoprawna." ) );
  return wynik;
}

QVariantMap NarzedziaProjektu::polaczObiekty( QgsVectorLayer *warstwa, const QVariantList &fidy, bool zapisz ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );
  wynik.insert( QStringLiteral( "fid" ), static_cast<qlonglong>( -1 ) );
  wynik.insert( QStringLiteral( "zlaczono" ), 0 );
  wynik.insert( QStringLiteral( "czesci" ), 0 );
  wynik.insert( QStringLiteral( "opis" ), QString() );

  if ( !warstwa )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Brak warstwy." ) );
    return wynik;
  }

  if ( fidy.size() < 2 )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Do złączenia potrzebne są co najmniej dwa obiekty." ) );
    return wynik;
  }

  QList<QgsFeatureId> lista;
  for ( int i = 0; i < fidy.size(); ++i )
  {
    const QgsFeatureId f = static_cast<QgsFeatureId>( fidy.at( i ).toLongLong() );
    if ( !lista.contains( f ) )
      lista << f;
  }

  QgsGeometry suma;
  for ( int i = 0; i < lista.size(); ++i )
  {
    const QgsGeometry g = warstwa->getFeature( lista.at( i ) ).geometry();
    if ( g.isNull() || g.isEmpty() )
      continue;

    // Niepoprawne skladniki psuja wynik combine — prostujemy je po drodze.
    const QgsGeometry skladnik = g.isGeosValid() ? g : g.makeValid();
    if ( skladnik.isNull() || skladnik.isEmpty() )
      continue;

    suma = suma.isNull() ? skladnik : suma.combine( skladnik );
    if ( suma.isNull() )
    {
      wynik.insert( QStringLiteral( "opis" ), tr( "Nie udało się złączyć geometrii." ) );
      return wynik;
    }
  }

  if ( suma.isNull() || suma.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Wskazane obiekty nie mają geometrii." ) );
    return wynik;
  }

  const QVector<QgsGeometry> dopasowane = suma.coerceToType( warstwa->wkbType() );
  if ( dopasowane.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Wynik złączenia nie pasuje do typu warstwy." ) );
    return wynik;
  }

  if ( dopasowane.size() > 1 )
  {
    wynik.insert( QStringLiteral( "czesci" ), dopasowane.size() );
    wynik.insert( QStringLiteral( "opis" ),
                  tr( "Obiekty nie stykają się — złączenie dałoby %1 osobnych obiektów, "
                      "a warstwa przyjmuje pojedyncze." )
                    .arg( dopasowane.size() ) );
    return wynik;
  }

  QgsGeometry docelowa = dopasowane.at( 0 );
  const QgsFeatureId zostaje = lista.at( 0 );
  wynik.insert( QStringLiteral( "fid" ), static_cast<qlonglong>( zostaje ) );
  wynik.insert( QStringLiteral( "zlaczono" ), lista.size() );
  wynik.insert( QStringLiteral( "czesci" ), docelowa.constGet() ? docelowa.constGet()->partCount() : 0 );

  if ( !zapisz )
  {
    wynik.insert( QStringLiteral( "ok" ), true );
    wynik.insert( QStringLiteral( "opis" ), tr( "Złączenie %1 obiektów jest możliwe." ).arg( lista.size() ) );
    return wynik;
  }

  const bool bylaEdycja = warstwa->isEditable();
  if ( !bylaEdycja && !warstwa->startEditing() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Nie udało się otworzyć warstwy do edycji." ) );
    return wynik;
  }

  warstwa->changeGeometry( zostaje, docelowa );
  for ( int i = 1; i < lista.size(); ++i )
    warstwa->deleteFeature( lista.at( i ) );

  if ( !bylaEdycja && !warstwa->commitChanges() )
  {
    warstwa->rollBack();
    wynik.insert( QStringLiteral( "opis" ), tr( "Zapis złączenia nie powiódł się." ) );
    return wynik;
  }

  const QgsGeometry poZapisie = warstwa->getFeature( zostaje ).geometry();
  const bool udalo = !poZapisie.isNull() && !poZapisie.isEmpty();

  wynik.insert( QStringLiteral( "ok" ), udalo );
  wynik.insert( QStringLiteral( "opis" ), udalo
                                            ? tr( "Złączono %1 obiektów w jeden." ).arg( lista.size() )
                                            : tr( "Po zapisie obiekt nie ma geometrii." ) );
  return wynik;
}
'''

# ------------------------------------------------------------------- mechanika

KOTWICA_H = "    // ---------------------------------------------------------------- stempel"
KOTWICA_INC_1 = "#include <qgsattributeeditorcontainer.h>"
KOTWICA_INC_2 = "#include <qgslayertree.h>"

ZNACZNIK = "sprawdzGeometrie"


def czytaj(sciezka):
    if not os.path.exists(sciezka):
        sys.exit("STOP: brak pliku %s (uruchom w korzeniu repo)" % sciezka)
    with open(sciezka, encoding="utf-8") as f:
        return f.read()


def raz(tresc, kotwica, plik):
    n = tresc.count(kotwica)
    if n != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1:\n  %s"
                 % (plik, n, kotwica.strip()))


def zapisz(sciezka, tresc):
    kopia = sciezka + ".przed_geometria"
    if not os.path.exists(kopia):
        shutil.copy2(sciezka, kopia)
    with open(sciezka, "w", encoding="utf-8") as f:
        f.write(tresc)
    print("  zapisano %s (kopia: %s)" % (sciezka, os.path.basename(kopia)))


def main():
    h = czytaj(H)
    c = czytaj(C)

    if ZNACZNIK in h and ZNACZNIK in c:
        print("Latka 29 juz jest — nic do zrobienia.")
        return

    if (ZNACZNIK in h) != (ZNACZNIK in c):
        sys.exit("STOP: latka nalozona polowicznie (naglowek i implementacja "
                 "sie rozjezdzaja). Przywroc kopie .przed_geometria i sprobuj ponownie.")

    raz(h, KOTWICA_H, H)
    raz(c, KOTWICA_INC_1, C)
    raz(c, KOTWICA_INC_2, C)

    print("Kotwice policzone, nakladam:")

    h = h.replace(KOTWICA_H, DEKLARACJE + KOTWICA_H)
    zapisz(H, h)

    c = c.replace(KOTWICA_INC_1, "#include <qgsabstractgeometry.h>\n" + KOTWICA_INC_1)
    c = c.replace(KOTWICA_INC_2, "#include <qgsgeometry.h>\n" + KOTWICA_INC_2)
    if not c.endswith("\n"):
        c += "\n"
    c += IMPLEMENTACJE
    zapisz(C, c)

    print("\nGotowe. Trzy nowe czasowniki: sprawdzGeometrie, naprawGeometrie, polaczObiekty.")
    print("Teraz build desktop:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | tail -30")


if __name__ == "__main__":
    main()
