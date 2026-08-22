# -*- coding: utf-8 -*-
"""
pobierz_nazwy_pl.py — nazwy polskie do słownika TAKSONY.

Dwa źródła, oba wolno redystrybuować:
  * Wikidata (CC0) — szersze pokrycie, brak walidacji nomenklaturowej,
  * GBIF /vernacularNames (CC BY) — dziurawe, ale niezależny drugi głos.

Nie pytamy o „wszystkie rośliny świata" — pytamy o NASZE nazwy, partiami.
Zapytanie po pełnej liście taksonów roślin przekracza limit 60 s zapytania
SPARQL; partia po 200 nazw wraca w sekundę.

    # z gotowej tabeli TAKSONY w GeoPackage
    python3 pobierz_nazwy_pl.py --gpkg dane.gpkg --wyjscie nazwy_pl.csv

    # z pliku CSV z kolumną nazw łacińskich
    python3 pobierz_nazwy_pl.py --csv slownik.csv --kolumna GATUNEK \
        --wyjscie nazwy_pl.csv

    # dopisz drugi głos z GBIF (wolniejsze, jedno zapytanie na takson)
    python3 pobierz_nazwy_pl.py --gpkg dane.gpkg --gbif --wyjscie nazwy_pl.csv

Wynik: CSV `NAZWA_LAT;NAZWA_PL;ZRODLO;QID;GBIF_KEY;WERYFIKACJA`, wpinany
do `zbuduj_taksony.py` przez `--nazwy-pl`.

UWAGA: to jest ZACZYN, nie gotowy słownik. Wikidata miesza nazwy odmian,
synonimy i kalki; „klon pospolity" vs „klon zwyczajny" rozstrzyga człowiek.
Kolumna WERYFIKACJA zostaje pusta, dopóki ktoś na to nie spojrzy.
"""

import argparse
import csv
import json
import os
import sqlite3
import sys
import time
import urllib.parse
import urllib.request

SPARQL = "https://query.wikidata.org/sparql"
GBIF = "https://api.gbif.org/v1"

# P225 nazwa naukowa, P1843 nazwa zwyczajowa (z językiem), P846 GBIF taxon ID
ZAPYTANIE = """
SELECT ?nazwaLat ?taxon ?pospolita ?etykieta ?gbif WHERE {
  VALUES ?nazwaLat { %s }
  ?taxon wdt:P225 ?nazwaLat .
  OPTIONAL { ?taxon wdt:P1843 ?pospolita . FILTER(LANG(?pospolita) = "pl") }
  OPTIONAL { ?taxon rdfs:label ?etykieta .  FILTER(LANG(?etykieta)  = "pl") }
  OPTIONAL { ?taxon wdt:P846 ?gbif }
}
"""


def wolaj(url, mail, dane=None, naglowki=None):
    h = {"User-Agent": "WorkFieldGIS/0.9 (%s)" % (mail or "brak-adresu"),
         "Accept": "application/sparql-results+json"}
    h.update(naglowki or {})
    zad = urllib.request.Request(url, data=dane, headers=h)
    for proba in range(5):
        try:
            with urllib.request.urlopen(zad, timeout=90) as o:
                return json.loads(o.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code in (429, 503):
                time.sleep(2 ** proba)
                continue
            raise
    raise RuntimeError("nie udało się po pięciu próbach: %s" % url)


def partia_wikidata(nazwy, mail):
    values = " ".join('"%s"' % n.replace('"', "") for n in nazwy)
    q = ZAPYTANIE % values
    dane = urllib.parse.urlencode({"query": q, "format": "json"}).encode()
    wynik = wolaj(SPARQL, mail, dane,
                  {"Content-Type": "application/x-www-form-urlencoded"})
    out = {}
    for w in wynik["results"]["bindings"]:
        lat = w["nazwaLat"]["value"]
        pospolita = w.get("pospolita", {}).get("value")
        etykieta = w.get("etykieta", {}).get("value")
        qid = w["taxon"]["value"].rsplit("/", 1)[-1]
        gbif = w.get("gbif", {}).get("value")
        # etykieta bywa po prostu łaciną — wtedy nie jest nazwą polską
        if etykieta and etykieta.strip().lower() == lat.strip().lower():
            etykieta = None
        nazwa = pospolita or etykieta
        if not nazwa:
            continue
        zrodlo = "wikidata:P1843" if pospolita else "wikidata:label"
        # pierwszeństwo ma P1843; nie nadpisujemy lepszego gorszym
        if lat in out and out[lat]["ZRODLO"] == "wikidata:P1843":
            continue
        out[lat] = {"NAZWA_LAT": lat, "NAZWA_PL": nazwa, "ZRODLO": zrodlo,
                    "QID": qid, "GBIF_KEY": gbif or "", "WERYFIKACJA": ""}
    return out


def z_gbif(nazwa, mail):
    p = urllib.parse.urlencode({"name": nazwa, "kingdom": "Plantae"})
    m = wolaj("%s/species/match?%s" % (GBIF, p), mail)
    key = m.get("usageKey")
    if not key or m.get("matchType") in (None, "NONE"):
        return None, None
    v = wolaj("%s/species/%s/vernacularNames?limit=200" % (GBIF, key), mail)
    for w in v.get("results", []):
        if w.get("language") == "pol" and w.get("vernacularName"):
            n = w["vernacularName"].strip()
            # GBIF bywa zapisuje "Sosna Zwyczajna" — wersaliki do poprawy
            if n.istitle() and " " in n:
                n = n[0] + n[1:].lower()
            return n, str(key)
    return None, str(key)


def wczytaj_nazwy(args):
    if args.gpkg:
        con = sqlite3.connect(args.gpkg)
        try:
            return [r[0] for r in con.execute(
                'SELECT DISTINCT GATUNEK FROM TAKSONY WHERE GATUNEK IS NOT NULL'
            ) if r[0]]
        finally:
            con.close()
    with open(args.csv, encoding="utf-8-sig", newline="") as f:
        próbka = f.read(4096)
        f.seek(0)
        sep = ";" if próbka.count(";") > próbka.count(",") else ","
        czyt = csv.DictReader(f, delimiter=sep)
        if args.kolumna not in (czyt.fieldnames or []):
            sys.exit("Brak kolumny %r. Są: %s"
                     % (args.kolumna, ", ".join(czyt.fieldnames or [])))
        return sorted({r[args.kolumna].strip() for r in czyt
                       if (r.get(args.kolumna) or "").strip()})


def main():
    a = argparse.ArgumentParser(description="Nazwy polskie: Wikidata + GBIF")
    a.add_argument("--gpkg", help="GeoPackage z tabelą TAKSONY")
    a.add_argument("--csv", help="CSV z nazwami łacińskimi")
    a.add_argument("--kolumna", default="GATUNEK")
    a.add_argument("--wyjscie", default="nazwy_pl.csv")
    a.add_argument("--partia", type=int, default=200)
    a.add_argument("--gbif", action="store_true", help="drugi głos z GBIF")
    a.add_argument("--mail", help="adres do User-Agent (grzeczność wobec API)")
    args = a.parse_args()
    if not args.gpkg and not args.csv:
        sys.exit("Podaj --gpkg albo --csv")

    nazwy = wczytaj_nazwy(args)
    print("Taksonów do sprawdzenia: %d" % len(nazwy))

    zebrane = {}
    for i in range(0, len(nazwy), args.partia):
        partia = nazwy[i:i + args.partia]
        try:
            zebrane.update(partia_wikidata(partia, args.mail))
        except Exception as e:
            print("  ! partia %d-%d: %s" % (i, i + len(partia), e))
        print("  Wikidata: %d/%d nazw, trafień %d"
              % (min(i + args.partia, len(nazwy)), len(nazwy), len(zebrane)))
        time.sleep(1)

    braki = [n for n in nazwy if n not in zebrane]
    print("Bez nazwy polskiej po Wikidacie: %d" % len(braki))

    if args.gbif and braki:
        for n in braki:
            try:
                nazwa, key = z_gbif(n, args.mail)
            except Exception as e:
                print("  ! %s: %s" % (n, e))
                continue
            if nazwa:
                zebrane[n] = {"NAZWA_LAT": n, "NAZWA_PL": nazwa,
                              "ZRODLO": "gbif:vernacular", "QID": "",
                              "GBIF_KEY": key or "", "WERYFIKACJA": ""}
            time.sleep(0.2)
        print("Po GBIF: %d nazw" % len(zebrane))

    pola = ["NAZWA_LAT", "NAZWA_PL", "ZRODLO", "QID", "GBIF_KEY", "WERYFIKACJA"]
    with open(args.wyjscie, "w", encoding="utf-8", newline="") as f:
        p = csv.DictWriter(f, fieldnames=pola, delimiter=";")
        p.writeheader()
        for n in nazwy:
            if n in zebrane:
                p.writerow(zebrane[n])
    print("Zapisano %d wierszy -> %s" % (len(zebrane), args.wyjscie))

    if braki:
        sciezka = os.path.splitext(args.wyjscie)[0] + "_braki.txt"
        with open(sciezka, "w", encoding="utf-8") as f:
            f.write("\n".join(n for n in nazwy if n not in zebrane))
        print("Bez nazwy polskiej: %d -> %s"
              % (sum(1 for n in nazwy if n not in zebrane), sciezka))


if __name__ == "__main__":
    main()
