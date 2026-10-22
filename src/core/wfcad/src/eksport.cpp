#include "wfcad/eksport.hpp"

#include <filesystem>

#include "wfcad/dxf.hpp"
#include "wfcad/gpkg.hpp"
#include "wfcad/odwzorowanie.hpp"
#include "wfcad/rysunek.hpp"
#include "wfcad/skrot.hpp"
#include "wfcad/uklad.hpp"

namespace wfcad {

namespace {
#include "wf_lsp.inc"
}  // namespace

WynikEksportu eksportuj(const std::string& zrodlo, const std::string& wyjscie, int uklad, Raport& raport) {
    if (uklad != UKLAD_AUTO && uklad != UKLAD_BRAK && !strefaPl2000(uklad))
        throw Blad("układ rysunku " + std::to_string(uklad) + " — dozwolone auto, brak albo EPSG 2176–2179");
    sprawdzDomkniecie(zrodlo);
    Zrodlo z;
    z.sciezka = std::filesystem::absolute(zrodlo).string();
    z.md5 = md5Pliku(zrodlo);
    z.rozmiar = static_cast<int64_t>(std::filesystem::file_size(zrodlo));
    std::vector<Warstwa> warstwy;
    {
        Gpkg db(zrodlo, false);
        for (const auto& t : db.warstwy()) warstwy.push_back(db.czytaj(t));
    }
    // Wczytanie nie może zmienić źródła — sprawdzone sumą, nie założone.
    if (md5Pliku(zrodlo) != z.md5) throw Blad("źródło zmieniło się podczas wczytywania");

    const bool dxf = wyjscie.size() > 4 && (wyjscie.compare(wyjscie.size() - 4, 4, ".dxf") == 0 ||
                                             wyjscie.compare(wyjscie.size() - 4, 4, ".DXF") == 0);
    OpcjeRysunku opcje;
    opcje.mpolygon = !dxf;
    opcje.uklad = uklad == UKLAD_AUTO ? dobierzStrefe(warstwy) : uklad;
    Rysunek rys = doRysunku(warstwy, z, raport, opcje);
    if (dxf) zapiszDxf(rys, wyjscie);
    else zapiszRysunek(rys, wyjscie);

    WynikEksportu w;
    w.md5Zrodla = z.md5;
    w.uklad = opcje.uklad;
    w.warstw = warstwy.size();
    for (const auto& x : warstwy) w.obiektow += x.obiekty.size();
    w.encji = rys.encje.size();
    return w;
}

const std::string& tekstWfLsp() {
    static const std::string t = [] {
        std::string s;
        for (const char* k : WF_LSP) s += k;
        return s;
    }();
    return t;
}

}  // namespace wfcad
