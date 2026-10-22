// odwzorowanie.cpp — patrz odwzorowanie.hpp.
#include "wfcad/odwzorowanie.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <optional>
#include <set>
#include <utility>

#include "wfcad/gpkg.hpp"
#include "wfcad/skrot.hpp"
#include "wfcad/uklad.hpp"
#include "wfcad/wkb.hpp"

namespace fs = std::filesystem;

namespace wfcad {

namespace {

// --- zapis binarny szkieletu, zawsze little endian --------------------------

struct Bin {
    std::string b;
    void u8(uint8_t v) { b.push_back(static_cast<char>(v)); }
    void u32(uint32_t v) {
        for (int i = 0; i < 4; ++i) b.push_back(static_cast<char>((v >> (8 * i)) & 0xFF));
    }
    void u64(uint64_t v) {
        for (int i = 0; i < 8; ++i) b.push_back(static_cast<char>((v >> (8 * i)) & 0xFF));
    }
    void f64(double d) {
        uint64_t v;
        std::memcpy(&v, &d, 8);
        u64(v);
    }
};

struct BinWej {
    const std::string& b;
    size_t poz = 0;
    void sprawdz(size_t n) {
        if (poz + n > b.size()) throw Blad("szkielet geometrii urwany");
    }
    uint8_t u8() {
        sprawdz(1);
        return static_cast<uint8_t>(b[poz++]);
    }
    uint32_t u32() {
        sprawdz(4);
        uint32_t v = 0;
        for (int i = 0; i < 4; ++i) v |= static_cast<uint32_t>(static_cast<uint8_t>(b[poz++])) << (8 * i);
        return v;
    }
    uint64_t u64() {
        sprawdz(8);
        uint64_t v = 0;
        for (int i = 0; i < 8; ++i) v |= static_cast<uint64_t>(static_cast<uint8_t>(b[poz++])) << (8 * i);
        return v;
    }
    double f64() {
        uint64_t v = u64();
        double d;
        std::memcpy(&d, &v, 8);
        return d;
    }
};

// Ochrona przed uszkodzonym szkieletem: 10 mln wierzchołków w jednym ciągu
// to 320 MB pamięci. Prawdziwy płat ma ich najwyżej tysiące.
constexpr uint32_t MAKS_WIERZCHOLKOW = 10'000'000;

bool rowneBitowo(double a, double b) { return std::memcmp(&a, &b, sizeof a) == 0; }

bool tenSamWierzcholek(const Wierzcholek& a, const Wierzcholek& b, bool zZ) {
    return rowneBitowo(a.x, b.x) && rowneBitowo(a.y, b.y) && (!zZ || rowneBitowo(a.z, b.z));
}

// Skrót ciągu wierzchołków WIDOCZNYCH w CAD (x, y i z, gdy geometria ma Z).
uint64_t skrotCiagu(const std::vector<Wierzcholek>& w, size_t od, size_t ile, bool zZ, bool wstecz = false) {
    uint64_t h = 1469598103934665603ull;
    const size_t n = w.size();
    for (size_t k = 0; k < ile; ++k) {
        size_t i = wstecz ? (od + n - k) % n : (od + k) % n;
        h = fnv64(&w[i].x, 8, h);
        h = fnv64(&w[i].y, 8, h);
        if (zZ) h = fnv64(&w[i].z, 8, h);
    }
    return h;
}

struct InfoCiagu {
    uint32_t n = 0;         // wierzchołki w WKB
    bool domkniety = false; // ostatni == pierwszy, w CAD pominięty
    uint64_t skrot = 0;     // ciągu widocznego w CAD
};

bool czyPierscien(const Geometria& g) { return g.rodzaj == POLIGON; }

InfoCiagu opiszCiag(const Geometria& g, const std::vector<Wierzcholek>& c) {
    InfoCiagu i;
    i.n = static_cast<uint32_t>(c.size());
    i.domkniety = czyPierscien(g) && c.size() >= 2 && tenSamWierzcholek(c.front(), c.back(), g.z);
    const size_t widoczne = i.domkniety ? c.size() - 1 : c.size();
    i.skrot = skrotCiagu(c, 0, widoczne, g.z);
    return i;
}

void piszSzkielet(Bin& b, const Geometria& g) {
    b.u8(g.porzadek);
    b.u32(g.kod);
    b.u8(g.maSrid ? 1 : 0);
    b.u32(g.srid);
    if (g.rodzaj <= POLIGON) {
        b.u32(static_cast<uint32_t>(g.pierscienie.size()));
        for (const auto& c : g.pierscienie) {
            InfoCiagu i = opiszCiag(g, c);
            b.u32(i.n);
            b.u8(i.domkniety ? 1 : 0);
            if (g.m)
                for (const auto& v : c) b.f64(v.m);
            b.u64(i.skrot);
            // Dokładne współrzędne (od WF2). Obieg przez DXF tekstowy zapisany
            // przez CAD może obciąć liczby do 15–16 cyfr; nietknięty wierzchołek
            // wraca wtedy różny o kilka ulp. Z kopią dokładnych wartości odczyt
            // dociąga go z powrotem zamiast uznać obiekt za edytowany.
            for (const auto& v : c) {
                b.f64(v.x);
                b.f64(v.y);
                if (g.z) b.f64(v.z);
            }
        }
    } else {
        b.u32(static_cast<uint32_t>(g.czesci.size()));
        for (const auto& c : g.czesci) piszSzkielet(b, c);
    }
}

// Szablon: geometria źródłowa w całości (współrzędne, M, kody, kolejność bajtów).
// Informacje o ciągach w tej samej kolejności co liście (DFS).
Geometria czytajSzkielet(BinWej& w, std::vector<std::vector<InfoCiagu>>& info, int glebokosc = 0) {
    if (glebokosc > 32) throw Blad("szkielet: zbyt głębokie zagnieżdżenie");
    Geometria g;
    g.porzadek = w.u8();
    g.kod = w.u32();
    g.maSrid = w.u8() != 0;
    g.srid = w.u32();
    ustawZKodu(g);
    if (g.maSrid != ((g.kod & 0x20000000u) != 0)) throw Blad("szkielet: niespójny SRID");
    if (g.rodzaj <= POLIGON) {
        const uint32_t nc = w.u32();
        std::vector<InfoCiagu> ic;
        for (uint32_t k = 0; k < nc; ++k) {
            InfoCiagu i;
            i.n = w.u32();
            if (i.n > MAKS_WIERZCHOLKOW) throw Blad("szkielet: nierealna liczba wierzchołków");
            // Licznik sprawdzany z tym, co szkielet NAPRAWDĘ niesie na wierzchołek
            // (M i współrzędne). 22.10 kontrola zakładała bajty na wierzchołek
            // także bez M i odrzucała każdy płat dłuższy niż ok. 40 wierzchołków.
            const uint64_t naWierzcholek = 8u * (2u + (g.z ? 1u : 0u) + (g.m ? 1u : 0u));
            const uint64_t potrzeba = 1 + static_cast<uint64_t>(i.n) * naWierzcholek + 8;
            if (potrzeba > w.b.size() - w.poz) throw Blad("szkielet: licznik wierzchołków większy niż dane");
            i.domkniety = w.u8() != 0;
            std::vector<Wierzcholek> c(i.n);
            if (g.m)
                for (auto& v : c) v.m = w.f64();
            i.skrot = w.u64();
            for (auto& v : c) {
                v.x = w.f64();
                v.y = w.f64();
                if (g.z) v.z = w.f64();
            }
            g.pierscienie.push_back(std::move(c));
            ic.push_back(i);
        }
        info.push_back(std::move(ic));
    } else {
        const uint32_t nc = w.u32();
        if (nc > w.b.size()) throw Blad("szkielet: licznik części większy niż dane");
        for (uint32_t k = 0; k < nc; ++k) g.czesci.push_back(czytajSzkielet(w, info, glebokosc + 1));
    }
    return g;
}

void zbierzLiscie(Geometria& g, std::vector<Geometria*>& out) {
    if (g.rodzaj <= POLIGON) out.push_back(&g);
    else
        for (auto& c : g.czesci) zbierzLiscie(c, out);
}

void zbierzLiscie(const Geometria& g, std::vector<const Geometria*>& out) {
    if (g.rodzaj <= POLIGON) out.push_back(&g);
    else
        for (const auto& c : g.czesci) zbierzLiscie(c, out);
}

std::string nazwaWarstwyCad(const std::string& tabela) {
    // Znaki niedozwolone w nazwach warstw DWG.
    static const std::string zle = "<>/\\\":;?*|,=`";
    std::string w = "WF_";
    for (char c : tabela) w += (zle.find(c) != std::string::npos || static_cast<unsigned char>(c) < 0x20) ? '_' : c;
    return w;
}

// Czy da się narysować: bez NaN we współrzędnych, ciągi o sensownej długości.
std::string dlaczegoNieDaSieNarysowac(const std::vector<const Geometria*>& liscie) {
    if (liscie.empty()) return "brak części";
    for (const Geometria* l : liscie) {
        for (const auto& c : l->pierscienie) {
            for (const auto& v : c)
                if (std::isnan(v.x) || std::isnan(v.y) || (l->z && std::isnan(v.z))) return "NaN we współrzędnych";
            InfoCiagu i = opiszCiag(*l, c);
            const size_t widoczne = i.domkniety ? c.size() - 1 : c.size();
            if (l->rodzaj == LINIA && widoczne < 2) return "linia krótsza niż 2 wierzchołki";
            if (l->rodzaj == POLIGON && widoczne < 3) return "pierścień krótszy niż 3 wierzchołki";
        }
        if (l->rodzaj == POLIGON && l->pierscienie.empty()) return "poligon bez pierścieni";
    }
    return {};
}

bool staleZ(const Geometria& g, double& z) {
    bool jest = false;
    for (const auto& c : g.pierscienie)
        for (const auto& v : c) {
            if (!jest) {
                z = v.z;
                jest = true;
            } else if (!rowneBitowo(v.z, z)) {
                return false;
            }
        }
    if (!jest) z = 0;
    return true;
}

// Współrzędne do CAD: przeliczone do układu rysunku, gdy warstwa jest w stopniach.
Wierzcholek wUkladzieCad(const Wierzcholek& v, const Uklad* u) {
    if (!u) return v;
    Wierzcholek w = v;
    u->doCad(v.x, v.y, w.x, w.y);
    return w;
}

std::vector<Wsp> widoczne(const Geometria& g, const std::vector<Wierzcholek>& c, double elewacja,
                          const Uklad* u = nullptr) {
    InfoCiagu i = opiszCiag(g, c);
    const size_t n = i.domkniety ? c.size() - 1 : c.size();
    std::vector<Wsp> w;
    for (size_t k = 0; k < n; ++k) {
        const Wierzcholek v = wUkladzieCad(c[k], u);
        w.push_back({v.x, v.y, g.z ? c[k].z : elewacja});
    }
    return w;
}

// --- rekord obiektu w XRecordzie ---------------------------------------------

enum Tryb : int16_t { BEZ_GEOMETRII = 0, Z_ENCJI = 1, SUROWA = 2 };

// WF2 (0.2.0): szkielet niesie dokładne współrzędne. Rysunku z WF1 nie da się
// odczytać tak samo, więc odmowa z jasną przyczyną zamiast cichej różnicy.
const char* const ZNACZNIK_REKORDU = "WF2";

struct Rekord {
    std::string uuid;
    int32_t warstwa = 0;
    int64_t fid = 0;
    int32_t element = -1, pierscien = -1, liczbaLisci = 0;
    int16_t tryb = BEZ_GEOMETRII;
    std::string szkielet, naglowek, surowa;
    uint64_t skrotWkb = 0, skrotObiektu = 0;
    std::vector<Wartosc> pola;
};

void dopiszCzytelne(Lista& l, const Rekord& r, const Warstwa& w);

Lista piszRekord(const Rekord& r, const Warstwa* w = nullptr) {
    Lista l;
    Pisarz p(l);
    p.znacznik(ZNACZNIK_REKORDU);
    p.bajty(r.uuid);
    p.i32(r.warstwa);
    p.i64(r.fid);
    p.i32(r.element);
    p.i32(r.pierscien);
    p.i32(r.liczbaLisci);
    p.i16(r.tryb);
    p.bajty(r.szkielet);
    p.bajty(r.naglowek);
    p.bajty(r.surowa);
    p.i64(static_cast<int64_t>(r.skrotWkb));
    p.i64(static_cast<int64_t>(r.skrotObiektu));
    p.i32(static_cast<int32_t>(r.pola.size()));
    for (const auto& v : r.pola) p.wartosc(v);
    if (w) dopiszCzytelne(l, r, *w);
    return l;
}

// --- czytelna kopia atrybutów (od 0.3.0) ------------------------------------------
//
// Za częścią binarną rekord niesie sekcję dla człowieka i dla LISP-a w CAD-zie:
//   (1 . "WF_CZYTELNE") (1 . "_warstwa") (1 . <tabela>) (1 . "_fid") (90 . <fid>)
//   potem dla każdej kolumny (1 . <nazwa>) i JEDNA para wartości:
//     (40 . liczba rzeczywista)  (90 . liczba całkowita)  (1 . tekst)  (70 . 0) = NULL
// Tylko do oglądania: odczyt do GPKG bierze wartości z części binarnej, więc ta
// sekcja nie może niczego zepsuć ani zgubić. Tekst, którego nie da się bezpiecznie
// pokazać (\0, zły UTF-8), dostaje opis zamiast treści.

const char* const ZNACZNIK_CZYTELNE = "WF_CZYTELNE";
constexpr size_t MAKS_TEKSTU_CZYTELNEGO = 250;

bool poprawnyUtf8(const std::string& s) {
    size_t i = 0;
    while (i < s.size()) {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        size_t n = c < 0x80 ? 1 : (c >> 5) == 0x6 ? 2 : (c >> 4) == 0xE ? 3 : (c >> 3) == 0x1E ? 4 : 0;
        if (n == 0 || i + n > s.size()) return false;
        for (size_t k = 1; k < n; ++k)
            if ((static_cast<unsigned char>(s[i + k]) >> 6) != 0x2) return false;
        i += n;
    }
    return true;
}

// Tekst do pokazania: bez znaków sterujących (rozbiłyby linię DXF), przycięty
// na granicy znaku UTF-8.
std::string tekstCzytelny(const std::string& s) {
    if (s.find('\0') != std::string::npos || !poprawnyUtf8(s))
        return "<tekst niewyświetlalny: " + std::to_string(s.size()) + " B>";
    std::string w;
    for (char c : s) w += (static_cast<unsigned char>(c) < 0x20 || c == 0x7F) ? ' ' : c;
    if (w.size() > MAKS_TEKSTU_CZYTELNEGO) {
        size_t k = MAKS_TEKSTU_CZYTELNEGO;
        while (k > 0 && (static_cast<unsigned char>(w[k]) >> 6) == 0x2) --k;
        w = w.substr(0, k) + "…";
    }
    return w;
}

void dopiszCzytelne(Lista& l, const Rekord& r, const Warstwa& w) {
    Pisarz p(l);
    p.znacznik(ZNACZNIK_CZYTELNE);
    p.znacznik("_warstwa");
    p.znacznik(tekstCzytelny(w.tabela));
    p.znacznik("_fid");
    if (r.fid >= INT32_MIN && r.fid <= INT32_MAX) p.i32(static_cast<int32_t>(r.fid));
    else p.znacznik(std::to_string(r.fid));
    for (size_t i = 0; i < r.pola.size() && i < w.kolumny.size(); ++i) {
        p.znacznik(tekstCzytelny(w.kolumny[i].nazwa));
        const Wartosc& v = r.pola[i];
        switch (v.klasa) {
            case Klasa::Null: p.i16(0); break;
            case Klasa::Calk:
                if (v.i >= INT32_MIN && v.i <= INT32_MAX) p.i32(static_cast<int32_t>(v.i));
                else p.znacznik(std::to_string(v.i));
                break;
            case Klasa::Rzecz:
                if (std::isfinite(v.d)) p.real(v.d);
                else p.znacznik(std::isnan(v.d) ? "NaN" : (v.d > 0 ? "+inf" : "-inf"));
                break;
            case Klasa::Tekst: p.znacznik(tekstCzytelny(v.s)); break;
            case Klasa::Blob: p.znacznik("<blob: " + std::to_string(v.s.size()) + " B>"); break;
        }
    }
}

bool czyRekordWF(const Lista& l) {
    if (l.empty() || l[0].kod != 1) return false;
    if (l[0].s == "WF1")
        throw Blad("rysunek z WorkFieldCAD 0.1 (rekord WF1) — wczytaj bazę do rysunku od nowa");
    return l[0].s == ZNACZNIK_REKORDU;
}

Rekord czytajRekord(const Lista& l) {
    Czytnik c(l);
    Rekord r;
    c.znacznik(ZNACZNIK_REKORDU);
    r.uuid = c.bajty();
    r.warstwa = c.i32();
    r.fid = c.i64();
    r.element = c.i32();
    r.pierscien = c.i32();
    r.liczbaLisci = c.i32();
    r.tryb = c.i16();
    r.szkielet = c.bajty();
    r.naglowek = c.bajty();
    r.surowa = c.bajty();
    r.skrotWkb = static_cast<uint64_t>(c.i64());
    r.skrotObiektu = static_cast<uint64_t>(c.i64());
    const int32_t n = c.i32();
    if (n < 0) throw Blad("XRecord uszkodzony: ujemna liczba pól");
    for (int32_t i = 0; i < n; ++i) r.pola.push_back(c.wartosc());
    // Za polami może stać tylko sekcja czytelna — do oglądania, odczyt jej nie używa.
    if (!c.koniec() && !c.czyZnacznik(ZNACZNIK_CZYTELNE)) throw Blad("XRecord: nadmiarowe pary po rekordzie");
    return r;
}

Lista piszSchemat(const Warstwa& w) {
    Lista l;
    Pisarz p(l);
    p.znacznik("WF_SCHEMAT1");
    p.bajty(w.tabela);
    p.bajty(w.kolumnaFid);
    p.bajty(w.kolumnaGeom);
    p.bajty(w.typGeom);
    p.i32(w.srs);
    p.bajty(w.srsNazwa);
    p.bajty(w.srsDefinicja);
    p.i16(static_cast<int16_t>(w.z));
    p.i16(static_cast<int16_t>(w.m));
    p.i32(static_cast<int32_t>(w.kolumny.size()));
    for (const auto& k : w.kolumny) {
        p.bajty(k.nazwa);
        p.bajty(k.typ);
        p.i16(k.niepusta ? 1 : 0);
        p.i16(k.maDomyslna ? 1 : 0);
        p.bajty(k.domyslna);
    }
    return l;
}

Warstwa czytajSchemat(const Lista& l) {
    Czytnik c(l);
    Warstwa w;
    c.znacznik("WF_SCHEMAT1");
    w.tabela = c.bajty();
    w.kolumnaFid = c.bajty();
    w.kolumnaGeom = c.bajty();
    w.typGeom = c.bajty();
    w.srs = c.i32();
    w.srsNazwa = c.bajty();
    w.srsDefinicja = c.bajty();
    w.z = c.i16();
    w.m = c.i16();
    const int32_t n = c.i32();
    for (int32_t i = 0; i < n; ++i) {
        Kolumna k;
        k.nazwa = c.bajty();
        k.typ = c.bajty();
        k.niepusta = c.i16() != 0;
        k.maDomyslna = c.i16() != 0;
        k.domyslna = c.bajty();
        w.kolumny.push_back(k);
    }
    return w;
}

std::string kluczSchematu(size_t i) { return "WF_S_" + std::to_string(i); }
std::string kluczSpisu(size_t i) { return "WF_SPIS_" + std::to_string(i); }
std::string kluczObiektu(const std::string& uuid) { return "WF_O_" + uuid; }

std::string opis(const Warstwa& w, int64_t fid) { return w.tabela + " fid " + std::to_string(fid); }

// --- składanie geometrii z obiektów CAD -----------------------------------------

struct Kontekst {
    Raport& raport;
    std::string kto;
    bool edytowana = false;
    size_t dociagniete = 0;
    const Uklad* uklad = nullptr;   // gdy warstwa w stopniach, a rysunek w PL-2000
};

std::vector<Wierzcholek> zCad(const std::vector<Wsp>& c) {
    std::vector<Wierzcholek> w(c.size());
    for (size_t i = 0; i < c.size(); ++i) {
        w[i].x = c[i].x;
        w[i].y = c[i].y;
        w[i].z = c[i].z;
    }
    return w;
}

// Granica dociągania: różnica, jaką wnosi zapis liczby mniejszą niż 17 liczbą
// cyfr znaczących (DXF tekstowy zapisany przez CAD). Względnie 1e-12: przy
// X = 7,5 mln to 7,5 µm. Obejmuje zapisy z co najmniej 13 cyframi i jest
// o rzędy wielkości mniejsza niż jakakolwiek zamierzona edycja.
constexpr double DOCIAGANIE = 1e-12;

bool blisko(double cad, double oryg) {
    return std::fabs(cad - oryg) <= std::max(std::fabs(oryg), 1.0) * DOCIAGANIE;
}

bool blisko(const Wierzcholek& c, const Wierzcholek& o, bool zZ) {
    return blisko(c.x, o.x) && blisko(c.y, o.y) && (!zZ || blisko(c.z, o.z));
}

struct Dopasowanie {
    bool obrot = false;         // CAD zaczął pętlę gdzie indziej albo odwrócił kierunek
    size_t dociagniete = 0;     // wierzchołki różne bitowo, ale w granicy dociągania
};

// Czy ciąg z CAD to oryginał: wprost albo — dla pierścienia — z obrotem
// i odwróceniem kierunku, każdy wierzchołek w granicy dociągania.
// Przy układzie: oryginał (stopnie) przeliczony TYM SAMYM wzorem co przy
// zapisie rysunku porównuje się z tym, co oddał CAD (PL-2000).
std::optional<Dopasowanie> dopasuj(const std::vector<Wierzcholek>& cad, const std::vector<Wierzcholek>& orygZrodla,
                                   size_t ile, bool zZ, bool pierscien, const Uklad* u = nullptr) {
    if (cad.size() != ile || orygZrodla.size() < ile) return std::nullopt;
    const size_t n = ile;
    std::vector<Wierzcholek> przeliczony;
    if (u) {
        przeliczony.reserve(n);
        for (size_t k = 0; k < n; ++k) przeliczony.push_back(wUkladzieCad(orygZrodla[k], u));
    }
    const std::vector<Wierzcholek>& oryg = u ? przeliczony : orygZrodla;
    auto proba = [&](size_t od, bool wstecz) -> std::optional<Dopasowanie> {
        Dopasowanie d;
        d.obrot = od != 0 || wstecz;
        for (size_t k = 0; k < n; ++k) {
            const size_t j = wstecz ? (od + n - k) % n : (od + k) % n;
            if (!blisko(cad[j], oryg[k], zZ)) return std::nullopt;
            if (!tenSamWierzcholek(cad[j], oryg[k], zZ)) ++d.dociagniete;
        }
        return d;
    };
    if (n == 0) return Dopasowanie{};
    if (auto d = proba(0, false)) return d;
    if (!pierscien) return std::nullopt;
    for (int kier = 0; kier < 2; ++kier)
        for (size_t od = 0; od < n; ++od)
            if (od != 0 || kier != 0)
                if (auto d = proba(od, kier == 1)) return d;
    return std::nullopt;
}

// Wypełnia ciąg szablonu (oryginał z szkieletu) współrzędnymi z CAD. Gdy CAD
// oddał oryginał (w granicy dociągania, ewentualnie obrócony), zostaje
// oryginał co do bitu. Zwraca true, gdy dokładnie odtworzony.
bool wypelnijCiag(std::vector<Wierzcholek>& cel, const InfoCiagu& info, const std::vector<Wierzcholek>& cad,
                  const Geometria& g, Kontekst& k, bool mozeObrot) {
    const size_t oczekiwane = info.domkniety ? info.n - 1 : info.n;
    if (auto d = dopasuj(cad, cel, oczekiwane, g.z, mozeObrot, k.uklad)) {
        if (skrotCiagu(cel, 0, oczekiwane, g.z) != info.skrot)
            throw Blad(k.kto + ": współrzędne w szkielecie niezgodne z jego skrótem — XRecord uszkodzony");
        if (d->obrot) k.raport.info(k.kto + ": przywrócono kolejność wierzchołków pętli zmienioną przez CAD");
        k.dociagniete += d->dociagniete;
        return true;
    }
    const bool tePrzyM = cad.size() == oczekiwane;
    std::vector<Wierzcholek> w(cad.size());
    for (size_t i = 0; i < cad.size(); ++i) {
        w[i].x = cad[i].x;
        w[i].y = cad[i].y;
        if (k.uklad) k.uklad->zCad(cad[i].x, cad[i].y, w[i].x, w[i].y);   // edycja: z PL-2000 do stopni
        w[i].z = g.z ? cad[i].z : 0.0;
        w[i].m = (tePrzyM && i < cel.size()) ? cel[i].m : std::nan("");
    }
    if (info.domkniety && !w.empty()) {
        Wierzcholek z = w.front();
        if (tePrzyM && !cel.empty()) z.m = cel.back().m;
        w.push_back(z);
    }
    k.edytowana = true;
    if (g.m && !tePrzyM)
        k.raport.strata(k.kto + ": zmieniona liczba wierzchołków — wartości M tego ciągu utracone (NaN)");
    cel = std::move(w);
    return false;
}

// Współrzędne obiektu CAD jako wierzchołki. Polilinia 2D ma jedną elewację
// dla całości; z wierzchołków od adaptera albo z DXF bywa 0, więc rozstrzyga
// pole elewacji.
std::vector<Wierzcholek> wspolrzedne(const Encja& e) {
    auto c = zCad(e.punkty);
    if (e.rodzaj == RodzajEncji::Polilinia)
        for (auto& q : c) q.z = e.elewacja;
    return c;
}

struct Slot {
    int32_t element, pierscien;
    bool operator<(const Slot& o) const {
        return element != o.element ? element < o.element : pierscien < o.pierscien;
    }
};

// Wypełnia jeden liść; false, gdy w rysunku nie ma po nim śladu.
bool wypelnijLisc(Geometria& l, const std::vector<InfoCiagu>& info, int32_t e,
                  const std::map<Slot, const Encja*>& encje, Kontekst& k) {
    auto znajdz = [&](int32_t p) -> const Encja* {
        auto it = encje.find({e, p});
        return it == encje.end() ? nullptr : it->second;
    };
    if (l.rodzaj == PUNKT || l.rodzaj == LINIA) {
        const Encja* en = znajdz(0);
        if (!en) return false;
        wypelnijCiag(l.pierscienie[0], info[0], wspolrzedne(*en), l, k, false);
        return true;
    }
    // POLIGON
    if (const Encja* mp = znajdz(-1)) {
        std::vector<std::vector<Wierzcholek>> petle;
        for (const auto& p : mp->petle) {
            auto v = zCad(p);
            for (auto& q : v) q.z = mp->elewacja;
            petle.push_back(std::move(v));
        }
        // Dopasowanie pierścieni do pętli po współrzędnych — CAD nie musi
        // zachować kolejności pętli.
        std::vector<int> przydzial(l.pierscienie.size(), -1);
        std::vector<bool> zajeta(petle.size(), false);
        for (size_t r = 0; r < l.pierscienie.size(); ++r) {
            const size_t ocz = info[r].domkniety ? info[r].n - 1 : info[r].n;
            for (size_t j = 0; j < petle.size() && przydzial[r] < 0; ++j)
                if (!zajeta[j] && dopasuj(petle[j], l.pierscienie[r], ocz, l.z, true, k.uklad)) {
                    przydzial[r] = static_cast<int>(j);
                    zajeta[j] = true;
                }
        }
        for (size_t r = 0; r < l.pierscienie.size(); ++r)
            for (size_t j = 0; j < petle.size() && przydzial[r] < 0; ++j)
                if (!zajeta[j]) {
                    przydzial[r] = static_cast<int>(j);
                    zajeta[j] = true;
                }
        std::vector<std::vector<Wierzcholek>> nowe;
        for (size_t r = 0; r < l.pierscienie.size(); ++r) {
            if (przydzial[r] < 0) {
                k.edytowana = true;
                k.raport.uwaga(k.kto + ": pierścień " + std::to_string(r) + " usunięty w CAD");
                continue;
            }
            auto c = l.pierscienie[r];
            wypelnijCiag(c, info[r], petle[static_cast<size_t>(przydzial[r])], l, k, true);
            nowe.push_back(std::move(c));
        }
        for (size_t j = 0; j < petle.size(); ++j)
            if (!zajeta[j]) {
                k.edytowana = true;
                k.raport.uwaga(k.kto + ": w CAD dodano pętlę — dopisana jako kolejny pierścień");
                std::vector<Wierzcholek> c = petle[j];
                for (auto& q : c) q.m = std::nan("");
                if (!c.empty()) c.push_back(c.front());
                nowe.push_back(std::move(c));
            }
        if (nowe.empty()) return false;
        l.pierscienie = std::move(nowe);
        return true;
    }
    // Pierścienie jako osobne polilinie (2D ze stałym Z albo 3D).
    std::vector<std::vector<Wierzcholek>> nowe;
    for (size_t r = 0; r < l.pierscienie.size(); ++r) {
        const Encja* en = znajdz(static_cast<int32_t>(r));
        if (!en) {
            if (r == 0) {
                if (l.pierscienie.size() > 1)
                    k.raport.uwaga(k.kto + ": usunięto obrys zewnętrzny — dziury bez obrysu pominięte");
                return false;
            }
            k.edytowana = true;
            k.raport.uwaga(k.kto + ": pierścień " + std::to_string(r) + " usunięty w CAD");
            continue;
        }
        auto c = l.pierscienie[r];
        wypelnijCiag(c, info[r], wspolrzedne(*en), l, k, true);
        nowe.push_back(std::move(c));
    }
    l.pierscienie = std::move(nowe);
    return true;
}

// Usuwa z drzewa liście oznaczone jako nieobecne. Zwraca false, gdy z całej
// geometrii nic nie zostało.
bool przytnij(Geometria& g, const std::set<const Geometria*>& brak, Kontekst& k) {
    if (g.rodzaj <= POLIGON) return brak.count(&g) == 0;
    std::vector<Geometria> zostaja;
    for (auto& c : g.czesci) {
        if (przytnij(c, brak, k)) zostaja.push_back(std::move(c));
        else {
            k.edytowana = true;
            k.raport.uwaga(k.kto + ": część geometrii usunięta w CAD");
        }
    }
    g.czesci = std::move(zostaja);
    return !g.czesci.empty();
}

struct WynikSkladania {
    bool jest = false;
    std::string blob;
    std::string zmiana;     // opis dla człowieka, gdy geometria różni się od źródła
};

struct Licznik {
    size_t czesci = 0, pierscieni = 0, wierzcholkow = 0;
};

void policz(const Geometria& g, Licznik& l) {
    if (g.rodzaj <= POLIGON) {
        ++l.czesci;
        l.pierscieni += g.pierscienie.size();
        for (const auto& c : g.pierscienie) l.wierzcholkow += c.size();
        return;
    }
    for (const auto& c : g.czesci) policz(c, l);
}

// Co się zmieniło w geometrii — tak, żeby człowiek mógł to porównać z tym,
// co zrobił w CAD-zie. Przy tej samej budowie: ile wierzchołków przesunięto
// i o ile najwięcej; przy innej: liczby części, pierścieni, wierzchołków.
std::string opiszZmiane(const Geometria& przed, const Geometria& po, const Uklad* u) {
    Licznik a, b;
    policz(przed, a);
    policz(po, b);
    char t[200];
    if (a.czesci != b.czesci || a.pierscieni != b.pierscieni || a.wierzcholkow != b.wierzcholkow) {
        std::string w;
        auto dodaj = [&](const char* co, size_t x, size_t y) {
            if (x == y) return;
            std::snprintf(t, sizeof t, "%s%s %zu→%zu", w.empty() ? "" : ", ", co, x, y);
            w += t;
        };
        dodaj("części", a.czesci, b.czesci);
        dodaj("pierścieni", a.pierscieni, b.pierscieni);
        dodaj("wierzchołków", a.wierzcholkow, b.wierzcholkow);
        return w;
    }
    std::vector<const Geometria*> la, lb;
    zbierzLiscie(przed, la);
    zbierzLiscie(po, lb);
    size_t ruszone = 0;
    double maks = 0;
    for (size_t i = 0; i < la.size() && i < lb.size(); ++i)
        for (size_t r = 0; r < la[i]->pierscienie.size() && r < lb[i]->pierscienie.size(); ++r) {
            const auto& c1 = la[i]->pierscienie[r];
            const auto& c2 = lb[i]->pierscienie[r];
            for (size_t v = 0; v < c1.size() && v < c2.size(); ++v) {
                // Odległość w układzie rysunku (metry), nie w stopniach źródła.
                const Wierzcholek p1 = wUkladzieCad(c1[v], u), p2 = wUkladzieCad(c2[v], u);
                const double d = std::hypot(p1.x - p2.x, p1.y - p2.y);
                const double dz = (przed.z && po.z) ? std::fabs(c1[v].z - c2[v].z) : 0.0;
                const double dd = std::max(d, dz);
                if (dd > 0) {
                    ++ruszone;
                    maks = std::max(maks, dd);
                }
            }
        }
    std::snprintf(t, sizeof t, "przesunięte wierzchołki: %zu, najwięcej o %.3f m", ruszone, maks);
    return t;
}

WynikSkladania zlozGeometrie(const Rekord& rek, const std::map<Slot, const Encja*>& encje, Kontekst& k) {
    BinWej w{rek.szkielet};
    std::vector<std::vector<InfoCiagu>> info;
    Geometria g = czytajSzkielet(w, info);
    if (w.poz != rek.szkielet.size()) throw Blad("szkielet geometrii: nadmiarowe bajty");
    std::vector<Geometria*> liscie;
    zbierzLiscie(g, liscie);
    if (liscie.size() != info.size()) throw Blad("szkielet geometrii niespójny");
    std::set<const Geometria*> brak;
    for (size_t e = 0; e < liscie.size(); ++e)
        if (!wypelnijLisc(*liscie[e], info[e], static_cast<int32_t>(e), encje, k)) brak.insert(liscie[e]);
    if (!przytnij(g, brak, k)) return {};

    const std::string wkb = piszWkb(g);
    WynikSkladania wy;
    wy.jest = true;
    if (!k.edytowana && fnv64(wkb) == rek.skrotWkb) {
        wy.blob = rek.naglowek + wkb;       // dokładnie jak w źródle, łącznie z obwiednią
    } else {
        k.edytowana = true;
        wy.blob = budujGpb(czytajGpb(rek.naglowek), g);
        BinWej w2{rek.szkielet};
        std::vector<std::vector<InfoCiagu>> info2;
        wy.zmiana = opiszZmiane(czytajSzkielet(w2, info2), g, k.uklad);
    }
    return wy;
}

void kopiujPlik(const std::string& z, const std::string& do_) {
    std::ifstream wej(z, std::ios::binary);
    if (!wej) throw Blad("nie mogę otworzyć " + z);
    std::ofstream wyj(do_, std::ios::binary | std::ios::trunc);
    if (!wyj) throw Blad("nie mogę utworzyć " + do_);
    wyj << wej.rdbuf();
    wyj.close();
    if (!wyj) throw Blad("błąd zapisu " + do_);
}

}  // namespace

uint64_t skrotObiektu(const Obiekt& o) {
    uint64_t h = 1469598103934665603ull;
    const uint8_t mg = o.maGeometrie ? 1 : 0;
    h = fnv64(&mg, 1, h);
    const uint64_t n = o.blob.size();
    h = fnv64(&n, 8, h);
    h = fnv64(o.blob, h);
    for (const auto& w : o.pola) {
        const uint8_t kl = static_cast<uint8_t>(w.klasa);
        h = fnv64(&kl, 1, h);
        switch (w.klasa) {
            case Klasa::Null: break;
            case Klasa::Calk: h = fnv64(&w.i, 8, h); break;
            case Klasa::Rzecz: h = fnv64(&w.d, 8, h); break;
            default: {
                const uint64_t d = w.s.size();
                h = fnv64(&d, 8, h);
                h = fnv64(w.s, h);
            }
        }
    }
    return h;
}

void sprawdzDomkniecie(const std::string& s) {
    for (const char* przyrostek : {"-wal", "-journal"}) {
        const std::string p = s + przyrostek;
        std::error_code ec;
        if (fs::exists(p, ec) && fs::file_size(p, ec) > 0)
            throw Blad("obok bazy leży niepusty " + p +
                       " — baza nie jest domknięta. Zamknij program, który ją trzyma, i sprawdź, czy plik zniknął.");
    }
}

Rysunek doRysunku(const std::vector<Warstwa>& warstwy, const Zrodlo& zrodlo, Raport& raport,
                  const OpcjeRysunku& opcje) {
    Rysunek rys;
    if (opcje.uklad && !strefaPl2000(opcje.uklad))
        throw Blad("układ rysunku EPSG:" + std::to_string(opcje.uklad) + " nieobsługiwany — tylko PL-2000 (2176–2179)");
    const Uklad uklad{opcje.uklad};
    if (opcje.uklad) {
        Lista l;
        Pisarz p(l);
        p.znacznik("WF_UKLAD1");
        p.i32(opcje.uklad);
        rys.slownik["WF_UKLAD"] = l;
    }
    {
        Lista l;
        Pisarz p(l);
        p.znacznik("WF_ZRODLO1");
        p.bajty(zrodlo.sciezka);
        p.bajty(zrodlo.md5);
        p.i64(zrodlo.rozmiar);
        p.i32(static_cast<int32_t>(warstwy.size()));
        rys.slownik["WF_ZRODLO"] = l;
    }
    for (size_t wi = 0; wi < warstwy.size(); ++wi) {
        const Warstwa& w = warstwy[wi];
        rys.slownik[kluczSchematu(wi)] = piszSchemat(w);
        Lista spis;
        Pisarz ps(spis);
        ps.znacznik("WF_SPIS1");
        ps.i32(static_cast<int32_t>(w.obiekty.size()));
        const std::string warstwaCad = nazwaWarstwyCad(w.tabela);
        const Uklad* ut = uklad.przelicza(w.srs) ? &uklad : nullptr;
        if (ut)
            raport.info(w.tabela + ": EPSG:4326 przeliczone w rysunku na EPSG:" + std::to_string(uklad.docelowy) +
                        " (w danych zostają dokładne stopnie)");
        else if (opcje.uklad && w.srs != uklad.docelowy && !w.obiekty.empty())
            raport.uwaga(w.tabela + ": warstwa w EPSG:" + std::to_string(w.srs) +
                         " — nie przeliczana, w rysunku nie zgra się z warstwami w EPSG:" +
                         std::to_string(uklad.docelowy));
        size_t narysowane = 0, bezRysunku = 0;

        for (const Obiekt& o : w.obiekty) {
            Rekord r;
            r.uuid = nowyUuid();
            r.warstwa = static_cast<int32_t>(wi);
            r.fid = o.fid;
            r.pola = o.pola;
            r.skrotObiektu = skrotObiektu(o);
            ps.i64(o.fid);
            ps.bajty(r.uuid);

            Geometria g;
            if (o.maGeometrie) {
                r.tryb = Z_ENCJI;
                try {
                    Gpb gpb = czytajGpb(o.blob);
                    g = czytajWkb(gpb.wkb);
                    r.naglowek = gpb.naglowek;
                    r.skrotWkb = fnv64(gpb.wkb);
                    std::vector<const Geometria*> liscie;
                    zbierzLiscie(g, liscie);
                    std::string dlaczego = gpb.pusta ? std::string("geometria pusta") : dlaczegoNieDaSieNarysowac(liscie);
                    if (!dlaczego.empty()) {
                        r.tryb = SUROWA;
                        raport.uwaga(opis(w, o.fid) + ": " + dlaczego + " — przechowana bez rysunku");
                    }
                } catch (const Blad& e) {
                    r.tryb = SUROWA;
                    raport.uwaga(opis(w, o.fid) + ": " + e.what() + " — przechowana bez rysunku");
                }
            }
            if (r.tryb == SUROWA) {
                r.naglowek.clear();
                r.surowa = o.blob;
            }
            if (r.tryb != Z_ENCJI) {
                ++bezRysunku;
                rys.slownik[kluczObiektu(r.uuid)] = piszRekord(r, &w);
                continue;
            }

            Bin b;
            piszSzkielet(b, g);
            r.szkielet = b.b;
            std::vector<const Geometria*> liscie;
            zbierzLiscie(g, liscie);
            r.liczbaLisci = static_cast<int32_t>(liscie.size());

            auto dodaj = [&](Encja e, int32_t element, int32_t pierscien) {
                Rekord rr = r;
                rr.element = element;
                rr.pierscien = pierscien;
                e.warstwaCad = warstwaCad;
                e.dane = piszRekord(rr, &w);
                rys.encje.push_back(std::move(e));
            };

            for (size_t li = 0; li < liscie.size(); ++li) {
                const Geometria& l = *liscie[li];
                const int32_t el = static_cast<int32_t>(li);
                double z = 0;
                const bool stale = !l.z || staleZ(l, z);
                if (!l.z) z = 0;
                if (l.rodzaj == PUNKT) {
                    Encja e;
                    e.rodzaj = RodzajEncji::Punkt;
                    e.punkty = widoczne(l, l.pierscienie[0], 0, ut);
                    dodaj(e, el, 0);
                } else if (l.rodzaj == LINIA) {
                    Encja e;
                    e.rodzaj = stale ? RodzajEncji::Polilinia : RodzajEncji::Polilinia3d;
                    e.elewacja = stale ? z : 0;
                    e.punkty = widoczne(l, l.pierscienie[0], e.elewacja, ut);
                    dodaj(e, el, 0);
                } else if (stale && opcje.mpolygon) {
                    Encja e;
                    e.rodzaj = RodzajEncji::MPolygon;
                    e.elewacja = z;
                    for (const auto& c : l.pierscienie) e.petle.push_back(widoczne(l, c, z, ut));
                    dodaj(e, el, -1);
                } else {
                    // Pierścień po pierścieniu: polilinia 2D z elewacją, gdy Z
                    // stałe (DXF i każdy CAD bez MPOLYGON), inaczej 3D.
                    for (size_t ri = 0; ri < l.pierscienie.size(); ++ri) {
                        Encja e;
                        e.rodzaj = stale ? RodzajEncji::Polilinia : RodzajEncji::Polilinia3d;
                        e.elewacja = stale ? z : 0;
                        e.punkty = widoczne(l, l.pierscienie[ri], e.elewacja, ut);
                        e.zamknieta = opiszCiag(l, l.pierscienie[ri]).domkniety;
                        dodaj(e, el, static_cast<int32_t>(ri));
                    }
                }
            }
            ++narysowane;
        }
        rys.slownik[kluczSpisu(wi)] = spis;
        raport.info(w.tabela + ": " + std::to_string(w.obiekty.size()) + " obiektów, narysowanych " +
                    std::to_string(narysowane) + ", bez rysunku " + std::to_string(bezRysunku));
    }
    return rys;
}

Odczyt zRysunku(const Rysunek& rys, Raport& raport) {
    Odczyt od;
    auto it = rys.slownik.find("WF_ZRODLO");
    if (it == rys.slownik.end()) throw Blad("rysunek nie ma wpisu WF_ZRODLO — nie pochodzi z WorkFieldCAD");
    Uklad uklad;
    if (auto u = rys.slownik.find("WF_UKLAD"); u != rys.slownik.end()) {
        Czytnik cu(u->second);
        cu.znacznik("WF_UKLAD1");
        uklad.docelowy = cu.i32();
        if (!strefaPl2000(uklad.docelowy)) throw Blad("WF_UKLAD: nieznany układ " + std::to_string(uklad.docelowy));
    }
    Czytnik cz(it->second);
    cz.znacznik("WF_ZRODLO1");
    od.zrodlo.sciezka = cz.bajty();
    od.zrodlo.md5 = cz.bajty();
    od.zrodlo.rozmiar = cz.i64();
    const int32_t nw = cz.i32();

    struct Pozycja {
        int64_t fid;
        std::string uuid;
    };
    std::vector<std::vector<Pozycja>> spisy;
    for (int32_t wi = 0; wi < nw; ++wi) {
        auto s = rys.slownik.find(kluczSchematu(static_cast<size_t>(wi)));
        auto p = rys.slownik.find(kluczSpisu(static_cast<size_t>(wi)));
        if (s == rys.slownik.end() || p == rys.slownik.end())
            throw Blad("brak schematu albo spisu warstwy " + std::to_string(wi));
        od.warstwy.push_back(czytajSchemat(s->second));
        Czytnik c(p->second);
        c.znacznik("WF_SPIS1");
        const int32_t n = c.i32();
        std::vector<Pozycja> sp;
        for (int32_t i = 0; i < n; ++i) {
            Pozycja q;
            q.fid = c.i64();
            q.uuid = c.bajty();
            sp.push_back(q);
        }
        spisy.push_back(std::move(sp));
    }

    // Grupy: UUID -> encje w kolejności rysunku.
    struct Grupa {
        Rekord rekord;
        std::vector<std::pair<Slot, const Encja*>> encje;
        bool bezRysunku = false;
    };
    std::map<std::string, Grupa> grupy;
    for (const Encja& e : rys.encje) {
        if (!czyRekordWF(e.dane)) {
            ++od.obce;
            continue;
        }
        Rekord r = czytajRekord(e.dane);
        if (r.warstwa < 0 || r.warstwa >= nw) throw Blad("rekord wskazuje nieistniejącą warstwę");
        auto [g, nowa] = grupy.try_emplace(r.uuid);
        if (nowa) g->second.rekord = r;
        g->second.encje.push_back({Slot{r.element, r.pierscien}, &e});
    }
    for (const auto& [k, l] : rys.slownik) {
        if (k.rfind("WF_O_", 0) != 0) continue;
        Rekord r = czytajRekord(l);
        auto& g = grupy[r.uuid];
        g.rekord = r;
        g.bezRysunku = true;
    }

    // Kolejność: jak w spisie, czyli jak w źródle.
    for (int32_t wi = 0; wi < nw; ++wi) {
        Warstwa& w = od.warstwy[static_cast<size_t>(wi)];
        for (const Pozycja& poz : spisy[static_cast<size_t>(wi)]) {
            auto gi = grupy.find(poz.uuid);
            if (gi == grupy.end()) {
                od.usuniete.push_back({w.tabela, poz.fid});
                od.zmiany.push_back(opis(w, poz.fid) + ": usunięty");
                raport.uwaga(opis(w, poz.fid) + ": usunięty w CAD — w bazie zostaje, decyzja należy do człowieka");
                continue;
            }
            Grupa& g = gi->second;
            const Rekord& rek = g.rekord;
            if (rek.fid != poz.fid || rek.warstwa != wi) throw Blad("rekord " + poz.uuid + " niezgodny ze spisem");

            if (g.bezRysunku) {
                Obiekt o;
                o.fid = rek.fid;
                o.pola = rek.pola;
                o.maGeometrie = rek.tryb == SUROWA;
                o.blob = rek.surowa;
                o.zmieniony = skrotObiektu(o) != rek.skrotObiektu;
                w.obiekty.push_back(std::move(o));
                grupy.erase(gi);
                continue;
            }
            // Wystąpienie k-te każdego miejsca: k = 0 to oryginał, dalsze to kopie.
            std::map<Slot, std::vector<const Encja*>> miejsca;
            for (const auto& [s, e] : g.encje) miejsca[s].push_back(e);
            size_t kopii = 0;
            for (const auto& [s, v] : miejsca) kopii = std::max(kopii, v.size() - 1);

            for (size_t kk = 0; kk <= kopii; ++kk) {
                std::map<Slot, const Encja*> wybrane;
                for (const auto& [s, v] : miejsca)
                    if (kk < v.size()) wybrane[s] = v[kk];
                Kontekst kt{raport, opis(w, rek.fid) + (kk ? " (kopia " + std::to_string(kk) + ")" : "")};
                if (uklad.przelicza(w.srs)) kt.uklad = &uklad;
                WynikSkladania ws = zlozGeometrie(rek, wybrane, kt);
                od.dociagniete += kt.dociagniete;
                if (!ws.jest) {
                    if (kk == 0) {
                        od.usuniete.push_back({w.tabela, rek.fid});
                        od.zmiany.push_back(kt.kto + ": usunięty (wszystkie części)");
                        raport.uwaga(kt.kto + ": wszystkie części usunięte w CAD — w bazie zostaje");
                    }
                    continue;
                }
                Obiekt o;
                o.fid = kk ? 0 : rek.fid;
                o.nowy = kk > 0;
                o.pola = rek.pola;
                o.maGeometrie = true;
                o.blob = ws.blob;
                o.zmieniony = o.nowy || skrotObiektu(o) != rek.skrotObiektu;
                if (o.nowy) raport.uwaga(kt.kto + ": skopiowany w CAD — zostanie wstawiony jako nowy obiekt");
                if (o.zmieniony)
                    od.zmiany.push_back(kt.kto + ": " +
                                        (o.nowy ? std::string("nowy obiekt (kopia)") +
                                                      (ws.zmiana.empty() ? "" : "; względem oryginału: " + ws.zmiana)
                                                : (ws.zmiana.empty() ? std::string("zmienione dane") : ws.zmiana)));
                w.obiekty.push_back(std::move(o));
            }
            grupy.erase(gi);
        }
    }
    for (const auto& [u, g] : grupy)
        raport.uwaga("rekord " + u + " nie występuje w spisie wczytania — pominięty");
    if (od.obce) raport.info(std::to_string(od.obce) + " obiektów CAD bez danych WorkField — pominięte");
    if (od.dociagniete)
        raport.info(std::to_string(od.dociagniete) +
                    " wierzchołków różnych od oryginału tylko w granicy precyzji zapisu — przywrócone dokładnie");
    return od;
}

WynikZapisu zapiszDoGpkg(const Odczyt& o, const std::string& zrodlo, const std::string& cel,
                         const OpcjeZapisu& opcje, Raport& raport) {
    if (fs::exists(cel)) throw Blad(cel + " już istnieje — nie nadpisuję. Wskaż nową nazwę.");
    sprawdzDomkniecie(zrodlo);
    const std::string md5 = md5Pliku(zrodlo);
    if (md5 != o.zrodlo.md5) {
        if (!opcje.mimoZmianZrodla)
            throw Blad("źródło zmieniło się od wczytania do rysunku (md5 " + md5 + ", przy wczytaniu " + o.zrodlo.md5 +
                       "). Zapis odmówiony, żeby nie nadpisać cudzej pracy.");
        raport.uwaga("źródło zmieniło się od wczytania — zapis wymuszony");
    }
    kopiujPlik(zrodlo, cel);
    if (md5Pliku(cel) != md5) {
        fs::remove(cel);
        throw Blad("kopia źródła ma inną sumę md5 niż źródło — przerwane");
    }

    WynikZapisu wy;
    try {
        Gpkg db(cel, true);
        db.poczatek();
        try {
            for (const Warstwa& w : o.warstwy) {
                Warstwa teraz = db.czytaj(w.tabela);
                bool zgodny = teraz.kolumnaFid == w.kolumnaFid && teraz.kolumnaGeom == w.kolumnaGeom &&
                              teraz.kolumny.size() == w.kolumny.size();
                for (size_t i = 0; zgodny && i < w.kolumny.size(); ++i)
                    zgodny = teraz.kolumny[i].nazwa == w.kolumny[i].nazwa && teraz.kolumny[i].typ == w.kolumny[i].typ;
                if (!zgodny) throw Blad("schemat warstwy " + w.tabela + " w bazie różni się od zapisanego w rysunku");
                for (const Obiekt& ob : w.obiekty) {
                    if (ob.nowy) {
                        int64_t fid = db.wstaw(w, ob);
                        raport.info(w.tabela + ": wstawiono nowy obiekt fid " + std::to_string(fid));
                        ++wy.wstawione;
                    } else if (opcje.wszystko || ob.zmieniony) {
                        if (db.zapisz(w, ob) != 1) {
                            raport.uwaga(opis(w, ob.fid) + ": nie ma go w bazie — pominięty");
                            ++wy.pominiete;
                        } else {
                            ++wy.zmienione;
                        }
                    }
                }
            }
            db.zatwierdz();
        } catch (...) {
            db.wycofaj();
            throw;
        }
        const std::string ic = db.integralnosc();
        if (ic != "ok") raport.strata("PRAGMA integrity_check: " + ic);
    } catch (...) {
        // Niedokończona kopia nie może zostać na dysku — wyglądałaby jak wynik.
        std::error_code ec;
        fs::remove(cel, ec);
        throw;
    }
    sprawdzDomkniecie(cel);
    return wy;
}

}  // namespace wfcad
