# -*- coding: utf-8 -*-
"""
Łatka LEKKA do etapu 2 załączników N:1 (patrz docs/ZALACZNIKI.md).

Trzy zmiany, żadna nie dotyka kolejki odroczeń ani paska szybkiego przechwytu:

  1. src/gui/qml/editorwidgets/relationeditors/gallery_relation_editor.qml
     Ewaluator konwencji nazw dostaje zmienne @rodzic_fid i @rodzic_warstwa.
     Bez tego wyrażenie w projekcie nie zna obiektu-rodzica i konwencja
     z podkatalogami (Mapit Spatial) nie ma się z czego policzyć.
     Zmiana generyczna, nie forkowa — kandydat na issue do QFielda.

  2. src/app/qml/QfPhotoGallery.qml
     Galeria widzi zdjęcia w podkatalogach DCIM (jeden poziom w głąb)
     i rozpoznaje warstwę mimo klucza obiektu w nazwie pliku.

  3. src/core/procesystudio.cpp
     "Zamień na szablon" czyści też tabele ZAL_* — inaczej szablon zrobiony
     z projektu terenowego wyjeżdża z cudzymi załącznikami.

URUCHOMIENIE (z katalogu repozytorium):
    python3 skrypty/latka_zalaczniki_lekka.py

Skrypt jest idempotentny: jeśli zmiana już jest, mówi "już jest" i nie rusza
pliku. Każda kotwica musi trafić dokładnie raz — inaczej STOP i żaden plik
nie zostaje zapisany.
"""
import os
import sys

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ------------------------------------------------------------------ 1. QML
GALERIA_REL = 'src/gui/qml/editorwidgets/relationeditors/gallery_relation_editor.qml'

REL_KOTWICA = """  ExpressionEvaluator {
    id: attachmentNamingEvaluator
    layer: referencingFeatureListModel.relation ? referencingFeatureListModel.relation.referencingLayer : null
    project: qgisProject
    appExpressionContextScopesGenerator: appScopesGenerator
  }
"""

REL_NOWE = """  ExpressionEvaluator {
    id: attachmentNamingEvaluator
    layer: referencingFeatureListModel.relation ? referencingFeatureListModel.relation.referencingLayer : null
    project: qgisProject
    appExpressionContextScopesGenerator: appScopesGenerator
    // WorkField: konwencja nazw załączników potrzebuje klucza obiektu-rodzica
    // (podkatalog na obiekt + klucz w nazwie pliku). Bez tych zmiennych
    // wyrażenie attachment_naming nie ma skąd wziąć rodzica.
    variables: ({
        "rodzic_fid": referencingFeatureListModel.feature.id,
        "rodzic_warstwa": referencingFeatureListModel.relation && referencingFeatureListModel.relation.referencedLayer ? referencingFeatureListModel.relation.referencedLayer.name : ""
      })
  }
"""

REL_ZNACZNIK = 'rodzic_fid'

# ------------------------------------------------------------- 2. GALERIA
GALERIA = 'src/app/qml/QfPhotoGallery.qml'

GAL_EXTRACT_KOTWICA = """  // <warstwa>_<yyyyMMdd_hhmmss>[_zzz] -> warstwa; image_0003 -> image (stary aparat)
  function extractLayer(name) {
    const base = name.replace(/\\.[^.]+$/, "");
    let m = base.match(/^(.*)_\\d{8}_\\d{6}(_\\d{1,3})?$/);
    if (m)
      return m[1];
    m = base.match(/^(.*)_\\d+$/);
    return m ? m[1] : base;
  }
"""

GAL_EXTRACT_NOWE = """  // <warstwa>_<yyyyMMdd_hhmmss>[_zzz] -> warstwa; image_0003 -> image (stary aparat)
  // Konwencja załączników dokłada klucz obiektu: <warstwa>_<fid>_<data>_<ms>,
  // a plik leży w podkatalogu o nazwie <warstwa>_<fid>. Klucz obcinamy tylko
  // wtedy, gdy katalog to potwierdza — dzięki temu warstwa nazwana "dzialki_2"
  // nie gubi swojej dwójki.
  function extractLayer(name, katalog) {
    const base = name.replace(/\\.[^.]+$/, "");
    let m = base.match(/^(.*)_\\d{8}_\\d{6}(_\\d{1,3})?$/);
    if (m) {
      if (katalog && katalog === m[1]) {
        const bezKlucza = m[1].match(/^(.*)_\\d+$/);
        return bezKlucza ? bezKlucza[1] : m[1];
      }
      return m[1];
    }
    m = base.match(/^(.*)_\\d+$/);
    return m ? m[1] : base;
  }
"""

GAL_EXTRACT_ZNACZNIK = 'function extractLayer(name, katalog)'

GAL_REBUILD_KOTWICA = """  function rebuildPhotos() {
    const arr = [];
    const prefixes = {};
    for (let i = 0; i < dcimModel.count; i++) {
      const name = dcimModel.get(i, "fileName");
      const layer = extractLayer(name);
      prefixes[layer] = true;
      if (layerFilter === "" || layer === layerFilter) {
        arr.push({
            "path": dcimModel.get(i, "filePath"),
            "name": name,
            "layer": layer,
            "mtime": dcimModel.get(i, "fileModified")
          });
      }
    }
    photos = arr;
"""

GAL_REBUILD_NOWE = """  //! zbiera zdjecia z jednego modelu katalogu do wspolnej listy
  function zbierzZKatalogu(model, katalog, arr, prefixes) {
    for (let i = 0; i < model.count; i++) {
      const name = model.get(i, "fileName");
      const layer = extractLayer(name, katalog);
      prefixes[layer] = true;
      if (layerFilter === "" || layer === layerFilter) {
        arr.push({
            "path": model.get(i, "filePath"),
            "name": name,
            "layer": layer,
            "mtime": model.get(i, "fileModified")
          });
      }
    }
  }

  function rebuildPhotos() {
    const arr = [];
    const prefixes = {};
    zbierzZKatalogu(dcimModel, "", arr, prefixes);
    // zdjecia w podkatalogach obiektow (konwencja zalacznikow N:1)
    for (let p = 0; p < podkatalogiDcim.count; p++) {
      const poz = podkatalogiDcim.itemAt(p);
      if (poz && poz.modelPlikow)
        zbierzZKatalogu(poz.modelPlikow, poz.nazwaKatalogu, arr, prefixes);
    }
    // kolejnosc: najnowsze pierwsze. Wczesniej wystarczalo sortowanie samego
    // FolderListModel, ale listy z kilku katalogow trzeba scalic recznie.
    arr.sort(function (a, b) {
      return b.mtime - a.mtime;
    });
    photos = arr;
"""

GAL_REBUILD_ZNACZNIK = 'function zbierzZKatalogu('

GAL_MODEL_KOTWICA = """  FolderListModel {
    id: dcimModel
    // QDir::Time = najnowsze pierwsze; odwrocenie: sortReversed: true
    folder: photoGallery.projectDir !== "" ? "file://" + photoGallery.projectDir + "/DCIM" : ""
    nameFilters: ["*.jpg", "*.jpeg", "*.JPG", "*.JPEG", "*.png", "*.PNG"]
    showDirs: false
    sortField: FolderListModel.Time
    onCountChanged: photoGallery.rebuildPhotos()
  }
"""

GAL_MODEL_NOWE = """  FolderListModel {
    id: dcimModel
    // QDir::Time = najnowsze pierwsze; odwrocenie: sortReversed: true
    folder: photoGallery.projectDir !== "" ? "file://" + photoGallery.projectDir + "/DCIM" : ""
    nameFilters: ["*.jpg", "*.jpeg", "*.JPG", "*.JPEG", "*.png", "*.PNG"]
    showDirs: false
    sortField: FolderListModel.Time
    onCountChanged: photoGallery.rebuildPhotos()
  }

  // Podkatalogi DCIM: konwencja zalacznikow trzyma pliki obiektu w katalogu
  // <warstwa>_<klucz>. Kosz (.kosz) jest ukryty, wiec nie wchodzi do modelu.
  FolderListModel {
    id: katalogiDcim
    folder: photoGallery.projectDir !== "" ? "file://" + photoGallery.projectDir + "/DCIM" : ""
    showDirs: true
    showFiles: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
    onCountChanged: photoGallery.rebuildPhotos()
  }

  Item {
    visible: false
    Repeater {
      id: podkatalogiDcim
      model: katalogiDcim
      delegate: Item {
        required property string fileName
        required property string filePath
        property string nazwaKatalogu: fileName
        property alias modelPlikow: plikiPodkatalogu
        FolderListModel {
          id: plikiPodkatalogu
          folder: "file://" + filePath
          nameFilters: ["*.jpg", "*.jpeg", "*.JPG", "*.JPEG", "*.png", "*.PNG"]
          showDirs: false
          sortField: FolderListModel.Time
          onCountChanged: photoGallery.rebuildPhotos()
        }
      }
    }
  }
"""

GAL_MODEL_ZNACZNIK = 'id: katalogiDcim'

# ---------------------------------------------------------------- 3. C++
STUDIO = 'src/core/procesystudio.cpp'

STUDIO_KOTWICA = """  //! czysci tabele FITO_* w jednym GPKG; zwraca liczbe wyczyszczonych
  int wyczyscFito( const QString &sciezka )
  {
    sqlite3 *baza = nullptr;
    if ( sqlite3_open( sciezka.toUtf8().constData(), &baza ) != SQLITE_OK )
      return 0;
    QStringList tabele;
    sqlite3_stmt *zapytanie = nullptr;
    if ( sqlite3_prepare_v2( baza,
           "SELECT table_name FROM gpkg_contents "
           "WHERE table_name LIKE 'FITO\\\\_%' ESCAPE '\\\\'",
           -1, &zapytanie, nullptr ) == SQLITE_OK )
"""

STUDIO_NOWE = """  //! czysci tabele FITO_* i ZAL_* w jednym GPKG; zwraca liczbe wyczyszczonych
  int wyczyscFito( const QString &sciezka )
  {
    sqlite3 *baza = nullptr;
    if ( sqlite3_open( sciezka.toUtf8().constData(), &baza ) != SQLITE_OK )
      return 0;
    QStringList tabele;
    sqlite3_stmt *zapytanie = nullptr;
    if ( sqlite3_prepare_v2( baza,
           "SELECT table_name FROM gpkg_contents "
           "WHERE table_name LIKE 'FITO\\\\_%' ESCAPE '\\\\' "
           "OR table_name LIKE 'ZAL\\\\_%' ESCAPE '\\\\'",
           -1, &zapytanie, nullptr ) == SQLITE_OK )
"""

STUDIO_ZNACZNIK = "LIKE 'ZAL"

# --------------------------------------------------------------- mechanika
ZMIANY = [
    (GALERIA_REL, REL_KOTWICA, REL_NOWE, REL_ZNACZNIK,
     'edytor galerii: zmienne @rodzic_fid / @rodzic_warstwa'),
    (GALERIA, GAL_EXTRACT_KOTWICA, GAL_EXTRACT_NOWE, GAL_EXTRACT_ZNACZNIK,
     'galeria: extractLayer rozumie klucz obiektu'),
    (GALERIA, GAL_REBUILD_KOTWICA, GAL_REBUILD_NOWE, GAL_REBUILD_ZNACZNIK,
     'galeria: zbieranie zdjęć z podkatalogów'),
    (GALERIA, GAL_MODEL_KOTWICA, GAL_MODEL_NOWE, GAL_MODEL_ZNACZNIK,
     'galeria: model podkatalogów DCIM'),
    (STUDIO, STUDIO_KOTWICA, STUDIO_NOWE, STUDIO_ZNACZNIK,
     'magazyn: "Zamień na szablon" czyści też ZAL_*'),
]


def main():
    plany = {}
    pominiete = []
    bledy = []

    for plik, kotwica, nowe, znacznik, opis in ZMIANY:
        sciezka = os.path.join(KATALOG, plik)
        if not os.path.exists(sciezka):
            bledy.append('%s: nie ma pliku %s' % (opis, plik))
            continue
        tresc = plany.get(sciezka)
        if tresc is None:
            with open(sciezka, encoding='utf-8') as f:
                tresc = f.read()
        if znacznik in tresc:
            pominiete.append(opis)
            plany[sciezka] = tresc
            continue
        ile = tresc.count(kotwica)
        if ile != 1:
            bledy.append('%s: kotwica trafia %d razy (oczekiwano 1) w %s'
                         % (opis, ile, plik))
            continue
        plany[sciezka] = tresc.replace(kotwica, nowe, 1)

    if bledy:
        print('STOP — nic nie zapisano:')
        for b in bledy:
            print('  !', b)
        print('\nPlik w repo różni się od oczekiwanego. Zrób "git status" '
              'i "git diff", potem odezwij się z wynikiem.')
        return 1

    for sciezka, tresc in plany.items():
        with open(sciezka, 'w', encoding='utf-8') as f:
            f.write(tresc)

    for _plik, _k, _n, _z, opis in ZMIANY:
        print('  %s %s' % ('. już było:' if opis in pominiete else '+ zrobione:',
                           opis))
    print('\nZmienione pliki:')
    for sciezka in sorted(plany):
        print('  ', os.path.relpath(sciezka, KATALOG))
    print('\nDalej: cmake --build build-sys -j$(nproc) i test na komputerze, '
          'potem build Androida.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
