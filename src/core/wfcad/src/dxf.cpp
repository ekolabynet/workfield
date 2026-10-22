// dxf.cpp — patrz dxf.hpp.
#include "wfcad/dxf.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <map>
#include <set>
#include <utility>
#include <vector>

#include "wfcad/skrot.hpp"

namespace wfcad {

namespace {

#include "szablon_dxf.inc"

struct ParaDxf {
    int kod = 0;
    std::string s;          // tekst; dla danych binarnych — szesnastkowo
    double d = 0;           // liczba z DXF binarnego (dokładna)
    bool maD = false;
};

std::string przytnij(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && (s[a] == ' ' || s[a] == '\t' || s[a] == '\r')) ++a;
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r')) --b;
    return s.substr(a, b - a);
}

double liczba(const ParaDxf& p) {
    if (p.maD) return p.d;
    const std::string t = przytnij(p.s);
    char* k = nullptr;
    const double v = std::strtod(t.c_str(), &k);
    if (t.empty() || *k != '\0') throw Blad("DXF: „" + t + "” nie jest liczbą (kod " + std::to_string(p.kod) + ")");
    return v;
}

long long calkowita(const ParaDxf& p) {
    if (p.maD) return static_cast<long long>(p.d);
    const std::string t = przytnij(p.s);
    char* k = nullptr;
    const long long v = std::strtoll(t.c_str(), &k, 10);
    if (t.empty() || *k != '\0') throw Blad("DXF: „" + t + "” nie jest liczbą całkowitą (kod " + std::to_string(p.kod) + ")");
    return v;
}

std::string doHex(const std::string& b) {
    static const char* h = "0123456789ABCDEF";
    std::string w;
    w.reserve(b.size() * 2);
    for (unsigned char c : b) {
        w += h[c >> 4];
        w += h[c & 0xF];
    }
    return w;
}

std::string zHex(const std::string& t) {
    const std::string s = przytnij(t);
    if (s.size() % 2) throw Blad("DXF: dane binarne o nieparzystej długości");
    auto cyfra = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        throw Blad("DXF: zły znak w danych binarnych");
    };
    std::string b(s.size() / 2, '\0');
    for (size_t i = 0; i < b.size(); ++i) b[i] = static_cast<char>(cyfra(s[2 * i]) * 16 + cyfra(s[2 * i + 1]));
    return b;
}

// --- tokenizacja -----------------------------------------------------------------

const char WARTOWNIK_BIN[] = "AutoCAD Binary DXF\r\n\x1a";   // + \0 = 22 bajty

std::vector<ParaDxf> paryTekstu(const std::string& t) {
    std::vector<ParaDxf> w;
    size_t poz = 0;
    if (t.size() >= 3 && static_cast<unsigned char>(t[0]) == 0xEF && static_cast<unsigned char>(t[1]) == 0xBB &&
        static_cast<unsigned char>(t[2]) == 0xBF)
        poz = 3;     // BOM UTF-8
    auto linia = [&](std::string& l) -> bool {
        if (poz >= t.size()) return false;
        size_t k = t.find('\n', poz);
        if (k == std::string::npos) k = t.size();
        l = t.substr(poz, k - poz);
        if (!l.empty() && l.back() == '\r') l.pop_back();
        poz = k + 1;
        return true;
    };
    std::string a, b;
    size_t nr = 0;
    while (linia(a)) {
        ++nr;
        if (przytnij(a).empty() && poz >= t.size()) break;
        if (!linia(b)) throw Blad("DXF urwany po kodzie w linii " + std::to_string(nr));
        ParaDxf p;
        const std::string k = przytnij(a);
        char* e = nullptr;
        p.kod = static_cast<int>(std::strtol(k.c_str(), &e, 10));
        if (k.empty() || *e != '\0') throw Blad("DXF: w linii " + std::to_string(nr) + " oczekiwano kodu grupy, jest „" + k + "”");
        p.s = b;
        w.push_back(std::move(p));
        if (w.back().kod == 0 && przytnij(w.back().s) == "EOF") break;
        ++nr;
    }
    return w;
}

enum class TypWart { Tekst, Real, I16, I32, I64, Bool, Bin };

TypWart typKodu(int k) {
    if ((k >= 10 && k <= 59) || (k >= 110 && k <= 149) || (k >= 210 && k <= 239) || (k >= 460 && k <= 469) ||
        (k >= 1010 && k <= 1059))
        return TypWart::Real;
    if ((k >= 60 && k <= 79) || (k >= 170 && k <= 179) || (k >= 270 && k <= 289) || (k >= 370 && k <= 389) ||
        (k >= 400 && k <= 409) || (k >= 1060 && k <= 1070))
        return TypWart::I16;
    if ((k >= 90 && k <= 99) || (k >= 420 && k <= 429) || (k >= 440 && k <= 459) || k == 1071) return TypWart::I32;
    if (k >= 160 && k <= 169) return TypWart::I64;
    if (k >= 290 && k <= 299) return TypWart::Bool;
    if ((k >= 310 && k <= 319) || k == 1004) return TypWart::Bin;
    return TypWart::Tekst;
}

std::vector<ParaDxf> paryBinarne(const std::string& t) {
    std::vector<ParaDxf> w;
    size_t poz = 22;
    auto potrzeba = [&](size_t n) {
        if (poz + n > t.size()) throw Blad("DXF binarny urwany");
    };
    auto le = [&](size_t n) {
        potrzeba(n);
        uint64_t v = 0;
        for (size_t i = 0; i < n; ++i) v |= static_cast<uint64_t>(static_cast<unsigned char>(t[poz + i])) << (8 * i);
        poz += n;
        return v;
    };
    while (poz < t.size()) {
        ParaDxf p;
        p.kod = static_cast<int>(le(2));
        switch (typKodu(p.kod)) {
            case TypWart::Real: {
                uint64_t v = le(8);
                std::memcpy(&p.d, &v, 8);
                p.maD = true;
                break;
            }
            case TypWart::I16: p.s = std::to_string(static_cast<int16_t>(le(2))); break;
            case TypWart::I32: p.s = std::to_string(static_cast<int32_t>(le(4))); break;
            case TypWart::I64: p.s = std::to_string(static_cast<int64_t>(le(8))); break;
            case TypWart::Bool: p.s = std::to_string(le(1)); break;
            case TypWart::Bin: {
                const size_t n = static_cast<size_t>(le(1));
                potrzeba(n);
                p.s = doHex(t.substr(poz, n));
                poz += n;
                break;
            }
            case TypWart::Tekst: {
                const size_t k = t.find('\0', poz);
                if (k == std::string::npos) throw Blad("DXF binarny: tekst bez zakończenia");
                p.s = t.substr(poz, k - poz);
                poz = k + 1;
            }
        }
        w.push_back(std::move(p));
        if (w.back().kod == 0 && w.back().s == "EOF") break;
    }
    return w;
}

std::string czytajPlik(const std::string& sciezka) {
    std::ifstream f(sciezka, std::ios::binary);
    if (!f) throw Blad("nie mogę otworzyć " + sciezka);
    return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

bool czyBinarny(const std::string& t) {
    return t.size() >= 22 && std::memcmp(t.data(), WARTOWNIK_BIN, 21) == 0 && t[21] == '\0';
}

// --- zapis ------------------------------------------------------------------------

class Wyjscie {
public:
    std::string t;
    void para(int kod, const std::string& v) {
        char b[16];
        std::snprintf(b, sizeof b, "%3d\n", kod);
        t += b;
        t += v;
        t += '\n';
    }
    void liczba(int kod, double v) {
        if (!std::isfinite(v)) throw Blad("DXF: liczba nieskończona albo NaN w kodzie " + std::to_string(kod));
        char b[40];
        std::snprintf(b, sizeof b, "%.17g", v);
        para(kod, b);
    }
    void calk(int kod, long long v) { para(kod, std::to_string(v)); }
};

class Uchwyty {
public:
    explicit Uchwyty(unsigned long long start) : n_(start) {}
    std::string nowy() { return hex(n_++); }
    unsigned long long nastepny() const { return n_; }
    static std::string hex(unsigned long long v) {
        char b[24];
        std::snprintf(b, sizeof b, "%llX", v);
        return b;
    }
private:
    unsigned long long n_;
};

void piszListe(Wyjscie& o, const Lista& l) {
    for (const auto& p : l) {
        switch (p.kod) {
            case 1: o.para(1, p.s); break;
            case 70: case 90: o.calk(p.kod, p.i); break;
            case 40: o.liczba(40, p.d); break;
            case 310: o.para(310, doHex(p.s)); break;
            default: throw Blad("XRecord: kod " + std::to_string(p.kod) + " nie należy do formatu WF");
        }
    }
}

std::string guid() {
    std::string u = nowyUuid();
    std::transform(u.begin(), u.end(), u.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    return "{" + u + "}";
}

struct Szablon {
    std::vector<ParaDxf> pary;
    std::string tabelaWarstw, przestrzenModelu, slownikGlowny, stylWydruku, material;
    unsigned long long ziarno = 0;
};

Szablon wczytajSzablon() {
    std::string t;
    for (const char* k : SZABLON_DXF) t += k;
    Szablon s;
    s.pary = paryTekstu(t);
    const auto& p = s.pary;
    std::string sekcja, typObiektu;
    bool pierwszyWObjects = false;
    for (size_t i = 0; i + 1 < p.size(); ++i) {
        if (p[i].kod == 0) typObiektu = p[i].s;
        if (p[i].kod == 0 && p[i].s == "SECTION") sekcja = p[i + 1].s;
        if (p[i].kod == 9 && p[i].s == "$HANDSEED") s.ziarno = std::stoull(przytnij(p[i + 1].s), nullptr, 16);
        if (p[i].kod == 0 && p[i].s == "TABLE" && p[i + 1].s == "LAYER" && i + 2 < p.size() && p[i + 2].kod == 5)
            s.tabelaWarstw = p[i + 2].s;
        if (p[i].kod == 2 && p[i].s == "*Model_Space" && typObiektu == "BLOCK_RECORD") {
            for (size_t j = i; j-- > 0;)
                if (p[j].kod == 5) { s.przestrzenModelu = p[j].s; break; }
        }
        if (p[i].kod == 2 && p[i].s == "0" && typObiektu == "LAYER") {
            for (size_t j = i; j < p.size() && p[j].kod != 0; ++j) {
                if (p[j].kod == 390) s.stylWydruku = p[j].s;
                if (p[j].kod == 347) s.material = p[j].s;
            }
        }
        if (p[i].kod == 2 && p[i].s == "OBJECTS") pierwszyWObjects = true;
        if (pierwszyWObjects && p[i].kod == 0 && p[i].s == "DICTIONARY" && p[i + 1].kod == 5) {
            s.slownikGlowny = p[i + 1].s;
            pierwszyWObjects = false;
        }
    }
    if (s.tabelaWarstw.empty() || s.przestrzenModelu.empty() || s.slownikGlowny.empty() || !s.ziarno)
        throw Blad("szablon DXF niekompletny — zbuduj go od nowa narzedzia/zbuduj_szablon_dxf.py");
    return s;
}

}  // namespace

void zapiszDxf(const Rysunek& rys, const std::string& sciezka) {
    const Szablon sz = wczytajSzablon();
    Uchwyty u(std::max<unsigned long long>(sz.ziarno, 0x100));

    // Warstwy.
    std::set<std::string> nazwy;
    for (const auto& e : rys.encje)
        if (e.warstwaCad != "0") nazwy.insert(e.warstwaCad);
    Wyjscie warstwy;
    for (const auto& n : nazwy) {
        warstwy.para(0, "LAYER");
        warstwy.para(5, u.nowy());
        warstwy.para(330, sz.tabelaWarstw);
        warstwy.para(100, "AcDbSymbolTableRecord");
        warstwy.para(100, "AcDbLayerTableRecord");
        warstwy.para(2, n);
        warstwy.calk(70, 0);
        warstwy.calk(62, 7);
        warstwy.para(6, "Continuous");
        warstwy.calk(370, -3);
        if (!sz.stylWydruku.empty()) warstwy.para(390, sz.stylWydruku);
        if (!sz.material.empty()) warstwy.para(347, sz.material);
    }

    // Obiekty rysunku i ich słowniki rozszerzeń.
    Wyjscie ent, obj;
    auto slownikRozszerzen = [&](const std::string& wlasciciel, const std::string& xd, const Lista& dane) {
        const std::string xr = u.nowy();
        obj.para(0, "DICTIONARY");
        obj.para(5, xd);
        obj.para(102, "{ACAD_REACTORS");
        obj.para(330, wlasciciel);
        obj.para(102, "}");
        obj.para(330, wlasciciel);
        obj.para(100, "AcDbDictionary");
        obj.calk(280, 1);
        obj.calk(281, 1);
        obj.para(3, "WF");
        obj.para(350, xr);
        obj.para(0, "XRECORD");
        obj.para(5, xr);
        obj.para(102, "{ACAD_REACTORS");
        obj.para(330, xd);
        obj.para(102, "}");
        obj.para(330, xd);
        obj.para(100, "AcDbXrecord");
        obj.calk(280, 1);
        piszListe(obj, dane);
    };
    auto naglowek = [&](const char* typ, const std::string& h, const std::string& xd, const Encja& e) {
        ent.para(0, typ);
        ent.para(5, h);
        if (!xd.empty()) {
            ent.para(102, "{ACAD_XDICTIONARY");
            ent.para(360, xd);
            ent.para(102, "}");
        }
        ent.para(330, sz.przestrzenModelu);
        ent.para(100, "AcDbEntity");
        ent.para(8, e.warstwaCad.empty() ? "0" : e.warstwaCad);
    };

    for (const auto& e : rys.encje) {
        const std::string h = u.nowy();
        const std::string xd = e.dane.empty() ? std::string() : u.nowy();
        switch (e.rodzaj) {
            case RodzajEncji::Punkt: {
                if (e.punkty.size() != 1) throw Blad("DXF: punkt bez jednej pozycji");
                naglowek("POINT", h, xd, e);
                ent.para(100, "AcDbPoint");
                ent.liczba(10, e.punkty[0].x);
                ent.liczba(20, e.punkty[0].y);
                ent.liczba(30, e.punkty[0].z);
                break;
            }
            case RodzajEncji::Polilinia: {
                naglowek("LWPOLYLINE", h, xd, e);
                ent.para(100, "AcDbPolyline");
                ent.calk(90, static_cast<long long>(e.punkty.size()));
                ent.calk(70, e.zamknieta ? 1 : 0);
                ent.liczba(38, e.elewacja);
                for (const auto& p : e.punkty) {
                    ent.liczba(10, p.x);
                    ent.liczba(20, p.y);
                }
                break;
            }
            case RodzajEncji::Polilinia3d: {
                naglowek("POLYLINE", h, xd, e);
                ent.para(100, "AcDb3dPolyline");
                ent.calk(66, 1);
                ent.liczba(10, 0);
                ent.liczba(20, 0);
                ent.liczba(30, 0);
                ent.calk(70, 8 | (e.zamknieta ? 1 : 0));
                for (const auto& p : e.punkty) {
                    ent.para(0, "VERTEX");
                    ent.para(5, u.nowy());
                    ent.para(330, h);
                    ent.para(100, "AcDbEntity");
                    ent.para(8, e.warstwaCad.empty() ? "0" : e.warstwaCad);
                    ent.para(100, "AcDbVertex");
                    ent.para(100, "AcDb3dPolylineVertex");
                    ent.liczba(10, p.x);
                    ent.liczba(20, p.y);
                    ent.liczba(30, p.z);
                    ent.calk(70, 32);
                }
                ent.para(0, "SEQEND");
                ent.para(5, u.nowy());
                ent.para(330, h);
                ent.para(100, "AcDbEntity");
                ent.para(8, e.warstwaCad.empty() ? "0" : e.warstwaCad);
                break;
            }
            case RodzajEncji::MPolygon:
                throw Blad("DXF: MPOLYGON nie jest zapisywany — zbuduj rysunek z poligonami jako polilinie");
        }
        if (!xd.empty()) slownikRozszerzen(h, xd, e.dane);
    }

    // Słownik WORKFIELD w słowniku głównym.
    const std::string wf = rys.slownik.empty() ? std::string() : u.nowy();
    if (!wf.empty()) {
        std::vector<std::pair<std::string, std::string>> wpisy;
        for (const auto& [k, l] : rys.slownik) wpisy.push_back({k, u.nowy()});
        obj.para(0, "DICTIONARY");
        obj.para(5, wf);
        obj.para(102, "{ACAD_REACTORS");
        obj.para(330, sz.slownikGlowny);
        obj.para(102, "}");
        obj.para(330, sz.slownikGlowny);
        obj.para(100, "AcDbDictionary");
        obj.calk(281, 1);
        for (const auto& [k, h] : wpisy) {
            obj.para(3, k);
            obj.para(350, h);
        }
        size_t i = 0;
        for (const auto& [k, l] : rys.slownik) {
            const std::string& h = wpisy[i++].second;
            obj.para(0, "XRECORD");
            obj.para(5, h);
            obj.para(102, "{ACAD_REACTORS");
            obj.para(330, wf);
            obj.para(102, "}");
            obj.para(330, wf);
            obj.para(100, "AcDbXrecord");
            obj.calk(280, 1);
            piszListe(obj, l);
        }
    }

    // Widok przy otwarciu (22.10, Piotr: „problem z szukaniem obiektów”): szablon
    // otwierał się na (0, 0) z wysokością 1000 m, obwiednia w nagłówku była pusta
    // (1e20), a punkty rysowały się jako kropka (PDMODE 0). Dane w PL-2000 leżą
    // 5–8 mln m dalej. Teraz: obwiednia i granice = dane, widok na danych,
    // punkty jako kółko z krzyżykiem 1,5% wysokości ekranu (PDSIZE < 0 — przy
    // każdym powiększeniu tak samo widoczne). To ustawienia rysunku, nie dane GIS.
    bool saDane = false;
    double mnx = 0, mny = 0, mnz = 0, mxx = 0, mxy = 0, mxz = 0;
    for (const auto& e : rys.encje)
        for (const auto& q : e.punkty) {
            if (!std::isfinite(q.x) || !std::isfinite(q.y) || !std::isfinite(q.z)) continue;
            if (!saDane) { mnx = mxx = q.x; mny = mxy = q.y; mnz = mxz = q.z; saDane = true; continue; }
            mnx = std::min(mnx, q.x); mxx = std::max(mxx, q.x);
            mny = std::min(mny, q.y); mxy = std::max(mxy, q.y);
            mnz = std::min(mnz, q.z); mxz = std::max(mxz, q.z);
        }
    double proporcja = 0;   // 41 w VPORT *Active szablonu
    for (size_t i = 0; i + 1 < sz.pary.size(); ++i)
        if (sz.pary[i].kod == 2 && przytnij(sz.pary[i].s) == "*Active")
            for (size_t j = i; j < sz.pary.size() && sz.pary[j].kod != 0; ++j)
                if (sz.pary[j].kod == 41) proporcja = liczba(sz.pary[j]);
    if (!(proporcja > 0)) proporcja = 1.0;
    const double wysokoscWidoku = std::max(10.0, 1.1 * std::max(mxy - mny, (mxx - mnx) / proporcja));

    // Szablon z wstawkami.
    Wyjscie o;
    std::string sekcja, tabela, zmienna, rekord;
    bool wSlownikuGlownym = false, pierwszyObiekt = false;
    const auto& p = sz.pary;
    for (size_t i = 0; i < p.size(); ++i) {
        const ParaDxf& x = p[i];
        if (x.kod == 0) {
            if (wSlownikuGlownym) {
                if (!wf.empty()) {
                    o.para(3, "WORKFIELD");
                    o.para(350, wf);
                }
                wSlownikuGlownym = false;
            }
            if (x.s == "ENDTAB" && tabela == "LAYER") o.t += warstwy.t;
            if (x.s == "ENDSEC" && sekcja == "ENTITIES") o.t += ent.t;
            if (x.s == "ENDSEC" && sekcja == "OBJECTS") o.t += obj.t;
            if (pierwszyObiekt && x.s == "DICTIONARY") {
                wSlownikuGlownym = true;
                pierwszyObiekt = false;
            }
        }
        if (x.kod == 2 && i > 0 && p[i - 1].kod == 0 && p[i - 1].s == "SECTION") {
            sekcja = x.s;
            pierwszyObiekt = sekcja == "OBJECTS";
        }
        if (x.kod == 2 && i > 0 && p[i - 1].kod == 0 && p[i - 1].s == "TABLE") tabela = x.s;
        if (x.kod == 0 && x.s == "ENDTAB") tabela.clear();
        if (x.kod == 0) rekord.clear();
        if (x.kod == 2 && tabela == "VPORT") rekord = przytnij(x.s);
        if (x.kod == 9) zmienna = przytnij(x.s);
        if (x.kod == 0) zmienna.clear();

        if (saDane && sekcja == "HEADER") {
            const bool mn = zmienna == "$EXTMIN" || zmienna == "$LIMMIN";
            const bool mx = zmienna == "$EXTMAX" || zmienna == "$LIMMAX";
            if ((mn || mx) && (x.kod == 10 || x.kod == 20 || x.kod == 30)) {
                o.liczba(x.kod, x.kod == 10 ? (mn ? mnx : mxx) : x.kod == 20 ? (mn ? mny : mxy) : (mn ? mnz : mxz));
                continue;
            }
            if (zmienna == "$PDMODE" && x.kod == 70) { o.calk(70, 34); continue; }
            if (zmienna == "$PDSIZE" && x.kod == 40) { o.liczba(40, -1.5); continue; }
        }
        if (saDane && tabela == "VPORT" && rekord == "*Active") {
            if (x.kod == 12) { o.liczba(12, (mnx + mxx) / 2); continue; }
            if (x.kod == 22) { o.liczba(22, (mny + mxy) / 2); continue; }
            if (x.kod == 40) { o.liczba(40, wysokoscWidoku); continue; }
        }

        if (i > 0 && p[i - 1].kod == 9) {
            const std::string& zm = p[i - 1].s;
            if (zm == "$HANDSEED") { o.para(x.kod, Uchwyty::hex(u.nastepny())); continue; }
            if (zm == "$FINGERPRINTGUID" || zm == "$VERSIONGUID") { o.para(x.kod, guid()); continue; }
            if (zm == "$LASTSAVEDBY") { o.para(x.kod, "WorkFieldCAD"); continue; }
        }
        o.para(x.kod, x.s);
    }

    std::ofstream f(sciezka, std::ios::binary | std::ios::trunc);
    if (!f) throw Blad("nie mogę zapisać " + sciezka);
    f.write(o.t.data(), static_cast<std::streamsize>(o.t.size()));
    if (!f) throw Blad("błąd zapisu " + sciezka);
}

// --- odczyt -----------------------------------------------------------------------

namespace {

using Obiekty = std::vector<std::vector<ParaDxf>>;

Obiekty podziel(const std::vector<ParaDxf>& p, size_t od, size_t do_) {
    Obiekty w;
    for (size_t i = od; i < do_; ++i) {
        if (p[i].kod == 0) w.emplace_back();
        if (!w.empty()) w.back().push_back(p[i]);
    }
    return w;
}

std::string wartosc(const std::vector<ParaDxf>& o, int kod) {
    for (const auto& x : o)
        if (x.kod == kod) return x.s;
    return {};
}

std::string slownikRozszerzen(const std::vector<ParaDxf>& o) {
    for (size_t i = 0; i + 1 < o.size(); ++i)
        if (o[i].kod == 102 && przytnij(o[i].s) == "{ACAD_XDICTIONARY" && o[i + 1].kod == 360)
            return przytnij(o[i + 1].s);
    return {};
}

std::map<std::string, std::string> wpisySlownika(const std::vector<ParaDxf>& o) {
    std::map<std::string, std::string> w;
    for (size_t i = 0; i + 1 < o.size(); ++i)
        if (o[i].kod == 3 && (o[i + 1].kod == 350 || o[i + 1].kod == 360)) w[o[i].s] = przytnij(o[i + 1].s);
    return w;
}

Lista listaXrecord(const std::vector<ParaDxf>& o) {
    size_t i = 0;
    while (i < o.size() && !(o[i].kod == 100 && przytnij(o[i].s) == "AcDbXrecord")) ++i;
    if (i == o.size()) throw Blad("XRECORD bez znacznika AcDbXrecord");
    ++i;
    if (i < o.size() && o[i].kod == 280) ++i;   // flaga klonowania
    Lista l;
    for (; i < o.size(); ++i) {
        Para p;
        p.kod = o[i].kod;
        switch (p.kod) {
            case 1: p.s = o[i].s; break;
            case 70: case 90: p.i = static_cast<int32_t>(calkowita(o[i])); break;
            case 40: p.d = liczba(o[i]); break;
            case 310: p.s = zHex(o[i].s); break;
            default:
                throw Blad("XRECORD: nieoczekiwany kod " + std::to_string(p.kod) + " — CAD zmienił dane WorkField?");
        }
        l.push_back(std::move(p));
    }
    return l;
}

}  // namespace

bool czyDxf(const std::string& sciezka) {
    std::ifstream f(sciezka, std::ios::binary);
    char b[64] = {};
    f.read(b, sizeof b);
    const std::string t(b, static_cast<size_t>(f.gcount()));
    if (czyBinarny(t)) return true;
    if (t.rfind("WFR1", 0) == 0) return false;
    // Tekstowy: pierwsza para to „0” / „SECTION” (dopuszczalny BOM i odstępy).
    size_t i = t.find_first_not_of(" \t\r\n\xEF\xBB\xBF");
    return i != std::string::npos && t[i] == '0' && t.find("SECTION") != std::string::npos;
}

Rysunek wczytajDxf(const std::string& sciezka, Raport& raport) {
    const std::string t = czytajPlik(sciezka);
    const bool bin = czyBinarny(t);
    const std::vector<ParaDxf> p = bin ? paryBinarne(t) : paryTekstu(t);

    // Sekcje.
    std::map<std::string, std::pair<size_t, size_t>> sekcje;
    for (size_t i = 0; i + 1 < p.size(); ++i)
        if (p[i].kod == 0 && przytnij(p[i].s) == "SECTION" && p[i + 1].kod == 2) {
            size_t k = i + 2;
            while (k < p.size() && !(p[k].kod == 0 && przytnij(p[k].s) == "ENDSEC")) ++k;
            sekcje[przytnij(p[i + 1].s)] = {i + 2, k};
            i = k;
        }
    std::string wersja;
    if (sekcje.count("HEADER")) {
        auto [a, b] = sekcje["HEADER"];
        for (size_t i = a; i + 1 < b; ++i)
            if (p[i].kod == 9 && przytnij(p[i].s) == "$ACADVER") wersja = przytnij(p[i + 1].s);
    }
    if (wersja == "AC1009" || wersja < "AC1015")
        throw Blad("DXF w wersji " + (wersja.empty() ? std::string("nieznanej") : wersja) +
                   " — XRecordy przenosi dopiero DXF 2000 (AC1015) i nowszy. Zapisz rysunek jako DXF 2000 lub nowszy.");
    if (!sekcje.count("ENTITIES") || !sekcje.count("OBJECTS")) throw Blad("DXF bez sekcji ENTITIES albo OBJECTS");
    raport.info(std::string("DXF ") + (bin ? "binarny" : "tekstowy") + ", wersja " + wersja);

    // Obiekty niegraficzne po uchwycie.
    auto [oa, ob] = sekcje["OBJECTS"];
    const Obiekty obiekty = podziel(p, oa, ob);
    std::map<std::string, const std::vector<ParaDxf>*> poUchwycie;
    for (const auto& o : obiekty) {
        const std::string h = przytnij(wartosc(o, 5));
        if (!h.empty()) poUchwycie[h] = &o;
    }
    auto daneWf = [&](const std::string& xd) -> Lista {
        auto it = poUchwycie.find(xd);
        if (it == poUchwycie.end()) return {};
        auto wpisy = wpisySlownika(*it->second);
        auto w = wpisy.find("WF");
        if (w == wpisy.end()) return {};
        auto x = poUchwycie.find(w->second);
        if (x == poUchwycie.end()) throw Blad("DXF: słownik rozszerzeń wskazuje nieistniejący XRECORD " + w->second);
        return listaXrecord(*x->second);
    };

    Rysunek r;
    // Słownik WORKFIELD w słowniku głównym (pierwszy obiekt sekcji OBJECTS).
    if (!obiekty.empty()) {
        auto wpisy = wpisySlownika(obiekty.front());
        auto w = wpisy.find("WORKFIELD");
        if (w != wpisy.end()) {
            auto d = poUchwycie.find(w->second);
            if (d == poUchwycie.end()) throw Blad("DXF: brak słownika WORKFIELD " + w->second);
            for (const auto& [k, h] : wpisySlownika(*d->second)) {
                auto x = poUchwycie.find(h);
                if (x == poUchwycie.end()) throw Blad("DXF: wpis " + k + " wskazuje nieistniejący XRECORD");
                r.slownik[k] = listaXrecord(*x->second);
            }
        }
    }

    // Obiekty graficzne.
    auto [ea, eb] = sekcje["ENTITIES"];
    const Obiekty encje = podziel(p, ea, eb);
    size_t luki = 0, nieobslugiwane = 0;
    std::map<std::string, size_t> inne;      // obiekty innych rodzajów, bez danych WF (np. LINE po EXPLODE)
    std::map<std::string, size_t> pochodne;  // warstwy WF_WIDOK_* z wf.lsp
    for (size_t i = 0; i < encje.size(); ++i) {
        const auto& o = encje[i];
        const std::string typ = przytnij(o.front().s);
        const std::string xd = slownikRozszerzen(o);
        Encja e;
        e.warstwaCad = wartosc(o, 8);
        // Obiekty pochodne z wf.lsp (okręgi WFSKALA itp.) — widok, nie dane.
        if (e.warstwaCad.rfind("WF_WIDOK_", 0) == 0) {
            ++pochodne[e.warstwaCad];
            if (typ == "POLYLINE") {
                while (i + 1 < encje.size() && przytnij(encje[i + 1].front().s) != "SEQEND") ++i;
                if (i + 1 < encje.size()) ++i;     // SEQEND
            }
            continue;
        }
        size_t lukiTu = 0;
        if (typ == "POINT") {
            e.rodzaj = RodzajEncji::Punkt;
            Wsp w;
            for (const auto& x : o) {
                if (x.kod == 10) w.x = liczba(x);
                if (x.kod == 20) w.y = liczba(x);
                if (x.kod == 30) w.z = liczba(x);
            }
            e.punkty.push_back(w);
        } else if (typ == "LWPOLYLINE") {
            e.rodzaj = RodzajEncji::Polilinia;
            bool podklasa = false;
            for (const auto& x : o) {
                if (x.kod == 100 && przytnij(x.s) == "AcDbPolyline") podklasa = true;
                if (!podklasa) continue;
                if (x.kod == 38) e.elewacja = liczba(x);
                if (x.kod == 70) e.zamknieta = (calkowita(x) & 1) != 0;
                if (x.kod == 10) e.punkty.push_back({liczba(x), 0, 0});
                if (x.kod == 20 && !e.punkty.empty()) e.punkty.back().y = liczba(x);
                if (x.kod == 42 && liczba(x) != 0) ++lukiTu;
            }
            for (auto& q : e.punkty) q.z = e.elewacja;
        } else if (typ == "POLYLINE") {
            long long flagi = 0;
            double elew = 0;
            for (const auto& x : o) {
                if (x.kod == 70) flagi = calkowita(x);
                if (x.kod == 30) elew = liczba(x);
            }
            const bool trojwym = (flagi & 8) != 0;
            if (flagi & (16 | 64)) {
                if (!xd.empty()) ++nieobslugiwane;
                while (i + 1 < encje.size() && przytnij(encje[i + 1].front().s) != "SEQEND") ++i;
                ++i;
                continue;
            }
            e.rodzaj = trojwym ? RodzajEncji::Polilinia3d : RodzajEncji::Polilinia;
            e.zamknieta = (flagi & 1) != 0;
            e.elewacja = trojwym ? 0 : elew;
            while (i + 1 < encje.size() && przytnij(encje[i + 1].front().s) == "VERTEX") {
                const auto& v = encje[++i];
                Wsp w;
                long long fv = 0;
                for (const auto& x : v) {
                    if (x.kod == 10) w.x = liczba(x);
                    if (x.kod == 20) w.y = liczba(x);
                    if (x.kod == 30) w.z = liczba(x);
                    if (x.kod == 70) fv = calkowita(x);
                    if (x.kod == 42 && liczba(x) != 0) ++lukiTu;
                }
                if (fv & 16) continue;       // punkt kontrolny ramy splajnu
                if (!trojwym) w.z = elew;
                e.punkty.push_back(w);
            }
            if (i + 1 < encje.size() && przytnij(encje[i + 1].front().s) == "SEQEND") ++i;
        } else {
            if (!xd.empty() && !daneWf(xd).empty()) {
                ++nieobslugiwane;
                raport.uwaga("obiekt " + typ + " z danymi WorkField — ten rodzaj obiektu nie jest obsługiwany, pominięty");
            } else {
                ++inne[typ];
            }
            continue;
        }
        if (!xd.empty()) e.dane = daneWf(xd);
        // Łuki liczą się tylko w obiektach WorkField — cudze polilinie
        // z łukami nie trafiają do GIS i nic nie tracą.
        if (!e.dane.empty()) luki += lukiTu;
        r.encje.push_back(std::move(e));
    }
    if (luki)
        raport.strata(std::to_string(luki) +
                      " wierzchołków z łukiem (bulge) — łuki nie są przenoszone do GIS, zostają odcinki");
    if (nieobslugiwane)
        raport.uwaga(std::to_string(nieobslugiwane) + " obiektów z danymi WorkField w nieobsługiwanej postaci");
    if (!pochodne.empty()) {
        std::string t;
        for (const auto& [k, n] : pochodne) t += (t.empty() ? "" : ", ") + k + " " + std::to_string(n);
        raport.info("obiekty pochodne (widok z wf.lsp, nie trafiają do GIS): " + t);
    }
    if (!inne.empty()) {
        std::string t;
        for (const auto& [k, n] : inne) t += (t.empty() ? "" : ", ") + k + " " + std::to_string(n);
        raport.info("obiekty innych rodzajów bez danych WorkField (pominięte): " + t +
                    " — np. linie po EXPLODE albo rysunek dodany w CAD-zie");
    }
    return r;
}

}  // namespace wfcad
