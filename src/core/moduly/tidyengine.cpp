/***************************************************************************
  tidyengine.cpp - TidyEngine (WorkFieldGIS)

  Moduł „Porządkowanie danych” — silnik, łatka 1 (tylko odczyt).
  Patrz tidyengine.h i claude/MODUL_porzadkowanie_plan.md.

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "tidyengine.h"

#include "zalacznikiutils.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>

#include <qgsproject.h>
#include <qgsvectorlayer.h>

#include <sqlite3.h>

#include <algorithm>

namespace
{
  //! Lists returned to QML are capped; the TSV report always has everything.
  const int LIST_LIMIT = 500;

  //! First bytes hashed in the cheap duplicate stage (same as skrypty/spis_zdjec.py).
  const qint64 HEAD_BYTES = 65536;

  //! Photos of the project. Orthophotos (.tif) are not photos — 31.08 a first
  //! inventory pulled in 3 GB of them and drowned the real photos.
  bool isPhoto( const QString &name )
  {
    static const QStringList extensions = {
      QStringLiteral( "jpg" ), QStringLiteral( "jpeg" ), QStringLiteral( "heic" ),
      QStringLiteral( "heif" ), QStringLiteral( "png" )
    };
    return extensions.contains( QFileInfo( name ).suffix().toLower() );
  }

  //! Mapit stores Android SAF URIs, never a local path. Reporting them as
  //! missing files would be a false alarm on every row (handoff 25.08).
  bool isForeignUri( const QString &path )
  {
    static const QRegularExpression android( QStringLiteral( "^(content://|/tree/|/document/)|primary:" ) );
    return android.match( path ).hasMatch();
  }

  //! "dane (2).gpkg" — made by a browser, not by a decision (workfield-obieg §4).
  bool isBrowserCopy( const QString &name )
  {
    static const QRegularExpression copy( QStringLiteral( "\\s\\(\\d+\\)\\.gpkg$" ), QRegularExpression::CaseInsensitiveOption );
    return copy.match( name ).hasMatch();
  }

  //! Name without extension, lower case — the comparison that does not report
  //! .JPG against .jpg as a loss (23.10.2026, twice).
  QString stemKey( const QString &path )
  {
    return QFileInfo( path ).completeBaseName().toLower();
  }

  QString md5Of( const QString &path, qint64 limit = -1 )
  {
    QFile file( path );
    if ( !file.open( QIODevice::ReadOnly ) )
      return QString();
    QCryptographicHash hash( QCryptographicHash::Md5 );
    if ( limit > 0 )
      hash.addData( file.read( limit ) );
    else
    {
      while ( !file.atEnd() )
        hash.addData( file.read( 1 << 20 ) );
    }
    return QString::fromLatin1( hash.result().toHex() );
  }

  //! Hidden folders (".kosz", ".thumbnails") and the project trash are not data.
  bool skipFolder( const QString &name )
  {
    return name.startsWith( QLatin1Char( '.' ) ) || name.compare( QLatin1String( "kosz" ), Qt::CaseInsensitive ) == 0;
  }

  void collectPhotos( const QString &root, const QString &folder, QStringList &out )
  {
    const QDir dir( folder );
    const QFileInfoList entries = dir.entryInfoList( QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden, QDir::Name );
    for ( const QFileInfo &entry : entries )
    {
      if ( entry.isDir() )
      {
        if ( !skipFolder( entry.fileName() ) && !entry.isSymLink() )
          collectPhotos( root, entry.absoluteFilePath(), out );
        continue;
      }
      if ( entry.fileName().startsWith( QLatin1Char( '.' ) ) || !isPhoto( entry.fileName() ) )
        continue;
      out << QDir( root ).relativeFilePath( entry.absoluteFilePath() );
    }
  }

  void collectDatabases( const QString &folder, int depth, QStringList &out )
  {
    const QDir dir( folder );
    const QFileInfoList entries = dir.entryInfoList( QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name );
    for ( const QFileInfo &entry : entries )
    {
      if ( entry.isDir() )
      {
        if ( depth > 0 && !skipFolder( entry.fileName() ) && !entry.isSymLink() )
          collectDatabases( entry.absoluteFilePath(), depth - 1, out );
        continue;
      }
      if ( entry.suffix().compare( QLatin1String( "gpkg" ), Qt::CaseInsensitive ) == 0 )
        out << entry.absoluteFilePath();
    }
  }

  //! Rows per table of one GeoPackage, read-only. Empty map + error text on failure.
  QVariantMap databaseInfo( const QString &path, bool withMd5 )
  {
    QVariantMap info;
    const QFileInfo fileInfo( path );
    info.insert( QStringLiteral( "sciezka" ), path );
    info.insert( QStringLiteral( "nazwa" ), fileInfo.fileName() );
    info.insert( QStringLiteral( "bajty" ), fileInfo.size() );
    // A database with a journal next to it shows the state BEFORE the last
    // writes — counters are low. 27.08: the process was dead and a 2.1 MB
    // -wal still lay next to it. We report, we do not assume.
    info.insert( QStringLiteral( "wal" ), QFileInfo::exists( path + QStringLiteral( "-wal" ) ) );
    info.insert( QStringLiteral( "kopiaPrzegladarki" ), isBrowserCopy( fileInfo.fileName() ) );
    if ( withMd5 )
      info.insert( QStringLiteral( "md5" ), md5Of( path ) );

    sqlite3 *db = nullptr;
    if ( sqlite3_open_v2( path.toUtf8().constData(), &db, SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
    {
      info.insert( QStringLiteral( "blad" ), QString::fromUtf8( db ? sqlite3_errmsg( db ) : "sqlite3_open_v2" ) );
      if ( db )
        sqlite3_close( db );
      return info;
    }

    QStringList tables;
    sqlite3_stmt *statement = nullptr;
    if ( sqlite3_prepare_v2( db,
                             "SELECT name FROM sqlite_master WHERE type='table' "
                             "AND name NOT LIKE 'gpkg%' AND name NOT LIKE 'rtree%' AND name NOT LIKE 'sqlite%' ORDER BY name",
                             -1, &statement, nullptr )
         == SQLITE_OK )
    {
      while ( sqlite3_step( statement ) == SQLITE_ROW )
        tables << QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( statement, 0 ) ) );
      sqlite3_finalize( statement );
    }

    QSet<QString> featureTables;
    if ( sqlite3_prepare_v2( db, "SELECT table_name FROM gpkg_contents WHERE data_type='features'", -1, &statement, nullptr ) == SQLITE_OK )
    {
      while ( sqlite3_step( statement ) == SQLITE_ROW )
        featureTables.insert( QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( statement, 0 ) ) ) );
      sqlite3_finalize( statement );
    }

    QVariantMap rows;
    qlonglong features = 0;
    qlonglong attachments = 0;
    int attachmentTables = 0;
    for ( const QString &table : std::as_const( tables ) )
    {
      QString quoted = table;
      quoted.replace( QLatin1Char( '"' ), QLatin1String( "\"\"" ) );
      const QByteArray sql = QStringLiteral( "SELECT count(*) FROM \"%1\"" ).arg( quoted ).toUtf8();
      qlonglong count = -1;
      if ( sqlite3_prepare_v2( db, sql.constData(), -1, &statement, nullptr ) == SQLITE_OK )
      {
        if ( sqlite3_step( statement ) == SQLITE_ROW )
          count = sqlite3_column_int64( statement, 0 );
        sqlite3_finalize( statement );
      }
      rows.insert( table, count );
      if ( count < 0 )
        continue;
      if ( table.startsWith( QLatin1String( "ZAL_" ), Qt::CaseInsensitive ) )
      {
        attachments += count;
        ++attachmentTables;
      }
      else if ( featureTables.contains( table ) )
      {
        features += count;
      }
    }
    sqlite3_close( db );

    info.insert( QStringLiteral( "tabele" ), rows );
    info.insert( QStringLiteral( "obiektow" ), features );
    info.insert( QStringLiteral( "zalacznikow" ), attachments );
    info.insert( QStringLiteral( "tabelZal" ), attachmentTables );
    return info;
  }

  //! GeoPackage files the open project reads from.
  QSet<QString> databasesInUse( QgsProject *project )
  {
    QSet<QString> used;
    const QMap<QString, QgsMapLayer *> layers = project->mapLayers();
    for ( QgsMapLayer *layer : layers )
    {
      QgsVectorLayer *vector = qobject_cast<QgsVectorLayer *>( layer );
      if ( !vector || vector->providerType() != QLatin1String( "ogr" ) )
        continue;
      const QString file = vector->source().section( QLatin1Char( '|' ), 0, 0 );
      if ( file.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive ) )
        used.insert( QFileInfo( file ).absoluteFilePath() );
    }
    return used;
  }

  QVariantList capped( const QVariantList &list )
  {
    return list.size() > LIST_LIMIT ? list.mid( 0, LIST_LIMIT ) : list;
  }

  QString humanSize( qint64 bytes )
  {
    if ( bytes >= ( 1LL << 30 ) )
      return QStringLiteral( "%1 GB" ).arg( bytes / double( 1LL << 30 ), 0, 'f', 1 );
    if ( bytes >= ( 1LL << 20 ) )
      return QStringLiteral( "%1 MB" ).arg( bytes / double( 1LL << 20 ), 0, 'f', 1 );
    return QStringLiteral( "%1 kB" ).arg( bytes / 1024.0, 0, 'f', 0 );
  }
} // namespace

TidyEngine::TidyEngine( QObject *parent )
  : QObject( parent )
{
}

QVariantMap TidyEngine::opis() const
{
  // Tool module (third kind next to equipment and domain modules): no
  // "przepis", no "start" — it does not create a project, it works on the
  // open one. The card appears in "W tym projekcie" whenever recognize()
  // returns no "blad"; QfSekcjaModulow.qml needs only the line in silniki().
  static const QByteArray json = QByteArrayLiteral( R"WFG({
  "id": "data_tidy",
  "nazwa": "Porządkowanie danych",
  "wersja": "0.1",
  "silnik": "TidyEngine",
  "opis": "Przegląd baz i załączników projektu: która baza obowiązuje, wpisy bez pliku, pliki bez wpisu, duplikaty. Automat proponuje, człowiek rozstrzyga. Ta wersja tylko czyta i pisze raport.",
  "wymaga_silnika": ["TidyEngine.recognize", "TidyEngine.scan"],
  "wymaga_modulow": [],
  "rozpoznanie": "TidyEngine.recognize",
  "role": [
    { "klucz": "opisWarstw", "nazwa": "załączniki" },
    { "klucz": "opisBaz", "nazwa": "bazy w katalogu" }
  ],
  "akcje": [
    {
      "etykieta": "Przegląd: bazy, martwe wpisy, duplikaty",
      "czasownik": "TidyEngine.scan",
      "ikona": "wfg_przeglad",
      "wyslij": "pliki",
      "komunikat": "Przegląd: wpisów bez pliku {martwe}, plików bez wpisu {sieroty}, grup duplikatów {grupyDuplikatow}, baz {bazy}. Raport w export/."
    }
  ]
})WFG" );
  static const QVariantMap description = QJsonDocument::fromJson( json ).object().toVariantMap();
  return description;
}

QVariantMap TidyEngine::recognize( QgsProject *project ) const
{
  QVariantMap result;
  QgsProject *p = project ? project : QgsProject::instance();
  if ( !p || p->homePath().isEmpty() )
  {
    result.insert( QStringLiteral( "blad" ), tr( "Brak otwartego projektu" ) );
    return result;
  }

  // Cheap on purpose: the panel calls this every time the drawer opens.
  // Feature counts of the attachment layers, no md5, no walking DCIM.
  ZalacznikiUtils attachments;
  int layersWithAttachments = 0;
  qlonglong attachmentRows = 0;
  const QMap<QString, QgsMapLayer *> layers = p->mapLayers();
  for ( QgsMapLayer *layer : layers )
  {
    QgsVectorLayer *parent = qobject_cast<QgsVectorLayer *>( layer );
    if ( !parent || !parent->isValid() )
      continue;
    const QVariantMap description = attachments.relacjaZalacznikow( parent );
    if ( !description.value( QStringLiteral( "istnieje" ), false ).toBool() )
      continue;
    ++layersWithAttachments;
    QgsVectorLayer *child = qobject_cast<QgsVectorLayer *>( description.value( QStringLiteral( "warstwa" ) ).value<QObject *>() );
    if ( child )
      attachmentRows += std::max<qlonglong>( 0, child->featureCount() );
  }

  QStringList databases;
  collectDatabases( p->homePath(), 1, databases );

  result.insert( QStringLiteral( "obiekty" ), attachmentRows );
  result.insert( QStringLiteral( "warstwa" ), tr( "Warstwy z tabelą zdjęć: %1" ).arg( layersWithAttachments ) );
  result.insert( QStringLiteral( "opisWarstw" ), tr( "wpisów %1 w %2 tabelach" ).arg( attachmentRows ).arg( layersWithAttachments ) );
  result.insert( QStringLiteral( "opisBaz" ), databases.size() == 1 ? QFileInfo( databases.first() ).fileName() : tr( "%1 plików .gpkg" ).arg( databases.size() ) );
  return result;
}

QVariantList TidyEngine::sourceDatabases( const QString &folder, int depth ) const
{
  QStringList paths;
  collectDatabases( folder, depth, paths );
  QVariantList result;
  for ( const QString &path : std::as_const( paths ) )
    result << databaseInfo( path, true );
  return result;
}

QVariantMap TidyEngine::compareWithDisk( const QString &projectDir, const QVariantMap &index ) const
{
  QVariantMap result;
  const QDir root( projectDir );

  // --- the disk side: every photo under DCIM, relative to the project ------
  QStringList files;
  if ( root.exists( QStringLiteral( "DCIM" ) ) )
    collectPhotos( projectDir, root.filePath( QStringLiteral( "DCIM" ) ), files );

  QHash<QString, QString> byLowerPath; // lower-case relative path -> real path
  QHash<QString, QStringList> byStem;  // lower-case name without extension -> real paths
  for ( const QString &file : std::as_const( files ) )
  {
    byLowerPath.insert( file.toLower(), file );
    byStem[stemKey( file )] << file;
  }

  // --- the table side: every attachment row --------------------------------
  QVariantList dead, caseOnly, elsewhere, foreign;
  QSet<QString> claimed; // real disk paths some row points at
  for ( auto it = index.constBegin(); it != index.constEnd(); ++it )
  {
    QString path = it.key();
    path.replace( QLatin1Char( '\\' ), QLatin1Char( '/' ) );

    QVariantMap row = it.value().toMap();
    row.insert( QStringLiteral( "sciezka" ), path );

    if ( isForeignUri( path ) )
    {
      // Never a local path. Matched by name only, and a miss means "not
      // downloaded from the phone", not "lost".
      const QStringList sameStem = byStem.value( stemKey( path ) );
      for ( const QString &f : sameStem )
        claimed.insert( f );
      row.insert( QStringLiteral( "naDysku" ), sameStem.value( 0 ) );
      foreign << row;
      continue;
    }

    QString relative = path;
    if ( QDir::isAbsolutePath( relative ) )
    {
      if ( relative.startsWith( projectDir + QLatin1Char( '/' ) ) )
        relative = relative.mid( projectDir.size() + 1 );
      else if ( QFileInfo::exists( relative ) )
        continue; // absolute path outside the project, file present: not ours to judge
    }

    if ( QFileInfo::exists( root.filePath( relative ) ) )
    {
      claimed.insert( byLowerPath.value( relative.toLower(), relative ) );
      continue;
    }

    const QString sameLower = byLowerPath.value( relative.toLower() );
    if ( !sameLower.isEmpty() )
    {
      // Exists with different letter case: works on Windows, fails on
      // Android and Linux. Not a loss — a name to fix.
      row.insert( QStringLiteral( "naDysku" ), sameLower );
      caseOnly << row;
      claimed.insert( sameLower );
      continue;
    }

    const QStringList sameStem = byStem.value( stemKey( relative ) );
    if ( sameStem.size() == 1 )
    {
      // The same name in another folder — typical after an interrupted
      // `adb pull` (DCIM/DCIM/...). Exactly one candidate, so it is shown;
      // with several candidates nobody guesses.
      row.insert( QStringLiteral( "naDysku" ), sameStem.first() );
      elsewhere << row;
      claimed.insert( sameStem.first() );
      continue;
    }
    if ( sameStem.size() > 1 )
      row.insert( QStringLiteral( "kandydaci" ), sameStem );
    dead << row;
  }

  QVariantList orphans;
  for ( const QString &file : std::as_const( files ) )
  {
    if ( !claimed.contains( file ) )
      orphans << file;
  }

  // --- duplicates by content: size -> first 64 kB -> full md5 --------------
  QHash<qint64, QStringList> bySize;
  for ( const QString &file : std::as_const( files ) )
    bySize[QFileInfo( root.filePath( file ) ).size()] << file;

  int partial = 0;
  int full = 0;
  QHash<QString, QStringList> byHead;
  for ( auto it = bySize.constBegin(); it != bySize.constEnd(); ++it )
  {
    if ( it.value().size() < 2 )
      continue;
    for ( const QString &file : it.value() )
    {
      byHead[QStringLiteral( "%1|%2" ).arg( it.key() ).arg( md5Of( root.filePath( file ), HEAD_BYTES ) )] << file;
      ++partial;
    }
  }
  QHash<QString, QStringList> byMd5;
  for ( auto it = byHead.constBegin(); it != byHead.constEnd(); ++it )
  {
    if ( it.value().size() < 2 )
      continue;
    for ( const QString &file : it.value() )
    {
      byMd5[md5Of( root.filePath( file ) )] << file;
      ++full;
    }
  }
  QVariantList groups;
  for ( auto it = byMd5.constBegin(); it != byMd5.constEnd(); ++it )
  {
    if ( it.value().size() < 2 || it.key().isEmpty() )
      continue;
    QStringList members = it.value();
    members.sort();
    QVariantMap group;
    group.insert( QStringLiteral( "md5" ), it.key() );
    group.insert( QStringLiteral( "bajty" ), QFileInfo( root.filePath( members.first() ) ).size() );
    group.insert( QStringLiteral( "pliki" ), members );
    groups << group;
  }
  std::sort( groups.begin(), groups.end(), []( const QVariant &a, const QVariant &b ) {
    return a.toMap().value( QStringLiteral( "pliki" ) ).toStringList().first() < b.toMap().value( QStringLiteral( "pliki" ) ).toStringList().first();
  } );

  result.insert( QStringLiteral( "zdjec" ), files.size() );
  result.insert( QStringLiteral( "wpisow" ), index.size() );
  result.insert( QStringLiteral( "martwe" ), dead );
  result.insert( QStringLiteral( "wielkoscLiter" ), caseOnly );
  result.insert( QStringLiteral( "gdzieIndziej" ), elsewhere );
  result.insert( QStringLiteral( "obce" ), foreign );
  result.insert( QStringLiteral( "sieroty" ), orphans );
  result.insert( QStringLiteral( "grupyDuplikatow" ), groups );
  result.insert( QStringLiteral( "czesciowychMd5" ), partial );
  result.insert( QStringLiteral( "pelnychMd5" ), full );
  return result;
}

QVariantMap TidyEngine::scan( QgsProject *project ) const
{
  QVariantMap result;
  QgsProject *p = project ? project : QgsProject::instance();
  if ( !p || p->homePath().isEmpty() )
  {
    result.insert( QStringLiteral( "blad" ), tr( "Brak otwartego projektu" ) );
    return result;
  }
  const QString home = QDir( p->homePath() ).absolutePath();

  // --- 1. databases ---------------------------------------------------------
  const QSet<QString> inUse = databasesInUse( p );
  QVariantList databases = sourceDatabases( home, 3 );
  for ( QVariant &entry : databases )
  {
    QVariantMap info = entry.toMap();
    info.insert( QStringLiteral( "uzywana" ), inUse.contains( QFileInfo( info.value( QStringLiteral( "sciezka" ) ).toString() ).absoluteFilePath() ) );
    entry = info;
  }

  // --- 2. attachment rows against the disk ----------------------------------
  ZalacznikiUtils attachments;
  const QVariantMap index = attachments.photoIndex( p );
  const QVariantMap compared = compareWithDisk( home, index );

  // --- 3. report: text for people, TSV for tools -----------------------------
  const QString stamp = QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmmss" ) );
  const QString folder = QStringLiteral( "%1/export/porzadki_%2" ).arg( home, stamp );
  if ( !QDir().mkpath( folder ) )
  {
    result.insert( QStringLiteral( "blad" ), tr( "Nie da się utworzyć katalogu raportu %1" ).arg( folder ) );
    return result;
  }

  const QVariantList dead = compared.value( QStringLiteral( "martwe" ) ).toList();
  const QVariantList caseOnly = compared.value( QStringLiteral( "wielkoscLiter" ) ).toList();
  const QVariantList elsewhere = compared.value( QStringLiteral( "gdzieIndziej" ) ).toList();
  const QVariantList foreign = compared.value( QStringLiteral( "obce" ) ).toList();
  const QVariantList orphans = compared.value( QStringLiteral( "sieroty" ) ).toList();
  const QVariantList groups = compared.value( QStringLiteral( "grupyDuplikatow" ) ).toList();

  QString text;
  auto line = [&text]( const QString &s ) { text += s + QLatin1Char( '\n' ); };
  line( tr( "PORZĄDKOWANIE DANYCH — przegląd (tylko odczyt)" ) );
  line( tr( "projekt: %1" ).arg( home ) );
  line( tr( "czas: %1" ).arg( QDateTime::currentDateTime().toString( Qt::ISODate ) ) );
  line( QString() );
  line( tr( "1. BAZY W KATALOGU PROJEKTU (%1)" ).arg( databases.size() ) );
  line( tr( "   Rozmiar i data nie rozstrzygają — rozstrzygają liczniki i md5." ) );
  for ( const QVariant &entry : std::as_const( databases ) )
  {
    const QVariantMap info = entry.toMap();
    QStringList marks;
    if ( info.value( QStringLiteral( "uzywana" ) ).toBool() )
      marks << tr( "UŻYWANA PRZEZ PROJEKT" );
    if ( info.value( QStringLiteral( "wal" ) ).toBool() )
      marks << tr( "obok -wal: liczniki mogą być zaniżone" );
    if ( info.value( QStringLiteral( "kopiaPrzegladarki" ) ).toBool() )
      marks << tr( "nazwa z „(n)” — kopia z przeglądarki, nie decyzja" );
    line( QStringLiteral( "   %1" ).arg( QDir( home ).relativeFilePath( info.value( QStringLiteral( "sciezka" ) ).toString() ) ) );
    if ( info.contains( QStringLiteral( "blad" ) ) )
    {
      line( tr( "      nie da się odczytać: %1" ).arg( info.value( QStringLiteral( "blad" ) ).toString() ) );
      continue;
    }
    line( tr( "      obiektów %1, załączników %2 w %3 tabelach ZAL_, %4, md5 %5" )
            .arg( info.value( QStringLiteral( "obiektow" ) ).toLongLong() )
            .arg( info.value( QStringLiteral( "zalacznikow" ) ).toLongLong() )
            .arg( info.value( QStringLiteral( "tabelZal" ) ).toInt() )
            .arg( humanSize( info.value( QStringLiteral( "bajty" ) ).toLongLong() ) )
            .arg( info.value( QStringLiteral( "md5" ) ).toString() ) );
    if ( !marks.isEmpty() )
      line( QStringLiteral( "      ! %1" ).arg( marks.join( QStringLiteral( "; " ) ) ) );
  }
  line( QString() );
  line( tr( "2. ZDJĘCIA I WPISY" ) );
  line( tr( "   zdjęć w DCIM: %1, wpisów w tabelach załączników: %2" ).arg( compared.value( QStringLiteral( "zdjec" ) ).toInt() ).arg( compared.value( QStringLiteral( "wpisow" ) ).toInt() ) );
  line( tr( "   wpisy bez pliku: %1" ).arg( dead.size() ) );
  line( tr( "   plik jest, inna wielkość liter (.JPG/.jpg): %1 — nie strata, nazwa do poprawy" ).arg( caseOnly.size() ) );
  line( tr( "   ta sama nazwa w innym katalogu: %1 — np. po przerwanym adb pull" ).arg( elsewhere.size() ) );
  line( tr( "   adresy Androida/Mapit (nie są ścieżkami): %1" ).arg( foreign.size() ) );
  line( tr( "   pliki bez żadnego wpisu: %1" ).arg( orphans.size() ) );
  line( tr( "   grupy identycznych plików: %1 (md5 z 64 kB: %2, pełne: %3)" ).arg( groups.size() ).arg( compared.value( QStringLiteral( "czesciowychMd5" ) ).toInt() ).arg( compared.value( QStringLiteral( "pelnychMd5" ) ).toInt() ) );
  line( tr( "   Duplikat NIE znaczy „do skasowania” — to dwa punkty cofnięcia albo dwa wpisy." ) );
  line( QString() );
  line( tr( "Nic nie zostało zmienione. Szczegóły w znaleziska.tsv." ) );

  QString tsv = QStringLiteral( "rodzaj\tsciezka\twarstwa\tklucz\tparent_uuid\tna_dysku\n" );
  auto rowLine = [&tsv]( const QString &kind, const QVariantMap &row ) {
    tsv += QStringLiteral( "%1\t%2\t%3\t%4\t%5\t%6\n" )
             .arg( kind, row.value( QStringLiteral( "sciezka" ) ).toString(), row.value( QStringLiteral( "layer" ) ).toString(),
                   row.value( QStringLiteral( "key" ) ).toString(), row.value( QStringLiteral( "parentUuid" ) ).toString(),
                   row.value( QStringLiteral( "naDysku" ) ).toString() );
  };
  for ( const QVariant &v : dead )
    rowLine( QStringLiteral( "wpis_bez_pliku" ), v.toMap() );
  for ( const QVariant &v : caseOnly )
    rowLine( QStringLiteral( "wielkosc_liter" ), v.toMap() );
  for ( const QVariant &v : elsewhere )
    rowLine( QStringLiteral( "inny_katalog" ), v.toMap() );
  for ( const QVariant &v : foreign )
    rowLine( QStringLiteral( "adres_androida" ), v.toMap() );
  for ( const QVariant &v : orphans )
    tsv += QStringLiteral( "plik_bez_wpisu\t%1\t\t\t\t\n" ).arg( v.toString() );
  int groupNumber = 0;
  for ( const QVariant &v : groups )
  {
    ++groupNumber;
    const QVariantMap group = v.toMap();
    for ( const QString &file : group.value( QStringLiteral( "pliki" ) ).toStringList() )
      tsv += QStringLiteral( "duplikat_%1\t%2\t\t\t\t%3\n" ).arg( groupNumber ).arg( file, group.value( QStringLiteral( "md5" ) ).toString() );
  }

  const QString reportPath = folder + QStringLiteral( "/raport.txt" );
  const QString tsvPath = folder + QStringLiteral( "/znaleziska.tsv" );
  QStringList written;
  for ( const auto &[path, content] : { std::pair<QString, QString>( reportPath, text ), std::pair<QString, QString>( tsvPath, tsv ) } )
  {
    QFile file( path );
    if ( file.open( QIODevice::WriteOnly | QIODevice::Truncate ) )
    {
      file.write( content.toUtf8() );
      file.close();
      written << path;
    }
  }
  if ( written.isEmpty() )
  {
    result.insert( QStringLiteral( "blad" ), tr( "Nie da się zapisać raportu w %1" ).arg( folder ) );
    return result;
  }

  // Counters for the message, capped lists for the next patch's screens.
  result.insert( QStringLiteral( "bazy" ), databases.size() );
  result.insert( QStringLiteral( "martwe" ), dead.size() );
  result.insert( QStringLiteral( "wielkoscLiter" ), caseOnly.size() );
  result.insert( QStringLiteral( "gdzieIndziej" ), elsewhere.size() );
  result.insert( QStringLiteral( "obce" ), foreign.size() );
  result.insert( QStringLiteral( "sieroty" ), orphans.size() );
  result.insert( QStringLiteral( "grupyDuplikatow" ), groups.size() );
  result.insert( QStringLiteral( "zdjec" ), compared.value( QStringLiteral( "zdjec" ) ) );
  result.insert( QStringLiteral( "wpisow" ), compared.value( QStringLiteral( "wpisow" ) ) );
  result.insert( QStringLiteral( "listaBaz" ), databases );
  result.insert( QStringLiteral( "listaMartwych" ), capped( dead ) );
  result.insert( QStringLiteral( "listaSierot" ), capped( orphans ) );
  result.insert( QStringLiteral( "listaDuplikatow" ), capped( groups ) );
  result.insert( QStringLiteral( "pliki" ), written );
  result.insert( QStringLiteral( "katalog" ), folder );
  result.insert( QStringLiteral( "raport" ), text );
  return result;
}
