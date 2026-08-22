/***************************************************************************
  wfnominatimlocatorfilter.h - WorkField: wyszukiwanie miejsc przez Nominatim

 ---------------------
 WorkField 18.08.2026. Filtr Locatora, który szuka miejsc i adresów w
 OpenStreetMap Nominatim i przesuwa/powiększa mapę do trafienia.

 DLACZEGO WŁASNY. Standardowy QField nie rejestruje żadnego geokodera —
 jedyny (fiński Digitransit) jest zakomentowany. QgsNominatimGeocoder siedzi
 w rdzeniu QGIS w czystym C++, więc nasze -DWITH_PYTHON=OFF go nie blokuje.
 Ten filtr to cienka nakładka na wzór QfFinlandLocatorFilter.

 GRANICE UŻYCIA NOMINATIM. Publiczny serwer Nominatim wymaga:
   • najwyżej 1 zapytanie na sekundę — pilnuje tego sam QgsNominatimGeocoder,
     dodatkowo setFetchResultsDelay(1000) dławi wpisywanie w pasku,
   • uczciwego User-Agent identyfikującego aplikację — QgsNetworkAccessManager
     wysyła nagłówek QGIS/QField; docelowo warto ustawić własny „WorkField/…".
 Złamanie tych zasad kończy się blokadą IP, więc to nie jest opcjonalne.
 ***************************************************************************/

#ifndef WFNOMINATIMLOCATORFILTER_H
#define WFNOMINATIMLOCATORFILTER_H

#include <QObject>
#include <qgsabstractgeocoderlocatorfilter.h>

class QfLocatorModelSuperBridge;

/**
 * WfNominatimLocatorFilter — wyszukiwanie miejsc przez OSM Nominatim.
 * Na trafienie obszarowe (miasto, gmina) ustawia zasięg mapy do obrysu;
 * na trafienie punktowe centruje mapę na punkcie.
 */
class WfNominatimLocatorFilter : public QgsAbstractGeocoderLocatorFilter
{
    Q_OBJECT

  public:
    explicit WfNominatimLocatorFilter( QgsGeocoderInterface *geocoder, QfLocatorModelSuperBridge *locatorBridge );
    WfNominatimLocatorFilter *clone() const override;

  private:
    void handleGeocodeResult( const QgsGeocoderResult &result ) override;

    QfLocatorModelSuperBridge *mLocatorBridge = nullptr;
};

#endif // WFNOMINATIMLOCATORFILTER_H
