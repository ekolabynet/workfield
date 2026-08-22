/***************************************************************************
  wfnominatimlocatorfilter.cpp - WorkField: wyszukiwanie miejsc przez Nominatim
 ***************************************************************************/

#include "wfnominatimlocatorfilter.h"
#include "locatormodelsuperbridge.h"
#include "qgsquickmapsettings.h"

#include <qgscoordinatetransform.h>
#include <qgsgeocoderresult.h>
#include <qgsproject.h>
#include <qgsrectangle.h>

WfNominatimLocatorFilter::WfNominatimLocatorFilter( QgsGeocoderInterface *geocoder, QfLocatorModelSuperBridge *locatorBridge )
  : QgsAbstractGeocoderLocatorFilter( QStringLiteral( "wf-nominatim" ), tr( "Miejsca (OSM Nominatim)" ), QStringLiteral( "n" ), geocoder )
  , mLocatorBridge( locatorBridge )
{
  // Bez ograniczenia obszarem — Nominatim jest globalny.
  // 1000 ms zwłoki: pasek nie strzela zapytaniem na każdą literę, co razem
  // z wewnętrznym dławieniem QgsNominatimGeocoder trzyma limit 1/s.
  setFetchResultsDelay( 1000 );
  // Aktywny bez prefiksu: „od razu zakłada wyszukiwanie" (życzenie Piotra).
  setUseWithoutPrefix( true );
}

WfNominatimLocatorFilter *WfNominatimLocatorFilter::clone() const
{
  return new WfNominatimLocatorFilter( geocoder(), mLocatorBridge );
}

void WfNominatimLocatorFilter::handleGeocodeResult( const QgsGeocoderResult &result )
{
  const QgsCoordinateReferenceSystem currentCrs = mLocatorBridge->mapSettings()->mapSettings().destinationCrs();
  const QgsCoordinateReferenceSystem wgs84Crs( QStringLiteral( "EPSG:4326" ) );

  QgsCoordinateTransform ct( wgs84Crs, currentCrs, QgsProject::instance()->transformContext() );
  QgsGeometry transformedGeometry = result.geometry();
  try
  {
    transformedGeometry.transform( ct );
  }
  catch ( const QgsException &e )
  {
    Q_UNUSED( e )
    return;
  }
  catch ( ... )
  {
    return;
  }

  // WAŻNE: QgsNominatimGeocoder zwraca geometrię jako PUNKT, a obrys obszaru
  // (miasto, gmina, park) trzyma osobno w result.viewport() — prostokącie
  // WGS84. Bounding box samej geometrii byłby zerowy, więc bierzemy viewport.
  // Jest → ustawiamy zasięg do niego (przesuwamy I POWIĘKSZAMY).
  // Nie ma (dokładny adres) → centrujemy na punkcie.
  const QgsRectangle viewport = result.viewport();
  if ( !viewport.isNull() && viewport.width() > 0 && viewport.height() > 0 )
  {
    QgsRectangle wCrs;
    try
    {
      wCrs = ct.transformBoundingBox( viewport );
    }
    catch ( ... )
    {
      wCrs = QgsRectangle();
    }
    if ( !wCrs.isNull() && wCrs.width() > 0 && wCrs.height() > 0 )
    {
      wCrs.scale( 1.05 );
      mLocatorBridge->mapSettings()->setExtent( wCrs, true );
    }
    else
    {
      mLocatorBridge->mapSettings()->setCenter( transformedGeometry.centroid().vertexAt( 0 ), true );
    }
  }
  else
  {
    mLocatorBridge->mapSettings()->setCenter( transformedGeometry.centroid().vertexAt( 0 ), true );
  }

  mLocatorBridge->geometryHighlighter()->setProperty( "qgsGeometry", result.geometry() );
  mLocatorBridge->geometryHighlighter()->setProperty( "crs", result.crs() );
}
