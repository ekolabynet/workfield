// dxf.hpp — rysunek WorkFieldCAD jako plik DXF i z powrotem.
//
// DXF to tekstowy (albo binarny) zapis tego samego modelu co DWG, więc
// XRecordy w słownikach rozszerzeń obiektów i słownik nazwanych obiektów
// mają w nim swoje kody. Plik otwiera każdy CAD — bez wtyczki i bez SDK.
//
// Zapis: DXF R2013 (AC1027, tekst UTF-8), liczby z 17 cyframi znaczącymi,
// czyli co do bitu. Obiekty: POINT, LWPOLYLINE, POLYLINE 3D. MPOLYGON nie
// jest zapisywany (rysunek do DXF budować z OpcjeRysunku::mpolygon = false).
//
// Odczyt: DXF tekstowy i binarny, dowolnej wersji R2000+, także przepisany
// przez CAD (inne uchwyty, kolejność, mniej cyfr w liczbach — tę różnicę
// rdzeń dociąga do wartości dokładnych z XRecordu).
#pragma once

#include <string>

#include "wfcad/rysunek.hpp"
#include "wfcad/typy.hpp"

namespace wfcad {

void zapiszDxf(const Rysunek& r, const std::string& sciezka);
Rysunek wczytajDxf(const std::string& sciezka, Raport& raport);

// Czy plik wygląda na DXF (tekstowy albo binarny), a nie na .wfr.
bool czyDxf(const std::string& sciezka);

}  // namespace wfcad
