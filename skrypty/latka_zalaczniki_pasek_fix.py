# -*- coding: utf-8 -*-
"""
Poprawki do łatki 2b-1 (latka_zalaczniki_pasek.py) — po przeglądzie kodu.

Nakładaj DOPIERO po tamtej łatce; ta zakłada, że tamte zmiany już są w plikach.

Naprawia cztery rzeczy, z których pierwsza jest regresją, a druga i trzecia
psują zapas awaryjny dokładnie wtedy, gdy jest potrzebny:

  1. TRYB DOKŁADNY GUBIŁ ZDJĘCIE. Warunek pomijania pola "foto" patrzył tylko
     na to, czy warstwa ma tabelę załączników — a w trybie dokładnym obiekt
     zapisuje formularz, nie pasek, więc załącznika nikt nie dopinał. Ścieżka
     nie trafiała ani do pola, ani do tabeli: zdjęcie zostawało w DCIM bez
     dowiązania i bez ostrzeżenia. Teraz pole "foto" jest pomijane wyłącznie
     wtedy, gdy pasek naprawdę zapisze załącznik (tryb szybki albo kolejka
     odroczeń). Tryb dokładny wraca do zachowania sprzed łatki.

  2. ZAPAS AWARYJNY MODYFIKOWAŁ KOPIĘ. `silentFeatureModel.feature` zwraca
     kopię obiektu, więc setAttribute na niej mógł nie dotrzeć do modelu i
     save() zapisywałby niezmieniony obiekt — cicho, z komunikatem o sukcesie.
     Teraz wzorzec jak w reszcie pliku: odczytaj do zmiennej, zmień, przypisz
     z powrotem, dopiero potem zapisz.

  3. KOMUNIKAT KŁAMAŁ, gdy warstwa nie ma pola "foto". Mówił, że ścieżka jest
     w polu, którego nie ma. Teraz są trzy różne komunikaty: załącznik zapisany,
     zapisano awaryjnie do pola "foto", zdjęcie zostało wyłącznie w DCIM.

  4. dopnijZalacznik() MELDOWAŁ SUKCES przy pustym kluczu. `if (!dziecko)` nie
     działa dla obiektu wartościowego — trzeba sprawdzać `dziecko.valid`, a
     wyniki setAttribute dla klucza obcego i ścieżki muszą być sprawdzone,
     inaczej powstaje wiersz-sierota bez klucza.

URUCHOMIENIE (z katalogu repozytorium):
    python3 skrypty/latka_zalaczniki_pasek_fix.py

Idempotentna. Kotwica musi trafić dokładnie raz — inaczej STOP.
"""
import os
import sys

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASEK = 'src/app/qml/QfQuickCaptureBar.qml'

# ------------------------------------------------ 1. tryb dokladny nie gubi
DEKL_KOTWICA = """    const zalacznikiTutaj = maZalaczniki(pendingLayer);
    const ujecieTeraz = cameraSource && cameraSource.photoShotType ? cameraSource.photoShotType : "";
    if (photoPath && photoPath !== "" && !zalacznikiTutaj && fieldNames.indexOf("foto") >= 0) {
"""

DEKL_NOWE = """    const zalacznikiTutaj = maZalaczniki(pendingLayer);
    const ujecieTeraz = cameraSource && cameraSource.photoShotType ? cameraSource.photoShotType : "";
    // Pole "foto" pomijamy TYLKO wtedy, gdy pasek sam zapisze obiekt i dopnie
    // zalacznik — czyli w trybie szybkim albo przez kolejke odroczen.
    // W trybie dokladnym obiekt zapisuje formularz, wiec zalacznika nie ma kto
    // dopiac; tam scieżka musi isc po staremu do pola, zeby zdjecie nie zostalo
    // w DCIM bez zadnego dowiazania.
    const zapiszemyZalacznik = zalacznikiTutaj && (odroczenieFlow || stateMachine.state === "digitize" || qfieldSettings.fastMode);
    if (photoPath && photoPath !== "" && !zapiszemyZalacznik && fieldNames.indexOf("foto") >= 0) {
"""

DEKL_ZNACZNIK = 'const zapiszemyZalacznik ='

# --- kolejka odroczen korzysta z nowego warunku
KOLEJKA_KOTWICA = """          "zalacznik": zalacznikiTutaj && photoPath && photoPath !== "" ? {
"""
KOLEJKA_NOWE = """          "zalacznik": zapiszemyZalacznik && photoPath && photoPath !== "" ? {
"""
KOLEJKA_ZNACZNIK = '"zalacznik": zapiszemyZalacznik'

# ------------------------------------- 2+3. zapas awaryjny i uczciwe komunikaty
ZAPAS_KOTWICA = """      if (zalacznikiTutaj && photoPath && photoPath !== "") {
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
"""

ZAPAS_NOWE = """      let zapasDoFoto = false;
        if (zapiszemyZalacznik && photoPath && photoPath !== "") {
          zalacznikOk = dopnijZalacznik(warstwaZapisu, silentFeatureModel.feature, photoPath, ujecieTeraz, "foto");
          if (!zalacznikOk) {
            // Zapas awaryjny: scieżka wraca do starego pola, zeby zdjecie z
            // terenu nie zostalo bez dowiazania. Obiekt czytamy do zmiennej i
            // przypisujemy z powrotem — wlasciwosc feature zwraca KOPIE, wiec
            // zmiana na niej sama z siebie nie dotarlaby do modelu.
            let ratunek = silentFeatureModel.feature;
            const nazwyZapisu = ratunek.fields.names;
            if (nazwyZapisu.indexOf("foto") >= 0) {
              ratunek.setAttribute("foto", photoPath);
              if (ujecieTeraz !== "" && nazwyZapisu.indexOf("ujecie") >= 0) {
                ratunek.setAttribute("ujecie", ujecieTeraz);
              }
              silentFeatureModel.feature = ratunek;
              zapasDoFoto = silentFeatureModel.save();
            }
          }
        }
        if (zalacznikOk) {
          displayToast(qsTr("Zapisano: %1 (%2. w serii)").arg(pendingLayer.name).arg(seriesCount));
        } else if (zapasDoFoto) {
          displayToast(qsTr("Obiekt zapisany, załącznik NIE — ścieżka poszła awaryjnie do pola foto"), "warning");
        } else {
          displayToast(qsTr("UWAGA: zdjęcie bez dowiązania — plik jest w DCIM: %1").arg(photoPath), "error");
        }
"""

ZAPAS_ZNACZNIK = 'let zapasDoFoto = false;'

# ------------------------------------------- 4. szczelne kontrole w dopnijZalacznik
DOPNIJ_KOTWICA = """    const dziecko = FeatureUtils.createFeature(opis.warstwa);
    if (!dziecko) {
      return false;
    }
    const nazwy = dziecko.fields.names;
    dziecko.setAttribute(opis.poleObce, klucz);
    dziecko.setAttribute(opis.poleSciezki, sciezka);
"""

DOPNIJ_NOWE = """    const dziecko = FeatureUtils.createFeature(opis.warstwa);
    // obiekt jest typem wartosciowym — "!dziecko" nigdy nie bylby prawda
    if (!dziecko || dziecko.valid !== true) {
      return false;
    }
    const nazwy = dziecko.fields.names;
    // bez klucza obcego i bez sciezki wiersz jest smieciem — lepiej zglosic
    // porazke i pozwolic zadzialac zapasowi awaryjnemu
    if (!dziecko.setAttribute(opis.poleObce, klucz)) {
      return false;
    }
    if (!dziecko.setAttribute(opis.poleSciezki, sciezka)) {
      return false;
    }
"""

DOPNIJ_ZNACZNIK = 'dziecko.valid !== true'

ZMIANY = [
    (PASEK, DEKL_KOTWICA, DEKL_NOWE, DEKL_ZNACZNIK,
     'tryb dokładny nie gubi zdjęcia'),
    (PASEK, KOLEJKA_KOTWICA, KOLEJKA_NOWE, KOLEJKA_ZNACZNIK,
     'kolejka odroczeń używa nowego warunku'),
    (PASEK, ZAPAS_KOTWICA, ZAPAS_NOWE, ZAPAS_ZNACZNIK,
     'zapas awaryjny zapisuje przez model + uczciwe komunikaty'),
    (PASEK, DOPNIJ_KOTWICA, DOPNIJ_NOWE, DOPNIJ_ZNACZNIK,
     'dopnijZalacznik: szczelne kontrole'),
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
        print('\nCzy na pewno nałożona jest wcześniejsza łatka '
              '(latka_zalaczniki_pasek.py)?')
        return 1

    for sciezka, tresc in plany.items():
        with open(sciezka, 'w', encoding='utf-8') as f:
            f.write(tresc)

    for _plik, _k, _n, _z, opis in ZMIANY:
        print('  %s %s' % ('. już było:' if opis in pominiete else '+ zrobione:',
                           opis))
    print('\nDalej: cmake --build build-sys -j$(nproc)')
    print('W logu musi pojawić się "Running rcc for resource app_qml".')
    return 0


if __name__ == '__main__':
    sys.exit(main())
