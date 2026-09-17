#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sklada `plugins.json` dla menedzera wtyczek QFielda.

PO CO. Menedzer ma gotowa zakladke "Available Plugins", ktora czyta liste
z `REMOTE_PLUGINS_URL` — jednego adresu wpisanego na stale w
`qfpluginmodel.cpp:29`. Zamiast pisac wlasny ekran, podmieniamy adres na
wlasny spis i dostajemy przegladarke z instalacja jednym tapnieciem.

SCALONA LISTA. Spis zawiera wtyczki WorkField ORAZ wpisy z qfield.org —
zeby jedna zakladka pokazywala wszystko. Zrodlo widac po `author`
i `homepage`.

SLABOSC, ktora trzeba znac: wpisy QFielda sa MIGAWKA z chwili generowania.
Nowa wtyczka od OPENGIS.ch pojawi sie dopiero po naszym kolejnym wydaniu.
Przy ich tempie to bez znaczenia, ale nie jest to zywe zrodlo.

`uuid` to NAZWA KATALOGU wtyczki po rozpakowaniu — `workfield-gugik`, nie
`gugik`. Po niej menedzer parzy zainstalowana ze zdalna i pokazuje
"aktualizuj" zamiast "zainstaluj" (qfpluginmodel.cpp:393, pierwszy
argument konstruktora to `pluginDir.fileName()`). Zly `uuid` = wtyczka
widoczna DWA RAZY.

    python3 zbuduj_spis_wtyczek.py /sciezka/do/repo > plugins.json
"""
import json
import os
import re
import subprocess
import sys
import urllib.request
import zipfile

REPO = sys.argv[1] if len(sys.argv) > 1 else "/DATA/SOFT/GIS/QFIELD_Pro/QField"
GALAZ = "plugins"
RAW = "https://raw.githubusercontent.com/ekolabynet/workfield/plugins/%s"
QFIELD = "https://qfield.org/plugins.json"


def zipy_na_galezi():
    """Nazwy zipow na galezi `plugins`, prosto z gita — bez przelaczania."""
    out = subprocess.run(["git", "-C", REPO, "ls-tree", "--name-only", GALAZ],
                         capture_output=True, text=True, check=True).stdout
    return [n for n in out.splitlines() if n.endswith(".zip")]


def wersja_klucz(w):
    """'0.11' > '0.9' — porownanie liczbowe, nie tekstowe."""
    return tuple(int(x) if x.isdigit() else 0 for x in w.split("."))


def najnowsze(nazwy):
    """Po jednej, NAJNOWSZEJ wersji kazdej wtyczki.

    Na galezi leza wszystkie wydania — dziewiec Pl@ntNetow, trzy Konsole.
    Lista z wszystkimi bylaby nie do uzycia.
    """
    best = {}
    for n in nazwy:
        m = re.match(r"(workfield-[a-z0-9_]+)-v([\d.]+)\.zip$", n)
        if not m:
            continue
        rdzen, wer = m.group(1), m.group(2)
        if rdzen not in best or wersja_klucz(wer) > wersja_klucz(best[rdzen][1]):
            best[rdzen] = (n, wer)
    return best


def metadane(nazwa_zipa):
    """`metadata.txt` ze srodka zipa, prosto z gita."""
    dane = subprocess.run(["git", "-C", REPO, "show", "%s:%s" % (GALAZ, nazwa_zipa)],
                          capture_output=True, check=True).stdout
    tmp = "/tmp/_spis_wtyczek.zip"
    with open(tmp, "wb") as f:
        f.write(dane)
    w = {}
    with zipfile.ZipFile(tmp) as z:
        nazwa = next((n for n in z.namelist() if n.endswith("metadata.txt")), None)
        if not nazwa:
            return w
        for linia in z.read(nazwa).decode("utf-8").splitlines():
            if "=" in linia and not linia.startswith("["):
                k, v = linia.split("=", 1)
                w[k.strip()] = v.strip()
    os.remove(tmp)
    return w


def wpisy_qfield():
    try:
        with urllib.request.urlopen(QFIELD, timeout=15) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        print("# nie pobralem listy QFielda: %s" % e, file=sys.stderr)
        return []


spis = []
for rdzen, (plik, wer) in sorted(najnowsze(zipy_na_galezi()).items()):
    m = metadane(plik)
    spis.append({
        # uuid = nazwa katalogu po rozpakowaniu, inaczej wtyczka dubluje sie
        "uuid": rdzen,
        "name": m.get("name", rdzen),
        "description": m.get("description", ""),
        "version": m.get("version", wer),
        "download": RAW % plik,
        # Ikona MUSI byc dostepna z sieci — menedzer pokazuje ja PRZED
        # instalacja, wiec ta w zipie jest za pozno. Leza na galezi obok
        # zipow, pomaranczowe: czarne (`fill="#000"`) byly na ciemnym tle
        # menedzera niewidzialne.
        "icon": RAW % ("icon_%s.svg" % rdzen.replace("workfield-", "")),
        "homepage": m.get("homepage", "https://github.com/ekolabynet/workfield"),
        "author": m.get("author", "ekolabynet"),
    })
    print("# %-22s v%-6s %s" % (rdzen, wer, plik), file=sys.stderr)

obce = wpisy_qfield()
nasze_uuid = {w["uuid"] for w in spis}
spis += [w for w in obce if w.get("uuid") not in nasze_uuid]
print("# WorkField: %d, QField: %d, razem: %d"
      % (len(nasze_uuid), len(spis) - len(nasze_uuid), len(spis)), file=sys.stderr)

json.dump(spis, sys.stdout, ensure_ascii=False, indent=2)
print()
