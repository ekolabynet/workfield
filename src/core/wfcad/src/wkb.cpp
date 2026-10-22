// wkb.cpp — patrz wkb.hpp.
#include "wfcad/wkb.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <utility>

namespace wfcad {

namespace {

bool hostLE() {
    const uint16_t x = 1;
    uint8_t b;
    std::memcpy(&b, &x, 1);
    return b == 1;
}

template <typename T>
T czytaj(const std::string& s, size_t& poz, uint8_t porzadek) {
    if (poz + sizeof(T) > s.size()) throw Blad("WKB urwane w pozycji " + std::to_string(poz));
    T v;
    unsigned char b[sizeof(T)];
    std::memcpy(b, s.data() + poz, sizeof(T));
    if ((porzadek == 1) != hostLE()) {
        for (size_t i = 0; i < sizeof(T) / 2; ++i) std::swap(b[i], b[sizeof(T) - 1 - i]);
    }
    std::memcpy(&v, b, sizeof(T));
    poz += sizeof(T);
    return v;
}

template <typename T>
void pisz(std::string& out, T v, uint8_t porzadek) {
    unsigned char b[sizeof(T)];
    std::memcpy(b, &v, sizeof(T));
    if ((porzadek == 1) != hostLE()) {
        for (size_t i = 0; i < sizeof(T) / 2; ++i) std::swap(b[i], b[sizeof(T) - 1 - i]);
    }
    out.append(reinterpret_cast<const char*>(b), sizeof(T));
}

void rozbierzKod(Geometria& g) {
    uint32_t k = g.kod;
    g.z = (k & 0x80000000u) != 0;
    g.m = (k & 0x40000000u) != 0;
    g.maSrid = (k & 0x20000000u) != 0;
    uint32_t baza = k & 0x1FFFFFFFu;
    uint32_t iso = baza / 1000;
    baza %= 1000;
    if (iso == 1 || iso == 3) g.z = true;
    if (iso == 2 || iso == 3) g.m = true;
    if (iso > 3) throw Nieobslugiwane("nieznany kod typu WKB " + std::to_string(k));
    if (baza < 1 || baza > 7)
        throw Nieobslugiwane("rodzaj geometrii WKB " + std::to_string(baza) +
                             " (krzywe, TIN, powierzchnie) — jeszcze nieobsługiwany");
    g.rodzaj = static_cast<int>(baza);
}

std::vector<Wierzcholek> czytajCiag(const std::string& s, size_t& poz, const Geometria& g, uint32_t n) {
    // Ochrona przed uszkodzonym licznikiem: nie rezerwuj więcej, niż zmieści bufor.
    const size_t naWierzcholek = 8u * (2 + g.z + g.m);
    if (n > (s.size() - poz) / naWierzcholek + 1) throw Blad("WKB: licznik wierzchołków większy niż dane");
    std::vector<Wierzcholek> w(n);
    for (auto& v : w) {
        v.x = czytaj<double>(s, poz, g.porzadek);
        v.y = czytaj<double>(s, poz, g.porzadek);
        if (g.z) v.z = czytaj<double>(s, poz, g.porzadek);
        if (g.m) v.m = czytaj<double>(s, poz, g.porzadek);
    }
    return w;
}

Geometria czytajRek(const std::string& s, size_t& poz, int glebokosc) {
    if (glebokosc > 32) throw Blad("WKB: zbyt głębokie zagnieżdżenie");
    if (poz >= s.size()) throw Blad("WKB urwane");
    Geometria g;
    g.porzadek = static_cast<uint8_t>(s[poz]);
    if (g.porzadek > 1) throw Blad("WKB: zły znacznik kolejności bajtów");
    ++poz;
    g.kod = czytaj<uint32_t>(s, poz, g.porzadek);
    rozbierzKod(g);
    if (g.maSrid) g.srid = czytaj<uint32_t>(s, poz, g.porzadek);

    switch (g.rodzaj) {
        case PUNKT:
            g.pierscienie.push_back(czytajCiag(s, poz, g, 1));
            break;
        case LINIA: {
            uint32_t n = czytaj<uint32_t>(s, poz, g.porzadek);
            g.pierscienie.push_back(czytajCiag(s, poz, g, n));
            break;
        }
        case POLIGON: {
            uint32_t r = czytaj<uint32_t>(s, poz, g.porzadek);
            if (r > s.size()) throw Blad("WKB: licznik pierścieni większy niż dane");
            for (uint32_t i = 0; i < r; ++i) {
                uint32_t n = czytaj<uint32_t>(s, poz, g.porzadek);
                g.pierscienie.push_back(czytajCiag(s, poz, g, n));
            }
            break;
        }
        default: {
            uint32_t n = czytaj<uint32_t>(s, poz, g.porzadek);
            if (n > s.size()) throw Blad("WKB: licznik części większy niż dane");
            for (uint32_t i = 0; i < n; ++i) g.czesci.push_back(czytajRek(s, poz, glebokosc + 1));
        }
    }
    return g;
}

void piszCiag(std::string& out, const Geometria& g, const std::vector<Wierzcholek>& w) {
    for (const auto& v : w) {
        pisz(out, v.x, g.porzadek);
        pisz(out, v.y, g.porzadek);
        if (g.z) pisz(out, v.z, g.porzadek);
        if (g.m) pisz(out, v.m, g.porzadek);
    }
}

void piszRek(std::string& out, const Geometria& g) {
    out.push_back(static_cast<char>(g.porzadek));
    pisz(out, g.kod, g.porzadek);
    if (g.maSrid) pisz(out, g.srid, g.porzadek);
    switch (g.rodzaj) {
        case PUNKT:
            if (g.pierscienie.size() != 1 || g.pierscienie[0].size() != 1)
                throw Blad("punkt musi mieć dokładnie jeden wierzchołek");
            piszCiag(out, g, g.pierscienie[0]);
            break;
        case LINIA:
            if (g.pierscienie.size() != 1) throw Blad("linia musi mieć jeden ciąg");
            pisz(out, static_cast<uint32_t>(g.pierscienie[0].size()), g.porzadek);
            piszCiag(out, g, g.pierscienie[0]);
            break;
        case POLIGON:
            pisz(out, static_cast<uint32_t>(g.pierscienie.size()), g.porzadek);
            for (const auto& r : g.pierscienie) {
                pisz(out, static_cast<uint32_t>(r.size()), g.porzadek);
                piszCiag(out, g, r);
            }
            break;
        default:
            pisz(out, static_cast<uint32_t>(g.czesci.size()), g.porzadek);
            for (const auto& c : g.czesci) piszRek(out, c);
    }
}

void zbierzObwiednie(const Geometria& g, bool zZ, bool zM, std::vector<double>& o, bool& jest) {
    for (const auto& r : g.pierscienie)
        for (const auto& v : r) {
            if (std::isnan(v.x) || std::isnan(v.y)) continue;
            if (!jest) {
                o = {v.x, v.x, v.y, v.y};
                if (zZ) { o.push_back(v.z); o.push_back(v.z); }
                if (zM) { o.push_back(v.m); o.push_back(v.m); }
                jest = true;
                continue;
            }
            o[0] = std::min(o[0], v.x); o[1] = std::max(o[1], v.x);
            o[2] = std::min(o[2], v.y); o[3] = std::max(o[3], v.y);
            size_t k = 4;
            if (zZ) { o[k] = std::min(o[k], v.z); o[k + 1] = std::max(o[k + 1], v.z); k += 2; }
            if (zM) { o[k] = std::min(o[k], v.m); o[k + 1] = std::max(o[k + 1], v.m); }
        }
    for (const auto& c : g.czesci) zbierzObwiednie(c, zZ, zM, o, jest);
}

}  // namespace

Geometria czytajWkb(const std::string& wkb) {
    size_t poz = 0;
    Geometria g = czytajRek(wkb, poz, 0);
    if (poz != wkb.size())
        throw Blad("WKB: " + std::to_string(wkb.size() - poz) + " bajtów nadmiaru po geometrii");
    return g;
}

std::string piszWkb(const Geometria& g) {
    std::string out;
    piszRek(out, g);
    return out;
}

std::vector<double> obwiednia(const Geometria& g, bool zZ, bool zM) {
    std::vector<double> o;
    bool jest = false;
    zbierzObwiednie(g, zZ, zM, o, jest);
    return o;
}

void ustawZKodu(Geometria& g) { rozbierzKod(g); }

bool czyPusta(const Geometria& g) {
    if (g.rodzaj == PUNKT) {
        const auto& v = g.pierscienie[0][0];
        return std::isnan(v.x) && std::isnan(v.y);
    }
    if (g.rodzaj == LINIA || g.rodzaj == POLIGON) {
        for (const auto& r : g.pierscienie)
            if (!r.empty()) return false;
        return true;
    }
    for (const auto& c : g.czesci)
        if (!czyPusta(c)) return false;
    return true;
}

const char* nazwaRodzaju(int r) {
    switch (r) {
        case PUNKT: return "POINT";
        case LINIA: return "LINESTRING";
        case POLIGON: return "POLYGON";
        case WIELOPUNKT: return "MULTIPOINT";
        case WIELOLINIA: return "MULTILINESTRING";
        case WIELOPOLIGON: return "MULTIPOLYGON";
        case KOLEKCJA: return "GEOMETRYCOLLECTION";
    }
    return "?";
}

// --- GeoPackageBinary -------------------------------------------------------

namespace {
int liczbObwiedni(uint8_t flagi) {
    switch ((flagi >> 1) & 0x07) {
        case 0: return 0;
        case 1: return 4;
        case 2: case 3: return 6;
        case 4: return 8;
    }
    return -1;
}
}  // namespace

Gpb czytajGpb(const std::string& b) {
    if (b.size() < 8 || b[0] != 'G' || b[1] != 'P') throw Blad("blob geometrii bez nagłówka GP");
    Gpb g;
    g.wersja = static_cast<uint8_t>(b[2]);
    g.flagi = static_cast<uint8_t>(b[3]);
    if (g.flagi & 0x20) throw Nieobslugiwane("rozszerzony GeoPackageBinary (bit X) — nieobsługiwany");
    const uint8_t porz = g.flagi & 1;
    size_t poz = 4;
    g.srs = czytaj<int32_t>(b, poz, porz);
    const int n = liczbObwiedni(g.flagi);
    if (n < 0) throw Blad("blob geometrii: zły wskaźnik obwiedni");
    for (int i = 0; i < n; ++i) g.obwiednia.push_back(czytaj<double>(b, poz, porz));
    g.pusta = (g.flagi & 0x10) != 0;
    g.naglowek = b.substr(0, poz);
    g.wkb = b.substr(poz);
    return g;
}

std::string budujGpb(const Gpb& wzor, const Geometria& g) {
    const uint8_t porz = wzor.flagi & 1;
    const int wsk = (wzor.flagi >> 1) & 0x07;
    const bool pusta = czyPusta(g);
    uint8_t flagi = static_cast<uint8_t>(wzor.flagi & ~0x10);
    if (pusta) flagi |= 0x10;

    std::string out;
    out.push_back('G');
    out.push_back('P');
    out.push_back(static_cast<char>(wzor.wersja));
    out.push_back(static_cast<char>(flagi));
    pisz(out, wzor.srs, porz);
    if (wsk != 0) {
        const bool zZ = (wsk == 2 || wsk == 4);
        const bool zM = (wsk == 3 || wsk == 4);
        std::vector<double> o = obwiednia(g, zZ, zM);
        const size_t n = static_cast<size_t>(liczbObwiedni(flagi));
        if (o.size() != n) o.assign(n, std::numeric_limits<double>::quiet_NaN());
        for (double v : o) pisz(out, v, porz);
    }
    out += piszWkb(g);
    return out;
}

}  // namespace wfcad
