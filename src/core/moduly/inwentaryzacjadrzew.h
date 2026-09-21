/***************************************************************************
  inwentaryzacjadrzew.h - WorkField

  Modul dziedzinowy "Inwentaryzacja drzew" - silnik: rozpoznanie warstwy
  drzew, styl na zywo (korona, SOD, pien) i eksport DXF + ODS.
  Rdzen bez QGIS (DXF, ODS, srednice) jest w dxfinwentaryzacja.h.
  Opis modulu i dalsze kroki: claude/MODULY_dziedzinowe.md.

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef INWENTARYZACJADRZEW_H
#define INWENTARYZACJADRZEW_H

#include <QObject>
#include <QVariantMap>

class QgsProject;

/**
 * Silnik modulu "Inwentaryzacja drzew". Singleton QML "InwentaryzacjaDrzew".
 * Warstwe i pola rozpoznaje po ROLI pola (obwody na 130 cm, korona,
 * nr inw.); ustawienia projektu wfg_inw/* nadpisuja rozpoznanie.
 */
class InwentaryzacjaDrzew : public QObject
{
    Q_OBJECT

  public:
    explicit InwentaryzacjaDrzew( QObject *parent = nullptr );

    /**
     * Opis modulu (odpowiednik modul.json): id, nazwa, wersja, opis,
     * wymaga_silnika, rozpoznanie, role pol, akcje. Zakladka "Moduly"
     * buduje z tego karte i przyciski.
     */
    Q_INVOKABLE QVariantMap opis() const;

    /**
     * Ktora warstwa i ktore pola beda uzyte - bez zmieniania czegokolwiek.
     * Zwraca {warstwa, warstwaId, obiekty, poleObwodow, poleKorony,
     * poleEtykiety} albo {blad}.
     */
    Q_INVOKABLE QVariantMap rozpoznaj( QgsProject *projekt ) const;

    /**
     * Styl warstwy drzew: korona, SOD (korona + 1,5 m z kazdej strony) i pien
     * jako okregi w metrach wokol punktu, liczone na zywo z pol obwodow
     * i korony (te same wzory co eksport DXF); etykieta nr inw. albo fid.
     * Zwraca {warstwa, pola} albo {blad}.
     */
    Q_INVOKABLE QVariantMap styluj( QgsProject *projekt ) const;

    /**
     * Eksport inwentaryzacji drzew: DXF (korony, symbole srodka, etykiety
     * z odsylaczem MULTILEADER bez kolizji - algorytm skryptu "Export Circles
     * + Callouts to DXF v1.3"), kopia rysunku projektu z dopisanymi warstwami
     * i tabela inwentaryzacyjna ODS, w <projekt>/export/inwentaryzacja_<czas>/.
     * Zwraca {pliki, katalog, drzewa, warstwa, rysunek, uwagi} albo {blad}.
     */
    Q_INVOKABLE QVariantMap eksportuj( QgsProject *projekt ) const;

    /**
     * Usuwa wszystkie obiekty z warstwy drzew i warstwy grup krzewow -
     * warstwy, pola, styl i zakres prac zostaja. TYLKO w projekcie
     * zalozonym z modulu (znacznik wfg_moduly/inwentaryzacja_drzew).
     * Zwraca {usuniete, warstwy} albo {blad}.
     */
    Q_INVOKABLE QVariantMap wyczysc( QgsProject *projekt ) const;

    /**
     * Zakres prac z pliku (GPKG, SHP, KML, GeoJSON, DXF...): poligony
     * i zamkniete linie ze wszystkich warstw pliku, przeliczone do ukladu
     * warstwy zakresu (plik bez ukladu, np. DXF = uklad projektu), z buforem
     * \a bufor [m]. Zwraca {dodane, pominiete, warstwaId} albo {blad}.
     */
    Q_INVOKABLE QVariantMap zakresZPliku( QgsProject *projekt, const QString &sciezka, double bufor ) const;

    /**
     * Rozbior odpowiedzi ULDK (GetParcelByXY / GetParcelById / GetParcelByIdOrNr,
     * srid=2180, result=...,geom_wkt): {wkt (EPSG:2180), id, opisy,
     * powierzchnia, zawiera} albo {blad, brak}. \a zawiera - czy obrys obejmuje
     * punkt zapytania \a x, \a y (tolerancja 3 m); sluzy do ustalenia
     * kolejnosci osi, jak we wtyczce GUGiK.
     */
    Q_INVOKABLE QVariantMap dzialkaZUldk( const QString &odpowiedz, double x, double y ) const;

    /**
     * Dzialki (lista {wkt w EPSG:2180, id}) jako obiekty zakresu prac
     * z buforem \a bufor [m]. Zwraca {dodane, warstwaId} albo {blad}.
     */
    Q_INVOKABLE QVariantMap dodajZakres( QgsProject *projekt, const QVariantList &dzialki, double bufor ) const;
};

#endif // INWENTARYZACJADRZEW_H
