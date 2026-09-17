/***************************************************************************
  wyposazenie.cpp - Wyposazenie (WorkField)
 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "wyposazenie.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonParseError>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <QDateTime>
#include <QJsonArray>

#include <qgsproject.h>
#include <qgssnappingconfig.h>
#include <qgstolerance.h>
#include <qgsvectorlayer.h>

#include <sqlite3.h>

Wyposazenie::Wyposazenie( QObject *parent )
  : QObject( parent )
{
}

namespace
{
  //! Baza projektu: `dane.gpkg` obok `projekt.qgs`. Ta sama konwencja,
  //! ktorej pilnuje `obieg.py` i cala reszta narzedzi.
  QString bazaProjektu( QgsProject *projekt )
  {
    if ( !projekt )
      return QString();
    const QString dom = projekt->homePath();
    if ( dom.isEmpty() )
      return QString();
    const QString p = dom + QStringLiteral( "/dane.gpkg" );
    return QFileInfo::exists( p ) ? p : QString();
  }
}

QVariantMap Wyposazenie::stempel( QgsProject *projekt ) const
{
  QVariantMap w;
  const QString baza = bazaProjektu( projekt );
  if ( baza.isEmpty() )
    return w;

  sqlite3 *db = nullptr;
  if ( sqlite3_open_v2( baza.toUtf8().constData(), &db,
                        SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
  {
    if ( db )
      sqlite3_close( db );
    return w;
  }

  // Brak tabeli to nie blad — tak wyglada projekt sprzed wprowadzenia
  // stempli. Kazdy modul wyjdzie wtedy jako `brak`, i slusznie.
  sqlite3_stmt *zap = nullptr;
  const char *sql = "SELECT modul, wersja, data FROM WF_WYPOSAZENIE";
  if ( sqlite3_prepare_v2( db, sql, -1, &zap, nullptr ) == SQLITE_OK )
  {
    while ( sqlite3_step( zap ) == SQLITE_ROW )
    {
      const QString mid = QString::fromUtf8(
        reinterpret_cast<const char *>( sqlite3_column_text( zap, 0 ) ) );
      QVariantMap wpis;
      wpis[QStringLiteral( "wersja" )] = sqlite3_column_int( zap, 1 );
      wpis[QStringLiteral( "data" )] = QString::fromUtf8(
        reinterpret_cast<const char *>( sqlite3_column_text( zap, 2 ) ) );
      w[mid] = wpis;
    }
  }
  if ( zap )
    sqlite3_finalize( zap );
  sqlite3_close( db );
  return w;
}

QVariantList Wyposazenie::sprawdz( QgsProject *projekt ) const
{
  QVariantList wynik;

  // Katalog jedzie w APK z tego samego commita co kod — rozjazd niemozliwy.
  QFile plik( QStringLiteral( ":/wyposazenie/katalog.json" ) );
  if ( !plik.open( QIODevice::ReadOnly ) )
    return wynik;
  const QJsonObject katalog =
    QJsonDocument::fromJson( plik.readAll() ).object();
  plik.close();

  const QVariantMap s = stempel( projekt );

  const QJsonArray moduly = katalog.value( QStringLiteral( "moduly" ) ).toArray();
  for ( const QJsonValue &v : moduly )
  {
    const QJsonObject wpis = v.toObject();
    const QString mid = wpis.value( QStringLiteral( "id" ) ).toString();
    const int wKatalogu = wpis.value( QStringLiteral( "wersja" ) ).toInt();
    const QString sciezka = wpis.value( QStringLiteral( "sciezka" ) ).toString();

    // Opis modulu — nazwa dla czlowieka i informacja, gdzie wolno zakladac.
    QString nazwa = mid;
    QString opis;
    QString gdzie;
    QFile mf( QStringLiteral( ":/wyposazenie/%1/modul.json" ).arg( sciezka ) );
    if ( mf.open( QIODevice::ReadOnly ) )
    {
      const QJsonObject m = QJsonDocument::fromJson( mf.readAll() ).object();
      nazwa = m.value( QStringLiteral( "nazwa" ) ).toString( mid );
      opis = m.value( QStringLiteral( "opis" ) ).toString();
      const QJsonArray g = m.value( QStringLiteral( "gdzie" ) ).toArray();
      QStringList gl;
      for ( const QJsonValue &x : g )
        gl << x.toString();
      gdzie = gl.join( QStringLiteral( ", " ) );
      mf.close();
    }

    const bool jest = s.contains( mid );
    const QVariantMap wpisStempla = s.value( mid ).toMap();
    const int wProjekcie = jest ? wpisStempla.value( QStringLiteral( "wersja" ) ).toInt() : 0;

    QString stan;
    if ( !jest )
      stan = QStringLiteral( "brak" );
    else if ( wProjekcie < wKatalogu )
      stan = QStringLiteral( "starszy" );
    else if ( wProjekcie > wKatalogu )
      stan = QStringLiteral( "nowszy" );
    else
      stan = QStringLiteral( "zgodny" );

    QVariantMap r;
    r[QStringLiteral( "modul" )] = mid;
    r[QStringLiteral( "nazwa" )] = nazwa;
    r[QStringLiteral( "opis" )] = opis;
    r[QStringLiteral( "gdzie" )] = gdzie;
    r[QStringLiteral( "wProjekcie" )] = wProjekcie;
    r[QStringLiteral( "wAplikacji" )] = wKatalogu;
    r[QStringLiteral( "stan" )] = stan;
    r[QStringLiteral( "data" )] = wpisStempla.value( QStringLiteral( "data" ) );
    wynik.append( r );
  }
  return wynik;
}

bool Wyposazenie::cosNieGra( QgsProject *projekt ) const
{
  const QVariantList l = sprawdz( projekt );
  for ( const QVariant &v : l )
  {
    const QString stan = v.toMap().value( QStringLiteral( "stan" ) ).toString();
    if ( stan != QLatin1String( "zgodny" ) )
      return true;
  }
  return false;
}

QString Wyposazenie::podsumowanie( QgsProject *projekt ) const
{
  const QVariantList l = sprawdz( projekt );
  if ( l.isEmpty() )
    return tr( "Nie udalo sie odczytac katalogu wyposazenia." );

  QStringList brak, starsze, nowsze;
  for ( const QVariant &v : l )
  {
    const QVariantMap m = v.toMap();
    const QString stan = m.value( QStringLiteral( "stan" ) ).toString();
    const QString nazwa = m.value( QStringLiteral( "nazwa" ) ).toString();
    if ( stan == QLatin1String( "brak" ) )
      brak << nazwa;
    else if ( stan == QLatin1String( "starszy" ) )
      starsze << nazwa;
    else if ( stan == QLatin1String( "nowszy" ) )
      nowsze << nazwa;
  }

  QStringList czesci;
  // Kolejnosc nieprzypadkowa: `nowszy` idzie PIERWSZY, bo znaczy cos
  // odwrotnego niz reszta — to aplikacja jest przestarzala, nie projekt.
  if ( !nowsze.isEmpty() )
    czesci << tr( "APLIKACJA JEST STARSZA niz projekt: %1. Zaktualizuj aplikacje, "
                  "zanim zaczniesz pracowac." ).arg( nowsze.join( QStringLiteral( ", " ) ) );
  if ( !brak.isEmpty() )
    czesci << tr( "Projekt nie ma modulow: %1." ).arg( brak.join( QStringLiteral( ", " ) ) );
  if ( !starsze.isEmpty() )
    czesci << tr( "Starsza wersja modulow: %1." ).arg( starsze.join( QStringLiteral( ", " ) ) );

  if ( czesci.isEmpty() )
    return QString();

  czesci << tr( "Zakladanie i aktualizacja modulow odbywa sie w biurze." );
  return czesci.join( QStringLiteral( " " ) );
}


// ==========================================================================
// ZAKLADANIE MODULOW W TERENIE
// ==========================================================================
//
// Aplikacja umie TRZY typy krokow z siedmiu: `wlasciwosc`,
// `wlasciwosc_warstwy` i `snapping`. Reszta (`tabele_gpkg`,
// `warstwa_istnieje`, `kontrola_klawiszy`, `plik_obok`) dotyka struktury
// bazy albo wymaga decyzji czlowieka — i zostaje w biurze, gdzie jest
// kopia i widac wynik przed wysylka.
//
// MODUL ALBO CALY, ALBO WCALE. Zalozony w polowie i ostemplowany klamalby
// o swoim stanie, a to gorsze niz brak.

//! Typy krokow, ktore aplikacja wykonuje. Reszta = odmowa.
static const QStringList UMIEMY = {
  QStringLiteral( "wlasciwosc" ),
  QStringLiteral( "wlasciwosc_warstwy" ),
  QStringLiteral( "snapping" ),
  // Kroki SPRAWDZAJACE — niczego nie zmieniaja, wiec wolno je wykonac
  // wszedzie. Odkryte 15.09: `tyczenie` tylko patrzy, czy warstwa jest,
  // a `klawisze` czy plik kafli jest poprawny.
  QStringLiteral( "warstwa_istnieje" ),
  QStringLiteral( "kontrola_klawiszy" )
};

//! Typy krokow, ktore da sie COFNAC. Reszta = modul nieodwracalny.
static const QStringList COFAMY = {
  QStringLiteral( "wlasciwosc" ),
  QStringLiteral( "wlasciwosc_warstwy" )
};

QJsonObject Wyposazenie::opisModulu( const QString &modul ) const
{
  QFile plik( QStringLiteral( ":/wyposazenie/katalog.json" ) );
  if ( !plik.open( QIODevice::ReadOnly ) )
    return QJsonObject();
  const QJsonObject katalog = QJsonDocument::fromJson( plik.readAll() ).object();
  plik.close();

  for ( const QJsonValue &v : katalog.value( QStringLiteral( "moduly" ) ).toArray() )
  {
    const QJsonObject wpis = v.toObject();
    if ( wpis.value( QStringLiteral( "id" ) ).toString() != modul )
      continue;
    QFile mf( QStringLiteral( ":/wyposazenie/%1/modul.json" )
                .arg( wpis.value( QStringLiteral( "sciezka" ) ).toString() ) );
    if ( !mf.open( QIODevice::ReadOnly ) )
      return QJsonObject();
    const QJsonObject m = QJsonDocument::fromJson( mf.readAll() ).object();
    mf.close();
    return m;
  }
  return QJsonObject();
}

QString Wyposazenie::mozeZalozyc( const QString &modul ) const
{
  const QJsonObject m = opisModulu( modul );
  if ( m.isEmpty() )
    return tr( "nie ma takiego modulu w katalogu" );

  QStringList gdzie;
  for ( const QJsonValue &g : m.value( QStringLiteral( "gdzie" ) ).toArray() )
    gdzie << g.toString();
  if ( !gdzie.contains( QStringLiteral( "teren" ) ) )
    return tr( "tylko w biurze" );

  const QJsonArray kroki = m.value( QStringLiteral( "kroki" ) ).toArray();
  if ( kroki.isEmpty() )
    return tr( "modul nie ma krokow do wykonania" );

  for ( const QJsonValue &k : kroki )
  {
    const QString typ = k.toObject().value( QStringLiteral( "typ" ) ).toString();
    if ( !UMIEMY.contains( typ ) )
      return tr( "krok \"%1\" wykonuje tylko biuro" ).arg( typ );
  }
  return QString();
}

QString Wyposazenie::wykonajKrok( QgsProject *projekt, const QJsonObject &krok ) const
{
  const QString typ = krok.value( QStringLiteral( "typ" ) ).toString();
  const QString grupa = krok.value( QStringLiteral( "grupa" ) ).toString();
  const QString klucz = krok.value( QStringLiteral( "klucz" ) ).toString();

  if ( typ == QLatin1String( "wlasciwosc" ) )
  {
    const QJsonValue w = krok.value( QStringLiteral( "wartosc" ) );
    const QString typWartosci =
      krok.value( QStringLiteral( "typ_wartosci" ) ).toString( QStringLiteral( "int" ) );
    if ( typWartosci == QLatin1String( "int" ) )
      projekt->writeEntry( grupa, QStringLiteral( "/" ) + klucz, w.toInt() );
    else if ( typWartosci == QLatin1String( "double" ) )
      projekt->writeEntry( grupa, QStringLiteral( "/" ) + klucz, w.toDouble() );
    else if ( typWartosci == QLatin1String( "bool" ) )
      projekt->writeEntry( grupa, QStringLiteral( "/" ) + klucz, w.toBool() );
    else
      projekt->writeEntry( grupa, QStringLiteral( "/" ) + klucz, w.toString() );
    return QStringLiteral( "%1/%2 = %3" ).arg( grupa, klucz, w.toVariant().toString() );
  }

  if ( typ == QLatin1String( "wlasciwosc_warstwy" ) )
  {
    // Wybor warstw PRZEPISANY WIERNIE z `wybierz_warstwy` w wyposazenie.py.
    // Ta lista to pole `AvoidIntersectionsList` — 21.08.2026 wypelnione zle
    // kosztowalo pol dnia terenu, bo obejmowalo warstwe pokrywajaca caly
    // teren i kazdy nowy obiekt byl przycinany do zera BEZ KOMUNIKATU.
    // Rozjazd miedzy ta funkcja a pythonowa byłby wiec drogi.
    const QJsonObject wybor = krok.value( QStringLiteral( "wybor" ) ).toObject();
    QStringList geometrie;
    for ( const QJsonValue &g : wybor.value( QStringLiteral( "geometria" ) ).toArray() )
      geometrie << g.toString();
    QStringList pomin;
    for ( const QJsonValue &g : wybor.value( QStringLiteral( "pomin_nazwy" ) ).toArray() )
      pomin << g.toString();
    const bool tylkoEdytowalne =
      wybor.value( QStringLiteral( "tylko_edytowalne" ) ).toBool( true );

    QStringList idki, nazwy;
    const auto warstwy = projekt->mapLayers();
    for ( auto it = warstwy.constBegin(); it != warstwy.constEnd(); ++it )
    {
      QgsVectorLayer *w = qobject_cast<QgsVectorLayer *>( it.value() );
      if ( !w )
        continue;
      const QString geom = QgsWkbTypes::displayString(
        static_cast<Qgis::WkbType>( w->wkbType() ) );
      bool pasuje = geometrie.isEmpty();
      for ( const QString &g : geometrie )
        if ( geom.contains( g, Qt::CaseInsensitive ) )
          pasuje = true;
      if ( !pasuje )
        continue;
      if ( tylkoEdytowalne && w->readOnly() )
        continue;
      if ( pomin.contains( w->name() ) )
        continue;
      idki << w->id();
      nazwy << w->name();
    }
    projekt->writeEntry( grupa, QStringLiteral( "/" ) + klucz, idki );
    return QStringLiteral( "%1/%2 = %3 warstw (%4)" )
      .arg( grupa, klucz ).arg( idki.size() )
      .arg( nazwy.isEmpty() ? QStringLiteral( "—" ) : nazwy.join( QStringLiteral( ", " ) ) );
  }

  if ( typ == QLatin1String( "snapping" ) )
  {
    // Python pisze ATRYBUTY XML wprost do <snapping-settings>. Aplikacja
    // ma QgsSnappingConfig. Mapowanie jest tutaj, JAWNIE — to najbardziej
    // krucha czesc calej klasy, bo rozjazd nie da znaku, tylko inne
    // zachowanie przyciagania w terenie niz w biurze:
    //
    //     enabled               -> setEnabled
    //     mode                  -> setMode      1 aktywna, 2 wszystkie, 3 zaawans.
    //     type                  -> setTypeFlag  flagi: 1 wierzcholek, 2 odcinek, 4 obszar
    //     tolerance             -> setTolerance
    //     unit                  -> setUnits     0 warstwa/mapa, 1 piksele, 2 projekt
    //     intersection-snapping -> setIntersectionSnapping
    const QJsonObject a = krok.value( QStringLiteral( "atrybuty" ) ).toObject();
    QgsSnappingConfig cfg = projekt->snappingConfig();
    QStringList opis;
    for ( auto it = a.constBegin(); it != a.constEnd(); ++it )
    {
      const QString k = it.key();
      const QString v = it.value().toVariant().toString();
      opis << QStringLiteral( "%1=%2" ).arg( k, v );
      if ( k == QLatin1String( "enabled" ) )
        cfg.setEnabled( v.toInt() != 0 );
      else if ( k == QLatin1String( "mode" ) )
        cfg.setMode( static_cast<Qgis::SnappingMode>( v.toInt() ) );
      else if ( k == QLatin1String( "type" ) )
        cfg.setTypeFlag( static_cast<Qgis::SnappingTypes>( v.toInt() ) );
      else if ( k == QLatin1String( "tolerance" ) )
        cfg.setTolerance( v.toDouble() );
      else if ( k == QLatin1String( "unit" ) )
        cfg.setUnits( static_cast<Qgis::MapToolUnit>( v.toInt() ) );
      else if ( k == QLatin1String( "intersection-snapping" ) )
        cfg.setIntersectionSnapping( v.toInt() != 0 );
      else
        return QString();  // nieznany atrybut — nie zgadujemy
    }
    projekt->setSnappingConfig( cfg );
    return QStringLiteral( "przyciaganie: " ) + opis.join( QStringLiteral( ", " ) );
  }

  if ( typ == QLatin1String( "warstwa_istnieje" ) )
  {
    // SPRAWDZENIE, nie zakladanie. Warstwe robocza i tak zakladasz recznie
    // — modul stwierdza, ze jest, i zapisuje to w stemplu.
    const QString nazwa = krok.value( QStringLiteral( "nazwa" ) ).toString();
    const auto warstwy = projekt->mapLayersByName( nazwa );
    if ( warstwy.isEmpty() )
      return QString();
    return tr( "warstwa \"%1\" jest" ).arg( nazwa );
  }

  if ( typ == QLatin1String( "kontrola_klawiszy" ) )
  {
    // Czytamy i sprawdzamy klucze. `nazwa` zamiast `etykieta` daje pasek
    // PUSTY, a dowiadujesz sie o tym dopiero w terenie — wiec sprawdzamy
    // dokladnie to, czego szuka QfQuickCaptureBar.loadDefinitions().
    const QString plik = projekt->homePath() + QStringLiteral( "/" )
                         + krok.value( QStringLiteral( "nazwa" ) ).toString();
    QFile f( plik );
    if ( !f.open( QIODevice::ReadOnly ) )
      return QString();
    QJsonParseError blad;
    const QJsonDocument d = QJsonDocument::fromJson( f.readAll(), &blad );
    f.close();
    if ( blad.error != QJsonParseError::NoError )
      return QString();
    const QJsonArray kafle = d.object().value( QStringLiteral( "klawisze" ) ).toArray();
    if ( kafle.isEmpty() )
      return QString();
    int dobre = 0;
    for ( const QJsonValue &k : kafle )
    {
      const QJsonObject o = k.toObject();
      if ( !o.contains( QStringLiteral( "etykieta" ) )
           || !o.contains( QStringLiteral( "warstwa" ) ) )
        return QString();
      if ( projekt->mapLayersByName(
             o.value( QStringLiteral( "warstwa" ) ).toString() ).isEmpty() )
        return QString();
      ++dobre;
    }
    return tr( "kafli: %1, wszystkie wskazuja na istniejace warstwy" ).arg( dobre );
  }

  return QString();
}

QString Wyposazenie::cofnijKrok( QgsProject *projekt, const QJsonObject &krok ) const
{
  const QString typ = krok.value( QStringLiteral( "typ" ) ).toString();
  const QString grupa = krok.value( QStringLiteral( "grupa" ) ).toString();
  const QString klucz = krok.value( QStringLiteral( "klucz" ) ).toString();

  if ( typ == QLatin1String( "wlasciwosc" ) )
  {
    const QJsonValue w = krok.value( QStringLiteral( "wartosc_cofniecia" ) );
    if ( w.isUndefined() )
      return QString();
    projekt->writeEntry( grupa, QStringLiteral( "/" ) + klucz, w.toInt() );
    return QStringLiteral( "%1/%2 = %3" ).arg( grupa, klucz ).arg( w.toInt() );
  }

  if ( typ == QLatin1String( "wlasciwosc_warstwy" ) )
  {
    // Cofniecie listy warstw to lista PUSTA — nie usuwamy wpisu, bo brak
    // wpisu i pusta lista to dla QGIS-a co innego.
    projekt->writeEntry( grupa, QStringLiteral( "/" ) + klucz, QStringList() );
    return QStringLiteral( "%1/%2 = (pusto)" ).arg( grupa, klucz );
  }

  return QString();
}

QString Wyposazenie::mozeZdjac( const QString &modul ) const
{
  const QJsonObject m = opisModulu( modul );
  if ( m.isEmpty() )
    return tr( "nie ma takiego modulu w katalogu" );
  if ( !m.value( QStringLiteral( "odwracalny" ) ).toBool() )
    return tr( "nieodwracalny" );

  for ( const QJsonValue &k : m.value( QStringLiteral( "kroki" ) ).toArray() )
  {
    const QJsonObject o = k.toObject();
    const QString typ = o.value( QStringLiteral( "typ" ) ).toString();
    if ( !COFAMY.contains( typ ) )
      return tr( "kroku \"%1\" nie umiem cofnac" ).arg( typ );
    if ( typ == QLatin1String( "wlasciwosc" )
         && o.value( QStringLiteral( "wartosc_cofniecia" ) ).isUndefined() )
      return tr( "modul nie podaje, do czego wrocic" );
  }
  return QString();
}

QVariantMap Wyposazenie::zdejmij( QgsProject *projekt, const QString &modul ) const
{
  QVariantMap w;
  w[QStringLiteral( "ok" )] = false;

  const QString powod = mozeZdjac( modul );
  if ( !powod.isEmpty() )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie zdejmuje — %1." ).arg( powod );
    return w;
  }
  if ( !projekt || projekt->fileName().isEmpty() )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie ma otwartego projektu." );
    return w;
  }

  const QString znacznik =
    QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmmss" ) );
  const QString kopia = projekt->fileName() + QStringLiteral( ".przed_" ) + znacznik;
  if ( !QFile::copy( projekt->fileName(), kopia ) )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie udalo sie zrobic kopii — nic nie zmieniam." );
    return w;
  }
  w[QStringLiteral( "kopia" )] = kopia;

  const QJsonObject m = opisModulu( modul );
  QStringList zrobione;
  for ( const QJsonValue &k : m.value( QStringLiteral( "kroki" ) ).toArray() )
  {
    const QString opis = cofnijKrok( projekt, k.toObject() );
    if ( opis.isEmpty() )
    {
      w[QStringLiteral( "opis" )] = tr( "Cofniecie sie nie powiodlo — kopia: %1" ).arg( kopia );
      return w;
    }
    zrobione << opis;
  }

  if ( !projekt->write() )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie udalo sie zapisac projektu." );
    return w;
  }

  // Stempel kasujemy DOPIERO po udanym cofnieciu i zapisie.
  const QString baza = bazaProjektu( projekt );
  sqlite3 *db = nullptr;
  if ( !baza.isEmpty() && sqlite3_open( baza.toUtf8().constData(), &db ) == SQLITE_OK )
  {
    const QString sql = QStringLiteral( "DELETE FROM WF_WYPOSAZENIE WHERE modul='%1'" )
                          .arg( QString( modul ).replace( '\'', QLatin1String( "''" ) ) );
    sqlite3_exec( db, sql.toUtf8().constData(), nullptr, nullptr, nullptr );
    sqlite3_close( db );
  }

  w[QStringLiteral( "ok" )] = true;
  w[QStringLiteral( "opis" )] = tr( "Zdjete: %1" ).arg( zrobione.join( QStringLiteral( "; " ) ) );
  return w;
}

QVariantMap Wyposazenie::szkieletKlawiszy( QgsProject *projekt ) const
{
  QVariantMap w;
  w[QStringLiteral( "ok" )] = false;
  if ( !projekt || projekt->homePath().isEmpty() )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie ma otwartego projektu." );
    return w;
  }

  const QString plik = projekt->homePath()
                       + QStringLiteral( "/workfield_klawisze.json" );
  if ( QFileInfo::exists( plik ) )
  {
    w[QStringLiteral( "opis" )] =
      tr( "Plik juz jest — nie nadpisuje. Popraw go w edytorze." );
    return w;
  }

  // Wzorzec wskazuje na PIERWSZA warstwe wektorowa projektu, zeby kafel
  // dzialal od razu. Kafel wskazujacy na nieistniejaca warstwe daje pasek
  // pusty — a o tym dowiadujesz sie dopiero w terenie.
  QString pierwsza;
  const auto warstwy = projekt->mapLayers();
  for ( auto it = warstwy.constBegin(); it != warstwy.constEnd(); ++it )
  {
    if ( qobject_cast<QgsVectorLayer *>( it.value() ) )
    {
      pierwsza = it.value()->name();
      break;
    }
  }
  if ( pierwsza.isEmpty() )
  {
    w[QStringLiteral( "opis" )] = tr( "Projekt nie ma zadnej warstwy wektorowej." );
    return w;
  }

  const QString tresc = QStringLiteral(
    "{\n"
    "  \"_uwaga\": \"Klucz to 'etykieta', NIE 'nazwa'. 'warstwa' musi sie zgadzac \"\n"
    "               \"z nazwa warstwy w projekcie, inaczej pasek wstanie PUSTY.\",\n"
    "  \"klawisze\": [\n"
    "    { \"etykieta\": \"P\", \"warstwa\": \"%1\", \"kolor\": \"#4caf50\" }\n"
    "  ]\n"
    "}\n" ).arg( pierwsza );

  QFile f( plik );
  if ( !f.open( QIODevice::WriteOnly | QIODevice::Text ) )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie udalo sie zapisac pliku." );
    return w;
  }
  f.write( tresc.toUtf8() );
  f.close();

  w[QStringLiteral( "ok" )] = true;
  w[QStringLiteral( "opis" )] =
    tr( "Szkielet zapisany z jednym kaflem na warstwie \"%1\". "
        "Popraw go w edytorze, potem sprawdz jeszcze raz." ).arg( pierwsza );
  return w;
}

bool Wyposazenie::ostempluj( QgsProject *projekt, const QString &modul, int wersja ) const
{
  const QString baza = bazaProjektu( projekt );
  if ( baza.isEmpty() )
    return false;

  sqlite3 *db = nullptr;
  if ( sqlite3_open( baza.toUtf8().constData(), &db ) != SQLITE_OK )
  {
    if ( db )
      sqlite3_close( db );
    return false;
  }
  sqlite3_exec( db,
                "CREATE TABLE IF NOT EXISTS WF_WYPOSAZENIE ("
                "modul TEXT PRIMARY KEY, wersja INTEGER NOT NULL, "
                "data TEXT NOT NULL, zrodlo TEXT, przez TEXT)",
                nullptr, nullptr, nullptr );

  // `przez` odroznia teren od biura — przy pozniejszej diagnozie bedzie
  // wiadomo, gdzie modul zalozono.
  const QString sql = QStringLiteral(
    "INSERT INTO WF_WYPOSAZENIE (modul, wersja, data, zrodlo, przez) "
    "VALUES ('%1', %2, '%3', 'katalog w aplikacji', 'teren') "
    "ON CONFLICT(modul) DO UPDATE SET wersja=excluded.wersja, "
    "data=excluded.data, zrodlo=excluded.zrodlo, przez=excluded.przez" )
    .arg( QString( modul ).replace( '\'', QLatin1String( "''" ) ) )
    .arg( wersja )
    .arg( QDateTime::currentDateTime().toString( Qt::ISODate ) );

  const bool ok = sqlite3_exec( db, sql.toUtf8().constData(),
                                nullptr, nullptr, nullptr ) == SQLITE_OK;
  sqlite3_close( db );
  return ok;
}

QVariantMap Wyposazenie::zaloz( QgsProject *projekt, const QString &modul ) const
{
  QVariantMap w;
  w[QStringLiteral( "ok" )] = false;

  const QString powod = mozeZalozyc( modul );
  if ( !powod.isEmpty() )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie zakladam — %1." ).arg( powod );
    return w;
  }
  if ( !projekt || projekt->fileName().isEmpty() )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie ma otwartego projektu." );
    return w;
  }

  // Kopia ZAWSZE, tak samo jak w biurze. `projekt.qgs` to pol megabajta,
  // wiec jest tania — a bez niej nie ma z czego wrocic.
  const QString znacznik =
    QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmmss" ) );
  const QString kopia = projekt->fileName() + QStringLiteral( ".przed_" ) + znacznik;
  if ( !QFile::copy( projekt->fileName(), kopia ) )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie udalo sie zrobic kopii projektu — nic nie zmieniam." );
    return w;
  }
  w[QStringLiteral( "kopia" )] = kopia;

  const QJsonObject m = opisModulu( modul );
  QStringList zrobione;
  for ( const QJsonValue &k : m.value( QStringLiteral( "kroki" ) ).toArray() )
  {
    const QString opis = wykonajKrok( projekt, k.toObject() );
    if ( opis.isEmpty() )
    {
      w[QStringLiteral( "opis" )] =
        tr( "Krok sie nie powiodl — projekt NIE zapisany, kopia: %1" ).arg( kopia );
      return w;
    }
    zrobione << opis;
  }

  if ( !projekt->write() )
  {
    w[QStringLiteral( "opis" )] = tr( "Nie udalo sie zapisac projektu." );
    return w;
  }

  // Stempel DOPIERO po komplecie krokow i po udanym zapisie.
  const int wersja = m.value( QStringLiteral( "wersja" ) ).toInt();
  if ( !ostempluj( projekt, modul, wersja ) )
  {
    w[QStringLiteral( "opis" )] =
      tr( "Kroki wykonane i zapisane, ale STEMPEL SIE NIE ZAPISAL — "
          "aplikacja bedzie nadal mowic, ze modulu brak." );
    return w;
  }

  w[QStringLiteral( "ok" )] = true;
  w[QStringLiteral( "opis" )] = tr( "%1 v%2: %3" )
                                 .arg( m.value( QStringLiteral( "nazwa" ) ).toString() )
                                 .arg( wersja )
                                 .arg( zrobione.join( QStringLiteral( "; " ) ) );
  return w;
}
