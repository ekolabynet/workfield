#!/usr/bin/env python3
"""
WorkFieldGIS — arkusze ortofotomapy z dowolnego folderu -> JEDEN GeoPackage
z kaflami na telefon (QField czyta go bez internetu).

    python3 orto_do_gpkg.py "/folder/z/arkuszami"              # PRÓBA: pokaże naloty
    python3 orto_do_gpkg.py "/folder/z/arkuszami" --zapisz     # składa wybrany nalot

opcje:
    --grupa N        który nalot złożyć (numer z tabeli w próbie);
                     domyślnie: NAJNOWSZY nalot RGB
    --wynik PLIK     plik wynikowy (domyślnie orto_<kolor>_<rok>.gpkg w tym folderze)
    --jakosc Q       jakość JPEG kafli, 1–100 (domyślnie 85)

Jak dobiera arkusze:
  * czyta opisy pobieracza GUGiK (pobieracz_ortofoto_*.txt): kolor (RGB/CIR),
    datę nalotu, piksel, układ;
  * a z każdego arkusza (gdalinfo): układ EPSG, kanały, piksel;
  * arkusz BEZ opisu dostaje opis serii, jeśli wszystkie opisane arkusze tej
    samej serii (pierwsza liczba w nazwie, np. „83855_”) mają ten sam opis;
  * dzieli arkusze na NALOTY: kolor + data + piksel + układ. Jeden plik = jeden
    nalot — kolory CIR i RGB, różne lata ani różne układy się NIE mieszają.

STOP, gdy: w wybranym nalocie to samo godło jest dwa razy, arkusze mają różny
układ albo piksel, plik wynikowy już istnieje, brak miejsca na dysku.

Oryginalne arkusze NIE są ruszane. Kopiujemy, nie przenosimy.
Wynik: <wynik>.gpkg + <wynik>.txt (md5, wymiary, lista arkuszy).
"""
import csv, glob, hashlib, json, os, re, shutil, sqlite3, subprocess, sys, time

ROZSZERZENIA = (".tif", ".tiff", ".jp2")


def uruchom(pol, pokaz=False):
    if pokaz:
        print("   $ " + " ".join(('"%s"' % p) if " " in p else p for p in pol))
        w = subprocess.run(pol)
        if w.returncode != 0:
            raise SystemExit("STOP: polecenie zakończone kodem %d" % w.returncode)
        return ""
    w = subprocess.run(pol, capture_output=True, text=True)
    if w.returncode != 0:
        raise SystemExit("STOP: %s\n%s" % (" ".join(pol), w.stderr.strip()))
    return w.stdout


def info(sciezka):
    return json.loads(uruchom(["gdalinfo", "-json", "--config", "GTIFF_SRS_SOURCE", "EPSG", sciezka]))


def epsg_z(inf):
    wkt = inf.get("coordinateSystem", {}).get("wkt", "")
    kody = [k.split("]")[0] for k in wkt.split('ID["EPSG",')[1:]]
    return int(kody[-1]) if kody else None


def md5(sciezka):
    h = hashlib.md5()
    with open(sciezka, "rb") as f:
        for k in iter(lambda: f.read(1 << 20), b""):
            h.update(k)
    return h.hexdigest()


def opcja(nazwa, domyslna=None):
    return sys.argv[sys.argv.index(nazwa) + 1] if nazwa in sys.argv else domyslna


def seria(nazwa_pliku):
    m = re.match(r"^(\d+)_", nazwa_pliku)
    return m.group(1) if m else None


def godlo_z_nazwy(nazwa_pliku):
    # 83855_1565626_N-33-108-C-b-2-2.tif -> N-33-108-C-b-2-2 ; 64858_335464_6.194.18.4.tif -> 6.194.18.4
    rdzen = os.path.splitext(nazwa_pliku)[0]
    m = re.match(r"^\d+_\d+_(.+)$", rdzen)
    return m.group(1) if m else rdzen


def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("--"):
        print(__doc__)
        sys.exit(2)
    katalog = os.path.abspath(sys.argv[1])
    zapisz = "--zapisz" in sys.argv
    jakosc = int(opcja("--jakosc", "85"))
    print("== folder: %s" % katalog)

    arkusze = sorted(f for f in os.listdir(katalog)
                     if f.lower().endswith(ROZSZERZENIA) and os.path.isfile(os.path.join(katalog, f)))
    if not arkusze:
        raise SystemExit("STOP: w folderze nie ma arkuszy (%s)." % ", ".join(ROZSZERZENIA))

    # ── opisy pobieracza ───────────────────────────────────────────────
    opisy = {}
    for txt in glob.glob(os.path.join(katalog, "pobieracz_ortofoto_*.txt")):
        with open(txt, encoding="utf-8") as f:
            for w in csv.DictReader(f):
                if w.get("nazwa_pliku"):
                    opisy[w["nazwa_pliku"]] = w

    # ── każdy arkusz ───────────────────────────────────────────────────
    print("== sprawdzam %d arkuszy (gdalinfo)…" % len(arkusze))
    dane = {}
    for a in arkusze:
        inf = info(os.path.join(katalog, a))
        gt = inf.get("geoTransform") or [0, 0, 0, 0, 0, 0]
        dane[a] = {
            "epsg": epsg_z(inf),
            "kanaly": len(inf.get("bands", [])),
            "typy": {b.get("type") for b in inf.get("bands", [])},
            "piksel": round(abs(gt[1]), 3),
            "rozmiar": os.path.getsize(os.path.join(katalog, a)),
            "godlo": godlo_z_nazwy(a),
            "kolor": None, "data": None, "skad": "brak opisu",
        }
        o = opisy.get(a)
        if o:
            dane[a].update(kolor=o.get("kolor"), data=o.get("aktualnosc"), skad="pobieracz")
            if o.get("godlo"):
                dane[a]["godlo"] = o["godlo"]

    # arkusz bez opisu dziedziczy opis serii, jeśli seria jest jednolita
    serie = {}
    for a, d in dane.items():
        if d["skad"] == "pobieracz" and seria(a):
            serie.setdefault(seria(a), set()).add((d["kolor"], d["data"]))
    for a, d in dane.items():
        if d["skad"] != "pobieracz":
            s = serie.get(seria(a))
            if s and len(s) == 1:
                d["kolor"], d["data"] = next(iter(s))
                d["skad"] = "seria %s" % seria(a)

    # ── naloty ─────────────────────────────────────────────────────────
    grupy = {}
    for a, d in dane.items():
        klucz = (d["kolor"] or "?", d["data"] or "?", d["piksel"], d["epsg"])
        grupy.setdefault(klucz, []).append(a)
    lista = sorted(grupy.items(), key=lambda kv: (kv[0][1], kv[0][0]), reverse=True)

    print("\n   nr  kolor  nalot        piksel  układ       arkuszy   rozmiar")
    for i, (k, pl) in enumerate(lista, 1):
        roz = sum(dane[a]["rozmiar"] for a in pl)
        print("   %2d  %-5s  %-10s  %5.2f m  EPSG:%-6s  %7d  %8s"
              % (i, k[0], k[1], k[2], k[3], len(pl),
                 "%.2f GB" % (roz / 1e9) if roz >= 1e9 else "%.0f MB" % (roz / 1e6)))
    bez = [a for a, d in dane.items() if d["skad"] == "brak opisu"]
    if bez:
        print("   (bez opisu i bez jednolitej serii: %d — kolor/data „?”)" % len(bez))
    if any(d["skad"].startswith("seria") for d in dane.values()):
        n = sum(1 for d in dane.values() if d["skad"].startswith("seria"))
        print("   (%d arkuszy bez opisu dostało opis swojej serii)" % n)

    # ── wybór ──────────────────────────────────────────────────────────
    if opcja("--grupa"):
        nr = int(opcja("--grupa"))
        if not 1 <= nr <= len(lista):
            raise SystemExit("STOP: nie ma grupy nr %d." % nr)
        klucz, wybrane = lista[nr - 1]
    else:
        rgb = [(k, pl) for k, pl in lista if k[0] == "RGB" and k[1] != "?"]
        if not rgb:
            raise SystemExit("\nSTOP: nie ma opisanego nalotu RGB. Wybierz nalot: --grupa N")
        najnowsza = max(k[1] for k, _ in rgb)
        kandydaci = [(k, pl) for k, pl in rgb if k[1] == najnowsza]
        if len(kandydaci) > 1:
            raise SystemExit("\nSTOP: najnowszy nalot RGB (%s) ma %d wariantów (piksel/układ). "
                             "Wybierz: --grupa N" % (najnowsza, len(kandydaci)))
        klucz, wybrane = kandydaci[0]
    kolor, nalot, piksel, epsg = klucz
    wybrane = sorted(wybrane)
    print("\n== wybrany nalot: %s %s, piksel %.2f m, EPSG:%s — %d arkuszy"
          % (kolor, nalot, piksel, epsg, len(wybrane)))

    # ── kontrole wybranych ─────────────────────────────────────────────
    bledy = []
    godla = {}
    for a in wybrane:
        godla.setdefault(dane[a]["godlo"], []).append(a)
        d = dane[a]
        if d["kanaly"] != 3 or d["typy"] != {"Byte"}:
            bledy.append("%s: kanałów %d, typy %s (oczekiwane 3 × Byte)" % (a, d["kanaly"], d["typy"]))
    for g, pl in godla.items():
        if len(pl) > 1:
            bledy.append("godło %s jest %d razy: %s" % (g, len(pl), ", ".join(pl)))
    if epsg is None:
        bledy.append("arkusze bez rozpoznanego układu EPSG")
    if bledy:
        print("\n".join("   " + b for b in bledy))
        raise SystemExit("STOP: wybrany nalot nie nadaje się do sklejenia. Nic nie zapisano.")

    rok = nalot[:4] if nalot != "?" else "bezdaty"
    nazwa = re.sub(r"[^a-z0-9_]", "_", ("orto_%s_%s" % (kolor, rok)).lower())
    wynik = os.path.abspath(opcja("--wynik", os.path.join(katalog, nazwa + ".gpkg")))
    nazwa = re.sub(r"[^A-Za-z0-9_]", "_", os.path.splitext(os.path.basename(wynik))[0])
    robocze = os.path.join(os.path.dirname(wynik), "_" + nazwa + "_robocze")
    rozmiar = sum(dane[a]["rozmiar"] for a in wybrane)
    print("== wynik: %s" % wynik)
    if os.path.exists(wynik):
        raise SystemExit("JUŻ JEST: %s — nic nie robię. Nie nadpisuję gotowego pliku." % wynik)
    wolne = shutil.disk_usage(os.path.dirname(wynik)).free
    print("== miejsce: wolne %.1f GB, potrzeba do ~%.1f GB" % (wolne / 1e9, rozmiar * 1.6 / 1e9))
    if wolne < rozmiar * 1.6:
        raise SystemExit("STOP: za mało miejsca na dysku.")

    if not zapisz:
        print("\nPRÓBA — nic nie zapisano. Wykonanie: dodaj --zapisz")
        return

    t0 = time.time()
    if os.path.exists(robocze):
        shutil.rmtree(robocze)
    os.makedirs(robocze)
    lista_pl = os.path.join(robocze, "arkusze.txt")
    with open(lista_pl, "w", encoding="utf-8") as f:
        f.write("\n".join(os.path.join(katalog, a) for a in wybrane) + "\n")
    vrt = os.path.join(robocze, nazwa + ".vrt")
    czesciowy = os.path.join(robocze, nazwa + ".gpkg")  # w katalogu roboczym = jeszcze niegotowy
    cfg = ["--config", "GDAL_NUM_THREADS", "ALL_CPUS", "--config", "GDAL_CACHEMAX", "2048",
           "--config", "GTIFF_SRS_SOURCE", "EPSG"]

    print("\n== 1/4 mozaika wirtualna")
    uruchom(["gdalbuildvrt", "-q", "-addalpha", "-input_file_list", lista_pl, vrt], pokaz=True)
    szer, wys = info(vrt)["size"]
    print("   mozaika: %d x %d px" % (szer, wys))

    print("\n== 2/4 GeoPackage z kaflami (najdłuższy krok)")
    uruchom(["gdal_translate", "-of", "GPKG"] + cfg +
            ["-co", "TILE_FORMAT=AUTO", "-co", "QUALITY=%d" % jakosc,
             "-co", "RASTER_TABLE=" + nazwa,
             "-co", "RASTER_IDENTIFIER=Ortofotomapa %s %s, piksel %.2f m" % (kolor, nalot, piksel),
             vrt, czesciowy], pokaz=True)

    print("\n== 3/4 podglądy do oddalania")
    poziomy, f = [], 2
    while max(szer, wys) / f >= 256:
        poziomy.append(str(f))
        f *= 2
    if poziomy:
        uruchom(["gdaladdo", "-r", "average"] + cfg + [czesciowy] + poziomy, pokaz=True)

    print("\n== 4/4 kontrola wyniku")
    inf_w = info(czesciowy)
    bl = []
    if inf_w["size"] != [szer, wys]:
        bl.append("wymiary %s, mozaika %s" % (inf_w["size"], [szer, wys]))
    if epsg_z(inf_w) != epsg:
        bl.append("układ %s, oczekiwany %s" % (epsg_z(inf_w), epsg))
    podglady = len(inf_w["bands"][0].get("overviews", []))
    if podglady != len(poziomy):
        bl.append("podglądów %d, oczekiwane %d" % (podglady, len(poziomy)))
    with sqlite3.connect(czesciowy) as db:
        qc = db.execute("PRAGMA quick_check").fetchone()[0]
        kafle = db.execute('SELECT count(*) FROM "%s"' % nazwa).fetchone()[0]
    if qc != "ok":
        bl.append("quick_check: %s" % qc)
    if kafle == 0:
        bl.append("brak kafli")
    if bl:
        print("\n".join("   " + b for b in bl))
        raise SystemExit("STOP: wynik nie przeszedł kontroli. Zostaje w %s" % robocze)

    os.replace(czesciowy, wynik)
    roz_w = os.path.getsize(wynik)
    suma = md5(wynik)
    with open(os.path.splitext(wynik)[0] + ".txt", "w", encoding="utf-8") as f:
        f.write("plik: %s\nmd5: %s\nrozmiar: %d B\nwymiary: %d x %d px, EPSG:%s, piksel %.2f m\n"
                "nalot: %s, %s\npodglądy: %s\nkafli: %d\nźródło: %s\nutworzono: %s\n\narkusze (%d):\n%s\n"
                % (os.path.basename(wynik), suma, roz_w, szer, wys, epsg, piksel, nalot, kolor,
                   ",".join(poziomy), kafle, katalog, time.strftime("%Y-%m-%d %H:%M"), len(wybrane),
                   "\n".join("%s  (%s)" % (a, dane[a]["skad"]) for a in wybrane)))
    shutil.rmtree(robocze)
    print("   wymiary %d x %d, EPSG:%s, podglądów %d, quick_check ok, kafli %d"
          % (szer, wys, epsg, podglady, kafle))
    print("\nGOTOWE: %s" % wynik)
    print("   rozmiar: %.2f GB (arkusze: %.2f GB)" % (roz_w / 1e9, rozmiar / 1e9))
    print("   md5: %s" % suma)
    print("   czas: %d min" % ((time.time() - t0) // 60))


if __name__ == "__main__":
    main()
