#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Kontrola spojnosci tabel zalacznikow w GeoPackage.

Do puszczenia PO PRZYJECIU ZWROTU, zanim dane pojada dalej. Zwykly
python3, bez QGIS-a — dziala wszedzie, takze na maszynie bez GIS-a.
Niczego nie zmienia: sam czyta.

Sprawdza cztery rzeczy, kazda z innego powodu:

1. SIEROTY — wiersz ZAL_ wskazuje rodzica, ktorego nie ma. Przy relacji
   o sile KOMPOZYCJA kasowanie rodzica ma kasowac dzieci; sierota znaczy,
   ze gdzies tego nie zrobiono i w bazie zostaja wiersze nie do znalezienia.

2. BEZ RODZICA — ID_RODZICA jest NULL. Tak wyglada zalacznik, ktoremu nie
   dopieto klucza po zatwierdzeniu rodzica (schemat celowo nie ma NOT NULL,
   wiec baza tego nie zlapie za nas).

3. TEN SAM PLIK U DWOCH RODZICOW — objaw duplikowania obiektu albo podzialu,
   ktory pociagnal dzieci. Grozne przy kompozycji: skasowanie jednego
   rodzica zabiera plik, na ktory patrzy drugi.

4. BRAKUJACE PLIKI — sciezka w bazie, ktorej nie ma na dysku. Sprawdzane
   wzgledem katalogu GPKG (tak jak liczy je aplikacja).

Uzycie:
    python3 sprawdz_zalaczniki.py <plik.gpkg> [<plik.gpkg> ...]
    python3 sprawdz_zalaczniki.py --bez-plikow dane.gpkg   # pomija punkt 4

Kod wyjscia: 0 gdy czysto, 1 gdy cokolwiek znaleziono.
"""
import os
import sqlite3
import sys

SPRAWDZAJ_PLIKI = True


def tabele_zalacznikow(con):
    kur = con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'ZAL\\_%' ESCAPE '\\'"
    )
    return sorted(w[0] for w in kur.fetchall())


def kolumny(con, tabela):
    return [w[1] for w in con.execute('PRAGMA table_info("%s")' % tabela)]


def zgadnij_rodzica(con, tabela):
    """ZAL_PLATY -> platy. Dopasowanie bez wzgledu na wielkosc liter."""
    trzon = tabela[4:]
    kandydaci = [w[0] for w in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")]
    for k in kandydaci:
        if k.lower() == trzon.lower():
            return k
    return None


def sprawdz(sciezka):
    if not os.path.exists(sciezka):
        print("BRAK PLIKU: %s" % sciezka)
        return 1

    katalog = os.path.dirname(os.path.abspath(sciezka))
    con = sqlite3.connect("file:%s?mode=ro" % sciezka, uri=True)
    znalezione = 0

    print("=" * 70)
    print(sciezka)

    tabele = tabele_zalacznikow(con)
    if not tabele:
        print("  brak tabel ZAL_ — nic do sprawdzenia")
        con.close()
        return 0

    for tabela in tabele:
        kol = kolumny(con, tabela)
        rodzic = zgadnij_rodzica(con, tabela)
        ile = con.execute('SELECT count(*) FROM "%s"' % tabela).fetchone()[0]

        print("\n  %s — %d wierszy, rodzic: %s"
              % (tabela, ile, rodzic if rodzic else "NIE ZNALEZIONO"))

        if "ID_RODZICA" not in kol:
            print("    ! brak kolumny ID_RODZICA — tabela nie pasuje do modelu")
            znalezione += 1
            continue

        # 2. bez rodzica
        n = con.execute(
            'SELECT count(*) FROM "%s" WHERE ID_RODZICA IS NULL' % tabela
        ).fetchone()[0]
        if n:
            print("    ! %d bez rodzica (ID_RODZICA NULL)" % n)
            znalezione += n

        # 1. sieroty
        if rodzic:
            wiersze = con.execute(
                'SELECT z.fid, z.ID_RODZICA FROM "%s" z LEFT JOIN "%s" p '
                'ON p.fid = z.ID_RODZICA '
                'WHERE z.ID_RODZICA IS NOT NULL AND p.fid IS NULL' % (tabela, rodzic)
            ).fetchall()
            if wiersze:
                print("    ! %d sierot (rodzic nie istnieje): fid %s"
                      % (len(wiersze), ", ".join(str(w[0]) for w in wiersze[:10])))
                znalezione += len(wiersze)

        if "SCIEZKA" not in kol:
            continue

        # 3. ten sam plik u dwoch rodzicow
        wiersze = con.execute(
            'SELECT SCIEZKA, count(DISTINCT ID_RODZICA) d, group_concat(DISTINCT ID_RODZICA) '
            'FROM "%s" WHERE SCIEZKA IS NOT NULL AND SCIEZKA <> "" '
            'GROUP BY SCIEZKA HAVING d > 1' % tabela
        ).fetchall()
        for sciezka_pliku, ile_rodzicow, lista in wiersze:
            print("    ! ten sam plik u %d rodzicow (%s): %s"
                  % (ile_rodzicow, lista, sciezka_pliku))
            znalezione += 1

        # 4. brakujace pliki
        if SPRAWDZAJ_PLIKI:
            brak = []
            for (s,) in con.execute(
                'SELECT SCIEZKA FROM "%s" WHERE SCIEZKA IS NOT NULL AND SCIEZKA <> ""' % tabela
            ):
                pelna = s if os.path.isabs(s) else os.path.join(katalog, s)
                if not os.path.exists(pelna):
                    brak.append(s)
            if brak:
                print("    ! %d plikow nie ma na dysku:" % len(brak))
                for s in brak[:5]:
                    print("        %s" % s)
                if len(brak) > 5:
                    print("        ... i %d wiecej" % (len(brak) - 5))
                znalezione += len(brak)

    con.close()

    if znalezione == 0:
        print("\n  CZYSTO — relacje zalacznikow spojne")
    else:
        print("\n  ZNALEZIONO %d rzeczy do obejrzenia" % znalezione)
    return 1 if znalezione else 0


def main():
    global SPRAWDZAJ_PLIKI
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--bez-plikow" in sys.argv:
        SPRAWDZAJ_PLIKI = False

    if not args:
        sys.exit(__doc__)

    wynik = 0
    for sciezka in args:
        wynik |= sprawdz(sciezka)
    sys.exit(wynik)


if __name__ == "__main__":
    main()
