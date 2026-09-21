/***************************************************************************
  cad.h - WorkField

  Modul dziedzinowy "Inwentaryzacja CAD" - silnik: rozpoznanie projektu
  zalozonego z rysunku DXF (warstwy rysunku + warstwy robocze) i czyszczenie
  danych terenowych. Sam kreator "Projekt z DXF" jest w QML
  (QfProjektZCAD.qml) i zostaje tam, gdzie byl - modul tylko do niego
  prowadzi, przez nowy rodzaj startu "z_pliku".

  Opis modulu i dalsze kroki: claude/MODULY_dziedzinowe.md, ImportDXF.md.

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef CAD_H
#define CAD_H

#include <QObject>
#include <QVariantMap>

class QgsProject;

/**
 * Silnik modulu "Inwentaryzacja CAD". Singleton QML "CAD".
 *
 * Roznica wobec inwentaryzacji drzew, dla ktorej ten mechanizm powstal:
 * drzewa zaczynaja od PUSTEGO PRZEPISU, a CAD od CUDZEGO PLIKU. Stad
 * w opisie modulu "start" zamiast "przepis" - i stad ten modul jest
 * sprawdzianem, czy opis modulu jest ogolny, a nie pisany pod drzewa.
 */
class CAD : public QObject
{
    Q_OBJECT

  public:
    explicit CAD( QObject *parent = nullptr );

    /**
     * Opis modulu (odpowiednik modul.json): id, nazwa, wersja, opis,
     * wymaga_silnika, rozpoznanie, role, start, akcje.
     */
    Q_INVOKABLE QVariantMap opis() const;

    /**
     * Co jest w projekcie - bez zmieniania czegokolwiek. Zwraca
     * {rysunek, warstwyRysunku, obiektyRysunku, warstwaPunktow, warstwaLinii,
     * warstwaPoligonow, obiekty, zModulu} albo {blad}.
     */
    Q_INVOKABLE QVariantMap rozpoznaj( QgsProject *projekt ) const;

    /**
     * Usuwa obiekty z trzech warstw roboczych (punkty, linie, poligony).
     * Rysunek CAD i same warstwy zostaja. TYLKO w projekcie zalozonym
     * z modulu (znacznik wfg_moduly/cad). Zwraca {usuniete, warstwy}
     * albo {blad}.
     */
    Q_INVOKABLE QVariantMap wyczysc( QgsProject *projekt ) const;

    /**
     * Wartosci pola "Layer" we wszystkich warstwach rysunku - czyli nazwy
     * warstw CAD, ktore GDAL wrzuca do jednego worka. Zwraca liste
     * {nazwa, obiekty, widoczna} posortowana po nazwie.
     *
     * Warstwy UKRYTE tez sa na liscie: pelny spis pamieta projekt
     * (wfg_cad/warstwyRysunku), bo po zalozeniu filtra dane o nich juz nie
     * wracaja z bazy i bez spisu filtr bylby droga w jedna strone.
     */
    Q_INVOKABLE QVariantList warstwyRysunku( QgsProject *projekt ) const;

    /**
     * Ukrywa wskazane warstwy rysunku; pusta lista zdejmuje filtr.
     *
     * To WIDOK, nie usuwanie: warunek siedzi w subsetString warstw rysunku,
     * zapisuje sie razem z projektem i da sie cofnac. Rysunek na dysku jest
     * nietkniety - a w module CAD rysunek jest cudzy i ma taki zostac.
     *
     * Zwraca {ukryte, warstwy} albo {blad}.
     */
    Q_INVOKABLE QVariantMap pokazWarstwy( QgsProject *projekt, const QStringList &ukryte ) const;

    /**
     * Znaczniki pod napisami rysunku: pokazac albo zgasic.
     *
     * Napis w DXF-ie jest encja PUNKTOWA, wiec QGIS rysuje mu znacznik
     * w miejscu zakorzenienia tekstu - obok obiektu, ktorego ten napis
     * dotyczy. Przy kilku tysiacach napisow mapa tonie w kropkach,
     * a kazda wyglada jak duplikat obiektu: przy pikiecie widac symbol,
     * kropke wartosci i kropke pustego atrybutu (telefon, 21.09.2026).
     * W probnym rysunku na 4301 tekstow 934 nie ma zadnej tresci -
     * te kropki nie oznaczaja nawet napisu.
     *
     * Gasnie SAM ZNACZNIK; napis zostaje. Robi sie to wlasciwoscia
     * sterowana wyrazeniem, wiec nic nie jest usuwane i da sie cofnac.
     *
     * Zwraca {warstwy, symbole, pokaz} albo {blad}.
     */
    Q_INVOKABLE QVariantMap kropkiNapisow( QgsProject *projekt, bool pokaz ) const;

    /**
     * Rysunki w projekcie: [{plik, nazwa, warstwy, wybrany}].
     *
     * Moduł czyta bloki i opisy z JEDNEGO rysunku. Dopóki był jeden,
     * nie było czego wybierać; gdy ktoś doloży drugi, wybór musi byc
     * jawny, a nie przypadkowy.
     */
    Q_INVOKABLE QVariantList rysunki( QgsProject *projekt ) const;

    /**
     * Wskazanie rysunku, z ktorego modul ma czytac. Zwraca {plik}
     * albo {blad}, gdy takiego rysunku nie ma w projekcie.
     */
    Q_INVOKABLE QVariantMap wybierzRysunek( QgsProject *projekt, const QString &plik ) const;

    /**
     * Bloki (encje INSERT) wstawione w rysunku. Zwraca
     * {rysunek, bloki: [{nazwa, obiekty, warstwy, wczytane}]} albo {blad};
     * lista posortowana po liczbie wystapien malejaco.
     *
     * Wymaga PONOWNEGO otwarcia pliku, i to POZA QGIS-em: aplikacja wczytuje
     * rysunek z DXF_INLINE_BLOCKS=TRUE (qflayerutils.cpp), a przy tym
     * ustawieniu INSERT-ow w danych nie ma - sa rozwiniete na kreski.
     * Druga QgsVectorLayer nic tu nie da, bo QGIS trzyma pule otwartych
     * zbiorow kluczowana sciezka i oddalby ten sam, juz otwarty (21.09).
     */
    Q_INVOKABLE QVariantMap bloki( QgsProject *projekt ) const;

    /**
     * Wczytuje wskazane bloki jako obiekty do warstwy "Symbole z rysunku"
     * (zaklada ja przy pierwszym uzyciu, w tym samym dane.gpkg co warstwy
     * robocze). Kazdy obiekt niesie nazwe bloku, warstwe rysunku, kat
     * obrotu i UCHWYT - identyfikator encji w rysunku.
     *
     * Uchwyt sprawia, ze powtorzone wczytanie NIC nie dubluje: to, co juz
     * jest, zostaje nietkniete razem z tym, co dopisano w terenie.
     *
     * Zwraca {dodane, pominiete, warstwa} albo {blad}.
     */
    Q_INVOKABLE QVariantMap zBlokow( QgsProject *projekt, const QStringList &nazwy ) const;

    /**
     * Dociaga do wczytanych symboli wartosci z TEKSTOW rysunku.
     *
     * Polskie rysunki geodezyjne zapisuja atrybuty bloku jako osobne teksty
     * na warstwach nazwanych po warstwie symbolu: "<warstwa>-Atr2" (rozbity
     * atrybut) albo "<warstwa>_O" (opis). Nazwa warstwy mowi, do czego
     * tekst nalezy; zostaje dobranie pary w obrebie warstwy.
     *
     * Przypisanie jest WZAJEMNE: kazdy tekst zuzywany raz, pary brane od
     * najkrotszych. Symboli bywa wiecej niz tekstow i wtedy nadmiarowe maja
     * zostac PUSTE, a nie dostac cudza rzedna.
     *
     * Wartosci trafiaja do kolumn nazwanych po przyrostku (ATR2, ATR17,
     * OPIS_RYS), a pierwsza z nich takze do OPIS, jesli OPIS jest pusty -
     * to on jest etykieta na mapie i to on idzie do eksportu DXF.
     * Wypelniamy TYLKO puste komorki, wiec powtorzenie nic nie nadpisuje.
     *
     * `zapisz` = false liczy bez zmieniania czegokolwiek (podglad).
     * Zwraca {dopasowane, bezWartosci, kolumny, szczegoly} albo {blad}.
     */
    Q_INVOKABLE QVariantMap dociagnijOpisy( QgsProject *projekt, double promien, bool zapisz ) const;

    /**
     * Eksport projektu do DXF - to samo, co pozycja w lewej szufladzie.
     *
     * Modul NIE MA wlasnego eksportu: wola NarzedziaProjektu::eksportujDxf,
     * czyli ten sam kod, te same ustawienia projektu i ten sam plik
     * wyjsciowy. Karta modulu jest tylko drugim WEJSCIEM - tym, ktorego
     * CADowiec szuka, bo reszta jego pracy tez tam jest.
     *
     * Rysunek zrodlowy zostaje poza wynikiem: projektant juz go ma.
     *
     * Zwraca {plik, pliki, warstwy, obiekty, uwagi} albo {blad}.
     */
    Q_INVOKABLE QVariantMap eksportuj( QgsProject *projekt ) const;

    /**
     * Warstwice z RZEDNYCH wczytanych z rysunku (warstwa "Symbole z rysunku").
     *
     * Wysokosci sa w kolumnie tekstowej (ATR2 albo OPIS - tak przychodza
     * z rysunku), wiec najpierw powstaje pomocnicza warstwa punktow
     * z liczbowym polem Z, potem powierzchnia (GDALGrid) i z niej warstwice.
     *
     * `metoda`: "gladko" (domyslna, invdistnn) albo "wiernie" (triangulacja).
     * Roznica jest widoczna golym okiem - patrz utils/warstwice.h.
     *
     * Zwraca {plik, linie, punkty, odstep} albo {blad}.
     */
    Q_INVOKABLE QVariantMap warstwiceZRzednych( QgsProject *projekt, const QString &pole, double odstep, const QString &metoda ) const;

    //! Kolumny warstwy symboli, ktore wygladaja na wysokosci: [{pole, ile}].
    Q_INVOKABLE QVariantList polaZWysokoscia( QgsProject *projekt ) const;
};

#endif // CAD_H
