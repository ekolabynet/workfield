// rysunek.cpp — patrz rysunek.hpp.
#include "wfcad/rysunek.hpp"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <sstream>

namespace wfcad {

namespace {

const char MAGIA[4] = {'W', 'F', 'R', '1'};

struct Wyj {
    std::string b;
    template <typename T>
    void p(T v) {
        b.append(reinterpret_cast<const char*>(&v), sizeof v);
    }
    void s(const std::string& t) {
        p<uint32_t>(static_cast<uint32_t>(t.size()));
        b += t;
    }
};

struct Wej {
    const std::string& b;
    size_t poz = 0;
    template <typename T>
    T p() {
        if (poz + sizeof(T) > b.size()) throw Blad("plik rysunku urwany");
        T v;
        std::memcpy(&v, b.data() + poz, sizeof v);
        poz += sizeof v;
        return v;
    }
    std::string s() {
        const uint32_t n = p<uint32_t>();
        if (poz + n > b.size()) throw Blad("plik rysunku urwany");
        std::string t = b.substr(poz, n);
        poz += n;
        return t;
    }
};

void piszListe(Wyj& w, const Lista& l) {
    w.p<uint32_t>(static_cast<uint32_t>(l.size()));
    for (const auto& x : l) {
        w.p<int32_t>(x.kod);
        w.p<int32_t>(x.i);
        w.p<double>(x.d);
        w.s(x.s);
    }
}

Lista czytajListe(Wej& w) {
    const uint32_t n = w.p<uint32_t>();
    Lista l;
    for (uint32_t i = 0; i < n; ++i) {
        Para x;
        x.kod = w.p<int32_t>();
        x.i = w.p<int32_t>();
        x.d = w.p<double>();
        x.s = w.s();
        l.push_back(std::move(x));
    }
    return l;
}

void piszWsp(Wyj& w, const std::vector<Wsp>& v) {
    w.p<uint32_t>(static_cast<uint32_t>(v.size()));
    for (const auto& q : v) {
        w.p(q.x);
        w.p(q.y);
        w.p(q.z);
    }
}

std::vector<Wsp> czytajWsp(Wej& w) {
    const uint32_t n = w.p<uint32_t>();
    std::vector<Wsp> v(n);
    for (auto& q : v) {
        q.x = w.p<double>();
        q.y = w.p<double>();
        q.z = w.p<double>();
    }
    return v;
}

const char* nazwa(RodzajEncji r) {
    switch (r) {
        case RodzajEncji::Punkt: return "PUNKT";
        case RodzajEncji::Polilinia: return "POLILINIA";
        case RodzajEncji::Polilinia3d: return "POLILINIA3D";
        case RodzajEncji::MPolygon: return "MPOLYGON";
    }
    return "?";
}

std::string liczba(double v) {
    char b[40];
    std::snprintf(b, sizeof b, "%.17g", v);
    return b;
}

std::string czytelne(const std::string& s) {
    std::string w;
    for (unsigned char c : s) {
        if (c >= 0x20 && c < 0x7F) w += static_cast<char>(c);
        else {
            char b[8];
            std::snprintf(b, sizeof b, "\\x%02x", c);
            w += b;
        }
    }
    return w;
}

void zrzutListy(std::ostringstream& o, const Lista& l, const char* wciecie) {
    for (const auto& x : l) {
        o << wciecie << x.kod << ": ";
        switch (x.kod) {
            case 1: o << x.s; break;
            case 40: o << liczba(x.d); break;
            case 70: case 90: o << x.i; break;
            case 310: o << "[" << x.s.size() << " B] " << czytelne(x.s.substr(0, 48)); break;
            default: o << "?";
        }
        o << "\n";
    }
}

}  // namespace

void zapiszRysunek(const Rysunek& r, const std::string& sciezka) {
    Wyj w;
    w.b.append(MAGIA, 4);
    w.p<uint32_t>(static_cast<uint32_t>(r.encje.size()));
    for (const auto& e : r.encje) {
        w.p<uint8_t>(static_cast<uint8_t>(e.rodzaj));
        w.s(e.warstwaCad);
        w.p<uint8_t>(e.zamknieta ? 1 : 0);
        w.p<double>(e.elewacja);
        piszWsp(w, e.punkty);
        w.p<uint32_t>(static_cast<uint32_t>(e.petle.size()));
        for (const auto& p : e.petle) piszWsp(w, p);
        piszListe(w, e.dane);
    }
    w.p<uint32_t>(static_cast<uint32_t>(r.slownik.size()));
    for (const auto& [k, l] : r.slownik) {
        w.s(k);
        piszListe(w, l);
    }
    std::ofstream f(sciezka, std::ios::binary | std::ios::trunc);
    if (!f) throw Blad("nie mogę zapisać " + sciezka);
    f.write(w.b.data(), static_cast<std::streamsize>(w.b.size()));
    if (!f) throw Blad("błąd zapisu " + sciezka);
}

Rysunek wczytajRysunek(const std::string& sciezka) {
    std::ifstream f(sciezka, std::ios::binary);
    if (!f) throw Blad("nie mogę otworzyć " + sciezka);
    std::string b((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    if (b.size() < 4 || std::memcmp(b.data(), MAGIA, 4) != 0) throw Blad(sciezka + " to nie jest plik rysunku WFR1");
    Wej w{b, 4};
    Rysunek r;
    const uint32_t n = w.p<uint32_t>();
    for (uint32_t i = 0; i < n; ++i) {
        Encja e;
        e.rodzaj = static_cast<RodzajEncji>(w.p<uint8_t>());
        e.warstwaCad = w.s();
        e.zamknieta = w.p<uint8_t>() != 0;
        e.elewacja = w.p<double>();
        e.punkty = czytajWsp(w);
        const uint32_t np = w.p<uint32_t>();
        for (uint32_t j = 0; j < np; ++j) e.petle.push_back(czytajWsp(w));
        e.dane = czytajListe(w);
        r.encje.push_back(std::move(e));
    }
    const uint32_t ns = w.p<uint32_t>();
    for (uint32_t i = 0; i < ns; ++i) {
        std::string k = w.s();
        r.slownik[k] = czytajListe(w);
    }
    if (w.poz != b.size()) throw Blad(sciezka + ": nadmiarowe bajty na końcu");
    return r;
}

std::string zrzutRysunku(const Rysunek& r) {
    std::ostringstream o;
    o << "# rysunek: " << r.encje.size() << " encji, " << r.slownik.size() << " wpisów w słowniku\n";
    for (size_t i = 0; i < r.encje.size(); ++i) {
        const auto& e = r.encje[i];
        o << "\n[" << i << "] " << nazwa(e.rodzaj) << "  warstwa CAD: " << e.warstwaCad;
        if (e.rodzaj == RodzajEncji::Polilinia || e.rodzaj == RodzajEncji::MPolygon)
            o << "  elewacja: " << liczba(e.elewacja);
        if (e.zamknieta) o << "  zamknięta";
        o << "\n";
        for (const auto& p : e.punkty) o << "    " << liczba(p.x) << " " << liczba(p.y) << " " << liczba(p.z) << "\n";
        for (size_t j = 0; j < e.petle.size(); ++j) {
            o << "  pętla " << j << ":\n";
            for (const auto& p : e.petle[j]) o << "    " << liczba(p.x) << " " << liczba(p.y) << "\n";
        }
        o << "  XRecord WF (" << e.dane.size() << " par):\n";
        zrzutListy(o, e.dane, "    ");
    }
    for (const auto& [k, l] : r.slownik) {
        o << "\n{" << k << "} (" << l.size() << " par)\n";
        zrzutListy(o, l, "    ");
    }
    return o.str();
}

}  // namespace wfcad
