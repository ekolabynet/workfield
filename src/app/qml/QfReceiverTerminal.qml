import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.gui
import Theme

/**
 * WorkFieldGIS 24.10.2026 [WF-RECEIVER-TERMINAL] — a terminal to the GNSS receiver
 * over the connection the app already holds.
 *
 * Why: a Facet accepts ONE Bluetooth connection. To look into its stream or
 * enter its menu ("+++") one had to close WorkField and lose the position.
 * This window talks over the app's own link (positionSource.sendToDevice,
 * deviceRawLineReceived — [WF-RECEIVER-CHANNEL]).
 *
 * SparkFun RTK firmware (Facet, first version): "+++" after 2 s of silence opens
 * the text menu; the receiver stops sending NMEA until the menu is left, so the
 * position disappears meanwhile. NTRIP corrections are paused for the menu
 * (they are bytes too and would break the 2 s silence) and resumed on leaving.
 *
 * Battery: the first Facet does not send its battery over Bluetooth; the menu
 * shows it ("Batt (NN%)"). The steps are editable — the exact keys are to be
 * confirmed with the tester's manual session. SparkFun docs: "~" makes the
 * receiver send a system report "$GNTXT,01,01,05,…,<battery %>*CS" — read too.
 *
 * Facet menu (24.10, Piotr: "hierarchiczne menu dla SparkFun Facet 4.x"): the
 * buttons are built from what the receiver prints itself ("Menu: System",
 * "1) Configure GNSS Receiver", "s) System Status"…), so they always match its
 * firmware. Dangerous keys ask first: in the System menu "b" changes the
 * Bluetooth protocol (SPP → BLE: the phone loses the receiver), "r" is a
 * factory reset, WiFi hangs Piotr's Facet (no reset button).
 */
QfWindowFrame {
  id: terminal

  title: qsTr("Terminal odbiornika")
  exitMode: "close"
  scrollable: false
  // [WF-WINDOW-FRAME] smaller and resizable (Piotr 18:04); the size is remembered
  preferredWidth: 640
  preferredHeight: 620
  resizable: true
  sizeKey: "WorkField/terminalOdbiornika"
  // a phone: the whole screen, otherwise the input line falls off the window
  forceFullScreen: narrowScreen

  //! small coloured button: "" plain, "go" green, "leave" orange, "danger" red
  component Maly: Button {
    id: maly
    property string kolor: ""
    font.pointSize: Theme.tinyFont.pointSize
    topPadding: 8
    bottomPadding: 8
    leftPadding: 10
    rightPadding: 10
    opacity: enabled ? 1.0 : 0.45
    background: Rectangle {
      radius: 6
      color: maly.kolor === "go" ? "#43a047" : maly.kolor === "leave" ? "#fb8c00" : maly.kolor === "danger" ? "#e53935"
           : (maly.down || maly.checked ? Qt.darker(Theme.controlBackgroundColor, 1.25) : Theme.controlBackgroundColor)
      border.color: Theme.controlBorderColor
    }
    contentItem: Text {
      text: maly.text
      font: maly.font
      color: maly.kolor !== "" ? "white" : Theme.mainTextColor
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignHCenter
    }
  }

  property var lines: []
  property bool pokazNmea: false
  property bool dodajEnter: true
  property bool poprawkiWstrzymane: false
  property bool wMenu: false
  property string bateria: ""
  property string bateriaCzas: ""
  property var kroki: []
  property int krok: -1
  //! the receiver's current menu, read from its own text
  property string menuTytul: ""
  property var menuOpcje: []
  property var opcjaDoPotwierdzenia: null
  property bool edytujKroki: false
  readonly property int maxLinii: 600

  function otworz() {
    lines = [];
    open();
  }

  onOpened: positionSource.setDeviceRawTap(true)
  onClosed: {
    positionSource.setDeviceRawTap(false);
    zegarKrokow.stop();
    krok = -1;
    if (poprawkiWstrzymane) {
      positionSource.setCorrectionsPaused(false);
      displayToast(qsTr("Poprawki NTRIP wznowione"));
    }
    if (wMenu)
      displayToast(qsTr("Odbiornik może być jeszcze w menu — wyjdź z menu, żeby wróciła pozycja"), "warning");
  }

  function dopisz(tekst, zrodlo) {
    const l = lines.slice(Math.max(0, lines.length - maxLinii + 1));
    l.push({
      "t": tekst,
      "z": zrodlo
    });
    lines = l;
  }

  function wyslij(tekst, zEnterem) {
    const doWyslania = tekst + (zEnterem ? "\r\n" : "");
    positionSource.sendToDevice(doWyslania);
    dopisz("→ " + tekst + (zEnterem ? "⏎" : ""), "ja");
  }

  //! "+++" needs 2 s without any byte: pause corrections, wait, send
  function wejdzDoMenu() {
    wstrzymajPoprawki();
    dopisz(qsTr("(czekam 2 s ciszy…)"), "info");
    zegarMenu.start();
  }

  function wstrzymajPoprawki() {
    if (!poprawkiWstrzymane) {
      positionSource.setCorrectionsPaused(true);
      poprawkiWstrzymane = true;
    }
  }

  function wznowPoprawki() {
    if (poprawkiWstrzymane) {
      positionSource.setCorrectionsPaused(false);
      poprawkiWstrzymane = false;
      dopisz(qsTr("(poprawki NTRIP wznowione)"), "info");
    }
  }

  //! battery: a sequence of steps, e.g. "+++ ; s ; x ; b"
  function odczytajBaterie() {
    kroki = poleKrokow.text.split(";").map(k => k.trim()).filter(k => k !== "");
    if (kroki.length === 0)
      return;
    bateria = "";
    wstrzymajPoprawki();
    krok = 0;
    dopisz(qsTr("(bateria: %1 kroków, czekam 2 s ciszy…)").arg(kroki.length), "info");
    zegarKrokow.interval = 2200;
    zegarKrokow.start();
  }

  //! keys that can cut the phone off or wipe the receiver: ask first
  function grozna(opcja) {
    if (/reset|factory|protocol|wi-?fi|format|erase|delete|bootloader|firmware|update/i.test(opcja.label))
      return true;
    return /system/i.test(menuTytul) && (opcja.key === "b" || opcja.key === "r" || opcja.key === "W");
  }

  function wybierz(opcja) {
    if (grozna(opcja)) {
      opcjaDoPotwierdzenia = opcja;
      potwierdzenieOpcji.open();
      return;
    }
    wyslij(opcja.key, dodajEnter);
  }

  //! "Menu: X" starts a menu; "k) label" lines are its options
  function czytajMenu(line) {
    const m = /^\s*Menu:\s*(.+?)\s*$/i.exec(line);
    if (m) {
      menuTytul = m[1];
      menuOpcje = [];
      return;
    }
    const o = /^\s*([0-9]{1,2}|[A-Za-z~])\)\s+(.+?)\s*$/.exec(line);
    if (o && menuTytul !== "") {
      const l = menuOpcje.filter(x => x.key !== o[1]);
      l.push({
        "key": o[1],
        "label": o[2]
      });
      menuOpcje = l;
    }
  }

  Connections {
    target: positionSource

    function onDeviceRawLineReceived(line) {
      const nmea = line.length > 0 && line[0] === "$";
      // system report "~": $GNTXT,01,01,05,…,battery*CS
      const raport = /^\$G.TXT,\d+,\d+,05,(.*)\*[0-9A-Fa-f]{2}$/.exec(line);
      if (raport) {
        const pola = raport[1].split(",");
        const proc = parseInt(pola[pola.length - 1]);
        if (!isNaN(proc) && proc >= 0 && proc <= 100) {
          terminal.bateria = proc + "%";
          terminal.bateriaCzas = new Date().toLocaleTimeString(Qt.locale(), "HH:mm");
          settings.setValue("WorkField/odbiornikBateria", terminal.bateria + " " + terminal.bateriaCzas);
        }
        terminal.dopisz(qsTr("raport stanu: dokładność %1 m, satelitów %2, bateria %3%").arg(pola[2] || "?").arg(pola[3] || "?").arg(pola[pola.length - 1]), "info");
      }
      if (!nmea)
        terminal.czytajMenu(line);
      if (!nmea)
        terminal.wMenu = terminal.wMenu || /menu|choice|option|exit/i.test(line);
      if (nmea && /^\$G[NPLAB]G[GL]A/.test(line)) {
        terminal.wMenu = false; // position sentences are back: the menu is closed
        terminal.menuTytul = "";
        terminal.menuOpcje = [];
      }
      const b = /Batt[^0-9]*\(?\s*(\d{1,3})\s*%/i.exec(line);
      if (b) {
        terminal.bateria = b[1] + "%";
        terminal.bateriaCzas = new Date().toLocaleTimeString(Qt.locale(), "HH:mm");
        settings.setValue("WorkField/odbiornikBateria", terminal.bateria + " " + terminal.bateriaCzas);
      }
      if (nmea && !terminal.pokazNmea)
        return;
      terminal.dopisz(line, nmea ? "nmea" : "odb");
    }

    function onCorrectionsPausedChanged(paused) {
      terminal.poprawkiWstrzymane = paused;
    }
  }

  Timer {
    id: zegarMenu
    interval: 2200
    onTriggered: {
      positionSource.sendToDevice("+++");
      terminal.dopisz("→ +++", "ja");
      terminal.wMenu = true;
    }
  }

  Timer {
    id: zegarKrokow
    onTriggered: {
      if (terminal.krok < 0 || terminal.krok >= terminal.kroki.length) {
        terminal.krok = -1;
        return;
      }
      const k = terminal.kroki[terminal.krok];
      if (k === "+++") {
        positionSource.sendToDevice("+++");
        terminal.dopisz("→ +++", "ja");
        terminal.wMenu = true;
      } else {
        terminal.wyslij(k, terminal.dodajEnter);
      }
      terminal.krok++;
      if (terminal.krok < terminal.kroki.length) {
        interval = 1500;
        start();
      } else {
        terminal.krok = -1;
        terminal.dopisz(qsTr("(kroki wysłane; gdy wróci pozycja — „Wznów poprawki”)"), "info");
      }
    }
  }

  // ── status (one line, the warning in orange) ─────────────────────────────
  Text {
    Layout.fillWidth: true
    text: (positionSource.deviceId === "" ? qsTr("Odbiornik wewnętrzny (telefon) — terminal działa tylko z odbiornikiem zewnętrznym.")
                                          : qsTr("%1 — %2").arg(positionSource.deviceId).arg(positionSource.deviceSocketStateString))
          + (terminal.wMenu ? qsTr("  ·  w menu: bez pozycji") : "")
          + (terminal.poprawkiWstrzymane ? qsTr("  ·  poprawki wstrzymane") : "")
          + (terminal.bateria !== "" ? qsTr("  ·  bateria %1 (%2)").arg(terminal.bateria).arg(terminal.bateriaCzas) : "")
    font: Theme.tipFont
    color: terminal.wMenu || terminal.poprawkiWstrzymane ? "#fb8c00" : Theme.mainTextColor
    wrapMode: Text.WordWrap
  }

  // ── shortcuts (SparkFun RTK Firmware 3.x / 4.x) ──────────────────────────
  Flow {
    Layout.fillWidth: true
    spacing: 4

    Maly {
      kolor: "go"
      text: qsTr("Menu (+++)")
      enabled: positionSource.deviceId !== "" && !zegarMenu.running && terminal.krok < 0
      onClicked: terminal.wejdzDoMenu()
    }
    Maly {
      text: qsTr("Bateria")
      enabled: positionSource.deviceId !== "" && terminal.krok < 0 && !zegarMenu.running
      onClicked: terminal.odczytajBaterie()
    }
    Maly {
      text: "⚙"
      checkable: true
      checked: terminal.edytujKroki
      onToggled: terminal.edytujKroki = checked
    }
    Maly {
      text: qsTr("Raport (~)")
      onClicked: terminal.wyslij("~", false)
    }
    Maly {
      kolor: "leave"
      text: qsTr("Wyjdź z menu (x)")
      onClicked: terminal.wyslij("x", terminal.dodajEnter)
    }
    Maly {
      kolor: "leave"
      text: qsTr("Koniec echo (b)")
      // 'b' leaves Bluetooth echo ONLY from the main menu; in System it switches SPP→BLE
      enabled: /main/i.test(terminal.menuTytul)
      onClicked: terminal.wyslij("b", terminal.dodajEnter)
    }
    Maly {
      text: terminal.poprawkiWstrzymane ? qsTr("Wznów poprawki") : qsTr("Wstrzymaj poprawki")
      onClicked: terminal.poprawkiWstrzymane ? terminal.wznowPoprawki() : terminal.wstrzymajPoprawki()
    }
    Maly {
      text: qsTr("Wyczyść")
      onClicked: terminal.lines = []
    }
    Maly {
      text: qsTr("NMEA")
      checkable: true
      checked: terminal.pokazNmea
      onToggled: terminal.pokazNmea = checked
    }
  }

  // ── the receiver's menu as buttons, built from its own text ─────────────
  Rectangle {
    Layout.fillWidth: true
    visible: terminal.menuOpcje.length > 0
    implicitHeight: menuKolumna.implicitHeight + 12
    radius: 6
    color: Qt.alpha(Theme.mainColor, 0.12)
    border.color: Qt.alpha(Theme.mainColor, 0.5)

    ColumnLayout {
      id: menuKolumna
      anchors.fill: parent
      anchors.margins: 6
      spacing: 4

      Text {
        Layout.fillWidth: true
        text: qsTr("Menu Faceta: %1").arg(terminal.menuTytul)
        font: Theme.strongTipFont
        color: Theme.mainTextColor
      }
      Flow {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
          model: terminal.menuOpcje

          delegate: Maly {
            required property var modelData
            kolor: terminal.grozna(modelData) ? "danger" : modelData.key === "x" ? "leave" : ""
            text: modelData.key + ")  " + modelData.label
            onClicked: terminal.wybierz(modelData)
          }
        }
      }
    }
  }

  QfDialog {
    id: potwierdzenieOpcji
    parent: mainWindow.contentItem
    title: terminal.opcjaDoPotwierdzenia ? qsTr("Wysłać „%1) %2”?").arg(terminal.opcjaDoPotwierdzenia.key).arg(terminal.opcjaDoPotwierdzenia.label) : ""
    confirmRole: "danger"
    width: Math.min(420, mainWindow.width - 32)

    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      color: Theme.mainTextColor
      text: qsTr("Ta opcja może odciąć telefon od odbiornika (zmiana protokołu Bluetooth, WiFi) albo skasować jego ustawienia. Facet nie ma przycisku resetu — gdy się zawiesi, trzeba czekać, aż rozładuje się bateria.")
    }

    onAccepted: {
      if (terminal.opcjaDoPotwierdzenia)
        terminal.wyslij(terminal.opcjaDoPotwierdzenia.key, terminal.dodajEnter);
      terminal.opcjaDoPotwierdzenia = null;
    }
    onRejected: terminal.opcjaDoPotwierdzenia = null
  }

  // ── battery steps (editable, hidden until needed) ─────────────────────────
  RowLayout {
    Layout.fillWidth: true
    visible: terminal.edytujKroki
    spacing: 6

    Text {
      text: qsTr("Kroki baterii:")
      font: Theme.tipFont
      color: Theme.mainTextColor
    }
    TextField {
      id: poleKrokow
      Layout.fillWidth: true
      text: settings.value("WorkField/odbiornikKrokiBaterii", "+++ ; s ; x ; b")
      placeholderText: qsTr("kroki rozdzielone średnikiem")
      font: Theme.tipFont
      onEditingFinished: settings.setValue("WorkField/odbiornikKrokiBaterii", text)
    }
  }

  // ── output ──────────────────────────────────────────────────────────────
  Rectangle {
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 120
    color: "#11181c"
    radius: 4
    border.color: Theme.controlBorderColor

    ListView {
      id: wyjscie
      anchors.fill: parent
      anchors.margins: 6
      clip: true
      model: terminal.lines
      onCountChanged: positionViewAtEnd()
      ScrollBar.vertical: QfScrollBar {
      }

      delegate: Text {
        required property var modelData
        width: ListView.view.width
        text: modelData.t
        font.family: "monospace"
        font.pointSize: Theme.tinyFont.pointSize
        wrapMode: Text.WrapAnywhere
        color: modelData.z === "ja" ? "#80CBC4" : modelData.z === "info" ? "#FFB74D" : modelData.z === "nmea" ? "#78909C" : "#ECEFF1"
      }
    }
  }

  // ── input ───────────────────────────────────────────────────────────────
  RowLayout {
    Layout.fillWidth: true
    spacing: 6

    TextField {
      id: poleWysylania
      Layout.fillWidth: true
      placeholderText: qsTr("polecenie dla odbiornika")
      font.family: "monospace"
      inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
      onAccepted: {
        terminal.wyslij(text, terminal.dodajEnter);
        text = "";
      }
    }
    CheckBox {
      text: qsTr("+ Enter")
      checked: terminal.dodajEnter
      onToggled: terminal.dodajEnter = checked
    }
    QfDecisionButton {
      role: "confirm"
      text: qsTr("Wyślij")
      enabled: poleWysylania.text !== "" && positionSource.deviceId !== ""
      onClicked: {
        terminal.wyslij(poleWysylania.text, terminal.dodajEnter);
        poleWysylania.text = "";
      }
    }
  }
}
