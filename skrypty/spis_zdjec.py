#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Inwentarz zdjęć — co mamy i gdzie, zanim cokolwiek ruszymy.

    TO NIE JEST `SpisPlikow`. Tamten (`src/core/utils/spisplikow.cpp`, panel
    „Spis plików — co zniknęło") odpowiada na pytanie **co się zmieniło
    między wczoraj a dziś** — 31 470 plików, 88,54 GB, sprawdzony w boju.
    Ten odpowiada na inne: **co mamy, gdzie, ile razy i czy jest w bazie.**
    Nie zastępuje tamtego i nie powinien. Jeśli chcesz wykrywać znikanie,
    używaj `SpisPlikow`; ten służy do jednorazowego rozeznania przed
    konsolidacją.

Odpowiada na sześć pytań, których nie da się odgadnąć z rozmowy:

  1. ILE i GDZIE — zdjęcia na katalog, rozmiar, rozszerzenia.
  2. ILE RAZY — ten sam plik w kilku miejscach. Po TREŚCI, nie po nazwie.
  3. CZY DWA POZIOMY — `.../DCIM/DCIM/...` i podobne. To ślad po przerwanym
     `adb pull` (DANE_obieg.md, punkt 4): po tygodniu nie wiadomo, który
     katalog jest prawdziwy.
  4. CO NIESIE NAZWA — konwencja Mapit z kluczem obiektu, płaska nazwa
     awaryjna, czy nic.
  5. KIEDY — rozkład na dni, ze stempla w nazwie albo z czasu pliku.
  6. CZY JEST W BAZIE — plik ma wiersz `ZAL_`, samą ścieżkę w polu `FOTO`,
     czy nie ma nic. Podaj `--gpkg` (można kilka razy).

NICZEGO NIE ZMIENIA. Czyta pliki, liczy sumy, wypisuje.

SUMY KONTROLNE — dlaczego dwustopniowo
--------------------------------------
Policzenie md5 z 88 GB to kilkadziesiąt minut. A duplikat MUSI mieć ten sam
rozmiar, więc:

  1. grupujemy po rozmiarze — pliki samotne w swojej grupie odpadają za darmo,
  2. w grupach po kilka liczymy md5 z **pierwszych 64 kB**,
  3. dopiero to, co nadal się zgadza, dostaje pełne md5.

Na typowym zbiorze zdjęć pełne md5 liczy się dla ułamka plików.
`--sumy wszedzie` wymusza pełne dla wszystkich; `--sumy nigdy` pomija
wykrywanie duplikatów.

    python3 spis_zdjec.py ~/WorkField_zwroty
    python3 spis_zdjec.py ~/WorkField_zwroty ~/Pobrane ~/DCIM --duplikaty dupy.csv
    python3 spis_zdjec.py ~/WorkField_zwroty --gpkg ZWROT/dane.gpkg --wyjscie spis.tsv
    python3 spis_zdjec.py ~/Zdjecia --exif        # GPS / kąty / tagi, wolniejsze

Wyjście `--wyjscie` to **posortowany TSV** — ten sam pomysł co w `SpisPlikow`:
format, na którym `git diff` działa za darmo.
"""

import argparse
import csv
import datetime as dt
import hashlib
import os
import re
import sqlite3
import sys
from collections import defaultdict, Counter

# Zdjęcie z aparatu kontra „obraz w ogóle". Rozdzielone, bo pierwszy przelot
# 31.08 na prawdziwych katalogach wciągnął 25 ortofotomap .tif (3,0 GB — więcej
# niż wszystkie zdjęcia terenowe razem), zrzuty ekranu .png i obrazki z Gemini.
# To nie są zdjęcia płatów i nie ma po co ich liczyć razem.
ROZSZ_ZDJECIA = {".jpg", ".jpeg", ".heic", ".heif", ".dng", ".cr2", ".nef"}
ROZSZ_INNE_OBRAZY = {".png", ".tif", ".tiff", ".webp", ".bmp", ".gif"}

# Trzy konwencje nazw naraz — bo w danych są trzy.
#   WorkField / ZALACZNIKI_model.md:  platy_37_20260815_120130_045.jpg
STEMPEL = re.compile(r"^(?P<trzon>.+?)_(?P<d>\d{8})_(?P<g>\d{6})(?:_(?P<ms>\d{1,4}))?$")
#   Mapit Spatial:                    186_2026-07-13 12-08-00.jpg
#   (klucz + spacja + myślniki; warstwa siedzi w katalogu, nie w nazwie)
MAPIT = re.compile(r"^(?P<klucz>\d+)_(?P<d>\d{4}-\d{2}-\d{2})[ _T]"
                   r"(?P<g>\d{2}-\d{2}-\d{2})")
#   aparat Androida:                  20260713_114626.jpg
APARAT = re.compile(r"^(?:IMG[-_])?(?P<d>\d{8})[-_](?P<g>\d{6})")
KLUCZ_NA_KONCU = re.compile(r"^(?P<warstwa>.+)_(?P<klucz>\d+)$")
TYLKO_KLUCZ = re.compile(r"^\d+$")
CZESC = 65536


def ludzko(b):
    for j, x in ((1 << 40, "TB"), (1 << 30, "GB"), (1 << 20, "MB"), (1 << 10, "kB")):
        if b >= j:
            return "%.1f %s" % (b / float(j), x)
    return "%d B" % b


def md5_pliku(sciezka, tylko_poczatek=False):
    h = hashlib.md5()
    try:
        with open(sciezka, "rb") as f:
            if tylko_poczatek:
                h.update(f.read(CZESC))
            else:
                for kawalek in iter(lambda: f.read(1 << 20), b""):
                    h.update(kawalek)
    except OSError as e:
        return "BLAD:%s" % e.errno
    return h.hexdigest()


def rozbierz_sciezke(pelna):
    """Zwraca (warstwa, klucz, czas, konwencja).

    Bierze pod uwagę KATALOGI, nie tylko nazwę pliku — bo Mapit trzyma warstwę
    i klucz w ścieżce:
        Attachments/<projekt>/<warstwa>/<klucz>/<klucz>_2026-07-13 12-08-00.jpg
    a WorkField w nazwie:
        DCIM/platy_37/platy_37_20260815_120130_045.jpg
    """
    baza = os.path.splitext(os.path.basename(pelna))[0]
    czesci = os.path.dirname(pelna).split(os.sep)
    rodzic = czesci[-1] if czesci else ""
    dziadek = czesci[-2] if len(czesci) > 1 else ""

    # 1. WorkField: klucz i warstwa w nazwie pliku
    m = STEMPEL.match(baza)
    if m:
        try:
            czas = dt.datetime.strptime(m.group("d") + m.group("g"), "%Y%m%d%H%M%S")
        except ValueError:
            czas = None
        k = KLUCZ_NA_KONCU.match(m.group("trzon"))
        if k:
            return k.group("warstwa"), k.group("klucz"), czas, "WorkField"
        # płaska nazwa awaryjna z paska — rodzica nie niesie
        return m.group("trzon"), None, czas, "płaska"

    # 2. Mapit Spatial: klucz w nazwie, warstwa w katalogu dziadka
    m = MAPIT.match(baza)
    if m:
        try:
            czas = dt.datetime.strptime(m.group("d") + " " + m.group("g"),
                                        "%Y-%m-%d %H-%M-%S")
        except ValueError:
            czas = None
        warstwa = dziadek if TYLKO_KLUCZ.match(rodzic or "") else rodzic
        return (warstwa or None), m.group("klucz"), czas, "Mapit"

    # 3. surowa nazwa z aparatu: 20260713_114626.jpg — czas jest, rodzica nie ma
    m = APARAT.match(baza)
    if m:
        try:
            czas = dt.datetime.strptime(m.group("d") + m.group("g"), "%Y%m%d%H%M%S")
        except ValueError:
            czas = None
        # katalog `<klucz>` nad plikiem i tak wskazuje rodzica
        if TYLKO_KLUCZ.match(rodzic or ""):
            return (dziadek or None), rodzic, czas, "Mapit (katalog)"
        return None, None, czas, "aparat"

    # 4. sam katalog może nieść klucz, choć nazwa pliku nie
    if TYLKO_KLUCZ.match(rodzic or ""):
        return (dziadek or None), rodzic, None, "Mapit (katalog)"
    return None, None, None, "spoza konwencji"


def znormalizuj(s):
    return os.path.normpath(str(s).strip().replace("\\", "/")).lower()


# ───────────────────────────── obchód ────────────────────────────────────────

class Plik(object):
    __slots__ = ("sciezka", "korzen", "wzgl", "rozmiar", "mtime",
                 "warstwa", "klucz", "czas", "konwencja", "md5", "w_bazie")

    def __init__(self, sciezka, korzen, st):
        self.sciezka = sciezka
        self.korzen = korzen
        self.wzgl = os.path.relpath(sciezka, korzen)
        self.rozmiar = st.st_size
        self.mtime = st.st_mtime
        (self.warstwa, self.klucz,
         self.czas, self.konwencja) = rozbierz_sciezke(sciezka)
        self.md5 = ""
        self.w_bazie = ""


def obejdz(korzenie, pomijaj, wszystkie_obrazy):
    szukane = set(ROZSZ_ZDJECIA)
    if wszystkie_obrazy:
        szukane |= ROZSZ_INNE_OBRAZY
    pliki, pominiete, inne_obrazy, niedostepne = [], Counter(), Counter(), []
    for korzen in korzenie:
        korzen = os.path.abspath(os.path.expanduser(korzen))
        if not os.path.isdir(korzen):
            print("! nie ma katalogu: %s" % korzen, file=sys.stderr)
            continue
        for katalog, podkatalogi, nazwy in os.walk(korzen, onerror=niedostepne.append):
            podkatalogi[:] = [d for d in podkatalogi
                              if not any(w in d for w in pomijaj)]
            for n in nazwy:
                r = os.path.splitext(n)[1].lower()
                if r not in szukane:
                    if r in ROZSZ_INNE_OBRAZY:
                        inne_obrazy[r] += 1
                    elif r:
                        pominiete[r] += 1
                    continue
                p = os.path.join(katalog, n)
                try:
                    st = os.stat(p)
                except OSError:
                    niedostepne.append(p)
                    continue
                if not os.path.isfile(p):
                    continue
                pliki.append(Plik(p, korzen, st))
    return pliki, pominiete, inne_obrazy, niedostepne


# ───────────────────────────── duplikaty ─────────────────────────────────────

def znajdz_duplikaty(pliki, tryb):
    """Dwustopniowo: rozmiar -> md5 z początku -> pełne md5."""
    if tryb == "nigdy":
        return {}, (0, 0)
    if tryb == "wszedzie":
        for p in pliki:
            p.md5 = md5_pliku(p.sciezka)
        wg = defaultdict(list)
        for p in pliki:
            wg[p.md5].append(p)
        return {k: v for k, v in wg.items() if len(v) > 1}, (0, len(pliki))

    wg_rozmiaru = defaultdict(list)
    for p in pliki:
        wg_rozmiaru[p.rozmiar].append(p)
    kandydaci = [g for g in wg_rozmiaru.values() if len(g) > 1]

    czesciowe = 0
    wg_poczatku = defaultdict(list)
    for grupa in kandydaci:
        for p in grupa:
            wg_poczatku[(p.rozmiar, md5_pliku(p.sciezka, True))].append(p)
            czesciowe += 1

    pelne = 0
    wynik = defaultdict(list)
    for grupa in wg_poczatku.values():
        if len(grupa) < 2:
            continue
        for p in grupa:
            p.md5 = md5_pliku(p.sciezka)
            pelne += 1
            wynik[p.md5].append(p)
    return {k: v for k, v in wynik.items() if len(v) > 1}, (czesciowe, pelne)


# ───────────────────────────── zestawienie z bazami ──────────────────────────

def znajdz_bazy(korzenie, pomijaj):
    """Wszystkie .gpkg pod podanymi katalogami. W katalogu zlecenia żyją
    osobne bazy obok `dane.gpkg` — `tyczenie.gpkg`, `foto_tagi.gpkg`,
    „Korekty płatów.gpkg" (DANE_obieg.md, punkt 10). Zdjęcie może mieć wiersz
    w każdej z nich, więc wskazywanie ich po jednej gubi część rekordów."""
    znalezione = []
    for korzen in korzenie:
        korzen = os.path.abspath(os.path.expanduser(korzen))
        for katalog, podkatalogi, nazwy in os.walk(korzen, onerror=lambda e: None):
            podkatalogi[:] = [d for d in podkatalogi
                              if not any(w in d for w in pomijaj)]
            for n in nazwy:
                if n.lower().endswith(".gpkg"):
                    znalezione.append(os.path.join(katalog, n))
    return sorted(set(znalezione))


ANDROID_URI = re.compile(r"^(content://|/tree/|/document/)|primary:")


def rozbierz_odwolanie(wartosc, korzen_bazy):
    """Zwraca (rodzaj, sciezka_do_sprawdzenia, nazwa_pliku).

    `rodzaj` to `dysk` albo `android`. Mapit zapisuje w `mapit_media_table`
    URI Androidowego SAF-a, nie ścieżkę:

        /tree/primary:Mapit-Spatial/Mapit-Data/document/primary:.../Attachments/
        APPL ZZW PTR 2026/ZZW_PTR_Toposektory_ziel_2178/186/186_2026-07-13 12-08-00.jpg

    Sprawdzanie tego przez `os.path.exists` jest bez sensu — taka ścieżka
    NIGDY nie istnieje na komputerze, więc każdy taki wiersz zgłaszałby się
    jako strata. To jest dokładnie ten fałszywy alarm, przed którym ostrzega
    handoff z 25.08: narzędzie, które straszy bez powodu, uczy ignorować
    także prawdziwe ostrzeżenia.
    """
    s = str(wartosc).strip()
    nazwa = os.path.basename(s.replace("\\", "/"))
    if ANDROID_URI.search(s):
        return "android", None, nazwa
    pelna = s if os.path.isabs(s) else os.path.join(korzen_bazy, s)
    return "dysk", os.path.abspath(pelna), nazwa


def z_baz(sciezki_gpkg):
    """Zbiera WSZYSTKIE odwołania do plików obrazów z podanych baz.

    Zwraca listę (baza, tabela, kolumna, rodzaj, sciezka, nazwa) — rozstrzyganie,
    co z nich wynika, dzieje się później, gdy znamy już zawartość dysku."""
    odwolania = []
    otwarte = []
    for g in sciezki_gpkg:
        if not os.path.exists(g):
            print("! nie ma bazy: %s" % g, file=sys.stderr)
            continue
        # Baza z dziennikiem obok pokazuje stan SPRZED ostatnich zapisów —
        # a my właśnie liczymy, czego brakuje. Punkt 3 z DANE_obieg.md.
        if os.path.exists(g + "-wal"):
            otwarte.append(g)
        korzen = os.path.dirname(os.path.abspath(g))
        con = sqlite3.connect("file:%s?mode=ro" % g, uri=True)
        tabele = [t for (t,) in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'gpkg_%' AND name NOT LIKE 'rtree_%' "
            "AND name NOT LIKE 'sqlite_%'")]
        for t in tabele:
            kol = [n for _, n, typ, _, _, _ in con.execute('PRAGMA table_info("%s")' % t)
                   if (typ or "").upper() not in ("BLOB", "INTEGER", "REAL")]
            for k in kol:
                try:
                    wartosci = [w for (w,) in con.execute(
                        'SELECT "%s" FROM "%s" WHERE "%s" IS NOT NULL AND "%s" <> \'\''
                        % (k, t, k, k)) if isinstance(w, str)]
                except sqlite3.Error:
                    continue
                wszystkie_rozsz = ROZSZ_ZDJECIA | ROZSZ_INNE_OBRAZY
                trafienia = [w for w in wartosci
                             if os.path.splitext(w)[1].lower() in wszystkie_rozsz]
                if not trafienia or len(trafienia) < max(1, len(wartosci) // 2):
                    continue
                znacznik = "ZAL" if t.upper().startswith("ZAL_") else "pole"
                for w in trafienia:
                    rodzaj, pelna, nazwa = rozbierz_odwolanie(w, korzen)
                    odwolania.append((os.path.basename(g), t, k, znacznik,
                                      rodzaj, pelna, nazwa, w.strip()))
        con.close()
    return odwolania, otwarte


def zestaw_odwolania(odwolania, pliki):
    """Rozstrzyga, co z odwołań wynika — dopiero tu, bo dopiero tu znamy dysk.

    Ważne: 70 baz to w większości WERSJE tego samego zlecenia
    (`APPL ZZW PTR 2026-07-13.gpkg`, `…13a.gpkg`, `…13a-1.gpkg`, `…17.gpkg`),
    więc liczba WIERSZY nic nie mówi. Liczy się liczba RÓŻNYCH PLIKÓW."""
    wg_sciezki = {znormalizuj(p.sciezka): p for p in pliki}
    wg_nazwy = defaultdict(list)
    for p in pliki:
        wg_nazwy[os.path.basename(p.sciezka).lower()].append(p)

    zajete = {}
    stan_pliku = {}          # nazwa -> 'jest' / 'brak'
    wg_bazy = defaultdict(lambda: Counter())
    for baza, t, k, znacznik, rodzaj, pelna, nazwa, surowa in odwolania:
        wg_bazy[baza]["wierszy"] += 1
        trafiony = None
        if pelna and znormalizuj(pelna) in wg_sciezki:
            trafiony = wg_sciezki[znormalizuj(pelna)]
            zajete[znormalizuj(pelna)] = znacznik
        elif nazwa.lower() in wg_nazwy:
            trafiony = wg_nazwy[nazwa.lower()][0]
            for p in wg_nazwy[nazwa.lower()]:
                zajete.setdefault(znormalizuj(p.sciezka), znacznik + "?")
        stan_pliku[nazwa.lower()] = "jest" if trafiony else "brak"
        wg_bazy[baza]["android" if rodzaj == "android" else "dysk"] += 1
        if trafiony:
            wg_bazy[baza]["trafione"] += 1

    rozne = len(stan_pliku)
    brakujace = sorted(n for n, s in stan_pliku.items() if s == "brak")
    androidowe = {n for _, _, _, _, r, _, n, _ in odwolania if r == "android"}
    return zajete, {
        "wierszy": len(odwolania),
        "roznych_plikow": rozne,
        "brakujacych": brakujace,
        "androidowych_nazw": len(androidowe),
        "wg_bazy": wg_bazy,
        "przyklady_brakow": [(b, t, k, s) for b, t, k, _, _, _, n, s in odwolania
                             if stan_pliku.get(n.lower()) == "brak"][:400],
    }


# ───────────────────────────── raport ────────────────────────────────────────

def wypisz(pliki, pominiete, inne_obrazy, niedostepne, duplikaty, policzone,
           braki, otwarte, a):
    if not pliki:
        print("Nie znalazłem ani jednego zdjęcia.")
        return

    razem = sum(p.rozmiar for p in pliki)
    print("=" * 72)
    print("ZDJĘĆ: %d,  RAZEM %s" % (len(pliki), ludzko(razem)))
    print("=" * 72)
    print()

    print("--- 1. GDZIE ---")
    wg_kat = defaultdict(lambda: [0, 0])
    for p in pliki:
        k = os.path.dirname(p.sciezka)
        wg_kat[k][0] += 1
        wg_kat[k][1] += p.rozmiar
    print("  katalogów ze zdjęciami: %d" % len(wg_kat))
    posortowane = sorted(wg_kat.items(), key=lambda x: -x[1][0])
    for k, (n, b) in posortowane[:a.limit]:
        print("  %7d  %10s  %s" % (n, ludzko(b), k))
    if len(posortowane) > a.limit:
        reszta = sum(n for _, (n, _) in posortowane[a.limit:])
        print("  %7d  %10s  ... (%d dalszych katalogów)"
              % (reszta, "", len(posortowane) - a.limit))
    print()
    rozsz = Counter(os.path.splitext(p.sciezka)[1].lower() for p in pliki)
    print("  rozszerzenia: %s"
          % ", ".join("%s %d" % (r, n) for r, n in rozsz.most_common()))
    if inne_obrazy:
        print("  POMINIĘTE OBRAZY (nie zdjęcia z aparatu): %s"
              % ", ".join("%s %d" % (r, n) for r, n in inne_obrazy.most_common()))
        print("    Ortofotomapy, zrzuty ekranu, wydruki map. Żeby je policzyć:")
        print("    --wszystkie-obrazy")
    if pominiete:
        print("  pominięte (nie obraz): %s"
              % ", ".join("%s %d" % (r, n) for r, n in pominiete.most_common(8)))
    if niedostepne:
        print("  NIEDOSTĘPNE: %d — prawa dostępu albo znikające dowiązania"
              % len(niedostepne))
        for x in niedostepne[:5]:
            print("     %s" % x)
    print()

    print("--- 2. TEN SAM PLIK W KILKU MIEJSCACH ---")
    czesciowe, pelne = policzone
    koszt = ("md5 z pierwszych 64 kB: %d plików, pełne md5: %d z %d"
             % (czesciowe, pelne, len(pliki)))
    if a.sumy == "nigdy":
        print("  pominięte (--sumy nigdy)")
    elif not duplikaty:
        print("  brak duplikatów  (%s)" % koszt)
    else:
        kopie = sum(len(g) - 1 for g in duplikaty.values())
        zmarnowane = sum((len(g) - 1) * g[0].rozmiar for g in duplikaty.values())
        print("  grup: %d,  zbędnych kopii: %d,  zajmują: %s"
              % (len(duplikaty), kopie, ludzko(zmarnowane)))
        print("  (%s)" % koszt)
        print()
        najwieksze = sorted(duplikaty.values(),
                            key=lambda g: -(len(g) - 1) * g[0].rozmiar)
        for g in najwieksze[:a.limit]:
            print("  %d x %s  (%s)" % (len(g), os.path.basename(g[0].sciezka),
                                       ludzko(g[0].rozmiar)))
            for p in g[:4]:
                print("        %s" % p.sciezka)
            if len(g) > 4:
                print("        ... (%d razem)" % len(g))
        if len(najwieksze) > a.limit:
            print("  ... (%d dalszych grup)" % (len(najwieksze) - a.limit))
        print()
        print("  UWAGA: duplikat NIE ZNACZY „do skasowania\". Kopia zwrotu")
        print("  z 21.08 i kopia z 24.08 to dwa punkty cofnięcia, nie odpad.")
        print("  Ta liczba mówi, ile miejsca zajmuje powtórzenie — nic więcej.")
    print()

    print("--- 3. DWA POZIOMY O TEJ SAMEJ NAZWIE ---")
    # Liczone WZGLĘDEM korzenia i tylko dla poziomów SĄSIEDNICH. Pierwszy
    # przelot 31.08 zgłosił `/DATA/APPL/ZZW_Parki_2026/DATA` — bo katalog
    # główny nazywa się `/DATA`, a podkatalog też `DATA`. To nie jest ślad po
    # przerwanym kopiowaniu, tylko zbieżność nazw. Fałszywy alarm usunięty.
    podejrzane = set()
    for p in pliki:
        czesci = os.path.relpath(p.sciezka, p.korzen).split(os.sep)[:-1]
        for i in range(len(czesci) - 1):
            if czesci[i] and czesci[i] == czesci[i + 1]:
                podejrzane.add(os.path.join(p.korzen, *czesci[:i + 2]))
    if not podejrzane:
        print("  nie ma (sprawdzane tylko poziomy sąsiednie, względem korzenia)")
    else:
        print("  %d ścieżek, w których nazwa katalogu się powtarza:" % len(podejrzane))
        for s in sorted(podejrzane)[:a.limit]:
            print("     %s" % s)
        print("  To zwykle ślad po przerwanym `adb pull` (punkt 4 DANE_obieg.md):")
        print("  `adb pull KATALOG CEL/` robi podkatalog o nazwie źródła, a potem")
        print("  dociąganie pojedynczych plików kładzie je poziom wyżej.")
    print()

    print("--- 4. CO NIESIE NAZWA ---")
    wg_konw = Counter(p.konwencja for p in pliki)
    opis = {
        "WorkField": "platy_37_20260815_… — klucz w nazwie",
        "Mapit": "186_2026-07-13 12-08-00 — klucz w nazwie, warstwa w katalogu",
        "Mapit (katalog)": "klucz z katalogu nad plikiem",
        "płaska": "nazwa awaryjna z paska — rodzica NIE niesie",
        "aparat": "20260713_114626 — sam czas, rodzica NIE niesie",
        "spoza konwencji": "ani klucza, ani czasu",
    }
    for k, n in wg_konw.most_common():
        gwiazdka = " <- da się przypiąć do rodzica" if k.startswith(
            ("WorkField", "Mapit")) else ""
        print("  %-17s %6d  %s%s" % (k, n, opis.get(k, ""), gwiazdka))
    z_kluczem = [p for p in pliki if p.klucz]
    print()
    print("  RAZEM Z KLUCZEM RODZICA: %d z %d (%.0f %%)"
          % (len(z_kluczem), len(pliki), 100.0 * len(z_kluczem) / len(pliki)))
    if z_kluczem:
        warstwy = Counter(p.warstwa for p in z_kluczem)
        print("  warstwy: %s"
              % ", ".join("%s %d" % (w, n) for w, n in warstwy.most_common(10)))
    poza = [p for p in pliki if p.konwencja == "spoza konwencji"]
    if poza:
        print("  przykłady spoza konwencji:")
        for p in poza[:5]:
            print("     %s" % os.path.basename(p.sciezka))
    print()

    print("--- 5. KIEDY ---")
    wg_dnia = Counter()
    ze_stempla = 0
    for p in pliki:
        if p.czas:
            wg_dnia[p.czas.date()] += 1
            ze_stempla += 1
        else:
            wg_dnia[dt.date.fromtimestamp(p.mtime)] += 1
    print("  dat ze stempla w nazwie: %d, z czasu pliku: %d"
          % (ze_stempla, len(pliki) - ze_stempla))
    print("  (czas pliku nie jest dowodem na nic — `shutil.copy2` zachowuje czas")
    print("   oryginału, a `QFile::copy` go gubił. Rozstrzyga stempel w nazwie.)")
    dni = sorted(wg_dnia.items())
    if dni:
        print("  zakres: %s … %s   (%d dni z pracą)"
              % (dni[0][0], dni[-1][0], len(dni)))
        szczyt = max(wg_dnia.values())
        for d, n in dni[-a.limit:]:
            print("    %s  %5d  %s" % (d, n, "█" * max(1, int(40.0 * n / szczyt))))
    print()

    if a.gpkg:
        print("--- 6. CZY JEST W BAZIE ---")
        print("  baz przeszukanych: %d" % len(a.gpkg))
        if otwarte:
            print()
            n = len(otwarte)
            odmiana = ("BAZA MA" if n == 1 else
                       "BAZY MAJĄ" if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14
                       else "BAZ MA")
            print("  ! %d %s OBOK DZIENNIK `-wal`:" % (n, odmiana))
            for g in otwarte[:6]:
                print("      %s" % g)
            print("    Czytam wtedy stan SPRZED ostatnich zapisów, więc liczby")
            print("    poniżej są ZANIŻONE — zdjęcie może mieć wiersz, którego")
            print("    jeszcze nie widzę. Zamknij QGIS-a albo zrób checkpoint")
            print("    (DANE_obieg.md, punkt 3) i powtórz.")
        print()
        licz = Counter(p.w_bazie or "NIC" for p in pliki)
        for stan, n in licz.most_common():
            etykieta = {"ZAL": "ma wiersz ZAL_",
                        "ZAL?": "ta sama NAZWA w ZAL_, inna ścieżka",
                        "pole": "tylko w polu tekstowym",
                        "pole?": "ta sama NAZWA w polu, inna ścieżka",
                        "NIC": "NIE MA NIGDZIE W BAZIE"}.get(stan, stan)
            print("  %-38s %6d" % (etykieta, n))
        bez = [p for p in pliki if not p.w_bazie]
        if bez:
            print()
            print("  %.0f %% zdjęć nie ma żadnego rekordu."
                  % (100.0 * len(bez) / len(pliki)))
            for p in bez[:5]:
                print("     %s" % p.sciezka)

        if braki:
            print()
            print("  W DRUGĄ STRONĘ — CO BAZY MÓWIĄ, ŻE MAJĄ")
            print("    wierszy z odwołaniem do obrazu ......... %6d" % braki["wierszy"])
            print("    RÓŻNYCH plików, na które wskazują ...... %6d"
                  % braki["roznych_plikow"])
            print("    z tego nie ma na dysku ................. %6d"
                  % len(braki["brakujacych"]))
            print()
            print("    Liczba wierszy jest myląca: %d baz to w dużej części WERSJE"
                  % len(a.gpkg))
            print("    tego samego zlecenia, więc ten sam plik liczy się wiele razy.")
            print("    Rozstrzyga druga liczba, nie pierwsza.")
            if braki["androidowych_nazw"]:
                print()
                print("    %d nazw pochodzi z URI Androida (`/tree/primary:…`),"
                      % braki["androidowych_nazw"])
                print("    zapisanych przez Mapit w `mapit_media_table`. To NIE SĄ")
                print("    ścieżki na tym komputerze i nigdy nie będą — sprawdzam je")
                print("    po samej nazwie pliku. Brak takiego pliku znaczy, że nie")
                print("    ściągnięto go z telefonu, a nie że przepadł.")
            if braki["brakujacych"]:
                print()
                print("    przykłady brakujących nazw:")
                for n in braki["brakujacych"][:a.limit]:
                    print("      %s" % n)
            print()
            print("    Rozkład na bazy (wierszy / trafionych na dysku):")
            for b, c in sorted(braki["wg_bazy"].items(),
                               key=lambda x: -x[1]["wierszy"])[:a.limit]:
                print("      %-46s %6d / %d" % (b[:46], c["wierszy"], c["trafione"]))
        print()

    print("=" * 72)
    print("Nic nie zostało zmienione. To jest rozeznanie, nie porządki.")


# ───────────────────────────── main ──────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("korzenie", nargs="+", help="katalogi do przeszukania w głąb")
    ap.add_argument("--sumy", choices=["nigdy", "kandydaci", "wszedzie"],
                    default="kandydaci")
    ap.add_argument("--wszystkie-obrazy", dest="wszystkie_obrazy",
                    action="store_true",
                    help="licz też .png/.tif — ortofotomapy, zrzuty ekranu, "
                         "wydruki map (domyślnie tylko zdjęcia z aparatu)")
    ap.add_argument("--gpkg", action="append", default=[],
                    help="baza do zestawienia (można podać kilka razy)")
    ap.add_argument("--gpkg-szukaj", dest="gpkg_szukaj", action="store_true",
                    help="znajdź wszystkie .gpkg pod podanymi katalogami "
                         "i zestaw ze wszystkimi naraz")
    ap.add_argument("--wyjscie", metavar="TSV", help="posortowany spis do pliku")
    ap.add_argument("--duplikaty", metavar="CSV", help="grupy duplikatów do pliku")
    ap.add_argument("--pomijaj", action="append",
                    default=[".git", ".thumbnails", ".trash", "__pycache__"],
                    help="fragment nazwy katalogu do pominięcia")
    ap.add_argument("--limit", type=int, default=12)
    a = ap.parse_args()

    print("szukam w:")
    for k in a.korzenie:
        print("   %s" % os.path.abspath(os.path.expanduser(k)))
    print()

    pliki, pominiete, inne_obrazy, niedostepne = obejdz(
        a.korzenie, a.pomijaj, a.wszystkie_obrazy)
    if not pliki:
        print("Nie znalazłem ani jednego zdjęcia.", file=sys.stderr)
        return 1

    if a.sumy != "nigdy":
        print("liczę sumy kontrolne (%s)..." % a.sumy, file=sys.stderr)
    duplikaty, policzone = znajdz_duplikaty(pliki, a.sumy)

    braki, otwarte = None, []
    if a.gpkg_szukaj:
        znalezione = znajdz_bazy(a.korzenie, a.pomijaj)
        nowe = [g for g in znalezione if os.path.abspath(g) not in
                {os.path.abspath(x) for x in a.gpkg}]
        if nowe:
            print("znalezione bazy (%d):" % len(nowe), file=sys.stderr)
            for g in nowe:
                print("   %s" % g, file=sys.stderr)
        a.gpkg = list(a.gpkg) + nowe
    if a.gpkg:
        print("czytam %d baz..." % len(a.gpkg), file=sys.stderr)
        odwolania, otwarte = z_baz(a.gpkg)
        zajete, braki = zestaw_odwolania(odwolania, pliki)
        for p in pliki:
            p.w_bazie = zajete.get(znormalizuj(p.sciezka), "")

    wypisz(pliki, pominiete, inne_obrazy, niedostepne, duplikaty, policzone,
           braki, otwarte, a)

    if a.wyjscie:
        # posortowany TSV — ten sam pomysł co w SpisPlikow: format, na którym
        # `git diff` działa za darmo. Sortowanie NIE jest kosmetyką: obchód
        # katalogów nie ma ustalonej kolejności.
        with open(a.wyjscie, "w", encoding="utf-8", newline="\n") as f:
            f.write("# spis zdjęć %s\n" % dt.datetime.now().strftime("%Y-%m-%d %H:%M"))
            f.write("# korzenie: %s\n" % " | ".join(
                os.path.abspath(os.path.expanduser(k)) for k in a.korzenie))
            f.write("# plików: %d, razem: %s\n"
                    % (len(pliki), ludzko(sum(p.rozmiar for p in pliki))))
            f.write("# sciezka\trozmiar\tmtime\tmd5\tkonwencja\twarstwa\tklucz"
                    "\tczas\tw_bazie\n")
            for p in sorted(pliki, key=lambda x: x.sciezka):
                f.write("%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % (
                    p.sciezka, p.rozmiar,
                    dt.datetime.fromtimestamp(p.mtime).strftime("%Y-%m-%d %H:%M:%S"),
                    p.md5, p.konwencja, p.warstwa or "", p.klucz or "",
                    p.czas.strftime("%Y-%m-%d %H:%M:%S") if p.czas else "",
                    p.w_bazie))
        print("\nSpis: %s" % a.wyjscie)
        print("`git init` w katalogu spisów i `git diff` pokaże zmianę między dniami.")

    if a.duplikaty and duplikaty:
        with open(a.duplikaty, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["GRUPA", "MD5", "ROZMIAR", "SCIEZKA", "MTIME"])
            for i, (suma, grupa) in enumerate(sorted(
                    duplikaty.items(), key=lambda x: -x[1][0].rozmiar), 1):
                for p in sorted(grupa, key=lambda x: x.sciezka):
                    w.writerow([i, suma, p.rozmiar, p.sciezka,
                                dt.datetime.fromtimestamp(p.mtime)
                                .strftime("%Y-%m-%d %H:%M:%S")])
        print("Duplikaty: %s" % a.duplikaty)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
