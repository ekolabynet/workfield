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
import org.qfield.gui // [WF-BUTTONS] QfDecisionButton
import org.qgis
import Theme

// [WF-WINDOW-FRAME] 24.10.2026 — common frame: ✕/✓ in the title bar, scrolling body
QfWindowFrame {
  id: kreatorCAD

  title: qsTr("Projekt z rysunku CAD")
  confirmText: qsTr("Utwórz")
  confirmEnabled: kreatorCAD.plikCAD !== "" && poleNazwy.text.trim() !== ""
  onConfirmed: kreatorCAD.utworz()
  preferredWidth: 540
  bodySpacing: 10

  property string plikCAD: ""
  property string ukladWybrany: "EPSG:2178"

  signal utworzono(string sciezka)

  focus: true

  function otworz() {
    plikCAD = "";
    ukladWybrany = "EPSG:2178";
    poleNazwy.text = "";
    komunikat.text = "";
    open();
    miejsceProjektu.upewnijSie(); // WorkFieldGIS 22.10.2026 — „gdzie zakładać” (raz, gdy jest karta)
  }

  //! [WF-FILE-BROWSER] 24.10.2026 — the drawing is chosen in the "Files"
  //! window (start: Pobrane; on a phone "Pobrane ↗" opens the system window,
  //! the same ACTION_OPEN_DOCUMENT as before). The kind is checked here too:
  //! "Inne miejsce…" lets any file through the system window.
  function plikWybrany(sciezka) {
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
    const katalogProjektow = iface.katalogNowychProjektow(); // WorkFieldGIS 22.10.2026 — pamięć / karta SD
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

  Text {
    Layout.fillWidth: true
    text: qsTr("Rysunek zostaje podkładem. Do niego dojdą trzy warstwy robocze: punkty, linie i poligony — każda z opisem, datą i zdjęciem.")
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
      onClicked: fileBrowser.pickFile({
                                        "title": qsTr("Wskaż rysunek DXF"),
                                        "pattern": /\.dxf$/i,
                                        "place": "pobrane",
                                        "done": function (sciezka) {
                                          kreatorCAD.plikWybrany(sciezka);
                                        }
                                      })
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
}
