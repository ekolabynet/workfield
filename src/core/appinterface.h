/***************************************************************************
                            appinterface.h
                              -------------------
              begin                : 10.12.2014
              copyright            : (C) 2014 by Matthias Kuhn
              email                : matthias.kuhn (at) opengis.ch
 ***************************************************************************/

/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#ifndef APPINTERFACE_H
#define APPINTERFACE_H

#include <QObject>
#include <QPointF>
#include <QQmlComponent>
#include <QStandardItemModel>

class QgisMobileapp;
class QgsRectangle;
class QgsFeature;
class QQuickItem;
class QQmlEngine;
class QFieldXmlHttpRequest;

/**
 * \brief App interface made available in QML as `iface`.
 * \ingroup core
 */
class QgsQuickMapSettings;

class AppInterface : public QObject
{
    Q_OBJECT

  public:
    explicit AppInterface( QQmlEngine *engine );
    AppInterface()
    {
      // You shouldn't get here, this constructor only exists that we can register it as a QML type
      Q_ASSERT( false );
    }

    /**
     * Imports a compressed project from a given URL and place the content into the Imported Projects
     * folder.
     * \param url the http/https URL where the project's compressed ZIP file is
     * \param url the title of the project being imported
     * \param loadOnImport set to TRUE to load the project on successful import
     */
    Q_INVOKABLE void importUrl( const QString &url, const QString &title = QString(), bool loadOnImport = false );

    //! Returns TRUE is a project was passed on when launching QField.
    Q_INVOKABLE bool hasProjectOnLaunch() const;

    /**
     * Loads a project file or standalone dataset.
     *
     * \param path the project file (.qgs or .qgz) or standalone dataset path
     * \param name a project name (if left empty, the project file will be used instead)
     */
    Q_INVOKABLE bool loadFile( const QString &path, const QString &name = QString() );

    //! Saves the currently opened project.
    Q_INVOKABLE bool saveProject();

    //! Saves the currently opened project under \a path.
    Q_INVOKABLE bool saveProjectAs( const QString &path );

    //! Clears the current project and writes a blank one at \a path.
    Q_INVOKABLE bool createBlankProject( const QString &path );

    //! Recursively removes a project folder at \a path. Refuses template masters.
    Q_INVOKABLE bool removeProjectFolder( const QString &path );

    //! Returns the current project title.
    Q_INVOKABLE QString projectTitle() const;

    //! Sets the current project \a title.
    Q_INVOKABLE void setProjectTitle( const QString &title );

    //! Returns the current project CRS authid (e.g. EPSG:2180).
    Q_INVOKABLE QString projectCrsAuthid() const;

    //! Returns the current project CRS description.
    Q_INVOKABLE QString projectCrsDescription() const;

    //! Sets the project CRS from \a authid, returns false when invalid.
    Q_INVOKABLE bool setProjectCrs( const QString &authid );

    //! Writes \a content into a text file at \a path.
    Q_INVOKABLE bool writeTextFile( const QString &path, const QString &content );

    //! Returns the user-preferred data directory, or empty when unset/invalid.
    Q_INVOKABLE QString preferredDataDir() const;

    //! Persists the user-preferred data directory (empty clears the preference).
    Q_INVOKABLE void setPreferredDataDir( const QString &path );

    //! Returns free space at \a path in gigabytes.
    Q_INVOKABLE double storageFreeGb( const QString &path ) const;

    //! Effective data root: preferred dir when set, first app data dir otherwise.
    Q_INVOKABLE QString dataRoot() const;

    //! Copies data content from \a source to \a destination; removes source content when \a removeSource.
    Q_INVOKABLE bool migrateDataDir( const QString &source, const QString &destination, bool removeSource );

    //! Runs a GDAL DEM tool (slope, aspect, hillshade, TRI, TPI, roughness) on \a inputPath.
    Q_INVOKABLE bool demProcessing( const QString &tool, const QString &inputPath, const QString &outputPath );

    //! Computes rasterA - rasterB (e.g. CHM = NMPT - NMT) into \a outputPath.
    Q_INVOKABLE bool rasterDifference( const QString &pathA, const QString &pathB, const QString &outputPath );

    //! Lists file names in \a dirPath matching \a nameFilter (e.g. "*.asc").
    Q_INVOKABLE QStringList listFiles( const QString &dirPath, const QString &nameFilter ) const;

    //! Async download of \a url into \a destinationPath; emits downloadFinished/downloadFailed.
    Q_INVOKABLE void downloadFile( const QString &url, const QString &destinationPath );

    //! Adds raster at \a path to the project with a turbo pseudocolor renderer.
    Q_INVOKABLE bool addRasterLayerToProject( const QString &path, const QString &name, const QString &crsAuthid, const QString &style = QString() );

    //! Sample points (grid x grid) covering the visible extent, reprojected to EPSG:2180.
    Q_INVOKABLE QVariantList visibleExtentPointsIn2180( QgsQuickMapSettings *mapSettings, int grid );

    //! Reloads the currently opened project.
    Q_INVOKABLE void reloadProject();

    /**
     * Reads a string from the specified scope and key.
     * \param scope	entry scope (group) name
     * \param key	entry key name. Keys are '/'-delimited entries, implying a hierarchy of keys and corresponding values
     * \param def	default value to return if the specified key does not exist within the scope
     */
    Q_INVOKABLE QString readProjectEntry( const QString &scope, const QString &key, const QString &def = QString() ) const;

    /**
     * Reads an integer from the specified scope and key.
     * \param scope	entry scope (group) name
     * \param key	entry key name. Keys are '/'-delimited entries, implying a hierarchy of keys and corresponding values
     * \param def	default value to return if the specified key does not exist within the scope
     */
    Q_INVOKABLE int readProjectNumEntry( const QString &scope, const QString &key, int def = 0 ) const;

    /**
     * Reads a double from the specified scope and key.
     * \param scope	entry scope (group) name
     * \param key	entry key name. Keys are '/'-delimited entries, implying a hierarchy of keys and corresponding values
     * \param def	default value to return if the specified key does not exist within the scope
     */
    Q_INVOKABLE double readProjectDoubleEntry( const QString &scope, const QString &key, double def = 0.0 ) const;

    /**
     * Reads a double from the specified scope and key.
     * \param scope	entry scope (group) name
     * \param key	entry key name. Keys are '/'-delimited entries, implying a hierarchy of keys and corresponding values
     * \param def	default value to return if the specified key does not exist within the scope
     */
    Q_INVOKABLE bool readProjectBoolEntry( const QString &scope, const QString &key, bool def = false ) const;

    /**
     * Prints a project layout to PDF.
     * \param layoutName the layout name
     */
    Q_INVOKABLE bool print( const QString &layoutName );

    /**
     * Prints an atlas-driven project layout to PDF.
     * \param layoutName the layout name
     * \param featureIds the list of atlas feature IDs
     */
    Q_INVOKABLE bool printAtlasFeatures( const QString &layoutName, const QList<long long> &featureIds );

    /**
     * Sets the screen drimmer timeout. Dimming can be disabled by setting the timeout to zero.
     * \param timeoutSeconds timeout in seconds
     */
    Q_INVOKABLE void setScreenDimmerTimeout( int timeoutSeconds );

    //! Returns a list of available UI translation languages
    Q_INVOKABLE QVariantMap availableLanguages() const;

    /**
     * Changes the application language to the specified \a languageCode.
     * This will reload translators and refresh all QML translations without restarting the app.
     * \param languageCode The language code (e.g., "en", "de")
     * \see availableLanguages
     */
    Q_INVOKABLE void changeLanguage( const QString &languageCode );

    //! Returns TRUE if a given \a filename can be opened as a project or standalone dataset.
    Q_INVOKABLE bool isFileExtensionSupported( const QString &filename ) const;

    /**
     * Adds a log \a message that will be visible to the user through the
     * message log panel, as well as added into the device's system logs
     * which will be captured by the sentry's reporting framework when enabled.
     */
    Q_INVOKABLE void logMessage( const QString &message );

    /**
     * Outputs the current runtime profiler model content into the message log
     * panel, as well as added into the device's system logs
     * which will be captured by the sentry's reporting framework when enabled.
     */
    Q_INVOKABLE void logRuntimeProfiler();

    /**
     * Sends a logs reporting through to sentry when enabled.
     */
    Q_INVOKABLE void sendLog( const QString &message, const QString &cloudUser );

    /**
     * Initalizes sentry connection.
     */
    Q_INVOKABLE void initiateSentry() const;

    /**
     * Closes active sentry connection.
     */
    Q_INVOKABLE void closeSentry() const;

    /**
     * Clears the currently opened project
     */
    Q_INVOKABLE void clearProject() const;

    /**
     * Returns the item matching the provided object \a name
     */
    Q_INVOKABLE QObject *findItemByObjectName( const QString &name ) const;

    /**
     * Adds an \a item in the plugins toolbar container
     */
    Q_INVOKABLE void addItemToPluginsToolbar( QQuickItem *item ) const;

    /**
     * Adds a geometry \a configuration to the persistent plugin 3D container.
     */
    Q_INVOKABLE void addItemToMapCanvas3D( QQuickItem *item ) const;

    /**
     * Adds an \a item in the map canvas menu's action toolbar container
     */
    Q_INVOKABLE void addItemToCanvasActionsToolbar( QQuickItem *item ) const;

    /**
     * Adds an \a item in the dashboard's action toolbar container
     */
    Q_INVOKABLE void addItemToDashboardActionsToolbar( QQuickItem *item ) const;

    /**
     * Adds an \a item in the dashboard's action toolbar container
     * \note This function is deprecated and will be removed in the future, use
     * the addItemToDashboardActionsToolbar function instead
     */
    Q_INVOKABLE void addItemToMainMenuActionsToolbar( QQuickItem *item ) const;

    /**
     * Returns the main window.
     */
    Q_INVOKABLE QObject *mainWindow() const;

    /**
     * Returns the main map canvas item.
     * \see MapCanvas
     */
    Q_INVOKABLE QObject *mapCanvas() const;

    /**
     * Returns the positioning item.
     * \see Positioning
     */
    Q_INVOKABLE QObject *positioning() const;


    /**
     * Applies network proxy settings stored in QSettings to the network access manager.
     * Call this after updating the proxy/ settings keys.
     */
    Q_INVOKABLE void setupNetworkProxy() const;

    //! One-shot xmlhttp request. Defaults to autoDelete = true.
    Q_INVOKABLE QObject *createHttpRequest() const;

    /// @cond PRIVATE
    //! Reads the content of the loaded project, called on loadProjectTriggered()
    Q_INVOKABLE void readProject();

    static void setInstance( AppInterface *instance ) { sAppInterface = instance; }
    static AppInterface *instance() { return sAppInterface; }
    ///@endcond

  signals:
    /**
     * Emitted when a dataset or project import has been triggered.
     * \param name a indentifier-friendly string (e.g. a file being imported)
     */
    void importTriggered( const QString &name );

    /**
     * Emitted when an ongoing import reports its \a progress.
     * \note when an import is started, its progress will be indefinite by default
     */
    void importProgress( double progress );

    /**
     * Emitted when an import has ended.
     * \param path the path within which the imported dataset or project has been copied into
     * \note if the import was not successful, the path value will be an empty string
     */
    void importEnded( const QString &path = QString(), const QString &originalUrl = QString() );

    /**
     * Emitted when a project has begin loading.
     */
    void loadProjectTriggered( const QString &path, const QString &name );

    /**
     * Emitted when a project loading has ended.
     */
    void loadProjectEnded( const QString &path, const QString &name );
    void downloadFinished( const QString &path );
    void downloadFailed( const QString &error, const QString &path );

    //! Requests QField to set its map to the provided \a extent.
    void setMapExtent( const QgsRectangle &extent );

    //! Requests QField to open its local data picker screen to show the \a path content.
    void openPath( const QString &path );

    //! Requests QField to execute a given \a action.
    void executeAction( const QString &action );

    //! Emitted when a volume key is pressed while QField is set to handle those keys.
    void volumeKeyDown( int volumeKeyCode );

    //! Emitted when a volume key is pressed while QField is set to handle those keys.
    void volumeKeyUp( int volumeKeyCode );

  private:
    QObject *rootObject() const;
    QgisMobileapp *app() const;

    static AppInterface *sAppInterface;

    QQmlEngine *mEngine = nullptr;
};

#endif // APPINTERFACE_H
