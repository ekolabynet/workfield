// rysunek.hpp — neutralny opis tego, co trafia do DWG.
//
// Cztery rodzaje obiektów, każdy z jednoznacznym odpowiednikiem w BRX:
//   PUNKT        AcDbPoint
//   POLILINIA    AcDbPolyline   (x, y + jedna elewacja dla całości)
//   POLILINIA3D  AcDb3dPolyline (x, y, z w każdym wierzchołku)
//   MPOLYGON     AcDbMPolygon   (pętle x, y + jedna elewacja)
// oraz słownik nazwanych obiektów rysunku (Named Object Dictionary).
//
// Plik .wfr to zrzut tego opisu na dysk: zastępuje DWG w testach i pozwala
// obejrzeć (`wfcad-obieg zrzut`), co dokładnie wtyczka zapisze w rysunku.
#pragma once

#include <map>
#include <string>
#include <vector>

#include "wfcad/xrecord.hpp"

namespace wfcad {

enum class RodzajEncji : uint8_t { Punkt = 1, Polilinia = 2, Polilinia3d = 3, MPolygon = 4 };

struct Wsp {
    double x = 0, y = 0, z = 0;
};

struct Encja {
    RodzajEncji rodzaj = RodzajEncji::Punkt;
    std::string warstwaCad;
    std::vector<Wsp> punkty;                // PUNKT, POLILINIA, POLILINIA3D
    std::vector<std::vector<Wsp>> petle;    // MPOLYGON (z pomijane)
    double elewacja = 0;                    // POLILINIA, MPOLYGON
    bool zamknieta = false;                 // POLILINIA, POLILINIA3D
    Lista dane;                             // XRecord w słowniku rozszerzeń encji
};

struct Rysunek {
    std::vector<Encja> encje;
    std::map<std::string, Lista> slownik;   // klucz = nazwa wpisu w słowniku rysunku
};

void zapiszRysunek(const Rysunek& r, const std::string& sciezka);
Rysunek wczytajRysunek(const std::string& sciezka);
std::string zrzutRysunku(const Rysunek& r);

}  // namespace wfcad
