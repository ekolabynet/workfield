# -*- coding: utf-8 -*-
"""
raport_taksony.py — cztery raporty do przejrzenia okiem, jako CSV.

`zbuduj_taksony.py` buduje słownik i pokazuje podsumowanie na ekranie.
Ten skrypt niczego nie buduje — wypisuje do plików to, co wymaga ludzkiej
decyzji, żeby dało się to przejść wierszami i poprawić u źródła.

    python3 raport_taksony.py \
        --zrodlo /…/wf_wskazniki.gpkg --tabela SLOWNIK_GATUNKOW \
        --kolumna GATUNEK --kolumna-skrot SKROT --kolumna-pl NAZWA_POLSKA \
        --dopasowania /…/wf_wskazniki.gpkg:taksony

Powstają cztery pliki w `raporty/RRRR-MM-DD/`:

  duplikaty.csv           wpisy sklejone przy deduplikacji — co się z czym zlało
  rozbieznosci_prawne.csv słownik mówi co innego niż rozporządzenie
  do_przegladu.csv        pozycje bez pewnego dopasowania do kręgosłupa
  podejrzane_nazwy.csv    pary nazw różniące się o literę — kandydaci na literówkę

Ostatni plik jest tu najważniejszy: `Antchemis` obok `Anthemis`,
`collna` obok `collina`, `silvestris` obok `sylvestris`. Skrypt NICZEGO nie
poprawia — poprawka nazwy to decyzja, nie operacja mechaniczna.
"""

import argparse
import csv
import difflib
import os
import sys
from collections import defaultdict
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from taksony_normalizacja import rozbierz, do_wyswietlenia          # noqa: E402
from zbuduj_taksony import (czytaj_zrodlo, najnowsze_prawo,         # noqa: E402
                            wczytaj_prawo, wersja_prawa, prawo_dla,
                            wczytaj_dopasowania, porownaj_prawo, _int,
                            najnowsza_ochrona, wczytaj_ochrone)

# próg podobieństwa dla podejrzenia literówki; niżej = więcej fałszywych par
PROG_PODOBIENSTWA = 0.86


def zapisz(katalog, nazwa, pola, wiersze):
    sciezka = os.path.join(katalog, nazwa)
    with open(sciezka, "w", encoding="utf-8", newline="") as f:
        p = csv.DictWriter(f, fieldnames=pola, delimiter=";")
        p.writeheader()
        p.writerows(wiersze)
    print("  %-26s %4d wierszy" % (nazwa, len(wiersze)))
    return len(wiersze)


def podejrzane_pary(kanoniczne):
    """Pary nazw w obrębie TEGO SAMEGO rodzaju, różniące się o włos.
    Blokowanie po rodzaju jest tu obowiązkowe: bez niego Acer i Alnus
    wyglądają na literówkę, a to zupełnie inne drzewa."""
    wg_rodzaju = defaultdict(list)
    for k in kanoniczne:
        wg_rodzaju[k.split()[0]].append(k)

    pary = []
    # 1. w obrębie rodzaju — literówki w epitecie
    for rodzaj, lista in wg_rodzaju.items():
        lista = sorted(set(lista))
        for i, a in enumerate(lista):
            for b in lista[i + 1:]:
                r = difflib.SequenceMatcher(None, a, b).ratio()
                if r >= PROG_PODOBIENSTWA:
                    pary.append((a, b, round(r, 3), "ten sam rodzaj"))
    # 2. same nazwy rodzajowe — literówki w rodzaju (Antchemis / Anthemis)
    rodzaje = sorted(wg_rodzaju)
    for i, a in enumerate(rodzaje):
        for b in rodzaje[i + 1:]:
            if abs(len(a) - len(b)) > 2:
                continue
            r = difflib.SequenceMatcher(None, a, b).ratio()
            if r >= PROG_PODOBIENSTWA:
                pary.append((a, b, round(r, 3), "nazwa rodzajowa"))
    return pary


def main():
    a = argparse.ArgumentParser(description="Raporty do przejrzenia okiem")
    a.add_argument("--zrodlo", required=True)
    a.add_argument("--tabela")
    a.add_argument("--kolumna", default="GATUNEK")
    a.add_argument("--kolumna-skrot")
    a.add_argument("--kolumna-pl")
    a.add_argument("--dopasowania")
    a.add_argument("--prawo")
    a.add_argument("--ochrona")
    a.add_argument("--katalog", help="gdzie zapisać (domyślnie raporty/RRRR-MM-DD)")
    args = a.parse_args()

    surowe = czytaj_zrodlo(args.zrodlo, args.tabela, args.kolumna)
    plik_prawa = najnowsze_prawo(args.prawo)
    po_gat, po_rodz = wczytaj_prawo(plik_prawa)
    gotowe = wczytaj_dopasowania(args.dopasowania)
    # ta sama warstwa ochrony co przy budowie — inaczej raport pokazuje
    # co innego niż zbuduj_taksony i nie wiadomo, któremu wierzyć
    ochrona_gat = wczytaj_ochrone(najnowsza_ochrona(args.ochrona))
    print("Wpisów: %d | warstwa prawna: %s | ochrona gatunkowa: %d | "
          "gotowych dopasowań: %d"
          % (len(surowe), wersja_prawa(plik_prawa), len(ochrona_gat),
             len(gotowe)))

    katalog = args.katalog or os.path.join(
        "raporty", datetime.now().strftime("%Y-%m-%d"))
    os.makedirs(katalog, exist_ok=True)

    wg_klucza = defaultdict(list)
    rozbieznosci, do_przegladu, kanoniczne = [], [], []

    for zrodlowy in surowe:
        surowy = zrodlowy[args.kolumna]
        w = rozbierz(surowy)
        if not w["kanoniczna"]:
            continue
        klucz = (w["klucz"], w["odmiana"])
        wg_klucza[klucz].append((surowy, zrodlowy))
        if len(wg_klucza[klucz]) > 1:
            continue                       # resztę liczymy raz na takson
        kanoniczne.append(w["kanoniczna"])

        p = prawo_dla(w["kanoniczna"], w["rodzaj"], po_gat, po_rodz)
        o = ochrona_gat.get(w["kanoniczna"])
        wiersz = {"IGO": p["IGO"],
                  "OCHRONA": o["ochrona"] if o else p["OCHRONA"]}
        for uwaga in porownaj_prawo(zrodlowy, wiersz):
            rozbieznosci.append({
                "GATUNEK": w["kanoniczna"],
                "NAZWA_PL": (zrodlowy.get(args.kolumna_pl) or ""
                             if args.kolumna_pl else ""),
                "SKROT": (zrodlowy.get(args.kolumna_skrot) or ""
                          if args.kolumna_skrot else ""),
                "ROZBIEZNOSC": uwaga,
                "SLOWNIK_CHRONIONY": zrodlowy.get("CHRONIONY") or "",
                "SLOWNIK_IGO": zrodlowy.get("IGO") or "",
                "PRAWO_OCHRONA": wiersz["OCHRONA"] or "",
                "PODSTAWA_OCHRONY": ("1409 zał.%s poz.%s" % (o["zal"], o["lp"])
                                     if o else ""),
                "PRAWO_IGO": p["IGO"] or "",
                "ZRODLO_PRAWO": p["ZRODLO"],
                "DECYZJA": "",
            })

        g = gotowe.get(surowy.strip()) or gotowe.get(w["kanoniczna"])
        if not g or g["dopasowanie"] != "EXACT":
            do_przegladu.append({
                "GATUNEK": w["kanoniczna"],
                "NAZWA_ZRODLOWA": surowy,
                "RANGA": w["ranga"],
                "POWOD": ("brak w tabeli dopasowań" if not g
                          else "dopasowanie %s" % g["dopasowanie"]),
                "GBIF_KEY": (g or {}).get("gbif_key") or "",
                "PROPOZYCJA": "",
                "DECYZJA": "",
            })

    duplikaty = []
    for (klucz, odmiana), lista in sorted(wg_klucza.items()):
        if len(lista) < 2:
            continue
        for surowy, _z in lista:
            duplikaty.append({
                "KLUCZ": klucz + (" '%s'" % odmiana if odmiana else ""),
                "NAZWA_ZRODLOWA": surowy,
                "ILE_SKLEJONYCH": len(lista),
                "DECYZJA": "",
            })

    print("\nZapisane do %s/" % katalog)
    zapisz(katalog, "duplikaty.csv",
           ["KLUCZ", "NAZWA_ZRODLOWA", "ILE_SKLEJONYCH", "DECYZJA"], duplikaty)
    zapisz(katalog, "rozbieznosci_prawne.csv",
           ["GATUNEK", "NAZWA_PL", "SKROT", "ROZBIEZNOSC", "SLOWNIK_CHRONIONY",
            "SLOWNIK_IGO", "PRAWO_OCHRONA", "PODSTAWA_OCHRONY", "PRAWO_IGO",
            "ZRODLO_PRAWO", "DECYZJA"], rozbieznosci)
    zapisz(katalog, "do_przegladu.csv",
           ["GATUNEK", "NAZWA_ZRODLOWA", "RANGA", "POWOD", "GBIF_KEY",
            "PROPOZYCJA", "DECYZJA"], do_przegladu)

    pary = podejrzane_pary(kanoniczne)
    zapisz(katalog, "podejrzane_nazwy.csv",
           ["NAZWA_A", "NAZWA_B", "PODOBIENSTWO", "POZIOM", "DECYZJA"],
           [{"NAZWA_A": a, "NAZWA_B": b, "PODOBIENSTWO": r, "POZIOM": poz,
             "DECYZJA": ""} for a, b, r, poz in sorted(pary)])

    print("\nKolumna DECYZJA jest pusta we wszystkich czterech plikach —"
          "\nto miejsce na Twój werdykt, nie na wynik działania skryptu.")


if __name__ == "__main__":
    main()
