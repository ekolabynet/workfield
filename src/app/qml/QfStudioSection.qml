import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.qfield
import Theme

/**
 * WFG Studio — zakładka "Studio" szuflady (etap 1, tylko desktop).
 *
 * Rusztowanie świadomie płaskie: lista projektów z drzewa + czasowniki +
 * zapis operacji. Radykalne porządkowanie menu przyjdzie, gdy czasowniki
 * pomieszkają w ręce; wtedy będzie przestawianiem klocków, nie przebudową.
 * Ten sam plik ma kiedyś trafić — toutes proportions gardées — na telefon.
 */
ColumnLayout {
  id: studio
  spacing: 4

  property var wybrany: null

  Settings {
    id: ustawieniaStudia
    category: "WFGStudio"
    // desktop ma szeroki dostęp do dysku, więc korzeń jest ustawialny;
    // domyślnie ~/WorkField — decyzja projektowa z 2026-08-07
    property string korzenProjektow: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/WorkField"
    property string telefonKarta: "/storage/3263-3061/WorkField/data/"
    // drzewo projektów: zwinięte gałęzie (JSON: klucz bramy -> true)
    property string zwinieteJson: '{"archiwum":true,"inne":true}'
  }

  ProcesyStudio {
    id: procesy
    onLinia: tekst => zapis.dopisz(tekst)
    onZakonczono: kod => {
      zapis.dopisz(kod === 0 ? qsTr("✓ Gotowe") : qsTr("✗ Nie udało się (kod %1) — zapis wyżej").arg(kod));
      studio.przeladuj();
    }
  }

  FolderDialog {
    id: wyborKorzenia
    title: qsTr("Katalog z projektami")
    onAccepted: {
      ustawieniaStudia.korzenProjektow = selectedFolder.toString().replace("file://", "");
      studio.przeladuj();
    }
  }

  // drzewo projektów: bramy z docs/MAGAZYN.md jako gałęzie
  property var zwiniete: ({})

  function przelaczBrame(klucz) {
    const z = zwiniete;
    z[klucz] = !z[klucz];
    zwiniete = z;
    ustawieniaStudia.zwinieteJson = JSON.stringify(z);
    przeladuj();
  }

  function przeladuj() {
    const zaznaczona = wybrany ? wybrany.sciezka : "";
    const plaska = procesy.znajdzProjekty(ustawieniaStudia.korzenProjektow, 4);

    let nowyWybrany = null;
    for (const p of plaska)
      if (zaznaczona !== "" && p.sciezka === zaznaczona)
        nowyWybrany = p;

    const BRAMY = [
      { klucz: "szablony", nazwa: qsTr("Szablony") },
      { klucz: "wydania",  nazwa: qsTr("Wydane w teren") },
      { klucz: "zwroty",   nazwa: qsTr("Przyjęte z terenu") },
      { klucz: "master",   nazwa: qsTr("Master") },
      { klucz: "archiwum", nazwa: qsTr("Archiwum") },
      { klucz: "inne",     nazwa: qsTr("Inne") }
    ];
    const kubelki = { wydania: [], zwroty: [], master: [],
                      szablony: [], archiwum: [], inne: [] };
    for (const p of plaska) {
      const pierwszy = String(p.gdzie || "").split("/")[0];
      (kubelki[pierwszy] !== undefined ? kubelki[pierwszy] : kubelki.inne).push(p);
    }

    const wiersze = [];
    for (const b of BRAMY) {
      const grupa = kubelki[b.klucz];
      if (grupa.length === 0)
        continue;
      wiersze.push({ rodzaj: "brama", klucz: b.klucz,
                     nazwa: b.nazwa, licznik: grupa.length });
      if (!zwiniete[b.klucz])
        for (const p of grupa)
          wiersze.push(Object.assign({ rodzaj: "projekt" }, p));
    }
    listaProjektow.model = wiersze;
    wybrany = nowyWybrany;
  }

  Component.onCompleted: {
    try {
      zwiniete = JSON.parse(ustawieniaStudia.zwinieteJson);
    } catch (e) {
      zwiniete = {};
    }
    przeladuj();
  }

  // ── korzeń drzewa ──────────────────────────────────────────────
  RowLayout {
    Layout.fillWidth: true
    Layout.margins: 8
    spacing: 4

    Text {
      Layout.fillWidth: true
      text: ustawieniaStudia.korzenProjektow
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      elide: Text.ElideMiddle
    }
    Button {
      flat: true
      text: qsTr("Zmień…")
      font: Theme.tinyFont
      onClicked: wyborKorzenia.open()
    }
    Button {
      flat: true
      text: qsTr("Odśwież")
      font: Theme.tinyFont
      onClicked: studio.przeladuj()
    }
  }

  // ── lista projektów ────────────────────────────────────────────
  ListView {
    id: listaProjektow

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    clip: true
    spacing: 2

    delegate: Rectangle {
      required property var modelData
      required property int index

      readonly property bool wierszBramy: modelData.rodzaj === "brama"
      readonly property bool zaznaczony: !wierszBramy && studio.wybrany
                                         && studio.wybrany.sciezka === modelData.sciezka

      width: listaProjektow.width
      height: (wierszBramy ? naglowekBramy.implicitHeight
                           : opisKol.implicitHeight) + 10
      radius: 4
      color: zaznaczony ? Theme.mainColor : "transparent"

      RowLayout {
        id: naglowekBramy
        visible: wierszBramy
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 6
        spacing: 6

        Text {
          text: wierszBramy && studio.zwiniete[modelData.klucz] ? "▸" : "▾"
          font: Theme.tipFont
          color: Theme.secondaryTextColor
        }
        Text {
          Layout.fillWidth: true
          text: wierszBramy ? modelData.nazwa : ""
          font: Theme.strongTipFont
          color: Theme.mainTextColor
          elide: Text.ElideRight
        }
        Text {
          text: wierszBramy ? modelData.licznik : ""
          font: Theme.tinyFont
          color: Theme.secondaryTextColor
        }
      }

      ColumnLayout {
        id: opisKol
        visible: !wierszBramy
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 22
        anchors.rightMargin: 6
        spacing: 0

        Text {
          Layout.fillWidth: true
          text: modelData.nazwa || ""
          font: Theme.tipFont
          color: zaznaczony ? "white" : Theme.mainTextColor
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: wierszBramy ? "" : modelData.typ + " · "
                + modelData.zmodyfikowano.replace("T", " ").substring(0, 16)
                + (modelData.gdzie !== "" ? " · " + modelData.gdzie : "")
          font: Theme.tinyFont
          color: zaznaczony ? "white" : Theme.secondaryTextColor
          elide: Text.ElideRight
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (wierszBramy)
            studio.przelaczBrame(modelData.klucz);
          else
            studio.wybrany = modelData;
        }
        onDoubleClicked: {
          if (wierszBramy)
            return;
          studio.wybrany = modelData;
          przyciskOtworz.clicked();
        }
      }
    }
  }

  // ── czasowniki ─────────────────────────────────────────────────
  GridLayout {
    Layout.fillWidth: true
    Layout.margins: 8
    columns: 2
    columnSpacing: 4
    rowSpacing: 4

    Button {
      id: przyciskOtworz
      Layout.fillWidth: true
      flat: true
      text: qsTr("Otwórz")
      font.pointSize: Theme.tinyFont.pointSize
      enabled: studio.wybrany && studio.wybrany.qgs !== ""
      onClicked: {
        dashBoard.close();
        iface.loadFile(studio.wybrany.qgs, studio.wybrany.nazwa);
      }
    }
    Button {
      Layout.fillWidth: true
      flat: true
      text: qsTr("Nowy z szablonu")
      font.pointSize: Theme.tinyFont.pointSize
      onClicked: kreatorNowego.open()
    }
    Button {
      Layout.fillWidth: true
      flat: true
      text: qsTr("Zbuduj projekt")
      font.pointSize: Theme.tinyFont.pointSize
      enabled: studio.wybrany && !procesy.dziala
      onClicked: {
        zapis.dopisz(qsTr("Buduję %1 ...").arg(studio.wybrany.nazwa));
        procesy.uruchomPyQgis(studio.wybrany.sciezka + "/zbuduj_projekt.py");
      }
    }
    Button {
      Layout.fillWidth: true
      flat: true
      text: qsTr("Wyślij na telefon")
      font.pointSize: Theme.tinyFont.pointSize
      enabled: studio.wybrany && !procesy.dziala
      onClicked: {
        // droga udowodniona na obecnym APK: zip -> karta -> import z przeglądarki
        const p = studio.wybrany.sciezka;
        const n = studio.wybrany.nazwa;
        zapis.dopisz(qsTr("Pakuję i wysyłam %1 ...").arg(n));
        procesy.uruchomPowloke("set -e; cd '" + p + "'"
          + " && zip -qr '/tmp/" + n + ".zip' . -x 'archiwum/*' '.kosz/*'"
          + " && adb push '/tmp/" + n + ".zip' '" + ustawieniaStudia.telefonKarta + "'"
          + " && echo 'Na telefonie: przeglądarka plików -> WorkField/data -> " + n + ".zip -> import.'");
      }
    }
    Button {
      Layout.columnSpan: 2
      Layout.fillWidth: true
      flat: true
      visible: procesy.dziala
      text: qsTr("Przerwij operację")
      font.pointSize: Theme.tinyFont.pointSize
      onClicked: procesy.przerwij()
    }
  }

  // ── zapis operacji ─────────────────────────────────────────────
  Text {
    Layout.leftMargin: 8
    text: qsTr("Zapis operacji")
    font: Theme.tinyFont
    color: Theme.secondaryTextColor
  }
  ScrollView {
    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Layout.bottomMargin: 8
    Layout.preferredHeight: 110
    clip: true

    TextArea {
      id: zapis
      readOnly: true
      wrapMode: TextEdit.Wrap
      font: Theme.tinyFont
      color: Theme.mainTextColor

      function dopisz(tekst) {
        append(tekst);
        cursorPosition = length;
      }
    }
  }

  // ── kreator: nowy projekt z szablonu ───────────────────────────
  Popup {
    id: kreatorNowego

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(420, mainWindow.width - 32)
    modal: true

    onAboutToShow: {
      const szablony = [];
      const wszystkie = procesy.znajdzProjekty(ustawieniaStudia.korzenProjektow, 4);
      for (const p of wszystkie)
        if (p.typ === "szablon")
          szablony.push(p);
      wyborSzablonu.model = szablony;
      poleNazwy.text = "";
    }

    ColumnLayout {
      width: parent.width
      spacing: 8

      Text {
        text: qsTr("Nowy projekt z szablonu")
        font: Theme.strongTipFont
        color: Theme.mainTextColor
      }
      ComboBox {
        id: wyborSzablonu
        Layout.fillWidth: true
        textRole: "nazwa"
      }
      TextField {
        id: poleNazwy
        Layout.fillWidth: true
        placeholderText: qsTr("nazwa, np. zzw_ptr_2603_inw")
      }
      RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        Button {
          flat: true
          text: qsTr("Anuluj")
          onClicked: kreatorNowego.close()
        }
        Button {
          text: qsTr("Utwórz")
          enabled: wyborSzablonu.currentIndex >= 0 && poleNazwy.text.trim() !== ""
          onClicked: {
            const szablon = wyborSzablonu.model[wyborSzablonu.currentIndex];
            const w = procesy.nowyZSzablonu(szablon.sciezka, "", poleNazwy.text,
                                            ustawieniaStudia.korzenProjektow);
            if (w.ok) {
              zapis.dopisz(qsTr("Utworzono %1 (z szablonu %2)").arg(w.sciezka).arg(szablon.nazwa));
              zapis.dopisz(qsTr("Teraz: Zbuduj projekt, potem Wyślij na telefon."));
              kreatorNowego.close();
              studio.przeladuj();
            } else {
              zapis.dopisz(qsTr("✗ %1").arg(w.blad));
            }
          }
        }
      }
    }
  }
}
