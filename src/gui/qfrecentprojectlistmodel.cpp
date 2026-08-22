/***************************************************************************
  qfrecentprojectlistmodel.h

 ---------------------
 begin                : 02.1.2020
 copyright            : (C) 2020 by Mathieu Pellerin
 email                : nirvn dot asia at gmail dot com
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#include "qfcloudutils.h"
#include "qfield.h"
#include "qfplatformutilities.h"
#include "qfrecentprojectlistmodel.h"

#include <QDir>
#include <QFile>
#include <QSettings>

// WorkField: podbij przy kazdej zmianie listy szablonow w sample_projects.json
static constexpr int WORKFIELD_SAMPLE_PROJECTS_VERSION = 2;

// WorkField: 3 szablony + miejsce na projekty terenowe
static constexpr int WORKFIELD_RECENT_PROJECTS_LIMIT = 10;

QfRecentProjectListModel::QfRecentProjectListModel( QObject *parent )
  : QAbstractListModel( parent )
{
  reloadModel();
}

QHash<int, QByteArray> QfRecentProjectListModel::roleNames() const
{
  QHash<int, QByteArray> roles = QAbstractListModel::roleNames();
  roles[ProjectTypeRole] = "ProjectType";
  roles[ProjectTitleRole] = "ProjectTitle";
  roles[ProjectPathRole] = "ProjectPath";
  roles[ProjectThumbnailRole] = "QfProjectThumbnail";

  return roles;
}

void QfRecentProjectListModel::reloadModel()
{
  beginResetModel();
  mRecentProjects.clear();

  QSettings settings;

  mRecentProjects = recentProjects( true );

  const int sampleProjectsVersion = settings.value( QStringLiteral( "WorkField/sampleProjectsVersion" ), 0 ).toInt();
  if ( sampleProjectsVersion < WORKFIELD_SAMPLE_PROJECTS_VERSION )
  {
    // WorkField: usun poprzednie wpisy-linki (szablony ze starej listy)
    QList<RecentProject> kept;
    for ( const RecentProject &project : std::as_const( mRecentProjects ) )
    {
      if ( project.type != LinkProject )
        kept.append( project );
    }
    mRecentProjects = kept;

    const QString sampleProjectsDirectory = QfPlatformUtilities::instance()->systemLocalDataLocation( QLatin1String( "sample_projects" ) );
    const QString sampleProjectsJson = QStringLiteral( "%1/sample_projects.json" ).arg( sampleProjectsDirectory );
    if ( QFileInfo::exists( sampleProjectsJson ) )
    {
      bool sampleProjectsJsonIsValid = true;
      QFile sampleProjectsFile( sampleProjectsJson );
      QJsonDocument doc;
      if ( sampleProjectsFile.open( QIODevice::ReadOnly ) )
      {
        QJsonParseError error;
        doc = QJsonDocument::fromJson( sampleProjectsFile.readAll(), &error );
        if ( doc.isNull() || !doc.isArray() )
        {
          sampleProjectsJsonIsValid = false;
        }
      }
      else
      {
        sampleProjectsJsonIsValid = false;
      }

      if ( sampleProjectsJsonIsValid )
      {
        const QJsonArray values = doc.array();
        for ( const QJsonValueConstRef &value : values )
        {
          if ( !value.isObject() )
          {
            continue;
          }

          const QJsonObject valueObject = value.toObject();
          mRecentProjects.append( RecentProject( LinkProject,
                                                 valueObject.value( QStringLiteral( "title" ) ).toString(),
                                                 valueObject.value( QStringLiteral( "link" ) ).toString(),
                                                 QStringLiteral( "%1/%2" ).arg( sampleProjectsDirectory, valueObject.value( QStringLiteral( "thumbnail" ) ).toString() ) ) );

        }
      }
    }
    saveRecentProjects( mRecentProjects );
    settings.setValue( QStringLiteral( "WorkField/sampleProjectsVersion" ), WORKFIELD_SAMPLE_PROJECTS_VERSION );
  }

  endResetModel();
}

int QfRecentProjectListModel::rowCount( const QModelIndex &parent ) const
{
  return !parent.isValid() ? static_cast<int>( mRecentProjects.size() ) : 0;
}

QVariant QfRecentProjectListModel::data( const QModelIndex &index, int role ) const
{
  if ( index.row() >= mRecentProjects.size() || index.row() < 0 )
    return QVariant();

  switch ( static_cast<Role>( role ) )
  {
    case ProjectTypeRole:
      return mRecentProjects.at( index.row() ).type;
    case ProjectTitleRole:
      return mRecentProjects.at( index.row() ).title;
    case ProjectPathRole:
      return mRecentProjects.at( index.row() ).path;
    case ProjectThumbnailRole:
      return mRecentProjects.at( index.row() ).thumbnail;
  }

  return QVariant();
}

void QfRecentProjectListModel::removeRecentProject( const QString &path )
{
  QList<RecentProject> projects = recentProjects();
  bool removed = false;
  for ( int idx = 0; idx < projects.count(); idx++ )
  {
    if ( projects.at( idx ).path == path )
    {
      projects.removeAt( idx );
      removed = true;
      break;
    }
  }
  if ( removed )
  {
    saveRecentProjects( projects );
  }
}

QList<QfRecentProjectListModel::RecentProject> QfRecentProjectListModel::recentProjects( bool skipNonAvailable )
{
  QList<RecentProject> projects;

  QSettings settings;
  const QString qfieldCloudUsername = QSettings().value( QStringLiteral( "/QFieldCloud/username" ) ).toString();
  const QString qdieldCloudLocalDirectory = QfCloudUtils::localCloudDirectory();

  settings.beginGroup( "/qgis/recentProjects" );

  const QStringList projectKeysList = settings.childGroups();
  QList<int> projectKeys;
  // This is overdoing it since we're clipping the recent projects list to five items at the moment, but might as well be futureproof
  for ( const QString &key : projectKeysList )
  {
    projectKeys.append( key.toInt() );
  }
  for ( int i = 0; i < projectKeys.count(); i++ )
  {
    settings.beginGroup( QString::number( projectKeys.at( i ) ) );

    const QString path = settings.value( QStringLiteral( "path" ) ).toString();
    const QFileInfo fi( path );

    bool skip = false;
    ProjectType type = LocalDataset;
    if ( path.startsWith( qdieldCloudLocalDirectory ) )
    {
      if ( skipNonAvailable && ( !fi.exists() || !path.startsWith( QStringLiteral( "%1%2%3%2" ).arg( qdieldCloudLocalDirectory, QDir::separator(), qfieldCloudUsername ) ) ) )
      {
        skip = true;
      }

      type = CloudProject;
    }
    else if ( path.startsWith( "http://", Qt::CaseInsensitive ) || path.startsWith( "https://", Qt::CaseInsensitive ) )
    {
      type = LinkProject;
    }
    else if ( SUPPORTED_PROJECT_EXTENSIONS.contains( fi.suffix() ) )
    {
      if ( skipNonAvailable && !fi.exists() )
      {
        skip = true;
      }

      type = LocalProject;
    }
    else
    {
      if ( skipNonAvailable && !fi.exists() )
      {
        skip = true;
      }

      type = LocalDataset;
    }

    if ( !skip )
    {
      projects.append( RecentProject( type,
                                      settings.value( QStringLiteral( "title" ) ).toString(),
                                      path,
                                      settings.value( QStringLiteral( "thumbnail" ) ).toString() ) );
    }

    settings.endGroup();
  }
  settings.endGroup();

  return projects;
}

void QfRecentProjectListModel::saveRecentProjects( const QList<RecentProject> &projects )
{
  QSettings settings;
  settings.remove( QStringLiteral( "/qgis/recentProjects" ) );
  for ( int idx = 0; idx < projects.count() && idx < WORKFIELD_RECENT_PROJECTS_LIMIT; idx++ )
  {
    settings.beginGroup( QStringLiteral( "/qgis/recentProjects/%1" ).arg( idx ) );
    settings.setValue( QStringLiteral( "title" ), projects.at( idx ).title );
    settings.setValue( QStringLiteral( "path" ), projects.at( idx ).path );
    settings.setValue( QStringLiteral( "thumbnail" ), projects.at( idx ).thumbnail );
    settings.endGroup();
  }
}
