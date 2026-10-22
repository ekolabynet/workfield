// skrot.hpp — sumy kontrolne i identyfikatory.
#pragma once

#include <cstdint>
#include <string>

namespace wfcad {

// FNV-1a 64 — szybki skrót do wykrywania zmian obiektu. Nie kryptograficzny:
// służy do pytania „czy to się zmieniło od wczytania”, nie do ochrony.
uint64_t fnv64(const void* dane, size_t n, uint64_t start = 1469598103934665603ull);
inline uint64_t fnv64(const std::string& s, uint64_t start = 1469598103934665603ull) {
    return fnv64(s.data(), s.size(), start);
}

// MD5 pliku w postaci szesnastkowej, ta sama co z `md5sum`. Do sprawdzenia,
// czy baza źródłowa zmieniła się od wczytania do rysunku — w obiegu
// WorkFielda o tym, który plik jest który, rozstrzygają sumy, nie daty.
std::string md5Pliku(const std::string& sciezka);
std::string md5(const std::string& dane);

// UUID wersji 4, małe litery, z myślnikami.
std::string nowyUuid();

std::string hex64(uint64_t v);

}  // namespace wfcad
