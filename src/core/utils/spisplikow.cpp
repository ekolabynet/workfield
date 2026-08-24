/***************************************************************************
  spisplikow.cpp - SpisPlikow

 ---------------------
 WorkField 23.08.2026. Patrz spisplikow.h — tam jest powod istnienia.
 ***************************************************************************/

#include "spisplikow.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSet>
#include <QTextStream>

#include <algorithm>
#include <utility>

namespace
{
  //! Wersja formatu. Rosnie tylko wtedy, gdy stary spis przestaje sie czytac.
  const int WERSJA = 1;

  //! Rozdzielamy tabulatorem, bo w nazwach plikow spacje sa, a tabulatorow nie ma.
  const QChar ROZDZIELACZ = QLatin1Char( '\t' );
}

SpisPlikow::SpisPlikow( QObject *parent )
  : QObject( parent )
{
}

// --------------------------------------------------------------------- reguly

bool SpisPlikow::pomijac( const QString &nazwa )
{
  // Pliki robocze SQLite NIGDY nie ida do spisu ani do kopii. Ich obecnosc
  // znaczy "ktos ma baze otwarta" i jest informacja o CHWILI, a nie o danych
  // (DANE_workflow.md, "czego nie robic" nr 1).
  if ( nazwa.endsWith( QLatin1String( "-wal" ) ) || nazwa.endsWith( QLatin1String( "-shm" ) )
       || nazwa.endsWith( QLatin1String( "-journal" ) ) )
    return true;

  // Kopie zapasowe doposazenia to balast, nie dane (pulapka nr 6 z 21.08).
  if ( nazwa.contains( QLatin1String( ".bak_" ) ) )
    return true;

  return nazwa == QLatin1String( ".DS_Store" ) || nazwa == QLatin1String( "Thumbs.db" );
}

bool SpisPlikow::nieodtwarzalny( const QString &sciezkaWzgledna )
{
  const QString nazwa = sciezkaWzgledna.section( QLatin1Char( '/' ), -1 ).toLower();

  // Zdjecia z terenu — nieodtwarzalne w najczystszej postaci.
  if ( sciezkaWzgledna.contains( QLatin1String( "/DCIM/" ) )
       || sciezkaWzgledna.startsWith( QLatin1String( "DCIM/" ) ) )
    return true;

  if ( nazwa.endsWith( QLatin1String( ".gpkg" ) ) )
  {
    // Podklady i slownik sa do pobrania i do skopiowania z biblioteki —
    // ta sama regula co w NarzedziaProjektu::plikDanych().
    if ( nazwa == QLatin1String( "support.gpkg" ) || nazwa.startsWith( QLatin1String( "wf_wskazniki" ) ) )
      return false;
    return true;
  }

  static const QStringList rozszerzenia = {
    QStringLiteral( ".qgs" ), QStringLiteral( ".qgz" ),
    QStringLiteral( ".json" ), QStringLiteral( ".qml" ),
    QStringLiteral( ".csv" ), QStringLiteral( ".txt" ),
    QStringLiteral( ".md" ), QStringLiteral( ".jpg" ),
    QStringLiteral( ".jpeg" ), QStringLiteral( ".png" ),
    QStringLiteral( ".wav" ), QStringLiteral( ".m4a" ),
    QStringLiteral( ".mp4" ), QStringLiteral( ".zip" )
  };
  for ( const QString &r : rozszerzenia )
  {
    if ( nazwa.endsWith( r ) )
      return true;
  }
  return false;
}

QString SpisPlikow::sumaPliku( const QString &sciezka )
{
  QFile plik( sciezka );
  if ( !plik.open( QIODevice::ReadOnly ) )
    return QString();

  QCryptographicHash skrot( QCryptographicHash::Md5 );
  const bool ok = skrot.addData( &plik );
  plik.close();
  return ok ? QString::fromLatin1( skrot.result().toHex() ) : QString();
}

// ------------------------------------------------------------------ tworzenie

QVariantMap SpisPlikow::zrob( const QString &korzen,
                              const QString &katalogSpisow,
                              const QString &zakres,
                              bool sumyWszedzie ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );

  const QDir katalogKorzenia( korzen );
  if ( korzen.isEmpty() || !katalogKorzenia.exists() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma katalogu %1" ).arg( korzen ) );
    return wynik;
  }

  const QString docelowy = katalogSpisow.isEmpty()
                             ? katalogKorzenia.filePath( QStringLiteral( "spisy" ) )
                             : katalogSpisow;
  if ( !QDir().mkpath( docelowy ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się utworzyć katalogu %1" ).arg( docelowy ) );
    return wynik;
  }

  const bool tylkoDane = zakres != QLatin1String( "wszystko" );

  QList<Wpis> wpisy;
  qint64 sumaBajtow = 0;
  int policzonych = 0;
  int pominietych = 0;

  QDirIterator obchod( korzen,
                       QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden,
                       QDirIterator::Subdirectories );
  while ( obchod.hasNext() )
  {
    const QString pelna = obchod.next();
    const QFileInfo info( pelna );
    const QString nazwa = info.fileName();

    if ( pomijac( nazwa ) )
    {
      ++pominietych;
      continue;
    }

    const QString wzgledna = katalogKorzenia.relativeFilePath( pelna );
    if ( wzgledna.startsWith( QLatin1String( ".git/" ) ) || wzgledna.contains( QLatin1String( "/.git/" ) ) )
      continue;

    const bool wazny = nieodtwarzalny( wzgledna );
    if ( tylkoDane && !wazny )
    {
      ++pominietych;
      continue;
    }

    Wpis w;
    w.sciezka = wzgledna;
    w.bajty = info.size();
    w.czas = info.lastModified().toUTC().toString( Qt::ISODate );

    // Suma liczona TAM, GDZIE COS ZMIENIA SIE W MIEJSCU. Baza danych zmienia
    // sie w miejscu i zachowuje rozmiar — stad 21.08. Zdjecie raz zapisane
    // sie nie zmienia, wiec do wykrycia jego zniknieca wystarczy nazwa,
    // a przeliczanie czterech gigabajtow kosztowaloby minuty bez zysku.
    const bool baza = w.sciezka.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive );
    if ( sumyWszedzie || baza
         || w.sciezka.endsWith( QLatin1String( ".qgs" ), Qt::CaseInsensitive )
         || w.sciezka.endsWith( QLatin1String( ".qgz" ), Qt::CaseInsensitive )
         || w.sciezka.endsWith( QLatin1String( ".json" ), Qt::CaseInsensitive ) )
    {
      w.suma = sumaPliku( pelna );
      if ( !w.suma.isEmpty() )
        ++policzonych;
    }

    sumaBajtow += w.bajty;
    wpisy.append( w );
  }

  // POSORTOWANE. Bez tego `git diff` na dwoch spisach pokazuje przetasowanie
  // zamiast zmiany, a obchod katalogow nie ma ustalonej kolejnosci.
  std::sort( wpisy.begin(), wpisy.end(), []( const Wpis &a, const Wpis &b ) {
    return a.sciezka < b.sciezka;
  } );

  const QString znacznik = QDateTime::currentDateTime().toString( QStringLiteral( "yyyy-MM-dd_HHmm" ) );
  QString cel = QStringLiteral( "%1/spis_%2.txt" ).arg( docelowy, znacznik );
  int kolejny = 2;
  while ( QFile::exists( cel ) )
    cel = QStringLiteral( "%1/spis_%2_%3.txt" ).arg( docelowy, znacznik ).arg( kolejny++ );

  QFile plik( cel );
  if ( !plik.open( QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się zapisać %1" ).arg( cel ) );
    return wynik;
  }

  QTextStream strumien( &plik );
  strumien.setEncoding( QStringConverter::Utf8 );
  // Naglowek w liniach z `#`: czytelny dla czlowieka i niewidoczny dla
  // porownania, bo `git diff` pokaze go raz, na gorze.
  strumien << "# WorkField SPIS " << WERSJA << "\n";
  strumien << "# korzen\t" << QDir::toNativeSeparators( katalogKorzenia.absolutePath() ) << "\n";
  strumien << "# data\t" << QDateTime::currentDateTime().toString( Qt::ISODate ) << "\n";
  strumien << "# zakres\t" << ( tylkoDane ? "dane" : "wszystko" ) << "\n";
  strumien << "# plikow\t" << wpisy.size() << "\n";
  strumien << "# bajtow\t" << sumaBajtow << "\n";
  strumien << "# sciezka\tbajty\tzmieniony\tmd5\n";

  for ( const Wpis &w : std::as_const( wpisy ) )
  {
    strumien << w.sciezka << ROZDZIELACZ << w.bajty << ROZDZIELACZ
             << w.czas << ROZDZIELACZ << w.suma << "\n";
  }
  strumien.flush();
  plik.close();

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "sciezka" ), cel );
  wynik.insert( QStringLiteral( "plikow" ), wpisy.size() );
  wynik.insert( QStringLiteral( "bajtow" ), sumaBajtow );
  wynik.insert( QStringLiteral( "sum" ), policzonych );
  wynik.insert( QStringLiteral( "pominietych" ), pominietych );
  wynik.insert( QStringLiteral( "zakres" ), tylkoDane ? QStringLiteral( "dane" ) : QStringLiteral( "wszystko" ) );
  return wynik;
}

// -------------------------------------------------------------------- odczyt

QList<SpisPlikow::Wpis> SpisPlikow::czytaj( const QString &spis, QVariantMap *naglowek )
{
  QList<Wpis> wpisy;
  QFile plik( spis );
  if ( !plik.open( QIODevice::ReadOnly | QIODevice::Text ) )
    return wpisy;

  QTextStream strumien( &plik );
  strumien.setEncoding( QStringConverter::Utf8 );
  while ( !strumien.atEnd() )
  {
    const QString linia = strumien.readLine();
    if ( linia.isEmpty() )
      continue;

    if ( linia.startsWith( QLatin1Char( '#' ) ) )
    {
      if ( !naglowek )
        continue;
      const QStringList czesci = linia.mid( 1 ).trimmed().split( ROZDZIELACZ );
      if ( czesci.size() >= 2 )
        naglowek->insert( czesci.at( 0 ).trimmed(), czesci.at( 1 ).trimmed() );
      continue;
    }

    const QStringList czesci = linia.split( ROZDZIELACZ );
    if ( czesci.size() < 3 )
      continue;

    Wpis w;
    w.sciezka = czesci.at( 0 );
    w.bajty = czesci.at( 1 ).toLongLong();
    w.czas = czesci.at( 2 );
    w.suma = czesci.size() > 3 ? czesci.at( 3 ) : QString();
    wpisy.append( w );
  }
  plik.close();
  return wpisy;
}

QVariantList SpisPlikow::spisy( const QString &katalogSpisow ) const
{
  QVariantList wynik;
  QDir katalog( katalogSpisow );
  if ( !katalog.exists() )
    return wynik;

  const QStringList nazwy = katalog.entryList( QStringList() << QStringLiteral( "spis_*.txt" ),
                                               QDir::Files, QDir::Name | QDir::Reversed );
  for ( const QString &nazwa : nazwy )
  {
    const QString pelna = katalog.filePath( nazwa );

    // Naglowek czytamy z pierwszych kilku linii — spis z pieciudziesieciu
    // tysiecy plikow nie musi wjezdzac do pamieci, zeby pokazac date.
    QVariantMap naglowek;
    QFile plik( pelna );
    if ( plik.open( QIODevice::ReadOnly | QIODevice::Text ) )
    {
      QTextStream strumien( &plik );
      strumien.setEncoding( QStringConverter::Utf8 );
      for ( int i = 0; i < 10 && !strumien.atEnd(); ++i )
      {
        const QString linia = strumien.readLine();
        if ( !linia.startsWith( QLatin1Char( '#' ) ) )
          break;
        const QStringList czesci = linia.mid( 1 ).trimmed().split( ROZDZIELACZ );
        if ( czesci.size() >= 2 )
          naglowek.insert( czesci.at( 0 ).trimmed(), czesci.at( 1 ).trimmed() );
      }
      plik.close();
    }

    QVariantMap wpis;
    wpis.insert( QStringLiteral( "sciezka" ), pelna );
    wpis.insert( QStringLiteral( "nazwa" ), nazwa );
    wpis.insert( QStringLiteral( "data" ), naglowek.value( QStringLiteral( "data" ) ) );
    wpis.insert( QStringLiteral( "zakres" ), naglowek.value( QStringLiteral( "zakres" ) ) );
    wpis.insert( QStringLiteral( "korzen" ), naglowek.value( QStringLiteral( "korzen" ) ) );
    wpis.insert( QStringLiteral( "plikow" ), naglowek.value( QStringLiteral( "plikow" ) ).toInt() );
    wpis.insert( QStringLiteral( "bajtow" ), naglowek.value( QStringLiteral( "bajtow" ) ).toLongLong() );
    wynik.append( wpis );
  }
  return wynik;
}

// ----------------------------------------------------------------- porownanie

QVariantMap SpisPlikow::porownaj( const QString &spisA, const QString &spisB ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );

  QVariantMap naglowekA, naglowekB;
  const QList<Wpis> a = czytaj( spisA, &naglowekA );
  const QList<Wpis> b = czytaj( spisB, &naglowekB );

  if ( a.isEmpty() && b.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie udało się wczytać spisów." ) );
    return wynik;
  }

  QHash<QString, Wpis> mapaA;
  mapaA.reserve( a.size() );
  for ( const Wpis &w : a )
    mapaA.insert( w.sciezka, w );

  QVariantList nowe, zmienione, podejrzane;
  QSet<QString> widziane;
  qint64 bajtowNowych = 0;

  for ( const Wpis &w : b )
  {
    widziane.insert( w.sciezka );
    const auto it = mapaA.constFind( w.sciezka );
    if ( it == mapaA.constEnd() )
    {
      QVariantMap m;
      m.insert( QStringLiteral( "sciezka" ), w.sciezka );
      m.insert( QStringLiteral( "bajty" ), w.bajty );
      nowe.append( m );
      bajtowNowych += w.bajty;
      continue;
    }

    const Wpis &stary = it.value();
    const bool innaSuma = !stary.suma.isEmpty() && !w.suma.isEmpty() && stary.suma != w.suma;

    if ( stary.bajty == w.bajty && innaSuma )
    {
      // TA KATEGORIA ISTNIEJE Z POWODU 21.08: dwa pliki o identycznym
      // rozmiarze 2 609 152 B i roznej liczbie obiektow. Rozmiar nie
      // rozstrzyga i nigdy nie rozstrzygal — tylko wygladal, jakby
      // rozstrzygal. Wyciagamy to osobno, bo jest to jedyna zmiana,
      // ktorej NIE WIDAC w menedzerze plikow.
      QVariantMap m;
      m.insert( QStringLiteral( "sciezka" ), w.sciezka );
      m.insert( QStringLiteral( "bajty" ), w.bajty );
      m.insert( QStringLiteral( "sumaPrzed" ), stary.suma );
      m.insert( QStringLiteral( "sumaPo" ), w.suma );
      podejrzane.append( m );
      continue;
    }

    if ( stary.bajty != w.bajty || innaSuma )
    {
      QVariantMap m;
      m.insert( QStringLiteral( "sciezka" ), w.sciezka );
      m.insert( QStringLiteral( "bajtyPrzed" ), stary.bajty );
      m.insert( QStringLiteral( "bajtyPo" ), w.bajty );
      m.insert( QStringLiteral( "roznica" ), w.bajty - stary.bajty );
      zmienione.append( m );
    }
  }

  QVariantList zniknely;
  qint64 bajtowStraconych = 0;
  for ( const Wpis &w : a )
  {
    if ( widziane.contains( w.sciezka ) )
      continue;
    QVariantMap m;
    m.insert( QStringLiteral( "sciezka" ), w.sciezka );
    m.insert( QStringLiteral( "bajty" ), w.bajty );
    zniknely.append( m );
    bajtowStraconych += w.bajty;
  }

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "dataA" ), naglowekA.value( QStringLiteral( "data" ) ) );
  wynik.insert( QStringLiteral( "dataB" ), naglowekB.value( QStringLiteral( "data" ) ) );
  wynik.insert( QStringLiteral( "przedPlikow" ), a.size() );
  wynik.insert( QStringLiteral( "poPlikow" ), b.size() );
  wynik.insert( QStringLiteral( "nowe" ), nowe );
  wynik.insert( QStringLiteral( "zniknely" ), zniknely );
  wynik.insert( QStringLiteral( "zmienione" ), zmienione );
  wynik.insert( QStringLiteral( "podejrzane" ), podejrzane );
  wynik.insert( QStringLiteral( "bajtowNowych" ), bajtowNowych );
  wynik.insert( QStringLiteral( "bajtowStraconych" ), bajtowStraconych );
  return wynik;
}

// ---------------------------------------------------------------- sprawdzenie

QVariantMap SpisPlikow::sprawdz( const QString &spis, const QString &korzen, bool zSumami ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );

  QVariantMap naglowek;
  const QList<Wpis> oczekiwane = czytaj( spis, &naglowek );
  if ( oczekiwane.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Spis jest pusty albo nie da się go wczytać." ) );
    return wynik;
  }

  const QDir katalog( korzen );
  if ( !katalog.exists() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma katalogu %1" ).arg( korzen ) );
    return wynik;
  }

  QVariantList brakuje, innyRozmiar, innaSuma;
  QSet<QString> zeSpisu;
  int sprawdzonych = 0;

  for ( const Wpis &w : oczekiwane )
  {
    zeSpisu.insert( w.sciezka );
    const QString pelna = katalog.filePath( w.sciezka );
    const QFileInfo info( pelna );

    if ( !info.exists() )
    {
      QVariantMap m;
      m.insert( QStringLiteral( "sciezka" ), w.sciezka );
      m.insert( QStringLiteral( "bajty" ), w.bajty );
      brakuje.append( m );
      continue;
    }

    ++sprawdzonych;

    if ( info.size() != w.bajty )
    {
      QVariantMap m;
      m.insert( QStringLiteral( "sciezka" ), w.sciezka );
      m.insert( QStringLiteral( "oczekiwano" ), w.bajty );
      m.insert( QStringLiteral( "jest" ), info.size() );
      innyRozmiar.append( m );
      continue;   // rozmiar juz sie nie zgadza, suma nic nie doda
    }

    // Suma liczy sie tylko tam, gdzie spis ja ma. Brak sumy w spisie nie jest
    // bledem — to swiadoma oszczednosc przy zdjeciach (patrz zrob()).
    if ( zSumami && !w.suma.isEmpty() )
    {
      const QString teraz = sumaPliku( pelna );
      if ( !teraz.isEmpty() && teraz != w.suma )
      {
        QVariantMap m;
        m.insert( QStringLiteral( "sciezka" ), w.sciezka );
        m.insert( QStringLiteral( "oczekiwano" ), w.suma );
        m.insert( QStringLiteral( "jest" ), teraz );
        innaSuma.append( m );
      }
    }
  }

  // Nadmiarowe pliki nie sa bledem, ale warto je widziec: na kopii zapasowej
  // znacza, ze ktos do niej pisal, a kopia ma byc tylko do odczytu.
  QVariantList nadmiarowe;
  QDirIterator obchod( korzen, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories );
  while ( obchod.hasNext() )
  {
    const QString pelna = obchod.next();
    const QString wzgledna = katalog.relativeFilePath( pelna );
    if ( pomijac( QFileInfo( pelna ).fileName() ) )
      continue;
    if ( wzgledna.startsWith( QLatin1String( "spis_" ) ) || wzgledna.endsWith( QLatin1String( "KOPIA.json" ) ) )
      continue;
    if ( !zeSpisu.contains( wzgledna ) )
      nadmiarowe.append( wzgledna );
  }

  wynik.insert( QStringLiteral( "ok" ), brakuje.isEmpty() && innyRozmiar.isEmpty() && innaSuma.isEmpty() );
  wynik.insert( QStringLiteral( "wSpisie" ), oczekiwane.size() );
  wynik.insert( QStringLiteral( "sprawdzonych" ), sprawdzonych );
  wynik.insert( QStringLiteral( "brakuje" ), brakuje );
  wynik.insert( QStringLiteral( "innyRozmiar" ), innyRozmiar );
  wynik.insert( QStringLiteral( "innaSuma" ), innaSuma );
  wynik.insert( QStringLiteral( "nadmiarowe" ), nadmiarowe );
  wynik.insert( QStringLiteral( "zSumami" ), zSumami );
  wynik.insert( QStringLiteral( "data" ), naglowek.value( QStringLiteral( "data" ) ) );
  return wynik;
}
