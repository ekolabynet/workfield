#!/usr/bin/env python3
"""
WorkFieldGIS — projekt QGIS -> samowystarczalna WERSJA TERENOWA (na telefon).

    python3 projekt_na_teren.py "/sciezka/do/Projekt.qgz"              # PRÓBA
    python3 projekt_na_teren.py "/sciezka/do/Projekt.qgz" --zapisz
    opcje:  --do KATALOG          gdzie złożyć wersję terenową
                                  (domyślnie ~/WorkField/teren/<katalog projektu>_<data>)
            --nazwa "NAZWA"       nazwa katalogu na telefonie
                                  (domyślnie: nazwa katalogu projektu)
            --mimo-brakow         złóż mimo warstw, których plików nie ma
                                  (te warstwy będą na telefonie puste)

ORYGINAŁ ZOSTAJE. Nic w katalogu projektu nie jest zmieniane — wersja terenowa
powstaje w OSOBNYM katalogu, z kopii plików. Kopiujemy, nie przenosimy.

Co robi z każdą warstwą (patrzy na dostawcę i plik):
  plik .gpkg (wektor/raster)  -> kopia pliku (jedna kopia, choćby czytało go 10 warstw)
  plik .shp                    -> kopia z plikami towarzyszącymi (.shx .dbf .prj .cpg…)
  raster (.tif .jp2 …)         -> kopia pliku
  inny wektor (.vrt .ods .xlsx .csv .geojson .kml …)
                               -> PRZEPISANY do teren.gpkg (arkusz na telefonie to krucha
                                  konstrukcja; liczba obiektów sprawdzana po przepisaniu)
  tekst rozdzielany (CSV z X/Y) -> kopia pliku
  internet (WMS/WMTS/XYZ/WFS…) -> bez zmian
  warstwa tymczasowa (memory)  -> OSTRZEŻENIE: na telefonie będzie pusta
  wszystkie ścieżki            -> względne (./plik)

STOP, gdy:
  - obok którejś bazy .gpkg leży -wal/-shm (projekt otwarty — dane w dzienniku),
  - katalog wersji terenowej już istnieje (nie nadpisuje),
  - brakuje pliku warstwy (chyba że --mimo-brakow),
  - po złożeniu w projekcie zostaje ścieżka spoza katalogu.

Wynik w katalogu terenowym:
  <projekt> teren <data>.qgz, pliki danych, TEREN.md5 (sumy), TEREN.txt (opis)
— dokładnie to, co bierze `wyslij_na_telefon.sh`.
"""
import hashlib, os, re, shutil, subprocess, sys, time, zipfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ONLINE = {"wms", "wfs", "wcs", "arcgismapserver", "arcgisfeatureserver", "vectortile",
          "postgres", "oracle", "mssql", "WFS", "xyzvectortiles", "mbtilesvectortiles"}
SHP_TOWARZYSZE = (".shx", ".dbf", ".prj", ".cpg", ".qpj", ".sbn", ".sbx", ".qix", ".shp.xml")
WEKTOR_KOPIA = (".gpkg", ".shp")
OSM_URL = ("https%3A%2F%2Ftile.openstreetmap.org%2F%7Bz%7D%2F%7Bx%7D%2F%7By%7D.png"
           "&amp;zmax=19&amp;zmin=0")


def md5(sciezka):
    h = hashlib.md5()
    with open(sciezka, "rb") as f:
        for k in iter(lambda: f.read(1 << 20), b""):
            h.update(k)
    return h.hexdigest()


def ludzko(b):
    for j, x in ((1 << 30, "GB"), (1 << 20, "MB"), (1 << 10, "kB")):
        if b >= j:
            return "%.1f %s" % (b / j, x)
    return "%d B" % b


def uruchom(pol):
    w = subprocess.run(pol, capture_output=True, text=True)
    if w.returncode != 0:
        raise SystemExit("STOP: %s\n%s" % (" ".join(pol), w.stderr.strip()))
    return w.stdout


def warstwy_ogr(plik):
    wyn, nazwa = {}, None
    for l in uruchom(["ogrinfo", "-ro", "-so", "-al", plik]).splitlines():
        if l.startswith("Layer name:"):
            nazwa = l.split(":", 1)[1].strip()
        elif l.startswith("Feature Count:") and nazwa:
            wyn[nazwa] = int(l.split(":", 1)[1])
    return wyn


def bezpieczna_nazwa(t):
    zamiana = str.maketrans("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ", "acelnoszzACELNOSZZ")
    t = re.sub(r"[^A-Za-z0-9]+", "_", t.translate(zamiana)).strip("_").lower()
    return (t or "warstwa")[:50]


def czytaj_projekt(sciezka):
    if sciezka.lower().endswith(".qgz"):
        with zipfile.ZipFile(sciezka) as z:
            nazwy = z.namelist()
            qgs = [n for n in nazwy if n.lower().endswith(".qgs")][0]
            return z.read(qgs).decode("utf-8"), {n: z.read(n) for n in nazwy if n != qgs}
    return open(sciezka, encoding="utf-8").read(), {}


def plik_z_zrodla(ds, dostawca):
    """(ścieżka_jak_w_projekcie, reszta_uri) albo (None, None)."""
    if dostawca == "delimitedtext":
        m = re.match(r"file:(?://)?([^?]*)(\?.*)?$", ds)
        return (m.group(1), m.group(2) or "") if m else (None, None)
    if dostawca in ("ogr", "gdal"):
        czesci = ds.split("|", 1)
        return czesci[0], ("|" + czesci[1] if len(czesci) > 1 else "")
    return None, None


def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("--"):
        print(__doc__)
        sys.exit(2)
    zapisz = "--zapisz" in sys.argv
    mimo_brakow = "--mimo-brakow" in sys.argv
    projekt = os.path.abspath(sys.argv[1])
    kat_proj = os.path.dirname(projekt)
    rdzen = re.sub(r"\.qg[sz]$", "", os.path.basename(projekt), flags=re.I)
    dzis = time.strftime("%Y-%m-%d")
    nazwa_tel = sys.argv[sys.argv.index("--nazwa") + 1] if "--nazwa" in sys.argv else os.path.basename(kat_proj)
    cel = (os.path.abspath(sys.argv[sys.argv.index("--do") + 1]) if "--do" in sys.argv else
           os.path.join(os.path.expanduser("~/WorkField/teren"), "%s_%s" % (os.path.basename(kat_proj), dzis)))
    # data w nazwie źródła („… 2026-10-07”) nie dubluje się z datą wersji terenowej
    wy_nazwa = "%s teren %s.qgz" % (re.sub(r"[ _-]*\d{4}-\d{2}-\d{2}$", "", rdzen), dzis)

    print("== projekt:  %s" % projekt)
    print("== terenowa: %s" % cel)
    print("== telefon:  Imported Projects/%s" % nazwa_tel)
    if not os.path.isfile(projekt):
        raise SystemExit("STOP: nie ma pliku projektu.")
    if os.path.exists(cel):
        raise SystemExit("STOP: katalog wersji terenowej już istnieje — nie nadpisuję.\n"
                         "   Podaj inny przez --do albo zajrzyj, co w nim jest.")

    qgs, reszta_zip = czytaj_projekt(projekt)
    korzen = ET.fromstring(qgs)

    # ── 1. rozpoznanie warstw ───────────────────────────────────────────
    pliki = {}       # pełna ścieżka źródła -> nazwa w katalogu terenowym
    konwersje = []   # (pełna ścieżka, reszta_uri, ds_w_projekcie, nazwa warstwy, nowa nazwa w teren.gpkg)
    zamiany = []     # (stary tekst ds, nowy tekst ds)
    problemy, ostrzezenia, wiersze = [], [], []
    zajete = set()

    def nazwa_w_terenie(pelna):
        if pelna in pliki:
            return pliki[pelna]
        n = os.path.basename(pelna)
        rdz, roz = os.path.splitext(n)
        i = 2
        while n.lower() in zajete or n.lower() == "teren.gpkg":
            n = "%s_%d%s" % (rdz, i, roz)
            i += 1
        zajete.add(n.lower())
        pliki[pelna] = n
        return n

    nazwy_tg = set()
    for ml in korzen.iter("maplayer"):
        ds = (ml.findtext("datasource") or "").strip()
        dost = (ml.findtext("provider") or "").strip()
        nazwa = (ml.findtext("layername") or "?").strip()
        if not ds:
            continue
        if dost == "memory":
            ostrzezenia.append("„%s” — warstwa TYMCZASOWA: na telefonie będzie pusta "
                               "(zapisz ją do .gpkg w QGIS, jeśli jest potrzebna)" % nazwa)
            wiersze.append(("tymczasowa", nazwa, "-"))
            continue
        if dost in ONLINE or "type=xyz" in ds or ds.startswith(("url=", "contextualWMSLegend")) or "url=http" in ds:
            if re.search(r"type=xyz&url$|type=xyz&url&", ds) or ds.endswith("&url"):
                if "openstreetmap" in nazwa.lower():
                    zamiany.append((ds, ds + "=" + OSM_URL.replace("&amp;", "&")))
                    wiersze.append(("internet", nazwa, "naprawiony ucięty adres kafli"))
                else:
                    ostrzezenia.append("„%s” — ucięty adres kafli (nic nie pokaże)" % nazwa)
                    wiersze.append(("internet", nazwa, "UCIĘTY ADRES"))
            else:
                wiersze.append(("internet", nazwa, "bez zmian"))
            continue
        sciezka, ogon = plik_z_zrodla(ds, dost)
        if sciezka is None or sciezka.startswith(("GPKG:", "/vsi", "dbname=")):
            ostrzezenia.append("„%s” — nieobsługiwane źródło (%s): %s — zostaje bez zmian" % (nazwa, dost, ds[:80]))
            wiersze.append(("?", nazwa, "bez zmian"))
            continue
        pelna = os.path.normpath(sciezka if os.path.isabs(sciezka) else os.path.join(kat_proj, sciezka))
        if not os.path.exists(pelna):
            problemy.append("„%s” — BRAK PLIKU: %s" % (nazwa, pelna))
            wiersze.append(("BRAK", nazwa, pelna))
            continue
        roz = os.path.splitext(pelna)[1].lower()
        if roz == ".gpkg":
            for d in ("-wal", "-shm"):
                if os.path.exists(pelna + d):
                    problemy.append("„%s” — obok bazy leży %s%s: projekt jest OTWARTY. "
                                    "Zamknij QGIS / WorkFieldGIS." % (nazwa, os.path.basename(pelna), d))
        if dost == "gdal" or roz in WEKTOR_KOPIA or dost == "delimitedtext":
            n = nazwa_w_terenie(pelna)
            if dost == "delimitedtext":
                zamiany.append((ds, "file:./%s%s" % (n, ogon)))
            else:
                zamiany.append((ds, "./%s%s" % (n, ogon)))
            wiersze.append(("kopia", nazwa, n))
        else:
            m = re.search(r"layername=([^|]+)", ogon)
            nowa = bezpieczna_nazwa(nazwa)
            while nowa in nazwy_tg:
                nowa += "_2"
            nazwy_tg.add(nowa)
            konwersje.append((pelna, m.group(1) if m else None, ds, nazwa, nowa))
            zamiany.append((ds, "./teren.gpkg|layername=%s" % nowa))
            wiersze.append(("do teren.gpkg", nazwa, nowa))

    # rozmiar
    razem = 0
    for p in pliki:
        razem += os.path.getsize(p)
        if p.lower().endswith(".shp"):
            razem += sum(os.path.getsize(p[:-4] + t) for t in SHP_TOWARZYSZE if os.path.exists(p[:-4] + t))

    print("\n== warstwy:")
    for co, nazwa, gdzie in wiersze:
        print("   %-14s %-45s %s" % (co, nazwa[:45], gdzie))
    print("\n== pliki do skopiowania: %d (%s)" % (len(pliki), ludzko(razem)))
    for p, n in pliki.items():
        print("   %s  <-  %s" % (n, p))
    if konwersje:
        print("== do przepisania w teren.gpkg: %d" % len(konwersje))
    for o in ostrzezenia:
        print("   UWAGA: " + o)
    for p in problemy:
        print("   PROBLEM: " + p)
    otwarte = [p for p in problemy if "OTWARTY" in p]
    if otwarte or (problemy and not mimo_brakow):
        raise SystemExit("\nSTOP: najpierw rozwiąż problemy wyżej%s."
                         % ("" if otwarte else " (albo --mimo-brakow)"))
    wolne = shutil.disk_usage(os.path.dirname(cel) if os.path.exists(os.path.dirname(cel)) else os.path.expanduser("~")).free
    if wolne < razem * 1.1 + (50 << 20):
        raise SystemExit("STOP: za mało miejsca (wolne %s, potrzeba %s)." % (ludzko(wolne), ludzko(razem)))

    if not zapisz:
        print("\nPRÓBA — nic nie zapisano. Wykonanie: dodaj --zapisz")
        return

    # ── 2. kopie ───────────────────────────────────────────────────────
    os.makedirs(cel)
    print("\n== kopiuję")
    for p, n in pliki.items():
        do = os.path.join(cel, n)
        shutil.copy2(p, do)
        if md5(do) != md5(p):
            raise SystemExit("STOP: kopia %s niezgodna z oryginałem." % n)
        print("   OK  %s" % n)
        if p.lower().endswith(".shp"):
            for t in SHP_TOWARZYSZE:
                if os.path.exists(p[:-4] + t):
                    shutil.copy2(p[:-4] + t, os.path.join(cel, n[:-4] + t))

    # ── 3. przepisanie do teren.gpkg ───────────────────────────────────
    tg = os.path.join(cel, "teren.gpkg")
    for pelna, warstwa_zr, ds, nazwa, nowa in konwersje:
        zr = warstwy_ogr(pelna)
        if warstwa_zr is None:
            if len(zr) != 1:
                raise SystemExit("STOP: „%s” — w %s jest %d warstw, nie wiem którą wziąć." % (nazwa, pelna, len(zr)))
            warstwa_zr = list(zr)[0]
        n_zr = zr.get(warstwa_zr)
        pol = ["ogr2ogr", "-f", "GPKG", tg, pelna, warstwa_zr, "-nln", nowa]
        if os.path.exists(tg):
            pol.insert(1, "-update")
        uruchom(pol)
        n_po = warstwy_ogr(tg).get(nowa)
        if n_po != n_zr:
            raise SystemExit("STOP: „%s” — przepisano %s obiektów z %s." % (nazwa, n_po, n_zr))
        print("   OK  teren.gpkg|%s  (%d obiektów)  <-  %s" % (nowa, n_po, os.path.basename(pelna)))

    # ── 4. projekt ze ścieżkami względnymi ─────────────────────────────
    # JEDNO przejście (re.sub z alternatywą): zamiana nie może trafić we własny
    # wynik — np. ucięty adres OSM jest przedrostkiem adresu naprawionego.
    slownik = {}
    for stary, nowy_ds in zamiany:
        for f in (lambda s: escape(s), lambda s: escape(s, {'"': "&quot;"})):
            slownik[f(stary)] = f(nowy_ds)
    if slownik:
        # tylko całe wartości: po źródle stoi |, <, " albo ?
        wzor = re.compile("(%s)(?=[|<\"?])" % "|".join(re.escape(k) for k in sorted(slownik, key=len, reverse=True)))
        nowy = wzor.sub(lambda m: slownik[m.group(1)], qgs)
    else:
        nowy = qgs
    # wpisy wtyczki GeoSpreadsheet trzymają ścieżki do arkusza na tym komputerze
    nowy = re.sub(r'\n[ \t]*<Option name="GeoSpreadsheet/[^"]*"[^>]*/>', "", nowy)
    nowy = re.sub(r'(<properties name="Absolute" type="bool">)true(</properties>)', r"\1false\2", nowy)

    bledy = []
    ET.fromstring(nowy)  # musi się dać przeczytać
    for ml in ET.fromstring(nowy).iter("maplayer"):
        ds = (ml.findtext("datasource") or "").strip()
        dost = (ml.findtext("provider") or "").strip()
        sc, _ = plik_z_zrodla(ds, dost)
        if sc and not sc.startswith(("GPKG:", "/vsi", "dbname=")):
            if not sc.startswith("./"):
                bledy.append("ścieżka spoza katalogu: %s" % ds[:120])
            elif not os.path.exists(os.path.join(cel, sc[2:])):
                bledy.append("brak pliku w katalogu terenowym: %s" % sc)
    for d in (kat_proj, os.path.expanduser("~")):
        if d and d in nowy:
            ostr = [w.strip()[:140] for w in nowy.splitlines() if d in w][:3]
            print("   UWAGA: w projekcie zostały odwołania do %s (nie źródła warstw):" % d)
            for w in ostr:
                print("      " + w)
    if bledy:
        print("\n".join("   " + b for b in bledy))
        raise SystemExit("STOP: projekt terenowy nie przeszedł kontroli. Katalog %s zostawiam do wglądu." % cel)

    wy = os.path.join(cel, wy_nazwa)
    with zipfile.ZipFile(wy, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(wy_nazwa[:-4] + ".qgs", nowy.encode("utf-8"))
        for n, d in reszta_zip.items():
            z.writestr(n, d)

    # ── 5. sumy i opis ─────────────────────────────────────────────────
    sumy = []
    for n in sorted(os.listdir(cel)):
        if os.path.isfile(os.path.join(cel, n)) and not n.startswith("TEREN."):
            sumy.append("%s  %s" % (md5(os.path.join(cel, n)), n))
    open(os.path.join(cel, "TEREN.md5"), "w", encoding="utf-8").write("\n".join(sumy) + "\n")
    open(os.path.join(cel, "TEREN.txt"), "w", encoding="utf-8").write(
        "telefon: %s\nprojekt: %s\nzrodlo: %s\nutworzono: %s\n\n%s\n"
        % (nazwa_tel, wy_nazwa, projekt, time.strftime("%Y-%m-%d %H:%M"),
           "\n".join("%-14s %-45s %s" % w for w in wiersze)))
    print("\nGOTOWE: %s" % cel)
    for s in sumy:
        print("   " + s)
    print("   oryginał projektu — bez zmian")
    print("\nDalej:  bash wyslij_na_telefon.sh \"%s\"" % cel)


if __name__ == "__main__":
    main()
