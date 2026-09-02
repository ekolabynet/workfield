#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — Pl@ntNet W FORMULARZU: rozpoznanie ze zdjecia wprost do pola.

==========================================================================
PO CO
==========================================================================
Piotr, 01.09.2026, z terenu:

  „Klikamy G, robimy zdjecie, otwiera sie formularz gdzie mozna wpisac
   nazwe, warstwe i pokrycie. Gdybysmy tu mieli mozliwosc od razu
   oznaczenia gatunku z Pl@ntNet, mozna by bylo umiescic nazwe w polu."

==========================================================================
DLACZEGO TRZY PLIKI, A NIE JEDEN
==========================================================================
Pierwsze podejscie mialo przycisk zapisujacy wprost z widgetu. **Nie da sie:**
widget ma tylko `valueChangeRequested(value, isNull)`, ktory zmienia WLASNA
wartosc. Do cudzego pola nie siegnie.

Sprawdzone przed napisaniem — inaczej przycisk dzialalby, lista by sie
pokazala, a pole zostaloby puste. Falszywa obecnosc w czystej postaci.

Aplikacja ma na to gotowy wzorzec: widget **zglasza** zadanie, formularz
je **wykonuje**. Tak dzialaja `requestGeometry` i `requestBarcode`
(`QfEditorWidgetBase.qml`, obsluga w `QfFeatureForm.qml:894`).

Stad podzial:

  1. **C++** — czasownik `ustawAtrybut(nazwa, wartosc)` w `QfFeatureModel`.
     Model MA juz role `AttributeName` i `AttributeValue` (qffeaturemodel.h:71),
     wiec dane sa dostepne — brakowalo tylko drogi z QML. Bez tego trzeba by
     zgadywac numery rol (`Qt.UserRole + 2`), co dziala do pierwszej zmiany
     w enumie.
  2. **Widget zdjecia** — przycisk, ktory zglasza `requestSpeciesName`.
  3. **Formularz** — lapie zgloszenie, wola Pl@ntNet, pokazuje liste,
     zapisuje wybrana nazwe.

==========================================================================
TRZY DECYZJE
==========================================================================
**Przycisk przy ZDJECIU.** Widget ma juz rzad ikon (aparat, wideo, mikrofon,
plik); dochodzi piata. Zdjecie jest tuz obok, wiec nie ma watpliwosci, co
rozpoznajemy.

**LISTA kandydatow, nie automat.** Pl@ntNet zwraca szesc z procentami; przy
trawach pierwszy bywa nietrafny. **Wpisana bez sprawdzenia zla nazwa jest
gorsza niz brak nazwy** — wyglada na oznaczenie i nikt jej nie zweryfikuje.
Procent stoi PRZED nazwa, wiec od razu widac, czy to 80% czy 20%.

**Pole wybierane przy pierwszym uzyciu, zapamietane W APLIKACJI.**
Nie w konfiguracji warstwy, bo `projekt.qgs` przy kazdym wydaniu jedzie
z biura i **nadpisalby wybor zrobiony w terenie**. Klucz zawiera nazwe
warstwy, wiec `gatunki` i `zdjecia_fito` moga miec rozne pola.

Uruchom w korzeniu repo:  python3 zastosuj_plantnet_formularz.py
Idempotentna. Kopie: <plik>.przed_plantnet
"""
import os
import shutil
import sys

H = "src/core/qffeaturemodel.h"
C = "src/core/qffeaturemodel.cpp"
BASE = "src/gui/qml/editorwidgets/QfEditorWidgetBase.qml"
ER = "src/gui/qml/editorwidgets/QfEditorWidgetExternalResource.qml"
FF = "src/gui/qml/QfFeatureForm.qml"

# ------------------------------------------------------------- 1. C++ naglowek

H_KOTWICA = "    Q_INVOKABLE bool updateAttributesFromFeature( const QgsFeature &feature );"

H_NOWE = '''    Q_INVOKABLE bool updateAttributesFromFeature( const QgsFeature &feature );

    /**
     * Ustawia wartość pola po NAZWIE.
     *
     * Model ma role `AttributeName` i `AttributeValue`, więc dane są
     * dostępne — brakowało tylko drogi z QML. Bez tego trzeba by zgadywać
     * numery ról (`Qt.UserRole + 2`), co działa do pierwszej zmiany w enumie.
     *
     * Potrzebne, bo widget edycyjny umie zmienić tylko WŁASNĄ wartość
     * (`valueChangeRequested`), a rozpoznanie gatunku ze zdjęcia musi trafić
     * do innego pola niż to, przy którym stoi przycisk.
     *
     * \\returns false gdy pola nie ma — wołający MA to sprawdzić i powiedzieć
     *          człowiekowi, zamiast milczeć.
     */
    Q_INVOKABLE bool ustawAtrybut( const QString &nazwa, const QVariant &wartosc );'''

# ---------------------------------------------------------- 2. C++ implementacja

C_KOTWICA = "void QfFeatureModel::resetAttributes( bool partialReset )"

C_NOWE = r'''bool QfFeatureModel::ustawAtrybut( const QString &nazwa, const QVariant &wartosc )
{
  if ( !mLayer )
    return false;

  const int indeks = mLayer->fields().lookupField( nazwa );
  if ( indeks < 0 )
    return false;

  // Przez setData, nie przez mFeature.setAttribute — model musi wiedzieć
  // o zmianie, żeby formularz ją pokazał i żeby trafiła do zapisu.
  const QModelIndex idx = index( indeks, 0 );
  if ( !idx.isValid() )
    return false;

  return setData( idx, wartosc, AttributeValue );
}

'''

# ------------------------------------------------------ 3. sygnal w bazie widgetow

BASE_KOTWICA = "  signal requestGeometry(var item, var layer)"

BASE_NOWE = '''  signal requestGeometry(var item, var layer)

  /**
   * Widget prosi o rozpoznanie gatunku ze zdjęcia.
   *
   * Widget nie może zapisać do cudzego pola — ma tylko
   * `valueChangeRequested` na własną wartość. Więc zgłasza zadanie,
   * a formularz je wykonuje: pyta Pl@ntNet, pokazuje kandydatów i wpisuje
   * wybraną nazwę do pola wskazanego przez człowieka.
   *
   * Ten sam wzorzec co `requestGeometry` i `requestBarcode`.
   */
  signal requestSpeciesName(string sciezkaZdjecia)'''

# ----------------------------------------------------------- 4. przycisk

ER_KOTWICA = """  QfToolButton {
    id: cameraButton"""

ER_NOWE = '''  // WorkField 01.09.2026 — rozpoznanie gatunku ze zdjęcia.
  //
  // Sam przycisk: widget nie umie zapisać do cudzego pola, więc tylko
  // zgłasza zadanie. Resztę robi formularz (QfFeatureForm).
  QfToolButton {
    id: przyciskPlantNet

    // Bez zdjęcia nie ma czego rozpoznawać, a przycisk prowadzący donikąd
    // to trzeci stan — więc go wtedy nie ma.
    readonly property bool maZdjecie: !isNull && value !== undefined
                                      && String(value) !== ""

    width: visible ? QfTheme.toolButtonSize : 0
    height: QfTheme.toolButtonSize
    visible: documentViewer == QfEditorWidgetExternalResource.DocumentImage
             && isEnabled && maZdjecie
    anchors.right: cameraButton.left
    anchors.top: parent.top
    iconSource: QfTheme.getThemeVectorIcon("ic_baseline-search_black_24dp")
    iconColor: QfTheme.mainTextColor
    bgcolor: "transparent"

    onClicked: requestSpeciesName(prefixToRelativePath + value)
  }

  QfToolButton {
    id: cameraButton'''

# --------------------------------------------- 5. obsluga w formularzu

FF_KOTWICA = """            function onRequestBarcode(item) {
              form.codeReader.barcodeRequestedItem = item;
              form.codeReader.open();
            }"""

FF_NOWE = '''            function onRequestBarcode(item) {
              form.codeReader.barcodeRequestedItem = item;
              form.codeReader.open();
            }

            // WorkField 01.09.2026 — rozpoznanie gatunku ze zdjęcia.
            // Widget zgłasza, formularz wykonuje: tylko on ma dostęp do
            // wszystkich pól obiektu.
            function onRequestSpeciesName(sciezkaZdjecia) {
              form.rozpoznajGatunek(sciezkaZdjecia);
            }'''

FF_MECHANIZM_KOTWICA = "  function requestCancel() {"

FF_MECHANIZM = '''  // ------------------------------------------------ rozpoznanie gatunku
  //
  // Silnik (QfPlantNet) wydzielony z galerii, żeby nie pisać go drugi raz.
  // Tutaj: uruchomienie, lista kandydatów i zapis do pola.

  QfPlantNet {
    id: silnikGatunku

    onGotowe: kandydaci => {
      listaGatunkow.wyniki = kandydaci;
      listaGatunkow.open();
    }
    onBlad: tekst => displayToast(tekst, "warning")
  }

  function rozpoznajGatunek(sciezka) {
    displayToast(qsTr("Rozpoznaję gatunek…"));
    silnikGatunku.identyfikuj(sciezka);
  }

  //! Klucz ustawienia z nazwą warstwy — `gatunki` i `zdjecia_fito` mogą
  //! mieć różne pola docelowe.
  function kluczPolaGatunku() {
    const w = form.model && form.model.featureModel && form.model.featureModel.currentLayer
            ? form.model.featureModel.currentLayer.name : "?";
    return "WorkFieldPlantNet/poleGatunku/" + w;
  }

  function wpiszGatunek(lacina) {
    const m = form.model ? form.model.featureModel : null;
    if (!m || m.ustawAtrybut === undefined) {
      displayToast(qsTr("Nie mogę zapisać nazwy — brak dostępu do pól obiektu"), "warning");
      return;
    }

    const zapamietane = String(settings.value(kluczPolaGatunku(), ""));
    if (zapamietane !== "") {
      if (m.ustawAtrybut(zapamietane, lacina)) {
        displayToast(qsTr("%1 → %2").arg(lacina).arg(zapamietane));
        return;
      }
      // Pole zniknęło ze schematu — pytamy od nowa, zamiast milczeć.
      settings.setValue(kluczPolaGatunku(), "");
    }

    // Pola do wyboru: tekstowe, bez systemowych i identyfikatorów.
    const kandydaci = [];
    const w = m.currentLayer;
    if (w) {
      const f = w.fields;
      for (let i = 0; i < f.count; i++) {
        const n = f.at(i).name;
        if (n === "fid" || n === "geom" || n.startsWith("ID_"))
          continue;
        kandydaci.push(n);
      }
    }
    if (kandydaci.length === 0) {
      displayToast(qsTr("Warstwa nie ma pola, do którego można wpisać nazwę"), "warning");
      return;
    }
    wyborPolaGatunku.lacina = lacina;
    wyborPolaGatunku.pola = kandydaci;
    wyborPolaGatunku.open();
  }

  // Lista kandydatów. NIE wpisujemy najlepszego automatycznie: przy trawach
  // pierwszy bywa nietrafny, a nazwa wpisana bez sprawdzenia wygląda jak
  // oznaczenie i nikt jej już nie zweryfikuje.
  QfDialog {
    id: listaGatunkow

    property var wyniki: []

    parent: mainWindow.contentItem
    z: 10000
    modal: true
    title: qsTr("Co to za gatunek?")
    standardButtons: Dialog.Cancel
    width: Math.min(mainWindow.width - 40, 460)

    background: Rectangle {
      color: QfTheme.mainBackgroundColor
      radius: 6
      border.width: 1
      border.color: QfTheme.controlBorderColor
    }

    contentItem: ListView {
      implicitHeight: Math.min(contentHeight, mainWindow.height * 0.55)
      clip: true
      model: listaGatunkow.wyniki

      delegate: ItemDelegate {
        required property var modelData
        width: ListView.view.width
        height: 58

        contentItem: Column {
          spacing: 2
          Row {
            spacing: 8
            Text {
              // Procent PRZED nazwą: od razu widać, czy to pewne
              // rozpoznanie, czy zgadywanie.
              text: modelData.score + "%"
              font.bold: true
              font.pointSize: QfTheme.tipFont.pointSize
              color: modelData.score >= 50 ? QfTheme.mainColor
                     : modelData.score >= 20 ? QfTheme.warningColor
                                             : QfTheme.secondaryTextColor
            }
            Text {
              text: modelData.lacina
              font.italic: true
              font.pointSize: QfTheme.tipFont.pointSize
              color: QfTheme.mainTextColor
            }
          }
          Text {
            text: modelData.ludowa
            visible: text !== ""
            font.pointSize: QfTheme.tinyFont.pointSize
            color: QfTheme.secondaryTextColor
          }
        }

        onClicked: {
          listaGatunkow.close();
          form.wpiszGatunek(modelData.lacina);
        }
      }
    }
  }

  // Pytamy RAZ na warstwę. Ustawienie zapamiętane W APLIKACJI, nie
  // w projekcie — bo projekt przy każdym wydaniu jedzie z biura
  // i nadpisałby wybór zrobiony w terenie.
  QfDialog {
    id: wyborPolaGatunku

    property string lacina: ""
    property var pola: []

    parent: mainWindow.contentItem
    z: 10000
    modal: true
    title: qsTr("Do którego pola wpisać nazwę?")
    standardButtons: Dialog.Cancel
    width: Math.min(mainWindow.width - 40, 420)

    background: Rectangle {
      color: QfTheme.mainBackgroundColor
      radius: 6
      border.width: 1
      border.color: QfTheme.controlBorderColor
    }

    contentItem: ListView {
      implicitHeight: Math.min(contentHeight, mainWindow.height * 0.5)
      clip: true
      model: wyborPolaGatunku.pola

      delegate: ItemDelegate {
        required property var modelData
        width: ListView.view.width
        height: 48
        contentItem: Text {
          text: modelData
          color: QfTheme.mainTextColor
          font.pointSize: QfTheme.tipFont.pointSize
          verticalAlignment: Text.AlignVCenter
        }
        onClicked: {
          settings.setValue(form.kluczPolaGatunku(), modelData);
          wyborPolaGatunku.close();
          form.wpiszGatunek(wyborPolaGatunku.lacina);
        }
      }
    }
  }

  function requestCancel() {'''


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def zapisz(p, t, opis):
    kopia = p + ".przed_plantnet"
    if not os.path.exists(kopia):
        shutil.copy2(p, kopia)
    open(p, "w", encoding="utf-8").write(t)
    print("   %-30s %s" % (opis, os.path.basename(p)))


def main():
    h, c = czytaj(H), czytaj(C)
    b, e, f = czytaj(BASE), czytaj(ER), czytaj(FF)

    stan = ["ustawAtrybut" in h, "ustawAtrybut" in c,
            "requestSpeciesName" in b, "przyciskPlantNet" in e,
            "silnikGatunku" in f]
    if all(stan):
        print("Latka juz jest — nic do zrobienia.")
        return
    if any(stan):
        sys.exit("STOP: latka polowiczna %s. Przywroc kopie .przed_plantnet." % stan)

    kotwice = [("naglowek C++", h, H_KOTWICA, H),
               ("implementacja C++", c, C_KOTWICA, C),
               ("sygnal w bazie", b, BASE_KOTWICA, BASE),
               ("przycisk", e, ER_KOTWICA, ER),
               ("obsluga sygnalu", f, FF_KOTWICA, FF),
               ("mechanizm", f, FF_MECHANIZM_KOTWICA, FF)]
    for nazwa, tresc, kot, plik in kotwice:
        n = tresc.count(kot)
        if n != 1:
            sys.exit("STOP: kotwica '%s' w %s wystepuje %d razy, oczekiwano 1"
                     % (nazwa, os.path.basename(plik), n))

    print("Kotwice policzone (6/6), nakladam:")

    h = h.replace(H_KOTWICA, H_NOWE, 1)
    c = c.replace(C_KOTWICA, C_NOWE + C_KOTWICA, 1)
    b = b.replace(BASE_KOTWICA, BASE_NOWE, 1)
    e = e.replace(ER_KOTWICA, ER_NOWE, 1)
    f = f.replace(FF_KOTWICA, FF_NOWE, 1)
    f = f.replace(FF_MECHANIZM_KOTWICA, FF_MECHANIZM, 1)

    zapisz(H, h, "czasownik ustawAtrybut")
    zapisz(C, c, "implementacja")
    zapisz(BASE, b, "sygnal requestSpeciesName")
    zapisz(ER, e, "przycisk przy zdjeciu")
    zapisz(FF, f, "silnik, listy, zapis")

    print("""
DO SPRAWDZENIA — ikona:
  ls images/themes/*/ | grep -iE "search|lupa|szukaj"

Uzylem `ic_baseline-search_black_24dp`. Jesli motyw jej nie ma, przycisk
bedzie PUSTY ale klikalny — podmien nazwe w QfEditorWidgetExternalResource.

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head -5

Sprawdzian:
  1. pasek G -> zdjecie -> formularz gatunku
  2. przy zdjeciu lupa -> „Rozpoznaje gatunek..."
  3. lista szesciu z procentami
  4. PIERWSZY raz: pytanie o pole docelowe
  5. wybor -> nazwa w polu, komunikat „Nazwa -> POLE"
  6. kolejne rozpoznania juz nie pytaja o pole
""")


if __name__ == "__main__":
    main()
