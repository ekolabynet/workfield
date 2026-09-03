#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Przyrost dnia terenowego — punkt 6 z `claude/OBIEG_zwroty_praktyka.md`.

Zestawia liczniki wierszy dwóch GeoPackage (rano / wieczór) i wypisuje
różnicę. To jedyny sposób, żeby wiedzieć, czy zwrot cokolwiek wnosi, ZANIM
zacznie się scalanie — i jedyna liczba, którą można potem sprawdzić po
scaleniu ("zwrot niósł +3 płaty, master ma urosnąć o +3").

Nic nie zapisuje. Czyta obie bazy tylko do odczytu.

    python3 przyrost.py RANO.gpkg WIECZOR.gpkg
    python3 przyrost.py RANO.gpkg WIECZOR.gpkg --dcim A/DCIM B/DCIM
    python3 przyrost.py RANO.gpkg WIECZOR.gpkg --json > przyrost.json

Najważniejszy wiersz wyniku to ZAL_* — rośnie tylko wtedy, gdy zdjęcia
trafiają do tabeli załączników, a nie do pola tekstowego. Brak wzrostu ZAL_
przy rosnącym DCIM znaczy, że coś się rozjechało.
"""

import argparse
import json
import os
import sqlite3
import sys

ROZSZERZENIA_ZDJEC = {".jpg", ".jpeg", ".png", ".heic", ".webp",
                      ".mp3", ".m4a", ".ogg", ".wav", ".3gp"}


def polacz_tylko_odczyt(sciezka):
    """Otwiera bazę w trybie read-only — żeby narzędzie diagnostyczne nigdy
    nie stworzyło -wal obok pliku, który właśnie badamy."""
    return sqlite3.connect("file:%s?mode=ro" % sciezka, uri=True)


def tabele(con):
    """Warstwy i tabele atrybutowe z gpkg_contents + wszystkie ZAL_*.

    Kafle (data_type='tiles') pomijamy — liczba kafelków rastra nic nie mówi
    o pracy terenowej, a potrafi być ogromna.
    """
    nazwy = []
    try:
        nazwy += [
            t for (t,) in con.execute(
                "SELECT table_name FROM gpkg_contents "
                "WHERE data_type IN ('features','attributes')")
        ]
    except sqlite3.Error:
        pass  # plik bez gpkg_contents — poradzimy sobie samym sqlite_master
    nazwy += [
        t for (t,) in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name LIKE 'ZAL\\_%' ESCAPE '\\'")
    ]
    if not nazwy:
        nazwy = [
            t for (t,) in con.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'gpkg_%' AND name NOT LIKE 'rtree_%' "
                "AND name NOT LIKE 'sqlite_%'")
        ]
    return sorted(set(nazwy))


def stan(sciezka):
    con = polacz_tylko_odczyt(sciezka)
    wynik = {}
    for t in tabele(con):
        try:
            wynik[t] = con.execute('SELECT count(*) FROM "%s"' % t).fetchone()[0]
        except sqlite3.Error as e:
            wynik[t] = None
            print("  ! nie policzyłem %s: %s" % (t, e), file=sys.stderr)
    con.close()
    return wynik


def policz_pliki(katalog):
    if not katalog or not os.path.isdir(katalog):
        return None
    n = 0
    for _, _, pliki in os.walk(katalog):
        for p in pliki:
            if os.path.splitext(p)[1].lower() in ROZSZERZENIA_ZDJEC:
                n += 1
    return n


def niebo_raport(sciezka):
    """Rozbicie NIEBO_EPOKA po POWOD — sprawdzian z handoffu 24.08.

    Po dniu z RTK odpowiada na pytanie, czy łatka „brak GSV nie blokuje
    zapisu" zadziałała:
      wiersze `/bez_gsv`   -> GSV faktycznie znika, diagnoza potwierdzona
      wiersze normalne     -> GSV działa, milczenie miało inną przyczynę
      nic po starcie       -> bramka 1 albo 2; `adb logcat | grep NIEBO:`
    """
    con = polacz_tylko_odczyt(sciezka)
    try:
        istnieje = con.execute(
            "SELECT count(*) FROM sqlite_master WHERE type='table' "
            "AND name='NIEBO_EPOKA'").fetchone()[0]
        if not istnieje:
            return
        wiersze = list(con.execute(
            "SELECT POWOD, COUNT(DISTINCT ID_POMIARU), COUNT(*) "
            "FROM NIEBO_EPOKA GROUP BY POWOD ORDER BY POWOD"))
    except sqlite3.Error:
        return
    finally:
        con.close()

    print()
    print("Dziennik Nieba — NIEBO_EPOKA wg POWOD:")
    if not wiersze:
        print("   PUSTO. Zapis nie ruszył po starcie — bramka 1 albo 2.")
        print("   Sprawdź:  adb logcat | grep NIEBO:")
        return
    for powod, pomiarow, epok in wiersze:
        print("   %-22s pomiarów %-5d epok %d" % (powod or "(null)", pomiarow, epok))
    bez_gsv = [w for w in wiersze if "bez_gsv" in (w[0] or "")]
    obiekt = [w for w in wiersze if (w[0] or "").startswith("obiekt")]
    if bez_gsv:
        print("   -> wiersze /bez_gsv SĄ: odbiornik nie podaje GSV,")
        print("      diagnoza z 24.08 potwierdzona, a zapis mimo to leci.")
    if not obiekt:
        print("   -> ani jednego wpisu przy OBIEKCIE mimo epok rytmu —")
        print("      to był objaw z 24.08; jeśli wróci, coś nadal blokuje zapis.")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rano", help="GeoPackage stanu wcześniejszego")
    ap.add_argument("wieczor", help="GeoPackage stanu późniejszego (zwrot)")
    ap.add_argument("--dcim", nargs=2, metavar=("RANO", "WIECZOR"),
                    help="katalogi DCIM do policzenia plików")
    ap.add_argument("--json", action="store_true", help="wynik jako JSON")
    a = ap.parse_args()

    for p in (a.rano, a.wieczor):
        if not os.path.exists(p):
            print("nie ma pliku: %s" % p, file=sys.stderr)
            return 2

    r, w = stan(a.rano), stan(a.wieczor)

    if a.dcim:
        nr, nw = policz_pliki(a.dcim[0]), policz_pliki(a.dcim[1])
        if nr is not None or nw is not None:
            r["DCIM"], w["DCIM"] = nr or 0, nw or 0

    wiersze = []
    for t in sorted(set(r) | set(w)):
        x, y = r.get(t, 0), w.get(t, 0)
        if x is None or y is None:
            continue
        if x or y:
            wiersze.append((t, x, y, y - x))

    if a.json:
        print(json.dumps(
            {"rano": a.rano, "wieczor": a.wieczor,
             "tabele": [{"tabela": t, "rano": x, "wieczor": y, "przyrost": d}
                        for t, x, y, d in wiersze]},
            ensure_ascii=False, indent=2))
        return 0

    print("rano:    %s" % a.rano)
    print("wieczór: %s" % a.wieczor)
    print()
    print("%-30s %8s %9s %9s" % ("tabela", "rano", "wieczór", "przyrost"))
    print("-" * 60)
    for t, x, y, d in wiersze:
        gwiazdka = " *" if t.startswith("ZAL_") else ""
        print("%-30s %8d %9d %+9d%s" % (t, x, y, d, gwiazdka))
    print("-" * 60)

    niebo_raport(a.wieczor)

    zal = [(t, d) for t, x, y, d in wiersze if t.startswith("ZAL_")]
    dcim = [d for t, x, y, d in wiersze if t == "DCIM"]
    if dcim and dcim[0] > 0 and zal and all(d == 0 for _, d in zal):
        print()
        print("!! DCIM urosło o %+d, a żadna tabela ZAL_ nie urosła." % dcim[0])
        print("   Zdjęcia idą do pola tekstowego zamiast do tabeli załączników.")
        print("   Patrz punkt 11 notatki: 20.08 z 268 zdjęć tylko 21 miało rekord.")
    if not wiersze:
        print("(nic do porównania)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
