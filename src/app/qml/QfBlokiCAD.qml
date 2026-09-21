import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core
import Theme

/**
 * \ingroup qml
 *
 * WorkField 21.09.2026 — BLOKI Z RYSUNKU jako obiekty do sprawdzenia.
 *
 * Rysunek już zawiera to, po co idzie się w teren: słupy, studzienki,
 * pikiety — wstawione jako BLOKI. W próbnym rysunku jest ich 454
 * w dwudziestu paru rodzajach. Zamiast tapać każdy od nowa, wczytujemy je
 * jako obiekty i w terenie zostaje ich SPRAWDZENIE i uzupełnienie.
 *
 * Trafiają do osobnej warstwy „Symbole z rysunku", nie do warstwy punktów.
 * Powód jest jeden i twardy: każdy obiekt niesie UCHWYT — identyfikator
 * encji w rysunku — dzięki czemu powtórzone wczytanie niczego nie dubluje.
 * Warstwa punktów nie ma gdzie takiego klucza trzymać.
 */
Popup {
  id: oknoBlokowCAD

  property var t: Theme

  //! [{nazwa, obiekty, wczytane, warstwy, atrybuty}]
  property var bloki: []

  //! Zaznaczenia trzymane OSOBNO od modelu listy, po nazwie bloku.
  //!
  //! Dotąd siedziały w samym modelu, więc każde tapnięcie podmieniało
  //! całą tablicę — a ListView na zmianę modelu zaczyna od początku
  //! i lista skakała na górę (telefon, 21.09.2026). Model jest teraz
  //! nieruchomy: zmienia się tylko ta mapa.
  property var wybrane: ({})

  //! Dlaczego lista jest pusta - gdy powodem jest awaria, a nie brak blokow.
  property string blad: ""
  property bool zajety: false

  objectName: "oknoBlokowCAD"

  readonly property int wybranych: Object.keys(wybrane).length

  function otworz(szuflada) {
    if (szuflada && szuflada.modal && szuflada.opened) {
      const potem = function () {
        szuflada.closed.disconnect(potem);
        oknoBlokowCAD.open();
      };
      szuflada.closed.connect(potem);
      szuflada.close();
    } else {
      open();
    }
  }

  function odswiez() {
    if (typeof CAD === "undefined" || typeof qgisProject === "undefined") {
      bloki = [];
      return;
    }
    const w = CAD.bloki(qgisProject) || {};
    // "Nie udalo sie otworzyc rysunku" i "rysunek nie ma blokow" to DWIE
    // rozne rzeczy. Pierwsza wersja mowila jedno i drugie tak samo, wiec
    // awaria wygladala jak brak danych (telefon, 21.09).
    blad = w.blad !== undefined ? w.blad : "";
    const z = w.bloki !== undefined ? w.bloki : [];
    const kopia = [];
    for (let i = 0; i < z.length; i++)
      kopia.push({
                   "nazwa": z[i].nazwa,
                   "obiekty": z[i].obiekty,
                   "wczytane": z[i].wczytane,
                   "warstwy": z[i].warstwy,
                   "atrybuty": z[i].atrybuty !== undefined ? z[i].atrybuty : ""
                 });
    bloki = kopia;
    // Domyślnie NIC nie jest zaznaczone: 454 obiekty naraz to nie jest
    // decyzja, którą podejmuje się przez przeoczenie.
    wybrane = ({});
  }

  function przelacz(nazwa, wybrany) {
    const kopia = Object.assign({}, wybrane);
    if (wybrany)
      kopia[nazwa] = true;
    else
      delete kopia[nazwa];
    wybrane = kopia;
  }

  function zaznaczWszystkie(tak) {
    const kopia = {};
    if (tak) {
      for (let i = 0; i < bloki.length; i++)
        kopia[bloki[i].nazwa] = true;
    }
    wybrane = kopia;
  }

  function wczytaj() {
    const nazwy = [];
    for (let i = 0; i < bloki.length; i++) {
      if (wybrane[bloki[i].nazwa])
        nazwy.push(bloki[i].nazwa);
    }
    if (nazwy.length === 0)
      return;
    zajety = true;
    const w = CAD.zBlokow(qgisProject, nazwy);
    zajety = false;
    console.log("WFG CAD.zBlokow: " + JSON.stringify(w));
    if (w.blad) {
      displayToast(w.blad, "warning");
      return;
    }
    if (typeof NarzedziaProjektu !== "undefined")
      NarzedziaProjektu.zapiszProjekt(qgisProject);
    oknoBlokowCAD.close();
    displayToast(w.pominiete > 0
                 ? qsTr("Wczytano %1 obiektów do „%2”; %3 już było").arg(w.dodane).arg(w.warstwa).arg(w.pominiete)
                 : qsTr("Wczytano %1 obiektów do „%2”").arg(w.dodane).arg(w.warstwa));
  }

  onOpened: odswiez()

  parent: mainWindow.contentItem
  width: Math.min(460, mainWindow.width - 24)
  height: Math.min(600, mainWindow.height - 80)
  x: (mainWindow.width - width) / 2
  y: Math.max(12, (mainWindow.height - height) / 3)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  background: Rectangle {
    color: oknoBlokowCAD.t.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: oknoBlokowCAD.t.controlBorderColor
  }

  contentItem: ColumnLayout {
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Bloki z rysunku")
      font: oknoBlokowCAD.t.strongFont
      color: oknoBlokowCAD.t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Symbole wstawione w rysunku wejdą jako obiekty do warstwy „Symbole z rysunku”. Powtórne wczytanie niczego nie zdubluje.")
      font: oknoBlokowCAD.t.tinyFont
      color: oknoBlokowCAD.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      visible: oknoBlokowCAD.bloki.length === 0
      text: oknoBlokowCAD.blad !== ""
            ? oknoBlokowCAD.blad
            : qsTr("Ten rysunek nie ma wstawionych bloków.")
      font: oknoBlokowCAD.t.tipFont
      color: oknoBlokowCAD.blad !== "" ? oknoBlokowCAD.t.warningColor : oknoBlokowCAD.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      visible: oknoBlokowCAD.bloki.length > 0
      spacing: 6

      Button {
        text: oknoBlokowCAD.wybranych < oknoBlokowCAD.bloki.length
              ? qsTr("Zaznacz wszystkie")
              : qsTr("Odznacz wszystkie")
        font.pointSize: oknoBlokowCAD.t.tinyFont.pointSize
        onClicked: oknoBlokowCAD.zaznaczWszystkie(oknoBlokowCAD.wybranych < oknoBlokowCAD.bloki.length)
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("zaznaczono %1 z %2").arg(oknoBlokowCAD.wybranych).arg(oknoBlokowCAD.bloki.length)
        font: oknoBlokowCAD.t.tinyFont
        color: oknoBlokowCAD.t.secondaryTextColor
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
      }
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: oknoBlokowCAD.bloki
      ScrollBar.vertical: ScrollBar {}

      // Wiersz skladamy sami, zamiast dawac CheckBox-owi wlasny
      // `contentItem`: tamten kotwiczyl sie do WLASNEGO rodzica, wiec
      // kwadracik ladowal na srodku wiersza, a drugi napis nie mial
      // ograniczonej szerokosci i wychodzil za okno (piaskownica 21.09).
      delegate: Item {
        required property int index
        required property var modelData

        width: ListView.view.width
        implicitHeight: kolumnaWpisu.implicitHeight + 10

        CheckBox {
          id: znacznik

          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          checked: !!oknoBlokowCAD.wybrane[modelData.nazwa]
          onToggled: oknoBlokowCAD.przelacz(modelData.nazwa, checked)
        }

        ColumnLayout {
          id: kolumnaWpisu

          anchors.left: znacznik.right
          anchors.leftMargin: 4
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Text {
            Layout.fillWidth: true
            text: modelData.wczytane > 0
                  ? qsTr("%1  ·  %2  (wczytane: %3)").arg(modelData.nazwa).arg(modelData.obiekty).arg(modelData.wczytane)
                  : qsTr("%1  ·  %2").arg(modelData.nazwa).arg(modelData.obiekty)
            font: oknoBlokowCAD.t.tipFont
            color: oknoBlokowCAD.t.mainTextColor
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: modelData.atrybuty !== undefined && modelData.atrybuty !== ""
            // Blok potrafi niesc wlasne wartosci (numer studzienki, rzedna).
            // Wejda jako OSOBNE KOLUMNY warstwy, wiec warto wiedziec z gory,
            // co sie dostanie.
            text: qsTr("z wartościami: %1").arg(modelData.atrybuty || "")
            font: oknoBlokowCAD.t.tinyFont
            color: oknoBlokowCAD.t.mainColor
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: modelData.warstwy !== ""
            // Nazwa bloku to kod (PW01, OP021); co to JEST, mowi warstwa
            // rysunku, na ktorej symbol stoi - "drzewo lisciaste".
            text: modelData.warstwy
            font: oknoBlokowCAD.t.tinyFont
            color: oknoBlokowCAD.t.secondaryTextColor
            elide: Text.ElideRight
          }
        }

        // Caly wiersz przelacza - na telefonie trafienie w sam kwadracik
        // jest zadaniem dla cierpliwych.
        MouseArea {
          anchors.fill: kolumnaWpisu
          onClicked: oknoBlokowCAD.przelacz(modelData.nazwa, !oknoBlokowCAD.wybrane[modelData.nazwa])
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true

      BusyIndicator {
        implicitWidth: 20
        implicitHeight: 20
        running: oknoBlokowCAD.zajety
        visible: running
      }

      Item {
        Layout.fillWidth: true
      }

      Button {
        text: qsTr("Zamknij")
        font.pointSize: oknoBlokowCAD.t.tinyFont.pointSize
        onClicked: oknoBlokowCAD.close()
      }

      Button {
        text: oknoBlokowCAD.wybranych > 0 ? qsTr("Wczytaj (%1)").arg(oknoBlokowCAD.wybranych) : qsTr("Wczytaj")
        font.pointSize: oknoBlokowCAD.t.tinyFont.pointSize
        highlighted: true
        enabled: !oknoBlokowCAD.zajety && oknoBlokowCAD.wybranych > 0
        onClicked: oknoBlokowCAD.wczytaj()
      }
    }
  }
}
