/***************************************************************************
  qfpositioningsource.cpp - QfPositioningSource

 ---------------------
 begin                : 20.12.2024
 copyright            : (C) 2024 by Mathieu Pellerin
 email                : mathieu at opengis dot ch
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#ifdef WITH_BLUETOOTH
#include "qfbluetoothlowenergyreceiver.h"
#include "qfbluetoothreceiver.h"
#endif
#ifdef WITH_SERIALPORT
#include "qfserialportreceiver.h"
#endif
#include "qfegenioussreceiver.h"
#include "qffilereceiver.h"
#include "qfinternalgnssreceiver.h"
#include "qfnmeagnssreceiver.h"
#include "qfntripclient.h"
#include "qfpositioningsource.h"
#include "qfpositioningutils.h"
#include "qftcpreceiver.h"
#include "qfudpreceiver.h"

#include <QtMath>

#include <QDateTime>
#include <QStandardPaths>

QString QfPositioningSource::backgroundFilePath = QStringLiteral( "%1/positioning.background" ).arg( QStandardPaths::writableLocation( QStandardPaths::AppDataLocation ) );

QfPositioningSource::QfPositioningSource( QObject *parent )
  : QObject( parent )
{
  // Setup internal gnss receiver by default
  setupDevice();

  // Setup the compass, use a timer instead of the compass's readingChanged signal to avoid handling
  // too many signals
  mCompassTimer.setInterval( 200 );
  connect( &mCompassTimer, &QTimer::timeout, this, &QfPositioningSource::processCompassReading );
}

void QfPositioningSource::setActive( bool active )
{
  if ( mActive == active )
    return;

  mActive = active;

  if ( mActive )
  {
    if ( !mReceiver )
    {
      setupDevice();
    }
    else
    {
      triggerConnectDevice();
    }
    if ( !QSensor::sensorsForType( QCompass::sensorType ).isEmpty() )
    {
      mCompass.setActive( true );
      mCompassTimer.start();
    }
  }
  else
  {
    if ( mReceiver )
    {
      mReceiver->disconnectDevice();
    }
    mCompassTimer.stop();
    mCompass.setActive( false );
    mCompassReadings.clear();
    mOrientation = std::numeric_limits<double>::quiet_NaN();
    emit orientationChanged();
  }

  emit activeChanged();
}

void QfPositioningSource::setDeviceId( const QString &id )
{
  if ( mDeviceId == id )
    return;

  mDeviceId = id;
  setupDevice();

  emit deviceIdChanged();
}

void QfPositioningSource::setValid( bool valid )
{
  if ( mValid == valid )
    return;

  mValid = valid;

  emit validChanged();
}

void QfPositioningSource::setLogging( bool logging )
{
  if ( mLogging == logging )
    return;

  mLogging = logging;

  if ( mReceiver )
  {
    if ( mLogging && !mLoggingPath.isEmpty() )
    {
      mReceiver->startLogging( mLoggingPath );
      if ( mNtripClient )
      {
        mNtripClient->startLogging( mLoggingPath );
      }
    }
    else
    {
      mReceiver->stopLogging();
      if ( mNtripClient )
      {
        mNtripClient->stopLogging();
      }
    }
  }

  emit loggingChanged();
}

void QfPositioningSource::setLoggingPath( const QString &path )
{
  if ( mLoggingPath == path )
    return;

  mLoggingPath = path;

  if ( mReceiver && mLogging )
  {
    mReceiver->startLogging( mLoggingPath );
    if ( mNtripClient )
    {
      mNtripClient->startLogging( mLoggingPath );
    }
  }

  emit loggingPathChanged();
}

void QfPositioningSource::setBackgroundMode( bool backgroundMode )
{
  if ( mBackgroundMode == backgroundMode )
    return;

  mBackgroundMode = backgroundMode;

  if ( mBackgroundMode )
  {
    if ( QFile::exists( QStringLiteral( "%1.information" ).arg( backgroundFilePath ) ) )
    {
      // Remove previously collected position information
      QFile::remove( QStringLiteral( "%1.information" ).arg( backgroundFilePath ) );
    }
  }

  emit backgroundModeChanged();
}


void QfPositioningSource::setEnableNtrip( bool enableNtrip )
{
  if ( mEnableNtrip == enableNtrip )
  {
    return;
  }

  mEnableNtrip = enableNtrip;

  if ( mEnableNtrip )
  {
    startNtripClient();
  }
  else
  {
    stopNtripClient();
  }

  emit enableNtripChanged();
}

void QfPositioningSource::setNtripSettings( const QfNtripSettings &ntripSettings )
{
  if ( mNtripSettings == ntripSettings )
  {
    return;
  }

  mNtripSettings = ntripSettings;

  if ( mEnableNtrip )
  {
    startNtripClient();
  }

  emit ntripSettingsChanged();
}

QList<QfGnssPositionInformation> QfPositioningSource::getBackgroundPositionInformation() const
{
  QList<QfGnssPositionInformation> positionInformationList;

  QFile file( QStringLiteral( "%1.information" ).arg( backgroundFilePath ) );
  if ( file.exists() )
  {
    if ( file.open( QFile::ReadOnly ) )
    {
      QDataStream stream( &file );
      while ( !stream.atEnd() )
      {
        QfGnssPositionInformation positionInformation;
        stream >> positionInformation;
        positionInformationList << positionInformation;
      }
      file.close();
    }
  }

  return positionInformationList;
}

void QfPositioningSource::setElevationCorrectionMode( ElevationCorrectionMode elevationCorrectionMode )
{
  if ( mElevationCorrectionMode == elevationCorrectionMode )
    return;

  mElevationCorrectionMode = elevationCorrectionMode;

  emit elevationCorrectionModeChanged();
}

void QfPositioningSource::setAntennaHeight( double antennaHeight )
{
  if ( mAntennaHeight == antennaHeight )
    return;

  mAntennaHeight = antennaHeight;

  emit antennaHeightChanged();
}

void QfPositioningSource::setupDevice()
{
  if ( mReceiver )
  {
    triggerDisconnectDevice();
    mReceiver->stopLogging();

    disconnect( mReceiver.get(), &QfAbstractGnssReceiver::lastGnssPositionInformationChanged, this, &QfPositioningSource::lastGnssPositionInformationChanged );
    disconnect( mReceiver.get(), &QfAbstractGnssReceiver::lastErrorChanged, this, &QfPositioningSource::deviceLastErrorChanged );
    disconnect( mReceiver.get(), &QfAbstractGnssReceiver::socketStateChanged, this, &QfPositioningSource::deviceSocketStateChanged );
    disconnect( mReceiver.get(), &QfAbstractGnssReceiver::socketStateStringChanged, this, &QfPositioningSource::deviceSocketStateStringChanged );
    disconnect( mReceiver.get(), &QfAbstractGnssReceiver::socketStateChanged, this, &QfPositioningSource::onDeviceSocketStateChanged );
    disconnect( mReceiver.get(), &QfAbstractGnssReceiver::batteryLevelChanged, this, &QfPositioningSource::deviceBatteryLevelChanged );

    mReceiver->deleteLater();
    mReceiver.reset();
    stopNtripClient();
  }

  if ( mDeviceId.isEmpty() )
  {
    mReceiver = std::make_unique<QfInternalGnssReceiver>( this );
  }
  else
  {
    if ( mDeviceId.startsWith( QfFileReceiver::identifier + ":" ) )
    {
      const qsizetype prefixLength = QfFileReceiver::identifier.length() + 1;
      const qsizetype intervalSeparator = mDeviceId.lastIndexOf( ':' );
      const QString filePath = mDeviceId.mid( prefixLength, intervalSeparator - prefixLength );
      const int interval = mDeviceId.mid( intervalSeparator + 1 ).toInt();
      mReceiver = std::make_unique<QfFileReceiver>( filePath, interval, this );
    }
    else if ( mDeviceId.startsWith( QfTcpReceiver::identifier + ":" ) )
    {
      const qsizetype prefixLength = QfTcpReceiver::identifier.length() + 1;
      const qsizetype portSeparator = mDeviceId.lastIndexOf( ':' );
      const QString address = mDeviceId.mid( prefixLength, portSeparator - prefixLength );
      const int port = mDeviceId.mid( portSeparator + 1 ).toInt();
      mReceiver = std::make_unique<QfTcpReceiver>( address, port, this );
    }
    else if ( mDeviceId.startsWith( QfUdpReceiver::identifier + ":" ) )
    {
      const qsizetype prefixLength = QfUdpReceiver::identifier.length() + 1;
      const qsizetype portSeparator = mDeviceId.lastIndexOf( ':' );
      const QString address = mDeviceId.mid( prefixLength, portSeparator - prefixLength );
      const int port = mDeviceId.mid( portSeparator + 1 ).toInt();
      mReceiver = std::make_unique<QfUdpReceiver>( address, port, this );
    }
    else if ( mDeviceId.startsWith( QfEgenioussReceiver::identifier + ":" ) )
    {
      const qsizetype prefixLength = QfEgenioussReceiver::identifier.length() + 1;
      const qsizetype portSeparator = mDeviceId.lastIndexOf( ':' );
      const QString address = mDeviceId.mid( prefixLength, portSeparator - prefixLength );
      const int port = mDeviceId.mid( portSeparator + 1 ).toInt();
      mReceiver = std::make_unique<QfEgenioussReceiver>( address, port, this );
    }
#ifdef WITH_SERIALPORT
    else if ( mDeviceId.startsWith( QfSerialPortReceiver::identifier + ":" ) )
    {
      const qsizetype prefixLength = QfSerialPortReceiver::identifier.length() + 1;
      const QString address = mDeviceId.mid( prefixLength );
      mReceiver = std::make_unique<QfSerialPortReceiver>( address, this );
    }
#endif
#ifdef WITH_BLUETOOTH
    else if ( mDeviceId.startsWith( QfBluetoothLowEnergyReceiver::identifier + ":" ) )
    {
      const qsizetype prefixLength = QfBluetoothLowEnergyReceiver::identifier.length() + 1;
      const QString address = mDeviceId.mid( prefixLength );
      mReceiver = std::make_unique<QfBluetoothLowEnergyReceiver>( address, this );
    }
    else
    {
      mReceiver = std::make_unique<QfBluetoothReceiver>( mDeviceId, this );
    }
#endif
  }

  // Reset the position information to insure no cross contamination between receiver types
  lastGnssPositionInformationChanged( QfGnssPositionInformation() );
  connect( mReceiver.get(), &QfAbstractGnssReceiver::lastGnssPositionInformationChanged, this, &QfPositioningSource::lastGnssPositionInformationChanged );
  connect( mReceiver.get(), &QfAbstractGnssReceiver::lastErrorChanged, this, &QfPositioningSource::deviceLastErrorChanged );
  connect( mReceiver.get(), &QfAbstractGnssReceiver::socketStateChanged, this, &QfPositioningSource::deviceSocketStateChanged );
  connect( mReceiver.get(), &QfAbstractGnssReceiver::socketStateChanged, this, &QfPositioningSource::onDeviceSocketStateChanged );
  connect( mReceiver.get(), &QfAbstractGnssReceiver::socketStateStringChanged, this, &QfPositioningSource::deviceSocketStateStringChanged );
  connect( mReceiver.get(), &QfAbstractGnssReceiver::batteryLevelChanged, this, &QfPositioningSource::deviceBatteryLevelChanged );

  setValid( mReceiver->valid() );

  emit deviceChanged();
  emit deviceBatteryLevelChanged();

  if ( mLogging && !mLoggingPath.isEmpty() )
  {
    mReceiver->startLogging( mLoggingPath );
  }

  if ( mActive )
  {
    triggerConnectDevice();
  }

  return;
}

void QfPositioningSource::lastGnssPositionInformationChanged( const QfGnssPositionInformation &lastGnssPositionInformation )
{
  if ( mPositionInformation == lastGnssPositionInformation )
    return;

  const QfGnssPositionInformation positionInformation( lastGnssPositionInformation.latitude(),
                                                       lastGnssPositionInformation.longitude(),
                                                       lastGnssPositionInformation.elevation(),
                                                       lastGnssPositionInformation.speed(),
                                                       lastGnssPositionInformation.direction(),
                                                       lastGnssPositionInformation.satellitesInView(),
                                                       lastGnssPositionInformation.pdop(),
                                                       lastGnssPositionInformation.hdop(),
                                                       lastGnssPositionInformation.vdop(),
                                                       lastGnssPositionInformation.hacc(),
                                                       lastGnssPositionInformation.vacc(),
                                                       lastGnssPositionInformation.utcDateTime().isValid() ? lastGnssPositionInformation.utcDateTime() : QDateTime::currentDateTimeUtc(),
                                                       lastGnssPositionInformation.fixMode(),
                                                       lastGnssPositionInformation.fixType(),
                                                       lastGnssPositionInformation.quality(),
                                                       lastGnssPositionInformation.satellitesUsed(),
                                                       lastGnssPositionInformation.status(),
                                                       lastGnssPositionInformation.satPrn(),
                                                       lastGnssPositionInformation.satInfoComplete(),
                                                       lastGnssPositionInformation.verticalSpeed(),
                                                       lastGnssPositionInformation.magneticVariation(),
                                                       lastGnssPositionInformation.averagedCount(),
                                                       lastGnssPositionInformation.sourceName(),
                                                       lastGnssPositionInformation.imuCorrection(),
                                                       lastGnssPositionInformation.imuRoll(),
                                                       lastGnssPositionInformation.imuPitch(),
                                                       lastGnssPositionInformation.imuHeading(),
                                                       lastGnssPositionInformation.imuSteering(),
                                                       mOrientation );
  mPositionInformation = positionInformation;

  if ( !mBackgroundMode )
  {
    emit positionInformationChanged();
  }
  else
  {
    QFile file( QStringLiteral( "%1.information" ).arg( backgroundFilePath ) );
    if ( file.open( QFile::Append ) )
    {
      QDataStream stream( &file );
      stream << mPositionInformation;
      file.close();
    }
  }
}

void QfPositioningSource::processCompassReading()
{
  if ( mCompass.reading() )
  {
    double orientation = 0.0;
    orientation += mCompass.reading()->azimuth();
    if ( orientation < 0.0 )
    {
      orientation = 360 + orientation;
    }

    // circular moving average to smooth noisy magnetometer readings
    if ( mCompassSmoothingWindowMs > 0 )
    {
      const int maxSamples = qMax( 1, mCompassSmoothingWindowMs / mCompassTimer.interval() );
      mCompassReadings.append( orientation );
      while ( mCompassReadings.size() > maxSamples )
        mCompassReadings.removeFirst();

      double sumSin = 0.0;
      double sumCos = 0.0;
      for ( const double reading : std::as_const( mCompassReadings ) )
      {
        sumSin += qSin( qDegreesToRadians( reading ) );
        sumCos += qCos( qDegreesToRadians( reading ) );
      }
      orientation = qRadiansToDegrees( qAtan2( sumSin, sumCos ) );
      if ( orientation < 0.0 )
      {
        orientation = 360 + orientation;
      }
    }

    if ( mOrientation != orientation )
    {
      mOrientation = orientation;
      if ( !mBackgroundMode )
      {
        emit orientationChanged();
      }
    }
  }
}

void QfPositioningSource::onDeviceSocketStateChanged()
{
  if ( mReceiver )
  {
    QAbstractSocket::SocketState state = mReceiver->socketState();

    // Stop NTRIP client when receiver is disconnected or has connection error
    if ( mNtripClient && ( state == QAbstractSocket::UnconnectedState || state == QAbstractSocket::ClosingState ) )
    {
      stopNtripClient();
    }
    // Start NTRIP client when external receiver connects and setting is enabled
    else if ( !mNtripClient && mEnableNtrip && !mDeviceId.isEmpty() && state == QAbstractSocket::ConnectedState )
    {
      startNtripClient();
    }
  }
}

void QfPositioningSource::triggerConnectDevice()
{
  if ( mReceiver )
  {
    mReceiver->connectDevice();

    if ( mEnableNtrip )
    {
      startNtripClient();
    }
  }
}

void QfPositioningSource::triggerDisconnectDevice()
{
  if ( mReceiver )
  {
    mReceiver->disconnectDevice();
    stopNtripClient();
  }
}

void QfPositioningSource::startNtripClient()
{
  if ( !mNtripSettings.isValid() )
  {
    return;
  }

  if ( !mReceiver || !( mReceiver->capabilities() & QfAbstractGnssReceiver::NtripCorrection ) )
  {
    return;
  }

  if ( !mNtripClient )
  {
    mNtripClient = std::make_unique<QfNtripClient>( this );

    connect( mNtripClient.get(), &QfNtripClient::streamConnected, this, [this]() {
      setNtripState( NtripState::Connected );
      setNtripLastError( QString() );
    } );

    connect( mNtripClient.get(), &QfNtripClient::streamDisconnected, this, [this]() {
      setNtripState( NtripState::Disconnected );
    } );

    connect( mNtripClient.get(), &QfNtripClient::errorOccurred, this, [this]( const QString &msg ) {
      setNtripLastError( msg );
      qInfo() << "NTRIP Client Error:" << msg;
    } );

    connect( mNtripClient.get(), &QfNtripClient::bytesSentChanged, this, [this]() {
      mNtripBytesSent = mNtripClient->bytesSent();
      emit ntripBytesSentChanged();
    } );

    connect( mNtripClient.get(), &QfNtripClient::bytesReceivedChanged, this, [this]() {
      mNtripBytesReceived = mNtripClient->bytesReceived();
      mNtripLastBytesReceivedUtcDateTime = QDateTime::currentDateTimeUtc();
      emit ntripBytesReceivedChanged();
      emit ntripLastBytesReceivedUtcDateTimeChanged();
    } );
  }

  mNtripBytesSent = 0;
  mNtripBytesReceived = 0;
  mNtripLastBytesReceivedUtcDateTime = QDateTime();
  emit ntripBytesSentChanged();
  emit ntripBytesReceivedChanged();
  emit ntripLastBytesReceivedUtcDateTimeChanged();
  setNtripState( NtripState::Disconnected );

  if ( mLogging )
  {
    mNtripClient->startLogging( mLoggingPath );
  }

  mNtripClient->start( mNtripSettings, mReceiver.get() );
  setNtripState( NtripState::Connecting );
}

void QfPositioningSource::stopNtripClient()
{
  if ( mNtripClient )
  {
    mNtripClient->stop();
    if ( mLogging )
    {
      mNtripClient->stopLogging();
    }
    mNtripClient.reset();

    setNtripState( NtripState::Disconnected );
    setNtripLastError( QString() );
  }
}

void QfPositioningSource::setNtripState( NtripState state )
{
  if ( mNtripState == state )
  {
    return;
  }

  mNtripState = state;
  emit ntripStateChanged();
}

void QfPositioningSource::setNtripLastError( const QString &error )
{
  if ( mNtripLastError == error )
  {
    return;
  }

  mNtripLastError = error;
  emit ntripLastErrorChanged();
}

int QfPositioningSource::deviceCapabilities() const
{
  return mReceiver ? mReceiver->capabilities() : QfAbstractGnssReceiver::NoCapabilities;
}

void QfPositioningSource::setCompassSmoothingWindowMs( int window )
{
  window = qMax( 0, window );
  if ( mCompassSmoothingWindowMs == window )
    return;

  mCompassSmoothingWindowMs = window;
  mCompassReadings.clear();
  emit compassSmoothingWindowMsChanged();
}

// WorkField: elevation mask via UBX-CFG-VALSET (CFG-NAVSPG-INFIL_MINELEV, RAM layer)
void QfPositioningSource::setGnssMinimumElevation( int degrees )
{
  if ( !mReceiver )
  {
    return;
  }

  const qint8 value = static_cast<qint8>( qBound( 0, degrees, 90 ) );

  QByteArray payload;
  payload.append( char( 0x00 ) ); // version
  payload.append( char( 0x01 ) ); // layers: RAM only
  payload.append( char( 0x00 ) ); // reserved
  payload.append( char( 0x00 ) ); // reserved
  payload.append( char( 0xA4 ) ); // key CFG-NAVSPG-INFIL_MINELEV = 0x201100A4 (LE)
  payload.append( char( 0x00 ) );
  payload.append( char( 0x11 ) );
  payload.append( char( 0x20 ) );
  payload.append( char( value ) );

  QByteArray frame;
  frame.append( char( 0xB5 ) );
  frame.append( char( 0x62 ) );
  frame.append( char( 0x06 ) ); // class CFG
  frame.append( char( 0x8A ) ); // id VALSET
  frame.append( char( payload.size() & 0xFF ) );
  frame.append( char( ( payload.size() >> 8 ) & 0xFF ) );
  frame.append( payload );

  quint8 ckA = 0;
  quint8 ckB = 0;
  for ( int i = 2; i < frame.size(); i++ )
  {
    ckA += static_cast<quint8>( frame.at( i ) );
    ckB += ckA;
  }
  frame.append( char( ckA ) );
  frame.append( char( ckB ) );

  mReceiver->onCorrectionDataReceived( frame );
}
