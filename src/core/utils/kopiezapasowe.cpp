/***************************************************************************
  kopiezapasowe.cpp - KopieZapasowe

 ---------------------
 WorkField 24.08.2026. Patrz kopiezapasowe.h — tam sa powody.
 ***************************************************************************/

#include "kopiezapasowe.h"
#include "spisplikow.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStorageInfo>
#include <QThread>
#include <QUuid>

#include <sqlite3.h>

#ifndef Q_OS_WIN
#include <unistd.h>
#endif

namespace
{
  const QLatin1String STEMPEL_NOSNIKA( "WF_NOSNIK.json" );
  const QLatin1String OPIS_MIGAWKI( "KOPIA.json" );

  QJsonObject czytajJson( const QString &sciezka )
  {
    QFile plik( sciezka );
    if ( !plik.open( QIODevice::ReadOnly ) )
      return QJsonObject();
    const QJsonDocument dokument = QJsonDocument::fromJson( plik.readAll() );
    plik.close();
    return dokument.object();
  }

  bool zapiszJson( const QString &sciezka, const QJsonObject &tresc )
  {
    QFile plik( sciezka );
    if ( !plik.open( QIODevice::WriteOnly | QIODevice::Truncate ) )
      return false;
    plik.write( QJsonDocument( tresc ).toJson( QJsonDocument::Indented ) );
    plik.close();
    return true;
  }

  /**
   * Czy da sie tu zrobic twarde dowiazanie. SPRAWDZAMY, NIE ZAKLADAMY:
   * pendrive'y wychodza z fabryki na exFAT, gdzie dowiazan nie ma, a system
   * plikow z nazwy nie zawsze mowi prawde (sterowniki, montowania sieciowe).
   */
  bool dowiazaniaDzialaja( const QString &katalog )
  {
#ifdef Q_OS_WIN
    Q_UNUSED( katalog )
    return false;
#else
    const QString proba = katalog + QStringLiteral( "/.wf_proba_dowiazania" );
    const QString cel = katalog + QStringLiteral( "/.wf_proba_dowiazania2" );
    QFile::remove( proba );
    QFile::remove( cel );

    QFile plik( proba );
    if ( !plik.open( QIODevice::WriteOnly ) )
      return false;
    plik.write( "x" );
    plik.close();

    const bool udalo = ::link( proba.toUtf8().constData(), cel.toUtf8().constData() ) == 0;
    QFile::remove( proba );
    QFile::remove( cel );
    return udalo;
#endif
  }

  //! Zrzuca dziennik WAL do pliku glownego. Zwraca false, gdy sie nie udalo —
  //! zwykle dlatego, ze baze trzyma otwarta ktos inny (QGIS na komputerze).
  bool zamknijDziennik( const QString &gpkg )
  {
    sqlite3 *baza = nullptr;
    if ( sqlite3_open( gpkg.toUtf8().constData(), &baza ) != SQLITE_OK )
    {
      if ( baza )
        sqlite3_close( baza );
      return false;
    }
    sqlite3_busy_timeout( baza, 4000 );
    const int rc = sqlite3_exec( baza, "PRAGMA wal_checkpoint(TRUNCATE)", nullptr, nullptr, nullptr );
    sqlite3_close( baza );
    return rc == SQLITE_OK;
  }

  //! `PRAGMA quick_check` na skopiowanej bazie.
  bool bazaZdrowa( const QString &gpkg )
  {
    sqlite3 *baza = nullptr;
    if ( sqlite3_open_v2( gpkg.toUtf8().constData(), &baza, SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
    {
      if ( baza )
        sqlite3_close( baza );
      return false;
    }

    bool ok = false;
    sqlite3_stmt *zapytanie = nullptr;
    if ( sqlite3_prepare_v2( baza, "PRAGMA quick_check", -1, &zapytanie, nullptr ) == SQLITE_OK
         && sqlite3_step( zapytanie ) == SQLITE_ROW )
    {
      const QString odpowiedz = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( zapytanie, 0 ) ) );
      ok = odpowiedz.compare( QLatin1String( "ok" ), Qt::CaseInsensitive ) == 0;
    }
    sqlite3_finalize( zapytanie );
    sqlite3_close( baza );
    return ok;
  }

  QString sumaMd5( const QString &sciezka )
  {
    QFile plik( sciezka );
    if ( !plik.open( QIODevice::ReadOnly ) )
      return QString();
    QCryptographicHash skrot( QCryptographicHash::Md5 );
    const bool ok = skrot.addData( &plik );
    plik.close();
    return ok ? QString::fromLatin1( skrot.result().toHex() ) : QString();
  }

  QString ludzkieBajty( qint64 b )
  {
    if ( b >= 1073741824LL )
      return QStringLiteral( "%1 GB" ).arg( b / 1073741824.0, 0, 'f', 1 );
    if ( b >= 1048576LL )
      return QStringLiteral( "%1 MB" ).arg( b / 1048576.0, 0, 'f', 0 );
    return QStringLiteral( "%1 kB" ).arg( b / 1024.0, 0, 'f', 0 );
  }

  QString ludzkiCzas( qint64 sekund )
  {
    if ( sekund < 90 )
      return QObject::tr( "%1 s" ).arg( sekund );
    if ( sekund < 5400 )
      return QObject::tr( "%1 min" ).arg( ( sekund + 30 ) / 60 );
    const qint64 godzin = sekund / 3600;
    const qint64 minut = ( sekund % 3600 + 30 ) / 60;
    return QObject::tr( "%1 h %2 min" ).arg( godzin ).arg( minut );
  }

  /**
   * Przepisuje czas modyfikacji ze zrodla na kopie.
   *
   * KONIECZNE, A NIE KOSMETYCZNE. `QFile::copy` NIE zachowuje mtime — kopia
   * dostaje czas "teraz". Sprawdzone doswiadczalnie 24.08.2026:
   *
   *     mtime zrodla: 2026-08-24T05:28:02
   *     mtime celu  : 2026-08-24T06:28:02
   *
   * Bez tego twarde dowiazania NIE ZADZIALALYBY NIGDY: warunek dowiazania
   * porownuje rozmiar I czas pliku w poprzedniej migawce z plikiem zrodlowym,
   * a czas nigdy by sie nie zgadzal. Kazda migawka bylaby pelna kopia —
   * dokladnie to, czego mieliśmy uniknac, i bez zadnego objawu poza dyskiem
   * zapelniajacym sie w tydzien zamiast w rok.
   */
  bool przepiszCzas( const QString &zrodlo, const QString &cel )
  {
    const QDateTime czas = QFileInfo( zrodlo ).lastModified();
    if ( !czas.isValid() )
      return false;
    QFile plik( cel );
    if ( !plik.open( QIODevice::ReadWrite ) )
      return false;
    const bool ok = plik.setFileTime( czas, QFileDevice::FileModificationTime );
    plik.close();
    return ok;
  }

  /**
   * Czy to ten sam plik co w poprzedniej migawce.
   *
   * Czas porownujemy z dokladnoscia DWOCH SEKUND, nie co do nanosekundy:
   * ext4 trzyma nanosekundy, exFAT dwie sekundy, a NTFS setki nanosekund.
   * Porownanie dokladne odrzucaloby pliki identyczne tylko dlatego, ze
   * przejechaly przez system plikow o grubszej podzialce.
   */
  bool tenSamPlik( const QFileInfo &a, const QFileInfo &b )
  {
    if ( a.size() != b.size() )
      return false;
    const qint64 ra = a.lastModified().toSecsSinceEpoch();
    const qint64 rb = b.lastModified().toSecsSinceEpoch();
    return qAbs( ra - rb ) <= 2;
  }

  //! Pliki, ktore nigdy nie ida do kopii — ta sama regula co w spisie.
  bool pomijac( const QString &nazwa )
  {
    return nazwa.endsWith( QLatin1String( "-wal" ) ) || nazwa.endsWith( QLatin1String( "-shm" ) )
           || nazwa.endsWith( QLatin1String( "-journal" ) ) || nazwa.contains( QLatin1String( ".bak_" ) );
  }
}

// =====================================================================
//  Robotnik — cala robota dzieje sie w osobnym watku.
// =====================================================================

class RobotnikKopii : public QObject
{
    Q_OBJECT

  public:
    void przerwij() { mPrzerwane = true; }

  public slots:
    void pracuj( const QString &korzen, const QString &zakres, const QString &nosnik )
    {
      mPrzerwane = false;
      QVariantMap wynik;
      wynik.insert( QStringLiteral( "ok" ), false );

      const QDir katalogKorzenia( korzen );
      if ( !katalogKorzenia.exists() )
      {
        wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma katalogu %1" ).arg( korzen ) );
        emit skonczone( wynik );
        return;
      }

      const bool tylkoDane = zakres != QLatin1String( "wszystko" );

      // ---------------------------------------------------------- 1. co kopiujemy
      emit postep( 0, tr( "Szukam plików…" ) );
      QStringList doKopiowania;
      QHash<QString, qint64> rozmiary;
      qint64 razemBajtow = 0;
      {
        QDirIterator obchod( korzen, QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden,
                             QDirIterator::Subdirectories );
        while ( obchod.hasNext() )
        {
          const QString pelna = obchod.next();
          const QFileInfo info( pelna );
          if ( pomijac( info.fileName() ) )
            continue;
          const QString wzgledna = katalogKorzenia.relativeFilePath( pelna );
          if ( wzgledna.contains( QLatin1String( "/.git/" ) ) || wzgledna.startsWith( QLatin1String( ".git/" ) ) )
            continue;
          if ( tylkoDane && !SpisPlikow::nieodtwarzalny( wzgledna ) )
            continue;
          doKopiowania.append( wzgledna );
          rozmiary.insert( wzgledna, info.size() );
          razemBajtow += info.size();
        }
      }
      doKopiowania.sort();

      // ---------------------------------------------------- 2. katalog migawki
      const QString baza = nosnik + QStringLiteral( "/WorkField_kopie" );
      if ( !QDir().mkpath( baza ) )
      {
        wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się pisać na %1" ).arg( nosnik ) );
        emit skonczone( wynik );
        return;
      }

      // Poprzednia migawka — do niej beda szly twarde dowiazania.
      //
      // TEGO SAMEGO ZAKRESU, a nie po prostu najnowsza. Migawka "wszystko"
      // po migawce "dane" nie znalazlaby w niej podkladow i skopiowalaby je
      // od nowa — kilkanascie gigabajtow za mieszanie zakresow. Nazwa niesie
      // zakres na koncu, wiec wystarczy zawezic wzorzec.
      // I KOMPLETNEJ, a nie po prostu najnowszej. To kosztowalo Piotra
      // 24.08.2026 blisko cztery godziny i drugie 89 GB na dysku:
      //
      //   snap_0511_wszystko      31469 plikow, kompletna
      //   snap_0844_wszystko          6 plikow, PRZERWANA
      //   snap_0844_wszystko_2       33 pliki,  PRZERWANA
      //   snap_0847_wszystko      31469 plikow — bo za podstawe wzial
      //                           te 33 pliki i 31438 nie mialo odpowiednika
      //
      // Braloem najnowsza po nazwie, nie pytajac, czy w ogole cos w niej jest.
      // Przerwana migawka jest gorsza niz zadna: udaje punkt odniesienia.
      // Wiec cofamy sie po liscie, az trafimy na taka, ktora ma KOPIA.json
      // i nie jest oznaczona jako przerwana. Brak KOPIA.json znaczy, ze
      // aplikacja nie doszla do konca — to tez migawka do pominiecia.
      const QString przyrostek = tylkoDane ? QStringLiteral( "dane" ) : QStringLiteral( "wszystko" );
      QString poprzednia;
      QStringList pominieteMigawki;
      {
        const QStringList nazwy = QDir( baza ).entryList(
          QStringList() << QStringLiteral( "snap_*_%1" ).arg( przyrostek )
                        << QStringLiteral( "snap_*_%1_*" ).arg( przyrostek ),
          QDir::Dirs, QDir::Name );
        for ( int i = nazwy.size() - 1; i >= 0; --i )
        {
          const QString kandydat = baza + QLatin1Char( '/' ) + nazwy.at( i );
          const QString opisKandydata = kandydat + QLatin1Char( '/' ) + OPIS_MIGAWKI;
          if ( !QFileInfo::exists( opisKandydata ) )
          {
            pominieteMigawki.append( tr( "%1 (bez KOPIA.json — nie doszła do końca)" ).arg( nazwy.at( i ) ) );
            continue;
          }
          if ( czytajJson( opisKandydata ).value( QStringLiteral( "przerwane" ) ).toBool() )
          {
            pominieteMigawki.append( tr( "%1 (przerwana)" ).arg( nazwy.at( i ) ) );
            continue;
          }
          poprzednia = kandydat;
          break;
        }
      }

      const QString znacznik = QDateTime::currentDateTime().toString( QStringLiteral( "yyyy-MM-dd_HHmm" ) );
      QString migawka = QStringLiteral( "%1/snap_%2_%3" ).arg( baza, znacznik, przyrostek );
      int kolejna = 2;
      while ( QDir( migawka ).exists() )
        migawka = QStringLiteral( "%1/snap_%2_%3_%4" ).arg( baza, znacznik, przyrostek ).arg( kolejna++ );
      QDir().mkpath( migawka );

      const bool dowiazania = dowiazaniaDzialaja( migawka );

      // ---------------------------------------------------------- 3. kopiowanie
      int skopiowanych = 0;
      int dowiazanych = 0;
      int pominietych = 0;

      /*
       * DLACZEGO NIC SIE NIE DOWIAZALO — liczone od razu, nie zgadywane potem.
       *
       * 24.08.2026 Piotr zrobil trzy migawki i wszystkie wyszly pelne. Zeby
       * odpowiedziec, dlaczego, trzeba bylo puscic osobny program na sztucznym
       * drzewie i dopytac go, czy przebudowal aplikacje. Program, ktory pisze
       * "dowiazanych: 0" i na tym konczy, kaze czlowiekowi zgadywac miedzy
       * czterema roznymi awariami, z ktorych kazda ma inna naprawe.
       *
       * Wiec liczymy powody. Ktory z nich wygra, ten trafia do KOPIA.json
       * zdaniem po polsku.
       */
      int bezOdpowiednika = 0;  // pliku nie bylo w poprzedniej migawce
      int innyRozmiar = 0;      // byl, ale ma inny rozmiar — naprawde sie zmienil
      int innyCzas = 0;         // ten sam rozmiar, inny czas — TO jest objaw braku mtime
      int linkOdmowil = 0;      // wszystko sie zgadzalo, a ::link nie dal rady
      QStringList bledy;
      QJsonArray bazyOpis;

      const int ile = doKopiowania.size();

      // POSTEP LICZONY W BAJTACH, NIE W PLIKACH.
      //
      // W tym drzewie jeden plik to raz 200 kB bazy, raz 70 MB mozaiki NMT.
      // Procent liczony z liczby plikow nie mowi nic o czasie, a czas z niego
      // wyliczony bylby zmysleniem. Czas pozostaly szacujemy z proporcji
      // przerobionych bajtow do calosci — i przez to sam sie poprawia, kiedy
      // zmienia sie proporcja plikow kopiowanych do dowiazywanych.
      qint64 zrobionychBajtow = 0;
      QElapsedTimer zegar;
      zegar.start();
      qint64 ostatniMeldunek = 0;

      for ( int i = 0; i < ile; ++i )
      {
        if ( mPrzerwane )
          break;

        const QString wzgledna = doKopiowania.at( i );
        const QString zrodlo = katalogKorzenia.filePath( wzgledna );
        const QString cel = migawka + QLatin1Char( '/' ) + wzgledna;

        // Meldunek co pol sekundy, a nie co N plikow: przy plikach roznej
        // wielkosci "co 25 plikow" znaczy raz co mgnienie, raz co minute.
        const qint64 uplynelo = zegar.elapsed();
        if ( uplynelo - ostatniMeldunek > 500 || i == 0 )
        {
          ostatniMeldunek = uplynelo;
          const int procent = razemBajtow > 0
                                ? static_cast<int>( ( zrobionychBajtow * 100 ) / razemBajtow )
                                : 0;

          QString opis = tr( "%1 z %2 plików · %3 z %4" )
                           .arg( i ).arg( ile )
                           .arg( ludzkieBajty( zrobionychBajtow ), ludzkieBajty( razemBajtow ) );

          // Predkosc i czas dopiero po kilku sekundach — wczesniejsze liczby
          // sa losowe i tylko wprowadzalyby w blad.
          if ( uplynelo > 4000 && zrobionychBajtow > 0 )
          {
            const double naSekunde = zrobionychBajtow * 1000.0 / uplynelo;
            const qint64 zostalo = razemBajtow - zrobionychBajtow;
            opis += tr( " · %1/s · zostało ~%2" )
                      .arg( ludzkieBajty( static_cast<qint64>( naSekunde ) ),
                            ludzkiCzas( static_cast<qint64>( zostalo / qMax( 1.0, naSekunde ) ) ) );
          }
          emit postep( procent, opis );
        }

        zrobionychBajtow += rozmiary.value( wzgledna, 0 );

        QDir().mkpath( QFileInfo( cel ).absolutePath() );

        const bool toBaza = wzgledna.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive );

        // --- BAZY: najpierw checkpoint, potem kopia, potem quick_check.
        if ( toBaza )
        {
          if ( !zamknijDziennik( zrodlo ) )
          {
            // NAZWANA I POMINIETA. Kopia bazy, ktorej ktos uzywa, otwiera sie
            // i klamie — a to jest najgorszy rodzaj awarii, bo nie ma objawu.
            bledy.append( tr( "%1 — ktoś ma tę bazę otwartą, pominięta" ).arg( wzgledna ) );
            ++pominietych;
            continue;
          }
          if ( !QFile::copy( zrodlo, cel ) )
          {
            bledy.append( tr( "%1 — kopiowanie nie powiodło się" ).arg( wzgledna ) );
            ++pominietych;
            continue;
          }
          przepiszCzas( zrodlo, cel );
          ++skopiowanych;

          QJsonObject opisBazy;
          opisBazy.insert( QStringLiteral( "plik" ), wzgledna );
          const bool zdrowa = bazaZdrowa( cel );
          opisBazy.insert( QStringLiteral( "quick_check" ), zdrowa ? QStringLiteral( "ok" ) : QStringLiteral( "BLAD" ) );
          if ( zdrowa )
          {
            opisBazy.insert( QStringLiteral( "md5" ), sumaMd5( cel ) );
          }
          else
          {
            // Kopia, ktora nie przeszla sprawdzenia, jest kasowana. Lepiej
            // brak kopii niz kopia, ktorej nie da sie odtworzyc.
            QFile::remove( cel );
            --skopiowanych;
            ++pominietych;
            bledy.append( tr( "%1 — kopia nie przeszła sprawdzenia i została skasowana" ).arg( wzgledna ) );
          }
          bazyOpis.append( opisBazy );
          continue;
        }

        // --- RESZTA: twarde dowiazanie, gdy plik jest identyczny jak
        //     w poprzedniej migawce; inaczej kopia.
        bool zrobione = false;
        if ( dowiazania && !poprzednia.isEmpty() )
        {
          const QString stary = poprzednia + QLatin1Char( '/' ) + wzgledna;
          const QFileInfo infoStary( stary );
          const QFileInfo infoZrodlo( zrodlo );
          if ( !infoStary.exists() )
          {
            ++bezOdpowiednika;
          }
          else if ( infoStary.size() != infoZrodlo.size() )
          {
            ++innyRozmiar;
          }
          else if ( !tenSamPlik( infoStary, infoZrodlo ) )
          {
            // Rozmiar ten sam, czas inny. Przy danych z terenu, ktorych nikt
            // nie ruszal, to prawie zawsze znaczy jedno: poprzednia migawka
            // ma czasy z chwili KOPIOWANIA, a nie z pliku zrodlowego.
            ++innyCzas;
          }
          else
          {
#ifndef Q_OS_WIN
            if ( ::link( stary.toUtf8().constData(), cel.toUtf8().constData() ) == 0 )
            {
              ++dowiazanych;
              zrobione = true;
            }
            else
            {
              ++linkOdmowil;
            }
#endif
          }
        }

        if ( !zrobione )
        {
          if ( QFile::copy( zrodlo, cel ) )
          {
            // Bez tego nastepna migawka nie rozpoznalaby tego pliku jako
            // niezmienionego i skopiowalaby go od nowa.
            przepiszCzas( zrodlo, cel );
            ++skopiowanych;
          }
          else
          {
            bledy.append( tr( "%1 — nie skopiowano" ).arg( wzgledna ) );
            ++pominietych;
          }
        }
      }

      // ------------------------------- 3b. dlaczego dowiazan bylo tyle, ile bylo
      //
      // Zdanie po polsku, nie cztery liczby do zinterpretowania. Liczby tez
      // zostaja — ale czlowiek ma dostac odpowiedz, a nie material na nia.
      QString powodDowiazan;
      // Pominiete migawki mowimy ZAWSZE, niezaleznie od reszty — czlowiek ma
      // prawo wiedziec, ze na nosniku lezy cos, co wyglada jak kopia, a nie
      // nadaje sie na podstawe.
      QString oPominietych;
      if ( !pominieteMigawki.isEmpty() )
      {
        oPominietych = tr( " Pominięto jako podstawę: %1." )
                         .arg( pominieteMigawki.join( QStringLiteral( ", " ) ) );
      }

      if ( poprzednia.isEmpty() )
      {
        powodDowiazan = pominieteMigawki.isEmpty()
                          ? tr( "To pierwsza migawka tego zakresu — nie było z czym porównywać. "
                                "Następna powinna być dużo szybsza." )
                          : tr( "Nie było kompletnej migawki, do której dałoby się dowiązać — "
                                "wszystkie wcześniejsze są przerwane albo niedokończone." );
      }
      else if ( !dowiazania )
      {
        powodDowiazan = tr( "Ten system plików nie obsługuje twardych dowiązań (tak mają pendrive'y "
                            "fabrycznie sformatowane na exFAT lub FAT32). Każda migawka będzie pełna. "
                            "Pomaga tylko przeformatowanie nośnika na ext4." );
      }
      else if ( dowiazanych > 0 )
      {
        powodDowiazan = tr( "Dowiązania działają — %1 plików nie zajęło miejsca po raz drugi." )
                          .arg( dowiazanych );
      }
      else if ( innyCzas > bezOdpowiednika && innyCzas > innyRozmiar )
      {
        // NAJWAZNIEJSZY PRZYPADEK. Wyglada jak awaria kopiowania, a jest
        // wlasciwoscia POPRZEDNIEJ migawki — tej zrobionej przed poprawka.
        powodDowiazan = tr( "Nic się nie dowiązało, bo poprzednia migawka (%1) ma czasy plików "
                            "z chwili kopiowania zamiast z oryginałów — %2 plików różni się tylko czasem, "
                            "przy zgodnym rozmiarze. Tak wygląda migawka zrobiona przed poprawką z 24.08.2026. "
                            "Ta migawka ma już czasy poprawne, więc NASTĘPNA się dowiąże. "
                            "Można też naprawić starą: „Napraw czasy w migawce”." )
                          .arg( QFileInfo( poprzednia ).fileName() )
                          .arg( innyCzas );
      }
      else if ( linkOdmowil > 0 )
      {
        powodDowiazan = tr( "Pliki się zgadzały, ale system odmówił zrobienia dowiązania (%1 razy). "
                            "Zwykle znaczy to brak miejsca na i-węzły albo nośnik zamontowany tylko do odczytu." )
                          .arg( linkOdmowil );
      }
      else if ( bezOdpowiednika > innyRozmiar )
      {
        powodDowiazan = tr( "Nic się nie dowiązało, bo %1 plików nie ma w poprzedniej migawce. "
                            "Sprawdź, czy poprzednia migawka nie została przerwana w połowie." )
                          .arg( bezOdpowiednika );
      }
      else
      {
        powodDowiazan = tr( "Nic się nie dowiązało — %1 plików ma inny rozmiar niż w poprzedniej migawce. "
                            "Jeśli dane naprawdę się zmieniły, tak ma być." )
                          .arg( innyRozmiar );
      }
      powodDowiazan += oPominietych;

      // ------------------------------------------------- 4. spis w migawce
      emit postep( 97, tr( "Robię spis migawki…" ) );
      SpisPlikow spis;
      const QVariantMap wynikSpisu = spis.zrob( migawka, migawka, QStringLiteral( "wszystko" ), false );

      // ----------------------------------------------------- 5. KOPIA.json
      const QJsonObject stempelNosnika = czytajJson( nosnik + QLatin1Char( '/' ) + STEMPEL_NOSNIKA );

      QJsonObject opis;
      opis.insert( QStringLiteral( "data" ), QDateTime::currentDateTime().toString( Qt::ISODate ) );
      opis.insert( QStringLiteral( "zakres" ), tylkoDane ? QStringLiteral( "dane" ) : QStringLiteral( "wszystko" ) );
      opis.insert( QStringLiteral( "korzen" ), katalogKorzenia.absolutePath() );
      opis.insert( QStringLiteral( "plikow" ), ile );
      opis.insert( QStringLiteral( "bajtow" ), razemBajtow );
      opis.insert( QStringLiteral( "skopiowanych" ), skopiowanych );
      opis.insert( QStringLiteral( "dowiazanych" ), dowiazanych );
      opis.insert( QStringLiteral( "pominietych" ), pominietych );
      opis.insert( QStringLiteral( "dowiazaniaDzialaja" ), dowiazania );
      opis.insert( QStringLiteral( "dowiazaniaPowod" ), powodDowiazan );
      QJsonObject rozbicie;
      rozbicie.insert( QStringLiteral( "bezOdpowiednika" ), bezOdpowiednika );
      rozbicie.insert( QStringLiteral( "innyRozmiar" ), innyRozmiar );
      rozbicie.insert( QStringLiteral( "innyCzas" ), innyCzas );
      rozbicie.insert( QStringLiteral( "linkOdmowil" ), linkOdmowil );
      opis.insert( QStringLiteral( "dlaczegoNieDowiazano" ), rozbicie );
      opis.insert( QStringLiteral( "przerwane" ), mPrzerwane );
      opis.insert( QStringLiteral( "poprzednia" ), QFileInfo( poprzednia ).fileName() );
      opis.insert( QStringLiteral( "sekund" ), static_cast<qint64>( zegar.elapsed() / 1000 ) );
      opis.insert( QStringLiteral( "bazy" ), bazyOpis );
      opis.insert( QStringLiteral( "spis" ), QFileInfo( wynikSpisu.value( QStringLiteral( "sciezka" ) ).toString() ).fileName() );

      // NA KTORYM NOSNIKU TO POWSTALO — cala tresc prosby Piotra.
      QJsonObject naNosniku;
      naNosniku.insert( QStringLiteral( "id" ), stempelNosnika.value( QStringLiteral( "id" ) ) );
      naNosniku.insert( QStringLiteral( "nazwa" ), stempelNosnika.value( QStringLiteral( "nazwa" ) ) );
      opis.insert( QStringLiteral( "nosnik" ), naNosniku );

      QJsonArray listaBledow;
      for ( const QString &b : std::as_const( bledy ) )
        listaBledow.append( b );
      opis.insert( QStringLiteral( "bledy" ), listaBledow );

      zapiszJson( migawka + QLatin1Char( '/' ) + OPIS_MIGAWKI, opis );

      wynik.insert( QStringLiteral( "ok" ), !mPrzerwane && bledy.isEmpty() );
      wynik.insert( QStringLiteral( "migawka" ), migawka );
      wynik.insert( QStringLiteral( "plikow" ), ile );
      wynik.insert( QStringLiteral( "bajtow" ), razemBajtow );
      wynik.insert( QStringLiteral( "skopiowanych" ), skopiowanych );
      wynik.insert( QStringLiteral( "dowiazanych" ), dowiazanych );
      wynik.insert( QStringLiteral( "pominietych" ), pominietych );
      wynik.insert( QStringLiteral( "dowiazaniaDzialaja" ), dowiazania );
      wynik.insert( QStringLiteral( "dowiazaniaPowod" ), powodDowiazan );
      wynik.insert( QStringLiteral( "przerwane" ), mPrzerwane );
      wynik.insert( QStringLiteral( "bazySprawdzone" ), bazyOpis.size() );
      wynik.insert( QStringLiteral( "bledy" ), QVariant( bledy ) );
      wynik.insert( QStringLiteral( "nazwaNosnika" ), stempelNosnika.value( QStringLiteral( "nazwa" ) ).toString() );
      wynik.insert( QStringLiteral( "sekund" ), zegar.elapsed() / 1000 );
      wynik.insert( QStringLiteral( "czas" ), ludzkiCzas( zegar.elapsed() / 1000 ) );

      emit postep( 100, tr( "Gotowe" ) );
      emit skonczone( wynik );
    }

  signals:
    void postep( int procent, const QString &etap );
    void skonczone( const QVariantMap &wynik );

  private:
    bool mPrzerwane = false;
};

// =====================================================================
//  KopieZapasowe
// =====================================================================

KopieZapasowe::KopieZapasowe( QObject *parent )
  : QObject( parent )
{
}

KopieZapasowe::~KopieZapasowe()
{
  if ( mWatek )
  {
    if ( mRobotnik )
      mRobotnik->przerwij();
    mWatek->quit();
    mWatek->wait( 5000 );
  }
}

QVariantList KopieZapasowe::nosniki() const
{
  QVariantList wynik;
  const QList<QStorageInfo> wolumeny = QStorageInfo::mountedVolumes();
  const QString systemowy = QStorageInfo::root().rootPath();

  for ( const QStorageInfo &wolumen : wolumeny )
  {
    if ( !wolumen.isValid() || !wolumen.isReady() || wolumen.isReadOnly() )
      continue;
    if ( wolumen.rootPath() == systemowy )
      continue;

    // Wolumeny wymienne poznajemy po miejscu montowania. Nie jest to
    // niezawodne, ale nie musi byc: czlowiek i tak wskazuje nosnik z listy,
    // a katalog da sie wskazac recznie, gdy tu go nie ma.
    const QString sciezka = wolumen.rootPath();
    const bool wymienny = sciezka.startsWith( QLatin1String( "/media/" ) )
                          || sciezka.startsWith( QLatin1String( "/run/media/" ) )
                          || sciezka.startsWith( QLatin1String( "/mnt/" ) )
                          || ( sciezka.startsWith( QLatin1String( "/storage/" ) )
                               && !sciezka.contains( QLatin1String( "emulated" ) ) );
    if ( !wymienny )
      continue;

    const QJsonObject nasz = czytajJson( sciezka + QLatin1Char( '/' ) + STEMPEL_NOSNIKA );

    QVariantMap wpis;
    wpis.insert( QStringLiteral( "sciezka" ), sciezka );
    wpis.insert( QStringLiteral( "etykieta" ), wolumen.name().isEmpty() ? wolumen.device() : wolumen.name() );
    wpis.insert( QStringLiteral( "system" ), QString::fromUtf8( wolumen.fileSystemType() ) );
    wpis.insert( QStringLiteral( "pojemnosc" ), wolumen.bytesTotal() );
    wpis.insert( QStringLiteral( "wolne" ), wolumen.bytesAvailable() );
    wpis.insert( QStringLiteral( "znany" ), !nasz.isEmpty() );
    wpis.insert( QStringLiteral( "nazwa" ), nasz.value( QStringLiteral( "nazwa" ) ).toString() );
    wpis.insert( QStringLiteral( "id" ), nasz.value( QStringLiteral( "id" ) ).toString() );
    wpis.insert( QStringLiteral( "odKiedy" ), nasz.value( QStringLiteral( "odKiedy" ) ).toString() );
    wpis.insert( QStringLiteral( "migawek" ),
                 QDir( sciezka + QStringLiteral( "/WorkField_kopie" ) )
                   .entryList( QStringList() << QStringLiteral( "snap_*" ), QDir::Dirs )
                   .size() );
    wynik.append( wpis );
  }
  return wynik;
}

QVariantMap KopieZapasowe::stempel( const QString &sciezkaNosnika ) const
{
  return czytajJson( sciezkaNosnika + QLatin1Char( '/' ) + STEMPEL_NOSNIKA ).toVariantMap();
}

QVariantMap KopieZapasowe::ostempluj( const QString &sciezkaNosnika, const QString &nazwa ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );

  if ( sciezkaNosnika.isEmpty() || nazwa.trimmed().isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Podaj nazwę nośnika." ) );
    return wynik;
  }

  const QString plik = sciezkaNosnika + QLatin1Char( '/' ) + STEMPEL_NOSNIKA;
  QJsonObject tresc = czytajJson( plik );

  // IDENTYFIKATOR RAZ NADANY ZOSTAJE. Zmiana nazwy nie moze rozlaczyc
  // nosnika od migawek, ktore juz na nim leza.
  if ( !tresc.contains( QStringLiteral( "id" ) ) )
  {
    tresc.insert( QStringLiteral( "id" ), QUuid::createUuid().toString( QUuid::WithoutBraces ).left( 12 ) );
    tresc.insert( QStringLiteral( "odKiedy" ), QDateTime::currentDateTime().toString( Qt::ISODate ) );
  }
  tresc.insert( QStringLiteral( "nazwa" ), nazwa.trimmed() );

  const QStorageInfo wolumen( sciezkaNosnika );
  tresc.insert( QStringLiteral( "etykietaSystemowa" ), wolumen.name() );
  tresc.insert( QStringLiteral( "systemPlikow" ), QString::fromUtf8( wolumen.fileSystemType() ) );

  if ( !zapiszJson( plik, tresc ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się zapisać na %1" ).arg( sciezkaNosnika ) );
    return wynik;
  }

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "id" ), tresc.value( QStringLiteral( "id" ) ).toString() );
  wynik.insert( QStringLiteral( "nazwa" ), tresc.value( QStringLiteral( "nazwa" ) ).toString() );
  return wynik;
}

QVariantList KopieZapasowe::migawki( const QString &sciezkaNosnika ) const
{
  QVariantList wynik;
  const QString baza = sciezkaNosnika + QStringLiteral( "/WorkField_kopie" );
  const QStringList nazwy = QDir( baza ).entryList( QStringList() << QStringLiteral( "snap_*" ),
                                                    QDir::Dirs, QDir::Name | QDir::Reversed );
  for ( const QString &nazwa : nazwy )
  {
    const QString katalog = baza + QLatin1Char( '/' ) + nazwa;
    const QJsonObject opis = czytajJson( katalog + QLatin1Char( '/' ) + OPIS_MIGAWKI );

    QVariantMap wpis;
    wpis.insert( QStringLiteral( "nazwa" ), nazwa );
    wpis.insert( QStringLiteral( "sciezka" ), katalog );
    wpis.insert( QStringLiteral( "data" ), opis.value( QStringLiteral( "data" ) ).toString() );
    wpis.insert( QStringLiteral( "zakres" ), opis.value( QStringLiteral( "zakres" ) ).toString() );
    wpis.insert( QStringLiteral( "plikow" ), opis.value( QStringLiteral( "plikow" ) ).toInt() );
    wpis.insert( QStringLiteral( "bajtow" ), opis.value( QStringLiteral( "bajtow" ) ).toDouble() );
    wpis.insert( QStringLiteral( "dowiazanych" ), opis.value( QStringLiteral( "dowiazanych" ) ).toInt() );
    wpis.insert( QStringLiteral( "dowiazaniaPowod" ), opis.value( QStringLiteral( "dowiazaniaPowod" ) ).toString() );
    wpis.insert( QStringLiteral( "przerwane" ), opis.value( QStringLiteral( "przerwane" ) ).toBool() );
    wpis.insert( QStringLiteral( "spis" ), opis.value( QStringLiteral( "spis" ) ).toString() );
    wpis.insert( QStringLiteral( "bledow" ), opis.value( QStringLiteral( "bledy" ) ).toArray().size() );
    wynik.append( wpis );
  }
  return wynik;
}

/**
 * Przepisuje czasy plikow w GOTOWEJ migawce z ich oryginalow.
 *
 * PO CO: migawka zrobiona przed poprawka z 24.08.2026 ma czasy z chwili
 * kopiowania. Nastepna migawka nie rozpozna w niej ani jednego pliku jako
 * niezmienionego i przepisze cale 88 GB od nowa. Ta funkcja naprawia stara
 * migawke w kilkanascie sekund i oszczedza te godzine i pol.
 *
 * CZEGO NIE RUSZAMY — i to jest tu najwazniejsze zdanie.
 *
 * Zgodnosc ROZMIARU nie dowodzi zgodnosci TRESCI. Plik, ktory zmienil sie
 * w miejscu bez zmiany rozmiaru, dostalby tu swiezy czas i od tej chwili
 * dowiazywalby sie w nieskonczonosc jako "niezmieniony" — czyli kopia
 * zostalaby na zawsze nieaktualna, nie mowiac o tym ani slowa. To jest ta
 * sama kategoria, ktora spis nazywa PODEJRZANE, i dokladnie dlatego spis
 * liczy dla niej sumy kontrolne.
 *
 * Wiec czasy przepisujemy wylacznie plikom z klasy, ktora sie w miejscu nie
 * zmienia: rastry, zdjecia, chmury punktow. Bazy, projekty i JSON-y zostaja
 * nietkniete — sa male, skopiuja sie na nowo i nic to nie kosztuje.
 */
QVariantMap KopieZapasowe::naprawCzasy( const QString &sciezkaMigawki, const QString &korzen ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "poprawionych" ), 0 );

  const QDir katalogMigawki( sciezkaMigawki );
  const QDir katalogZrodla( korzen );
  if ( !katalogMigawki.exists() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma migawki %1" ).arg( sciezkaMigawki ) );
    return wynik;
  }
  if ( !katalogZrodla.exists() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma katalogu z oryginałami: %1" ).arg( korzen ) );
    return wynik;
  }

  int sprawdzonych = 0;
  int poprawionych = 0;
  int juzDobrych = 0;
  int bezOryginalu = 0;
  int innyRozmiar = 0;
  int ostroznie = 0;  // klasa zmienna w miejscu — celowo pominieta

  QDirIterator it( sciezkaMigawki, QDir::Files, QDirIterator::Subdirectories );
  while ( it.hasNext() )
  {
    const QString wMigawce = it.next();
    const QString wzgledna = katalogMigawki.relativeFilePath( wMigawce );

    // Wlasne papiery migawki nie maja oryginalu i nie o nie tu chodzi.
    if ( wzgledna.startsWith( QLatin1String( "spis_" ) )
         || wzgledna == QLatin1String( "KOPIA.json" ) )
      continue;

    ++sprawdzonych;

    if ( wzgledna.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive )
         || wzgledna.endsWith( QLatin1String( ".qgs" ), Qt::CaseInsensitive )
         || wzgledna.endsWith( QLatin1String( ".qgz" ), Qt::CaseInsensitive )
         || wzgledna.endsWith( QLatin1String( ".json" ), Qt::CaseInsensitive ) )
    {
      ++ostroznie;
      continue;
    }

    const QString oryginal = korzen + QLatin1Char( '/' ) + wzgledna;
    const QFileInfo infoOryginal( oryginal );
    if ( !infoOryginal.exists() )
    {
      ++bezOryginalu;
      continue;
    }

    const QFileInfo infoKopia( wMigawce );
    if ( infoKopia.size() != infoOryginal.size() )
    {
      ++innyRozmiar;
      continue;
    }
    if ( qAbs( infoKopia.lastModified().toSecsSinceEpoch()
               - infoOryginal.lastModified().toSecsSinceEpoch() ) <= 2 )
    {
      ++juzDobrych;
      continue;
    }

    if ( przepiszCzas( oryginal, wMigawce ) )
      ++poprawionych;
  }

  wynik.insert( QStringLiteral( "sprawdzonych" ), sprawdzonych );
  wynik.insert( QStringLiteral( "poprawionych" ), poprawionych );
  wynik.insert( QStringLiteral( "juzDobrych" ), juzDobrych );
  wynik.insert( QStringLiteral( "bezOryginalu" ), bezOryginalu );
  wynik.insert( QStringLiteral( "innyRozmiar" ), innyRozmiar );
  wynik.insert( QStringLiteral( "pominietychOstroznie" ), ostroznie );
  wynik.insert( QStringLiteral( "opis" ),
                tr( "Poprawiono czasy %1 plików z %2 sprawdzonych. "
                    "%3 miało już dobre. %4 pominięto celowo (bazy, projekty, JSON-y — "
                    "mogą się zmieniać bez zmiany rozmiaru). "
                    "Następna migawka tego zakresu powinna się dowiązać." )
                  .arg( poprawionych ).arg( sprawdzonych ).arg( juzDobrych ).arg( ostroznie ) );
  return wynik;
}

QVariantMap KopieZapasowe::zbadaj( const QString &korzen, const QString &zakres, const QString &sciezkaNosnika ) const
{
  QVariantMap wynik;
  const QDir katalogKorzenia( korzen );
  const bool tylkoDane = zakres != QLatin1String( "wszystko" );

  int plikow = 0;
  qint64 bajtow = 0;
  QStringList otwarte;

  QDirIterator obchod( korzen, QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden, QDirIterator::Subdirectories );
  while ( obchod.hasNext() )
  {
    const QString pelna = obchod.next();
    const QFileInfo info( pelna );
    const QString wzgledna = katalogKorzenia.relativeFilePath( pelna );

    // Dziennik obok bazy znaczy "ktos ma ja otwarta". Mowimy o tym PRZED
    // kopiowaniem, zeby czlowiek mial szanse zamknac QGIS-a.
    if ( info.fileName().endsWith( QLatin1String( "-wal" ) ) )
    {
      QString bazaObok = wzgledna;
      bazaObok.chop( 4 );
      otwarte.append( bazaObok );
      continue;
    }
    if ( pomijac( info.fileName() ) )
      continue;
    if ( wzgledna.contains( QLatin1String( "/.git/" ) ) || wzgledna.startsWith( QLatin1String( ".git/" ) ) )
      continue;
    if ( tylkoDane && !SpisPlikow::nieodtwarzalny( wzgledna ) )
      continue;

    ++plikow;
    bajtow += info.size();
  }

  const QStorageInfo wolumen( sciezkaNosnika );
  const qint64 wolne = wolumen.isValid() ? wolumen.bytesAvailable() : -1;

  wynik.insert( QStringLiteral( "plikow" ), plikow );
  wynik.insert( QStringLiteral( "bajtow" ), bajtow );
  wynik.insert( QStringLiteral( "otwarteBazy" ), otwarte );
  wynik.insert( QStringLiteral( "wolne" ), wolne );
  wynik.insert( QStringLiteral( "zmiesciSie" ), wolne < 0 || wolne > bajtow );
  return wynik;
}

void KopieZapasowe::wykonaj( const QString &korzen, const QString &zakres, const QString &sciezkaNosnika )
{
  if ( mPracuje )
    return;

  mWatek = new QThread( this );
  mRobotnik = new RobotnikKopii();
  mRobotnik->moveToThread( mWatek );

  connect( mRobotnik, &RobotnikKopii::postep, this, &KopieZapasowe::naPostep );
  connect( mRobotnik, &RobotnikKopii::skonczone, this, &KopieZapasowe::naKoniec );
  connect( mWatek, &QThread::finished, mRobotnik, &QObject::deleteLater );

  mPracuje = true;
  mPostep = 0;
  mEtap = tr( "Zaczynam…" );
  emit pracujeChanged();
  emit postepChanged();
  emit etapChanged();

  mWatek->start();
  QMetaObject::invokeMethod( mRobotnik, "pracuj", Qt::QueuedConnection,
                             Q_ARG( QString, korzen ),
                             Q_ARG( QString, zakres ),
                             Q_ARG( QString, sciezkaNosnika ) );
}

void KopieZapasowe::przerwij()
{
  if ( mRobotnik )
    mRobotnik->przerwij();
}

void KopieZapasowe::naPostep( int procent, const QString &etap )
{
  mPostep = procent;
  mEtap = etap;
  emit postepChanged();
  emit etapChanged();
}

void KopieZapasowe::naKoniec( const QVariantMap &wynik )
{
  mPracuje = false;
  emit pracujeChanged();

  if ( mWatek )
  {
    mWatek->quit();
    mWatek->wait( 5000 );
    mWatek->deleteLater();
    mWatek = nullptr;
    mRobotnik = nullptr;
  }

  emit skonczone( wynik );
}

#include "kopiezapasowe.moc"
