/***************************************************************************
  cameraorientationnormalizer.cpp - CameraOrientationNormalizer

 ---------------------
 begin                : 16.4.2026
 copyright            : (C) 2026 by Kaustuv Pokharel
 email                : kaustuv@opengis.ch
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#include "cameraorientationnormalizer.h"

#include <QGuiApplication>
#include <QImage>
#include <QImageReader>
#include <QImageWriter>
#include <QScreen>
#include <QTransform>

CameraOrientationNormalizer::CameraOrientationNormalizer( QObject *parent )
  : QObject( parent )
{
  QScreen *screen = QGuiApplication::primaryScreen();
  if ( screen )
  {
    mCurrentOrientation = screen->orientation();
    connect( screen, &QScreen::orientationChanged, this, &CameraOrientationNormalizer::handleScreenOrientationChanged );
  }
}

int CameraOrientationNormalizer::previewRotation() const
{
  return mPreviewRotation;
}

void CameraOrientationNormalizer::recordCaptureOrientation()
{
  QScreen *screen = QGuiApplication::primaryScreen();
  mCaptureOrientation = screen ? screen->orientation() : Qt::PortraitOrientation;
}

bool CameraOrientationNormalizer::normalizeImageOrientation( const QString &path )
{
#if defined( Q_OS_IOS ) || defined( Q_OS_WIN )
  if ( path.isEmpty() )
  {
    return false;
  }

  QImageReader reader( path );
  reader.setAutoTransform( false );
  const QImageIOHandler::Transformations exifTransform = reader.transformation();
  QImage image = reader.read();
  if ( image.isNull() )
  {
    return false;
  }

  const bool capturedInLandscape = ( mCaptureOrientation == Qt::LandscapeOrientation || mCaptureOrientation == Qt::InvertedLandscapeOrientation );
  const bool pixelsAreLandscape = image.width() > image.height();
  const bool needsRotation = ( capturedInLandscape != pixelsAreLandscape );
  const bool hasExifTag = ( exifTransform != QImageIOHandler::TransformationNone );

  if ( !needsRotation && !hasExifTag )
  {
    return false;
  }

  if ( needsRotation )
  {
    QTransform transform;
    transform.rotate( pixelsAreLandscape ? 90 : 270 );
    image = image.transformed( transform, Qt::SmoothTransformation );
  }

  QImageWriter writer( path );
  writer.setTransformation( QImageIOHandler::TransformationNone );
  writer.setQuality( 95 );
  return writer.write( image );
#else
  Q_UNUSED( path )
  return false;
#endif
}

void CameraOrientationNormalizer::handleScreenOrientationChanged( Qt::ScreenOrientation orientation )
{
  if ( mCurrentOrientation == orientation )
  {
    return;
  }

  mCurrentOrientation = orientation;
  updatePreviewRotation();
}

void CameraOrientationNormalizer::updatePreviewRotation()
{
  const QScreen *screen = QGuiApplication::primaryScreen();
  if ( !screen )
  {
    return;
  }

  const int screenAngle = screen->angleBetween( screen->nativeOrientation(), mCurrentOrientation );
  const bool isLandscape = ( screenAngle == 90 || screenAngle == 270 );
#if defined( Q_OS_ANDROID )
  // urzadzenia z czujnikiem obroconym wzgledem ekranu: korekta w pionie, poziom bez zmian
  const int rotation = isLandscape ? 0 : 180;
#else
  const int rotation = isLandscape ? 180 : 0;
#endif

  if ( rotation != mPreviewRotation )
  {
    mPreviewRotation = rotation;
    emit previewRotationChanged();
  }
}

bool CameraOrientationNormalizer::rotateImageFile( const QString &path, int degrees )
{
  const int normalized = ( ( degrees % 360 ) + 360 ) % 360;
  if ( path.isEmpty() || normalized == 0 )
    return false;

  QImageReader reader( path );
  reader.setAutoTransform( false );
  QImage image = reader.read();
  if ( image.isNull() )
    return false;

  QTransform transform;
  transform.rotate( normalized );
  image = image.transformed( transform, Qt::SmoothTransformation );

  QImageWriter writer( path );
  writer.setTransformation( QImageIOHandler::TransformationNone );
  writer.setQuality( 95 );
  return writer.write( image );
}
