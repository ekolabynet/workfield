# -*- coding: utf-8 -*-
"""
Budowa szablonu WorkFieldGIS — inwentaryzacja dendrologiczna.

URUCHOMIENIE:
  QGIS -> Wtyczki -> Konsola Pythona -> ikona "Pokaż edytor" -> otwórz ten plik
  -> Uruchom. Skrypt tworzy dane.gpkg i projekt.qgs obok siebie, w katalogu,
  w którym leży.

Nazwy warstw (drzewa / grupy / uwagi) rozpoznaje pasek szybkiego przechwytu
WorkFieldGIS — NIE ZMIENIAĆ bez poprawienia workfield_klawisze.json.

ZAŁOŻENIA METODYCZNE (wynikają z metody OpenVTA, nie zmieniać bez decyzji):

  * Pole UWAGI to PROZA — rekord opuszcza teren w formie finalnej. Aplikacja
    nigdy go nie przetwarza. Rozwijanie skrótów robi klawiatura predykcyjna
    (Gboard), nie formularz. Dlatego UWAGI jest zwykłym polem tekstowym bez
    ograniczeń i bez podpowiedzi.
  * GATUNEK też bywa wprowadzany skrótem klawiatury, więc jest polem
    TEKSTOWYM, nie listą wyboru. Zgodność ze słownikiem sprawdza miękkie
    ograniczenie — ostrzega, nie blokuje. Spację doklejaną przez Gboard
    przycina parser w biurze, nie aplikacja.
  * Oba pola obwodów są TEKSTOWE, bo niosą trzy różne stany: pomiar ("74"),
    wartość cenzurowaną (">65") i wielopień ("60+36"), a przy krzewach
    powierzchnię (">25m2"). Rozbicie ich wymuszałoby decyzję w terenie tam,
    gdzie metoda świadomie jej nie wymusza. Parsuje się je przy odczycie.
  * Kolumny mają nazwy techniczne, a pełne opisy idą jako ALIASY — w terenie
    i na wydruku widać opis, w wyrażeniach i skryptach krótką nazwę.
    Mapowanie na nagłówki oczekiwane przez odbiorcę robi eksport.

Wymaga: QGIS z GDAL (czyli każdej normalnej instalacji QGIS-a).
"""
import os
import json

from qgis.core import (
    QgsProject, QgsVectorLayer, QgsEditorWidgetSetup, QgsDefaultValue,
    QgsFieldConstraints, QgsAttributeEditorContainer, QgsAttributeEditorField,
    QgsEditFormConfig, QgsRelation, QgsAttributeEditorRelation,
    QgsCoordinateReferenceSystem,
)
from qgis.core import QgsExpressionContextUtils as ECU

KAT = os.path.dirname(os.path.abspath(__file__))
GPKG = os.path.join(KAT, 'dane.gpkg')
QGS = os.path.join(KAT, 'projekt.qgs')
CRS = 'EPSG:2178'          # PUWG 2000 strefa 7
CRS_KOD = 2178

# ============================================================ definicje warstw
# (nazwa_kolumny, typ, alias)  — typ: 'str' | 'real' | 'int'
POLA_DRZEWA = [
    ('NR_INW', 'str', 'nr inw.'),
    ('DECYZJA', 'str', 'decyzja Projektowa'),
    ('KATEGORIA', 'str', 'Kategoria'),
    ('GATUNEK', 'str', 'Nazwa techniczna'),
    ('NAZWA_PL', 'str', 'Nazwa polska'),
    ('OBW_5', 'str', 'Obwody pni [cm] na wys. 5cm lub powierzchnia krzewów [m2]'),
    ('OBW_130', 'str', 'Obwody pni [cm] na wys. 130cm lub faktyczna powierzchnia [m2]'),
    ('KORONA_SZER', 'real', 'Szerokość korony [m]'),
    ('WYSOKOSC', 'real', 'Wysokość [m]'),
    ('STAN', 'int', 'Stan zdrowotny [0-5]'),
    ('UWAGI', 'str', 'Uwagi'),
    ('SZEROKOSC_M', 'real', 'szerokosc_M'),
    ('RTK_DOKL', 'real', 'Dokładność RTK [m]'),
    ('RTK_KAT', 'real', 'Kąt podniesienia [°]'),
    ('RTK_SAT', 'int', 'Satelity'),
    ('DATA', 'str', 'Data'),
    ('WYKONAWCA', 'str', 'Wykonawca'),
]

POLA_GRUPY = [
    ('NR_INW', 'str', 'nr inw.'),
    ('DECYZJA', 'str', 'decyzja Projektowa'),
    ('KATEGORIA', 'str', 'Kategoria'),
    ('GATUNKI', 'str', 'Skład gatunkowy'),
    ('POW_M2', 'real', 'Powierzchnia [m2]'),
    ('WYSOKOSC', 'real', 'Wysokość [m]'),
    ('STAN', 'int', 'Stan zdrowotny [0-5]'),
    ('UWAGI', 'str', 'Uwagi'),
    ('DATA', 'str', 'Data'),
    ('WYKONAWCA', 'str', 'Wykonawca'),
]

POLA_UWAGI = [
    ('TRESC', 'str', 'Treść'),
    ('DATA', 'str', 'Data'),
    ('WYKONAWCA', 'str', 'Wykonawca'),
]

POLA_ZASIEG = [
    ('NAZWA', 'str', 'Nazwa obszaru'),
    ('POW_M2', 'real', 'Powierzchnia [m2]'),
]

# Warstwa pomocnicza dla kafla "bez zdjęcia". To ona odblokowuje trzy rzeczy
# naraz (QfQuickCaptureBar.captureInto, l. 1114-1130): czysty punkt bez
# uruchamiania aparatu, serię wierzchołków pod długim przytrzymaniem oraz
# dokładanie wierzchołków z GNSS do rysowanej geometrii. Bez niej obrysu grupy
# nie da się obejść pieszo. Przełączniki KTW i ODL własnej warstwy nie mają —
# zapisują do warstwy tapniętego kafla.
POLA_TYCZENIE = [
    ('OPIS', 'str', 'Opis'),
    ('DATA', 'str', 'Data'),
    ('WYKONAWCA', 'str', 'Wykonawca'),
]

# Słownik taksonów. PROG_CM to ustawowy próg obwodu na wys. 5 cm, powyżej
# którego wycinka wymaga zezwolenia — 80 dla topoli, wierzb, klonu
# jesionolistnego i srebrzystego, 65 dla kasztanowca, robinii i platanu,
# 50 dla pozostałych. Trzymamy go przy gatunku, żeby dało się z niego
# korzystać przy kontroli i przy opracowaniu.
POLA_TAKSONY = [
    ('GATUNEK', 'str', 'Nazwa techniczna'),
    ('NAZWA_POLSKA', 'str', 'Nazwa polska'),
    ('PROG_CM', 'int', 'Próg zezwolenia [cm]'),
]

WARSTWY = [
    # (nazwa w projekcie, tabela, typ geometrii ogr, pola)
    ('drzewa', 'DEN_DRZEWA', 'point25d', POLA_DRZEWA),
    ('grupy', 'DEN_GRUPY', 'polygon', POLA_GRUPY),
    ('uwagi', 'DEN_UWAGI', 'point', POLA_UWAGI),
    ('tyczenie', 'DEN_TYCZENIE', 'point', POLA_TYCZENIE),
    ('zasieg', 'DEN_ZASIEG', 'polygon', POLA_ZASIEG),
    ('taksony', 'TAKSONY', None, POLA_TAKSONY),
]

# warstwy, które dostają tabelę załączników ZAL_<WARSTWA>
Z_ZALACZNIKAMI = ['drzewa', 'grupy', 'uwagi']

POLA_ZALACZNIKA = [
    ('ID_RODZICA', 'int'), ('TYP', 'str'), ('SCIEZKA', 'str'),
    ('UJECIE', 'str'), ('CZAS', 'str'), ('AUTOR', 'str'), ('UWAGI', 'str'),
]


# ------------------------------------------------------------ 1. GeoPackage
def zbuduj_gpkg():
    """Zakłada brakujące tabele w dane.gpkg. Istniejących nie rusza."""
    from osgeo import ogr, osr

    typy = {'str': ogr.OFTString, 'real': ogr.OFTReal, 'int': ogr.OFTInteger}
    geom = {'point': ogr.wkbPoint, 'point25d': ogr.wkbPoint25D,
            'polygon': ogr.wkbMultiPolygon, None: ogr.wkbNone}

    srs = osr.SpatialReference()
    srs.ImportFromEPSG(CRS_KOD)

    if os.path.exists(GPKG):
        ds = ogr.Open(GPKG, 1)
        if ds is None:
            raise RuntimeError('Nie otwarto do zapisu: ' + GPKG)
    else:
        ds = ogr.GetDriverByName('GPKG').CreateDataSource(GPKG)
        if ds is None:
            raise RuntimeError('Nie utworzono pliku: ' + GPKG)

    def tabela(nazwa, typ_geom, pola):
        if ds.GetLayerByName(nazwa) is not None:
            print('  tabela %s: już była' % nazwa)
            return
        lyr = ds.CreateLayer(nazwa, srs if typ_geom is not None else None,
                             geom[typ_geom], options=['FID=fid'])
        if lyr is None:
            raise RuntimeError('Nie utworzono tabeli: ' + nazwa)
        for pole in pola:
            fd = ogr.FieldDefn(pole[0], typy[pole[1]])
            if pole[1] == 'str':
                fd.SetWidth(0)          # bez limitu długości — UWAGI bywają długie
            if lyr.CreateField(fd) != 0:
                raise RuntimeError('Nie utworzono pola %s w %s' % (pole[0], nazwa))
        print('  tabela %s: utworzona' % nazwa)

    try:
        for _nazwa, tab, typ_geom, pola in WARSTWY:
            tabela(tab, typ_geom, pola)
        for nazwa in Z_ZALACZNIKAMI:
            tabela('ZAL_' + nazwa.upper(), None, POLA_ZALACZNIKA)
    finally:
        ds = None


# --------------------------------------------------------------- 2. pomocnicze
def idx(lyr, pole):
    i = lyr.fields().indexOf(pole)
    if i < 0:
        raise KeyError('%s: brak pola %s' % (lyr.name(), pole))
    return i


def widget(lyr, pole, setup):
    lyr.setEditorWidgetSetup(idx(lyr, pole), setup)


def domyslna(lyr, pole, wyr, przy_aktualizacji=False):
    lyr.setDefaultValueDefinition(idx(lyr, pole),
                                  QgsDefaultValue(wyr, przy_aktualizacji))


def alias(lyr, pole, tekst):
    lyr.setFieldAlias(idx(lyr, pole), tekst)


def ograniczenie_miekkie(lyr, pole, wyr, opis):
    i = idx(lyr, pole)
    lyr.setConstraintExpression(i, wyr, opis)
    lyr.setFieldConstraint(i, QgsFieldConstraints.ConstraintExpression,
                           QgsFieldConstraints.ConstraintStrengthSoft)


def _layout_tab():
    try:
        from qgis.core import Qgis
        return Qgis.AttributeFormLayout.DragAndDrop
    except Exception:
        return QgsEditFormConfig.TabLayout


def _suppress_on():
    try:
        from qgis.core import Qgis
        return Qgis.AttributeFormSuppression.On
    except Exception:
        return QgsEditFormConfig.SuppressOn


def zakladki(lyr, uklad):
    """uklad: [(tytuł, [pola]), ...] — relacje dokładamy osobno."""
    cfg = lyr.editFormConfig()
    cfg.setLayout(_layout_tab())
    root = cfg.invisibleRootContainer()
    root.clear()
    for tytul, pola in uklad:
        k = QgsAttributeEditorContainer(tytul, root)
        try:
            from qgis.core import Qgis
            k.setType(Qgis.AttributeEditorContainerType.Tab)
        except Exception:
            k.setIsGroupBox(False)
        for p in pola:
            k.addChildElement(QgsAttributeEditorField(p, idx(lyr, p), k))
        root.addChildElement(k)
    lyr.setEditFormConfig(cfg)


def zakladka_relacji(lyr, rel_id, tytul):
    cfg = lyr.editFormConfig()
    root = cfg.invisibleRootContainer()
    k = QgsAttributeEditorContainer(tytul, root)
    try:
        from qgis.core import Qgis
        k.setType(Qgis.AttributeEditorContainerType.Tab)
    except Exception:
        k.setIsGroupBox(False)
    k.addChildElement(QgsAttributeEditorRelation(rel_id, k))
    root.addChildElement(k)
    lyr.setEditFormConfig(cfg)


# =============================================================== 3. budowanie
print('Dane   :', GPKG)
print('Projekt:', QGS)
print('\n[GeoPackage]')
zbuduj_gpkg()

proj = QgsProject.instance()
proj.clear()
proj.setCrs(QgsCoordinateReferenceSystem(CRS))

print('\n[Warstwy]')
L = {}
for nazwa, tab, _g, pola in WARSTWY:
    lyr = QgsVectorLayer('{}|layername={}'.format(GPKG, tab), nazwa, 'ogr')
    if not lyr.isValid():
        raise RuntimeError('Nie wczytano warstwy: ' + tab)
    proj.addMapLayer(lyr)
    L[nazwa] = lyr
    for kol, _typ, opis in pola:
        alias(lyr, kol, opis)
    print('  ', nazwa)

UKRYTY = QgsEditorWidgetSetup('Hidden', {})
MAPA = lambda d: QgsEditorWidgetSetup('ValueMap', {'map': [{k: v} for k, v in d]})
WIELOLINIOWY = QgsEditorWidgetSetup('TextEdit', {'IsMultiline': True, 'UseHtml': False})
ZASOB = QgsEditorWidgetSetup('ExternalResource', {
    'DocumentViewer': 1, 'RelativeStorage': 1, 'StorageMode': 0,
    'FileWidget': True, 'FileWidgetButton': True})

KATEGORIE = MAPA([('drzewa', 'drzewa'), ('krzewy', 'krzewy')])
STAN_05 = MAPA([('0 - drzewo martwe', '0'), ('1 - zamierające', '1'),
                ('2 - osłabione', '2'), ('3 - dobry', '3'),
                ('4 - bardzo dobry', '4'), ('5 - wzorcowy', '5')])

# --------------------------------------------------------------------- DRZEWA
d = L['drzewa']
widget(d, 'KATEGORIA', KATEGORIE)
widget(d, 'STAN', STAN_05)
widget(d, 'UWAGI', WIELOLINIOWY)
widget(d, 'SZEROKOSC_M', UKRYTY)

domyslna(d, 'KATEGORIA', "'drzewa'")
domyslna(d, 'DATA', "format_date(now(),'yyyy-MM-dd')")
domyslna(d, 'WYKONAWCA', '@wykonawca')

# Pole pochodne: we wzorcowym zbiorze szerokosc_M to dokładnie ćwiartka
# szerokości korony (sprawdzone na 25 rekordach, bez wyjątku). Liczymy je
# wyrażeniem przy każdej edycji zamiast wpisywać ręcznie.
domyslna(d, 'SZEROKOSC_M', 'round("KORONA_SZER" / 4.0, 1)', True)

# Metadane pozycji. UWAGA: @position_* wypełnia się TYLKO przy zamrożonej
# pozycji, @gnss_* zawsze (expressioncontextutils.cpp: addPositionVariable).
domyslna(d, 'RTK_DOKL', 'round(@gnss_horizontal_accuracy, 3)')
domyslna(d, 'RTK_SAT', '@gnss_number_of_used_satellites')
domyslna(d, 'RTK_KAT', 'round(@gnss_imu_pitch, 1)')

# Nazwa polska podpowiadana ze słownika po przycięciu spacji, którą dokleja
# klawiatura predykcyjna. Podpowiedź, nie przymus — pole zostaje edytowalne.
domyslna(d, 'NAZWA_PL',
         "coalesce(attribute(get_feature('taksony','GATUNEK',trim(\"GATUNEK\")),"
         "'NAZWA_POLSKA'), \"NAZWA_PL\")")

# Miękka kontrola gatunku: ostrzega, nie blokuje zapisu.
ograniczenie_miekkie(
    d, 'GATUNEK',
    "\"GATUNEK\" IS NULL OR array_length(array_agg(\"GATUNEK\", layer:='taksony', "
    "filter:=\"GATUNEK\" = trim(attribute(@parent,'GATUNEK')))) > 0",
    'Gatunek spoza słownika — sprawdź pisownię (spacja na końcu jest OK)')

zakladki(d, [
    ('1. Drzewo', ['KATEGORIA', 'GATUNEK', 'NAZWA_PL', 'OBW_5', 'OBW_130',
                   'KORONA_SZER', 'WYSOKOSC', 'STAN']),
    ('2. Opis', ['UWAGI']),
    ('4. Biuro', ['NR_INW', 'DECYZJA', 'RTK_DOKL', 'RTK_KAT', 'RTK_SAT',
                  'DATA', 'WYKONAWCA']),
])
d.setDisplayExpression(
    "coalesce(\"NR_INW\", 'bez nr') || ' · ' || coalesce(trim(\"GATUNEK\"),'?')")

# ---------------------------------------------------------------------- GRUPY
g = L['grupy']
widget(g, 'KATEGORIA', KATEGORIE)
widget(g, 'STAN', STAN_05)
widget(g, 'UWAGI', WIELOLINIOWY)
domyslna(g, 'KATEGORIA', "'krzewy'")
domyslna(g, 'POW_M2', 'round($area, 2)', True)
domyslna(g, 'DATA', "format_date(now(),'yyyy-MM-dd')")
domyslna(g, 'WYKONAWCA', '@wykonawca')
zakladki(g, [
    ('1. Grupa', ['KATEGORIA', 'GATUNKI', 'POW_M2', 'WYSOKOSC', 'STAN']),
    ('2. Opis', ['UWAGI']),
    ('4. Biuro', ['NR_INW', 'DECYZJA', 'DATA', 'WYKONAWCA']),
])
g.setDisplayExpression("coalesce(\"NR_INW\",'grupa') || ' · ' || round(\"POW_M2\") || ' m2'")

# ---------------------------------------------------------------------- UWAGI
u = L['uwagi']
widget(u, 'TRESC', WIELOLINIOWY)
domyslna(u, 'DATA', "format_date(now(),'yyyy-MM-dd')")
domyslna(u, 'WYKONAWCA', '@wykonawca')
u.setDisplayExpression('"TRESC"')

# ------------------------------------------------------------------- TYCZENIE
t = L['tyczenie']
domyslna(t, 'DATA', "format_date(now(),'yyyy-MM-dd')")
domyslna(t, 'WYKONAWCA', '@wykonawca')
t.setDisplayExpression("coalesce(\"OPIS\", 'punkt ' || \"fid\")")

# --------------------------------------------------------------------- ZASIEG
z = L['zasieg']
domyslna(z, 'POW_M2', 'round($area, 2)', True)
z.setReadOnly(True)
z.setDisplayExpression('"NAZWA"')

# ============================================================== 4. załączniki
print('\n[Załączniki]')
for nazwa in Z_ZALACZNIKAMI:
    rodzic = L[nazwa]
    tab = 'ZAL_' + nazwa.upper()
    dziecko = QgsVectorLayer('{}|layername={}'.format(GPKG, tab),
                             'zal_' + nazwa, 'ogr')
    if not dziecko.isValid():
        raise RuntimeError('Nie wczytano tabeli załączników: ' + tab)
    proj.addMapLayer(dziecko, False)
    korzen = proj.layerTreeRoot()
    grupa = korzen.findGroup('Załączniki') or korzen.addGroup('Załączniki')
    grupa.setExpanded(False)
    grupa.setItemVisibilityChecked(False)
    if grupa.findLayer(dziecko.id()) is None:
        grupa.addLayer(dziecko)

    widget(dziecko, 'fid', UKRYTY)
    widget(dziecko, 'ID_RODZICA', UKRYTY)
    widget(dziecko, 'SCIEZKA', ZASOB)
    widget(dziecko, 'TYP', MAPA([('zdjęcie', 'foto'), ('szkic', 'szkic'),
                                 ('nagranie', 'audio'), ('notatka', 'notatka')]))
    domyslna(dziecko, 'TYP', "'foto'")
    domyslna(dziecko, 'CZAS', "format_date(now(),'yyyy-MM-dd HH:mm:ss')")
    domyslna(dziecko, 'AUTOR', '@wykonawca')
    dziecko.setCustomProperty('QFieldSync/attachment_naming', json.dumps({
        'SCIEZKA': ("CASE WHEN @rodzic_fid IS NULL "
                    "THEN 'DCIM/{w}_' || format_date(now(),'yyyyMMdd_HHmmss_zzz') || '.{{extension}}' "
                    "ELSE 'DCIM/{w}_' || @rodzic_fid || '/{w}_' || @rodzic_fid || '_' "
                    "|| format_date(now(),'yyyyMMdd_HHmmss_zzz') || '.{{extension}}' END"
                    ).format(w=nazwa)}, ensure_ascii=False))
    cfg = dziecko.editFormConfig()
    cfg.setSuppress(_suppress_on())
    dziecko.setEditFormConfig(cfg)
    dziecko.setDisplayExpression('coalesce("SCIEZKA", "TYP", \'załącznik\')')

    rel = QgsRelation()
    rel.setId('zal_' + nazwa)
    rel.setName('Załączniki')
    rel.setReferencedLayer(rodzic.id())
    rel.setReferencingLayer(dziecko.id())
    rel.addFieldPair('ID_RODZICA', 'fid')
    try:
        from qgis.core import Qgis
        rel.setStrength(Qgis.RelationshipStrength.Composition)
    except Exception:
        rel.setStrength(QgsRelation.Composition)
    if not rel.isValid():
        raise RuntimeError('Relacja załączników nieprawidłowa: ' + nazwa)
    proj.relationManager().addRelation(rel)
    if rodzic.editFormConfig().layout() == _layout_tab():
        zakladka_relacji(rodzic, rel.id(), '3. Załączniki')
    print('  %s -> %s' % (nazwa, tab))

# ========================================================= 5. klawisze paska
# Schemat wg QfQuickCaptureBar.loadDefinitions(): klucze "etykieta", "warstwa",
# "kolor", "zdjecie", opcjonalnie "rozmiar". Trybu ani podpowiedzi NIE podajemy
# — pasek wylicza je sam z typu geometrii warstwy.
klawisze = {
    'odleglosci': [25, 50, 100, 200],
    'klawisze': [
        {'etykieta': 'D', 'warstwa': 'drzewa', 'kolor': '#2E7D32', 'zdjecie': True},
        {'etykieta': 'G', 'warstwa': 'grupy', 'kolor': '#00897B', 'zdjecie': True},
        {'etykieta': 'U', 'warstwa': 'uwagi', 'kolor': '#F9A825', 'zdjecie': True},
        # kafel BEZ zdjęcia — punkt tyczenia, seria wierzchołków, wierzchołki
        # z GNSS przy obrysie grupy. Bez "zdjecie": false te tryby nie działają.
        {'etykieta': 'T', 'warstwa': 'tyczenie', 'kolor': '#546E7A', 'zdjecie': False},
    ]}
with open(os.path.join(KAT, 'workfield_klawisze.json'), 'w', encoding='utf-8') as f:
    json.dump(klawisze, f, ensure_ascii=False, indent=2)
print('\n[Klawisze paska] workfield_klawisze.json — %d kafle: %s'
      % (len(klawisze['klawisze']),
         ', '.join(k['etykieta'] for k in klawisze['klawisze'])))

# ============================================================ 6. zmienne, zapis
ECU.setProjectVariable(proj, 'wykonawca', 'Imię Nazwisko')
ECU.setProjectVariable(proj, 'nazwa_obiektu', 'Obiekt')
proj.setTitle('Inwentaryzacja dendrologiczna — szablon')

if not proj.write(QGS):
    raise RuntimeError('QGIS nie zapisał projektu: ' + QGS)
print('\nZAPISANO:', QGS)
print('Warstwy:', ', '.join(l.name() for l in proj.mapLayers().values()))
print('\nDalej: podkład DXF dołóż ręcznie i zapisz projekt — szablon nie zna '
      'jeszcze ścieżki do mapy zasadniczej.')
