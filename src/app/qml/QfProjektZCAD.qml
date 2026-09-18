/**
 * Projekt z rysunku CAD — dla projektanta, nie dla gisowca.
 *
 * WorkField 18.09.2026. Tester jest CADowcem: ma DXF i chce z nim chodzic
 * po terenie, dopinac obserwacje ze zdjeciami i wywiezc wynik z powrotem
 * do DXF. Nie bedzie wczytywal rysunku w QGIS ani skladal projektu recznie.
 *
 * LISTA ZAMIAST MENEDZERA PLIKOW: `QfPhotoGallery.openFiles()` otwiera
 * przegladarke, ale nie oddaje wybranej sciezki — nie ma sygnalu ani
 * wywolania zwrotnego. Kreator sam przeglada katalogi, w ktorych rysunek
 * moze wyladowac. Wyszlo lepiej niz zamierzone: projektant wgrywa plik
 * kablem albo przez LocalSend i widzi go na liscie, bez szukania.
 *
 * PROJEKT POWSTAJE OBOK RYSUNKU. `QfFileUtils` nie ma kopiowania
 * POJEDYNCZEGO pliku (jest `copyRecursively` na katalogi), a przepisywanie
 * DXF-a przez pamiec byloby ciezkie. Obok jest zreszta blizsze temu, jak
 * pracuje projektant: ma katalog ze zleceniem i tam trzyma wszystko.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as SystemoweOkna
import org.qfield
import org.qgis
import Theme

Popup {
  id: kreatorCAD

  property string plikCAD: ""
  property string ukladWybrany: "EPSG:2178"

  signal utworzono(string sciezka)

  parent: mainWindow.contentItem
  x: (parent.width - width) / 2
  y: (parent.height - height) / 2
  width: Math.min(parent.width - 24, 540)
  height: Math.min(parent.height - 48, 620)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape

  background: Rectangle {
    color: Theme.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: Theme.controlBorderColor
  }

  function otworz() {
    plikCAD = "";
    ukladWybrany = "EPSG:2178";
    poleNazwy.text = "";
    komunikat.text = "";
    open();
  }

  //! Systemowe okno wyboru pliku — `ACTION_OPEN_DOCUMENT` Androida.
  //! Uzytkownik wskazuje plik sam i tylko do niego aplikacja dostaje
  //! dostep. Wlasne przeszukiwanie katalogow (pierwsza proba, 18.09)
  //! nie widzialo `Download` i bylo obce czlowiekowi, ktory zna swoj
  //! telefon lepiej niz nasza liste.
  SystemoweOkna.FileDialog {
    id: wybieraczPliku

    title: qsTr("Wskaż rysunek DXF")
    // Start w Pobranych: tam ląduje rysunek przysłany przez LocalSend,
    // WhatsAppa albo wgrany kablem. Bez tego Qt otwiera okno w przestrzeni
    // aplikacji, gdzie projektant swojego pliku nie znajdzie.
    currentFolder: "file:///storage/emulated/0/Download"
    // BEZ filtra rozszerzen. Systemowe okno Androida filtruje po typie
    // MIME, nie po nazwie — a DXF nie ma zarejestrowanego typu, wiec
    // `*.dxf` chowalo wszystko poza obrazkami. Sprawdzamy rozszerzenie
    // PO wybraniu, wtedy widac tez, dlaczego plik sie nie nadaje.
    nameFilters: [qsTr("Wszystkie pliki (*)")]
    onAccepted: {
      const sciezka = String(selectedFile).replace(/^file:\/\//, "");
      if (FileUtils.fileSuffix(sciezka).toLowerCase() !== "dxf") {
        komunikat.text = qsTr("To nie jest rysunek DXF: %1")
                          .arg(FileUtils.fileName(sciezka));
        return;
      }
      komunikat.text = "";
      kreatorCAD.plikCAD = sciezka;
      if (poleNazwy.text === "")
        poleNazwy.text = FileUtils.fileName(sciezka, false)
                          .replace(/[.]/g, "_")
                          .replace(/[^A-Za-z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ _-]/g, "")
                          .substring(0, 48).trim();
    }
  }

  function utworz() {
    const nazwa = poleNazwy.text.trim();
    if (nazwa === "") {
      komunikat.text = qsTr("Podaj nazwę projektu.");
      return;
    }
    if (plikCAD === "") {
      komunikat.text = qsTr("Wskaż rysunek.");
      return;
    }

    // PROJEKT W `Imported Projects`, nie obok rysunku. Android zabrania
    // zapisu poza katalogami aplikacji — w logu widac to wprost:
    // "Creating or writing to a non-default top level directory is not
    // allowed". Odczyt z `Download` dziala, zapis nie.
    const katalogProjektow = iface.dataRoot() + "Imported Projects";
    const cel = katalogProjektow + "/" + nazwa;
    if (FileUtils.fileExists(cel)) {
      komunikat.text = qsTr("Projekt o tej nazwie już istnieje.");
      return;
    }
    // `NarzedziaProjektu.nowyProjekt` zamiast `createBlankProject`:
    // ten drugi nie zna ukladu i zostawia EPSG:3857, przez co rysunek
    // w PL-2000 rozciagal sie na tysiace kilometrow (18.09.2026).
    // Katalog zaklada sam, wiec `createDir` juz niepotrzebne.
    const plikProjektu = NarzedziaProjektu.nowyProjekt(katalogProjektow,
                                                       nazwa, ukladWybrany);
    if (plikProjektu === "") {
      komunikat.text = qsTr("Nie udało się utworzyć projektu.");
      return;
    }

    // Warstwy zakladamy PO wczytaniu projektu — `createEmptyLayer` wpina je
    // do OTWARTEGO projektu. Stan przez mainWindow, bo kreator zamyka sie
    // zanim projekt wstanie.
    // Rysunek KOPIUJEMY do projektu. Zostawiony w `Download` nie pojedzie
    // ani w wydaniu, ani w kopii na nosnik — a projekt bez podkladu jest
    // bezuzyteczny. `kopiujPlik` dopisane 18.09.2026 do `QfFileUtils`,
    // ktore mialo tylko `copyRecursively` na katalogi.
    const nazwaRysunku = FileUtils.fileName(plikCAD);
    if (!FileUtils.kopiujPlik(plikCAD, cel + "/" + nazwaRysunku, false)) {
      komunikat.text = qsTr("Nie udało się skopiować rysunku do projektu.");
      return;
    }

    mainWindow.cadRysunek = cel + "/" + nazwaRysunku;
    mainWindow.cadUklad = ukladWybrany;
    mainWindow.cadKatalog = cel;
    kreatorCAD.close();
    displayToast(qsTr("Tworzę projekt %1…").arg(nazwa));
    iface.loadFile(plikProjektu, nazwa);
    kreatorCAD.utworzono(cel);
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 16
    spacing: 10

    Text {
      Layout.fillWidth: true
      text: qsTr("Projekt z rysunku CAD")
      font: Theme.strongFont
      color: Theme.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Rysunek zostaje podkładem. Do niego dojdą trzy warstwy robocze: punkty, linie i poligony (hatch) — każda z opisem, datą i zdjęciem.")
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 6
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: kreatorCAD.plikCAD !== ""
              ? FileUtils.fileName(kreatorCAD.plikCAD)
              : qsTr("nie wskazano rysunku")
        font: Theme.tipFont
        color: kreatorCAD.plikCAD !== "" ? Theme.mainTextColor
                                         : Theme.secondaryTextColor
        elide: Text.ElideMiddle
      }

      Button {
        text: qsTr("Wybierz…")
        onClicked: wybieraczPliku.open()
      }
    }

    Text {
      Layout.fillWidth: true
      visible: kreatorCAD.plikCAD !== ""
      text: kreatorCAD.plikCAD
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      elide: Text.ElideMiddle
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Układ")
        font: Theme.tipFont
        color: Theme.mainTextColor
      }

      ComboBox {
        Layout.fillWidth: true
        // PL-2000 strefa 7 pierwsza (Mazowsze), dalej pozostale strefy 2000,
        // PL-1992 na koncu jako wyjatek.
        model: ["EPSG:2178", "EPSG:2179", "EPSG:2177", "EPSG:2176", "EPSG:2180"]
        currentIndex: 0
        onActivated: kreatorCAD.ukladWybrany = model[currentIndex]
      }
    }

    TextField {
      id: poleNazwy

      Layout.fillWidth: true
      placeholderText: qsTr("Nazwa projektu")
      font: Theme.tipFont
    }

    Text {
      id: komunikat

      Layout.fillWidth: true
      visible: text !== ""
      color: Theme.errorColor
      font: Theme.tipFont
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Item { Layout.fillWidth: true }

      Button {
        text: qsTr("Anuluj")
        onClicked: kreatorCAD.close()
      }

      Button {
        text: qsTr("Utwórz")
        enabled: kreatorCAD.plikCAD !== "" && poleNazwy.text.trim() !== ""
        onClicked: kreatorCAD.utworz()
      }
    }
  }
}
