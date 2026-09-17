#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Odbudowa indeksow przestrzennych w GeoPackage.

==========================================================================
PO CO
==========================================================================
**Zdjecie wyzwalaczy RTree uniewaznia indeks, a przywrocenie ich go NIE
odbudowuje.** Wiersze wstawione przy zdjetych wyzwalaczach nigdy do niego
nie trafiaja.

Skutek jest mylacy: dane sa, warstwa sie wczytuje, „Przybliz do warstwy"
dziala (bo bierze zasieg z `gpkg_contents`), ale **na mapie nic nie widac**
— QGIS i QField pytaja indeks i dostaja zero.

07.09 kosztowalo to godzine szukania w PTR: sprawdzalem kolejno drzewo
warstw, skale, typ geometrii i przezroczystosc, zanim doszedlem do indeksu.
Potem to samo wrocilo przy punktach: `FITO_ZDJECIA` miala 2 obiekty
i 0 w indeksie.

Kazdy skrypt, ktory zdejmuje wyzwalacze przed wstawianiem, musi konczyc
sie odbudowa indeksu. Ten skrypt to robi.

==========================================================================
DLACZEGO PRZEZ ogrinfo, A NIE SQL-em
==========================================================================
Wyzwalacze RTree wolaja `ST_MinX`, `ST_IsEmpty` i podobne — funkcje
SpatiaLite, ktorych zwykly `sqlite3` nie zna. Odbudowa recznym INSERT-em
sie nie uda.

`CreateSpatialIndex` z GDAL robi to poprawnie. Wymaga jednak, zeby
wczesniej **usunac wpis z `gpkg_extensions`** — zostaje po starym indeksie
i blokuje zalozenie nowego kluczem unikalnym.

Uruchom:
    python3 napraw_indeksy.py <katalog_lub_gpkg>
    python3 napraw_indeksy.py <...> --wykonaj
"""
import os
import subprocess
import sqlite3
import sys


def stan(p):
    c = sqlite3.connect("file:%s?mode=ro" % p, uri=True)
    w = []
    for t, kol in c.execute("SELECT table_name, column_name FROM gpkg_geometry_columns"):
        n = c.execute('SELECT count("%s") FROM "%s"' % (kol, t)).fetchone()[0]
        idx = "rtree_%s_%s" % (t, kol)
        jest = c.execute("SELECT count(*) FROM sqlite_master WHERE name=?",
                         (idx,)).fetchone()[0]
        i = c.execute('SELECT count(*) FROM "%s"' % idx).fetchone()[0] if jest else -1
        w.append((t, kol, n, i))
    c.close()
    return w


def main():
    arg = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not arg:
        sys.exit("Uzycie: napraw_indeksy.py <katalog_lub_plik.gpkg> [--wykonaj]")
    p = os.path.expanduser(arg[0])
    if os.path.isdir(p):
        p = os.path.join(p, "dane.gpkg")
    if not os.path.exists(p):
        sys.exit("STOP: brak %s" % p)
    wykonaj = "--wykonaj" in sys.argv

    print("Baza: %s\n" % p)
    print("%-24s %8s %8s" % ("TABELA", "obiekty", "indeks"))
    print("-" * 46)
    doNaprawy = []
    for t, kol, n, i in stan(p):
        if i < 0:
            s = "BRAK INDEKSU"
            if n > 0 or True:
                doNaprawy.append((t, kol))
        elif i != n:
            s = "<<< ROZJAZD"
            doNaprawy.append((t, kol))
        else:
            s = "ok"
        print("%-24s %8d %8s  %s" % (t, n, i if i >= 0 else "-", s))

    print("\ndo naprawy: %d" % len(doNaprawy))
    if not wykonaj:
        print("\nTo byl RAPORT. Aby wykonac: --wykonaj")
        return

    import shutil
    kopia = p + ".przed_indeksami"
    if not os.path.exists(kopia):
        shutil.copy2(p, kopia)
        print("Kopia: %s" % os.path.basename(kopia))

    for t, kol in doNaprawy:
        c = sqlite3.connect(p)
        # Wpis zostaje po starym indeksie i blokuje zalozenie nowego —
        # ogr2ogr trafia na klucz unikalny i przerywa CALE tworzenie
        # wyzwalaczy, zostawiajac tabele bez indeksu.
        c.execute("DELETE FROM gpkg_extensions WHERE table_name=? AND column_name=? "
                  "AND extension_name='gpkg_rtree_index'", (t, kol))
        c.execute('DROP TABLE IF EXISTS "rtree_%s_%s"' % (t, kol))
        for suf in ("insert", "delete", "update1", "update2", "update3",
                    "update4", "update5", "update6", "update7"):
            c.execute('DROP TRIGGER IF EXISTS "rtree_%s_%s_%s"' % (t, kol, suf))
        c.commit()
        c.close()

        w = subprocess.run(["ogrinfo", p, "-sql",
                            "SELECT CreateSpatialIndex('%s','%s')" % (t, kol)],
                           capture_output=True, text=True)
        ok = "= 1" in w.stdout
        print("   %-24s %s" % (t, "odbudowany" if ok else
                               "NIE UDALO SIE: " + (w.stderr or w.stdout).strip()[:80]))

    print("\nPo naprawie:")
    print("%-24s %8s %8s" % ("TABELA", "obiekty", "indeks"))
    print("-" * 46)
    for t, kol, n, i in stan(p):
        print("%-24s %8d %8s  %s" % (t, n, i if i >= 0 else "-",
                                     "ok" if i == n else "<<< NADAL ROZJAZD"))
    print("""
Uwaga: rozjazd o kilka obiektow bywa NORMALNY — indeks pomija geometrie
puste i zdegenerowane. Wazne, zeby nie bylo zera przy niezerowej liczbie
obiektow.
""")


if __name__ == "__main__":
    main()
