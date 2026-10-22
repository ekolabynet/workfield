// uklad.hpp — WGS84 (EPSG:4326) <-> PL-2000 (EPSG:2176–2179) dla rysunku CAD.
//
// Bazy z Mapit i z telefonu bywają w stopniach. W CAD-zie stopnie są
// bezużyteczne (pomiar, mapa zasadnicza, okręgi w metrach), więc rysunek
// dostaje współrzędne PL-2000, a XRecord dalej niesie dokładne stopnie.
// Przy powrocie oryginał przeliczony TYM SAMYM wzorem porównuje się z tym,
// co oddał CAD: wierzchołek nieruszony wraca jako oryginalne stopnie co do
// bitu, przesunięty — przeliczony odwrotnie.
//
// Wzór: szereg Krügera, przeniesiony 1:1 z skrypty/geom_gpkg.py (WorkFieldGIS),
// sprawdzonego tam przeciw pyproj na 868 punktach (0,0002 mm w prostej,
// 0,0012 mm w odwrotnej). JEDEN WZÓR W DWÓCH MIEJSCACH: zmieniając jeden,
// zmień drugi i powtórz test testy/test_obiegu.py (porównuje oba).
//
// GeoPackage w 4326 trzyma x = długość, y = szerokość; CAD i GIS w PL-2000
// trzymają x = easting, y = northing. Z nie jest przeliczane.
#pragma once

#include <vector>

#include "wfcad/typy.hpp"

namespace wfcad {

struct Uklad {
    int docelowy = 0;       // 2176..2179; 0 = bez przeliczenia

    bool przelicza(int srsWarstwy) const { return docelowy != 0 && srsWarstwy == 4326; }
    void doCad(double lon, double lat, double& e, double& n) const;
    void zCad(double e, double n, double& lon, double& lat) const;
};

bool strefaPl2000(int epsg);

// Strefa PL-2000 dla średniej długości geograficznej wszystkich obiektów
// warstw w EPSG:4326; 0, gdy takich nie ma albo leżą poza Polską (14–24,5° E).
int dobierzStrefe(const std::vector<Warstwa>& warstwy);

}  // namespace wfcad
