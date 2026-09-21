/***************************************************************************
  dxfinwentaryzacja.h - WorkField

  Eksport inwentaryzacji drzew do DXF: korony jako okregi, symbole srodka
  (srednica pnia z obwodow), etykiety z odsylaczami rozmieszczone bez kolizji.
  Przeniesienie skryptu Processing "Export Circles + Callouts to DXF v1.3"
  (ezdxf) do C++ - bez ezdxf, bez QGIS: tylko Qt, zeby dalo sie to
  skompilowac i sprawdzic poza aplikacja.

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#ifndef DXFINWENTARYZACJA_H
#define DXFINWENTARYZACJA_H

#include <QByteArray>
#include <QString>
#include <QStringList>
#include <QPointF>
#include <QVector>

namespace DxfInwentaryzacja
{
  //! Jedno drzewo (albo karpa, grupa krzewow) we wspolrzednych rysunku.
  struct Drzewo
  {
      double x = 0.0;
      double y = 0.0;
      double rKorony = 0.0; //!< [m]; 0 = bez okregu korony
      double rPnia = 0.0;   //!< [m]; 0 = symbol zastepczy
      QString etykieta;
  };

  /**
   * Obszar rysowany jako obrys: zakres prac, bufor zakresu, grupa krzewow.
   * \a pierscienie - zewnetrzny i ewentualne wewnetrzne (dziury), kazdy
   * zamkniety, we wspolrzednych rysunku; \a warstwa - nazwa warstwy DXF;
   * \a etykieta - napis w srodku obrysu (pusty = bez napisu).
   */
  struct Obszar
  {
      QVector<QVector<QPointF>> pierscienie;
      QString warstwa;
      QString etykieta;
  };

  struct Ustawienia
  {
      double wysokoscTekstu = 0.25; //!< [m]
      double szerokoscZnaku = 0.09; //!< [m] do oceny szerokosci etykiety (jak w skrypcie); 0 = 0,6 x wysokosc
      double odsylaczMin = 0.5;     //!< [m]
      double odsylaczMax = 0.0;     //!< [m]; 0 = do 15 m
      double margines = 0.1;        //!< [m]
      double promienZastepczy = 0.1; //!< [m] symbol srodka, gdy brak obwodow
      int aciWarstw = 7;
  };

  struct Wynik
  {
      QByteArray dxf;
      QStringList uwagi;
      int etykietyZOdsylaczem = 0;
      int etykietyBezMiejsca = 0;
      QString odsylacz; //!< MULTILEADER albo LINE+TEXT
  };

  /**
   * Srednica pnia [m] z opisu obwodow, np. "26+26+19", "sr35+ sr28", "ok 350".
   * Wzor skryptu: obwod efektywny = najwiekszy + polowa pozostalych,
   * srednica = obwod / pi. Prefiks "sr"/"s"/"śr"/"Ø"/"d" = SREDNICA w cm,
   * nie obwod. Wartosci w m2 (powierzchnia krzewow) daja 0. Minus miedzy
   * liczbami traktowany jak plus ("68-67" = dwa pnie).
   */
  double srednicaZObwodow( const QString &opis, QString *uwaga = nullptr );

  //! Liczba z pola tekstowego ("7", "7,5", " 12 m"); 0 gdy brak.
  double liczba( const QString &tekst );

  /**
   * Dopisuje inwentaryzacje do DXF \a bazowy (pusty = czysty szablon R2018).
   * \a koduj zamienia tekst etykiet na bajty dla plikow sprzed R2007
   * (np. CP1250); nullptr = Latin-1. Od R2007 DXF jest zawsze w UTF-8.
   */
  Wynik dopisz( const QByteArray &bazowy, const QVector<Drzewo> &drzewa, const Ustawienia &ust,
                QByteArray ( *koduj )( const QString & ) = nullptr,
                const QVector<Obszar> &obszary = QVector<Obszar>() );

  //! Wiersz tabeli inwentaryzacyjnej - pola jak w zrodle, jako tekst.
  struct Wiersz
  {
      qlonglong fid = 0;
      QString grupa, kategoria, nazwaTechniczna, nazwaPolska, obwody5, obwody130, korona, wysokosc, stan, uwagi;
      QString obreb, dzialka, teryt, wkt;
  };

  /**
   * Tabela inwentaryzacyjna w ODS (wlasny zapis, zip przez GDAL; formatowanie jak arkusz pracowni) - kolumny jak w arkuszu
   * "Tabela inwentaryzacyjna" (APPL LS Bruzdowa 2026-06-17), z kolumnami
   * liczonymi przez nas zamiast formul: obwod efektywny, srednica SOD
   * (korona + 2 x 1,5 m), srednica pnia, frazy z "Uwag". Drugi i trzeci
   * arkusz: zestawienie gatunkow i stanu zdrowotnego.
   * Zwraca pusty tekst albo opis bledu.
   */
  //! \a grupy - wiersze arkusza "Grupy krzewow" (ostatnia kolumna liczbowa:
  //! powierzchnia); pusta lista = bez tego arkusza.
  QString zapiszOds( const QString &sciezka, const QVector<Wiersz> &wiersze, const QList<QStringList> &grupy = QList<QStringList>() );
} // namespace DxfInwentaryzacja

#endif // DXFINWENTARYZACJA_H
