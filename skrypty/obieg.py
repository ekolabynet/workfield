#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OBIEG — bezpieczna wysylka i pobieranie danych z telefonu.

==========================================================================
PO CO
==========================================================================
07.09.2026 wieczorem przepadly opisy kilkunastu platow PTR z calego dnia
pracy. Przyczyna byla potrojna i kazda czesc dalo sie przewidziec:

  1. Polecenie wykrywalo telefon automatycznie
     (`T=$(adb devices | awk 'NR==2{print $1}')`) i wysylalo na ten, ktory
     byl podlaczony — bez pokazania KTOREGO dotyczy.
  2. Przed wysylka usuwalo dziennik WAL, w ktorym siedziala praca dnia.
  3. Nie pobieralo zwrotu przed nadpisaniem.

Ten skrypt zastepuje wszystkie recznie skladane polecenia `adb push`.

==========================================================================
CO ROBI INACZEJ
==========================================================================
**Pokazuje, czego dotyczy.** Nazwa urzadzenia, projekt, rozmiar i data
bazy PO OBU STRONACH — zanim cokolwiek ruszy.

**Punkt kontrolny przed pobraniem.** `PRAGMA wal_checkpoint(TRUNCATE)`
przenosi zawartosc dziennika do bazy. Bez tego kopiujemy baze bez
ostatnich zmian — dokladnie to, co przepadlo 07.09.

**Zwrot ZAWSZE przed nadpisaniem.** Bezwarunkowo, nawet gdy „na pewno nic
tam nie ma". Kosztuje kilkanascie sekund; utrata jest nieodwracalna.

**Pyta o potwierdzenie**, pokazujac roznice: ile platow i wierszy spisu
jest po kazdej stronie. Jesli na telefonie jest WIECEJ niz w tym, co
wysylamy — ostrzega wyraznie, bo to znak, ze nadpisujemy prace.

Uzycie:
    python3 obieg.py pobierz <projekt>            # zwrot z telefonu
    python3 obieg.py wyslij <projekt> <katalog>   # wydanie na telefon
    python3 obieg.py stan                          # co na ktorym telefonie
"""
import os
import subprocess
import sqlite3
import sys
import shutil
import datetime

KORZEN = "/storage/emulated/0/Android/data/ch.opengis.qfield_home/files/Imported Projects"
ZWROTY = os.path.expanduser("~/WorkField/zwroty/zzw_2026")


def adb(dev, *args, tekst=True):
    w = subprocess.run(["adb", "-s", dev] + list(args),
                       capture_output=True, text=tekst)
    return w.stdout if tekst else w.stdout


def urzadzenia():
    w = subprocess.run(["adb", "devices"], capture_output=True, text=True)
    return [l.split()[0] for l in w.stdout.splitlines()[1:]
            if l.strip() and l.split()[-1] == "device"]


def wybierz_urzadzenie():
    u = urzadzenia()
    if not u:
        sys.exit("STOP: zaden telefon nie jest podlaczony")
    if len(u) == 1:
        return u[0]
    # Dwa telefony z tym samym projektem to wlasnie ta sytuacja, ktora
    # 07.09 kosztowala dzien pracy. Nie zgadujemy.
    print("Podlaczone telefony:")
    for i, d in enumerate(u, 1):
        model = adb(d, "shell", "getprop ro.product.model").strip()
        print("  %d. %s  (%s)" % (i, d, model))
    o = input("Ktory? [numer, Enter = przerwij] ").strip()
    if not o.isdigit() or not (1 <= int(o) <= len(u)):
        sys.exit("Przerwane.")
    return u[int(o) - 1]


# Wzorce tabel, ktore niosa prace z terenu. NIE lista nazw — 11.09.2026
# reczna krotka nie miala `ZAL_ZDJECIA_FITO` i przez to wydruk po kazdym
# zwrocie od 09.09 milczal o 320 zalacznikach. Ta sama pomylka kazala
# przeoczyc te tabele przy scalaniu dwoch telefonow.
WZORCE_TABEL = ("FITO\\_%", "ZAL\\_%", "NIEBO\\_%")


def tabele_danych(c):
    """Nazwy tabel z terenu, odczytane Z BAZY. Nigdy z listy w kodzie."""
    nazwy = []
    for wz in WZORCE_TABEL:
        for (t,) in c.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name LIKE ? ESCAPE '\\' ORDER BY name", (wz,)):
            nazwy.append(t)
    return nazwy


def tabele_zalacznikow(c):
    """Tabele `ZAL_*` — te trzymaja SCIEZKA do pliku w DCIM."""
    return [t for t in tabele_danych(c) if t.upper().startswith("ZAL_")]


def opis_bazy(p):
    """Ile czego w bazie — do pokazania czlowiekowi przed nadpisaniem."""
    if not os.path.exists(p):
        return None
    try:
        c = sqlite3.connect("file:%s?mode=ro" % p, uri=True)
        w = {}
        for t in tabele_danych(c):
            try:
                w[t] = c.execute('SELECT count(*) FROM "%s"' % t).fetchone()[0]
            except Exception:
                pass
        c.close()
        return w
    except Exception as e:
        return {"BLAD": str(e)[:40]}


# Pliki robocze wtyczki Pl@ntNet: zdjecie idzie do API, wiersz NIE powstaje
# i nie ma powstawac. Bez tego wykluczenia zaciemniaja obraz przy kazdym
# wydaniu — 11.09 bylo ich dziewiec z samego jednego dnia.
ROBOCZE = ("plantnet_",)


def pliki_dcim(katalog):
    """Nazwy plikow w DCIM, REKURENCYJNIE.

    Rekurencja nie jest ozdoba: konwencja Mapit tworzy podkatalog na obiekt
    (`DCIM/platy_473/`), a plaskie listowanie gubilo go 09.09 dwa razy —
    raz przy skladaniu wydania, raz przy kontroli sierot.
    """
    dcim = os.path.join(katalog, "DCIM")
    if not os.path.isdir(dcim):
        return set()
    w = set()
    for korzen, _, pliki in os.walk(dcim):
        w.update(pliki)
    return w


def kontrola_zalacznikow(katalog):
    """Porownuje wiersze `ZAL_*` z zawartoscia DCIM.

    SIEROTA  — wiersz wskazuje na plik, ktorego nie ma. Wyglada w terenie
               jak zdjecie, ktorego nie da sie otworzyc. To jest strata.
    LUZEM    — plik jest, wiersza nie ma. Nic nie zginelo, ale nikt tego
               zdjecia nie zobaczy, bo nie wisi przy zadnym obiekcie.

    Zwraca (sieroty, luzem) jako posortowane listy nazw plikow.
    """
    baza = os.path.join(katalog, "dane.gpkg")
    if not os.path.exists(baza):
        return [], []
    w_bazie = set()
    try:
        c = sqlite3.connect("file:%s?mode=ro" % baza, uri=True)
        for t in tabele_zalacznikow(c):
            try:
                for (sc,) in c.execute('SELECT SCIEZKA FROM "%s"' % t):
                    if sc:
                        w_bazie.add(str(sc).replace("\\", "/").split("/")[-1])
            except Exception:
                pass
        c.close()
    except Exception:
        return [], []
    na_dysku = pliki_dcim(katalog)
    luzem = {f for f in (na_dysku - w_bazie)
             if not any(f.startswith(r) for r in ROBOCZE)}
    return sorted(w_bazie - na_dysku), sorted(luzem)


def rodzic_tabeli(c, zal):
    """Ktora tabela jest rodzicem dla `zal`. USTALANE Z DANYCH, nie z nazwy.

    Konwencja `ZAL_<WARSTWA>` zawodzi: `ZAL_GATUNKI` wskazuje na
    `FITO_SPIS_GATUNKOWY`, a nie na `FITO_GATUNKI`, ktorej nie ma.
    Dopasowanie po sufiksie 09.09 kazalo przeoczyc `ZAL_ZDJECIA_FITO`
    przy scalaniu dwoch telefonow.

    Wybieramy wiec te tabele, przy ktorej `ID_RODZICA` NAJLEPIEJ pasuje
    do `fid`. Brzydkie, ale odporne na nazwy — a nazwy juz raz sklamaly.
    """
    try:
        wartosci = [r[0] for r in c.execute(
            'SELECT DISTINCT ID_RODZICA FROM "%s" WHERE ID_RODZICA IS NOT NULL' % zal)]
    except Exception:
        return None, 0
    if not wartosci:
        return None, 0
    najlepsza, najwiecej = None, -1
    for (t,) in c.execute("SELECT name FROM sqlite_master WHERE type='table' "
                          "AND name LIKE 'FITO\\_%' ESCAPE '\\'"):
        try:
            fidy = {r[0] for r in c.execute('SELECT fid FROM "%s"' % t)}
        except Exception:
            continue
        trafien = sum(1 for w in wartosci if w in fidy)
        if trafien > najwiecej:
            najlepsza, najwiecej = t, trafien
    return najlepsza, najwiecej


def sieroty_rodzica(katalog):
    """Wiersze `ZAL_*` wskazujace na NIEISTNIEJACEGO rodzica.

    To DRUGA rodzina sierot, inna niz brak pliku. 14.09.2026 kontrola
    mowila „zero sierot", a osiem zdjec wisialo przy platach usunietych
    przy scalaniu tydzien wczesniej — bo pliki byly na dysku i porownanie
    z DCIM ich nie widzialo.

    Zwraca [(tabela, rodzic, ile)].
    """
    baza = os.path.join(katalog, "dane.gpkg")
    if not os.path.exists(baza):
        return []
    out = []
    try:
        c = sqlite3.connect("file:%s?mode=ro" % baza, uri=True)
        for zal in tabele_zalacznikow(c):
            rodzic, _ = rodzic_tabeli(c, zal)
            if not rodzic:
                continue
            try:
                for r in c.execute(
                        'SELECT ID_RODZICA, count(*) FROM "%s" WHERE ID_RODZICA '
                        'NOT IN (SELECT fid FROM "%s") GROUP BY 1' % (zal, rodzic)):
                    out.append((zal, r[0], r[1]))
            except Exception:
                pass
        c.close()
    except Exception:
        pass
    return out


def pokaz_kontrole(katalog):
    """Wypisuje wynik kontroli. Sieroty Z NAZWY — jest ich malo i kazda
    cos znaczy. Luzem tylko liczba, bo to zwykle zdjecia poza formularzem."""
    sieroty, luzem = kontrola_zalacznikow(katalog)
    bezrodzica = sieroty_rodzica(katalog)
    ile_br = sum(x[2] for x in bezrodzica)
    print("   sierot: %-4d bez rodzica: %-4d luzem: %d"
          % (len(sieroty), ile_br, len(luzem)))
    for tab, rodzic, ile in bezrodzica:
        print("      %s: %d wierszy wskazuje na nieistniejacy obiekt %s"
              % (tab, ile, rodzic))
    for f in sieroty[:10]:
        print("      BRAK PLIKU: %s" % f)
    if len(sieroty) > 10:
        print("      ... i jeszcze %d" % (len(sieroty) - 10))
    return sieroty, luzem


def pokaz(naglowek, sciezka, stan):
    print("  %s" % naglowek)
    if stan is None:
        print("     (brak pliku)")
        return
    for k, v in stan.items():
        print("     %-22s %s" % (k, v))


def checkpoint_na_telefonie(dev, projekt):
    """Zamyka aplikacje i scala dziennik do bazy.

    Bez tego pobrana baza NIE MA ostatnich zmian — siedza w `-wal`,
    ktory latwo pominac przy kopiowaniu. To druga z trzech przyczyn
    utraty z 07.09.
    """
    print("Zamykam aplikacje i scalam dziennik...")
    adb(dev, "shell", "am force-stop ch.opengis.qfield_home")
    import time
    time.sleep(3)
    baza = "%s/%s/dane.gpkg" % (KORZEN, projekt)
    w = adb(dev, "shell", "ls -la '%s'-shm '%s'-wal 2>/dev/null" % (baza, baza))
    if w.strip():
        print("   dziennik jest — scalam przez pobranie kompletu")
    return bool(w.strip())


def pobierz(dev, projekt, docelowy=None):
    zdalny = "%s/%s" % (KORZEN, projekt)
    if adb(dev, "shell", "ls -d '%s' 2>/dev/null" % zdalny).strip() == "":
        sys.exit("STOP: na telefonie nie ma projektu %s" % projekt)

    checkpoint_na_telefonie(dev, projekt)

    if docelowy is None:
        dzis = datetime.date.today().isoformat()
        docelowy = os.path.join(ZWROTY, "%s_%s_%s" % (dzis, projekt, dev))
    os.makedirs(docelowy, exist_ok=True)

    # Dziennik pobieramy RAZEM z baza i scalamy dopiero na dysku —
    # nigdy nie usuwamy go na telefonie przed pobraniem.
    #
    # WSZYSTKO poza wykluczeniami, nie lista nazw. Do 17.09.2026 bylo tu
    # szesc wypisanych plikow i `wf_wskazniki.gpkg` z `workfield_klawisze.json`
    # NIGDY nie wracaly — slownik gatunkow i kafle paska zyly na telefonie
    # i ginely przy nowym wydaniu. Brak pliku nie jest bledem, tylko cisza.
    ZOSTAJA_NA_TELEFONIE = (
        ".png",           # podglady projektu i kafli
        ".roboczy",       # kopia robocza edytora
        "~",              # kopia zapasowa QGIS-a
        ".zip",           # projekt_attachments.zip
        "-shm",           # dziennik pustej bazy — `gugik.gpkg-shm` bez tresci
    )
    # Kopie robione przed kazda zmiana w projekcie (konsola, wyposazenie).
    # 17.09.2026 zwrot przywiozl ich cztery po 571 kB — 2,3 MB smieci.
    ZOSTAJA_WZORCE = (".przed_",)
    spis = adb(dev, "shell", "ls -p '%s' 2>/dev/null" % zdalny).splitlines()
    do_pobrania = []
    for nazwa in spis:
        nazwa = nazwa.strip()
        # `ls -p` konczy katalogi ukosnikiem — DCIM bierzemy osobno nizej,
        # `kopie/` i `kosz/` zostaja na telefonie.
        if nazwa == "" or nazwa.endswith("/"):
            continue
        if any(nazwa.endswith(k) for k in ZOSTAJA_NA_TELEFONIE):
            continue
        if any(w in nazwa for w in ZOSTAJA_WZORCE):
            continue
        do_pobrania.append(nazwa)

    if not do_pobrania:
        do_pobrania = ["dane.gpkg", "dane.gpkg-shm", "dane.gpkg-wal",
                       "foto_tagi.gpkg", "gugik.gpkg", "projekt.qgs"]

    for f in do_pobrania:
        subprocess.run(["adb", "-s", dev, "pull",
                        "%s/%s" % (zdalny, f), docelowy + "/"],
                       capture_output=True, text=True)
    print("Pobieram zdjecia...")
    subprocess.run(["adb", "-s", dev, "pull", "%s/DCIM" % zdalny, docelowy + "/"],
                   capture_output=True, text=True)

    baza = os.path.join(docelowy, "dane.gpkg")
    if os.path.exists(baza):
        c = sqlite3.connect(baza)
        c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        c.commit()
        c.close()
    print("\nZwrot: %s" % docelowy)
    print("   zdjec: %d" % len(pliki_dcim(docelowy)))
    pokaz("zawartosc:", baza, opis_bazy(baza))
    pokaz_kontrole(docelowy)
    return docelowy


def wyslij(dev, projekt, zrodlo):
    zrodlo = os.path.expanduser(zrodlo)
    baza_zr = os.path.join(zrodlo, "dane.gpkg")
    if not os.path.exists(baza_zr):
        sys.exit("STOP: brak %s" % baza_zr)

    model = adb(dev, "shell", "getprop ro.product.model").strip()
    zdalny = "%s/%s" % (KORZEN, projekt)
    jest = adb(dev, "shell", "ls -d '%s' 2>/dev/null" % zdalny).strip() != ""

    print("=" * 66)
    print("TELEFON:  %s  (%s)" % (dev, model))
    print("PROJEKT:  %s" % projekt)
    print("=" * 66)

    if jest:
        # Zwrot ZAWSZE przed nadpisaniem — bezwarunkowo. 07.09 pominiecie
        # tego kroku kosztowalo dzien pracy w terenie.
        print("\nNa telefonie JEST juz ten projekt. Pobieram zwrot...")
        z = pobierz(dev, projekt)
        print()
        print("Porownanie:")
        pokaz("NA TELEFONIE (zwrot):", os.path.join(z, "dane.gpkg"),
              opis_bazy(os.path.join(z, "dane.gpkg")))
        pokaz("DO WYSLANIA:", baza_zr, opis_bazy(baza_zr))

        a = opis_bazy(os.path.join(z, "dane.gpkg")) or {}
        b = opis_bazy(baza_zr) or {}
        wieksze = [k for k in a if k in b and a[k] > b[k]]
        if wieksze:
            print()
            print("  !!! UWAGA: na telefonie jest WIECEJ niz w tym, co wysylamy:")
            for k in wieksze:
                print("      %-22s telefon %-6d  wysylka %d" % (k, a[k], b[k]))
            print("      To moze znaczyc, ze nadpisujesz PRACE Z TERENU.")
    else:
        print("\nNa telefonie nie ma tego projektu — wysylka nowego wydania.")
        pokaz("DO WYSLANIA:", baza_zr, opis_bazy(baza_zr))

    # Sieroty w wydaniu to zdjecia, ktorych w terenie NIE DA SIE otworzyc.
    # Ostrzezenie, nie blokada: zero sierot jest norma, a twarda odmowa
    # w posciechu przed wyjazdem bywa gorsza od swiadomej decyzji.
    print()
    print("Kontrola zalacznikow w tym, co wysylamy:")
    sieroty, luzem = pokaz_kontrole(zrodlo)
    if bezrodzica_w := sieroty_rodzica(zrodlo):
        print()
        print("  !!! UWAGA: %d zalacznikow wisi przy NIEISTNIEJACYCH obiektach."
              % sum(x[2] for x in bezrodzica_w))
        print("      W terenie nikt ich nie zobaczy. Zwykle po scaleniu")
        print("      albo rozbiciu obiektu — patrz StozkiWidzenia.")
    if sieroty:
        print()
        print("  !!! UWAGA: %d wierszy wskazuje na NIEISTNIEJACE pliki." % len(sieroty))
        print("      W terenie beda wygladac jak zdjecia, ktorych nie da sie otworzyc.")

    print()
    o = input("Wyslac? [tak/NIE] ").strip().lower()
    if o not in ("tak", "t", "yes", "y"):
        sys.exit("Przerwane. Nic nie zmieniono.")

    adb(dev, "shell", "am force-stop ch.opengis.qfield_home")
    adb(dev, "shell", "mkdir -p '%s'" % zdalny)
    # Dziennik usuwamy DOPIERO teraz — po pobraniu zwrotu.
    adb(dev, "shell", "rm -f '%s/dane.gpkg-shm' '%s/dane.gpkg-wal'" % (zdalny, zdalny))
    # Kopie robocze i podglady nie maja po co jechac na telefon —
    # `dane.gpkg.przed_indeksami` to 2,7 MB, `projekt.qgs.png` kolejny.
    # Kopiujemy do katalogu tymczasowego bez nich.
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        czyste = os.path.join(tmp, "wyslij")
        shutil.copytree(zrodlo, czyste, ignore=shutil.ignore_patterns(
            "*.przed_*", "*~", "*.png", "*.zip", "kopie"))
        w = subprocess.run(["adb", "-s", dev, "push", czyste + "/.", zdalny + "/"],
                           capture_output=True, text=True)
    print(w.stdout.strip().splitlines()[-1] if w.stdout.strip() else w.stderr[:200])
    # Pusty katalog nie przechodzi przez adb push — zakladamy osobno.
    adb(dev, "shell", "mkdir -p '%s/DCIM'" % zdalny)
    print("\nPo wysylce:")
    print(adb(dev, "shell", "ls -la '%s' | head -12" % zdalny))


def stan():
    for d in urzadzenia():
        model = adb(d, "shell", "getprop ro.product.model").strip()
        print("=== %s (%s)" % (d, model))
        w = adb(d, "shell", "ls -d '%s'/*/ 2>/dev/null" % KORZEN)
        for l in w.splitlines():
            nazwa = l.rstrip("/").split("/")[-1]
            b = adb(d, "shell", "ls -la '%s/%s/dane.gpkg' 2>/dev/null" % (KORZEN, nazwa)).split()
            print("   %-34s %s" % (nazwa, " ".join(b[4:8]) if len(b) > 7 else ""))
        print()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "stan":
        stan()
    elif cmd == "pobierz":
        if len(sys.argv) < 3:
            sys.exit("Uzycie: obieg.py pobierz <projekt>")
        pobierz(wybierz_urzadzenie(), sys.argv[2])
    elif cmd == "wyslij":
        if len(sys.argv) < 4:
            sys.exit("Uzycie: obieg.py wyslij <projekt> <katalog_zrodlowy>")
        wyslij(wybierz_urzadzenie(), sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
