/***************************************************************************
  procesystudio.cpp - silnik czasowników WFG Studio

  WorkField (fork QField) - GPL-2.0-or-later
 ***************************************************************************/
#include "procesystudio.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QTemporaryFile>

// Rozruch PyQGIS: zbuduj_projekt.py i pokrewne zakładają działający QGIS.
// Poza konsolą QGIS trzeba silnik obudzić samemu — dokładnie jak w wf_core.
static const char *ROZRUCH_PYQGIS =
  "import sys\n"
  "sciezka = sys.argv[1]\n"
  "try:\n"
  "    from qgis.core import QgsApplication\n"
  "except ImportError:\n"
  "    sys.exit('Brak PyQGIS w systemowym pythonie (sudo apt install python3-qgis)')\n"
  "QgsApplication.setPrefixPath('/usr', True)\n"
  "aplikacja = QgsApplication([], False)\n"
  "aplikacja.initQgis()\n"
  "try:\n"
  "    kod = open(sciezka, encoding='utf-8').read()\n"
  "    exec(compile(kod, sciezka, 'exec'), {'__file__': sciezka, '__name__': '__main__'})\n"
  "finally:\n"
  "    aplikacja.exitQgis()\n";

// katalogi pomijane przy skanowaniu i kopiowaniu z szablonu
static const QStringList POMIJANE = { QStringLiteral( "archiwum" ), QStringLiteral( ".kosz" ),
                                      QStringLiteral( "__pycache__" ), QStringLiteral( ".git" ),
                                      QStringLiteral( "DCIM" ), QStringLiteral( "Attachments" ) };

ProcesyStudio::ProcesyStudio( QObject *parent )
  : QObject( parent )
{
  mProces.setProcessChannelMode( QProcess::MergedChannels );

  connect( &mProces, &QProcess::readyReadStandardOutput, this, [this]() {
    const QStringList linie = QString::fromUtf8( mProces.readAllStandardOutput() )
                                .split( QLatin1Char( '\n' ), Qt::SkipEmptyParts );
    for ( const QString &l : linie )
      emit linia( l );
  } );

  connect( &mProces, &QProcess::finished, this, [this]( int kod, QProcess::ExitStatus ) {
    if ( !mPlikRozruchu.isEmpty() )
    {
      QFile::remove( mPlikRozruchu );
      mPlikRozruchu.clear();
    }
    emit zakonczono( kod );
    emit dzialaChanged();
  } );

  connect( &mProces, &QProcess::errorOccurred, this, [this]( QProcess::ProcessError ) {
    emit linia( tr( "Błąd uruchomienia: %1" ).arg( mProces.errorString() ) );
    emit dzialaChanged();
  } );
}

ProcesyStudio::~ProcesyStudio()
{
  // zamknięcie aplikacji nie może zostawić sieroty ani czekać na nią minutami
  if ( mProces.state() != QProcess::NotRunning )
  {
    mProces.terminate();
    if ( !mProces.waitForFinished( 2000 ) )
      mProces.kill();
  }
}

bool ProcesyStudio::dziala() const
{
  return mProces.state() != QProcess::NotRunning;
}

bool ProcesyStudio::startuj( const QString &program, const QStringList &argumenty,
                             const QString &katalog )
{
#ifdef Q_OS_ANDROID
  Q_UNUSED( program )
  Q_UNUSED( argumenty )
  Q_UNUSED( katalog )
  emit linia( tr( "Ta operacja jest dostępna tylko na komputerze." ) );
  return false;
#else
  if ( dziala() )
  {
    emit linia( tr( "Poprzednia operacja jeszcze trwa — poczekaj albo przerwij." ) );
    return false;
  }
  if ( !katalog.isEmpty() )
    mProces.setWorkingDirectory( katalog );
  mProces.start( program, argumenty );
  emit dzialaChanged();
  return true;
#endif
}

bool ProcesyStudio::uruchom( const QString &program, const QStringList &argumenty,
                             const QString &katalog )
{
  return startuj( program, argumenty, katalog );
}

bool ProcesyStudio::uruchomPowloke( const QString &polecenie, const QString &katalog )
{
  return startuj( QStringLiteral( "/bin/sh" ), { QStringLiteral( "-c" ), polecenie }, katalog );
}

bool ProcesyStudio::uruchomPyQgis( const QString &sciezkaSkryptu )
{
  const QFileInfo fi( sciezkaSkryptu );
  if ( !fi.exists() )
  {
    emit linia( tr( "Brak skryptu: %1" ).arg( sciezkaSkryptu ) );
    return false;
  }

  QTemporaryFile rozruch( QDir::tempPath() + QStringLiteral( "/wfg_rozruch_XXXXXX.py" ) );
  rozruch.setAutoRemove( false );
  if ( !rozruch.open() )
  {
    emit linia( tr( "Nie mogę zapisać pliku rozruchowego." ) );
    return false;
  }
  rozruch.write( ROZRUCH_PYQGIS );
  rozruch.close();
  mPlikRozruchu = rozruch.fileName();

  return startuj( QStringLiteral( "python3" ),
                  { mPlikRozruchu, fi.absoluteFilePath() },
                  fi.absolutePath() );
}

void ProcesyStudio::przerwij()
{
  if ( !dziala() )
    return;
  emit linia( tr( "Przerywam..." ) );
  mProces.terminate();
  if ( !mProces.waitForFinished( 2000 ) )
    mProces.kill();
}

void ProcesyStudio::przeszukaj( const QString &katalog, const QString &korzen,
                                int pozostalaGlebokosc, QVariantList &wynik ) const
{
  const QDir dir( katalog );

  const QStringList qgsy = dir.entryList( { QStringLiteral( "*.qgs" ), QStringLiteral( "*.qgz" ) },
                                          QDir::Files, QDir::Name );
  const QStringList gpkgi = dir.entryList( { QStringLiteral( "*.gpkg" ) }, QDir::Files, QDir::Name );

  if ( !qgsy.isEmpty() || !gpkgi.isEmpty() )
  {
    QDateTime najnowszy;
    for ( const QString &p : qgsy + gpkgi )
    {
      const QDateTime m = QFileInfo( dir.filePath( p ) ).lastModified();
      if ( m > najnowszy )
        najnowszy = m;
    }
    const QString sciezka = dir.absolutePath();
    const bool szablon = sciezka.toLower().contains( QLatin1String( "szablon" ) );
    QVariantMap wpis;
    wpis[QStringLiteral( "nazwa" )] = dir.dirName();
    wpis[QStringLiteral( "sciezka" )] = sciezka;
    wpis[QStringLiteral( "qgs" )] = qgsy.isEmpty() ? QString() : dir.filePath( qgsy.first() );
    wpis[QStringLiteral( "typ" )] = szablon ? QStringLiteral( "szablon" ) : QStringLiteral( "projekt" );
    wpis[QStringLiteral( "zmodyfikowano" )] = najnowszy.toString( Qt::ISODate );
    QString gdzie = QDir( korzen ).relativeFilePath( QFileInfo( sciezka ).absolutePath() );
    if ( gdzie == QLatin1String( "." ) )
      gdzie.clear();
    wpis[QStringLiteral( "gdzie" )] = gdzie;
    wynik.append( wpis );
    return; // projekt znaleziony — nie schodzimy w jego wnętrze
  }

  if ( pozostalaGlebokosc <= 0 )
    return;

  const QStringList podkatalogi = dir.entryList( QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name );
  for ( const QString &p : podkatalogi )
  {
    if ( POMIJANE.contains( p ) )
      continue;
    przeszukaj( dir.filePath( p ), korzen, pozostalaGlebokosc - 1, wynik );
  }
}

QVariantList ProcesyStudio::znajdzProjekty( const QString &korzen, int glebokosc ) const
{
  QVariantList wynik;
  const QString pelna = korzen.startsWith( QLatin1Char( '~' ) )
                          ? QDir::homePath() + korzen.mid( 1 )
                          : korzen;
  if ( !QDir( pelna ).exists() )
    return wynik;
  przeszukaj( pelna, pelna, glebokosc, wynik );

  // projekty od najświeższych, szablony alfabetycznie na końcu
  std::sort( wynik.begin(), wynik.end(), []( const QVariant &a, const QVariant &b ) {
    const QVariantMap ma = a.toMap(), mb = b.toMap();
    const bool sa = ma.value( QStringLiteral( "typ" ) ) == QLatin1String( "szablon" );
    const bool sb = mb.value( QStringLiteral( "typ" ) ) == QLatin1String( "szablon" );
    if ( sa != sb )
      return sb; // projekty przed szablonami
    if ( sa )
      return ma.value( QStringLiteral( "nazwa" ) ).toString()
             < mb.value( QStringLiteral( "nazwa" ) ).toString();
    return ma.value( QStringLiteral( "zmodyfikowano" ) ).toString()
           > mb.value( QStringLiteral( "zmodyfikowano" ) ).toString();
  } );
  return wynik;
}

bool ProcesyStudio::kopiujKatalog( const QString &zrodlo, const QString &cel ) const
{
  QDir dirCel( cel );
  if ( !dirCel.mkpath( QStringLiteral( "." ) ) )
    return false;

  QDirIterator it( zrodlo, QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot );
  while ( it.hasNext() )
  {
    it.next();
    const QFileInfo fi = it.fileInfo();
    if ( fi.isDir() )
    {
      if ( POMIJANE.contains( fi.fileName() ) )
        continue;
      if ( !kopiujKatalog( fi.absoluteFilePath(), dirCel.filePath( fi.fileName() ) ) )
        return false;
    }
    else
    {
      if ( fi.fileName().endsWith( QLatin1String( ".bak" ) )
           || fi.fileName().endsWith( QLatin1Char( '~' ) ) )
        continue;
      if ( !QFile::copy( fi.absoluteFilePath(), dirCel.filePath( fi.fileName() ) ) )
        return false;
    }
  }
  return true;
}

QVariantMap ProcesyStudio::nowyZSzablonu( const QString &szablon, const QString &katalogDocelowy,
                                          const QString &nazwa, const QString &korzen ) const
{
  QVariantMap w;
  QString cel = katalogDocelowy;
  if ( cel.isEmpty() && !korzen.isEmpty() )
  {
    const QString wymiana = QDir( korzen ).filePath( QStringLiteral( "wymiana" ) );
    cel = QDir( wymiana ).exists() ? wymiana : korzen;
  }
  const QString oczyszczona = nazwa.trimmed();
  if ( oczyszczona.isEmpty() || cel.isEmpty() )
  {
    w[QStringLiteral( "ok" )] = false;
    w[QStringLiteral( "blad" )] = tr( "Podaj nazwę projektu." );
    return w;
  }
  const QString docelowa = QDir( cel ).filePath( oczyszczona );
  if ( QFileInfo::exists( docelowa ) )
  {
    w[QStringLiteral( "ok" )] = false;
    w[QStringLiteral( "blad" )] = tr( "Katalog już istnieje: %1" ).arg( docelowa );
    return w;
  }
  if ( !kopiujKatalog( szablon, docelowa ) )
  {
    w[QStringLiteral( "ok" )] = false;
    w[QStringLiteral( "blad" )] = tr( "Kopiowanie nie powiodło się (uprawnienia? miejsce?)." );
    return w;
  }
  w[QStringLiteral( "ok" )] = true;
  w[QStringLiteral( "sciezka" )] = docelowa;
  return w;
}
