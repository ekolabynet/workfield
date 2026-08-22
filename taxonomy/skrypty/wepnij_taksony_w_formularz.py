# -*- coding: utf-8 -*-
"""
wepnij_taksony_w_formularz.py — kontrola miękka gatunku + podgląd progu.

DO URUCHOMIENIA W KONSOLI QGIS (Wtyczki → Konsola Pythona), przy otwartym
projekcie. NIE testowane u mnie — w tej sesji nie mam QGIS-a. Uruchom
najpierw z `SUCHO = True`: nic nie zmienia, tylko wypisuje, co by zrobił.

Co robi:
  1. Wpina tabelę TAKSONY do projektu, jeśli jej tam nie ma.
  2. Zakłada na polu GATUNEK OGRANICZENIE MIĘKKIE: wpis spoza słownika
     ostrzega żółtym paskiem, ale NIE blokuje zapisu. Decyzja z 16.08 stoi:
     GATUNEK zostaje tekstem, bo bywa wpisywany skrótem.
  3. Dokłada pola wirtualne (żyją w projekcie, nie w bazie):
       _PROG      — ustawowy próg obwodu na 5 cm dla wpisanego gatunku,
       _PROG_INFO — słowna podpowiedź: czy pomiar przekracza próg,
       _IGO       — status prawny IGO, jeśli jest,
       _OCHRONA   — ochrona gatunkowa, jeśli jest.
  4. Ustawia te pola jako tylko-do-odczytu i wrzuca je do zakładki formularza.

Pola wirtualne są policzone przy każdym otwarciu rekordu i NIE zapisują się
do GPKG. To celowe: prawo się zmienia, a wyliczona wartość sprzed roku
w bazie byłaby gorsza niż jej brak.
"""

from qgis.core import (QgsProject, QgsVectorLayer, QgsField, QgsFieldConstraints,
                       QgsExpression)
from qgis.PyQt.QtCore import QVariant

SUCHO = True                      # najpierw True, potem False
WARSTWA = "drzewa"                # warstwa robocza z polem GATUNEK
POLE = "GATUNEK"
POLE_OBWODU = "OBW_5"             # tekstowe: "74", ">65", "60+36"
TABELA = "TAKSONY"

# --- wyrażenia -------------------------------------------------------------
# aggregate() sięga do innej warstwy projektu; attribute(@parent, …) podaje
# wartość z EDYTOWANEGO rekordu do filtra.
KONTROLA = (
    '"{p}" IS NULL OR "{p}" = \'\' OR array_contains('
    "aggregate('{t}', 'array_agg', \"NAZWA\"), \"{p}\")"
).format(p=POLE, t=TABELA)

PROG = (
    "aggregate('{t}', 'max', \"PROG_CM\", "
    "filter:= \"NAZWA\" = attribute(@parent, '{p}'))"
).format(t=TABELA, p=POLE)

# OBW_5 jest tekstem i niesie trzy stany (74, >65, 60+36) — do porównania
# bierzemy pierwszą liczbę, a przy wielopniu sumujemy człony.
OBWOD = (
    "coalesce(array_sum(array_foreach("
    "string_to_array(regexp_replace(\"{o}\", '[^0-9+]', ''), '+'), "
    "to_int(@element))), 0)"
).format(o=POLE_OBWODU)

PROG_INFO = (
    "CASE WHEN \"_PROG\" IS NULL THEN 'gatunek spoza słownika' "
    "WHEN {ob} = 0 THEN 'brak pomiaru' "
    "WHEN {ob} > \"_PROG\" THEN 'ponad próg ' || \"_PROG\" || ' cm — zezwolenie' "
    "ELSE 'poniżej progu ' || \"_PROG\" || ' cm' END"
).format(ob=OBWOD)

IGO = ("aggregate('{t}', 'concatenate', \"IGO\", "
       "filter:= \"NAZWA\" = attribute(@parent, '{p}'), concatenator:='')"
       ).format(t=TABELA, p=POLE)

OCHRONA = ("aggregate('{t}', 'concatenate', \"OCHRONA\", "
           "filter:= \"NAZWA\" = attribute(@parent, '{p}'), concatenator:='')"
           ).format(t=TABELA, p=POLE)

WIRTUALNE = [("_PROG", QVariant.Int, PROG),
             ("_PROG_INFO", QVariant.String, PROG_INFO),
             ("_IGO", QVariant.String, IGO),
             ("_OCHRONA", QVariant.String, OCHRONA)]


def znajdz(nazwa):
    w = QgsProject.instance().mapLayersByName(nazwa)
    return w[0] if w else None


def main():
    projekt = QgsProject.instance()
    warstwa = znajdz(WARSTWA)
    if warstwa is None:
        print("BŁĄD: nie ma warstwy %r w projekcie." % WARSTWA)
        return

    if znajdz(TABELA) is None:
        zrodlo = warstwa.source().split("|")[0]
        tab = QgsVectorLayer("%s|layername=%s" % (zrodlo, TABELA), TABELA, "ogr")
        if not tab.isValid():
            print("BŁĄD: nie mogę wczytać tabeli %s z %s" % (TABELA, zrodlo))
            print("      Czy zbuduj_taksony.py zapisał ją do TEJ bazy?")
            return
        print("Wczytana tabela %s: %d wierszy" % (TABELA, tab.featureCount()))
        if not SUCHO:
            projekt.addMapLayer(tab, False)
            projekt.layerTreeRoot().insertLayer(-1, tab)
    else:
        print("Tabela %s już jest w projekcie." % TABELA)

    for wyr in (KONTROLA, PROG, PROG_INFO, IGO, OCHRONA):
        e = QgsExpression(wyr)
        if e.hasParserError():
            print("BŁĄD wyrażenia: %s\n  %s" % (e.parserErrorString(), wyr))
            return
    print("Wyrażenia sparsowane bez błędu.")

    idx = warstwa.fields().indexOf(POLE)
    if idx < 0:
        print("BŁĄD: warstwa %s nie ma pola %s" % (WARSTWA, POLE))
        return

    print("\nOgraniczenie miękkie na %s:\n  %s" % (POLE, KONTROLA))
    for nazwa, typ, wyr in WIRTUALNE:
        print("Pole wirtualne %s:\n  %s" % (nazwa, wyr))

    if SUCHO:
        print("\nSUCHO = True — nic nie zmieniono. Ustaw False i uruchom ponownie.")
        return

    warstwa.setConstraintExpression(
        idx, KONTROLA, "Gatunek spoza słownika TAKSONY — sprawdź pisownię")
    warstwa.setFieldConstraint(idx, QgsFieldConstraints.ConstraintExpression,
                               QgsFieldConstraints.ConstraintStrengthSoft)

    istnieje = set(warstwa.fields().names())
    for nazwa, typ, wyr in WIRTUALNE:
        if nazwa in istnieje:
            print("Pominięte (już jest): %s" % nazwa)
            continue
        warstwa.addExpressionField(wyr, QgsField(nazwa, typ))

    konf = warstwa.editFormConfig()
    for nazwa, _t, _w in WIRTUALNE:
        i = warstwa.fields().indexOf(nazwa)
        if i >= 0:
            konf.setReadOnly(i, True)
    warstwa.setEditFormConfig(konf)

    print("\nGotowe. ZAPISZ PROJEKT — pola wirtualne i ograniczenie żyją "
          "w pliku projektu, nie w GPKG.")


main()
