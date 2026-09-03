# -*- coding: utf-8 -*-
"""
Łatka 2b-1: pasek szybkiego przechwytu zapisuje zdjęcie do tabeli załączników.

FUNDAMENT — obejmuje tryb szybki (krótkie tapnięcie kafla) i kolejkę odroczeń.
Seria pod długim przytrzymaniem i aparat w nagłówku formularza wchodzą osobno,
na tym fundamencie.

Zmiany:

  1. src/core/utils/zalacznikiutils.{h,cpp}  (NOWE PLIKI — muszą już leżeć
     w repo, skrypt ich nie tworzy)
     Pomocnik C++: która tabela jest tabelą załączników danej warstwy i jakim
     kluczem się do niej wchodzi. Menedżer relacji QGIS nie jest wystawiony
     do QML, więc bez tego pasek jest ślepy.

  2. src/core/CMakeLists.txt — nowe pliki do budowy.

  3. src/core/qfieldcoreqmlregistration.cpp — ZalacznikiUtils widoczne z QML.

  4. src/app/qml/QfQuickCaptureBar.qml
     - model FeatureModel do zapisu załączników,
     - funkcja dopnijZalacznik(): tworzy wiersz w ZAL_<warstwa> dla właśnie
       zapisanego obiektu,
     - tryb szybki: ścieżka zdjęcia NIE idzie już do pola "foto", gdy warstwa
       ma tabelę załączników; idzie do tabeli, a pole "foto" zostaje pustym
       zapasem na wypadek nieudanego zapisu (wtedy dodatkowo głośny toast),
     - kolejka odroczeń niesie zdjęcie razem z obiektem i dopina je po zapisie.

  Pozostałe ścieżki paska — kotwice, obiekt odległy, zdjęcie przed geometrią —
  na razie zapisują jak dotąd, do pola "foto". Przejdą w następnym kroku.

URUCHOMIENIE (z katalogu repozytorium):
    python3 skrypty/latka_zalaczniki_pasek.py

Idempotentna. Każda kotwica musi trafić dokładnie raz — inaczej STOP i żaden
plik nie zostaje zapisany.
"""
import os
import sys

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ------------------------------------------------------------------ CMake
CMAKE = 'src/core/CMakeLists.txt'

CMAKE_CPP_KOTWICA = """    phototagstore.cpp
    tabelamodel.cpp
    procesystudio.cpp
"""
CMAKE_CPP_NOWE = """    phototagstore.cpp
    tabelamodel.cpp
    procesystudio.cpp
    utils/zalacznikiutils.cpp
"""
CMAKE_CPP_ZNACZNIK = 'utils/zalacznikiutils.cpp'

CMAKE_H_KOTWICA = """    phototagstore.h
    tabelamodel.h
    procesystudio.h
"""
CMAKE_H_NOWE = """    phototagstore.h
    tabelamodel.h
    procesystudio.h
    utils/zalacznikiutils.h
"""
CMAKE_H_ZNACZNIK = 'utils/zalacznikiutils.h'

# ----------------------------------------------------------- rejestracja QML
REJESTRACJA = 'src/core/qfieldcoreqmlregistration.cpp'

REJ_INCLUDE_KOTWICA = '#include "utils/relationutils.h"\n'
REJ_INCLUDE_NOWE = ('#include "utils/relationutils.h"\n'
                    '#include "utils/zalacznikiutils.h"\n')
REJ_INCLUDE_ZNACZNIK = 'utils/zalacznikiutils.h'

REJ_SINGLETON_KOTWICA = """    REGISTER_SINGLETON( "org.qfield", UrlUtils, "UrlUtils" );
"""
REJ_SINGLETON_NOWE = """    REGISTER_SINGLETON( "org.qfield", UrlUtils, "UrlUtils" );
    REGISTER_SINGLETON( "org.qfield", ZalacznikiUtils, "ZalacznikiUtils" );
"""
REJ_SINGLETON_ZNACZNIK = 'ZalacznikiUtils, "ZalacznikiUtils"'

# --------------------------------------------------------------- pasek QML
PASEK = 'src/app/qml/QfQuickCaptureBar.qml'

# --- 4a. model zapisu + funkcja dopinajaca zalacznik
PASEK_MODEL_KOTWICA = """  // model do cichego zapisu w trybie szybkim - niezalezny od szuflady formularza
  FeatureModel {
    id: silentFeatureModel
    project: qgisProject
  }
"""

PASEK_MODEL_NOWE = """  // model do cichego zapisu w trybie szybkim - niezalezny od szuflady formularza
  FeatureModel {
    id: silentFeatureModel
    project: qgisProject
  }

  // WorkField: osobny model do zapisu zalacznikow (tabele ZAL_<warstwa>).
  // Osobny, bo silentFeatureModel trzyma wlasnie zapisanego rodzica i jego
  // klucz jest nam potrzebny az do konca dopinania.
  FeatureModel {
    id: zalacznikFeatureModel
    project: qgisProject
  }

  //! Czy warstwa ma tabele zalacznikow (relacja + pole ExternalResource)?
  function maZalaczniki(layer) {
    if (!layer) {
      return false;
    }
    return ZalacznikiUtils.relacjaZalacznikow(layer).istnieje === true;
  }

  /**
   * Dopina zalacznik do WLASNIE ZAPISANEGO obiektu rodzica.
   *
   * Zwraca true przy powodzeniu. Przy porazce nic nie zapisuje i zostawia
   * decyzje wolajacemu — w trybie szybkim scieżka ląduje wtedy w starym polu
   * "foto" rodzica, zeby zdjecie z terenu nigdy nie zniknelo tylko dlatego,
   * ze nie zmiescilo sie w modelu danych.
   */
  function dopnijZalacznik(layerRodzica, featureRodzica, sciezka, ujecie, typ) {
    if (!layerRodzica || !sciezka || sciezka === "") {
      return false;
    }
    const opis = ZalacznikiUtils.relacjaZalacznikow(layerRodzica);
    if (opis.istnieje !== true || !opis.warstwa) {
      return false;
    }
    const klucz = ZalacznikiUtils.kluczRodzica(layerRodzica, featureRodzica);
    if (klucz === undefined || klucz === null || klucz === "") {
      return false;
    }
    const dziecko = FeatureUtils.createFeature(opis.warstwa);
    if (!dziecko) {
      return false;
    }
    const nazwy = dziecko.fields.names;
    dziecko.setAttribute(opis.poleObce, klucz);
    dziecko.setAttribute(opis.poleSciezki, sciezka);
    if (opis.poleTypu && nazwy.indexOf(opis.poleTypu) >= 0) {
      dziecko.setAttribute(opis.poleTypu, typ && typ !== "" ? typ : "foto");
    }
    if (ujecie && ujecie !== "" && opis.poleUjecia && nazwy.indexOf(opis.poleUjecia) >= 0) {
      dziecko.setAttribute(opis.poleUjecia, ujecie);
    }
    zalacznikFeatureModel.currentLayer = opis.warstwa;
    zalacznikFeatureModel.feature = dziecko;
    return zalacznikFeatureModel.create();
  }
"""

PASEK_MODEL_ZNACZNIK = 'function dopnijZalacznik('

# --- 4b. tryb szybki: scieżka nie idzie do pola "foto", gdy sa zalaczniki
PASEK_FOTO_KOTWICA = """    let feature = pendingFeature;
    const fieldNames = feature.fields.names;
    if (photoPath && photoPath !== "" && fieldNames.indexOf("foto") >= 0) {
      feature.setAttribute("foto", photoPath);
      if (cameraSource && cameraSource.photoShotType && fieldNames.indexOf("ujecie") >= 0) {
        feature.setAttribute("ujecie", cameraSource.photoShotType);
      }
    }
"""

PASEK_FOTO_NOWE = """    let feature = pendingFeature;
    const fieldNames = feature.fields.names;
    // WorkField: gdy warstwa ma tabele zalacznikow, scieżka idzie tam, a nie
    // w pole "foto" — wiersz powstaje dopiero po zapisie rodzica, bo wczesniej
    // nie ma klucza, do ktorego mozna by go przypiac.
    const zalacznikiTutaj = maZalaczniki(pendingLayer);
    const ujecieTeraz = cameraSource && cameraSource.photoShotType ? cameraSource.photoShotType : "";
    if (photoPath && photoPath !== "" && !zalacznikiTutaj && fieldNames.indexOf("foto") >= 0) {
      feature.setAttribute("foto", photoPath);
      if (ujecieTeraz !== "" && fieldNames.indexOf("ujecie") >= 0) {
        feature.setAttribute("ujecie", ujecieTeraz);
      }
    }
"""

PASEK_FOTO_ZNACZNIK = 'const zalacznikiTutaj = maZalaczniki(pendingLayer)'

# --- 4c. kolejka odroczen niesie zdjecie
PASEK_ODROCZ_KOTWICA = """      odroczone.push({
          "layer": pendingLayer,
          "feature": feature
        });
"""

PASEK_ODROCZ_NOWE = """      odroczone.push({
          "layer": pendingLayer,
          "feature": feature,
          // WorkField: zalacznik czeka razem z obiektem — dopnie sie dopiero,
          // gdy rodzic dostanie swoj klucz przy materializacji kolejki
          "zalacznik": zalacznikiTutaj && photoPath && photoPath !== "" ? {
            "sciezka": photoPath,
            "ujecie": ujecieTeraz
          } : null
        });
"""

PASEK_ODROCZ_ZNACZNIK = '"zalacznik": zalacznikiTutaj'

# --- 4d. materializacja kolejki dopina zalaczniki
PASEK_MATER_KOTWICA = """      silentFeatureModel.currentLayer = wpis.layer;
      silentFeatureModel.feature = wpis.feature;
      if (silentFeatureModel.create()) {
        zapisane += 1;
        wgWarstw[wpis.layer.name] = (wgWarstw[wpis.layer.name] || 0) + 1;
      } else {
        nieudane += 1;
      }
"""

PASEK_MATER_NOWE = """      silentFeatureModel.currentLayer = wpis.layer;
      silentFeatureModel.feature = wpis.feature;
      if (silentFeatureModel.create()) {
        zapisane += 1;
        wgWarstw[wpis.layer.name] = (wgWarstw[wpis.layer.name] || 0) + 1;
        if (wpis.zalacznik) {
          if (!dopnijZalacznik(wpis.layer, silentFeatureModel.feature, wpis.zalacznik.sciezka, wpis.zalacznik.ujecie, "foto")) {
            zalacznikiNieudane.push(wpis.zalacznik.sciezka);
          }
        }
      } else {
        nieudane += 1;
      }
"""

PASEK_MATER_ZNACZNIK = 'zalacznikiNieudane.push('

# --- 4e. licznik nieudanych zalacznikow w kolejce + komunikat
PASEK_LICZNIK_KOTWICA = """    const kolejka = odroczone;
    odroczone = [];
    let zapisane = 0;
    let nieudane = 0;
    const wgWarstw = {};
"""

PASEK_LICZNIK_NOWE = """    const kolejka = odroczone;
    odroczone = [];
    let zapisane = 0;
    let nieudane = 0;
    const zalacznikiNieudane = [];
    const wgWarstw = {};
"""

PASEK_LICZNIK_ZNACZNIK = 'const zalacznikiNieudane = []'

PASEK_KOMUNIKAT_KOTWICA = """    if (nieudane > 0) {
      displayToast(qsTr("Nie zapisano %1 wpisów odroczonych (zdjęcia ocalone w DCIM)").arg(nieudane), "error");
    }
"""

PASEK_KOMUNIKAT_NOWE = """    if (nieudane > 0) {
      displayToast(qsTr("Nie zapisano %1 wpisów odroczonych (zdjęcia ocalone w DCIM)").arg(nieudane), "error");
    }
    if (zalacznikiNieudane.length > 0) {
      displayToast(qsTr("Obiekty zapisane, ale %1 zdjęć nie podpięło się jako załączniki — pliki są w DCIM").arg(zalacznikiNieudane.length), "error");
    }
"""

PASEK_KOMUNIKAT_ZNACZNIK = 'zalacznikiNieudane.length > 0'

# --- 4f. cichy zapis w trybie szybkim dopina zalacznik
PASEK_CICHY_KOTWICA = """      silentFeatureModel.currentLayer = pendingLayer;
      silentFeatureModel.feature = feature;
      if (silentFeatureModel.create()) {
        seriesCount += 1;
        displayToast(qsTr("Zapisano: %1 (%2. w serii)").arg(pendingLayer.name).arg(seriesCount));
      } else {
        displayToast(qsTr("NIE zapisano obiektu — zdjęcie ocalone: %1").arg(photoPath), "error");
      }
"""

PASEK_CICHY_NOWE = """      silentFeatureModel.currentLayer = pendingLayer;
      silentFeatureModel.feature = feature;
      const warstwaZapisu = pendingLayer;
      if (silentFeatureModel.create()) {
        seriesCount += 1;
        let zalacznikOk = true;
        if (zalacznikiTutaj && photoPath && photoPath !== "") {
          zalacznikOk = dopnijZalacznik(warstwaZapisu, silentFeatureModel.feature, photoPath, ujecieTeraz, "foto");
          if (!zalacznikOk) {
            // zapas awaryjny: scieżka wraca do starego pola, zeby zdjecie
            // nie zostalo bez obiektu — i mowimy o tym glosno
            const nazwyZapisu = silentFeatureModel.feature.fields.names;
            if (nazwyZapisu.indexOf("foto") >= 0) {
              silentFeatureModel.feature.setAttribute("foto", photoPath);
              if (ujecieTeraz !== "" && nazwyZapisu.indexOf("ujecie") >= 0) {
                silentFeatureModel.feature.setAttribute("ujecie", ujecieTeraz);
              }
              silentFeatureModel.save();
            }
          }
        }
        if (zalacznikOk) {
          displayToast(qsTr("Zapisano: %1 (%2. w serii)").arg(pendingLayer.name).arg(seriesCount));
        } else {
          displayToast(qsTr("Obiekt zapisany, ale zdjęcie nie weszło do załączników — ścieżka w polu foto"), "error");
        }
      } else {
        displayToast(qsTr("NIE zapisano obiektu — zdjęcie ocalone: %1").arg(photoPath), "error");
      }
"""

PASEK_CICHY_ZNACZNIK = 'const warstwaZapisu = pendingLayer'

# --------------------------------------------------------------- mechanika
ZMIANY = [
    (CMAKE, CMAKE_CPP_KOTWICA, CMAKE_CPP_NOWE, CMAKE_CPP_ZNACZNIK,
     'CMake: zalacznikiutils.cpp'),
    (CMAKE, CMAKE_H_KOTWICA, CMAKE_H_NOWE, CMAKE_H_ZNACZNIK,
     'CMake: zalacznikiutils.h'),
    (REJESTRACJA, REJ_INCLUDE_KOTWICA, REJ_INCLUDE_NOWE, REJ_INCLUDE_ZNACZNIK,
     'rejestracja QML: include'),
    (REJESTRACJA, REJ_SINGLETON_KOTWICA, REJ_SINGLETON_NOWE, REJ_SINGLETON_ZNACZNIK,
     'rejestracja QML: singleton ZalacznikiUtils'),
    (PASEK, PASEK_MODEL_KOTWICA, PASEK_MODEL_NOWE, PASEK_MODEL_ZNACZNIK,
     'pasek: model zapisu + dopnijZalacznik()'),
    (PASEK, PASEK_FOTO_KOTWICA, PASEK_FOTO_NOWE, PASEK_FOTO_ZNACZNIK,
     'pasek: ścieżka omija pole foto, gdy są załączniki'),
    (PASEK, PASEK_ODROCZ_KOTWICA, PASEK_ODROCZ_NOWE, PASEK_ODROCZ_ZNACZNIK,
     'pasek: kolejka odroczeń niesie zdjęcie'),
    (PASEK, PASEK_LICZNIK_KOTWICA, PASEK_LICZNIK_NOWE, PASEK_LICZNIK_ZNACZNIK,
     'pasek: licznik nieudanych załączników'),
    (PASEK, PASEK_MATER_KOTWICA, PASEK_MATER_NOWE, PASEK_MATER_ZNACZNIK,
     'pasek: materializacja kolejki dopina załączniki'),
    (PASEK, PASEK_KOMUNIKAT_KOTWICA, PASEK_KOMUNIKAT_NOWE, PASEK_KOMUNIKAT_ZNACZNIK,
     'pasek: komunikat o niedopiętych załącznikach'),
    (PASEK, PASEK_CICHY_KOTWICA, PASEK_CICHY_NOWE, PASEK_CICHY_ZNACZNIK,
     'pasek: cichy zapis dopina załącznik z zapasem awaryjnym'),
]

WYMAGANE_PLIKI = [
    'src/core/utils/zalacznikiutils.h',
    'src/core/utils/zalacznikiutils.cpp',
]


def main():
    plany = {}
    pominiete = []
    bledy = []

    for plik in WYMAGANE_PLIKI:
        if not os.path.exists(os.path.join(KATALOG, plik)):
            bledy.append('brakuje nowego pliku: %s '
                         '(wgraj go do repo przed uruchomieniem łatki)' % plik)

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
    print('\nDalej: cmake -S . -B build-sys -Wno-dev  (nowe pliki w CMake!)')
    print('       cmake --build build-sys -j$(nproc)')
    print('W logu builda muszą pojawić się zalacznikiutils.cpp '
          'oraz "Running rcc for resource app_qml".')
    return 0


if __name__ == '__main__':
    sys.exit(main())
