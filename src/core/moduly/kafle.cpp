/***************************************************************************
  kafle.cpp - ModulKafli (WorkFieldGIS)

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "kafle.h"

#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QObject>
#include <QSet>
#include <QVariantMap>

#include <qgis.h>
#include <qgsproject.h>
#include <qgsvectorlayer.h>
#include <qgswkbtypes.h>

namespace
{
  const QString NAZWA_PLIKU = QStringLiteral( "workfield_klawisze.json" );

  //! Klucze, ktorych szuka QfQuickCaptureBar.loadDefinitions(). „nazwa”
  //! zamiast „etykieta” daje pasek PUSTY — stad ta lista jest tu jawnie.
  const QString KLUCZ_LISTY = QStringLiteral( "klawisze" );
  const QString KLUCZ_ETYKIETY = QStringLiteral( "etykieta" );
  const QString KLUCZ_WARSTWY = QStringLiteral( "warstwa" );
  const QString KLUCZ_KOLORU = QStringLiteral( "kolor" );
  const QString KLUCZ_ZDJECIA = QStringLiteral( "zdjecie" );

  //! Warstwy, ktore nigdy nie dostaja kafla. Ta sama lista co w modulach
  //! zalacznikow — rozjazd dalby kafel na tabeli zalacznikow.
  const QStringList POMIN_PREFIKSY = {
    QStringLiteral( "zal_" ), QStringLiteral( "ZAL_" ),
    QStringLiteral( "podklad_" ), QStringLiteral( "REF_" ), QStringLiteral( "ref_" )
  };
  const QStringList POMIN_NAZWY = {
    QStringLiteral( "slownik" ), QStringLiteral( "slownik_gatunkow" ),
    QStringLiteral( "taksony" ), QStringLiteral( "wskazniki" ),
    QStringLiteral( "wskazniki_polaczone" ), QStringLiteral( "SLOWNIK_GATUNKOW" )
  };

  //! Barwy kafli po kolei. Kolejnosc z dendro (zielen, blekit, pomarancz),
  //! dalej cokolwiek — byle sasiednie kafle nie byly tego samego koloru.
  const QStringList PALETA = {
    QStringLiteral( "#4CAF50" ), QStringLiteral( "#2196F3" ),
    QStringLiteral( "#FF9800" ), QStringLiteral( "#9C27B0" ),
    QStringLiteral( "#00BCD4" ), QStringLiteral( "#E91E63" ),
    QStringLiteral( "#8BC34A" ), QStringLiteral( "#FFC107" )
  };

  QString bezOgonkow( const QString &tekst )
  {
    static const QString zrodlo = QStringLiteral( "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ" );
    static const QString cel = QStringLiteral( "acelnoszzACELNOSZZ" );
    QString w;
    w.reserve( tekst.size() );
    for ( const QChar &z : tekst )
    {
      const int i = zrodlo.indexOf( z );
      w.append( i >= 0 ? cel.at( i ) : z );
    }
    return w;
  }

  //! Nazwa warstwy sprowadzona do [A-Z0-9] — z tego bierze sie etykieta.
  QString litery( const QString &nazwa )
  {
    const QString bezOg = bezOgonkow( nazwa ).toUpper();
    QString w;
    for ( const QChar &z : bezOg )
    {
      if ( ( z >= 'A' && z <= 'Z' ) || ( z >= '0' && z <= '9' ) )
        w.append( z );
    }
    return w;
  }

  /**
   * Etykieta, ktorej jeszcze nie ma na pasku.
   *
   * ZNALEZIONE PRZY CZYTANIU `QfNaprawaProjektu.zbudujKlawisze()` 23.09.2026:
   * tamta funkcja bierze `nazwa.substring(0, 1)` i nie sprawdza NICZEGO.
   * Kreator „Projekt z DXF” zaklada „Punkty” i „Poligony” — oba dostaja „P”.
   * Pasek wstaje z dwoma takimi samymi klawiszami i w terenie nie wiadomo,
   * w ktory sie stuka.
   *
   * Kolejnosc prob jest taka, zeby etykieta zostala CZYTELNA: najpierw
   * jedna litera, potem dwie pierwsze („PO” dla „Poligony”), potem pierwsza
   * z kolejna („PL”, „PI”), na koncu pierwsza z cyfra.
   */
  QString etykietaDla( const QString &nazwa, const QSet<QString> &zajete )
  {
    const QString l = litery( nazwa );
    if ( l.isEmpty() )
    {
      for ( int c = 1; c <= 9; ++c )
      {
        const QString p = QStringLiteral( "K%1" ).arg( c );
        if ( !zajete.contains( p ) )
          return p;
      }
      return QStringLiteral( "K" );
    }

    QStringList proby;
    proby << l.left( 1 );
    if ( l.size() >= 2 )
      proby << l.left( 2 );
    for ( int i = 1; i < l.size(); ++i )
      proby << l.left( 1 ) + l.at( i );
    for ( int c = 2; c <= 9; ++c )
      proby << l.left( 1 ) + QString::number( c );

    for ( const QString &p : proby )
    {
      if ( !zajete.contains( p ) )
        return p;
    }
    return l.left( 1 );
  }

  //! Tresc pliku kafli. Pusty obiekt, gdy pliku nie ma. \a blad dostaje
  //! przyczyne, gdy plik JEST, ale nie da sie go przeczytac albo sparsowac.
  QJsonObject wczytaj( const QString &plik, QString *blad )
  {
    if ( !QFileInfo::exists( plik ) )
      return QJsonObject();
    QFile f( plik );
    if ( !f.open( QIODevice::ReadOnly ) )
    {
      if ( blad )
        *blad = QObject::tr( "nie mogę odczytać %1 obok projektu" ).arg( NAZWA_PLIKU );
      return QJsonObject();
    }
    QJsonParseError e;
    const QJsonDocument d = QJsonDocument::fromJson( f.readAll(), &e );
    f.close();
    if ( e.error != QJsonParseError::NoError )
    {
      // NIE NADPISUJEMY pliku, ktorego nie rozumiemy. Zepsuty JSON to
      // zwykle literowka w recznie dopisanym kaflu — nadpisanie skasowaloby
      // cala reszte, ktora byla dobra.
      if ( blad )
        *blad = QObject::tr( "%1 nie jest poprawnym JSON-em: %2 (znak %3). "
                             "Nie nadpisuję pliku, którego nie rozumiem — popraw go najpierw." )
                  .arg( NAZWA_PLIKU, e.errorString() )
                  .arg( e.offset );
      return QJsonObject();
    }
    return d.object();
  }

  //! Kopia `.przed_<data>` istniejacego pliku. Pusty ciag = nie bylo czego.
  QString kopia( const QString &plik )
  {
    if ( !QFileInfo::exists( plik ) )
      return QString();
    const QString cel = plik + QStringLiteral( ".przed_" )
                        + QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmmss" ) );
    // `QFile::copy` odmawia, gdy cel juz jest, a znacznik ma rozdzielczosc
    // jednej sekundy — patrz ta sama pulapka w `Wyposazenie::zaloz()`.
    if ( !QFile::exists( cel ) )
      QFile::copy( plik, cel );
    return cel;
  }

  bool zapisz( const QString &plik, const QJsonObject &obj, QString *blad )
  {
    QFile f( plik );
    if ( !f.open( QIODevice::WriteOnly | QIODevice::Text ) )
    {
      if ( blad )
        *blad = QObject::tr( "nie udało się zapisać %1" ).arg( NAZWA_PLIKU );
      return false;
    }
    f.write( QJsonDocument( obj ).toJson( QJsonDocument::Indented ) );
    f.close();
    return true;
  }

  //! Nazwa geometrii po polsku — do okna wyboru, nie do pliku.
  QString geometriaPoLudzku( QgsVectorLayer *w )
  {
    switch ( static_cast<Qgis::GeometryType>( w->geometryType() ) )
    {
      case Qgis::GeometryType::Point:
        return QObject::tr( "punkty" );
      case Qgis::GeometryType::Line:
        return QObject::tr( "linie" );
      case Qgis::GeometryType::Polygon:
        return QObject::tr( "obszary" );
      default:
        return QObject::tr( "bez geometrii" );
    }
  }

  //! Warstwy wektorowe projektu, ktorym wolno dac kafel, po nazwie.
  QList<QgsVectorLayer *> warstwyDoKafli( QgsProject *projekt )
  {
    QList<QgsVectorLayer *> out;
    if ( !projekt )
      return out;
    const QMap<QString, QgsMapLayer *> warstwy = projekt->mapLayers();
    for ( QgsMapLayer *m : warstwy )
    {
      QgsVectorLayer *w = qobject_cast<QgsVectorLayer *>( m );
      if ( !w || !w->isValid() || w->readOnly() )
        continue;
      // Kafel sluzy do ZAKLADANIA obiektu — warstwa bez geometrii nie ma
      // czego zalozyc na mapie.
      if ( static_cast<Qgis::GeometryType>( w->geometryType() ) == Qgis::GeometryType::Null
           || static_cast<Qgis::GeometryType>( w->geometryType() ) == Qgis::GeometryType::Unknown )
        continue;
      const QString nazwa = w->name();
      if ( POMIN_NAZWY.contains( nazwa ) )
        continue;
      bool pomin = false;
      for ( const QString &p : POMIN_PREFIKSY )
      {
        if ( nazwa.startsWith( p ) )
        {
          pomin = true;
          break;
        }
      }
      if ( pomin )
        continue;
      out << w;
    }
    std::sort( out.begin(), out.end(), []( QgsVectorLayer *a, QgsVectorLayer *b ) {
      return a->name().localeAwareCompare( b->name() ) < 0;
    } );
    return out;
  }
} // namespace

namespace ModulKafli
{
  QString plikKafli( QgsProject *projekt )
  {
    if ( !projekt || projekt->homePath().isEmpty() )
      return QString();
    return projekt->homePath() + QStringLiteral( "/" ) + NAZWA_PLIKU;
  }

  QVariantList kandydaci( QgsProject *projekt )
  {
    QVariantList out;
    const QString plik = plikKafli( projekt );
    if ( plik.isEmpty() )
      return out;

    QString blad;
    const QJsonObject obj = wczytaj( plik, &blad );
    const QJsonArray kafle = obj.value( KLUCZ_LISTY ).toArray();

    // Co JUZ jest na pasku: etykieta po warstwie i zbior zajetych etykiet.
    QMap<QString, QString> etykietaWarstwy;
    QSet<QString> zajete;
    for ( const QJsonValue &v : kafle )
    {
      const QJsonObject k = v.toObject();
      const QString e = k.value( KLUCZ_ETYKIETY ).toString();
      const QString w = k.value( KLUCZ_WARSTWY ).toString();
      if ( !e.isEmpty() )
        zajete.insert( e );
      if ( !w.isEmpty() && !e.isEmpty() && !etykietaWarstwy.contains( w ) )
        etykietaWarstwy[w] = e;
    }

    int barwa = 0;
    const QList<QgsVectorLayer *> warstwy = warstwyDoKafli( projekt );
    for ( QgsVectorLayer *w : warstwy )
    {
      const QString nazwa = w->name();
      const bool ma = etykietaWarstwy.contains( nazwa );
      QString etykieta;
      if ( ma )
      {
        etykieta = etykietaWarstwy.value( nazwa );
      }
      else
      {
        // Propozycja REZERWUJE etykiete, zeby dwie warstwy z tej samej
        // listy nie dostaly tej samej litery.
        etykieta = etykietaDla( nazwa, zajete );
        zajete.insert( etykieta );
      }

      QVariantMap m;
      m[QStringLiteral( "warstwa" )] = nazwa;
      m[QStringLiteral( "etykieta" )] = etykieta;
      m[QStringLiteral( "geometria" )] = geometriaPoLudzku( w );
      m[QStringLiteral( "maKafel" )] = ma;
      m[QStringLiteral( "kolor" )] = PALETA.at( barwa % PALETA.size() );
      m[QStringLiteral( "zdjecie" )] = true;
      out << m;
      if ( !ma )
        ++barwa;
    }
    return out;
  }

  Wynik zaloz( QgsProject *projekt, const QStringList &warstwy )
  {
    Wynik w;
    const QString plik = plikKafli( projekt );
    if ( plik.isEmpty() )
    {
      w.opis = QObject::tr( "Projekt nie ma katalogu — nie ma gdzie zapisać kafli." );
      return w;
    }
    if ( warstwy.isEmpty() )
    {
      w.opis = QObject::tr( "Nie wskazano ani jednej warstwy." );
      return w;
    }

    QString blad;
    QJsonObject obj = wczytaj( plik, &blad );
    if ( !blad.isEmpty() )
    {
      w.opis = blad;
      return w;
    }

    QJsonArray kafle = obj.value( KLUCZ_LISTY ).toArray();
    QSet<QString> zajete;
    QSet<QString> majaKafel;
    for ( const QJsonValue &v : kafle )
    {
      const QJsonObject k = v.toObject();
      if ( !k.value( KLUCZ_ETYKIETY ).toString().isEmpty() )
        zajete.insert( k.value( KLUCZ_ETYKIETY ).toString() );
      if ( !k.value( KLUCZ_WARSTWY ).toString().isEmpty() )
        majaKafel.insert( k.value( KLUCZ_WARSTWY ).toString() );
    }

    int barwa = kafle.size();
    int dolozone = 0;
    for ( const QString &nazwa : warstwy )
    {
      // Kafel wskazujacy na warstwe, ktorej nie ma, daje pasek PUSTY —
      // i dowiadujesz sie o tym dopiero w terenie. Wiec sprawdzamy TU.
      if ( !projekt || projekt->mapLayersByName( nazwa ).isEmpty() )
      {
        w.opis = QObject::tr( "W projekcie nie ma warstwy „%1” — nie robię kafla, "
                              "który wskazywałby w pustkę." )
                   .arg( nazwa );
        return w;
      }
      if ( majaKafel.contains( nazwa ) )
      {
        w.szczegoly << QObject::tr( "%1: kafel już był" ).arg( nazwa );
        continue;
      }
      const QString e = etykietaDla( nazwa, zajete );
      zajete.insert( e );
      majaKafel.insert( nazwa );

      QJsonObject k;
      k[KLUCZ_ETYKIETY] = e;
      k[KLUCZ_WARSTWY] = nazwa;
      k[KLUCZ_KOLORU] = PALETA.at( barwa % PALETA.size() );
      k[KLUCZ_ZDJECIA] = true;
      kafle.append( k );
      w.szczegoly << QObject::tr( "%1 → „%2”" ).arg( nazwa, e );
      ++barwa;
      ++dolozone;
    }

    if ( dolozone == 0 )
    {
      w.ok = true;
      w.opis = QObject::tr( "Wszystkie wskazane warstwy miały już kafel." );
      return w;
    }

    kopia( plik );
    obj[KLUCZ_LISTY] = kafle;
    if ( !zapisz( plik, obj, &blad ) )
    {
      w.opis = blad;
      return w;
    }

    w.ok = true;
    w.opis = QObject::tr( "kafle: %1" ).arg( w.szczegoly.join( QStringLiteral( ", " ) ) );
    return w;
  }

  Wynik dolozKafel( QgsProject *projekt, const QString &warstwa,
                    const QString &etykieta, const QString &kolor, bool zdjecie )
  {
    Wynik w;
    const QString plik = plikKafli( projekt );
    if ( plik.isEmpty() )
    {
      w.opis = QObject::tr( "Projekt nie ma katalogu — nie ma gdzie zapisać kafla." );
      return w;
    }

    QString blad;
    QJsonObject obj = wczytaj( plik, &blad );
    if ( !blad.isEmpty() )
    {
      w.opis = blad;
      return w;
    }

    QJsonArray kafle = obj.value( KLUCZ_LISTY ).toArray();
    QSet<QString> zajete;
    for ( const QJsonValue &v : kafle )
    {
      const QJsonObject k = v.toObject();
      if ( k.value( KLUCZ_WARSTWY ).toString() == warstwa )
      {
        // IDEMPOTENCJA PO WARSTWIE, nie po etykiecie. Projekty dendro maja
        // kafel tyczenia pod etykieta „T” od 20.09 — gdybysmy patrzyli na
        // etykiete, dolozylibysmy drugi kafel na te sama warstwe.
        w.ok = true;
        w.opis = QObject::tr( "kafel „%1” dla warstwy %2 już był" )
                   .arg( k.value( KLUCZ_ETYKIETY ).toString(), warstwa );
        return w;
      }
      if ( !k.value( KLUCZ_ETYKIETY ).toString().isEmpty() )
        zajete.insert( k.value( KLUCZ_ETYKIETY ).toString() );
    }

    QString e = etykieta;
    if ( e.isEmpty() || zajete.contains( e ) )
      e = etykietaDla( e.isEmpty() ? warstwa : e, zajete );

    QJsonObject k;
    k[KLUCZ_ETYKIETY] = e;
    k[KLUCZ_WARSTWY] = warstwa;
    k[KLUCZ_KOLORU] = kolor.isEmpty() ? PALETA.at( kafle.size() % PALETA.size() ) : kolor;
    k[KLUCZ_ZDJECIA] = zdjecie;
    kafle.append( k );

    kopia( plik );
    obj[KLUCZ_LISTY] = kafle;
    if ( !zapisz( plik, obj, &blad ) )
    {
      w.opis = blad;
      return w;
    }

    w.ok = true;
    w.opis = QObject::tr( "kafel „%1” → %2" ).arg( e, warstwa );
    w.szczegoly << w.opis;
    return w;
  }
} // namespace ModulKafli
