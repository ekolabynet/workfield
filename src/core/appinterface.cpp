/***************************************************************************
                            appinterface.cpp
                              -------------------
              begin                : 10.12.2014
              copyright            : (C) 2014 by Matthias Kuhn
              email                : matthias (at) opengis.ch
 ***************************************************************************/

/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#include "appcontroller.h"
#include "appinterface.h"
#include "fileutils.h"
#include "platformutilities.h"
#include "qfield.h"
#include "qfieldxmlhttprequest.h"
#include "translatormanager.h"
#if WITH_SENTRY
#include "sentry_wrapper.h"
#endif

#include <QCoreApplication>
#include <QDirIterator>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QLocale>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSettings>
#include <QTemporaryFile>
#include <QTranslator>
#include <qgsapplication.h>
#include <qgsmessagelog.h>
#include <qgsnetworkaccessmanager.h>
#include <qgsproject.h>
#include <qgsruntimeprofiler.h>
#include <qgsziputils.h>

AppInterface *AppInterface::sAppInterface = nullptr;

AppInterface::AppInterface( QQmlEngine *engine, AppController *controller )
  : mEngine( engine )
  , mController( controller )
{
}

QObject *AppInterface::rootObject() const
{
  QQmlApplicationEngine *appEngine = qobject_cast<QQmlApplicationEngine *>( mEngine );
  if ( appEngine )
  {
    return appEngine->rootObjects().isEmpty() ? nullptr : appEngine->rootObjects().at( 0 );
  }

  // Engine only path (eg. QtQuickTest harness) the test window is not
  // necessarily parented under the engine, so locate it via the application's
  // top-level windows and match it back to mEngine through its content item
  if ( mEngine )
  {
    const QList<QWindow *> windows = QGuiApplication::topLevelWindows();
    for ( QWindow *window : windows )
    {
      QQuickWindow *quickWindow = qobject_cast<QQuickWindow *>( window );
      if ( quickWindow && quickWindow->contentItem() && qmlEngine( quickWindow->contentItem() ) == mEngine )
      {
        return quickWindow->contentItem();
      }
    }
  }

  return mEngine;
}

QObject *AppInterface::createHttpRequest() const
{
  QFieldXmlHttpRequest *request = new QFieldXmlHttpRequest();

  QObject *root = rootObject();
  if ( root && qmlEngine( root ) )
  {
    QQmlEngine::setObjectOwnership( request, QQmlEngine::CppOwnership );
  }

  return request;
}

QObject *AppInterface::findItemByObjectName( const QString &name ) const
{
  QObject *root = rootObject();
  return root ? root->findChild<QObject *>( name ) : nullptr;
}

void AppInterface::addItemToPluginsToolbar( QQuickItem *item ) const
{
  QObject *root = rootObject();
  if ( !root )
  {
    return;
  }

  QQuickItem *toolbar = root->findChild<QQuickItem *>( QStringLiteral( "pluginsToolbar" ) );
  if ( toolbar )
  {
    item->setParentItem( toolbar );
  }
}

void AppInterface::addItemToMapCanvas3D( QQuickItem *item ) const
{
  QObject *root = rootObject();
  if ( !root )
    return;

  QQuickItem *container = root->findChild<QQuickItem *>( QStringLiteral( "mapCanvas3DPluginContainer" ) );
  if ( container )
  {
    item->setParentItem( container );
  }
}

void AppInterface::addItemToCanvasActionsToolbar( QQuickItem *item ) const
{
  QObject *root = rootObject();
  if ( !root )
  {
    return;
  }

  QQuickItem *toolbar = root->findChild<QQuickItem *>( QStringLiteral( "canvasMenuActionsToolbar" ) );
  if ( toolbar )
  {
    item->setParentItem( toolbar );
  }
}

void AppInterface::addItemToDashboardActionsToolbar( QQuickItem *item ) const
{
  QObject *root = rootObject();
  if ( !root )
  {
    return;
  }

  QQuickItem *toolbar = root->findChild<QQuickItem *>( QStringLiteral( "dashboardActionsToolbar" ) );
  if ( toolbar )
  {
    item->setParentItem( toolbar );
  }
}

void AppInterface::addItemToMainMenuActionsToolbar( QQuickItem *item ) const
{
  addItemToDashboardActionsToolbar( item );
}

QObject *AppInterface::mainWindow() const
{
  return rootObject();
}

QObject *AppInterface::mapCanvas() const
{
  QObject *root = rootObject();
  if ( !root )
  {
    return nullptr;
  }

  return root->findChild<QObject *>( QStringLiteral( "mapCanvas" ) );
}

QObject *AppInterface::positioning() const
{
  QObject *root = rootObject();
  if ( !root )
  {
    return nullptr;
  }

  return root->findChild<QObject *>( QStringLiteral( "positionSource" ) );
}

bool AppInterface::hasProjectOnLaunch() const
{
  if ( PlatformUtilities::instance()->hasQgsProject() )
  {
    return true;
  }
  else
  {
    if ( QSettings().value( "/QField/loadProjectOnLaunch", true ).toBool() )
    {
      const QString lastProjectFilePath = QSettings().value( QStringLiteral( "QField/lastProjectFilePath" ), QString() ).toString();
      if ( !lastProjectFilePath.isEmpty() && QFileInfo::exists( lastProjectFilePath ) )
      {
        return true;
      }
    }
  }
  return false;
}

bool AppInterface::loadFile( const QString &path, const QString &name )
{
  qInfo() << QStringLiteral( "AppInterface loading file: %1" ).arg( path );
  if ( !mController )
  {
    return false;
  }
  if ( QFileInfo::exists( path ) )
  {
    return mController->loadProjectFile( path, name );
  }

  const QUrl url( path );
  return mController->loadProjectFile( url.isLocalFile() ? url.toLocalFile() : url.path(), name );
}

void AppInterface::reloadProject()
{
  if ( mController )
  {
    mController->reloadProjectFile();
  }
}

void AppInterface::readProject()
{
  if ( mController )
  {
    mController->readProjectFile();
  }
}

QString AppInterface::readProjectEntry( const QString &scope, const QString &key, const QString &def ) const
{
  return mController ? mController->readProjectEntry( scope, key, def ) : def;
}

int AppInterface::readProjectNumEntry( const QString &scope, const QString &key, int def ) const
{
  return mController ? mController->readProjectNumEntry( scope, key, def ) : def;
}

double AppInterface::readProjectDoubleEntry( const QString &scope, const QString &key, double def ) const
{
  return mController ? mController->readProjectDoubleEntry( scope, key, def ) : def;
}

bool AppInterface::readProjectBoolEntry( const QString &scope, const QString &key, bool def ) const
{
  return mController ? mController->readProjectBoolEntry( scope, key, def ) : def;
}

bool AppInterface::print( const QString &layoutName )
{
  return mController ? mController->print( layoutName ) : false;
}

bool AppInterface::printAtlasFeatures( const QString &layoutName, const QList<long long> &featureIds )
{
  return mController ? mController->printAtlasFeatures( layoutName, featureIds ) : false;
}

void AppInterface::setScreenDimmerTimeout( int timeoutSeconds )
{
  if ( mController )
  {
    mController->setScreenDimmerTimeout( timeoutSeconds );
  }
}

void AppInterface::setupNetworkProxy() const
{
  QgsNetworkAccessManager::instance()->setupDefaultProxyAndCache();
}

QVariantMap AppInterface::availableLanguages() const
{
  QVariantMap languages;
  QDirIterator it( QStringLiteral( ":/i18n/" ), { QStringLiteral( "*.qm" ) }, QDir::Files );
  while ( it.hasNext() )
  {
    it.next();
    if ( it.fileName().startsWith( "qfield_" ) )
    {
      const qsizetype delimiter = it.fileName().indexOf( '.' );
      const QString languageCode = it.fileName().mid( 7, delimiter - 7 );
      const bool hasCoutryCode = languageCode.indexOf( '_' ) > -1;

      const QLocale locale( languageCode );
      QString displayName;
      if ( languageCode == QStringLiteral( "en" ) )
      {
        displayName = QStringLiteral( "english" );
      }
      else if ( locale.nativeLanguageName().isEmpty() )
      {
        displayName = QStringLiteral( "code (%1)" ).arg( languageCode );
      }
      else
      {
        displayName = locale.nativeLanguageName().toLower() + ( hasCoutryCode ? QStringLiteral( " / %1" ).arg( locale.nativeTerritoryName() ) : QString() );
      }

      languages.insert( languageCode, displayName );
    }
  }
  return languages;
}

void AppInterface::changeLanguage( const QString &languageCode )
{
  if ( !languageCode.isEmpty() && !availableLanguages().contains( languageCode ) )
  {
    qWarning() << "Language code" << languageCode << "is not available, ignoring language change request";
    return;
  }

  QTranslator *qfieldTranslator = TranslatorManager::instance()->qfieldTranslator();
  QTranslator *qtTranslator = TranslatorManager::instance()->qtTranslator();

  QCoreApplication::removeTranslator( qtTranslator );
  QCoreApplication::removeTranslator( qfieldTranslator );

  if ( !qfieldTranslator->load( QStringLiteral( "qfield_%1" ).arg( languageCode ), QStringLiteral( ":/i18n/" ), "_" ) )
  {
    qWarning() << "Failed to load QField translation for" << languageCode;
  }
  if ( !qtTranslator->load( QStringLiteral( "qt_%1" ).arg( languageCode ), QStringLiteral( ":/i18n/" ), "_" ) )
  {
    qWarning() << "Failed to load Qt translation for" << languageCode;
  }

  QCoreApplication::installTranslator( qtTranslator );
  QCoreApplication::installTranslator( qfieldTranslator );

  QSettings settings;
  settings.setValue( QStringLiteral( "/customLanguage" ), languageCode );

  if ( !languageCode.isEmpty() )
  {
    QLocale customLocale( languageCode );
    QLocale::setDefault( customLocale );
    QgsApplication::setTranslation( languageCode );
    QgsApplication::setLocale( QLocale() );
  }
  else
  {
    QLocale systemLocale = QLocale::system();
    QLocale::setDefault( systemLocale );
    QgsApplication::setTranslation( systemLocale.name() );
    QgsApplication::setLocale( systemLocale );
  }

  if ( mEngine )
  {
    mEngine->retranslate();
  }
}

bool AppInterface::isFileExtensionSupported( const QString &filename ) const
{
  const QFileInfo fi( filename );
  const QString suffix = fi.suffix().toLower();
  return SUPPORTED_PROJECT_EXTENSIONS.contains( suffix ) || SUPPORTED_VECTOR_EXTENSIONS.contains( suffix ) || SUPPORTED_RASTER_EXTENSIONS.contains( suffix );
}

void AppInterface::logMessage( const QString &message )
{
  QgsMessageLog::logMessage( message, QStringLiteral( "QField" ) );
}

void AppInterface::logRuntimeProfiler()
{
  QgsMessageLog::logMessage( QgsApplication::profiler()->asText(), QStringLiteral( "QField" ) );
}

void AppInterface::sendLog( const QString &message, const QString &cloudUser )
{
#if WITH_SENTRY
  sentry_wrapper::capture_event( message.toUtf8().constData(), cloudUser.toUtf8().constData() );
#endif
}

void AppInterface::initiateSentry() const
{
#if WITH_SENTRY
  sentry_wrapper::init();
#endif
}

void AppInterface::closeSentry() const
{
#if WITH_SENTRY
  sentry_wrapper::close();
#endif
}

void AppInterface::clearProject() const
{
  if ( mController )
  {
    mController->clearProject();
  }
}

void AppInterface::importUrl( const QString &url, const QString &title, bool loadOnImport )
{
  QString sanitizedUrl = url.trimmed();
  if ( sanitizedUrl.isEmpty() )
  {
    return;
  }

  if ( !sanitizedUrl.contains( QRegularExpression( "^([a-z][a-z0-9+\\-.]*):" ) ) )
  {
    // Prepend HTTPS when the URL scheme is missing instead of assured failure
    sanitizedUrl = QStringLiteral( "https://%1" ).arg( sanitizedUrl );
  }

  const QString applicationDirectory = PlatformUtilities::instance()->applicationDirectory();
  if ( applicationDirectory.isEmpty() )
  {
    return;
  }

  QgsNetworkAccessManager *manager = QgsNetworkAccessManager::instance();
  QNetworkRequest request( ( QUrl( sanitizedUrl ) ) );
  request.setAttribute( QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy );

  emit importTriggered( !title.isEmpty() ? title : request.url().fileName() );

  QNetworkReply *reply = manager->get( request );

  QTemporaryFile *temporaryFile = new QTemporaryFile( reply );
  temporaryFile->setFileTemplate( QStringLiteral( "%1/XXXXXXXXXXXX" ).arg( applicationDirectory ) );
  if ( !temporaryFile->open() )
  {
    reply->abort();
    return;
  }

  connect( reply, &QNetworkReply::downloadProgress, this, [this, reply, temporaryFile]( qint64 bytesReceived, qint64 bytesTotal ) {
    temporaryFile->write( reply->readAll() );
    if ( bytesTotal != 0 )
    {
      emit importProgress( static_cast<double>( bytesReceived ) / bytesTotal );
    }
  } );

  connect( reply, &QNetworkReply::finished, this, [this, url, reply, temporaryFile, applicationDirectory, loadOnImport]() {
    if ( reply->error() == QNetworkReply::NoError )
    {
      QString fileName = reply->url().fileName();
      QString contentDisposition = reply->header( QNetworkRequest::ContentDispositionHeader ).toString();
      if ( !contentDisposition.isEmpty() )
      {
        QRegularExpression rx( QStringLiteral( "filename=\"?([^\";]*)\"?" ) );
        QRegularExpressionMatch match = rx.match( contentDisposition );
        if ( match.hasMatch() )
        {
          fileName = match.captured( 1 );
        }
      }

      QFileInfo fileInfo = QFileInfo( fileName );
      const QString fileSuffix = fileInfo.suffix().toLower();
      const bool isProjectFile = fileSuffix == QLatin1String( "qgs" ) || fileSuffix == QLatin1String( "qgz" );

      QString filePath = QStringLiteral( "%1/%2/%3" ).arg( applicationDirectory, isProjectFile ? QLatin1String( "Imported Projects" ) : QLatin1String( "Imported Datasets" ), fileName );
      {
        int i = 0;
        while ( QFileInfo::exists( filePath ) )
        {
          filePath = QStringLiteral( "%1/%2/%3_%4.%5" ).arg( applicationDirectory, isProjectFile ? QLatin1String( "Imported Projects" ) : QLatin1String( "Imported Datasets" ), fileInfo.completeBaseName(), QString::number( ++i ), fileSuffix );
        }
      }
      QDir( QFileInfo( filePath ).absolutePath() ).mkpath( "." );

      temporaryFile->write( reply->readAll() );
      temporaryFile->setAutoRemove( false );
      temporaryFile->close();
      if ( temporaryFile->rename( filePath ) )
      {
        if ( fileSuffix == QLatin1String( "zip" ) )
        {
          // Check if this is a compressed project and handle accordingly
          QStringList zipFiles = QgsZipUtils::files( filePath );
          const bool isCompressedProject = std::find_if( zipFiles.begin(),
                                                         zipFiles.end(),
                                                         []( const QString &zipFile ) {
                                                           return zipFile.toLower().endsWith( QLatin1String( ".qgs" ) ) || zipFile.toLower().endsWith( QLatin1String( ".qgz" ) );
                                                         } )
                                           != zipFiles.end();
          if ( isCompressedProject )
          {
            QString zipDirectory = QStringLiteral( "%1/Imported Projects/%2" ).arg( applicationDirectory, fileInfo.baseName() );
            {
              int i = 0;
              while ( QFileInfo::exists( zipDirectory ) )
              {
                zipDirectory = QStringLiteral( "%1/Imported Projects/%2_%3" ).arg( applicationDirectory, fileInfo.baseName(), QString::number( ++i ) );
              }
            }
            QDir( zipDirectory ).mkpath( "." );

            if ( FileUtils::unzip( filePath, zipDirectory, zipFiles, false ) )
            {
              // we need to close the project to safely flush the gpkg files and avoid file lock on Windows
              QDirIterator it( zipDirectory, { QStringLiteral( "*.qgs" ), QStringLiteral( "*.qgz" ) }, QDir::Filter::Files, QDirIterator::Subdirectories );
              QStringList projectFilePaths;
              while ( it.hasNext() )
              {
                projectFilePaths << it.nextFileInfo().absoluteFilePath();
              }

              // Project archive successfully imported
              QFile::remove( filePath );
              emit importEnded( loadOnImport && projectFilePaths.size() == 1 ? projectFilePaths.at( 0 ) : zipDirectory, url );
              return;
            }
            else
            {
              // Broken project archive, bail out
              QFile::remove( filePath );
              QDir dir( zipDirectory );
              dir.removeRecursively();
              emit importEnded();
              return;
            }
          }
        }

        // Dataset successfully imported
        QFileInfo fi( filePath );
        emit importEnded( loadOnImport ? fi.absoluteFilePath() : fi.isFile() ? fi.absolutePath()
                                                                             : fi.absoluteFilePath(),
                          url );
        return;
      }
    }

    emit importEnded();
  } );
}

bool AppInterface::saveProject()
{
  return QgsProject::instance()->write();
}

bool AppInterface::saveProjectAs( const QString &path )
{
  return QgsProject::instance()->write( path );
}

bool AppInterface::createBlankProject( const QString &path )
{
  QgsProject::instance()->clear();
  return QgsProject::instance()->write( path );
}

bool AppInterface::removeProjectFolder( const QString &path )
{
  if ( path.contains( QStringLiteral( "/templates/" ) ) )
    return false;

  QDir dir( path );
  if ( !dir.exists() )
    return false;

  return dir.removeRecursively();
}

QString AppInterface::projectTitle() const
{
  return QgsProject::instance()->title();
}

void AppInterface::setProjectTitle( const QString &title )
{
  QgsProject::instance()->setTitle( title );
}

QString AppInterface::projectCrsAuthid() const
{
  return QgsProject::instance()->crs().authid();
}

QString AppInterface::projectCrsDescription() const
{
  return QgsProject::instance()->crs().description();
}

bool AppInterface::setProjectCrs( const QString &authid )
{
  const QgsCoordinateReferenceSystem crs( authid );
  if ( !crs.isValid() )
    return false;

  QgsProject::instance()->setCrs( crs );
  return true;
}

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <qgsrasterlayer.h>
#include <qgscolorrampshader.h>
#include <qgsrastershader.h>
#include <qgssinglebandpseudocolorrenderer.h>
#include <qgsrasterbandstats.h>
#include "qgsquickmapsettings.h"

void AppInterface::downloadFile( const QString &url, const QString &destinationPath )
{
  static QNetworkAccessManager sManager;
  sManager.setRedirectPolicy( QNetworkRequest::NoLessSafeRedirectPolicy );
  QNetworkReply *reply = sManager.get( QNetworkRequest( QUrl( url ) ) );
  connect( reply, &QNetworkReply::finished, this, [this, reply, destinationPath]() {
    if ( reply->error() != QNetworkReply::NoError )
    {
      emit downloadFailed( reply->errorString(), destinationPath );
    }
    else
    {
      QDir().mkpath( QFileInfo( destinationPath ).absolutePath() );
      QFile file( destinationPath );
      if ( file.open( QIODevice::WriteOnly ) )
      {
        file.write( reply->readAll() );
        file.close();
        emit downloadFinished( destinationPath );
      }
      else
      {
        emit downloadFailed( QStringLiteral( "Cannot write file" ), destinationPath );
      }
    }
    reply->deleteLater();
  } );
}

bool AppInterface::addRasterLayerToProject( const QString &path, const QString &name, const QString &crsAuthid, const QString &style )
{
  QgsRasterLayer *layer = new QgsRasterLayer( path, name );
  if ( !layer->isValid() )
  {
    delete layer;
    return false;
  }
  if ( !crsAuthid.isEmpty() )
    layer->setCrs( QgsCoordinateReferenceSystem( crsAuthid ) );

  QgsColorRampShader colorRampShader;
  QList<QgsColorRampShader::ColorRampItem> items;
  if ( style == QStringLiteral( "chm" ) )
  {
    colorRampShader = QgsColorRampShader( 0.0, 40.0 );
    colorRampShader.setColorRampType( Qgis::ShaderInterpolationMethod::Discrete );
    const QList<QPair<double, QString>> classes = {
      { 1.0, QStringLiteral( "#30123B" ) }, { 5.0, QStringLiteral( "#3E63CD" ) },
      { 10.0, QStringLiteral( "#3E9BFE" ) }, { 15.0, QStringLiteral( "#46F884" ) },
      { 20.0, QStringLiteral( "#E1DD37" ) }, { 25.0, QStringLiteral( "#FA7D20" ) },
      { 30.0, QStringLiteral( "#D23105" ) }, { 10000.0, QStringLiteral( "#7A0403" ) } };
    for ( const auto &cls : classes )
      items << QgsColorRampShader::ColorRampItem( cls.first, QColor( cls.second ), cls.first > 100 ? QStringLiteral( "> 30 m" ) : QStringLiteral( "<= %1 m" ).arg( cls.first ) );
  }
  else
  {
    const QgsRasterBandStats stats = layer->dataProvider()->bandStatistics( 1 );
    colorRampShader = QgsColorRampShader( stats.minimumValue, stats.maximumValue );
    colorRampShader.setColorRampType( Qgis::ShaderInterpolationMethod::Linear );
    const QList<QPair<double, QString>> turbo = {
      { 0.00, QStringLiteral( "#30123B" ) }, { 0.17, QStringLiteral( "#3E9BFE" ) },
      { 0.33, QStringLiteral( "#46F884" ) }, { 0.50, QStringLiteral( "#E1DD37" ) },
      { 0.67, QStringLiteral( "#FA7D20" ) }, { 0.83, QStringLiteral( "#D23105" ) },
      { 1.00, QStringLiteral( "#7A0403" ) } };
    for ( const auto &stop : turbo )
    {
      const double value = stats.minimumValue + stop.first * ( stats.maximumValue - stats.minimumValue );
      items << QgsColorRampShader::ColorRampItem( value, QColor( stop.second ), QString::number( value, 'f', 1 ) );
    }
  }
  colorRampShader.setColorRampItemList( items );
  QgsRasterShader *shader = new QgsRasterShader();
  shader->setRasterShaderFunction( new QgsColorRampShader( colorRampShader ) );
  layer->setRenderer( new QgsSingleBandPseudoColorRenderer( layer->dataProvider(), 1, shader ) );
  layer->setOpacity( 0.7 );
  QgsProject::instance()->addMapLayer( layer );
  return true;
}

QVariantList AppInterface::visibleExtentPointsIn2180( QgsQuickMapSettings *mapSettings, int grid )
{
  QVariantList points;
  if ( !mapSettings || grid < 1 )
    return points;

  const QgsCoordinateReferenceSystem crs2180( QStringLiteral( "EPSG:2180" ) );
  const QgsCoordinateTransform transform( mapSettings->destinationCrs(), crs2180, QgsProject::instance() );
  const QgsRectangle extent = mapSettings->visibleExtent();
  for ( int i = 0; i <= grid; i++ )
  {
    for ( int j = 0; j <= grid; j++ )
    {
      const double x = extent.xMinimum() + ( extent.width() * i ) / grid;
      const double y = extent.yMinimum() + ( extent.height() * j ) / grid;
      try
      {
        const QgsPointXY pt = transform.transform( QgsPointXY( x, y ) );
        QVariantMap map;
        map.insert( QStringLiteral( "x" ), pt.x() );
        map.insert( QStringLiteral( "y" ), pt.y() );
        points << map;
      }
      catch ( const QgsCsException & )
      {
      }
    }
  }
  return points;
}

bool AppInterface::writeTextFile( const QString &path, const QString &content )
{
  QDir().mkpath( QFileInfo( path ).absolutePath() );
  QFile file( path );
  if ( !file.open( QIODevice::WriteOnly | QIODevice::Text ) )
    return false;
  file.write( content.toUtf8() );
  file.close();
  return true;
}

QString AppInterface::preferredDataDir() const
{
  QSettings settings;
  const QString path = settings.value( QStringLiteral( "workfield/preferredDataDir" ) ).toString();
  if ( path.isEmpty() || !QDir( path ).exists() )
    return QString();
  return path;
}

void AppInterface::setPreferredDataDir( const QString &path )
{
  QSettings settings;
  if ( path.isEmpty() )
    settings.remove( QStringLiteral( "workfield/preferredDataDir" ) );
  else
    settings.setValue( QStringLiteral( "workfield/preferredDataDir" ), path );
}

#include <QStorageInfo>
#include "platforms/platformutilities.h"

double AppInterface::storageFreeGb( const QString &path ) const
{
  const QStorageInfo info( path );
  return info.isValid() ? info.bytesAvailable() / 1073741824.0 : 0.0;
}

QString AppInterface::dataRoot() const
{
  QString root = preferredDataDir();
  if ( root.isEmpty() )
    root = PlatformUtilities::instance()->appDataDirs().value( 0 );
  if ( !root.isEmpty() && !root.endsWith( QLatin1Char( '/' ) ) )
    root += QLatin1Char( '/' );
  return root;
}

static bool wfCopyRecursively( const QString &source, const QString &destination )
{
  QDir sourceDir( source );
  if ( !sourceDir.exists() )
    return false;
  QDir().mkpath( destination );
  const QFileInfoList entries = sourceDir.entryInfoList( QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot );
  for ( const QFileInfo &entry : entries )
  {
    const QString target = destination + QLatin1Char( '/' ) + entry.fileName();
    if ( entry.isDir() )
    {
      if ( !wfCopyRecursively( entry.absoluteFilePath(), target ) )
        return false;
    }
    else
    {
      QFile::remove( target );
      if ( !QFile::copy( entry.absoluteFilePath(), target ) )
        return false;
    }
  }
  return true;
}

bool AppInterface::migrateDataDir( const QString &source, const QString &destination, bool removeSource )
{
  if ( source.isEmpty() || destination.isEmpty() || source == destination )
    return false;
  if ( !wfCopyRecursively( source, destination ) )
    return false;
  if ( removeSource )
  {
    QDir sourceDir( source );
    const QFileInfoList entries = sourceDir.entryInfoList( QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot );
    for ( const QFileInfo &entry : entries )
    {
      if ( entry.isDir() )
        QDir( entry.absoluteFilePath() ).removeRecursively();
      else
        QFile::remove( entry.absoluteFilePath() );
    }
  }
  return true;
}

#include <gdal_utils.h>
#include <qgsrastercalculator.h>

bool AppInterface::demProcessing( const QString &tool, const QString &inputPath, const QString &outputPath )
{
  GDALAllRegister();
  GDALDatasetH input = GDALOpen( inputPath.toUtf8().constData(), GA_ReadOnly );
  if ( !input )
    return false;

  GDALDEMProcessingOptions *options = GDALDEMProcessingOptionsNew( nullptr, nullptr );
  int usageError = FALSE;
  GDALDatasetH output = GDALDEMProcessing( outputPath.toUtf8().constData(), input, tool.toUtf8().constData(), nullptr, options, &usageError );
  GDALDEMProcessingOptionsFree( options );
  GDALClose( input );
  if ( !output )
    return false;
  GDALClose( output );
  return true;
}

bool AppInterface::rasterDifference( const QString &pathA, const QString &pathB, const QString &outputPath )
{
  QDir().mkpath( QFileInfo( outputPath ).absolutePath() );
  std::unique_ptr<QgsRasterLayer> layerA = std::make_unique<QgsRasterLayer>( pathA, QStringLiteral( "A" ) );
  std::unique_ptr<QgsRasterLayer> layerB = std::make_unique<QgsRasterLayer>( pathB, QStringLiteral( "B" ) );
  if ( !layerA->isValid() || !layerB->isValid() )
    return false;

  QgsRasterCalculatorEntry entryA;
  entryA.ref = QStringLiteral( "A@1" );
  entryA.raster = layerA.get();
  entryA.bandNumber = 1;
  QgsRasterCalculatorEntry entryB;
  entryB.ref = QStringLiteral( "B@1" );
  entryB.raster = layerB.get();
  entryB.bandNumber = 1;

  QgsRasterCalculator calculator( QStringLiteral( "\"A@1\" - \"B@1\"" ), outputPath, QStringLiteral( "GTiff" ), layerA->extent(), layerA->crs(), layerA->width(), layerA->height(), { entryA, entryB }, QgsProject::instance()->transformContext() );
  return calculator.processCalculation() == QgsRasterCalculator::Result::Success;
}

QStringList AppInterface::listFiles( const QString &dirPath, const QString &nameFilter ) const
{
  QDir dir( dirPath );
  return dir.entryList( QStringList() << nameFilter, QDir::Files, QDir::Name );
}
