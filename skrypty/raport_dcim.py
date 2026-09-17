#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Raport DCIM — kto jest czyj. Czyta bazę, patrzy na dysk, nic nie zmienia.

==========================================================================
PO CO
==========================================================================
Nazwa pliku niesie WARSTWĘ i CZAS, ale nie niesie PŁATU:

    platy_20260825_074408_403.jpg

Wiedza „do czego to należy" siedzi wyłącznie w tabelach `ZAL_*`. Kiedy
wiersz zniknie — a znika, bo **usunięcie płatu nie usuwa jego załączników**
(25.08: siedem sierot, cztery świeże) — plik zostaje niemy. Patrząc na DCIM
nie da się powiedzieć, co jest podpięte, co osierocone, a co nigdy nie
trafiło do bazy.

Ten raport odpowiada na cztery pytania naraz:

  1. **PODPIĘTE**    — plik ma wiersz w ZAL_, a rodzic istnieje
  2. **SIEROTY**     — wiersz wskazuje na płat, którego już nie ma
  3. **LUZEM**       — plik na dysku, o którym baza nic nie wie
  4. **BRAKUJĄCE**   — baza wskazuje na plik, którego nie ma na dysku

Czwarta grupa jest najgroźniejsza i najtrudniejsza do zauważenia gołym
okiem: 20.08 zabrakło 72 z 387 potrzebnych zdjęć i nie znalazły się nigdzie
po przeszukaniu 825 tysięcy plików na dysku.

==========================================================================
CZEGO NIE ROBI
==========================================================================
Niczego nie przemianowuje, nie kasuje i nie przepina. To jest OKNO, nie
narzędzie naprawcze — bo naprawa powiązań wymaga wiedzy, której skrypt nie
ma (do którego płatu należy zdjęcie sprzed tygodnia?).

Rozważane alternatywy i dlaczego nie teraz:

  - **fid w nazwie pliku** — DCIM byłby samoopisujący, ale w chwili robienia
    zdjęcia płat CZĘSTO NIE MA JESZCZE fid (numer powstaje przy zapisie,
    a aparat uruchamia się wcześniej). Przemianowanie po zapisie musiałoby
    iść RAZEM z aktualizacją ścieżki w bazie — rozjazd byłby gorszy niż
    obecny stan.
  - **fid w EXIF** — plik zostaje pod swoją nazwą, a niesie odpowiedź
    w sobie; odporne na przemianowania. Tańsze i bezpieczniejsze, ale
    wymaga zmiany w aplikacji, w momencie zapisu.

Użycie:
    python3 raport_dcim.py KATALOG_PROJEKTU
    python3 raport_dcim.py KATALOG_PROJEKTU --pelny    # wypisuje wszystkie
"""
import os
import sqlite3
import sys
from collections import defaultdict


def znajdz_baze(katalog):
    """data.gpkg/dane.gpkg mają pierwszeństwo — reguła z NarzedziaProjektu."""
    for nazwa in ("data.gpkg", "dane.gpkg"):
        p = os.path.join(katalog, nazwa)
        if os.path.exists(p):
            return p
    kandydaci = [f for f in os.listdir(katalog) if f.endswith(".gpkg")
                 and not f.startswith(("wf_wskazniki", "support", "tool_"))]
    if len(kandydaci) == 1:
        return os.path.join(katalog, kandydaci[0])
    sys.exit("STOP: nie wiem, która baza jest danymi. Kandydaci: %s" % kandydaci)


def tabele_zal(con):
    return [t for (t,) in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND (name LIKE 'ZAL\\_%' ESCAPE '\\' OR name LIKE 'ATT\\_%' ESCAPE '\\')")]


def znajdz_rodzica(con, nazwa_zal):
    """Która tabela jest rodzicem — NAZWA plus POTWIERDZENIE W DANYCH.

    Żaden z tych sygnałów osobno nie wystarcza, co pokazały dwa testy:

    * **sama nazwa zawodzi** — `ZAL_GATUNKI` ma rodzica `FITO_SPIS_GATUNKOWY`,
      a `ZAL_ZDJECIA_FITO` → `FITO_ZDJECIA`. Żadnej z tych par nie da się
      wyprowadzić przez doklejenie przedrostka;
    * **same dane zawodzą** — zakresy `fid` różnych tabel się pokrywają,
      więc `ZAL_PLATY` trafiało w `FITO_SPIS_GATUNKOWY` ze stuprocentowym
      „pokryciem".

    Więc: nazwa proponuje, dane potwierdzają. Gdy nic nie przejdzie obu
    prób, mówimy „nie rozpoznano" — zamiast zgłaszać wszystko jako sieroty.
    """
    idr = [r[0] for r in con.execute(
        'SELECT DISTINCT ID_RODZICA FROM "%s" WHERE ID_RODZICA IS NOT NULL LIMIT 50'
        % nazwa_zal)]
    if not idr:
        return None, 0.0

    kandydaci = [t for (t,) in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'gpkg_%' AND name NOT LIKE 'rtree_%' "
        "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'ZAL\\_%' ESCAPE '\\'")]

    # Rdzeń nazwy rozbity na człony; sześć znaków wystarcza, bo końcówki
    # fleksyjne się różnią (GATUNKI / GATUNKOWY).
    czlony = [c[:6] for c in nazwa_zal.split("_", 1)[1].split("_") if len(c) > 2]

    znaki = ",".join("?" * len(idr))
    oceny = []
    for tab in kandydaci:
        kol = [r[1] for r in con.execute('PRAGMA table_info("%s")' % tab)]
        if "fid" not in kol:
            continue
        n = con.execute('SELECT count(*) FROM "%s" WHERE fid IN (%s)' % (tab, znaki),
                        idr).fetchone()[0]
        pokrycie = n / len(idr)
        gora = tab.upper()
        z_nazwy = sum(1 for c in czlony if c in gora)
        oceny.append((z_nazwy, pokrycie, tab))

    if not oceny:
        return None, 0.0

    # Najpierw zgodność nazwy, przy remisie pokrycie w danych.
    oceny.sort(reverse=True)
    z_nazwy, pokrycie, tab = oceny[0]
    if z_nazwy == 0 or pokrycie <= 0.5:
        return None, pokrycie
    return tab, pokrycie


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    katalog = os.path.expanduser(sys.argv[1])
    pelny = "--pelny" in sys.argv

    if not os.path.isdir(katalog):
        sys.exit("STOP: brak katalogu %s" % katalog)

    baza = znajdz_baze(katalog)
    dcim = os.path.join(katalog, "DCIM")
    if not os.path.isdir(dcim):
        sys.exit("STOP: brak %s" % dcim)

    # --- pliki na dysku, także w podkatalogach (platy_168 itp.)
    na_dysku = {}
    for korzen, _, pliki in os.walk(dcim):
        for f in pliki:
            if f.lower().endswith((".jpg", ".jpeg", ".png")):
                pelna = os.path.join(korzen, f)
                wzgl = os.path.relpath(pelna, katalog)
                na_dysku[f] = wzgl

    con = sqlite3.connect("file:%s?mode=ro" % baza, uri=True)
    zal = tabele_zal(con)

    podpiete, sieroty, brakujace = [], [], []
    nierozpoznane, rodzice = [], {}
    uzyte_pliki = set()

    for t in zal:
        kol = [r[1] for r in con.execute('PRAGMA table_info("%s")' % t)]
        if "SCIEZKA" not in kol or "ID_RODZICA" not in kol:
            continue
        rodzic, pokrycie = znajdz_rodzica(con, t)
        if rodzic is None:
            nierozpoznane.append((t, pokrycie))
            continue
        rodzice[t] = rodzic

        for zfid, idr, sc in con.execute(
                'SELECT fid, ID_RODZICA, SCIEZKA FROM "%s"' % t):
            nazwa = os.path.basename(sc or "")
            uzyte_pliki.add(nazwa)
            jest_plik = nazwa in na_dysku
            jest_rodzic = False
            if rodzic and idr is not None:
                jest_rodzic = bool(con.execute(
                    'SELECT count(*) FROM "%s" WHERE fid=?' % rodzic, (idr,)).fetchone()[0])

            if not jest_rodzic:
                sieroty.append((t, zfid, idr, nazwa, jest_plik))
            elif not jest_plik:
                brakujace.append((t, zfid, idr, sc))
            else:
                podpiete.append((t, idr, nazwa))
    con.close()

    luzem = sorted(set(na_dysku) - uzyte_pliki)

    # ------------------------------------------------------------- wydruk
    print("Projekt: %s" % katalog)
    print("Baza:    %s" % os.path.basename(baza))
    print("Plików w DCIM: %d   tabel załączników: %d\n" % (len(na_dysku), len(zal)))

    print("%-14s %6s" % ("STAN", "ile"))
    print("-" * 30)
    print("%-14s %6d" % ("podpięte", len(podpiete)))
    print("%-14s %6d" % ("sieroty", len(sieroty)))
    print("%-14s %6d" % ("luzem", len(luzem)))
    print("%-14s %6d" % ("brakujące", len(brakujace)))

    if podpiete:
        wg = defaultdict(int)
        for t, _, _ in podpiete:
            wg[t] += 1
        print("\nPodpięte wg tabel: %s" % dict(wg))

    if rodzice:
        print("\nRodzice rozpoznani po danych: %s"
              % ", ".join("%s->%s" % (k, v) for k, v in rodzice.items()))
    if nierozpoznane:
        print("\nNIE ROZPOZNANO tabeli rodzica (pominięte, NIE liczone jako sieroty):")
        for t_, p in nierozpoznane:
            print("   %-20s najlepsze pokrycie %.0f%%" % (t_, p * 100))

    if sieroty:
        print("\n" + "=" * 74)
        print("SIEROTY — wiersz wskazuje na nieistniejący obiekt (%d)" % len(sieroty))
        print("Powstają, bo USUNIĘCIE PŁATU NIE USUWA JEGO ZAŁĄCZNIKÓW.")
        print("%-18s %-6s %-8s %-40s %s" % ("tabela", "zal", "rodzic", "plik", "na dysku"))
        for t, zfid, idr, nazwa, jest in sieroty:
            print("%-18s %-6s %-8s %-40s %s"
                  % (t, zfid, idr, nazwa[:40], "TAK" if jest else "nie"))

    if brakujace:
        print("\n" + "=" * 74)
        print("BRAKUJĄCE PLIKI — baza wskazuje, dysku nie ma (%d)" % len(brakujace))
        print("To jest ta grupa, której nie widać gołym okiem.")
        for t, zfid, idr, sc in brakujace[:20 if not pelny else len(brakujace)]:
            print("   %-18s zal %-6s rodzic %-6s %s" % (t, zfid, idr, sc))
        if not pelny and len(brakujace) > 20:
            print("   ... i %d więcej (--pelny)" % (len(brakujace) - 20))

    if luzem:
        print("\n" + "=" * 74)
        print("LUZEM — plik jest, baza o nim nie wie (%d)" % len(luzem))
        wg = defaultdict(list)
        for f in luzem:
            wg[f.split("_")[0]].append(f)
        for przedrostek, lista in sorted(wg.items(), key=lambda x: -len(x[1])):
            print("   %-24s %d" % (przedrostek, len(lista)))
            if pelny:
                for f in lista:
                    print("        %s" % f)
        if not pelny:
            print("   (--pelny wypisuje nazwy)")

    print("\n" + "=" * 74)
    print("Nic nie zmieniono. To okno, nie naprawa — przypisanie zdjęcia")
    print("sprzed tygodnia do płatu wymaga wiedzy, której skrypt nie ma.")


if __name__ == "__main__":
    main()
