// xrecord.cpp — patrz xrecord.hpp.
#include "wfcad/xrecord.hpp"

#include <cstring>

namespace wfcad {

bool Para::operator==(const Para& o) const {
    return kod == o.kod && i == o.i && std::memcmp(&d, &o.d, sizeof d) == 0 && s == o.s;
}

void Pisarz::znacznik(const std::string& a) {
    Para p;
    p.kod = 1;
    p.s = a;
    l_.push_back(p);
}

void Pisarz::i16(int16_t v) {
    Para p;
    p.kod = 70;
    p.i = v;
    l_.push_back(p);
}

void Pisarz::i32(int32_t v) {
    Para p;
    p.kod = 90;
    p.i = v;
    l_.push_back(p);
}

void Pisarz::i64(int64_t v) {
    const uint64_t u = static_cast<uint64_t>(v);
    i32(static_cast<int32_t>(static_cast<uint32_t>(u >> 32)));
    i32(static_cast<int32_t>(static_cast<uint32_t>(u & 0xFFFFFFFFu)));
}

void Pisarz::real(double v) {
    Para p;
    p.kod = 40;
    p.d = v;
    l_.push_back(p);
}

void Pisarz::bajty(const std::string& b) {
    if (b.size() > 0x7FFFFFFFu) throw Blad("wartość większa niż 2 GB");
    i32(static_cast<int32_t>(b.size()));
    for (size_t poz = 0; poz < b.size(); poz += PORCJA_BAJTOW) {
        Para p;
        p.kod = 310;
        p.s = b.substr(poz, PORCJA_BAJTOW);
        l_.push_back(p);
    }
}

void Pisarz::wartosc(const Wartosc& w) {
    i16(static_cast<int16_t>(w.klasa));
    switch (w.klasa) {
        case Klasa::Null: break;
        case Klasa::Calk: i64(w.i); break;
        case Klasa::Rzecz: {
            // 8 bajtów, nie kod 40: DXF tekstowy zapisuje kod 40 cyframi, a CAD
            // może je obciąć; Inf w kodzie 40 nie przejdzie przez każdy czytnik.
            std::string b(8, '\0');
            uint64_t v;
            std::memcpy(&v, &w.d, 8);
            for (int i = 0; i < 8; ++i) b[static_cast<size_t>(i)] = static_cast<char>((v >> (8 * i)) & 0xFF);
            bajty(b);
            break;
        }
        case Klasa::Tekst:
        case Klasa::Blob: bajty(w.s); break;
    }
}

const Para& Czytnik::nastepna(int kod) {
    if (i_ >= l_.size())
        throw Blad("XRecord uszkodzony: koniec danych, oczekiwano kodu " + std::to_string(kod));
    const Para& p = l_[i_];
    if (p.kod != kod)
        throw Blad("XRecord uszkodzony w pozycji " + std::to_string(i_) + ": kod " + std::to_string(p.kod) +
                   " zamiast " + std::to_string(kod));
    ++i_;
    return p;
}

void Czytnik::znacznik(const std::string& z) {
    const Para& p = nastepna(1);
    if (p.s != z) throw Blad("XRecord uszkodzony: znacznik „" + p.s + "” zamiast „" + z + "”");
}

bool Czytnik::czyZnacznik(const std::string& z) const {
    return i_ < l_.size() && l_[i_].kod == 1 && l_[i_].s == z;
}

int16_t Czytnik::i16() { return static_cast<int16_t>(nastepna(70).i); }
int32_t Czytnik::i32() { return nastepna(90).i; }

int64_t Czytnik::i64() {
    const uint64_t hi = static_cast<uint32_t>(i32());
    const uint64_t lo = static_cast<uint32_t>(i32());
    return static_cast<int64_t>((hi << 32) | lo);
}

double Czytnik::real() { return nastepna(40).d; }

std::string Czytnik::bajty() {
    const int32_t n = i32();
    if (n < 0) throw Blad("XRecord uszkodzony: ujemna długość");
    std::string b;
    b.reserve(static_cast<size_t>(n));
    while (b.size() < static_cast<size_t>(n)) {
        const Para& p = nastepna(310);
        if (p.s.empty() || p.s.size() > PORCJA_BAJTOW) throw Blad("XRecord uszkodzony: zła porcja bajtów");
        b += p.s;
    }
    if (b.size() != static_cast<size_t>(n)) throw Blad("XRecord uszkodzony: porcje dłuższe niż zapowiedziano");
    return b;
}

Wartosc Czytnik::wartosc() {
    const int16_t k = i16();
    switch (static_cast<Klasa>(k)) {
        case Klasa::Null: return Wartosc::null_();
        case Klasa::Calk: return Wartosc::calk(i64());
        case Klasa::Rzecz: {
            const std::string b = bajty();
            if (b.size() != 8) throw Blad("XRecord uszkodzony: liczba rzeczywista nie ma 8 bajtów");
            uint64_t v = 0;
            for (int i = 0; i < 8; ++i) v |= static_cast<uint64_t>(static_cast<unsigned char>(b[static_cast<size_t>(i)])) << (8 * i);
            double d;
            std::memcpy(&d, &v, 8);
            return Wartosc::rzecz(d);
        }
        case Klasa::Tekst: return Wartosc::tekst(bajty());
        case Klasa::Blob: return Wartosc::blob(bajty());
    }
    throw Blad("XRecord uszkodzony: nieznana klasa wartości " + std::to_string(k));
}

}  // namespace wfcad
