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
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <qgsproject.h>
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
