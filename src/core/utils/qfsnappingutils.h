/***************************************************************************
  qfsnappingutils.h

 ---------------------
 begin                : 8.10.2016
 copyright            : (C) 2016 by Matthias Kuhn
 email                : matthias@opengis.ch
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#ifndef QFSNAPPINGUTILS_H
#define QFSNAPPINGUTILS_H

class QgsQuickMapSettings;

#include "qfsnappingresult.h"

#include <qgssnappingutils.h>

/**
 * \ingroup core
 */
class QfSnappingUtils : public QgsSnappingUtils
{
    Q_OBJECT

    Q_PROPERTY( bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged )
    Q_PROPERTY( QgsQuickMapSettings *mapSettings READ mapSettings WRITE setMapSettings NOTIFY mapSettingsChanged )
    Q_PROPERTY( QgsVectorLayer *currentLayer READ currentLayer WRITE setCurrentLayer NOTIFY currentLayerChanged )
    Q_PROPERTY( QfSnappingResult snappingResult READ snappingResult NOTIFY snappingResultChanged )
    Q_PROPERTY( QPointF inputCoordinate READ inputCoordinate WRITE setInputCoordinate NOTIFY inputCoordinateChanged )

    /**
     * Ile razy wiekszy prog obowiazuje, gdy wierzcholek JUZ jest zaczepiony.
     *
     * 1.0 (domyslnie) = zachowanie bez zmian. 2.0 = lapie z 2 m, puszcza
     * dopiero po 4 m. Bez tego wierzcholek drga na granicy progu: wchodzi,
     * przyskakuje, wychodzi, puszcza — przy kazdym drgnieciu reki.
     */
    Q_PROPERTY( double mnoznikHisterezy READ mnoznikHisterezy WRITE setMnoznikHisterezy NOTIFY mnoznikHisterezyChanged )

  public:
    explicit QfSnappingUtils( QObject *parent = nullptr );

    bool enabled() const;
    void setEnabled( bool enabled );

    QgsQuickMapSettings *mapSettings() const;
    void setMapSettings( QgsQuickMapSettings *settings );

    QgsVectorLayer *currentLayer() const;
    void setCurrentLayer( QgsVectorLayer *currentLayer );

    QPointF inputCoordinate() const;
    void setInputCoordinate( const QPointF &inputCoordinate );

    QfSnappingResult snappingResult() const;

    double mnoznikHisterezy() const { return mMnoznikHisterezy; }
    void setMnoznikHisterezy( double mnoznik );

    static QgsPoint newPoint( const QgsPoint &snappedPoint, const Qgis::WkbType wkbType );

    /**
     * Returns an empty snapping configuration object
     * \note This can be used in QML to avoid errors when a parent object pointer goes undefined
     */
    static Q_INVOKABLE QgsSnappingConfig emptySnappingConfig() { return QgsSnappingConfig(); }

  signals:
    void enabledChanged();
    void mapSettingsChanged();
    void currentLayerChanged();
    void snappingResultChanged();
    void inputCoordinateChanged();
    void mnoznikHisterezyChanged();

    void indexingStarted( int count );
    void indexingProgress( int index );
    void indexingFinished();

  protected:
    virtual void prepareIndexStarting( int count ) override;
    virtual void prepareIndexProgress( int index ) override;

  private slots:
    void onMapSettingsUpdated();
    void removeOutdatedLocators();

  private:
    void snap();

    bool mEnabled = false;
    QgsQuickMapSettings *mSettings = nullptr;
    QgsVectorLayer *mCurrentLayer = nullptr;

    int mIndexLayerCount;
    QfSnappingResult mSnappingResult;
    QPointF mInputCoordinate;

    //! 1.0 = bez histerezy. Patrz `mnoznikHisterezy`.
    double mMnoznikHisterezy = 1.0;
    //! Czy poprzedni pomiar byl zaczepiony — od tego zalezy, ktory prog.
    bool mBylZaczepiony = false;
};


#endif // QFSNAPPINGUTILS_H
