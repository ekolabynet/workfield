/***************************************************************************
  dxfinwentaryzacja.cpp - WorkField
 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "dxfinwentaryzacja.h"

#include <QFile>
#include <QHash>
#include <QList>
#include <QMap>
#include <QRegularExpression>

#include <gdal.h>
#include <ogr_api.h>
#include <cpl_conv.h>
#include <cpl_string.h>

#include <algorithm>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace
{
  // =========================================================================
  // Szablon pustego rysunku (R2018, jednostki: metry). Wygenerowany przez
  // ezdxf.new('R2018', setup=False) - ma STYLE Standard, LTYPE ByBlock
  // i slownik ACAD_MLEADERSTYLE, ktorych potrzebuje MULTILEADER.
  // =========================================================================
  QByteArray szablon();

  // --- pary kod/wartosc ------------------------------------------------------
  struct Dxf
  {
      QList<QByteArray> linie; // bez znakow konca linii
      QByteArray eol = "\n";

      int par() const { return static_cast<int>( linie.size() / 2 ); }
      QByteArray kod( int i ) const { return linie.at( 2 * i ).trimmed(); }
      QByteArray wart( int i ) const { return linie.at( 2 * i + 1 ).trimmed(); }
      bool jest( int i, const char *k, const char *w ) const { return kod( i ) == k && wart( i ) == w; }
  };

  Dxf wczytaj( const QByteArray &bajty )
  {
    Dxf d;
    if ( bajty.contains( "\r\n" ) )
      d.eol = "\r\n";
    d.linie = bajty.split( '\n' );
    for ( QByteArray &l : d.linie )
    {
      if ( l.endsWith( '\r' ) )
        l.chop( 1 );
    }
    while ( !d.linie.isEmpty() && d.linie.last().trimmed().isEmpty() )
      d.linie.removeLast();
    if ( d.linie.size() % 2 )
      d.linie.removeLast();
    return d;
  }

  QByteArray kodDxf( int kod )
  {
    return QByteArray::number( kod ).rightJustified( 3, ' ' );
  }

  QByteArray liczbaDxf( double v )
  {
    QByteArray s = QByteArray::number( v, 'f', 6 );
    // 7508145.192334 zamiast 7508145.192334000; zostawiamy co najmniej .0
    while ( s.endsWith( '0' ) && !s.endsWith( ".0" ) )
      s.chop( 1 );
    return s;
  }

  // Zbiera pary do dopisania.
  struct Pisarz
  {
      QList<QByteArray> linie;
      void p( int kod, const QByteArray &w )
      {
        linie << kodDxf( kod ) << w;
      }
      void p( int kod, double v ) { p( kod, liczbaDxf( v ) ); }
      void pi( int kod, int v ) { p( kod, QByteArray::number( v ) ); }
  };

  // --- zakres sekcji ------------------------------------------------------------
  struct Zakres
  {
      int od = -1; // para "0 SECTION"
      int koniec = -1; // para "0 ENDSEC"
  };

  QHash<QByteArray, Zakres> sekcje( const Dxf &d )
  {
    QHash<QByteArray, Zakres> w;
    for ( int i = 0; i + 1 < d.par(); ++i )
    {
      if ( d.jest( i, "0", "SECTION" ) && d.kod( i + 1 ) == "2" )
      {
        Zakres z;
        z.od = i;
        for ( int j = i + 1; j < d.par(); ++j )
        {
          if ( d.jest( j, "0", "ENDSEC" ) )
          {
            z.koniec = j;
            break;
          }
        }
        w.insert( d.wart( i + 1 ), z );
      }
    }
    return w;
  }

  //! Indeks pary z wartoscia zmiennej naglowka ($HANDSEED -> para "5 ...").
  int zmienna( const Dxf &d, const Zakres &naglowek, const char *nazwa, const char *kod )
  {
    if ( naglowek.od < 0 )
      return -1;
    for ( int i = naglowek.od; i < naglowek.koniec; ++i )
    {
      if ( d.jest( i, "9", nazwa ) )
      {
        for ( int j = i + 1; j < naglowek.koniec && d.kod( j ) != "9"; ++j )
        {
          if ( d.kod( j ) == kod )
            return j;
        }
      }
    }
    return -1;
  }

  //! Koniec obiektu zaczynajacego sie w parze \a i (indeks nastepnego "0").
  int koniecObiektu( const Dxf &d, int i )
  {
    int j = i + 1;
    while ( j < d.par() && d.kod( j ) != "0" )
      ++j;
    return j;
  }

  //! Wartosc pierwszej pary \a kod w obiekcie zaczynajacym sie w \a i.
  QByteArray pole( const Dxf &d, int i, const char *kod )
  {
    const int k = koniecObiektu( d, i );
    for ( int j = i + 1; j < k; ++j )
    {
      if ( d.kod( j ) == kod )
        return d.wart( j );
    }
    return QByteArray();
  }

  struct Tabela
  {
      int naglowek = -1; // "0 TABLE"
      int endtab = -1;   // "0 ENDTAB"
      QByteArray uchwyt;
  };

  Tabela tabela( const Dxf &d, const Zakres &tables, const char *nazwa )
  {
    Tabela t;
    for ( int i = tables.od; i >= 0 && i < tables.koniec; ++i )
    {
      if ( d.jest( i, "0", "TABLE" ) && i + 1 < d.par() && d.kod( i + 1 ) == "2" && d.wart( i + 1 ) == nazwa )
      {
        t.naglowek = i;
        t.uchwyt = pole( d, i, "5" );
        for ( int j = i + 1; j < tables.koniec; ++j )
        {
          if ( d.jest( j, "0", "ENDTAB" ) )
          {
            t.endtab = j;
            break;
          }
        }
        break;
      }
    }
    return t;
  }

  //! Rekord tabeli po nazwie (bez rozrozniania wielkosci liter).
  int rekord( const Dxf &d, const Tabela &t, const char *typ, const QByteArray &nazwa )
  {
    for ( int i = t.naglowek + 1; t.naglowek >= 0 && i < t.endtab; ++i )
    {
      if ( d.jest( i, "0", typ ) && pole( d, i, "2" ).toUpper() == nazwa.toUpper() )
        return i;
    }
    return -1;
  }

  // --- geometria rozmieszczenia (skrypt v1.3, metody pomocnicze) --------------
  struct Prost
  {
      double x0, y0, x1, y1;
  };

  Prost ramkaTekstu( double tx, double ty, int dlugosc, double h, double cw, double m )
  {
    const double w = dlugosc * cw;
    return { tx - m, ty - h / 2 - m, tx + w + m, ty + h / 2 + m };
  }

  bool nachodza( const Prost &a, const Prost &b )
  {
    return !( a.x1 < b.x0 || b.x1 < a.x0 || a.y1 < b.y0 || b.y1 < a.y0 );
  }

  bool kolkoProst( double cx, double cy, double r, const Prost &p )
  {
    const double nx = std::max( p.x0, std::min( cx, p.x1 ) );
    const double ny = std::max( p.y0, std::min( cy, p.y1 ) );
    return std::hypot( cx - nx, cy - ny ) < r;
  }

  bool odcinkiSieTna( double p1x, double p1y, double p2x, double p2y, double p3x, double p3y, double p4x, double p4y )
  {
    const double d1x = p2x - p1x, d1y = p2y - p1y;
    const double d2x = p4x - p3x, d2y = p4y - p3y;
    const double cross = d1x * d2y - d1y * d2x;
    if ( std::abs( cross ) < 1e-10 )
      return false;
    const double dx = p3x - p1x, dy = p3y - p1y;
    const double t = ( dx * d2y - dy * d2x ) / cross;
    const double u = ( dx * d1y - dy * d1x ) / cross;
    return 0.01 < t && t < 0.99 && 0.01 < u && u < 0.99;
  }

  bool liniaBlisko( double lx, double ly, double ex, double ey, double cx, double cy, double r )
  {
    const double dx = ex - lx, dy = ey - ly;
    const double t = std::max( 0.0, std::min( 1.0, ( ( cx - lx ) * dx + ( cy - ly ) * dy ) / ( dx * dx + dy * dy + 1e-10 ) ) );
    return std::hypot( cx - lx - t * dx, cy - ly - t * dy ) < r;
  }

  struct Punkt
  {
      double cx, cy, r, rCtr;
      QString etykieta;
  };

  struct Miejsce
  {
      bool jest = false;
      double lx, ly, ex, ey, tx, ty, kat;
      Prost ramka;
  };

  struct Odcinek
  {
      double x0, y0, x1, y1;
  };

  Miejsce umiescEtykiete( const Punkt &pt, const QVector<Punkt> &wszystkie, const QVector<Prost> &ramki,
                          const QVector<Odcinek> &odcinki, double h, double cw, double m, double dMin, double dMax )
  {
    static const int KATY[] = { 45, 135, 225, 315, 30, 60, 120, 150, 210, 240, 300, 330,
                                0, 90, 180, 270, 22, 67, 112, 157, 202, 247, 292, 337 };
    const double gorny = dMax > 0 ? dMax : 15.0;
    const double krok = std::max( ( gorny - dMin ) / 6.0, 0.5 );
    QVector<double> odleglosci;
    for ( double d = dMin; d <= gorny + 0.001; d += krok )
      odleglosci << std::round( d * 1000.0 ) / 1000.0;
    if ( odleglosci.isEmpty() )
      odleglosci << dMin;

    const int dl = static_cast<int>( pt.etykieta.size() );
    for ( const double dist : std::as_const( odleglosci ) )
    {
      for ( const int katSt : KATY )
      {
        const double rad = katSt * M_PI / 180.0;
        const double ca = std::cos( rad ), sa = std::sin( rad );
        const double lx = pt.cx + pt.rCtr * ca, ly = pt.cy + pt.rCtr * sa;
        const double ex = pt.cx + ( pt.r + dist ) * ca, ey = pt.cy + ( pt.r + dist ) * sa;
        const double szer = dl * cw;
        const double tx = ca >= 0 ? ex : ex - szer;
        const Prost ramka = ramkaTekstu( tx, ey, dl, h, cw, m );

        bool kolizja = false;
        for ( const Punkt &o : wszystkie )
        {
          if ( kolkoProst( o.cx, o.cy, std::max( o.r, o.rCtr ), ramka ) )
          {
            kolizja = true;
            break;
          }
        }
        if ( kolizja )
          continue;
        for ( const Prost &p : ramki )
        {
          if ( nachodza( ramka, p ) )
          {
            kolizja = true;
            break;
          }
        }
        if ( kolizja )
          continue;
        for ( const Odcinek &o : odcinki )
        {
          if ( odcinkiSieTna( lx, ly, ex, ey, o.x0, o.y0, o.x1, o.y1 ) )
          {
            kolizja = true;
            break;
          }
        }
        if ( kolizja )
          continue;
        for ( const Punkt &o : wszystkie )
        {
          if ( &o != &pt && liniaBlisko( lx, ly, ex, ey, o.cx, o.cy, o.rCtr * 3 ) )
          {
            kolizja = true;
            break;
          }
        }
        if ( kolizja )
          continue;

        Miejsce w;
        w.jest = true;
        w.lx = lx;
        w.ly = ly;
        w.ex = ex;
        w.ey = ey;
        w.tx = tx;
        w.ty = ey;
        w.kat = katSt;
        w.ramka = ramka;
        return w;
      }
    }
    return Miejsce();
  }

  //! Tekst MTEXT bez kodow formatowania - do oceny szerokosci istniejacych napisow.
  QString goly( QString t )
  {
    static const QRegularExpression kody( QStringLiteral( R"(\\[A-Za-z][^;\\]*;|\\[PpNn~]|[{}])" ) );
    return t.replace( kody, QStringLiteral( " " ) );
  }
  // clang-format off
  // Szablon: ezdxf.new('R2018', setup=False), $INSUNITS=6 (metry), 15293 bajtow,
  // skompresowany qCompress i zapisany base64 (5184 znakow zamiast 15293).
  QByteArray szablon()
  {
    static const QByteArray s = qUncompress( QByteArray::fromBase64(
      "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"
    ) );
    return s;
  }
  // clang-format on
} // namespace

namespace DxfInwentaryzacja
{
  double liczba( const QString &tekst )
  {
    static const QRegularExpression wz( QStringLiteral( R"((\d+(?:[.,]\d+)?))" ) );
    const QRegularExpressionMatch m = wz.match( tekst );
    if ( !m.hasMatch() )
      return 0.0;
    return m.captured( 1 ).replace( QLatin1Char( ',' ), QLatin1Char( '.' ) ).toDouble();
  }

  double srednicaZObwodow( const QString &opis, QString *uwaga )
  {
    QString t = opis.trimmed().toLower();
    if ( t.isEmpty() )
      return 0.0;
    // Powierzchnia krzewow, nie pien.
    if ( t.contains( QLatin1String( "m2" ) ) || t.contains( QChar( 0x00B2 ) ) )
    {
      if ( uwaga )
        *uwaga = QStringLiteral( "powierzchnia, nie obwod" );
      return 0.0;
    }
    // Minus i przecinek miedzy liczbami jak plus ("68-67", "56,48").
    // Przecinek dziesietny ("7,5") zostaje: wymaga cyfry po obu stronach
    // i co najwyzej dwoch cyfr po nim - obwod pnia to liczba calkowita.
    static const QRegularExpression minus( QStringLiteral( R"((\d)\s*-\s*(?=\D*\d))" ) );
    t.replace( minus, QStringLiteral( "\\1+" ) );
    static const QRegularExpression przecinek( QStringLiteral( R"((\d)\s*,\s*(?=\D*\d{3}|\D+\d))" ) );
    t.replace( przecinek, QStringLiteral( "\\1+" ) );

    static const QRegularExpression czesc( QStringLiteral( R"(^\s*(śr|sr|s|ø|φ|d)?\s*\.?\s*(?:ok\.?\s*)?(\d+(?:[.,]\d+)?))" ) );
    static const QRegularExpression dowolna( QStringLiteral( R"((\d+(?:[.,]\d+)?))" ) );
    QVector<double> obwody; // [cm]
    bool bylaSrednica = false;
    const QStringList czesci = t.split( QLatin1Char( '+' ), Qt::SkipEmptyParts );
    for ( const QString &c : czesci )
    {
      double v = 0.0;
      bool srednica = false;
      const QRegularExpressionMatch m = czesc.match( c );
      if ( m.hasMatch() )
      {
        v = m.captured( 2 ).replace( QLatin1Char( ',' ), QLatin1Char( '.' ) ).toDouble();
        srednica = !m.captured( 1 ).isEmpty();
      }
      else
      {
        const QRegularExpressionMatch m2 = dowolna.match( c );
        if ( m2.hasMatch() )
          v = m2.captured( 1 ).replace( QLatin1Char( ',' ), QLatin1Char( '.' ) ).toDouble();
      }
      if ( v <= 0 )
        continue;
      if ( srednica )
      {
        bylaSrednica = true;
        v *= M_PI; // srednica -> obwod, zeby wzor byl jeden
      }
      obwody << v;
    }
    if ( obwody.isEmpty() )
      return 0.0;
    std::sort( obwody.begin(), obwody.end(), std::greater<double>() );
    double efektywny = obwody.first();
    for ( int i = 1; i < obwody.size(); ++i )
      efektywny += 0.5 * obwody.at( i );
    if ( uwaga && bylaSrednica )
      *uwaga = QStringLiteral( "srednica (sr/s), nie obwod" );
    return efektywny / 100.0 / M_PI;
  }

  Wynik dopisz( const QByteArray &bazowy, const QVector<Drzewo> &drzewa, const Ustawienia &ust,
                QByteArray ( *koduj )( const QString & ) )
  {
    Wynik wynik;
    Dxf d = wczytaj( bazowy.isEmpty() ? szablon() : bazowy );
    const QHash<QByteArray, Zakres> sek = sekcje( d );
    const Zakres naglowek = sek.value( "HEADER" );
    const Zakres tables = sek.value( "TABLES" );
    const Zakres entities = sek.value( "ENTITIES" );
    const Zakres objects = sek.value( "OBJECTS" );
    if ( entities.koniec < 0 || tables.koniec < 0 )
    {
      wynik.uwagi << QStringLiteral( "Rysunek bez sekcji ENTITIES/TABLES - nie umiem do niego dopisac" );
      return wynik;
    }

    // --- wersja i uchwyty -------------------------------------------------
    const int iWersja = zmienna( d, naglowek, "$ACADVER", "1" );
    const QByteArray wersja = iWersja >= 0 ? d.wart( iWersja ) : QByteArray( "AC1009" );
    const int nrWersji = wersja.mid( 2 ).toInt();
    const bool zUchwytami = nrWersji >= 1015;  // R2000+
    const bool utf8 = nrWersji >= 1021;        // R2007+
    const int iSeed = zmienna( d, naglowek, "$HANDSEED", "5" );
    bool ok = false;
    qulonglong seed = iSeed >= 0 ? d.wart( iSeed ).toULongLong( &ok, 16 ) : 0;
    if ( !ok )
      seed = 0;
    // Nastepny wolny uchwyt: HANDSEED, ale nigdy ponizej najwiekszego
    // istniejacego (niektore programy zapisuja HANDSEED za nisko).
    for ( int i = 0; i < d.par(); ++i )
    {
      const QByteArray k = d.kod( i );
      if ( k == "5" || k == "105" )
      {
        const qulonglong h = d.wart( i ).toULongLong( &ok, 16 );
        if ( ok && h >= seed )
          seed = h + 1;
      }
    }
    auto nowy = [&seed]() { return QByteArray::number( seed++, 16 ).toUpper(); };
    auto tekstDxf = [&]( const QString &s ) -> QByteArray {
      if ( utf8 )
        return s.toUtf8();
      return koduj ? koduj( s ) : s.toLatin1();
    };

    // --- odwolania: model, tabele, style ---------------------------------
    const Tabela tBlockRecord = tabela( d, tables, "BLOCK_RECORD" );
    const int iModel = rekord( d, tBlockRecord, "BLOCK_RECORD", "*Model_Space" );
    const QByteArray model = iModel >= 0 ? pole( d, iModel, "5" ) : QByteArray();
    const Tabela tLayer = tabela( d, tables, "LAYER" );
    const Tabela tStyle = tabela( d, tables, "STYLE" );
    const Tabela tLtype = tabela( d, tables, "LTYPE" );
    const int iStyl = rekord( d, tStyle, "STYLE", "Standard" );
    const QByteArray stylTekstu = iStyl >= 0 ? pole( d, iStyl, "5" ) : QByteArray();
    const int iByBlock = rekord( d, tLtype, "LTYPE", "ByBlock" );
    const QByteArray liniaByBlock = iByBlock >= 0 ? pole( d, iByBlock, "5" ) : QByteArray();
    if ( tLayer.naglowek < 0 )
    {
      wynik.uwagi << QStringLiteral( "Rysunek bez tabeli LAYER - nie umiem do niego dopisac" );
      return wynik;
    }

    // --- styl MULTILEADER: slownik ACAD_MLEADERSTYLE w OBJECTS ------------------
    QByteArray slownikStyli, stylOdsylacza;
    int iSlownikStyli = -1;
    if ( utf8 && objects.od >= 0 )
    {
      for ( int i = objects.od; i < objects.koniec; ++i )
      {
        if ( d.kod( i ) == "3" && d.wart( i ) == "ACAD_MLEADERSTYLE" && i + 1 < d.par() && d.kod( i + 1 ) == "350" )
        {
          slownikStyli = d.wart( i + 1 );
          break;
        }
      }
      for ( int i = objects.od; !slownikStyli.isEmpty() && i < objects.koniec; ++i )
      {
        if ( d.jest( i, "0", "DICTIONARY" ) && pole( d, i, "5" ) == slownikStyli )
        {
          iSlownikStyli = i;
          const int k = koniecObiektu( d, i );
          for ( int j = i + 1; j + 1 < k; ++j )
          {
            if ( d.kod( j ) == "3" && d.wart( j ) == "CALLOUT_STYLE" && d.kod( j + 1 ) == "350" )
              stylOdsylacza = d.wart( j + 1 );
          }
          break;
        }
      }
    }
    const bool multileader = utf8 && zUchwytami && iSlownikStyli >= 0 && !model.isEmpty() && !stylTekstu.isEmpty() && !liniaByBlock.isEmpty();
    wynik.odsylacz = multileader ? QStringLiteral( "MULTILEADER" ) : QStringLiteral( "LINE+TEXT" );
    if ( !multileader )
      wynik.uwagi << QStringLiteral( "Rysunek %1 bez stylu MULTILEADER - odsylacze jako LINE+TEXT" ).arg( QString::fromLatin1( wersja ) );

    QHash<int, QList<QByteArray>> przed; // pary wstawiane PRZED para o indeksie
    auto wstawPrzed = [&przed]( int i, const QList<QByteArray> &l ) { przed[i] << l; };

    // --- warstwy ---------------------------------------------------------------
    const int iWarstwa0 = rekord( d, tLayer, "LAYER", "0" );
    auto warstwa = [&]( const QByteArray &nazwa ) {
      if ( rekord( d, tLayer, "LAYER", nazwa ) >= 0 )
        return; // juz jest - dopisujemy do istniejacej
      Pisarz w;
      if ( zUchwytami && iWarstwa0 >= 0 )
      {
        // Klon warstwy "0": ten sam zestaw pol (390 styl wydruku, 370...),
        // ktorego oczekuje program, ktory zapisal rysunek.
        const int k = koniecObiektu( d, iWarstwa0 );
        w.linie << d.linie.at( 2 * iWarstwa0 ) << d.linie.at( 2 * iWarstwa0 + 1 );
        for ( int j = iWarstwa0 + 1; j < k; ++j )
        {
          const QByteArray kd = d.kod( j );
          if ( kd == "5" )
            w.p( 5, nowy() );
          else if ( kd == "2" )
            w.p( 2, nazwa );
          else if ( kd == "62" )
            w.pi( 62, ust.aciWarstw );
          else if ( kd == "70" )
            w.pi( 70, 0 );
          else
            w.linie << d.linie.at( 2 * j ) << d.linie.at( 2 * j + 1 );
        }
      }
      else
      {
        w.p( 0, "LAYER" );
        if ( zUchwytami )
        {
          w.p( 5, nowy() );
          w.p( 330, tLayer.uchwyt );
          w.p( 100, "AcDbSymbolTableRecord" );
          w.p( 100, "AcDbLayerTableRecord" );
        }
        w.p( 2, nazwa );
        w.pi( 70, 0 );
        w.pi( 62, ust.aciWarstw );
        w.p( 6, "CONTINUOUS" );
      }
      wstawPrzed( tLayer.endtab, w.linie );
    };

    // --- encje -------------------------------------------------------------
    Pisarz e;
    auto poczatek = [&]( const char *typ, const QByteArray &nazwaWarstwy, const char *podklasa ) {
      e.p( 0, typ );
      if ( zUchwytami )
      {
        e.p( 5, nowy() );
        e.p( 330, model );
        e.p( 100, "AcDbEntity" );
      }
      e.p( 8, nazwaWarstwy );
      if ( zUchwytami )
        e.p( 100, podklasa );
    };
    double minX = 1e300, minY = 1e300, maxX = -1e300, maxY = -1e300;
    auto zasieg = [&]( double x, double y, double r ) {
      minX = std::min( minX, x - r );
      minY = std::min( minY, y - r );
      maxX = std::max( maxX, x + r );
      maxY = std::max( maxY, y + r );
    };
    auto okrag = [&]( const QByteArray &w, double x, double y, double r ) {
      poczatek( "CIRCLE", w, "AcDbCircle" );
      e.p( 10, x );
      e.p( 20, y );
      e.p( 30, 0.0 );
      e.p( 40, r );
      zasieg( x, y, r );
    };
    auto linia = [&]( const QByteArray &w, double x0, double y0, double x1, double y1 ) {
      poczatek( "LINE", w, "AcDbLine" );
      e.p( 10, x0 );
      e.p( 20, y0 );
      e.p( 30, 0.0 );
      e.p( 11, x1 );
      e.p( 21, y1 );
      e.p( 31, 0.0 );
    };
    auto tekst = [&]( const QByteArray &w, double x, double y, double h, const QString &t ) {
      // TEXT wysrodkowany (72=1, 73=2) - punkt w 10 i 11.
      poczatek( "TEXT", w, "AcDbText" );
      e.p( 10, x );
      e.p( 20, y );
      e.p( 30, 0.0 );
      e.p( 40, h );
      e.p( 1, tekstDxf( t ) );
      e.pi( 72, 1 );
      e.p( 11, x );
      e.p( 21, y );
      e.p( 31, 0.0 );
      if ( zUchwytami )
        e.p( 100, "AcDbText" );
      e.pi( 73, 2 );
    };

    // --- styl odsylacza (klon ustawien skryptu: bez grota i polki) -----------
    if ( multileader && stylOdsylacza.isEmpty() )
    {
      stylOdsylacza = nowy();
      Pisarz s;
      s.p( 0, "MLEADERSTYLE" );
      s.p( 5, stylOdsylacza );
      s.p( 102, "{ACAD_REACTORS" );
      s.p( 330, slownikStyli );
      s.p( 102, "}" );
      s.p( 330, slownikStyli );
      s.p( 100, "AcDbMLeaderStyle" );
      s.pi( 179, 2 );
      s.pi( 170, 2 );
      s.pi( 171, 1 );
      s.pi( 172, 0 );
      s.pi( 90, 2 );
      s.p( 40, 0.0 );
      s.p( 41, 0.0 );
      s.pi( 173, 1 );
      s.pi( 91, 256 );
      s.pi( 92, -2 );
      s.pi( 290, 1 );
      s.p( 42, 0.0 );
      s.pi( 291, 0 );
      s.p( 43, 0.0 );
      s.p( 3, "CALLOUT_STYLE" );
      s.p( 44, 0.0 );
      s.p( 300, "" );
      s.pi( 174, 1 );
      s.pi( 175, 1 );
      s.pi( 176, 0 );
      s.pi( 178, 1 );
      s.pi( 93, 256 );
      s.p( 45, ust.wysokoscTekstu );
      s.pi( 292, 0 );
      s.pi( 297, 0 );
      s.p( 46, 4.0 );
      s.pi( 94, -1056964608 );
      s.p( 47, 1.0 );
      s.p( 49, 1.0 );
      s.p( 140, 1.0 );
      s.pi( 294, 1 );
      s.p( 141, 0.0 );
      s.pi( 177, 0 );
      s.p( 142, 1.0 );
      s.pi( 295, 0 );
      s.pi( 296, 0 );
      s.p( 143, 3.75 );
      s.pi( 271, 0 );
      s.pi( 272, 9 );
      s.pi( 273, 9 );
      wstawPrzed( objects.koniec, s.linie );
      // wpis w slowniku stylow
      Pisarz wpis;
      wpis.p( 3, "CALLOUT_STYLE" );
      wpis.p( 350, stylOdsylacza );
      wstawPrzed( koniecObiektu( d, iSlownikStyli ), wpis.linie );
    }

    auto odsylacz = [&]( double lx, double ly, double cx, double cy, bool wPrawo, const QString &t ) {
      // MULTILEADER jak w wynikach skryptu v1.3 (ezdxf quick_leader,
      // polaczenie "middle_of_top_line", grot 0, bez polki).
      const double h = ust.wysokoscTekstu;
      const double szer = t.size() * ( ust.szerokoscZnaku > 0 ? ust.szerokoscZnaku : 0.6 * h );
      const int zaczep = wPrawo ? 1 : 3;
      poczatek( "MULTILEADER", "ETY_ODSYL", "AcDbMLeader" );
      e.pi( 270, 2 );
      e.p( 300, "CONTEXT_DATA{" );
      e.p( 40, 1.0 );
      e.p( 10, wPrawo ? cx : cx - szer );
      e.p( 20, cy );
      e.p( 30, 0.0 );
      e.p( 41, h );
      e.p( 140, 0.0 );
      e.p( 145, 0.0 );
      e.pi( 174, 1 );
      e.pi( 175, 1 );
      e.pi( 176, 0 );
      e.pi( 177, 0 );
      e.pi( 290, 1 );
      e.p( 304, tekstDxf( t ) );
      e.p( 11, 0.0 );
      e.p( 21, 0.0 );
      e.p( 31, 1.0 );
      e.p( 340, stylTekstu );
      e.p( 12, cx );
      e.p( 22, cy + h / 2 );
      e.p( 32, 0.0 );
      e.p( 13, 1.0 );
      e.p( 23, 0.0 );
      e.p( 33, 0.0 );
      e.p( 42, 0.0 );
      e.p( 43, 0.0 );
      e.p( 44, 0.0 );
      e.p( 45, 1.0 );
      e.pi( 170, 1 );
      e.pi( 90, 256 );
      e.pi( 171, zaczep );
      e.pi( 172, 1 );
      e.pi( 91, -939524096 );
      e.p( 141, 1.5 );
      e.pi( 92, 0 );
      e.pi( 291, 0 );
      e.pi( 292, 0 );
      e.pi( 173, 0 );
      e.pi( 293, 0 );
      e.p( 142, 0.0 );
      e.p( 143, 0.0 );
      e.pi( 294, 0 );
      e.pi( 295, 1 );
      e.pi( 296, 0 );
      e.p( 110, 0.0 );
      e.p( 120, 0.0 );
      e.p( 130, 0.0 );
      e.p( 111, 1.0 );
      e.p( 121, 0.0 );
      e.p( 131, 0.0 );
      e.p( 112, 0.0 );
      e.p( 122, 1.0 );
      e.p( 132, 0.0 );
      e.pi( 297, 0 );
      e.p( 302, "LEADER{" );
      e.pi( 290, 1 );
      e.pi( 291, 1 );
      e.p( 10, cx );
      e.p( 20, cy );
      e.p( 30, 0.0 );
      e.p( 11, wPrawo ? 1.0 : -1.0 );
      e.p( 21, 0.0 );
      e.p( 31, 0.0 );
      e.pi( 90, 0 );
      e.p( 40, 0.0 );
      e.p( 304, "LEADER_LINE{" );
      e.p( 10, lx );
      e.p( 20, ly );
      e.p( 30, 0.0 );
      e.pi( 91, 0 );
      e.pi( 92, -1056964608 );
      e.p( 305, "}" );
      e.pi( 271, 0 );
      e.p( 303, "}" );
      e.pi( 272, 9 );
      e.pi( 273, 9 );
      e.p( 301, "}" );
      e.p( 340, stylOdsylacza );
      e.pi( 90, 2147483647 );
      e.pi( 170, 1 );
      e.pi( 91, -1073741824 );
      e.p( 341, liniaByBlock );
      e.pi( 171, 25 );
      e.pi( 290, 1 );
      e.pi( 291, 0 );
      e.p( 41, 0.0 );
      e.p( 42, 0.0 );
      e.pi( 172, 2 );
      e.p( 343, stylTekstu );
      e.pi( 173, 1 );
      e.pi( 95, 1 );
      e.pi( 174, 1 );
      e.pi( 175, 0 );
      e.pi( 92, -1073741824 );
      e.pi( 292, 0 );
      e.pi( 93, -1056964608 );
      e.p( 10, 1.0 );
      e.p( 20, 1.0 );
      e.p( 30, 1.0 );
      e.p( 43, 0.0 );
      e.pi( 176, 0 );
      e.pi( 293, 0 );
      e.pi( 294, 0 );
      e.pi( 178, 0 );
      e.pi( 179, zaczep );
      e.p( 45, 1.0 );
      e.pi( 271, 0 );
      e.pi( 272, 9 );
      e.pi( 273, 9 );
      e.pi( 295, 0 );
    };

    // --- istniejace napisy rysunku = strefy zakazane dla etykiet --------------
    const double h = ust.wysokoscTekstu;
    const double cw = ust.szerokoscZnaku > 0 ? ust.szerokoscZnaku : 0.6 * h;
    const double m = ust.margines;
    QVector<Prost> ramki;
    QVector<Odcinek> odcinki;
    {
      QByteArray typ;
      double x = 0, y = 0, wys = 0;
      QString t;
      auto zamknij = [&]() {
        if ( typ == "TEXT" || typ == "MTEXT" )
        {
          const double hh = std::max( wys > 0 ? wys : h, 0.001 );
          const double w = goly( t ).trimmed().size() * hh * 0.7;
          ramki << Prost { x - m, y - hh / 2 - m, x + w + m, y + hh / 2 + m };
        }
      };
      for ( int i = entities.od + 2; i < entities.koniec; ++i )
      {
        const QByteArray k = d.kod( i );
        if ( k == "0" )
        {
          zamknij();
          typ = d.wart( i );
          x = y = wys = 0;
          t.clear();
        }
        else if ( k == "10" )
          x = d.wart( i ).toDouble();
        else if ( k == "20" )
          y = d.wart( i ).toDouble();
        else if ( k == "40" )
          wys = d.wart( i ).toDouble();
        else if ( k == "1" || k == "3" )
          t += QString::fromUtf8( d.wart( i ) );
      }
      zamknij();
    }
    const int napisyRysunku = static_cast<int>( ramki.size() );

    // --- punkty, kolejnosc od najciasniejszych -------------------------------
    QVector<Punkt> pkt;
    pkt.reserve( drzewa.size() );
    for ( const Drzewo &dr : drzewa )
      pkt << Punkt { dr.x, dr.y, std::max( 0.0, dr.rKorony ), dr.rPnia > 0 ? dr.rPnia : ust.promienZastepczy, dr.etykieta };

    QVector<int> kolejnosc( pkt.size() );
    for ( int i = 0; i < pkt.size(); ++i )
      kolejnosc[i] = i;
    QVector<int> ciasnota( pkt.size(), 0 );
    for ( int i = 0; i < pkt.size(); ++i )
      for ( int j = 0; j < pkt.size(); ++j )
        if ( i != j && std::hypot( pkt[i].cx - pkt[j].cx, pkt[i].cy - pkt[j].cy ) < pkt[i].r + pkt[j].r + 2 )
          ++ciasnota[i];
    std::stable_sort( kolejnosc.begin(), kolejnosc.end(), [&]( int a, int b ) { return ciasnota[a] > ciasnota[b]; } );

    QVector<Miejsce> miejsca( pkt.size() );
    for ( const int i : std::as_const( kolejnosc ) )
    {
      if ( pkt[i].etykieta.isEmpty() )
        continue;
      const Miejsce w = umiescEtykiete( pkt[i], pkt, ramki, odcinki, h, cw, m, ust.odsylaczMin, ust.odsylaczMax );
      if ( w.jest )
      {
        ramki << w.ramka;
        odcinki << Odcinek { w.lx, w.ly, w.ex, w.ey };
      }
      miejsca[i] = w;
    }

    // --- zapis w kolejnosci drzew ----------------------------------------------
    bool uzyteKola = false, uzyteEtykiety = false, uzyteOdsylacze = false, uzyteEtyOdsyl = false;
    for ( int i = 0; i < pkt.size(); ++i )
    {
      const Punkt &p = pkt[i];
      if ( p.r > 0 )
      {
        okrag( "KOLA", p.cx, p.cy, p.r );
        uzyteKola = true;
      }
      okrag( "CENTROIDY", p.cx, p.cy, p.rCtr );
      if ( p.etykieta.isEmpty() )
        continue;
      const Miejsce &w = miejsca[i];
      if ( !w.jest )
      {
        tekst( "ETYKIETY", p.cx, p.cy, h, p.etykieta );
        uzyteEtykiety = true;
        ++wynik.etykietyBezMiejsca;
        continue;
      }
      const double rad = w.kat * M_PI / 180.0;
      const double exS = w.ex - std::cos( rad ) * m;
      const double eyS = w.ey - std::sin( rad ) * m;
      if ( multileader )
      {
        odsylacz( w.lx, w.ly, exS, eyS, std::cos( rad ) >= 0, p.etykieta );
        uzyteEtyOdsyl = true;
      }
      else
      {
        linia( "ODSYLACZE", w.lx, w.ly, exS, eyS );
        tekst( "ETY_ODSYL", w.tx + p.etykieta.size() * cw / 2, w.ty, h, p.etykieta );
        uzyteOdsylacze = uzyteEtyOdsyl = true;
      }
      ++wynik.etykietyZOdsylaczem;
    }

    if ( uzyteKola )
      warstwa( "KOLA" );
    warstwa( "CENTROIDY" );
    if ( uzyteEtykiety )
      warstwa( "ETYKIETY" );
    if ( uzyteOdsylacze )
      warstwa( "ODSYLACZE" );
    if ( uzyteEtyOdsyl )
      warstwa( "ETY_ODSYL" );
    wstawPrzed( entities.koniec, e.linie );

    // --- naglowek: HANDSEED i zasieg ---------------------------------------------
    QHash<int, QByteArray> zamiana; // indeks pary -> nowa linia wartosci
    if ( iSeed >= 0 )
      zamiana.insert( iSeed, QByteArray::number( seed, 16 ).toUpper() );
    if ( !pkt.isEmpty() )
    {
      auto popraw = [&]( const char *nazwa, const char *kod, double v, bool mniejsze ) {
        const int j = zmienna( d, naglowek, nazwa, kod );
        if ( j < 0 )
          return;
        bool okV = false;
        const double stare = d.wart( j ).toDouble( &okV );
        const bool pusty = !okV || std::abs( stare ) >= 1e19;
        if ( pusty || ( mniejsze ? v < stare : v > stare ) )
          zamiana.insert( j, liczbaDxf( v ) );
      };
      popraw( "$EXTMIN", "10", minX, true );
      popraw( "$EXTMIN", "20", minY, true );
      popraw( "$EXTMAX", "10", maxX, false );
      popraw( "$EXTMAX", "20", maxY, false );
    }

    // --- zlozenie ------------------------------------------------------------
    QList<QByteArray> wyj;
    wyj.reserve( d.linie.size() + e.linie.size() + 64 );
    for ( int i = 0; i < d.par(); ++i )
    {
      if ( przed.contains( i ) )
        wyj << przed.value( i );
      wyj << d.linie.at( 2 * i );
      wyj << ( zamiana.contains( i ) ? zamiana.value( i ) : d.linie.at( 2 * i + 1 ) );
    }
    wynik.dxf = wyj.join( d.eol ) + d.eol;
    wynik.uwagi << QStringLiteral( "Inwentaryzacja: %1 drzew, %2 etykiet z odsylaczem, %3 bez miejsca, %4 napisow rysunku omijanych, odsylacze %5, DXF %6" )
                     .arg( pkt.size() )
                     .arg( wynik.etykietyZOdsylaczem )
                     .arg( wynik.etykietyBezMiejsca )
                     .arg( napisyRysunku )
                     .arg( wynik.odsylacz, QString::fromLatin1( wersja ) );
    return wynik;
  }

  // --- ODS pisany recznie (WorkField 19.09.2026) --------------------------------
  // Sterownik ODS z GDAL zapisuje same wartosci. Arkusz roboczy pracowni ma
  // wyglad: czcionka Barlow, obramowania, zawijanie, szerokosci kolumn,
  // kolorowana kolumna Grupa, zamrozony naglowek, autofiltr - i formuly, bo
  // tabela jest dalej uzupelniana w biurze. Piszemy wiec content.xml sami,
  // a zip robi GDAL (CPLCreateZip), bez nowej zaleznosci.
  namespace
  {
    //! Kolumna arkusza w notacji literowej: 0 -> A, 26 -> AA.
    QString litera( int i )
    {
      QString s;
      for ( ++i; i > 0; i = ( i - 1 ) / 26 )
        s.prepend( QChar( 'A' + ( i - 1 ) % 26 ) );
      return s;
    }

    QString atrybut( const QString &t )
    {
      QString s = t.toHtmlEscaped(); // & < > "
      s.replace( QLatin1Char( '\'' ), QLatin1String( "&apos;" ) );
      return s;
    }

    //! Tekst jako akapity ODF: nowe linie -> <text:p>, spacje wielokrotne,
    //! wiodace i koncowe -> <text:s/> (ODF zwija biale znaki).
    QString akapity( const QString &t )
    {
      QString wy;
      const QStringList linie = t.split( QRegularExpression( QStringLiteral( "\r\n|\r|\n" ) ) );
      for ( const QString &l : linie )
      {
        QString p;
        int spacje = 0;
        auto zrzuc = [&]( bool koniec ) {
          if ( spacje == 0 )
            return;
          if ( p.isEmpty() || koniec )
            p += QStringLiteral( "<text:s text:c=\"%1\"/>" ).arg( spacje );
          else
          {
            p += QLatin1Char( ' ' );
            if ( spacje > 1 )
              p += QStringLiteral( "<text:s text:c=\"%1\"/>" ).arg( spacje - 1 );
          }
          spacje = 0;
        };
        for ( const QChar ch : l )
        {
          if ( ch == QLatin1Char( ' ' ) )
          {
            ++spacje;
            continue;
          }
          zrzuc( false );
          if ( ch == QLatin1Char( '\t' ) )
            p += QLatin1String( "<text:tab/>" );
          else if ( ch.unicode() < 0x20 || ch.unicode() == 0xFFFE || ch.unicode() == 0xFFFF )
            continue; // znaki niedozwolone w XML
          else if ( ch == QLatin1Char( '&' ) )
            p += QLatin1String( "&amp;" );
          else if ( ch == QLatin1Char( '<' ) )
            p += QLatin1String( "&lt;" );
          else if ( ch == QLatin1Char( '>' ) )
            p += QLatin1String( "&gt;" );
          else
            p += ch;
        }
        zrzuc( true );
        wy += QStringLiteral( "<text:p>%1</text:p>" ).arg( p );
      }
      return wy;
    }

    QString liczbaOds( double v )
    {
      return QString::number( v, 'g', 15 );
    }

    QString styl( const QString &s )
    {
      return s.isEmpty() ? QString() : QStringLiteral( " table:style-name=\"%1\"" ).arg( s );
    }

    QString kPusta( const QString &s )
    {
      return QStringLiteral( "<table:table-cell%1/>" ).arg( styl( s ) );
    }

    QString kTekst( const QString &s, const QString &t )
    {
      if ( t.isEmpty() )
        return kPusta( s );
      return QStringLiteral( "<table:table-cell%1 office:value-type=\"string\">%2</table:table-cell>" ).arg( styl( s ), akapity( t ) );
    }

    QString kLiczba( const QString &s, double v )
    {
      return QStringLiteral( "<table:table-cell%1 office:value-type=\"float\" office:value=\"%2\"><text:p>%2</text:p></table:table-cell>" ).arg( styl( s ), liczbaOds( v ) );
    }

    //! Formula z zapamietanym wynikiem liczbowym (albo pustym, gdy \a v jest NaN).
    QString kFormula( const QString &s, const QString &f, double v )
    {
      if ( std::isnan( v ) )
        return QStringLiteral( "<table:table-cell%1 table:formula=\"%2\" office:value-type=\"string\" office:string-value=\"\"><text:p/></table:table-cell>" ).arg( styl( s ), atrybut( f ) );
      return QStringLiteral( "<table:table-cell%1 table:formula=\"%2\" office:value-type=\"float\" office:value=\"%3\"><text:p>%3</text:p></table:table-cell>" ).arg( styl( s ), atrybut( f ), liczbaOds( v ) );
    }

    QString kFormulaTekst( const QString &s, const QString &f, const QString &t )
    {
      return QStringLiteral( "<table:table-cell%1 table:formula=\"%2\" office:value-type=\"string\" office:string-value=\"%3\">%4</table:table-cell>" ).arg( styl( s ), atrybut( f ), atrybut( t ), akapity( t ) );
    }

    //! Czysta liczba ("7", "7,5", "103") -> komorka liczbowa, reszta -> tekst.
    bool czystaLiczba( const QString &t, double *v )
    {
      static const QRegularExpression re( QStringLiteral( "^[+-]?\\d+([.,]\\d+)?$" ) );
      if ( !re.match( t ).hasMatch() )
        return false;
      *v = QString( t ).replace( QLatin1Char( ',' ), QLatin1Char( '.' ) ).toDouble();
      return true;
    }

    QString kWartosc( const QString &s, const QString &t )
    {
      double v = 0;
      return czystaLiczba( t, &v ) ? kLiczba( s, v ) : kTekst( s, t );
    }

    // Grupa -> kolor tla (i tekstu), jak w arkuszu pracowni.
    struct KolorGrupy
    {
        const char *grupa;
        const char *styl;
        const char *tlo;
        const char *tekst;
    };
    const KolorGrupy kGrupy[] = {
      { "A", "Grupa_A", "#00e676", nullptr },
      { "A*", "Grupa_A_gw", "#c6ff00", nullptr },
      { "b/d/a", "Grupa_bda", "#c6ff00", nullptr },
      { "AC", "Grupa_AC", "#ffeb3b", nullptr },
      { "G", "Grupa_G", "#ff9900", nullptr },
      { "G*", "Grupa_G_gw", "#e91e63", nullptr },
      { "O", "Grupa_O", "#993366", "#fafafa" },
      { "Z", "Grupa_Z", "#808080", "#fff9c4" },
      { "M", "Grupa_M", "#333333", "#ffffff" },
      { "b/d", "Grupa_bd", "#0000ff", "#ffffff" },
      { "p/t", "Grupa_pt", "#0000ff", "#ffffff" },
    };

    const char *kKomorka = "<style:table-cell-properties fo:wrap-option=\"wrap\" fo:border=\"0.74pt solid #000000\" fo:padding=\"0.071cm\" style:vertical-align=\"middle\"/>"
                           "<style:paragraph-properties fo:text-align=\"center\"/>";
    const char *kBarlow = "<style:text-properties style:font-name=\"Barlow\" fo:font-size=\"12pt\" style:font-size-asian=\"12pt\" style:font-size-complex=\"12pt\"/>";
    const char *kBarlowBlack = "<style:text-properties style:font-name=\"Barlow Black\" fo:font-size=\"12pt\" fo:font-weight=\"bold\" style:font-size-asian=\"12pt\" style:font-weight-asian=\"bold\" style:font-size-complex=\"12pt\" style:font-weight-complex=\"bold\"/>";
    const char *kFonty = "<office:font-face-decls>"
                         "<style:font-face style:name=\"Barlow\" svg:font-family=\"Barlow\" style:font-family-generic=\"swiss\" style:font-pitch=\"variable\"/>"
                         "<style:font-face style:name=\"Barlow Black\" svg:font-family=\"&apos;Barlow Black&apos;\" style:font-family-generic=\"swiss\" style:font-pitch=\"variable\"/>"
                         "</office:font-face-decls>";
    const char *kPrzestrzenie = "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" "
                                "xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" "
                                "xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" "
                                "xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" "
                                "xmlns:number=\"urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0\" "
                                "xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" "
                                "xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\" "
                                "xmlns:of=\"urn:oasis:names:tc:opendocument:xmlns:of:1.2\" "
                                "xmlns:meta=\"urn:oasis:names:tc:opendocument:xmlns:meta:1.0\" "
                                "xmlns:config=\"urn:oasis:names:tc:opendocument:xmlns:config:1.0\" "
                                "office:version=\"1.3\"";

    //! styles.xml: styl Default i nazwane style grup (style:map wymaga
    //! stylow nazwanych, nie automatycznych).
    QByteArray stylesXml()
    {
      QString s = QStringLiteral( "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-styles %1>%2<office:styles>" ).arg( QLatin1String( kPrzestrzenie ), QLatin1String( kFonty ) );
      s += QStringLiteral( "<style:default-style style:family=\"table-cell\"><style:text-properties style:font-name=\"Barlow\" fo:font-size=\"12pt\" fo:language=\"pl\" fo:country=\"PL\"/></style:default-style>" );
      s += QStringLiteral( "<style:style style:name=\"Default\" style:family=\"table-cell\"/>" );
      for ( const KolorGrupy &g : kGrupy )
      {
        s += QStringLiteral( "<style:style style:name=\"%1\" style:family=\"table-cell\" style:parent-style-name=\"Default\">"
                             "<style:table-cell-properties fo:background-color=\"%2\" fo:wrap-option=\"no-wrap\" fo:border=\"0.74pt solid #000000\" fo:padding=\"0.071cm\" style:vertical-align=\"middle\"/>"
                             "<style:paragraph-properties fo:text-align=\"center\"/>" )
               .arg( QLatin1String( g.styl ), QLatin1String( g.tlo ) );
        QString tekst = QLatin1String( kBarlowBlack );
        if ( g.tekst )
          tekst.replace( QLatin1String( "<style:text-properties " ), QStringLiteral( "<style:text-properties fo:color=\"%1\" " ).arg( QLatin1String( g.tekst ) ) );
        s += tekst + QStringLiteral( "</style:style>" );
      }
      s += QStringLiteral( "</office:styles></office:document-styles>" );
      return s.toUtf8();
    }

    //! Styl komorki automatyczny (content.xml).
    QString stylKomorki( const QString &nazwa, const QString &komorka, const QString &akapit, const QString &tekst, const QString &format = QString(), const QString &mapy = QString() )
    {
      return QStringLiteral( "<style:style style:name=\"%1\" style:family=\"table-cell\" style:parent-style-name=\"Default\"%2>%3%4%5%6</style:style>" )
        .arg( nazwa, format.isEmpty() ? QString() : QStringLiteral( " style:data-style-name=\"%1\"" ).arg( format ), komorka, akapit, tekst, mapy );
    }

    //! settings.xml: zamrozony pierwszy wiersz w kazdym arkuszu.
    QByteArray settingsXml( const QStringList &arkusze )
    {
      QString s = QStringLiteral( "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-settings %1><office:settings>"
                                  "<config:config-item-set config:name=\"ooo:view-settings\"><config:config-item-map-indexed config:name=\"Views\"><config:config-item-map-entry>"
                                  "<config:config-item config:name=\"ViewId\" config:type=\"string\">view1</config:config-item>"
                                  "<config:config-item-map-named config:name=\"Tables\">" )
                    .arg( QLatin1String( kPrzestrzenie ) );
      for ( const QString &a : arkusze )
      {
        s += QStringLiteral( "<config:config-item-map-entry config:name=\"%1\">"
                             "<config:config-item config:name=\"CursorPositionX\" config:type=\"int\">0</config:config-item>"
                             "<config:config-item config:name=\"CursorPositionY\" config:type=\"int\">1</config:config-item>"
                             "<config:config-item config:name=\"HorizontalSplitMode\" config:type=\"short\">0</config:config-item>"
                             "<config:config-item config:name=\"VerticalSplitMode\" config:type=\"short\">2</config:config-item>"
                             "<config:config-item config:name=\"HorizontalSplitPosition\" config:type=\"int\">0</config:config-item>"
                             "<config:config-item config:name=\"VerticalSplitPosition\" config:type=\"int\">1</config:config-item>"
                             "<config:config-item config:name=\"ActiveSplitRange\" config:type=\"short\">2</config:config-item>"
                             "<config:config-item config:name=\"PositionLeft\" config:type=\"int\">0</config:config-item>"
                             "<config:config-item config:name=\"PositionRight\" config:type=\"int\">0</config:config-item>"
                             "<config:config-item config:name=\"PositionTop\" config:type=\"int\">0</config:config-item>"
                             "<config:config-item config:name=\"PositionBottom\" config:type=\"int\">1</config:config-item>"
                             "</config:config-item-map-entry>" )
               .arg( atrybut( a ) );
      }
      s += QStringLiteral( "</config:config-item-map-named>"
                           "<config:config-item config:name=\"ActiveTable\" config:type=\"string\">%1</config:config-item>"
                           "</config:config-item-map-entry></config:config-item-map-indexed></config:config-item-set></office:settings></office:document-settings>" )
             .arg( atrybut( arkusze.value( 0 ) ) );
      return s.toUtf8();
    }

    QString zapiszZip( const QString &sciezka, const QList<QPair<QByteArray, QByteArray>> &pliki )
    {
      void *zip = CPLCreateZip( sciezka.toUtf8().constData(), nullptr );
      if ( !zip )
        return QStringLiteral( "nie mozna utworzyc %1" ).arg( sciezka );
      QString blad;
      for ( int i = 0; i < pliki.size() && blad.isEmpty(); ++i )
      {
        // "mimetype" musi byc pierwszy i nieskompresowany (wymog ODF).
        char **opcje = i == 0 ? CSLSetNameValue( nullptr, "COMPRESSED", "NO" ) : nullptr;
        if ( CPLCreateFileInZip( zip, pliki.at( i ).first.constData(), opcje ) != CE_None )
          blad = QStringLiteral( "zip: %1" ).arg( QString::fromLatin1( pliki.at( i ).first ) );
        CSLDestroy( opcje );
        if ( !blad.isEmpty() )
          break;
        const QByteArray &b = pliki.at( i ).second;
        if ( CPLWriteFileInZip( zip, b.constData(), static_cast<int>( b.size() ) ) != CE_None )
          blad = QStringLiteral( "zip: zapis %1" ).arg( QString::fromLatin1( pliki.at( i ).first ) );
        CPLCloseFileInZip( zip );
      }
      if ( CPLCloseZip( zip ) != CE_None && blad.isEmpty() )
        blad = QStringLiteral( "zip: zamkniecie %1" ).arg( sciezka );
      return blad;
    }
  } // namespace

  QString zapiszOds( const QString &sciezka, const QVector<Wiersz> &wiersze )
  {
    // Frazy szukane w "Uwagach" - naglowki kolumn arkusza. W komorkach sa
    // formuly SZUKAJ (bez rozrozniania wielkosci liter, jak nasz C++), wiec
    // zmiana tekstu naglowka - np. w ostatniej kolumnie "TUTAJ WPISZ HASŁO" -
    // od razu przelicza cala kolumne.
    static const QStringList frazy = {
      QStringLiteral( "poza zakresem" ), QStringLiteral( "osłabione" ), QStringLiteral( "drzewo zaczyna zamiera" ),
      QStringLiteral( "wysokie potencjalne zagrożenie" ), QStringLiteral( "potencjalne zagrożenie" ),
      QStringLiteral( "potencjalne zagrożenie złamaniem konar" ), QStringLiteral( "potencjalne zagrożenie złamaniem posusz" ),
      QStringLiteral( "potencjalne zagrożenie rozłamaniem" ), QStringLiteral( "wskazane cięcia korekc" ),
      QStringLiteral( "wskazane cięcia sanit" ), QStringLiteral( "wskazane usunięcie" ), QStringLiteral( "wskazane założenie wiązań" ),
      QStringLiteral( "wskazane rozgęszczenie" ), QStringLiteral( "drzewostan lokalnie przegęszczony" ) };
    const QString haslo = QStringLiteral( "TUTAJ WPISZ HASŁO DO WYSZUKANIA" );
    const QString myslnik = QStringLiteral( "—" );

    // --- style ---------------------------------------------------------------
    const QString komorka = QLatin1String( kKomorka );
    const QString barlow = QLatin1String( kBarlow );
    const QString barlowBold = QString( barlow ).replace( QLatin1String( "fo:font-size=\"12pt\"" ), QLatin1String( "fo:font-size=\"12pt\" fo:font-weight=\"bold\" style:font-weight-asian=\"bold\" style:font-weight-complex=\"bold\"" ) );
    const QString srodek = QStringLiteral( "<style:paragraph-properties fo:text-align=\"center\"/>" );
    const QString bezRamki = QStringLiteral( "<style:table-cell-properties fo:wrap-option=\"wrap\" fo:padding=\"0.071cm\" style:vertical-align=\"middle\"/>" );
    const QString cienka = QString( komorka ).replace( QLatin1String( "0.74pt" ), QLatin1String( "0.06pt" ) );
    auto tlo = []( QString k, const char *kolor ) { return k.replace( QLatin1String( "<style:table-cell-properties " ), QStringLiteral( "<style:table-cell-properties fo:background-color=\"%1\" " ).arg( QLatin1String( kolor ) ) ); };

    QString mapyGrup;
    for ( const KolorGrupy &g : kGrupy )
      mapyGrup += QStringLiteral( "<style:map style:condition=\"cell-content()=&quot;%1&quot;\" style:apply-style-name=\"%2\" style:base-cell-address=\"&apos;Tabela inwentaryzacyjna&apos;.A2\"/>" )
                    .arg( QLatin1String( g.grupa ), QLatin1String( g.styl ) );

    QString automatyczne;
    const double szer[] = { 1.633, 1.737, 2.588, 4.879, 5.346, 3.295, 3.672, 2.251, 2.808, 2.489, 14.6, 4.431 }; // cm, z arkusza pracowni
    for ( int i = 0; i < 12; ++i )
      automatyczne += QStringLiteral( "<style:style style:name=\"co%1\" style:family=\"table-column\"><style:table-column-properties fo:break-before=\"auto\" style:column-width=\"%2cm\"/></style:style>" ).arg( i + 1 ).arg( szer[i] );
    for ( int i = 0; i < 4; ++i ) // zestawienia: 5 / 5 / 4 / 2,5 cm
      automatyczne += QStringLiteral( "<style:style style:name=\"cz%1\" style:family=\"table-column\"><style:table-column-properties fo:break-before=\"auto\" style:column-width=\"%2cm\"/></style:style>" ).arg( i + 1 ).arg( QList<double> { 6.0, 5.0, 4.5, 2.5 }.at( i ) );
    automatyczne += QStringLiteral( "<style:style style:name=\"ro1\" style:family=\"table-row\"><style:table-row-properties style:row-height=\"0.9cm\" fo:break-before=\"auto\" style:use-optimal-row-height=\"true\"/></style:style>" );
    automatyczne += QStringLiteral( "<style:style style:name=\"ta1\" style:family=\"table\" style:master-page-name=\"Default\"><style:table-properties table:display=\"true\" style:writing-mode=\"lr-tb\"/></style:style>" );
    automatyczne += QStringLiteral( "<number:number-style style:name=\"N1\"><number:number number:decimal-places=\"1\" number:min-decimal-places=\"1\" number:min-integer-digits=\"1\"/></number:number-style>" );
    automatyczne += QStringLiteral( "<number:number-style style:name=\"N2\"><number:number number:decimal-places=\"2\" number:min-decimal-places=\"2\" number:min-integer-digits=\"1\"/></number:number-style>" );
    automatyczne += stylKomorki( QStringLiteral( "nGrupa" ), tlo( komorka, "#c6ff00" ).replace( QLatin1String( "\"wrap\"" ), QLatin1String( "\"no-wrap\"" ) ), srodek, QLatin1String( kBarlowBlack ) );
    automatyczne += stylKomorki( QStringLiteral( "nag" ), cienka, srodek, barlowBold );
    automatyczne += stylKomorki( QStringLiteral( "nagFraza" ), cienka, srodek, barlow );
    automatyczne += stylKomorki( QStringLiteral( "nagHaslo" ), tlo( cienka, "#fff9c4" ), srodek, barlowBold );
    automatyczne += stylKomorki( QStringLiteral( "nagZest" ), tlo( komorka, "#e0e0e0" ), srodek, barlowBold );
    automatyczne += stylKomorki( QStringLiteral( "grupa" ), QString( komorka ).replace( QLatin1String( "\"wrap\"" ), QLatin1String( "\"no-wrap\"" ) ), srodek, QLatin1String( kBarlowBlack ), QString(), mapyGrup );
    automatyczne += stylKomorki( QStringLiteral( "dane" ), komorka, srodek, barlow );
    automatyczne += stylKomorki( QStringLiteral( "danePogr" ), komorka, srodek, barlowBold );
    automatyczne += stylKomorki( QStringLiteral( "wyl1" ), bezRamki, srodek, barlow, QStringLiteral( "N1" ) );
    automatyczne += stylKomorki( QStringLiteral( "wyl2" ), bezRamki, srodek, barlow, QStringLiteral( "N2" ) );
    automatyczne += stylKomorki( QStringLiteral( "fraza" ), bezRamki, srodek, barlow );

    // --- arkusz 1: tabela -------------------------------------------------------
    const QStringList naglowki = QStringList {
      QStringLiteral( "Grupa" ), QStringLiteral( "fid" ), QStringLiteral( "Kategoria" ), QStringLiteral( "Nazwa techniczna" ), QStringLiteral( "Nazwa polska" ),
      QStringLiteral( "Obwody pni [cm] na wys. 5cm lub powierzchnia krzewów [m2]" ), QStringLiteral( "Obwody pni [cm] na wys. 130cm lub faktyczna powierzchnia [m2]" ),
      QStringLiteral( "Szerokość korony [m]" ), QStringLiteral( "Wysokość [m]" ), QStringLiteral( "Stan zdrowotny [0-5]" ), QStringLiteral( "Uwagi" ),
      QStringLiteral( "obreb" ), QStringLiteral( "nr_dzialki" ), QStringLiteral( "teryt" ), QStringLiteral( "wkt_geom" ), QString(),
      QStringLiteral( "Obwód efektywny [cm]" ), QStringLiteral( "Średnica +1,5m" ), QStringLiteral( "Średnica pnia efektywna" ), QString() }
                                  + frazy + QStringList { haslo };
    const int nKol = static_cast<int>( naglowki.size() ); // 35: A..AI
    const int kFraz = 20;                                 // U

    QString tabela = QStringLiteral( "<table:table table:name=\"Tabela inwentaryzacyjna\" table:style-name=\"ta1\">" );
    const char *kolumny[] = { "co1", "co2", "co3", "co4", "co5", "co6", "co7", "co8", "co9", "co10", "co11", "co12", "co12", "co12", "co12", "co8" };
    for ( int i = 0; i < nKol; ++i )
    {
      const QString co = i < 16 ? QLatin1String( kolumny[i] ) : QStringLiteral( "co8" );
      // kolumna Grupa: styl z kolorami takze w pustych komorkach ponizej danych
      tabela += QStringLiteral( "<table:table-column table:style-name=\"%1\"%2/>" ).arg( co, i == 0 ? QStringLiteral( " table:default-cell-style-name=\"grupa\"" ) : QString() );
    }
    tabela += QStringLiteral( "<table:table-row table:style-name=\"ro1\">" );
    for ( int i = 0; i < nKol; ++i )
    {
      const QString s = i == 0 ? QStringLiteral( "nGrupa" ) : i == nKol - 1 ? QStringLiteral( "nagHaslo" ) : i >= kFraz ? QStringLiteral( "nagFraza" ) : naglowki.at( i ).isEmpty() ? QString() : QStringLiteral( "nag" );
      tabela += kTekst( s, naglowki.at( i ) );
    }
    tabela += QStringLiteral( "</table:table-row>" );

    QMap<QString, int> gatunki, stany;
    QMap<QString, QString> polskie, kategorie;
    int nr = 1;
    for ( const Wiersz &w : wiersze )
    {
      ++nr;
      const QString n = QString::number( nr );
      QString r = QStringLiteral( "<table:table-row table:style-name=\"ro1\">" );
      r += kTekst( QStringLiteral( "grupa" ), w.grupa.trimmed() );
      r += kLiczba( QStringLiteral( "dane" ), static_cast<double>( w.fid ) );
      r += kTekst( QStringLiteral( "dane" ), w.kategoria.trimmed() );
      r += kTekst( QStringLiteral( "dane" ), w.nazwaTechniczna.trimmed() );
      r += kTekst( QStringLiteral( "dane" ), w.nazwaPolska.trimmed() );
      r += kWartosc( QStringLiteral( "dane" ), w.obwody5.trimmed() );
      r += kWartosc( QStringLiteral( "dane" ), w.obwody130.trimmed() );
      r += kWartosc( QStringLiteral( "dane" ), w.korona.trimmed() );
      r += kWartosc( QStringLiteral( "dane" ), w.wysokosc.trimmed() );
      r += kWartosc( QStringLiteral( "dane" ), w.stan.trimmed() );
      r += kTekst( QStringLiteral( "dane" ), w.uwagi.trimmed() );
      r += kTekst( QStringLiteral( "dane" ), w.obreb.trimmed() );
      r += kTekst( QStringLiteral( "dane" ), w.dzialka.trimmed() );
      r += kTekst( QStringLiteral( "dane" ), w.teryt.trimmed() );
      r += kTekst( QStringLiteral( "dane" ), w.wkt.trimmed() );
      r += kPusta( QString() );

      // Q: obwod efektywny - wartosc z C++ (arkusz nie umie "sr35", m2 itd.)
      const double d = srednicaZObwodow( w.obwody130 );
      const double q = d > 0 ? std::round( d * 100.0 * M_PI * 100.0 ) / 100.0 : std::nan( "" );
      r += std::isnan( q ) ? kPusta( QStringLiteral( "wyl1" ) ) : kLiczba( QStringLiteral( "wyl1" ), q );
      // R: SOD = korona + 2 x 1,5 m; formula, gdy korona jest liczba w komorce
      double kor = 0;
      const bool korLiczba = czystaLiczba( w.korona.trimmed(), &kor );
      if ( korLiczba )
        r += kFormula( QStringLiteral( "wyl2" ), QStringLiteral( "of:=IF(ISNUMBER([.H%1]);IF([.H%1]>0;[.H%1]+3;\"\");\"\")" ).arg( n ), kor > 0 ? kor + 3.0 : std::nan( "" ) );
      else
      {
        kor = liczba( w.korona );
        r += kor > 0 ? kLiczba( QStringLiteral( "wyl2" ), kor + 3.0 ) : kPusta( QStringLiteral( "wyl2" ) );
      }
      // S: srednica pnia [cm] = Q / pi
      r += kFormula( QStringLiteral( "wyl1" ), QStringLiteral( "of:=IF(ISNUMBER([.Q%1]);[.Q%1]/PI();\"\")" ).arg( n ), std::isnan( q ) ? q : q / M_PI );
      r += kPusta( QString() );
      const QString uw = w.uwagi.toLower();
      for ( int k = 0; k <= frazy.size(); ++k )
      {
        const QString kol = litera( kFraz + k );
        const QString fr = k < frazy.size() ? frazy.at( k ) : haslo;
        const QString wynik = !uw.isEmpty() && uw.contains( fr.toLower() ) ? fr : myslnik;
        r += kFormulaTekst( QStringLiteral( "fraza" ), QStringLiteral( "of:=IF(ISERROR(SEARCH([.%1$1];[.$K%2]));\"—\";[.%1$1])" ).arg( kol, n ), wynik );
      }
      r += QStringLiteral( "</table:table-row>" );
      tabela += r;

      const QString gat = w.nazwaTechniczna.trimmed();
      gatunki[gat] += 1;
      if ( !w.nazwaPolska.trimmed().isEmpty() )
        polskie[gat] = w.nazwaPolska.trimmed();
      if ( !w.kategoria.trimmed().isEmpty() && !kategorie.contains( gat ) )
        kategorie[gat] = w.kategoria.trimmed();
      stany[w.stan.trimmed()] += 1;
    }
    tabela += QStringLiteral( "</table:table>" );

    // --- arkusz 2 i 3: zestawienia z suma ---------------------------------------
    auto zestawienie = [&]( const QString &nazwa, const QStringList &nag, const QList<QStringList> &wiersze2 ) {
      QString t = QStringLiteral( "<table:table table:name=\"%1\" table:style-name=\"ta1\">" ).arg( atrybut( nazwa ) );
      for ( int i = 0; i < nag.size(); ++i )
        t += QStringLiteral( "<table:table-column table:style-name=\"cz%1\"/>" ).arg( nag.size() == 2 && i == 0 ? 3 : nag.size() == 2 ? 4 : i + 1 );
      t += QStringLiteral( "<table:table-row table:style-name=\"ro1\">" );
      for ( const QString &h : nag )
        t += kTekst( QStringLiteral( "nagZest" ), h );
      t += QStringLiteral( "</table:table-row>" );
      for ( const QStringList &w : wiersze2 )
      {
        t += QStringLiteral( "<table:table-row table:style-name=\"ro1\">" );
        for ( int i = 0; i < w.size(); ++i )
          t += i == w.size() - 1 ? kLiczba( QStringLiteral( "dane" ), w.at( i ).toDouble() ) : kWartosc( QStringLiteral( "dane" ), w.at( i ) );
        t += QStringLiteral( "</table:table-row>" );
      }
      // wiersz "Razem"
      const QString ost = litera( static_cast<int>( nag.size() ) - 1 );
      double suma = 0;
      for ( const QStringList &w : wiersze2 )
        suma += w.last().toDouble();
      t += QStringLiteral( "<table:table-row table:style-name=\"ro1\">" );
      t += kTekst( QStringLiteral( "nagZest" ), QStringLiteral( "Razem" ) );
      for ( int i = 1; i < nag.size() - 1; ++i )
        t += kPusta( QStringLiteral( "nagZest" ) );
      t += wiersze2.isEmpty() ? kLiczba( QStringLiteral( "nagZest" ), 0 )
                              : kFormula( QStringLiteral( "nagZest" ), QStringLiteral( "of:=SUM([.%1%2:.%1%3])" ).arg( ost ).arg( 2 ).arg( wiersze2.size() + 1 ), suma );
      t += QStringLiteral( "</table:table-row></table:table>" );
      return t;
    };
    QList<QStringList> wg;
    for ( auto it = gatunki.constBegin(); it != gatunki.constEnd(); ++it )
      wg << QStringList { it.key(), polskie.value( it.key() ), kategorie.value( it.key() ), QString::number( it.value() ) };
    QList<QStringList> ws;
    for ( auto it = stany.constBegin(); it != stany.constEnd(); ++it )
      ws << QStringList { it.key(), QString::number( it.value() ) };
    const QString arkusz2 = QStringLiteral( "Zestawienie gatunków" ), arkusz3 = QStringLiteral( "Zestawienie stanu" );
    const QString zg = zestawienie( arkusz2, { QStringLiteral( "Nazwa techniczna" ), QStringLiteral( "Nazwa polska" ), QStringLiteral( "Kategoria" ), QStringLiteral( "Liczba" ) }, wg );
    const QString zs = zestawienie( arkusz3, { QStringLiteral( "Stan zdrowotny [0-5]" ), QStringLiteral( "Liczba" ) }, ws );

    // --- zlozenie -----------------------------------------------------------------
    QString content = QStringLiteral( "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-content %1><office:scripts/>%2<office:automatic-styles>%3</office:automatic-styles>"
                                      "<office:body><office:spreadsheet>"
                                      "<table:calculation-settings table:automatic-find-labels=\"false\" table:use-regular-expressions=\"false\" table:use-wildcards=\"false\"/>" )
                        .arg( QLatin1String( kPrzestrzenie ), QLatin1String( kFonty ), automatyczne );
    content += tabela + zg + zs;
    content += QStringLiteral( "<table:database-ranges><table:database-range table:name=\"__Anonymous_Sheet_DB__0\" table:target-range-address=\"&apos;Tabela inwentaryzacyjna&apos;.A1:&apos;Tabela inwentaryzacyjna&apos;.%1%2\" table:display-filter-buttons=\"true\"/></table:database-ranges>" )
                 .arg( litera( nKol - 1 ) )
                 .arg( wiersze.size() + 1 );
    content += QStringLiteral( "</office:spreadsheet></office:body></office:document-content>" );

    const QByteArray manifest = QByteArrayLiteral( "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                                                   "<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.3\">"
                                                   "<manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.3\" manifest:media-type=\"application/vnd.oasis.opendocument.spreadsheet\"/>"
                                                   "<manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/>"
                                                   "<manifest:file-entry manifest:full-path=\"styles.xml\" manifest:media-type=\"text/xml\"/>"
                                                   "<manifest:file-entry manifest:full-path=\"meta.xml\" manifest:media-type=\"text/xml\"/>"
                                                   "<manifest:file-entry manifest:full-path=\"settings.xml\" manifest:media-type=\"text/xml\"/>"
                                                   "</manifest:manifest>" );
    const QByteArray meta = QStringLiteral( "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-meta %1><office:meta><meta:generator>WorkField</meta:generator></office:meta></office:document-meta>" )
                              .arg( QLatin1String( kPrzestrzenie ) )
                              .toUtf8();

    QFile::remove( sciezka );
    return zapiszZip( sciezka, {
                                 { QByteArrayLiteral( "mimetype" ), QByteArrayLiteral( "application/vnd.oasis.opendocument.spreadsheet" ) },
                                 { QByteArrayLiteral( "content.xml" ), content.toUtf8() },
                                 { QByteArrayLiteral( "styles.xml" ), stylesXml() },
                                 { QByteArrayLiteral( "meta.xml" ), meta },
                                 { QByteArrayLiteral( "settings.xml" ), settingsXml( { QStringLiteral( "Tabela inwentaryzacyjna" ), arkusz2, arkusz3 } ) },
                                 { QByteArrayLiteral( "META-INF/manifest.xml" ), manifest },
                               } );
  }
} // namespace DxfInwentaryzacja
