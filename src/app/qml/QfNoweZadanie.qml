import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.qfield
import Theme

/**
 * Nowe zadanie z szablonu.
 *
 * Szablon niesie strukturę i formularze; zadanie dokłada do tego kontekst:
 * kto zleca, jaki teren, kiedy. Z tych trzech rzeczy powstaje nazwa katalogu
 * w postaci `zleceniodawca_teren_id_typ` — po niej rozpoznaje się później,
 * do którego zadania wracają dane z terenu.
 *
 * Świadomie NIE pytamy o nazwę katalogu wprost: nazwa jest wnioskiem
 * z wypełnionych pól, a nie kolejnym polem do wymyślenia w deszczu.
 */
Popup {
  id: kreator

  property var t
  //! katalog, w którym szukamy szablonów
  property string katalogSzablonow: ""
  //! katalog, w którym powstaje zadanie
  property string katalogProjektow: ""

  signal utworzono(string sciezka)

  width: Math.min(mainWindow.width - 32, 520)
  height: Math.min(mainWindow.height - 64, 640)
  x: Math.round((mainWindow.width - width) / 2)
  y: Math.round((mainWindow.height - height) / 2)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape

  background: Rectangle {
    color: t.mainBackgroundColor
    radius: 8
    border.color: t.controlBorderColor
  }

  onOpened: {
    // dopiero tutaj: przy tworzeniu obiektu iface może jeszcze nie być gotowy
    if (katalogSzablonow === "")
      katalogSzablonow = NarzedziaProjektu.katalogSzablonow(iface.dataRoot());
    if (katalogSzablonow === "")
      katalogSzablonow = iface.dataRoot() + "Szablony";
    if (katalogProjektow === "")
      katalogProjektow = iface.dataRoot() + "Imported Projects";
    poleData.text = new Date().toLocaleDateString(Qt.locale(), "yyyy-MM-dd");
    szablonWybrany = "";
    komunikat.text = "";
  }

  property string szablonWybrany: ""
  //! pusta pozycja na liście: zadanie bez szablonu, z pustym projektem
  readonly property string bezSzablonu: qsTr("(bez szablonu — pusty projekt)")

  // ------------------------------------------------------------ nazwa zadania
  // Powstaje z pól, nie z osobnego wpisu: klient_teren_data_typ.
  // Skróty budujemy z pierwszych liter, bo w nazwach katalogów nie chcemy
  // spacji ani polskich znaków — te potrafią popsuć ścieżki na Androidzie.
  function skrot(tekst, ile) {
    const czysty = tekst.trim().toLowerCase()
      .replace(/ą/g, "a").replace(/ć/g, "c").replace(/ę/g, "e")
      .replace(/ł/g, "l").replace(/ń/g, "n").replace(/ó/g, "o")
      .replace(/ś/g, "s").replace(/[żź]/g, "z")
      .replace(/[^a-z0-9 ]/g, "").replace(/\s+/g, " ");
    if (czysty === "")
      return "";
    const slowa = czysty.split(" ");
    if (slowa.length === 1)
      return slowa[0].substring(0, ile);
    return slowa.map(s => s.charAt(0)).join("").substring(0, ile);
  }

  property var listaSzablonow: [bezSzablonu]

  //! Pusty projekt zawsze na liście: nie każde zadanie zaczyna się od szablonu.
  function przebudujListe() {
    const lista = [bezSzablonu];
    for (let i = 0; i < modelSzablonow.count; i++) {
      lista.push(modelSzablonow.get(i, "fileName"));
    }
    listaSzablonow = lista;
  }

  function typZadania() {
    // typ bierzemy z nazwy szablonu: szablon_inw_zzw → inw
    const m = szablonWybrany.match(/_(inw|obs|inwazyjne|ciecia)(_|$)/);
    return m ? m[1] : "prj";
  }

  function nazwaZadania() {
    const klient = skrot(poleKlient.text, 6);
    const teren = skrot(poleTeren.text, 6);
    const rok = poleData.text.substring(2, 4);
    if (klient === "" || teren === "")
      return "";
    return klient + "_" + teren + "_" + rok + "_" + typZadania();
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 14
    spacing: 10

    Label {
      text: qsTr("Nowe zadanie z szablonu")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    // ---------------------------------------------------------- szablon
    Label {
      text: qsTr("Szablon")
      font: t.tinyFont
      color: t.secondaryTextColor
    }

    FolderListModel {
      id: modelSzablonow
      folder: kreator.katalogSzablonow !== "" ? "file://" + kreator.katalogSzablonow : ""
      showFiles: false
      showDirs: true
      showDotAndDotDot: false
      onCountChanged: kreator.przebudujListe()
    }

    ComboBox {
      id: wyborSzablonu
      Layout.fillWidth: true
      model: kreator.listaSzablonow
      onCurrentTextChanged: kreator.szablonWybrany = (currentText === kreator.bezSzablonu ? "" : currentText)
    }

    // ---------------------------------------------------------- kontekst
    Label {
      text: qsTr("Zleceniodawca")
      font: t.tinyFont
      color: t.secondaryTextColor
    }
    TextField {
      id: poleKlient
      Layout.fillWidth: true
      placeholderText: qsTr("np. ZZW")
    }

    Label {
      text: qsTr("Teren opracowania")
      font: t.tinyFont
      color: t.secondaryTextColor
    }
    TextField {
      id: poleTeren
      Layout.fillWidth: true
      placeholderText: qsTr("np. Park Żerański")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      ColumnLayout {
        Layout.fillWidth: true
        Label {
          text: qsTr("Data")
          font: t.tinyFont
          color: t.secondaryTextColor
        }
        TextField {
          id: poleData
          Layout.fillWidth: true
          inputMask: "9999-99-99"
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Label {
          text: qsTr("Tagi (oddziel przecinkiem)")
          font: t.tinyFont
          color: t.secondaryTextColor
        }
        TextField {
          id: poleTagi
          Layout.fillWidth: true
          placeholderText: qsTr("np. rekonesans, etap 1")
        }
      }
    }

    // ---------------------------------------------------------- podgląd nazwy
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 46
      color: t.controlBackgroundAlternateColor
      radius: 4

      Label {
        anchors.centerIn: parent
        text: kreator.nazwaZadania() !== ""
              ? qsTr("katalog: %1").arg(kreator.nazwaZadania())
              : qsTr("uzupełnij zleceniodawcę i teren")
        font: t.tipFont
        color: kreator.nazwaZadania() !== "" ? t.mainTextColor : t.secondaryTextColor
      }
    }

    Label {
      id: komunikat
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      font: t.tinyFont
      color: t.errorColor
      visible: text !== ""
    }

    Item {
      Layout.fillHeight: true
    }

    // ---------------------------------------------------------- przyciski
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Button {
        Layout.fillWidth: true
        flat: true
        text: qsTr("Anuluj")
        onClicked: kreator.close()
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Utwórz")
        enabled: kreator.nazwaZadania() !== ""
        onClicked: kreator.utworz()
      }
    }
  }

  // ------------------------------------------------------------ utworzenie
  function utworz() {
    const nazwa = nazwaZadania();
    const zrodlo = katalogSzablonow + "/" + szablonWybrany;
    const cel = katalogProjektow + "/" + nazwa;

    if (FileUtils.fileExists(cel)) {
      komunikat.text = qsTr("Katalog %1 już istnieje — zmień teren albo datę.").arg(nazwa);
      return;
    }

    // WorkField: szablon z przepisem budujemy od zera z aktualnego
    // wyposazenia. Interpreter sam wczytuje gotowy projekt, wiec NIE
    // emitujemy utworzono() — inaczej wczytalby sie dwa razy.
    if (szablonWybrany !== "" && FileUtils.fileExists(zrodlo + "/przepis.json")) {
      if (!mainWindow.przepisy.noweZadanie(zrodlo + "/przepis.json", katalogProjektow, nazwa)) {
        komunikat.text = qsTr("Nie udało się zbudować zadania z przepisu.");
        return;
      }
      kreator.zapiszMetryczke(cel, nazwa);
      kreator.close();
      return;
    }

    if (szablonWybrany === "") {
      // bez szablonu: pusty projekt w nowym katalogu
      platformUtilities.createDir(katalogProjektow, nazwa);
      if (!iface.createBlankProject(cel + "/projekt.qgs")) {
        komunikat.text = qsTr("Nie udało się utworzyć pustego projektu.");
        return;
      }
    } else if (!FileUtils.copyRecursively(zrodlo, cel, null, false)) {
      komunikat.text = qsTr("Nie udało się skopiować szablonu.");
      return;
    }

    zapiszMetryczke(cel, nazwa);

    displayToast(qsTr("Utworzono zadanie %1").arg(nazwa));
    kreator.utworzono(cel);
    kreator.close();
  }

  // Metryczka zadania: po niej rozpoznaje się, dokąd wracają dane z terenu.
  function zapiszMetryczke(cel, nazwa) {
    const tagi = poleTagi.text.split(",").map(s => s.trim()).filter(s => s !== "");
    const zadanie = {
      "id_zadania": nazwa,
      "rola": "wydanie",
      "szablon": typZadania(),
      "zleceniodawca": poleKlient.text.trim(),
      "teren": poleTeren.text.trim(),
      "data_rozpoczecia": poleData.text,
      "tagi": tagi,
      "zrodlo_szablonu": szablonWybrany !== "" ? szablonWybrany : "brak",
      "utworzono": new Date().toISOString().substring(0, 19).replace("T", " ")
    };
    FileUtils.writeFileContent(cel + "/ZADANIE.json",
                               JSON.stringify(zadanie, null, 2));
  }
}
