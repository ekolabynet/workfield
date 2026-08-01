/***************************************************************************
  captureattitude.h - CaptureAttitude (WorkField)
  Pitch/roll osi optycznej aparatu z akcelerometru + zapis pozy zdjecia
  do metadanych XMP GPano i EXIF UserComment.
 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef CAPTUREATTITUDE_H
#define CAPTUREATTITUDE_H

#include <QAccelerometer>
#include <QObject>

/**
 * \brief Poza aparatu w chwili zdjecia.
 *
 * Probkuje akcelerometr przez caly czas zycia obiektu (tworzyc razem
 * z aparatem!), wygladza filtrem dolnoprzepustowym i wystawia:
 *  - pitch: kat elewacji osi optycznej tylnego aparatu
 *           0 = poziomo, -90 = pionowo w dol (plat), +90 = w niebo
 *  - roll:  obrot wokol osi optycznej; 0 = pion (portret), +/-90 = poziom
 *
 * snapshot() zamraza wartosci w chwili migawki, writePoseMetadata()
 * zapisuje je do pliku razem z azymutem z kompasu.
 * \ingroup core
 */
class CaptureAttitude : public QObject
{
    Q_OBJECT
    Q_PROPERTY( double pitch READ pitch NOTIFY attitudeChanged )
    Q_PROPERTY( double roll READ roll NOTIFY attitudeChanged )
    Q_PROPERTY( bool hasReading READ hasReading NOTIFY attitudeChanged )

  public:
    explicit CaptureAttitude( QObject *parent = nullptr );

    double pitch() const { return mPitch; }
    double roll() const { return mRoll; }
    bool hasReading() const { return mHasReading; }

    //! Zamraza biezaca poze; wolac w chwili nacisniecia migawki.
    Q_INVOKABLE void snapshot();

    /**
     * Zapisuje zamrozona poze i \a headingDegrees (azymut z kompasu, NaN gdy
     * nieznany) do pliku \a path jako Xmp.GPano.Pose* oraz JSON w
     * Exif.Photo.UserComment. Zwraca false, gdy nie bylo czego zapisac.
     */
    Q_INVOKABLE bool writePoseMetadata( const QString &path, double headingDegrees );

    /**
     * Czy plik ma juz poze zapisana przez aplikacje aparatu (OpenCamera pisze
     * Yaw/Pitch/Roll w chwili migawki). Takiej pozy nie wolno nadpisywac -
     * jest prawdziwa, a nasza, zamrozona przed przejsciem do aparatu, nie jest:
     * czujniki orientacji spia, gdy aplikacja jest w tle.
     */
    Q_INVOKABLE bool hasExternalPose( const QString &path ) const;

    /**
     * Dopisuje wspolrzedne z naszego GNSS, ale TYLKO gdy plik ich nie ma.
     * Aparat systemowy Samsunga nie geotaguje wcale - tak przepadl caly
     * dzien dokumentacji z 30 lipca.
     */
    Q_INVOKABLE bool fillMissingPosition( const QString &path, double latitude, double longitude, double elevation );

  signals:
    void attitudeChanged();

  private slots:
    void processReading();

  private:
    QAccelerometer mAccelerometer;
    double mGx = 0.0;
    double mGy = 0.0;
    double mGz = 0.0;
    bool mHasReading = false;
    double mPitch = 0.0;
    double mRoll = 0.0;
    double mSnapPitch;
    double mSnapRoll;
    bool mHasSnapshot = false;
};

#endif // CAPTUREATTITUDE_H
