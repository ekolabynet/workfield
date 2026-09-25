/***************************************************************************
  warstwarobocza.cpp - ModulWarstwyRoboczej (WorkFieldGIS)

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "warstwarobocza.h"

#include "kafle.h"

#include <QFileInfo>
#include <QJsonArray>
#include <QObject>

#include <qgis.h>
#include <qgscoordinatereferencesystem.h>
#include <qgsdefaultvalue.h>
#include <qgsproject.h>
#include <qgsvectorlayer.h>

#include <cpl_string.h>
#include <gdal.h>
#include <ogr_api.h>
#include <ogr_srs_api.h>
#include <sqlite3.h>

namespace
{
  //! Geometria po nazwie z `modul.json`. Nieznana = punkt, bo warstwy
  //! robocze sa punktowe i to jedyny sensowny domysl.
  OGRwkbGeometryType geometriaZOpisu( const QString &nazwa )
  {
    if ( nazwa == QLatin1String( "linia" ) )
      return wkbLineString;
    if ( nazwa == QLatin1String( "obszar" ) || nazwa == QLatin1String( "poligon" ) )
      return wkbPolygon;
    return wkbPoint;
  }

  //! Typ pola po nazwie z `modul.json`.
  OGRFieldType typPolaZOpisu( const QString &nazwa )
  {
    if ( nazwa == QLatin1String( "liczba" ) )
      return OFTInteger;
    if ( nazwa == QLatin1String( "rzeczywista" ) )
      return OFTReal;
    if ( nazwa == QLatin1String( "data" ) )
      return OFTDate;
    return OFTString;
  }

  QString geometriaPoLudzku( const QString &nazwa )
  {
    if ( nazwa == QLatin1String( "linia" ) )
      return QObject::tr( "liniowa" );
    if ( nazwa == QLatin1String( "obszar" ) || nazwa == QLatin1String( "poligon" ) )
      return QObject::tr( "obszarowa" );
    return QObject::tr( "punktowa" );
  }

  /**
   * Uklad, w ktorym ma powstac warstwa robocza.
   *
   * Najpierw uklad PROJEKTU — warstwa robocza ma lezec tam, gdzie czlowiek
   * patrzy. Gdy projekt ukladu nie ma (zdarza sie projektom zlozonym poza
   * QGIS-em i kazdemu swiezo utworzonemu w probie), bierzemy uklad
   * PIERWSZEJ WARSTWY WEKTOROWEJ. Warstwa bez ukladu wyladowalaby w innym
   * miejscu swiata niz reszta projektu i nikt by tego nie zauwazyl
   * do pierwszego tyczenia.
   */
  QgsCoordinateReferenceSystem ukladDlaWarstwy( QgsProject *projekt )
  {
    if ( !projekt )
      return QgsCoordinateReferenceSystem();
    if ( projekt->crs().isValid() )
      return projekt->crs();
    const QMap<QString, QgsMapLayer *> warstwy = projekt->mapLayers();
    for ( QgsMapLayer *m : warstwy )
    {
      QgsVectorLayer *w = qobject_cast<QgsVectorLayer *>( m );
      if ( w && w->isValid() && w->crs().isValid() )
        return w->crs();
    }
    return QgsCoordinateReferenceSystem();
  }

  //! Czy tabela o tej nazwie jest juz w pliku.
  bool tabelaJest( const QString &gpkg, const QString &tabela )
  {
    sqlite3 *db = nullptr;
    if ( sqlite3_open_v2( gpkg.toUtf8().constData(), &db, SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
    {
      if ( db )
        sqlite3_close( db );
      return false;
    }
    bool jest = false;
    sqlite3_stmt *zap = nullptr;
    if ( sqlite3_prepare_v2( db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                             -1, &zap, nullptr ) == SQLITE_OK )
    {
      sqlite3_bind_text( zap, 1, tabela.toUtf8().constData(), -1, SQLITE_TRANSIENT );
      jest = sqlite3_step( zap ) == SQLITE_ROW;
      sqlite3_finalize( zap );
    }
    sqlite3_close( db );
    return jest;
  }

  /**
   * Zaklada tabele przez GDAL. Pusty ciag = sukces, inaczej przyczyna.
   *
   * `FID=fid` nie jest ozdoba: bez tego GDAL nazywa klucz glowny inaczej
   * niz reszta warstw projektu, a zalaczniki N:1 przypinaja sie wlasnie
   * do `fid`. Warstwa robocza bez `fid` nie dostalaby wiec galerii.
   */
  QString utworzTabele( const QString &gpkg, const QString &tabela,
                        OGRwkbGeometryType geom, const QgsCoordinateReferenceSystem &crs,
                        const QJsonArray &pola )
  {
    GDALDatasetH ds = GDALOpenEx( gpkg.toUtf8().constData(),
                                  GDAL_OF_VECTOR | GDAL_OF_UPDATE,
                                  nullptr, nullptr, nullptr );
    if ( !ds )
      return QObject::tr( "nie otwarto bazy do zapisu" );

    OGRSpatialReferenceH srs = nullptr;
    const QString authid = crs.authid();
    if ( !authid.isEmpty() )
    {
      srs = OSRNewSpatialReference( nullptr );
      if ( OSRSetFromUserInput( srs, authid.toUtf8().constData() ) != OGRERR_NONE )
      {
        OSRDestroySpatialReference( srs );
        srs = nullptr;
      }
    }
    if ( !srs )
    {
      const QString wkt = crs.toWkt();
      if ( !wkt.isEmpty() )
      {
        srs = OSRNewSpatialReference( nullptr );
        if ( OSRSetFromUserInput( srs, wkt.toUtf8().constData() ) != OGRERR_NONE )
        {
          OSRDestroySpatialReference( srs );
          srs = nullptr;
        }
      }
    }
    if ( !srs )
    {
      // Warstwa bez ukladu wyladuje w innym miejscu swiata niz reszta
      // projektu i nikt tego nie zauwazy do pierwszego tyczenia.
      GDALClose( ds );
      return QObject::tr( "ani projekt, ani żadna jego warstwa nie ma układu "
                          "współrzędnych — nie wiem, gdzie tę warstwę położyć" );
    }

    char **opcje = CSLSetNameValue( nullptr, "FID", "fid" );
    OGRLayerH l = GDALDatasetCreateLayer( ds, tabela.toUtf8().constData(), srs, geom, opcje );
    CSLDestroy( opcje );
    OSRDestroySpatialReference( srs );
    if ( !l )
    {
      GDALClose( ds );
      return QObject::tr( "nie utworzono tabeli %1" ).arg( tabela );
    }

    for ( const QJsonValue &v : pola )
    {
      const QJsonObject p = v.toObject();
      const QString nazwaPola = p.value( QStringLiteral( "nazwa" ) ).toString();
      if ( nazwaPola.isEmpty() )
        continue;
      OGRFieldDefnH fd = OGR_Fld_Create(
        nazwaPola.toUtf8().constData(),
        typPolaZOpisu( p.value( QStringLiteral( "typ" ) ).toString() ) );
      // ZADNE pole nie dostaje NOT NULL: punkt tyczenia zakladany jednym
      // tapnieciem musi sie zapisac takze wtedy, gdy nikt nic nie wpisal.
      const OGRErr err = OGR_L_CreateField( l, fd, TRUE );
      OGR_Fld_Destroy( fd );
      if ( err != OGRERR_NONE )
      {
        GDALClose( ds );
        return QObject::tr( "nie utworzono pola %1 w %2" ).arg( nazwaPola, tabela );
      }
    }
    GDALClose( ds );
    return QString();
  }
} // namespace

namespace ModulWarstwyRoboczej
{
  QString baza( QgsProject *projekt )
  {
    if ( !projekt )
      return QString();
    const QString dom = projekt->homePath();
    if ( dom.isEmpty() )
      return QString();
    const QString p = dom + QStringLiteral( "/dane.gpkg" );
    return QFileInfo::exists( p ) ? p : QString();
  }

  QString zapowiedz( const QJsonObject &krok )
  {
    const QString nazwa = krok.value( QStringLiteral( "nazwa" ) ).toString();
    const QString geom = geometriaPoLudzku( krok.value( QStringLiteral( "geometria" ) ).toString() );

    QStringList pola;
    for ( const QJsonValue &v : krok.value( QStringLiteral( "pola" ) ).toArray() )
    {
      const QString p = v.toObject().value( QStringLiteral( "nazwa" ) ).toString();
      if ( !p.isEmpty() )
        pola << p;
    }

    QString t = QObject::tr( "Powstanie warstwa %1 „%2” w dane.gpkg" ).arg( geom, nazwa );
    if ( !pola.isEmpty() )
      t += QObject::tr( ", pola: %1" ).arg( pola.join( QStringLiteral( ", " ) ) );

    const QJsonObject kafel = krok.value( QStringLiteral( "kafel" ) ).toObject();
    if ( !kafel.isEmpty() )
      t += QObject::tr( ", oraz kafel „%1” na pasku szybkiego przechwytu" )
             .arg( kafel.value( QStringLiteral( "etykieta" ) ).toString() );
    return t + QStringLiteral( "." );
  }

  Wynik zaloz( QgsProject *projekt, const QJsonObject &krok )
  {
    Wynik w;
    const QString nazwa = krok.value( QStringLiteral( "nazwa" ) ).toString();
    if ( nazwa.isEmpty() )
    {
      w.opis = QObject::tr( "krok nie podaje nazwy warstwy" );
      return w;
    }
    if ( !projekt )
    {
      w.opis = QObject::tr( "nie ma otwartego projektu" );
      return w;
    }

    // --- 1. warstwa w projekcie ------------------------------------------
    QgsVectorLayer *warstwa = nullptr;
    const QList<QgsMapLayer *> znalezione = projekt->mapLayersByName( nazwa );
    for ( QgsMapLayer *m : znalezione )
    {
      if ( QgsVectorLayer *l = qobject_cast<QgsVectorLayer *>( m ) )
      {
        warstwa = l;
        break;
      }
    }

    bool nowa = false;
    if ( !warstwa )
    {
      const QString gpkg = baza( projekt );
      if ( gpkg.isEmpty() )
      {
        w.opis = QObject::tr( "obok projektu nie ma pliku dane.gpkg — warstwy roboczej "
                              "nie ma gdzie założyć. Ten projekt trzyma dane inaczej "
                              "i warstwę trzeba dołożyć w biurze." );
        return w;
      }

      if ( !tabelaJest( gpkg, nazwa ) )
      {
        const QString blad = utworzTabele(
          gpkg, nazwa,
          geometriaZOpisu( krok.value( QStringLiteral( "geometria" ) ).toString() ),
          ukladDlaWarstwy( projekt ),
          krok.value( QStringLiteral( "pola" ) ).toArray() );
        if ( !blad.isEmpty() )
        {
          w.opis = QObject::tr( "Warstwa %1: %2." ).arg( nazwa, blad );
          return w;
        }
        nowa = true;
        w.szczegoly << QObject::tr( "tabela %1 w dane.gpkg" ).arg( nazwa );
      }
      else
      {
        // Tabela jest, warstwy w projekcie nie ma — wczytujemy ISTNIEJACA.
        // Drugiej takiej samej nie robimy nigdy: w tamtej moga juz lezec
        // punkty z terenu, a projekt po prostu ich nie pokazywal.
        w.szczegoly << QObject::tr( "tabela %1 już była w bazie — wczytana" ).arg( nazwa );
      }

      const QString uri = QStringLiteral( "%1|layername=%2" ).arg( gpkg, nazwa );
      warstwa = new QgsVectorLayer( uri, nazwa, QStringLiteral( "ogr" ) );
      if ( !warstwa->isValid() )
      {
        // GDAL bywa „przyzwyczajony” do starej zawartosci pliku, ktory QGIS
        // trzyma otwarty — swieza tabela potrafi nie byc widoczna za
        // pierwszym razem. Jedna ponowna proba zwykle wystarcza.
        delete warstwa;
        warstwa = new QgsVectorLayer( uri, nazwa, QStringLiteral( "ogr" ) );
      }
      if ( !warstwa->isValid() )
      {
        delete warstwa;
        w.opis = QObject::tr( "Nie wczytałem warstwy %1. Tabela w pliku już jest, "
                              "więc ponowne uruchomienie jej nie zdubluje." )
                   .arg( nazwa );
        return w;
      }
      projekt->addMapLayer( warstwa );
      w.szczegoly << QObject::tr( "warstwa %1 w projekcie" ).arg( nazwa );
    }
    else
    {
      w.szczegoly << QObject::tr( "warstwa %1 już była" ).arg( nazwa );
    }

    // --- 2. wartosci domyslne pol ----------------------------------------
    // Ustawiamy TYLKO tam, gdzie nic jeszcze nie ma — warstwa mogla
    // przyjechac z biura z wlasnym wyrazeniem i nie nam je poprawiac.
    for ( const QJsonValue &v : krok.value( QStringLiteral( "pola" ) ).toArray() )
    {
      const QJsonObject p = v.toObject();
      const QString domyslnie = p.value( QStringLiteral( "domyslnie" ) ).toString();
      if ( domyslnie.isEmpty() )
        continue;
      const int idx = warstwa->fields().indexOf( p.value( QStringLiteral( "nazwa" ) ).toString() );
      if ( idx < 0 )
        continue;
      if ( !warstwa->defaultValueDefinition( idx ).expression().isEmpty() )
        continue;
      warstwa->setDefaultValueDefinition( idx, QgsDefaultValue( domyslnie ) );
    }

    const QString wyswietlaj = krok.value( QStringLiteral( "wyswietlaj" ) ).toString();
    if ( !wyswietlaj.isEmpty() && warstwa->displayExpression().isEmpty() )
      warstwa->setDisplayExpression( wyswietlaj );

    // --- 3. kafel --------------------------------------------------------
    const QJsonObject kafel = krok.value( QStringLiteral( "kafel" ) ).toObject();
    if ( !kafel.isEmpty() )
    {
      const ModulKafli::Wynik k = ModulKafli::dolozKafel(
        projekt, nazwa,
        kafel.value( QStringLiteral( "etykieta" ) ).toString(),
        kafel.value( QStringLiteral( "kolor" ) ).toString(),
        kafel.value( QStringLiteral( "zdjecie" ) ).toBool( false ) );
      if ( !k.ok )
      {
        // Warstwa JUZ POWSTALA. Mowimy o tym wprost, zeby ponowne
        // uruchomienie nie wygladalo na probe zalozenia jej drugi raz.
        w.opis = QObject::tr( "Warstwa %1 założona, ale kafel nie: %2" ).arg( nazwa, k.opis );
        return w;
      }
      w.szczegoly << k.opis;
    }

    w.ok = true;
    w.opis = nowa
               ? QObject::tr( "warstwa %1 założona (%2)" )
                   .arg( nazwa, w.szczegoly.join( QStringLiteral( ", " ) ) )
               : QObject::tr( "%1" ).arg( w.szczegoly.join( QStringLiteral( ", " ) ) );
    return w;
  }
} // namespace ModulWarstwyRoboczej
