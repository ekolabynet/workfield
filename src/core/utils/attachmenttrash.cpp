/***************************************************************************
  attachmenttrash.cpp - AttachmentTrash

 ---------------------
 WorkField 24.10.2026 [WF-ATTACHMENT-TRASH]. See attachmenttrash.h.
 ***************************************************************************/

#include "attachmenttrash.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <qgsexpression.h>
#include <qgsfeatureiterator.h>
#include <qgsfeaturerequest.h>
#include <qgsmessagelog.h>
#include <qgsproject.h>
#include <qgsrelationmanager.h>
#include <qgsvectordataprovider.h>
#include <qgsvectorlayer.h>
#include <qgsvectorlayereditbuffer.h>

namespace
{
  const QString kTrash = QStringLiteral( "kosz" );

  QString relativeTo( const QString &home, const QString &path )
  {
    QString result = path;
    result.replace( QLatin1Char( '\\' ), QLatin1Char( '/' ) );
    if ( !home.isEmpty() && result.startsWith( home + QLatin1Char( '/' ) ) )
      result = result.mid( home.length() + 1 );
    while ( result.startsWith( QLatin1String( "./" ) ) )
      result = result.mid( 2 );
    return result;
  }

  QString absoluteIn( const QString &home, const QString &path )
  {
    return QDir::isAbsolutePath( path ) ? path : home + QLatin1Char( '/' ) + relativeTo( home, path );
  }

  //! The field with the file in an attachment table: the ExternalResource widget.
  QString pathFieldOf( QgsVectorLayer *layer )
  {
    for ( int i = 0; i < layer->fields().count(); ++i )
    {
      if ( layer->editorWidgetSetup( i ).type() == QLatin1String( "ExternalResource" ) )
        return layer->fields().at( i ).name();
    }
    return QString();
  }

  void log( const QString &text )
  {
    QgsMessageLog::logMessage( QStringLiteral( "WorkField [WF-ATTACHMENT-TRASH]: " ) + text, QStringLiteral( "WorkField" ), Qgis::Info );
  }
} // namespace

AttachmentTrash::AttachmentTrash( QObject *parent )
  : QObject( parent )
{
}

QString AttachmentTrash::moveToTrash( const QString &projectHome, const QString &absolutePath )
{
  if ( projectHome.isEmpty() || !QFileInfo::exists( absolutePath ) )
    return QString();
  QDir trash( projectHome + QLatin1Char( '/' ) + kTrash );
  if ( !trash.exists() && !trash.mkpath( QStringLiteral( "." ) ) )
    return QString();
  // the gallery file browser restores by the part after the first "__"
  const QString encoded = relativeTo( projectHome, absolutePath ).replace( QLatin1Char( '/' ), QLatin1String( "__" ) );
  const QString stamp = QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmmss" ) );
  QString target = trash.filePath( stamp + QLatin1String( "__" ) + encoded );
  for ( int i = 2; QFileInfo::exists( target ); ++i )
    target = trash.filePath( stamp + QStringLiteral( "-%1__" ).arg( i ) + encoded );
  return QFile::rename( absolutePath, target ) ? target : QString();
}

bool AttachmentTrash::restoreFromTrash( const QString &projectHome, const QString &relativePath )
{
  const QString absolute = absoluteIn( projectHome, relativePath );
  if ( QFileInfo::exists( absolute ) )
    return false;
  const QString encoded = relativeTo( projectHome, relativePath ).replace( QLatin1Char( '/' ), QLatin1String( "__" ) );
  QDir trash( projectHome + QLatin1Char( '/' ) + kTrash );
  QStringList candidates;
  const QStringList entries = trash.entryList( QDir::Files, QDir::Name | QDir::Reversed );
  for ( const QString &entry : entries )
  {
    const int separator = entry.indexOf( QLatin1String( "__" ) );
    if ( separator > 0 && entry.mid( separator + 2 ) == encoded )
      candidates << entry;
  }
  if ( candidates.isEmpty() )
    return false;
  QDir().mkpath( QFileInfo( absolute ).absolutePath() );
  // newest first: the name starts with the time of trashing
  return QFile::rename( trash.filePath( candidates.first() ), absolute );
}

int AttachmentTrash::watchProject( QgsProject *project )
{
  if ( !project )
    return 0;
  if ( mProject != project )
  {
    if ( mProject )
      disconnect( mProject, nullptr, this, nullptr );
    mProject = project;
    mWatched.clear();
    mPathField.clear();
    mPending.clear();
    connect( project, &QgsProject::layersAdded, this, [this]() { watchProject( mProject ); } );
    connect( project->relationManager(), &QgsRelationManager::relationsLoaded, this, [this]() { watchProject( mProject ); } );
  }

  const QList<QgsRelation> relations = project->relationManager()->relations().values();
  for ( const QgsRelation &relation : relations )
  {
    if ( !relation.isValid() || relation.strength() != Qgis::RelationshipStrength::Composition )
      continue;
    QgsVectorLayer *child = relation.referencingLayer();
    if ( !child || mWatched.contains( child->id() ) )
      continue;
    const QString field = pathFieldOf( child );
    if ( field.isEmpty() )
      continue;
    watchLayer( child, field );
  }
  return mWatched.size();
}

void AttachmentTrash::watchLayer( QgsVectorLayer *layer, const QString &pathField )
{
  mWatched.insert( layer->id() );
  mPathField.insert( layer->id(), pathField );
  QPointer<QgsVectorLayer> guarded( layer );
  connect( layer, &QgsVectorLayer::beforeCommitChanges, this, [this, guarded]( bool ) {
    if ( guarded )
      collectDeleted( guarded );
  } );
  connect( layer, &QgsVectorLayer::afterCommitChanges, this, [this, guarded]() {
    if ( guarded )
      trashCollected( guarded );
  } );
  connect( layer, &QgsVectorLayer::afterRollBack, this, [this, guarded]() {
    if ( guarded )
      mPending.remove( guarded->id() );
  } );
  // undo of a deletion: the row comes back — the file too
  connect( layer, &QgsVectorLayer::committedFeaturesAdded, this, [this, guarded]( const QString &, const QgsFeatureList &features ) {
    if ( !guarded || !mProject )
      return;
    const QString field = mPathField.value( guarded->id() );
    int restored = 0;
    for ( const QgsFeature &feature : features )
    {
      const QString path = feature.attribute( field ).toString();
      if ( !path.isEmpty() && restoreFromTrash( mProject->homePath(), path ) )
      {
        ++restored;
        log( QStringLiteral( "restored %1" ).arg( path ) );
      }
    }
    if ( restored > 0 )
      emit filesRestored( restored );
  } );
}

void AttachmentTrash::collectDeleted( QgsVectorLayer *layer )
{
  QgsVectorLayerEditBuffer *buffer = layer->editBuffer();
  if ( !buffer || buffer->deletedFeatureIds().isEmpty() )
    return;
  const QString field = mPathField.value( layer->id() );
  const int index = layer->dataProvider()->fields().lookupField( field );
  if ( index < 0 )
    return;
  // the rows are still in the file: read them from the provider, not the layer
  QgsFeatureRequest request;
  request.setFilterFids( buffer->deletedFeatureIds() );
  request.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
  request.setSubsetOfAttributes( QgsAttributeList() << index );
  QgsFeatureIterator it = layer->dataProvider()->getFeatures( request );
  QgsFeature feature;
  QStringList paths;
  while ( it.nextFeature( feature ) )
  {
    const QString path = feature.attribute( index ).toString().trimmed();
    if ( !path.isEmpty() )
      paths << path;
  }
  if ( !paths.isEmpty() )
    mPending.insert( layer->id(), paths );
}

void AttachmentTrash::trashCollected( QgsVectorLayer *layer )
{
  const QStringList paths = mPending.take( layer->id() );
  if ( paths.isEmpty() || !mProject )
    return;
  const QString home = mProject->homePath();
  const QString field = mPathField.value( layer->id() );
  int moved = 0;
  for ( const QString &path : paths )
  {
    // another row (of any object) still uses the file: it stays
    QgsFeatureRequest request( QgsExpression( QStringLiteral( "%1 = %2" ).arg( QgsExpression::quotedColumnRef( field ), QgsExpression::quotedString( path ) ) ) );
    request.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
    request.setNoAttributes();
    request.setLimit( 1 );
    QgsFeature other;
    if ( layer->getFeatures( request ).nextFeature( other ) )
    {
      log( QStringLiteral( "kept %1 — still used by another row" ).arg( path ) );
      continue;
    }
    const QString target = moveToTrash( home, absoluteIn( home, path ) );
    if ( !target.isEmpty() )
    {
      ++moved;
      log( QStringLiteral( "%1 → %2" ).arg( path, relativeTo( home, target ) ) );
    }
  }
  if ( moved > 0 )
    emit filesTrashed( moved );
}
