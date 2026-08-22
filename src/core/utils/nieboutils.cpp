/***************************************************************************
                            nieboutils.cpp - NieboUtils
                              -------------------
  WorkField, 22.08.2026
 ***************************************************************************/

#include "nieboutils.h"
#include "positioning/qfgnsspositioninformation.h"

#include <QVariantMap>
#include <algorithm>
#include <cmath>

NieboUtils::NieboUtils( QObject *parent )
  : QObject( parent )
{
}

namespace
{
  // Litera konstelacji z NMEA. Odbiorniki, ktore jej nie podaja, zostawiaja
  // pusty znak — wtedy nie zgadujemy, tylko mowimy "?".
  QString nazwaKonstelacji( QChar litera )
  {
    switch ( litera.toLatin1() )
    {
      case 'G':
        return QStringLiteral( "GPS" );
      case 'R':
        return QStringLiteral( "GLONASS" );
      case 'E':
        return QStringLiteral( "Galileo" );
      case 'C':
        return QStringLiteral( "BeiDou" );
      case 'J':
        return QStringLiteral( "QZSS" );
      case 'S':
        return QStringLiteral( "SBAS" );
      default:
        return QStringLiteral( "?" );
    }
  }

  QList<QgsSatelliteInfo> wyciagnijSatelity( const QVariant &informacjaOPozycji )
  {
    if ( !informacjaOPozycji.canConvert<QfGnssPositionInformation>() )
      return QList<QgsSatelliteInfo>();

    return informacjaOPozycji.value<QfGnssPositionInformation>().satellitesInView();
  }
}

QVariantList NieboUtils::satelity( const QVariant &informacjaOPozycji ) const
{
  QVariantList wynik;

  const QList<QgsSatelliteInfo> lista = wyciagnijSatelity( informacjaOPozycji );
  for ( const QgsSatelliteInfo &sat : lista )
  {
    // Odbiornik, ktory nie zna polozenia satelity, wysyla puste pola. Kropka
    // w (0, 0) trafilaby na polnoc przy horyzoncie i klamala o przeszkodzie.
    if ( std::isnan( sat.elevation ) || std::isnan( sat.azimuth ) )
      continue;
    if ( sat.elevation < 0.0 || sat.elevation > 90.0 )
      continue;

    QVariantMap m;
    m.insert( QStringLiteral( "numer" ), sat.id );
    m.insert( QStringLiteral( "azymut" ), sat.azimuth );
    m.insert( QStringLiteral( "elewacja" ), sat.elevation );
    m.insert( QStringLiteral( "sygnal" ), sat.signal < 0 ? 0 : sat.signal );
    m.insert( QStringLiteral( "uzyty" ), sat.inUse );
    m.insert( QStringLiteral( "konstelacja" ), nazwaKonstelacji( sat.satType ) );
    wynik.append( m );
  }

  return wynik;
}

QVariantMap NieboUtils::podsumowanie( const QVariant &informacjaOPozycji, double progNiski ) const
{
  QVariantMap wynik;
  int widoczne = 0;
  int uzyte = 0;
  int nisko = 0;
  QList<int> snrUzytych;

  const QList<QgsSatelliteInfo> lista = wyciagnijSatelity( informacjaOPozycji );
  for ( const QgsSatelliteInfo &sat : lista )
  {
    if ( std::isnan( sat.elevation ) || std::isnan( sat.azimuth ) )
      continue;

    widoczne++;
    if ( sat.inUse )
    {
      uzyte++;
      if ( sat.signal > 0 )
        snrUzytych.append( sat.signal );
      if ( sat.elevation < progNiski )
        nisko++;
    }
  }

  // Mediana, nie srednia: jeden satelita tuz nad horyzontem z SNR 12 nie ma
  // przesuwac obrazu calego zestawu.
  int mediana = 0;
  if ( !snrUzytych.isEmpty() )
  {
    std::sort( snrUzytych.begin(), snrUzytych.end() );
    const int srodek = snrUzytych.size() / 2;
    mediana = snrUzytych.size() % 2 == 1
                ? snrUzytych.at( srodek )
                : ( snrUzytych.at( srodek - 1 ) + snrUzytych.at( srodek ) ) / 2;
  }

  wynik.insert( QStringLiteral( "widoczne" ), widoczne );
  wynik.insert( QStringLiteral( "uzyte" ), uzyte );
  wynik.insert( QStringLiteral( "medianaSnr" ), mediana );
  wynik.insert( QStringLiteral( "nisko" ), nisko );
  return wynik;
}
