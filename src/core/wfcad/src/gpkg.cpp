// gpkg.cpp — patrz gpkg.hpp.
#include "wfcad/gpkg.hpp"

#include <sqlite3.h>

#include <cmath>

#include "wfcad/wkb.hpp"

namespace wfcad {

namespace {

struct Zapytanie {
    sqlite3_stmt* st = nullptr;
    Zapytanie(sqlite3* db, const std::string& sql) {
        if (sqlite3_prepare_v2(db, sql.c_str(), static_cast<int>(sql.size()), &st, nullptr) != SQLITE_OK)
            throw Blad(std::string("SQLite: ") + sqlite3_errmsg(db) + " — w: " + sql);
    }
    ~Zapytanie() { sqlite3_finalize(st); }
    bool krok(sqlite3* db) {
        int r = sqlite3_step(st);
        if (r == SQLITE_ROW) return true;
        if (r == SQLITE_DONE) return false;
        throw Blad(std::string("SQLite: ") + sqlite3_errmsg(db));
    }
    std::string tekst(int k) {
        const unsigned char* t = sqlite3_column_text(st, k);
        return t ? std::string(reinterpret_cast<const char*>(t), static_cast<size_t>(sqlite3_column_bytes(st, k)))
                 : std::string();
    }
};

Wartosc wartoscKolumny(sqlite3_stmt* st, int k) {
    switch (sqlite3_column_type(st, k)) {
        case SQLITE_INTEGER: return Wartosc::calk(sqlite3_column_int64(st, k));
        case SQLITE_FLOAT: return Wartosc::rzecz(sqlite3_column_double(st, k));
        case SQLITE_TEXT: {
            // Bajty dosłownie: bez przekodowania i bez obcinania na \0.
            const unsigned char* t = sqlite3_column_text(st, k);
            return Wartosc::tekst(std::string(reinterpret_cast<const char*>(t),
                                              static_cast<size_t>(sqlite3_column_bytes(st, k))));
        }
        case SQLITE_BLOB: {
            const void* b = sqlite3_column_blob(st, k);
            int n = sqlite3_column_bytes(st, k);
            return Wartosc::blob(n ? std::string(static_cast<const char*>(b), static_cast<size_t>(n)) : std::string());
        }
        default: return Wartosc::null_();
    }
}

// Uwaga o powinowactwie typów SQLite: wiązanie wartości w JEJ klasie
// (a nie w typie kolumny) oddaje to, co było zapisane. Tekst w kolumnie
// INTEGER istnieje tylko wtedy, gdy nie dał się zamienić na liczbę —
// ponowny zapis da więc ten sam tekst.
void zwiaz(sqlite3* db, sqlite3_stmt* st, int k, const Wartosc& w) {
    int r = SQLITE_OK;
    switch (w.klasa) {
        case Klasa::Null: r = sqlite3_bind_null(st, k); break;
        case Klasa::Calk: r = sqlite3_bind_int64(st, k, w.i); break;
        case Klasa::Rzecz: r = sqlite3_bind_double(st, k, w.d); break;
        case Klasa::Tekst:
            r = sqlite3_bind_text(st, k, w.s.data(), static_cast<int>(w.s.size()), SQLITE_TRANSIENT);
            break;
        case Klasa::Blob:
            r = sqlite3_bind_blob(st, k, w.s.data(), static_cast<int>(w.s.size()), SQLITE_TRANSIENT);
            break;
    }
    if (r != SQLITE_OK) throw Blad(std::string("SQLite bind: ") + sqlite3_errmsg(db));
}

// --- funkcje SQL dla wyzwalaczy R-tree -------------------------------------

bool obwiedniaBloba(sqlite3_value* v, std::vector<double>& o, bool& pusta) {
    if (sqlite3_value_type(v) != SQLITE_BLOB) return false;
    std::string b(static_cast<const char*>(sqlite3_value_blob(v)), static_cast<size_t>(sqlite3_value_bytes(v)));
    Gpb g = czytajGpb(b);
    pusta = g.pusta;
    if (g.obwiednia.size() >= 4) {
        o = g.obwiednia;
    } else {
        Geometria geo = czytajWkb(g.wkb);
        o = obwiednia(geo, false, false);
        if (o.empty()) pusta = true;
    }
    return true;
}

void stWspolrzedna(sqlite3_context* c, int argc, sqlite3_value** argv, int ktora) {
    if (argc != 1) { sqlite3_result_error(c, "zła liczba argumentów", -1); return; }
    try {
        std::vector<double> o;
        bool pusta = false;
        if (!obwiedniaBloba(argv[0], o, pusta) || pusta || o.size() < 4 || std::isnan(o[ktora])) {
            sqlite3_result_null(c);
            return;
        }
        sqlite3_result_double(c, o[ktora]);
    } catch (const std::exception& e) {
        sqlite3_result_error(c, e.what(), -1);
    }
}

void stMinX(sqlite3_context* c, int n, sqlite3_value** a) { stWspolrzedna(c, n, a, 0); }
void stMaxX(sqlite3_context* c, int n, sqlite3_value** a) { stWspolrzedna(c, n, a, 1); }
void stMinY(sqlite3_context* c, int n, sqlite3_value** a) { stWspolrzedna(c, n, a, 2); }
void stMaxY(sqlite3_context* c, int n, sqlite3_value** a) { stWspolrzedna(c, n, a, 3); }

void stIsEmpty(sqlite3_context* c, int argc, sqlite3_value** argv) {
    if (argc != 1 || sqlite3_value_type(argv[0]) != SQLITE_BLOB) { sqlite3_result_null(c); return; }
    try {
        std::vector<double> o;
        bool pusta = false;
        obwiedniaBloba(argv[0], o, pusta);
        sqlite3_result_int(c, pusta ? 1 : 0);
    } catch (const std::exception& e) {
        sqlite3_result_error(c, e.what(), -1);
    }
}

void stGeometryType(sqlite3_context* c, int argc, sqlite3_value** argv) {
    if (argc != 1 || sqlite3_value_type(argv[0]) != SQLITE_BLOB) { sqlite3_result_null(c); return; }
    try {
        std::string b(static_cast<const char*>(sqlite3_value_blob(argv[0])),
                      static_cast<size_t>(sqlite3_value_bytes(argv[0])));
        Geometria g = czytajWkb(czytajGpb(b).wkb);
        sqlite3_result_text(c, nazwaRodzaju(g.rodzaj), -1, SQLITE_STATIC);
    } catch (const std::exception& e) {
        sqlite3_result_error(c, e.what(), -1);
    }
}

void stSrid(sqlite3_context* c, int argc, sqlite3_value** argv) {
    if (argc != 1 || sqlite3_value_type(argv[0]) != SQLITE_BLOB) { sqlite3_result_null(c); return; }
    try {
        std::string b(static_cast<const char*>(sqlite3_value_blob(argv[0])),
                      static_cast<size_t>(sqlite3_value_bytes(argv[0])));
        sqlite3_result_int(c, czytajGpb(b).srs);
    } catch (const std::exception& e) {
        sqlite3_result_error(c, e.what(), -1);
    }
}

}  // namespace

std::string cytujNazwe(const std::string& n) {
    std::string w = "\"";
    for (char ch : n) {
        if (ch == '"') w += "\"\"";
        else w += ch;
    }
    return w + "\"";
}

void zarejestrujFunkcjeGpkg(sqlite3* db) {
    struct F { const char* nazwa; void (*f)(sqlite3_context*, int, sqlite3_value**); };
    const F funkcje[] = {
        {"ST_MinX", stMinX}, {"ST_MaxX", stMaxX}, {"ST_MinY", stMinY}, {"ST_MaxY", stMaxY},
        {"ST_IsEmpty", stIsEmpty}, {"ST_GeometryType", stGeometryType}, {"ST_SRID", stSrid},
    };
    for (const auto& f : funkcje) {
        if (sqlite3_create_function(db, f.nazwa, 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nullptr, f.f, nullptr,
                                    nullptr) != SQLITE_OK)
            throw Blad(std::string("nie udało się zarejestrować ") + f.nazwa);
    }
}

Gpkg::Gpkg(const std::string& sciezka, bool doZapisu) : sciezka_(sciezka) {
    const int flagi = doZapisu ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY;
    if (sqlite3_open_v2(sciezka.c_str(), &db_, flagi, nullptr) != SQLITE_OK) {
        std::string e = db_ ? sqlite3_errmsg(db_) : "brak pamięci";
        sqlite3_close(db_);
        db_ = nullptr;
        throw Blad("nie mogę otworzyć " + sciezka + ": " + e);
    }
    zarejestrujFunkcjeGpkg(db_);
}

Gpkg::~Gpkg() { sqlite3_close(db_); }

void Gpkg::wykonaj(const std::string& sql) {
    char* e = nullptr;
    if (sqlite3_exec(db_, sql.c_str(), nullptr, nullptr, &e) != SQLITE_OK) {
        std::string t = e ? e : "?";
        sqlite3_free(e);
        throw Blad("SQLite: " + t + " — w: " + sql);
    }
}

void Gpkg::poczatek() { wykonaj("BEGIN"); }
void Gpkg::zatwierdz() { wykonaj("COMMIT"); }
void Gpkg::wycofaj() { sqlite3_exec(db_, "ROLLBACK", nullptr, nullptr, nullptr); }

std::string Gpkg::integralnosc() {
    Zapytanie z(db_, "PRAGMA integrity_check");
    std::string w;
    while (z.krok(db_)) {
        if (!w.empty()) w += "; ";
        w += z.tekst(0);
    }
    return w;
}

std::string Gpkg::trybDziennika() {
    Zapytanie z(db_, "PRAGMA journal_mode");
    return z.krok(db_) ? z.tekst(0) : std::string();
}

std::vector<std::string> Gpkg::warstwy() {
    Zapytanie z(db_, "SELECT table_name FROM gpkg_contents WHERE data_type = 'features' ORDER BY table_name");
    std::vector<std::string> w;
    while (z.krok(db_)) w.push_back(z.tekst(0));
    return w;
}

Warstwa Gpkg::czytaj(const std::string& tabela) {
    Warstwa w;
    w.tabela = tabela;
    {
        Zapytanie z(db_,
                    "SELECT g.column_name, g.geometry_type_name, g.srs_id, g.z, g.m, "
                    "s.srs_name, s.definition FROM gpkg_geometry_columns g "
                    "LEFT JOIN gpkg_spatial_ref_sys s ON s.srs_id = g.srs_id WHERE g.table_name = ?");
        sqlite3_bind_text(z.st, 1, tabela.c_str(), -1, SQLITE_TRANSIENT);
        if (!z.krok(db_)) throw Blad("warstwa " + tabela + " nie ma wpisu w gpkg_geometry_columns");
        w.kolumnaGeom = z.tekst(0);
        w.typGeom = z.tekst(1);
        w.srs = sqlite3_column_int(z.st, 2);
        w.z = sqlite3_column_int(z.st, 3);
        w.m = sqlite3_column_int(z.st, 4);
        w.srsNazwa = z.tekst(5);
        w.srsDefinicja = z.tekst(6);
    }
    {
        Zapytanie z(db_, "PRAGMA table_info(" + cytujNazwe(tabela) + ")");
        while (z.krok(db_)) {
            Kolumna k;
            k.nazwa = z.tekst(1);
            k.typ = z.tekst(2);
            k.niepusta = sqlite3_column_int(z.st, 3) != 0;
            k.maDomyslna = sqlite3_column_type(z.st, 4) != SQLITE_NULL;
            k.domyslna = z.tekst(4);
            k.klucz = sqlite3_column_int(z.st, 5) != 0;
            if (k.klucz) {
                if (!w.kolumnaFid.empty()) throw Blad("warstwa " + tabela + " ma klucz złożony — nieobsługiwane");
                w.kolumnaFid = k.nazwa;
                continue;
            }
            if (k.nazwa == w.kolumnaGeom) continue;
            w.kolumny.push_back(k);
        }
        if (w.kolumnaFid.empty()) throw Blad("warstwa " + tabela + " nie ma klucza głównego");
    }
    std::string sql = "SELECT " + cytujNazwe(w.kolumnaFid) + ", " + cytujNazwe(w.kolumnaGeom);
    for (const auto& k : w.kolumny) sql += ", " + cytujNazwe(k.nazwa);
    sql += " FROM " + cytujNazwe(tabela) + " ORDER BY " + cytujNazwe(w.kolumnaFid);
    Zapytanie z(db_, sql);
    while (z.krok(db_)) {
        Obiekt o;
        o.fid = sqlite3_column_int64(z.st, 0);
        Wartosc g = wartoscKolumny(z.st, 1);
        if (g.klasa == Klasa::Blob) {
            o.maGeometrie = true;
            o.blob = g.s;
        } else if (g.klasa != Klasa::Null) {
            throw Blad("warstwa " + tabela + ", fid " + std::to_string(o.fid) + ": geometria nie jest blobem");
        }
        for (size_t i = 0; i < w.kolumny.size(); ++i) o.pola.push_back(wartoscKolumny(z.st, static_cast<int>(i + 2)));
        w.obiekty.push_back(std::move(o));
    }
    return w;
}

int Gpkg::zapisz(const Warstwa& s, const Obiekt& o) {
    std::string sql = "UPDATE " + cytujNazwe(s.tabela) + " SET " + cytujNazwe(s.kolumnaGeom) + " = ?1";
    for (size_t i = 0; i < s.kolumny.size(); ++i)
        sql += ", " + cytujNazwe(s.kolumny[i].nazwa) + " = ?" + std::to_string(i + 2);
    sql += " WHERE " + cytujNazwe(s.kolumnaFid) + " = ?" + std::to_string(s.kolumny.size() + 2);
    Zapytanie z(db_, sql);
    zwiaz(db_, z.st, 1, o.maGeometrie ? Wartosc::blob(o.blob) : Wartosc::null_());
    if (o.pola.size() != s.kolumny.size()) throw Blad("liczba pól obiektu nie zgadza się ze schematem");
    for (size_t i = 0; i < o.pola.size(); ++i) zwiaz(db_, z.st, static_cast<int>(i + 2), o.pola[i]);
    sqlite3_bind_int64(z.st, static_cast<int>(s.kolumny.size() + 2), o.fid);
    z.krok(db_);
    return sqlite3_changes(db_);
}

int64_t Gpkg::wstaw(const Warstwa& s, const Obiekt& o) {
    std::string sql = "INSERT INTO " + cytujNazwe(s.tabela) + " (" + cytujNazwe(s.kolumnaGeom);
    for (const auto& k : s.kolumny) sql += ", " + cytujNazwe(k.nazwa);
    sql += ") VALUES (?1";
    for (size_t i = 0; i < s.kolumny.size(); ++i) sql += ", ?" + std::to_string(i + 2);
    sql += ")";
    Zapytanie z(db_, sql);
    zwiaz(db_, z.st, 1, o.maGeometrie ? Wartosc::blob(o.blob) : Wartosc::null_());
    if (o.pola.size() != s.kolumny.size()) throw Blad("liczba pól obiektu nie zgadza się ze schematem");
    for (size_t i = 0; i < o.pola.size(); ++i) zwiaz(db_, z.st, static_cast<int>(i + 2), o.pola[i]);
    z.krok(db_);
    return sqlite3_last_insert_rowid(db_);
}

}  // namespace wfcad
