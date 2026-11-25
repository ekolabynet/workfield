import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qgis
import org.qfield
import org.qfield.gui // QfWindowFrame
import Theme

/**
 * \ingroup qml
 *
 * WorkFieldGIS 24.11.2026 [WF-QC-OPTIONS] — ustawienia paska szybkiego zapisu
 * w jednym oknie. Piotr 22:48: „wyraźne ustawienie w panelu Narzędzia, jako
 * osobny duży punkt”, do tego zębatka na samym pasku — oba otwierają to okno.
 *
 * Krawędź i rozmiar kafli są ustawieniem TEGO urządzenia (QSettings) i mają
 * pierwszeństwo przed sekcją „ustawienia” pliku workfield_klawisze.json
 * projektu; „Jak w projekcie” wraca do pliku. Same kafle (warstwy, litery,
 * kolory) zostają w pliku projektu — edytuje je okno „Klawisze szybkiego zapisu”.
 */
QfWindowFrame {
  id: options

  title: qsTr("Pasek szybkiego zapisu")
  exitMode: "close"
  preferredWidth: 460
  backgroundColor: "#EE263238"
  titleBarColor: "#263238"
  titleTextColor: "#80CBC4"
  borderColor: "#455A64"

  readonly property bool onPhone: Qt.platform.os === "android" || Qt.platform.os === "ios"
  readonly property string visibilityKey: onPhone ? "WorkField/quickCaptureNaTelefonie" : "WorkField/quickCaptureNaKomputerze"
  readonly property bool barShown: onPhone ? quickCaptureBar.naTelefonie : quickCaptureBar.naKomputerze

  function openOptions() {
    visible = true;
  }

  function setBarShown(on) {
    settings.setValue(visibilityKey, on);
    if (onPhone)
      quickCaptureBar.naTelefonie = on;
    else
      quickCaptureBar.naKomputerze = on;
  }

  function setEdge(edge) {
    settings.setValue("WorkField/qcUserEdge", edge);
    quickCaptureBar.userEdge = edge;
  }

  function setTileSize(size) {
    settings.setValue("WorkField/qcUserTileSize", size);
    quickCaptureBar.userTileSize = size;
  }

  component SectionTitle: Text {
    Layout.fillWidth: true
    Layout.topMargin: 6
    color: "#80CBC4"
    font: Theme.strongTipFont
  }

  component Hint: Text {
    Layout.fillWidth: true
    color: "#B0BEC5"
    font: Theme.tinyFont
    wrapMode: Text.Wrap
  }

  component OptionSwitch: RowLayout {
    property alias checked: optionSwitch.checked
    property alias text: optionText.text
    signal toggled(bool on)
    Layout.fillWidth: true
    spacing: 8
    Switch {
      id: optionSwitch
      onToggled: parent.toggled(checked)
    }
    Text {
      id: optionText
      Layout.fillWidth: true
      color: "white"
      font: Theme.tipFont
      wrapMode: Text.Wrap
    }
  }

  // ── widoczność ───────────────────────────────────────────────
  SectionTitle {
    text: qsTr("Widoczność")
  }

  OptionSwitch {
    checked: options.barShown
    text: options.onPhone ? qsTr("Pokaż pasek na mapie") : qsTr("Pokaż pasek na mapie (na komputerze)")
    onToggled: on => options.setBarShown(on)
  }

  Hint {
    text: qsTr("Ukryty pasek przywrócisz tutaj: Narzędzia → Pasek szybkiego zapisu. Kafli w tym projekcie: %1.").arg(quickCaptureBar.resolvedLayers.length)
  }

  // ── położenie i rozmiar ──────────────────────────────────────
  SectionTitle {
    text: qsTr("Krawędź ekranu")
  }

  Flow {
    Layout.fillWidth: true
    spacing: 4

    Repeater {
      model: [
        { "value": "", "label": qsTr("Jak w projekcie") },
        { "value": "lewa", "label": qsTr("Lewa") },
        { "value": "prawa", "label": qsTr("Prawa") }
      ]

      delegate: RadioButton {
        required property var modelData
        text: modelData.label
        checked: quickCaptureBar.userEdge === modelData.value
        onClicked: options.setEdge(modelData.value)
      }
    }
  }

  SectionTitle {
    text: qsTr("Rozmiar kafli")
  }

  Flow {
    Layout.fillWidth: true
    spacing: 4

    Repeater {
      model: [
        { "value": 0, "label": qsTr("Jak w projekcie") },
        { "value": 44, "label": qsTr("Mały") },
        { "value": 56, "label": qsTr("Średni") },
        { "value": 72, "label": qsTr("Duży") },
        { "value": 88, "label": qsTr("Bardzo duży") }
      ]

      delegate: RadioButton {
        required property var modelData
        text: modelData.label
        checked: quickCaptureBar.userTileSize === modelData.value
        onClicked: options.setTileSize(modelData.value)
      }
    }
  }

  Hint {
    text: qsTr("Gdy kafle nie mieszczą się w pionie między górną belką a przyciskami mapy, pasek układa je w dwóch kolumnach, a gdy i to nie wystarcza — przewija się palcem. Strzałka i zębatka zostają zawsze na górze paska.")
  }

  // ── tryby ────────────────────────────────────────────────────
  SectionTitle {
    text: qsTr("Tryby paska")
  }

  OptionSwitch {
    checked: qfieldSettings.fastMode
    text: qsTr("Tryb szybki (błyskawica) — zapis bez formularza i potwierdzeń, kontekst z automatu")
    onToggled: on => qfieldSettings.fastMode = on
  }

  OptionSwitch {
    checked: quickCaptureBar.kotwicaTryb
    text: qsTr("Kotwica czasowa (KTW) — tap w marszu, punkt z pozycji z chwili tapnięcia")
    onToggled: on => quickCaptureBar.kotwicaTryb = on
  }

  OptionSwitch {
    checked: quickCaptureBar.distantMode
    text: qsTr("Tryb odległy (ODL) — następne zdjęcie z podaniem odległości do obiektu")
    onToggled: on => quickCaptureBar.distantMode = on
  }

  OptionSwitch {
    checked: quickCaptureBar.ustawieniaZwiniete
    visible: quickCaptureBar.qcSekcja === "zwijana"
    text: qsTr("Zwiń przyciski ustawień na pasku (błyskawica, ODL, KTW, +) — kafle zostają")
    onToggled: on => quickCaptureBar.ustawieniaZwiniete = on
  }

  // ── kafle ────────────────────────────────────────────────────
  SectionTitle {
    text: qsTr("Kafle")
  }

  QfButton {
    Layout.fillWidth: true
    text: qsTr("Edytuj kafle (warstwy, litery, kolory)")
    onClicked: {
      options.visible = false;
      captureSettings.openDialog();
    }
  }

  Hint {
    text: qsTr("Kafle zapisują się w pliku workfield_klawisze.json obok projektu i jadą z nim na inne urządzenia. Krawędź i rozmiar wybrane wyżej dotyczą tylko tego urządzenia.")
  }
}
