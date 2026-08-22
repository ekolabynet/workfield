# -*- coding: utf-8 -*-
"""
zbuduj_taksony.py — buduje słownik taksonów w GeoPackage szablonu.

Bez QGIS-a, bez GDAL-a, bez `pip install`. Sam sqlite3 + biblioteka standardowa.
Obok musi leżeć `taksony_normalizacja.py` i plik warstwy prawnej
`prawo_gatunki_RRRR-MM-DD.csv` (brany jest NAJNOWSZY, chyba że wskażesz inny).

    # 1. sucha próba — nic nie zapisuje, pokazuje co by wyszło
    python3 zbuduj_taksony.py --zrodlo slownik.csv --kolumna GATUNEK --sucho

    # 2. z importem istniejących skrótów z Gboarda
    python3 zbuduj_taksony.py --zrodlo slownik.csv --kolumna GATUNEK \
        --skroty gboard_slownik.csv --sucho

    # 3. zapis do szablonu (kopia zapasowa robi się sama)
    python3 zbuduj_taksony.py --zrodlo slownik.csv --kolumna GATUNEK \
        --gpkg /DATA/WorkField/szablony/szablon_inw_zzw/dane.gpkg

    # 4. dopasowanie do kręgosłupa przez sieć (biuro, nie teren)
    python3 zbuduj_taksony.py ... --gbif --mail twoj@adres.pl

    # 5. eksport słownika skrótów dla Gboarda z gotowej tabeli
    python3 zbuduj_taksony.py --gpkg dane.gpkg --gboard gboard.csv

Trzy tabele na wyjściu:
  TAKSONY       — słownik: tożsamość + prawo, jedno źródło prawdy
  TAKSONY_XREF  — klucze obce (GBIF, COL, iNat, NCBI…) z wersją i datą
  WF_ZRODLA     — CO i W JAKIEJ WERSJI zbudowało tę bazę

Zasady wpisane w kod:
  * oryginał nietknięty — kopia zapasowa przed każdym zapisem,
  * surowa nazwa z terenu zostaje w NAZWA_ZRODLOWA na zawsze,
  * kultywar NIGDY nie idzie do dopasowania — jedzie osobną kolumną,
  * kluczem jest PARA (GATUNEK, KROLESTWO) — Iris to i kosaciec, i modliszka,
  * klucz obcy nie jest kluczem głównym — ma wersję i datę, bo wygasa,
  * nic nie ginie po cichu: każdy wiersz niesie DOPASOWANIE i DECYZJA.
"""

import argparse
import csv
import glob
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from taksony_normalizacja import rozbierz, do_wyswietlenia  # noqa: E402

KATALOG = os.path.dirname(os.path.abspath(__file__))
WERSJA_SKRYPTU = "2026-08-22"
TABELA = "TAKSONY"
TABELA_XREF = "TAKSONY_XREF"
TABELA_ZRODLA = "WF_ZRODLA"

KOLUMNY = [
    ("FID", "INTEGER PRIMARY KEY AUTOINCREMENT"),
    ("NAZWA", "TEXT"),              # do wyświetlenia: Tilia cordata 'Greenspire'
    ("GATUNEK", "TEXT"),            # kanoniczna łacina — klucz łączenia
    ("KROLESTWO", "TEXT"),          # druga połowa klucza (homonimy!)
    ("ODMIANA", "TEXT"),            # epitet kultywaru, dosłownie, bez fuzzy
    ("NAZWA_PL", "TEXT"),
    ("SKROT", "TEXT"),              # kod dla paska podpowiedzi i Gboarda
    ("SKROT_ZRODLO", "TEXT"),       # gboard (Twój, używany) / auto (wygenerowany)
    ("RODZAJ", "TEXT"),
    ("RANGA", "TEXT"),              # SPECIES / GENUS / SUBSPECIES / CULTIVAR
    ("HYBRYDA", "INTEGER"),
    ("KWALIFIKATOR", "TEXT"),       # cf / aff
    ("NAZWA_ZRODLOWA", "TEXT"),     # dosłownie to, co było w źródle
    ("STATUS", "TEXT"),             # ACCEPTED / SYNONYM
    ("AKCEPTOWANA", "TEXT"),        # nazwa przyjęta, gdy wpis jest synonimem
    ("RODZINA", "TEXT"),
    ("DOPASOWANIE", "TEXT"),        # EXACT / VARIANT / FUZZY / HIGHERRANK / NONE
    ("PEWNOSC", "INTEGER"),
    ("DECYZJA", "TEXT"),            # AUTO / AUTO_RODZAJ / PRZEGLAD / RECZNIE
    ("PROG_CM", "INTEGER"),         # art. 83f ust. 1 pkt 3 — obwód na 5 cm
    ("GRUPA_STAWKI", "INTEGER"),    # Dz.U. 2017 poz. 1330 zał. 1 (drzewa)
    ("GRUPA_KRZEWY", "INTEGER"),    # Dz.U. 2017 poz. 1330 zał. 2 (krzewy)
    ("POMNIK_CM", "INTEGER"),       # Dz.U. 2017 poz. 2300 — obwód na 130 cm
    ("ZWOLN_CM", "INTEGER"),        # art. 86 ust. 1 pkt 7
    ("OWOCOWE", "INTEGER"),         # art. 83f ust. 1 pkt 5
    ("IGO", "TEXT"),                # status PRAWNY, nie przyrodniczy
    ("OCHRONA", "TEXT"),            # scisla / czesciowa (Dz.U. 2014 poz. 1409)
    ("OCHRONA_CZYNNA", "INTEGER"),  # adnotacja (1) w rozporządzeniu
    ("ZRODLO_PRAWO", "TEXT"),
    ("WERSJA_PRAWA", "TEXT"),       # z nazwy pliku CSV — datowanie warstwy
    ("WERYFIKACJA", "TEXT"),        # puste = nikt tego nie sprawdził okiem
    ("AKTUALIZACJA", "TEXT"),
]

KOLUMNY_XREF = [
    ("FID", "INTEGER PRIMARY KEY AUTOINCREMENT"),
    ("GATUNEK", "TEXT"),
    ("KROLESTWO", "TEXT"),
    ("ZRODLO", "TEXT"),             # GBIF / COLXR / WFO / INAT / NCBI / GLOBI
    ("ID_OBCE", "TEXT"),
    ("WERSJA_ZRODLA", "TEXT"),
    ("TYP_DOPASOWANIA", "TEXT"),
    ("PEWNOSC", "INTEGER"),
    ("DATA", "TEXT"),
]

KOLUMNY_ZRODLA = [
    ("KLUCZ", "TEXT PRIMARY KEY"),
    ("WERSJA", "TEXT"),
    ("DATA", "TEXT"),
    ("LICENCJA", "TEXT"),
    ("UWAGA", "TEXT"),
]

PRAWO_KOLUMNY = ["PROG_5", "GRUPA_STAWKI", "GRUPA_KRZEWY", "POMNIK_130",
                 "ZWOLN_130", "OWOCOWE", "IGO", "OCHRONA", "ZRODLO"]
DOMYSLNE_PRAWO = {"PROG_5": 50, "GRUPA_STAWKI": 5, "GRUPA_KRZEWY": 2,
                  "POMNIK_130": None, "ZWOLN_130": 80, "OWOCOWE": None,
                  "IGO": None, "OCHRONA": None,
                  "ZRODLO": "domyślne (art. 83f pkt 3 lit. c, gr. 5 i 2)"}


# --------------------------------------------------------------- warstwa prawna
# warstwa prawna leży w katalogu obok skryptów (taxonomy/dane/prawo),
# ale skrypt ma działać też uruchomiony z dowolnego miejsca
SZUKAJ_PRAWA = [
    os.path.join(KATALOG, "..", "dane", "prawo"),
    os.path.join(KATALOG, "dane", "prawo"),
    KATALOG,
    os.getcwd(),
]


def najnowsze_prawo(wskazany=None):
    """Bierze NAJNOWSZY plik prawo_gatunki_RRRR-MM-DD.csv. Data w nazwie
    jest wersją warstwy i trafia do kolumny WERSJA_PRAWA."""
    if wskazany:
        return wskazany
    for katalog in SZUKAJ_PRAWA:
        pliki = sorted(glob.glob(os.path.join(katalog, "prawo_gatunki_*.csv")))
        if pliki:
            return pliki[-1]
    for katalog in SZUKAJ_PRAWA:
        domyslny = os.path.join(katalog, "prawo_gatunki.csv")
        if os.path.exists(domyslny):
            return domyslny
    return None


def wersja_prawa(sciezka):
    """Wersja = data z nazwy pliku. Prawo się zmienia — musi być datowane."""
    if not sciezka:
        return "brak"
    baza = os.path.basename(sciezka)
    trzon = os.path.splitext(baza)[0]
    return trzon.replace("prawo_gatunki_", "").replace("prawo_gatunki", "bez daty")


def wczytaj_prawo(sciezka):
    """Zwraca (po_gatunku, po_rodzaju). Puste komórki = dziedzicz wyżej."""
    po_gat, po_rodz = {}, {}
    if not sciezka or not os.path.exists(sciezka):
        return po_gat, po_rodz
    with open(sciezka, encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f, delimiter=";"):
            klucz = (r.get("NAZWA_LAT") or "").strip()
            if not klucz:
                continue
            wpis = {k: (r.get(k) or "").strip() or None for k in PRAWO_KOLUMNY}
            wpis["NAZWA_PL"] = (r.get("NAZWA_PL") or "").strip() or None
            wpis["WERYFIKACJA"] = (r.get("WERYFIKACJA") or "").strip() or None
            poziom = (r.get("POZIOM") or "").strip()
            (po_gat if poziom == "gatunek" else po_rodz)[klucz] = wpis
    return po_gat, po_rodz


def prawo_dla(kanoniczna, rodzaj, po_gat, po_rodz):
    """Rozstrzyganie kolumna po kolumnie: gatunek -> rodzaj -> domyślne.
    Ustawa mówi 'topoli, wierzb' — czyli rodzajami. Poziom rodzaju musi być
    pierwszą klasą, nie wyjątkiem."""
    wynik, zrodla = {}, []
    warstwy = [po_gat.get(kanoniczna), po_rodz.get(rodzaj)]
    for kol in PRAWO_KOLUMNY:
        wartosc = None
        for w in warstwy:
            if w and w.get(kol):
                wartosc = w[kol]
                break
        wynik[kol] = wartosc if wartosc is not None else DOMYSLNE_PRAWO[kol]
    for w in warstwy:
        if w and w.get("ZRODLO"):
            zrodla.append(w["ZRODLO"])
    wynik["ZRODLO"] = " + ".join(dict.fromkeys(zrodla)) or DOMYSLNE_PRAWO["ZRODLO"]
    # nazwa polska WYŁĄCZNIE z poziomu gatunku: progi wolno dziedziczyć
    # po rodzaju ("topoli, wierzb"), ale Abies concolor nie nazywa się "jodła"
    wynik["NAZWA_PL"] = (po_gat.get(kanoniczna) or {}).get("NAZWA_PL")
    wynik["WERYFIKACJA"] = next((w["WERYFIKACJA"] for w in warstwy
                                 if w and w.get("WERYFIKACJA")), None)
    return wynik


def najnowsza_ochrona(wskazany=None):
    if wskazany:
        return wskazany
    for katalog in SZUKAJ_PRAWA:
        pliki = sorted(glob.glob(os.path.join(katalog, "ochrona_roslin_*.csv")))
        if pliki:
            return pliki[-1]
    return None


def wczytaj_ochrone(sciezka):
    """Pełne załączniki rozporządzenia o ochronie gatunkowej roślin.
    Klucz: nazwa naukowa z aktu ORAZ podane w nim synonimy — akt z 2014 r.
    miejscami używa nazw, które dziś są synonimami."""
    mapa = {}
    if not sciezka or not os.path.exists(sciezka):
        return mapa
    with open(sciezka, encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f, delimiter=";"):
            lat = (r.get("NAZWA_LAT") or "").strip()
            if not lat:
                continue
            wpis = {
                "ochrona": (r.get("OCHRONA") or "").replace(
                    "_pozyskiwanie", "").strip() or None,
                "czynna": 1 if (r.get("OCHRONA_CZYNNA") or "").strip() else None,
                "zal": r.get("ZALACZNIK"), "lp": r.get("LP"),
                "adn": (r.get("ADNOTACJE") or "").strip(),
                "nazwa_pl": (r.get("NAZWA_PL") or "").strip() or None,
            }
            mapa.setdefault(lat, wpis)
            syn = (r.get("SYNONIM") or "").strip()
            if syn and " " in syn:
                mapa.setdefault(syn, wpis)
    return mapa


def _int(x):
    try:
        return int(str(x).strip())
    except (TypeError, ValueError):
        return None


# ------------------------------------------------------------------- skróty
def wczytaj_skroty(sciezka):
    """Twoje skróty są lepsze, bo używane. Czyta dwa formaty:
    słownik Gboarda (fraza<TAB>skrót<TAB>język) i zwykły CSV skrót;nazwa."""
    mapa = {}
    if not sciezka or not os.path.exists(sciezka):
        return mapa
    with open(sciezka, encoding="utf-8-sig", newline="") as f:
        for linia in f:
            linia = linia.rstrip("\n\r")
            if not linia or linia.startswith("#"):
                continue
            if "\t" in linia:                       # format Gboarda
                czesci = linia.split("\t")
                if len(czesci) >= 2 and czesci[0] and czesci[1]:
                    mapa.setdefault(czesci[0].strip(), czesci[1].strip())
                continue
            czesci = [c.strip() for c in linia.split(";")]
            if len(czesci) < 2:
                czesci = [c.strip() for c in linia.split(",")]
            if len(czesci) >= 2 and czesci[0] and czesci[1]:
                # zgadujemy kolejność: krótszy człon to skrót
                a, b = czesci[0], czesci[1]
                if len(a) <= len(b):
                    mapa.setdefault(b, a)
                else:
                    mapa.setdefault(a, b)
    return mapa


def zbuduj_skrot(kanoniczna, odmiana, zajete):
    """Konwencja z istniejącego słownika: pierwsza litera rodzaju + dwie
    pierwsze epitetu, małymi literami (Abies alba -> aba, A. concolor -> abc).
    Kolumna SKROT_ZRODLO mówi, czy skrót przyszedł ze słownika, czy powstał
    tutaj — wygenerowanego nikt jeszcze nie używał w terenie."""
    czlony = kanoniczna.split()
    if not czlony:
        return None
    if len(czlony) == 1:
        rdzen = czlony[0][:3].lower()
    else:
        rdzen = (czlony[0][0] + czlony[1][:2]).lower()
    if odmiana:
        rdzen += "".join(c for c in odmiana if c.isalnum())[:2].lower()
    kandydat, n = rdzen, 1
    while kandydat in zajete:
        n += 1
        kandydat = "%s%d" % (rdzen, n)
    zajete.add(kandydat)
    return kandydat


# ------------------------------------------------------------- dopasowanie GBIF
def gbif_match(nazwa, krolestwo, mail, pamiec, checklist=None, opoznienie=0.2):
    """Jedno zapytanie do /v2/species/match. Kultywar MUSI być już zdjęty.
    Bez podanego królestwa rodzaj Betula trafia na błonkówkę."""
    klucz = "%s|%s|%s" % (nazwa, krolestwo, checklist or "-")
    if klucz in pamiec:
        return pamiec[klucz]
    p = {"scientificName": nazwa, "kingdom": krolestwo, "verbose": "true"}
    if checklist:
        p["checklistKey"] = checklist
    url = "https://api.gbif.org/v2/species/match?" + urllib.parse.urlencode(p)
    zad = urllib.request.Request(url, headers={
        "User-Agent": "WorkFieldGIS/0.9 (%s)" % (mail or "brak-adresu")})
    for proba in range(5):
        try:
            with urllib.request.urlopen(zad, timeout=30) as o:
                dane = json.loads(o.read().decode("utf-8"))
            pamiec[klucz] = dane
            time.sleep(opoznienie)
            return dane
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(2 ** proba)
                continue
            raise
    raise RuntimeError("GBIF: 429 po pięciu próbach — przerwij i wróć później")


def decyzja(match_type, pewnosc, byl_epitet):
    if match_type in (None, "NONE"):
        return "RECZNIE"          # przy NONE pewność bywa 100 — nie ufaj jej
    if match_type == "EXACT" and pewnosc >= 95:
        return "AUTO"
    if match_type in ("EXACT", "VARIANT") and pewnosc >= 80:
        return "AUTO"
    if match_type == "FUZZY" and pewnosc >= 95:
        return "AUTO_OZNACZ"
    if match_type == "HIGHERRANK":
        return "AUTO_RODZAJ" if not byl_epitet else "PRZEGLAD"
    return "PRZEGLAD"


# ------------------------------------------------------------------ wejście
def czytaj_zrodlo(sciezka, tabela, kolumna):
    """Zwraca listę słowników — całe wiersze źródła, nie same nazwy.
    Dzięki temu skróty i nazwy polskie, które już są w słowniku, nie muszą
    być generowane od nowa."""
    if sciezka.lower().endswith((".gpkg", ".sqlite", ".db")):
        if not tabela:
            sys.exit("Przy źródle w GPKG podaj --tabela")
        con = sqlite3.connect(sciezka)
        con.row_factory = sqlite3.Row
        try:
            kol = [r[1] for r in con.execute('PRAGMA table_info("%s")' % tabela)]
            if kolumna not in kol:
                sys.exit("W tabeli %s nie ma kolumny %r. Są: %s"
                         % (tabela, kolumna, ", ".join(kol)))
            return [dict(r) for r in con.execute('SELECT * FROM "%s"' % tabela)
                    if (r[kolumna] or "").strip()]
        finally:
            con.close()
    with open(sciezka, encoding="utf-8-sig", newline="") as f:
        próbka = f.read(4096)
        f.seek(0)
        sep = ";" if próbka.count(";") > próbka.count(",") else ","
        czyt = csv.DictReader(f, delimiter=sep)
        if kolumna not in (czyt.fieldnames or []):
            sys.exit("W pliku nie ma kolumny %r. Są: %s"
                     % (kolumna, ", ".join(czyt.fieldnames or [])))
        return [dict(r) for r in czyt if (r.get(kolumna) or "").strip()]


def wczytaj_dopasowania(wskazanie):
    """--dopasowania PLIK.gpkg:tabela — wciąga GOTOWE wyniki dopasowania do
    kręgosłupa. 2824 rozstrzygnięć już istnieje; pytanie API o nie drugi raz
    to strata czasu i niepotrzebny ruch."""
    if not wskazanie:
        return {}
    if ":" in wskazanie:
        plik, tabela = wskazanie.rsplit(":", 1)
    else:
        plik, tabela = wskazanie, "taksony"
    if not os.path.exists(plik):
        sys.exit("Nie ma pliku z dopasowaniami: %s" % plik)
    con = sqlite3.connect(plik)
    con.row_factory = sqlite3.Row
    try:
        kol = [r[1] for r in con.execute('PRAGMA table_info("%s")' % tabela)]
        if not kol:
            sys.exit("W %s nie ma tabeli %s" % (plik, tabela))
        wiersze = [dict(r) for r in con.execute('SELECT * FROM "%s"' % tabela)]
    finally:
        con.close()
    mapa = {}
    for w in wiersze:
        wpis = {
            "gbif_key": (w.get("gbif_key") or "") or None,
            "kanoniczna": (w.get("nazwa_kanoniczna") or "") or None,
            "status": (w.get("status") or "") or None,
            "ranga": (w.get("ranga") or "") or None,
            "rodzina": (w.get("rodzina") or "") or None,
            "dopasowanie": (w.get("dopasowanie") or "") or None,
            "nazwa_pl": (w.get("nazwa_polska") or "") or None,
        }
        for klucz in (w.get("nazwa_zrodlowa"), w.get("nazwa_kanoniczna")):
            if klucz and klucz.strip():
                mapa.setdefault(klucz.strip(), wpis)
    return mapa


def porownaj_prawo(zrodlowy, wiersz):
    """Słownik Piotra ma własne kolumny CHRONIONY / IGO / CENNY. Warstwa prawna
    ma swoje, wprost z Dz.U. Rozbieżność nie jest błędem — bywa różnicą między
    inwazyjnością przyrodniczą a statusem prawnym — ale ma być WIDOCZNA."""
    uwagi = []
    igo_zrodlo = (zrodlowy.get("IGO") or "").strip().upper()
    if igo_zrodlo in ("TAK", "NIE"):
        ma_prawnie = bool(wiersz.get("IGO"))
        if igo_zrodlo == "TAK" and not ma_prawnie:
            uwagi.append("IGO: słownik TAK, brak na liście z Dz.U.")
        elif igo_zrodlo == "NIE" and ma_prawnie:
            uwagi.append("IGO: słownik NIE, jest na liście z Dz.U. (%s)"
                         % wiersz["IGO"])
    chr_zrodlo = (zrodlowy.get("CHRONIONY") or "").strip().upper()
    if chr_zrodlo in ("TAK", "NIE"):
        ma_prawnie = bool(wiersz.get("OCHRONA"))
        if chr_zrodlo == "TAK" and not ma_prawnie:
            uwagi.append("ochrona: słownik TAK, brak w rozporządzeniu")
        elif chr_zrodlo == "NIE" and ma_prawnie:
            uwagi.append("ochrona: słownik NIE, jest w rozporządzeniu (%s)"
                         % wiersz["OCHRONA"])
    return uwagi


# ------------------------------------------------------------------- zapis
def kopia_zapasowa(gpkg, katalog):
    """Kopie NIE lądują obok projektu — cztery .bak w katalogu jadącym
    w teren pamiętamy z 21.08."""
    katalog = katalog or tempfile.gettempdir()
    os.makedirs(katalog, exist_ok=True)
    cel = os.path.join(katalog, "%s.bak_%s" % (
        os.path.basename(gpkg), datetime.now().strftime("%Y%m%d_%H%M%S")))
    shutil.copy2(gpkg, cel)
    return cel


def _stworz(con, nazwa, kolumny):
    con.execute('DROP TABLE IF EXISTS "%s"' % nazwa)
    con.execute('CREATE TABLE "%s" (%s)' % (
        nazwa, ", ".join('"%s" %s' % kt for kt in kolumny)))


def _wstaw(con, nazwa, kolumny, wiersze):
    nazwy = [k for k, _ in kolumny if k != "FID"]
    con.executemany(
        'INSERT INTO "%s" (%s) VALUES (%s)' % (
            nazwa, ",".join('"%s"' % n for n in nazwy),
            ",".join("?" * len(nazwy))),
        [[w.get(n) for n in nazwy] for w in wiersze])


def _zarejestruj(con, nazwa, opis):
    """Bez wpisu w gpkg_contents QGIS tabeli nie widzi."""
    if not con.execute("SELECT count(*) FROM sqlite_master "
                       "WHERE name='gpkg_contents'").fetchone()[0]:
        return
    con.execute("DELETE FROM gpkg_contents WHERE table_name=?", (nazwa,))
    con.execute(
        "INSERT INTO gpkg_contents (table_name,data_type,identifier,"
        "description,last_change,srs_id) VALUES (?,?,?,?,?,NULL)",
        (nazwa, "attributes", nazwa, opis,
         datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")))


def zapisz(gpkg, wiersze, xref, zrodla):
    con = sqlite3.connect(gpkg)
    try:
        con.execute("PRAGMA foreign_keys=OFF")
        _stworz(con, TABELA, KOLUMNY)
        _wstaw(con, TABELA, KOLUMNY, wiersze)
        con.execute('CREATE INDEX IF NOT EXISTS idx_taksony_gatunek '
                    'ON "%s"("GATUNEK","KROLESTWO")' % TABELA)
        con.execute('CREATE INDEX IF NOT EXISTS idx_taksony_skrot '
                    'ON "%s"("SKROT")' % TABELA)
        _stworz(con, TABELA_XREF, KOLUMNY_XREF)
        _wstaw(con, TABELA_XREF, KOLUMNY_XREF, xref)
        con.execute('CREATE INDEX IF NOT EXISTS idx_xref_gatunek '
                    'ON "%s"("GATUNEK","ZRODLO")' % TABELA_XREF)
        _stworz(con, TABELA_ZRODLA, KOLUMNY_ZRODLA)
        _wstaw(con, TABELA_ZRODLA, KOLUMNY_ZRODLA, zrodla)
        for n, o in ((TABELA, "Słownik taksonów WorkField"),
                     (TABELA_XREF, "Klucze obce taksonów (z wersją i datą)"),
                     (TABELA_ZRODLA, "Wersje źródeł, z których zbudowano bazę")):
            _zarejestruj(con, n, o)
        con.commit()
    finally:
        con.close()


def eksport_gboard(gpkg, cel):
    con = sqlite3.connect(gpkg)
    try:
        wiersze = con.execute(
            'SELECT SKROT, NAZWA FROM "%s" WHERE SKROT IS NOT NULL '
            'ORDER BY NAZWA' % TABELA).fetchall()
    finally:
        con.close()
    with open(cel, "w", encoding="utf-8", newline="") as f:
        f.write("# Gboard Dictionary version:1\n")
        for skrot, nazwa in wiersze:
            f.write("%s\t%s\tpl-PL\n" % (nazwa, skrot))
    return len(wiersze)


# -------------------------------------------------------------------- główna
def main():
    a = argparse.ArgumentParser(description="Budowa słownika TAKSONY")
    a.add_argument("--zrodlo", help="CSV albo GPKG z listą nazw")
    a.add_argument("--tabela", help="tabela w GPKG źródłowym")
    a.add_argument("--kolumna", default="GATUNEK", help="kolumna z nazwą")
    a.add_argument("--gpkg", help="docelowy GeoPackage szablonu")
    a.add_argument("--prawo", help="CSV warstwy prawnej (domyślnie najnowszy)")
    a.add_argument("--ochrona", help="CSV z ochroną gatunkową roślin "
                                     "(domyślnie najnowszy ochrona_roslin_*.csv)")
    a.add_argument("--nazwy-pl", help="CSV: NAZWA_LAT;NAZWA_PL (Wikidata/GBIF)")
    a.add_argument("--skroty", help="istniejący słownik Gboarda albo CSV")
    a.add_argument("--kolumna-skrot", help="kolumna ze skrótem w źródle "
                                           "(np. SKROT) — ma pierwszeństwo")
    a.add_argument("--kolumna-pl", help="kolumna z nazwą polską w źródle "
                                        "(np. NAZWA_POLSKA)")
    a.add_argument("--dopasowania", help="PLIK.gpkg:tabela z GOTOWYMI wynikami "
                                         "dopasowania (domyślna tabela: taksony)")
    a.add_argument("--krolestwo", default="Plantae",
                   help="królestwo dla wpisów bez własnego (domyślnie Plantae)")
    a.add_argument("--gbif", action="store_true", help="dopasuj przez sieć")
    a.add_argument("--checklist", help="checklistKey, np. COL XR")
    a.add_argument("--mail", help="adres do nagłówka User-Agent (grzeczność)")
    a.add_argument("--pamiec", default="gbif_cache.json")
    a.add_argument("--kopie", help="katalog na kopie zapasowe (domyślnie /tmp)")
    a.add_argument("--gboard", help="wyeksportuj słownik skrótów do pliku")
    a.add_argument("--csv-out", help="zapisz zbudowany słownik jako CSV "
                                     "(to jest wersja do repo — diffowalna)")
    a.add_argument("--sucho", action="store_true", help="nic nie zapisuj")
    args = a.parse_args()

    if args.gboard and not args.zrodlo:
        if not args.gpkg:
            sys.exit("--gboard wymaga --gpkg")
        n = eksport_gboard(args.gpkg, args.gboard)
        print("Gboard: %d haseł -> %s" % (n, args.gboard))
        return

    if not args.zrodlo:
        sys.exit("Podaj --zrodlo (CSV albo GPKG) albo użyj --gboard")

    surowe = czytaj_zrodlo(args.zrodlo, args.tabela, args.kolumna)
    print("Wczytano %d wpisów źródłowych" % len(surowe))

    plik_prawa = najnowsze_prawo(args.prawo)
    wersja_pr = wersja_prawa(plik_prawa)
    po_gat, po_rodz = wczytaj_prawo(plik_prawa)
    print("Warstwa prawna [%s]: %d gatunków, %d rodzajów"
          % (wersja_pr, len(po_gat), len(po_rodz)))

    plik_ochrony = najnowsza_ochrona(args.ochrona)
    ochrona_gat = wczytaj_ochrone(plik_ochrony)
    if ochrona_gat:
        print("Ochrona gatunkowa: %d nazw z %s"
              % (len(ochrona_gat), os.path.basename(plik_ochrony)))

    stare_skroty = wczytaj_skroty(args.skroty)
    if args.skroty:
        print("Skróty z Gboarda: %d haseł" % len(stare_skroty))

    nazwy_pl = {}
    if args.nazwy_pl and os.path.exists(args.nazwy_pl):
        with open(args.nazwy_pl, encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f, delimiter=";"):
                if r.get("NAZWA_LAT") and r.get("NAZWA_PL"):
                    nazwy_pl[r["NAZWA_LAT"].strip()] = r["NAZWA_PL"].strip()

    pamiec = {}
    if args.gbif and os.path.exists(args.pamiec):
        pamiec = json.load(open(args.pamiec, encoding="utf-8"))

    dzis = datetime.now().strftime("%Y-%m-%d")
    widziane, zajete, wiersze, xref = {}, set(), [], []
    widziane_xref = set()
    licznik = {}
    z_gboarda = 0

    gotowe = wczytaj_dopasowania(args.dopasowania)
    if gotowe:
        print("Gotowe dopasowania: %d kluczy z %s"
              % (len(gotowe), args.dopasowania))
    rozbieznosci = []

    for zrodlowy in surowe:
        surowy = zrodlowy[args.kolumna]
        w = rozbierz(surowy)
        if not w["kanoniczna"]:
            continue
        klucz = (w["klucz"], w["odmiana"])
        if klucz in widziane:
            continue                      # deduplikacja: Festuca rubra x3 -> 1
        widziane[klucz] = True

        nazwa_do_wyswietlenia = do_wyswietlenia(w)
        skrot = None
        if args.kolumna_skrot:
            skrot = (zrodlowy.get(args.kolumna_skrot) or "").strip() or None
        skrot = (skrot
                 or stare_skroty.get(nazwa_do_wyswietlenia)
                 or stare_skroty.get(w["kanoniczna"])
                 or stare_skroty.get(surowy.strip()))
        if skrot in zajete:
            # ten sam skrót nie może wskazywać dwóch taksonów: gatunek zabiera
            # skrót z Gboarda, kultywar dostaje własny, wygenerowany
            skrot = None
        if skrot:
            skrot_zrodlo = "slownik" if (args.kolumna_skrot and
                                         (zrodlowy.get(args.kolumna_skrot) or "").strip()
                                         == skrot) else "gboard"
            zajete.add(skrot)
            z_gboarda += 1
        else:
            skrot = zbuduj_skrot(w["kanoniczna"], w["odmiana"], zajete)
            skrot_zrodlo = "auto"

        p = prawo_dla(w["kanoniczna"], w["rodzaj"], po_gat, po_rodz)
        wiersz = {
            "NAZWA": nazwa_do_wyswietlenia,
            "GATUNEK": w["kanoniczna"],
            "KROLESTWO": args.krolestwo,
            "ODMIANA": w["odmiana"] or None,
            "NAZWA_PL": ((zrodlowy.get(args.kolumna_pl) or "").strip()
                         if args.kolumna_pl else None)
                        or nazwy_pl.get(w["kanoniczna"]) or p["NAZWA_PL"],
            "SKROT": skrot,
            "SKROT_ZRODLO": skrot_zrodlo,
            "RODZAJ": w["rodzaj"],
            "RANGA": w["ranga"],
            "HYBRYDA": w["hybryda"],
            "KWALIFIKATOR": w["kwalifikator"] or None,
            "NAZWA_ZRODLOWA": surowy,
            "PROG_CM": _int(p["PROG_5"]),
            "GRUPA_STAWKI": _int(p["GRUPA_STAWKI"]),
            "GRUPA_KRZEWY": _int(p["GRUPA_KRZEWY"]),
            "POMNIK_CM": _int(p["POMNIK_130"]),
            "ZWOLN_CM": _int(p["ZWOLN_130"]),
            "OWOCOWE": _int(p["OWOCOWE"]),
            "IGO": p["IGO"],
            "OCHRONA": p["OCHRONA"],
            "ZRODLO_PRAWO": p["ZRODLO"],
            "WERSJA_PRAWA": wersja_pr,
            "WERYFIKACJA": p["WERYFIKACJA"],
            "AKTUALIZACJA": dzis,
            "DOPASOWANIE": None, "PEWNOSC": None, "DECYZJA": "BEZ_SIECI",
            "STATUS": None, "AKCEPTOWANA": None, "RODZINA": None,
        }

        o = ochrona_gat.get(w["kanoniczna"])
        if o:
            # rozporządzenie ma pierwszeństwo nad dendrologiczną warstwą prawną:
            # tam jest 26 drzewiastych, tu komplet 728 pozycji
            wiersz["OCHRONA"] = o["ochrona"]
            wiersz["OCHRONA_CZYNNA"] = o["czynna"]
            wiersz["ZRODLO_PRAWO"] = "%s + 1409 zał.%s poz.%s%s" % (
                wiersz["ZRODLO_PRAWO"], o["zal"], o["lp"],
                " (adn. %s)" % o["adn"] if o["adn"] else "")
            if not wiersz["NAZWA_PL"]:
                wiersz["NAZWA_PL"] = o["nazwa_pl"]

        g = gotowe.get(surowy.strip()) or gotowe.get(w["kanoniczna"])
        if g:
            wiersz["DOPASOWANIE"] = g["dopasowanie"]
            wiersz["STATUS"] = g["status"]
            wiersz["RODZINA"] = g["rodzina"]
            wiersz["DECYZJA"] = ("AUTO" if g["dopasowanie"] == "EXACT"
                                 else "PRZEGLAD")
            if not wiersz["NAZWA_PL"]:
                wiersz["NAZWA_PL"] = g["nazwa_pl"]
            if g["gbif_key"]:
                klucz_x = (w["kanoniczna"], args.krolestwo, "GBIF")
                if klucz_x not in widziane_xref:
                    widziane_xref.add(klucz_x)
                    xref.append({
                        "GATUNEK": w["kanoniczna"],
                        "KROLESTWO": args.krolestwo,
                        "ZRODLO": "GBIF",
                        "ID_OBCE": str(g["gbif_key"]),
                        "WERSJA_ZRODLA": "import: %s" % (args.dopasowania or "-"),
                        "TYP_DOPASOWANIA": g["dopasowanie"],
                        "PEWNOSC": None,
                        "DATA": dzis,
                    })

        uwagi_prawne = porownaj_prawo(zrodlowy, wiersz)
        if uwagi_prawne:
            rozbieznosci.append((wiersz["NAZWA"], "; ".join(uwagi_prawne)))
            wiersz["WERYFIKACJA"] = "; ".join(
                [x for x in [wiersz["WERYFIKACJA"]] + uwagi_prawne if x])

        if args.gbif and not g:
            try:
                r = gbif_match(w["kanoniczna"], args.krolestwo, args.mail,
                               pamiec, args.checklist)
            except Exception as e:                        # sieć bywa kapryśna
                print("  ! %s: %s" % (w["kanoniczna"], e))
                r = None
            if r:
                d = r.get("diagnostics") or {}
                u = r.get("usage") or {}
                akc = r.get("acceptedUsage") or {}
                wiersz["DOPASOWANIE"] = d.get("matchType")
                wiersz["PEWNOSC"] = d.get("confidence")
                wiersz["STATUS"] = u.get("status")
                wiersz["AKCEPTOWANA"] = akc.get("canonicalName")
                wiersz["RODZINA"] = next(
                    (c["name"] for c in (r.get("classification") or [])
                     if c.get("rank") == "FAMILY"), None)
                wiersz["DECYZJA"] = decyzja(d.get("matchType"),
                                            d.get("confidence") or 0,
                                            bool(w["epitet"]))
                if w["odmiana"] and not wiersz["WERYFIKACJA"]:
                    # kultywar zawsze wypada z kręgosłupa — to nie jest błąd
                    wiersz["WERYFIKACJA"] = "kultywar poza kręgosłupem"
                klucz_x = (w["kanoniczna"], args.krolestwo,
                           "COLXR" if args.checklist else "GBIF")
                if u.get("key") and klucz_x not in widziane_xref:
                    widziane_xref.add(klucz_x)   # gatunek i jego kultywary
                    xref.append({                # dzielą jeden klucz obcy
                        "GATUNEK": w["kanoniczna"],
                        "KROLESTWO": args.krolestwo,
                        "ZRODLO": "COLXR" if args.checklist else "GBIF",
                        "ID_OBCE": str(u["key"]),
                        "WERSJA_ZRODLA": args.checklist or "gbif-v2-match",
                        "TYP_DOPASOWANIA": d.get("matchType"),
                        "PEWNOSC": d.get("confidence"),
                        "DATA": dzis,
                    })
        licznik[wiersz["DECYZJA"]] = licznik.get(wiersz["DECYZJA"], 0) + 1
        wiersze.append(wiersz)

    print("Unikalnych taksonów: %d" % len(wiersze))
    for k, v in sorted(licznik.items()):
        print("  %-12s %d" % (k, v))
    if args.skroty:
        print("  skróty: %d z Gboarda, %d wygenerowanych (małymi literami)"
              % (z_gboarda, len(wiersze) - z_gboarda))
    if rozbieznosci:
        print("\nRozbieżności między słownikiem a warstwą prawną (%d):"
              % len(rozbieznosci))
        for nazwa, opis in rozbieznosci[:20]:
            print("  %-34s %s" % (nazwa[:34], opis))
        if len(rozbieznosci) > 20:
            print("  … i %d dalszych (wszystkie w kolumnie WERYFIKACJA)"
                  % (len(rozbieznosci) - 20))

    do_oka = [w for w in wiersze if w["DECYZJA"] in ("PRZEGLAD", "RECZNIE")]
    if do_oka:
        print("\nDo obejrzenia okiem (%d):" % len(do_oka))
        for w in do_oka[:20]:
            print("  %-40s <- %s" % (w["NAZWA"], w["NAZWA_ZRODLOWA"]))
        if len(do_oka) > 20:
            print("  … i %d dalszych" % (len(do_oka) - 20))

    zrodla = [
        {"KLUCZ": "warstwa_prawna", "WERSJA": wersja_pr, "DATA": dzis,
         "LICENCJA": "domena publiczna (art. 4 pr.aut.)",
         "UWAGA": os.path.basename(plik_prawa or "brak")},
        {"KLUCZ": "ochrona_gatunkowa",
         "WERSJA": os.path.basename(plik_ochrony) if plik_ochrony else "brak",
         "DATA": dzis, "LICENCJA": "domena publiczna (art. 4 pr.aut.)",
         "UWAGA": "Dz.U. 2014 poz. 1409, zał. 1-3"},
        {"KLUCZ": "skrypt", "WERSJA": WERSJA_SKRYPTU, "DATA": dzis,
         "LICENCJA": "GPL-2.0-or-later", "UWAGA": "zbuduj_taksony.py"},
        {"KLUCZ": "kregoslup", "WERSJA": (args.checklist or "GBIF v2 match")
         if args.gbif else "brak (bez sieci)", "DATA": dzis,
         "LICENCJA": "CC BY 4.0", "UWAGA": "dopasowanie nazw"},
        {"KLUCZ": "nazwy_pl", "WERSJA": os.path.basename(args.nazwy_pl)
         if args.nazwy_pl else "brak", "DATA": dzis,
         "LICENCJA": "CC0 (Wikidata) / CC BY (GBIF)",
         "UWAGA": "własne opracowanie na podstawie źródeł CC0/CC BY"},
        {"KLUCZ": "skroty", "WERSJA": os.path.basename(args.skroty)
         if args.skroty else "tylko generowane", "DATA": dzis,
         "LICENCJA": "własne", "UWAGA": "gboard = używane, auto = małe litery"},
    ]

    if args.gbif:
        json.dump(pamiec, open(args.pamiec, "w", encoding="utf-8"),
                  ensure_ascii=False)

    if args.csv_out:
        nazwy_kol = [k for k, _ in KOLUMNY if k != "FID"]
        with open(args.csv_out, "w", encoding="utf-8", newline="") as f:
            p = csv.DictWriter(f, fieldnames=nazwy_kol, delimiter=";")
            p.writeheader()
            for w in sorted(wiersze, key=lambda x: (x["KROLESTWO"] or "",
                                                    x["NAZWA"] or "")):
                p.writerow({k: w.get(k) for k in nazwy_kol})
        print("Słownik jako CSV: %d wierszy -> %s" % (len(wiersze), args.csv_out))
        if xref:
            sciezka_x = args.csv_out.replace(".csv", "_xref.csv")
            nazwy_x = [k for k, _ in KOLUMNY_XREF if k != "FID"]
            with open(sciezka_x, "w", encoding="utf-8", newline="") as f:
                p = csv.DictWriter(f, fieldnames=nazwy_x, delimiter=";")
                p.writeheader()
                p.writerows(sorted(xref, key=lambda x: (x["GATUNEK"], x["ZRODLO"])))
            print("Klucze obce jako CSV: %d -> %s" % (len(xref), sciezka_x))

    if args.sucho or not args.gpkg:
        print("\nSUCHA PRÓBA — nic nie zapisano.")
        return
    kopia = kopia_zapasowa(args.gpkg, args.kopie)
    print("\nKopia zapasowa: %s" % kopia)
    zapisz(args.gpkg, wiersze, xref, zrodla)
    print("Zapisano: %s %d wierszy, %s %d, %s %d"
          % (TABELA, len(wiersze), TABELA_XREF, len(xref),
             TABELA_ZRODLA, len(zrodla)))
    if args.gboard:
        n = eksport_gboard(args.gpkg, args.gboard)
        print("Gboard: %d haseł -> %s" % (n, args.gboard))


if __name__ == "__main__":
    main()
