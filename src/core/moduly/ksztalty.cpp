/***************************************************************************
  ksztalty.cpp - Ksztalty (WorkFieldGIS)

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "ksztalty.h"

#include <cmath>
#include <vector>

#include <QDebug>
#include <QPointF>

#include <qgsabstractgeometry.h>
#include <qgscircle.h>
#include <qgscircularstring.h>
#include <qgscompoundcurve.h>
#include <qgscoordinatereferencesystem.h>
#include <qgscurvepolygon.h>
#include <qgslinestring.h>
#include <qgspoint.h>
#include <qgspointxy.h>
#include <qgspolygon.h>
#include <qgsquadrilateral.h>
#include <qgsvectorlayer.h>

///@cond PRIVATE

/**
 * Punkt z QML-a moze przyjechac na pieć sposobow i kazdy z nich jest
 * poprawny gdzie indziej: `QgsPoint` z silnika, `QgsPointXY` ze starszych
 * miejsc QFielda, `QPointF` z czystego QML-a, lista `[x, y]` z JSON-a
 * i mapa `{x, y}` z modelu. Wolimy przyjac wszystkie, niz zmuszac pasek
 * do konwersji — jeden blad w konwersji po tamtej stronie konczy sie
 * ksztaltem w okolicach zera, czyli u wybrzezy Afryki.
 */
static bool naPunkt( const QVariant &v, QgsPoint &wynik )
{
  // `QgsPoint` NIE ma w QGIS-ie `Q_DECLARE_METATYPE`, wiec `value<QgsPoint>()`
  // nie skompilowaloby sie pod Qt5 (piaskownica), choc pod Qt6 (telefon) tak.
  // Bierzemy go po NAZWIE TYPU — to dokladnie to, co robi `value<T>()` w
  // srodku, tylko bez wymogu identyfikatora znanego w czasie kompilacji.
  // Nazwa jest sprawdzona, wiec rzutowanie nie ma na czym sie pomylic.
  if ( qstrcmp( v.typeName(), "QgsPoint" ) == 0 && v.constData() )
  {
    const QgsPoint *p = reinterpret_cast<const QgsPoint *>( v.constData() );
    if ( !std::isnan( p->x() ) && !std::isnan( p->y() ) )
    {
      wynik = QgsPoint( p->x(), p->y() );
      return true;
    }
    return false;
  }
  if ( v.canConvert<QgsPointXY>() )
  {
    const QgsPointXY p = v.value<QgsPointXY>();
    wynik = QgsPoint( p.x(), p.y() );
    return !std::isnan( p.x() ) && !std::isnan( p.y() );
  }
  if ( v.canConvert<QgsGeometry>() )
  {
    const QgsGeometry g = v.value<QgsGeometry>();
    if ( !g.isNull() && !g.isEmpty() )
    {
      const QgsPointXY p = g.asPoint();
      wynik = QgsPoint( p.x(), p.y() );
      return true;
    }
  }
  if ( v.canConvert<QPointF>() )
  {
    const QPointF p = v.toPointF();
    wynik = QgsPoint( p.x(), p.y() );
    return true;
  }
  if ( v.userType() == QMetaType::QVariantList )
  {
    const QVariantList l = v.toList();
    if ( l.size() >= 2 )
    {
      wynik = QgsPoint( l.at( 0 ).toDouble(), l.at( 1 ).toDouble() );
      return true;
    }
  }
  if ( v.userType() == QMetaType::QVariantMap )
  {
    const QVariantMap m = v.toMap();
    if ( m.contains( QStringLiteral( "x" ) ) && m.contains( QStringLiteral( "y" ) ) )
    {
      wynik = QgsPoint( m.value( QStringLiteral( "x" ) ).toDouble(),
                        m.value( QStringLiteral( "y" ) ).toDouble() );
      return true;
    }
  }
  return false;
}

//! Cala lista naraz; pusto, gdy ktorykolwiek punkt jest nie do odczytania.
static QVector<QgsPoint> naPunkty( const QVariantList &lista )
{
  QVector<QgsPoint> w;
  w.reserve( lista.size() );
  for ( const QVariant &v : lista )
  {
    QgsPoint p;
    if ( !naPunkt( v, p ) )
      return QVector<QgsPoint>();
    w.append( p );
  }
  return w;
}

/**
 * Przedzial wezlowy, w ktorym lezy `u` (NURBS Book, alg. A2.1).
 *
 * `n` to liczba punktow kontrolnych, `p` stopien. Dla `u` na samym koncu
 * dziedziny zwracamy ostatni przedzial, a nie ten za nim — inaczej
 * ostatni punkt krzywej wypadlby poza tablica.
 */
static int przedzial( const std::vector<double> &wezly, int n, int p, double u )
{
  if ( u >= wezly[static_cast<size_t>( n )] )
    return n - 1;
  if ( u <= wezly[static_cast<size_t>( p )] )
    return p;

  int lo = p;
  int hi = n;
  int sr = ( lo + hi ) / 2;
  while ( u < wezly[static_cast<size_t>( sr )] || u >= wezly[static_cast<size_t>( sr ) + 1] )
  {
    if ( u < wezly[static_cast<size_t>( sr )] )
      hi = sr;
    else
      lo = sr;
    sr = ( lo + hi ) / 2;
  }
  return sr;
}

/**
 * Nazwa ksztaltu sprowadzona do jednej postaci.
 *
 * `QLatin1String( "prostokąt" )` NIE porowna sie z `QString`-iem: w zrodle
 * „ą" to dwa bajty UTF-8, a `QLatin1String` czyta bajty jak Latin-1, wiec
 * widzi dwa znaki zamiast jednego. Porownanie po cichu wychodzi falszywe
 * i pasek dostaje pusta geometrie bez slowa wyjasnienia. Zdejmujemy wiec
 * ogonki tutaj i dalej porownujemy juz samo ASCII.
 */
static QString klucz( const QString &ksztalt )
{
  QString k = ksztalt.trimmed().toLower();
  k.replace( QChar( 0x0105 ), QLatin1Char( 'a' ) );  // ą
  k.replace( QChar( 0x0119 ), QLatin1Char( 'e' ) );  // ę
  k.replace( QChar( 0x00F3 ), QLatin1Char( 'o' ) );  // ó
  k.replace( QChar( 0x0142 ), QLatin1Char( 'l' ) );  // ł
  k.replace( QChar( 0x015B ), QLatin1Char( 's' ) );  // ś
  k.replace( QChar( 0x017C ), QLatin1Char( 'z' ) );  // ż
  k.replace( QChar( 0x017A ), QLatin1Char( 'z' ) );  // ź
  k.replace( QChar( 0x0107 ), QLatin1Char( 'c' ) );  // ć
  k.replace( QChar( 0x0144 ), QLatin1Char( 'n' ) );  // ń
  return k;
}

//! Wspolne cialo obu wejsc do okregu — bez podrozy przez QVariant.
static QgsGeometry okragZ( const QgsPoint &srodek, double promien, int segmentow )
{
  // Promien zero to nie korona, tylko tapniecie dwa razy w to samo miejsce.
  if ( !( promien > 0 ) || std::isnan( promien ) || std::isinf( promien ) )
    return QgsGeometry();

  const int seg = std::max( 8, std::min( 4096, segmentow ) );

  const QgsCircle kolo( srodek, promien );
  QgsPolygon *wielokat = kolo.toPolygon( static_cast<unsigned int>( seg ) );
  if ( !wielokat )
    return QgsGeometry();

  return QgsGeometry( wielokat );
}

///@endcond

Ksztalty::Ksztalty( QObject *parent )
  : QObject( parent )
{
}

void Ksztalty::setBokMetry( double bok )
{
  // Ponizej milimetra nie ma sensu: to juz szum pomiaru, a wierzcholkow
  // przybywa wykladniczo. Zero i mniej znaczy „zostaw stare 72".
  const double nowy = ( bok > 0 && bok < 0.001 ) ? 0.001 : bok;
  if ( qFuzzyCompare( mBokMetry, nowy ) )
    return;
  mBokMetry = nowy;
  emit bokMetryChanged();
}

void Ksztalty::setMaksWierzcholkow( int maks )
{
  // Osmiokat to najmniej, co jeszcze wyglada jak okrag.
  const int nowy = std::max( 8, maks );
  if ( mMaksWierzcholkow == nowy )
    return;
  mMaksWierzcholkow = nowy;
  emit maksWierzcholkowChanged();
}

void Ksztalty::setKrzywaPrzezPunkty( bool przez )
{
  if ( mKrzywaPrzezPunkty == przez )
    return;
  mKrzywaPrzezPunkty = przez;
  emit krzywaPrzezPunktyChanged();
}

void Ksztalty::setChmurkaLuk( double luk )
{
  const double nowy = luk > 0 ? luk : 0.0;
  if ( qFuzzyCompare( mChmurkaLuk, nowy ) )
    return;
  mChmurkaLuk = nowy;
  emit chmurkaLukChanged();
}

int Ksztalty::segmentowDlaOkregu( double promien ) const
{
  // Bez ustawienia zostaje stare zachowanie, co do wierzcholka.
  if ( !( promien > 0 ) || !( mBokMetry > 0 ) )
    return 72;

  // Bok `c` w okregu o promieniu `r` opiera sie na kacie 2*asin(c/2r).
  const double polowa = mBokMetry / ( 2.0 * promien );
  if ( polowa >= 1.0 )
  {
    // Bok dluzszy od srednicy — nie ma czego dzielic, zostaje minimum.
    return 8;
  }
  const double kat = 2.0 * std::asin( polowa );
  const double ile = std::ceil( 2.0 * M_PI / kat );
  if ( ile >= static_cast<double>( mMaksWierzcholkow ) )
    return mMaksWierzcholkow;
  return std::max( 8, static_cast<int>( ile ) );
}

int Ksztalty::potrzebaPunktow( const QString &ksztalt ) const
{
  const QString k = klucz( ksztalt );
  // Prostokat potrzebuje TRZECH: dwa na os, trzeci na szerokosc.
  if ( k == QLatin1String( "prostokat" ) )
    return 3;
  if ( k == QLatin1String( "okrag" ) )
    return 2;
  if ( k == QLatin1String( "krzywa" ) )
    return 2;
  // Chmurka obrysowuje OBSZAR — dwa punkty daja odcinek, a nie obszar.
  if ( k == QLatin1String( "chmurka" ) )
    return 3;
  return 0;
}

QString Ksztalty::podpowiedz( const QString &ksztalt, int juzWskazanych ) const
{
  const QString k = klucz( ksztalt );

  if ( k == QLatin1String( "prostokat" ) )
  {
    if ( juzWskazanych <= 0 )
      return tr( "Wskaż początek pierwszego boku." );
    if ( juzWskazanych == 1 )
      return tr( "Wskaż koniec tego boku — on wyznaczy oś." );
    if ( juzWskazanych == 2 )
      return tr( "Wskaż szerokość — prostokąt stanie wzdłuż osi." );
    return tr( "Gotowe." );
  }

  if ( k == QLatin1String( "okrag" ) )
  {
    if ( juzWskazanych <= 0 )
      return tr( "Wskaż środek — np. pień drzewa." );
    if ( juzWskazanych == 1 )
      return tr( "Wskaż punkt na obwodzie albo wpisz promień." );
    return tr( "Gotowe." );
  }

  if ( k == QLatin1String( "krzywa" ) )
  {
    if ( juzWskazanych <= 0 )
      return tr( "Wskaż początek." );
    if ( juzWskazanych == 1 )
      return tr( "Wskaż koniec — albo kolejne punkty, żeby wygiąć." );
    return tr( "Wskazano %n punkt(ów). Wygina się z każdym kolejnym.", nullptr, juzWskazanych );
  }

  if ( k == QLatin1String( "chmurka" ) )
  {
    if ( juzWskazanych <= 0 )
      return tr( "Obrysuj obszar do sprawdzenia — wskaż pierwszy narożnik." );
    if ( juzWskazanych == 1 )
      return tr( "Wskaż drugi narożnik." );
    if ( juzWskazanych == 2 )
      return tr( "Wskaż trzeci — od niego zrobi się chmurka." );
    return tr( "Wskazano %n narożnik(ów). Kolejne dokładają załamań.", nullptr, juzWskazanych );
  }

  return QString();
}

QgsGeometry Ksztalty::prostokat( const QVariantList &punkty ) const
{
  const QVector<QgsPoint> p = naPunkty( punkty );

  // TRZY punkty, zawsze. Dwa pierwsze to PIERWSZY BOK, czyli os, wzdluz
  // ktorej prostokat stoi; trzeci daje szerokosc.
  //
  // Bylo tu kiedys drugie zachowanie — dwa punkty jako naroza po
  // przekatnej, boki rownolegle do osi ukladu. Wypadlo 23.09.2026 na
  // zyczenie Piotra i slusznie: plat, poletko ani zakres prac nie stoja
  // rownolegle do polnocy, wiec ten wariant dawal ksztalt do poprawiania.
  // Dwa zachowania na jednym przycisku tylko mylily.
  if ( p.size() < 3 )
    return QgsGeometry();

  // `Projected` znaczy: trzeci punkt rzutujemy na prostopadla do boku a–b,
  // wiec prostokat trzyma sie wskazanej osi nawet wtedy, gdy palec zjedzie
  // w bok. W terenie zjezdza zawsze.
  const QgsQuadrilateral czworokat = QgsQuadrilateral::rectangleFrom3Points(
    p.at( 0 ), p.at( 1 ), p.at( 2 ), QgsQuadrilateral::Projected );

  if ( !czworokat.isValid() )
    return QgsGeometry();

  return QgsGeometry( czworokat.toPolygon( false ) );
}

QgsGeometry Ksztalty::okrag( const QVariantList &punkty, int segmentow ) const
{
  const QVector<QgsPoint> p = naPunkty( punkty );
  if ( p.size() < 2 )
    return QgsGeometry();

  const double r = p.at( 0 ).distance( p.at( 1 ) );
  return okragZ( p.at( 0 ), r, segmentow > 0 ? segmentow : segmentowDlaOkregu( r ) );
}

QgsGeometry Ksztalty::okragOPromieniu( const QVariant &srodek, double promien,
                                       int segmentow ) const
{
  QgsPoint s;
  if ( !naPunkt( srodek, s ) )
    return QgsGeometry();

  return okragZ( s, promien, segmentow > 0 ? segmentow : segmentowDlaOkregu( promien ) );
}

QgsGeometry Ksztalty::krzywa( const QVariantList &punkty, int stopien, int gestosc,
                              const QVariantList &wagi, bool zamknieta ) const
{
  const QVector<QgsPoint> kontrolne = naPunkty( punkty );
  const int n = kontrolne.size();
  if ( n < 2 )
    return QgsGeometry();

  // Pierscienia z dwoch punktow nie ma. Zamknieta krzywa potrzebuje
  // co najmniej trojki, zeby w ogole objac jakikolwiek kawalek terenu.
  if ( zamknieta && n < 3 )
    return QgsGeometry();

  // Stopien schodzi sam. Trzy punkty nie udzwigna krzywej szescienej,
  // a czlowiek w terenie nie ma sie zastanawiac nad stopniem — ma tapac.
  int p = std::max( 1, stopien );
  p = std::min( p, n - 1 );

  // Dwa punkty przy stopniu 1 to zwykly odcinek — liczmy go wprost,
  // zeby nie zagescic prostej na dwanascie wierzcholkow bez powodu.
  if ( n == 2 )
  {
    QgsLineString *odcinek = new QgsLineString( QVector<QgsPoint>()
                                                << kontrolne.at( 0 ) << kontrolne.at( 1 ) );
    return QgsGeometry( odcinek );
  }

  // --- wagi ---------------------------------------------------------------
  std::vector<double> w( static_cast<size_t>( n ), 1.0 );
  if ( wagi.size() == n )
  {
    for ( int i = 0; i < n; ++i )
    {
      const double waga = wagi.at( i ).toDouble();
      // Waga <= 0 wywraca dzielenie na koncu; zero znaczy „punkt nie liczy
      // sie wcale”, a tego nie da sie narysowac. Wracamy do jedynki.
      w[static_cast<size_t>( i )] = ( waga > 0 && !std::isinf( waga ) ) ? waga : 1.0;
    }
  }

  // --- ZAMKNIETA: okrezamy punkty kontrolne -------------------------------
  //
  // Krzywa zamknieta to NIE jest krzywa otwarta z dostawionym odcinkiem.
  // Tak bylo do 24.09.2026 i skutek byl widoczny golym okiem: na calym
  // gladkim obrysie jedno miejsce bylo ostre — dokladnie to, w ktore
  // czlowiek tapnal najpierw. Rog tam, gdzie zaczynal rysowac.
  //
  // Robimy wiec krzywa OKRESOWA: pierwsze `p` punktow kontrolnych
  // dopisujemy na koniec, a wezly bierzemy ROWNOMIERNE zamiast
  // zacisnietych. Krzywa domyka sie wtedy sama i nie ma na niej zadnego
  // punktu wyroznionego.
  //
  // Cena: obrys przestaje przechodzic przez pierwszy i ostatni wskazany
  // punkt. Przez SRODKOWE i tak nigdy nie przechodzil — B-sklejana je
  // tylko przyciaga — wiec zamkniety obrys jest po tej zmianie bardziej
  // konsekwentny, nie mniej: wszystkie punkty liczą sie tak samo.
  QVector<QgsPoint> kp = kontrolne;
  if ( zamknieta )
  {
    for ( int i = 0; i < p; ++i )
    {
      kp.append( kontrolne.at( i % n ) );
      w.push_back( w[static_cast<size_t>( i % n )] );
    }
  }
  const int nr = kp.size();

  // --- wektor wezlowy ------------------------------------------------------
  // Otwarta: p+1 zer, wnetrze 1..n-p-1, p+1 kopii (n-p). Zaciśnięcie jest
  // tym, co sprawia, ze krzywa zaczyna sie w pierwszym i konczy w ostatnim
  // punkcie. Zamknieta: wezly rownomierne, bo zadnego konca nie ma.
  const int rozmiar = nr + p + 1;
  std::vector<double> wezly( static_cast<size_t>( rozmiar ), 0.0 );
  for ( int i = 0; i < rozmiar; ++i )
  {
    if ( zamknieta )
      wezly[static_cast<size_t>( i )] = i;
    else if ( i <= p )
      wezly[static_cast<size_t>( i )] = 0.0;
    else if ( i < n )
      wezly[static_cast<size_t>( i )] = i - p;
    else
      wezly[static_cast<size_t>( i )] = n - p;
  }

  const double poczatek = zamknieta ? wezly[static_cast<size_t>( p )] : 0.0;
  const double koniec = zamknieta ? wezly[static_cast<size_t>( nr )]
                                  : static_cast<double>( n - p );
  const int przesel = nr - p;

  // Probkowanie wyjete do OSOBNEJ funkcji, bo trzeba je wykonac dwa razy:
  // raz zgrubnie, zeby zmierzyc dlugosc krzywej, i raz naprawde — z takim
  // zageszczeniem, zeby bok wyszedl `bokMetry`. Bez pomiaru nie da sie
  // tego policzyc z gory: dlugosc krzywej B-sklejanej nie ma wzoru.
  auto probkuj = [&]( int naPrzeslo ) {
    QVector<QgsPoint> wynik;
    const int probek = przesel * naPrzeslo;
    wynik.reserve( probek + 1 );

    for ( int krok = 0; krok <= probek; ++krok )
    {
    const double u = poczatek + ( koniec - poczatek ) * static_cast<double>( krok ) / static_cast<double>( probek );
    const int k = przedzial( wezly, nr, p, u );

    // de Boor we wspolrzednych jednorodnych (wx, wy, w) — dopiero dzielenie
    // na koncu robi z tego krzywa WYMIERNA, czyli prawdziwy NURBS.
    std::vector<double> dx( static_cast<size_t>( p ) + 1 );
    std::vector<double> dy( static_cast<size_t>( p ) + 1 );
    std::vector<double> dw( static_cast<size_t>( p ) + 1 );
    for ( int j = 0; j <= p; ++j )
    {
      const int i = k - p + j;
      const double waga = w[static_cast<size_t>( i )];
      dx[static_cast<size_t>( j )] = kp.at( i ).x() * waga;
      dy[static_cast<size_t>( j )] = kp.at( i ).y() * waga;
      dw[static_cast<size_t>( j )] = waga;
    }

    for ( int r = 1; r <= p; ++r )
    {
      for ( int j = p; j >= r; --j )
      {
        const int i = k - p + j;
        const double a = wezly[static_cast<size_t>( i )];
        const double b = wezly[static_cast<size_t>( i + p - r + 1 )];
        const double mian = b - a;
        const double alfa = ( mian > 0 ) ? ( u - a ) / mian : 0.0;
        const size_t jj = static_cast<size_t>( j );
        dx[jj] = ( 1.0 - alfa ) * dx[jj - 1] + alfa * dx[jj];
        dy[jj] = ( 1.0 - alfa ) * dy[jj - 1] + alfa * dy[jj];
        dw[jj] = ( 1.0 - alfa ) * dw[jj - 1] + alfa * dw[jj];
      }
    }

    const size_t ost = static_cast<size_t>( p );
    if ( !( std::fabs( dw[ost] ) > 1e-12 ) )
      continue;
    wynik.append( QgsPoint( dx[ost] / dw[ost], dy[ost] / dw[ost] ) );
    }
    return wynik;
  };

  int naPrzeslo = std::max( 2, std::min( 200, gestosc ) );

  if ( gestosc <= 0 )
  {
    // AUTOMAT. Mierzymy krzywa zgrubnie, a potem dobieramy zageszczenie tak,
    // zeby sredni bok wyszedl `bokMetry`. Zgrubny pomiar zanizy dlugosc
    // (ciecziwy sa krotsze od luku), wiec wychodzi troche gesciej niz trzeba
    // — i dobrze, bo blad idzie w strone dokladnosci, nie zgrubienia.
    naPrzeslo = 12;
    if ( mBokMetry > 0 )
    {
      const QVector<QgsPoint> zgrubna = probkuj( 6 );
      double dlugosc = 0.0;
      for ( int i = 1; i < zgrubna.size(); ++i )
        dlugosc += zgrubna.at( i ).distance( zgrubna.at( i - 1 ) );

      if ( dlugosc > 0 )
      {
        const double trzeba = dlugosc / mBokMetry;
        const double naJedno = std::ceil( trzeba / static_cast<double>( przesel ) );
        const double sufit = static_cast<double>( mMaksWierzcholkow ) / static_cast<double>( przesel );
        naPrzeslo = static_cast<int>( std::max( 2.0, std::min( std::min( 200.0, sufit ), naJedno ) ) );
      }
    }
  }

  QVector<QgsPoint> linia = probkuj( naPrzeslo );

  if ( gestosc <= 0 && mBokMetry > 0 )
  {
    // SPRAWDZAMY, a nie ufamy oszacowaniu. Zgrubny pomiar zaniza dlugosc,
    // a krzywa nie jest rozlozona rowno: w ciasnym zakolu boki wychodza
    // dluzsze niz srednia. Poprawiamy, dopoki najdluzszy bok nie zmiesci
    // sie w zadanym — najwyzej trzy razy, zeby to zawsze sie konczylo.
    const int sufitNaPrzeslo = std::max( 2, mMaksWierzcholkow / przesel );
    for ( int proba = 0; proba < 3; ++proba )
    {
      double naj = 0.0;
      for ( int i = 1; i < linia.size(); ++i )
        naj = std::max( naj, linia.at( i ).distance( linia.at( i - 1 ) ) );

      if ( !( naj > mBokMetry ) )
        break;

      int nowy = static_cast<int>( std::ceil( naPrzeslo * ( naj / mBokMetry ) ) );
      nowy = std::min( nowy, std::min( 200, sufitNaPrzeslo ) );
      if ( nowy <= naPrzeslo )
        break; // sufit — gesciej sie nie da i nie bedziemy krecic w kolko
      naPrzeslo = nowy;
      linia = probkuj( naPrzeslo );
    }
  }

  if ( linia.size() < 2 )
    return QgsGeometry();

  if ( zamknieta )
  {
    // Pierscien z trzech wierzcholkow to odcinek tam i z powrotem.
    if ( linia.size() < 4 )
      return QgsGeometry();
    // Okres liczy sie dokladnie, ale arytmetyka zmiennoprzecinkowa potrafi
    // zostawic milimetr — a niedomkniety o milimetr pierscien to dla OGR-a
    // nie pierscien wcale. Domykamy KOPIA, nie zaokragleniem.
    linia.last() = linia.first();
    return QgsGeometry( new QgsLineString( linia ) );
  }

  // Zaciśnięcie liczy sie dokladnie, ale arytmetyka zmiennoprzecinkowa
  // potrafi zostawic milimetr. Poczatek i koniec sa jedynymi punktami,
  // ktore czlowiek WSKAZAL palcem — maja lezec tam, gdzie tapnal.
  linia.first() = kontrolne.first();
  linia.last() = kontrolne.last();

  return QgsGeometry( new QgsLineString( linia ) );
}

QgsGeometry Ksztalty::krzywaPrzez( const QVariantList &punkty, int gestosc,
                                   bool zamknieta ) const
{
  const QVector<QgsPoint> p = naPunkty( punkty );
  const int n = p.size();
  if ( n < 2 )
    return QgsGeometry();
  if ( zamknieta && n < 3 )
    return QgsGeometry();

  if ( n == 2 && !zamknieta )
  {
    return QgsGeometry( new QgsLineString( QVector<QgsPoint>() << p.at( 0 ) << p.at( 1 ) ) );
  }

  // Splajn Catmulla-Roma w odmianie DOSRODKOWEJ (alfa = 0.5).
  //
  // Wybrany, bo jako jedyny z tej rodziny nie robi petelek ani dziobow,
  // gdy dwa tapniecia leza blisko siebie, a trzecie daleko — a tak
  // wyglada kazdy obrys robiony w terenie: gesto tam, gdzie brzeg kreci,
  // rzadko na prostej. Odmiana jednostajna (alfa = 0) w takim miejscu
  // strzela petla poza obrys, a cieciwowa (alfa = 1) splaszcza zakola.
  //
  // Jest LOKALNY: kazdy odcinek liczy sie z czterech punktow i nie ma
  // zadnego ukladu rownan do rozwiazania. Poprawka jednego punktu
  // w terenie nie przelicza calego obrysu.
  const double alfa = 0.5;

  // Punkty widmowe dla krzywej otwartej: przedluzenie pierwszego i
  // ostatniego odcinka. Bez nich pierwszy i ostatni kawalek nie mialby
  // z czego policzyc stycznej.
  auto punkt = [&]( int i ) -> QgsPoint {
    if ( zamknieta )
      return p.at( ( ( i % n ) + n ) % n );
    if ( i < 0 )
      return QgsPoint( 2 * p.at( 0 ).x() - p.at( 1 ).x(),
                       2 * p.at( 0 ).y() - p.at( 1 ).y() );
    if ( i > n - 1 )
      return QgsPoint( 2 * p.at( n - 1 ).x() - p.at( n - 2 ).x(),
                       2 * p.at( n - 1 ).y() - p.at( n - 2 ).y() );
    return p.at( i );
  };

  auto wezel = [&]( double t, const QgsPoint &a, const QgsPoint &b ) {
    return t + std::pow( a.distance( b ), alfa );
  };

  const int odcinkow = zamknieta ? n : n - 1;

  QVector<QgsPoint> linia;
  linia.append( p.at( 0 ) );

  for ( int s = 0; s < odcinkow; ++s )
  {
    const QgsPoint P0 = punkt( s - 1 );
    const QgsPoint P1 = punkt( s );
    const QgsPoint P2 = punkt( s + 1 );
    const QgsPoint P3 = punkt( s + 2 );

    const double t0 = 0.0;
    const double t1 = wezel( t0, P0, P1 );
    const double t2 = wezel( t1, P1, P2 );
    const double t3 = wezel( t2, P2, P3 );

    // Zdublowany punkt zeruje przedzial wezlowy i wywraca dzielenie.
    // Wtedy zostaje zwykly odcinek — i tak nie ma czego wygladzac.
    if ( !( t1 > t0 ) || !( t2 > t1 ) || !( t3 > t2 ) )
    {
      linia.append( P2 );
      continue;
    }

    // Ile probek na ten odcinek. Liczymy z JEGO dlugosci, nie z calosci:
    // krotki kawalek przy gestych tapnieciach nie potrzebuje tylu
    // wierzcholkow, co dlugi przelot przez pole.
    int probek = std::max( 2, gestosc > 0 ? gestosc : 12 );
    if ( gestosc <= 0 && mBokMetry > 0 )
    {
      const double dlugosc = P1.distance( P2 );
      const double sufit = static_cast<double>( mMaksWierzcholkow ) / odcinkow;
      probek = static_cast<int>( std::max( 2.0, std::min( std::min( 200.0, sufit ),
                                                          std::ceil( dlugosc / mBokMetry ) ) ) );
    }

    for ( int k = 1; k <= probek; ++k )
    {
      const double t = t1 + ( t2 - t1 ) * static_cast<double>( k ) / static_cast<double>( probek );

      const double a1 = ( t1 - t ) / ( t1 - t0 ), b1 = ( t - t0 ) / ( t1 - t0 );
      const double a2 = ( t2 - t ) / ( t2 - t1 ), b2 = ( t - t1 ) / ( t2 - t1 );
      const double a3 = ( t3 - t ) / ( t3 - t2 ), b3 = ( t - t2 ) / ( t3 - t2 );

      const double A1x = a1 * P0.x() + b1 * P1.x(), A1y = a1 * P0.y() + b1 * P1.y();
      const double A2x = a2 * P1.x() + b2 * P2.x(), A2y = a2 * P1.y() + b2 * P2.y();
      const double A3x = a3 * P2.x() + b3 * P3.x(), A3y = a3 * P2.y() + b3 * P3.y();

      const double c1 = ( t2 - t ) / ( t2 - t0 ), d1 = ( t - t0 ) / ( t2 - t0 );
      const double c2 = ( t3 - t ) / ( t3 - t1 ), d2 = ( t - t1 ) / ( t3 - t1 );

      const double B1x = c1 * A1x + d1 * A2x, B1y = c1 * A1y + d1 * A2y;
      const double B2x = c2 * A2x + d2 * A3x, B2y = c2 * A2y + d2 * A3y;

      const double e = ( t2 - t ) / ( t2 - t1 ), f = ( t - t1 ) / ( t2 - t1 );
      linia.append( QgsPoint( e * B1x + f * B2x, e * B1y + f * B2y ) );
    }
  }

  if ( linia.size() < 2 )
    return QgsGeometry();

  if ( zamknieta )
  {
    if ( linia.size() < 4 )
      return QgsGeometry();
    linia.last() = linia.first();
    return QgsGeometry( new QgsLineString( linia ) );
  }

  // Krzywa PRZECHODZI przez wskazane punkty — to jej cala racja bytu,
  // wiec konce maja lezec dokladnie tam, gdzie czlowiek tapnal.
  linia.first() = p.first();
  linia.last() = p.last();

  return QgsGeometry( new QgsLineString( linia ) );
}

bool Ksztalty::zamien( QObject *modelGumki, const QString &ksztalt ) const
{
  if ( !modelGumki || ksztalt.trimmed().isEmpty() )
    return false;

  const int typ = modelGumki->property( "geometryType" ).toInt();
  const QgsGeometry g = naTyp( zModelu( modelGumki, ksztalt, 0.0, false, typ ), typ );
  if ( g.isNull() || g.isEmpty() )
    return false;

  // Wolamy po NAZWIE, a nie przez naglowek gumki — dzieki temu caly ten
  // plik nadal buduje sie i sprawdza w piaskownicy, gdzie gumki nie ma.
  const QVariant uklad = modelGumki->property( "crs" );
  return QMetaObject::invokeMethod(
    modelGumki, "setDataFromGeometry",
    Q_ARG( QgsGeometry, g ),
    Q_ARG( QgsCoordinateReferenceSystem, uklad.value<QgsCoordinateReferenceSystem>() ) );
}

QgsGeometry Ksztalty::chmurka( const QVariantList &punkty, bool zamknieta ) const
{
  QVector<QgsPoint> p = naPunkty( punkty );
  if ( p.size() < ( zamknieta ? 3 : 2 ) )
    return QgsGeometry();

  // Sciezka bazowa: lamana przez wskazane punkty. Prosto, nie po krzywej —
  // chmurka ma MOWIC „przyjrzyj sie temu miejscu", a nie udawac pomiar.
  QVector<QgsPoint> sciezka = p;
  if ( zamknieta )
    sciezka.append( p.first() );

  // Dlugosci czastkowe, zeby dalo sie chodzic po sciezce metrami.
  QVector<double> narastajaco;
  narastajaco.reserve( sciezka.size() );
  narastajaco.append( 0.0 );
  for ( int i = 1; i < sciezka.size(); ++i )
    narastajaco.append( narastajaco.last() + sciezka.at( i ).distance( sciezka.at( i - 1 ) ) );

  const double obwod = narastajaco.last();
  if ( !( obwod > 0 ) )
    return QgsGeometry();

  // DLUGOSC LUKU. Zero znaczy AUTOMAT: jedna dwudziesta obwodu.
  //
  // Automat, bo chmurka o stalym luku wyglada dobrze tylko w jednej skali.
  // Przy luku 1 m drzewo o srednicy 5 m dostaje szesnascie zabkow (jeszcze
  // ujdzie), a pole o boku 500 m — dwa tysiace (wyglada jak gruba kreska
  // i wazy tyle, co caly dzien pomiarow). Jedna dwudziesta obwodu daje
  // ten sam obrazek niezaleznie od tego, co obrysowujesz.
  double luk = mChmurkaLuk > 0 ? mChmurkaLuk : obwod / 20.0;
  luk = std::max( 0.2, std::min( 50.0, luk ) );

  // Dzielimy obwod ROWNO, zeby ostatni zabek nie wyszedl kikutem.
  const int najmniej = zamknieta ? 3 : 2;
  int zabkow = static_cast<int>( std::lround( obwod / luk ) );
  zabkow = std::max( najmniej, std::min( 400, zabkow ) );
  luk = obwod / zabkow;

  // Punkt na sciezce w zadanej odleglosci od poczatku.
  auto naSciezce = [&]( double s ) -> QgsPoint {
    if ( s <= 0 )
      return sciezka.first();
    if ( s >= obwod )
      return sciezka.last();
    int i = 1;
    while ( i < narastajaco.size() - 1 && narastajaco.at( i ) < s )
      ++i;
    const double a = narastajaco.at( i - 1 ), b = narastajaco.at( i );
    const double u = ( b > a ) ? ( s - a ) / ( b - a ) : 0.0;
    const QgsPoint &A = sciezka.at( i - 1 );
    const QgsPoint &B = sciezka.at( i );
    return QgsPoint( A.x() + u * ( B.x() - A.x() ), A.y() + u * ( B.y() - A.y() ) );
  };

  // W KTORA STRONE wybrzuszac. Przy pierscieniu — na zewnatrz, czyli
  // przeciwnie do wnetrza; bierzemy to ze znaku pola. Przy linii otwartej
  // nie ma „zewnatrz", wiec zawsze w lewo od kierunku marszu, zeby chmurka
  // nie zmieniala strony w polowie.
  double pole2 = 0.0;
  for ( int i = 1; i < sciezka.size(); ++i )
    pole2 += sciezka.at( i - 1 ).x() * sciezka.at( i ).y()
             - sciezka.at( i ).x() * sciezka.at( i - 1 ).y();
  // Znak wyprowadzony PROBA, nie z glowy: zamiatanie o +PI prowadzi
  // luk na PRAWO od kierunku marszu, a przy pierscieniu przeciwnym do
  // wskazowek zegara (pole2 > 0) wnetrze lezy po LEWEJ — wiec na
  // zewnatrz znaczy w prawo. Za pierwszym razem mialem to odwrotnie
  // i chmurka ZJADALA obrysowany obszar zamiast go obejmowac: pole
  // spadalo z 400 do 275 m kw. Wygladalo podobnie, znaczylo co innego.
  const double strona = zamknieta ? ( pole2 > 0 ? 1.0 : -1.0 ) : 1.0;

  // Ile odcinkow na jeden zabek — z `bokMetry`, jak wszedzie indziej.
  const double promien = luk / 2.0;
  int naZabek = 8;
  if ( mBokMetry > 0 )
  {
    const double sufit = static_cast<double>( mMaksWierzcholkow ) / zabkow;
    naZabek = static_cast<int>( std::max( 3.0, std::min( std::min( 64.0, sufit ),
                                                         std::ceil( M_PI * promien / mBokMetry ) ) ) );
  }

  QVector<QgsPoint> linia;
  linia.reserve( zabkow * naZabek + 1 );

  for ( int z = 0; z < zabkow; ++z )
  {
    const QgsPoint A = naSciezce( z * luk );
    const QgsPoint B = naSciezce( ( z + 1 ) * luk );

    const double sx = ( A.x() + B.x() ) / 2.0;
    const double sy = ( A.y() + B.y() ) / 2.0;
    const double r = A.distance( B ) / 2.0;
    if ( !( r > 0 ) )
      continue;

    // Polokrag od A do B. Zamiatanie o PI w jedna albo w druga strone —
    // obie koncza sie w B, roznia sie tylko tym, po ktorej stronie cieciwy
    // przechodza. Stad `strona` jako znak.
    const double kat = std::atan2( A.y() - sy, A.x() - sx );
    for ( int k = 0; k < naZabek; ++k )
    {
      const double t = kat + strona * M_PI * static_cast<double>( k ) / static_cast<double>( naZabek );
      linia.append( QgsPoint( sx + r * std::cos( t ), sy + r * std::sin( t ) ) );
    }
  }

  if ( linia.size() < 3 )
    return QgsGeometry();

  if ( zamknieta )
  {
    linia.append( linia.first() );
    return QgsGeometry( new QgsLineString( linia ) );
  }

  // Otwarta konczy sie na ostatnim wskazanym punkcie, a nie w polowie luku.
  linia.append( sciezka.last() );
  return QgsGeometry( new QgsLineString( linia ) );
}

///@cond PRIVATE

/**
 * Zdejmuje ostatni punkt, jesli lezy na poprzednim.
 *
 * Zaraz po tapnieciu gumka trzyma wskazany punkt DWA RAZY: raz jako
 * wierzcholek, raz jako punkt zywy, ktory dopiero zacznie chodzic za
 * celownikiem. Przy podgladzie bierzemy oba, wiec bez tego krzywa
 * dostawalaby zdublowany punkt kontrolny i szarpalaby w tym miejscu.
 *
 * Prog to milimetr: mniej niz cokolwiek, co da sie wskazac palcem na
 * mapie, i duzo mniej niz dokladnosc GNSS.
 */
static void zdejmijZdublowanyOgon( QVector<QgsPoint> &punkty, bool zZywym )
{
  if ( !zZywym || punkty.size() < 2 )
    return;
  if ( punkty.at( punkty.size() - 1 ).distance( punkty.at( punkty.size() - 2 ) ) < 0.001 )
    punkty.removeLast();
}

/**
 * Punkty JUZ WSKAZANE w modelu gumki.
 *
 * `vertices` trzyma TAKZE punkt zywy — ten, ktory chodzi za celownikiem —
 * pod indeksem `currentCoordinateIndex`. Gdyby go zostawic, kazdy ksztalt
 * mialby jeden wierzcholek za duzo: ten, gdzie akurat stoi krzyzyk,
 * a nie ten, ktory czlowiek wskazal palcem.
 */
static QVector<QgsPoint> punktyGumki( QObject *model, bool zZywym = false )
{
  QVector<QgsPoint> w;
  if ( !model )
    return w;

  const QVariant surowe = model->property( "vertices" );
  if ( !surowe.isValid() )
    return w;

  const QVariant indeks = model->property( "currentCoordinateIndex" );
  const bool znamyZywy = indeks.isValid() && !zZywym;
  const int zywy = indeks.toInt();

  // Pojemnika NIE da sie rozlozyc przez `toList()` ani
  // `QSequentialIterable`: jedno i drugie potrzebuje metatypu elementu,
  // a `QgsPoint` go nie ma. Sprawdzone — `toList()` oddaje pustke.
  // Bierzemy go wiec tak samo jak pojedynczy punkt: po NAZWIE TYPU.
  //
  // Nazwy sa dwie, bo w Qt6 `QVector` to juz tylko inna nazwa `QList`,
  // wiec ten sam naglowek gumki opisuje sie raz tak, raz tak. Uklad
  // pamieci jest w obu przypadkach ten, ktory `QVector` znaczy w danej
  // kompilacji, wiec rzutowanie jest poprawne w obu.
  const char *nazwa = surowe.typeName();
  if ( surowe.constData()
       && ( qstrcmp( nazwa, "QVector<QgsPoint>" ) == 0
            || qstrcmp( nazwa, "QList<QgsPoint>" ) == 0
            || qstrcmp( nazwa, "QgsPointSequence" ) == 0 ) )
  {
    const QVector<QgsPoint> *punkty =
      reinterpret_cast<const QVector<QgsPoint> *>( surowe.constData() );
    for ( int i = 0; i < punkty->size(); ++i )
    {
      if ( znamyZywy && i == zywy )
        continue;
      w.append( punkty->at( i ) );
    }
    zdejmijZdublowanyOgon( w, zZywym );
    return w;
  }

  // Zwykla tablica z QML-a — na wypadek, gdyby pasek podal punkty sam.
  const QVariantList lista = surowe.toList();
  for ( int i = 0; i < lista.size(); ++i )
  {
    if ( znamyZywy && i == zywy )
      continue;
    QgsPoint p;
    if ( naPunkt( lista.at( i ), p ) )
      w.append( p );
  }
  zdejmijZdublowanyOgon( w, zZywym );


  // Zadna droga nie zadzialala, a wlasciwosc przyszla. To znaczy, ze
  // pojemnik nazywa sie inaczej, niz przewidzielismy — i bez tej linijki
  // pasek po prostu milczalby na zawsze, a czlowiek widzialby wylacznie
  // przygaszone przyciski, bez slowa wyjasnienia.
  //
  // Wypisujemy RAZ, bo `wskazanych()` wola wiazanie i przy kazdym ruchu
  // celownika poszloby to do logu kilkadziesiat razy na sekunde.
  if ( w.isEmpty() && lista.isEmpty() )
  {
    static bool juzPowiedziane = false;
    if ( !juzPowiedziane )
    {
      juzPowiedziane = true;
      qWarning( "WorkField/Ksztalty: nie umiem rozlozyc `vertices` — typ to \"%s\"; "
                "wskazanych() bedzie oddawac 0",
                nazwa ? nazwa : "(brak)" );
    }
  }
  return w;
}

//! Punkty jako `QVariantList` — tak, jak biora je czasowniki publiczne.
static QVariantList jakoWarianty( const QVector<QgsPoint> &punkty )
{
  QVariantList w;
  for ( const QgsPoint &p : punkty )
    w << QVariant( QVariantList() << p.x() << p.y() );
  return w;
}

///@endcond

void Ksztalty::powiedz( const QString &gdzie, const QgsGeometry &geometria ) const
{
  if ( geometria.isNull() )
  {
    qWarning( "WorkField/Ksztalty %s: geometria PUSTA (null)", gdzie.toUtf8().constData() );
    return;
  }

  const char *typ = "?";
  switch ( geometria.type() )
  {
    case Qgis::GeometryType::Point: typ = "punkt"; break;
    case Qgis::GeometryType::Line: typ = "linia"; break;
    case Qgis::GeometryType::Polygon: typ = "wielokat"; break;
    default: typ = "nieznany"; break;
  }

  int wierzcholkow = 0;
  if ( const QgsAbstractGeometry *g = geometria.constGet() )
  {
    QgsVertexId vid;
    QgsPoint p;
    while ( g->nextVertex( vid, p ) )
      ++wierzcholkow;
  }

  const QgsRectangle o = geometria.boundingBox();
  qWarning( "WorkField/Ksztalty %s: typ=%s wierzcholkow=%d pole=%.3f obwiednia=%.2f x %.2f",
            gdzie.toUtf8().constData(), typ, wierzcholkow, geometria.area(),
            o.width(), o.height() );
}

void Ksztalty::powiedzOGumce( const QString &gdzie, QObject *modelGumki ) const
{
  if ( !modelGumki )
  {
    qWarning( "WorkField/Ksztalty %s: gumki NIE MA", gdzie.toUtf8().constData() );
    return;
  }

  const QVector<QgsPoint> wszystkie = punktyGumki( modelGumki, true );
  const int licznik = modelGumki->property( "vertexCount" ).toInt();
  const int zywy = modelGumki->property( "currentCoordinateIndex" ).toInt();

  if ( wszystkie.isEmpty() )
  {
    qWarning( "WorkField/Ksztalty %s: gumka PUSTA (vertexCount=%d)",
              gdzie.toUtf8().constData(), licznik );
    return;
  }

  qWarning( "WorkField/Ksztalty %s: vertexCount=%d zywy=%d odczytanych=%d "
            "pierwszy=(%.2f %.2f) ostatni=(%.2f %.2f)",
            gdzie.toUtf8().constData(), licznik, zywy, wszystkie.size(),
            wszystkie.first().x(), wszystkie.first().y(),
            wszystkie.last().x(), wszystkie.last().y() );
}

bool Ksztalty::pusty( const QgsGeometry &geometria ) const
{
  return geometria.isNull() || geometria.isEmpty();
}

int Ksztalty::wskazanych( QObject *modelGumki, bool zPunktemZywym ) const
{
  return punktyGumki( modelGumki, zPunktemZywym ).size();
}

QgsGeometry Ksztalty::zModelu( QObject *modelGumki, const QString &ksztalt,
                               double promien, bool zPunktemZywym,
                               int typDocelowy ) const
{
  const QVector<QgsPoint> punkty = punktyGumki( modelGumki, zPunktemZywym );
  if ( punkty.isEmpty() )
    return QgsGeometry();

  // Promien z dalmierza: wystarczy jeden wskazany punkt — srodek.
  if ( promien > 0 && klucz( ksztalt ) == QLatin1String( "okrag" ) )
    return okragZ( punkty.first(), promien, segmentowDlaOkregu( promien ) );

  // Krzywa na warstwie POLIGONOWEJ ma byc zamknieta OD RAZU, a nie
  // domykana potem akordem — akord zostawial rog w punkcie, w ktory
  // czlowiek tapnal najpierw.
  const QString k = klucz( ksztalt );
  const bool zamknieta = ( k == QLatin1String( "krzywa" ) || k == QLatin1String( "chmurka" ) )
                         && static_cast<Qgis::GeometryType>( typDocelowy ) == Qgis::GeometryType::Polygon;

  return zbuduj( ksztalt, jakoWarianty( punkty ), zamknieta );
}

QgsGeometry Ksztalty::naTyp( const QgsGeometry &ksztalt, int typ ) const
{
  if ( ksztalt.isNull() || ksztalt.isEmpty() )
    return QgsGeometry();

  const Qgis::GeometryType ma = ksztalt.type();
  const Qgis::GeometryType chce = static_cast<Qgis::GeometryType>( typ );
  if ( ma == chce )
    return ksztalt;

  // Wielokat -> linia: sam obrys zewnetrzny.
  if ( ma == Qgis::GeometryType::Polygon && chce == Qgis::GeometryType::Line )
  {
    const QgsCurvePolygon *w = qgsgeometry_cast<const QgsCurvePolygon *>( ksztalt.constGet() );
    if ( !w || !w->exteriorRing() )
      return QgsGeometry();
    return QgsGeometry( w->exteriorRing()->clone() );
  }

  // Linia -> wielokat: domykamy pierscien.
  if ( ma == Qgis::GeometryType::Line && chce == Qgis::GeometryType::Polygon )
  {
    const QgsLineString *l = qgsgeometry_cast<const QgsLineString *>( ksztalt.constGet() );
    if ( !l || l->numPoints() < 3 )
      return QgsGeometry();

    QgsLineString *pierscien = l->clone();
    if ( !pierscien->isClosed() )
      pierscien->addVertex( pierscien->pointN( 0 ) );

    // Trzy wierzcholki po domknieciu to odcinek tam i z powrotem, nie plat.
    if ( pierscien->numPoints() < 4 )
    {
      delete pierscien;
      return QgsGeometry();
    }

    QgsPolygon *plat = new QgsPolygon();
    plat->setExteriorRing( pierscien );
    return QgsGeometry( plat );
  }

  // Punkt z ksztaltu to nie ksztalt — lepiej pusto niz centroid udajacy plat.
  return QgsGeometry();
}

QgsGeometry Ksztalty::zbuduj( const QString &ksztalt, const QVariantList &punkty,
                              bool zamknieta ) const
{
  const QString k = klucz( ksztalt );
  if ( k == QLatin1String( "prostokat" ) )
    return prostokat( punkty );
  if ( k == QLatin1String( "okrag" ) )
    return okrag( punkty );
  // 25.09.2026: ta galaz stala tu DWA RAZY. Druga byla martwa —
  // nieszkodliwa, ale mylaca przy czytaniu.
  if ( k == QLatin1String( "chmurka" ) )
    return chmurka( punkty, zamknieta );
  if ( k == QLatin1String( "krzywa" ) )
  {
    // 0 = AUTOMAT: zageszczenie z `bokMetry`, nie na sztywno.
    //
    // Ktora krzywa — decyduje przelacznik, nie ten plik. Obie drogi maja
    // te sama sygnature wejscia i wyjscia, wiec reszta aplikacji nie musi
    // wiedziec, ktora akurat chodzi.
    if ( mKrzywaPrzezPunkty )
      return krzywaPrzez( punkty, 0, zamknieta );
    return krzywa( punkty, 3, 0, QVariantList(), zamknieta );
  }
  return QgsGeometry();
}

// ══════════════════════════════════════════════════════════════════
//  PRAWDZIWE LUKI — okrag i chmurka
// ══════════════════════════════════════════════════════════════════
//
// Patrz dlugi komentarz przy deklaracjach w `ksztalty.h`. W skrocie:
// GPKG i OGR luki UMIEJA (sprawdzone: `CURVEPOLYGON (CIRCULARSTRING …)`
// przezywa zapis i odczyt, pole wychodzi dokladnie pi*r^2), a lamana
// brala sie z `QfGeometry::asQgsGeometry()`, ktore skladalo geometrie
// od nowa z punktow gumki.

///@cond PRIVATE

/**
 * Okrag jako `CIRCULARSTRING` przez cztery cwiartki.
 *
 * Piec wierzcholkow zamiast dziewiecdziesieciu, i to nie jest
 * oszczednosc miejsca tylko DOKLADNOSC: pole wychodzi pi*r^2 bez bledu
 * przyblizenia, a ksztalt zostaje okragly przy kazdym powiekszeniu.
 *
 * Trzy punkty by wystarczyly do jednoznacznego okregu, ale cztery
 * cwiartki plus domkniecie to postac, ktora QGIS i GDAL pokazuja
 * najgrzeczniej, a czlowiek czytajacy WKT od razu widzi srodek
 * i promien.
 */
static QgsGeometry okragLukiem( const QgsPoint &srodek, double promien )
{
  if ( !( promien > 0 ) || std::isnan( promien ) || std::isinf( promien ) )
    return QgsGeometry();

  const double x = srodek.x();
  const double y = srodek.y();

  QgsCircularString *obwod = new QgsCircularString();
  obwod->setPoints( QgsPointSequence()
                    << QgsPoint( x + promien, y )
                    << QgsPoint( x, y + promien )
                    << QgsPoint( x - promien, y )
                    << QgsPoint( x, y - promien )
                    << QgsPoint( x + promien, y ) );

  QgsCurvePolygon *plat = new QgsCurvePolygon();
  plat->setExteriorRing( obwod );
  return QgsGeometry( plat );
}

/**
 * Jeden zabek chmurki: poczatek, szczyt, koniec.
 *
 * Tyle wlasnie potrzebuje `CIRCULARSTRING`, i tyle wystarcza, bo zabek
 * JEST polokregiem — nie przyblizamy tu niczego.
 */
struct Zabek
{
    QgsPoint od;
    QgsPoint szczyt;
    QgsPoint doo;
};

/**
 * Rozklada sciezke chmurki na zabki.
 *
 * Wyliczenie stoi w JEDNYM miejscu, wspolnym dla postaci lamanej
 * i lukowej. Gdyby stalo w dwoch, wersje rozjechalyby sie przy
 * pierwszej zmianie `chmurkaLuk` albo `bokMetry` — a rozjazd byl by
 * niewidoczny, bo obie rysuja sie podobnie.
 *
 * Zwraca pusto, gdy sciezki nie da sie zbudowac.
 */
static QVector<Zabek> zabkiChmurki( const QVector<QgsPoint> &p, bool zamknieta,
                                    double chmurkaLuk )
{
  QVector<Zabek> zabki;
  if ( p.size() < ( zamknieta ? 3 : 2 ) )
    return zabki;

  QVector<QgsPoint> sciezka = p;
  if ( zamknieta )
    sciezka.append( p.first() );

  QVector<double> narastajaco;
  narastajaco.reserve( sciezka.size() );
  narastajaco.append( 0.0 );
  for ( int i = 1; i < sciezka.size(); ++i )
    narastajaco.append( narastajaco.last() + sciezka.at( i ).distance( sciezka.at( i - 1 ) ) );

  const double obwod = narastajaco.last();
  if ( !( obwod > 0 ) )
    return zabki;

  // Te same liczby, co w `chmurka()`: zero znaczy AUTOMAT, jedna
  // dwudziesta obwodu, zeby chmurka wygladala tak samo niezaleznie od
  // tego, czy obrysowujesz drzewo, czy pole.
  double luk = chmurkaLuk > 0 ? chmurkaLuk : obwod / 20.0;
  luk = std::max( 0.2, std::min( 50.0, luk ) );

  const int najmniej = zamknieta ? 3 : 2;
  int ile = static_cast<int>( std::lround( obwod / luk ) );
  ile = std::max( najmniej, std::min( 400, ile ) );
  luk = obwod / ile;

  auto naSciezce = [&]( double s ) -> QgsPoint {
    if ( s <= 0 )
      return sciezka.first();
    if ( s >= obwod )
      return sciezka.last();
    int i = 1;
    while ( i < narastajaco.size() - 1 && narastajaco.at( i ) < s )
      ++i;
    const double a = narastajaco.at( i - 1 ), b = narastajaco.at( i );
    const double u = ( b > a ) ? ( s - a ) / ( b - a ) : 0.0;
    const QgsPoint &A = sciezka.at( i - 1 );
    const QgsPoint &B = sciezka.at( i );
    return QgsPoint( A.x() + u * ( B.x() - A.x() ), A.y() + u * ( B.y() - A.y() ) );
  };

  // Znak wyprowadzony PROBA (patrz `chmurka()`): przy pierscieniu
  // przeciwnym do wskazowek zegara wnetrze lezy po lewej, wiec na
  // zewnatrz znaczy w prawo.
  double pole2 = 0.0;
  for ( int i = 1; i < sciezka.size(); ++i )
    pole2 += sciezka.at( i - 1 ).x() * sciezka.at( i ).y()
             - sciezka.at( i ).x() * sciezka.at( i - 1 ).y();
  const double strona = zamknieta ? ( pole2 > 0 ? 1.0 : -1.0 ) : 1.0;

  zabki.reserve( ile );
  for ( int z = 0; z < ile; ++z )
  {
    const QgsPoint A = naSciezce( z * luk );
    const QgsPoint B = naSciezce( ( z + 1 ) * luk );

    const double sx = ( A.x() + B.x() ) / 2.0;
    const double sy = ( A.y() + B.y() ) / 2.0;
    const double r = A.distance( B ) / 2.0;
    if ( !( r > 0 ) )
      continue;

    // Szczyt to polowa zamiatania — tam, gdzie luk najdalej odchodzi
    // od cieciwy.
    const double kat = std::atan2( A.y() - sy, A.x() - sx ) + strona * M_PI / 2.0;
    zabki.append( Zabek { A, QgsPoint( sx + r * std::cos( kat ), sy + r * std::sin( kat ) ), B } );
  }

  return zabki;
}

///@endcond

bool Ksztalty::umieLuki( const QString &ksztalt ) const
{
  const QString k = klucz( ksztalt );
  return k == QLatin1String( "okrag" ) || k == QLatin1String( "chmurka" );
}

bool Ksztalty::warstwaPrzyjmieLuki( QObject *warstwa ) const
{
  if ( !warstwa )
    return false;

  // RZUTOWANIE, nie odczyt po nazwie — i to jest poprawka z ostatniej
  // chwili, warta zapamietania.
  //
  // Pierwsza wersja pytala `warstwa->property( "wkbType" )`, przez
  // analogie do `zamien()`, ktore po nazwie wola gumke. Tamto jest
  // uzasadnione: `QfRubberbandModel` to naglowek QFielda, ktorego ten
  // modul celowo nie wciaga. Ale `wkbType` NIE JEST wlasnoscia
  // metaobiektu — sprawdzone: `QgsVectorLayer` wystawia po nazwie tylko
  // objectName, name, autoRefreshInterval, metadata, crs, type, isValid,
  // opacity, mapTipTemplate, mapTipsEnabled, subsetString,
  // displayExpression, editFormConfig, readOnly i supportsEditing.
  //
  // Odczyt oddawal wiec `QVariant(Invalid)`, funkcja zawsze mowila
  // „nie przyjmuje lukow" i KAZDY ksztalt po cichu spadalby na lamana
  // — z dymkiem tlumaczacym cos, co nie bylo prawda. `qgsvectorlayer.h`
  // to naglowek QGIS-a, nie QFielda, wiec nic nie stoi na przeszkodzie,
  // zeby zapytac wprost.
  const QgsVectorLayer *w = qobject_cast<const QgsVectorLayer *>( warstwa );
  if ( !w )
    return false;

  return QgsWkbTypes::isCurvedType( w->wkbType() );
}

QgsGeometry Ksztalty::zbudujLuk( const QString &ksztalt, const QVariantList &punkty,
                                 bool zamknieta ) const
{
  const QString k = klucz( ksztalt );

  if ( k == QLatin1String( "okrag" ) )
  {
    const QVector<QgsPoint> p = naPunkty( punkty );
    if ( p.size() < 2 )
      return QgsGeometry();
    return okragLukiem( p.at( 0 ), p.at( 0 ).distance( p.at( 1 ) ) );
  }

  if ( k == QLatin1String( "chmurka" ) )
  {
    const QVector<Zabek> zabki = zabkiChmurki( naPunkty( punkty ), zamknieta, mChmurkaLuk );
    if ( zabki.size() < 2 )
      return QgsGeometry();

    QgsCompoundCurve *lancuch = new QgsCompoundCurve();
    for ( const Zabek &z : zabki )
    {
      QgsCircularString *polokrag = new QgsCircularString();
      polokrag->setPoints( QgsPointSequence() << z.od << z.szczyt << z.doo );
      lancuch->addCurve( polokrag );
    }

    if ( zamknieta )
    {
      // Lancuch zabkow obchodzi cala sciezke, wiec konczy tam, gdzie
      // zaczal. Gdyby przez zaokraglenia nie domknal sie co do bitu,
      // domykamy odcinkiem — `QgsCurvePolygon` bez domknietego
      // pierscienia jest niepoprawny.
      if ( !lancuch->isClosed() )
      {
        QgsLineString *akord = new QgsLineString();
        akord->setPoints( QgsPointSequence() << lancuch->endPoint() << lancuch->startPoint() );
        lancuch->addCurve( akord );
      }
      QgsCurvePolygon *plat = new QgsCurvePolygon();
      plat->setExteriorRing( lancuch );
      return QgsGeometry( plat );
    }

    // Otwarta konczy sie na ostatnim WSKAZANYM punkcie, a nie w polowie
    // zabka — tak samo jak postac lamana.
    const QVector<QgsPoint> p = naPunkty( punkty );
    if ( !p.isEmpty() && lancuch->endPoint().distance( p.last() ) > 0.0 )
    {
      QgsLineString *ogon = new QgsLineString();
      ogon->setPoints( QgsPointSequence() << lancuch->endPoint() << p.last() );
      lancuch->addCurve( ogon );
    }
    return QgsGeometry( lancuch );
  }

  // Prostokat i krzywa lukow nie maja. Pusto to POPRAWNA odpowiedz.
  return QgsGeometry();
}

QgsGeometry Ksztalty::naTypLuk( const QgsGeometry &ksztalt, int typ ) const
{
  if ( ksztalt.isNull() || ksztalt.isEmpty() )
    return QgsGeometry();

  const Qgis::GeometryType ma = ksztalt.type();
  const Qgis::GeometryType chce = static_cast<Qgis::GeometryType>( typ );
  if ( ma == chce )
    return ksztalt;

  if ( ma == Qgis::GeometryType::Polygon && chce == Qgis::GeometryType::Line )
  {
    const QgsCurvePolygon *w = qgsgeometry_cast<const QgsCurvePolygon *>( ksztalt.constGet() );
    if ( !w || !w->exteriorRing() )
      return QgsGeometry();
    return QgsGeometry( w->exteriorRing()->clone() );
  }

  if ( ma == Qgis::GeometryType::Line && chce == Qgis::GeometryType::Polygon )
  {
    const QgsCurve *c = qgsgeometry_cast<const QgsCurve *>( ksztalt.constGet() );
    if ( !c || c->numPoints() < 3 )
      return QgsGeometry();

    QgsCompoundCurve *pierscien = new QgsCompoundCurve();
    pierscien->addCurve( c->clone() );
    if ( !pierscien->isClosed() )
    {
      QgsLineString *akord = new QgsLineString();
      akord->setPoints( QgsPointSequence() << pierscien->endPoint() << pierscien->startPoint() );
      pierscien->addCurve( akord );
    }

    QgsCurvePolygon *plat = new QgsCurvePolygon();
    plat->setExteriorRing( pierscien );
    return QgsGeometry( plat );
  }

  return QgsGeometry();
}

QgsGeometry Ksztalty::zModeluLuk( QObject *modelGumki, const QString &ksztalt,
                                  double promien, bool zPunktemZywym,
                                  int typDocelowy ) const
{
  if ( !umieLuki( ksztalt ) )
    return QgsGeometry();

  // Z punktem zywym albo bez — TAK SAMO, jak liczy `zModelu`. Wolajacy
  // ma podac to samo, co podal tamtej; inaczej na ekranie bylby jeden
  // okrag, a w pliku drugi.
  const QVector<QgsPoint> punkty = punktyGumki( modelGumki, zPunktemZywym );
  if ( punkty.isEmpty() )
    return QgsGeometry();

  const QString k = klucz( ksztalt );

  // Promien z dalmierza: wystarczy jeden wskazany punkt — srodek.
  if ( promien > 0 && k == QLatin1String( "okrag" ) )
    return okragLukiem( punkty.first(), promien );

  const bool zamknieta = k == QLatin1String( "chmurka" )
                         && static_cast<Qgis::GeometryType>( typDocelowy ) == Qgis::GeometryType::Polygon;

  return naTypLuk( zbudujLuk( ksztalt, jakoWarianty( punkty ), zamknieta ), typDocelowy );
}
