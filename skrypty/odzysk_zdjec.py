#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
odzysk_zdjec.py — czy któraś stara wersja zna zdjęcie płatu, który dziś go nie ma.

    python3 odzysk_zdjec.py --biezaca dane_pgrs_v12_0_ZAL.gpkg --szukaj ~/WorkField
    python3 odzysk_zdjec.py --biezaca ... --szukaj ... --dcim ~/WorkField/zwroty --csv odzysk.csv
    python3 odzysk_zdjec.py --biezaca ... --szukaj ... --napraw --wykonaj

Domyślnie NICZEGO NIE ZMIENIA — to rozeznanie. `--napraw` dopisuje brakujące
wiersze załączników do NOWEJ wersji pliku; wersja wejściowa zostaje nietknięta.

TO NIE JEST `spis_zdjec.py`. Tamten pyta: co mamy na dysku, gdzie, ile razy
i czy jest w bazie — idzie od PLIKU. Ten idzie od PŁATU i pyta o jedno:
**czy jakakolwiek inna wersja bazy zna załącznik dla płatu, który w bieżącej
nie ma żadnego.** Pierwszy szuka sierot, drugi szuka strat.

----------------------------------------------------------------------------
Dlaczego czyta WSZYSTKIE pokolenia nazewnictwa ZAL_
----------------------------------------------------------------------------
2.10.2026 doposażenie modułu `zalaczniki` v2 założyło w terenie drugi,
równoległy zestaw tabel: `ZAL_FITO_PLATY` obok `ZAL_PLATY`, przy IDENTYCZNYCH
kolumnach. Trzy zdjęcia z tego dnia wylądowały w nowej tabeli, a każda
kontrola patrząca na `ZAL_PLATY` odpowiadała, że ich nie ma — stąd zgłoszenie
„zdjęcia zgubiły się z niewiadomych powodów". Zdjęcia nie zginęły; zginęła
nazwa, pod którą ich szukano (`claude/AWARIA_zalaczniki_v2.md`).

Wniosek na stałe: nazwa tabeli załączników jest ZMIENNĄ, nie stałą. Szukamy
po wzorcu `ZAL_%` i po kształcie kolumn, nigdy po jednej nazwie.

----------------------------------------------------------------------------
Dlaczego klucz to fid, a nie ID_PŁATU
----------------------------------------------------------------------------
Zmierzone na łańcuchu PGRS (10 wersji, od `arch/dane.gpkg` do wydania):
`fid` płatu jest stabilny — 345 wspólnych `fid`, 345 zgodnych `ID_PŁATU`,
zero rozjazdów. Natomiast w dwóch najstarszych plikach `ID_PŁATU` jest
PUSTE W CAŁOŚCI (352 płaty, 0 wypełnionych), bo pochodzą sprzed
przenumerowania. Dopasowanie po `ID_PŁATU` milczałoby tam na wszystkim.

Ale `fid` jest stabilny tylko WEWNĄTRZ łańcucha jednego parku. Dlatego:
  * park rozstrzyga `ID_OBIEKTU`, nie numery płatów (numery PZE 1–138 są
    podzbiorem numerów PTR 1–175 — sprawdzone 01.10, katalog zdjęć PZE
    dopasował się do PTR w 99 %);
  * gdy kandydat ma niepuste `ID_PŁATU` SPRZECZNE z bieżącą bazą pod tym
    samym `fid`, wiersz jest ODRZUCANY i zgłaszany, nie dopasowywany.
"""
import argparse
import collections
import os
import re
import shutil
import sqlite3
import sys
from datetime import datetime

# Geometria z osobnego modułu, wspólnego ze scal_parki.py. Musi leżeć obok.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import geom_gpkg as GEO
except ImportError:
    GEO = None

WERSJA = "1.4.0"   # nośniki wymienne i migawki przerwane rozpoznawane osobno

OBRAZY = (".jpg", ".jpeg", ".png", ".heic", ".heif")


def jest_obrazem(sciezka):
    """Czy to w ogóle odwołanie do pliku zdjęcia.

    Skąd: w `dane.gpkg` kolumna FOTO ma 111 wartości, które plikami nie są —
    `DCIM/R` sto dziewięć razy i `DCIM/I` dwa razy. To ślad po wyrażeniu,
    które wpisało jedną literę zamiast ścieżki. Bez tego filtru naprawa
    dopisałaby je do ZAL_PLATY jako ścieżki do zdjęć."""
    return os.path.splitext(str(sciezka).strip())[1].lower() in OBRAZY

# Kolumny, po których rozpoznajemy tabelę załączników — niezależnie od nazwy.
KSZTALT_ZAL = {"SCIEZKA"}
KLUCZE_RODZICA = ("ID_RODZICA", "ID_PŁATU", "ID_PLATU", "FID_PLATU")
# Warstwa nadrzędna dla danej tabeli załączników. Nazwa tabeli jest zmienną,
# więc rozpoznajemy po rdzeniu: ZAL_PLATY i ZAL_FITO_PLATY to ten sam rodzic.
RDZEN_PLATY = re.compile(r"^ZAL_(FITO_)?PLATY$", re.I)


# Katalogi montowań nośników wymiennych. Plik, który leży TYLKO tam, nie jest
# „na dysku": po odłączeniu pendrive'a wiersz wskazuje w pustkę.
WYMIENNE = ("/run/media/", "/media/", "/mnt/", "/run/mount/")


def wymienny(sciezka):
    return any(str(sciezka).startswith(w) for w in WYMIENNE)


# Ile członów ścieżki po katalogu montowań identyfikuje NOŚNIK. Przy udisks
# jest to /run/media/<użytkownik>/<etykieta>, więc dwa — jeden dałby
# „/run/media/piotr", czyli użytkownika zamiast dysku.
CZLONY_NOSNIKA = {"/run/media/": 2, "/run/mount/": 2, "/media/": 1, "/mnt/": 1}


def nosnik(sciezka):
    """Korzeń nośnika — do rozbicia liczb na dysk stały i wymienny."""
    s = os.path.abspath(sciezka)
    for w in WYMIENNE:
        if s.startswith(w):
            czesci = [x for x in s[len(w):].split(os.sep) if x]
            return w + os.sep.join(czesci[:CZLONY_NOSNIKA.get(w, 1)])
    return "dysk stały"


NIEPLIKI = collections.Counter()
SKASOWANE = collections.defaultdict(dict)
SIEROTY = collections.defaultdict(dict)
NUMERACJA = []


def otw_ro(p):
    return sqlite3.connect("file:%s?mode=ro" % p, uri=True)


def tabele(c):
    return [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")]


def kolumny(c, t):
    return [r[1] for r in c.execute('PRAGMA table_info("%s")' % t)]


def park(c):
    for t in ("FITO_PLATY", "FITO_SPIS_GATUNKOWY"):
        try:
            w = [str(r[0]) for r in c.execute(
                'SELECT DISTINCT ID_OBIEKTU FROM "%s" WHERE ID_OBIEKTU IS NOT NULL' % t)]
            if len(w) == 1:
                return w[0]
            if w:
                return "+".join(sorted(w))
        except sqlite3.Error:
            continue
    return None


def tabele_zalacznikow(c):
    """Wszystkie tabele załączników płatów, bez względu na pokolenie nazwy."""
    wynik = []
    for t in tabele(c):
        if not t.upper().startswith("ZAL_"):
            continue
        ks = set(kolumny(c, t))
        if not KSZTALT_ZAL <= ks:
            continue
        if not RDZEN_PLATY.match(t):
            continue                     # ZAL_GATUNKI, ZAL_ZDJECIA_FITO — inny rodzic
        po = next((k for k in KLUCZE_RODZICA if k in ks), None)
        if po:
            wynik.append((t, po))
    return wynik


NIEPEWNE_GEO = []        # (stary_fid, cel, udzial, nazwa, plik)
BEZ_PLATU_GEO = []       # (stary_fid, nazwa, plik) — dawny płat poza dzisiejszymi


def kol_geom(c, t):
    """Nazwa kolumny geometrii. Nie zakładamy `geom` — bywa `geometry`."""
    try:
        r = c.execute("SELECT column_name FROM gpkg_geometry_columns "
                      "WHERE table_name=?", (t,)).fetchone()
        if r:
            return r[0]
    except sqlite3.Error:
        pass
    for k in kolumny(c, t):
        if k.lower() in ("geom", "geometry", "shape", "the_geom"):
            return k
    return None


def wczytaj_platy_geo(c):
    """[(fid, wkb, obwiednia)] z FITO_PLATY. Pusta lista, gdy brak geometrii."""
    g = kol_geom(c, "FITO_PLATY")
    if not g or GEO is None:
        return []
    w = []
    for fid, blob in c.execute('SELECT fid, "%s" FROM FITO_PLATY' % g):
        if not blob:
            continue
        srs, wkb = GEO.czytaj_blob(blob)
        if not wkb:
            continue
        ob = GEO.obwiednia(wkb)
        if ob:
            w.append((fid, wkb, ob, srs))
    return w


def dopasuj_po_geometrii(stary_wkb, dzisiejsze, prog, ile_probek=60):
    """Który dzisiejszy płat pokrywa najwięcej dawnego. (cel, udział, głosów).

    Nie po `fid` — bo po przenumerowaniu nie znaczy tego samego — i nie po
    numerze płatu, bo on też został nadany od nowa. Po tym, co się nie
    zmieniło: po miejscu w terenie. Głosy punktów rozłożonych wewnątrz dawnego
    płatu przybliżają udział powierzchni; płat rozcięty na pół daje udział
    ~50%, czyli poniżej progu, i zostaje NIEROZSTRZYGNIĘTY."""
    pr = GEO.probki(stary_wkb, ile_probek)
    if not pr:
        return (None, 0.0, 0)
    glosy = collections.Counter()
    for q in pr:
        for fid, wkb, ob, _ in dzisiejsze:
            if GEO.zawiera(wkb, q, ob):
                glosy[fid] += 1
                break
    if not glosy:
        return (None, 0.0, 0)
    cel, n = glosy.most_common(1)[0]
    udzial = n / float(len(pr))
    return (cel if udzial >= prog else None, udzial, n)


def mapa_platow(c):
    """fid -> ID_PŁATU (albo None, gdy kolumna pusta — tak jest w najstarszych)."""
    kol = "ID_PŁATU" if "ID_PŁATU" in kolumny(c, "FITO_PLATY") else "ID_PLATU"
    m = {}
    for f, i in c.execute('SELECT fid, "%s" FROM FITO_PLATY' % kol):
        s = None if i is None or not str(i).strip() else str(i).strip()
        m[f] = s
    return m


def zbierz_zalaczniki(c, mapa):
    """[(fid, nazwa_pliku, sciezka, czas, tabela)] — po fid, bo ten jest stabilny."""
    wynik = []
    for t, po in tabele_zalacznikow(c):
        ks = kolumny(c, t)
        czas = "CZAS" if "CZAS" in ks else None
        q = 'SELECT "%s", SCIEZKA%s FROM "%s"' % (po, ', "%s"' % czas if czas else "", t)
        for r in c.execute(q):
            klucz, sciezka = r[0], r[1]
            cz = r[2] if czas else None
            if not sciezka or not str(sciezka).strip():
                continue
            if not jest_obrazem(sciezka):
                NIEPLIKI[str(sciezka).strip()[:40]] += 1
                continue
            if po in ("ID_RODZICA", "FID_PLATU"):
                fid = klucz
            else:
                # klucz to ID_PŁATU — przeliczamy na fid przez mapę TEJ bazy
                szukane = None if klucz is None else str(klucz).strip()
                fid = next((f for f, i in mapa.items() if i == szukane), None)
            if fid is None:
                continue
            wynik.append((fid, os.path.basename(str(sciezka).strip()),
                          str(sciezka).strip(), cz, t))
    return wynik


def zbierz_foto(c, mapa):
    """Stare pole FOTO w FITO_PLATY — też jest odwołaniem do zdjęcia."""
    if "FOTO" not in kolumny(c, "FITO_PLATY"):
        return []
    wynik = []
    for fid, v in c.execute("SELECT fid, FOTO FROM FITO_PLATY"):
        if v and str(v).strip() and not jest_obrazem(v):
            NIEPLIKI[str(v).strip()[:40]] += 1
            continue
        if v and str(v).strip():
            wynik.append((fid, os.path.basename(str(v).strip()),
                          str(v).strip(), None, "FITO_PLATY.FOTO"))
    return wynik


def migawka_przerwana(katalog):
    """Czy ten katalog to migawka, która się nie dokończyła.

    Skąd: `snap_2026-10-06_1141_dane` ma 2,7 GB i `przerwane: true`
    w `KOPIA.json` — z łańcucha kopii wyklucza się sama (OTWARTE, B7).
    Baza skopiowana w połowie otwiera się bez błędu i ma mniej wierszy,
    więc „plik jest na dysku" policzone z niej byłoby nieprawdą."""
    j = os.path.join(katalog, "KOPIA.json")
    if not os.path.isfile(j):
        return False
    try:
        import json
        with open(j, encoding="utf-8") as f:
            return bool(json.load(f).get("przerwane"))
    except (OSError, ValueError):
        return False


def znajdz_gpkg(sciezki, pomijaj=(".bak_", ".przed_")):
    pliki, przerwane = [], []
    for s in sciezki:
        s = os.path.expanduser(s)
        if os.path.isfile(s) and s.endswith(".gpkg"):
            pliki.append(s)
            continue
        for korzen, katalogi, nazwy in os.walk(s):
            if migawka_przerwana(korzen):
                przerwane.append(korzen)
                katalogi[:] = []
                continue
            katalogi[:] = [d for d in katalogi if not any(w in d for w in pomijaj)]
            for n in nazwy:
                if n.endswith(".gpkg") and not any(w in n for w in pomijaj):
                    pliki.append(os.path.join(korzen, n))
    return sorted(set(pliki)), przerwane


def indeks_plikow(korzenie):
    """nazwa pliku -> ścieżka na dysku (największy przy powtórzeniu nazwy)."""
    idx, rozm = {}, {}
    for k in korzenie:
        k = os.path.expanduser(k)
        if not os.path.isdir(k):
            print("   ! nie ma katalogu: %s" % k, file=sys.stderr)
            continue
        for korzen, _, nazwy in os.walk(k):
            for n in nazwy:
                if os.path.splitext(n)[1].lower() not in (".jpg", ".jpeg", ".png", ".heic"):
                    continue
                p = os.path.join(korzen, n)
                try:
                    r = os.path.getsize(p)
                except OSError:
                    continue
                kl = n.lower()
                if kl not in idx or r > rozm[kl]:
                    idx[kl], rozm[kl] = p, r
    return idx


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wersja", action="store_true",
                    help="wypisz wersję narzędzia i wyjdź")
    ap.add_argument("--biezaca", help="baza obowiązująca (kopia _ZAL)")
    ap.add_argument("--szukaj", nargs="+",
                    help="katalogi albo pliki .gpkg do przeszukania")
    ap.add_argument("--dcim", action="append", default=[],
                    help="katalog ze zdjęciami — sprawdzi, czy plik w ogóle jest na dysku")
    ap.add_argument("--csv", help="zapisz wykaz kandydatów")
    ap.add_argument("--napraw", action="store_true",
                    help="dopisz brakujące wiersze do nowej wersji pliku")
    ap.add_argument("--wykonaj", action="store_true", help="zapisz naprawę")
    ap.add_argument("--tabela-nazw", action="append", default=[],
                    help="CSV przemianowania (kolumny nazwa_z_aparatu i nowa); "
                         "bez niej nie da się rozstrzygnąć, czy stara i nowa nazwa "
                         "to ten sam plik")
    ap.add_argument("--po-geometrii", action="store_true",
                    help="dopasuj po geometrii TAKŻE w plikach, które przeszły "
                         "bramę numeracji (domyślnie tylko w odrzuconych)")
    ap.add_argument("--prog-glosow", type=float, default=0.6,
                    help="jaki udział powierzchni dawnego płatu musi leżeć "
                         "w dzisiejszym, żeby uznać dopasowanie (domyślnie 0.6)")
    ap.add_argument("--okres", metavar="OD:DO",
                    help="wyróżnij odwołania z tego okresu, np. 2026-08-15:2026-08-25")
    ap.add_argument("--wymienny-tez", action="store_true",
                    help="dopisz też pliki leżące tylko na nośniku wymiennym")
    ap.add_argument("--napraw-dodatki", action="store_true",
                    help="dopisz też odwołania dla płatów, które jakieś zdjęcie mają")
    ap.add_argument("--limit", type=int, default=12)
    a = ap.parse_args()
    if a.wersja:
        print(WERSJA)
        return 0
    if not a.biezaca or not a.szukaj:
        ap.error("--biezaca i --szukaj są wymagane")

    # Pomost między konwencjami nazw. Zmierzone: płat fid 152 ma w starych
    # wersjach JPEG_20260812090203393.JPG, a w wydaniu 124_20260812_110213.jpg —
    # ta sama data, godzina różna o 2 h 10 s, bo przemianowanie wzięło czas
    # z EXIF, a nie z nazwy. Po stemplu czasu TEŻ się tego nie dopasuje.
    # Jedynym pewnym pomostem jest tabela przemianowania.
    rownowazne = {}
    for t in a.tabela_nazw:
        import csv as _c
        try:
            with open(os.path.expanduser(t), encoding="utf-8-sig", newline="") as f:
                for w in _c.DictReader(f):
                    stara = (w.get("nazwa_z_aparatu") or w.get("sciezka") or "").strip()
                    nowa = (w.get("nowa") or w.get("sciezka_docelowa") or "").strip()
                    if stara and nowa:
                        rownowazne[os.path.basename(stara).lower()] = \
                            os.path.basename(nowa).lower()
        except OSError as e:
            print("   ! tabela nazw %s: %s" % (t, e), file=sys.stderr)
    if rownowazne:
        print("tabela przemianowania: %d powiązań nazw" % len(rownowazne))

    def norm(nazwa):
        n = nazwa.lower()
        return rownowazne.get(n, n)

    c = otw_ro(a.biezaca)
    mapa = mapa_platow(c)
    park_b = park(c)
    zal_b = zbierz_zalaczniki(c, mapa) + zbierz_foto(c, mapa)
    tab_b = tabele_zalacznikow(c)
    c.close()

    pary_b = {(f, norm(n)) for f, n, *_ in zal_b}
    maja_b = collections.Counter(f for f, *_ in zal_b)
    bez_zdjec = {f for f in mapa if maja_b.get(f, 0) == 0}

    print("=" * 76)
    print("ODZYSK ZDJĘĆ %s — %s" % (WERSJA, os.path.basename(a.biezaca)))
    print("=" * 76)
    print("park %s, płatów %d, tabele załączników: %s"
          % (park_b, len(mapa), ", ".join("%s (po %s)" % x for x in tab_b) or "BRAK"))
    print("odwołań do zdjęć %d, różnych par płat+plik %d" % (len(zal_b), len(pary_b)))
    print("PŁATÓW BEZ ANI JEDNEGO ZDJĘCIA: %d" % len(bez_zdjec))
    print()

    kandydaci, przerwane = znajdz_gpkg(a.szukaj)
    print("przeszukuję %d plików .gpkg" % len(kandydaci))
    if przerwane:
        print("   pominięte migawki PRZERWANE (przerwane: true w KOPIA.json): %d"
              % len(przerwane))
        for k in przerwane[:3]:
            print("      %s" % k)
    # Rozbicie na nośniki — żeby było widać, co dołożył dysk zewnętrzny.
    wg_nosnika = collections.Counter(nosnik(p) for p in kandydaci)
    if len(wg_nosnika) > 1:
        for n, ile in wg_nosnika.most_common():
            print("   %-46s %d plików%s" % (n, ile,
                  "  (NOŚNIK WYMIENNY)" if wymienny(n) else ""))

    # Lokalizator dzisiejszych płatów — czytany RAZ, bo służy każdemu
    # plikowi źródłowemu z inną numeracją.
    c = otw_ro(a.biezaca)
    dzisiejsze = wczytaj_platy_geo(c)
    c.close()
    srs_b = {x[3] for x in dzisiejsze}
    if GEO is None:
        print("   ! nie ma geom_gpkg.py obok skryptu — dopasowanie po geometrii")
        print("     wyłączone. Skopiuj $REPO/skrypty/geom_gpkg.py obok tego pliku.")
    elif dzisiejsze:
        print("lokalizator: %d dzisiejszych płatów z geometrią, srs %s"
              % (len(dzisiejsze), ", ".join(str(x) for x in sorted(srs_b))))
    else:
        print("   ! bieżąca baza nie ma geometrii płatów — zostaje tylko fid")

    nowe = []                      # (fid, nazwa, sciezka, czas, tabela, plik_zrodlowy)
    sprzeczne = []
    po_geo = collections.Counter()
    pominiete = collections.Counter()
    przejrzane = 0
    for p in kandydaci:
        if os.path.abspath(p) == os.path.abspath(a.biezaca):
            continue
        try:
            cc = otw_ro(p)
            if "FITO_PLATY" not in tabele(cc):
                pominiete["bez FITO_PLATY"] += 1
                cc.close(); continue
            pk = park(cc)
            # Park rozstrzyga ID_OBIEKTU. Numery płatów go NIE identyfikują.
            if pk and park_b and pk != park_b:
                pominiete["inny park (%s)" % pk] += 1
                cc.close(); continue
            m = mapa_platow(cc)
            # Brama numeracji. `fid` jest kluczem tylko wtedy, gdy oba pliki
            # należą do tego samego łańcucha. `pgrs_baza.gpkg` ma park 2602,
            # 19 płatów o fid 5–95, ZERO wspólnych z wydaniem (96–507)
            # i ID_PŁATU puste w całości — to fragment z 28.07 w innej generacji
            # numeracji. Bez tej bramy jego pole FOTO wyglądało jak 21 zdjęć
            # „płatów skasowanych", a fid 80 nie znaczy tam nic wspólnego.
            # Ta sama rodzina błędu co numery płatów PZE dopasowane do PTR.
            wspolne = len(set(m) & set(mapa))
            inna_numeracja = bool(m) and wspolne == 0
            if inna_numeracja and not (dzisiejsze and GEO):
                pominiete["inna numeracja fid (0 wspólnych z %d)" % len(m)] += 1
                cc.close(); continue
            if m and wspolne < len(m) * 0.5:
                NUMERACJA.append((p, wspolne, len(m)))
            lista = zbierz_zalaczniki(cc, m) + zbierz_foto(cc, m)
            przejrzane += 1

            # ---- dopasowanie po geometrii
            #
            # Tu jest sedno odzysku z generacji sprzed przenumerowania.
            # Plik z 20.08 ma WŁASNĄ numerację fid — zero wspólnych
            # z wydaniem — więc po fid nie da się z niego wyjąć nic, choćby
            # zdjęcia tam siedziały. To, co w nim NIE straciło znaczenia,
            # to geometria: dawny płat leży w tym samym miejscu w terenie,
            # co dzisiejszy, który go zastąpił.
            if inna_numeracja or a.po_geometrii:
                geo_k = wczytaj_platy_geo(cc)
                stare_geo = {f: (w_, o_) for f, w_, o_, _ in geo_k}
                srs_k = {s_ for _, _, _, s_ in geo_k}
                if srs_k and srs_b and srs_k != srs_b:
                    pominiete["inny układ współrzędnych (%s)"
                              % ", ".join(str(x) for x in srs_k)] += 1
                    cc.close(); continue
                cel_dla = {}
                for fid, nazwa, sciezka, czas, tab in lista:
                    if fid not in stare_geo:
                        BEZ_PLATU_GEO.append((fid, nazwa, os.path.basename(p)))
                        continue
                    if fid not in cel_dla:
                        cel_dla[fid] = dopasuj_po_geometrii(
                            stare_geo[fid][0], dzisiejsze, a.prog_glosow)
                    cel, udzial, _ = cel_dla[fid]
                    if cel is None:
                        NIEPEWNE_GEO.append((fid, None, udzial, nazwa,
                                             os.path.basename(p)))
                        continue
                    if (cel, norm(nazwa)) in pary_b:
                        continue
                    nowe.append((cel, nazwa, sciezka, czas,
                                 "%s ~geo %.0f%% z fid %s" % (tab, 100 * udzial, fid),
                                 p))
                    po_geo[os.path.basename(p)] += 1
                if inna_numeracja:
                    pominiete["inna numeracja fid -> dopasowane po geometrii"] += 1
                cc.close(); continue
            for fid, nazwa, sciezka, czas, tab in lista:
                if fid not in mapa:
                    # Dwa różne przypadki, które trzeba rozdzielić:
                    #  * fid istnieje we WŁASNEJ FITO_PLATY kandydata, a nie ma go
                    #    w bieżącej — płat skasowany między wersjami; jego zdjęcia
                    #    należą do płatu, który go wchłonął (decyzja merytoryczna);
                    #  * fid nie istnieje nawet u kandydata — wiersz był sierotą
                    #    już tam i nie ma czego ratować.
                    gdzie = SKASOWANE if fid in m else SIEROTY
                    gdzie[fid][norm(nazwa)] = (nazwa, os.path.basename(p))
                    continue
                # straż przed cichym dopasowaniem przy przenumerowaniu
                if m.get(fid) and mapa.get(fid) and m[fid] != mapa[fid]:
                    sprzeczne.append((fid, m[fid], mapa[fid], p))
                    continue
                if (fid, norm(nazwa)) in pary_b:
                    continue
                nowe.append((fid, nazwa, sciezka, czas, tab, p))
            cc.close()
        except Exception as e:
            pominiete["błąd odczytu"] += 1
            print("   ! %s: %s" % (os.path.basename(p), e), file=sys.stderr)

    print("przejrzanych z tego parku: %d" % przejrzane)
    for k, v in pominiete.most_common():
        print("   pominięto — %s: %d" % (k, v))
    if NIEPLIKI:
        print("   odwołania, które NIE SĄ plikiem obrazu: %d (%s)"
              % (sum(NIEPLIKI.values()),
                 ", ".join("%r×%d" % x for x in NIEPLIKI.most_common(3))))
    if NUMERACJA:
        print()
        print("CZĘŚCIOWE POKRYCIE NUMERACJI — liczę, ale ostrożnie:")
        for pl, w, ile in NUMERACJA[:a.limit]:
            print("      %-44s %d z %d fid wspólnych" % (os.path.basename(pl)[:44], w, ile))
    if SIEROTY:
        print()
        print("SIEROTY W PLIKACH ŹRÓDŁOWYCH: %d różnych zdjęć w %d kluczach"
              % (sum(len(v) for v in SIEROTY.values()), len(SIEROTY)))
        print("   Te wiersze nie miały rodzica już w pliku, z którego pochodzą —")
        print("   nie ma czego ratować, jest co posprzątać u źródła.")
    if SKASOWANE:
        print()
        print("ZAŁĄCZNIKI PŁATÓW SKASOWANYCH MIĘDZY WERSJAMI: %d różnych zdjęć "
              "w %d płatach" % (sum(len(v) for v in SKASOWANE.values()), len(SKASOWANE)))
        print("   Te płaty nie istnieją w bieżącej bazie, więc nie ma do czego")
        print("   dopisać. Jeżeli były scalone z innymi, zdjęcia należą do płatu,")
        print("   który je wchłonął — to decyzja merytoryczna, nie mechaniczna.")
        for fid in sorted(SKASOWANE)[:a.limit]:
            pierwsze = next(iter(SKASOWANE[fid].values()))[0]
            print("      fid %-5s %d zdjęć, np. %s"
                  % (fid, len(SKASOWANE[fid]), pierwsze[:46]))
    print()

    if po_geo:
        print()
        print("DOPASOWANE PO GEOMETRII: %d odwołań z %d plików"
              % (sum(po_geo.values()), len(po_geo)))
        print("   Te pliki mają własną numerację fid — po fid nie dałoby się")
        print("   z nich wyjąć nic. Dopasowanie idzie po tym, co się nie")
        print("   zmieniło: dawny płat leży w tym samym miejscu w terenie.")
        print("   Udział powierzchni jest wpisany w kolumnie tabeli źródłowej.")
        for n, i in po_geo.most_common(a.limit):
            print("      %-44s %4d" % (n, i))
    if NIEPEWNE_GEO:
        print()
        print("NIEROZSTRZYGNIĘTE PO GEOMETRII: %d odwołań" % len(NIEPEWNE_GEO))
        print("   Dawny płat rozkłada się na kilka dzisiejszych i żaden nie ma")
        print("   %.0f%% jego powierzchni — czyli płat został ROZCIĘTY, a to,"
              % (100 * a.prog_glosow))
        print("   do którego z kawałków należy zdjęcie, widać na zdjęciu,")
        print("   nie w geometrii. Decyzja autora, nie skryptu.")
        for fid, _, u, nazwa, zp in sorted(NIEPEWNE_GEO,
                                           key=lambda x: -x[2])[:a.limit]:
            print("      dawny fid %-6s najlepszy udział %3.0f%%  %-32s %s"
                  % (fid, 100 * u, nazwa[:32], zp))
        if len(NIEPEWNE_GEO) > a.limit:
            print("      ...i jeszcze %d" % (len(NIEPEWNE_GEO) - a.limit))
    if BEZ_PLATU_GEO:
        print()
        print("BEZ GEOMETRII U ŹRÓDŁA: %d odwołań — wiersz wskazywał płat,"
              % len(BEZ_PLATU_GEO))
        print("   którego nie ma we własnej FITO_PLATY pliku źródłowego.")

    if sprzeczne:
        print("ODRZUCONE — ten sam fid, inny ID_PŁATU (przenumerowanie):")
        for fid, a_, b_, p in sprzeczne[:a.limit]:
            print("   fid %-5s kandydat %-6s bieżąca %-6s  %s"
                  % (fid, a_, b_, os.path.basename(p)))
        print("   razem %d — tych NIE dopasowuję, bo to może być inny płat." % len(sprzeczne))
        print()

    # jedna para płat+plik może wystąpić w wielu wersjach — grupujemy
    wg_pary = collections.OrderedDict()
    for fid, nazwa, sciezka, czas, tab, p in nowe:
        wg_pary.setdefault((fid, norm(nazwa)),
                           {"fid": fid, "nazwa": nazwa, "sciezka": sciezka,
                            "czas": czas, "tabele": set(), "pliki": []})
        w = wg_pary[(fid, norm(nazwa))]
        w["tabele"].add(tab)
        w["pliki"].append(p)
        if czas and not w["czas"]:
            w["czas"] = czas

    idx = indeks_plikow(a.dcim) if a.dcim else {}
    for w in wg_pary.values():
        w["na_dysku"] = idx.get(w["nazwa"].lower()) if idx else None
        w["wymienny"] = bool(w["na_dysku"]) and wymienny(w["na_dysku"])

    # --- okres straty. Daty szukamy w CZAS, a gdy go nie ma — w nazwie pliku,
    # bo nazwy niosą znacznik 20260820_... Nie zgadujemy z czasu pliku na
    # dysku: kopiowanie i rozpakowanie archiwum przestawiają mtime, a wtedy
    # „okres" pokazywałby dzień kopii, nie dzień zdjęcia.
    okres = None
    if a.okres and ":" in a.okres:
        od, do = [x.strip().replace("-", "") for x in a.okres.split(":", 1)]
        okres = (od, do)
    def w_okresie(w):
        if not okres:
            return False
        zrodla = [str(w.get("czas") or "")]
        zrodla += [str(w.get("nazwa") or "")]
        for z in zrodla:
            for m8 in re.findall(r"20\d{6}", z.replace("-", "")):
                if okres[0] <= m8 <= okres[1]:
                    return True
        return False
    for w in wg_pary.values():
        w["w_okresie"] = w_okresie(w)
    if okres:
        ile_ok = sum(1 for w in wg_pary.values() if w["w_okresie"])
        print()
        print("W OKRESIE %s–%s: %d z %d znalezionych odwołań"
              % (okres[0], okres[1], ile_ok, len(wg_pary)))
        if not ile_ok and wg_pary:
            print("   Żadne znalezione odwołanie nie ma daty z tego okresu.")
            print("   Sprawdź, czy przeszukane katalogi obejmują migawki z tamtych dni.")

    strata = [w for w in wg_pary.values() if w["fid"] in bez_zdjec]
    dodatek = [w for w in wg_pary.values() if w["fid"] not in bez_zdjec]
    # „Strata" jest pewna niezależnie od konwencji nazw: płat NIE MA ani jednego
    # zdjęcia, więc każde znalezione odwołanie jest nową wiedzą. „Dodatek"
    # pewny nie jest — bez tabeli przemianowania nie wiadomo, czy to nowe
    # zdjęcie, czy to samo pod starą nazwą.
    niepewne = not rownowazne and bool(dodatek)

    print("=" * 76)
    print("ZNALEZIONE ODWOŁANIA, KTÓRYCH BIEŻĄCA BAZA NIE MA: %d" % len(wg_pary))
    print("   w płatach BEZ ŻADNEGO zdjęcia (to są straty) .... %d" % len(strata))
    print("   w płatach, które jakieś zdjęcie mają (dodatek) ... %d" % len(dodatek))
    if niepewne:
        print()
        print("   UWAGA: dodatków NIE DA SIĘ rozstrzygnąć bez tabeli przemianowania.")
        print("   Wersje używają trzech konwencji nazw naraz, a przemianowanie wzięło")
        print("   czas z EXIF, nie z nazwy — ten sam plik ma w wydaniu inną godzinę")
        print("   niż w zwrocie. Podaj --tabela-nazw przeksztalcenie_nazw_<park>.csv,")
        print("   inaczej część z tych %d to te same zdjęcia pod starą nazwą." % len(dodatek))
    if idx:
        bez_pliku = [w for w in wg_pary.values() if not w["na_dysku"]]
        tylko_wym = [w for w in wg_pary.values() if w["wymienny"]]
        print("   z tego nie ma pliku nigdzie ...................... %d" % len(bez_pliku))
        if tylko_wym:
            print("   plik TYLKO na nośniku wymiennym .................. %d" % len(tylko_wym))
            print("      Dopisanie wiersza wskazującego na odłączany nośnik przenosi")
            print("      problem, nie naprawia. Najpierw skopiuj te pliki na dysk stały.")
    print()

    if strata:
        print("STRATY — płat bez zdjęcia, a wersja je zna:")
        for w in sorted(strata, key=lambda x: x["fid"])[:a.limit]:
            print("   płat %-6s %-40s %s" % (mapa.get(w["fid"]) or "fid %s" % w["fid"],
                                             w["nazwa"][:40],
                                             ("NA NOŚNIKU WYMIENNYM" if w["wymienny"]
                                              else "NA DYSKU") if w["na_dysku"] else
                                             ("brak pliku" if idx else "")))
            print("        %s  (%s)" % (", ".join(sorted(w["tabele"])),
                                        os.path.basename(w["pliki"][0])))
        if len(strata) > a.limit:
            print("   ...i jeszcze %d" % (len(strata) - a.limit))
        print()

    if a.csv:
        import csv as _csv
        with open(a.csv, "w", newline="", encoding="utf-8") as f:
            wr = _csv.writer(f)
            wr.writerow(["ID_PLATU", "fid", "rodzaj", "nazwa_pliku", "sciezka_w_bazie",
                         "czas", "tabela_zrodlowa", "plik_zrodlowy", "na_dysku",
                         "nosnik_wymienny", "w_okresie"])
            for w in sorted(wg_pary.values(), key=lambda x: x["fid"]):
                wr.writerow([mapa.get(w["fid"]) or "", w["fid"],
                             "strata" if w["fid"] in bez_zdjec else "dodatek",
                             w["nazwa"], w["sciezka"], w["czas"] or "",
                             ";".join(sorted(w["tabele"])), w["pliki"][0],
                             w["na_dysku"] or "",
                             "tak" if wymienny(w["na_dysku"] or "") else "",
                             "tak" if w.get("w_okresie") else ""])
        print("wykaz: %s" % a.csv)

    if not a.napraw:
        print()
        print("Nic nie zmieniono. To rozeznanie. Naprawa: --napraw [--wykonaj]")
        return 0

    # ----------------------------------------------------------------- naprawa
    if not tab_b:
        print("Bieżąca baza nie ma tabeli załączników — nie ma gdzie dopisać.",
              file=sys.stderr)
        return 2
    # Dopisujemy do pokolenia, które w bieżącej bazie ma NAJWIĘCEJ wierszy:
    # to ono niesie dane, a nie to, które założyło się samo w terenie.
    c = otw_ro(a.biezaca)
    ile = {t: c.execute('SELECT count(*) FROM "%s"' % t).fetchone()[0] for t, _ in tab_b}
    c.close()
    cel_tab, cel_po = max(tab_b, key=lambda x: ile[x[0]])
    print()
    print("dopisuję do %s (po %s), bo ma najwięcej wierszy: %s"
          % (cel_tab, cel_po, ", ".join("%s=%d" % x for x in ile.items())))

    # ---- brama naprawy: bez indeksu plików nie wolno dopisać ANI JEDNEGO wiersza
    #
    # Do 1.2.0 naprawa wpisywała wszystkie straty, nie patrząc na `na_dysku`.
    # Przebieg PGRS 16.10: 20 strat, z tego 14 z adnotacją „brak pliku" —
    # naprawa dopisałaby 14 odwołań do plików, których nie ma NIGDZIE.
    # Skutek jest gorszy niż brak zdjęcia: płat pokazuje LICZBA_ZDJEC = 1,
    # styl przestaje go świecić jako zero, załącznik otwiera pustkę,
    # a człowiek jedzie w teren z mapą, która mówi, że to już zrobione.
    # Bez `--dcim` skrypt nie WIE, czy plik istnieje — i właśnie dlatego
    # nie ma prawa zgadywać.
    if not idx:
        print()
        print("ODMAWIAM naprawy bez --dcim.", file=sys.stderr)
        print("Bez indeksu plików nie wiem, czy plik istnieje, a odwołanie do",
              file=sys.stderr)
        print("nieistniejącego pliku jest gorsze niż brak odwołania: płat wygląda",
              file=sys.stderr)
        print("wtedy na opisany i wypada z listy do zrobienia w terenie.",
              file=sys.stderr)
        return 2

    kandydaci = sorted(strata if not a.napraw_dodatki else wg_pary.values(),
                       key=lambda x: x["fid"])
    odsiane = collections.Counter()
    do_zapisu = []
    for w in kandydaci:
        if not w["na_dysku"]:
            odsiane["nie ma pliku nigdzie"] += 1
            continue
        if w["wymienny"] and not a.wymienny_tez:
            odsiane["plik tylko na nośniku wymiennym"] += 1
            continue
        do_zapisu.append(w)
    if odsiane:
        print()
        print("ODSIANE przed zapisem (zostają w wykazie CSV, nie w bazie):")
        for r, n in sorted(odsiane.items(), key=lambda x: -x[1]):
            print("   %-44s %4d" % (r, n))
        if odsiane["plik tylko na nośniku wymiennym"]:
            print("   Skopiuj te pliki na dysk stały albo wymuś --wymienny-tez;")
            print("   odwołanie do odłączanego nośnika przenosi problem, nie naprawia.")
    if not a.napraw_dodatki:
        print("dopisuję TYLKO straty: %d z %d (resztę odsiano wyżej). Dodatki "
              "wymagają tabeli nazw i --napraw-dodatki."
              % (len(do_zapisu), len(strata)))
    elif niepewne:
        print("ODMAWIAM: --napraw-dodatki bez --tabela-nazw dopisałoby te same "
              "zdjęcia pod starą nazwą.", file=sys.stderr)
        return 2
    if not do_zapisu:
        print("nie ma czego dopisać")
        return 0

    cel = re.sub(r"\.gpkg$", "", a.biezaca) + "_odzysk.gpkg"
    if not a.wykonaj:
        print("SUCHO — dopisałbym %d wierszy do %s" % (len(do_zapisu), cel))
        return 0

    shutil.copy2(a.biezaca, cel)
    for k in ("-wal", "-shm"):
        if os.path.exists(cel + k):
            os.remove(cel + k)
    cc = sqlite3.connect(cel)
    cc.execute("PRAGMA foreign_keys=OFF")
    wyzw = list(cc.execute("SELECT name, sql FROM sqlite_master WHERE type='trigger' "
                           "AND sql IS NOT NULL"))
    for n, _ in wyzw:
        cc.execute('DROP TRIGGER IF EXISTS "%s"' % n)
    ks = kolumny(cc, cel_tab)

    # Ścieżkę budujemy z MIEJSCA, W KTÓRYM PLIK LEŻY, a nie z zapisu starej bazy.
    # PTR trzymał zdjęcia w podkatalogach (DCIM/PTR ×158), a wydanie ma jeden
    # płaski DCIM — przepisanie starej ścieżki dałoby odwołanie do katalogu,
    # którego już nie ma. Wzorzec bierzemy z tego, co w TEJ tabeli przeważa.
    przedrostki = collections.Counter()
    for (sc,) in cc.execute('SELECT SCIEZKA FROM "%s" WHERE SCIEZKA IS NOT NULL'
                            % cel_tab):
        if os.path.splitext(str(sc))[1].lower() in OBRAZY:
            przedrostki[os.path.dirname(str(sc).replace("\\", "/"))] += 1
    wzor = przedrostki.most_common(1)[0][0] if przedrostki else "DCIM"
    print("ścieżki dopisywane jako %s/<nazwa> — tak zapisuje %d z %d odwołań "
          "w tej tabeli" % (wzor, przedrostki[wzor] if przedrostki else 0,
                            sum(przedrostki.values())))
    katalog_bazy = os.path.dirname(os.path.abspath(cel)) or "."
    nietrafione = []
    nast = (cc.execute('SELECT coalesce(max(fid), 0) FROM "%s"' % cel_tab).fetchone()[0]) + 1
    stempel = "[claude %s odzyskane z %%s]" % datetime.now().strftime("%d.%m")
    n_ok = 0
    for w in do_zapisu:
        wart = {"fid": nast, cel_po: (w["fid"] if cel_po in ("ID_RODZICA", "FID_PLATU")
                                      else mapa.get(w["fid"])),
                "SCIEZKA": "%s/%s" % (wzor, os.path.basename(w["na_dysku"]))
                            if wzor else os.path.basename(w["na_dysku"])}
        # Sprawdzenie, a nie założenie: czy tak zapisana ścieżka wskazuje plik
        # licząc od katalogu bazy. Jeżeli nie — wiersz i tak powstaje (plik
        # istnieje, tylko leży gdzie indziej), ale mówimy o tym wprost.
        if not os.path.exists(os.path.join(katalog_bazy, wart["SCIEZKA"])):
            nietrafione.append((wart["SCIEZKA"], w["na_dysku"]))
        if "TYP" in ks:
            wart["TYP"] = "foto"
        if "CZAS" in ks and w["czas"]:
            wart["CZAS"] = w["czas"]
        if "UWAGI" in ks:
            wart["UWAGI"] = stempel % os.path.basename(w["pliki"][0])
        pola = [k for k in wart if k in ks]
        cc.execute('INSERT INTO "%s" (%s) VALUES (%s)'
                   % (cel_tab, ", ".join('"%s"' % k for k in pola),
                      ", ".join("?" for _ in pola)), [wart[k] for k in pola])
        nast += 1
        n_ok += 1
    for n, s in wyzw:
        try:
            cc.execute(s)
        except sqlite3.Error:
            pass
    try:
        for t, in list(cc.execute("SELECT table_name FROM gpkg_ogr_contents")):
            cc.execute('UPDATE gpkg_ogr_contents SET feature_count='
                       '(SELECT count(*) FROM "%s") WHERE table_name=?' % t, (t,))
    except sqlite3.Error:
        pass
    cc.commit()
    cc.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    cc.close()
    print("dopisane: %d wierszy -> %s" % (n_ok, cel))
    if nietrafione:
        print()
        print("UWAGA: %d dopisanych ścieżek NIE wskazuje pliku licząc od katalogu"
              % len(nietrafione))
        print("bazy. Plik istnieje, ale leży gdzie indziej — skopiuj go do %s/"
              % wzor)
        print("albo popraw ścieżkę. Dopóki tego nie zrobisz, te załączniki")
        print("nie otworzą się w WorkFieldzie:")
        for sc, gdzie in nietrafione[:10]:
            print("   %-44s plik jest w %s" % (sc, gdzie))
        if len(nietrafione) > 10:
            print("   ...i jeszcze %d" % (len(nietrafione) - 10))
    print("Wersja wejściowa nietknięta. Uruchom teraz licz_zdjecia.py na nowym pliku.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
