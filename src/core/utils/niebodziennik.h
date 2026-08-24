/***************************************************************************
                            niebodziennik.h - NieboDziennik
                              -------------------
  WorkField, 23.08.2026

  Krok 0 z `claude/NIEBO_logowanie_plan.md`: SAM ZAPIS, bez analizy.

  Dwie tabele w `data.gpkg` projektu:

    NIEBO_SESJA  — jeden wiersz na sesje pracy. Bez niej reszta jest
                   nieczytelna: MASKA_ELEWACJI decyduje o tym, czy brak
                   satelity znaczy "nie bylo widac", czy "odbiornik go
                   odfiltrowal". W danych oba wygladaja identycznie.
    NIEBO_EPOKA  — pelna migawka nieba, jeden wiersz na satelite.
                   Zapisujemy TAKZE satelity nieuzyte: to one niosa
                   informacje o przesloniecu. Zapis samych uzytych to
                   zapis wniosku zamiast obserwacji.

  Dwa powody zapisu epoki:
    "obiekt" — obiekt trafil do pliku (WARSTWA i ID_OBIEKTU wypelnione),
    "rytm"   — co N sekund, domyslnie 5 (WARSTWA pusta).

  Dlaczego podpinamy sie pod `committedFeaturesAdded`, a nie pod
  QfFeatureModel::create(): sygnal warstwy niesie IDENTYFIKATOR JUZ ZAPISANY
  W PLIKU, a nie tymczasowy ujemny z bufora edycji. Przy okazji nie dotykamy
  ani jednego pliku upstreamu, wiec kolejne scalenie nie ma czego zgubic.

 ***************************************************************************/

#ifndef NIEBODZIENNIK_H
#define NIEBODZIENNIK_H

#include <QDateTime>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QVariantMap>

class QfPositioning;
class QgsVectorLayer;
struct sqlite3;

/**
 * \ingroup core
 */
class NieboDziennik : public QObject
{
    Q_OBJECT

    //! Sciezka do data.gpkg, do ktorego piszemy; pusta, gdy nie ma dokad
    Q_PROPERTY( QString baza READ baza NOTIFY stanZmieniony )

    //! Dlaczego nie piszemy — pusty string, gdy piszemy. Objaw niemy jest
    //! gorszy od bledu, wiec panel ma co pokazac.
    Q_PROPERTY( QString przeszkoda READ przeszkoda NOTIFY stanZmieniony )

    //! Identyfikator biezacej sesji, pusty przed pierwszym zapisem
    Q_PROPERTY( QString idSesji READ idSesji NOTIFY stanZmieniony )

    //! Ile epok zapisano w tej sesji (nie wierszy — epok)
    Q_PROPERTY( int epoki READ epoki NOTIFY stanZmieniony )

    //! Ile wierszy satelitarnych zapisano w tej sesji
    Q_PROPERTY( int wiersze READ wiersze NOTIFY stanZmieniony )

    //! Czy dziala rejestrator rytmiczny
    Q_PROPERTY( bool rytm READ rytm WRITE ustawRytm NOTIFY stanZmieniony )

    //! Okres rejestratora rytmicznego w sekundach
    Q_PROPERTY( int okres READ okres WRITE ustawOkres NOTIFY stanZmieniony )

  public:
    //! Jedna instancja na proces — QML dostaje ja jako singleton, a sygnaly
    //! warstw dochodza do tej samej.
    static NieboDziennik *instancja();

    explicit NieboDziennik( QObject *parent = nullptr );
    ~NieboDziennik() override;

    QString baza() const { return mBaza; }
    QString przeszkoda() const { return mPrzeszkoda; }
    QString idSesji() const { return mIdSesji; }
    int epoki() const { return mEpoki; }
    int wiersze() const { return mWiersze; }
    bool rytm() const { return mRytm; }
    int okres() const { return mOkres; }

    void ustawRytm( bool wlaczony );
    void ustawOkres( int sekundy );

    /**
     * Podpina zrodlo pozycji (obiekt QfPositioning z QML). Wolane raz,
     * z QgisMobileapp.qml. Bez tego dziennik nie ma czego zapisywac.
     */
    Q_INVOKABLE void podepnij( QObject *zrodloPozycji );

    /**
     * Zapisuje epoke recznie — przycisk "Zapisz niebo teraz" w panelu.
     * Zwraca liczbe zapisanych wierszy (0 = nie bylo czego albo nie ma gdzie).
     */
    Q_INVOKABLE int zapiszTeraz( const QString &powod = QString() );

    /**
     * Zamyka sesje: wpisuje KONIEC_UTC i zamyka polaczenie z baza.
     * Kolejny zapis otworzy nowa sesje.
     */
    Q_INVOKABLE void zamknijSesje();

  signals:
    void stanZmieniony();

  private slots:
    void naZmianeProjektu();
    void naRytm();

  private:
    //! Ustala sciezke data.gpkg z warstw projektu; pusta, gdy nie da rady
    QString ustalBaze() const;

    //! Otwiera baze, tworzy tabele, zaklada sesje. FALSE = nie ma gdzie pisac.
    bool zapewnijSesje();

    //! Wspolny zapis; \a warstwa i \a idObiektu tylko dla powodu "obiekt"
    int zapisz( const QString &powod, const QString &warstwa, qint64 idObiektu );

    void podepnijWarstwy();
    void ustawPrzeszkode( const QString &tekst );

    QPointer<QObject> mZrodlo;
    sqlite3 *mBazaUchwyt = nullptr;
    QString mBaza;
    QString mPrzeszkoda;
    QString mIdSesji;
    int mEpoki = 0;
    int mWiersze = 0;
    int mLicznikPomiaru = 0;
    bool mRytm = true;
    int mOkres = 5;
    QTimer mZegar;
    QSet<QString> mPodpieteWarstwy;
};

#endif // NIEBODZIENNIK_H
