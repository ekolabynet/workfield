#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Wyposażenie WorkField — silnik doposażania projektów i szablonów.

Odpowiada na jedno pytanie, którego dziś nie da się zadać:
„co ten projekt ma założone, a czego mu brakuje".

Projekt nosi STEMPEL — tabelę WF_WYPOSAZENIE w GeoPackage — a katalog
wyposażenia mówi, co powinien mieć. Różnica między jednym a drugim to
lista rzeczy do zrobienia. Pełna umowa: docs/WYPOSAZENIE.md.

CZASOWNIKI
    spis                       — co jest w katalogu
    sprawdz  <ścieżka>         — stan projektu albo całego drzewa
    doposaz  <projekt>         — dołóż brakujące (albo wskazane) moduły
    zdejmij  <projekt> --moduly X

URUCHOMIENIE
    python3 skrypty/wyposazenie.py sprawdz ~/WorkField
    python3 skrypty/wyposazenie.py sprawdz ~/WorkField/master/zzw_pze_2605_inw_v3
    python3 skrypty/wyposazenie.py doposaz <projekt> --wszystko

    Zwykły python3. QGIS NIE jest potrzebny do sprawdzania ani do modułów
    deklaratywnych — dlatego to samo sprawdzenie może kiedyś zrobić sama
    aplikacja na telefonie. Moduły strukturalne (rodzaj "struktura") wymagają
    konsoli Pythona w QGIS-ie i są wypisywane jako „wymaga biura".

BEZPIECZEŃSTWO
    Każdy zapis poprzedza kopia zapasowa (.bak_RRRRMMDD_GGMMSS) pliku
    projektu i GeoPackage. Kopiujemy, nie przenosimy — zgodnie z magazynem.

PUŁAPKA UDOKUMENTOWANA (sprawdzona w źródłach QGIS)
    Właściwości projektu mają DWA zapisy w XML: nowy
    <properties name="AvoidIntersectionsMode" type="int">2</properties>
    i stary <AvoidIntersectionsMode type="int">0</AvoidIntersectionsMode>.
    QGIS czyta oba, a przy powtórzeniu wygrywa OSTATNI napotkany
    (qgsprojectproperty.cpp: delete take() + insert w pętli po dzieciach).
    W szablonie szablon_obs_roslinnosc występują oba naraz i wygrywa stary.
    Dlatego ustawiając właściwość zawsze kasujemy stary zapis.
"""

import argparse
import datetime
import json
import os
import shutil
import sqlite3
import sys
import zipfile
import xml.etree.ElementTree as ET

WERSJA_SILNIKA = 1
TABELA_STEMPLA = 'WF_WYPOSAZENIE'

# Stany modułu w projekcie
ZALOZONY = 'zalozony'      # jest, w aktualnej wersji, stan zgodny
STARSZY = 'starszy'        # jest, ale starsza wersja niż w katalogu
BRAK = 'brak'              # nie ma
ROZJECHANY = 'rozjechany'  # stempel mówi, że jest — a stan mówi, że nie
NIE_DOTYCZY = 'niedotyczy'  # moduł nie ma tu zastosowania
WYMAGA_BIURA = 'wymagabiura'  # trzeba PyQGIS, a lecimy bez QGIS-a

ZNAKI = {
    ZALOZONY: '  OK ',
    STARSZY: ' STAR',
    BRAK: ' BRAK',
    ROZJECHANY: '!ROZJ',
    NIE_DOTYCZY: '  -  ',
    WYMAGA_BIURA: ' BIUR',
}


def stempel_czasu():
    return datetime.datetime.now().strftime('%Y%m%d_%H%M%S')


# --------------------------------------------------------------------- katalog

class Katalog:
    """Spis dostępnego wyposażenia — z repo, z NextClouda albo z kopii lokalnej."""

    def __init__(self, sciezka):
        self.sciezka = os.path.abspath(sciezka)
        self.korzen = os.path.dirname(self.sciezka)
        with open(self.sciezka, encoding='utf-8') as f:
            dane = json.load(f)
        self.zrodlo = dane.get('zrodlo', 'lokalny')
        self.moduly = {}
        for wpis in dane['moduly']:
            plik = os.path.join(self.korzen, wpis['sciezka'], 'modul.json')
            with open(plik, encoding='utf-8') as f:
                m = json.load(f)
            m['_katalog'] = os.path.dirname(plik)
            m['_zrodlo'] = self.zrodlo
            if m['wersja'] != wpis['wersja']:
                raise SystemExit(
                    'Katalog kłamie: %s ma w spisie wersję %s, a w module %s'
                    % (m['id'], wpis['wersja'], m['wersja']))
            self.moduly[m['id']] = m

    def kolejnosc(self, wybrane=None):
        """Moduły w kolejności zależności (wymaga → potem)."""
        chciane = list(self.moduly) if wybrane is None else list(wybrane)
        gotowe, wynik = set(), []

        def wejdz(mid, sciezka):
            if mid in gotowe:
                return
            if mid in sciezka:
                raise SystemExit('Zapętlone zależności: %s' % ' -> '.join(sciezka + [mid]))
            m = self.moduly.get(mid)
            if m is None:
                raise SystemExit('Katalog nie zna modułu: %s' % mid)
            for w in m.get('wymaga', []):
                wejdz(w, sciezka + [mid])
            gotowe.add(mid)
            wynik.append(mid)

        for mid in chciane:
            wejdz(mid, [])
        return wynik


# --------------------------------------------------------------------- projekt

class Projekt:
    """Projekt QGIS/WorkField — plik .qgs albo .qgz, plus jego GeoPackage."""

    def __init__(self, sciezka):
        sciezka = os.path.abspath(sciezka)
        if os.path.isdir(sciezka):
            plik = None
            for n in sorted(os.listdir(sciezka)):
                if n.endswith(('.qgs', '.qgz')):
                    plik = os.path.join(sciezka, n)
                    break
            if plik is None:
                raise SystemExit('W katalogu nie ma pliku projektu: %s' % sciezka)
            sciezka = plik
        self.plik = sciezka
        self.katalog = os.path.dirname(sciezka)
        self.nazwa = os.path.basename(self.katalog) or os.path.basename(sciezka)
        self._wczytaj()

    # ---------------------------------------------------------- wczytaj/zapisz
    def _wczytaj(self):
        if self.plik.endswith('.qgz'):
            with zipfile.ZipFile(self.plik) as z:
                self._zawartosc_qgz = {n: z.read(n) for n in z.namelist()}
            self._nazwa_qgs = next(n for n in self._zawartosc_qgz if n.endswith('.qgs'))
            xml = self._zawartosc_qgz[self._nazwa_qgs]
        else:
            self._zawartosc_qgz = None
            self._nazwa_qgs = None
            with open(self.plik, 'rb') as f:
                xml = f.read()
        self.drzewo = ET.ElementTree(ET.fromstring(xml))
        self.korzen = self.drzewo.getroot()

    def zapisz(self, znacznik):
        kopia(self.plik, znacznik)
        surowe = ET.tostring(self.korzen, encoding='utf-8', xml_declaration=True)
        if self._zawartosc_qgz is None:
            with open(self.plik, 'wb') as f:
                f.write(surowe)
        else:
            self._zawartosc_qgz[self._nazwa_qgs] = surowe
            with zipfile.ZipFile(self.plik, 'w', zipfile.ZIP_DEFLATED) as z:
                for n, dane in self._zawartosc_qgz.items():
                    z.writestr(n, dane)

    # ------------------------------------------------------------------ warstwy
    def warstwy(self):
        """[(id, nazwa, geometria, readOnly)] dla warstw wektorowych."""
        out = []
        for m in self.korzen.iter('maplayer'):
            if m.get('type') != 'vector':
                continue
            out.append((m.findtext('id') or '', m.findtext('layername') or '',
                        m.get('geometry') or '', m.get('readOnly') == '1'))
        return out

    def gpkg(self):
        """Ścieżki do GeoPackage'ów projektu, bez powtórzeń."""
        widziane, out = set(), []
        for n in sorted(os.listdir(self.katalog)):
            if n.lower().endswith('.gpkg'):
                p = os.path.join(self.katalog, n)
                if p not in widziane:
                    widziane.add(p)
                    out.append(p)
        return out

    def gpkg_glowny(self):
        g = self.gpkg()
        if not g:
            return None
        for p in g:
            if os.path.basename(p).lower() in ('dane.gpkg', 'projekt.gpkg'):
                return p
        return g[0]

    # -------------------------------------------------------------- właściwości
    def _grupa_wlasciwosci(self, grupa, utworz=False):
        props = self.korzen.find('properties')
        if props is None:
            if not utworz:
                return None
            props = ET.SubElement(self.korzen, 'properties')
        for e in props:
            if e.tag == 'properties' and e.get('name') == grupa:
                return e
            if e.tag == grupa:
                return e
        if not utworz:
            return None
        e = ET.SubElement(props, 'properties')
        e.set('name', grupa)
        return e

    def czytaj_wlasciwosc(self, grupa, klucz):
        """Zwraca wartość tak, jak ODCZYTA ją QGIS: wygrywa ostatnie wystąpienie."""
        g = self._grupa_wlasciwosci(grupa)
        if g is None:
            return None
        wynik = None
        for e in g:
            nazwa = e.get('name') if (e.tag == 'properties' and e.get('name')) else e.tag
            if nazwa != klucz or not e.get('type'):
                continue
            if e.get('type') == 'QStringList':
                wynik = [v.text or '' for v in e.findall('value')]
            else:
                wynik = e.text or ''
        return wynik

    def ustaw_wlasciwosc(self, grupa, klucz, typ, wartosc):
        """Wpisuje wartość w postaci kanonicznej i kasuje stary zapis (patrz PUŁAPKA)."""
        g = self._grupa_wlasciwosci(grupa, utworz=True)
        for e in list(g):
            nazwa = e.get('name') if (e.tag == 'properties' and e.get('name')) else e.tag
            if nazwa == klucz:
                g.remove(e)
        e = ET.SubElement(g, 'properties')
        e.set('name', klucz)
        e.set('type', typ)
        if typ == 'QStringList':
            for v in wartosc:
                ET.SubElement(e, 'value').text = v
        else:
            e.text = str(wartosc)

    def usun_wlasciwosc(self, grupa, klucz):
        g = self._grupa_wlasciwosci(grupa)
        if g is None:
            return
        for e in list(g):
            nazwa = e.get('name') if (e.tag == 'properties' and e.get('name')) else e.tag
            if nazwa == klucz:
                g.remove(e)

    # ----------------------------------------------------------------- snapping
    def snapping(self, utworz=False):
        e = self.korzen.find('snapping-settings')
        if e is None and utworz:
            e = ET.SubElement(self.korzen, 'snapping-settings')
        return e


# ---------------------------------------------------------------------- stempel

def kopia(sciezka, znacznik):
    cel = '%s.bak_%s' % (sciezka, znacznik)
    if not os.path.exists(cel):
        shutil.copy2(sciezka, cel)
    return cel


def stempel_czytaj(gpkg):
    if not gpkg or not os.path.exists(gpkg):
        return {}
    con = sqlite3.connect(gpkg)
    try:
        con.execute('SELECT 1 FROM "%s" LIMIT 1' % TABELA_STEMPLA)
    except sqlite3.OperationalError:
        con.close()
        return {}
    out = {r[0]: {'wersja': r[1], 'data': r[2], 'zrodlo': r[3]}
           for r in con.execute('SELECT modul, wersja, data, zrodlo FROM "%s"' % TABELA_STEMPLA)}
    con.close()
    return out


def stempel_zapisz(gpkg, mid, wersja, zrodlo, kto):
    con = sqlite3.connect(gpkg)
    con.execute('CREATE TABLE IF NOT EXISTS "%s" ('
                'modul TEXT PRIMARY KEY, wersja INTEGER NOT NULL, '
                'data TEXT NOT NULL, zrodlo TEXT, przez TEXT)' % TABELA_STEMPLA)
    con.execute('INSERT INTO "%s" (modul, wersja, data, zrodlo, przez) VALUES (?,?,?,?,?) '
                'ON CONFLICT(modul) DO UPDATE SET wersja=excluded.wersja, data=excluded.data, '
                'zrodlo=excluded.zrodlo, przez=excluded.przez' % TABELA_STEMPLA,
                (mid, wersja, datetime.datetime.now().isoformat(timespec='seconds'), zrodlo, kto))
    con.commit()
    con.close()


def stempel_skasuj(gpkg, mid):
    con = sqlite3.connect(gpkg)
    try:
        con.execute('DELETE FROM "%s" WHERE modul=?' % TABELA_STEMPLA, (mid,))
        con.commit()
    except sqlite3.OperationalError:
        pass
    con.close()


# ------------------------------------------------------------------ wybór warstw

def wybierz_warstwy(proj, wybor):
    """Zwraca [(id, nazwa)] warstw pasujących do opisu wyboru z modułu."""
    geometrie = wybor.get('geometria')
    pomin = set(wybor.get('pomin_nazwy', []))
    tylko_edytowalne = wybor.get('tylko_edytowalne', True)
    out = []
    for wid, nazwa, geom, tylko_odczyt in proj.warstwy():
        if geometrie and geom not in geometrie:
            continue
        if tylko_edytowalne and tylko_odczyt:
            continue
        if nazwa in pomin:
            continue
        out.append((wid, nazwa))
    return out


# ------------------------------------------------------------------------ kroki
# Każdy krok umie dwie rzeczy: powiedzieć, czy jest spełniony (sprawdz),
# i doprowadzić do spełnienia (zastosuj). Trzecia, cofnij, bywa niemożliwa
# i wtedy moduł deklaruje "odwracalny": false.

def krok_sprawdz(proj, krok):
    typ = krok['typ']

    if typ == 'wlasciwosc':
        return str(proj.czytaj_wlasciwosc(krok['grupa'], krok['klucz'])) == str(krok['wartosc'])

    if typ == 'wlasciwosc_warstwy':
        obecne = proj.czytaj_wlasciwosc(krok['grupa'], krok['klucz']) or []
        chciane = [wid for wid, _ in wybierz_warstwy(proj, krok.get('wybor', {}))]
        if not chciane:
            return True
        return set(obecne) == set(chciane)

    if typ == 'snapping':
        e = proj.snapping()
        if e is None:
            return False
        return all(e.get(k) == str(v) for k, v in krok['atrybuty'].items())

    if typ == 'plik_obok':
        return os.path.exists(os.path.join(proj.katalog, krok['nazwa']))

    if typ == 'kontrola_klawiszy':
        p = os.path.join(proj.katalog, krok.get('nazwa', 'workfield_klawisze.json'))
        if not os.path.exists(p):
            return False
        try:
            with open(p, encoding='utf-8') as f:
                d = json.load(f)
        except Exception:
            return False
        kl = d.get('klawisze')
        if not isinstance(kl, list) or not kl:
            return False
        nazwy = {n for _, n, _, _ in proj.warstwy()}
        for k in kl:
            # Pułapka z QfQuickCaptureBar.loadDefinitions(): klucz to "etykieta",
            # nie "nazwa". Zły klucz daje w logu "definicje z pliku, 0 klawiszy".
            if 'etykieta' not in k or 'warstwa' not in k:
                return False
            if k['warstwa'] not in nazwy:
                return False
        return True

    if typ == 'warstwa_istnieje':
        return krok['nazwa'] in {n for _, n, _, _ in proj.warstwy()}

    if typ == 'tabele_gpkg':
        g = proj.gpkg_glowny()
        if not g:
            return False
        con = sqlite3.connect(g)
        sa = {r[0].upper() for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        con.close()
        wzor = krok['wzorzec'].upper().replace('%', '')
        return any(t.startswith(wzor) for t in sa)

    raise SystemExit('Nieznany typ kroku: %s' % typ)


def krok_zastosuj(proj, krok):
    """Zwraca opis tego, co zrobiono — albo None, gdy krok nie jest deklaratywny."""
    typ = krok['typ']

    if typ == 'wlasciwosc':
        proj.ustaw_wlasciwosc(krok['grupa'], krok['klucz'],
                              krok.get('typ_wartosci', 'int'), krok['wartosc'])
        return '%s/%s = %s' % (krok['grupa'], krok['klucz'], krok['wartosc'])

    if typ == 'wlasciwosc_warstwy':
        pary = wybierz_warstwy(proj, krok.get('wybor', {}))
        proj.ustaw_wlasciwosc(krok['grupa'], krok['klucz'], 'QStringList', [w for w, _ in pary])
        return '%s/%s = %d warstw (%s)' % (krok['grupa'], krok['klucz'], len(pary),
                                           ', '.join(n for _, n in pary) or '—')

    if typ == 'snapping':
        e = proj.snapping(utworz=True)
        for k, v in krok['atrybuty'].items():
            e.set(k, str(v))
        return 'przyciąganie: ' + ', '.join('%s=%s' % (k, v) for k, v in krok['atrybuty'].items())

    return None


def krok_cofnij(proj, krok):
    typ = krok['typ']
    if typ == 'wlasciwosc' and 'wartosc_cofniecia' in krok:
        proj.ustaw_wlasciwosc(krok['grupa'], krok['klucz'],
                              krok.get('typ_wartosci', 'int'), krok['wartosc_cofniecia'])
        return '%s/%s = %s' % (krok['grupa'], krok['klucz'], krok['wartosc_cofniecia'])
    if typ == 'wlasciwosc_warstwy':
        proj.usun_wlasciwosc(krok['grupa'], krok['klucz'])
        return 'usunięto %s/%s' % (krok['grupa'], krok['klucz'])
    if typ == 'snapping' and 'atrybuty_cofniecia' in krok:
        e = proj.snapping(utworz=True)
        for k, v in krok['atrybuty_cofniecia'].items():
            e.set(k, str(v))
        return 'przyciąganie cofnięte'
    return None


# ----------------------------------------------------------------------- ocena

def dotyczy(proj, modul):
    """Czy moduł ma tu w ogóle zastosowanie."""
    war = modul.get('dotyczy')
    if not war:
        return True
    if 'geometria' in war:
        geom = {g for _, _, g, _ in proj.warstwy()}
        if not (set(war['geometria']) & geom):
            return False
    return True


def oswiadczenie(proj, modul, stempel):
    """Stan modułu w projekcie: (stan, [niespełnione kroki])."""
    if not dotyczy(proj, modul):
        return NIE_DOTYCZY, []

    kroki = modul.get('kroki', [])
    braki = [k for k in kroki if not krok_sprawdz(proj, k)]
    wpis = stempel.get(modul['id'])
    stan_ok = not braki

    if wpis is None:
        if stan_ok and kroki:
            # stan zgodny, ale projekt o tym nie wie — np. zrobione ręcznie
            return STARSZY, []
        return BRAK, braki
    if not stan_ok:
        return ROZJECHANY, braki
    if wpis['wersja'] < modul['wersja']:
        return STARSZY, []
    return ZALOZONY, []


# -------------------------------------------------------------------- czasowniki

def czasownik_spis(kat):
    print('Katalog wyposażenia: %s (źródło: %s)\n' % (kat.sciezka, kat.zrodlo))
    for mid in kat.kolejnosc():
        m = kat.moduly[mid]
        print('  %-16s v%-3d %-11s %-14s %s' % (
            m['id'], m['wersja'], m['rodzaj'], '/'.join(m.get('gdzie', [])), m['nazwa']))
        if m.get('wymaga'):
            print('  %-16s      wymaga: %s' % ('', ', '.join(m['wymaga'])))
    print()


def czasownik_sprawdz(kat, sciezka, glosno=False):
    projekty = znajdz_projekty(sciezka)
    sieroty = znajdz_sieroty(sciezka)
    if not projekty and not sieroty:
        raise SystemExit('Nie znalazłem żadnego projektu w: %s' % sciezka)
    if not projekty:
        wypisz_sieroty(sieroty)
        return

    mids = kat.kolejnosc()
    szer = max(24, max(len(os.path.basename(os.path.dirname(p))) for p in projekty) + 2)

    print()
    print(' ' * szer + ''.join('%-7s' % m[:6] for m in mids))
    print('-' * (szer + 7 * len(mids)))

    rozjazdy = 0
    for p in projekty:
        proj = Projekt(p)
        st = stempel_czytaj(proj.gpkg_glowny())
        wiersz = '%-*s' % (szer, proj.nazwa[:szer - 1])
        szczegoly = []
        for mid in mids:
            stan, braki = oswiadczenie(proj, kat.moduly[mid], st)
            wiersz += '%-7s' % ZNAKI[stan]
            if stan in (BRAK, ROZJECHANY, STARSZY) and braki:
                rozjazdy += 1
                szczegoly.append((mid, stan, braki))
        print(wiersz)
        if glosno:
            for mid, stan, braki in szczegoly:
                for k in braki:
                    print('        %-14s %s: %s' % (mid, stan, opis_kroku(k)))

    print('-' * (szer + 7 * len(mids)))
    print('OK = założony   STAR = starszy/niestemplowany   BRAK = nie ma')
    print('ROZJ = stempel mówi, że jest, a nie ma   - = nie dotyczy')
    if rozjazdy:
        print('\nDo doposażenia: %d pozycji. Szczegóły: dodaj --glosno' % rozjazdy)
    print()
    if sieroty:
        wypisz_sieroty(sieroty)


def wypisz_sieroty(sieroty):
    """Katalogi z danymi, ale bez pliku projektu — najgorszy możliwy stan szablonu."""
    print('BEZ PLIKU PROJEKTU (są dane, nie ma czego otworzyć):')
    for k, pliki in sieroty:
        print('  %-40s %s' % (os.path.basename(k), ', '.join(pliki)))
    print()


def opis_kroku(k):
    t = k['typ']
    if t == 'wlasciwosc':
        return '%s/%s ma być %s' % (k['grupa'], k['klucz'], k['wartosc'])
    if t == 'wlasciwosc_warstwy':
        return '%s/%s — lista warstw' % (k['grupa'], k['klucz'])
    if t == 'snapping':
        return 'przyciąganie: ' + ', '.join('%s=%s' % (a, b) for a, b in k['atrybuty'].items())
    if t == 'plik_obok':
        return 'brak pliku %s' % k['nazwa']
    if t == 'kontrola_klawiszy':
        return 'klawisze paska: brak pliku albo zła treść'
    if t == 'warstwa_istnieje':
        return 'brak warstwy %s' % k['nazwa']
    if t == 'tabele_gpkg':
        return 'brak tabel %s w GeoPackage' % k['wzorzec']
    return t


def czasownik_doposaz(kat, sciezka, wybrane, wszystko, kto):
    proj = Projekt(sciezka)
    gpkg = proj.gpkg_glowny()
    if gpkg is None:
        raise SystemExit('Projekt nie ma GeoPackage — nie ma gdzie postawić stempla.')
    st = stempel_czytaj(gpkg)

    mids = kat.kolejnosc(wybrane if wybrane else None)
    if not wszystko and not wybrane:
        mids = [m for m in mids
                if oswiadczenie(proj, kat.moduly[m], st)[0] in (BRAK, ROZJECHANY, STARSZY)]

    if not mids:
        print('Nic do zrobienia — projekt ma pełne wyposażenie.')
        return

    znacznik = stempel_czasu()
    zmieniono_projekt = False
    print('Projekt: %s' % proj.plik)
    print('Kopie zapasowe ze znacznikiem: %s\n' % znacznik)

    for mid in mids:
        m = kat.moduly[mid]
        if not dotyczy(proj, m):
            print('  %-16s pomijam — nie dotyczy tego projektu' % mid)
            continue
        # Stan już zgodny, tylko bez stempla — np. rzecz założona zanim stempel
        # w ogóle istniał. Nie ma co robić drugi raz, wystarczy przyznać się.
        if all(krok_sprawdz(proj, k) for k in m.get('kroki', [])):
            stempel_zapisz(gpkg, mid, m['wersja'], m.get('_zrodlo', 'lokalny'), kto)
            print('  %-16s BYŁ JUŻ ZAŁOŻONY — dostempluję v%d' % (mid, m['wersja']))
            continue
        if m['rodzaj'] == 'struktura':
            print('  %-16s WYMAGA BIURA — uruchom w konsoli Pythona QGIS-a:' % mid)
            print('  %-16s   %s' % ('', m.get('skrypt', '(brak wskazanego skryptu)')))
            continue
        if any(k['typ'] in ('plik_obok', 'kontrola_klawiszy') and not krok_sprawdz(proj, k)
               for k in m.get('kroki', [])):
            print('  %-16s WYMAGA DECYZJI — %s' % (mid, m.get('podpowiedz', 'brak treści do wpisania')))
            continue

        opisy = []
        for k in m.get('kroki', []):
            o = krok_zastosuj(proj, k)
            if o:
                opisy.append(o)
                zmieniono_projekt = True
        stempel_zapisz(gpkg, mid, m['wersja'], m.get('_zrodlo', 'lokalny'), kto)
        print('  %-16s ZAŁOŻONY v%d' % (mid, m['wersja']))
        for o in opisy:
            print('  %-16s   %s' % ('', o))

    if zmieniono_projekt:
        kopia(gpkg, znacznik)
        proj.zapisz(znacznik)
        print('\nZapisano projekt. Otwórz go w QGIS-ie i sprawdź, zanim wyjedziesz.')
    else:
        print('\nPliku projektu nie ruszałem.')


def czasownik_zdejmij(kat, sciezka, wybrane, kto):
    if not wybrane:
        raise SystemExit('Powiedz, co zdjąć: --moduly bez_nakladania')
    proj = Projekt(sciezka)
    gpkg = proj.gpkg_glowny()
    znacznik = stempel_czasu()
    ruszone = False
    for mid in wybrane:
        m = kat.moduly.get(mid)
        if m is None:
            raise SystemExit('Katalog nie zna modułu: %s' % mid)
        if not m.get('odwracalny', True):
            print('  %-16s NIEODWRACALNY — zdejmowanie należy do biura' % mid)
            continue
        for k in m.get('kroki', []):
            o = krok_cofnij(proj, k)
            if o:
                ruszone = True
                print('  %-16s %s' % (mid, o))
        stempel_skasuj(gpkg, mid)
        print('  %-16s ZDJĘTY' % mid)
    if ruszone:
        kopia(gpkg, znacznik)
        proj.zapisz(znacznik)
        print('\nZapisano projekt.')


def znajdz_sieroty(sciezka):
    """Katalogi z GeoPackage, ale bez .qgs/.qgz — dane bez projektu."""
    sciezka = os.path.abspath(sciezka)
    if os.path.isfile(sciezka):
        return []
    out = []
    for korzen, katalogi, pliki in os.walk(sciezka):
        katalogi[:] = [d for d in katalogi if not d.startswith('.') and d != 'DCIM']
        if any(p.endswith(('.qgs', '.qgz')) for p in pliki):
            katalogi[:] = []
            continue
        gp = sorted(p for p in pliki if p.lower().endswith('.gpkg'))
        if gp:
            out.append((korzen, gp))
    return out


def znajdz_projekty(sciezka):
    sciezka = os.path.abspath(sciezka)
    if os.path.isfile(sciezka):
        return [sciezka]
    out = []
    for korzen, katalogi, pliki in os.walk(sciezka):
        katalogi[:] = [d for d in katalogi if not d.startswith('.') and d != 'DCIM']
        znalezione = sorted(p for p in pliki if p.endswith(('.qgs', '.qgz')))
        if znalezione:
            out.append(os.path.join(korzen, znalezione[0]))
            katalogi[:] = []
    return out


# ------------------------------------------------------------------------ wejście

def main(argv=None):
    ap = argparse.ArgumentParser(
        description='Wyposażenie WorkField — sprawdzanie i doposażanie projektów.')
    ap.add_argument('czasownik', choices=['spis', 'sprawdz', 'doposaz', 'zdejmij'])
    ap.add_argument('sciezka', nargs='?', help='projekt albo katalog do przejrzenia')
    ap.add_argument('--katalog', default=None, help='ścieżka do katalog.json')
    ap.add_argument('--moduly', default='', help='lista modułów po przecinku')
    ap.add_argument('--wszystko', action='store_true', help='doposaż także te już założone')
    ap.add_argument('--glosno', action='store_true', help='wypisz, czego dokładnie brakuje')
    ap.add_argument('--kto', default=os.environ.get('USER', 'biuro'))
    a = ap.parse_args(argv)

    domyslny = a.katalog or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'wyposazenie', 'katalog.json')
    if not os.path.exists(domyslny):
        raise SystemExit('Nie widzę katalogu wyposażenia: %s\n'
                         '(wskaż go przez --katalog)' % domyslny)
    kat = Katalog(domyslny)
    wybrane = [x.strip() for x in a.moduly.split(',') if x.strip()]

    if a.czasownik == 'spis':
        return czasownik_spis(kat)
    if a.sciezka is None:
        raise SystemExit('Podaj ścieżkę do projektu albo katalogu.')
    if a.czasownik == 'sprawdz':
        return czasownik_sprawdz(kat, a.sciezka, a.glosno)
    if a.czasownik == 'doposaz':
        return czasownik_doposaz(kat, a.sciezka, wybrane, a.wszystko, a.kto)
    if a.czasownik == 'zdejmij':
        return czasownik_zdejmij(kat, a.sciezka, wybrane, a.kto)


if __name__ == '__main__':
    sys.exit(main())
