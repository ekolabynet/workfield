#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Kontrola przepisu WorkField — zanim pojedzie na telefon.

Build Androida trwa godziny, a błąd w przepisie widać dopiero w terenie.
Ten skrypt czyta przepis tak, jak przeczyta go QfPrzepis.qml, i sprawdza
to, co da się sprawdzić bez QGIS-a: spójność nazw, typy pól, czy relacje
wskazują na istniejące warstwy, czy kafle paska mają klucz `etykieta`
i czy pola wymienione w zakładkach w ogóle w warstwie są.

UŻYCIE:
    python3 skrypty/sprawdz_przepis.py wyposazenie/przepisy/*.json
"""

import json
import sys

# Typy pól przyjmowane przez LayerUtils::createEmptyLayer (layerutils.cpp)
TYPY_POL = {'text', 'multiline', 'integer', 'real', 'date', 'datetime', 'bool'}

# Typy geometrii przyjmowane przez QgsWkbTypes::parseType
GEOMETRIE = {'Point', 'LineString', 'Polygon', 'MultiPoint',
             'MultiLineString', 'MultiPolygon', 'NoGeometry'}

# Qgis::SnappingMode / SnappingTypes / MapToolUnit / AvoidIntersectionsMode
TRYBY_PRZYCIAGANIA = {1, 2, 3}
JEDNOSTKI = {0, 1, 2}
TRYBY_NAKLADANIA = {0, 1, 2}


def sprawdz(sciezka):
    bledy, ostrzezenia = [], []

    try:
        with open(sciezka, encoding='utf-8') as f:
            p = json.load(f)
    except Exception as e:
        return ['przepis się nie parsuje: %s' % e], []

    for klucz in ('id', 'wersja', 'nazwa', 'warstwy'):
        if klucz not in p:
            bledy.append('brak pola "%s"' % klucz)
    if bledy:
        return bledy, ostrzezenia

    warstwy = {w.get('nazwa'): w for w in p['warstwy']}
    if None in warstwy:
        bledy.append('warstwa bez nazwy')

    # --- warstwy, pola, geometrie
    for nazwa, w in warstwy.items():
        geom = w.get('geometria', 'NoGeometry')
        if geom not in GEOMETRIE:
            bledy.append('%s: nieznana geometria "%s"' % (nazwa, geom))

        pola = {f.get('name') for f in w.get('pola', [])}
        for f in w.get('pola', []):
            if f.get('type') not in TYPY_POL:
                bledy.append('%s.%s: nieznany typ "%s" (dozwolone: %s)'
                             % (nazwa, f.get('name'), f.get('type'), ', '.join(sorted(TYPY_POL))))

        # fid jest zakładany przez GPKG, nie wymieniamy go w przepisie
        if 'fid' in pola:
            ostrzezenia.append('%s: pole "fid" zakłada GeoPackage sam — usuń z przepisu' % nazwa)

        znane = pola | {'fid'}
        for sekcja in ('aliasy', 'widgety', 'domyslne', 'ograniczenia'):
            for pole in (w.get(sekcja) or {}):
                if pole not in znane:
                    bledy.append('%s.%s: pole "%s" nie istnieje w tej warstwie' % (nazwa, sekcja, pole))

        for z in w.get('zakladki', []):
            if 'relacja' in z:
                continue
            for pole in z.get('pola', []):
                if pole not in znane:
                    # QfPrzepis pomija je po cichu, ale w przepisie to zwykle literówka
                    ostrzezenia.append('%s: zakładka "%s" wymienia pole "%s", którego nie ma'
                                       % (nazwa, z.get('tytul'), pole))

    # --- relacje
    relacje = {}
    for r in p.get('relacje', []):
        rid = r.get('id')
        if not rid:
            bledy.append('relacja bez id')
            continue
        relacje[rid] = r
        for rola in ('rodzic', 'dziecko'):
            if r.get(rola) not in warstwy:
                bledy.append('relacja %s: %s "%s" nie jest warstwą tego przepisu'
                             % (rid, rola, r.get(rola)))
        dziecko = warstwy.get(r.get('dziecko'), {})
        pola_dziecka = {f.get('name') for f in dziecko.get('pola', [])}
        if r.get('poleDziecka') not in pola_dziecka:
            bledy.append('relacja %s: dziecko nie ma pola "%s"' % (rid, r.get('poleDziecka')))

    # --- zakładki relacji wskazujące na nieistniejącą relację
    for nazwa, w in warstwy.items():
        for z in w.get('zakladki', []):
            rid = z.get('relacja')
            if rid and rid not in relacje:
                bledy.append('%s: zakładka "%s" wskazuje na relację "%s", której przepis nie zakłada'
                             % (nazwa, z.get('tytul'), rid))

    # --- ustawienia projektu
    proj = p.get('projekt', {})
    sn = proj.get('przyciaganie')
    if sn:
        if sn.get('tryb') not in TRYBY_PRZYCIAGANIA:
            bledy.append('przyciąganie: tryb %s poza {1,2,3}' % sn.get('tryb'))
        if sn.get('jednostka') not in JEDNOSTKI:
            bledy.append('przyciąganie: jednostka %s poza {0,1,2}' % sn.get('jednostka'))
        if not sn.get('typ'):
            ostrzezenia.append('przyciąganie: typ = 0 znaczy "nie przyciągaj do niczego"')
    un = proj.get('unikajNakladania')
    if un:
        if un.get('tryb') not in TRYBY_NAKLADANIA:
            bledy.append('unikajNakladania: tryb %s poza {0,1,2}' % un.get('tryb'))
        for nazwa in un.get('warstwy', []):
            if nazwa not in warstwy:
                bledy.append('unikajNakladania: warstwa "%s" nie istnieje' % nazwa)
            elif warstwy[nazwa].get('geometria', '') not in ('Polygon', 'MultiPolygon'):
                bledy.append('unikajNakladania: warstwa "%s" nie jest poligonowa' % nazwa)
        if un.get('tryb') == 2 and not un.get('warstwy'):
            ostrzezenia.append('unikajNakladania: tryb 2 z pustą listą — silnik weźmie '
                               'wszystkie edytowalne warstwy poligonowe')

    # --- kafle paska (pułapka: klucz "etykieta", nie "nazwa")
    for plik in p.get('pliki', []):
        if 'klawisze' not in plik.get('nazwa', ''):
            continue
        tresc = plik.get('tresc', {})
        kafle = tresc.get('klawisze')
        if not isinstance(kafle, list) or not kafle:
            bledy.append('%s: brak listy "klawisze"' % plik.get('nazwa'))
            continue
        for k in kafle:
            if 'etykieta' not in k:
                bledy.append('%s: kafel bez klucza "etykieta" (klucz "nazwa" daje pusty pasek)'
                             % plik.get('nazwa'))
            if k.get('warstwa') not in warstwy:
                bledy.append('%s: kafel "%s" wskazuje na warstwę "%s", której przepis nie zakłada'
                             % (plik.get('nazwa'), k.get('etykieta', '?'), k.get('warstwa')))

    return bledy, ostrzezenia


def main(argv):
    if not argv:
        raise SystemExit(__doc__)
    zle = 0
    for sciezka in argv:
        bledy, ostrzezenia = sprawdz(sciezka)
        print('=== %s' % sciezka)
        for b in bledy:
            print('  BŁĄD       %s' % b)
        for o in ostrzezenia:
            print('  ostrzeżenie %s' % o)
        if not bledy and not ostrzezenia:
            print('  bez zastrzeżeń')
        print()
        zle += len(bledy)
    return 1 if zle else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
