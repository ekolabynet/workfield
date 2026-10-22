// uklad.cpp — patrz uklad.hpp. Przeniesione z skrypty/geom_gpkg.py (do_2000, z_2000).
#include "wfcad/uklad.hpp"

#include <cmath>

#include "wfcad/wkb.hpp"

namespace wfcad {

namespace {

constexpr double A = 6378137.0;
constexpr double F = 1 / 298.257222101;     // GRS80
constexpr double E2 = F * (2 - F);
constexpr double K0 = 0.999923;
constexpr double PI = 3.14159265358979323846;

double poludnik(int epsg) { return (epsg - 2176) * 3.0 + 15.0; }
double przesuniecie(int epsg) { return (epsg - 2176) * 1000000.0 + 5500000.0; }
double rad(double s) { return s * PI / 180.0; }
double stopnie(double r) { return r * 180.0 / PI; }

}  // namespace

bool strefaPl2000(int epsg) { return epsg >= 2176 && epsg <= 2179; }

void Uklad::doCad(double lon, double lat, double& e_, double& n_) const {
    const double n = F / (2 - F);
    const double lam0 = rad(poludnik(docelowy));
    const double phi = rad(lat), lam = rad(lon);
    const double e = std::sqrt(E2);
    // szerokość konforemna
    const double t = std::sinh(std::atanh(std::sin(phi)) - e * std::atanh(e * std::sin(phi)));
    const double xi = std::atan(t / std::cos(lam - lam0));
    // η w jednej postaci (asinh z hypot) — w geom_gpkg.py opisana pułapka
    // mieszania dwóch tożsamych postaci: błąd rośnie z odległością od południka.
    const double eta = std::asinh(std::sin(lam - lam0) / std::hypot(t, std::cos(lam - lam0)));
    const double a_ = A / (1 + n) * (1 + n * n / 4 + std::pow(n, 4) / 64);
    const double al[4] = {n / 2 - 2 * n * n / 3 + 5 * std::pow(n, 3) / 16 + 41 * std::pow(n, 4) / 180,
                          13 * n * n / 48 - 3 * std::pow(n, 3) / 5 + 557 * std::pow(n, 4) / 1440,
                          61 * std::pow(n, 3) / 240 - 103 * std::pow(n, 4) / 140,
                          49561 * std::pow(n, 4) / 161280};
    double x = eta, y = xi;
    for (int j = 0; j < 4; ++j) {
        x += al[j] * std::cos(2 * (j + 1) * xi) * std::sinh(2 * (j + 1) * eta);
        y += al[j] * std::sin(2 * (j + 1) * xi) * std::cosh(2 * (j + 1) * eta);
    }
    e_ = K0 * a_ * x + przesuniecie(docelowy);
    n_ = K0 * a_ * y;
}

void Uklad::zCad(double e_, double n_, double& lon, double& lat) const {
    const double n = F / (2 - F);
    const double a_ = A / (1 + n) * (1 + n * n / 4 + std::pow(n, 4) / 64);
    const double xi = n_ / (K0 * a_);
    const double eta = (e_ - przesuniecie(docelowy)) / (K0 * a_);
    const double be[4] = {n / 2 - 2 * n * n / 3 + 37 * std::pow(n, 3) / 96 - std::pow(n, 4) / 360,
                          n * n / 48 + std::pow(n, 3) / 15 - 437 * std::pow(n, 4) / 1440,
                          17 * std::pow(n, 3) / 480 - 37 * std::pow(n, 4) / 840,
                          4397 * std::pow(n, 4) / 161280};
    double xi_ = xi, eta_ = eta;
    for (int j = 0; j < 4; ++j) {
        xi_ -= be[j] * std::sin(2 * (j + 1) * xi) * std::cosh(2 * (j + 1) * eta);
        eta_ -= be[j] * std::cos(2 * (j + 1) * xi) * std::sinh(2 * (j + 1) * eta);
    }
    const double chi = std::asin(std::sin(xi_) / std::cosh(eta_));
    const double de[4] = {2 * n - 2 * n * n / 3 - 2 * std::pow(n, 3) + 116 * std::pow(n, 4) / 45,
                          7 * n * n / 3 - 8 * std::pow(n, 3) / 5 - 227 * std::pow(n, 4) / 45,
                          56 * std::pow(n, 3) / 15 - 136 * std::pow(n, 4) / 35,
                          4279 * std::pow(n, 4) / 630};
    double phi = chi;
    for (int j = 0; j < 4; ++j) phi += de[j] * std::sin(2 * (j + 1) * chi);
    lat = stopnie(phi);
    lon = stopnie(rad(poludnik(docelowy)) + std::atan(std::sinh(eta_) / std::cos(xi_)));
}

int dobierzStrefe(const std::vector<Warstwa>& warstwy) {
    double suma = 0;
    size_t ile = 0;
    for (const auto& w : warstwy) {
        if (w.srs != 4326) continue;
        for (const auto& o : w.obiekty) {
            if (!o.maGeometrie) continue;
            try {
                Geometria g = czytajWkb(czytajGpb(o.blob).wkb);
                std::vector<double> ob = obwiednia(g, false, false);
                if (ob.size() >= 2 && std::isfinite(ob[0]) && std::isfinite(ob[1])) {
                    suma += (ob[0] + ob[1]) / 2;
                    ++ile;
                }
            } catch (const Blad&) {
            }
        }
    }
    if (!ile) return 0;
    const double lon = suma / static_cast<double>(ile);
    if (lon < 13.5 || lon > 25.5) return 0;
    const int strefa = static_cast<int>(std::lround(lon / 3.0)) - 5;     // 15° -> 0 ... 24° -> 3
    return (strefa < 0 || strefa > 3) ? 0 : 2176 + strefa;
}

}  // namespace wfcad
