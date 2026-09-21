/***************************************************************************
  warstwice.h - WorkField

  Warstwice z rastra i z punktow pomiarowych. Wspolne dla okna danych
  wysokosciowych (NMT) i dla modulu CAD (rzedne z rysunku) - zrodlo decyduje
  o tym, GDZIE stoi przycisk, ale rachunek jest jeden.

  Tylko GDAL: GDALGrid (punkty -> raster) i GDALContourGenerateEx
  (raster -> warstwice). Ta sama rodzina API, ktorej aplikacja uzywa juz
  w qfappinterface.cpp (GDALDEMProcessing, GDALWarp).

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef WARSTWICE_H
#define WARSTWICE_H

#include <QFileInfo>
#include <QDir>
#include <QString>
#include <QStringList>
#include <QVariantMap>

#include <cpl_conv.h>
#include <cpl_string.h>
#include <gdal.h>
#include <gdal_alg.h>
#include <gdal_utils.h>
#include <ogr_api.h>
#include <ogr_srs_api.h>

namespace Warstwice
{
  //! Domyslny odstep warstwic [m] - co pol metra, jak na mapie zasadniczej.
  inline constexpr double ODSTEP = 0.5;

  /**
   * Warstwice z rastra wysokosciowego do pliku GPKG.
   *
   * Pole RZEDNA niesie wysokosc linii - to po nim styluje sie warstwice
   * pogrubione (co 5 x odstep) i podpisuje je na mapie.
   *
   * Zwraca {plik, linie} albo {blad}.
   */
  inline QVariantMap zRastra( const QString &raster, const QString &wyjscie, double odstep )
  {
    QVariantMap wynik;
    if ( odstep <= 0 )
      odstep = ODSTEP;
    GDALAllRegister();

    GDALDatasetH zrodlo = GDALOpen( raster.toUtf8().constData(), GA_ReadOnly );
    if ( !zrodlo )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się otworzyć rastra: %1" ).arg( raster ) );
      return wynik;
    }
    GDALRasterBandH pasmo = GDALGetRasterBand( zrodlo, 1 );
    if ( !pasmo )
    {
      GDALClose( zrodlo );
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Raster nie ma pasma wysokości" ) );
      return wynik;
    }

    GDALDriverH sterownik = GDALGetDriverByName( "GPKG" );
    if ( !sterownik )
    {
      GDALClose( zrodlo );
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak sterownika GPKG" ) );
      return wynik;
    }
    QDir().mkpath( QFileInfo( wyjscie ).absolutePath() );
    // Plik od nowa: powtorzone liczenie ma dac jeden komplet warstwic,
    // a nie dolozyc drugi na wierzchu pierwszego.
    VSIUnlink( wyjscie.toUtf8().constData() );
    GDALDatasetH cel = GDALCreate( sterownik, wyjscie.toUtf8().constData(), 0, 0, 0, GDT_Unknown, nullptr );
    if ( !cel )
    {
      GDALClose( zrodlo );
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się utworzyć pliku warstwic" ) );
      return wynik;
    }

    OGRSpatialReferenceH uklad = GDALGetSpatialRef( zrodlo );
    OGRLayerH warstwa = GDALDatasetCreateLayer( cel, "warstwice", uklad, wkbLineString, nullptr );
    if ( !warstwa )
    {
      GDALClose( cel );
      GDALClose( zrodlo );
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się utworzyć warstwy warstwic" ) );
      return wynik;
    }
    OGRFieldDefnH pole = OGR_Fld_Create( "RZEDNA", OFTReal );
    OGR_L_CreateField( warstwa, pole, TRUE );
    OGR_Fld_Destroy( pole );
    const int idPola = OGR_FD_GetFieldIndex( OGR_L_GetLayerDefn( warstwa ), "RZEDNA" );

    int maNodata = 0;
    const double nodata = GDALGetRasterNoDataValue( pasmo, &maNodata );

    char **opcje = nullptr;
    opcje = CSLSetNameValue( opcje, "LEVEL_INTERVAL", CPLSPrintf( "%g", odstep ) );
    opcje = CSLSetNameValue( opcje, "ELEV_FIELD", CPLSPrintf( "%d", idPola ) );
    if ( maNodata )
      opcje = CSLSetNameValue( opcje, "NODATA", CPLSPrintf( "%.18g", nodata ) );
    const CPLErr blad = GDALContourGenerateEx( pasmo, warstwa, opcje, nullptr, nullptr );
    CSLDestroy( opcje );

    const int linii = ( blad == CE_None ) ? static_cast<int>( OGR_L_GetFeatureCount( warstwa, TRUE ) ) : 0;
    GDALClose( cel );
    GDALClose( zrodlo );

    if ( blad != CE_None )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Liczenie warstwic nie powiodło się" ) );
      return wynik;
    }
    wynik.insert( QStringLiteral( "plik" ), wyjscie );
    wynik.insert( QStringLiteral( "linie" ), linii );
    wynik.insert( QStringLiteral( "odstep" ), odstep );
    return wynik;
  }

  /**
   * Powierzchnia z punktow pomiarowych (GDALGrid) - krok posredni przed
   * warstwicami.
   *
   * METODA. "gladko" to invdistnn: odwrotna odleglosc z sasiedztwem
   * w promieniu. "wiernie" to linear: triangulacja Delaunaya.
   *
   * Sprawdzone na 1240 rzednych z rysunku 3853_24_pin: linear jest wierny
   * punktom, ale daje warstwice kanciaste i z prostymi artefaktami tam,
   * gdzie pomiar szedl wzdluz drogi - geodeta tego nie uzna. Stad domyslna
   * jest gladka, a wierna zostaje do wyboru dla kogos, kto wie, czego chce.
   */
  inline QVariantMap powierzchnia( const QString &punkty, const QString &warstwa, const QString &poleZ,
                                   const QString &wyjscie, const QString &metoda, double piksel )
  {
    QVariantMap wynik;
    GDALAllRegister();
    if ( piksel <= 0 )
      piksel = 2.0;

    GDALDatasetH zrodlo = GDALOpenEx( punkty.toUtf8().constData(), GDAL_OF_VECTOR | GDAL_OF_READONLY, nullptr, nullptr, nullptr );
    if ( !zrodlo )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się otworzyć punktów" ) );
      return wynik;
    }
    OGRLayerH w = GDALDatasetGetLayerByName( zrodlo, warstwa.toUtf8().constData() );
    if ( !w || OGR_L_GetFeatureCount( w, TRUE ) < 3 )
    {
      GDALClose( zrodlo );
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Za mało punktów z wysokością (potrzeba co najmniej trzech)" ) );
      return wynik;
    }
    OGREnvelope zasieg;
    if ( OGR_L_GetExtent( w, &zasieg, TRUE ) != OGRERR_NONE )
    {
      GDALClose( zrodlo );
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się ustalić zasięgu punktów" ) );
      return wynik;
    }
    const int szerokosc = qBound( 16, static_cast<int>( ( zasieg.MaxX - zasieg.MinX ) / piksel ), 4000 );
    const int wysokosc = qBound( 16, static_cast<int>( ( zasieg.MaxY - zasieg.MinY ) / piksel ), 4000 );

    // Promien sasiedztwa z gestosci punktow: osiem razy sredni odstep miedzy
    // nimi. Za maly zostawia dziury, za duzy rozmazuje teren na plasko.
    const double pole = ( zasieg.MaxX - zasieg.MinX ) * ( zasieg.MaxY - zasieg.MinY );
    const double sredniOdstep = std::sqrt( qMax( 1.0, pole ) / qMax( 1.0, static_cast<double>( OGR_L_GetFeatureCount( w, TRUE ) ) ) );
    const double promien = qBound( 5.0, 8.0 * sredniOdstep, 200.0 );

    const QString algorytm = metoda == QLatin1String( "wiernie" )
                               ? QStringLiteral( "linear:radius=-1.0:nodata=-9999" )
                               : QStringLiteral( "invdistnn:power=2:radius=%1:max_points=12:min_points=1:nodata=-9999" ).arg( promien, 0, 'f', 1 );

    QDir().mkpath( QFileInfo( wyjscie ).absolutePath() );
    QStringList argumenty;
    argumenty << QStringLiteral( "-a" ) << algorytm
              << QStringLiteral( "-zfield" ) << poleZ
              << QStringLiteral( "-l" ) << warstwa
              << QStringLiteral( "-outsize" ) << QString::number( szerokosc ) << QString::number( wysokosc )
              << QStringLiteral( "-of" ) << QStringLiteral( "GTiff" )
              << QStringLiteral( "-ot" ) << QStringLiteral( "Float32" );
    QList<QByteArray> bajty;
    QList<char *> argv;
    for ( const QString &a : std::as_const( argumenty ) )
    {
      bajty << a.toUtf8();
      argv << bajty.last().data();
    }
    argv << nullptr;

    GDALGridOptions *opcje = GDALGridOptionsNew( argv.data(), nullptr );
    int uzycie = 0;
    GDALDatasetH siatka = GDALGrid( wyjscie.toUtf8().constData(), zrodlo, opcje, &uzycie );
    GDALGridOptionsFree( opcje );
    GDALClose( zrodlo );
    if ( !siatka )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się policzyć powierzchni z punktów" ) );
      return wynik;
    }
    GDALClose( siatka );

    wynik.insert( QStringLiteral( "plik" ), wyjscie );
    wynik.insert( QStringLiteral( "piksel" ), piksel );
    wynik.insert( QStringLiteral( "promien" ), promien );
    return wynik;
  }
} // namespace Warstwice

#endif // WARSTWICE_H
