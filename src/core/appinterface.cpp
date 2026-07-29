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

#include "appinterface.h"
#include "fileutils.h"
#include "platformutilities.h"
#include "qfield.h"
#include "qfieldxmlhttprequest.h"
#include "qgismobileapp.h"
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

AppInterface::AppInterface( QQmlEngine *engine )
  : mEngine( engine )
{
}

QgisMobileapp *AppInterface::app() const
{
  return qobject_cast<QgisMobileapp *>( mEngine );
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
  QgisMobileapp *mobileApp = app();
  if ( !mobileApp )
  {
    return false;
  }
  if ( QFileInfo::exists( path ) )
  {
    return mobileApp->loadProjectFile( path, name );
  }

  const QUrl url( path );
  return mobileApp->loadProjectFile( url.isLocalFile() ? url.toLocalFile() : url.path(), name );
}

void AppInterface::reloadProject()
{
  QgisMobileapp *mobileApp = app();
  if ( mobileApp )
  {
    mobileApp->reloadProjectFile();
  }
}

void AppInterface::readProject()
{
  QgisMobileapp *mobileApp = app();
  if ( mobileApp )
  {
    mobileApp->readProjectFile();
  }
}

QString AppInterface::readProjectEntry( const QString &scope, const QString &key, const QString &def ) const
{
  const QgisMobileapp *mobileApp = app();
  return mobileApp ? mobileApp->readProjectEntry( scope, key, def ) : def;
}

int AppInterface::readProjectNumEntry( const QString &scope, const QString &key, int def ) const
{
  const QgisMobileapp *mobileApp = app();
  return mobileApp ? mobileApp->readProjectNumEntry( scope, key, def ) : def;
}

double AppInterface::readProjectDoubleEntry( const QString &scope, const QString &key, double def ) const
{
  const QgisMobileapp *mobileApp = app();
  return mobileApp ? mobileApp->readProjectDoubleEntry( scope, key, def ) : def;
}

bool AppInterface::readProjectBoolEntry( const QString &scope, const QString &key, bool def ) const
{
  const QgisMobileapp *mobileApp = app();
  return mobileApp ? mobileApp->readProjectBoolEntry( scope, key, def ) : def;
}

bool AppInterface::print( const QString &layoutName )
{
  QgisMobileapp *mobileApp = app();
  return mobileApp ? mobileApp->print( layoutName ) : false;
}

bool AppInterface::printAtlasFeatures( const QString &layoutName, const QList<long long> &featureIds )
{
  QgisMobileapp *mobileApp = app();
  return mobileApp ? mobileApp->printAtlasFeatures( layoutName, featureIds ) : false;
}

void AppInterface::setScreenDimmerTimeout( int timeoutSeconds )
{
  QgisMobileapp *mobileApp = app();
  if ( mobileApp )
  {
    mobileApp->setScreenDimmerTimeout( timeoutSeconds );
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

  QgisMobileapp *mobileApp = app();
  if ( mobileApp )
  {
    mobileApp->retranslate();
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
  QgisMobileapp *mobileApp = app();
  if ( mobileApp )
  {
    mobileApp->clearProject();
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

#include <algorithm>
#include <cmath>
#include <limits>
#include <qgsexpressioncontextutils.h>
#include <qgsvectorlayer.h>
#include <qgsmaplayer.h>
#include <qgslayertree.h>
#include <qgslayertreegroup.h>
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

bool AppInterface::addRasterLayerToProject( const QString &path, const QString &name, const QString &crsAuthid, const QString &style, const QString &groupName )
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
      { 1.0, QStringLiteral( "#1030123B" ) }, { 5.0, QStringLiteral( "#903E63CD" ) },
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
  if ( groupName.isEmpty() )
  {
    QgsProject::instance()->addMapLayer( layer );
  }
  else
  {
    QgsLayerTreeGroup *group = QgsProject::instance()->layerTreeRoot()->findGroup( groupName );
    if ( !group )
      group = QgsProject::instance()->layerTreeRoot()->insertGroup( 0, groupName );
    QgsProject::instance()->addMapLayer( layer, false );
    group->addLayer( layer );
  }
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
  const QString markerPath = PlatformUtilities::instance()->appDataDirs().value( 0 ) + QStringLiteral( "/.preferred_data_dir" );
  if ( path.isEmpty() )
  {
    QFile::remove( markerPath );
  }
  else
  {
    QFile marker( markerPath );
    if ( marker.open( QIODevice::WriteOnly | QIODevice::Text ) )
    {
      marker.write( path.toUtf8() );
      marker.close();
    }
  }
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

bool AppInterface::clipMergeRasters( const QStringList &inputPaths, double xmin, double ymin, double xmax, double ymax, const QString &outputPath )
{
  if ( inputPaths.isEmpty() )
    return false;

  GDALAllRegister();
  QDir().mkpath( QFileInfo( outputPath ).absolutePath() );
  QFile::remove( outputPath );

  QVector<GDALDatasetH> inputs;
  for ( const QString &path : inputPaths )
  {
    GDALDatasetH dataset = GDALOpen( path.toUtf8().constData(), GA_ReadOnly );
    if ( dataset )
      inputs << dataset;
  }
  if ( inputs.isEmpty() )
    return false;

  char **argv = nullptr;
  argv = CSLAddString( argv, "-s_srs" );
  argv = CSLAddString( argv, "EPSG:2180" );
  argv = CSLAddString( argv, "-t_srs" );
  argv = CSLAddString( argv, "EPSG:2180" );
  argv = CSLAddString( argv, "-te" );
  argv = CSLAddString( argv, QByteArray::number( xmin, 'f', 2 ).constData() );
  argv = CSLAddString( argv, QByteArray::number( ymin, 'f', 2 ).constData() );
  argv = CSLAddString( argv, QByteArray::number( xmax, 'f', 2 ).constData() );
  argv = CSLAddString( argv, QByteArray::number( ymax, 'f', 2 ).constData() );
  argv = CSLAddString( argv, "-co" );
  argv = CSLAddString( argv, "COMPRESS=DEFLATE" );

  GDALWarpAppOptions *options = GDALWarpAppOptionsNew( argv, nullptr );
  CSLDestroy( argv );
  int usageError = FALSE;
  GDALDatasetH output = GDALWarp( outputPath.toUtf8().constData(), nullptr, inputs.size(), inputs.data(), options, &usageError );
  GDALWarpAppOptionsFree( options );
  for ( GDALDatasetH dataset : inputs )
    GDALClose( dataset );
  if ( !output )
    return false;
  GDALClose( output );
  return true;
}

bool AppInterface::addXyzBasemap( const QString &name, const QString &url, int zmax )
{
  const QString uri = QStringLiteral( "type=xyz&url=%1&zmin=0&zmax=%2" ).arg( QString( QUrl::toPercentEncoding( url ) ), QString::number( zmax ) );
  QgsRasterLayer *layer = new QgsRasterLayer( uri, name, QStringLiteral( "wms" ) );
  if ( !layer->isValid() )
  {
    delete layer;
    return false;
  }
  QgsProject::instance()->addMapLayer( layer, false );
  QgsLayerTree *root = QgsProject::instance()->layerTreeRoot();
  root->insertLayer( root->children().count(), layer );
  return true;
}

QVariantMap AppInterface::transformPointToProjectCrs( double x, double y, const QString &fromAuthid ) const
{
  QVariantMap result;
  const QgsCoordinateReferenceSystem fromCrs( fromAuthid );
  const QgsCoordinateTransform transform( fromCrs, QgsProject::instance()->crs(), QgsProject::instance() );
  try
  {
    const QgsPointXY pt = transform.transform( QgsPointXY( x, y ) );
    result.insert( QStringLiteral( "x" ), pt.x() );
    result.insert( QStringLiteral( "y" ), pt.y() );
  }
  catch ( const QgsCsException & )
  {
  }
  return result;
}

bool AppInterface::zoomToProjectData( QgsQuickMapSettings *mapSettings )
{
  if ( !mapSettings )
    return false;
  QgsRectangle combined;
  const QMap<QString, QgsMapLayer *> layers = QgsProject::instance()->mapLayers();
  for ( QgsMapLayer *layer : layers )
  {
    if ( layer->providerType() == QStringLiteral( "wms" ) )
      continue;
    QgsRectangle extent = layer->extent();
    if ( extent.isEmpty() )
      continue;
    try
    {
      const QgsCoordinateTransform transform( layer->crs(), QgsProject::instance()->crs(), QgsProject::instance() );
      extent = transform.transformBoundingBox( extent );
    }
    catch ( const QgsCsException & )
    {
      continue;
    }
    combined.combineExtentWith( extent );
  }
  if ( combined.isEmpty() )
    return false;
  combined.scale( 1.1 );
  mapSettings->setExtent( combined );
  return true;
}

QString AppInterface::layerInfoLabel( QgsVectorLayer *layer ) const
{
  if ( !layer )
    return QString();
  QString geometry;
  switch ( layer->geometryType() )
  {
    case Qgis::GeometryType::Point:
      geometry = tr( "punkty" );
      break;
    case Qgis::GeometryType::Line:
      geometry = tr( "linie" );
      break;
    case Qgis::GeometryType::Polygon:
      geometry = tr( "poligony" );
      break;
    default:
      geometry = tr( "tabela" );
      break;
  }
  return QStringLiteral( "%1 \u00b7 %2" ).arg( geometry ).arg( layer->featureCount() );
}

bool AppInterface::layerSelectable( QgsMapLayer *layer ) const
{
  if ( !layer )
    return false;
  return layer->customProperty( QStringLiteral( "workfield/selectable" ), true ).toBool();
}

void AppInterface::setLayerSelectable( QgsMapLayer *layer, bool selectable )
{
  if ( !layer )
    return;
  layer->setCustomProperty( QStringLiteral( "workfield/selectable" ), selectable );
  QgsProject::instance()->setDirty( true );
}

QString AppInterface::projectVariable( const QString &name ) const
{
  std::unique_ptr<QgsExpressionContextScope> scope( QgsExpressionContextUtils::projectScope( QgsProject::instance() ) );
  return scope ? scope->variable( name ).toString() : QString();
}

void AppInterface::setProjectVariable( const QString &name, const QString &value )
{
  QgsExpressionContextUtils::setProjectVariable( QgsProject::instance(), name, value );
  QgsProject::instance()->setDirty( true );
}

double AppInterface::sampleRasterAt( QgsMapLayer *layer, double x, double y ) const
{
  QgsRasterLayer *rl = qobject_cast<QgsRasterLayer *>( layer );
  if ( !rl || !rl->dataProvider() )
    return std::numeric_limits<double>::quiet_NaN();

  QgsPointXY point( x, y );
  if ( rl->crs() != QgsProject::instance()->crs() )
  {
    try
    {
      const QgsCoordinateTransform transform( QgsProject::instance()->crs(), rl->crs(), QgsProject::instance() );
      point = transform.transform( point );
    }
    catch ( const QgsCsException & )
    {
      return std::numeric_limits<double>::quiet_NaN();
    }
  }

  bool ok = false;
  const double value = rl->dataProvider()->sample( point, 1, &ok );
  return ok ? value : std::numeric_limits<double>::quiet_NaN();
}

double AppInterface::sampleRasterByName( const QString &nameFragment, double x, double y ) const
{
  const QMap<QString, QgsMapLayer *> layers = QgsProject::instance()->mapLayers();
  for ( QgsMapLayer *layer : layers )
  {
    if ( qobject_cast<QgsRasterLayer *>( layer ) && layer->name().contains( nameFragment, Qt::CaseInsensitive ) )
      return sampleRasterAt( layer, x, y );
  }
  return std::numeric_limits<double>::quiet_NaN();
}

double AppInterface::sampleRasterBuffered( const QString &nameFragment, double x, double y, double radiusMeters, const QString &statistic ) const
{
  QgsRasterLayer *target = nullptr;
  const QMap<QString, QgsMapLayer *> layers = QgsProject::instance()->mapLayers();
  for ( QgsMapLayer *layer : layers )
  {
    if ( QgsRasterLayer *rl = qobject_cast<QgsRasterLayer *>( layer ) )
    {
      if ( rl->name().contains( nameFragment, Qt::CaseInsensitive ) )
      {
        target = rl;
        break;
      }
    }
  }
  if ( !target || !target->dataProvider() )
    return std::numeric_limits<double>::quiet_NaN();

  // krok probkowania: rozmiar piksela rastra, min 0.5 m
  const double pixelSize = std::max( 0.5, target->rasterUnitsPerPixelX() );
  const int steps = std::max( 1, static_cast<int>( radiusMeters / pixelSize ) );

  QVector<double> values;
  for ( int i = -steps; i <= steps; i++ )
  {
    for ( int j = -steps; j <= steps; j++ )
    {
      const double dx = i * pixelSize;
      const double dy = j * pixelSize;
      if ( std::sqrt( dx * dx + dy * dy ) > radiusMeters )
        continue;
      const double value = sampleRasterAt( target, x + dx, y + dy );
      if ( !std::isnan( value ) )
        values << value;
    }
  }
  if ( values.isEmpty() )
    return std::numeric_limits<double>::quiet_NaN();

  if ( statistic.compare( QLatin1String( "median" ), Qt::CaseInsensitive ) == 0 )
  {
    std::sort( values.begin(), values.end() );
    const int mid = values.size() / 2;
    return values.size() % 2 == 0 ? ( values[mid - 1] + values[mid] ) / 2.0 : values[mid];
  }

  double sum = 0.0;
  for ( double v : values )
    sum += v;
  return sum / values.size();
}

QVariantMap AppInterface::rasterContextFor( QgsVectorLayer *layer, double x, double y ) const
{
  QVariantMap result;
  if ( !layer )
    return result;

  const QList<QPair<QString, QPair<QString, QString>>> rules = {
    { QStringLiteral( "chm" ), { QStringLiteral( "CHM" ), QStringLiteral( "median" ) } },
    { QStringLiteral( "nmt" ), { QStringLiteral( "NMT" ), QStringLiteral( "mean" ) } },
    { QStringLiteral( "npm" ), { QStringLiteral( "NMT" ), QStringLiteral( "mean" ) } },
    { QStringLiteral( "twi" ), { QStringLiteral( "TWI" ), QStringLiteral( "mean" ) } },
    { QStringLiteral( "swiat" ), { QStringLiteral( "SWIATLO" ), QStringLiteral( "mean" ) } },
    { QStringLiteral( "nachyl" ), { QStringLiteral( "NACHYLENIE" ), QStringLiteral( "mean" ) } },
    { QStringLiteral( "ekspoz" ), { QStringLiteral( "EKSPOZYCJA" ), QStringLiteral( "mean" ) } }
  };

  const QgsFields fields = layer->fields();
  for ( const QgsField &field : fields )
  {
    const QString lower = field.name().toLower();
    for ( const auto &rule : rules )
    {
      if ( !lower.startsWith( rule.first ) )
        continue;
      const double value = sampleRasterBuffered( rule.second.first, x, y, 1.5, rule.second.second );
      if ( !std::isnan( value ) )
        result.insert( field.name(), QString::number( value, 'f', 2 ).toDouble() );
      break;
    }
  }
  return result;
}

QString AppInterface::layerKind( QgsMapLayer *layer ) const
{
  if ( !layer )
    return QString();

  if ( layer->providerType() == QStringLiteral( "wms" ) || layer->providerType() == QStringLiteral( "vectortile" ) || layer->providerType() == QStringLiteral( "xyzvectortiles" ) )
    return QStringLiteral( "podklad" );

  if ( QgsVectorLayer *vl = qobject_cast<QgsVectorLayer *>( layer ) )
    return vl->readOnly() ? QStringLiteral( "wektor" ) : QStringLiteral( "robocza" );

  if ( qobject_cast<QgsRasterLayer *>( layer ) )
    return QStringLiteral( "raster" );

  return QStringLiteral( "wektor" );
}

bool AppInterface::removeLayer( QgsMapLayer *layer )
{
  if ( !layer )
    return false;
  QgsProject::instance()->removeMapLayer( layer->id() );
  QgsProject::instance()->setDirty( true );
  return true;
}
