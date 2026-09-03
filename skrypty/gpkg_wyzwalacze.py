#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Zdejmowanie i odtwarzanie wyzwalaczy RTree w GeoPackage.

Powód istnienia — punkt 9 z `claude/OBIEG_zwroty_praktyka.md`:

    GeoPackage ma dziewięć wyzwalaczy na warstwę, z czego siedem RTree woła
    ST_IsEmpty — funkcję ze SpatiaLite, której zwykły sqlite3 nie zna.
    Odpalają się przy KAŻDYM zapisie do tabeli, także gdy zmieniamy kolumnę
    tekstową i geometrii nie dotykamy:

        sqlite3.OperationalError: no such function: ST_IsEmpty

Użycie:

    import sqlite3
    from gpkg_wyzwalacze import bez_wyzwalaczy

    con = sqlite3.connect("dane.gpkg")
    with bez_wyzwalaczy(con, "FITO_PLATY"):
        con.execute("UPDATE FITO_PLATY SET UWAGI=? WHERE fid=?", ("x", 12))
    con.commit()

UWAGA: to wystarcza, gdy zmieniamy WYŁĄCZNIE atrybuty. Gdy zmieniamy
geometrię, po odtworzeniu wyzwalaczy trzeba jeszcze odbudować indeks
przestrzenny z obwiedni — tego ten moduł świadomie NIE robi, żeby nie udawać,
że zrobił.
"""

import sqlite3
from contextlib import contextmanager


def zdejmij_wyzwalacze(con, tabela):
    """Zdejmuje wyzwalacze RTree tabeli. Zwraca listę (nazwa, sql) do odtworzenia."""
    zachowane = [
        (n, s)
        for n, s in con.execute(
            "SELECT name, sql FROM sqlite_master WHERE type='trigger' "
            "AND tbl_name=? AND name LIKE 'rtree_%'",
            (tabela,),
        )
        if s
    ]
    for n, _ in zachowane:
        con.execute('DROP TRIGGER IF EXISTS "%s"' % n)
    return zachowane


def odtworz_wyzwalacze(con, zachowane):
    """Odtwarza wyzwalacze z ich własnego SQL-a."""
    for n, s in zachowane:
        con.execute('DROP TRIGGER IF EXISTS "%s"' % n)
        con.execute(s)


@contextmanager
def bez_wyzwalaczy(con, tabela):
    """Blok, w którym wyzwalacze RTree tabeli są zdjęte.

    Odtwarza je także wtedy, gdy w środku poleci wyjątek — inaczej pierwszy
    nieudany zapis zostawiłby bazę bez indeksu przestrzennego, po cichu.
    """
    zachowane = zdejmij_wyzwalacze(con, tabela)
    try:
        yield zachowane
    finally:
        odtworz_wyzwalacze(con, zachowane)


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        print("użycie: gpkg_wyzwalacze.py PLIK.gpkg   (tylko wypisuje, nic nie zmienia)")
        raise SystemExit(2)
    con = sqlite3.connect(sys.argv[1])
    for (t,) in con.execute("SELECT table_name FROM gpkg_geometry_columns"):
        n = con.execute(
            "SELECT count(*) FROM sqlite_master WHERE type='trigger' "
            "AND tbl_name=? AND name LIKE 'rtree_%'",
            (t,),
        ).fetchone()[0]
        print("%-30s wyzwalaczy RTree: %d" % (t, n))
    con.close()
