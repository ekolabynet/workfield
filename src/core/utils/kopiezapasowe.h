/***************************************************************************
  kopiezapasowe.h - KopieZapasowe

 ---------------------
 WorkField 24.08.2026: kopia zapasowa na nosnik zewnetrzny.

 SIOSTRA SPISU. Podzial, na ktorym stoi calosc (claude/SPIS_i_kopie.md):

     KOPIA zapobiega stracie.   SPIS ja wykrywa i nazywa.

 Dlatego kazda migawka wiezie ze soba SPIS swojej zawartosci. Po pol roku
 da sie zapytac dysku, czy nadal ma to, co dostal — bez oryginalu.

 -------------------------------------------------------------------------
 TOZSAMOSC NOSNIKA: STEMPEL, NIE SCIEZKA

 `/media/piotr/WF_BACKUP` to MIEJSCE, w ktorym cos akurat stoi. Jutro moze
 tam stac inny pendrive, a ten sam pendrive moze wyladowac pod `WF_BACKUP1`.
 Kopia, ktora pamieta sciezke, za pol roku nie odpowie na pytanie "na ktorym
 nosniku to lezy".

 Dlatego STEMPLUJEMY NOSNIK: `WF_NOSNIK.json` w jego korzeniu, z wlasnym
 identyfikatorem, nazwa nadana przez czlowieka i data. Ta sama zasada, co
 `WF_WYPOSAZENIE` w GeoPackage — tozsamosc jedzie razem z rzecza. Dziala na
 kazdym systemie plikow i przezywa zmiane etykiety, przenumerowanie urzadzen
 i przelozenie do innego portu. UUID i etykieta systemowa sa zapisywane obok,
 ale jako podpowiedz; rozstrzyga plik.

 EWIDENCJA WYNIKA Z UZYCIA, nie z konfiguracji (decyzja Piotra, 24.08):
 nie ma osobnego kroku "zarejestruj nosnik". Przy pierwszej kopii na nieznany
 dysk okno pyta o nazwe — i to JEST rejestracja. Nie ma listy, ktora moglaby
 sie rozjechac z rzeczywistoscia.

 -------------------------------------------------------------------------
 CZTERY RZECZY, KTORE ROBI APLIKACJA, A CZEGO NIE ZROBI RSYNC

 1. CHECKPOINT WAL przed kopiowaniem kazdej bazy. Tylko aplikacja wie, czy
    baza nie jest w srodku transakcji, i tylko ona moze wymusic zrzut
    dziennika. Kopia zrobiona w tle na otwartej bazie daje plik, ktory
    OTWIERA SIE I KLAMIE (DANE_workflow.md, warunek twardy).
 2. Baza, ktorej nie da sie zacheckpointowac — bo trzyma ja QGIS na
    komputerze — jest NAZWANA I POMINIETA, a nie kopiowana na slepo.
 3. `quick_check` na kopii kazdej bazy PO skopiowaniu.
 4. Spis calej migawki, zapisany w niej.

 -------------------------------------------------------------------------
 TWARDE DOWIAZANIA I DLACZEGO SIE JE SPRAWDZA, A NIE ZAKLADA

 Migawka laczy sie z poprzednia twardymi dowiazaniami: kazda wyglada na
 pelna, kosztuje przyrost. Na exFAT i FAT32 dowiazania nie dzialaja — a to
 sa systemy plikow, na ktorych pendrive'y wychodza z fabryki.

 Nie pytamy o system plikow, tylko PROBUJEMY zrobic dowiazanie i patrzymy,
 czy wyszlo. Jesli nie — kopia i tak sie wykona, ale wynik POWIE WPROST,
 ze kazda migawka jest pelna. Przy drzewie 88 GB to roznica miedzy "dysk
 starczy na rok" a "dysk starczy na tydzien", i czlowiek ma prawo to
 wiedziec, zanim dysk sie zapelni.
 ***************************************************************************/

#ifndef KOPIEZAPASOWE_H
#define KOPIEZAPASOWE_H

#include <QObject>
#include <QVariantMap>

class QThread;
class RobotnikKopii;

/**
 * \ingroup core
 */
class KopieZapasowe : public QObject
{
    Q_OBJECT

    Q_PROPERTY( bool pracuje READ pracuje NOTIFY pracujeChanged )
    Q_PROPERTY( int postep READ postep NOTIFY postepChanged )
    Q_PROPERTY( QString etap READ etap NOTIFY etapChanged )

  public:
    explicit KopieZapasowe( QObject *parent = nullptr );
    ~KopieZapasowe() override;

    bool pracuje() const { return mPracuje; }
    int postep() const { return mPostep; }
    QString etap() const { return mEtap; }

    /**
     * Nosniki, ktore MOZNA teraz wybrac: zamontowane, zapisywalne, poza
     * dyskiem systemowym. Kazdy wpis: sciezka, etykieta, pojemnosc, wolne,
     * znany (bool), nazwa, id, odKiedy, migawek.
     *
     * Lista jest budowana z tego, co jest PODPIETE — nie z zapamietanej
     * konfiguracji. Nie da sie przez to zobaczyc nosnika, ktorego nie ma.
     */
    Q_INVOKABLE QVariantList nosniki() const;

    //! Stempel z korzenia nosnika albo pusta mapa. {id, nazwa, odKiedy}
    Q_INVOKABLE QVariantMap stempel( const QString &sciezkaNosnika ) const;

    /**
     * Nadaje nosnikowi nazwe i zapisuje na nim `WF_NOSNIK.json`.
     * Ponowne wywolanie na juz ostemplowanym nosniku ZMIENIA nazwe,
     * zachowujac identyfikator — zeby stare migawki nadal do niego pasowaly.
     */
    Q_INVOKABLE QVariantMap ostempluj( const QString &sciezkaNosnika, const QString &nazwa ) const;

    //! Migawki lezace na nosniku, od najnowszej. Czytane z `KOPIA.json`.
    Q_INVOKABLE QVariantList migawki( const QString &sciezkaNosnika ) const;

    /**
     * Rozpoznanie przed kopiowaniem — SZYBKIE, bez sum kontrolnych.
     * Zwraca: plikow, bajtow, otwarteBazy (lista sciezek z `-wal`/`-shm`
     * obok), wolneNaNosniku, zmiesciSie.
     */
    Q_INVOKABLE QVariantMap zbadaj( const QString &korzen,
                                    const QString &zakres,
                                    const QString &sciezkaNosnika ) const;

    /**
     * Przepisuje czasy plikow w GOTOWEJ migawce z ich oryginalow, zeby dalo
     * sie do niej dowiazywac. Ratunek dla migawek zrobionych przed poprawka
     * z 24.08.2026 — bez tego nastepna kopia przepisuje cale drzewo od nowa.
     *
     * Nie rusza baz, projektow ani JSON-ow: te moga zmienic sie w miejscu bez
     * zmiany rozmiaru, a fałszywy czas zamrozilby w kopii nieaktualna tresc
     * na zawsze. Zwraca: sprawdzonych, poprawionych, juzDobrych, bezOryginalu,
     * innyRozmiar, pominietychOstroznie, opis.
     */
    Q_INVOKABLE QVariantMap naprawCzasy( const QString &sciezkaMigawki,
                                         const QString &korzen ) const;

    /**
     * Wykonuje kopie W OSOBNYM WATKU. Wynik przychodzi sygnalem `skonczone`.
     * Kopiowanie kilkudziesieciu gigabajtow nie moze zamrozic interfejsu.
     */
    Q_INVOKABLE void wykonaj( const QString &korzen,
                              const QString &zakres,
                              const QString &sciezkaNosnika );

    //! Prosi robotnika o zatrzymanie po biezacym pliku. Migawka zostaje
    //! oznaczona w `KOPIA.json` jako przerwana — niepelna kopia, ktora
    //! udaje pelna, jest gorsza niz jej brak.
    Q_INVOKABLE void przerwij();

  signals:
    void pracujeChanged();
    void postepChanged();
    void etapChanged();

    //! {ok, migawka, plikow, skopiowanych, dowiazanych, bajtow, pominietych,
    //!  bazySprawdzone, bledy[], dowiazaniaDzialaja, przerwane, blad}
    void skonczone( const QVariantMap &wynik );

  private slots:
    void naPostep( int procent, const QString &etap );
    void naKoniec( const QVariantMap &wynik );

  private:
    bool mPracuje = false;
    int mPostep = 0;
    QString mEtap;

    QThread *mWatek = nullptr;
    RobotnikKopii *mRobotnik = nullptr;
};

#endif // KOPIEZAPASOWE_H
