// wkb.hpp — WKB i GeoPackageBinary bez GDAL-a, odwracalnie co do bajtu.
//
// Model zachowuje to, co zwykle się gubi: kolejność bajtów KAŻDEJ
// zagnieżdżonej geometrii osobno, dosłowny kod typu (ISO 1000+ albo flagi
// EWKB), wartości M, wzorce bitowe NaN. piszWkb(czytajWkb(x)) == x.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "wfcad/typy.hpp"

namespace wfcad {

enum Rodzaj : int {
    PUNKT = 1, LINIA = 2, POLIGON = 3,
    WIELOPUNKT = 4, WIELOLINIA = 5, WIELOPOLIGON = 6, KOLEKCJA = 7
};

struct Wierzcholek {
    double x = 0, y = 0, z = 0, m = 0;
};

struct Geometria {
    uint8_t porzadek = 1;       // 1 = little endian, 0 = big endian
    uint32_t kod = 0;           // surowy kod typu z WKB
    int rodzaj = 0;             // 1..7
    bool z = false, m = false;
    bool maSrid = false;        // EWKB
    uint32_t srid = 0;
    // PUNKT: pierscienie[0] z jednym wierzchołkiem
    // LINIA: pierscienie[0]
    // POLIGON: pierscienie[0] zewnętrzny, dalej dziury
    std::vector<std::vector<Wierzcholek>> pierscienie;
    std::vector<Geometria> czesci;      // WIELO* i KOLEKCJA
};

struct Nieobslugiwane : Blad {
    using Blad::Blad;
};

Geometria czytajWkb(const std::string& wkb);
std::string piszWkb(const Geometria& g);

// Nagłówek GeoPackageBinary (GPKG 1.x, p. 2.1.3).
struct Gpb {
    uint8_t wersja = 0;
    uint8_t flagi = 0;
    int32_t srs = 0;
    std::vector<double> obwiednia;      // 0, 4, 6 albo 8 liczb
    bool pusta = false;
    std::string naglowek;               // dosłowne bajty nagłówka
    std::string wkb;                    // reszta bloba
};

Gpb czytajGpb(const std::string& blob);

// Nowy blob: nagłówek z tymi samymi flagami co `wzor`, obwiednia
// przeliczona z geometrii.
std::string budujGpb(const Gpb& wzor, const Geometria& g);

// Obwiednia [minx, maxx, miny, maxy, (minz, maxz), (minm, maxm)] — kolejność
// jak w GPKG. Pomija NaN. Pusta, gdy brak wierzchołków.
std::vector<double> obwiednia(const Geometria& g, bool zZ, bool zM);

bool czyPusta(const Geometria& g);
// Ustawia rodzaj, z, m, maSrid na podstawie g.kod.
void ustawZKodu(Geometria& g);
const char* nazwaRodzaju(int rodzaj);

}  // namespace wfcad
