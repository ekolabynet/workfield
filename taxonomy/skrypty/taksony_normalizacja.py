# -*- coding: utf-8 -*-
"""
taksony_normalizacja.py — rozbiór nazwy roślinnej wpisanej w terenie.

Bez zależności zewnętrznych (sama biblioteka standardowa). Uruchomienie bez
argumentów odpala autotest na 20 realnych przypadkach:

    python3 taksony_normalizacja.py

Zasada: NIC NIE JEST KASOWANE PO CICHU. Każdy zdjęty fragment (autorstwo,
kultywar, "cf.", "sp.") ląduje we własnym polu wyniku. Surowy ciąg zostaje.
To ta sama reguła co przy parserze kodów gatunków z 21.08: źródłem prawdy
jest to, co wpisał człowiek, wiersze są WYPROWADZANE.
"""

import re
import unicodedata

# fragmenty, które nie są nazwą, a bywają wpisane w to samo pole
KWALIFIKATORY = r"(?:cf|aff|indet|ind|nov|prox|inc|stet|sensu\s+auct|nom\.\s*\w+)"
RANGI = {
    "ssp": "subsp.", "ssp.": "subsp.", "subsp": "subsp.", "subsp.": "subsp.",
    "var": "var.", "var.": "var.", "v.": "var.",
    "f.": "f.", "fo.": "f.", "forma": "f.",
}
CUDZYSLOWY = {
    "‘": "'", "’": "'", "‚": "'", "‛": "'",
    "“": '"', "”": '"', "„": '"', "«": '"', "»": '"',
}
SPACJE = {" ": " ", " ": " ", " ": " ", " ": " ", "\t": " "}


def _bez_diakrytykow(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s)
                   if not unicodedata.combining(c))


def rozbierz(surowy):
    """Zwraca słownik: surowy, kanoniczna, rodzaj, epitet, infra, ranga,
    odmiana, handlowa, hybryda, kwalifikator, klucz, uwagi."""
    w = {
        "surowy": surowy, "kanoniczna": "", "rodzaj": "", "epitet": "",
        "infra": "", "ranga": "", "odmiana": "", "handlowa": "",
        "hybryda": 0, "kwalifikator": "", "klucz": "", "uwagi": [],
    }
    s = surowy or ""

    # 1. białe znaki — NBSP z Worda i spacja doklejana przez Gboard
    for zly, dobry in SPACJE.items():
        s = s.replace(zly, dobry)
    s = re.sub(r"\s+", " ", s).strip()
    if not s:
        return w

    # 2. cudzysłowy typograficzne -> proste, potem wyłuskanie kultywaru
    s = "".join(CUDZYSLOWY.get(c, c) for c in s)
    m = re.search(r"['\"]([^'\"]{2,40})['\"]", s)
    if m:
        w["odmiana"] = m.group(1).strip()
        s = (s[:m.start()] + " " + s[m.end():])
    else:
        m = re.search(r"\bcv\.?\s+([A-Z][\w' -]{1,39})$", s)
        if m:
            w["odmiana"] = m.group(1).strip()
            s = s[:m.start()]

    # 3. znaki handlowe i oznaczenia hodowlane
    if re.search(r"[®™]|\bPBR\b|\bPP\s*#?\d+", s):
        w["uwagi"].append("nazwa handlowa/ochrona odmiany")
    s = re.sub(r"[®™©]|\(\s*[RrCc]\s*\)|PP\s*#?\d+|\bPBR\b", " ", s)

    # 4. mieszaniec: x / X / × ujednolicone; litera x w środku słowa NIE liczy się
    if re.search(r"(?<![A-Za-z])[x×✕✖](?![A-Za-z])", s) or "×" in s:
        w["hybryda"] = 1
    s = re.sub(r"(?<![A-Za-z])[x×✕✖](?![A-Za-z])", " ", s)
    s = re.sub(r"×", " ", s)

    # 5. kwalifikator niepewności — zapamiętany, nie skasowany
    k = re.findall(rf"\b{KWALIFIKATORY}\.?", s, flags=re.I)
    if k:
        w["kwalifikator"] = k[0].rstrip(".").lower()
        s = re.sub(rf"\b{KWALIFIKATORY}\.?", " ", s, flags=re.I)

    # 6. "sp." / "spp." -> oznaczenie rangi rodzajowej
    if re.search(r"\bsp{1,2}\.?\s*$", s, flags=re.I):
        w["ranga"] = "GENUS"
        s = re.sub(r"\bsp{1,2}\.?\s*$", " ", s, flags=re.I)

    # 7. autorstwo w nawiasach + resztki
    s = re.sub(r"\([^)]*\)", " ", s)
    s = re.sub(r"\b(1[6-9]\d{2}|20\d{2})\b", " ", s)
    s = re.sub(r"[\[\]?;,]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()

    # 8. rozbiór na człony
    czlony = s.split(" ")
    if not czlony or not czlony[0]:
        return w
    w["rodzaj"] = czlony[0].capitalize()
    reszta = czlony[1:]

    if reszta:
        pierwszy = reszta[0]
        # epitet gatunkowy = człon z małej litery, bez kropki, dłuższy niż 2 znaki
        if pierwszy.lower() in RANGI or pierwszy.endswith("."):
            pass  # od razu ranga wewnątrzgatunkowa albo autor — nie epitet
        elif pierwszy[:1].isupper():
            w["uwagi"].append("drugi człon z wielkiej litery — autor albo nazwa handlowa")
        else:
            w["epitet"] = pierwszy.lower()
            reszta = reszta[1:]

    # ranga wewnątrzgatunkowa
    for i, c in enumerate(reszta):
        if c.lower() in RANGI and i + 1 < len(reszta):
            w["ranga"] = {"subsp.": "SUBSPECIES", "var.": "VARIETY",
                          "f.": "FORM"}[RANGI[c.lower()]]
            w["infra"] = reszta[i + 1].lower().strip(".")
            break

    # 9. nazwa kanoniczna i klucz
    czesci = [w["rodzaj"]]
    if w["epitet"]:
        czesci.append(w["epitet"])
    if w["infra"]:
        czesci.append({"SUBSPECIES": "subsp.", "VARIETY": "var.",
                       "FORM": "f."}[w["ranga"]])
        czesci.append(w["infra"])
    w["kanoniczna"] = " ".join(czesci)
    if not w["ranga"]:
        w["ranga"] = "SPECIES" if w["epitet"] else "GENUS"
    if w["odmiana"] and w["ranga"] in ("SPECIES", "GENUS"):
        w["ranga"] = "CULTIVAR" if w["epitet"] else "GENUS"

    w["klucz"] = _bez_diakrytykow(w["kanoniczna"].lower()).replace(".", "").strip()
    return w


def do_wyswietlenia(w):
    """Nazwa złożona z powrotem — tak, jak ma stanąć w formularzu i na wydruku."""
    n = w["kanoniczna"]
    if w["hybryda"] and w["epitet"]:
        n = n.replace(" ", " × ", 1)
    if w["kwalifikator"] == "cf" and w["epitet"]:
        n = n.replace(" ", " cf. ", 1)
    if w["ranga"] == "GENUS" and not w["epitet"]:
        n += " sp."
    if w["odmiana"]:
        n += " '%s'" % w["odmiana"]
    return n


PRZYPADKI = [
    "Tilia cordata",
    "Tilia cordata Mill.",
    "Tilia cordata 'Greenspire'",
    "Thuja occidentalis „Smaragd”",
    "Acer platanoides cv. Royal Red",
    "Acer platanoides 'Globosum' ",
    "Quercus cf. robur",
    "Crataegus sp.",
    "Salix × fragilis",
    "Salix x fragilis L.",
    "Betula pendula Roth",
    "Euonymus fortunei 'Emerald Gaiety'",
    "Thuja plicata 'Green Giant'®",
    "Populus nigra 'Italica'",
    "Festuca rubra subsp. rubra",
    "Festuca rubra ssp. commutata",
    "Prunus serotina",
    "Lolium perenne ",
    "Buxus sempervirens",
    "Platanus × hispanica Mill. ex Münchh.",
]

if __name__ == "__main__":
    szer = max(len(p) for p in PRZYPADKI)
    print("%-*s | %-28s | %-9s | %-14s | h | kw" % (szer, "WEJŚCIE", "KANONICZNA", "RANGA", "ODMIANA"))
    print("-" * (szer + 70))
    for p in PRZYPADKI:
        w = rozbierz(p)
        print("%-*s | %-28s | %-9s | %-14s | %d | %s"
              % (szer, p, w["kanoniczna"], w["ranga"], w["odmiana"],
                 w["hybryda"], w["kwalifikator"] or "-"))
    print()
    for p in PRZYPADKI[:9]:
        print("  %-40s -> %s" % (p, do_wyswietlenia(rozbierz(p))))
