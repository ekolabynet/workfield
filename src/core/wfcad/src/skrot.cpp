// skrot.cpp — patrz skrot.hpp. MD5 według RFC 1321.
#include "wfcad/skrot.hpp"

#include <algorithm>
#include <array>
#include <cstring>
#include <fstream>
#include <random>

#include "wfcad/typy.hpp"

namespace wfcad {

uint64_t fnv64(const void* dane, size_t n, uint64_t h) {
    const auto* p = static_cast<const unsigned char*>(dane);
    for (size_t i = 0; i < n; ++i) {
        h ^= p[i];
        h *= 1099511628211ull;
    }
    return h;
}

std::string hex64(uint64_t v) {
    static const char* c = "0123456789abcdef";
    std::string s(16, '0');
    for (int i = 15; i >= 0; --i) {
        s[static_cast<size_t>(i)] = c[v & 0xF];
        v >>= 4;
    }
    return s;
}

namespace {

class Md5 {
public:
    Md5() { a_ = 0x67452301; b_ = 0xefcdab89; c_ = 0x98badcfe; d_ = 0x10325476; }

    void dodaj(const unsigned char* p, size_t n) {
        dlugosc_ += n;
        while (n > 0) {
            size_t ile = std::min(n, size_t{64} - wBuforze_);
            std::memcpy(bufor_ + wBuforze_, p, ile);
            wBuforze_ += ile;
            p += ile;
            n -= ile;
            if (wBuforze_ == 64) {
                blok(bufor_);
                wBuforze_ = 0;
            }
        }
    }

    std::string koniec() {
        const uint64_t bity = dlugosc_ * 8;
        const unsigned char jedynka = 0x80;
        dodaj(&jedynka, 1);
        const unsigned char zero = 0;
        while (wBuforze_ != 56) dodaj(&zero, 1);
        unsigned char d[8];
        for (int i = 0; i < 8; ++i) d[i] = static_cast<unsigned char>(bity >> (8 * i));
        dodaj(d, 8);
        static const char* h = "0123456789abcdef";
        std::string s;
        for (uint32_t v : {a_, b_, c_, d_})
            for (int i = 0; i < 4; ++i) {
                unsigned char b = static_cast<unsigned char>(v >> (8 * i));
                s += h[b >> 4];
                s += h[b & 0xF];
            }
        return s;
    }

private:
    static uint32_t rol(uint32_t x, int c) { return (x << c) | (x >> (32 - c)); }

    void blok(const unsigned char* p) {
        static const uint32_t K[64] = {
            0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
            0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
            0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
            0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
            0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
            0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
            0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
            0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391};
        static const int S[64] = {7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
                                  5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20,
                                  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
                                  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21};
        uint32_t M[16];
        for (int i = 0; i < 16; ++i)
            M[i] = static_cast<uint32_t>(p[i * 4]) | (static_cast<uint32_t>(p[i * 4 + 1]) << 8) |
                   (static_cast<uint32_t>(p[i * 4 + 2]) << 16) | (static_cast<uint32_t>(p[i * 4 + 3]) << 24);
        uint32_t A = a_, B = b_, C = c_, D = d_;
        for (int i = 0; i < 64; ++i) {
            uint32_t F;
            int g;
            if (i < 16) { F = (B & C) | (~B & D); g = i; }
            else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
            else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
            else { F = C ^ (B | ~D); g = (7 * i) % 16; }
            F = F + A + K[i] + M[g];
            A = D;
            D = C;
            C = B;
            B = B + rol(F, S[i]);
        }
        a_ += A; b_ += B; c_ += C; d_ += D;
    }

    uint32_t a_, b_, c_, d_;
    unsigned char bufor_[64];
    size_t wBuforze_ = 0;
    uint64_t dlugosc_ = 0;
};

}  // namespace

std::string md5(const std::string& dane) {
    Md5 m;
    m.dodaj(reinterpret_cast<const unsigned char*>(dane.data()), dane.size());
    return m.koniec();
}

std::string md5Pliku(const std::string& sciezka) {
    std::ifstream f(sciezka, std::ios::binary);
    if (!f) throw Blad("nie mogę otworzyć " + sciezka);
    Md5 m;
    std::array<char, 1 << 16> b{};
    while (f) {
        f.read(b.data(), b.size());
        std::streamsize n = f.gcount();
        if (n > 0) m.dodaj(reinterpret_cast<const unsigned char*>(b.data()), static_cast<size_t>(n));
    }
    return m.koniec();
}

std::string nowyUuid() {
    static std::mt19937_64 gen{[] {
        std::random_device rd;
        return (static_cast<uint64_t>(rd()) << 32) ^ rd();
    }()};
    uint64_t a = gen(), b = gen();
    a = (a & 0xFFFFFFFFFFFF0FFFull) | 0x0000000000004000ull;   // wersja 4
    b = (b & 0x3FFFFFFFFFFFFFFFull) | 0x8000000000000000ull;   // wariant RFC 4122
    std::string h = hex64(a) + hex64(b);
    return h.substr(0, 8) + "-" + h.substr(8, 4) + "-" + h.substr(12, 4) + "-" + h.substr(16, 4) + "-" +
           h.substr(20, 12);
}

}  // namespace wfcad
