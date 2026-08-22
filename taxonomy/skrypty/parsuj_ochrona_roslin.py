# -*- coding: utf-8 -*-
"""
parsuj_ochrona_roslin.py — załączniki rozporządzenia o ochronie gatunkowej
roślin (Dz.U. 2014 poz. 1409) → CSV.

Czyta ORYGINALNY PDF z Dziennika Ustaw. Bliźniak
`parsuj_ochrona_zwierzat.py`, ale struktura aktu jest inna i dlatego jest to
osobny plik, a nie flaga:

  * jednostki systematyczne to **gromady** (WIELKIE, pogrubione) i **rodziny**
    (małe, pogrubione) — rozpoznajemy je po kroju pisma, tak jak każe akt
    w objaśnieniach, nie po liście nazw;
  * nie ma kolumny „x" — ochronę czynną niesie adnotacja **(1)**;
  * załączniki 3 i 4 mają trzecią kolumnę (sposób pozyskiwania / opis strefy),
    łamaną na kilka linii — trzeba sklejać wiersze.

    pip install pdfplumber
    python3 parsuj_ochrona_roslin.py D20141409.pdf

Powstają dwa pliki:
    ochrona_roslin_2014-1409.csv    załączniki 1-3
    strefy_roslin_2014-1409.csv     załącznik 4 (strefy ochrony stanowisk)

Znaczenie adnotacji, wprost z objaśnień aktu:
    (1) gatunki wymagające ochrony czynnej
    (2) zakaz transportu okazów (§ 6 ust. 1 pkt 6), bez odstępstwa z § 8 pkt 3
    (3) gatunki, których nie dotyczy odstępstwo z § 8 pkt 1
"""

import csv
import re
import sys
from collections import defaultdict

import pdfplumber

WIERSZ = re.compile(
    r"^(\d+)\.\s+"
    r"(.+?)\s+"
    r"([A-ZŚŻŹĆŃŁÓĄĘ][A-Za-zżźćńłóąęśë×\.\-]+"
    r"(?:\s+[A-Za-zżźćńłóąęśë×\.\-]+){0,3})"
    r"\s*$"
)
ADNOTACJE = re.compile(r"\((\d)\)")
STOPKA = re.compile(r"^Dziennik Ustaw|^Załącznik|^Lp\.|^Objaśnienia|^– \d+ –|^\s*$")

ZALACZNIKI = [
    ("GATUNKIROŚLINOBJĘTYCHOCHRONĄŚCISŁĄ", "1", "scisla"),
    ("GATUNKIROŚLINOBJĘTYCHOCHRONĄCZĘŚCIOWĄ,KTÓREMOGĄBYĆPOZYSKIWANE",
     "3", "czesciowa_pozyskiwanie"),
    ("GATUNKIROŚLINOBJĘTYCHOCHRONĄCZĘŚCIOWĄ", "2", "czesciowa"),
    ("GATUNKIROŚLINWYMAGAJĄCYCHUSTALENIASTREF", "4", "strefy"),
]

POLA = ["ZALACZNIK", "LP", "GROMADA", "RODZINA", "NAZWA_PL", "NAZWA_LAT",
        "SYNONIM", "OCHRONA", "OCHRONA_CZYNNA", "ADNOTACJE", "POZYSKIWANIE",
        "ZRODLO", "WERYFIKACJA"]
POLA_STREFY = ["LP", "GROMADA", "RODZINA", "NAZWA_PL", "NAZWA_LAT", "STREFA",
               "ZRODLO", "WERYFIKACJA"]


def linie_strony(strona):
    """[(tekst, czy_pogrubiona)] — słowa grupowane po wysokości wiersza."""
    kubelki = defaultdict(list)
    for w in strona.extract_words(extra_attrs=["fontname"]):
        kubelki[round(w["top"])].append(w)
    out = []
    for top in sorted(kubelki):
        slowa = sorted(kubelki[top], key=lambda w: w["x0"])
        tekst = " ".join(w["text"] for w in slowa).replace(" ", " ").strip()
        pogrubiona = any("Bold" in w.get("fontname", "") for w in slowa)
        out.append((tekst, pogrubiona))
    return out


def rozbierz_wiersz(tekst):
    """Zwraca (lp, nazwa_pl, nazwa_lat, synonim, adnotacje, ogon) albo None.
    Ogon to trzecia kolumna z załączników 3 i 4 — jeśli jest."""
    syn, ogon = "", ""
    s = tekst
    # synonim w nawiasie PO nazwie naukowej: "(Ch. jubata)"
    m = re.search(r"\s\(([A-Z][^)]{2,60})\)\s*$", s)
    if m:
        syn = m.group(1).strip()
        s = s[:m.start()].strip()
    m = WIERSZ.match(s)
    if m:
        lp, pl, lat = m.groups()
        adn = ",".join(sorted(set(ADNOTACJE.findall(pl))))
        pl = ADNOTACJE.sub("", pl)
        return lp, re.sub(r"\s+", " ", pl).strip(), lat.strip(), syn, adn, ogon
    # załączniki 3 i 4: po nazwie naukowej idzie opis zaczynający się wielką
    # literą albo cyfrą — odcinamy go i zapamiętujemy
    m = re.match(r"^(\d+)\.\s+(.+?)\s+"
                 r"([A-ZŚŻŹĆŃŁÓĄĘ][A-Za-zżźćńłóąęśë×\.\-]+"
                 r"(?:\s+[a-zżźćńłóąęśë×\.\-]+){0,2})\s+(.+)$", s)
    if m:
        lp, pl, lat, ogon = m.groups()
        adn = ",".join(sorted(set(ADNOTACJE.findall(pl))))
        pl = ADNOTACJE.sub("", pl)
        return lp, re.sub(r"\s+", " ", pl).strip(), lat.strip(), syn, adn, ogon
    return None


def czytaj_strefy(sciezka):
    """Załącznik 4 — z siatki tabeli, nie z linii tekstu."""
    out = []
    gromada = rodzina = ""
    biezacy = None
    with pdfplumber.open(sciezka) as pdf:
        w_zalaczniku = False
        for strona in pdf.pages:
            tekst = re.sub(r"\s+", "", strona.extract_text() or "")
            if "GATUNKIROŚLINWYMAGAJĄCYCHUSTALENIASTREF" in tekst:
                w_zalaczniku = True
            if not w_zalaczniku:
                continue
            for tabela in strona.extract_tables():
                for wiersz in tabela:
                    kom = [(c or "").replace("\n", " ").strip() for c in wiersz]
                    while len(kom) < 4:
                        kom.append("")
                    lp, pl, lat, opis = kom[0], kom[1], kom[2], kom[3]
                    if lp.startswith("Lp"):
                        continue
                    if not lp:
                        if pl and lat and not opis:          # nagłówek
                            if pl.isupper():
                                gromada, rodzina = "%s (%s)" % (pl, lat), ""
                            else:
                                rodzina = "%s (%s)" % (pl, lat)
                            biezacy = None
                        elif biezacy is not None:            # ciąg dalszy
                            czesci = [biezacy["NAZWA_PL"], pl] if pl else None
                            if czesci:
                                biezacy["NAZWA_PL"] = " ".join(czesci).strip()
                            if opis:
                                biezacy["STREFA"] = (biezacy["STREFA"] + " "
                                                     + opis).strip()
                        continue
                    biezacy = {"LP": lp.rstrip("."), "GROMADA": gromada,
                               "RODZINA": rodzina, "NAZWA_PL": pl,
                               "NAZWA_LAT": lat, "STREFA": opis,
                               "ZRODLO": "Dz.U. 2014 poz. 1409",
                               "WERYFIKACJA": ""}
                    out.append(biezacy)
    for w in out:
        w["STREFA"] = re.sub(r"\s+", " ", w["STREFA"]).strip()
    return out


def main(sciezka):
    wiersze, strefy, watpliwe = [], [], []
    zal = ochrona = None
    gromada = rodzina = ""
    ostatni = None                      # do doklejania linii łamanych
    czekajacy = None                    # wiersz rozpoczęty, jeszcze niedomknięty

    with pdfplumber.open(sciezka) as pdf:
        for nr, strona in enumerate(pdf.pages, 1):
            for linia, pogrubiona in linie_strony(strona):
                plaska = re.sub(r"\s+", "", linia)
                trafil = False
                for tytul, z, o in ZALACZNIKI:
                    if plaska.startswith(tytul):
                        zal, ochrona = z, o
                        gromada = rodzina = ""
                        ostatni = None
                        trafil = True
                        break
                if trafil or zal is None or STOPKA.match(linia):
                    continue

                if pogrubiona:
                    czlony = linia.split()
                    if len(czlony) >= 2:
                        pl, lat = " ".join(czlony[:-1]), czlony[-1]
                        if linia.isupper():
                            gromada, rodzina = "%s (%s)" % (pl, lat), ""
                        else:
                            rodzina = "%s (%s)" % (pl, lat)
                    ostatni = None
                    continue

                r = rozbierz_wiersz(linia)
                if not r and czekajacy:
                    # poprzednia linia zaczynała wiersz, ale się nie domknęła
                    r = rozbierz_wiersz(czekajacy + " " + linia)
                    if r:
                        watpliwe.pop()
                        czekajacy = None
                if not r:
                    # linia ciągnąca się z poprzedniego wiersza (kolumna opisu)
                    if ostatni is not None and not re.match(r"^\d+\.", linia):
                        ostatni["_ogon"] = (ostatni.get("_ogon", "") + " "
                                            + linia).strip()
                    elif re.match(r"^\d+\.", linia):
                        czekajacy = linia      # może dokończy się w następnej
                        watpliwe.append("s.%d: %s" % (nr, linia))
                    continue

                lp, pl, lat, syn, adn, ogon = r
                wpis = {
                    "ZALACZNIK": zal, "LP": lp, "GROMADA": gromada,
                    "RODZINA": rodzina, "NAZWA_PL": pl, "NAZWA_LAT": lat,
                    "SYNONIM": syn, "OCHRONA": ochrona,
                    "OCHRONA_CZYNNA": "1" if "1" in adn else "",
                    "ADNOTACJE": adn, "_ogon": ogon,
                    "ZRODLO": "Dz.U. 2014 poz. 1409", "WERYFIKACJA": "",
                }
                if zal == "4":
                    continue          # strefy czytamy z siatki tabeli, niżej
                wiersze.append(wpis)
                ostatni = wpis

    for w in wiersze:
        w["POZYSKIWANIE"] = re.sub(r"\s+", " ", w.pop("_ogon", "")).strip()

    # Załącznik 4 ma komórki łamane na kilka linii, a wiersze sąsiadują ze sobą
    # tak blisko, że sklejanie po liniach przecieka między pozycjami. Siatka
    # tabeli z pdfplumbera rozstrzyga to jednoznacznie.
    strefy[:] = czytaj_strefy(sciezka)

    with open("ochrona_roslin_2014-1409.csv", "w", encoding="utf-8",
              newline="") as f:
        p = csv.DictWriter(f, fieldnames=POLA, delimiter=";",
                           extrasaction="ignore")
        p.writeheader()
        p.writerows(wiersze)
    with open("strefy_roslin_2014-1409.csv", "w", encoding="utf-8",
              newline="") as f:
        p = csv.DictWriter(f, fieldnames=POLA_STREFY, delimiter=";",
                           extrasaction="ignore")
        p.writeheader()
        p.writerows(strefy)
    if watpliwe:
        with open("ochrona_roslin_do_recznego_sprawdzenia.txt", "w",
                  encoding="utf-8") as f:
            f.write("\n".join(watpliwe))

    for z in ("1", "2", "3"):
        lp = [int(x["LP"]) for x in wiersze if x["ZALACZNIK"] == z]
        if lp:
            braki = [i for i in range(1, max(lp) + 1) if i not in set(lp)]
            print("Załącznik %s: %d pozycji, ostatnia lp. %d, braki: %s"
                  % (z, len(lp), max(lp), braki or "brak"))
    print("Załącznik 4 (strefy): %d pozycji" % len(strefy))
    print("Ochrona czynna (1): %d"
          % sum(1 for x in wiersze if x["OCHRONA_CZYNNA"]))
    print("Rodzin rozpoznanych: %d"
          % len({x["RODZINA"] for x in wiersze if x["RODZINA"]}))
    print("Wierszy nieodczytanych: %d" % len(watpliwe))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "D20141409.pdf")
