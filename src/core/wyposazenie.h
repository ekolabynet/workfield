/***************************************************************************
  wyposazenie.h - Wyposazenie (WorkField)
  Czy projekt nadaza za aplikacja: odczyt stempla WF_WYPOSAZENIE
  i porownanie z katalogiem modulow zapakowanym w APK.
 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef WYPOSAZENIE_H
#define WYPOSAZENIE_H

#include <QObject>
#include <QVariantList>

class QgsProject;

/**
 * \brief Czy ten projekt ma to, czego aplikacja od niego oczekuje.
 *
 * ==========================================================================
 * PO CO
 * ==========================================================================
 * Kazda zmiana schematu — kolumny kontraktu parsera, `UUID_WIERSZA`,
 * geometria w tabelach `ZAL_*` — wymagala dotad, zeby CZLOWIEK PAMIETAL,
 * ze trzeba ja wykonac, i zrobil to recznie na kazdej bazie.
 *
 * Stad `ALTER TABLE` przez konsole 09.09 i stad `FITO_PLATY_2603`, ktory
 * zostal po jakiejs operacji sprzed miesiaca i do dzis nikt nie wie, czym
 * jest. Stad tez 11 zapisow gatunkowych, ktore istnieja TYLKO w tamtej
 * tabeli, niewidocznej dla QGIS-a.
 *
 * Projekt nosi STEMPEL: tabele `WF_WYPOSAZENIE` z wersja kazdego modulu.
 * Aplikacja wozi KATALOG: `:/wyposazenie/katalog.json`, pakowany do APK
 * z tego samego commita, wiec rozjazd jest niemozliwy z definicji.
 *
 * ==========================================================================
 * SPRAWDZA, NIE NAPRAWIA
 * ==========================================================================
 * Zasada z 09.09: **sprawdzac wolno wszedzie, naprawiac nie wszedzie.**
 * Zakladanie modulow zostaje w biurze (`skrypty/wyposazenie.py`), gdzie
 * jest kopia bazy i widac wynik przed wysylka.
 *
 * W terenie wartosc ma sama WIADOMOSC: dowiadujesz sie, ze projekt nie
 * nadaza, ZANIM zaczniesz nim pracowac — a nie wieczorem przy scalaniu.
 *
 * ==========================================================================
 * STAN `nowszy` JEST WAZNY
 * ==========================================================================
 * Latwo go przeoczyc, a znaczy cos odwrotnego niz reszta: projekt zrobiony
 * NOWSZA aplikacja, otwarty starsza. Wtedy to APLIKACJA jest przestarzala
 * i komunikat musi mowic co innego — bo "dolóż modul" byloby rada zla.
 *
 * \ingroup core
 */
class Wyposazenie : public QObject
{
    Q_OBJECT

  public:
    explicit Wyposazenie( QObject *parent = nullptr );

    /**
     * Porownuje stempel projektu z katalogiem w zasobach aplikacji.
     *
     * Zwraca liste map, po jednej na modul z katalogu:
     *   `modul`       QString  identyfikator (`zalaczniki`, `tyczenie`, ...)
     *   `nazwa`       QString  nazwa dla czlowieka
     *   `opis`        QString  po co ten modul jest
     *   `gdzie`       QString  "biuro" albo "teren" — gdzie wolno zakladac
     *   `wProjekcie`  int      wersja ze stempla, 0 gdy brak
     *   `wAplikacji`  int      wersja z katalogu
     *   `stan`        QString  brak | starszy | zgodny | nowszy
     *   `data`        QString  kiedy ostatnio stemplowano, gdy jest
     *
     * Pusta lista oznacza, ze nie dalo sie odczytac katalogu — a to jest
     * blad aplikacji, nie projektu.
     */
    Q_INVOKABLE QVariantList sprawdz( QgsProject *projekt ) const;

    /**
     * Jednozdaniowe podsumowanie do paska albo do komunikatu przy starcie.
     * Pusty ciag, gdy wszystko sie zgadza — wtedy nie ma o czym mowic.
     */
    Q_INVOKABLE QString podsumowanie( QgsProject *projekt ) const;

    //! Czy jest cokolwiek do powiedzenia (brak albo starszy albo nowszy).
    Q_INVOKABLE bool cosNieGra( QgsProject *projekt ) const;

  private:
    //! Wersje ze stempla `WF_WYPOSAZENIE` w `dane.gpkg` projektu.
    QVariantMap stempel( QgsProject *projekt ) const;
};

#endif // WYPOSAZENIE_H
