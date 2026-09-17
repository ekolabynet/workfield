#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PZE v4_0 — zdjecia z korzenia do DCIM, razem ze sciezkami w bazie.

==========================================================================
CO ZASTALISMY
==========================================================================
W jednej bazie **dwie konwencje sciezek**:

    FITO_PLATY          JPEG_20260803123811849.JPG        ← bez katalogu
    FITO_ZDJECIA        DCIM/zdjecia_fito_20260805_...    ← z katalogiem
    FITO_SPIS_GATUNKOWY DCIM/PLAT_gat_20260804_1049.jpg   ← z katalogiem

Dlatego zdjecia platow leza luzem w korzeniu projektu — tam ich szuka
aplikacja. 43 pliki wsrod plikow projektu, bazy i skryptow.

==========================================================================
DLACZEGO NIE SAMO `mv`
==========================================================================
Przeniesienie plikow bez poprawy sciezek zrobi z 32 zdjec **sieroty**:
wpis w bazie zostanie, plik bedzie gdzie indziej, a w formularzu pojawi sie
puste miejsce zamiast fotografii. **Pliki i sciezki musza isc RAZEM** —
stad jeden skrypt, a nie `mv` plus poprawka potem.

Sprawdzone przed napisaniem (28.08.2026):
  * 32 wpisy bez katalogu, wszystkie wskazuja na istniejace pliki,
  * **zero kolizji** — zaden plik z korzenia nie ma odpowiednika w DCIM
    o tej samej nazwie, wiec nic sie nie nadpisze,
  * 11 plikow w korzeniu, o ktorych baza nie wie — zrobione i nigdzie
    niepodpiete.

Te 11 tez przenosimy: w DCIM sa **do odzyskania** (widac je w galerii,
mozna podpiac recznie), w korzeniu gina wsrod plikow projektu.

==========================================================================
CO ROBI
==========================================================================
  1. kopia bazy (`dane.gpkg.przed_dcim`),
  2. przenosi WSZYSTKIE zdjecia z korzenia do `DCIM/`,
  3. dopisuje `DCIM/` do wpisow `FOTO` w `FITO_PLATY`,
  4. **sprawdza po fakcie**, czy kazdy wpis wskazuje na istniejacy plik.

Punkt 4 jest istota: `rowcount` mowi tylko, ile wierszy dotknieto, a nie
czy wynik jest poprawny. Kontrola idzie po plikach na dysku.

Uruchom:  python3 przenies_zdjecia_do_dcim.py
Idempotentny — po przeniesieniu nie ma czego przenosic.
"""
import os
import shutil
import sqlite3
import sys

D = os.path.expanduser("~/WorkField/wydania/zzw_2026/zzw_pze_2605_inw_v4_0")
BAZA = os.path.join(D, "dane.gpkg")
DCIM = os.path.join(D, "DCIM")
ROZSZERZENIA = (".jpg", ".jpeg", ".png")

# Tabele z polem FOTO — sprawdzamy wszystkie, choc dzis tylko FITO_PLATY
# ma sciezki bez katalogu.
TABELE = ("FITO_PLATY", "FITO_ZDJECIA", "FITO_SPIS_GATUNKOWY", "FITO_ZALAZKI")


def main():
    if not os.path.isdir(D):
        sys.exit("STOP: brak %s" % D)
    if not os.path.isdir(DCIM):
        sys.exit("STOP: brak katalogu DCIM")

    w_korzeniu = sorted(f for f in os.listdir(D)
                        if f.lower().endswith(ROZSZERZENIA)
                        and os.path.isfile(os.path.join(D, f)))

    if not w_korzeniu:
        print("W korzeniu nie ma zdjęć — nic do zrobienia.")
        return

    print("Zdjęć w korzeniu: %d" % len(w_korzeniu))

    # --- twarda kontrola kolizji PRZED czymkolwiek
    w_dcim = set(os.listdir(DCIM))
    kolizje = [f for f in w_korzeniu if f in w_dcim]
    if kolizje:
        print("STOP: %d plików ma odpowiednik w DCIM o tej samej nazwie." % len(kolizje))
        for f in kolizje[:10]:
            print("   %s" % f)
        sys.exit("Przenoszenie nadpisałoby je — rozstrzygnij ręcznie.")
    print("Kolizji nazw: 0")

    # --- kopia bazy
    kopia = BAZA + ".przed_dcim"
    if not os.path.exists(kopia):
        shutil.copy2(BAZA, kopia)
        print("Kopia bazy: %s" % os.path.basename(kopia))

    # --- poprawa ścieżek NAJPIERW, pliki potem
    #
    # Kolejność ma znaczenie: gdyby skrypt padł między przeniesieniem
    # a poprawą, zostałyby sieroty. Odwrotnie — wpisy wskazują na DCIM,
    # pliki jeszcze w korzeniu, i wystarczy uruchomić ponownie.
    con = sqlite3.connect(BAZA)

    # Wyzwalacze RTree wolaja ST_IsEmpty — funkcje ze SpatiaLite, ktorej
    # zwykly sqlite3 nie zna. Odpalaja sie przy KAZDYM zapisie do warstwy,
    # takze przy zmianie samej kolumny tekstowej. Czwarty raz ta sama
    # pulapka w tym projekcie.
    wyzw = [(n, s) for n, s in con.execute(
        "SELECT name, sql FROM sqlite_master WHERE type='trigger' AND name LIKE 'rtree_%'") if s]
    for n, _ in wyzw:
        con.execute('DROP TRIGGER IF EXISTS "%s"' % n)
    print("Zdjete wyzwalacze RTree: %d" % len(wyzw))

    zmienione = 0
    for tab in TABELE:
        try:
            kol = [r[1] for r in con.execute('PRAGMA table_info("%s")' % tab)]
        except sqlite3.OperationalError:
            continue
        if "FOTO" not in kol:
            continue
        n = con.execute(
            'UPDATE "%s" SET FOTO = \'DCIM/\' || FOTO '
            'WHERE FOTO IS NOT NULL AND FOTO <> \'\' AND FOTO NOT LIKE \'%%/%%\'' % tab
        ).rowcount
        if n:
            print("   %-22s poprawionych ścieżek: %d" % (tab, n))
            zmienione += n
    for n, s in wyzw:
        con.execute(s)
    con.commit()

    # --- przeniesienie plików
    przeniesione = 0
    for f in w_korzeniu:
        shutil.move(os.path.join(D, f), os.path.join(DCIM, f))
        przeniesione += 1
    print("Przeniesionych plików: %d" % przeniesione)

    # --- kontrola PO FAKCIE, po plikach na dysku
    #
    # rowcount mówi, ile wierszy dotknięto — nie czy wynik jest poprawny.
    print("\nKontrola:")
    braki = []
    for tab in TABELE:
        try:
            kol = [r[1] for r in con.execute('PRAGMA table_info("%s")' % tab)]
        except sqlite3.OperationalError:
            continue
        if "FOTO" not in kol:
            continue
        for fid, sc in con.execute(
                'SELECT fid, FOTO FROM "%s" WHERE FOTO IS NOT NULL AND FOTO <> \'\'' % tab):
            if not os.path.exists(os.path.join(D, sc)):
                braki.append((tab, fid, sc))
    con.close()

    if braki:
        print("   WPISY BEZ PLIKU: %d" % len(braki))
        for tab, fid, sc in braki[:10]:
            print("      %-22s fid %-6s %s" % (tab, fid, sc))
    else:
        print("   każdy wpis FOTO wskazuje na istniejący plik")

    zostalo = [f for f in os.listdir(D)
               if f.lower().endswith(ROZSZERZENIA) and os.path.isfile(os.path.join(D, f))]
    print("   zdjęć w korzeniu po operacji: %d" % len(zostalo))
    print("   plików w DCIM: %d" % len(os.listdir(DCIM)))

    print("""
Poprawionych ścieżek: %d
Przeniesionych plików: %d

Baza sprzed operacji: %s

UWAGA: zmieniła się TYLKO kopia w wydaniu. Na telefonie stare v3 ma nadal
zdjęcia w korzeniu — v4_0 wyślij dopiero po tej poprawce, żeby pojechał
z jedną konwencją.
""" % (zmienione, przeniesione, os.path.basename(kopia)))


if __name__ == "__main__":
    main()
