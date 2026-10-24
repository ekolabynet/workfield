/***************************************************************************
  journalutils.cpp - JournalUtils

 ---------------------
 WorkField 24.10.2026 [WF-JOURNAL]. See journalutils.h.
 ***************************************************************************/

#include "journalutils.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QSet>
#include <QSettings>
#include <QSysInfo>
#include <qgsmessagelog.h>
#include <qgsproject.h>
#include <qgsproviderregistry.h>
#include <qgsvectorlayer.h>
#include <sqlite3.h>

namespace
{
  const int kVersion = 1;

  const char *kSchema =
    "CREATE TABLE IF NOT EXISTS WF_SESSION (KEY TEXT PRIMARY KEY, VALUE TEXT);"
    "CREATE TABLE IF NOT EXISTS WF_JOURNAL ("
    "  SEQ INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  ENTRY_UUID TEXT NOT NULL,"
    "  TIME_UTC TEXT NOT NULL,"
    "  TABLE_NAME TEXT NOT NULL,"
    "  FID INTEGER,"
    "  OBJECT_UUID TEXT,"
    "  EVENT TEXT NOT NULL,"
    "  GEOMETRY_CHANGED INTEGER,"
    "  CHANGED TEXT,"
    "  OLD_GEOMETRY BLOB,"
    "  OPERATION TEXT,"
    "  ORIGIN TEXT,"
    "  DEVICE TEXT,"
    "  APP_VERSION TEXT,"
    "  AUTHOR TEXT );"
    "CREATE INDEX IF NOT EXISTS WF_JOURNAL_OBJECT ON WF_JOURNAL(TABLE_NAME, OBJECT_UUID);";

  //! Tables never journaled: technical, heavy (NIEBO_EPOKA: 71 thousand rows), reference.
  bool skipped( const QString &table )
  {
    static const QStringList prefixes { QStringLiteral( "wf_" ), QStringLiteral( "niebo_" ), QStringLiteral( "gpkg_" ), QStringLiteral( "rtree_" ), QStringLiteral( "sqlite_" ), QStringLiteral( "ref_" ) };
    const QString lower = table.toLower();
    for ( const QString &prefix : prefixes )
    {
      if ( lower.startsWith( prefix ) )
        return true;
    }
    return false;
  }

  QString quoted( const QString &name )
  {
    return QLatin1Char( '"' ) + QString( name ).replace( QLatin1Char( '"' ), QLatin1String( "\"\"" ) ) + QLatin1Char( '"' );
  }

  QString literal( const QString &text )
  {
    return QLatin1Char( '\'' ) + QString( text ).replace( QLatin1Char( '\'' ), QLatin1String( "''" ) ) + QLatin1Char( '\'' );
  }

  QStringList stringColumn( sqlite3 *db, const QString &sql, const QString &bind = QString() )
  {
    QStringList result;
    sqlite3_stmt *stmt = nullptr;
    if ( sqlite3_prepare_v2( db, sql.toUtf8().constData(), -1, &stmt, nullptr ) != SQLITE_OK )
      return result;
    if ( !bind.isNull() )
      sqlite3_bind_text( stmt, 1, bind.toUtf8().constData(), -1, SQLITE_TRANSIENT );
    while ( sqlite3_step( stmt ) == SQLITE_ROW )
      result << QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, 0 ) ) );
    sqlite3_finalize( stmt );
    return result;
  }

  bool exec( sqlite3 *db, const QString &sql, QString *error )
  {
    char *message = nullptr;
    if ( sqlite3_exec( db, sql.toUtf8().constData(), nullptr, nullptr, &message ) != SQLITE_OK )
    {
      if ( error )
        *error = QString::fromUtf8( message ? message : "?" );
      sqlite3_free( message );
      return false;
    }
    return true;
  }

  QStringList workingTables( sqlite3 *db )
  {
    QStringList names = stringColumn( db, QStringLiteral( "SELECT table_name FROM gpkg_contents WHERE data_type IN ('features','attributes')" ) );
    // attachment tables made by older versions are not always registered
    names << stringColumn( db, QStringLiteral( "SELECT name FROM sqlite_master WHERE type='table' AND upper(name) LIKE 'ZAL\\_%' ESCAPE '\\'" ) );
    QStringList result;
    for ( const QString &name : std::as_const( names ) )
    {
      if ( !skipped( name ) && !result.contains( name ) )
        result << name;
    }
    return result;
  }

  QString sessionValue( const QString &key )
  {
    return QStringLiteral( "(SELECT VALUE FROM WF_SESSION WHERE KEY = '%1')" ).arg( key );
  }

  //! BLOBs (thumbnails) cannot go into JSON: their size instead.
  QString jsonValue( const QString &column )
  {
    const QString c = QStringLiteral( "OLD." ) + quoted( column );
    return QStringLiteral( "json_quote(CASE typeof(%1) WHEN 'blob' THEN '<blob ' || length(%1) || ' B>' ELSE %1 END)" ).arg( c );
  }

  QString triggerName( const QString &table, const QString &suffix )
  {
    return QStringLiteral( "wf_journal_v%1_%2_%3" ).arg( kVersion ).arg( table, suffix );
  }

  //! name → SQL of the three triggers of \a table; empty without a primary key.
  QList<QPair<QString, QString>> triggersFor( sqlite3 *db, const QString &table )
  {
    QList<QPair<QString, QString>> result;
    QStringList columns;
    QString primaryKey;
    sqlite3_stmt *stmt = nullptr;
    if ( sqlite3_prepare_v2( db, QStringLiteral( "PRAGMA table_info(%1)" ).arg( quoted( table ) ).toUtf8().constData(), -1, &stmt, nullptr ) == SQLITE_OK )
    {
      while ( sqlite3_step( stmt ) == SQLITE_ROW )
      {
        const QString name = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, 1 ) ) );
        columns << name;
        if ( sqlite3_column_int( stmt, 5 ) > 0 && primaryKey.isEmpty() )
          primaryKey = name;
      }
      sqlite3_finalize( stmt );
    }
    if ( primaryKey.isEmpty() )
      return result;

    const QStringList geometryColumns = stringColumn( db, QStringLiteral( "SELECT column_name FROM gpkg_geometry_columns WHERE table_name = ?" ), table );
    const QString geometry = geometryColumns.value( 0 );
    QString uuid;
    QStringList attributes;
    for ( const QString &column : std::as_const( columns ) )
    {
      if ( column.compare( QLatin1String( "uuid" ), Qt::CaseInsensitive ) == 0 && uuid.isEmpty() )
        uuid = column;
      if ( column != primaryKey && column != geometry )
        attributes << column;
    }

    const QString common = QStringLiteral( "lower(hex(randomblob(16))), strftime('%Y-%m-%dT%H:%M:%fZ','now'), %1" ).arg( literal( table ) );
    const QString session = QStringList { sessionValue( QStringLiteral( "operation" ) ), sessionValue( QStringLiteral( "origin" ) ), sessionValue( QStringLiteral( "device" ) ), sessionValue( QStringLiteral( "app_version" ) ), sessionValue( QStringLiteral( "author" ) ) }.join( QStringLiteral( ", " ) );
    const QString insertInto = QStringLiteral( "INSERT INTO WF_JOURNAL (ENTRY_UUID, TIME_UTC, TABLE_NAME, FID, OBJECT_UUID, EVENT, GEOMETRY_CHANGED, CHANGED, OLD_GEOMETRY, OPERATION, ORIGIN, DEVICE, APP_VERSION, AUTHOR)" );
    const QString uuidNew = uuid.isEmpty() ? QStringLiteral( "NULL" ) : QStringLiteral( "NEW." ) + quoted( uuid );
    const QString uuidOld = uuid.isEmpty() ? QStringLiteral( "NULL" ) : QStringLiteral( "OLD." ) + quoted( uuid );

    // INSERT: the new state is in the table itself — only the fact
    result << qMakePair( triggerName( table, QStringLiteral( "ins" ) ), QStringLiteral( "CREATE TRIGGER %1 AFTER INSERT ON %2 BEGIN %3 VALUES (%4, NEW.%5, %6, 'created', NULL, NULL, NULL, %7); END" ).arg( quoted( triggerName( table, QStringLiteral( "ins" ) ) ), quoted( table ), insertInto, common, quoted( primaryKey ), uuidNew, session ) );

    // UPDATE: only when something changed; old values of the changed fields
    QStringList changedParts;
    QStringList anyChange;
    for ( const QString &attribute : std::as_const( attributes ) )
    {
      changedParts << QStringLiteral( "CASE WHEN OLD.%1 IS NOT NEW.%1 THEN ',' || json_quote(%2) || ':' || %3 ELSE '' END" ).arg( quoted( attribute ), literal( attribute ), jsonValue( attribute ) );
      anyChange << QStringLiteral( "OLD.%1 IS NOT NEW.%1" ).arg( quoted( attribute ) );
    }
    const QString geometryChanged = geometry.isEmpty() ? QStringLiteral( "0" ) : QStringLiteral( "OLD.%1 IS NOT NEW.%1" ).arg( quoted( geometry ) );
    if ( !geometry.isEmpty() )
      anyChange << geometryChanged;
    const QString oldGeometry = geometry.isEmpty() ? QStringLiteral( "NULL" ) : QStringLiteral( "CASE WHEN %1 THEN OLD.%2 END" ).arg( geometryChanged, quoted( geometry ) );
    const QString changed = changedParts.isEmpty() ? QStringLiteral( "NULL" ) : QStringLiteral( "NULLIF('{' || substr(%1, 2) || '}', '{}')" ).arg( changedParts.join( QStringLiteral( " || " ) ) );
    result << qMakePair( triggerName( table, QStringLiteral( "upd" ) ), QStringLiteral( "CREATE TRIGGER %1 AFTER UPDATE ON %2 WHEN %3 BEGIN %4 VALUES (%5, NEW.%6, %7, 'updated', %8, %9, %10, %11); END" ).arg( quoted( triggerName( table, QStringLiteral( "upd" ) ) ), quoted( table ), anyChange.isEmpty() ? QStringLiteral( "0" ) : anyChange.join( QStringLiteral( " OR " ) ), insertInto, common, quoted( primaryKey ), uuidNew, geometryChanged, changed ).arg( oldGeometry, session ) );

    // DELETE: all old values and the old geometry — enough to bring it back
    QStringList allParts;
    for ( const QString &attribute : std::as_const( attributes ) )
      allParts << QStringLiteral( "',' || json_quote(%1) || ':' || %2" ).arg( literal( attribute ), jsonValue( attribute ) );
    const QString all = allParts.isEmpty() ? QStringLiteral( "NULL" ) : QStringLiteral( "'{' || substr(%1, 2) || '}'" ).arg( allParts.join( QStringLiteral( " || " ) ) );
    result << qMakePair( triggerName( table, QStringLiteral( "del" ) ), QStringLiteral( "CREATE TRIGGER %1 AFTER DELETE ON %2 BEGIN %3 VALUES (%4, OLD.%5, %6, 'deleted', NULL, %7, %8, %9); END" ).arg( quoted( triggerName( table, QStringLiteral( "del" ) ) ), quoted( table ), insertInto, common, quoted( primaryKey ), uuidOld, all, geometry.isEmpty() ? QStringLiteral( "NULL" ) : QStringLiteral( "OLD." ) + quoted( geometry ), session ) );
    return result;
  }

  sqlite3 *openDatabase( const QString &gpkg, QString *error )
  {
    sqlite3 *db = nullptr;
    if ( sqlite3_open_v2( gpkg.toUtf8().constData(), &db, SQLITE_OPEN_READWRITE, nullptr ) != SQLITE_OK )
    {
      if ( error )
        *error = db ? QString::fromUtf8( sqlite3_errmsg( db ) ) : QStringLiteral( "?" );
      sqlite3_close( db );
      return nullptr;
    }
    // the app holds the same file open through OGR: wait instead of failing
    sqlite3_busy_timeout( db, 5000 );
    return db;
  }
} // namespace

JournalUtils::JournalUtils( QObject *parent )
  : QObject( parent )
{
}

QString JournalUtils::gpkgPath( const QgsVectorLayer *layer )
{
  if ( !layer || layer->providerType() != QLatin1String( "ogr" ) )
    return QString();
  const QVariantMap parts = QgsProviderRegistry::instance()->decodeUri( QStringLiteral( "ogr" ), layer->source() );
  const QString path = parts.value( QStringLiteral( "path" ) ).toString();
  if ( !path.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive ) )
    return QString();
  if ( QFileInfo( path ).fileName().compare( QLatin1String( "foto_tagi.gpkg" ), Qt::CaseInsensitive ) == 0 )
    return QString();
  return path;
}

bool JournalUtils::install( const QString &gpkg, const QString &table, QString *error, int *tables, int *refreshed )
{
  sqlite3 *db = openDatabase( gpkg, error );
  if ( !db )
    return false;

  bool ok = exec( db, QString::fromLatin1( kSchema ), error );
  const QStringList names = table.isEmpty() ? workingTables( db ) : QStringList { table };
  int changedTables = 0;
  if ( ok )
  {
    ok = exec( db, QStringLiteral( "BEGIN" ), error );
    for ( const QString &name : names )
    {
      if ( !ok || skipped( name ) )
        continue;
      const QList<QPair<QString, QString>> wanted = triggersFor( db, name );
      // compare with what is there: no DDL when nothing changed
      bool same = !wanted.isEmpty();
      for ( const auto &trigger : wanted )
      {
        const QStringList existing = stringColumn( db, QStringLiteral( "SELECT sql FROM sqlite_master WHERE type='trigger' AND name = ?" ), trigger.first );
        if ( existing.value( 0 ) != trigger.second )
          same = false;
      }
      const QStringList present = stringColumn( db, QStringLiteral( "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name = ? AND name LIKE 'wf\\_journal\\_%' ESCAPE '\\'" ), name );
      if ( same && present.size() == wanted.size() )
        continue;
      for ( const QString &old : present )
        ok = ok && exec( db, QStringLiteral( "DROP TRIGGER IF EXISTS %1" ).arg( quoted( old ) ), error );
      for ( const auto &trigger : wanted )
        ok = ok && exec( db, trigger.second, error );
      ++changedTables;
    }
    exec( db, ok ? QStringLiteral( "COMMIT" ) : QStringLiteral( "ROLLBACK" ), nullptr );
  }
  sqlite3_close( db );
  if ( tables )
    *tables += names.size();
  if ( refreshed )
    *refreshed += changedTables;
  return ok;
}

bool JournalUtils::dropTriggers( const QString &gpkg, const QString &table, QString *error )
{
  sqlite3 *db = openDatabase( gpkg, error );
  if ( !db )
    return false;
  const QStringList names = table.isEmpty()
                              ? stringColumn( db, QStringLiteral( "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'wf\\_journal\\_%' ESCAPE '\\'" ) )
                              : stringColumn( db, QStringLiteral( "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name = ? AND name LIKE 'wf\\_journal\\_%' ESCAPE '\\'" ), table );
  bool ok = true;
  for ( const QString &name : names )
    ok = ok && exec( db, QStringLiteral( "DROP TRIGGER IF EXISTS %1" ).arg( quoted( name ) ), error );
  sqlite3_close( db );
  return ok;
}

bool JournalUtils::setSessionValue( const QString &gpkg, const QString &key, const QString &value )
{
  if ( gpkg.isEmpty() )
    return false;
  sqlite3 *db = openDatabase( gpkg, nullptr );
  if ( !db )
    return false;
  bool ok = exec( db, QStringLiteral( "CREATE TABLE IF NOT EXISTS WF_SESSION (KEY TEXT PRIMARY KEY, VALUE TEXT)" ), nullptr );
  sqlite3_stmt *stmt = nullptr;
  if ( ok && sqlite3_prepare_v2( db, value.isEmpty() ? "DELETE FROM WF_SESSION WHERE KEY = ?1" : "INSERT OR REPLACE INTO WF_SESSION (KEY, VALUE) VALUES (?1, ?2)", -1, &stmt, nullptr ) == SQLITE_OK )
  {
    sqlite3_bind_text( stmt, 1, key.toUtf8().constData(), -1, SQLITE_TRANSIENT );
    if ( !value.isEmpty() )
      sqlite3_bind_text( stmt, 2, value.toUtf8().constData(), -1, SQLITE_TRANSIENT );
    ok = sqlite3_step( stmt ) == SQLITE_DONE;
    sqlite3_finalize( stmt );
  }
  sqlite3_close( db );
  return ok;
}

QVariantMap JournalUtils::installForProject( QgsProject *project )
{
  QVariantMap result;
  QStringList files;
  QStringList errors;
  int tables = 0;
  int refreshed = 0;
  if ( project )
  {
    const QMap<QString, QgsMapLayer *> layers = project->mapLayers();
    for ( QgsMapLayer *mapLayer : layers )
    {
      const QString path = gpkgPath( qobject_cast<QgsVectorLayer *>( mapLayer ) );
      if ( path.isEmpty() || files.contains( path ) || !QFileInfo( path ).isWritable() )
        continue;
      files << path;
    }
    const QString device = QSysInfo::machineHostName() + QStringLiteral( " / " ) + QSysInfo::prettyProductName();
    for ( const QString &path : std::as_const( files ) )
    {
      QString error;
      if ( !install( path, QString(), &error, &tables, &refreshed ) )
        errors << QFileInfo( path ).fileName() + QStringLiteral( ": " ) + error;
      setSessionValue( path, QStringLiteral( "device" ), device );
      setSessionValue( path, QStringLiteral( "app_version" ), QCoreApplication::applicationVersion() );
      // who: the field signature from Settings → Teren (empty: not recorded)
      setSessionValue( path, QStringLiteral( "author" ), QSettings().value( QStringLiteral( "workfield/podpisTerenowy" ) ).toString() );
      // a crash in the middle of an operation must not mark later entries
      setSessionValue( path, QStringLiteral( "operation" ), QString() );
      setSessionValue( path, QStringLiteral( "origin" ), QString() );
    }
  }
  result.insert( QStringLiteral( "files" ), files.size() );
  result.insert( QStringLiteral( "tables" ), tables );
  result.insert( QStringLiteral( "refreshed" ), refreshed );
  result.insert( QStringLiteral( "errors" ), errors );
  QgsMessageLog::logMessage( QStringLiteral( "WorkField [WF-JOURNAL]: %1 files, %2 tables, %3 refreshed%4" ).arg( files.size() ).arg( tables ).arg( refreshed ).arg( errors.isEmpty() ? QString() : QStringLiteral( ", ERRORS: " ) + errors.join( QStringLiteral( "; " ) ) ), QStringLiteral( "WorkField" ), errors.isEmpty() ? Qgis::Info : Qgis::Warning );
  return result;
}

JournalUtils::OperationScope::OperationScope( const QgsVectorLayer *layer, const QString &operation, const QString &origin )
  : mGpkg( JournalUtils::gpkgPath( layer ) )
{
  if ( mGpkg.isEmpty() )
    return;
  JournalUtils::setSessionValue( mGpkg, QStringLiteral( "operation" ), operation );
  JournalUtils::setSessionValue( mGpkg, QStringLiteral( "origin" ), origin );
}

JournalUtils::OperationScope::~OperationScope()
{
  if ( mGpkg.isEmpty() )
    return;
  JournalUtils::setSessionValue( mGpkg, QStringLiteral( "operation" ), QString() );
  JournalUtils::setSessionValue( mGpkg, QStringLiteral( "origin" ), QString() );
}
