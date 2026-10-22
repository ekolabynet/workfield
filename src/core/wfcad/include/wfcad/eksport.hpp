// Eksport GeoPackage -> rysunek (DXF albo .wfr) — jedna droga dla wfcad-obieg
// i dla aplikacji WorkFieldGIS (Eksport do CAD). Wcześniej żyła w main()
// narzędzia; aplikacja nie powinna jej powtarzać.
#pragma once

#include <cstddef>
#include <string>

#include "wfcad/typy.hpp"

namespace wfcad {

constexpr int UKLAD_AUTO = -1;   // strefa PL-2000 dobrana z położenia danych
constexpr int UKLAD_BRAK = 0;    // współrzędne jak w źródle

struct WynikEksportu {
    std::string md5Zrodla;
    int uklad = 0;               // EPSG układu rysunku; 0 = bez przeliczenia
    size_t warstw = 0;
    size_t obiektow = 0;
    size_t encji = 0;
};

// Rysunek z bazy \a zrodlo do \a wyjscie (.dxf = DXF R2013, inaczej .wfr).
// \a uklad: UKLAD_AUTO, UKLAD_BRAK albo 2176..2179. Źródło tylko do odczytu;
// odmawia przy niepustym -wal/-journal i gdy źródło zmieni się w trakcie.
WynikEksportu eksportuj(const std::string& zrodlo, const std::string& wyjscie, int uklad, Raport& raport);

// Treść lisp/wf.lsp wkompilowana w rdzeń (core/src/wf_lsp.inc, generowana
// narzedzia/zbuduj_lsp_inc.py; test „lsp” pilnuje zgodności z lisp/wf.lsp).
const std::string& tekstWfLsp();

}  // namespace wfcad
