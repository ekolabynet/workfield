#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
geom_gpkg.py — geometria z GeoPackage bez GDAL-a. Moduł wspólny, nie czasownik.

    import geom_gpkg as G
    srs, wkb = G.czytaj_blob(blob)
    G.wkt(wkb)                    # WKT, domyślnie 2 miejsca = centymetr
    G.pole(wkb)                   # m² wzorem Gaussa, dziury odjęte
    G.probki(wkb, 60)             # środek + wierzchołki do głosowania
    G.zawiera(wkb, (x, y))        # punkt w poligonie, z dziurami

Dlaczego osobny plik, a nie wklejka w każdym czasowniku: tego samego parsera
potrzebują `scal_parki.py` (kolumna WKT) i `odzysk_zdjec.py` (dopasowanie
zdjęć po geometrii, gdy `fid` przestał znaczyć to samo). Wklejony dwa razy
rozjedzie się przy pierwszej poprawce — tak powstały `scal_pze_02_09`,
`_04_09` i `_07_09`: jeden czasownik, trzy daty.

NIE WYMAGA NICZEGO poza biblioteką standardową. Czasowniki mają działać na
laptopie w terenie, a nie po instalacji pakietów.
"""
import math
import os
import struct
import urllib.parse

WERSJA = "1.2.0"


def uri_ro(sciezka):
    """URI „tylko do odczytu” dla SQLite, z poprawnym cytowaniem ścieżki.

    Spacja w nazwie pliku psuje URI i `sqlite3.connect(uri=True)` zglasza
    „unable to open database file”, jakby pliku nie bylo. 19.10 na telefonie
    lezalo `Foto Add.gpkg` — nazwa ze spacja jest normalna, a komunikat
    wysyla na zle poszukiwania."""
    return "file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(
        os.path.expanduser(sciezka)))


def czytaj_blob(b):
    """Zwraca (srs_id, wkb). Nagłówek GPKG: 'GP', wersja, flagi, srs_id, obwiednia.

    Flagi: bit0 kolejność bajtów nagłówka, bity 1–3 rodzaj obwiedni,
    bit4 geometria pusta. Obwiednia ma 0, 32, 48 albo 64 bajty — pominięcie
    tego pola przesuwa start WKB i geometria wychodzi jako śmieć."""
    if not b or len(b) < 8 or b[0:2] != b"GP":
        return (None, None)
    flagi = b[3]
    e = "<" if (flagi & 1) == 1 else ">"
    srs = struct.unpack(e + "i", b[4:8])[0]
    dlug = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}.get((flagi >> 1) & 0x07)
    if dlug is None or (flagi >> 4) & 1:
        return (srs, None)
    return (srs, b[8 + dlug:])


def _wsp(bufor, poz, e, wymiarow):
    x, y = struct.unpack_from(e + "dd", bufor, poz)
    return (x, y), poz + 8 * wymiarow


def _pierscien(bufor, poz, e, wymiarow):
    n, = struct.unpack_from(e + "I", bufor, poz)
    poz += 4
    punkty = []
    for _ in range(n):
        p, poz = _wsp(bufor, poz, e, wymiarow)
        punkty.append(p)
    return punkty, poz


def rozbierz(bufor, poz=0):
    """(rodzaj, dane, nowa pozycja). Rodzaje 1–7, ISO (1001+) i EWKB (0x8...)."""
    e = "<" if bufor[poz] == 1 else ">"
    typ, = struct.unpack_from(e + "I", bufor, poz + 1)
    poz += 5
    wymiarow = 2
    if typ & 0x80000000:
        wymiarow += 1
    if typ & 0x40000000:
        wymiarow += 1
    if typ & 0x20000000:
        poz += 4
    baza = typ & 0xFFFF
    if 1000 <= baza < 4000:
        t = baza // 1000
        wymiarow = 2 + (1 if t in (1, 3) else 0) + (1 if t in (2, 3) else 0)
        baza = baza % 1000

    if baza == 1:
        p, poz = _wsp(bufor, poz, e, wymiarow)
        return ("POINT", p, poz)
    if baza == 2:
        r, poz = _pierscien(bufor, poz, e, wymiarow)
        return ("LINESTRING", r, poz)
    if baza == 3:
        n, = struct.unpack_from(e + "I", bufor, poz)
        poz += 4
        p = []
        for _ in range(n):
            r, poz = _pierscien(bufor, poz, e, wymiarow)
            p.append(r)
        return ("POLYGON", p, poz)
    if baza in (4, 5, 6, 7):
        n, = struct.unpack_from(e + "I", bufor, poz)
        poz += 4
        s = []
        for _ in range(n):
            r = rozbierz(bufor, poz)
            s.append((r[0], r[1]))
            poz = r[2]
        return ({4: "MULTIPOINT", 5: "MULTILINESTRING", 6: "MULTIPOLYGON",
                 7: "GEOMETRYCOLLECTION"}[baza], s, poz)
    raise ValueError("nieznany rodzaj geometrii WKB: %d" % baza)


def wkt(wkb, miejsc=2):
    """WKT z WKB. Domyślnie 2 miejsca po kropce — w PL-2000 to centymetr.

    Dokładność nie jest kosmetyką: WKT płatu o kilkuset wierzchołkach przy
    pełnej precyzji float przekracza 32 767 znaków, czyli granicę komórki
    arkusza. Centymetr skraca zapis o połowę i niczego nie gubi."""
    if not wkb:
        return ""

    def licz(v):
        if not miejsc:
            return "%d" % round(v)
        s = ("%.*f" % (miejsc, v)).rstrip("0").rstrip(".")
        return "0" if s in ("-0", "") else s

    def pkt(p):
        return "%s %s" % (licz(p[0]), licz(p[1]))

    def wypisz(rodzaj, dane):
        if rodzaj == "POINT":
            return "POINT (%s)" % pkt(dane)
        if rodzaj == "LINESTRING":
            return "LINESTRING (%s)" % ", ".join(pkt(p) for p in dane)
        if rodzaj == "POLYGON":
            return "POLYGON (%s)" % ", ".join(
                "(%s)" % ", ".join(pkt(p) for p in r) for r in dane)
        if rodzaj == "MULTIPOINT":
            return "MULTIPOINT (%s)" % ", ".join("(%s)" % pkt(d) for _, d in dane)
        if rodzaj == "MULTILINESTRING":
            return "MULTILINESTRING (%s)" % ", ".join(
                "(%s)" % ", ".join(pkt(p) for p in d) for _, d in dane)
        if rodzaj == "MULTIPOLYGON":
            return "MULTIPOLYGON (%s)" % ", ".join(
                "(%s)" % ", ".join("(%s)" % ", ".join(pkt(p) for p in r) for r in d)
                for _, d in dane)
        if rodzaj == "GEOMETRYCOLLECTION":
            return "GEOMETRYCOLLECTION (%s)" % ", ".join(wypisz(t, d) for t, d in dane)
        raise ValueError(rodzaj)

    r, d, _ = rozbierz(wkb, 0)
    return wypisz(r, d)


def _pole_pierscienia(r):
    s = 0.0
    for i in range(len(r)):
        x1, y1 = r[i]
        x2, y2 = r[(i + 1) % len(r)]
        s += x1 * y2 - x2 * y1
    return abs(s) / 2.0


def poligony(wkb):
    """Lista poligonów jako list pierścieni. Pusta, gdy to nie poligon."""
    if not wkb:
        return []
    r, d, _ = rozbierz(wkb, 0)
    if r == "POLYGON":
        return [d]
    if r == "MULTIPOLYGON":
        return [x for _, x in d]
    if r == "GEOMETRYCOLLECTION":
        w = []
        for t, x in d:
            if t == "POLYGON":
                w.append(x)
            elif t == "MULTIPOLYGON":
                w += [y for _, y in x]
        return w
    return []


def pole(wkb):
    """Powierzchnia wzorem Gaussa, dziury odjęte. None, gdy to nie poligon."""
    p = poligony(wkb)
    if not p:
        return None
    s = 0.0
    for pier in p:
        if pier:
            s += _pole_pierscienia(pier[0]) - sum(_pole_pierscienia(r)
                                                  for r in pier[1:])
    return s


def obwiednia(wkb):
    """(min_x, min_y, max_x, max_y) — do odsiewu przed testem punktowym."""
    p = poligony(wkb)
    if not p:
        return None
    xs = [x for pier in p for r in pier for x, _ in r]
    ys = [y for pier in p for r in pier for _, y in r]
    return (min(xs), min(ys), max(xs), max(ys)) if xs else None


def srodek(wkb):
    """Środek ciężkości powierzchni. UWAGA: przy kształcie wklęsłym może leżeć
    POZA poligonem — dlatego sam środek nie wystarcza do dopasowania płatu
    i do tego służy `probki`."""
    p = poligony(wkb)
    if not p:
        return None
    sx = sy = sa = 0.0
    for pier in p:
        if not pier:
            continue
        r = pier[0]
        a2 = 0.0
        cx = cy = 0.0
        for i in range(len(r)):
            x1, y1 = r[i]
            x2, y2 = r[(i + 1) % len(r)]
            w = x1 * y2 - x2 * y1
            a2 += w
            cx += (x1 + x2) * w
            cy += (y1 + y2) * w
        if a2 == 0:
            continue
        sx += cx / 3.0
        sy += cy / 3.0
        sa += a2
    if sa == 0:
        r = p[0][0]
        return (sum(x for x, _ in r) / len(r), sum(y for _, y in r) / len(r))
    return (sx / sa, sy / sa)


def probki(wkb, ile=60):
    """Punkty WEWNĄTRZ płatu, rozłożone równomiernie po jego powierzchni.

    Po co, a nie sam środek: środek płatu wklęsłego (a takie są płaty docinane
    do ścieżek) wypada poza nim i trafiałby w sąsiada. Rozłożone punkty
    przybliżają to, który dzisiejszy płat pokrywa NAJWIĘCEJ powierzchni
    dawnego — bez przycinania poligonów, czyli bez GDAL-a.

    Dlaczego nie wierzchołki: wierzchołek leży DOKŁADNIE na krawędzi, a po
    przesunięciu granicy wypada raz po jednej, raz po drugiej stronie.
    Głosowanie wierzchołkami pobierałoby głosy z miejsc najmniej stabilnych —
    sprawdzone: na kwadracie 2 z 6 wierzchołków dają inny wynik niż shapely,
    bo „w środku" na samej krawędzi nie jest zdefiniowane. Punkty z siatki
    leżą w głębi i są jednoznaczne (0 rozbieżności na 4000 losowych)."""
    p = poligony(wkb)
    if not p:
        return []
    bb = obwiednia(wkb)
    if not bb:
        return []
    punkty = []
    s = srodek(wkb)
    if s and zawiera(wkb, s, bb):
        punkty.append(s)
    szer, wys = bb[2] - bb[0], bb[3] - bb[1]
    if szer > 0 and wys > 0:
        # Siatka gęstsza niż `ile`, bo część oczek wypadnie poza płatem.
        n = max(3, int((ile * 2.5) ** 0.5) + 1)
        for i in range(n):
            for j in range(n):
                q = (bb[0] + szer * (i + 0.5) / n, bb[1] + wys * (j + 0.5) / n)
                if zawiera(wkb, q, bb):
                    punkty.append(q)
    if len(punkty) >= 3:
        # Krok w GÓRĘ, i żadnego obcinania na końcu. Przy `len // ile`
        # i `[:ile]` ucinała się końcówka listy, a siatka jest budowana
        # kolumnami — więc przepadały punkty o największym X i głosowanie
        # przestawało być proporcjonalne do powierzchni. Zmierzone: dawny
        # płat przecięty na 71% i 29% dawał głosy 59:1 zamiast ~71:29.
        krok = -(-len(punkty) // ile) if len(punkty) > ile else 1
        return punkty[::krok]
    # Płat-drzazga: siatka go nie trafia. Wtedy wierzchołki ściągnięte o 5%
    # do środka — niedokładne, ale leżą wewnątrz, a lepszego sygnału nie ma.
    w = [x for pier in p for x in pier[0]]
    if s and w:
        punkty += [(x + (s[0] - x) * 0.05, y + (s[1] - y) * 0.05) for x, y in w[:ile]]
    return punkty or ([s] if s else [])


def _w_pierscieniu(r, x, y):
    """Promień poziomy. Wierzchołek dokładnie na promieniu rozstrzyga reguła
    półotwartego przedziału (y1 <= y < y2), inaczej jeden wierzchołek liczy
    się dwa razy i punkt wychodzi na zewnątrz."""
    w = False
    n = len(r)
    for i in range(n):
        x1, y1 = r[i]
        x2, y2 = r[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            if y2 != y1 and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                w = not w
    return w


def zawiera(wkb, punkt, bbox=None):
    """Czy punkt leży w geometrii. Dziury odejmowane."""
    x, y = punkt
    if bbox and not (bbox[0] <= x <= bbox[2] and bbox[1] <= y <= bbox[3]):
        return False
    for pier in poligony(wkb):
        if not pier or not _w_pierscieniu(pier[0], x, y):
            continue
        if any(_w_pierscieniu(d, x, y) for d in pier[1:]):
            continue        # w dziurze, czyli poza płatem
        return True
    return False


# ===========================================================================
#  WSPÓŁRZĘDNE — WGS84 <-> PL-2000, szereg Krügera, bez zależności
# ===========================================================================
#  Potrzebne, żeby zestawić GPS z EXIF-u zdjęcia z geometrią płatu. `pyproj`
#  na laptopie w terenie może nie być, a to jest kilkadziesiąt linii.
#
#  SPRAWDZONE przeciw pyproj 3.7.2 na 868 punktach w strefach 5–8 (49–56° N,
#  ±1,5° od południka każdej strefy): największy rozjazd 0,0002 mm w prostej
#  i 0,0012 mm w odwrotnej.
#
#  Pułapka, w którą wpadłem przy pisaniu: η ma dwie TOŻSAME postacie —
#  atanh(sin dλ / √(1+t²)) albo asinh(sin dλ / hypot(t, cos dλ)). Wolno użyć
#  jednej w całości. Pomieszanie ich daje błąd ROSNĄCY Z ODLEGŁOŚCIĄ OD
#  POŁUDNIKA strefy: zero na południku, 13 m przy brzegu. W Warszawie byłby
#  niewidoczny — czyli najgorszy możliwy rodzaj błędu.

A_ELIPSOIDY = 6378137.0
SPLASZCZENIE = 1 / 298.257222101          # GRS80
E2 = SPLASZCZENIE * (2 - SPLASZCZENIE)
A = A_ELIPSOIDY
F = SPLASZCZENIE


STREFY = {2176: 15.0, 2177: 18.0, 2178: 21.0, 2179: 24.0}
K0 = 0.999923
FE = {2176: 5500000.0, 2177: 6500000.0, 2178: 7500000.0, 2179: 8500000.0}


def _n():
    return F / (2 - F)


def do_2000(lat, lon, epsg=2178):
    """(lat, lon) w stopniach -> (easting, northing) w metrach."""
    n = _n()
    lam0 = math.radians(STREFY[epsg])
    phi, lam = math.radians(lat), math.radians(lon)
    e = math.sqrt(E2)
    # szerokość konforemna
    t = math.sinh(math.atanh(math.sin(phi)) - e * math.atanh(e * math.sin(phi)))
    xi = math.atan(t / math.cos(lam - lam0))
    # η: atanh(sin dλ / √(1+t²)) ALBO asinh(sin dλ / hypot(t, cos dλ)) — te dwie
    # postacie są tożsame, ale wolno użyć tylko jednej w całości. Pomieszanie
    # ich (asinh z argumentem od atanh) daje błąd rosnący z odległością od
    # południka strefy: 0 na południku, 13 m przy brzegu. W Warszawie byłby
    # niewidoczny — i to jest najgorszy rodzaj błędu.
    eta = math.asinh(math.sin(lam - lam0) / math.hypot(t, math.cos(lam - lam0)))
    a_ = A / (1 + n) * (1 + n**2 / 4 + n**4 / 64)
    al = [n/2 - 2*n**2/3 + 5*n**3/16 + 41*n**4/180,
          13*n**2/48 - 3*n**3/5 + 557*n**4/1440,
          61*n**3/240 - 103*n**4/140,
          49561*n**4/161280]
    x = eta + sum(al[j] * math.cos(2*(j+1)*xi) * math.sinh(2*(j+1)*eta) for j in range(4))
    y = xi + sum(al[j] * math.sin(2*(j+1)*xi) * math.cosh(2*(j+1)*eta) for j in range(4))
    return (K0 * a_ * x + FE[epsg], K0 * a_ * y)


def z_2000(e_, n_, epsg=2178):
    """(easting, northing) -> (lat, lon) w stopniach."""
    n = _n()
    a_ = A / (1 + n) * (1 + n**2 / 4 + n**4 / 64)
    xi = n_ / (K0 * a_)
    eta = (e_ - FE[epsg]) / (K0 * a_)
    be = [n/2 - 2*n**2/3 + 37*n**3/96 - n**4/360,
          n**2/48 + n**3/15 - 437*n**4/1440,
          17*n**3/480 - 37*n**4/840,
          4397*n**4/161280]
    xi_ = xi - sum(be[j] * math.sin(2*(j+1)*xi) * math.cosh(2*(j+1)*eta) for j in range(4))
    eta_ = eta - sum(be[j] * math.cos(2*(j+1)*xi) * math.sinh(2*(j+1)*eta) for j in range(4))
    chi = math.asin(math.sin(xi_) / math.cosh(eta_))
    de = [2*n - 2*n**2/3 - 2*n**3 + 116*n**4/45,
          7*n**2/3 - 8*n**3/5 - 227*n**4/45,
          56*n**3/15 - 136*n**4/35,
          4279*n**4/630]
    phi = chi + sum(de[j] * math.sin(2*(j+1)*chi) for j in range(4))
    lam = math.radians(STREFY[epsg]) + math.atan(math.sinh(eta_) / math.cos(xi_))
    return (math.degrees(phi), math.degrees(lam))
