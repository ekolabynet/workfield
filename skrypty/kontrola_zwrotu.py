#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kontrola zwrotu: puste geometrie i dziury w fid.

Punkty 7 i 8 z `claude/OBIEG_zwroty_praktyka.md`.

PUSTA GEOMETRIA to nie NULL. Obiekt istnieje, ma atrybuty, nie ma kształtu.
Znacznik siedzi w bicie 4 flag nagłówka GPKG. Wyzwalacz indeksu przestrzennego
pomija je (WHEN NOT ST_IsEmpty), więc na mapie ich nie widać i nie da się ich
zaznaczyć — wyglądają jak duchy. 21.08 było ich sześć, w tym jedna z pełnym
opisem, gatunkami i zdjęciem: praca do odzyskania, nie śmieć.

DZIURY W fid to zwykle nie strata. fid NIE są przenumerowywane po usunięciu
obiektu, a przy AUTOINCREMENT nowe wiersze liczą się od najwyższego, jaki
kiedykolwiek był. Liczba dziur ma się zgadzać z tym, co pamiętasz z terenu —
skrypt jej nie ocenia, tylko podaje.

NIC NIE KASUJE. Wypisuje gotowe polecenia do wklejenia.

    python3 kontrola_zwrotu.py ZWROT/dane.gpkg
    python3 kontrola_zwrotu.py ZWROT/dane.gpkg --tabela FITO_PLATY
"""

import argparse
import os
import sqlite3
import sys

FLAGA_PUSTA = 0x10  # bit 4 flag nagłówka GPKG


def polacz_tylko_odczyt(sciezka):
    return sqlite3.connect("file:%s?mode=ro" % sciezka, uri=True)


def pusta_geometria(blob):
    """True, gdy nagłówek GPKG mówi 'geometria pusta'."""
    return (blob is not None
            and len(blob) > 3
            and blob[:2] == b"GP"
            and bool(blob[3] & FLAGA_PUSTA))


def kolumna_klucza(con, tabela):
    """Nazwa kolumny klucza głównego (zwykle fid)."""
    for _, nazwa, typ, _, _, pk in con.execute('PRAGMA table_info("%s")' % tabela):
        if pk:
            return nazwa
    return None


def warstwy(con):
    """(tabela, kolumna_geometrii) dla każdej warstwy."""
    return list(con.execute(
        "SELECT table_name, column_name FROM gpkg_geometry_columns"))


def kolumny_tekstowe(con, tabela, pomin):
    return [n for _, n, t, _, _, _ in con.execute('PRAGMA table_info("%s")' % tabela)
            if n not in pomin and (t or "").upper() not in ("BLOB",)]


def opis_wiersza(con, tabela, klucz, fid, geom_kol):
    """Kilka pierwszych niepustych wartości — żeby było widać, czy to śmieć,
    czy praca do odzyskania."""
    kol = kolumny_tekstowe(con, tabela, {klucz, geom_kol})[:12]
    if not kol:
        return ""
    sql = 'SELECT %s FROM "%s" WHERE "%s"=?' % (
        ", ".join('"%s"' % k for k in kol), tabela, klucz)
    wiersz = con.execute(sql, (fid,)).fetchone()
    czesci = []
    for nazwa, wart in zip(kol, wiersz or []):
        if wart is None:
            continue
        s = str(wart).strip()
        if not s or s.lower() in ("null", "none"):
            continue
        czesci.append("%s=%s" % (nazwa, s[:40]))
        if len(czesci) >= 4:
            break
    return "; ".join(czesci)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gpkg")
    ap.add_argument("--tabela", action="append",
                    help="ogranicz do wskazanej warstwy (można podać wiele razy)")
    a = ap.parse_args()

    if not os.path.exists(a.gpkg):
        print("nie ma pliku: %s" % a.gpkg, file=sys.stderr)
        return 2

    for pomocniczy in (a.gpkg + "-wal", a.gpkg + "-shm"):
        if os.path.exists(pomocniczy):
            print("!! obok pliku leży %s — ktoś ma tę bazę OTWARTĄ."
                  % os.path.basename(pomocniczy))
            print("   Zamknij QGIS-a (albo aplikację na telefonie) i skopiuj od nowa.")
            print("   Kontrola na takim pliku czyta stan bez zapisów z WAL-a.")
            print()

    con = polacz_tylko_odczyt(a.gpkg)
    lista = warstwy(con)
    if a.tabela:
        chciane = set(a.tabela)
        lista = [(t, g) for t, g in lista if t in chciane]
    if not lista:
        print("brak warstw z geometrią w %s" % a.gpkg)
        return 0

    problemy = 0
    print("plik: %s" % a.gpkg)
    print()

    for tabela, geom_kol in lista:
        klucz = kolumna_klucza(con, tabela) or "rowid"

        try:
            mn, mx, ile = con.execute(
                'SELECT min("%s"), max("%s"), count(*) FROM "%s"'
                % (klucz, klucz, tabela)).fetchone()
        except sqlite3.Error as e:
            print("%-28s ! %s" % (tabela, e))
            continue

        if ile == 0:
            print("%-28s pusta" % tabela)
            continue

        dziury = (mx - mn + 1) - ile
        nulle = con.execute(
            'SELECT count(*) FROM "%s" WHERE "%s" IS NULL' % (tabela, geom_kol)
        ).fetchone()[0]

        puste = []
        for fid, blob in con.execute(
                'SELECT "%s", "%s" FROM "%s" WHERE "%s" IS NOT NULL'
                % (klucz, geom_kol, tabela, geom_kol)):
            if pusta_geometria(blob):
                puste.append(fid)

        print("%-28s wierszy %-7d %s %d..%d, dziur %d"
              % (tabela, ile, klucz, mn, mx, dziury))
        if nulle:
            print("      geometria NULL: %d" % nulle)

        if puste:
            problemy += len(puste)
            print("      GEOMETRIA PUSTA: %d  -> %s"
                  % (len(puste), ", ".join(str(f) for f in puste[:20])
                     + (" ..." if len(puste) > 20 else "")))
            for fid in puste:
                opis = opis_wiersza(con, tabela, klucz, fid, geom_kol)
                etykieta = "PRACA DO ODZYSKANIA" if opis else "pusty w całości"
                print("        %s=%-6s %-20s %s" % (klucz, fid, etykieta, opis))
            print()
            print("      Do obejrzenia w QGIS (te obiekty NIE dają się kliknąć na mapie):")
            print('        "%s" IN (%s)   <- wyrażenie filtru warstwy %s'
                  % (klucz, ", ".join(str(f) for f in puste), tabela))
            print("      Do skasowania TYCH BEZ TREŚCI — wklej ręcznie, po obejrzeniu:")
            print('        DELETE FROM "%s" WHERE "%s" IN (...);' % (tabela, klucz))
        print()

    con.close()

    if problemy:
        print("=" * 62)
        print("Pustych geometrii razem: %d." % problemy)
        print("NIE SCALAJ tego zwrotu, dopóki ich nie obejrzysz —")
        print("wpuszczone do mastera zostają tam jako duchy na zawsze.")
        return 1

    print("Pustych geometrii nie ma.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
