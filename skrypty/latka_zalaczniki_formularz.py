# -*- coding: utf-8 -*-
"""
Łatka 2b-2: zdjęcie z paska trafia do załączników także wtedy, gdy obiekt
zapisuje FORMULARZ, a nie pasek.

Nakładaj po latka_zalaczniki_pasek.py i latka_zalaczniki_pasek_fix.py.

Problem: dwie drogi paska nie zapisują obiektu same, tylko otwierają szufladę
formularza — tryb dokładny (kafel bez błyskawicy) oraz kafel „zdjęcie, potem
geometria". W obu klucz obiektu powstaje dopiero, gdy operator zatwierdzi
formularz, więc dopięcie załącznika musi na ten moment poczekać.

Rozwiązanie: pasek zapamiętuje „załącznik oczekujący" i dopina go, gdy
formularz zgłosi zapis (FeatureForm ma sygnał saved). Porzucenie formularza
kasuje oczekiwanie, żeby zdjęcie nie przykleiło się do następnego obiektu.

Po tej łatce WSZYSTKIE drogi paska poza kotwicami i obiektem odległym
zapisują zdjęcia do tabeli załączników.

URUCHOMIENIE (z katalogu repozytorium):
    python3 skrypty/latka_zalaczniki_formularz.py

Idempotentna. Kotwica musi trafić dokładnie raz — inaczej STOP.
"""
import os
import sys

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASEK = 'src/app/qml/QfQuickCaptureBar.qml'

# --------------------------------- 1. warunek obejmuje znowu wszystkie drogi
WARUNEK_KOTWICA = """    // Pole "foto" pomijamy TYLKO wtedy, gdy pasek sam zapisze obiekt i dopnie
    // zalacznik — czyli w trybie szybkim albo przez kolejke odroczen.
    // W trybie dokladnym obiekt zapisuje formularz, wiec zalacznika nie ma kto
    // dopiac; tam scieżka musi isc po staremu do pola, zeby zdjecie nie zostalo
    // w DCIM bez zadnego dowiazania.
    const zapiszemyZalacznik = zalacznikiTutaj && (odroczenieFlow || stateMachine.state === "digitize" || qfieldSettings.fastMode);
"""

WARUNEK_NOWE = """    // Pole "foto" pomijamy zawsze, gdy warstwa ma tabele zalacznikow — kazda
    // droga paska ma juz swoje miejsce dopiecia: tryb szybki dopina od razu po
    // cichym zapisie, kolejka odroczen przy materializacji, a tryb dokladny
    // przez zalacznik oczekujacy, gdy formularz zglosi zapis.
    const zapiszemyZalacznik = zalacznikiTutaj;
"""

WARUNEK_ZNACZNIK = 'const zapiszemyZalacznik = zalacznikiTutaj;'

# ------------------------------------------- 2. tryb dokladny odklada zalacznik
DOKLADNY_KOTWICA = """    // tryb dokladny: formularz przez szuflade
    // celowo bez dotykania dashBoard.activeLayer - przypisanie imperatywne,
    // binding do warstwy aktywnej odtwarzany przy zamknieciu szuflady
    overlayFeatureFormDrawer.featureModel.currentLayer = pendingLayer;
"""

DOKLADNY_NOWE = """    // tryb dokladny: formularz przez szuflade
    // WorkField: obiekt zapisze formularz, wiec zalacznik czeka na jego zapis
    if (zapiszemyZalacznik && photoPath && photoPath !== "") {
      ustawZalacznikOczekujacy(pendingLayer, photoPath, ujecieTeraz);
    }
    // celowo bez dotykania dashBoard.activeLayer - przypisanie imperatywne,
    // binding do warstwy aktywnej odtwarzany przy zamknieciu szuflady
    overlayFeatureFormDrawer.featureModel.currentLayer = pendingLayer;
"""

DOKLADNY_ZNACZNIK = 'ustawZalacznikOczekujacy(pendingLayer, photoPath, ujecieTeraz)'

# ------------------------------- 3. zdjecie przed geometria odklada zalacznik
GEOM_KOTWICA = """    const fieldNames = feature.fields.names;
    if (fieldNames.indexOf("foto") >= 0) {
      feature.setAttribute("foto", pendingGeomPhoto);
      if (cameraSource && cameraSource.photoShotType && fieldNames.indexOf("ujecie") >= 0) {
        feature.setAttribute("ujecie", cameraSource.photoShotType);
      }
    }
"""

GEOM_NOWE = """    const fieldNames = feature.fields.names;
    const ujecieGeom = cameraSource && cameraSource.photoShotType ? cameraSource.photoShotType : "";
    // WorkField: obiekt powstaje przez formularz po narysowaniu geometrii,
    // wiec zalacznik czeka na zapis formularza; bez tabeli zalacznikow
    // scieżka idzie po staremu do pola "foto"
    if (maZalaczniki(pendingGeomLayer)) {
      ustawZalacznikOczekujacy(pendingGeomLayer, pendingGeomPhoto, ujecieGeom);
    } else if (fieldNames.indexOf("foto") >= 0) {
      feature.setAttribute("foto", pendingGeomPhoto);
      if (ujecieGeom !== "" && fieldNames.indexOf("ujecie") >= 0) {
        feature.setAttribute("ujecie", ujecieGeom);
      }
    }
"""

GEOM_ZNACZNIK = 'ustawZalacznikOczekujacy(pendingGeomLayer, pendingGeomPhoto, ujecieGeom)'

# ------------------------------- 4. mechanika zalacznika oczekujacego
MECHANIKA_KOTWICA = """  //! Czy warstwa ma tabele zalacznikow (relacja + pole ExternalResource)?
"""

MECHANIKA_NOWE = """  // WorkField: zalacznik czekajacy na zapis obiektu przez FORMULARZ.
  // {layer, sciezka, ujecie} albo null. Kasowany przy zamknieciu szuflady,
  // zeby porzucone zdjecie nie przyklejalo sie do nastepnego obiektu.
  property var zalacznikOczekujacy: null

  function ustawZalacznikOczekujacy(layer, sciezka, ujecie) {
    zalacznikOczekujacy = {
      "layer": layer,
      "sciezka": sciezka,
      "ujecie": ujecie ? ujecie : ""
    };
  }

  //! Dopina zalacznik oczekujacy do obiektu zapisanego przez szuflade formularza
  function dopnijZalacznikPoFormularzu() {
    const czeka = zalacznikOczekujacy;
    zalacznikOczekujacy = null;
    if (!czeka || !czeka.layer || !czeka.sciezka) {
      return;
    }
    const model = overlayFeatureFormDrawer.featureModel;
    if (!model || model.currentLayer !== czeka.layer) {
      displayToast(qsTr("UWAGA: zdjęcie bez dowiązania — plik jest w DCIM: %1").arg(czeka.sciezka), "error");
      return;
    }
    if (!dopnijZalacznik(czeka.layer, model.feature, czeka.sciezka, czeka.ujecie, "foto")) {
      displayToast(qsTr("UWAGA: zdjęcie bez dowiązania — plik jest w DCIM: %1").arg(czeka.sciezka), "error");
    }
  }

  Connections {
    target: typeof overlayFeatureFormDrawer !== 'undefined' ? overlayFeatureFormDrawer.featureForm : null
    ignoreUnknownSignals: true

    function onSaved() {
      quickCaptureBar.dopnijZalacznikPoFormularzu();
    }
  }

  Connections {
    target: typeof overlayFeatureFormDrawer !== 'undefined' ? overlayFeatureFormDrawer : null
    ignoreUnknownSignals: true

    // porzucony formularz = porzucone dowiazanie; plik zostaje w DCIM
    function onClosed() {
      if (quickCaptureBar.zalacznikOczekujacy) {
        const zgubione = quickCaptureBar.zalacznikOczekujacy.sciezka;
        quickCaptureBar.zalacznikOczekujacy = null;
        displayToast(qsTr("Formularz porzucony — zdjęcie zostało w DCIM: %1").arg(zgubione), "warning");
      }
    }
  }

  //! Czy warstwa ma tabele zalacznikow (relacja + pole ExternalResource)?
"""

MECHANIKA_ZNACZNIK = 'function dopnijZalacznikPoFormularzu('

ZMIANY = [
    (PASEK, MECHANIKA_KOTWICA, MECHANIKA_NOWE, MECHANIKA_ZNACZNIK,
     'mechanika załącznika oczekującego'),
    (PASEK, WARUNEK_KOTWICA, WARUNEK_NOWE, WARUNEK_ZNACZNIK,
     'warunek obejmuje wszystkie drogi paska'),
    (PASEK, DOKLADNY_KOTWICA, DOKLADNY_NOWE, DOKLADNY_ZNACZNIK,
     'tryb dokładny odkłada załącznik'),
    (PASEK, GEOM_KOTWICA, GEOM_NOWE, GEOM_ZNACZNIK,
     'zdjęcie przed geometrią odkłada załącznik'),
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
        print('\nCzy nałożone są obie wcześniejsze łatki paska?')
        return 1

    for sciezka, tresc in plany.items():
        with open(sciezka, 'w', encoding='utf-8') as f:
            f.write(tresc)

    for _plik, _k, _n, _z, opis in ZMIANY:
        print('  %s %s' % ('. już było:' if opis in pominiete else '+ zrobione:',
                           opis))
    print('\nDalej: cmake --build build-sys -j$(nproc)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
