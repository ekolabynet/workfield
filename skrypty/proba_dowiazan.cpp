// WorkField 24.08.2026 — odtworzenie cyklu trzech migawek POZA aplikacja.
//
// Piotr: "zrobily sie trzy kopie, druga i trzecia po patchu, i wszystkie chyba
// szly jako pelne". Zamiast zgadywac, ktory kawalek nie dziala, przepisuje tu
// DOKLADNIE te fragmenty kopiezapasowe.cpp, ktore decyduja o dowiazaniu:
// wybor poprzedniej migawki, tenSamPlik, przepiszCzas i ::link. Jesli blad
// siedzi w kodzie, to sie tu pokaze. Jesli sie nie pokaze — blad jest gdzie
// indziej i nie wolno "naprawiac" kodu, ktory dziala.
//
// Migawka 1 jedzie BEZ przepiszCzas (tak, jak przed poprawka), 2 i 3 z nia.

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <unistd.h>

static QTextStream out( stdout );

// --- przepisane z kopiezapasowe.cpp, bez zmian ------------------------------

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

bool tenSamPlik( const QFileInfo &a, const QFileInfo &b )
{
  if ( a.size() != b.size() )
    return false;
  const qint64 ra = a.lastModified().toSecsSinceEpoch();
  const qint64 rb = b.lastModified().toSecsSinceEpoch();
  return qAbs( ra - rb ) <= 2;
}

bool dowiazaniaDzialaja( const QString &katalog )
{
  const QString proba = katalog + QStringLiteral( "/.wf_proba_dowiazania" );
  const QString cel = katalog + QStringLiteral( "/.wf_proba_dowiazania2" );
  QFile::remove( proba );
  QFile::remove( cel );
  QFile p( proba );
  if ( !p.open( QIODevice::WriteOnly ) )
    return false;
  p.write( "x" );
  p.close();
  const bool udalo = ::link( proba.toUtf8().constData(), cel.toUtf8().constData() ) == 0;
  QFile::remove( proba );
  QFile::remove( cel );
  return udalo;
}

// --- jedna migawka ----------------------------------------------------------

struct Wynik
{
  QString nazwa;
  QString poprzednia;
  int skopiowanych = 0;
  int dowiazanych = 0;
  bool dowiazaniaOk = false;
  bool przerwana = false;
};

Wynik migawka( const QString &korzen, const QString &baza,
               const QString &znacznik, const QString &przyrostek,
               bool zPrzepisaniemCzasu, int przerwijPo = -1 )
{
  Wynik w;

  // WYBOR POPRZEDNIEJ — przepisany 1:1 z kopiezapasowe.cpp.
  //
  // Cofamy sie po liscie az do migawki KOMPLETNEJ. Migawka przerwana jest
  // gorsza niz zadna: udaje punkt odniesienia, a nie ma w niej plikow.
  // 24.08.2026 wlasnie ona zjadla Piotrowi cztery godziny i 89 GB.
  {
    const QStringList nazwy = QDir( baza ).entryList(
      QStringList() << QStringLiteral( "snap_*_%1" ).arg( przyrostek )
                    << QStringLiteral( "snap_*_%1_*" ).arg( przyrostek ),
      QDir::Dirs, QDir::Name );
    out << "    entryList zwrocil: [" << nazwy.join( ", " ) << "]\n";
    for ( int i = nazwy.size() - 1; i >= 0; --i )
    {
      const QString kandydat = baza + QLatin1Char( '/' ) + nazwy.at( i );
      const QString opis = kandydat + QStringLiteral( "/KOPIA.json" );
      if ( !QFileInfo::exists( opis ) )
      {
        out << "    pomijam " << nazwy.at( i ) << " (bez KOPIA.json)\n";
        continue;
      }
      QFile f( opis );
      f.open( QIODevice::ReadOnly );
      const bool przerwana = QString::fromUtf8( f.readAll() ).contains( QStringLiteral( "\"przerwane\": true" ) );
      f.close();
      if ( przerwana )
      {
        out << "    pomijam " << nazwy.at( i ) << " (PRZERWANA)\n";
        continue;
      }
      w.poprzednia = kandydat;
      break;
    }
  }

  const QString mig = QStringLiteral( "%1/snap_%2_%3" ).arg( baza, znacznik, przyrostek );
  QDir().mkpath( mig );
  w.nazwa = QFileInfo( mig ).fileName();
  w.dowiazaniaOk = dowiazaniaDzialaja( mig );

  bool przerwana = false;
  int zrobionych = 0;
  QDirIterator it( korzen, QDir::Files, QDirIterator::Subdirectories );
  while ( it.hasNext() )
  {
    if ( przerwijPo >= 0 && zrobionych >= przerwijPo )
    {
      przerwana = true;
      break;
    }
    ++zrobionych;
    const QString zrodlo = it.next();
    const QString wzgledna = QDir( korzen ).relativeFilePath( zrodlo );
    const QString cel = mig + QLatin1Char( '/' ) + wzgledna;
    QDir().mkpath( QFileInfo( cel ).absolutePath() );

    bool zrobione = false;
    if ( w.dowiazaniaOk && !w.poprzednia.isEmpty() )
    {
      const QString stary = w.poprzednia + QLatin1Char( '/' ) + wzgledna;
      const QFileInfo infoStary( stary );
      const QFileInfo infoZrodlo( zrodlo );
      if ( infoStary.exists() && tenSamPlik( infoStary, infoZrodlo ) )
      {
        if ( ::link( stary.toUtf8().constData(), cel.toUtf8().constData() ) == 0 )
        {
          ++w.dowiazanych;
          zrobione = true;
        }
      }
    }
    if ( !zrobione && QFile::copy( zrodlo, cel ) )
    {
      if ( zPrzepisaniemCzasu )
        przepiszCzas( zrodlo, cel );
      ++w.skopiowanych;
    }
  }

  // KOPIA.json — bo to on decyduje, czy ta migawka nadaje sie na podstawe.
  QFile opis( mig + QStringLiteral( "/KOPIA.json" ) );
  opis.open( QIODevice::WriteOnly );
  opis.write( przerwana ? "{\n    \"przerwane\": true\n}\n"
                        : "{\n    \"przerwane\": false\n}\n" );
  opis.close();
  w.przerwana = przerwana;
  return w;
}

int main( int argc, char *argv[] )
{
  QCoreApplication app( argc, argv );

  const QString korzen = QStringLiteral( "/tmp/proba_zrodlo" );
  const QString nosnik = QStringLiteral( "/tmp/proba_nosnik" );
  const QString baza = nosnik + QStringLiteral( "/WorkField_kopie" );
  QDir( korzen ).removeRecursively();
  QDir( nosnik ).removeRecursively();
  QDir().mkpath( korzen + QStringLiteral( "/podkatalog" ) );
  QDir().mkpath( baza );

  // Zrodlo: pliki ze STARYM mtime, tak jak dane w terenie — nikt ich dzis
  // nie ruszal. Gdyby mialy czas "teraz", proba bylaby latwiejsza niz zycie.
  const QDateTime stary = QDateTime::currentDateTime().addDays( -30 );
  for ( int i = 0; i < 5; ++i )
  {
    const QString sc = QStringLiteral( "%1/%2plik%3.tif" )
                         .arg( korzen, i % 2 ? QStringLiteral( "podkatalog/" ) : QString() )
                         .arg( i );
    QFile f( sc );
    f.open( QIODevice::WriteOnly );
    f.write( QByteArray( 1024 * ( i + 1 ), 'a' ) );
    f.close();
    QFile g( sc );
    g.open( QIODevice::ReadWrite );
    g.setFileTime( stary, QFileDevice::FileModificationTime );
    g.close();
  }

  out << "=== Migawka 1 (jak PRZED poprawka — bez przepiszCzas)\n";
  Wynik w1 = migawka( korzen, baza, QStringLiteral( "2026-08-24_0500" ),
                      QStringLiteral( "wszystko" ), false );
  out << "    poprzednia=" << ( w1.poprzednia.isEmpty() ? QStringLiteral( "(brak)" ) : QFileInfo( w1.poprzednia ).fileName() )
      << "  skopiowanych=" << w1.skopiowanych << "  dowiazanych=" << w1.dowiazanych
      << "  dowiazaniaDzialaja=" << ( w1.dowiazaniaOk ? "true" : "false" ) << "\n\n";

  out << "=== Migawka 2 (PO poprawce; poprzednia ma zle czasy)\n";
  Wynik w2 = migawka( korzen, baza, QStringLiteral( "2026-08-24_0600" ),
                      QStringLiteral( "wszystko" ), true );
  out << "    poprzednia=" << QFileInfo( w2.poprzednia ).fileName()
      << "  skopiowanych=" << w2.skopiowanych << "  dowiazanych=" << w2.dowiazanych << "\n\n";

  out << "=== Migawka 3 (PO poprawce; poprzednia ma juz dobre czasy)\n";
  Wynik w3 = migawka( korzen, baza, QStringLiteral( "2026-08-24_0700" ),
                      QStringLiteral( "wszystko" ), true );
  out << "    poprzednia=" << QFileInfo( w3.poprzednia ).fileName()
      << "  skopiowanych=" << w3.skopiowanych << "  dowiazanych=" << w3.dowiazanych << "\n\n";

  // --- CZY NAPRAWA CZASOW RATUJE STARA MIGAWKE ------------------------------
  //
  // Drugie drzewo, od zera: migawka 1 bez przepiszCzas (jak u Piotra), potem
  // naprawa jej czasow, potem migawka 2. Jesli naprawa dziala, migawka 2
  // dowiaze wszystko — czyli Piotr NIE musi przepisywac 88 GB po raz kolejny.
  out << "=== Proba naprawy czasow w gotowej migawce\n";
  const QString baza2 = nosnik + QStringLiteral( "/WorkField_kopie2" );
  QDir().mkpath( baza2 );
  Wynik n1 = migawka( korzen, baza2, QStringLiteral( "2026-08-24_0500" ),
                      QStringLiteral( "wszystko" ), false );
  out << "    migawka 1 (zle czasy): skopiowanych=" << n1.skopiowanych << "\n";

  int poprawionych = 0;
  {
    const QString mig = baza2 + QLatin1Char( '/' ) + n1.nazwa;
    QDirIterator it2( mig, QDir::Files, QDirIterator::Subdirectories );
    while ( it2.hasNext() )
    {
      const QString wKopii = it2.next();
      const QString wzgl = QDir( mig ).relativeFilePath( wKopii );
      const QString oryg = korzen + QLatin1Char( '/' ) + wzgl;
      const QFileInfo io( oryg ), ik( wKopii );
      if ( !io.exists() || io.size() != ik.size() )
        continue;
      if ( qAbs( ik.lastModified().toSecsSinceEpoch() - io.lastModified().toSecsSinceEpoch() ) <= 2 )
        continue;
      if ( przepiszCzas( oryg, wKopii ) )
        ++poprawionych;
    }
  }
  out << "    naprawa: poprawiono czasy " << poprawionych << " plikow\n";

  Wynik n2 = migawka( korzen, baza2, QStringLiteral( "2026-08-24_0600" ),
                      QStringLiteral( "wszystko" ), true );
  out << "    migawka 2 PO naprawie: skopiowanych=" << n2.skopiowanych
      << "  dowiazanych=" << n2.dowiazanych << "\n\n";

  // --- SCENARIUSZ PIOTRA Z 24.08.2026 ---------------------------------------
  //
  // Pelna migawka, potem DWIE przerwane (6 i 33 pliki), potem kolejna pelna.
  // Stary kod bral za podstawe te ostatnia przerwana i przepisywal wszystko.
  out << "=== Scenariusz z 24.08.2026: dwie przerwane migawki po drodze\n";
  const QString baza3 = nosnik + QStringLiteral( "/WorkField_kopie3" );
  QDir().mkpath( baza3 );
  migawka( korzen, baza3, QStringLiteral( "2026-08-24_0511" ), QStringLiteral( "wszystko" ), true );
  migawka( korzen, baza3, QStringLiteral( "2026-08-24_0844" ), QStringLiteral( "wszystko" ), true, 1 );
  migawka( korzen, baza3, QStringLiteral( "2026-08-24_0845" ), QStringLiteral( "wszystko" ), true, 2 );
  Wynik p4 = migawka( korzen, baza3, QStringLiteral( "2026-08-24_0847" ), QStringLiteral( "wszystko" ), true );
  out << "    podstawa=" << QFileInfo( p4.poprzednia ).fileName()
      << "  skopiowanych=" << p4.skopiowanych << "  dowiazanych=" << p4.dowiazanych << "\n\n";

  out << "=== WERDYKT\n";
  out << "  Migawka 2 pelna  : " << ( w2.dowiazanych == 0 ? "TAK (spodziewane)" : "nie" ) << "\n";
  out << "  Migawka 3 pelna  : " << ( w3.dowiazanych == 0 ? "TAK — TO JEST BLAD W KODZIE" : "nie — kod dziala" ) << "\n";
  out << "  Przerwane omija  : " << ( p4.dowiazanych > 0 ? "TAK — podstawa jest ostatnia KOMPLETNA" : "NIE — blad wrocil" ) << "\n";
  out << "  Naprawa ratuje   : " << ( n2.dowiazanych > 0 ? "TAK — nie trzeba przepisywac calosci" : "NIE" ) << "\n";
  out.flush();
  return 0;
}

/*
 * JAK TO SKOMPILOWAC I URUCHOMIC (nie potrzeba calego QField-a):
 *
 *     g++ -fPIC -o /tmp/proba_dowiazan skrypty/proba_dowiazan.cpp \
 *         $(pkg-config --cflags --libs Qt6Core)
 *     /tmp/proba_dowiazan
 *
 * Program pracuje w /tmp na sztucznym drzewie i niczego nie rusza poza nim.
 *
 * WYNIK Z 24.08.2026 (Qt 6.4.2, ext4):
 *     Migawka 2 pelna  : TAK (spodziewane — poprzednia ma czasy z kopiowania)
 *     Migawka 3 pelna  : nie — kod dziala
 *     Przerwane omija  : TAK — podstawa jest ostatnia KOMPLETNA
 *     Naprawa ratuje   : TAK — nie trzeba przepisywac calosci
 *
 * Trzecia proba to scenariusz Piotra 1:1 i to ona jest tu najwazniejsza.
 * Pierwsza wersja tego programu jej NIE MIALA — sprawdzalem tylko lancuch
 * samych kompletnych migawek, wiec kod przeszedl probe, a u Piotra nie
 * dzialal. Proba, ktora nie odtwarza tego, co sie stalo naprawde, potwierdza
 * tylko wlasne zalozenia.
 */
