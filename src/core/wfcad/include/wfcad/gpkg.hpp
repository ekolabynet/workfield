// gpkg.hpp — odczyt i zapis GeoPackage przez czysty SQLite.
//
// Bez GDAL-a celowo: wtyczka ładuje się do procesu CAD-a, który może mieć
// własną kopię GDAL-a w innej wersji. SQLite jest wszędzie i jest mały.
#pragma once

#include <string>
#include <vector>

#include "wfcad/typy.hpp"

struct sqlite3;

namespace wfcad {

class Gpkg {
public:
    Gpkg(const std::string& sciezka, bool doZapisu);
    ~Gpkg();
    Gpkg(const Gpkg&) = delete;
    Gpkg& operator=(const Gpkg&) = delete;

    // Tabele z gpkg_contents o data_type = 'features'.
    std::vector<std::string> warstwy();

    // Schemat i wszystkie obiekty warstwy.
    Warstwa czytaj(const std::string& tabela);

    // UPDATE wszystkich pól i geometrii obiektu o danym fid.
    // Zwraca liczbę zmienionych wierszy (0 = nie ma takiego fid).
    int zapisz(const Warstwa& schemat, const Obiekt& o);
    // INSERT; zwraca nadany fid.
    int64_t wstaw(const Warstwa& schemat, const Obiekt& o);

    void poczatek();
    void zatwierdz();
    void wycofaj();
    // Wynik PRAGMA integrity_check; "ok" gdy wszystko w porządku.
    std::string integralnosc();
    // Tryb dziennika ("delete", "wal", ...).
    std::string trybDziennika();

    sqlite3* uchwyt() { return db_; }

private:
    void wykonaj(const std::string& sql);
    sqlite3* db_ = nullptr;
    std::string sciezka_;
};

// Funkcje SQL, których wymagają wyzwalacze R-tree zakładane przez GDAL
// i QGIS (ST_MinX, ST_MaxX, ST_MinY, ST_MaxY, ST_IsEmpty, ...). Bez nich
// pierwszy UPDATE geometrii kończy się błędem „no such function”.
void zarejestrujFunkcjeGpkg(sqlite3* db);

std::string cytujNazwe(const std::string& nazwa);

}  // namespace wfcad
