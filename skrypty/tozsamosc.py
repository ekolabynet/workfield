#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tożsamość obiektów w GeoPackage: porównania po `uuid`, nie po `fid`.

WorkFieldGIS 24.10.2026 [WF-IDENTITY-SCRIPTS] — punkt 10 z
`claude/ZALEGLE_2026-10-24.md`. Decyzje: `claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md`.

`fid` to numer wiersza w JEDNYM pliku: zmienia się przy scalaniu zwrotów do
mastera. Ten sam `fid` w dwóch plikach nie musi znaczyć tego samego obiektu,
a ten sam obiekt może mieć w nich różne `fid`. `uuid` (od 24.10 w każdej
warstwie roboczej i w `ZAL_*`) jest tożsamością, która jedzie z obiektem.

Moduł do użytku z innych skryptów (`przyrost.py`, `sprawdz_zalaczniki.py`)
i samodzielnie:

    python3 tozsamosc.py porownaj RANO.gpkg WIECZOR.gpkg
    python3 tozsamosc.py sprawdz dane.gpkg

`porownaj` — dla każdej warstwy z `uuid` w obu plikach: nowe, usunięte,
zmienione (atrybuty albo geometria), przenumerowane (ten sam `uuid`, inny
`fid`). `sprawdz` — puste i powtórzone `uuid` oraz zgodność dwóch kluczy
w tabelach zdjęć: `ID_RODZICA` (fid) i `PARENT_UUID` muszą wskazywać ten sam
obiekt.

Tylko odczyt (`mode=ro`). Nic nie zapisuje.
"""

import hashlib
import sqlite3
import sys

POMIJANE = ("gpkg_", "rtree_", "sqlite_", "wf_", "niebo_")
KOL_UUID = "uuid"
KOL_PARENT_UUID = "PARENT_UUID"
KOL_RODZICA = "ID_RODZICA"


def polacz(sciezka):
    import urllib.parse
    import os
    return sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(sciezka)), uri=True)


def kolumny(con, tabela):
    return [r[1] for r in con.execute('PRAGMA table_info("%s")' % tabela.replace('"', '""'))]


def klucz(con, tabela):
    for r in con.execute('PRAGMA table_info("%s")' % tabela.replace('"', '""')):
        if r[5]:
            return r[1]
    return "rowid"


def kolumna(con, tabela, nazwa):
    """Nazwa kolumny bez względu na wielkość liter albo None."""
    for k in kolumny(con, tabela):
        if k.lower() == nazwa.lower():
            return k
    return None


def tabele_robocze(con):
    """Warstwy i tabele atrybutowe z gpkg_contents + wszystkie ZAL_*,
    bez technicznych (WF_*, NIEBO_*) i systemowych."""
    nazwy = []
    try:
        nazwy += [t for (t,) in con.execute(
            "SELECT table_name FROM gpkg_contents WHERE data_type IN ('features','attributes')")]
    except sqlite3.Error:
        pass
    nazwy += [t for (t,) in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'ZAL\\_%' ESCAPE '\\'")]
    wynik = []
    for t in nazwy:
        if t.lower().startswith(POMIJANE) or t in wynik:
            continue
        wynik.append(t)
    return sorted(wynik)


def q(nazwa):
    return '"%s"' % nazwa.replace('"', '""')


def odcisk(wartosci):
    """Skrót zawartości wiersza (bez klucza) — zmiana atrybutu albo geometrii zmienia skrót."""
    h = hashlib.md5()
    for v in wartosci:
        if isinstance(v, bytes):
            h.update(b"B" + v)
        else:
            h.update(("%s:%r" % (type(v).__name__, v)).encode("utf-8"))
        h.update(b"\x1f")
    return h.hexdigest()


def mapa_uuid(con, tabela):
    """uuid -> (fid, odcisk); oraz liczba wierszy bez uuid. None, gdy brak kolumny uuid."""
    ku = kolumna(con, tabela, KOL_UUID)
    if not ku:
        return None, 0
    pk = klucz(con, tabela)
    reszta = [k for k in kolumny(con, tabela) if k != pk]
    sql = "SELECT %s, %s, %s FROM %s" % (q(pk), q(ku), ", ".join(q(k) for k in reszta), q(tabela))
    mapa, bez = {}, 0
    for r in con.execute(sql):
        fid, u, wartosci = r[0], r[1], r[2:]
        if u is None or str(u).strip() == "":
            bez += 1
            continue
        mapa[str(u)] = (fid, odcisk(wartosci))
    return mapa, bez


def porownaj(sciezka_a, sciezka_b):
    """Lista słowników — po jednym na tabelę obecną w którymkolwiek pliku."""
    ca, cb = polacz(sciezka_a), polacz(sciezka_b)
    try:
        ta, tb = set(tabele_robocze(ca)), set(tabele_robocze(cb))
        wynik = []
        for t in sorted(ta | tb):
            w = {"tabela": t, "uuid": False}
            ma = mb = None
            bez_a = bez_b = 0
            if t in ta:
                ma, bez_a = mapa_uuid(ca, t)
            if t in tb:
                mb, bez_b = mapa_uuid(cb, t)
            if ma is None or mb is None:
                if t not in ta or t not in tb:
                    w["powod"] = "tabela tylko w jednym pliku"
                elif ma is None and mb is None:
                    w["powod"] = "brak kolumny uuid"
                else:
                    w["powod"] = "brak kolumny uuid w %s pliku" % ("pierwszym" if ma is None else "drugim")
                wynik.append(w)
                continue
            wspolne = set(ma) & set(mb)
            w.update({
                "uuid": True,
                "nowe": sorted(set(mb) - set(ma)),
                "usuniete": sorted(set(ma) - set(mb)),
                "zmienione": sorted(u for u in wspolne if ma[u][1] != mb[u][1]),
                "przenumerowane": sorted(u for u in wspolne if ma[u][0] != mb[u][0]),
                "bez_uuid": (bez_a, bez_b),
                "fid_a": {u: ma[u][0] for u in ma},
                "fid_b": {u: mb[u][0] for u in mb},
            })
            wynik.append(w)
        return wynik
    finally:
        ca.close()
        cb.close()


def wszystkie_uuid(con):
    """uuid -> lista (tabela, fid) we wszystkich tabelach roboczych."""
    gdzie = {}
    for t in tabele_robocze(con):
        ku = kolumna(con, t, KOL_UUID)
        if not ku:
            continue
        pk = klucz(con, t)
        for fid, u in con.execute("SELECT %s, %s FROM %s" % (q(pk), q(ku), q(t))):
            if u is not None and str(u).strip():
                gdzie.setdefault(str(u), []).append((t, fid))
    return gdzie


def sprawdz(sciezka, limit=10):
    """Kontrola tożsamości jednego pliku. Zwraca (wiersze_raportu, liczba_problemow)."""
    con = polacz(sciezka)
    out, problemy = [], 0
    try:
        gdzie = wszystkie_uuid(con)
        for t in tabele_robocze(con):
            ku = kolumna(con, t, KOL_UUID)
            n = con.execute("SELECT count(*) FROM %s" % q(t)).fetchone()[0]
            if not ku:
                out.append("%-32s %6d  brak kolumny uuid (porównania tylko po fid)" % (t, n))
                continue
            puste = con.execute("SELECT count(*) FROM %s WHERE %s IS NULL OR trim(%s) = ''"
                                % (q(t), q(ku), q(ku))).fetchone()[0]
            powt = con.execute("SELECT count(*) FROM (SELECT %s FROM %s WHERE %s IS NOT NULL AND trim(%s) <> ''"
                               " GROUP BY %s HAVING count(*) > 1)" % (q(ku), q(t), q(ku), q(ku), q(ku))).fetchone()[0]
            linia = "%-32s %6d  uuid puste %d, powtórzone %d" % (t, n, puste, powt)
            if powt:
                problemy += powt
                linia += "   <- POWTÓRZONE: duplikat albo kopia bez nowego uuid"
            out.append(linia)
            # dwa klucze w tabeli zdjęć
            kp = kolumna(con, t, KOL_PARENT_UUID)
            kr = kolumna(con, t, KOL_RODZICA)
            if not (kp and kr):
                continue
            pk = klucz(con, t)
            niezgodne, nieznane, bez = [], [], 0
            for fid, rodzic, puuid in con.execute("SELECT %s, %s, %s FROM %s" % (q(pk), q(kr), q(kp), q(t))):
                if puuid is None or str(puuid).strip() == "":
                    bez += 1
                    continue
                miejsca = [m for m in gdzie.get(str(puuid), []) if not m[0].upper().startswith("ZAL_")]
                if not miejsca:
                    nieznane.append((fid, puuid))
                elif all(m[1] != rodzic for m in miejsca):
                    niezgodne.append((fid, rodzic, miejsca[0]))
            out.append("%-32s         dwa klucze: PARENT_UUID puste %d, nieznane %d, NIEZGODNE z ID_RODZICA %d"
                       % ("", bez, len(nieznane), len(niezgodne)))
            for fid, rodzic, (tab, f) in niezgodne[:limit]:
                out.append("%-32s           %s=%s: ID_RODZICA=%s, a PARENT_UUID wskazuje %s fid %s"
                           % ("", pk, fid, rodzic, tab, f))
            # 24.10.2026: nieznane — wypisane, żeby dało się je obejrzeć
            for fid, puuid in nieznane[:limit]:
                out.append("%-32s           %s=%s: PARENT_UUID %s nie wskazuje żadnego obiektu (rodzic usunięty?)"
                           % ("", pk, fid, puuid))
            problemy += len(niezgodne)
        return out, problemy
    finally:
        con.close()


def drukuj_porownanie(wynik, limit=10):
    print("%-32s %7s %7s %9s %14s" % ("tabela (po uuid)", "nowe", "usun.", "zmienione", "przenumerowane"))
    print("-" * 74)
    bez = []
    for w in wynik:
        if not w["uuid"]:
            bez.append("%s (%s)" % (w["tabela"], w.get("powod", "")))
            continue
        if not (w["nowe"] or w["usuniete"] or w["zmienione"] or w["przenumerowane"]):
            continue
        print("%-32s %7d %7d %9d %14d" % (w["tabela"], len(w["nowe"]), len(w["usuniete"]),
                                          len(w["zmienione"]), len(w["przenumerowane"])))
        for u in w["usuniete"][:limit]:
            print("     usunięty:  %s (był fid %s)" % (u, w["fid_a"][u]))
        for u in w["przenumerowane"][:limit]:
            print("     ten sam obiekt, inny fid: %s  fid %s -> %s" % (u, w["fid_a"][u], w["fid_b"][u]))
    print("-" * 74)
    if bez:
        print("bez uuid — tylko liczniki (%d): %s%s" % (len(bez), ", ".join(bez[:6]), " …" if len(bez) > 6 else ""))
        print("   uuid dopisuje aplikacja: Projekt → Napraw projekt → „Uzupełnij identyfikatory”.")


def main(argv):
    if len(argv) >= 3 and argv[0] == "porownaj":
        drukuj_porownanie(porownaj(argv[1], argv[2]))
        return 0
    if len(argv) >= 2 and argv[0] == "sprawdz":
        out, problemy = sprawdz(argv[1])
        print("\n".join(out))
        print()
        print("Problemów tożsamości: %d" % problemy if problemy else "Tożsamość spójna.")
        return 1 if problemy else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
