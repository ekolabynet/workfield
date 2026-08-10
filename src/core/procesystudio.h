/***************************************************************************
  procesystudio.h - silnik czasowników WFG Studio w desktopowym WorkField

  Jedyny nowy prymityw architektury "desktop = Studio": most między QML
  a światem zewnętrznym (python3/PyQGIS, adb, zip). Na Androidzie klasa
  istnieje, ale grzecznie odmawia — sekcja Studio i tak jest tam ukryta.

  WorkField (fork QField) - GPL-2.0-or-later
 ***************************************************************************/
#ifndef PROCESYSTUDIO_H
#define PROCESYSTUDIO_H

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>

class ProcesyStudio : public QObject
{
    Q_OBJECT
    Q_PROPERTY( bool dziala READ dziala NOTIFY dzialaChanged )

  public:
    explicit ProcesyStudio( QObject *parent = nullptr );
    ~ProcesyStudio() override;

    bool dziala() const;

    //! Uruchamia program z argumentami; wyjście płynie sygnałem linia().
    Q_INVOKABLE bool uruchom( const QString &program, const QStringList &argumenty,
                              const QString &katalog = QString() );

    //! Uruchamia polecenie powłoki (/bin/sh -c) — dla potoków typu zip+adb.
    Q_INVOKABLE bool uruchomPowloke( const QString &polecenie,
                                     const QString &katalog = QString() );

    //! Uruchamia skrypt wymagający PyQGIS (np. zbuduj_projekt.py):
    //! rozruch QgsApplication w pythonie systemowym, cwd = katalog skryptu.
    Q_INVOKABLE bool uruchomPyQgis( const QString &sciezkaSkryptu );

    //! Czyta plik tekstowy (UTF-8); pusty string, gdy brak/nieczytelny.
    //! Uzywane m.in. przez widok Stanu zlecen (dziennik/stan.json).
    Q_INVOKABLE QString czytajTekst( const QString &sciezka );

    //! Grzeczne przerwanie bieżącego procesu (terminate, po 2 s kill).
    Q_INVOKABLE void przerwij();

    //! Skan drzewa w poszukiwaniu projektów (katalogi z .qgs/.qgz/.gpkg).
    //! Zwraca listę map: nazwa, sciezka, qgs, typ (projekt|szablon),
    //! zmodyfikowano (ISO), gdzie (ścieżka względna rodzica).
    Q_INVOKABLE QVariantList znajdzProjekty( const QString &korzen,
                                             int glebokosc = 4 ) const;

    //! Kopia szablonu do katalogDocelowy/nazwa (odmawia nadpisania).
    //! Pusty katalogDocelowy => <korzen>/wydania (przejściowo wymiana) jeśli istnieje, inaczej korzen.
    Q_INVOKABLE QVariantMap nowyZSzablonu( const QString &szablon,
                                           const QString &katalogDocelowy,
                                           const QString &nazwa,
                                           const QString &korzen = QString() ) const;

    //! "Zamien na szablon": kopiuje projekt do <korzen>/szablony/<nazwa>
    //! z pominieciem czesci terenowej (DCIM, foto_tagi.gpkg, zdjecia,
    //! metryki, smieci edytora) i czysci tabele FITO_* we wszystkich GPKG
    //! kopii. Oryginal nietkniety. Zwraca { ok, sciezka|blad, wyczyszczono }.
    Q_INVOKABLE QVariantMap zamienNaSzablon( const QString &sciezkaProjektu,
                                             const QString &korzen,
                                             const QString &nazwa ) const;

  signals:
    void linia( const QString &tekst );
    void zakonczono( int kod );
    void dzialaChanged();

  private:
    bool startuj( const QString &program, const QStringList &argumenty,
                  const QString &katalog );
    void przeszukaj( const QString &katalog, const QString &korzen,
                     int pozostalaGlebokosc, QVariantList &wynik ) const;
    bool kopiujKatalog( const QString &zrodlo, const QString &cel ) const;

    QProcess mProces;
    QString mPlikRozruchu;   // tymczasowy rozruch PyQGIS do posprzątania
};

#endif // PROCESYSTUDIO_H
