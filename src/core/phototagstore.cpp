/**
 * phototagstore.cpp - WorkField
 */
#include "phototagstore.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QVariantMap>
#include <sqlite3.h>

#include <qgseditorwidgetsetup.h>
#include <qgsproject.h>
#include <qgsvectorlayer.h>

PhotoTagStore::PhotoTagStore( QObject *parent )
  : QObject( parent )
{
}

PhotoTagStore::~PhotoTagStore()
{
  close();
}

void PhotoTagStore::setAuthor( const QString &author )
{
  const QString cleaned = author.trimmed().isEmpty() ? QStringLiteral( "workfield" ) : author.trimmed();
  if ( cleaned == mAuthor )
    return;
  mAuthor = cleaned;
  emit authorChanged();
}

bool PhotoTagStore::open( const QString &projectDir )
{
  close();
  if ( projectDir.isEmpty() || !QDir( projectDir ).exists() )
  {
    qWarning() << "PhotoTagStore: katalog projektu nie istnieje:" << projectDir;
    return false;
  }

  const QString path = QDir( projectDir ).filePath( QStringLiteral( "foto_tagi.gpkg" ) );
  if ( sqlite3_open_v2( path.toUtf8().constData(), &mDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr ) != SQLITE_OK )
  {
    qWarning() << "PhotoTagStore: nie mozna otworzyc" << path << ( mDb ? sqlite3_errmsg( mDb ) : "" );
    close();
    return false;
  }

  if ( !ensureSchema() )
  {
    close();
    return false;
  }

  mProjectDir = projectDir;
  mSpeciesLoaded = false;
  mProjectSpecies.clear();
  mFormSpeciesLoaded = false;
  mFormSpecies.clear();
  mStoragePath = path;
  emit storagePathChanged();
  return true;
}

void PhotoTagStore::close()
{
  if ( mDb )
  {
    sqlite3_close( mDb );
    mDb = nullptr;
  }
  if ( !mStoragePath.isEmpty() )
  {
    mStoragePath.clear();
    emit storagePathChanged();
  }
}

bool PhotoTagStore::ensureSchema()
{
  // Minimalny, poprawny GeoPackage z jedna tabela atrybutowa.
  static const char *schema =
    "PRAGMA application_id = 0x47504B47;"
    "PRAGMA user_version = 10300;"
    "CREATE TABLE IF NOT EXISTS gpkg_spatial_ref_sys ("
    "  srs_name TEXT NOT NULL, srs_id INTEGER PRIMARY KEY,"
    "  organization TEXT NOT NULL, organization_coordsys_id INTEGER NOT NULL,"
    "  definition TEXT NOT NULL, description TEXT );"
    "INSERT OR IGNORE INTO gpkg_spatial_ref_sys VALUES"
    "  ('Undefined Cartesian', -1, 'NONE', -1, 'undefined', NULL),"
    "  ('Undefined Geographic', 0, 'NONE', 0, 'undefined', NULL),"
    "  ('WGS 84', 4326, 'EPSG', 4326, 'GEOGCS[\"WGS 84\",DATUM[\"WGS_1984\",SPHEROID[\"WGS 84\",6378137,298.257223563]],PRIMEM[\"Greenwich\",0],UNIT[\"degree\",0.0174532925199433]]', NULL);"
    "CREATE TABLE IF NOT EXISTS gpkg_contents ("
    "  table_name TEXT NOT NULL PRIMARY KEY, data_type TEXT NOT NULL,"
    "  identifier TEXT UNIQUE, description TEXT DEFAULT '',"
    "  last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),"
    "  min_x DOUBLE, min_y DOUBLE, max_x DOUBLE, max_y DOUBLE, srs_id INTEGER );"
    "CREATE TABLE IF NOT EXISTS FOTO_TAGI ("
    "  fid INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  foto TEXT NOT NULL,"
    "  x REAL, y REAL,"
    "  tag TEXT NOT NULL,"
    "  pokrycie_procent REAL,"
    "  uwagi TEXT,"
    "  autor TEXT,"
    "  data_czas TEXT NOT NULL );"
    "INSERT OR IGNORE INTO gpkg_contents(table_name, data_type, identifier, description)"
    "  VALUES('FOTO_TAGI', 'attributes', 'FOTO_TAGI', 'WorkField: tagi zdjec projektu');"
    "CREATE INDEX IF NOT EXISTS idx_foto_tagi_foto ON FOTO_TAGI(foto);";

  char *err = nullptr;
  if ( sqlite3_exec( mDb, schema, nullptr, nullptr, &err ) != SQLITE_OK )
  {
    qWarning() << "PhotoTagStore: blad schematu:" << ( err ? err : "?" );
    sqlite3_free( err );
    return false;
  }
  return true;
}

QVariantList PhotoTagStore::tagsForPhoto( const QString &foto )
{
  QVariantList result;
  if ( !mDb )
    return result;

  sqlite3_stmt *stmt = nullptr;
  if ( sqlite3_prepare_v2( mDb, "SELECT fid, tag, pokrycie_procent, uwagi, autor, data_czas, x, y FROM FOTO_TAGI WHERE foto = ?1 ORDER BY fid", -1, &stmt, nullptr ) != SQLITE_OK )
    return result;

  sqlite3_bind_text( stmt, 1, foto.toUtf8().constData(), -1, SQLITE_TRANSIENT );
  while ( sqlite3_step( stmt ) == SQLITE_ROW )
  {
    QVariantMap row;
    row[QStringLiteral( "fid" )] = sqlite3_column_int( stmt, 0 );
    row[QStringLiteral( "tag" )] = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, 1 ) ) );
    row[QStringLiteral( "pokrycie" )] = sqlite3_column_type( stmt, 2 ) == SQLITE_NULL ? QVariant() : sqlite3_column_double( stmt, 2 );
    row[QStringLiteral( "uwagi" )] = sqlite3_column_type( stmt, 3 ) == SQLITE_NULL ? QString() : QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, 3 ) ) );
    row[QStringLiteral( "autor" )] = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, 4 ) ) );
    row[QStringLiteral( "data_czas" )] = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, 5 ) ) );
    row[QStringLiteral( "x" )] = sqlite3_column_type( stmt, 6 ) == SQLITE_NULL ? -1.0 : sqlite3_column_double( stmt, 6 );
    row[QStringLiteral( "y" )] = sqlite3_column_type( stmt, 7 ) == SQLITE_NULL ? -1.0 : sqlite3_column_double( stmt, 7 );
    result << row;
  }
  sqlite3_finalize( stmt );
  return result;
}

int PhotoTagStore::addTag( const QString &foto, const QString &tag, double pokrycie, const QString &uwagi, double x, double y )
{
  if ( !mDb || foto.isEmpty() || tag.trimmed().isEmpty() )
    return -1;

  sqlite3_stmt *stmt = nullptr;
  if ( sqlite3_prepare_v2( mDb, "INSERT INTO FOTO_TAGI(foto, x, y, tag, pokrycie_procent, uwagi, autor, data_czas) VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)", -1, &stmt, nullptr ) != SQLITE_OK )
    return -1;

  sqlite3_bind_text( stmt, 1, foto.toUtf8().constData(), -1, SQLITE_TRANSIENT );
  if ( x >= 0 && y >= 0 )
  {
    sqlite3_bind_double( stmt, 2, x );
    sqlite3_bind_double( stmt, 3, y );
  }
  else
  {
    sqlite3_bind_null( stmt, 2 );
    sqlite3_bind_null( stmt, 3 );
  }
  sqlite3_bind_text( stmt, 4, tag.trimmed().toUtf8().constData(), -1, SQLITE_TRANSIENT );
  if ( pokrycie >= 0 )
    sqlite3_bind_double( stmt, 5, pokrycie );
  else
    sqlite3_bind_null( stmt, 5 );
  if ( uwagi.trimmed().isEmpty() )
    sqlite3_bind_null( stmt, 6 );
  else
    sqlite3_bind_text( stmt, 6, uwagi.trimmed().toUtf8().constData(), -1, SQLITE_TRANSIENT );
  sqlite3_bind_text( stmt, 7, mAuthor.toUtf8().constData(), -1, SQLITE_TRANSIENT );
  sqlite3_bind_text( stmt, 8, QDateTime::currentDateTime().toString( Qt::ISODate ).toUtf8().constData(), -1, SQLITE_TRANSIENT );

  const bool ok = sqlite3_step( stmt ) == SQLITE_DONE;
  sqlite3_finalize( stmt );
  if ( !ok )
  {
    qWarning() << "PhotoTagStore: addTag nieudany:" << sqlite3_errmsg( mDb );
    return -1;
  }
  emit tagsChanged( foto );
  return static_cast<int>( sqlite3_last_insert_rowid( mDb ) );
}

bool PhotoTagStore::removeTag( int fid )
{
  if ( !mDb )
    return false;

  QString foto;
  sqlite3_stmt *sel = nullptr;
  if ( sqlite3_prepare_v2( mDb, "SELECT foto FROM FOTO_TAGI WHERE fid = ?1", -1, &sel, nullptr ) == SQLITE_OK )
  {
    sqlite3_bind_int( sel, 1, fid );
    if ( sqlite3_step( sel ) == SQLITE_ROW )
      foto = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( sel, 0 ) ) );
    sqlite3_finalize( sel );
  }

  sqlite3_stmt *stmt = nullptr;
  if ( sqlite3_prepare_v2( mDb, "DELETE FROM FOTO_TAGI WHERE fid = ?1", -1, &stmt, nullptr ) != SQLITE_OK )
    return false;
  sqlite3_bind_int( stmt, 1, fid );
  const bool ok = sqlite3_step( stmt ) == SQLITE_DONE;
  sqlite3_finalize( stmt );
  if ( ok && !foto.isEmpty() )
    emit tagsChanged( foto );
  return ok;
}

int PhotoTagStore::tagCount( const QString &foto )
{
  if ( !mDb )
    return 0;
  sqlite3_stmt *stmt = nullptr;
  if ( sqlite3_prepare_v2( mDb, "SELECT count(*) FROM FOTO_TAGI WHERE foto = ?1", -1, &stmt, nullptr ) != SQLITE_OK )
    return 0;
  sqlite3_bind_text( stmt, 1, foto.toUtf8().constData(), -1, SQLITE_TRANSIENT );
  int n = 0;
  if ( sqlite3_step( stmt ) == SQLITE_ROW )
    n = sqlite3_column_int( stmt, 0 );
  sqlite3_finalize( stmt );
  return n;
}

QStringList PhotoTagStore::knownTags()
{
  QStringList result;
  if ( !mDb )
    return result;
  sqlite3_stmt *stmt = nullptr;
  if ( sqlite3_prepare_v2( mDb, "SELECT DISTINCT tag FROM FOTO_TAGI ORDER BY tag COLLATE NOCASE", -1, &stmt, nullptr ) != SQLITE_OK )
    return result;
  while ( sqlite3_step( stmt ) == SQLITE_ROW )
    result << QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, 0 ) ) );
  sqlite3_finalize( stmt );
  return result;
}

QStringList PhotoTagStore::recentTags( int limit )
{
  QStringList result;
  if ( !mDb )
    return result;
  sqlite3_stmt *stmt = nullptr;
  if ( sqlite3_prepare_v2( mDb, "SELECT tag FROM FOTO_TAGI GROUP BY tag ORDER BY MAX(data_czas) DESC LIMIT ?1", -1, &stmt, nullptr ) != SQLITE_OK )
    return result;
  sqlite3_bind_int( stmt, 1, limit );
  while ( sqlite3_step( stmt ) == SQLITE_ROW )
    result << QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, 0 ) ) );
  sqlite3_finalize( stmt );
  return result;
}

QStringList PhotoTagStore::projectSpecies()
{
  if ( mSpeciesLoaded )
    return mProjectSpecies;
  mSpeciesLoaded = true;
  mProjectSpecies.clear();
  if ( mProjectDir.isEmpty() )
    return mProjectSpecies;

  QSet<QString> unique;
  const QStringList gpkgs = QDir( mProjectDir ).entryList( QStringList() << QStringLiteral( "*.gpkg" ), QDir::Files );
  for ( const QString &name : gpkgs )
  {
    if ( name == QLatin1String( "foto_tagi.gpkg" ) )
      continue;
    sqlite3 *db = nullptr;
    const QString path = QDir( mProjectDir ).filePath( name );
    if ( sqlite3_open_v2( path.toUtf8().constData(), &db, SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
    {
      if ( db )
        sqlite3_close( db );
      continue;
    }

    QStringList tables;
    sqlite3_stmt *ts = nullptr;
    if ( sqlite3_prepare_v2( db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'gpkg_%' AND name NOT LIKE 'rtree_%' AND name NOT LIKE 'sqlite_%'", -1, &ts, nullptr ) == SQLITE_OK )
    {
      while ( sqlite3_step( ts ) == SQLITE_ROW )
        tables << QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( ts, 0 ) ) );
      sqlite3_finalize( ts );
    }

    for ( const QString &table : tables )
    {
      QString kolumna;
      sqlite3_stmt *ci = nullptr;
      const QString pragma = QStringLiteral( "PRAGMA table_info(\"%1\")" ).arg( QString( table ).replace( '"', QString() ) );
      if ( sqlite3_prepare_v2( db, pragma.toUtf8().constData(), -1, &ci, nullptr ) == SQLITE_OK )
      {
        while ( sqlite3_step( ci ) == SQLITE_ROW )
        {
          const QString col = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( ci, 1 ) ) );
          if ( col.compare( QLatin1String( "gatunek" ), Qt::CaseInsensitive ) == 0 )
          {
            kolumna = col;
            break;
          }
        }
        sqlite3_finalize( ci );
      }
      if ( kolumna.isEmpty() )
        continue;

      const QString sel = QStringLiteral( "SELECT DISTINCT \"%1\" FROM \"%2\" WHERE \"%1\" IS NOT NULL AND trim(\"%1\") <> ''" ).arg( kolumna, QString( table ).replace( '"', QString() ) );
      sqlite3_stmt *vs = nullptr;
      if ( sqlite3_prepare_v2( db, sel.toUtf8().constData(), -1, &vs, nullptr ) == SQLITE_OK )
      {
        while ( sqlite3_step( vs ) == SQLITE_ROW )
          unique.insert( QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( vs, 0 ) ) ).trimmed() );
        sqlite3_finalize( vs );
      }
    }
    sqlite3_close( db );
  }

  mProjectSpecies = QStringList( unique.begin(), unique.end() );
  mProjectSpecies.sort( Qt::CaseInsensitive );
  return mProjectSpecies;
}

QVariantList PhotoTagStore::tagStats( int limit )
{
  QVariantList result;
  if ( !mDb )
    return result;
  sqlite3_stmt *stmt = nullptr;
  if ( sqlite3_prepare_v2( mDb, "SELECT tag, count(*) FROM FOTO_TAGI GROUP BY tag ORDER BY count(*) DESC, tag COLLATE NOCASE LIMIT ?1", -1, &stmt, nullptr ) != SQLITE_OK )
    return result;
  sqlite3_bind_int( stmt, 1, limit );
  while ( sqlite3_step( stmt ) == SQLITE_ROW )
  {
    QVariantMap row;
    row[QStringLiteral( "tag" )] = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, 0 ) ) );
    row[QStringLiteral( "n" )] = sqlite3_column_int( stmt, 1 );
    result << row;
  }
  sqlite3_finalize( stmt );
  return result;
}

QStringList PhotoTagStore::formSpecies()
{
  if ( mFormSpeciesLoaded )
    return mFormSpecies;
  mFormSpeciesLoaded = true;
  mFormSpecies.clear();

  QSet<QString> unique;
  const QMap<QString, QgsMapLayer *> layers = QgsProject::instance()->mapLayers();
  for ( auto it = layers.constBegin(); it != layers.constEnd(); ++it )
  {
    QgsVectorLayer *vl = qobject_cast<QgsVectorLayer *>( it.value() );
    if ( !vl )
      continue;
    const QgsFields fields = vl->fields();
    for ( int i = 0; i < fields.count(); ++i )
    {
      if ( fields.at( i ).name().compare( QLatin1String( "gatunek" ), Qt::CaseInsensitive ) != 0 )
        continue;

      const QgsEditorWidgetSetup setup = vl->editorWidgetSetup( i );
      const QVariantMap cfg = setup.config();

      if ( setup.type() == QLatin1String( "ValueMap" ) )
      {
        const QVariant mapVar = cfg.value( QStringLiteral( "map" ) );
        const QVariantList entries = mapVar.type() == QVariant::List ? mapVar.toList() : QVariantList() << mapVar;
        for ( const QVariant &entry : entries )
        {
          const QVariantMap m = entry.toMap();
          for ( auto mi = m.constBegin(); mi != m.constEnd(); ++mi )
          {
            const QString v = mi.value().toString().trimmed();
            if ( !v.isEmpty() )
              unique.insert( v );
          }
        }
      }
      else if ( setup.type() == QLatin1String( "ValueRelation" ) )
      {
        QgsVectorLayer *ref = qobject_cast<QgsVectorLayer *>( QgsProject::instance()->mapLayer( cfg.value( QStringLiteral( "Layer" ) ).toString() ) );
        const QString valueField = cfg.value( QStringLiteral( "Value" ) ).toString();
        if ( ref && !valueField.isEmpty() )
        {
          const int idx = ref->fields().lookupField( valueField );
          if ( idx >= 0 )
          {
            const QSet<QVariant> vals = ref->uniqueValues( idx );
            for ( const QVariant &v : vals )
            {
              const QString t = v.toString().trimmed();
              if ( !t.isEmpty() )
                unique.insert( t );
            }
          }
        }
      }
    }
  }

  mFormSpecies = QStringList( unique.begin(), unique.end() );
  mFormSpecies.sort( Qt::CaseInsensitive );
  qInfo() << "PhotoTagStore: slownik z formularzy:" << mFormSpecies.count() << "pozycji";
  return mFormSpecies;
}
