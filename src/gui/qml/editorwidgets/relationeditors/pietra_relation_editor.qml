import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.qfield.core
import org.qfield.gui
import org.qgis
import Theme

/**
 * Spis gatunkowy pogrupowany po PIĘTRACH — A, B, C, D.
 *
 * Zamiast płaskiej listy kilkudziesięciu gatunków: cztery sekcje z sumą
 * pokrycia w nagłówku, rozwijane tapnięciem. Bez zdjęć — te są
 * w formularzu obiektu, dokąd prowadzi tapnięcie w nazwę.
 *
 * Zamówienie współpracownika Piotra, 03.09.2026: *„hierarchiczny spis
 * gatunków bez zdjęć, pogrupowane według warstw — A na górze z nagłówkiem,
 * B, potem C i D. W nagłówku suma pokrycia."*
 *
 * WYBÓR JAKO EDYTOR RELACJI, nie osobny ekran: relacja `platy_gatunki`
 * już istnieje i działa, `QfReferencingFeatureListModel` daje obiekty
 * powiązane bez pisania zapytań, a `QfRelationEditorBase` przynosi
 * nagłówek, sortowanie i dodawanie. Osobny ekran znaczyłby napisanie
 * tego wszystkiego drugi raz.
 *
 * CZEGO TU NIE MA — świadomie:
 * Przycisków plus-minus do zmiany pokrycia z listy. Zapis do obiektu
 * INNEJ warstwy bez otwierania jego formularza wymaga czasownika, którego
 * w aplikacji nie ma — `QfLayerUtils` ma `canEditFields`, ale nic, co
 * zapisuje wartość. Dokładanie go na ślepo byłoby dziewiątą próbą tego
 * samego rodzaju, co dziś już kilka razy nie wyszło. Najpierw ta część
 * ma się sprawdzić w terenie.
 */
QfRelationEditorBase {
  id: spisPieter

  relationEditorModel: QfReferencingFeatureListModel {
    id: model
    currentRelationId: relationId
    currentNmRelationId: nmRelationId ? nmRelationId : ""
    feature: currentFeature
  }

  //! Nazwy pól w tabeli spisu. Gdyby projekt ich nie miał, widget pokaże
  //! puste sekcje zamiast się wywalić — patrz `wartosc()`.
  readonly property string polePietra: "WARSTWA"
  readonly property string poleGatunku: "GATUNEK"
  readonly property string polePokrycia: "POKRYCIE_PROCENT"
  readonly property string poleZapisu: "ZAPIS_SUROWY"

  readonly property var pietra: [
    { "kod": "A", "nazwa": qsTr("A — drzewa"), "kolor": "#1b5e20" },
    { "kod": "B", "nazwa": qsTr("B — krzewy"), "kolor": "#43a047" },
    { "kod": "C", "nazwa": qsTr("C — runo"), "kolor": "#c0ca33" },
    { "kod": "D", "nazwa": qsTr("D — mszaki"), "kolor": "#8d6e63" }
  ]

  //! Które sekcje są rozwinięte. Domyślnie C, bo tam jest najwięcej.
  //! Domyslnie ZWINIETE — przy 31 gatunkach w placie rozwinieta lista
  //! zasłania cala zakladke, a suma w naglowku wystarcza, zeby
  //! zobaczyc strukture pietrowa.
  property var rozwiniete: ({ "A": false, "B": false, "C": false, "D": false, "?": false })

  //! Przebudowywane przy każdej zmianie modelu.
  //! Plaska lista wierszy do listView: naglowki pieter i gatunki
  //! przemieszane w kolejnosci wyswietlania.
  property var wiersze: []

  showAllItems: true
  showSortButton: false
  maximumVisibleItems: 999

  function wartosc(obiekt, pole) {
    if (!obiekt)
      return undefined;
    try {
      return obiekt.attribute(pole);
    } catch (e) {
      return undefined;
    }
  }

  /**
   * Buduje strukturę: cztery piętra, w każdym lista gatunków i suma.
   *
   * Gatunki bez przypisanego piętra trafiają do osobnej sekcji „bez
   * piętra" — bo ukrycie ich znaczyłoby, że praca ginie z widoku.
   * 03.09 takich wierszy było czternaście.
   */
  function przebuduj() {
    const kubelki = {};
    for (let i = 0; i < pietra.length; i++)
      kubelki[pietra[i].kod] = [];
    kubelki["?"] = [];

    for (let r = 0; r < zbieracz.count; r++) {
      const poz = zbieracz.objectAt(r);
      const f = poz ? poz.obiekt : null;
      if (!f)
        continue;

      let kod = String(wartosc(f, polePietra) || "").trim().toUpperCase();
      if (kod.length > 1)
        kod = kod.charAt(0);
      if (kubelki[kod] === undefined)
        kod = "?";

      const nazwa = wartosc(f, poleGatunku);
      const zapis = wartosc(f, poleZapisu);
      const pokrycie = Number(wartosc(f, polePokrycia)) || 0;

      kubelki[kod].push({
          "wiersz": r,
          "nazwa": (nazwa && String(nazwa).trim() !== "")
                   ? String(nazwa)
                   : ((zapis && String(zapis).trim() !== "")
                      ? String(zapis) + " " + qsTr("(robocza)")
                      : qsTr("bez nazwy")),
          "nazwana": !!(nazwa && String(nazwa).trim() !== ""),
          "pokrycie": pokrycie
        });
    }

    const wynik = [];
    for (let i = 0; i < pietra.length; i++) {
      const p = pietra[i];
      const lista = kubelki[p.kod];
      if (lista.length === 0)
        continue;
      // Od największego pokrycia — dominanty na górze, bo one określają
      // charakter płatu.
      lista.sort((a, b) => b.pokrycie - a.pokrycie);
      let suma = 0;
      for (let j = 0; j < lista.length; j++)
        suma += lista[j].pokrycie;
      wynik.push({
          "kod": p.kod,
          "nazwa": p.nazwa,
          "kolor": p.kolor,
          "suma": suma,
          "gatunki": lista
        });
    }
    if (kubelki["?"].length > 0) {
      let suma = 0;
      for (let j = 0; j < kubelki["?"].length; j++)
        suma += kubelki["?"][j].pokrycie;
      wynik.push({
          "kod": "?",
          "nazwa": qsTr("bez piętra"),
          "kolor": "#9e9e9e",
          "suma": suma,
          "gatunki": kubelki["?"]
        });
    }
    // Splaszczenie: naglowek, potem gatunki jesli sekcja rozwinieta.
    const plaska = [];
    for (let i = 0; i < wynik.length; i++) {
      const s = wynik[i];
      plaska.push({ "typ": "naglowek", "kod": s.kod, "nazwa": s.nazwa,
                    "kolor": s.kolor, "suma": s.suma, "ile": s.gatunki.length,
                    "nazwana": true, "pokrycie": 0, "wiersz": -1 });
      if (!rozwiniete[s.kod])
        continue;
      for (let j = 0; j < s.gatunki.length; j++) {
        const g = s.gatunki[j];
        plaska.push({ "typ": "gatunek", "kod": s.kod, "kolor": s.kolor,
                      "nazwa": g.nazwa, "nazwana": g.nazwana,
                      "pokrycie": g.pokrycie, "wiersz": g.wiersz,
                      "suma": 0, "ile": 0 });
      }
    }
    wiersze = plaska;
  }

  function przelacz(kod) {
    // Kopia obiektu, bo QML nie zauwaza zmiany pola w miejscu.
    const s = Object.assign({}, rozwiniete);
    s[kod] = !s[kod];
    rozwiniete = s;
    przebuduj();
  }

  // Zbieracz zamiast recznego `model.data(idx, 257)`.
  //
  // Numer roli zaszyty w kodzie dziala do pierwszej zmiany w enumie C++ —
  // a dzis juz raz nas to ugryzlo (`AttributeValue` w QfFeatureModel).
  // `Instantiator` czyta po NAZWIE roli, tak jak delegat listy.
  Instantiator {
    id: zbieracz
    model: spisPieter.relationEditorModel
    delegate: QtObject {
      required property var referencingFeature
      readonly property var obiekt: referencingFeature
    }
    onCountChanged: Qt.callLater(spisPieter.przebuduj)
    onObjectAdded: Qt.callLater(spisPieter.przebuduj)
    onObjectRemoved: Qt.callLater(spisPieter.przebuduj)
  }

  Connections {
    target: spisPieter.relationEditorModel
    function onModelUpdated() {
      Qt.callLater(spisPieter.przebuduj);
    }
  }

  Component.onCompleted: przebuduj()

  /**
   * Otwiera formularz obiektu ze spisu — tam jest zdjęcie i pełny zestaw
   * pól. Ta sama droga, którą idzie galeria (`gallery_relation_editor`).
   */
  function otworzWiersz(wiersz) {
    const poz = zbieracz.objectAt(wiersz);
    const f = poz ? poz.obiekt : null;
    if (f)
      showViewFeaturePopup(f);
    else
      displayToast(qsTr("Nie mogę otworzyć tego wpisu"), "warning");
  }

  // listView z bazy jest PUSTY — dziecko ma mu nadac model i delegat.
  // Pierwsza wersja budowala wlasny uklad OBOK niego i teksty nachodzily
  // na siebie: baza rysowala swoje, ja swoje, w tym samym miejscu.
  listView.model: spisPieter.wiersze

  listView.delegate: Item {
    required property var modelData
    width: ListView.view.width
    height: modelData.typ === "naglowek" ? 44 : 38

    Rectangle {
      anchors.fill: parent
      visible: modelData.typ === "naglowek"
      color: QfTheme.controlBackgroundColor

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 5
        color: modelData.kolor
      }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        spacing: 8
        Text {
          text: spisPieter.rozwiniete[modelData.kod] ? "\u25BE" : "\u25B8"
          color: QfTheme.mainTextColor
          font.pointSize: QfTheme.tipFont.pointSize
        }
        Text {
          Layout.fillWidth: true
          text: modelData.nazwa
          color: QfTheme.mainTextColor
          font.bold: true
          font.pointSize: QfTheme.tipFont.pointSize
          elide: Text.ElideRight
        }
        Text {
          text: qsTr("%1 gat.").arg(modelData.ile)
          color: QfTheme.secondaryTextColor
          font.pointSize: QfTheme.tinyFont.pointSize
        }
        Text {
          text: Math.round(modelData.suma) + "%"
          color: modelData.kolor
          font.bold: true
          font.pointSize: QfTheme.tipFont.pointSize
        }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: spisPieter.przelacz(modelData.kod)
      }
    }

    Item {
      anchors.fill: parent
      visible: modelData.typ === "gatunek"
      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 26
        anchors.rightMargin: 12
        spacing: 8
        Text {
          Layout.fillWidth: true
          text: modelData.nazwa
          font.italic: !modelData.nazwana
          color: modelData.nazwana ? QfTheme.mainTextColor : QfTheme.secondaryTextColor
          font.pointSize: QfTheme.tipFont.pointSize
          elide: Text.ElideRight
        }
        Text {
          text: modelData.pokrycie > 0 ? modelData.pokrycie + "%" : "\u2014"
          color: QfTheme.secondaryTextColor
          font.pointSize: QfTheme.tipFont.pointSize
        }
      }
      Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 26
        height: 1
        color: QfTheme.controlBorderColor
        opacity: 0.35
      }
      MouseArea {
        anchors.fill: parent
        onClicked: spisPieter.otworzWiersz(modelData.wiersz)
      }
    }
  }
}
