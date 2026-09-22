/***************************************************************************
  zalaczniki.h - ModulZalacznikow (WorkFieldGIS)

  Zakladanie zalacznikow N:1 ("multiodnosniki"): tabela ZAL_<WARSTWA>
  w GeoPackage, relacja o sile kompozycji i galeria w formularzu obiektu.

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef MODUL_ZALACZNIKI_H
#define MODUL_ZALACZNIKI_H

#include <QList>
#include <QString>
#include <QStringList>

class QgsProject;
class QgsVectorLayer;

/**
 * \brief Modul "zalaczniki" wykonywany w terenie, a nie tylko w biurze.
 *
 * ==========================================================================
 * PO CO
 * ==========================================================================
 * Bez tego modulu obiekt niesie JEDNO zdjecie w polu FOTO/ZDJECIE. Drzewo
 * ma awers i rewers, szkode widac z dwoch stron, a studzienka ma tabliczke
 * i wnetrze — jedno pole tekstowe na sciezke pliku wystarcza do pierwszego
 * zdjecia i do niczego wiecej.
 *
 * Przepis istnial od 21.09.2026 jako `skrypty/zaloz_zalaczniki.py` i byl
 * wykonywalny TYLKO w biurze, w konsoli QGIS-a. `Wyposazenie` uczciwie
 * odmawialo w terenie ("krok tabele_gpkg wykonuje tylko biuro"), bo
 * `wykonajKrok()` nie umial tego typu kroku. Ten plik jest tym krokiem.
 *
 * ==========================================================================
 * JEDEN PRZEPIS, DWIE KUCHNIE
 * ==========================================================================
 * Nazwy tabel, pol, relacji i identyfikatorow sa CELOWO identyczne jak
 * w skrypcie biurowym — z jednym skutkiem, ktory jest tu najwazniejszy:
 * projekt wyposazony w biurze i projekt wyposazony w terenie wygladaja
 * tak samo, a ponowne uruchomienie drugiej drogi na projekcie zrobionym
 * pierwsza NICZEGO NIE DUBLUJE. Relacja jest rozpoznawana po tym samym
 * identyfikatorze, tabela po tej samej nazwie.
 *
 * Zmieniajac cokolwiek tutaj, zmienic tam. Rozjazd nie objawi sie bledem
 * kompilacji, tylko druga zakladka "Zalaczniki" w formularzu.
 *
 * ==========================================================================
 * CZEGO NIE ROBI
 * ==========================================================================
 * NIE RUSZA pol FOTO/ZDJECIE. Zostaja jako awaryjny zapis pojedynczego
 * zdjecia; migracja starych zdjec do tabel jest osobna operacja magazynowa
 * i swiadomie nie ma jej tutaj (skasowanie pola skasowaloby sciezki do
 * plikow, ktore juz leza w DCIM).
 *
 * NIE JEST ODWRACALNE. Modul ma `"odwracalny": false` i to nie jest
 * ostroznosc, tylko fakt: skasowanie tabeli kasuje dane. Dlatego
 * `Wyposazenie::zaloz()` robi kopie — od tej latki takze kopie `dane.gpkg`,
 * bo do tej pory kopiowal sam `projekt.qgs`, a ten krok pisze do bazy.
 *
 * \ingroup core
 */
namespace ModulZalacznikow
{
  struct Wynik
  {
      bool ok = false;
      //! Jedno zdanie dla czlowieka — co zrobiono albo dlaczego nie.
      QString opis;
      //! Po wierszu na warstwe, do dziennika i do okna Wyposazenia.
      QStringList szczegoly;
  };

  /**
   * Warstwy robocze, ktore dostana tabele zalacznikow.
   *
   * Warstwa musi byc wektorowa, prawidlowa, zapisywalna, lezec w pliku
   * GeoPackage i miec pole `fid`. Odpadaja slowniki, podklady, warstwy
   * odniesienia (REF_) i same tabele zalacznikow (ZAL_).
   */
  QList<QgsVectorLayer *> kandydaci( QgsProject *projekt );

  /**
   * Pliki GeoPackage, ktore zakladanie tknie — do kopii zapasowej.
   *
   * Osobno od `zaloz()`, bo kopia musi powstac ZANIM cokolwiek ruszy,
   * a robi ja `Wyposazenie::zaloz()`, ktore o zalacznikach nic nie wie.
   */
  QStringList bazy( QgsProject *projekt );

  /**
   * Zaklada zalaczniki we wszystkich warstwach-kandydatach.
   *
   * Idempotentne: to, co juz jest, zostaje nietkniete. Nie zapisuje
   * projektu — zapis nalezy do `Wyposazenie::zaloz()`, zeby stempel
   * i zapis szly ta sama droga co przy kazdym innym module.
   *
   * Odmawia w calosci, gdy ktorakolwiek warstwa jest w trybie edycji:
   * dopisywanie tabel do pliku, w ktorym ktos ma otwarty bufor edycji,
   * konczy sie w najlepszym razie utracona sesja.
   */
  Wynik zaloz( QgsProject *projekt );
} // namespace ModulZalacznikow

#endif // MODUL_ZALACZNIKI_H
