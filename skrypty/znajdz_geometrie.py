#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Szuka UTRACONYCH GEOMETRII w starszych kopiach baz.

==========================================================================
PO CO
==========================================================================
W zwrocie z 25.08.2026 czternascie platow ma geometrie zniszczona albo pusta.
Piec z nich niesie prawdziwa robote — opis, spis gatunkow z pokryciem,
zdjecie, zalaczniki. Sam obrys zginal.

Ale te platy ISTNIALY wczesniej z geometria. Starsze kopie bazy moga ja
nadal miec — i wtedy nie trzeba niczego obrysowywac od nowa.

==========================================================================
DLACZEGO DOPASOWANIE PO TRESCI, A NIE PO fid
==========================================================================
`fid` przenumerowaly sie przy odbudowie projektu 8_0 (21.08): tabela zostala
odtworzona, a AUTOINCREMENT liczy od najwyzszego, jaki kiedykolwiek byl.
Ten sam plat mial fid 159 w jednej wersji i 235 w nastepnej.

Dopasowujemy wiec po tym, co sie NIE zmienia:

  1. FOTO            — nazwa pliku zdjecia; najmocniejszy klucz,
  2. OPIS_PŁATU      — pierwsze 60 znakow, bo koncowka bywa dopisywana,
  3. ZAPIS_SUROWY_GATUNKI — pierwsze 60 znakow.

Wystarczy JEDNO trafienie z tych trzech. Przy dwoch kandydatach skrypt
nie zgaduje — wypisuje oba i zostawia decyzje czlowiekowi.

==========================================================================
CZEGO NIE ROBI
==========================================================================
**Niczego nie zapisuje.** To jest wylacznie wyszukiwanie: mowi, gdzie leży
geometria i jaka ma wielkosc. Przeniesienie to osobna, swiadoma operacja —
bo wstawienie cudzej geometrii do rekordu jest zmiana nieodwracalna,
a przy blednym dopasowaniu przenioslby sie obrys innego platu.

Uzycie:
    python3 znajdz_geometrie.py NOWA_BAZA.gpkg KATALOG_ZE_STARSZYMI [...]

    python3 znajdz_geometrie.py \\
        ~/WorkField/zwroty/zzw_2026/2026-08-25_pgrs_v10_0/dane.gpkg \\
        ~/WorkField/zwroty/zzw_2026 ~/WorkField/wydania
"""
import os
import struct
import sqlite3
import sys

TABELA = "FITO_PLATY"
KLUCZE = ["FOTO", "OPIS_PŁATU", "ZAPIS_SUROWY_GATUNKI"]
DLUGOSC = 60


def pusta(g):
    """Bit 4 flag naglowka GPKG: geometria PUSTA (nie NULL)."""
    return not g or (len(g) > 3 and g[:2] == b"GP" and bool(g[3] & 0x10))


def bok(g):
    """Dluzszy bok obwiedni w metrach; None gdy sie nie da odczytac."""
    if not g or len(g) < 40 or g[:2] != b"GP":
        return None
    f = g[3]
    if (f >> 1) & 7 == 0:
        return None
    e = "<" if f & 1 else ">"
    x0, x1, y0, y1 = struct.unpack_from(e + "4d", g, 8)
    return max(x1 - x0, y1 - y0)


def skroc(v):
    return str(v).strip()[:DLUGOSC] if v else None


def wczytaj(sciezka):
    """{klucz: [(fid, bok, geom)]} — wszystkie platy Z GEOMETRIA."""
    try:
        con = sqlite3.connect("file:%s?mode=ro" % sciezka, uri=True)
        kol = [r[1] for r in con.execute('PRAGMA table_info("%s")' % TABELA)]
    except sqlite3.Error:
        return {}
    if "geom" not in kol:
        con.close(); return {}

    uzyte = [k for k in KLUCZE if k in kol]
    if not uzyte:
        con.close(); return {}

    mapa = {}
    zapyt = 'SELECT fid, geom, %s FROM "%s"' % (", ".join('"%s"' % k for k in uzyte), TABELA)
    for wiersz in con.execute(zapyt):
        fid, geom = wiersz[0], wiersz[1]
        if pusta(geom):
            continue
        b = bok(geom)
        if b is None or b < 0.5:      # zlepki nie sa zrodlem odzysku
            continue
        for nazwa, wartosc in zip(uzyte, wiersz[2:]):
            s = skroc(wartosc)
            if s:
                mapa.setdefault((nazwa, s), []).append((fid, b, geom))
    con.close()
    return mapa


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    nowa, katalogi = sys.argv[1], sys.argv[2:]

    if not os.path.exists(nowa):
        sys.exit("STOP: brak %s" % nowa)

    # --- uszkodzone platy w nowej bazie
    con = sqlite3.connect("file:%s?mode=ro" % nowa, uri=True)
    kol = [r[1] for r in con.execute('PRAGMA table_info("%s")' % TABELA)]
    uzyte = [k for k in KLUCZE if k in kol]
    zapyt = 'SELECT fid, geom, %s FROM "%s"' % (", ".join('"%s"' % k for k in uzyte), TABELA)
    uszkodzone = []
    for wiersz in con.execute(zapyt):
        fid, geom = wiersz[0], wiersz[1]
        b = bok(geom)
        if pusta(geom) or (b is not None and b < 0.5):
            tresc = {n: skroc(v) for n, v in zip(uzyte, wiersz[2:]) if skroc(v)}
            uszkodzone.append((fid, "pusta" if pusta(geom) else "%.2f m" % b, tresc))
    con.close()

    print("Uszkodzonych platow w %s: %d\n" % (os.path.basename(nowa), len(uszkodzone)))

    # --- starsze bazy
    zrodla = []
    for k in katalogi:
        for korzen, _, pliki in os.walk(os.path.expanduser(k)):
            for p in pliki:
                pelna = os.path.join(korzen, p)
                if p.endswith(".gpkg") and os.path.abspath(pelna) != os.path.abspath(nowa):
                    zrodla.append(pelna)
    print("Przeszukuje %d starszych baz...\n" % len(zrodla))

    indeks = {}
    for z in zrodla:
        m = wczytaj(z)
        for klucz, lista in m.items():
            for fid, b, geom in lista:
                indeks.setdefault(klucz, []).append((z, fid, b))

    # --- dopasowanie
    znalezione, bez = 0, []
    for fid, stan, tresc in uszkodzone:
        if not tresc:
            bez.append((fid, stan, "nic nie niesie — nie ma po czym szukać"))
            continue

        trafienia = {}
        for nazwa, wartosc in tresc.items():
            for z, zfid, b in indeks.get((nazwa, wartosc), []):
                trafienia.setdefault((z, zfid, round(b, 2)), set()).add(nazwa)

        print("=" * 74)
        etykieta = tresc.get("OPIS_PŁATU") or tresc.get("FOTO") or ""
        print("fid %-5s (%s)  %s" % (fid, stan, etykieta[:44]))
        if not trafienia:
            print("   NIE ZNALEZIONO w starszych bazach")
            bez.append((fid, stan, "brak w starszych kopiach"))
            continue

        znalezione += 1
        for (z, zfid, b), po_czym in sorted(trafienia.items(), key=lambda x: -len(x[1])):
            print("   %s" % os.path.relpath(z, os.path.expanduser("~")))
            print("      fid %-5s obwiednia %6.2f m   dopasowane po: %s"
                  % (zfid, b, ", ".join(sorted(po_czym))))
        if len(trafienia) > 1:
            print("   UWAGA: wiecej niz jedno zrodlo — sprawdz, ktore jest wlasciwe")

    print("\n" + "=" * 74)
    print("Geometria do odzyskania: %d z %d" % (znalezione, len(uszkodzone)))
    if bez:
        print("\nBez szans na odzysk:")
        for fid, stan, powod in bez:
            print("   fid %-5s (%s) — %s" % (fid, stan, powod))
    print("\nSkrypt NICZEGO NIE ZAPISAL. Przeniesienie geometrii to osobna,")
    print("swiadoma operacja — przy blednym dopasowaniu przenioslby sie")
    print("obrys innego platu, a tego nie da sie cofnac.")


if __name__ == "__main__":
    main()
