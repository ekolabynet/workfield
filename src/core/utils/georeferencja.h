/***************************************************************************
  georeferencja.h - WorkField

  Szybkie georeferencjonowanie rastra z punktow dopasowania: zdjecia mapy
  albo planu zrobionego w terenie, skanu, pobranego pliku bez georeferencji.

  METODY. Siedem, tak jak w Georeferencerze QGIS-a - bo to jest jezyk,
  ktorym geodeta juz mowi. Kazda ma swoje minimum punktow i swoje miejsce:

    liniowa      2   przesuniecie i skala, osobno w X i Y. Skan lezacy
                     prosto. Nie obraca.
    helmerta     2   przesuniecie, jedna skala i OBROT. Skan lezacy krzywo.
                     Nie zmienia proporcji, wiec nie ukrywa bledow.
    afiniczna    3   szesc parametrow: obrot, dwie skale, skosowanie.
                     To samo, co "-order 1" w GDAL-u.
    rzutowa      4   PERSPEKTYWA. Zdjecie plaskiej mapy zrobione pod katem.
                     To jest wlasciwa metoda do zdjecia z reki.
    wielomian 2  6   wyginanie globalne. Mapa z dystorsja ukladowa.
    wielomian 3 10   mocniejsze wyginanie. Poza punktami potrafi oszalec.
    miejscowa    3   TPS: przechodzi przez KAZDY punkt i wygina lokalnie.
                     Do map rysowanych "na oko".

  CZTERY ROGI WYSTARCZA - ale tylko metodzie RZUTOWEJ. Wczesniej ten plik
  twierdzil, ze nie wystarcza; to byla prawda o wielomianach, a nie
  o zdjeciu. Zmierzone na zdjeciu mapy 800x600 m zrobionym pod katem
  (piaskownica 21.09, odchylka na punktach KONTROLNYCH, ktorych
  dopasowanie nie widzialo) - patrz tabela w instalatorze.

  GDAL NIE MA przeksztalcenia rzutowego ani helmertowskiego (3.8: tylko
  wielomiany 1-3 i TPS). Liczymy je wiec same, najmniejszymi kwadratami
  na wspolrzednych PRZESUNIETYCH DO SRODKA CIEZKOSCI I PRZESKALOWANYCH -
  bez tego uklad rownan dla homografii przy wspolrzednych rzedu 7,5 mln
  jest zle uwarunkowany i rozwiazanie ucieka.

  MIARA JAKOSCI. Dwie liczby, nie jedna:

    odchylka na dopasowaniu - jak w QGIS-ie: ile brakuje w punktach,
      ktore samo dopasowanie widzialo. Przy MINIMALNEJ liczbie punktow
      jest ZEROWA Z DEFINICJI i nie znaczy nic.

    sprawdzian krzyzowy - kazdy punkt po kolei wyjmowany z dopasowania
      i mierzony tym, co zostalo (leave-one-out). To jest jedyna liczba,
      ktora mowi, ile wynik jest wart - i to ona ma decydowac.

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef GEOREFERENCJA_H
#define GEOREFERENCJA_H

#include <QDir>
#include <QFileInfo>
#include <QList>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

#include <QDebug>

#include <algorithm>
#include <cmath>

#include <cpl_conv.h>
#include <cpl_string.h>
#include <gdal.h>
#include <gdal_alg.h>
#include <gdal_utils.h>
#include <gdalwarper.h>
#include <ogr_srs_api.h>

namespace Georeferencja
{
  /**
   * Wymiary obrazu w pikselach PLIKU: {szerokosc, wysokosc} albo {blad}.
   *
   * Podglad w QML nie moze ich podac. Zdjecie z telefonu ma dzis bok
   * ponad 4000 px, a tekstura o takim boku przekracza GL_MAX_TEXTURE_SIZE
   * wielu Androidow - obraz nie rysuje sie WCALE i okno wyglada na
   * zawieszone. Podglad trzeba wiec dekodowac mniejszy, a wtedy
   * `Image.sourceSize` pokazuje rozmiar PODGLADU, nie pliku.
   *
   * Piksel dopasowania musi byc pikselem PLIKU, bo taki GCP bierze GDAL.
   * Wymiary podaje wiec ten, kto i tak otwiera plik.
   */
  inline QVariantMap wymiary( const QString &obraz )
  {
    QVariantMap wynik;
    GDALAllRegister();
    GDALDatasetH zbior = GDALOpen( obraz.toUtf8().constData(), GA_ReadOnly );
    if ( !zbior )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się otworzyć obrazu: %1" ).arg( QFileInfo( obraz ).fileName() ) );
      return wynik;
    }
    wynik.insert( QStringLiteral( "szerokosc" ), GDALGetRasterXSize( zbior ) );
    wynik.insert( QStringLiteral( "wysokosc" ), GDALGetRasterYSize( zbior ) );
    GDALClose( zbior );
    return wynik;
  }

  //! Ile punktow potrzebuje metoda, zeby rachunek mial rozwiazanie.
  inline int minimum( const QString &metoda )
  {
    if ( metoda == QLatin1String( "liniowa" ) || metoda == QLatin1String( "helmerta" ) )
      return 2;
    if ( metoda == QLatin1String( "afiniczna" ) || metoda == QLatin1String( "miejscowa" ) )
      return 3;
    if ( metoda == QLatin1String( "rzutowa" ) )
      return 4;
    if ( metoda == QLatin1String( "wielomian2" ) )
      return 6;
    if ( metoda == QLatin1String( "wielomian3" ) )
      return 10;
    return 4;
  }

  /**
   * Spis metod dla okna: {klucz, nazwa, minimum, opis}.
   *
   * Kolejnosc od najprostszej do najbardziej gietkiej - bo tak sie
   * wybiera: bierze sie NAJPROSTSZA, ktora wystarcza. Kazda nastepna
   * ma wiecej swobody, czyli wiecej sposobow na ukrycie zlego punktu.
   */
  inline QVariantList metody()
  {
    QVariantList lista;
    auto dodaj = []( QVariantList &l, const char *klucz, const char *nazwa, int min, const char *opis ) {
      QVariantMap m;
      m.insert( QStringLiteral( "klucz" ), QString::fromUtf8( klucz ) );
      m.insert( QStringLiteral( "nazwa" ), QString::fromUtf8( nazwa ) );
      m.insert( QStringLiteral( "minimum" ), min );
      m.insert( QStringLiteral( "opis" ), QString::fromUtf8( opis ) );
      l << m;
    };
    dodaj( lista, "liniowa", "Liniowa (przesunięcie i skala)", 2,
           "Skan leżący prosto. Nie obraca obrazu." );
    dodaj( lista, "helmerta", "Helmerta (podobieństwo)", 2,
           "Skan leżący krzywo. Obraca i skaluje, nie zmienia proporcji — więc nie ukryje złego punktu." );
    dodaj( lista, "afiniczna", "Afiniczna (wielomian 1)", 3,
           "Obrót, dwie skale i skosowanie. Dobra do planu, słaba do zdjęcia pod kątem." );
    dodaj( lista, "rzutowa", "Rzutowa (perspektywa)", 4,
           "Zdjęcie płaskiej mapy zrobione pod kątem. Cztery rogi wystarczą. To jest właściwy wybór dla zdjęcia z ręki." );
    dodaj( lista, "wielomian2", "Wielomian 2. stopnia", 6,
           "Wygina obraz globalnie. Do map z dystorsją układową." );
    dodaj( lista, "wielomian3", "Wielomian 3. stopnia", 10,
           "Mocniejsze wyginanie. Poza obszarem punktów potrafi oszaleć." );
    dodaj( lista, "miejscowa", "Miejscowa (TPS)", 3,
           "Przechodzi przez każdy punkt i wygina obraz lokalnie. Do map rysowanych „na oko”." );
    return lista;
  }

  /**
   * Punkty dopasowania z QML: lista map {px, py, x, y} - piksel obrazu
   * i odpowiadajacy mu punkt na mapie.
   */
  inline QList<GDAL_GCP> zListy( const QVariantList &punkty )
  {
    QList<GDAL_GCP> gcp;
    for ( const QVariant &v : punkty )
    {
      const QVariantMap m = v.toMap();
      GDAL_GCP g;
      GDALInitGCPs( 1, &g );
      g.dfGCPPixel = m.value( QStringLiteral( "px" ) ).toDouble();
      g.dfGCPLine = m.value( QStringLiteral( "py" ) ).toDouble();
      g.dfGCPX = m.value( QStringLiteral( "x" ) ).toDouble();
      g.dfGCPY = m.value( QStringLiteral( "y" ) ).toDouble();
      g.dfGCPZ = 0;
      gcp << g;
    }
    return gcp;
  }

  // =================================================================
  //  WLASNY RACHUNEK: liniowa, Helmerta, afiniczna, rzutowa
  // =================================================================

  //! Uklad rownan normalnych A^T A x = A^T b, eliminacja z wyborem elementu.
  inline bool rozwiaz( QVector<double> &m, QVector<double> &b, int n )
  {
    for ( int k = 0; k < n; k++ )
    {
      int naj = k;
      for ( int i = k + 1; i < n; i++ )
        if ( std::abs( m[i * n + k] ) > std::abs( m[naj * n + k] ) )
          naj = i;
      if ( std::abs( m[naj * n + k] ) < 1e-12 )
        return false;
      if ( naj != k )
      {
        for ( int j = 0; j < n; j++ )
          std::swap( m[k * n + j], m[naj * n + j] );
        std::swap( b[k], b[naj] );
      }
      for ( int i = k + 1; i < n; i++ )
      {
        const double w = m[i * n + k] / m[k * n + k];
        if ( w == 0 )
          continue;
        for ( int j = k; j < n; j++ )
          m[i * n + j] -= w * m[k * n + j];
        b[i] -= w * b[k];
      }
    }
    for ( int i = n - 1; i >= 0; i-- )
    {
      double s = b[i];
      for ( int j = i + 1; j < n; j++ )
        s -= m[i * n + j] * b[j];
      b[i] = s / m[i * n + i];
    }
    return true;
  }

  //! Najmniejsze kwadraty: wiersze A (n kolumn) i prawa strona -> x.
  inline bool nmk( const QVector<double> &A, const QVector<double> &y, int n, QVector<double> &x )
  {
    const int wierszy = y.size();
    QVector<double> m( n * n, 0.0 ), b( n, 0.0 );
    for ( int r = 0; r < wierszy; r++ )
      for ( int i = 0; i < n; i++ )
      {
        b[i] += A[r * n + i] * y[r];
        for ( int j = 0; j < n; j++ )
          m[i * n + j] += A[r * n + i] * A[r * n + j];
      }
    if ( !rozwiaz( m, b, n ) )
      return false;
    x = b;
    return true;
  }

  /**
   * Normalizacja: srodek ciezkosci do zera i sredni promien do 1.
   *
   * Bez tego homografia liczona na wspolrzednych rzedu 7,5 mln ma uklad
   * rownan z elementami rzedu 10^14 obok jedynek - i rozwiazanie ucieka
   * w szum. To jest klasyczna normalizacja Hartleya i jest obowiazkowa,
   * a nie kosmetyczna.
   */
  struct Skala
  {
    double sx = 0, sy = 0, s = 1;

    void policz( const QVector<double> &x, const QVector<double> &y )
    {
      const int n = x.size();
      if ( n == 0 )
        return;
      sx = sy = 0;
      for ( int i = 0; i < n; i++ )
      {
        sx += x[i];
        sy += y[i];
      }
      sx /= n;
      sy /= n;
      double r = 0;
      for ( int i = 0; i < n; i++ )
        r += std::hypot( x[i] - sx, y[i] - sy );
      r /= n;
      s = r > 1e-9 ? 1.0 / r : 1.0;
    }
    double wX( double v ) const { return ( v - sx ) * s; }
    double wY( double v ) const { return ( v - sy ) * s; }
    double zX( double v ) const { return v / s + sx; }
    double zY( double v ) const { return v / s + sy; }
  };

  //! Model wlasny: wspolczynniki plus obie normalizacje.
  struct Wlasny
  {
    QString metoda;
    QVector<double> w;
    Skala p, m;
    bool dobry = false;

    //! Rozmiar obrazu zrodlowego - GRANICA ZAUFANIA dla przeksztalcenia
    //! odwrotnego. 0 = nieznany (ocena i sprawdzian go nie potrzebuja).
    double szerObrazu = 0;
    double wysObrazu = 0;
  };

  //! Wspolczynnik nieskonczony albo NaN = modelu nie ma, choc uklad
  //! rownan "sie rozwiazal". Lepiej powiedziec to tutaj niz puscic
  //! takie liczby do GDAL-a.
  inline bool policzalne( const QVector<double> &w )
  {
    for ( double v : w )
      if ( !std::isfinite( v ) )
        return false;
    return true;
  }

  inline Wlasny dopasujWlasny( const QString &metoda, const QList<GDAL_GCP> &gcp )
  {
    Wlasny model;
    model.metoda = metoda;
    const int n = gcp.size();
    QVector<double> px( n ), py( n ), mx( n ), my( n );
    for ( int i = 0; i < n; i++ )
    {
      px[i] = gcp[i].dfGCPPixel;
      py[i] = gcp[i].dfGCPLine;
      mx[i] = gcp[i].dfGCPX;
      my[i] = gcp[i].dfGCPY;
    }
    model.p.policz( px, py );
    model.m.policz( mx, my );

    QVector<double> u( n ), v( n ), X( n ), Y( n );
    for ( int i = 0; i < n; i++ )
    {
      u[i] = model.p.wX( px[i] );
      v[i] = model.p.wY( py[i] );
      X[i] = model.m.wX( mx[i] );
      Y[i] = model.m.wY( my[i] );
    }

    if ( metoda == QLatin1String( "liniowa" ) )
    {
      // x = a0 + a1*u ; y = b0 + b1*v. Osobno w kazdej osi, bez obrotu.
      QVector<double> A( 2 * n ), wx, wy;
      for ( int i = 0; i < n; i++ )
      {
        A[i * 2] = 1;
        A[i * 2 + 1] = u[i];
      }
      if ( !nmk( A, X, 2, wx ) )
        return model;
      for ( int i = 0; i < n; i++ )
        A[i * 2 + 1] = v[i];
      if ( !nmk( A, Y, 2, wy ) )
        return model;
      model.w = QVector<double> { wx[0], wx[1], wy[0], wy[1] };
      model.dobry = policzalne( model.w );
      return model;
    }

    if ( metoda == QLatin1String( "helmerta" ) )
    {
      // x = a + c*u - d*w ; y = b + d*u + c*w, gdzie w = -v.
      // Odwrocenie osi pionowej jest tu konieczne: wiersz obrazu rosnie
      // w dol, a wspolrzedna mapy w gore - bez tego "podobienstwo"
      // musialoby miec odbicie, ktorego cztery parametry nie maja.
      QVector<double> A( 4 * 2 * n ), y( 2 * n ), x;
      for ( int i = 0; i < n; i++ )
      {
        const double uu = u[i], ww = -v[i];
        double *r1 = A.data() + ( 2 * i ) * 4;
        r1[0] = 1;
        r1[1] = 0;
        r1[2] = uu;
        r1[3] = -ww;
        y[2 * i] = X[i];
        double *r2 = A.data() + ( 2 * i + 1 ) * 4;
        r2[0] = 0;
        r2[1] = 1;
        r2[2] = ww;
        r2[3] = uu;
        y[2 * i + 1] = Y[i];
      }
      if ( !nmk( A, y, 4, x ) )
        return model;
      model.w = x;
      model.dobry = policzalne( model.w );
      return model;
    }

    if ( metoda == QLatin1String( "afiniczna" ) )
    {
      QVector<double> A( 3 * n ), wx, wy;
      for ( int i = 0; i < n; i++ )
      {
        A[i * 3] = 1;
        A[i * 3 + 1] = u[i];
        A[i * 3 + 2] = v[i];
      }
      if ( !nmk( A, X, 3, wx ) || !nmk( A, Y, 3, wy ) )
        return model;
      model.w = QVector<double> { wx[0], wx[1], wx[2], wy[0], wy[1], wy[2] };
      model.dobry = policzalne( model.w );
      return model;
    }

    if ( metoda == QLatin1String( "rzutowa" ) )
    {
      // Homografia, 8 niewiadomych, po dwa rownania na punkt:
      //   h0 u + h1 v + h2 - h6 u X - h7 v X = X
      //   h3 u + h4 v + h5 - h6 u Y - h7 v Y = Y
      QVector<double> A( 8 * 2 * n, 0.0 ), y( 2 * n ), x;
      for ( int i = 0; i < n; i++ )
      {
        double *r1 = A.data() + ( 2 * i ) * 8;
        r1[0] = u[i];
        r1[1] = v[i];
        r1[2] = 1;
        r1[6] = -u[i] * X[i];
        r1[7] = -v[i] * X[i];
        y[2 * i] = X[i];
        double *r2 = A.data() + ( 2 * i + 1 ) * 8;
        r2[3] = u[i];
        r2[4] = v[i];
        r2[5] = 1;
        r2[6] = -u[i] * Y[i];
        r2[7] = -v[i] * Y[i];
        y[2 * i + 1] = Y[i];
      }
      if ( !nmk( A, y, 8, x ) )
        return model;
      model.w = x;
      model.dobry = policzalne( model.w );
      return model;
    }

    return model;
  }

  //! Piksel -> mapa wedlug modelu wlasnego.
  inline bool policzWlasny( const Wlasny &model, double px, double py, double &x, double &y )
  {
    if ( !model.dobry )
      return false;
    const double u = model.p.wX( px );
    const double v = model.p.wY( py );
    double X = 0, Y = 0;
    const QVector<double> &w = model.w;
    if ( model.metoda == QLatin1String( "liniowa" ) )
    {
      X = w[0] + w[1] * u;
      Y = w[2] + w[3] * v;
    }
    else if ( model.metoda == QLatin1String( "helmerta" ) )
    {
      const double ww = -v;
      X = w[0] + w[2] * u - w[3] * ww;
      Y = w[1] + w[3] * u + w[2] * ww;
    }
    else if ( model.metoda == QLatin1String( "afiniczna" ) )
    {
      X = w[0] + w[1] * u + w[2] * v;
      Y = w[3] + w[4] * u + w[5] * v;
    }
    else if ( model.metoda == QLatin1String( "rzutowa" ) )
    {
      const double mianownik = w[6] * u + w[7] * v + 1.0;
      if ( std::abs( mianownik ) < 1e-12 )
        return false;
      X = ( w[0] * u + w[1] * v + w[2] ) / mianownik;
      Y = ( w[3] * u + w[4] * v + w[5] ) / mianownik;
    }
    else
      return false;
    if ( !std::isfinite( X ) || !std::isfinite( Y ) )
      return false;
    // Model wolno pytac tylko o okolice tego, z czego powstal. Sto
    // sredniich promieni rozrzutu punktow to juz bardzo daleko; dalej
    // nie ma modelu, jest ekstrapolacja przez linie znikania.
    if ( std::hypot( X, Y ) > 100.0 )
      return false;
    x = model.m.zX( X );
    y = model.m.zY( Y );
    return std::isfinite( x ) && std::isfinite( y );
  }

  //! Mapa -> piksel. Przeliczenie obrazu pyta WLASNIE O TO: dla kazdego
  //! piksela wyniku, skad go wziac w zrodle.
  inline bool policzWlasnyOdwrotnie( const Wlasny &model, double x, double y, double &px, double &py )
  {
    if ( !model.dobry )
      return false;
    const double X = model.m.wX( x );
    const double Y = model.m.wY( y );
    const QVector<double> &w = model.w;
    double u = 0, v = 0;
    if ( model.metoda == QLatin1String( "liniowa" ) )
    {
      if ( std::abs( w[1] ) < 1e-12 || std::abs( w[3] ) < 1e-12 )
        return false;
      u = ( X - w[0] ) / w[1];
      v = ( Y - w[2] ) / w[3];
    }
    else if ( model.metoda == QLatin1String( "helmerta" ) )
    {
      const double det = w[2] * w[2] + w[3] * w[3];
      if ( det < 1e-18 )
        return false;
      const double dx = X - w[0], dy = Y - w[1];
      u = ( w[2] * dx + w[3] * dy ) / det;
      v = -( -w[3] * dx + w[2] * dy ) / det;
    }
    else if ( model.metoda == QLatin1String( "afiniczna" ) )
    {
      const double det = w[1] * w[5] - w[2] * w[4];
      if ( std::abs( det ) < 1e-18 )
        return false;
      const double dx = X - w[0], dy = Y - w[3];
      u = ( w[5] * dx - w[2] * dy ) / det;
      v = ( -w[4] * dx + w[1] * dy ) / det;
    }
    else if ( model.metoda == QLatin1String( "rzutowa" ) )
    {
      // Odwrotnosc homografii to dopelnienie algebraiczne macierzy 3x3.
      const double h[9] = { w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7], 1.0 };
      const double a0 = h[4] * h[8] - h[5] * h[7];
      const double a1 = h[2] * h[7] - h[1] * h[8];
      const double a2 = h[1] * h[5] - h[2] * h[4];
      const double a3 = h[5] * h[6] - h[3] * h[8];
      const double a4 = h[0] * h[8] - h[2] * h[6];
      const double a5 = h[2] * h[3] - h[0] * h[5];
      const double a6 = h[3] * h[7] - h[4] * h[6];
      const double a7 = h[1] * h[6] - h[0] * h[7];
      const double a8 = h[0] * h[4] - h[1] * h[3];
      const double mianownik = a6 * X + a7 * Y + a8;
      if ( std::abs( mianownik ) < 1e-15 )
        return false;
      u = ( a0 * X + a1 * Y + a2 ) / mianownik;
      v = ( a3 * X + a4 * Y + a5 ) / mianownik;
    }
    else
      return false;
    if ( !std::isfinite( u ) || !std::isfinite( v ) )
      return false;
    px = model.p.zX( u );
    py = model.p.zY( v );
    if ( !std::isfinite( px ) || !std::isfinite( py ) )
      return false;

    // GRANICA ZAUFANIA. Przy perspektywie punkty wyniku lezace za linia
    // znikania odwzorowuja sie na piksele zrodla oddalone o miliony -
    // zmierzone: 2,9 mln piksela dla obrazu szerokiego na 4032 (21.09).
    // Im blizej tej linii, tym wieksze, az do 1e15. GDAL rzutuje to na
    // `int`, a rzutowanie takiej liczby jest niezdefiniowane: wychodzi
    // dziki indeks i SIGSEGV pod adresem w rodzaju 0x800000000.
    //
    // Taki punkt NIE MA odpowiednika w zrodle i tak ma byc zglaszany.
    // GDAL zrobi z niego przezroczystosc, czyli dokladnie to, czym on
    // jest: miejscem, ktorego na zdjeciu nie widac.
    if ( model.szerObrazu > 0 )
    {
      if ( px < -model.szerObrazu || px > 2 * model.szerObrazu
           || py < -model.wysObrazu || py > 2 * model.wysObrazu )
        return false;
    }
    else if ( std::hypot( u, v ) > 100.0 )
    {
      return false;
    }
    return true;
  }

  /**
   * Nasz model podany GDAL-owi jako JEGO WLASNY transformer.
   *
   * GDALWarpOptions ma pole `pfnTransformer` wlasnie po to. Dzieki temu
   * przeliczenie obrazu uzywa DOKLADNIE tego samego rachunku, co odchylki
   * w oknie - a nie przyblizenia siatka punktow. Zmierzone, dlaczego
   * przyblizenie odpadlo: siatka 7x7 + TPS mijala sie z homografia
   * srednio o 1,00 m, siatka 21x21 + wielomian 3. stopnia o 0,40 m -
   * przy metodzie, ktora sama w sobie trafia w 0,00 m.
   */
  inline int transformerWlasny( void *arg, int bDstToSrc, int n, double *x, double *y, double *z, int *ok )
  {
    Q_UNUSED( z )
    const Wlasny *model = static_cast<const Wlasny *>( arg );
    int wszystkie = TRUE;
    for ( int i = 0; i < n; i++ )
    {
      double a = 0, b = 0;
      const bool dobrze = bDstToSrc ? policzWlasnyOdwrotnie( *model, x[i], y[i], a, b )
                                    : policzWlasny( *model, x[i], y[i], a, b );
      ok[i] = dobrze ? TRUE : FALSE;
      if ( dobrze )
      {
        x[i] = a;
        y[i] = b;
      }
      else
        wszystkie = FALSE;
    }
    Q_UNUSED( wszystkie )
    return TRUE;
  }

  /**
   * Ten sam model, ale w ukladzie, ktorego zada GDALWarpOperation:
   * PIKSEL WYNIKU <-> piksel zrodla. Roznica wobec `transformerWlasny`
   * jest jedna - po drodze siedzi geotransformacja obrazu wyjsciowego.
   */
  struct MostekWarp
  {
    const Wlasny *model = nullptr;
    double gt[6] = { 0 };
    double odwrotna[6] = { 0 };
  };

  inline int transformerWarp( void *arg, int bDstToSrc, int n, double *x, double *y, double *z, int *ok )
  {
    Q_UNUSED( z )
    const MostekWarp *m = static_cast<const MostekWarp *>( arg );
    for ( int i = 0; i < n; i++ )
    {
      double a = 0, b = 0;
      bool dobrze = false;
      if ( bDstToSrc )
      {
        double gx = 0, gy = 0;
        GDALApplyGeoTransform( const_cast<double *>( m->gt ), x[i], y[i], &gx, &gy );
        dobrze = policzWlasnyOdwrotnie( *m->model, gx, gy, a, b );
      }
      else
      {
        double gx = 0, gy = 0;
        dobrze = policzWlasny( *m->model, x[i], y[i], gx, gy );
        if ( dobrze )
          GDALApplyGeoTransform( const_cast<double *>( m->odwrotna ), gx, gy, &a, &b );
      }
      ok[i] = dobrze ? TRUE : FALSE;
      if ( dobrze )
      {
        x[i] = a;
        y[i] = b;
      }
    }
    return TRUE;
  }

  /**
   * Piramida podgladow w gotowym pliku.
   *
   * Bez niej przesuwanie mapy nad podkladem 15 Mpx dekoduje za kazdym
   * odrysowaniem wielki kawalek pliku - na telefonie to jest roznica
   * miedzy podkladem a zwieszona aplikacja. Kosztuje ulamek sekundy raz.
   */
  inline void piramida( const QString &plik )
  {
    GDALDatasetH ds = GDALOpen( plik.toUtf8().constData(), GA_Update );
    if ( !ds )
      return;
    const int bok = std::max( GDALGetRasterXSize( ds ), GDALGetRasterYSize( ds ) );
    QVector<int> poziomy;
    for ( int p = 2; bok / p > 256 && poziomy.size() < 8; p *= 2 )
      poziomy << p;
    if ( !poziomy.isEmpty() )
      GDALBuildOverviews( ds, "AVERAGE", poziomy.size(), poziomy.data(), 0, nullptr, GDALDummyProgress, nullptr );
    GDALClose( ds );
  }

  /**
   * Przeliczenie obrazu NASZYM modelem, bez posrednictwa punktow.
   *
   * Zwraca pusty napis albo tresc bledu. Wypelnia szerokosc/wysokosc/piksel.
   */
  inline QString przeliczWlasnym( GDALDatasetH obraz, const Wlasny &model, const QString &uklad,
                                  const QString &wyjscie, int &szerokosc, int &wysokosc, double &piksel )
  {
    MostekWarp mostek;
    mostek.model = &model;
    int szerW = 0, wysW = 0;
    if ( GDALSuggestedWarpOutput( obraz, transformerWlasny, const_cast<Wlasny *>( &model ), mostek.gt, &szerW, &wysW ) != CE_None
         || szerW <= 0 || wysW <= 0 )
      return QStringLiteral( "Nie udało się wyznaczyć zasięgu wyniku — sprawdź punkty" );

    // BUDZET ROZMIARU. Perspektywa potrafi rozciagnac daleki brzeg zdjecia
    // w wielokrotnosc oryginalu, a telefon nie ma z czego tego zrobic.
    // Przeliczenie nie tworzy szczegolow, ktorych nie ma w zrodle, wiec
    // zamiast ODMAWIAC - grubiejemy piksel tak, zeby wynik sie miescil.
    // Bez tego proba konczyla sie zabiciem aplikacji przez system.
    const double zrodloPx = double( GDALGetRasterXSize( obraz ) ) * GDALGetRasterYSize( obraz );
    const double budzet = std::min( 40e6, std::max( 4e6, 1.5 * zrodloPx ) );
    const double ile = double( szerW ) * wysW;
    if ( ile > budzet )
    {
      const double k = std::sqrt( ile / budzet );
      mostek.gt[1] *= k;
      mostek.gt[5] *= k;
      szerW = std::max( 1, int( std::ceil( szerW / k ) ) );
      wysW = std::max( 1, int( std::ceil( wysW / k ) ) );
      qInfo() << "WFG georef: wynik zgrubiony do" << szerW << "x" << wysW << "piksel" << mostek.gt[1];
    }
    if ( !GDALInvGeoTransform( mostek.gt, mostek.odwrotna ) )
      return QStringLiteral( "Nie udało się odwrócić geotransformacji wyniku" );

    OGRSpatialReferenceH srs = OSRNewSpatialReference( nullptr );
    char *wkt = nullptr;
    if ( OSRSetFromUserInput( srs, uklad.toUtf8().constData() ) != OGRERR_NONE || OSRExportToWkt( srs, &wkt ) != OGRERR_NONE )
    {
      OSRDestroySpatialReference( srs );
      return QStringLiteral( "Nieznany układ współrzędnych: %1" ).arg( uklad );
    }
    OSRDestroySpatialReference( srs );

    // Pasmo alfa ZRODLA (np. PNG) nie powiela sie w wyniku - idzie
    // do GDAL-a jako maska, a wynik dostaje swoje jedno, nowe.
    const int pasmZrodla = GDALGetRasterCount( obraz );
    int alfaZrodla = 0;
    for ( int i = 1; i <= pasmZrodla; i++ )
      if ( GDALGetRasterColorInterpretation( GDALGetRasterBand( obraz, i ) ) == GCI_AlphaBand )
        alfaZrodla = i;
    const int pasm = alfaZrodla ? pasmZrodla - 1 : pasmZrodla;
    if ( pasm < 1 )
    {
      CPLFree( wkt );
      return QStringLiteral( "Obraz nie ma pasm do przeliczenia" );
    }
    const GDALDataType typ = GDALGetRasterDataType( GDALGetRasterBand( obraz, 1 ) );

    GDALDriverH sterownik = GDALGetDriverByName( "GTiff" );
    if ( !sterownik )
    {
      CPLFree( wkt );
      return QStringLiteral( "Brak sterownika GTiff" );
    }
    qInfo() << "WFG georef: tworze wynik" << szerW << "x" << wysW << "pasm" << pasm + 1;
    char **opcje = nullptr;
    opcje = CSLSetNameValue( opcje, "COMPRESS", "DEFLATE" );
    opcje = CSLSetNameValue( opcje, "TILED", "YES" );
    GDALDatasetH cel = GDALCreate( sterownik, wyjscie.toUtf8().constData(), szerW, wysW, pasm + 1, typ, opcje );
    CSLDestroy( opcje );
    if ( !cel )
    {
      CPLFree( wkt );
      return QStringLiteral( "Nie udało się utworzyć pliku wyniku" );
    }
    GDALSetGeoTransform( cel, mostek.gt );
    GDALSetProjection( cel, wkt );
    CPLFree( wkt );
    GDALSetRasterColorInterpretation( GDALGetRasterBand( cel, pasm + 1 ), GCI_AlphaBand );

    GDALWarpOptions *wo = GDALCreateWarpOptions();
    wo->hSrcDS = obraz;
    wo->hDstDS = cel;
    wo->eResampleAlg = GRA_Bilinear;
    // Wprost, a nie domyslnie: na telefonie kazde 64 MB jest pozyczone
    // od kogos innego. Mniejszy kawalek = wiecej przebiegow i troche
    // wolniej, ale bez wychodzenia poza to, co jest.
    wo->dfWarpMemoryLimit = 24 * 1024 * 1024;
    wo->pfnTransformer = transformerWarp;
    wo->pTransformerArg = &mostek;
    wo->pfnProgress = GDALDummyProgress;
    wo->nBandCount = pasm;
    wo->panSrcBands = static_cast<int *>( CPLMalloc( sizeof( int ) * pasm ) );
    wo->panDstBands = static_cast<int *>( CPLMalloc( sizeof( int ) * pasm ) );
    for ( int i = 0; i < pasm; i++ )
    {
      wo->panSrcBands[i] = i + 1;
      wo->panDstBands[i] = i + 1;
    }
    wo->nSrcAlphaBand = alfaZrodla;
    wo->nDstAlphaBand = pasm + 1;

    GDALWarpOperationH operacja = GDALCreateWarpOperation( wo );
    const CPLErr blad = operacja ? GDALChunkAndWarpImage( operacja, 0, 0, szerW, wysW ) : CE_Failure;
    if ( operacja )
      GDALDestroyWarpOperation( operacja );
    GDALDestroyWarpOptions( wo );
    GDALClose( cel );
    if ( blad != CE_None )
      return QStringLiteral( "Przeliczenie obrazu nie powiodło się" );
    qInfo() << "WFG georef: przeliczone, buduje piramide";
    piramida( wyjscie );
    qInfo() << "WFG georef: gotowe" << wyjscie;

    szerokosc = szerW;
    wysokosc = wysW;
    piksel = std::abs( mostek.gt[1] );
    return QString();
  }

  inline bool wlasnaMetoda( const QString &metoda )
  {
    return metoda == QLatin1String( "liniowa" ) || metoda == QLatin1String( "helmerta" )
           || metoda == QLatin1String( "afiniczna" ) || metoda == QLatin1String( "rzutowa" );
  }

  // =================================================================
  //  WSPOLNY CZASOWNIK: dopasuj na tych punktach, policz w tamtych
  // =================================================================

  /**
   * Dopasowanie liczone na `gcp`, wyliczone w punktach `px`/`py`.
   *
   * Jeden czasownik dla wszystkich metod i wszystkich zastosowan:
   * odchylek, sprawdzianu krzyzowego i siatki punktow dla GDAL-a.
   * Dzieki temu liczba w oknie i obraz na mapie NIE MOGA sie rozejsc.
   */
  inline bool przelicz( const QString &metoda, const QList<GDAL_GCP> &gcp,
                        const QVector<double> &px, const QVector<double> &py,
                        QVector<double> &wx, QVector<double> &wy )
  {
    const int n = px.size();
    wx.resize( n );
    wy.resize( n );
    if ( gcp.size() < minimum( metoda ) )
      return false;

    if ( wlasnaMetoda( metoda ) )
    {
      const Wlasny model = dopasujWlasny( metoda, gcp );
      if ( !model.dobry )
        return false;
      for ( int i = 0; i < n; i++ )
        if ( !policzWlasny( model, px[i], py[i], wx[i], wy[i] ) )
          return false;
      return true;
    }

    const bool tps = metoda == QLatin1String( "miejscowa" );
    const int stopien = metoda == QLatin1String( "wielomian3" ) ? 3 : 2;
    QList<GDAL_GCP> kopia = gcp;
    // Cisza na czas proby: sprawdzian krzyzowy wola to N razy, a GDAL
    // krzyczy "Transform is not solvable" do dziennika przy kazdym
    // nieudanym ukladzie. Odpowiedz i tak wraca przez `false`.
    CPLPushErrorHandler( CPLQuietErrorHandler );
    void *pt = tps ? GDALCreateTPSTransformer( kopia.size(), kopia.data(), FALSE )
                   : GDALCreateGCPTransformer( kopia.size(), kopia.data(), stopien, FALSE );
    CPLPopErrorHandler();
    if ( !pt )
      return false;
    for ( int i = 0; i < n; i++ )
    {
      double x = px[i], y = py[i], z = 0;
      int ok = 0;
      if ( tps )
        GDALTPSTransform( pt, FALSE, 1, &x, &y, &z, &ok );
      else
        GDALGCPTransform( pt, FALSE, 1, &x, &y, &z, &ok );
      if ( !ok )
      {
        if ( tps )
          GDALDestroyTPSTransformer( pt );
        else
          GDALDestroyGCPTransformer( pt );
        return false;
      }
      wx[i] = x;
      wy[i] = y;
    }
    if ( tps )
      GDALDestroyTPSTransformer( pt );
    else
      GDALDestroyGCPTransformer( pt );
    return true;
  }

  /**
   * Odchylki na punktach i sprawdzian krzyzowy - {odchylki, srednie,
   * najwieksze, najgorszy, sprawdzian, sprawdzianNajwiekszy,
   * sprawdzianNajgorszy, sprawdzianOdchylki, minimum, dosc} albo {blad}.
   *
   * ODCHYLKI mowia, ile brakuje w punktach, ktore dopasowanie WIDZIALO.
   * Przy minimalnej liczbie punktow sa zerowe z definicji - kazda metoda
   * przechodzi wtedy przez nie dokladnie. Ta liczba nie jest wiec miara
   * jakosci, tylko wykrywaczem punktu wskazanego krzywo.
   *
   * SPRAWDZIAN KRZYZOWY wyjmuje kazdy punkt po kolei, dopasowuje bez
   * niego i mierzy, o ile chybia w to wyjete miejsce. To jest jedyna
   * liczba, ktora mowi, ile wynik jest wart w miejscu, ktorego nikt
   * nie wskazywal - czyli wszedzie tam, gdzie sie potem chodzi.
   * Wymaga o jeden punkt wiecej niz minimum metody.
   */
  inline QVariantMap ocena( const QString &metoda, const QList<GDAL_GCP> &gcp )
  {
    QVariantMap wynik;
    const int ile = gcp.size();
    const int min = minimum( metoda );
    wynik.insert( QStringLiteral( "minimum" ), min );
    wynik.insert( QStringLiteral( "dosc" ), ile >= min );
    if ( ile < min )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Ta metoda potrzebuje co najmniej %1 punktów — masz %2" ).arg( min ).arg( ile ) );
      return wynik;
    }

    QVector<double> px( ile ), py( ile ), wx, wy;
    for ( int i = 0; i < ile; i++ )
    {
      px[i] = gcp[i].dfGCPPixel;
      py[i] = gcp[i].dfGCPLine;
    }
    if ( !przelicz( metoda, gcp, px, py, wx, wy ) )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Z tych punktów nie da się policzyć przekształcenia — rozłóż je po całym obrazie, nie na jednej prostej" ) );
      return wynik;
    }

    QVariantList lista;
    double suma = 0, najwieksze = 0;
    int najgorszy = -1;
    for ( int i = 0; i < ile; i++ )
    {
      const double d = std::hypot( wx[i] - gcp[i].dfGCPX, wy[i] - gcp[i].dfGCPY );
      lista << d;
      suma += d * d;
      if ( d > najwieksze )
      {
        najwieksze = d;
        najgorszy = i;
      }
    }
    wynik.insert( QStringLiteral( "odchylki" ), lista );
    wynik.insert( QStringLiteral( "srednie" ), std::sqrt( suma / ile ) );
    wynik.insert( QStringLiteral( "najwieksze" ), najwieksze );
    wynik.insert( QStringLiteral( "najgorszy" ), najgorszy );

    // --- sprawdzian krzyzowy -------------------------------------
    if ( ile <= min )
      return wynik;

    QVariantList sLista;
    double sSuma = 0, sNaj = 0;
    int sNajgorszy = -1, policzonych = 0;
    for ( int i = 0; i < ile; i++ )
    {
      QList<GDAL_GCP> bez;
      for ( int j = 0; j < ile; j++ )
        if ( j != i )
          bez << gcp[j];
      QVector<double> jx { gcp[i].dfGCPPixel }, jy { gcp[i].dfGCPLine }, ox, oy;
      if ( !przelicz( metoda, bez, jx, jy, ox, oy ) )
      {
        sLista << -1.0;
        continue;
      }
      const double d = std::hypot( ox[0] - gcp[i].dfGCPX, oy[0] - gcp[i].dfGCPY );
      sLista << d;
      sSuma += d * d;
      policzonych++;
      if ( d > sNaj )
      {
        sNaj = d;
        sNajgorszy = i;
      }
    }
    if ( policzonych > 0 )
    {
      wynik.insert( QStringLiteral( "sprawdzianOdchylki" ), sLista );
      wynik.insert( QStringLiteral( "sprawdzian" ), std::sqrt( sSuma / policzonych ) );
      wynik.insert( QStringLiteral( "sprawdzianNajwiekszy" ), sNaj );
      wynik.insert( QStringLiteral( "sprawdzianNajgorszy" ), sNajgorszy );
    }
    return wynik;
  }

  /**
   * Obraz + punkty dopasowania -> GeoTIFF w podanym ukladzie.
   *
   * Zwraca {plik, srednie, najwieksze, najgorszy, sprawdzian, odchylki,
   * szerokosc, wysokosc, piksel, metoda} albo {blad}.
   */
  inline QVariantMap dopasuj( const QString &zrodlo, const QVariantList &punkty, const QString &uklad,
                              const QString &metoda, const QString &wyjscie )
  {
    QVariantMap wynik;
    GDALAllRegister();

    QList<GDAL_GCP> gcp = zListy( punkty );
    qInfo() << "WFG georef: start" << metoda << "punktow" << punkty.size();
    QVariantMap oc = ocena( metoda, gcp );
    if ( oc.contains( QStringLiteral( "blad" ) ) )
    {
      GDALDeinitGCPs( gcp.size(), gcp.data() );
      return oc;
    }

    GDALDatasetH obraz = GDALOpen( zrodlo.toUtf8().constData(), GA_ReadOnly );
    if ( !obraz )
    {
      GDALDeinitGCPs( gcp.size(), gcp.data() );
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się otworzyć obrazu: %1" ).arg( zrodlo ) );
      return wynik;
    }

    QDir().mkpath( QFileInfo( wyjscie ).absolutePath() );

    // Metody liczone u nas (liniowa, Helmerta, afiniczna, rzutowa) ida
    // do GDAL-a jako JEGO transformer - nie jako siatka punktow, ktora
    // by je tylko przyblizala. Wielomiany i TPS zostaja u GDAL-a.
    if ( wlasnaMetoda( metoda ) )
    {
      Wlasny model = dopasujWlasny( metoda, gcp );
      model.szerObrazu = GDALGetRasterXSize( obraz );
      model.wysObrazu = GDALGetRasterYSize( obraz );
      GDALDeinitGCPs( gcp.size(), gcp.data() );
      if ( !model.dobry )
      {
        GDALClose( obraz );
        wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się policzyć przekształcenia" ) );
        return wynik;
      }
      int szerokosc = 0, wysokosc = 0;
      double piksel = 0;
      const QString blad = przeliczWlasnym( obraz, model, uklad, wyjscie, szerokosc, wysokosc, piksel );
      GDALClose( obraz );
      if ( !blad.isEmpty() )
      {
        wynik.insert( QStringLiteral( "blad" ), blad );
        return wynik;
      }
      wynik = oc;
      wynik.insert( QStringLiteral( "plik" ), wyjscie );
      wynik.insert( QStringLiteral( "szerokosc" ), szerokosc );
      wynik.insert( QStringLiteral( "wysokosc" ), wysokosc );
      wynik.insert( QStringLiteral( "piksel" ), piksel );
      wynik.insert( QStringLiteral( "metoda" ), metoda );
      return wynik;
    }

    const bool tps = metoda == QLatin1String( "miejscowa" );
    const int stopien = metoda == QLatin1String( "wielomian3" ) ? 3 : 2;
    QList<GDAL_GCP> &doPliku = gcp;

    // Krok 1: obraz z wpisanymi punktami, w pamieci - na dysku zostaje
    // tylko wynik, a nie polprodukt, ktory nikomu nie jest potrzebny.
    const QString posredni = QStringLiteral( "/vsimem/wfg_georef.vrt" );
    QStringList argTranslate;
    argTranslate << QStringLiteral( "-of" ) << QStringLiteral( "VRT" )
                 << QStringLiteral( "-a_srs" ) << uklad;
    for ( const GDAL_GCP &g : std::as_const( doPliku ) )
    {
      argTranslate << QStringLiteral( "-gcp" )
                   << QString::number( g.dfGCPPixel, 'f', 4 ) << QString::number( g.dfGCPLine, 'f', 4 )
                   << QString::number( g.dfGCPX, 'f', 4 ) << QString::number( g.dfGCPY, 'f', 4 );
    }
    QList<QByteArray> bajty1;
    QList<char *> argv1;
    for ( const QString &a : std::as_const( argTranslate ) )
    {
      bajty1 << a.toUtf8();
      argv1 << bajty1.last().data();
    }
    argv1 << nullptr;
    GDALTranslateOptions *opcje1 = GDALTranslateOptionsNew( argv1.data(), nullptr );
    GDALDatasetH zPunktami = GDALTranslate( posredni.toUtf8().constData(), obraz, opcje1, nullptr );
    GDALTranslateOptionsFree( opcje1 );
    GDALDeinitGCPs( doPliku.size(), doPliku.data() );
    if ( !zPunktami )
    {
      GDALClose( obraz );
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się wpisać punktów dopasowania" ) );
      return wynik;
    }
    // UWAGA: `obraz` musi ZYC do konca przeliczenia. VRT trzyma do niego
    // wskaznik, a nie kopie - zamkniecie go tutaj wywracalo GDALWarp
    // w BuildVirtualOverviews (piaskownica 21.09, segmentation fault).

    // Krok 2: przeliczenie. `-r bilinear` wygladza, `-dstalpha` daje
    // przezroczyste obrzeza zamiast czarnych trojkatow po obroceniu.
    QStringList argWarp;
    argWarp << QStringLiteral( "-t_srs" ) << uklad
            << QStringLiteral( "-r" ) << QStringLiteral( "bilinear" )
            << QStringLiteral( "-dstalpha" )
            << QStringLiteral( "-of" ) << QStringLiteral( "GTiff" )
            << QStringLiteral( "-co" ) << QStringLiteral( "COMPRESS=DEFLATE" )
            << QStringLiteral( "-co" ) << QStringLiteral( "TILED=YES" );
    // TO SAMO przeksztalcenie, ktore policzylo odchylki - inaczej liczby
    // w oknie opisywalyby co innego niz obraz na mapie.
    if ( tps )
      argWarp << QStringLiteral( "-tps" );
    else
      argWarp << QStringLiteral( "-order" ) << QString::number( stopien );
    QList<QByteArray> bajty2;
    QList<char *> argv2;
    for ( const QString &a : std::as_const( argWarp ) )
    {
      bajty2 << a.toUtf8();
      argv2 << bajty2.last().data();
    }
    argv2 << nullptr;
    GDALWarpAppOptions *opcje2 = GDALWarpAppOptionsNew( argv2.data(), nullptr );
    int uzycie = 0;
    GDALDatasetH gotowe = GDALWarp( wyjscie.toUtf8().constData(), nullptr, 1, &zPunktami, opcje2, &uzycie );
    GDALWarpAppOptionsFree( opcje2 );
    GDALClose( zPunktami );
    GDALClose( obraz );
    VSIUnlink( posredni.toUtf8().constData() );
    if ( !gotowe )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Przeliczenie obrazu nie powiodło się" ) );
      return wynik;
    }
    const int szerokosc = GDALGetRasterXSize( gotowe );
    const int wysokosc = GDALGetRasterYSize( gotowe );
    double gt[6] = { 0 };
    GDALGetGeoTransform( gotowe, gt );
    GDALClose( gotowe );
    piramida( wyjscie );
    qInfo() << "WFG georef: gotowe" << wyjscie << szerokosc << "x" << wysokosc;

    wynik = oc;
    wynik.insert( QStringLiteral( "plik" ), wyjscie );
    wynik.insert( QStringLiteral( "szerokosc" ), szerokosc );
    wynik.insert( QStringLiteral( "wysokosc" ), wysokosc );
    wynik.insert( QStringLiteral( "piksel" ), std::abs( gt[1] ) );
    wynik.insert( QStringLiteral( "metoda" ), metoda );
    return wynik;
  }
} // namespace Georeferencja

#endif // GEOREFERENCJA_H
