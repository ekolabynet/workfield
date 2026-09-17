#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sprzatanie uszkodzonych geometrii w FITO_PLATY.

==========================================================================
KARTA FAKTOW — zwrot 10_0 z 25.08.2026, 306 platow
==========================================================================
Czternascie obiektow ma geometrie nie do uzycia:

  PUSTA GEOMETRIA (9)   235, 267, 285, 314, 322, 349, 350, 385, 386
     Nie NULL — bit 4 flag naglowka GPKG. Obiekt istnieje, ma atrybuty,
     ale nie widac go na mapie i NIE DA SIE GO ZAZNACZYC (wyzwalacz RTree
     pomija go przez WHEN NOT ST_IsEmpty).

  ZLEPKI (5)            290 (0.14 m), 345 (0.42 m), 352 (0.11 m),
                        407 (0.00 m), 415 (0.00 m)
     Wierzcholki zlepione w jeden punkt przez EDYCJE TOPOLOGICZNA
     (qffeaturemodel.cpp:1489 — wszystkie wierzcholki w promieniu laduja
     w jednym punkcie). Wlaczona 24.08, wylaczona 25.08 wieczorem.

Przeszukanie 427 starszych baz (`znajdz_geometrie.py`) znalazlo geometrie
dla czterech: 314, 345, 407, 415.

DECYZJA PIOTRA (25.08): **nie przenosimy zadnej.** Dziura w danych, ktora
widac, jest bezpieczniejsza niz obrys, ktorego nie jestesmy pewni —
a przy powrocie w teren dorysowanie kosztuje minute.

==========================================================================
CO ROBI TEN SKRYPT
==========================================================================

1. **Odklada tresc do pliku tekstowego** — zanim cokolwiek usunie.
   Cztery obiekty niosa opis i spis gatunkow z pokryciem (235, 314, 345, 415),
   ktorych nikt nie odtworzy z pamieci za tydzien. Plik lezy obok bazy
   i sluzy do przepisania po ponownym obrysowaniu.

2. **Przepina zalaczniki 407 -> 412.** Oba maja to samo zdjecie
   (`PLAT_20260825_0735.jpg`) i te sama date: 407 to nieudana proba
   (0.00 m, brak ZROBIONE), 412 to wlasciwy plat (77.30 m, KOMPLET).
   Plat narysowany dwa razy. Bez przepiecia dzisiejsze zdjecie zostaloby
   sierota.

3. **Usuwa zalaczniki pozostalych** usuwanych platow. Wiersz wskazujacy
   nieistniejacego rodzica to sierota — dokladnie to, co
   `sprawdz_zalaczniki.py` zglasza jako blad. Pliki w DCIM ZOSTAJA.

4. **Usuwa czternascie platow.**

WYZWALACZE RTREE

GeoPackage ma siedem wyzwalaczy RTree wolajacych `ST_IsEmpty` — funkcje
ze SpatiaLite, ktorej zwykly sqlite3 nie zna. Odpalaja sie przy KAZDYM
zapisie do tabeli. Zdejmujemy je na czas operacji i odtwarzamy z ich
wlasnego SQL-a; indeks przestrzenny czyscimy z usunietych wpisow recznie.
(Trzeci raz ta sama pulapka w tym tygodniu — patrz claude/DANE_obieg.md p. 9.)

Uzycie:
    python3 sprzataj_geometrie.py dane.gpkg            # tylko raport
    python3 sprzataj_geometrie.py dane.gpkg --wykonaj  # z zapisem
"""
import datetime
import os
import shutil
import sqlite3
import struct
import sys

TABELA = "FITO_PLATY"
ZALACZNIKI = "ZAL_PLATY"

# Ustalone przez znajdz_geometrie.py na zwrocie z 25.08.
DO_USUNIECIA = [235, 267, 285, 290, 314, 322, 345, 349, 350, 352, 385, 386, 407, 415]
PRZEPNIJ = {407: 412}          # zalaczniki nieudanej proby -> wlasciwy plat

POLA_TRESCI = ["_KATEGORIA", "NAZWA_PŁATU", "OPIS_PŁATU", "ZAPIS_SUROWY_GATUNKI",
               "ZAPIS_POPRAWIONY", "_ZALECENIA", "FOTO", "ZROBIONE",
               "DATA_WIZJI_LOKALNEJ", "UWAGI"]


def pusta(g):
    return not g or (len(g) > 3 and g[:2] == b"GP" and bool(g[3] & 0x10))


def bok(g):
    if not g or len(g) < 40 or g[:2] != b"GP":
        return None
    f = g[3]
    if (f >> 1) & 7 == 0:
        return None
    e = "<" if f & 1 else ">"
    x0, x1, y0, y1 = struct.unpack_from(e + "4d", g, 8)
    return max(x1 - x0, y1 - y0)


def zdejmij_wyzwalacze(con, tabela):
    """Patrz naglowek: ST_IsEmpty nie istnieje w zwyklym sqlite3."""
    zachowane = [(n, s) for n, s in con.execute(
        "SELECT name, sql FROM sqlite_master WHERE type='trigger' AND tbl_name=? "
        "AND name LIKE 'rtree_%'", (tabela,)) if s]
    for n, _ in zachowane:
        con.execute('DROP TRIGGER IF EXISTS "%s"' % n)
    return zachowane


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    baza = sys.argv[1]
    wykonaj = "--wykonaj" in sys.argv

    if not os.path.exists(baza):
        sys.exit("STOP: brak %s" % baza)

    con = sqlite3.connect(baza)
    kol = [r[1] for r in con.execute('PRAGMA table_info("%s")' % TABELA)]
    pola = [p for p in POLA_TRESCI if p in kol]

    # ---------------------------------------------------------- kontrola
    print("Sprawdzam %d obiektów wskazanych do usunięcia\n" % len(DO_USUNIECIA))
    istnieje, brakuje, niepasuje = [], [], []
    tresc = {}

    for fid in DO_USUNIECIA:
        r = con.execute('SELECT geom, %s FROM "%s" WHERE fid=?'
                        % (", ".join('"%s"' % p for p in pola), TABELA), (fid,)).fetchone()
        if not r:
            brakuje.append(fid)
            continue
        geom = r[0]
        b = bok(geom)
        # Twarda kontrola: usuwamy TYLKO to, co naprawdę jest uszkodzone.
        # Gdyby lista rozjechała się z danymi, lepiej stanąć niż skasować płat.
        if not pusta(geom) and (b is None or b >= 0.5):
            niepasuje.append((fid, "%.2f m" % b if b else "?"))
            continue
        istnieje.append(fid)
        d = {p: v for p, v in zip(pola, r[1:]) if v not in (None, "")}
        if d:
            tresc[fid] = d

    if brakuje:
        print("NIE MA w bazie (już usunięte?): %s" % brakuje)
    if niepasuje:
        print("STOP: te obiekty NIE są uszkodzone — lista rozjechała się z danymi:")
        for fid, b in niepasuje:
            print("   fid %-5s obwiednia %s" % (fid, b))
        sys.exit(1)

    ile_zal = {}
    for fid in istnieje:
        ile_zal[fid] = con.execute('SELECT count(*) FROM "%s" WHERE ID_RODZICA=?'
                                   % ZALACZNIKI, (fid,)).fetchone()[0]

    # Sieroty ISTNIEJACE — zeby nie wygladalo, ze zrobil je ten skrypt.
    # W zwrocie z 25.08 byly dwie: zalaczniki 42 i 45 wskazujace na platy
    # 178 i 181, ktorych nie ma w bazie od dawna.
    sieroty_przed = con.execute(
        'SELECT z.fid, z.ID_RODZICA FROM "%s" z LEFT JOIN "%s" p '
        'ON p.fid=z.ID_RODZICA WHERE p.fid IS NULL' % (ZALACZNIKI, TABELA)).fetchall()
    if sieroty_przed:
        print("UWAGA — sieroty JUŻ BYŁY przed tą operacją: %d" % len(sieroty_przed))
        for zfid, rodzic in sieroty_przed[:6]:
            print("   załącznik %s wskazuje na nieistniejący płat %s" % (zfid, rodzic))
        print("   (ten skrypt ich nie tworzy i nie rusza)\n")

    print("Do usunięcia: %d obiektów" % len(istnieje))
    print("Niosących treść: %d" % len(tresc))
    print("Z załącznikami: %s" % {k: v for k, v in ile_zal.items() if v})
    print("Przepięcie załączników: %s" % PRZEPNIJ)

    if not wykonaj:
        print("\nTo był tylko RAPORT. Nic nie zmieniono.")
        print("Aby wykonać: dodaj --wykonaj")
        con.close()
        return

    # ------------------------------------------------- odłożenie treści
    dzis = datetime.date.today().isoformat()
    plik = os.path.join(os.path.dirname(os.path.abspath(baza)),
                        "usuniete_platy_%s.txt" % dzis)
    with open(plik, "w", encoding="utf-8") as f:
        f.write("Płaty usunięte %s z %s — geometria pusta albo zwinięta do punktu.\n"
                % (dzis, os.path.basename(baza)))
        f.write("Treść odłożona, żeby dało się ją przepisać po ponownym obrysowaniu.\n")
        f.write("=" * 74 + "\n\n")
        for fid in istnieje:
            f.write("fid %s   załączników: %d\n" % (fid, ile_zal.get(fid, 0)))
            for k, v in tresc.get(fid, {}).items():
                f.write("    %-24s %s\n" % (k, v))
            if fid not in tresc:
                f.write("    (nic nie niósł)\n")
            f.write("\n")
    print("\nTreść odłożona: %s" % plik)

    # --------------------------------------------------------- operacja
    kopia = baza + ".przed_sprzataniem"
    if not os.path.exists(kopia):
        shutil.copy2(baza, kopia)
        print("Kopia bazy: %s" % os.path.basename(kopia))

    wyzwalacze = zdejmij_wyzwalacze(con, TABELA)
    print("Zdjęte wyzwalacze RTree: %d" % len(wyzwalacze))

    przepiete = 0
    for stary, nowy in PRZEPNIJ.items():
        if stary in istnieje:
            n = con.execute('UPDATE "%s" SET ID_RODZICA=? WHERE ID_RODZICA=?'
                            % ZALACZNIKI, (nowy, stary)).rowcount
            przepiete += n
            print("Przepięte załączniki %s -> %s: %d" % (stary, nowy, n))

    usuniete_zal = 0
    for fid in istnieje:
        if fid in PRZEPNIJ:
            continue
        usuniete_zal += con.execute('DELETE FROM "%s" WHERE ID_RODZICA=?'
                                    % ZALACZNIKI, (fid,)).rowcount

    znaki = ",".join("?" * len(istnieje))
    usuniete = con.execute('DELETE FROM "%s" WHERE fid IN (%s)' % (TABELA, znaki),
                           istnieje).rowcount

    # indeks przestrzenny: usunięte wpisy zostałyby jako duchy
    try:
        con.execute('DELETE FROM "rtree_%s_geom" WHERE id IN (%s)' % (TABELA, znaki),
                    istnieje)
    except sqlite3.OperationalError:
        pass

    for n, s in wyzwalacze:
        con.execute(s)

    try:
        con.execute("UPDATE gpkg_ogr_contents SET feature_count="
                    '(SELECT count(*) FROM "%s") WHERE table_name=?' % TABELA, (TABELA,))
    except sqlite3.OperationalError:
        pass

    con.commit()

    # --------------------------------- kontrola PO fakcie, nie z rowcount
    zostalo = con.execute('SELECT count(*) FROM "%s"' % TABELA).fetchone()[0]
    sieroty = con.execute(
        'SELECT count(*) FROM "%s" z LEFT JOIN "%s" p ON p.fid=z.ID_RODZICA '
        'WHERE p.fid IS NULL' % (ZALACZNIKI, TABELA)).fetchone()[0]
    nadal = []
    for fid, g in con.execute('SELECT fid, geom FROM "%s" WHERE geom IS NOT NULL' % TABELA):
        b = bok(g)
        if pusta(g) or (b is not None and b < 0.5):
            nadal.append(fid)
    con.close()

    print("\nUsunięte płaty: %d   załączniki: %d   przepięte: %d"
          % (usuniete, usuniete_zal, przepiete))
    print("Zostało płatów: %d" % zostalo)
    print("Sierot w %s: %d  (przed operacją: %d)"
          % (ZALACZNIKI, sieroty, len(sieroty_przed)))
    print("Nadal uszkodzonych: %d %s" % (len(nadal), nadal if nadal else ""))
    print("\nPliki w DCIM NIETKNIĘTE — usunięto tylko wiersze.")


if __name__ == "__main__":
    main()
