/***************************************************************************
  stozkiwidzenia.h - StozkiWidzenia (WorkField)
  Przypisywanie zdjec do obiektow warstwy na podstawie EXIF: pozycji,
  azymutu i pochylenia aparatu.
 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef STOZKIWIDZENIA_H
#define STOZKIWIDZENIA_H

#include <QObject>
#include <QVariantMap>

class QgsVectorLayer;

/**
 * \brief Ktory obiekt warstwy widac na zdjeciu.
 *
 * ==========================================================================
 * PO CO
 * ==========================================================================
 * 09.09.2026 przy rozbiciu multipoligonu 316 na cztery platy zostaly cztery
 * zdjecia bez rodzica. Odzyskalismy je licząc, W CO APARAT PATRZYL — i wtedy
 * okazalo sie, ze to nie jest ratunek doraźny, tylko brakujacy mechanizm:
 * 37 zdjec w PTR nie ma wiersza w zadnej tabeli `ZAL_*`.
 *
 * ==========================================================================
 * DLACZEGO NIE WYSTARCZY PUNKT
 * ==========================================================================
 * Punkt stania to NIE JEST punkt fotografowany. Przy pochyleniu -41 stopni
 * i aparacie na 1,5 m srodek kadru pada okolo 1,7 m przed nogami. Zdjecie
 * robione z krawedzi platu do jego wnetrza ma GPS POZA platem — dopasowanie
 * po samym punkcie odrzucilo by je jako "nie w tym platcie".
 *
 * Tak bylo z zalacznikiem 34 (09.09): punkt w platcie 467, stozek w 476.
 * Zdjecie nalezalo do 476.
 *
 * ==========================================================================
 * PARAMETRY — SPRAWDZONE, NIE ZALOZONE
 * ==========================================================================
 * Pole 60x45 stopni i zasieg 8 m to nie sa dane z karty katalogowej.
 * Przy pelnym polu aparatu (97 stopni w pionie przy zdjeciu portretowym)
 * i zasiegu 25 m stozki zachodzily na trzy-cztery platy naraz i nie
 * rozstrzygaly niczego. Przy tych wezszych kazdy trafial w jeden plat.
 *
 * Roznica bierze sie stad, ze kadr OBEJMUJE duzo, a SWIADECTWEM jest
 * o niewielu: peryferia szerokokatnego obiektywu sa rozciagniete, a gorna
 * czesc kadru przy pochyleniu -41 stopni celuje ponad horyzont i nie
 * dotyka ziemi wcale.
 *
 * ==========================================================================
 * CO TA KLASA ROBI, A CZEGO NIE
 * ==========================================================================
 * PROPONUJE. Niczego nie zapisuje, nie tworzy wierszy, nie kasuje.
 * Rozstrzygniecie Piotra z 11.09.2026:
 *
 *     "Przeliczanie PROPONUJE i prosi o zatwierdzenie. Nie kumulujmy
 *      nadmiaru nadmiarowości, bo się nią udusimy."
 *
 * Odrzucony zostal wariant "dodaje wiersz i oznacza flaga" — produkowalby
 * wiersze, ktorych nikt nie zamawial, i po miesiacu `ZAL_*` byloby pelne
 * smieci ze znacznikami.
 *
 * \ingroup core
 */
class StozkiWidzenia : public QObject
{
    Q_OBJECT

  public:
    explicit StozkiWidzenia( QObject *parent = nullptr );

    /**
     * Odczytuje z EXIF wszystko, czego trzeba do zbudowania stozka.
     *
     * Zwraca mape: `lat`, `lon` (WGS84), `wysokosc` (m n.p.m. lub NaN),
     * `azymut` (stopnie, magnetyczny), `pitch`, `roll`, `czas`, oraz
     * `ok` = czy da sie z tego cokolwiek policzyc.
     *
     * Pusta mapa oznacza plik bez EXIF-u — nie blad.
     */
    Q_INVOKABLE QVariantMap odczytaj( const QString &sciezkaZdjecia ) const;

    /**
     * Buduje stozek widzenia jako wielokat w ukladzie warstwy.
     *
     * Zwraca WKT albo pusty ciag. Do podgladu i do rysowania; samo
     * dopasowanie robi `proponuj()`, wiec ta metoda nie jest do niego
     * potrzebna.
     */
    Q_INVOKABLE QString stozekWkt( const QString &sciezkaZdjecia,
                                   QgsVectorLayer *warstwa ) const;

    /**
     * Kandydaci na obiekt widoczny na zdjeciu, od najlepszego.
     *
     * Kazdy wpis to mapa: `fid`, `uuid` (z `UUID_WIERSZA`, gdy kolumna
     * istnieje), `etykieta`, `udzial` (procent POWIERZCHNI STOZKA, ktora
     * pada na ten obiekt), `stoje` (czy punkt aparatu lezy w obiekcie).
     *
     * `uuid` jest tu wazniejsze niz `fid`: wiazanie po nim przezyje
     * przenumerowanie i rozbicie, a `fid` nie — 09.09 wlasnie dlatego
     * cztery zdjecia zostaly bez rodzica.
     *
     * Pusta lista = stozek nie trafil w nic. To tez jest odpowiedz.
     */
    Q_INVOKABLE QVariantList proponuj( const QString &sciezkaZdjecia,
                                       QgsVectorLayer *warstwa ) const;

    /**
     * To samo dla wielu zdjec naraz — do porzadkowania zaleglosci.
     * Zwraca liste map: `plik`, `kandydaci` (jak wyzej), `powod` gdy pusto.
     */
    Q_INVOKABLE QVariantList proponujDlaWielu( const QStringList &pliki,
                                               QgsVectorLayer *warstwa ) const;

    // --- parametry: jawne, bo kazdy z nich zmienia wynik ---------------

    //! Pole widzenia w poziomie [stopnie]. 60 = srodkowa, uzyteczna czesc kadru.
    Q_PROPERTY( double poleH MEMBER mPoleH )
    //! Pole widzenia w pionie [stopnie].
    Q_PROPERTY( double poleV MEMBER mPoleV )
    //! Najdalszy punkt, ktory uznajemy za swiadectwo [m].
    Q_PROPERTY( double zasieg MEMBER mZasieg )
    //! Wysokosc aparatu nad gruntem [m].
    Q_PROPERTY( double wysokoscAparatu MEMBER mWysokosc )
    //! Deklinacja magnetyczna [stopnie]. Warszawa 2026: okolo +6.
    Q_PROPERTY( double deklinacja MEMBER mDeklinacja )

  private:
    double mPoleH = 60.0;
    double mPoleV = 45.0;
    double mZasieg = 8.0;
    double mWysokosc = 1.5;
    double mDeklinacja = 6.0;
};

#endif // STOZKIWIDZENIA_H
