# -*- coding: utf-8 -*-
"""
parsuj_ochrona_zwierzat.py — załączniki 1–3 rozporządzenia o ochronie
gatunkowej zwierząt (Dz.U. 2016 poz. 2183) → CSV.

Czyta ORYGINALNY PDF z Dziennika Ustaw, nie przedruk. Nic nie dopisuje
z własnej wiedzy: czego nie da się odczytać jednoznacznie, ląduje
w `ochrona_zwierzat_do_recznego_sprawdzenia.txt`.

    pip install pdfplumber        # jedyna zależność
    python3 parsuj_ochrona_zwierzat.py D20162183.pdf

Gromady rozpoznajemy PO KROJU PISMA, nie po liście nazw — bo tak mówi sam
akt w objaśnieniach: „wielkimi literami, czcionką pogrubioną wyróżniono
nazwy GROMAD, wielkimi literami, czcionką zwykłą — nazwy RZĘDÓW".
Lista nazw byłaby zgadywaniem i myliła się na „RYBY PROMIENIOPŁETWE
ACTINOPTERYGII" oraz „SIODEŁKOWCE CLITELLATA".

Załącznik nr 4 (strefy ochrony) NIE jest tu parsowany — jego strony są
obrócone, a tekst wychodzi z nich odwrócony. Leży osobno,
w `strefy_ochrony_2016-2183.csv`, przepisany ręcznie i sprawdzony wzrokiem.
"""

import csv
import re
import sys
from collections import defaultdict

import pdfplumber

# "12. nazwa polska (1)(3) Genus species" — "x" i synonimy zdejmowane wcześniej
WIERSZ = re.compile(
    r"^(\d+)\.\s+"
    r"(.+?)\s+"
    r"([A-ZŚŻŹĆŃŁÓĄĘ][A-Za-zżźćńłóąęśęë.\-]+"
    r"(?:\s+[a-zżźćńłóąęśë.\-]+){1,3})"
    r"\s*$"
)
ADNOTACJE = re.compile(r"\((\d)\)")
STOPKA = re.compile(r"^Dziennik Ustaw|^Załącznik|^Lp\.|^Objaśnienia|^\s*$")
ODWROCONE = re.compile(r"^\d{2}\.\d{2}[–-]\d{2}\.\d{2}$")   # ślad załącznika 4

ZALACZNIKI = [
    ("GATUNKI ZWIERZĄT OBJĘTYCH OCHRONĄ ŚCISŁĄ", "1", "scisla"),
    ("GATUNKI ZWIERZĄT OBJĘTYCH OCHRONĄ CZĘŚCIOWĄ, KTÓRE MOGĄ BYĆ POZYSKIWANE",
     "3", "czesciowa_pozyskiwanie"),
    ("GATUNKI ZWIERZĄT OBJĘTYCH OCHRONĄ CZĘŚCIOWĄ", "2", "czesciowa"),
]

# Pięć pozycji łamie się w PDF-ie na kilka linii (pozycje zbiorcze i nazwy
# z synonimami). Przepisane ręcznie ze stron 5, 24, 28, 32 i 40.
UZUPELNIENIA = [
    {"ZALACZNIK": "1", "LP": "13", "GROMADA": "SSAKI (MAMMALIA)",
     "RZAD": "WALENIE (CETACEA)", "NAZWA_PL": "WALENIE - pozostałe gatunki",
     "NAZWA_LAT": "", "SYNONIM": "", "OCHRONA": "scisla",
     "OCHRONA_CZYNNA": "", "ADNOTACJE": "1",
     "WERYFIKACJA": "pozycja zbiorcza, brak nazwy naukowej w akcie"},
    {"ZALACZNIK": "1", "LP": "479", "GROMADA": "PTAKI (AVES)",
     "RZAD": "inne gatunki ptaków",
     "NAZWA_PL": "Pozostałe gatunki ptaków (inne niż: gatunki łowne, "
                 "gatunki objęte ochroną częściową oraz wymienione "
                 "w lp. 52-478 gatunki objęte ochroną ścisłą) występujące "
                 "naturalnie na terytorium państw Unii Europejskiej, "
                 "przebywające na terytorium Rzeczypospolitej Polskiej",
     "NAZWA_LAT": "", "SYNONIM": "", "OCHRONA": "scisla",
     "OCHRONA_CZYNNA": "", "ADNOTACJE": "",
     "WERYFIKACJA": "pozycja zbiorcza; osobny reżim zakazów wg § 8 ust. 1"},
    {"ZALACZNIK": "1", "LP": "567", "GROMADA": "OWADY (INSECTA)",
     "RZAD": "MOTYLE (LEPIDOPTERA)", "NAZWA_PL": "modraszek nausitous",
     "NAZWA_LAT": "Phengaris nausithous", "SYNONIM": "Maculinea nausithous",
     "OCHRONA": "scisla", "OCHRONA_CZYNNA": "1", "ADNOTACJE": "1",
     "WERYFIKACJA": "wiersz łamany w PDF, przepisany ręcznie"},
    {"ZALACZNIK": "2", "LP": "52",
     "GROMADA": "RYBY PROMIENIOPŁETWE (ACTINOPTERYGII)",
     "RZAD": "KARPIOKSZTAŁTNE (CYPRINIFORMES)", "NAZWA_PL": "brzanka",
     "NAZWA_LAT": "Barbus peloponnesius",
     "SYNONIM": "B. carpthicus, B. meridionalis",
     "OCHRONA": "czesciowa", "OCHRONA_CZYNNA": "", "ADNOTACJE": "",
     "WERYFIKACJA": "wiersz łamany w PDF; pisownia synonimu jak w akcie "
                    "(carpthicus)"},
    {"ZALACZNIK": "2", "LP": "211", "GROMADA": "", "RZAD": "inne gatunki",
     "NAZWA_PL": "gatunki wymienione w załączniku IV do dyrektywy Rady "
                 "92/43/EWG z dnia 21 maja 1992 r. w sprawie ochrony siedlisk "
                 "przyrodniczych oraz dzikiej fauny i flory (Dz. Urz. WE L 206 "
                 "z 22.07.1992, str. 7, z późn. zm.) - inne niż gatunki objęte "
                 "ochroną ścisłą na podstawie załącznika nr 1 do "
                 "rozporządzenia oraz inne niż gatunki objęte ochroną "
                 "częściową wymienione w lp. 1-210",
     "NAZWA_LAT": "", "SYNONIM": "", "OCHRONA": "czesciowa",
     "OCHRONA_CZYNNA": "", "ADNOTACJE": "",
     "WERYFIKACJA": "pozycja zbiorcza; osobny reżim zakazów wg § 8 ust. 2"},
]

POLA = ["ZALACZNIK", "LP", "GROMADA", "RZAD", "NAZWA_PL", "NAZWA_LAT",
        "SYNONIM", "OCHRONA", "OCHRONA_CZYNNA", "ADNOTACJE", "ZRODLO",
        "WERYFIKACJA"]


def linie_strony(strona):
    """Zwraca [(tekst, czy_pogrubiona)] — słowa grupowane po wysokości."""
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


def main(sciezka):
    wiersze, watpliwe = [], []
    zal = ochrona = None
    gromada = rzad = ""

    with pdfplumber.open(sciezka) as pdf:
        for nr, strona in enumerate(pdf.pages, 1):
            for linia, pogrubiona in linie_strony(strona):
                if linia.startswith("GATUNKI ZWIERZĄT WYMAGAJĄCYCH"):
                    zal = None                 # zaczyna się załącznik 4
                    continue
                plaska = re.sub(r"\s+", "", linia)
                for tytul, z, o in ZALACZNIKI:
                    if plaska.startswith(re.sub(r"\s+", "", tytul)):
                        zal, ochrona = z, o
                        gromada = rzad = ""
                        break
                if zal is None or STOPKA.match(linia) or ODWROCONE.match(linia):
                    continue

                # nagłówek systematyczny: WIELKIE LITERY
                if linia.isupper() and not re.match(r"^\d", linia):
                    czlony = linia.split()
                    if len(czlony) < 2:
                        continue
                    pl, lat = " ".join(czlony[:-1]), czlony[-1]
                    if pogrubiona:
                        gromada, rzad = "%s (%s)" % (pl, lat), ""
                    else:
                        rzad = "%s (%s)" % (pl, lat)
                    continue

                czynna = bool(re.search(r"\sx$", linia))
                robocza = re.sub(r"\sx$", "", linia).strip()
                syn = ""
                s = re.search(r"\s(\([A-Z][^)]*\))\s*$", robocza)
                if s:
                    syn = s.group(1).strip("()")
                    robocza = robocza[:s.start()].strip()
                if zal == "3":          # po nazwie idzie opis pozyskiwania
                    robocza = re.sub(
                        r"^(\d+\.\s+.+?\s+[A-ZŚŻŹĆŃŁÓĄĘ][a-zżźćńłóąęśë.\-]+"
                        r"\s+[a-zżźćńłóąęśë.\-]+)\s+.*$", r"\1", robocza)

                m = WIERSZ.match(robocza)
                if not m:
                    if re.match(r"^\d+\.", robocza):
                        watpliwe.append("s.%d: %s" % (nr, linia))
                    continue

                lp, nazwa_pl, nazwa_lat = m.groups()
                adn = "".join(sorted(set(ADNOTACJE.findall(nazwa_pl))))
                nazwa_pl = ADNOTACJE.sub("", nazwa_pl).replace("  ", " ").strip()
                wiersze.append({
                    "ZALACZNIK": zal, "LP": lp, "GROMADA": gromada,
                    "RZAD": rzad, "NAZWA_PL": nazwa_pl,
                    "NAZWA_LAT": nazwa_lat.strip(), "SYNONIM": syn,
                    "OCHRONA": ochrona, "OCHRONA_CZYNNA": "1" if czynna else "",
                    "ADNOTACJE": adn, "ZRODLO": "Dz.U. 2016 poz. 2183",
                    "WERYFIKACJA": "",
                })

    for u in UZUPELNIENIA:
        u = dict(u)
        u["ZRODLO"] = "Dz.U. 2016 poz. 2183"
        wiersze.append(u)
    wiersze.sort(key=lambda r: (r["ZALACZNIK"], int(r["LP"])))

    with open("ochrona_zwierzat_2016-2183.csv", "w", encoding="utf-8",
              newline="") as f:
        p = csv.DictWriter(f, fieldnames=POLA, delimiter=";")
        p.writeheader()
        p.writerows(wiersze)

    if watpliwe:
        with open("ochrona_zwierzat_do_recznego_sprawdzenia.txt", "w",
                  encoding="utf-8") as f:
            f.write("\n".join(watpliwe))

    for z in ("1", "2", "3"):
        lp = [int(x["LP"]) for x in wiersze if x["ZALACZNIK"] == z]
        if lp:
            braki = [i for i in range(1, max(lp) + 1) if i not in set(lp)]
            print("Załącznik %s: %d wierszy, ostatnia lp. %d, braki: %s"
                  % (z, len(lp), max(lp), braki or "brak"))
    print("Ochrona czynna: %d" % sum(1 for x in wiersze if x["OCHRONA_CZYNNA"]))
    print("Gromad rozpoznanych: %d"
          % len({x["GROMADA"] for x in wiersze if x["GROMADA"]}))
    print("Wierszy nieodczytanych automatycznie: %d (uzupełnione ręcznie: %d)"
          % (len(watpliwe), len(UZUPELNIENIA)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "D20162183.pdf")
