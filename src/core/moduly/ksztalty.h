/***************************************************************************
  ksztalty.h - Ksztalty (WorkFieldGIS)

  Prostokat, okrag i krzywa B-sklejana z kilku wskazanych punktow.

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef KSZTALTY_H
#define KSZTALTY_H

#include <QObject>
#include <QVariantList>
#include <QVector>

#include <qgsgeometry.h>

/**
 * \brief Ksztalty rysowane trzema tapnieciami zamiast trzydziestoma.
 *
 * ==========================================================================
 * PO CO
 * ==========================================================================
 * Korona drzewa jest okregiem. Dzis obchodzi sie ja pieszo albo klika po
 * kilkunastu wierzcholkach — przy inwentaryzacji to najdrozsza czynnosc
 * dnia. Srodek z GNSS, promien z dalmierza i korona gotowa.
 *
 * Plat, poletko, zakres prac sa prostokatami. Sciezka, ciek, granica
 * poprowadzona „na oko" jest krzywa gladka, a nie lamana z dwudziestu
 * odcinkow.
 *
 * ==========================================================================
 * DLACZEGO WLASNE, A NIE Z QGIS-a
 * ==========================================================================
 * Narzedzia rysowania ksztaltow w QGIS-ie (`QgsMapToolShape*`) siedza
 * w bibliotece `qgis_gui`, ktora jest QWidgetowa i ktorej WorkFieldGIS
 * NIE LINKUJE — sprawdzone 23.09.2026: `grep -rn "qgis_gui\|QgsMapTool"
 * src/` nie znajduje niczego. Narzedzia sa wiec nie do wziecia.
 *
 * Ale SAMA GEOMETRIA jest w `qgis_core` i z niej korzystamy: `QgsCircle`
 * i `QgsQuadrilateral` licza to, co trzeba, i sa sprawdzone od lat.
 * Piszemy tylko to, czego w core nie ma.
 *
 * ==========================================================================
 * KRZYWA: NURBS, ALE ZAPISANA JAKO LAMANA
 * ==========================================================================
 * „Digitize with NURBS Curve" w QGIS-ie to WTYCZKA PYTHONA, a QField
 * Pythona nie ma. Krzywa jest tu policzona od zera algorytmem de Boora,
 * z wagami — czyli naprawde wymierna B-sklejana, nie jej przyblizenie.
 *
 * ZAPISUJE SIE JAKO LAMANA i tak ma byc. GeoPackage potrafi trzymac
 * `CIRCULARSTRING`, ale NIE potrafi trzymac B-sklejanej — zadna baza
 * tego nie potrafi. Kazde narzedzie na swiecie zapisuje takie krzywe
 * PO ZAGESZCZENIU. Punkty kontrolne zostaja u czlowieka na ekranie,
 * w pliku lezy gladka lamana.
 *
 * \ingroup core
 */
class Ksztalty : public QObject
{
    Q_OBJECT

    /**
     * Dlugosc boku w METRACH, na jaka dzielimy luki. 0 = zostaw stare 72.
     *
     * Do 24.09.2026 okrag mial na sztywno 72 odcinki — niezaleznie od
     * tego, czy byl korona drzewa o promieniu 3 m, czy obrysem stawu
     * o promieniu 200 m. Przy koronie to marnotrawstwo, przy stawie
     * gruby blad: bok wychodzil siedemnastometrowy.
     *
     * Bok jest tym, co da sie WYOBRAZIC w terenie („co cwierc metra"),
     * inaczej niz skok katowy. Odchylka od prawdziwego luku wychodzi
     * z niego sama i wynosi mniej wiecej bok^2 / (8 * promien) — przy
     * 25 cm i koronie 5 m to niespelna dwa milimetry.
     */
    Q_PROPERTY( double bokMetry READ bokMetry WRITE setBokMetry NOTIFY bokMetryChanged )

    /**
     * Gorny ogranicznik liczby wierzcholkow jednego ksztaltu.
     *
     * Bez niego staw o promieniu 200 m przy boku 25 cm dostalby ponad
     * piec tysiecy wierzcholkow — plik puchnie, mapa zwalnia, a na
     * ekranie telefonu i tak tego nie widac.
     */
    Q_PROPERTY( int maksWierzcholkow READ maksWierzcholkow WRITE setMaksWierzcholkow NOTIFY maksWierzcholkowChanged )

    /**
     * Czy krzywa ma PRZECHODZIC przez wskazane punkty.
     *
     * Falsz (domyslnie) — B-sklejana: gladsza, ale tapniete punkty tylko
     * ja przyciagaja, a obrys biegnie obok nich. Prawda — splajn
     * Catmulla-Roma dosrodkowy: przechodzi przez KAZDY wskazany punkt,
     * za cene lekkiego falowania miedzy punktami postawionymi blisko
     * siebie.
     *
     * Przelacznik, a nie wybor raz na zawsze, bo to zalezy od roboty:
     * obrys laki „na oko" chce gladkosci, a inwentaryzacja, w ktorej
     * kazdy tapniety punkt jest POMIAREM, chce wiernosci.
     */
    Q_PROPERTY( bool krzywaPrzezPunkty READ krzywaPrzezPunkty WRITE setKrzywaPrzezPunkty NOTIFY krzywaPrzezPunktyChanged )

    /**
     * Dlugosc jednego zabka chmurki w METRACH. 0 = AUTOMAT.
     *
     * Automat bierze jedna dwudziesta obwodu, bo chmurka o stalym luku
     * wyglada dobrze tylko w jednej skali: przy luku 1 m drzewo
     * o srednicy 5 m dostaje szesnascie zabkow, a pole o boku 500 m —
     * dwa tysiace, czyli gruba kreske.
     */
    Q_PROPERTY( double chmurkaLuk READ chmurkaLuk WRITE setChmurkaLuk NOTIFY chmurkaLukChanged )

  public:
    explicit Ksztalty( QObject *parent = nullptr );

    //! \copydoc bokMetry
    double bokMetry() const { return mBokMetry; }
    //! \copydoc bokMetry
    void setBokMetry( double bok );
    //! \copydoc maksWierzcholkow
    int maksWierzcholkow() const { return mMaksWierzcholkow; }
    //! \copydoc maksWierzcholkow
    void setMaksWierzcholkow( int maks );
    //! \copydoc krzywaPrzezPunkty
    bool krzywaPrzezPunkty() const { return mKrzywaPrzezPunkty; }
    //! \copydoc krzywaPrzezPunkty
    void setKrzywaPrzezPunkty( bool przez );
    //! \copydoc chmurkaLuk
    double chmurkaLuk() const { return mChmurkaLuk; }
    //! \copydoc chmurkaLuk
    void setChmurkaLuk( double luk );

    /**
     * Ile odcinkow na pelny okrag o danym promieniu, zeby bok wyszedl
     * `bokMetry`. Zawsze co najmniej 8 i nie wiecej niz `maksWierzcholkow`.
     *
     * Wystawione, zeby karta ustawien mogla POKAZAC skutek liczby, ktora
     * czlowiek wlasnie wpisal, zanim zacznie rysowac.
     */
    Q_INVOKABLE int segmentowDlaOkregu( double promien ) const;

    /**
     * Ile punktow trzeba wskazac, zeby ksztalt dalo sie policzyc.
     *
     * Pasek pyta o to, zeby wiedziec, kiedy zapalic „Gotowe" — a nie
     * zeby probowac i dostawac pusta geometrie.
     */
    Q_INVOKABLE int potrzebaPunktow( const QString &ksztalt ) const;

    //! Zdanie dla czlowieka: co ma wskazac. Puste dla nieznanego ksztaltu.
    Q_INVOKABLE QString podpowiedz( const QString &ksztalt, int juzWskazanych ) const;

    /**
     * Prostokat z DWOCH albo TRZECH punktow.
     *
     * Dwa punkty = przeciwlegle narozniki, boki rownolegle do osi.
     * Trzy punkty = bok `a`–`b`, a trzeci wyznacza szerokosc. Tak rysuje
     * QGIS i tak trzeba w terenie: plat rzadko stoi rownolegle do polnocy.
     */
    Q_INVOKABLE QgsGeometry prostokat( const QVariantList &punkty ) const;

    /**
     * Okrag ze srodka i punktu na obwodzie (dwa punkty).
     *
     * \a segmentow to zageszczenie. 0 albo mniej znaczy AUTOMAT: tyle
     * odcinkow, zeby bok wyszedl `bokMetry` — patrz `segmentowDlaOkregu()`.
     */
    Q_INVOKABLE QgsGeometry okrag( const QVariantList &punkty, int segmentow = 0 ) const;

    /**
     * Okrag ze srodka i WPISANEGO promienia — dla dalmierza i tasmy.
     *
     * Osobno od `okrag()`, bo w terenie promien czesciej sie ZNA, niz
     * dochodzi sie do jego konca.
     */
    Q_INVOKABLE QgsGeometry okragOPromieniu( const QVariant &srodek, double promien,
                                             int segmentow = 0 ) const;

    /**
     * Krzywa wymierna B-sklejana (NURBS) przez punkty kontrolne.
     *
     * \a stopien   3 = sześcienna; przy zbyt malej liczbie punktow schodzi
     *              sama, az do odcinka prostego przy dwoch.
     * \a gestosc   ile punktow na przesle. 12 to gladko i tanio.
     * \a wagi      puste = wszystkie rowne 1 (zwykla B-sklejana). Waga
     *              wieksza od 1 przyciaga krzywa do punktu.
     *
     * \a zamknieta krzywa OKRESOWA, domykajaca sie sama i gladko. Do
     *              obrysow na warstwach poligonowych: dotad pierscien
     *              powstawal przez doklejenie akordu i w punkcie, w ktory
     *              czlowiek tapnal NAJPIERW, siedzial rog — jedyne ostre
     *              miejsce na calym gladkim obrysie.
     *
     * Krzywa OTWARTA zawsze przechodzi przez pierwszy i ostatni punkt
     * kontrolny — wezly sa zaciśnięte. Bez tego poczatek linii nie lezalby
     * tam, gdzie czlowiek tapnal, a to jedyna rzecz, ktorej jest pewien.
     *
     * Krzywa ZAMKNIETA nie przechodzi przez zaden punkt kontrolny — ale
     * przez srodkowe nie przechodzila nigdy, wiec obrys jest po prostu
     * konsekwentny: kazdy wskazany punkt przyciaga tak samo.
     */
    Q_INVOKABLE QgsGeometry krzywa( const QVariantList &punkty, int stopien = 3,
                                    int gestosc = 12,
                                    const QVariantList &wagi = QVariantList(),
                                    bool zamknieta = false ) const;

    /**
     * Wypisuje do logu, CO naprawde jest w geometrii.
     *
     * Nie diagnostyka „na chwile": 23/24.09.2026 kształt byl widoczny na
     * mapie, a do pliku szedl roboczy wielobok, i trzy kolejne poprawki
     * poszly na domysly, bo nikt nie umial powiedziec, w ktorym miejscu
     * dlugiej drogi „gumka → obiekt → formularz → GeoPackage" geometria
     * sie podmienia. Logcat milczal, bo nie bylo czym mowic.
     *
     * Zostaje na stale. Kosztuje jedna linijke w logu na zatwierdzenie.
     */
    Q_INVOKABLE void powiedz( const QString &gdzie, const QgsGeometry &geometria ) const;

    //! To samo o modelu gumki — ile wierzcholkow i gdzie ma konce.
    Q_INVOKABLE void powiedzOGumce( const QString &gdzie, QObject *modelGumki ) const;

    /**
     * Czy geometria jest pusta.
     *
     * `QgsGeometry` jest typem WARTOSCIOWYM, wiec w QML-u nie ma pewnosci,
     * ze `g.isNull` cokolwiek znaczy. Pasek musi umiec odroznic „nie da sie"
     * od „gotowe", wiec pytamy o to tutaj, po stronie C++.
     */
    Q_INVOKABLE bool pusty( const QgsGeometry &geometria ) const;

    /**
     * Ile punktow czlowiek JUZ WSKAZAL w modelu gumki.
     *
     * Pasek pyta o to, zeby napisac „wskazano 1 z 2" i zeby wiedziec,
     * kiedy zapalic przycisk.
     */
    Q_INVOKABLE int wskazanych( QObject *modelGumki, bool zPunktemZywym = false ) const;

    /**
     * Ksztalt prosto z modelu gumki (`QfRubberbandModel`).
     *
     * Model bierzemy jako zwykly `QObject` i pytamy o wlasciwosci po
     * nazwie. Dzieki temu `Ksztalty` NIE musi znac naglowka gumki — a to
     * znaczy, ze caly ten plik daje sie zbudowac i sprawdzic w piaskownicy,
     * gdzie gumki nie ma wcale.
     *
     * Drugi powod jest wazniejszy: `vertices` to `QVector<QgsPoint>`,
     * a `QgsPoint` nie ma metatypu. Nie ma pewnosci, ze QML zamieni to
     * na tablice — i gdyby nie zamienil, pasek dostalby `undefined`
     * zamiast punktow. Tutaj rozpakowujemy to przez `QSequentialIterable`,
     * ktory radzi sobie z kazdym zarejestrowanym pojemnikiem.
     *
     * \a promien > 0 znaczy: okrag ze srodka w PIERWSZYM wskazanym
     * punkcie i o podanym promieniu — dla dalmierza i tasmy.
     *
     * \a zPunktemZywym dolacza punkt chodzacy za celownikiem. Dla PODGLADU
     * jest konieczny: bez niego prostokat po dwoch tapnieciach nie mialby
     * jak pokazac, dokad sie rozciaga, i czlowiek zobaczylby ksztalt
     * dopiero po fakcie. Dla ZAPISU musi byc wylaczony — do pliku ma trafic
     * to, co czlowiek wskazal palcem, a nie to, gdzie akurat stal krzyzyk.
     *
     * \a typDocelowy `Qgis::GeometryType` warstwy, do ktorej ksztalt idzie
     * (2 = wielokat). Podany, sprawia, ze KRZYWA na warstwie poligonowej
     * powstaje od razu jako zamknieta i gladka, zamiast byc domykana
     * akordem juz po fakcie. -1 znaczy „nie wiem", czyli jak dotad.
     */
    Q_INVOKABLE QgsGeometry zModelu( QObject *modelGumki, const QString &ksztalt,
                                     double promien = 0.0,
                                     bool zPunktemZywym = false,
                                     int typDocelowy = -1 ) const;

    /**
     * Ksztalt dopasowany do typu geometrii warstwy.
     *
     * \a typ to `Qgis::GeometryType` liczba: 1 = linia, 2 = wielokat.
     *
     * Okrag narysowany na warstwie LINIOWEJ ma dac okragla linie, a nie
     * odmowe — czlowiek w terenie rysuje obrys korony tak samo, niezaleznie
     * od tego, czy warstwa trzyma go jako plat czy jako obwodnice. W druga
     * strone: krzywa na warstwie POLIGONOWEJ domyka sie w pierscien, bo po
     * to sie ja tam rysuje (laka o gladkim brzegu).
     *
     * Pusta geometria, gdy przejscie nie ma sensu (punkt) albo gdy linia
     * ma mniej niz trzy wierzcholki i nie ma z czego zrobic pierscienia.
     */
    Q_INVOKABLE QgsGeometry naTyp( const QgsGeometry &ksztalt, int typ ) const;

    /**
     * Ten sam ksztalt po nazwie — jedno wejscie dla paska.
     *
     * `ksztalt`: "prostokat" | "okrag" | "krzywa".
     * \a zamknieta dotyczy wylacznie krzywej — patrz `krzywa()`.
     * Pusta geometria, gdy punktow za malo albo nazwa nieznana.
     */
    Q_INVOKABLE QgsGeometry zbuduj( const QString &ksztalt, const QVariantList &punkty,
                                    bool zamknieta = false ) const;

    /**
     * Krzywa PRZEZ wskazane punkty — splajn Catmulla-Roma dosrodkowy.
     *
     * Odmiana dosrodkowa (alfa = 0.5), bo jako jedyna z tej rodziny nie
     * robi petelek ani dziobow, gdy dwa tapniecia leza blisko siebie,
     * a trzecie daleko — czyli dokladnie tak, jak wyglada kazdy obrys
     * robiony w terenie.
     *
     * \a gestosc  0 albo mniej = AUTOMAT z `bokMetry`, liczony osobno
     *             dla kazdego odcinka.
     * \a zamknieta domyka obrys gladko, bez wyroznionego punktu.
     */
    Q_INVOKABLE QgsGeometry krzywaPrzez( const QVariantList &punkty, int gestosc = 0,
                                         bool zamknieta = false ) const;

    /**
     * Chmurka rewizyjna — obrys z lancucha polokregow, jak REVCLOUD.
     *
     * Rysuje sie ja tam, gdzie cos wymaga sprawdzenia: ksztalt ma MOWIC
     * „przyjrzyj sie temu miejscu", a nie udawac pomiar. Dlatego sciezka
     * bazowa jest lamana przez wskazane punkty, bez wygladzania — nikt
     * nie wezmie tego za granice dzialki.
     *
     * \a zamknieta pierscien (warstwa poligonowa) zamiast wstegi.
     */
    Q_INVOKABLE QgsGeometry chmurka( const QVariantList &punkty,
                                     bool zamknieta = false ) const;

    /**
     * Zamienia zawartosc gumki na KSZTALT zbudowany z jej wlasnych punktow.
     *
     * Jedno wejscie dla edytorow geometrii (ciecie, zmiana obrysu, dziura).
     * Wszystkie czytaja z gumki i wolaja `...FromRubberband`, wiec wystarczy,
     * zeby przed odczytem siedzial tam ksztalt zamiast lamanej.
     *
     * Po stronie QML-a zostaje wtedy JEDNA linijka na edytor. Ma to znaczenie,
     * bo pliki edytorow leza w osobnych komponentach i nie widza ani paska
     * ksztaltow, ani jego silnika — a `settings` i typ `Ksztalty` widza.
     *
     * Typ geometrii i uklad bierzemy Z SAMEJ GUMKI: ciecie chce linii,
     * zmiana obrysu i dziura — wielokata, i kazdy z nich ustawia to sobie sam.
     *
     * BEZ punktu zywego: to jest zatwierdzenie, a nie podglad.
     *
     * Zwraca falsz, gdy ksztaltu nie da sie zbudowac albo gumka go nie
     * przyjela — wtedy zostaje w niej to, co bylo, i nic sie nie psuje.
     */
    Q_INVOKABLE bool zamien( QObject *modelGumki, const QString &ksztalt ) const;

    // ══ PRAWDZIWE LUKI (25.09.2026) ═════════════════════════════════
    //
    // Do dzis kazdy ksztalt konczyl w pliku jako LAMANA — i to nie
    // dlatego, ze GPKG nie umie lukow (umie: `CURVEPOLYGON
    // (CIRCULARSTRING …)` przezywa zapis i odczyt, pole wychodzi
    // dokladnie pi*r^2). Winowajca byl u nas:
    // `QfGeometry::asQgsGeometry()` sklada geometrie ZAWSZE od nowa,
    // z punktow gumki, przez `QgsLineString`. Cokolwiek policzyl ten
    // silnik, tamta funkcja zamieniala to z powrotem na odcinki.
    //
    // Dlatego okregi „wygladaly na CIRCULAR*" — mialy tylko gesto
    // rozstawione wierzcholki.
    //
    // KTORE KSZTALTY. Tylko te, ktore sa lukami DOKLADNIE:
    //
    //   * okrag — `CIRCULARSTRING` przez cztery cwiartki: piec
    //     wierzcholkow zamiast dziewiecdziesieciu i pole bez bledu
    //     przyblizenia;
    //   * chmurka — jej zabki JUZ SA polokregami, wiec lancuch lukow
    //     to jej wlasny, naturalny zapis, a nie przyblizenie.
    //
    // Krzywa i prostokat swiadomie NIE. Prostokat lukow nie ma.
    // Krzywa Catmulla-Roma nie jest lukowa i dalo by sie ja oddac
    // tylko BILUKAMI — przy tej samej dokladnosci oszczedzaja 1,6x,
    // wiec to osobna robota o wlasnym bilansie, nie doklejka do tej.
    // (Lukiem przez kolejne TROJKI punktow sie nie da: na stykach
    // wychodzi zalamanie kilkunastu stopni, czyli dokladnie te ostre
    // wierzcholki, ktore usunelismy 24.09.)

    /**
     * Czy ten ksztalt ma postac lukowa — czyli czy `zbudujLuk` cos odda.
     *
     * Pytanie zadaje QML, zanim zacznie cokolwiek liczyc: dla prostokata
     * i krzywej nie ma po co chodzic druga droga.
     */
    Q_INVOKABLE bool umieLuki( const QString &ksztalt ) const;

    /**
     * Czy warstwa PRZYJMIE luki, czyli czy jej typ jest krzywoliniowy.
     *
     * To nie jest kosmetyka. Na zwyklej warstwie `POLYGON` luk ginie
     * BEZ SLOWA: sprawdzone — okrag o piaciu wierzcholkach zapisuje sie
     * jako dziewiecdziesiat jeden i nikt tego nie zglasza. Dlatego
     * pytamy PRZED zapisem i mowimy o tym raz na warstwe.
     *
     * \a warstwa `QgsVectorLayer` (przychodzi z QML-a jako QObject).
     */
    Q_INVOKABLE bool warstwaPrzyjmieLuki( QObject *warstwa ) const;

    /**
     * To samo co `zbuduj`, ale z prawdziwymi lukami.
     *
     * Zwraca PUSTO, gdy ksztalt postaci lukowej nie ma — i to jest
     * poprawna odpowiedz, nie blad. Wolajacy ma wtedy zostac przy
     * `zbuduj`, a nie probowac czegos naprawiac.
     */
    Q_INVOKABLE QgsGeometry zbudujLuk( const QString &ksztalt, const QVariantList &punkty,
                                       bool zamknieta = false ) const;

    /**
     * Jak `zModelu`, ale lukowa — droga zapisu, nie podgladu.
     *
     * Podglad zostaje na gumce i na lamanej; luk jest potrzebny dopiero
     * w pliku.
     *
     * KOLEJNOSC I ZNACZENIE PARAMETROW SA TE SAME, CO W `zModelu`, i to
     * nie jest wygoda tylko bezpieczenstwo: obie drogi musza policzyc
     * ksztalt z DOKLADNIE tych samych punktow. Pierwsza wersja brala tu
     * punkty bez zywego („to przeciez zatwierdzenie") — a `wlozKsztalt`
     * liczy lamana Z zywym, bo tak liczy podglad. Wyszlyby dwa rozne
     * okregi: jeden na ekranie, drugi w pliku.
     */
    Q_INVOKABLE QgsGeometry zModeluLuk( QObject *modelGumki, const QString &ksztalt,
                                        double promien = 0.0, bool zPunktemZywym = false,
                                        int typDocelowy = -1 ) const;

    /**
     * `naTyp` dla geometrii, ktore moga miec luki.
     *
     * Osobna, bo tamta rzutuje na `QgsLineString` i `QgsPolygon`, a luk
     * jest `QgsCircularString`/`QgsCompoundCurve` w `QgsCurvePolygon` —
     * tamto rzutowanie oddaje przy nich `nullptr` i ksztalt znika.
     */
    Q_INVOKABLE QgsGeometry naTypLuk( const QgsGeometry &ksztalt, int typ ) const;

  signals:
    //! \copydoc bokMetry
    void bokMetryChanged();
    //! \copydoc maksWierzcholkow
    void maksWierzcholkowChanged();
    //! \copydoc krzywaPrzezPunkty
    void krzywaPrzezPunktyChanged();
    //! \copydoc chmurkaLuk
    void chmurkaLukChanged();

  private:
    //! \copydoc bokMetry
    double mBokMetry = 0.25;
    //! \copydoc maksWierzcholkow
    int mMaksWierzcholkow = 512;
    //! \copydoc krzywaPrzezPunkty
    bool mKrzywaPrzezPunkty = false;
    //! \copydoc chmurkaLuk
    double mChmurkaLuk = 0.0;
};

#endif // KSZTALTY_H
