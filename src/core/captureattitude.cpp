/***************************************************************************
  captureattitude.cpp - CaptureAttitude (WorkField)
 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "captureattitude.h"

#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <QtDebug>
#include <QtMath>
#include <cmath>

#include <qgsexiftools.h>

CaptureAttitude::CaptureAttitude( QObject *parent )
  : QObject( parent )
{
  connect( &mAccelerometer, &QAccelerometer::readingChanged, this, &CaptureAttitude::processReading );
  mAccelerometer.setAccelerationMode( QAccelerometer::Gravity );
  mAccelerometer.start();
  // awaryjne zrodlo: gdy backend nie wspiera trybu Gravity i milczy,
  // po 2 s przelacz na tryb podstawowy (filtr wygladzi reszte)
  QTimer::singleShot( 2000, this, [this]() {
    if ( !mHasReading )
    {
      qInfo() << "CaptureAttitude: brak odczytow w trybie Gravity, przelaczam na Combined";
      mAccelerometer.stop();
      mAccelerometer.setAccelerationMode( QAccelerometer::Combined );
      mAccelerometer.start();
    }
  } );
}

void CaptureAttitude::processReading()
{
  QAccelerometerReading *reading = mAccelerometer.reading();
  if ( !reading )
  {
    return;
  }

  // filtr dolnoprzepustowy: tlumi drzenie reki, nie gubi swiadomego kadrowania
  constexpr double alpha = 0.2;
  if ( !mHasReading )
  {
    mGx = reading->x();
    mGy = reading->y();
    mGz = reading->z();
  }
  else
  {
    mGx = ( 1.0 - alpha ) * mGx + alpha * reading->x();
    mGy = ( 1.0 - alpha ) * mGy + alpha * reading->y();
    mGz = ( 1.0 - alpha ) * mGz + alpha * reading->z();
  }

  const double g = std::sqrt( mGx * mGx + mGy * mGy + mGz * mGz );
  if ( g < 1.0 )
  {
    // sensor jeszcze sie nie rozpedzil albo urzadzenie w swobodnym spadku;
    // nie udawajmy, ze znamy poze
    return;
  }

  mHasReading = true;
  // os optyczna tylnego aparatu = -Z urzadzenia:
  // ekranem do gory (aparat w dol)  -> gz=+g -> pitch=-90
  // pion, aparat poziomo            -> gz~=0 -> pitch=0
  // ekranem do ziemi (aparat w gore)-> gz=-g -> pitch=+90
  mPitch = qRadiansToDegrees( std::asin( std::clamp( -mGz / g, -1.0, 1.0 ) ) );
  // 0 = portret; znak wedle obrotu urzadzenia wokol osi optycznej
  mRoll = qRadiansToDegrees( std::atan2( mGx, mGy ) );
  emit attitudeChanged();
}

void CaptureAttitude::snapshot()
{
  if ( !mHasReading )
  {
    mHasSnapshot = false;
    return;
  }
  mSnapPitch = mPitch;
  mSnapRoll = mRoll;
  mHasSnapshot = true;
}

bool CaptureAttitude::writePoseMetadata( const QString &path, double headingDegrees )
{
  if ( path.isEmpty() || !QFileInfo::exists( path ) )
  {
    return false;
  }

  double headingResolved = headingDegrees;
  if ( !std::isfinite( headingResolved ) )
  {
    // awaryjne zrodlo azymutu: to, co geotag wlasnie zapisal do pliku
    const QVariant fromFile = QgsExifTools::readTag( path, QStringLiteral( "Exif.GPSInfo.GPSImgDirection" ) );
    bool ok = false;
    const double v = fromFile.toDouble( &ok );
    if ( ok )
      headingResolved = v;
  }
  const bool hasHeading = std::isfinite( headingResolved );
  if ( !mHasSnapshot && !hasHeading )
  {
    return false;
  }

  QVariantMap metadata;
  QJsonObject pose;
  if ( hasHeading )
  {
    // znormalizuj do 0..360, jak chce GPano
    double heading = std::fmod( headingResolved, 360.0 );
    if ( heading < 0 )
      heading += 360.0;
    metadata[QStringLiteral( "Xmp.GPano.PoseHeadingDegrees" )] = heading;
    pose[QStringLiteral( "azymut_deg" )] = std::round( heading * 10.0 ) / 10.0;
  }
  if ( mHasSnapshot )
  {
    metadata[QStringLiteral( "Xmp.GPano.PosePitchDegrees" )] = mSnapPitch;
    metadata[QStringLiteral( "Xmp.GPano.PoseRollDegrees" )] = mSnapRoll;
    pose[QStringLiteral( "pitch_deg" )] = std::round( mSnapPitch * 10.0 ) / 10.0;
    pose[QStringLiteral( "roll_deg" )] = std::round( mSnapRoll * 10.0 ) / 10.0;
  }
  metadata[QStringLiteral( "Exif.Photo.UserComment" )] = QString::fromUtf8( QJsonDocument( pose ).toJson( QJsonDocument::Compact ) );

  qInfo() << "CaptureAttitude: zapis pozy" << path << "heading:" << ( hasHeading ? QString::number( headingResolved, 'f', 1 ) : QStringLiteral( "brak" ) ) << "pitch/roll:" << ( mHasSnapshot ? QStringLiteral( "%1 / %2" ).arg( mSnapPitch, 0, 'f', 1 ).arg( mSnapRoll, 0, 'f', 1 ) : QStringLiteral( "brak" ) );
  bool ok = true;
  for ( auto it = metadata.constBegin(); it != metadata.constEnd(); ++it )
  {
    ok = QgsExifTools::tagImage( path, it.key(), it.value() ) && ok;
  }
  return ok;
}
