# -*- coding: utf-8 -*-
"""
Załączniki N:1 w projekcie WorkField — zakładanie tabel i relacji.

Dla każdej wskazanej warstwy zakłada tabelę-dziecko ZAL_<WARSTWA> w GeoPackage
i wiąże ją z warstwą-rodzicem zwykłą relacją QGIS. QField/WorkField sam
podmienia edytor relacji na galerię (gallery_relation_editor), bo tabela ma
pole z widgetem ExternalResource — dzięki temu w formularzu obiektu pojawia
się galeria "Załączniki" z aparatem, i to BEZ przebudowy aplikacji.

URUCHOMIENIE (tak samo jak zbuduj_projekt.py):
  QGIS -> Wtyczki -> Konsola Pythona -> "Pokaż edytor" -> otwórz ten plik -> Uruchom

  Wariant A (najprostszy): otwórz projekt w QGIS, uruchom skrypt bez zmian —
  weźmie aktualnie otwarty projekt i wszystkie warstwy robocze.

  PRZED URUCHOMIENIEM zakończ wszystkie sesje edycji warstw (żółty ołówek
  wyłączony) — skrypt dopisuje tabele do tego samego pliku GeoPackage.

  Wariant B: ustaw PROJEKT poniżej na ścieżkę do projekt.qgs / projekt.qgz.

  Wariant C (wiersz poleceń, jeśli python3 widzi qgis):
      python3 zaloz_zalaczniki.py /sciezka/projekt.qgs [warstwa1 warstwa2 ...]

CO ROBI:
  1. Kopia zapasowa GPKG i pliku projektu (sufiks .bak_<data_godzina>).
  2. Tabela ZAL_<WARSTWA> w GPKG (jeśli jej nie ma) — przez GDAL/OGR, więc
     z poprawnym kluczem głównym fid i rejestracją w gpkg_contents.
  3. Warstwa zal_<warstwa> w projekcie (grupa "Załączniki", domyślnie zwinięta
     i niewidoczna na mapie).
  4. Widgety: SCIEZKA = ExternalResource (ścieżka względna, podgląd obrazu),
     ID_RODZICA ukryte, TYP jako lista wyboru, czas/autor z wartości domyślnych.
  5. QFieldSync/attachment_naming — nazwa pliku wg konwencji paska szybkiego
     przechwytu: DCIM/<warstwa_rodzica>_RRRRMMDD_GGMMSS_mmm.<rozszerzenie>,
     żeby galeria zdjęć nadal rozpoznawała warstwę z nazwy pliku.
  6. Relacja rodzic -> dziecko (ID_RODZICA -> fid), siła "kompozycja"
     (skasowanie obiektu kasuje jego załączniki).
  7. Zakładka "Załączniki" w formularzu rodzica (gdy formularz ma zakładki;
     przy formularzu automatycznym QGIS/QField dokłada galerię sam).

Skrypt jest IDEMPOTENTNY: to, co już jest, zostaje nietknięte, brakujące
elementy są dokładane. Można go uruchamiać wielokrotnie i na projektach,
które dostały już część konfiguracji.

NIE RUSZA istniejących pól FOTO — zostają jako awaryjny zapis pojedynczego
zdjęcia (patrz docs/ZALACZNIKI.md). Migracja starych zdjęć do tabel jest
osobną operacją magazynową.
"""
import os
import sys
import json
import shutil
import datetime

from qgis.core import (
    QgsProject, QgsVectorLayer, QgsEditorWidgetSetup, QgsDefaultValue,
    QgsRelation, QgsAttributeEditorContainer, QgsAttributeEditorRelation,
    QgsEditFormConfig,
)

# --------------------------------------------------------------- USTAWIENIA
# Pusty PROJEKT = użyj projektu aktualnie otwartego w QGIS.
PROJEKT = ''

# Puste WARSTWY = wszystkie warstwy robocze projektu (wektorowe, edytowalne,
# z pliku GeoPackage), z pominięciem słowników i podkładów z listy POMIN.
WARSTWY = []

# Warstwy, które nigdy nie dostają załączników (słowniki, podkłady, tabele
# wskaźnikowe, same tabele załączników — w obu pisowniach, bo warstwa bywa
# wczytana pod nazwą tabeli).
POMIN_PREFIKSY = ('zal_', 'ZAL_', 'podklad_', 'REF_', 'ref_')
POMIN_NAZWY = {'slownik', 'slownik_gatunkow', 'taksony', 'wskazniki',
               'wskazniki_polaczone', 'SLOWNIK_GATUNKOW'}

# Nazwy elementów — zmiana tutaj rozjeżdża projekt z aplikacją. Nie ruszać
# bez świadomej decyzji (etap 2 zna te nazwy z kodu paska przechwytu).
PREFIKS_TABELI = 'ZAL_'
POLE_RODZIC = 'ID_RODZICA'
POLE_SCIEZKA = 'SCIEZKA'
POLE_TYP = 'TYP'
POLE_UJECIE = 'UJECIE'
POLE_CZAS = 'CZAS'
POLE_AUTOR = 'AUTOR'
POLE_UWAGI = 'UWAGI'
KLUCZ_RODZICA = 'fid'          # pole rodzica, na które wskazuje ID_RODZICA
NAZWA_GRUPY = 'Załączniki'
NAZWA_ZAKLADKI = 'Załączniki'

TYPY_ZALACZNIKA = [('zdjęcie', 'foto'), ('szkic', 'szkic'),
                   ('nagranie', 'audio'), ('notatka', 'notatka')]

# Konwencja nazw plików — zgodna z tym, czego oczekują programy branżowe
# (Mapit Spatial): podkatalog na obiekt, a w nazwie pliku klucz obiektu
# między nazwą warstwy a datą.
#
#     DCIM/<warstwa>_<klucz>/<warstwa>_<klucz>_RRRRMMDD_GGMMSS_mmm.<rozsz>
#
# Klucz obiektu-rodzica podaje aplikacja w zmiennej @rodzic_fid. Aplikacja
# bez tej zmiennej (czyli każde APK sprzed etapu 2) dostaje NULL — wtedy
# wyrażenie schodzi do starej, płaskiej nazwy zamiast robić katalog "NULL":
#
#     DCIM/<warstwa>_RRRRMMDD_GGMMSS_mmm.<rozsz>
#
# Dzięki temu ten sam projekt działa na starym i nowym APK, a konwencja
# włącza się sama, gdy w telefonie wyląduje wersja z etapu 2.
KONWENCJA_PODKATALOGI = True

# Polskie znaki w nazwie tabeli i w nazwie pliku zdjęcia to proszenie się
# o kłopoty (karta SD, zip, transliteracja w chmurze) — sprowadzamy do ASCII.
ASCII = str.maketrans({'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n',
                       'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
                       'Ą': 'A', 'Ć': 'C', 'Ę': 'E', 'Ł': 'L', 'Ń': 'N',
                       'Ó': 'O', 'Ś': 'S', 'Ź': 'Z', 'Ż': 'Z'})


def bez_ogonkow(tekst):
    return tekst.translate(ASCII)

# ------------------------------------------------------------- zgodność API
def _suppress_on():
    """Qgis.AttributeFormSuppression.On albo stara stała QgsEditFormConfig."""
    try:
        from qgis.core import Qgis
        return Qgis.AttributeFormSuppression.On
    except Exception:
        return QgsEditFormConfig.SuppressOn


def _layout_tab():
    try:
        from qgis.core import Qgis
        return Qgis.AttributeFormLayout.DragAndDrop
    except Exception:
        return QgsEditFormConfig.TabLayout


def _relation_composition(rel):
    """Kompozycja: kasowanie rodzica kasuje dzieci. Gdy API inne — pomiń."""
    try:
        from qgis.core import Qgis
        rel.setStrength(Qgis.RelationshipStrength.Composition)
        return True
    except Exception:
        pass
    try:
        rel.setStrength(QgsRelation.Composition)
        return True
    except Exception:
        return False


# ------------------------------------------------------------------ pomoce
def stempel():
    return datetime.datetime.now().strftime('%Y%m%d_%H%M%S')


def kopia(sciezka, znacznik):
    """Kopia zapasowa pliku; zwraca ścieżkę kopii albo None."""
    if not sciezka or not os.path.exists(sciezka):
        return None
    cel = '{}.bak_{}'.format(sciezka, znacznik)
    if not os.path.exists(cel):
        shutil.copy2(sciezka, cel)
        print('  kopia zapasowa:', os.path.basename(cel))
    return cel


def gpkg_warstwy(lyr):
    """Zwraca (plik.gpkg, nazwa_tabeli) dla warstwy OGR z GeoPackage."""
    if lyr.providerType() != 'ogr':
        return None, None
    src = lyr.source()
    plik = src.split('|')[0]
    if not plik.lower().endswith('.gpkg'):
        return None, None
    tabela = None
    for czesc in src.split('|')[1:]:
        if czesc.startswith('layername='):
            tabela = czesc[len('layername='):]
    return plik, (tabela or lyr.name())


def kandydaci(proj):
    """Warstwy robocze nadające się na rodzica załączników."""
    out = []
    for lyr in proj.mapLayers().values():
        if not isinstance(lyr, QgsVectorLayer) or not lyr.isValid():
            continue
        nazwa = lyr.name()
        if nazwa in POMIN_NAZWY or nazwa.startswith(POMIN_PREFIKSY):
            continue
        if lyr.readOnly():
            continue
        plik, _tab = gpkg_warstwy(lyr)
        if not plik:
            continue
        if lyr.fields().indexOf(KLUCZ_RODZICA) < 0:
            print('  pomijam %s: brak pola %s' % (nazwa, KLUCZ_RODZICA))
            continue
        out.append(lyr)
    return out


# Kolejność pól tabeli załączników — jedno źródło prawdy dla obu wariantów
# zakładania tabeli (GDAL i awaryjny SQL).
# UWAGA: żadne z tych pól nie może dostać ograniczenia NOT NULL. Przy nowym,
# jeszcze niezapisanym obiekcie rodzica QField wpisuje klucz obcy dopiero po
# zatwierdzeniu (featuremodel.cpp), a NOT NULL na ID_RODZICA wyłączyłoby wtedy
# galerię (referencingfeaturelistmodel.cpp: checkParentPrimaries).
POLA_ZALACZNIKA = [
    (POLE_RODZIC, 'INTEGER'),
    (POLE_TYP, 'TEXT'),
    (POLE_SCIEZKA, 'TEXT'),
    (POLE_UJECIE, 'TEXT'),
    (POLE_CZAS, 'TEXT'),
    (POLE_AUTOR, 'TEXT'),
    (POLE_UWAGI, 'TEXT'),
]


def _tabela_istnieje(gpkg, tabela):
    import sqlite3
    con = sqlite3.connect(gpkg)
    try:
        r = con.execute("SELECT 1 FROM sqlite_master WHERE type='table' "
                        "AND name=?", (tabela,)).fetchone()
        return r is not None
    finally:
        con.close()


def _utworz_tabele_gdal(gpkg, tabela):
    """Wariant zalecany: tabelę zakłada GDAL, tak jak resztę GeoPackage."""
    from osgeo import ogr
    typy = {'INTEGER': ogr.OFTInteger64, 'TEXT': ogr.OFTString}
    ds = ogr.Open(gpkg, 1)
    if ds is None:
        raise RuntimeError('Nie otwarto do zapisu: ' + gpkg)
    try:
        lyr = ds.CreateLayer(tabela, geom_type=ogr.wkbNone, options=['FID=fid'])
        if lyr is None:
            raise RuntimeError('Nie utworzono tabeli: ' + tabela)
        for nazwa, typ in POLA_ZALACZNIKA:
            if lyr.CreateField(ogr.FieldDefn(nazwa, typy[typ])) != 0:
                raise RuntimeError('Nie utworzono pola %s w %s' % (nazwa, tabela))
    finally:
        ds = None


def _utworz_tabele_sql(gpkg, tabela):
    """Wariant awaryjny (bez GDAL): czysty SQL zgodny z GeoPackage.

    Rejestracja w gpkg_contents jako 'attributes', bez wpisu do
    gpkg_ogr_contents — dokładnie tak, jak wyglądają tabele nieprzestrzenne
    już obecne w szablonie (SLOWNIK_GATUNKOW). Wpis do gpkg_ogr_contents bez
    wyzwalaczy liczników dałby warstwę widzianą przez OGR jako pusta.
    """
    import sqlite3
    kolumny = ',\n  '.join('"%s" %s' % (n, t) for n, t in POLA_ZALACZNIKA)
    con = sqlite3.connect(gpkg)
    try:
        con.execute('CREATE TABLE "{t}" (\n  '
                    '"fid" INTEGER PRIMARY KEY AUTOINCREMENT,\n  {k}\n)'
                    .format(t=tabela, k=kolumny))
        con.execute(
            'INSERT INTO gpkg_contents '
            '(table_name, data_type, identifier, description, last_change, srs_id) '
            "VALUES (?, 'attributes', ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ','now'), NULL)",
            (tabela, tabela, 'Załączniki'))
        con.commit()
    finally:
        con.close()


def utworz_tabele(gpkg, tabela):
    """Zakłada tabelę załączników w GeoPackage. True = utworzono teraz."""
    if _tabela_istnieje(gpkg, tabela):
        return False
    try:
        _utworz_tabele_gdal(gpkg, tabela)
    except ImportError:
        print('  (bez GDAL w tym Pythonie — zakładam tabelę czystym SQL)')
        _utworz_tabele_sql(gpkg, tabela)
    return True


def indeks_rodzica(gpkg, tabela):
    """Indeks po ID_RODZICA — galeria pyta o dzieci przy każdym formularzu."""
    import sqlite3
    con = sqlite3.connect(gpkg)
    try:
        con.execute('CREATE INDEX IF NOT EXISTS "idx_{t}_rodzic" '
                    'ON "{t}" ("{p}")'.format(t=tabela, p=POLE_RODZIC))
        con.commit()
    finally:
        con.close()


def wyrazenie_nazwy(warstwa):
    """Wyrażenie QGIS liczące ścieżkę pliku załącznika (patrz KONWENCJA_*)."""
    stempel_czasu = "format_date(now(),'yyyyMMdd_HHmmss_zzz')"
    plaska = "'DCIM/{w}_' || {t} || '.{{extension}}'".format(w=warstwa,
                                                            t=stempel_czasu)
    if not KONWENCJA_PODKATALOGI:
        return plaska
    z_kluczem = ("'DCIM/{w}_' || @rodzic_fid || '/{w}_' || @rodzic_fid "
                 "|| '_' || {t} || '.{{extension}}'").format(w=warstwa,
                                                             t=stempel_czasu)
    return 'CASE WHEN @rodzic_fid IS NULL THEN {p} ELSE {k} END'.format(
        p=plaska, k=z_kluczem)


def konfiguruj_dziecko(dziecko, nazwa_rodzica):
    """Widgety, wartości domyślne i konwencja nazw plików w tabeli-dziecku."""
    def idx(pole):
        return dziecko.fields().indexOf(pole)

    # Bez tych dwóch pól cała funkcja nie ma sensu: SCIEZKA nosi widget
    # ExternalResource (to on przełącza edytor relacji na galerię),
    # ID_RODZICA trzyma klucz obcy. Lepiej zatrzymać się głośno.
    for wymagane in (POLE_SCIEZKA, POLE_RODZIC):
        if idx(wymagane) < 0:
            raise RuntimeError(
                'Tabela załączników %s nie ma pola %s — usuń tabelę i uruchom '
                'skrypt ponownie' % (dziecko.name(), wymagane))

    ukryty = QgsEditorWidgetSetup('Hidden', {})
    zasob = QgsEditorWidgetSetup('ExternalResource', {
        'DocumentViewer': 1,        # podgląd obrazu
        'RelativeStorage': 1,       # ścieżka względem katalogu projektu
        'StorageMode': 0,
        'FileWidget': True,
        'FileWidgetButton': True,
    })
    lista_typow = QgsEditorWidgetSetup('ValueMap', {
        'map': [{k: v} for k, v in TYPY_ZALACZNIKA]})

    if idx('fid') >= 0:
        dziecko.setEditorWidgetSetup(idx('fid'), ukryty)
    if idx(POLE_RODZIC) >= 0:
        dziecko.setEditorWidgetSetup(idx(POLE_RODZIC), ukryty)
    if idx(POLE_SCIEZKA) >= 0:
        dziecko.setEditorWidgetSetup(idx(POLE_SCIEZKA), zasob)
    if idx(POLE_TYP) >= 0:
        dziecko.setEditorWidgetSetup(idx(POLE_TYP), lista_typow)
        dziecko.setDefaultValueDefinition(idx(POLE_TYP), QgsDefaultValue("'foto'"))
    if idx(POLE_CZAS) >= 0:
        dziecko.setDefaultValueDefinition(
            idx(POLE_CZAS),
            QgsDefaultValue("format_date(now(),'yyyy-MM-dd HH:mm:ss')"))
    if idx(POLE_AUTOR) >= 0:
        dziecko.setDefaultValueDefinition(idx(POLE_AUTOR),
                                          QgsDefaultValue('@wykonawca'))

    # Nazwa pliku: <warstwa_rodzica>_RRRRMMDD_GGMMSS_mmm — taka sama konwencja,
    # jaką stosuje pasek szybkiego przechwytu, więc galeria zdjęć dalej
    # rozpoznaje warstwę po nazwie pliku (QfPhotoGallery.extractLayer).
    wyrazenie = wyrazenie_nazwy(bez_ogonkow(nazwa_rodzica))
    dziecko.setCustomProperty('QFieldSync/attachment_naming',
                              json.dumps({POLE_SCIEZKA: wyrazenie},
                                         ensure_ascii=False))

    # Formularz dziecka pomijany: zdjęcie z galerii zapisuje się od razu,
    # bez pytania o atrybuty (gallery_relation_editor -> suppressFeatureForm).
    cfg = dziecko.editFormConfig()
    cfg.setSuppress(_suppress_on())
    dziecko.setEditFormConfig(cfg)

    dziecko.setDisplayExpression(
        'coalesce("{s}", "{t}", \'załącznik\')'.format(s=POLE_SCIEZKA, t=POLE_TYP))


def dodaj_zakladke(rodzic, rel_id):
    """Zakładka z galerią w formularzu rodzica. True = dołożono teraz."""
    cfg = rodzic.editFormConfig()
    if cfg.layout() != _layout_tab():
        # Formularz automatyczny: QGIS i WorkField same dokładają relacje
        # (attributeformmodelbase.cpp: generateRootContainer).
        return False
    root = cfg.invisibleRootContainer()

    def ma_relacje(element):
        for dziecko in element.children():
            if isinstance(dziecko, QgsAttributeEditorRelation):
                # Świeżo utworzony element zna tylko swoją nazwę (= id relacji);
                # relation() wypełnia się dopiero przy wczytaniu projektu z XML,
                # więc bez sprawdzenia nazwy drugie uruchomienie w tej samej
                # sesji QGIS dołożyłoby drugą zakładkę.
                if dziecko.name() == rel_id:
                    return True
                rel = dziecko.relation()
                if rel is not None and rel.id() == rel_id:
                    return True
            if isinstance(dziecko, QgsAttributeEditorContainer):
                if ma_relacje(dziecko):
                    return True
        return False

    if ma_relacje(root):
        return False

    kontener = QgsAttributeEditorContainer(NAZWA_ZAKLADKI, root)
    try:
        from qgis.core import Qgis
        kontener.setType(Qgis.AttributeEditorContainerType.Tab)
    except Exception:
        kontener.setIsGroupBox(False)
    kontener.addChildElement(QgsAttributeEditorRelation(rel_id, kontener))
    root.addChildElement(kontener)
    rodzic.setEditFormConfig(cfg)
    return True


def do_grupy(proj, warstwa):
    """Warstwa techniczna: grupa 'Załączniki', zwinięta, wyłączona na mapie."""
    korzen = proj.layerTreeRoot()
    grupa = korzen.findGroup(NAZWA_GRUPY)
    if grupa is None:
        grupa = korzen.addGroup(NAZWA_GRUPY)
        grupa.setExpanded(False)
        grupa.setItemVisibilityChecked(False)
    if grupa.findLayer(warstwa.id()) is None:
        wezel = korzen.findLayer(warstwa.id())
        grupa.addLayer(warstwa)
        if wezel is not None:
            wezel.parent().removeChildNode(wezel)
    lyr_node = grupa.findLayer(warstwa.id())
    if lyr_node is not None:
        lyr_node.setItemVisibilityChecked(False)


# ------------------------------------------------------------------- główna
def main(sciezka_projektu='', nazwy_warstw=None):
    proj = QgsProject.instance()

    if sciezka_projektu:
        if not os.path.exists(sciezka_projektu):
            raise RuntimeError('Nie ma pliku projektu: ' + sciezka_projektu)
        if not proj.read(sciezka_projektu):
            raise RuntimeError('Nie wczytano projektu: ' + sciezka_projektu)
    plik_projektu = proj.fileName()
    if not plik_projektu:
        raise RuntimeError('Brak otwartego projektu — otwórz projekt w QGIS '
                           'albo ustaw PROJEKT na ścieżkę do pliku .qgs/.qgz')
    print('Projekt:', plik_projektu)

    wybrane = kandydaci(proj)
    if nazwy_warstw:
        chciane = set(nazwy_warstw)
        wybrane = [l for l in wybrane if l.name() in chciane]
        brakujace = chciane - {l.name() for l in wybrane}
        if brakujace:
            raise RuntimeError('Nie ma takich warstw roboczych: '
                               + ', '.join(sorted(brakujace)))
    if not wybrane:
        raise RuntimeError('Nie znalazłem warstw, którym można dołożyć załączniki')

    print('Warstwy do wyposażenia:', ', '.join(l.name() for l in wybrane))

    znacznik = stempel()
    kopia(plik_projektu, znacznik)
    if plik_projektu.lower().endswith('.qgs'):
        kopia(plik_projektu[:-4] + '.qgd', znacznik)   # magazyn pomocniczy
    zrobione_kopie = set()
    for lyr in wybrane:
        plik, _tab = gpkg_warstwy(lyr)
        if plik and plik not in zrobione_kopie:
            kopia(plik, znacznik)
            zrobione_kopie.add(plik)

    podsumowanie = []
    for rodzic in wybrane:
        nazwa = rodzic.name()
        gpkg, _tab = gpkg_warstwy(rodzic)
        tabela = PREFIKS_TABELI + bez_ogonkow(nazwa).upper()
        nazwa_dziecka = 'zal_' + nazwa
        print('\n[%s]' % nazwa)

        nowa = utworz_tabele(gpkg, tabela)
        print('  tabela %s: %s' % (tabela, 'utworzona' if nowa else 'już była'))
        indeks_rodzica(gpkg, tabela)

        dziecko = None
        for lyr in proj.mapLayers().values():
            if isinstance(lyr, QgsVectorLayer):
                p, t = gpkg_warstwy(lyr)
                if p == gpkg and t == tabela:
                    dziecko = lyr
                    break
        if dziecko is None:
            uri = '{}|layername={}'.format(gpkg, tabela)
            dziecko = QgsVectorLayer(uri, nazwa_dziecka, 'ogr')
            if not dziecko.isValid():
                # GDAL bywa "przyzwyczajony" do starej zawartości pliku, który
                # QGIS trzyma otwarty — świeża tabela potrafi nie być widoczna
                # za pierwszym razem. Jedna ponowna próba zwykle wystarcza.
                dziecko = QgsVectorLayer(uri, nazwa_dziecka, 'ogr')
            if not dziecko.isValid():
                raise RuntimeError(
                    'Nie wczytano tabeli załączników: %s\n'
                    'Zamknij sesje edycji warstw, zapisz projekt i uruchom '
                    'skrypt jeszcze raz (tabela w pliku już jest, więc drugie '
                    'uruchomienie jej nie zdubluje).' % tabela)
            proj.addMapLayer(dziecko, False)
            print('  warstwa %s: dodana do projektu' % nazwa_dziecka)
        else:
            print('  warstwa %s: już była' % dziecko.name())
        do_grupy(proj, dziecko)

        konfiguruj_dziecko(dziecko, nazwa)
        print('  widgety i konwencja nazw: ustawione')

        rel_id = 'zal_' + nazwa
        istniejaca = proj.relationManager().relation(rel_id)
        if istniejaca is not None and istniejaca.isValid():
            print('  relacja %s: już była' % rel_id)
        else:
            rel = QgsRelation()
            rel.setId(rel_id)
            rel.setName('Załączniki')
            rel.setReferencedLayer(rodzic.id())
            rel.setReferencingLayer(dziecko.id())
            rel.addFieldPair(POLE_RODZIC, KLUCZ_RODZICA)
            _relation_composition(rel)
            if not rel.isValid():
                raise RuntimeError('Relacja nieprawidłowa dla warstwy ' + nazwa)
            proj.relationManager().addRelation(rel)
            print('  relacja %s: utworzona (%s -> %s)'
                  % (rel_id, POLE_RODZIC, KLUCZ_RODZICA))

        dolozona = dodaj_zakladke(rodzic, rel_id)
        print('  zakładka "%s": %s' % (
            NAZWA_ZAKLADKI,
            'dołożona' if dolozona else 'już była albo formularz automatyczny'))

        podsumowanie.append((nazwa, tabela, rel_id))

    if not proj.write():
        raise RuntimeError(
            'QGIS nie zapisał projektu: %s\n'
            'Tabele w GeoPackage są już założone — po usunięciu przyczyny '
            '(np. plik tylko do odczytu) uruchom skrypt ponownie.'
            % plik_projektu)
    print('\nZAPISANO projekt:', plik_projektu)
    print('%-18s %-22s %s' % ('WARSTWA', 'TABELA', 'RELACJA'))
    for nazwa, tabela, rel_id in podsumowanie:
        print('%-18s %-22s %s' % (nazwa, tabela, rel_id))
    print('\nSprawdź w terenie: otwórz obiekt -> zakładka "Załączniki" -> '
          'aparat. Kopie zapasowe mają sufiks .bak_%s' % znacznik)


if __name__ == '__console__' or __name__ == '__main__':
    _args = [a for a in sys.argv[1:] if not a.endswith('.py')]
    _projekt = PROJEKT or (_args[0] if _args else '')
    _warstwy = WARSTWY or (_args[1:] if len(_args) > 1 else None)
    main(_projekt, _warstwy)
