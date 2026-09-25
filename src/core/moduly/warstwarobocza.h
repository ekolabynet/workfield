/***************************************************************************
  warstwarobocza.h - ModulWarstwyRoboczej (WorkFieldGIS)

  Zakladanie warstwy TECHNICZNEJ opisanej w `modul.json` — razem z jej
  kaflem na pasku szybkiego przechwytu.

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef MODUL_WARSTWA_ROBOCZA_H
#define MODUL_WARSTWA_ROBOCZA_H

#include <QJsonObject>
#include <QString>
#include <QStringList>

class QgsProject;

/**
 * \brief Warstwa robocza — zakladana, nie tylko sprawdzana.
 *
 * ==========================================================================
 * PO CO
 * ==========================================================================
 * Modul `tyczenie` od 15.09.2026 tylko STWIERDZAL, czy warstwa jest.
 * W terenie konczylo sie to zdaniem „w projekcie nie ma warstwy »tyczenie«”
 * i niczym wiecej — warstwe trzeba bylo zalozyc w biurze, czyli jutro.
 *
 * A `tyczenie` to warstwa TECHNICZNA: dwa pola, zadnej branzy, zadnej
 * decyzji do podjecia. Nie ma czego konsultowac z biurem. Od 23.09.2026
 * aplikacja zaklada ja sama — po zapytaniu czlowieka, bo warstwa dokladana
 * do cudzego projektu bez pytania to zmiana, ktorej nikt nie zamawial.
 *
 * ==========================================================================
 * OPIS SIEDZI W `modul.json`, NIE TUTAJ
 * ==========================================================================
 * Krok niesie nazwe, geometrie, pola i kafel:
 *
 *     { "typ": "warstwa_robocza", "nazwa": "tyczenie", "geometria": "punkt",
 *       "pola": [ { "nazwa": "opis", "typ": "tekst" },
 *                 { "nazwa": "data_czas", "typ": "tekst",
 *                   "domyslnie": "format_date(now(),'yyyy-MM-dd HH:mm:ss')" } ],
 *       "kafel": { "etykieta": "TY", "kolor": "#546E7A", "zdjecie": false } }
 *
 * Dzieki temu nastepna warstwa techniczna nie wymaga ani linijki C++,
 * a schemat pol widac tam, gdzie go szukasz — w opisie modulu.
 *
 * ==========================================================================
 * PO CO KAFEL RAZEM Z WARSTWA
 * ==========================================================================
 * Warstwa tyczenia bez kafla jest bezuzyteczna: kafel z `"zdjecie": false`
 * na warstwie punktowej odblokowuje trzy tryby naraz — punkt bez aparatu,
 * serie wierzcholkow pod dlugim przytrzymaniem i dokladanie wierzcholkow
 * z GNSS do rysowanej geometrii. Zalozenie samej warstwy bylo wiec
 * polowa roboty, po ktorej i tak trzeba wracac do biura.
 *
 * ==========================================================================
 * IDEMPOTENCJA
 * ==========================================================================
 * Warstwa w projekcie → nie ruszamy. Tabela w bazie, ale nie w projekcie →
 * wczytujemy ISTNIEJACA (drugiej takiej samej nie robimy nigdy, bo w tamtej
 * moga juz lezec punkty z terenu). Kafel dla tej warstwy → sprawdzany po
 * NAZWIE WARSTWY, nie po etykiecie: projekty dendro maja go pod „T” od 20.09.
 *
 * \ingroup core
 */
namespace ModulWarstwyRoboczej
{
  struct Wynik
  {
      bool ok = false;
      //! Jedno zdanie dla czlowieka — co zrobiono albo dlaczego nie.
      QString opis;
      QStringList szczegoly;
  };

  /**
   * Plik GeoPackage, ktory krok tknie — do kopii zapasowej.
   *
   * Osobno od `zaloz()`, bo kopia musi powstac ZANIM cokolwiek ruszy,
   * a robi ja `Wyposazenie::zaloz()`. Pusty ciag, gdy bazy nie ma.
   */
  QString baza( QgsProject *projekt );

  /**
   * Zdanie dla czlowieka PRZED zalozeniem: co dokladnie powstanie.
   *
   * Pytanie „czy zalozyc warstwe?” bez wymienienia pol i kafla jest
   * pytaniem o nic — czlowiek nie ma na co odpowiedziec.
   */
  QString zapowiedz( const QJsonObject &krok );

  //! Zaklada warstwe opisana w kroku i jej kafel. Nie zapisuje projektu.
  Wynik zaloz( QgsProject *projekt, const QJsonObject &krok );
} // namespace ModulWarstwyRoboczej

#endif // MODUL_WARSTWA_ROBOCZA_H
