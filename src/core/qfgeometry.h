/***************************************************************************
    qfgeometry.h
    ---------------------
    begin                : March 2020
    copyright            : (C) 2020 by David Signer
    email                : david at opengis dot ch
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/
#ifndef QFGEOMETRY_H
#define QFGEOMETRY_H

#include "qfrubberbandmodel.h"

#include <QPointer>
#include <QtPositioning/QGeoCoordinate>
#include <qgsgeometry.h>

/**
 * \ingroup core
 */
class QfGeometry : public QObject
{
    Q_OBJECT

    Q_PROPERTY( QfRubberbandModel *rubberbandModel READ rubberbandModel WRITE setRubberbandModel NOTIFY rubberbandModelChanged )
    Q_PROPERTY( QgsVectorLayer *vectorLayer READ vectorLayer WRITE setVectorLayer NOTIFY vectorLayerChanged )

  public:
    explicit QfGeometry( QObject *parent = nullptr );

    QgsGeometry asQgsGeometry() const;

    /**
     * WorkField 25.09.2026 — JEDNORAZOWE NADPISANIE GEOMETRII.
     *
     * `asQgsGeometry()` sklada geometrie zawsze od nowa, z punktow gumki,
     * przez `QgsLineString`/`QgsPolygon`. To wystarcza wszystkiemu, co
     * rysuje sie odcinkami — i uniemozliwia zapisanie czegokolwiek
     * innego. Ksztalty (okrag, chmurka) policzone jako prawdziwe luki
     * wracaly stad jako lamane o kilkudziesieciu wierzcholkach.
     *
     * Tu mozna podlozyc gotowa geometrie, ktora pojdzie do obiektu
     * ZAMIAST skladania z gumki. Gumka i podglad zostaja bez zmian —
     * luk jest potrzebny dopiero w pliku.
     *
     * ZUZYWA SIE PRZY PIERWSZYM ODCZYCIE. Gdyby zostawalo, nastepny
     * obiekt dostalby ksztalt poprzedniego; to ta sama klasa bledu, co
     * „wypelnienie dziala tylko za pierwszym razem" z 24.09. Gasnie
     * takze przy zmianie warstwy i przy porzuceniu rysowania.
     */
    Q_INVOKABLE void ustawNadpisanie( const QgsGeometry &geometria );

    //! Czy cos czeka na podlozenie — do sprawdzenia w probach i w QML-u.
    Q_INVOKABLE bool maNadpisanie() const;

    //! Wyrzuca nieuzyte nadpisanie. Wolac przy porzuceniu rysowania.
    Q_INVOKABLE void zapomnijNadpisanie();

    QfRubberbandModel *rubberbandModel() const;
    void setRubberbandModel( QfRubberbandModel *rubberbandModel );
    void updateRubberband( const QgsGeometry &geometry );

    Q_INVOKABLE void applyRubberband();

    QgsVectorLayer *vectorLayer() const;
    void setVectorLayer( QgsVectorLayer *vectorLayer );

  signals:
    void rubberbandModelChanged();
    void vectorLayerChanged();

  private:
    QfRubberbandModel *mRubberbandModel = nullptr;
    QPointer<QgsVectorLayer> mVectorLayer;

    //! \copydoc ustawNadpisanie
    //!
    //! `mutable`, bo gasnie w `asQgsGeometry()`, ktore jest `const`.
    mutable QgsGeometry mNadpisanie;

    /**
     * Ile wierzcholkow miala gumka, gdy nadpisanie zostalo podlozone.
     *
     * TO JEST TERMIN WAZNOSCI. Do 25.09.2026 nadpisanie bylo
     * JEDNORAZOWE — zuzywalo sie przy pierwszym odczycie. Pomiar tego
     * samego dnia pokazal, ze `asQgsGeometry()` wola sie przy jednym
     * ksztalcie CZTERY razy, a obiekt zapisuja dwa OSTATNIE. Luk
     * dochodzil wiec do dwoch pierwszych, po czym byl nadpisywany
     * lamana.
     *
     * Poprawianie licznika bylo by powtorzeniem tego samego bledu:
     * liczba wywolan to zalozenie o cudzym kodzie, a to wlasnie sie
     * rozsypalo. Wiazemy wiec waznosc z tym, CZEGO nadpisanie dotyczy —
     * z ksztaltem lezacym w gumce. Dopoki gumka ma te sama liczbe
     * wierzcholkow, kazdy odczyt dostaje luk; gdy sie zmieni,
     * nadpisanie gasnie samo.
     *
     * -1 znaczy „nic nie czeka".
     */
    mutable int mNadpisanieWierzcholkow = -1;
};

#endif // QFGEOMETRY_H
