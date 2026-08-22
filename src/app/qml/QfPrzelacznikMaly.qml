import QtQuick
import Theme

/**
 * WorkField 22.08.2026 — mały okrągły przełącznik do list ustawień.
 *
 * Zastępuje QfSwitch, który jest SwitchDelegate — a więc niesie ze sobą
 * wyściółkę pozycji listy (kilkanaście pikseli u góry i u dołu). To ona,
 * nie sam suwak, pogrubiała każdy wiersz ustawień.
 *
 * Kółko może być małe, bo celem palca jest CAŁY WIERSZ: etykieta ma pod
 * spodem MouseArea, która przełącza. W rękawicy trafia się w wiersz,
 * nie w suwak — więc rozmiar kontrolki jest sprawą czytelności, nie celu.
 *
 * Zgodność z QfSwitch: te same `checked`, `toggle()` i sygnał zmiany,
 * więc podmiana w miejscu użycia jest jednolinijkowa.
 */
Item {
  id: control

  // `checked` jest tylko ODCZYTEM stanu — komponent go nie zmienia. Gdyby
  // zmieniał, zerwałby wiązanie z ustawieniem i przestał za nim nadążać,
  // kiedy ktoś przestawi je z innego miejsca. Właściciel wiersza reaguje
  // na `przelaczono` i zapisuje wartość u siebie.
  property bool checked: false
  property bool enabled: true

  signal przelaczono

  function toggle() {
    if (control.enabled)
      control.przelaczono();
  }

  implicitWidth: 26
  implicitHeight: 26
  opacity: control.enabled ? 1.0 : 0.4

  Rectangle {
    id: obwodka
    anchors.centerIn: parent
    width: 22
    height: 22
    radius: width / 2
    color: control.checked ? Theme.mainColor : "transparent"
    border.color: control.checked ? Theme.mainColor : Theme.controlBorderColor
    border.width: 2

    Behavior on color {
      ColorAnimation {
        duration: 120
      }
    }

    // Ptaszek rysowany dwiema kreskami — mniejszy plik niż ikona i skaluje
    // się z kółkiem.
    Canvas {
      anchors.fill: parent
      visible: control.checked
      onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.strokeStyle = Theme.mainOverlayColor;
        ctx.lineWidth = 2.4;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(width * 0.28, height * 0.52);
        ctx.lineTo(width * 0.44, height * 0.68);
        ctx.lineTo(width * 0.74, height * 0.34);
        ctx.stroke();
      }
      onVisibleChanged: requestPaint()
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: control.toggle()
  }
}
