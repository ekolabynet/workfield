/***************************************************************************
  stozkiwidzenia.cpp - StozkiWidzenia (WorkField)
 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "stozkiwidzenia.h"

#include <QFileInfo>
#include <QtMath>

#include <qgscoordinatereferencesystem.h>
#include <qgscoordinatetransform.h>
#include <qgsexiftools.h>
#include <qgsexpression.h>
#include <qgsexpressioncontext.h>
#include <qgsexpressioncontextutils.h>
#include <qgsfeature.h>
#include <qgsfeatureiterator.h>
#include <qgsfeaturerequest.h>
#include <qgsgeometry.h>
#include <qgspointxy.h>
#include <qgspolygon.h>
#include <qgsproject.h>
#include <qgsvectorlayer.h>

StozkiWidzenia::StozkiWidzenia( QObject *parent )
  : QObject( parent )
{
}

namespace
{
  //! OpenCamera pisze "Yaw:303.9,Pitch:-41.3,Roll:-2.4" w UserComment.
  //! Nasz wlasny zapis to JSON. Oba formaty obsluguje CaptureAttitude,
  //! ale tu potrzebujemy tylko pitcha, wiec czytamy wprost.
  double wyjmijLiczbe( const QString &tekst, const QString &klucz )
  {
    const int i = tekst.indexOf( klucz, 0, Qt::CaseInsensitive );
    if ( i < 0 )
      return qQNaN();
    int j = i + klucz.length();
    while ( j < tekst.length() && ( tekst.at( j ) == ':' || tekst.at( j ) == '"'
                                    || tekst.at( j ) == ' ' ) )
      ++j;
    int k = j;
    while ( k < tekst.length()
            && ( tekst.at( k ).isDigit() || tekst.at( k ) == '.'
                 || tekst.at( k ) == '-' || tekst.at( k ) == '+' ) )
      ++k;
    bool ok = false;
    const double v = tekst.mid( j, k - j ).toDouble( &ok );
    return ok ? v : qQNaN();
  }
}

QVariantMap StozkiWidzenia::odczytaj( const QString &sciezkaZdjecia ) const
{
  QVariantMap w;
  if ( !QFileInfo::exists( sciezkaZdjecia ) )
    return w;

  // getGeoTag zwraca QgsPoint i sygnalizuje powodzenie przez `ok`.
  // Sam punkt przy braku geotagu jest (0,0), a to wspolrzedne prawidlowe —
  // gdybysmy sprawdzali tylko jego, zdjecia bez GPS ladowalyby na Atlantyku.
  bool maGeotag = false;
  const QgsPoint poz = QgsExifTools::getGeoTag( sciezkaZdjecia, maGeotag );
  if ( !maGeotag )
    return w;

  w[QStringLiteral( "lon" )] = poz.x();
  w[QStringLiteral( "lat" )] = poz.y();

  const QVariant kierunek =
    QgsExifTools::readTag( sciezkaZdjecia,
                           QStringLiteral( "Exif.GPSInfo.GPSImgDirection" ) );
  w[QStringLiteral( "azymut" )] = kierunek.isValid() ? kierunek.toDouble() : qQNaN();

  // UserComment bywa zwracane jako QByteArray, nie QString — wtedy
  // `.toString()` daje pustke i pitch przepada po cichu. Bierzemy oba
  // warianty. EXIF dopuszcza osmiobajtowy naglowek kodowania (`ASCII\0..`);
  // OpenCamera go NIE pisze, ale inne aparaty tak, wiec zdejmujemy go,
  // jesli jest.
  const QVariant surowy =
    QgsExifTools::readTag( sciezkaZdjecia,
                           QStringLiteral( "Exif.Photo.UserComment" ) );
  QString komentarz = surowy.toString();
  if ( komentarz.isEmpty() )
  {
    QByteArray bajty = surowy.toByteArray();
    if ( bajty.size() > 8
         && ( bajty.startsWith( "ASCII" ) || bajty.startsWith( "UNICODE" )
              || bajty.startsWith( "JIS" ) ) )
      bajty = bajty.mid( 8 );
    komentarz = QString::fromUtf8( bajty ).trimmed();
  }
  w[QStringLiteral( "pitch" )] = wyjmijLiczbe( komentarz, QStringLiteral( "Pitch" ) );
  w[QStringLiteral( "roll" )] = wyjmijLiczbe( komentarz, QStringLiteral( "Roll" ) );
  const double yaw = wyjmijLiczbe( komentarz, QStringLiteral( "Yaw" ) );
  if ( !std::isnan( yaw ) && std::isnan( w[QStringLiteral( "azymut" )].toDouble() ) )
    w[QStringLiteral( "azymut" )] = yaw;

  const QVariant wys =
    QgsExifTools::readTag( sciezkaZdjecia,
                           QStringLiteral( "Exif.GPSInfo.GPSAltitude" ) );
  w[QStringLiteral( "wysokosc" )] = wys.isValid() ? wys.toDouble() : qQNaN();

  // Bez azymutu stozka nie ma jak obrocic. Bez pitcha przyjmiemy -45,
  // bo to typowe ujecie platu — ale mowimy o tym wprost.
  const bool maAzymut = !std::isnan( w[QStringLiteral( "azymut" )].toDouble() );
  w[QStringLiteral( "ok" )] = maAzymut;
  if ( !maAzymut )
    w[QStringLiteral( "powod" )] = tr( "brak azymutu w EXIF" );
  else if ( std::isnan( w[QStringLiteral( "pitch" )].toDouble() ) )
    w[QStringLiteral( "powod" )] = tr( "brak pochylenia — przyjeto -45 stopni" );

  return w;
}

QString StozkiWidzenia::stozekWkt( const QString &sciezkaZdjecia,
                                   QgsVectorLayer *warstwa ) const
{
  if ( !warstwa )
    return QString();

  const QVariantMap e = odczytaj( sciezkaZdjecia );
  if ( e.isEmpty() || !e[QStringLiteral( "ok" )].toBool() )
    return QString();

  // Punkt aparatu przenosimy do ukladu warstwy — cala reszta liczy sie
  // w metrach, wiec uklad geograficzny tu nie wystarczy.
  const QgsCoordinateReferenceSystem wgs84( QStringLiteral( "EPSG:4326" ) );
  QgsCoordinateTransform doWarstwy( wgs84, warstwa->crs(),
                                    QgsProject::instance() );
  QgsPointXY stoje;
  try
  {
    stoje = doWarstwy.transform( QgsPointXY( e[QStringLiteral( "lon" )].toDouble(),
                                             e[QStringLiteral( "lat" )].toDouble() ) );
  }
  catch ( ... )
  {
    return QString();
  }

  double pitch = e[QStringLiteral( "pitch" )].toDouble();
  if ( std::isnan( pitch ) )
    pitch = -45.0;
  // Azymut w EXIF jest MAGNETYCZNY, geometria jest w ukladzie geograficznym.
  const double azymut = e[QStringLiteral( "azymut" )].toDouble() + mDeklinacja;

  // Odleglosc srodka kadru od nog: h / tan(|pitch|). Przy -50 stopniach
  // to ~1,3 m, przy -34 ~2,2 m. Malo, ale przy platach kilkumetrowych
  // wlasnie ta roznica rozstrzyga o przynaleznosci.
  const double tg = std::tan( qDegreesToRadians( std::abs( pitch ) ) );
  const double doSrodka = tg > 0.05 ? mWysokosc / tg : mZasieg;

  // Stozek scinamy na `mZasieg` — dalej kadr obejmuje krajobraz, ktory
  // swiadectwem juz nie jest.
  const double bliski = std::max( 0.2, doSrodka * 0.3 );
  const double daleki = std::min( mZasieg, std::max( doSrodka * 2.0, 2.0 ) );

  const double polH = qDegreesToRadians( mPoleH / 2.0 );
  const double a = qDegreesToRadians( azymut );

  QVector<QgsPointXY> wierzcholki;
  auto dodaj = [&]( double odleglosc, double kat ) {
    const double k = a + kat;
    wierzcholki << QgsPointXY( stoje.x() + odleglosc * std::sin( k ),
                               stoje.y() + odleglosc * std::cos( k ) );
  };

  const int krokow = 12;
  dodaj( bliski, -polH );
  for ( int i = 0; i <= krokow; ++i )
    dodaj( daleki, -polH + 2 * polH * i / krokow );
  dodaj( bliski, polH );
  for ( int i = krokow; i >= 0; --i )
    dodaj( bliski, -polH + 2 * polH * i / krokow );

  QgsGeometry g = QgsGeometry::fromPolygonXY( QVector<QVector<QgsPointXY>>() << wierzcholki );
  if ( !g.isGeosValid() )
    g = g.makeValid();
  return g.asWkt( 3 );
}

QVariantList StozkiWidzenia::proponuj( const QString &sciezkaZdjecia,
                                       QgsVectorLayer *warstwa ) const
{
  QVariantList wynik;
  if ( !warstwa )
    return wynik;

  const QString wkt = stozekWkt( sciezkaZdjecia, warstwa );
  if ( wkt.isEmpty() )
    return wynik;

  const QgsGeometry stozek = QgsGeometry::fromWkt( wkt );
  if ( stozek.isEmpty() )
    return wynik;

  const double poleStozka = stozek.area();
  if ( poleStozka <= 0 )
    return wynik;

  // Punkt aparatu — do kolumny `stoje`. Czlowiek widzi wtedy, czy
  // propozycja bierze sie z tego, GDZIE STAL, czy z tego, GDZIE PATRZYL.
  const QVariantMap e = odczytaj( sciezkaZdjecia );
  QgsPointXY stoje;
  {
    const QgsCoordinateReferenceSystem wgs84( QStringLiteral( "EPSG:4326" ) );
    QgsCoordinateTransform t( wgs84, warstwa->crs(), QgsProject::instance() );
    try
    {
      stoje = t.transform( QgsPointXY( e[QStringLiteral( "lon" )].toDouble(),
                                       e[QStringLiteral( "lat" )].toDouble() ) );
    }
    catch ( ... )
    {
    }
  }
  const QgsGeometry punkt = QgsGeometry::fromPointXY( stoje );

  const int iUuid = warstwa->fields().lookupField( QStringLiteral( "UUID_WIERSZA" ) );
  const QString wyrazenie = warstwa->displayExpression();

  QgsFeatureRequest zadanie;
  zadanie.setFilterRect( stozek.boundingBox() );
  QgsFeatureIterator it = warstwa->getFeatures( zadanie );
  QgsFeature f;
  while ( it.nextFeature( f ) )
  {
    if ( !f.hasGeometry() )
      continue;
    const QgsGeometry czesc = f.geometry().intersection( stozek );
    if ( czesc.isEmpty() )
      continue;
    const double udzial = 100.0 * czesc.area() / poleStozka;
    if ( udzial < 1.0 )
      continue;

    QVariantMap w;
    w[QStringLiteral( "fid" )] = f.id();
    w[QStringLiteral( "uuid" )] = iUuid >= 0 ? f.attribute( iUuid ) : QVariant();
    // displayExpression() zwraca WYRAZENIE, nie wartosc — trzeba je policzyc
    // dla konkretnego obiektu, inaczej czlowiek widzi kod zamiast nazwy.
    QString etykieta = QString::number( f.id() );
    if ( !wyrazenie.isEmpty() )
    {
      QgsExpressionContext kontekst(
        QgsExpressionContextUtils::globalProjectLayerScopes( warstwa ) );
      kontekst.setFeature( f );
      QgsExpression wyr( wyrazenie );
      wyr.prepare( &kontekst );
      const QVariant v = wyr.evaluate( &kontekst );
      if ( !wyr.hasEvalError() && !v.toString().isEmpty() )
        etykieta = v.toString();
    }
    w[QStringLiteral( "etykieta" )] = etykieta;
    w[QStringLiteral( "udzial" )] = udzial;
    w[QStringLiteral( "stoje" )] = !punkt.isEmpty() && f.geometry().contains( punkt );
    wynik.append( w );
  }

  std::sort( wynik.begin(), wynik.end(), []( const QVariant &a, const QVariant &b ) {
    return a.toMap()[QStringLiteral( "udzial" )].toDouble()
           > b.toMap()[QStringLiteral( "udzial" )].toDouble();
  } );
  return wynik;
}

QVariantList StozkiWidzenia::proponujDlaWielu( const QStringList &pliki,
                                               QgsVectorLayer *warstwa ) const
{
  QVariantList wynik;
  for ( const QString &p : pliki )
  {
    QVariantMap w;
    w[QStringLiteral( "plik" )] = p;
    const QVariantList k = proponuj( p, warstwa );
    w[QStringLiteral( "kandydaci" )] = k;
    if ( k.isEmpty() )
    {
      const QVariantMap e = odczytaj( p );
      w[QStringLiteral( "powod" )] = e.isEmpty()
                                       ? tr( "brak danych EXIF" )
                                       : e.value( QStringLiteral( "powod" ),
                                                  tr( "stozek nie trafil w zaden obiekt" ) );
    }
    wynik.append( w );
  }
  return wynik;
}
