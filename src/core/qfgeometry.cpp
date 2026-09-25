/***************************************************************************
    qfgeometry.cpp
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
#include "qfgeometry.h"

#include <qgslinestring.h>
#include <qgspoint.h>
#include <qgspolygon.h>
#include <qgsvectorlayer.h>

#include <QLoggingCategory>

// ── POMIARY SĄ CICHE, ALE ZOSTAJĄ (25.09.2026) ────────────────────
//
// Decyzja Piotra: „Tak. Wycisz.” — tych 6 wywołań zalewało konsolę
// przy każdym zapisie kształtu z łukami. Ani jedno NIE ZNIKA:
// `ZASADY_LATEK.md` mówi wprost, że punkty pomiarowe zostają
// w kodzie, bo pomiar okazał się tańszy niż trzecia próba naprawy.
//
// Zamiast kasowania — kategoria z progiem `QtWarningMsg`. Wszystkie
// wywołania idą teraz przez `qCDebug`, czyli poniżej progu, więc
// domyślnie milczą. Wracają jedną zmienną, bez przebudowy:
//
//     QT_LOGGING_RULES="workfield.*=true"       — wszystkie
//     QT_LOGGING_RULES="workfield.luki=true"           — same te
//
Q_LOGGING_CATEGORY( wfgLuki, "workfield.luki", QtWarningMsg )

QfGeometry::QfGeometry( QObject *parent )
  : QObject( parent )
{
}

QgsGeometry QfGeometry::asQgsGeometry() const
{
  QgsAbstractGeometry *geom = nullptr;

  if ( !mVectorLayer )
  {
    return QgsGeometry();
  }

  // WorkField 25.09.2026 — podlozona geometria ma PIERWSZENSTWO.
  //
  // Ponizszy `switch` sklada ksztalt od nowa, z punktow gumki, przez
  // `QgsLineString`. Dla wszystkiego, co rysuje sie odcinkami, to jest
  // w porzadku; dla okregu zapisanego jako `CIRCULARSTRING` to jest
  // wyrok — piec wierzcholkow wracalo stad jako dziewiecdziesiat jeden.
  //
  // Zuzywamy nadpisanie OD RAZU: nastepny obiekt ma sie skladac
  // normalnie, a nie dziedziczyc ksztalt poprzedniego.
  // ── PUNKT POMIAROWY (25.09.2026) ────────────────────────────────
  // Licznik wywolan jest tu NAJWAZNIEJSZA liczba: nadpisanie jest
  // jednorazowe, wiec jesli te funkcje wola trzy razy, trzecie sklada
  // lamana z gumki i nia nadpisuje luk.
  static int ileRazy = 0;
  ++ileRazy;
  qCDebug( wfgLuki, "WorkField/Luki: asQgsGeometry #%d nadpisanie=%s warstwa=%s",
          ileRazy,
          ( !mNadpisanie.isNull() && !mNadpisanie.isEmpty() ) ? "JEST" : "brak",
          mVectorLayer ? mVectorLayer->name().toUtf8().constData() : "(brak)" );

  if ( !mNadpisanie.isNull() && !mNadpisanie.isEmpty() )
  {
    // TERMIN WAZNOSCI, nie licznik. Nadpisanie dotyczy ksztaltu, ktory
    // lezy w gumce — dopoki lezy, kazdy odczyt ma dostac luk, bez
    // wzgledu na to, ile razy kto zapyta.
    // WYGASZA DOPIERO WYZEROWANIE, nie kazda zmiana.
    //
    // Pierwsza wersja porownywala liczbe wierzcholkow i uznawala
    // rozbieznosc za „inny ksztalt". Pomiar z 08:28 pokazal, ze to za
    // ostre: `QfFeatureModel::updateRubberband()` wklada zatwierdzona
    // geometrie Z POWROTEM do gumki, wiec 513 zamienialo sie w 6
    // (piec punktow sterujacych okregu plus zywy) — i nadpisanie ginelo
    // tuz przed zapisem.
    //
    // Liczy sie jedno: czy rysowanie SIE SKONCZYLO. Widac to po tym, ze
    // w gumce nie ma juz ksztaltu.
    const int teraz = mRubberbandModel ? mRubberbandModel->vertexCount() : -1;
    if ( teraz <= 1 )
    {
      qCDebug( wfgLuki, "WorkField/Luki:   -> nadpisanie PRZETERMINOWANE (gumka wyzerowana, ma %d)",
              teraz );
      mNadpisanie = QgsGeometry();
      mNadpisanieWierzcholkow = -1;
    }
    else
    {
      QgsGeometry podlozona = mNadpisanie;
      if ( QgsWkbTypes::isMultiType( mVectorLayer->wkbType() ) )
      {
        podlozona.convertToMultiType();
      }
      qCDebug( wfgLuki, "WorkField/Luki:   -> oddaje PODLOZONA, wierzcholkow=%d luki=%s",
              podlozona.constGet() ? podlozona.constGet()->nCoordinates() : -1,
              ( podlozona.constGet() && podlozona.constGet()->hasCurvedSegments() ) ? "TAK" : "nie" );
      return podlozona;
    }
  }

  switch ( mVectorLayer->geometryType() )
  {
    case Qgis::GeometryType::Point:
    {
      geom = new QgsPoint( mRubberbandModel->currentPoint( mVectorLayer->crs(), mVectorLayer->wkbType() ) );
      break;
    }
    case Qgis::GeometryType::Line:
    {
      QgsLineString *line = new QgsLineString();
      line->setPoints( mRubberbandModel->pointSequence( mVectorLayer->crs(), mVectorLayer->wkbType() ) );
      geom = line;
      break;
    }
    case Qgis::GeometryType::Polygon:
    {
      QgsPolygon *polygon = new QgsPolygon();
      QgsLineString *ring = new QgsLineString();
      ring->setPoints( mRubberbandModel->pointSequence( mVectorLayer->crs(), mVectorLayer->wkbType(), true ) );
      polygon->setExteriorRing( ring );
      geom = polygon;
      break;
    }

    case Qgis::GeometryType::Unknown:
      break;

    case Qgis::GeometryType::Null:
      break;
  }

  QgsGeometry geometry( geom );
  if ( QgsWkbTypes::isMultiType( mVectorLayer->wkbType() ) )
  {
    geometry.convertToMultiType();
  }

  qCDebug( wfgLuki, "WorkField/Luki:   -> zlozona z gumki, wierzcholkow=%d",
          geometry.constGet() ? geometry.constGet()->nCoordinates() : -1 );

  return geometry;
}

QfRubberbandModel *QfGeometry::rubberbandModel() const
{
  return mRubberbandModel;
}

void QfGeometry::setRubberbandModel( QfRubberbandModel *rubberbandModel )
{
  if ( mRubberbandModel == rubberbandModel )
    return;

  if ( mRubberbandModel )
    disconnect( mRubberbandModel, &QfRubberbandModel::vertexCountChanged, this, nullptr );

  mRubberbandModel = rubberbandModel;
  zapomnijNadpisanie();

  // Nadpisanie dotyczy ksztaltu lezacego w gumce. Gdy gumka sie zmieni —
  // nowy obiekt, wyzerowanie po zapisie — przestaje cokolwiek znaczyc
  // i ma zgasnac SAMO, a nie czekac, az ktos o nim pamieta.
  if ( mRubberbandModel )
  {
    connect( mRubberbandModel, &QfRubberbandModel::vertexCountChanged, this, [this]() {
      // Jak wyzej: liczy sie WYZEROWANIE, nie kazda zmiana. Odswiezenie
      // gumki zatwierdzona geometria tez zmienia te liczbe, a ksztalt
      // zostaje ten sam.
      if ( mNadpisanieWierzcholkow >= 0 && mRubberbandModel
           && mRubberbandModel->vertexCount() <= 1 )
      {
        zapomnijNadpisanie();
      }
    } );
  }

  emit rubberbandModelChanged();
}

void QfGeometry::applyRubberband()
{
  // TODO: Will need to be implemented for multipart features or polygons with holes.
}

void QfGeometry::updateRubberband( const QgsGeometry &geometry )
{
  if ( !mRubberbandModel )
    return;

  if ( !geometry.isEmpty() )
  {
    // ODSWIEZENIE NIE JEST ZMIANA KSZTALTU.
    //
    // Tu `QfGeometry` wklada do gumki geometrie, ktora sam przed chwila
    // oddal. Gumka trzyma PUNKTY, wiec luk zamienia sie w niej na piec
    // wierzcholkow — ale nadpisanie dalej opisuje TEN SAM ksztalt
    // i nie ma powodu, zeby ginelo. Przechowujemy je przez ta operacje
    // i stemplujemy nowa liczba wierzcholkow.
    const QgsGeometry przechowane = mNadpisanie;

    if ( mVectorLayer )
    {
      mRubberbandModel->setDataFromGeometry( geometry, mVectorLayer->crs() );
    }
    else
    {
      mRubberbandModel->setDataFromGeometry( geometry );
    }

    if ( !przechowane.isNull() && !przechowane.isEmpty() )
    {
      mNadpisanie = przechowane;
      mNadpisanieWierzcholkow = mRubberbandModel->vertexCount();
      qCDebug( wfgLuki, "WorkField/Luki: odswiezenie gumki — nadpisanie ZOSTAJE, nowy stempel %d",
              mNadpisanieWierzcholkow );
    }
  }
  else
  {
    // Porzucenie rysowania. Nadpisanie odnosilo sie do TEGO ksztaltu,
    // wiec po nim jest juz tylko falszywa obietnica.
    mNadpisanie = QgsGeometry();
    mRubberbandModel->reset( false );
  }
}

void QfGeometry::ustawNadpisanie( const QgsGeometry &geometria )
{
  mNadpisanie = geometria;
  // Termin waznosci — patrz `mNadpisanieWierzcholkow`.
  mNadpisanieWierzcholkow = mRubberbandModel ? mRubberbandModel->vertexCount() : -1;
  qCDebug( wfgLuki, "WorkField/Luki: podlozone dla gumki o %d wierzcholkach", mNadpisanieWierzcholkow );
}

bool QfGeometry::maNadpisanie() const
{
  return !mNadpisanie.isNull() && !mNadpisanie.isEmpty();
}

void QfGeometry::zapomnijNadpisanie()
{
  mNadpisanie = QgsGeometry();
  mNadpisanieWierzcholkow = -1;
}

QgsVectorLayer *QfGeometry::vectorLayer() const
{
  return mVectorLayer.data();
}

void QfGeometry::setVectorLayer( QgsVectorLayer *vectorLayer )
{
  if ( mVectorLayer == vectorLayer )
    return;

  mVectorLayer = vectorLayer;
  // Inna warstwa to inny typ geometrii i inny uklad — ksztalt policzony
  // dla poprzedniej nie ma prawa tu dojechac.
  mNadpisanie = QgsGeometry();
  emit vectorLayerChanged();
}
