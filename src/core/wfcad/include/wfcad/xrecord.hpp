// xrecord.hpp — neutralny odpowiednik XRecordu DWG: lista par (kod, wartość).
//
// Rdzeń zapisuje dane GIS WYŁĄCZNIE kodami, które przenosi każdy program
// zgodny z DWG, a adapter BRX tylko przepisuje tę listę 1:1 na łańcuch
// resbuf. Dzięki temu test obiegu w rdzeniu sprawdza dokładnie to, co
// trafi do pliku DWG, bez BricsCAD-a.
//
// Używane kody:
//    1   krótki znacznik ASCII (nazwy pól formatu, nigdy dane użytkownika)
//   70   liczba 16-bitowa
//   90   liczba 32-bitowa
//   40   liczba rzeczywista (double) — w formacie WF nieużywany: wartości
//        rzeczywiste idą jako 8 bajtów (310), bo DXF tekstowy zapisuje kod 40
//        cyframi, które CAD może obciąć
//  310   porcja bajtów, najwyżej 127 B
//
// Liczby 64-bitowe idą jako DWA kody 90 (starsze i młodsze 32 bity), a nie
// kodem 160 — nie mam pewności, że każdy klon CAD-a przenosi 160
// w XRecordzie. Do sprawdzenia w BricsCAD V27, potem można uprościć.
//
// Dane użytkownika (teksty pól, nazwy warstw, UUID) idą jako BAJTY (310),
// nie jako tekst (1): tekst DWG jest przekodowywany na Unicode, a pole TEXT
// w SQLite może zawierać bajty, które nie są poprawnym UTF-8, albo znak \0.
// Bajty wracają nietknięte.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "wfcad/typy.hpp"

namespace wfcad {

struct Para {
    int kod = 0;
    int32_t i = 0;          // 70, 90
    double d = 0;           // 40
    std::string s;          // 1, 310

    bool operator==(const Para& o) const;
};

using Lista = std::vector<Para>;

constexpr size_t PORCJA_BAJTOW = 127;

class Pisarz {
public:
    explicit Pisarz(Lista& l) : l_(l) {}
    void znacznik(const std::string& ascii);
    void i16(int16_t v);
    void i32(int32_t v);
    void i64(int64_t v);
    void real(double v);
    void bajty(const std::string& b);
    void wartosc(const Wartosc& w);
private:
    Lista& l_;
};

class Czytnik {
public:
    explicit Czytnik(const Lista& l, size_t od = 0) : l_(l), i_(od) {}
    void znacznik(const std::string& oczekiwany);
    bool czyZnacznik(const std::string& z) const;
    int16_t i16();
    int32_t i32();
    int64_t i64();
    double real();
    std::string bajty();
    Wartosc wartosc();
    bool koniec() const { return i_ >= l_.size(); }
    size_t pozycja() const { return i_; }
private:
    const Para& nastepna(int kod);
    const Lista& l_;
    size_t i_;
};

}  // namespace wfcad
