// odwzorowanie.hpp — GIS do rysunku i z powrotem.
//
// Zasada: współrzędne X, Y, Z żyją w obiektach CAD (to je użytkownik
// edytuje), a wszystko, czego CAD nie ma, żyje w XRecordzie obiektu
// („szkielet” geometrii: kolejność bajtów, kod typu, wartości M,
// domknięcia pierścieni, skróty). Odczyt składa jedno z drugim.
//
// Czego obieg NIE zmienia sam: obiekt usunięty w CAD nie jest kasowany
// z bazy — trafia do raportu. Oryginał zostaje.
#pragma once

#include <string>
#include <vector>

#include "wfcad/rysunek.hpp"
#include "wfcad/typy.hpp"

namespace wfcad {

struct Zrodlo {
    std::string sciezka;
    std::string md5;
    int64_t rozmiar = 0;
};

struct OpcjeRysunku {
    // Poligony ze stałym Z jako jeden MPOLYGON (dziury natywnie). Wyłączone:
    // pierścień po pierścieniu jako zamknięte polilinie — dla DXF i dla CAD-ów
    // bez MPOLYGON; przynależność dziur do obrysu niesie XRecord.
    bool mpolygon = true;
    // Układ współrzędnych rysunku: 0 = jak w bazie; 2176–2179 = PL-2000, na
    // który przeliczane są warstwy w EPSG:4326 (dane zostają w stopniach).
    int uklad = 0;
};

Rysunek doRysunku(const std::vector<Warstwa>& warstwy, const Zrodlo& zrodlo, Raport& raport,
                  const OpcjeRysunku& opcje = {});

struct Usuniety {
    std::string tabela;
    int64_t fid = 0;
};

struct Odczyt {
    Zrodlo zrodlo;
    std::vector<Warstwa> warstwy;       // obiekty odtworzone z rysunku
    std::vector<Usuniety> usuniete;     // były przy wczytaniu, nie ma ich w rysunku
    size_t obce = 0;                    // encje CAD bez danych WF
    size_t dociagniete = 0;             // wierzchołki przywrócone do wartości dokładnych
    std::vector<std::string> zmiany;    // każdy zmieniony, nowy i usunięty obiekt, opisany dla człowieka
};

Odczyt zRysunku(const Rysunek& r, Raport& raport);

struct OpcjeZapisu {
    bool wszystko = false;      // przepisz każdy obiekt, nie tylko zmienione
    bool mimoZmianZrodla = false;
};

struct WynikZapisu {
    size_t zmienione = 0, wstawione = 0, pominiete = 0;
};

// Kopiuje źródło do `cel` (cel nie może istnieć) i nanosi na kopię obiekty
// z odczytu. Źródła nie dotyka.
WynikZapisu zapiszDoGpkg(const Odczyt& o, const std::string& zrodlo, const std::string& cel,
                         const OpcjeZapisu& opcje, Raport& raport);

// Wspólne dla wczytania i zapisu: sprawdza, czy baza jest domknięta
// (brak niepustego -wal). Rzuca Blad, gdy nie jest.
void sprawdzDomkniecie(const std::string& sciezka);

uint64_t skrotObiektu(const Obiekt& o);

}  // namespace wfcad
