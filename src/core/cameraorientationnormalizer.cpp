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

#include <QFile>
#include <QGuiApplication>
#include <QSaveFile>
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
  // stan poczatkowy: bez tego previewRotation trzyma 0 do pierwszego obrotu
  // urzadzenia i podglad startuje odwrocony (pion na Androidzie wymaga 180)
  updatePreviewRotation();
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

bool CameraOrientationNormalizer::setExifOrientation( const QString &path, int degrees )
{
  const int normalized = ( ( degrees % 360 ) + 360 ) % 360;
  quint16 orientationValue = 0;
  switch ( normalized )
  {
    case 0:
      orientationValue = 1;
      break;
    case 90:
      orientationValue = 6;
      break;
    case 180:
      orientationValue = 3;
      break;
    case 270:
      orientationValue = 8;
      break;
    default:
      return false; // tylko wielokrotnosci 90 stopni
  }

  QFile file( path );
  if ( !file.open( QIODevice::ReadWrite ) )
    return false;

  QByteArray data = file.readAll();
  const qsizetype size = data.size();
  if ( size < 4 || quint8( data[0] ) != 0xFF || quint8( data[1] ) != 0xD8 )
    return false; // nie JPEG

  // przejdz po segmentach JPEG w poszukiwaniu APP1/Exif
  qsizetype pos = 2;
  while ( pos + 4 <= size )
  {
    if ( quint8( data[pos] ) != 0xFF )
      return false; // uszkodzona struktura segmentow
    const quint8 markerType = quint8( data[pos + 1] );
    if ( markerType == 0xDA )
      break; // start skompresowanych danych - APP1 juz nie wystapi
    if ( markerType == 0xD8 || ( markerType >= 0xD0 && markerType <= 0xD7 ) || markerType == 0x01 )
    {
      pos += 2; // markery bez pola dlugosci
      continue;
    }
    const quint16 segLen = quint16( ( quint8( data[pos + 2] ) << 8 ) | quint8( data[pos + 3] ) );
    if ( segLen < 2 || pos + 2 + segLen > size )
      return false;

    if ( markerType == 0xE1 && segLen >= 2 + 6 + 8 + 2 && data.mid( pos + 4, 6 ) == QByteArray( "Exif\0\0", 6 ) )
    {
      const qsizetype tiff = pos + 10;          // poczatek naglowka TIFF
      const qsizetype segEnd = pos + 2 + segLen; // pierwszy bajt ZA segmentem
      const QByteArray byteOrder = data.mid( tiff, 2 );
      const bool little = ( byteOrder == "II" );
      if ( !little && byteOrder != "MM" )
        return false;

      const auto rd16 = [&data, little]( qsizetype o ) -> quint16 {
        const quint8 a = quint8( data[o] );
        const quint8 b = quint8( data[o + 1] );
        return little ? quint16( a | ( b << 8 ) ) : quint16( ( a << 8 ) | b );
      };
      const auto rd32 = [&data, little]( qsizetype o ) -> quint32 {
        const quint32 a = quint8( data[o] );
        const quint32 b = quint8( data[o + 1] );
        const quint32 c = quint8( data[o + 2] );
        const quint32 d = quint8( data[o + 3] );
        return little ? ( a | ( b << 8 ) | ( c << 16 ) | ( d << 24 ) )
                      : ( ( a << 24 ) | ( b << 16 ) | ( c << 8 ) | d );
      };

      if ( tiff + 8 > segEnd || rd16( tiff + 2 ) != 42 )
        return false;
      const qsizetype ifd0 = tiff + rd32( tiff + 4 );
      if ( ifd0 + 2 > segEnd )
        return false;
      const quint16 entries = rd16( ifd0 );
      for ( quint16 i = 0; i < entries; ++i )
      {
        const qsizetype e = ifd0 + 2 + qsizetype( i ) * 12;
        if ( e + 12 > segEnd )
          return false;
        if ( rd16( e ) != 0x0112 )
          continue;
        // Orientation: typ SHORT(3), count 1 - wartosc w 2 pierwszych bajtach pola
        if ( rd16( e + 2 ) != 3 || rd32( e + 4 ) != 1 )
          return false;
        char out[2];
        if ( little )
        {
          out[0] = char( orientationValue & 0xFF );
          out[1] = char( orientationValue >> 8 );
        }
        else
        {
          out[0] = char( orientationValue >> 8 );
          out[1] = char( orientationValue & 0xFF );
        }
        if ( !file.seek( e + 8 ) || file.write( out, 2 ) != 2 )
          return false;
        return file.flush();
      }
      return false; // EXIF bez znacznika Orientation - dopisywanie do cudzego
                    // IFD wymaga przesuwania offsetow; oddaj sprawe fallbackowi
    }
    pos += 2 + segLen;
  }

  // Brak segmentu EXIF: wstaw minimalny APP1 (little-endian) zaraz za SOI.
  if ( orientationValue == 1 )
    return true; // i tak nie ma czego prostowac

  file.close();
  QByteArray app1;
  app1.append( char( 0xFF ) ).append( char( 0xE1 ) );
  app1.append( char( 0x00 ) ).append( char( 0x22 ) );     // dlugosc 34
  app1.append( "Exif\0\0", 6 );
  app1.append( "II", 2 );                                  // little-endian
  app1.append( char( 0x2A ) ).append( char( 0x00 ) );      // magiczne 42
  app1.append( char( 0x08 ) ).append( char( 0x00 ) ).append( char( 0x00 ) ).append( char( 0x00 ) ); // IFD0 @ 8
  app1.append( char( 0x01 ) ).append( char( 0x00 ) );      // 1 wpis
  app1.append( char( 0x12 ) ).append( char( 0x01 ) );      // tag 0x0112
  app1.append( char( 0x03 ) ).append( char( 0x00 ) );      // typ SHORT
  app1.append( char( 0x01 ) ).append( char( 0x00 ) ).append( char( 0x00 ) ).append( char( 0x00 ) ); // count 1
  app1.append( char( orientationValue & 0xFF ) ).append( char( orientationValue >> 8 ) );
  app1.append( char( 0x00 ) ).append( char( 0x00 ) );      // dopelnienie wartosci
  app1.append( 4, char( 0x00 ) );                          // brak kolejnego IFD

  QSaveFile save( path );
  if ( !save.open( QIODevice::WriteOnly ) )
    return false;
  save.write( data.constData(), 2 );
  save.write( app1 );
  save.write( data.constData() + 2, size - 2 );
  return save.commit();
}

