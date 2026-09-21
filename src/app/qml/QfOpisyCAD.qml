import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core
import Theme

/**
 * \ingroup qml
 *
 * WorkField 21.09.2026 — DOCIĄGNIJ OPISY Z RYSUNKU.
 *
 * Rzędne są dla projektanta najważniejsze, a w rysunku NIE SIEDZĄ w bloku:
 * w trzech sprawdzonych rysunkach (Bruzdowa, Adamowizna, 3853_24_pin) nie ma
 * ani jednej encji ATTRIB. Wartości zostały przy zapisie rozbite na osobne
 * teksty, na warstwach nazwanych po warstwie symbolu — „…-Atr2" (rozbity
 * atrybut) albo „…_O" (opis).
 *
 * Nazwa warstwy mówi wprost, do czego tekst należy; zostaje dobranie pary
 * w obrębie warstwy. Dlatego okno pyta tylko o jedno: jak daleko szukać.
 *
 * Najpierw POLICZ, potem zapisz — bo symboli bywa więcej niż tekstów
 * i warto zobaczyć, ilu obiektów to dotyczy, zanim cokolwiek wejdzie.
 */
Popup {
  id: oknoOpisowCAD

  property var t: Theme
  property string stan: ""
  property bool zajety: false
  property bool policzone: false

  objectName: "oknoOpisowCAD"

  function otworz(szuflada) {
    if (szuflada && szuflada.modal && szuflada.opened) {
      const potem = function () {
        szuflada.closed.disconnect(potem);
        oknoOpisowCAD.open();
      };
      szuflada.closed.connect(potem);
      szuflada.close();
    } else {
      open();
    }
  }

  function promien() {
    const v = parseFloat(String(polePromienia.text).replace(",", "."));
    return isNaN(v) || v <= 0 ? 3.0 : v;
  }

  function wykonaj(zapisz) {
    if (typeof CAD === "undefined")
      return;
    zajety = true;
    const w = CAD.dociagnijOpisy(qgisProject, promien(), zapisz);
    zajety = false;
    console.log("WFG CAD.dociagnijOpisy: " + JSON.stringify(w));
    if (w.blad) {
      stan = w.blad;
      policzone = false;
      return;
    }
    if (!zapisz) {
      policzone = w.dopasowane > 0;
      stan = w.dopasowane > 0
             ? qsTr("Znaleziono %1 wartości — %2.\nSymboli bez warstwy z wartościami: %3.")
               .arg(w.dopasowane).arg(w.kolumny).arg(w.bezWartosci)
             : qsTr("Nic nie pasuje w promieniu %1 m. Spróbuj większego.").arg(promien());
      return;
    }
    if (typeof NarzedziaProjektu !== "undefined")
      NarzedziaProjektu.zapiszProjekt(qgisProject);
    oknoOpisowCAD.close();
    displayToast(qsTr("Wpisano %1 wartości do warstwy symboli").arg(w.wpisane !== undefined ? w.wpisane : w.dopasowane));
  }

  onOpened: {
    stan = "";
    policzone = false;
  }

  parent: mainWindow.contentItem
  width: Math.min(460, mainWindow.width - 24)
  x: (mainWindow.width - width) / 2
  y: Math.max(12, (mainWindow.height - height) / 3)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  background: Rectangle {
    color: oknoOpisowCAD.t.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: oknoOpisowCAD.t.controlBorderColor
  }

  contentItem: ColumnLayout {
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Dociągnij opisy z rysunku")
      font: oknoOpisowCAD.t.strongFont
      color: oknoOpisowCAD.t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Rzędne i opisy stoją w rysunku jako osobne teksty — na warstwach „…-Atr2” i „…_O”, nazwanych po warstwie symbolu. Każdy tekst zostanie użyty raz, dla najbliższego symbolu.")
      font: oknoOpisowCAD.t.tinyFont
      color: oknoOpisowCAD.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        text: qsTr("Szukaj w promieniu [m]")
        font: oknoOpisowCAD.t.tipFont
        color: oknoOpisowCAD.t.mainTextColor
      }

      TextField {
        id: polePromienia

        Layout.preferredWidth: 70
        text: "3"
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        font.pointSize: oknoOpisowCAD.t.tipFont.pointSize
        onTextChanged: oknoOpisowCAD.policzone = false
      }

      Item {
        Layout.fillWidth: true
      }
    }

    Text {
      Layout.fillWidth: true
      visible: oknoOpisowCAD.stan !== ""
      text: oknoOpisowCAD.stan
      font: oknoOpisowCAD.t.tipFont
      color: oknoOpisowCAD.policzone ? oknoOpisowCAD.t.mainTextColor : oknoOpisowCAD.t.warningColor
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Wypełniane są tylko puste pola — to, co wpisano w terenie, zostaje.")
      font: oknoOpisowCAD.t.tinyFont
      color: oknoOpisowCAD.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true

      BusyIndicator {
        implicitWidth: 20
        implicitHeight: 20
        running: oknoOpisowCAD.zajety
        visible: running
      }

      Item {
        Layout.fillWidth: true
      }

      Button {
        text: qsTr("Zamknij")
        font.pointSize: oknoOpisowCAD.t.tinyFont.pointSize
        onClicked: oknoOpisowCAD.close()
      }

      Button {
        text: qsTr("Policz")
        font.pointSize: oknoOpisowCAD.t.tinyFont.pointSize
        enabled: !oknoOpisowCAD.zajety
        onClicked: oknoOpisowCAD.wykonaj(false)
      }

      Button {
        text: qsTr("Zapisz")
        font.pointSize: oknoOpisowCAD.t.tinyFont.pointSize
        highlighted: true
        enabled: !oknoOpisowCAD.zajety && oknoOpisowCAD.policzone
        onClicked: oknoOpisowCAD.wykonaj(true)
      }
    }
  }
}
