import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.qfield
import Theme

/**
 * \\ingroup qml
 *
 * WorkField: prosty edytor tekstowy plikow konfiguracyjnych projektu
 * (json/txt/md/csv). Do szybkich poprawek w terenie, bez laptopa.
 * Zapis .json poprzedza walidacja skladni; pierwszy zapis robi kopie .bak.
 */
Popup {
  id: textEditor

  parent: mainWindow.contentItem
  width: Math.min(760, mainWindow.width - 16)
  height: Math.min(860, mainWindow.height - 32)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: Popup.CloseOnEscape

  property string sciezka: ""
  property string oryginal: ""
  property bool zmieniono: false
  property bool bakZapisany: false
  property bool ladowanie: false
  property int potwierdz: 0 // 0: nic, 1: powrot do listy, 2: zamkniecie

  background: Rectangle {
    color: "#EE263238"
    radius: 8
    border.color: "#455A64"
    border.width: 1
  }

  function nazwaPliku(fp) {
    return String(fp).split('/').pop();
  }

  function wczytaj(fp) {
    const tresc = String(FileUtils.readFileContent(fp));
    if (tresc.length > 2000000) {
      displayToast(qsTr("Plik za duży na edytor terenowy (limit 2 MB)"), "warning");
      return;
    }
    ladowanie = true;
    obszar.text = tresc;
    ladowanie = false;
    sciezka = fp;
    oryginal = tresc;
    zmieniono = false;
    bakZapisany = false;
    potwierdz = 0;
  }

  function zapisz() {
    if (sciezka === "") {
      return;
    }
    if (nazwaPliku(sciezka).toLowerCase().endsWith(".json")) {
      try {
        JSON.parse(obszar.text);
      } catch (e) {
        displayToast(qsTr("Błąd składni JSON — NIE zapisano: %1").arg(e.message), "error");
        return;
      }
    }
    if (!bakZapisany) {
      FileUtils.writeFileContent(sciezka + ".bak", oryginal);
      bakZapisany = true;
    }
    if (FileUtils.writeFileContent(sciezka, obszar.text)) {
      zmieniono = false;
      oryginal = obszar.text;
      displayToast(qsTr("Zapisano %1 (kopia: .bak)").arg(nazwaPliku(sciezka)));
      if (nazwaPliku(sciezka) === "workfield_klawisze.json" && typeof quickCaptureBar !== 'undefined') {
        quickCaptureBar.refreshLayers();
      }
    } else {
      displayToast(qsTr("Zapis nie powiódł się — plik na dysku bez zmian"), "error");
    }
  }

  function sprobujWyjsc(tryb) {
    if (!zmieniono) {
      wykonajWyjscie(tryb);
      return;
    }
    if (potwierdz === tryb) {
      potwierdz = 0;
      zegarPotwierdzenia.stop();
      wykonajWyjscie(tryb);
    } else {
      potwierdz = tryb;
      zegarPotwierdzenia.restart();
      displayToast(qsTr("Niezapisane zmiany — tapnij ponownie, aby porzucić"), "warning");
    }
  }

  function wykonajWyjscie(tryb) {
    if (tryb === 1) {
      sciezka = "";
      zmieniono = false;
    } else {
      textEditor.close();
    }
  }

  onClosed: {
    sciezka = "";
    zmieniono = false;
    potwierdz = 0;
  }

  Timer {
    id: zegarPotwierdzenia

    interval: 3000

    onTriggered: textEditor.potwierdz = 0
  }

  FolderListModel {
    id: plikiProjektu

    folder: qgisProject && qgisProject.homePath !== "" ? "file://" + qgisProject.homePath : ""
    nameFilters: ["*.json", "*.txt", "*.md", "*.csv"]
    showDirs: false
    sortField: FolderListModel.Name
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: textEditor.sciezka === "" ? qsTr("Pliki projektu — edytor") : textEditor.nazwaPliku(textEditor.sciezka) + (textEditor.zmieniono ? " \u25cf" : "")
      color: textEditor.zmieniono ? "#FFC107" : "#80CBC4"
      font: Theme.strongFont
      elide: Text.ElideMiddle
    }

    // ---------------- widok 1: lista plikow ----------------
    ListView {
      visible: textEditor.sciezka === ""
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: plikiProjektu
      spacing: 2

      delegate: ItemDelegate {
        width: ListView.view.width
        height: 52

        contentItem: RowLayout {
          spacing: 8

          Text {
            Layout.fillWidth: true
            text: fileName
            color: "white"
            font: Theme.defaultFont
            elide: Text.ElideMiddle
          }

          Text {
            text: (fileSize / 1024).toFixed(1) + " kB"
            color: "#B0BEC5"
            font: Theme.tinyFont
          }
        }

        onClicked: textEditor.wczytaj(filePath.toString().replace("file://", ""))
      }

      Text {
        anchors.centerIn: parent
        visible: parent.count === 0
        text: qgisProject && qgisProject.homePath !== "" ? qsTr("Brak plików json/txt/md/csv w katalogu projektu") : qsTr("Najpierw otwórz projekt")
        color: "#B0BEC5"
        font: Theme.tipFont
      }
    }

    // ---------------- widok 2: edycja ----------------
    ScrollView {
      visible: textEditor.sciezka !== ""
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true

      TextArea {
        id: obszar

        wrapMode: TextArea.Wrap
        selectByMouse: true
        font.family: "monospace"
        font.pointSize: Theme.tipFont.pointSize
        color: "white"
        placeholderText: qsTr("(pusty plik)")

        background: Rectangle {
          color: "#1B262C"
          radius: 4
          border.color: "#455A64"
          border.width: 1
        }

        onTextChanged: {
          if (!textEditor.ladowanie && textEditor.sciezka !== "") {
            textEditor.zmieniono = true;
          }
        }
      }
    }

    RowLayout {
      visible: textEditor.sciezka !== ""
      Layout.fillWidth: true
      spacing: 8

      Button {
        Layout.fillWidth: true
        text: textEditor.potwierdz === 1 ? qsTr("Porzucić zmiany?") : qsTr("Wróć do listy")
        onClicked: textEditor.sprobujWyjsc(1)
      }

      Button {
        Layout.fillWidth: true
        enabled: textEditor.zmieniono
        text: qsTr("Zapisz")
        onClicked: textEditor.zapisz()
      }
    }

    Button {
      Layout.fillWidth: true
      text: textEditor.potwierdz === 2 ? qsTr("Porzucić zmiany?") : qsTr("Zamknij")
      onClicked: textEditor.sciezka !== "" ? textEditor.sprobujWyjsc(2) : textEditor.close()
    }
  }
}
