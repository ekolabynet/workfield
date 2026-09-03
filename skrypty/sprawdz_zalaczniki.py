#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kontrola załączników po zwrocie — punkt 11 z `claude/OBIEG_zwroty_praktyka.md`.

Zdjęcie może istnieć na trzy sposoby i KAŻDY trzeba sprawdzić osobno:
  1. plik w DCIM,
  2. ścieżka w polu tekstowym (FOTO) — zapas awaryjny,
  3. wiersz w tabeli ZAL_ — właściwy model N:1.

Skrypt sprawdza pięć rzeczy:
  A. sieroty — wiersz ZAL_ wskazuje nieistniejącego rodzica
  B. wiersze bez rodzica — ID_RODZICA jest NULL
  C. ten sam plik u dwóch rodziców
  D. ścieżki bez pliku na dysku          <- ta łapie stratę, ZANIM plik zniknie
  E. pliki bez wiersza (wymaga --dcim)   <- 20.08: z 268 zdjęć tylko 21 miało rekord

NIC NIE KASUJE i nic nie zapisuje. Wypisuje raport, a przy sierotach — gotowe
polecenie do obejrzenia.

    python3 sprawdz_zalaczniki.py ZWROT/dane.gpkg
    python3 sprawdz_zalaczniki.py ZWROT/dane.gpkg --dcim ZWROT/DCIM
    python3 sprawdz_zalaczniki.py dane.gpkg --rodzic ZAL_PLATY=FITO_PLATY

Kod wyjścia: 0 gdy czysto, 1 gdy cokolwiek znaleziono, 2 przy błędzie użycia.

Schemat ZAL_ jest wiążący (claude/WERSJONOWANIE_zasady.md): ID_RODZICA INTEGER,
reszta TEXT, nigdzie NOT NULL; klucz relacji ID_RODZICA -> fid, kompozycja.
Zmiana tego = MAJOR. Kolumnę ze ścieżką skrypt wykrywa sam, bo bywa różnie
nazywana — można ją narzucić przez --kolumna-pliku.
"""

import argparse
import os
import sqlite3
import sys
from collections import defaultdict

KOL_RODZICA = "ID_RODZICA"
ROZSZERZENIA = {".jpg", ".jpeg", ".png", ".heic", ".webp",
                ".mp3", ".m4a", ".ogg", ".wav", ".3gp", ".mp4", ".txt"}


def polacz_tylko_odczyt(sciezka):
    return sqlite3.connect("file:%s?mode=ro" % sciezka, uri=True)


def tabele_zal(con):
    return [t for (t,) in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name LIKE 'ZAL\\_%' ESCAPE '\\' ORDER BY name")]


def kolumny(con, tabela):
    return [(n, (t or "").upper()) for _, n, t, _, _, _
            in con.execute('PRAGMA table_info("%s")' % tabela)]


def kolumna_klucza(con, tabela):
    for _, nazwa, _, _, _, pk in con.execute('PRAGMA table_info("%s")' % tabela):
        if pk:
            return nazwa
    return "rowid"


def wszystkie_tabele(con):
    return [t for (t,) in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'gpkg_%' AND name NOT LIKE 'rtree_%' "
        "AND name NOT LIKE 'sqlite_%'")]


def zgadnij_rodzica(tabela_zal, kandydaci):
    """ZAL_PLATY -> FITO_PLATY. Dopasowanie po sufiksie, nigdy po cichu:
    wynik jest zawsze wypisywany, żeby dało się go zakwestionować."""
    trzon = tabela_zal[4:]
    if not trzon:
        return None
    dokladne = [t for t in kandydaci if t.upper() == trzon.upper()]
    if dokladne:
        return dokladne[0]
    z_kreska = [t for t in kandydaci
                if t.upper().endswith("_" + trzon.upper()) and not t.startswith("ZAL_")]
    if len(z_kreska) == 1:
        return z_kreska[0]
    if len(z_kreska) > 1:
        return sorted(z_kreska, key=len)[0]
    luzne = [t for t in kandydaci
             if t.upper().endswith(trzon.upper()) and not t.startswith("ZAL_")]
    return sorted(luzne, key=len)[0] if luzne else None


def zgadnij_kolumne_pliku(con, tabela):
    """Kolumna tekstowa, której wartości wyglądają jak ścieżki plików."""
    najlepsza, najlepszy_wynik = None, 0
    for nazwa, typ in kolumny(con, tabela):
        if nazwa == KOL_RODZICA or typ in ("BLOB", "INTEGER", "REAL"):
            continue
        try:
            wartosci = [w for (w,) in con.execute(
                'SELECT "%s" FROM "%s" WHERE "%s" IS NOT NULL AND "%s" <> "" LIMIT 200'
                % (nazwa, tabela, nazwa, nazwa))]
        except sqlite3.Error:
            continue
        if not wartosci:
            continue
        trafienia = sum(
            1 for w in wartosci
            if isinstance(w, str)
            and os.path.splitext(w)[1].lower() in ROZSZERZENIA)
        wynik = trafienia / float(len(wartosci))
        if wynik > najlepszy_wynik:
            najlepsza, najlepszy_wynik = nazwa, wynik
    return najlepsza if najlepszy_wynik >= 0.5 else None


def znormalizuj(s):
    return os.path.normpath(str(s).strip().replace("\\", "/")).lower()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gpkg")
    ap.add_argument("--dcim", help="katalog ze zdjęciami (włącza kontrolę E)")
    ap.add_argument("--rodzic", action="append", default=[],
                    metavar="ZAL_X=TABELA", help="narzuć tabelę rodzica")
    ap.add_argument("--kolumna-pliku", dest="kolumna_pliku",
                    help="narzuć nazwę kolumny ze ścieżką")
    ap.add_argument("--limit", type=int, default=20,
                    help="ile pozycji wypisywać na kategorię (domyślnie 20)")
    a = ap.parse_args()

    if not os.path.exists(a.gpkg):
        print("nie ma pliku: %s" % a.gpkg, file=sys.stderr)
        return 2

    narzucone = {}
    for para in a.rodzic:
        if "=" not in para:
            print("--rodzic wymaga postaci ZAL_X=TABELA", file=sys.stderr)
            return 2
        k, v = para.split("=", 1)
        narzucone[k.strip()] = v.strip()

    korzen = os.path.dirname(os.path.abspath(a.gpkg))
    con = polacz_tylko_odczyt(a.gpkg)
    kandydaci = wszystkie_tabele(con)
    zal = tabele_zal(con)

    print("plik:  %s" % a.gpkg)
    print("korzeń ścieżek względnych: %s" % korzen)
    print()

    if not zal:
        print("Nie ma ani jednej tabeli ZAL_*.")
        print("Jeśli w projekcie są zdjęcia, to znaczy, że siedzą wyłącznie")
        print("w polach tekstowych — model N:1 nie działa tą drogą.")
        return 1

    znalezione = 0
    zajete_pliki = set()

    for tabela in zal:
        klucz = kolumna_klucza(con, tabela)
        nazwy_kolumn = [n for n, _ in kolumny(con, tabela)]
        rodzic = narzucone.get(tabela) or zgadnij_rodzica(tabela, kandydaci)
        kol_plik = a.kolumna_pliku or zgadnij_kolumne_pliku(con, tabela)
        ile = con.execute('SELECT count(*) FROM "%s"' % tabela).fetchone()[0]

        print("=" * 62)
        print("%s  (wierszy: %d)" % (tabela, ile))
        print("  rodzic:  %s%s" % (rodzic or "NIE ROZPOZNANY",
                                   "" if narzucone.get(tabela) else "  (zgadnięty)"))
        print("  ścieżka: %s" % (kol_plik or "NIE ROZPOZNANA"))
        if not rodzic:
            print("  ! Podaj rodzica ręcznie: --rodzic %s=NAZWA_TABELI" % tabela)
        if not kol_plik:
            print("  ! Podaj kolumnę ręcznie: --kolumna-pliku NAZWA")
        print()

        if KOL_RODZICA not in nazwy_kolumn:
            print("  ! Brak kolumny %s — to nie jest tabela załączników"
                  " zgodna ze standardem." % KOL_RODZICA)
            znalezione += 1
            print()
            continue

        # B. wiersze bez rodzica
        bez = [r for (r,) in con.execute(
            'SELECT "%s" FROM "%s" WHERE "%s" IS NULL' % (klucz, tabela, KOL_RODZICA))]
        if bez:
            znalezione += len(bez)
            print("  B. WIERSZE BEZ RODZICA: %d  -> %s"
                  % (len(bez), ", ".join(str(x) for x in bez[:a.limit])))
        else:
            print("  B. wierszy bez rodzica: 0")

        # A. sieroty
        if rodzic:
            klucz_rodzica = kolumna_klucza(con, rodzic)
            istniejace = {r for (r,) in con.execute(
                'SELECT "%s" FROM "%s"' % (klucz_rodzica, rodzic))}
            sieroty = [(r, p) for r, p in con.execute(
                'SELECT "%s", "%s" FROM "%s" WHERE "%s" IS NOT NULL'
                % (klucz, KOL_RODZICA, tabela, KOL_RODZICA))
                if p not in istniejace]
            if sieroty:
                znalezione += len(sieroty)
                print("  A. SIEROTY (rodzic nie istnieje): %d" % len(sieroty))
                for r, p in sieroty[:a.limit]:
                    print("       %s=%s  ->  %s=%s (nie ma)"
                          % (klucz, r, KOL_RODZICA, p))
                if len(sieroty) > a.limit:
                    print("       ... (razem %d)" % len(sieroty))
                print("     Do obejrzenia — filtr warstwy %s:" % tabela)
                print('       "%s" IN (%s)'
                      % (klucz, ", ".join(str(r) for r, _ in sieroty[:200])))
            else:
                print("  A. sierot: 0")
        else:
            print("  A. sierot: NIE SPRAWDZONE (nieznany rodzic)")

        if kol_plik:
            wiersze = list(con.execute(
                'SELECT "%s", "%s", "%s" FROM "%s" WHERE "%s" IS NOT NULL AND "%s" <> ""'
                % (klucz, KOL_RODZICA, kol_plik, tabela, kol_plik, kol_plik)))

            # C. ten sam plik u dwóch rodziców
            wg_pliku = defaultdict(set)
            for _, p, sciezka in wiersze:
                wg_pliku[znormalizuj(sciezka)].add(p)
            wspoldzielone = {s: r for s, r in wg_pliku.items() if len(r) > 1}
            if wspoldzielone:
                znalezione += len(wspoldzielone)
                print("  C. TEN SAM PLIK U WIELU RODZICÓW: %d" % len(wspoldzielone))
                for s, r in list(wspoldzielone.items())[:a.limit]:
                    print("       %s  -> rodzice %s"
                          % (s, ", ".join(str(x) for x in sorted(r))))
            else:
                print("  C. plików u wielu rodziców: 0")

            # D. ścieżki bez pliku na dysku
            brakujace = []
            for r, _, sciezka in wiersze:
                s = str(sciezka).strip()
                pelna = s if os.path.isabs(s) else os.path.join(korzen, s)
                if os.path.exists(pelna):
                    zajete_pliki.add(znormalizuj(os.path.abspath(pelna)))
                else:
                    brakujace.append((r, s))
            if brakujace:
                znalezione += len(brakujace)
                print("  D. ŚCIEŻKI BEZ PLIKU NA DYSKU: %d  (z %d)"
                      % (len(brakujace), len(wiersze)))
                for r, s in brakujace[:a.limit]:
                    print("       %s=%s  %s" % (klucz, r, s))
                if len(brakujace) > a.limit:
                    print("       ... (razem %d)" % len(brakujace))
                print("     To jest ta kontrola, której nikt nie robi.")
                print("     Szukaj plików TERAZ — 20.08 po tygodniu 72 z 387 nie")
                print("     znalazły się nigdzie na dysku, mimo 825 tys. przeszukanych.")
            else:
                print("  D. ścieżek bez pliku: 0")
        else:
            print("  C/D: NIE SPRAWDZONE (nieznana kolumna ze ścieżką)")
        print()

    # E. pliki bez wiersza
    if a.dcim:
        print("=" * 62)
        if not os.path.isdir(a.dcim):
            print("E. nie ma katalogu %s" % a.dcim)
        else:
            wszystkie, osierocone = 0, []
            for katalog, _, pliki in os.walk(a.dcim):
                for p in pliki:
                    if os.path.splitext(p)[1].lower() not in ROZSZERZENIA:
                        continue
                    wszystkie += 1
                    pelna = znormalizuj(os.path.abspath(os.path.join(katalog, p)))
                    if pelna not in zajete_pliki:
                        osierocone.append(os.path.join(katalog, p))
            print("E. pliki w DCIM: %d, bez wiersza w ZAL_: %d"
                  % (wszystkie, len(osierocone)))
            if osierocone:
                znalezione += len(osierocone)
                for s in osierocone[:a.limit]:
                    print("     %s" % os.path.relpath(s, a.dcim))
                if len(osierocone) > a.limit:
                    print("     ... (razem %d)" % len(osierocone))
                udzial = 100.0 * len(osierocone) / max(wszystkie, 1)
                print("   %.0f %% zdjęć istnieje WYŁĄCZNIE jako pliki." % udzial)
                print("   Mogą siedzieć w polu tekstowym FOTO (zapas awaryjny)")
                print("   albo nigdzie. Sprawdź, zanim projekt pojedzie dalej.")
        print()

    con.close()

    print("=" * 62)
    if znalezione:
        print("Znalezionych nieprawidłowości: %d." % znalezione)
        print("Skrypt niczego nie zmienił. NIE SCALAJ tego zwrotu przed obejrzeniem.")
        return 1
    print("Czysto: sierot nie ma, wszystkie ścieżki mają pliki.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
