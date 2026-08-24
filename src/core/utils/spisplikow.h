/***************************************************************************
  spisplikow.h - SpisPlikow

 ---------------------
 WorkField 23.08.2026: spis plikow jako lokalna historia drzewa.

 POMYSL PIOTRA: "cos w rodzaju lokalnego gita dla plikow — przynajmniej dla
 ich listy". Trafiony, bo rozdziela dwie rzeczy, ktore latwo pomylic:

   KOPIA zapobiega stracie.   SPIS ja WYKRYWA I NAZYWA.

 Tylko druga z nich jest tania. Piecdziesiat tysiecy plikow to kilka
 megabajtow tekstu — spis z kazdego dnia przez rok nie zajmie tyle, co jedno
 zdjecie z terenu.

 Spis odpowiada na trzy awarie, ktore juz sa w naszych notatkach:

   - 72 zgubione zdjecia (21.08) — wczorajszy spis je wymienia, dzisiejszy
     nie. Dostajesz LISTE NAZW, a nie liczbe.
   - dwa pliki po 2 609 152 B i roznej tresci, 278 kontra 280 platow (21.08)
     — ten sam rozmiar, inna suma md5. Spis to widzi, `ls` nie widzial.
   - siedem plikow GPKG w katalogu jednego zlecenia (20.08) — spis mowi,
     ktorego dnia kazdy sie pojawil.

 CZEGO SPIS NIE ZROBI: nie odda danych. Powie dokladnie, co przepadlo
 i kiedy. Dlatego spis i kopia to jedna calosc — spis jedzie razem z kopia
 na USB, zeby kopie dalo sie sprawdzic pozniej BEZ ORYGINALU.

 DLACZEGO NIE PRAWDZIWY GIT: na Androidzie go nie ma, a `/DATA/WorkField` to
 dane, nie kod (MasterScript: dane terenowe nigdy do repo). Zamiast zaleznosci
 od gita — FORMAT, NA KTORYM GIT DZIALA: posortowany tekst, jedna linia na
 plik, naglowek w liniach z `#`. Kto chce historii na komputerze, robi
 `git init` w katalogu spisow i ma `git diff` za darmo.
 ***************************************************************************/

#ifndef SPISPLIKOW_H
#define SPISPLIKOW_H

#include <QObject>
#include <QVariantMap>

/**
 * \ingroup core
 */
class SpisPlikow : public QObject
{
    Q_OBJECT

  public:
    explicit SpisPlikow( QObject *parent = nullptr );

    /**
     * Robi spis drzewa \a korzen i zapisuje go w \a katalogSpisow jako
     * `spis_RRRR-MM-DD_GGmm.txt`.
     *
     * \a zakres:
     *   "dane"     — tylko nieodtwarzalne: bazy, projekty, przepisy, DCIM.
     *                Podklady, NMT i mozaiki pomijane, bo sa do pobrania
     *                ponownie (kryterium odtwarzalnosci, DANE_workflow.md).
     *   "wszystko" — wszystko poza plikami roboczymi SQLite i `.git`.
     *
     * \a sumyWszedzie: gdy false (domyslnie), md5 liczone tylko dla klasy
     * "dane". Zdjecia sa append-only — raz zapisany JPEG sie nie zmienia,
     * wiec do wykrycia jego ZNIKNIECIA wystarczy nazwa, a przeliczanie
     * czterech gigabajtow przy kazdym spisie kosztowaloby minuty bez zysku.
     *
     * Zwraca mape: ok, sciezka, plikow, bajtow, sum, pominietych, blad.
     */
    Q_INVOKABLE QVariantMap zrob( const QString &korzen,
                                  const QString &katalogSpisow,
                                  const QString &zakres = QStringLiteral( "dane" ),
                                  bool sumyWszedzie = false ) const;

    /**
     * Spisy lezace w katalogu, od najnowszego. Kazdy wpis: sciezka, nazwa,
     * data, zakres, korzen, plikow, bajtow — czytane z naglowka, bez
     * wczytywania calej listy.
     */
    Q_INVOKABLE QVariantList spisy( const QString &katalogSpisow ) const;

    /**
     * Roznica miedzy dwoma spisami. \a spisA jest starszy.
     *
     * Zwraca mape z czterema listami i ich licznikami:
     *   nowe        — pliki, ktorych wczesniej nie bylo
     *   zniknely    — byly, nie ma
     *   zmienione   — inny rozmiar albo inna suma
     *   PODEJRZANE  — TEN SAM ROZMIAR, INNA SUMA
     *
     * Ostatnia kategoria istnieje z powodu 21.08: dwa pliki o identycznym
     * rozmiarze 2 609 152 B i roznej liczbie obiektow. Rozmiar nie
     * rozstrzyga i nigdy nie rozstrzygal — tylko wygladal, jakby rozstrzygal.
     */
    Q_INVOKABLE QVariantMap porownaj( const QString &spisA, const QString &spisB ) const;

    /**
     * Sprawdza drzewo \a korzen wobec zapisanego \a spis.
     *
     * TO JEST TO, CO POZWALA SPRAWDZIC KOPIE NA USB BEZ ORYGINALU: spis
     * jedzie razem z kopia, wiec po pol roku da sie zapytac dysku, czy nadal
     * ma to, co dostał, i czy tresc sie nie rozjechala.
     *
     * \a zSumami: gdy true, przelicza md5 tam, gdzie spis je ma. Wolne,
     * ale to jedyne, co wykrywa ciche przeklamanie bitow.
     *
     * Zwraca mape: ok, sprawdzonych, brakuje[], inny_rozmiar[], inna_suma[],
     * nadmiarowe[].
     */
    Q_INVOKABLE QVariantMap sprawdz( const QString &spis,
                                     const QString &korzen,
                                     bool zSumami = false ) const;

    //! Czy plik nalezy do klasy "dane" — jedno miejsce, w ktorym ta regula zyje.
    static bool nieodtwarzalny( const QString &sciezkaWzgledna );

  private:
    struct Wpis
    {
        QString sciezka;
        qint64 bajty = 0;
        QString czas;   //!< ISO, sekundy — mtime
        QString suma;   //!< md5 albo pusty
    };

    static QString sumaPliku( const QString &sciezka );
    static bool pomijac( const QString &nazwa );
    static QList<Wpis> czytaj( const QString &spis, QVariantMap *naglowek );
};

#endif // SPISPLIKOW_H
