// typy.hpp — wspólne typy rdzenia: wartość pola, kolumna, obiekt, warstwa.
//
// Zasada nadrzędna: wartość pamięta KLASĘ PRZECHOWYWANIA SQLite, a nie typ
// zadeklarowany w schemacie. Kolumna DATE może w praktyce trzymać tekst,
// liczbę albo NULL — i obieg ma oddać dokładnie to, co dostał.
#pragma once

#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

namespace wfcad {

enum class Klasa : uint8_t { Null = 0, Calk = 1, Rzecz = 2, Tekst = 3, Blob = 4 };

struct Wartosc {
    Klasa klasa = Klasa::Null;
    int64_t i = 0;
    double d = 0.0;
    std::string s;          // tekst (bajty UTF-8, bez przekodowania) albo blob

    static Wartosc null_() { return {}; }
    static Wartosc calk(int64_t v) { Wartosc w; w.klasa = Klasa::Calk; w.i = v; return w; }
    static Wartosc rzecz(double v) { Wartosc w; w.klasa = Klasa::Rzecz; w.d = v; return w; }
    static Wartosc tekst(std::string v) { Wartosc w; w.klasa = Klasa::Tekst; w.s = std::move(v); return w; }
    static Wartosc blob(std::string v) { Wartosc w; w.klasa = Klasa::Blob; w.s = std::move(v); return w; }

    // Porównanie BITOWE dla liczb rzeczywistych: 0.1 i 0.1000000000000001
    // są różne, -0.0 i 0.0 też. Obieg bezstratny nie ma prawa ich zrównać.
    bool operator==(const Wartosc& o) const {
        if (klasa != o.klasa) return false;
        switch (klasa) {
            case Klasa::Null: return true;
            case Klasa::Calk: return i == o.i;
            case Klasa::Rzecz: return std::memcmp(&d, &o.d, sizeof d) == 0;
            default: return s == o.s;
        }
    }
    bool operator!=(const Wartosc& o) const { return !(*this == o); }
};

struct Kolumna {
    std::string nazwa;
    std::string typ;        // zadeklarowany, dosłownie (np. "TEXT(10)", "DATETIME")
    bool niepusta = false;  // NOT NULL
    bool klucz = false;     // PRIMARY KEY
    bool maDomyslna = false;
    std::string domyslna;   // tekst wyrażenia DEFAULT, dosłownie
};

struct Obiekt {
    int64_t fid = 0;
    bool nowy = false;              // brak fid — do wstawienia
    bool zmieniony = true;          // wynik odczytu z rysunku: różni się od stanu z wczytania
    std::vector<Wartosc> pola;      // w kolejności Warstwa::kolumny (bez fid i geometrii)
    bool maGeometrie = false;       // false = NULL w kolumnie geometrii
    std::string blob;               // GeoPackageBinary, dosłownie
};

struct Warstwa {
    std::string tabela;
    std::string kolumnaFid;
    std::string kolumnaGeom;
    std::string typGeom;            // z gpkg_geometry_columns
    int32_t srs = 0;
    std::string srsNazwa;
    std::string srsDefinicja;       // WKT z gpkg_spatial_ref_sys
    int z = 0, m = 0;               // z gpkg_geometry_columns
    std::vector<Kolumna> kolumny;   // bez fid i geometrii
    std::vector<Obiekt> obiekty;
};

struct Blad : std::runtime_error {
    using std::runtime_error::runtime_error;
};

// Raport: co się stało, osobno ostrzeżenia (dane zachowane, ale coś
// wymaga uwagi) i straty (czegoś nie dało się zachować).
struct Raport {
    std::vector<std::string> informacje;
    std::vector<std::string> ostrzezenia;
    std::vector<std::string> straty;
    void info(std::string t) { informacje.push_back(std::move(t)); }
    void uwaga(std::string t) { ostrzezenia.push_back(std::move(t)); }
    void strata(std::string t) { straty.push_back(std::move(t)); }
};

}  // namespace wfcad
