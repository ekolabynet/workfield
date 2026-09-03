# -*- coding: utf-8 -*-
"""
Łatka: ikona aparatu w nagłówku formularza atrybutów.

Jedno tapnięcie robi zdjęcie i zapisuje je jako załącznik OBECNIE otwartego
obiektu — bez wchodzenia w zakładkę „Załączniki". Ikona pokazuje się wyłącznie
wtedy, gdy warstwa ma tabelę załączników i obiekt jest już zapisany.

WYMAGA zaktualizowanych plików src/core/utils/zalacznikiutils.{h,cpp}
(z sygnałem zazadanoZdjecia) — wgraj je przed uruchomieniem łatki.

Dlaczego przez sygnał, a nie wprost: nagłówek formularza (NavigationBar.qml)
żyje w innym komponencie QML niż pasek szybkiego przechwytu i nie ma jak go
zawołać po identyfikatorze. ZalacznikiUtils jest singletonem, więc widzą go
obie strony — nagłówek zgłasza żądanie, pasek je obsługuje swoim aparatem.
Dzięki temu zdjęcie z ikony przechodzi dokładnie tą samą drogą co zdjęcie
z kafla: te same nazwy plików, ten sam zapis, ten sam zapas awaryjny.

Zmiany:
  1. src/gui/qml/NavigationBar.qml — przycisk aparatu obok pisaczka
     (+ uwzględnienie go w wyliczaniu marginesu tytułu).
  2. src/app/qml/QfQuickCaptureBar.qml — nasłuch żądania, tryb „zdjęcie do
     istniejącego obiektu" i obsługa w openPendingForm.

Długie przytrzymanie NIE jest tu używane — w tym interfejsie znaczy już
„seria" (wierzchołki, a docelowo ujęcia) i trzecie znaczenie tego samego
gestu byłoby proszeniem się o pomyłkę w rękawicach.

URUCHOMIENIE (z katalogu repozytorium):
    python3 skrypty/latka_zalaczniki_naglowek.py

Idempotentna.
"""
import os
import sys

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAGLOWEK = 'src/gui/qml/NavigationBar.qml'
PASEK = 'src/app/qml/QfQuickCaptureBar.qml'

# ----------------------------------------------------- 1. przycisk w naglowku
PRZYCISK_KOTWICA = """  QfToolButton {
    id: digitizeToggle
"""

PRZYCISK_NOWE = """  QfToolButton {
    id: zalacznikButton

    // WorkField: aparat zalacznikow. Widoczny tylko dla warstw z tabela
    // ZAL_<warstwa> i tylko przy obiekcie juz zapisanym — przed zapisem nie
    // ma klucza, do ktorego mozna by zalacznik przypiac.
    property bool warstwaZZalacznikami: {
      if (!selection || !selection.focusedLayer)
        return false;
      return ZalacznikiUtils.relacjaZalacznikow(selection.focusedLayer).istnieje === true;
    }

    visible: toolBar.state === "Navigation" && warstwaZZalacznikami && selection && selection.focusedFeature && selection.focusedFeature.id >= 0
    round: true

    anchors.right: digitizeToggle.left
    anchors.top: parent.top
    anchors.topMargin: toolBar.topMargin + 5

    iconSource: Theme.getThemeVectorIcon("ic_camera_photo_black_24dp")
    iconColor: Theme.mainOverlayColor
    bgcolor: "transparent"

    width: visible ? Theme.toolButtonSize : 0
    height: Theme.toolButtonSize

    onClicked: {
      ZalacznikiUtils.zazadajZdjecia(selection.focusedLayer, selection.focusedFeature);
    }
  }

  QfToolButton {
    id: digitizeToggle
"""

PRZYCISK_ZNACZNIK = 'id: zalacznikButton'

# --- marginesy tytulu musza znac nowy przycisk, inaczej tytul ucieka z osi
MARGINES_KOTWICA = """(digitizeToggle.visible ? digitizeToggle.width : 0)"""
MARGINES_NOWE = """(digitizeToggle.visible ? digitizeToggle.width : 0) + (zalacznikButton.visible ? zalacznikButton.width : 0)"""
MARGINES_ZNACZNIK = 'zalacznikButton.visible ? zalacznikButton.width'

# --------------------------------------------------- 2. obsluga w pasku
OBSLUGA_KOTWICA = """  //! Czy warstwa ma tabele zalacznikow (relacja + pole ExternalResource)?
"""

OBSLUGA_NOWE = """  // WorkField: zdjecie robione dla obiektu, ktory JUZ ISTNIEJE — z ikony
  // aparatu w naglowku formularza. {layer, feature} albo null.
  property var zalacznikDoObiektu: null

  Connections {
    target: ZalacznikiUtils
    ignoreUnknownSignals: true

    function onZazadanoZdjecia(warstwa, obiekt) {
      quickCaptureBar.zrobZdjecieDoObiektu(warstwa, obiekt);
    }
  }

  //! Uruchamia aparat, zeby dopiac zdjecie do istniejacego obiektu
  function zrobZdjecieDoObiektu(layer, feature) {
    if (!layer || !feature) {
      return;
    }
    zalacznikDoObiektu = {
      "layer": layer,
      "feature": feature
    };
    openCameraFor(layer);
  }

  //! Czy warstwa ma tabele zalacznikow (relacja + pole ExternalResource)?
"""

OBSLUGA_ZNACZNIK = 'function zrobZdjecieDoObiektu('

# --- galaz w openPendingForm, PRZED cala reszta przeplywow
GALAZ_KOTWICA = """  function openPendingForm(photoPath) {
    uzupelnijMetadane(photoPath ? qgisProject.homePath + "/" + photoPath : "");
"""

GALAZ_NOWE = """  function openPendingForm(photoPath) {
    uzupelnijMetadane(photoPath ? qgisProject.homePath + "/" + photoPath : "");
    // WorkField: zdjecie z ikony w naglowku — obiekt juz jest, wiec nie ma
    // czego tworzyc; dopinamy zalacznik i konczymy. Ta galaz musi byc PIERWSZA,
    // zeby nie wpasc w zaden z przeplywow tworzacych nowe obiekty.
    if (zalacznikDoObiektu) {
      const cel = zalacznikDoObiektu;
      zalacznikDoObiektu = null;
      if (!photoPath || photoPath === "") {
        displayToast(qsTr("Anulowano — bez załącznika"));
        return;
      }
      const ujecieIkona = cameraSource && cameraSource.photoShotType ? cameraSource.photoShotType : "";
      if (dopnijZalacznik(cel.layer, cel.feature, photoPath, ujecieIkona, "foto")) {
        haptyka(40);
        displayToast(qsTr("Załącznik dodany do: %1").arg(cel.layer.name));
      } else {
        displayToast(qsTr("UWAGA: zdjęcie bez dowiązania — plik jest w DCIM: %1").arg(photoPath), "error");
      }
      cameraSource = null;
      return;
    }
"""

GALAZ_ZNACZNIK = 'zdjecie z ikony w naglowku'

ZMIANY = [
    (NAGLOWEK, PRZYCISK_KOTWICA, PRZYCISK_NOWE, PRZYCISK_ZNACZNIK,
     'nagłówek: przycisk aparatu załączników'),
    (NAGLOWEK, MARGINES_KOTWICA, MARGINES_NOWE, MARGINES_ZNACZNIK,
     'nagłówek: margines tytułu uwzględnia nowy przycisk'),
    (PASEK, OBSLUGA_KOTWICA, OBSLUGA_NOWE, OBSLUGA_ZNACZNIK,
     'pasek: nasłuch żądania i tryb zdjęcia do istniejącego obiektu'),
    (PASEK, GALAZ_KOTWICA, GALAZ_NOWE, GALAZ_ZNACZNIK,
     'pasek: gałąź dopięcia w openPendingForm'),
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
    print('\nDalej: cmake --build build-sys -j$(nproc)')
    print('W logu muszą pojawić się zalacznikiutils.cpp oraz '
          '"Running rcc for resource gui_qml" i "app_qml".')
    return 0


if __name__ == '__main__':
    sys.exit(main())
