import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core
import Theme

/**
 * \ingroup qml
 *
 * WorkField 21.09.2026 — WARSTWY RYSUNKU CAD: pokaż tylko potrzebne.
 *
 * GDAL zwraca z DXF-a jedną warstwę na TYP GEOMETRII (punkty, linie,
 * poligony), a projektant myśli warstwami rysunku — te siedzą w atrybucie
 * „Layer". W terenie rysunek architektoniczny potrafi mieć czterdzieści
 * warstw, z których potrzebne są trzy.
 *
 * Ukrycie jest WIDOKIEM, nie usuwaniem: idzie przez `subsetString` warstw
 * rysunku, zapisuje się razem z projektem i da się cofnąć. Plik DXF na
 * dysku jest nietknięty — w module CAD rysunek jest cudzy i ma taki zostać.
 */
Popup {
  id: oknoWarstwRysunku

  property var t: Theme

  //! [{nazwa, obiekty, widoczna}] — wprost z silnika, plus lokalna zmiana
  //! zaznaczenia, dopóki nie naciśnie się „Zastosuj".
  property var warstwy: []

  objectName: "oknoWarstwRysunku"

  /**
   * Otwarcie z szuflady albo z karty modułu. Szuflada na telefonie jest
   * modalna i jej przyciemnienie gaśnie z opóźnieniem — okno otwarte spod
   * niej wychodzi wyblakłe (notatka z 24.08.2026).
   */
  function otworz(szuflada) {
    if (szuflada && szuflada.modal && szuflada.opened) {
      const potem = function () {
        szuflada.closed.disconnect(potem);
        oknoWarstwRysunku.open();
      };
      szuflada.closed.connect(potem);
      szuflada.close();
    } else {
      open();
    }
  }

  function odswiez() {
    if (typeof CAD === "undefined" || typeof qgisProject === "undefined") {
      warstwy = [];
      return;
    }
    // Kopia, a nie lista z silnika: zaznaczenie zmienia się w oknie i ma
    // NIE ruszać projektu, dopóki nie padnie „Zastosuj".
    const z = CAD.warstwyRysunku(qgisProject) || [];
    const kopia = [];
    for (let i = 0; i < z.length; i++)
      kopia.push({
                   "nazwa": z[i].nazwa,
                   // Klucz to SUROWA wartość z bazy; nazwa bywa naprawiona
                   // (krzaki z $DWGCODEPAGE). Filtr musi pasować do bazy.
                   "klucz": z[i].klucz !== undefined ? z[i].klucz : z[i].nazwa,
                   "obiekty": z[i].obiekty,
                   "widoczna": z[i].widoczna
                 });
    warstwy = kopia;
  }

  function ustawWszystkie(widoczna) {
    const kopia = warstwy.slice();
    for (let i = 0; i < kopia.length; i++)
      kopia[i] = {
        "nazwa": kopia[i].nazwa,
        "klucz": kopia[i].klucz,
        "obiekty": kopia[i].obiekty,
        "widoczna": widoczna
      };
    warstwy = kopia;
  }

  function zastosuj() {
    const ukryte = [];
    for (let i = 0; i < warstwy.length; i++) {
      if (!warstwy[i].widoczna)
        ukryte.push(warstwy[i].klucz);
    }
    const w = CAD.pokazWarstwy(qgisProject, ukryte);
    console.log("WFG CAD.pokazWarstwy: " + JSON.stringify(w));
    if (w.blad) {
      displayToast(w.blad, "warning");
      return;
    }
    if (typeof NarzedziaProjektu !== "undefined")
      NarzedziaProjektu.zapiszProjekt(qgisProject);
    oknoWarstwRysunku.close();
    displayToast(ukryte.length === 0 ? qsTr("Rysunek w całości") : qsTr("Ukryte warstwy rysunku: %1").arg(ukryte.length));
  }

  onOpened: odswiez()

  parent: mainWindow.contentItem
  width: Math.min(460, mainWindow.width - 24)
  height: Math.min(560, mainWindow.height - 80)
  x: (mainWindow.width - width) / 2
  y: Math.max(12, (mainWindow.height - height) / 3)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  background: Rectangle {
    color: oknoWarstwRysunku.t.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: oknoWarstwRysunku.t.controlBorderColor
  }

  contentItem: ColumnLayout {
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Warstwy rysunku")
      font: oknoWarstwRysunku.t.strongFont
      color: oknoWarstwRysunku.t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Odznaczone znikają z mapy. Rysunek na dysku zostaje bez zmian — to filtr widoku, zapisywany z projektem.")
      font: oknoWarstwRysunku.t.tinyFont
      color: oknoWarstwRysunku.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Button {
        text: qsTr("Wszystkie")
        font.pointSize: oknoWarstwRysunku.t.tinyFont.pointSize
        enabled: oknoWarstwRysunku.warstwy.length > 0
        onClicked: oknoWarstwRysunku.ustawWszystkie(true)
      }

      Button {
        text: qsTr("Żadna")
        font.pointSize: oknoWarstwRysunku.t.tinyFont.pointSize
        enabled: oknoWarstwRysunku.warstwy.length > 0
        onClicked: oknoWarstwRysunku.ustawWszystkie(false)
      }

      Item {
        Layout.fillWidth: true
      }

      Text {
        text: qsTr("%1 warstw").arg(oknoWarstwRysunku.warstwy.length)
        font: oknoWarstwRysunku.t.tinyFont
        color: oknoWarstwRysunku.t.secondaryTextColor
      }
    }

    // Napis w DXF-ie jest encją PUNKTOWĄ, więc QGIS rysuje mu znacznik
    // w miejscu zakorzenienia tekstu — obok obiektu, którego napis dotyczy.
    // Przy kilku tysiącach napisów mapa tonie w kropkach i każda wygląda
    // jak duplikat obiektu. Napis zostaje, gaśnie sama kropka.
    CheckBox {
      Layout.fillWidth: true
      visible: oknoWarstwRysunku.warstwy.length > 0
      text: qsTr("Kropki pod napisami rysunku")
      font.pointSize: oknoWarstwRysunku.t.tipFont.pointSize
      checked: typeof iface !== "undefined"
               ? iface.readProjectNumEntry("wfg_cad", "/kropkiNapisow", 1) !== 0
               : true
      onToggled: {
        const w = CAD.kropkiNapisow(qgisProject, checked);
        console.log("WFG CAD.kropkiNapisow: " + JSON.stringify(w));
        if (w.blad)
          displayToast(w.blad, "warning");
        else if (typeof NarzedziaProjektu !== "undefined")
          NarzedziaProjektu.zapiszProjekt(qgisProject);
      }
    }

    Text {
      Layout.fillWidth: true
      visible: oknoWarstwRysunku.warstwy.length === 0
      text: qsTr("Ten projekt nie ma warstw rysunku z polem „Layer”.")
      font: oknoWarstwRysunku.t.tipFont
      color: oknoWarstwRysunku.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: oknoWarstwRysunku.warstwy
      ScrollBar.vertical: ScrollBar {}

      delegate: CheckBox {
        required property int index
        required property var modelData

        width: ListView.view.width
        text: modelData.obiekty > 0 ? qsTr("%1  ·  %2").arg(modelData.nazwa).arg(modelData.obiekty) : modelData.nazwa
        font.pointSize: oknoWarstwRysunku.t.tipFont.pointSize
        checked: modelData.widoczna
        onToggled: {
          // Podmiana CALEJ tablicy, bo `property var` nie zglasza zmiany
          // pojedynczego pola i widok zostalby na starym zaznaczeniu.
          const kopia = oknoWarstwRysunku.warstwy.slice();
          kopia[index] = {
            "nazwa": modelData.nazwa,
            "klucz": modelData.klucz,
            "obiekty": modelData.obiekty,
            "widoczna": checked
          };
          oknoWarstwRysunku.warstwy = kopia;
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true

      Item {
        Layout.fillWidth: true
      }

      Button {
        text: qsTr("Zamknij")
        font.pointSize: oknoWarstwRysunku.t.tinyFont.pointSize
        onClicked: oknoWarstwRysunku.close()
      }

      Button {
        text: qsTr("Zastosuj")
        font.pointSize: oknoWarstwRysunku.t.tinyFont.pointSize
        highlighted: true
        enabled: oknoWarstwRysunku.warstwy.length > 0
        onClicked: oknoWarstwRysunku.zastosuj()
      }
    }
  }
}
