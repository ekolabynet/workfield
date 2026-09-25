/***************************************************************************
  kafle.h - ModulKafli (WorkFieldGIS)

  Kafle paska szybkiego przechwytu: `workfield_klawisze.json` obok projektu.
  Do 23.09.2026 aplikacja umiala ten plik TYLKO SPRAWDZIC.

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef MODUL_KAFLE_H
#define MODUL_KAFLE_H

#include <QString>
#include <QStringList>
#include <QVariantList>

class QgsProject;

/**
 * \brief Kafle paska szybkiego przechwytu — zakladane, nie tylko sprawdzane.
 *
 * ==========================================================================
 * PO CO
 * ==========================================================================
 * Pasek szybkiego przechwytu czyta `workfield_klawisze.json` obok projektu.
 * Bez tego pliku pasek wstaje PUSTY i kazdy obiekt zakladasz przez menu
 * warstw — w rekawicach, na mrozie, przy kazdym drzewie osobno.
 *
 * Tresc jest branzowa (D/G/U/T w dendro, inna w platach), wiec przez tydzien
 * modul uczciwie jej NIE WYMYSLAL: sprawdzal, czy plik jest i czy jest
 * poprawny. Klopot w tym, ze w terenie „sprawdzil i powiedzial, ze nie ma”
 * konczy sie dokladnie tak samo jak brak modulu — plikiem, ktorego nikt nie
 * napisze, bo nie ma w czym.
 *
 * Od 23.09.2026 modul PYTA, ktorym warstwom ma przybyc kafel, i pisze.
 * Tresc nadal nie jest zgadywana — wskazuje ja czlowiek, jednym tapnieciem
 * na warstwe.
 *
 * ==========================================================================
 * SCALA, NIE NADPISUJE
 * ==========================================================================
 * `QfNaprawaProjektu` robi kafle od 20.09 i robi je PRZEZ NADPISANIE calego
 * pliku. Kto dolozyl sobie kafel recznie — traci go przy nastepnym
 * uruchomieniu naprawy. Ten modul czyta plik, DOKLADA brakujace kafle
 * i zapisuje calosc: obce klucze, kolejnosc i komentarze zostaja.
 *
 * ==========================================================================
 * ETYKIETY BEZ ZDERZEN
 * ==========================================================================
 * Pierwsza litera nazwy warstwy to etykieta oczywista i zderza sie natychmiast:
 * „Punkty” i „Poligony” w kreatorze DXF daja oba „P”, a dwa kafle o tej samej
 * etykiecie to pasek, na ktorym nie wiadomo, w co sie stuka. Etykieta jest
 * wiec DOBIERANA: pierwsza litera, potem dwie pierwsze, potem pierwsza
 * z kolejna, na koncu pierwsza z cyfra. Zajete sa takze te, ktore w pliku
 * JUZ sa — scalanie nie moze zepsuc cudzego kafla.
 *
 * \ingroup core
 */
namespace ModulKafli
{
  struct Wynik
  {
      bool ok = false;
      //! Jedno zdanie dla czlowieka — co zrobiono albo dlaczego nie.
      QString opis;
      //! Po wierszu na kafel, do dziennika i do okna Wyposazenia.
      QStringList szczegoly;
  };

  //! Sciezka `workfield_klawisze.json` obok projektu; pusta, gdy nie ma domu.
  QString plikKafli( QgsProject *projekt );

  /**
   * Warstwy, ktorym MOZE przybyc kafel, z propozycja etykiety.
   *
   * Kazdy wpis to mapa: `warstwa`, `etykieta`, `geometria`, `maKafel`,
   * `kolor`, `zdjecie`. Warstwy, ktore kafel juz maja, sa w liscie takze —
   * z `maKafel = true` i etykieta ISTNIEJACA, zeby okno pokazywalo stan
   * calego paska, a nie tylko dziure w nim.
   *
   * Odpadaja tabele zalacznikow (ZAL_), podklady, slowniki i warstwy
   * odniesienia (REF_) — kafel na slowniku nie ma sensu.
   */
  QVariantList kandydaci( QgsProject *projekt );

  /**
   * Doklada kafle dla WSKAZANYCH warstw i zapisuje plik.
   *
   * Idempotentne: warstwa, ktora kafel juz ma, jest pomijana. Plik, ktory
   * juz byl, dostaje kopie `.przed_<data>` — scalanie jest dopisywaniem,
   * ale plik pisze tez czlowiek i nie nam decydowac, ze nic w nim nie bylo.
   *
   * Nie zapisuje projektu — zapis nalezy do `Wyposazenie::zaloz()`.
   */
  Wynik zaloz( QgsProject *projekt, const QStringList &warstwy );

  /**
   * Doklada JEDEN kafel o zadanej etykiecie. Uzywa tego modul warstwy
   * roboczej, ktory zaklada warstwe i jej kafel jednym ruchem.
   *
   * Gdy warstwa kafel juz ma — nie robi nic i mowi o tym. Gdy zadana
   * etykieta jest zajeta — dobiera wolna, zamiast robic pasek z dwoma
   * takimi samymi klawiszami.
   */
  Wynik dolozKafel( QgsProject *projekt, const QString &warstwa,
                    const QString &etykieta, const QString &kolor, bool zdjecie );
} // namespace ModulKafli

#endif // MODUL_KAFLE_H
