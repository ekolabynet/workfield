# -*- coding: utf-8 -*-
"""
Łatka DIAGNOSTYCZNA — wypisuje do logu każdy krok dopinania załącznika.

Nie zmienia zachowania, tylko dokłada console.log w sześciu miejscach, żeby
było widać, gdzie łańcuch się urywa:

    ZAL: maZalaczniki(<warstwa>) = true/false
    ZAL: ustawiam oczekujacy ...
    ZAL: formularz zglosil zapis ...
    ZAL: dopnijZalacznik ...

Po znalezieniu przyczyny zdejmiemy ją jednym `git checkout` albo zostawimy
tylko te linie, które okażą się przydatne na stałe.

URUCHOMIENIE (z katalogu repozytorium):
    python3 skrypty/latka_zalaczniki_diag.py
    cmake --build build-sys -j$(nproc)
    ./build-sys/output/bin/qfield 2>&1 | grep "ZAL:"

Idempotentna.
"""
import os
import sys

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASEK = 'src/app/qml/QfQuickCaptureBar.qml'

# 1. maZalaczniki
MZ_KOTWICA = """  function maZalaczniki(layer) {
    if (!layer) {
      return false;
    }
    return ZalacznikiUtils.relacjaZalacznikow(layer).istnieje === true;
  }
"""
MZ_NOWE = """  function maZalaczniki(layer) {
    if (!layer) {
      console.log("ZAL: maZalaczniki — brak warstwy");
      return false;
    }
    let opisDiag = null;
    try {
      opisDiag = ZalacznikiUtils.relacjaZalacznikow(layer);
    } catch (e) {
      console.log("ZAL: BLAD wolania ZalacznikiUtils:", e);
      return false;
    }
    console.log("ZAL: maZalaczniki(" + layer.name + ") =", opisDiag ? opisDiag.istnieje : "brak mapy", "| relacja:", opisDiag ? opisDiag.relacja : "-", "| pole:", opisDiag ? opisDiag.poleSciezki : "-");
    return opisDiag && opisDiag.istnieje === true;
  }
"""
MZ_ZNACZNIK = 'ZAL: maZalaczniki('

# 2. ustawZalacznikOczekujacy
UZ_KOTWICA = """  function ustawZalacznikOczekujacy(layer, sciezka, ujecie) {
    zalacznikOczekujacy = {
"""
UZ_NOWE = """  function ustawZalacznikOczekujacy(layer, sciezka, ujecie) {
    console.log("ZAL: ustawiam oczekujacy —", layer ? layer.name : "brak warstwy", sciezka);
    zalacznikOczekujacy = {
"""
UZ_ZNACZNIK = 'ZAL: ustawiam oczekujacy'

# 3. dopnijZalacznikPoFormularzu
PF_KOTWICA = """    const czeka = zalacznikOczekujacy;
    zalacznikOczekujacy = null;
    if (!czeka || !czeka.layer || !czeka.sciezka) {
      return;
    }
    const model = overlayFeatureFormDrawer.featureModel;
    if (!model || model.currentLayer !== czeka.layer) {
"""
PF_NOWE = """    const czeka = zalacznikOczekujacy;
    zalacznikOczekujacy = null;
    console.log("ZAL: formularz zglosil zapis — oczekujacy:", czeka ? czeka.sciezka : "BRAK");
    if (!czeka || !czeka.layer || !czeka.sciezka) {
      return;
    }
    const model = overlayFeatureFormDrawer.featureModel;
    console.log("ZAL: warstwa modelu:", model && model.currentLayer ? model.currentLayer.name : "brak", "| oczekiwana:", czeka.layer.name, "| fid:", model && model.feature ? model.feature.id : "brak");
    if (!model || model.currentLayer !== czeka.layer) {
"""
PF_ZNACZNIK = 'ZAL: formularz zglosil zapis'

# 4. dopnijZalacznik — wejscie i wszystkie wczesne wyjscia
DZ_KOTWICA = """    const opis = ZalacznikiUtils.relacjaZalacznikow(layerRodzica);
    if (opis.istnieje !== true || !opis.warstwa) {
      return false;
    }
    const klucz = ZalacznikiUtils.kluczRodzica(layerRodzica, featureRodzica);
    if (klucz === undefined || klucz === null || klucz === "") {
      return false;
    }
"""
DZ_NOWE = """    const opis = ZalacznikiUtils.relacjaZalacznikow(layerRodzica);
    if (opis.istnieje !== true || !opis.warstwa) {
      console.log("ZAL: dopnijZalacznik — brak relacji dla", layerRodzica.name);
      return false;
    }
    const klucz = ZalacznikiUtils.kluczRodzica(layerRodzica, featureRodzica);
    console.log("ZAL: dopnijZalacznik — klucz rodzica:", klucz, "| tabela:", opis.warstwa.name, "| pole obce:", opis.poleObce);
    if (klucz === undefined || klucz === null || klucz === "") {
      console.log("ZAL: dopnijZalacznik — PUSTY KLUCZ, przerywam");
      return false;
    }
"""
DZ_ZNACZNIK = 'ZAL: dopnijZalacznik — klucz rodzica'

# 5. wynik create() dziecka
DZ2_KOTWICA = """    zalacznikFeatureModel.currentLayer = opis.warstwa;
    zalacznikFeatureModel.feature = dziecko;
    return zalacznikFeatureModel.create();
"""
DZ2_NOWE = """    zalacznikFeatureModel.currentLayer = opis.warstwa;
    zalacznikFeatureModel.feature = dziecko;
    const wynikDiag = zalacznikFeatureModel.create();
    console.log("ZAL: zapis wiersza zalacznika =", wynikDiag, "| sciezka:", sciezka);
    return wynikDiag;
"""
DZ2_ZNACZNIK = 'ZAL: zapis wiersza zalacznika'

# 6. finishGeometryCapture — czy w ogole tam wchodzimy
FG_KOTWICA = """    const ujecieGeom = cameraSource && cameraSource.photoShotType ? cameraSource.photoShotType : "";
"""
FG_NOWE = """    const ujecieGeom = cameraSource && cameraSource.photoShotType ? cameraSource.photoShotType : "";
    console.log("ZAL: finishGeometryCapture — warstwa:", pendingGeomLayer ? pendingGeomLayer.name : "brak", "| zdjecie:", pendingGeomPhoto);
"""
FG_ZNACZNIK = 'ZAL: finishGeometryCapture'

ZMIANY = [
    (PASEK, MZ_KOTWICA, MZ_NOWE, MZ_ZNACZNIK, 'diag: maZalaczniki'),
    (PASEK, UZ_KOTWICA, UZ_NOWE, UZ_ZNACZNIK, 'diag: ustawZalacznikOczekujacy'),
    (PASEK, PF_KOTWICA, PF_NOWE, PF_ZNACZNIK, 'diag: dopnijZalacznikPoFormularzu'),
    (PASEK, DZ_KOTWICA, DZ_NOWE, DZ_ZNACZNIK, 'diag: dopnijZalacznik — klucz'),
    (PASEK, DZ2_KOTWICA, DZ2_NOWE, DZ2_ZNACZNIK, 'diag: wynik zapisu wiersza'),
    (PASEK, FG_KOTWICA, FG_NOWE, FG_ZNACZNIK, 'diag: finishGeometryCapture'),
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
        return 1

    for sciezka, tresc in plany.items():
        with open(sciezka, 'w', encoding='utf-8') as f:
            f.write(tresc)

    for _plik, _k, _n, _z, opis in ZMIANY:
        print('  %s %s' % ('. już było:' if opis in pominiete else '+ zrobione:',
                           opis))
    print('\nDalej:')
    print('  cmake --build build-sys -j$(nproc)')
    print('  ./build-sys/output/bin/qfield 2>&1 | grep "ZAL:"')
    return 0


if __name__ == '__main__':
    sys.exit(main())
