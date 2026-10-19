#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Domknij bazy — scal osierocone dzienniki WAL z plikami GeoPackage.

WERSJA = "2026-10-03a"

==========================================================================
PO CO TO JEST
==========================================================================

Baza, obok której leży niepusty `-wal`, jest przez panel „Kopia na nośnik"
uznawana za OTWARTĄ i **pomijana w migawce** — po cichu, za każdym razem.
24.08.2026 pominiętych było 2. 03.10.2026 jest ich 22, w tym `master`.

Każda ubita sesja dokłada jedną bazę, której już nigdy nie będzie w kopii.

Ten skrypt znajduje takie bazy, scala ich dzienniki
(`PRAGMA wal_checkpoint(TRUNCATE)`) i sprawdza wynik. Po nim migawka
widzi je jako zamknięte i kopiuje.

==========================================================================
CZEGO PILNUJE
==========================================================================

* **TRYB PRÓBNY JEST DOMYŚLNY.** Bez `--wykonaj` nic nie jest zapisywane.
* **Sprawdza, czy ktoś trzyma plik**, zanim go tknie (`lsof`). Deklaracja
  człowieka, że „nic nie jest otwarte", nie wystarcza — proces mógł zostać.
* **Oryginał zostaje.** Przed scaleniem kopiuje bazę RAZEM z `-wal` i `-shm`
  (cała trójka, bo bez dziennika kopia byłaby niepełna) i sprawdza md5.
  Domyślnie na INNY dysk, jeśli nośnik 4_DATA jest podpięty.
* **Nie rusza bazy, której kopia się nie udała.**
* Po scaleniu sprawdza: dziennik zniknął, `quick_check` przechodzi,
  liczby wierszy są takie same jak przed.

Liczby wierszy NIE POWINNY się zmienić: SQLite czytając bazę z dziennikiem
obok i tak widzi jego zawartość. Checkpoint tylko ją utrwala. Gdyby się
zmieniły — coś jest nie tak i skrypt to wypisze.

==========================================================================
UŻYCIE
==========================================================================

    python3 domknij_bazy.py                      # tryb próbny, sam raport
    python3 domknij_bazy.py --wykonaj            # kopia + scalenie
    python3 domknij_bazy.py --korzen=/inny/kat
    python3 domknij_bazy.py --kopie=/gdzie/kopie --wykonaj

Kod wyjścia: 0 czysto, 1 zostały bazy do ręki, 2 błąd użycia.

Miejsce w repozytorium: skrypty/domknij_bazy.py
"""
import datetime as dt
import hashlib
import os
import shutil
import sqlite3
import subprocess
import sys

WERSJA = "2026-10-03a"
KORZEN_DOMYSLNY = "/DATA/WorkField"


def md5(sciezka):
    h = hashlib.md5()
    with open(sciezka, "rb") as f:
        for blok in iter(lambda: f.read(1 << 20), b""):
            h.update(blok)
    return h.hexdigest()


def ludzko(bajty):
    for jednostka in ("B", "kB", "MB", "GB"):
        if bajty < 1024 or jednostka == "GB":
            return "%.1f %s" % (bajty, jednostka)
        bajty /= 1024.0


def kto_trzyma(sciezki):
    """Zwraca tekst z procesami trzymającymi którykolwiek plik, albo ''.

    Gdy nie ma `lsof`, zwraca None — czyli 'nie wiem', co jest czymś innym
    niż 'nikt'. Narzędzie, które nie umie sprawdzić, ma to powiedzieć."""
    if shutil.which("lsof") is None:
        return None
    istniejace = [s for s in sciezki if os.path.exists(s)]
    if not istniejace:
        return ""
    try:
        w = subprocess.run(["lsof", "--"] + istniejace,
                           capture_output=True, text=True, timeout=30)
    except Exception:
        return None
    linie = [l for l in w.stdout.splitlines()[1:] if l.strip()]
    return "\n".join(linie)


def tabele_i_liczby(sciezka):
    """Liczby wierszy w tabelach użytkownika — do porównania przed i po."""
    con = sqlite3.connect("file:%s?mode=ro" % sciezka, uri=True)
    try:
        out = {}
        for (t,) in con.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'rtree_%' "
                "ORDER BY 1"):
            try:
                out[t] = con.execute('SELECT count(*) FROM "%s"' % t).fetchone()[0]
            except sqlite3.Error:
                out[t] = None
        return out
    finally:
        con.close()


def znajdz(korzen):
    """Bazy z NIEPUSTYM dziennikiem WAL."""
    znalezione = []
    for katalog, _, pliki in os.walk(korzen):
        for p in pliki:
            if not p.endswith("-wal"):
                continue
            wal = os.path.join(katalog, p)
            baza = wal[:-4]
            if not os.path.exists(baza):
                continue
            try:
                if os.path.getsize(wal) == 0:
                    continue
            except OSError:
                continue
            znalezione.append(baza)
    return sorted(znalezione)


def domknij_jedna(baza, katalog_kopii, korzen):
    """Zwraca (stan, komunikat). Stan: 'ok' / 'pominieta' / 'blad'."""
    wal, shm = baza + "-wal", baza + "-shm"
    trojka = [baza, wal, shm]

    trzyma = kto_trzyma(trojka)
    if trzyma is None:
        return "pominieta", "nie ma `lsof` — nie umiem sprawdzic, czy ktos trzyma plik"
    if trzyma:
        return "pominieta", "plik trzyma proces:\n      " + trzyma.replace("\n", "\n      ")

    # --- 1. stan przed
    try:
        przed = tabele_i_liczby(baza)
    except sqlite3.Error as e:
        return "blad", "nie moge otworzyc do odczytu: %s" % e

    # --- 2. kopia calej trojki, na bok
    wzgledna = os.path.relpath(baza, korzen)
    cel_kat = os.path.join(katalog_kopii, os.path.dirname(wzgledna))
    os.makedirs(cel_kat, exist_ok=True)
    skopiowane = []
    for s in trojka:
        if not os.path.exists(s):
            continue
        cel = os.path.join(cel_kat, os.path.basename(s))
        shutil.copy2(s, cel)
        if md5(s) != md5(cel):
            return "blad", "kopia %s nie zgadza sie suma — NIE ruszam oryginalu" % os.path.basename(s)
        skopiowane.append(os.path.basename(s))

    # --- 3. scalenie dziennika
    try:
        con = sqlite3.connect(baza)
        wynik = con.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        con.commit()
        con.close()
    except sqlite3.Error as e:
        return "blad", "checkpoint sie nie udal: %s (kopia lezy w %s)" % (e, cel_kat)

    if wynik and wynik[0] != 0:
        return "blad", "checkpoint zajety (wynik %s) — ktos jednak trzyma baze" % (wynik,)

    # --- 4. sprawdzenie
    uwagi = []
    zostal = os.path.exists(wal) and os.path.getsize(wal) > 0
    if zostal:
        uwagi.append("dziennik NADAL niepusty")
    try:
        con = sqlite3.connect("file:%s?mode=ro" % baza, uri=True)
        qc = con.execute("PRAGMA quick_check").fetchone()[0]
        con.close()
        if qc != "ok":
            uwagi.append("quick_check: %s" % qc)
    except sqlite3.Error as e:
        uwagi.append("quick_check sie nie udal: %s" % e)

    try:
        po = tabele_i_liczby(baza)
        roznice = [t for t in set(przed) | set(po) if przed.get(t) != po.get(t)]
        if roznice:
            uwagi.append("ZMIENILY SIE LICZBY: " + ", ".join(
                "%s %s->%s" % (t, przed.get(t), po.get(t)) for t in sorted(roznice)))
    except sqlite3.Error as e:
        uwagi.append("nie moge policzyc po scaleniu: %s" % e)

    if uwagi:
        return "blad", "; ".join(uwagi) + "  (kopia: %s)" % cel_kat

    # --- 5. usuniecie pustego dziennika
    #
    # Bez tego kroku CALA ROBOTA JEST BEZUZYTECZNA: panel „Kopia na nosnik"
    # rozpoznaje otwarta baze po OBECNOSCI pliku `-wal`, nie po jego
    # rozmiarze. Zerowy dziennik nadal wykluczalby baze z kazdej migawki.
    #
    # Usuwamy dopiero TU, po sprawdzeniu, ze dane sa w glownym pliku.
    # Zerowy `-wal` z definicji nic nie niesie, a `-shm` to sam indeks
    # pamieci wspolnej, odtwarzany przy otwarciu. Dokladnie to robi SQLite
    # przy czystym zamknieciu ostatniego polaczenia; tutaj trzeba recznie,
    # bo GeoPackage bywa otwierany w trybie trwalego WAL.
    #
    # Kopia calej trojki lezy juz na boku, wiec cofniecie jest mozliwe.
    for s in (wal, shm):
        try:
            if os.path.exists(s) and os.path.getsize(s) == 0:
                os.remove(s)
            elif os.path.exists(s) and s == shm:
                os.remove(s)
        except OSError as e:
            return "blad", "nie moge usunac %s: %s  (dane scalone, kopia: %s)" % (
                os.path.basename(s), e, cel_kat)

    # --- 6. odczyt po usunieciu dziennika — W TRYBIE `immutable`
    #
    # UWAGA, pulapka, w ktora sam wpadlem przy pierwszej probie:
    # zwykle otwarcie bazy ODTWARZA `-wal` i `-shm`, bo GeoPackage bywa
    # w trybie trwalego WAL. Sprawdzenie niszczylo wtedy dokladnie to,
    # co mialo potwierdzic — dzienniki wracaly i baza nadal wypadalaby
    # z migawki.
    #
    # `immutable=1` czyta SAM GLOWNY PLIK, bez dziennika i bez blokad.
    # Dlatego jest to zarazem jedyny uczciwy dowod, ze dane naprawde
    # sa w glownym pliku, a nie tylko widoczne przez dziennik obok.
    try:
        con = sqlite3.connect("file:%s?mode=ro&immutable=1" % baza, uri=True)
        po2 = {}
        for (t,) in con.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'rtree_%' ORDER BY 1"):
            try:
                po2[t] = con.execute('SELECT count(*) FROM "%s"' % t).fetchone()[0]
            except sqlite3.Error:
                po2[t] = None
        con.close()
    except sqlite3.Error as e:
        return "blad", "sam glowny plik sie nie otwiera: %s  (kopia: %s)" % (e, cel_kat)

    roznice2 = [t for t in set(przed) | set(po2) if przed.get(t) != po2.get(t)]
    if roznice2:
        return "blad", "w samym glownym pliku inne liczby: " + ", ".join(
            "%s %s->%s" % (t, przed.get(t), po2.get(t)) for t in sorted(roznice2)
        ) + "  (kopia: %s)" % cel_kat

    # --- 7. czy dzienniki naprawde zostaly usuniete
    wrocily = [os.path.basename(s) for s in (wal, shm) if os.path.exists(s)]
    if wrocily:
        return "blad", "dzienniki wrocily po sprawdzeniu: %s  (kopia: %s)" % (
            ", ".join(wrocily), cel_kat)

    return "ok", "scalone i dziennik usuniety, kopia trojki w %s" % cel_kat


def main():
    korzen = KORZEN_DOMYSLNY
    katalog_kopii = ""
    wykonaj = False

    for a in sys.argv[1:]:
        if a == "--wykonaj":
            wykonaj = True
        elif a.startswith("--korzen="):
            korzen = a.split("=", 1)[1]
        elif a.startswith("--kopie="):
            katalog_kopii = a.split("=", 1)[1]
        else:
            print(__doc__)
            return 2

    print("domknij_bazy, wersja skryptu: %s" % WERSJA)
    print("korzen: %s" % korzen)
    if not os.path.isdir(korzen):
        print("STOP: nie ma katalogu %s" % korzen, file=sys.stderr)
        return 2

    if not katalog_kopii:
        stempel = dt.datetime.now().strftime("%Y-%m-%d_%H%M")
        nosnik = "/run/media/%s/4_DATA" % os.environ.get("USER", "piotr")
        if os.path.isdir(nosnik):
            katalog_kopii = os.path.join(nosnik, "WorkField_przed_domknieciem", stempel)
        else:
            katalog_kopii = os.path.join(korzen, "_przed_domknieciem", stempel)

    print("szukam baz z niepustym dziennikiem…")
    bazy = znajdz(korzen)
    if not bazy:
        print("\nNie ma zadnej bazy z niepustym dziennikiem. Nic do zrobienia.")
        return 0

    print("\nznalezione: %d\n" % len(bazy))
    print("  %-10s %-10s  %s" % ("baza", "dziennik", "sciezka"))
    razem = 0
    for b in bazy:
        w = b + "-wal"
        razem += os.path.getsize(w)
        print("  %-10s %-10s  %s" % (ludzko(os.path.getsize(b)),
                                     ludzko(os.path.getsize(w)),
                                     os.path.relpath(b, korzen)))
    print("\n  dzienniki razem: %s" % ludzko(razem))

    if not wykonaj:
        print("\nTRYB PROBNY — nic nie zapisano.")
        print("Kopie trojek trafilyby do: %s" % katalog_kopii)
        print("Wykonanie:  python3 %s --wykonaj" % os.path.basename(sys.argv[0]))
        return 0

    print("\nkopie trojek (baza + -wal + -shm) ida do:\n  %s\n" % katalog_kopii)
    os.makedirs(katalog_kopii, exist_ok=True)

    liczniki = {"ok": 0, "pominieta": 0, "blad": 0}
    for b in bazy:
        stan, komunikat = domknij_jedna(b, katalog_kopii, korzen)
        liczniki[stan] += 1
        znacznik = {"ok": "  domkniete ", "pominieta": "  POMINIETA ",
                    "blad": "  BLAD      "}[stan]
        print("%s %s" % (znacznik, os.path.relpath(b, korzen)))
        if stan != "ok":
            print("      %s" % komunikat)

    print("\n%s" % ("=" * 66))
    print("domknietych: %d   pominietych: %d   bledow: %d"
          % (liczniki["ok"], liczniki["pominieta"], liczniki["blad"]))
    print("kopie sprzed scalenia: %s" % katalog_kopii)
    if liczniki["ok"]:
        print("\nTeraz zrob DRUGA migawke — dowiaze wszystko niezmienione")
        print("i skopiuje wylacznie te bazy. To minuty, nie godziny.")
    return 1 if (liczniki["pominieta"] or liczniki["blad"]) else 0


if __name__ == "__main__":
    sys.exit(main())
