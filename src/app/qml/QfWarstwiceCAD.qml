import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core
import Theme

/**
 * \ingroup qml
 *
 * WorkField 21.09.2026 — WARSTWICE Z RZĘDNYCH wczytanych z rysunku.
 *
 * Rzędne przyszły z rysunku (czynność „Dociągnij opisy"), więc i warstwice
 * z nich należą do modułu CAD. Warstwice z NMT stoją gdzie indziej — przy
 * NMT i NMPT, w oknie danych wysokościowych. Źródło decyduje o miejscu,
 * ale sam rachunek jest jeden (utils/warstwice.h).
 *
 * METODA to nie kosmetyka. „Wiernie" (triangulacja Delaunaya) trzyma się
 * punktów co do centymetra, ale przy pomiarze wzdłuż dróg daje warstwice
 * kanciaste i z prostymi artefaktami — sprawdzone na 1240 rzędnych
 * z rysunku 3853_24_pin. „Gładko" daje linie, jakich geodeta się spodziewa.
 */
Popup {
  id: oknoWarstwicCAD

  property var t: Theme
  property var pola: []
  property string stan: ""
  property bool zajety: false

  objectName: "oknoWarstwicCAD"

  function otworz(szuflada) {
    if (szuflada && szuflada.modal && szuflada.opened) {
      const potem = function () {
        szuflada.closed.disconnect(potem);
        oknoWarstwicCAD.open();
      };
      szuflada.closed.connect(potem);
      szuflada.close();
    } else {
      open();
    }
  }

  function odswiez() {
    stan = "";
    pola = (typeof CAD !== "undefined" ? CAD.polaZWysokoscia(qgisProject) : []) || [];
    wyborPola.currentIndex = 0;
  }

  function odstep() {
    const v = parseFloat(String(poleOdstepu.text).replace(",", "."));
    return isNaN(v) || v <= 0 ? 0.5 : v;
  }

  function policz() {
    if (pola.length === 0)
      return;
    zajety = true;
    const w = CAD.warstwiceZRzednych(qgisProject,
                                     pola[wyborPola.currentIndex].pole,
                                     odstep(),
                                     przelacznikMetody.checked ? "wiernie" : "gladko");
    zajety = false;
    console.log("WFG CAD.warstwiceZRzednych: " + JSON.stringify(w));
    if (w.blad) {
      stan = w.blad;
      return;
    }
    if (typeof NarzedziaProjektu !== "undefined")
      NarzedziaProjektu.zapiszProjekt(qgisProject);
    oknoWarstwicCAD.close();
    displayToast(qsTr("Warstwice co %1 m: %2 linii z %3 rzędnych").arg(w.odstep).arg(w.linie).arg(w.punkty));
  }

  onOpened: odswiez()

  parent: mainWindow.contentItem
  width: Math.min(460, mainWindow.width - 24)
  x: (mainWindow.width - width) / 2
  y: Math.max(12, (mainWindow.height - height) / 3)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  background: Rectangle {
    color: oknoWarstwicCAD.t.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: oknoWarstwicCAD.t.controlBorderColor
  }

  contentItem: ColumnLayout {
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Warstwice z rzędnych")
      font: oknoWarstwicCAD.t.strongFont
      color: oknoWarstwicCAD.t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Z rzędnych wczytanych z rysunku powstaje powierzchnia, a z niej warstwice. Poza obrysem pomiaru warstwic nie ma i nie powinno być.")
      font: oknoWarstwicCAD.t.tinyFont
      color: oknoWarstwicCAD.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      visible: oknoWarstwicCAD.pola.length === 0
      text: qsTr("W warstwie symboli nie ma pola z wysokościami. Najpierw „Wczytaj bloki” i „Dociągnij opisy”.")
      font: oknoWarstwicCAD.t.tipFont
      color: oknoWarstwicCAD.t.warningColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6
      visible: oknoWarstwicCAD.pola.length > 0

      Text {
        text: qsTr("Wysokości z pola")
        font: oknoWarstwicCAD.t.tipFont
        color: oknoWarstwicCAD.t.mainTextColor
      }

      ComboBox {
        id: wyborPola

        Layout.fillWidth: true
        font.pointSize: oknoWarstwicCAD.t.tipFont.pointSize
        model: oknoWarstwicCAD.pola
        // Liczba obok nazwy: pole z trzema wartosciami i pole z tysiacem
        // wygladaja tak samo, dopoki sie ich nie policzy.
        textRole: "pole"
        displayText: oknoWarstwicCAD.pola.length > 0 && currentIndex >= 0
                     ? qsTr("%1  ·  %2 wartości").arg(oknoWarstwicCAD.pola[currentIndex].pole).arg(oknoWarstwicCAD.pola[currentIndex].ile)
                     : ""
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6
      visible: oknoWarstwicCAD.pola.length > 0

      Text {
        text: qsTr("Co ile metrów")
        font: oknoWarstwicCAD.t.tipFont
        color: oknoWarstwicCAD.t.mainTextColor
      }

      TextField {
        id: poleOdstepu

        Layout.preferredWidth: 70
        text: "0,5"
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        font.pointSize: oknoWarstwicCAD.t.tipFont.pointSize
      }

      Item {
        Layout.fillWidth: true
      }
    }

    CheckBox {
      id: przelacznikMetody

      Layout.fillWidth: true
      visible: oknoWarstwicCAD.pola.length > 0
      text: qsTr("Wiernie punktom (kanciaste)")
      font.pointSize: oknoWarstwicCAD.t.tinyFont.pointSize
      checked: false
    }

    Text {
      Layout.fillWidth: true
      visible: oknoWarstwicCAD.pola.length > 0
      text: przelacznikMetody.checked
            ? qsTr("Triangulacja: linie trzymają się punktów co do centymetra, ale przy pomiarze wzdłuż dróg wychodzą kanciaste.")
            : qsTr("Wygładzone: linie czytelne, jak na mapie — kosztem drobnych załamań terenu.")
      font: oknoWarstwicCAD.t.tinyFont
      color: oknoWarstwicCAD.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      visible: oknoWarstwicCAD.stan !== ""
      text: oknoWarstwicCAD.stan
      font: oknoWarstwicCAD.t.tipFont
      color: oknoWarstwicCAD.t.warningColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true

      BusyIndicator {
        implicitWidth: 20
        implicitHeight: 20
        running: oknoWarstwicCAD.zajety
        visible: running
      }

      Item {
        Layout.fillWidth: true
      }

      Button {
        text: qsTr("Zamknij")
        font.pointSize: oknoWarstwicCAD.t.tinyFont.pointSize
        onClicked: oknoWarstwicCAD.close()
      }

      Button {
        text: qsTr("Policz warstwice")
        font.pointSize: oknoWarstwicCAD.t.tinyFont.pointSize
        highlighted: true
        enabled: !oknoWarstwicCAD.zajety && oknoWarstwicCAD.pola.length > 0
        onClicked: oknoWarstwicCAD.policz()
      }
    }
  }
}
