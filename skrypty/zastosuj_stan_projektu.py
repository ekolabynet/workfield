#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — czasownik `stanProjektu`: co aplikacja NAPRAWDE widzi.

==========================================================================
SKAD SIE WZIAL
==========================================================================
25.08.2026, teren: punkty nie siadaly na wlasciwym miejscu przy malych
platach. Przyczyne znalezlismy dopiero wieczorem, przy komputerze, grepujac
XML projektu: `type="3" tolerance="12"` — przyciaganie lapalo wierzcholek
I segment naraz, a przy malym placie 12 pikseli to znaczna czesc obiektu.

W danych zostal slad: dwa platy 0,0 x 0,0 m, dwa po 10 cm, jeden 40 cm,
i dziewiec z pusta geometria (wczoraj bylo szesc). Obrys zwijal sie do zera.

**Zadnej z tych rzeczy nie dalo sie sprawdzic w terenie.** Aplikacja nie ma
jak odpowiedziec na pytanie "co jest teraz ustawione i czy z moimi danymi
jest wszystko w porzadku".

==========================================================================
CO ROBI
==========================================================================
Jeden czasownik `NarzedziaProjektu::stanProjektu( projekt )` zwracajacy mape
z czterema sekcjami. QML tylko ja rysuje.

**warstwy** — nazwa, plik, tabela, geometria, liczba obiektow, edytowalna,
    **czy jest W EDYCJI**, widoczna
**pomiar** — przyciaganie i unikanie nakladania, SLOWNIE
**dane** — gdzie pisze plikDanych(), czy jest wf_wskazniki.gpkg, tabele ZAL_
**ostrzezenia** — liczone Z DANYCH, nie z ustawien

DLACZEGO C++, A NIE QML

Dwie rzeczy sa z QML NIEWIDOCZNE, a tu potrzebne:

1. `QgsVectorLayer::isEditable()` nie jest Q_INVOKABLE (potwierdzone
   22.08 przy wtyczce Zrobione). Z C++ czyta sie normalnie — czyli ten sam
   czasownik zalatwia przy okazji **wskaznik edycji na gornej belce**,
   o ktory Piotr prosil 25.08.
2. `QgsSnappingConfig` nie ma odpowiednika w QML; `NarzedziaProjektu`
   ma dotad tylko ZAPIS (`przyciaganie()`), bez odczytu.

DLACZEGO SLOWNIE, NIE LICZBAMI

`type=3` nic nie mowi. "wierzcholek i segment" mowi wszystko — i to wlasnie
ta liczba kosztowala dzien terenu. Zrzut, ktory trzeba tlumaczyc, jest
zrzutem do niczego.

OSTRZEZENIA LICZONE Z DANYCH — i po co

Sam zrzut stanu **nie zlapalby dzisiejszej awarii**: `type=3` to poprawne
ustawienie, nie blad. Dopiero zestawienie "przyciaganie lapie segment przy
tolerancji 12 px" z "najmniejszy plat ma 40 cm" mowi, ze cos jest nie tak.

Dlatego osobno liczymy:
  - obiekty o zerowej albo znikomej obwiedni (zwiniete wierzcholki),
  - obiekty z PUSTA geometria — nie NULL, tylko bit 4 flag naglowka GPKG:
    istnieja, maja atrybuty, nie widac ich i nie da sie ich zaznaczyc,
  - warstwy wskazujace na plik SPOZA katalogu projektu (nie pojada
    ze zleceniem),
  - brak wf_wskazniki.gpkg (24.08: przez to milczaly metadane gatunkow).

CZEGO NIE ROBI

Nie naprawia. Nie ocenia, czy ustawienie jest dobre — poza jawnymi
ostrzezeniami. Nie czyta pliku .qgs z dysku: pokazuje ZYWY projekt, czyli
to, co aplikacja widzi teraz, lacznie ze zmianami niezapisanymi. Porownanie
dwoch plikow to robota biurowa i tam wystarczy Python.

Uruchom w korzeniu repo:  python3 zastosuj_stan_projektu.py
Idempotentna. Kopie: <plik>.przed_stanem
"""
import os
import shutil
import sys

H = "src/core/utils/narzedziaprojektu.h"
C = "src/core/utils/narzedziaprojektu.cpp"
MARKER = "stanProjektu"

# ------------------------------------------------------------------ naglowek

H_KOTWICA = "    Q_INVOKABLE QString plikDanych( QgsProject *projekt ) const;"

H_NOWE = '''    /**
     * Zrzut stanu ŻYWEGO projektu — co aplikacja naprawdę widzi.
     *
     * Zwraca mapę z sekcjami: `warstwy`, `pomiar`, `dane`, `ostrzezenia`.
     * Wartości opisowe są **słownie**, nie liczbowo: `type=3` nic nie mówi
     * człowiekowi w rękawicach, a to właśnie ta liczba kosztowała dzień
     * terenu 25.08.2026.
     *
     * W C++, bo dwie potrzebne tu rzeczy są z QML niewidoczne:
     * `QgsVectorLayer::isEditable()` nie jest Q_INVOKABLE, a
     * `QgsSnappingConfig` nie ma odpowiednika w QML.
     */
    Q_INVOKABLE QVariantMap stanProjektu( QgsProject *projekt ) const;

'''

# --------------------------------------------------------------- implementacja

C_KOTWICA = "QString NarzedziaProjektu::plikDanych( QgsProject *projekt ) const"

C_NOWE = r'''namespace
{
  //! `type=3` nic nie mowi. "wierzcholek i segment" mowi wszystko.
  QString typySlownie( Qgis::SnappingTypes typy )
  {
    QStringList czesci;
    if ( typy & Qgis::SnappingType::Vertex )
      czesci << QObject::tr( "wierzchołek" );
    if ( typy & Qgis::SnappingType::Segment )
      czesci << QObject::tr( "segment" );
    if ( typy & Qgis::SnappingType::Area )
      czesci << QObject::tr( "obszar" );
    if ( typy & Qgis::SnappingType::Centroid )
      czesci << QObject::tr( "środek ciężkości" );
    if ( typy & Qgis::SnappingType::MiddleOfSegment )
      czesci << QObject::tr( "środek segmentu" );
    if ( typy & Qgis::SnappingType::LineEndpoint )
      czesci << QObject::tr( "koniec linii" );
    return czesci.isEmpty() ? QObject::tr( "nic" ) : czesci.join( QStringLiteral( " + " ) );
  }

  QString trybSlownie( Qgis::SnappingMode tryb )
  {
    switch ( tryb )
    {
      case Qgis::SnappingMode::ActiveLayer:
        return QObject::tr( "warstwa aktywna" );
      case Qgis::SnappingMode::AllLayers:
        return QObject::tr( "wszystkie warstwy" );
      case Qgis::SnappingMode::AdvancedConfiguration:
        return QObject::tr( "ustawienia per warstwa" );
    }
    return QObject::tr( "nieznany" );
  }

  QString jednostkaSlownie( Qgis::MapToolUnit jednostka )
  {
    switch ( jednostka )
    {
      case Qgis::MapToolUnit::Layer:
        return QObject::tr( "jednostki warstwy" );
      case Qgis::MapToolUnit::Project:
        return QObject::tr( "jednostki mapy" );
      case Qgis::MapToolUnit::Pixels:
        return QObject::tr( "piksele ekranu" );
    }
    return QObject::tr( "nieznane" );
  }

  QString geometriaSlownie( Qgis::GeometryType typ )
  {
    switch ( typ )
    {
      case Qgis::GeometryType::Point:
        return QObject::tr( "punkt" );
      case Qgis::GeometryType::Line:
        return QObject::tr( "linia" );
      case Qgis::GeometryType::Polygon:
        return QObject::tr( "poligon" );
      case Qgis::GeometryType::Unknown:
        return QObject::tr( "nieznana" );
      case Qgis::GeometryType::Null:
        return QObject::tr( "tabela" );
    }
    return QObject::tr( "nieznana" );
  }
}

QVariantMap NarzedziaProjektu::stanProjektu( QgsProject *projekt ) const
{
  QVariantMap wynik;
  if ( !projekt )
    return wynik;

  QVariantList warstwy;
  QVariantList ostrzezenia;

  auto ostrzez = [&ostrzezenia]( const QString &waga, const QString &tekst ) {
    QVariantMap o;
    o.insert( QStringLiteral( "waga" ), waga );
    o.insert( QStringLiteral( "opis" ), tekst );
    ostrzezenia.append( o );
  };

  const QString katalog = QFileInfo( projekt->fileName() ).absolutePath();
  double najmniejszaObwiednia = -1.0;
  QString najmniejszyObiekt;

  const auto mapaWarstw = projekt->mapLayers();
  for ( auto it = mapaWarstw.constBegin(); it != mapaWarstw.constEnd(); ++it )
  {
    QgsVectorLayer *wektor = qobject_cast<QgsVectorLayer *>( it.value() );
    if ( !wektor )
      continue;

    QVariantMap w;
    w.insert( QStringLiteral( "nazwa" ), wektor->name() );
    w.insert( QStringLiteral( "geometria" ), geometriaSlownie( wektor->geometryType() ) );
    w.insert( QStringLiteral( "obiektow" ), static_cast<qlonglong>( wektor->featureCount() ) );

    // isEditable() NIE jest Q_INVOKABLE — z QML tego nie widać. Stąd cała
    // ta klasa: to jest odpowiedź na wskaźnik edycji na górnej belce.
    w.insert( QStringLiteral( "edytowalna" ), wektor->isEditable() );
    w.insert( QStringLiteral( "wEdycji" ), wektor->isEditable() && wektor->isModified() );

    const QString zrodlo = wektor->source().section( QLatin1Char( '|' ), 0, 0 );
    const QString tabela = wektor->source().contains( QLatin1String( "layername=" ) )
                             ? wektor->source().section( QLatin1String( "layername=" ), 1, 1 ).section( QLatin1Char( '|' ), 0, 0 )
                             : QString();
    w.insert( QStringLiteral( "plik" ), QFileInfo( zrodlo ).fileName() );
    w.insert( QStringLiteral( "tabela" ), tabela );

    // Warstwa wskazująca poza katalog projektu nie pojedzie ze zleceniem —
    // na telefonie będzie pusta i nikt tego nie zauważy przed wyjazdem.
    const bool wKatalogu = !katalog.isEmpty()
                           && QFileInfo( zrodlo ).absolutePath().startsWith( katalog );
    w.insert( QStringLiteral( "wKatalogu" ), wKatalogu || zrodlo.isEmpty() );
    if ( !zrodlo.isEmpty() && !wKatalogu && wektor->providerType() == QLatin1String( "ogr" ) )
      ostrzez( QStringLiteral( "uwaga" ),
               tr( "warstwa „%1” wskazuje poza katalog projektu — nie pojedzie w teren" )
                 .arg( wektor->name() ) );

    // Obiekty zwinięte do punktu i puste geometrie. Liczone Z DANYCH,
    // bo z samych ustawień tego nie widać.
    if ( wektor->geometryType() == Qgis::GeometryType::Polygon )
    {
      int puste = 0;
      QgsFeature obiekt;
      QgsFeatureIterator iterator = wektor->getFeatures();
      while ( iterator.nextFeature( obiekt ) )
      {
        const QgsGeometry geom = obiekt.geometry();
        if ( geom.isNull() )
          continue;
        if ( geom.isEmpty() )
        {
          ++puste;
          continue;
        }
        const QgsRectangle obw = geom.boundingBox();
        const double bok = std::max( obw.width(), obw.height() );
        if ( najmniejszaObwiednia < 0 || bok < najmniejszaObwiednia )
        {
          najmniejszaObwiednia = bok;
          najmniejszyObiekt = QStringLiteral( "%1 / fid %2" ).arg( wektor->name() ).arg( obiekt.id() );
        }
      }
      if ( puste > 0 )
        ostrzez( QStringLiteral( "brak" ),
                 tr( "„%1”: %2 obiektów z PUSTĄ geometrią — istnieją, "
                     "ale nie widać ich na mapie i nie da się ich zaznaczyć" )
                   .arg( wektor->name() ).arg( puste ) );
    }

    warstwy.append( w );
  }

  // --------------------------------------------------------------- pomiar
  const QgsSnappingConfig snap = projekt->snappingConfig();
  QVariantMap pomiar;
  pomiar.insert( QStringLiteral( "przyciaganieWlaczone" ), snap.enabled() );
  pomiar.insert( QStringLiteral( "tryb" ), trybSlownie( snap.mode() ) );
  pomiar.insert( QStringLiteral( "typ" ), typySlownie( snap.typeFlag() ) );
  pomiar.insert( QStringLiteral( "tolerancja" ), snap.tolerance() );
  pomiar.insert( QStringLiteral( "jednostka" ), jednostkaSlownie( snap.units() ) );
  pomiar.insert( QStringLiteral( "przeciecia" ), snap.intersectionSnapping() );
  pomiar.insert( QStringLiteral( "wlasnyObiekt" ), snap.selfSnapping() );

  const int trybNakladania = projekt->readNumEntry( QStringLiteral( "Digitizing" ),
                                                    QStringLiteral( "/AvoidIntersectionsMode" ), 0 );
  const QStringList listaNakladania = projekt->readListEntry( QStringLiteral( "Digitizing" ),
                                                              QStringLiteral( "/AvoidIntersectionsList" ) );
  QStringList nazwyNakladania;
  for ( const QString &id : listaNakladania )
  {
    if ( QgsMapLayer *w = projekt->mapLayer( id ) )
      nazwyNakladania << w->name();
  }
  pomiar.insert( QStringLiteral( "unikanieNakladania" ), trybNakladania == 2 );
  pomiar.insert( QStringLiteral( "warstwyNakladania" ), nazwyNakladania );

  // Zestawienie USTAWIENIA z DANYMI — sam zrzut stanu nie złapałby awarii
  // z 25.08, bo type=3 jest poprawnym ustawieniem. Dopiero razem z rozmiarem
  // najmniejszego obiektu widać, że coś jest nie tak.
  if ( ( snap.typeFlag() & Qgis::SnappingType::Segment ) && najmniejszaObwiednia >= 0
       && najmniejszaObwiednia < 2.0 )
    ostrzez( QStringLiteral( "uwaga" ),
             tr( "przyciąganie łapie segment, a najmniejszy obiekt ma %1 m (%2) — "
                 "przy takich rozmiarach wierzchołki zlepiają się w jeden punkt" )
               .arg( najmniejszaObwiednia, 0, 'f', 1 ).arg( najmniejszyObiekt ) );

  if ( najmniejszaObwiednia >= 0 && najmniejszaObwiednia < 0.5 )
    ostrzez( QStringLiteral( "brak" ),
             tr( "obiekt o obwiedni %1 m (%2) — to nie jest płat, tylko zlepione wierzchołki" )
               .arg( najmniejszaObwiednia, 0, 'f', 2 ).arg( najmniejszyObiekt ) );

  // ----------------------------------------------------------------- dane
  QVariantMap dane;
  const QString plik = plikDanych( projekt );
  dane.insert( QStringLiteral( "plikDanych" ), QFileInfo( plik ).fileName() );
  dane.insert( QStringLiteral( "katalog" ), katalog );

  const bool maWskazniki = !katalog.isEmpty()
                           && QFileInfo::exists( katalog + QStringLiteral( "/wf_wskazniki.gpkg" ) );
  dane.insert( QStringLiteral( "wskazniki" ), maWskazniki );
  if ( !maWskazniki )
    ostrzez( QStringLiteral( "brak" ),
             tr( "brak wf_wskazniki.gpkg — metadane gatunków i podpowiadanie nie zadziałają" ) );

  if ( plik.isEmpty() )
    ostrzez( QStringLiteral( "brak" ),
             tr( "projekt nie ma pliku z danymi — dziennik Nieba nie ma dokąd pisać" ) );

  wynik.insert( QStringLiteral( "warstwy" ), warstwy );
  wynik.insert( QStringLiteral( "pomiar" ), pomiar );
  wynik.insert( QStringLiteral( "dane" ), dane );
  wynik.insert( QStringLiteral( "ostrzezenia" ), ostrzezenia );
  return wynik;
}

'''

C_INCLUDE_KOTWICA = "#include <qgssnappingconfig.h>"


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
    h, c = czytaj(H), czytaj(C)

    if MARKER in h and "NarzedziaProjektu::stanProjektu" in c:
        print("Latka juz jest — nic do zrobienia.")
        return
    if MARKER in h or "NarzedziaProjektu::stanProjektu" in c:
        sys.exit("STOP: latka polowiczna. Przywroc kopie .przed_stanem.")

    raz(h, H_KOTWICA, H)
    raz(c, C_KOTWICA, C)

    print("Kotwice policzone (2/2), nakladam:")

    h = h.replace(H_KOTWICA, H_NOWE + H_KOTWICA, 1)
    c = c.replace(C_KOTWICA, C_NOWE + C_KOTWICA, 1)

    if C_INCLUDE_KOTWICA not in c:
        print("  UWAGA: brak #include <qgssnappingconfig.h> — dopisz recznie")

    for p, tresc in ((H, h), (C, c)):
        kopia = p + ".przed_stanem"
        if not os.path.exists(kopia):
            shutil.copy2(p, kopia)
        open(p, "w", encoding="utf-8").write(tresc)
        print("  zapisano %s (kopia: %s)" % (p, os.path.basename(kopia)))

    print("""
Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error' | head

Sprawdzenie z konsoli QML albo z QfKontrolaProjektu:
  const s = NarzedziaProjektu.stanProjektu(qgisProject);
  console.log(JSON.stringify(s.pomiar));
  console.log(JSON.stringify(s.ostrzezenia));

Ekran do tego to OSOBNA latka — najpierw sprawdzmy, czy dane sa te,
ktorych potrzeba w terenie.
""")


if __name__ == "__main__":
    main()
