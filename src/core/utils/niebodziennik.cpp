/***************************************************************************
                            niebodziennik.cpp - NieboDziennik
                              -------------------
  WorkField, 23.08.2026
 ***************************************************************************/

#include "niebodziennik.h"

#include "utils/narzedziaprojektu.h"

#include "positioning/qfgnsspositioninformation.h"
#include "positioning/qfntripsettings.h"
#include "qfield.h"

#include <QCoreApplication>
#include <QDebug>
#include <QFileInfo>
#include <QHash>
#include <QSettings>

#include <qgscoordinatereferencesystem.h>
#include <qgscoordinatetransform.h>
#include <qgsexception.h>
#include <qgsfeature.h>
#include <qgspointxy.h>
#include <qgsproject.h>
#include <qgsvectorlayer.h>

#include <cmath>
#include <limits>
#include <sqlite3.h>

namespace
{
  const char *SCHEMAT_SESJA =
    "CREATE TABLE IF NOT EXISTS NIEBO_SESJA ("
    " fid INTEGER PRIMARY KEY AUTOINCREMENT,"
    " ID_SESJI TEXT NOT NULL,"
    " START_UTC TEXT,"
    " KONIEC_UTC TEXT,"
    " ODBIORNIK TEXT,"
    " FIRMWARE TEXT,"
    " WYS_ANTENY REAL,"
    " MASKA_ELEWACJI INTEGER,"
    " PROG_CNO INTEGER,"
    " NTRIP_MOUNTPOINT TEXT,"
    " WERSJA_WF TEXT)";

  const char *SCHEMAT_EPOKA =
    "CREATE TABLE IF NOT EXISTS NIEBO_EPOKA ("
    " fid INTEGER PRIMARY KEY AUTOINCREMENT,"
    " ID_SESJI TEXT NOT NULL,"
    " ID_POMIARU TEXT NOT NULL,"
    " POWOD TEXT,"
    " WARSTWA TEXT,"
    " ID_OBIEKTU INTEGER,"
    " CZAS_UTC TEXT,"
    " SZEROKOSC REAL,"
    " DLUGOSC REAL,"
    " X_2180 REAL,"
    " Y_2180 REAL,"
    " H_ELIP REAL,"
    " HDOP REAL,"
    " PDOP REAL,"
    " VDOP REAL,"
    " N_UZYTYCH INTEGER,"
    " DOKLADNOSC_H REAL,"
    " PRN INTEGER,"
    " KONSTELACJA TEXT,"
    " AZYMUT REAL,"
    " ELEWACJA REAL,"
    " SNR INTEGER,"
    " UZYTY INTEGER)";

  // Indeks po ID_POMIARU: kazde pytanie do tych danych zaczyna sie od
  // "pokaz mi cale niebo tego pomiaru".
  const char *INDEKS_EPOKA =
    "CREATE INDEX IF NOT EXISTS NIEBO_EPOKA_pomiar ON NIEBO_EPOKA (ID_POMIARU)";

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

  void wykonaj( sqlite3 *baza, const char *sql )
  {
    sqlite3_exec( baza, sql, nullptr, nullptr, nullptr );
  }

  void zwiazDouble( sqlite3_stmt *z, int i, double wartosc )
  {
    if ( std::isnan( wartosc ) || std::isinf( wartosc ) )
      sqlite3_bind_null( z, i );
    else
      sqlite3_bind_double( z, i, wartosc );
  }

  void zwiazTekst( sqlite3_stmt *z, int i, const QString &wartosc )
  {
    if ( wartosc.isEmpty() )
      sqlite3_bind_null( z, i );
    else
      sqlite3_bind_text( z, i, wartosc.toUtf8().constData(), -1, SQLITE_TRANSIENT );
  }

} // namespace

NieboDziennik *NieboDziennik::instancja()
{
  static NieboDziennik *jedna = new NieboDziennik( qApp );
  return jedna;
}

NieboDziennik::NieboDziennik( QObject *parent )
  : QObject( parent )
{
  QSettings ustawienia;
  mRytm = ustawienia.value( QStringLiteral( "WorkField/nieboRytm" ), true ).toBool();
  mOkres = ustawienia.value( QStringLiteral( "WorkField/nieboOkres" ), 5 ).toInt();
  if ( mOkres < 1 )
    mOkres = 1;

  mZegar.setInterval( mOkres * 1000 );
  connect( &mZegar, &QTimer::timeout, this, &NieboDziennik::naRytm );

  // Nowy projekt = nowy data.gpkg. Sesja jest wlasnoscia projektu, nie
  // aplikacji — inaczej wpisy z dwoch zlecen wladowalyby sie do jednego pliku.
  connect( QgsProject::instance(), &QgsProject::readProject, this, &NieboDziennik::naZmianeProjektu );
  connect( QgsProject::instance(), &QgsProject::cleared, this, &NieboDziennik::naZmianeProjektu );
  connect( QgsProject::instance(), &QgsProject::layersAdded, this, [this]( const QList<QgsMapLayer *> & ) { podepnijWarstwy(); } );
}

NieboDziennik::~NieboDziennik()
{
  zamknijSesje();
}

void NieboDziennik::ustawPrzeszkode( const QString &tekst )
{
  if ( mPrzeszkoda == tekst )
    return;
  mPrzeszkoda = tekst;

  // WorkField 24.08.2026 — przeszkoda trafia TAKZE do logu systemowego.
  // Do tej pory powod milczenia dziennika widac bylo wylacznie w panelu
  // Niebo, ktorego nikt nie oglada w trakcie pracy: dzien zbierania danych
  // przepadl, zanim ktokolwiek zauwazyl. Teraz wystarczy:
  //     adb logcat | grep NIEBO:
  if ( tekst.isEmpty() )
    qInfo() << "NIEBO: zapis wznowiony";
  else
    qWarning() << "NIEBO:" << tekst;

  emit stanZmieniony();
}

void NieboDziennik::ustawRytm( bool wlaczony )
{
  if ( mRytm == wlaczony )
    return;
  mRytm = wlaczony;
  QSettings().setValue( QStringLiteral( "WorkField/nieboRytm" ), mRytm );
  if ( mRytm )
    mZegar.start();
  else
    mZegar.stop();
  emit stanZmieniony();
}

void NieboDziennik::ustawOkres( int sekundy )
{
  if ( sekundy < 1 )
    sekundy = 1;
  if ( mOkres == sekundy )
    return;
  mOkres = sekundy;
  QSettings().setValue( QStringLiteral( "WorkField/nieboOkres" ), mOkres );
  mZegar.setInterval( mOkres * 1000 );
  emit stanZmieniony();
}

void NieboDziennik::podepnij( QObject *zrodloPozycji )
{
  mZrodlo = zrodloPozycji;
  podepnijWarstwy();
  if ( mRytm )
    mZegar.start();
  emit stanZmieniony();
}

void NieboDziennik::naZmianeProjektu()
{
  // Zamykamy sesje POPRZEDNIEGO projektu, zanim baza zniknie z pola widzenia.
  zamknijSesje();
  mPodpieteWarstwy.clear();
  podepnijWarstwy();
  emit stanZmieniony();
}

void NieboDziennik::podepnijWarstwy()
{
  const auto warstwy = QgsProject::instance()->mapLayers();
  for ( auto it = warstwy.constBegin(); it != warstwy.constEnd(); ++it )
  {
    QgsVectorLayer *wektor = qobject_cast<QgsVectorLayer *>( it.value() );
    if ( !wektor || mPodpieteWarstwy.contains( it.key() ) )
      continue;

    mPodpieteWarstwy.insert( it.key() );
    connect( wektor, &QgsVectorLayer::committedFeaturesAdded, this,
             [this]( const QString &idWarstwy, const QgsFeatureList &obiekty ) {
               QgsMapLayer *warstwa = QgsProject::instance()->mapLayer( idWarstwy );
               if ( !warstwa || obiekty.isEmpty() )
                 return;

               const QString nazwa = warstwa->name();
               // Zalaczniki i nasze wlasne tabele nie sa pomiarem terenowym —
               // logowanie ich zrobiloby z dziennika kopie samego siebie.
               if ( nazwa.startsWith( QLatin1String( "ZAL_" ), Qt::CaseInsensitive )
                    || nazwa.startsWith( QLatin1String( "NIEBO_" ), Qt::CaseInsensitive ) )
                 return;

               // Przy zapisie wsadowym commit obejmuje kilka obiektow naraz.
               // Niebo jest wtedy jedno — wiazemy je z pierwszym obiektem
               // i tyle; udawanie osobnych migawek byloby falszem.
               const qint64 id = obiekty.first().id();

               // Zapis ODLOZONY. Sygnal leci w srodku commitu OGR-a, ktory
               // wciaz trzyma zamek na tym samym pliku — zapis wprost stalby
               // pod zamkiem i zamrozil interfejs na te sekundy. Kolejka
               // zdarzen odklada go o jeden obrot petli, czyli o milisekundy;
               // niebo przez ten czas sie nie zmienia.
               QMetaObject::invokeMethod(
                 this, [this, nazwa, id]() { zapisz( QStringLiteral( "obiekt" ), nazwa, id ); },
                 Qt::QueuedConnection );
             } );
  }
}

QString NieboDziennik::ustalBaze() const
{
  // WorkField 23.08.2026 — regula "gdzie wolno pisac dane nieodtwarzalne"
  // mieszka w JEDNYM miejscu: NarzedziaProjektu::plikDanych(). Wczesniej
  // stala tu jej kopia i rozjechalaby sie przy pierwszej zmianie ukladu
  // katalogow, cicho i w tylko jednym z dwoch miejsc.
  NarzedziaProjektu narzedzia;
  return narzedzia.plikDanych( QgsProject::instance() );
}

bool NieboDziennik::zapewnijSesje()
{
  const QString sciezka = ustalBaze();
  if ( sciezka.isEmpty() )
  {
    ustawPrzeszkode( tr( "Projekt nie ma pliku z danymi — nie ma dokąd pisać." ) );
    return false;
  }

  if ( mBazaUchwyt && mBaza == sciezka )
    return true;

  if ( mBazaUchwyt )
    zamknijSesje();

  if ( sqlite3_open( sciezka.toUtf8().constData(), &mBazaUchwyt ) != SQLITE_OK )
  {
    ustawPrzeszkode( tr( "Nie da się otworzyć %1" ).arg( QFileInfo( sciezka ).fileName() ) );
    if ( mBazaUchwyt )
    {
      sqlite3_close( mBazaUchwyt );
      mBazaUchwyt = nullptr;
    }
    return false;
  }

  // Plik jest jednoczesnie otwarty przez QGIS. Bez czekania na zamek kazdy
  // zapis w trakcie zapisu obiektu konczylby sie cicho bledem.
  sqlite3_busy_timeout( mBazaUchwyt, 4000 );

  wykonaj( mBazaUchwyt, SCHEMAT_SESJA );
  wykonaj( mBazaUchwyt, SCHEMAT_EPOKA );
  wykonaj( mBazaUchwyt, INDEKS_EPOKA );

  // Rejestrujemy w gpkg_contents jako 'attributes': dzieki temu QGIS je widzi
  // i — co wazniejsze — widzi je czyszczenie szablonu, ktore pyta wlasnie
  // gpkg_contents. Tabela niezarejestrowana pojechalaby do szablonu z cudzymi
  // logami w srodku.
  wykonaj( mBazaUchwyt,
           "INSERT OR IGNORE INTO gpkg_contents (table_name, data_type, identifier, description, last_change) "
           "VALUES ('NIEBO_SESJA','attributes','NIEBO_SESJA','WorkField: sesje logowania nieba', strftime('%Y-%m-%dT%H:%M:%fZ','now'))" );
  wykonaj( mBazaUchwyt,
           "INSERT OR IGNORE INTO gpkg_contents (table_name, data_type, identifier, description, last_change) "
           "VALUES ('NIEBO_EPOKA','attributes','NIEBO_EPOKA','WorkField: migawki nieba przy pomiarze', strftime('%Y-%m-%dT%H:%M:%fZ','now'))" );

  mBaza = sciezka;
  mIdSesji = QStringLiteral( "S_" ) + QDateTime::currentDateTimeUtc().toString( QStringLiteral( "yyyyMMdd_HHmmss" ) );
  mEpoki = 0;
  mWiersze = 0;
  mLicznikPomiaru = 0;

  QString odbiornik;
  QString mountpoint;
  double wysAnteny = 0.0;
  if ( mZrodlo )
  {
    odbiornik = mZrodlo->property( "deviceId" ).toString();
    wysAnteny = mZrodlo->property( "antennaHeight" ).toDouble();
    const QVariant ntrip = mZrodlo->property( "ntripSettings" );
    if ( ntrip.canConvert<QfNtripSettings>() )
      mountpoint = ntrip.value<QfNtripSettings>().mountPoint();
  }
  if ( odbiornik.isEmpty() )
    odbiornik = QStringLiteral( "wbudowany" );

  const int maska = QSettings().value( QStringLiteral( "WorkField/maskaElewacji" ), 0 ).toInt();

  sqlite3_stmt *z = nullptr;
  if ( sqlite3_prepare_v2( mBazaUchwyt,
                           "INSERT INTO NIEBO_SESJA (ID_SESJI, START_UTC, ODBIORNIK, WYS_ANTENY,"
                           " MASKA_ELEWACJI, NTRIP_MOUNTPOINT, WERSJA_WF) VALUES (?,?,?,?,?,?,?)",
                           -1, &z, nullptr )
       == SQLITE_OK )
  {
    zwiazTekst( z, 1, mIdSesji );
    zwiazTekst( z, 2, QDateTime::currentDateTimeUtc().toString( Qt::ISODateWithMs ) );
    zwiazTekst( z, 3, odbiornik );
    zwiazDouble( z, 4, wysAnteny );
    sqlite3_bind_int( z, 5, maska );
    zwiazTekst( z, 6, mountpoint );
    zwiazTekst( z, 7, Qfield::appVersionStr );
    sqlite3_step( z );
  }
  sqlite3_finalize( z );

  ustawPrzeszkode( QString() );
  emit stanZmieniony();
  return true;
}

int NieboDziennik::zapisz( const QString &powod, const QString &warstwa, qint64 idObiektu )
{
  if ( !mZrodlo )
  {
    ustawPrzeszkode( tr( "Dziennik nie jest podpięty do odbiornika." ) );
    return 0;
  }

  const QVariant surowa = mZrodlo->property( "positionInformation" );
  if ( !surowa.canConvert<QfGnssPositionInformation>() )
  {
    ustawPrzeszkode( tr( "Odbiornik nie podaje pozycji." ) );
    return 0;
  }

  const QfGnssPositionInformation info = surowa.value<QfGnssPositionInformation>();
  const QList<QgsSatelliteInfo> satelity = info.satellitesInView();

  // WorkField 24.08.2026 — brak GSV NIE blokuje juz zapisu.
  //
  // Do tej pory pusta lista satelitow konczyla metode, i to PRZED
  // zapewnijSesje(). Skutek w terenie: 24 sekundy zapisu z wbudowanego GPS-u,
  // potem cisza na caly dzien, bez jednego wpisu POWOD='obiekt' mimo
  // jedenastu nowych platow.
  //
  // Pozycja, DOKLADNOSC_H, N_UZYTYCH i czas nadal cos znacza. Zapisujemy
  // wiersz z pustymi polami satelitarnymi — wtedy w danych widac roznice
  // miedzy "nie mierzylem" a "mierzylem, ale nie wiem, co bylo na niebie".
  // Dzis oba stany wygladaja identycznie: brak wierszy.
  const bool bezGsv = satelity.isEmpty();
  if ( bezGsv )
    ustawPrzeszkode( tr( "Odbiornik nie podaje satelitów (brak depeszy GSV) — "
                         "zapisuję sam pomiar." ) );

  if ( !zapewnijSesje() )
    return 0;

  // Czas z ODBIORNIKA. Zegar telefonu potrafi skoczyc, a bez rzetelnego UTC
  // przepada powtarzalnosc dobowa (23 h 56 min), na ktorej stoi caly plan.
  QString czas = info.utcDateTime().isValid()
                   ? info.utcDateTime().toString( Qt::ISODateWithMs )
                   : QString();
  const bool czasZTelefonu = czas.isEmpty();
  if ( czasZTelefonu )
    czas = QDateTime::currentDateTimeUtc().toString( Qt::ISODateWithMs );

  double x2180 = std::numeric_limits<double>::quiet_NaN();
  double y2180 = std::numeric_limits<double>::quiet_NaN();
  if ( info.latitudeValid() && info.longitudeValid() )
  {
    static QgsCoordinateTransform przelicznik(
      QgsCoordinateReferenceSystem::fromEpsgId( 4326 ),
      QgsCoordinateReferenceSystem::fromEpsgId( 2180 ),
      QgsProject::instance()->transformContext() );
    try
    {
      const QgsPointXY punkt = przelicznik.transform( QgsPointXY( info.longitude(), info.latitude() ) );
      x2180 = punkt.x();
      y2180 = punkt.y();
    }
    catch ( const QgsCsException & )
    {
      // poza zasiegiem PUWG 1992 — zostaja same stopnie i to wystarczy
    }
  }

  mLicznikPomiaru++;
  const QString idPomiaru = QStringLiteral( "%1_%2" ).arg( mIdSesji ).arg( mLicznikPomiaru, 6, 10, QLatin1Char( '0' ) );

  sqlite3_stmt *z = nullptr;
  if ( sqlite3_prepare_v2( mBazaUchwyt,
                           "INSERT INTO NIEBO_EPOKA (ID_SESJI, ID_POMIARU, POWOD, WARSTWA, ID_OBIEKTU,"
                           " CZAS_UTC, SZEROKOSC, DLUGOSC, X_2180, Y_2180, H_ELIP,"
                           " HDOP, PDOP, VDOP, N_UZYTYCH, DOKLADNOSC_H,"
                           " PRN, KONSTELACJA, AZYMUT, ELEWACJA, SNR, UZYTY)"
                           " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                           -1, &z, nullptr )
       != SQLITE_OK )
  {
    ustawPrzeszkode( tr( "Tabela NIEBO_EPOKA nie przyjmuje zapisu." ) );
    return 0;
  }

  // Przyrostki POWODU sa skladane RAZ, przed petla: mowia o calym pomiarze,
  // nie o pojedynczym satelicie.
  QString powodPelny = powod;
  if ( czasZTelefonu )
    powodPelny += QStringLiteral( "/czas_telefonu" );
  if ( bezGsv )
    powodPelny += QStringLiteral( "/bez_gsv" );

  wykonaj( mBazaUchwyt, "BEGIN" );
  int zapisanych = 0;

  // Bez GSV robimy JEDEN obrot petli — wiersz opisuje pomiar, nie satelite.
  const int ile = bezGsv ? 1 : satelity.size();
  for ( int i = 0; i < ile; ++i )
  {
    sqlite3_reset( z );
    sqlite3_clear_bindings( z );

    zwiazTekst( z, 1, mIdSesji );
    zwiazTekst( z, 2, idPomiaru );
    zwiazTekst( z, 3, powodPelny );
    zwiazTekst( z, 4, warstwa );
    if ( idObiektu >= 0 )
      sqlite3_bind_int64( z, 5, idObiektu );
    zwiazTekst( z, 6, czas );
    zwiazDouble( z, 7, info.latitudeValid() ? info.latitude() : std::numeric_limits<double>::quiet_NaN() );
    zwiazDouble( z, 8, info.longitudeValid() ? info.longitude() : std::numeric_limits<double>::quiet_NaN() );
    zwiazDouble( z, 9, x2180 );
    zwiazDouble( z, 10, y2180 );
    zwiazDouble( z, 11, info.elevationValid() ? info.elevation() : std::numeric_limits<double>::quiet_NaN() );
    zwiazDouble( z, 12, info.hdop() );
    zwiazDouble( z, 13, info.pdop() );
    zwiazDouble( z, 14, info.vdop() );
    sqlite3_bind_int( z, 15, info.satellitesUsed() );
    zwiazDouble( z, 16, info.haccValid() ? info.hacc() : std::numeric_limits<double>::quiet_NaN() );

    // Bez GSV pola 17-22 zostaja NULL. sqlite3_clear_bindings() ustawil je
    // wyzej, wiec wystarczy ich NIE wiazac — pusty wiersz jest wtedy jawny,
    // a nie udawany zerami.
    if ( !bezGsv )
    {
      const QgsSatelliteInfo &sat = satelity.at( i );
      sqlite3_bind_int( z, 17, sat.id );
      zwiazTekst( z, 18, nazwaKonstelacji( sat.satType ) );
      zwiazDouble( z, 19, sat.azimuth );
      zwiazDouble( z, 20, sat.elevation );
      sqlite3_bind_int( z, 21, sat.signal < 0 ? 0 : sat.signal );
      sqlite3_bind_int( z, 22, sat.inUse ? 1 : 0 );
    }

    if ( sqlite3_step( z ) == SQLITE_DONE )
      zapisanych++;
  }
  sqlite3_finalize( z );

  // Koniec sesji dopisujemy przy KAZDYM zapisie. Aplikacja terenowa bywa
  // ubijana przez system i "zamkniecie na wyjsciu" po prostu nie nastapi.
  sqlite3_stmt *k = nullptr;
  if ( sqlite3_prepare_v2( mBazaUchwyt, "UPDATE NIEBO_SESJA SET KONIEC_UTC=? WHERE ID_SESJI=?", -1, &k, nullptr ) == SQLITE_OK )
  {
    zwiazTekst( k, 1, czas );
    zwiazTekst( k, 2, mIdSesji );
    sqlite3_step( k );
  }
  sqlite3_finalize( k );

  wykonaj( mBazaUchwyt, "COMMIT" );

  if ( zapisanych > 0 )
  {
    mEpoki++;
    mWiersze += zapisanych;
    ustawPrzeszkode( QString() );
    emit stanZmieniony();
  }
  return zapisanych;
}

int NieboDziennik::zapiszTeraz( const QString &powod )
{
  return zapisz( powod.isEmpty() ? QStringLiteral( "recznie" ) : powod, QString(), -1 );
}

void NieboDziennik::naRytm()
{
  if ( !mRytm || !mZrodlo )
    return;
  if ( !mZrodlo->property( "active" ).toBool() )
    return;
  zapisz( QStringLiteral( "rytm" ), QString(), -1 );
}

void NieboDziennik::zamknijSesje()
{
  if ( !mBazaUchwyt )
    return;

  sqlite3_stmt *k = nullptr;
  if ( !mIdSesji.isEmpty()
       && sqlite3_prepare_v2( mBazaUchwyt, "UPDATE NIEBO_SESJA SET KONIEC_UTC=? WHERE ID_SESJI=?", -1, &k, nullptr ) == SQLITE_OK )
  {
    zwiazTekst( k, 1, QDateTime::currentDateTimeUtc().toString( Qt::ISODateWithMs ) );
    zwiazTekst( k, 2, mIdSesji );
    sqlite3_step( k );
  }
  sqlite3_finalize( k );

  sqlite3_close( mBazaUchwyt );
  mBazaUchwyt = nullptr;
  mBaza.clear();
  mIdSesji.clear();
  emit stanZmieniony();
}
