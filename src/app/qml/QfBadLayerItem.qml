import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield.core
import org.qfield.app
import org.qfield.gui

/**
 * \ingroup qml
 */
Page {
  id: badLayerPage

  /**
   * WorkField 23.08.2026 — CZWARTA ODSLONA TEGO SAMEGO WZORCA.
   *
   * `Page` bez wlasnego tla bierze je ZE STYLU, a styl pulpitowy
   * (org.kde.desktop) rysuje jasny prostokat. Napisy i strzalka powrotu sa
   * w barwie motywu, czyli jasne — i znikaja. Tak wlasnie "okna nie dalo sie
   * zamknac": przycisk byl na miejscu, tylko bialy na bialym.
   */
  background: Rectangle {
    color: QfTheme.mainBackgroundColor
  }


  property alias model: table.model

  // [WF-BAD-LAYERS] What can be repaired: photo layers (ZAL_) and the rest.
  property var invalid: []
  readonly property int attachmentCount: invalid.filter(function (l) { return l.kind !== "other"; }).length
  readonly property int otherCount: invalid.length - attachmentCount

  function reload() {
    invalid = qgisProject && typeof NarzedziaProjektu !== "undefined" ? NarzedziaProjektu.invalidLayers(qgisProject) : [];
  }

  function finish(result, automatic) {
    const saved = result.ok && ProjectUtils.saveProject(qgisProject);
    displayToast((automatic ? qsTr("Naprawiono przy otwarciu projektu. ") : "") + result.opis + (result.ok && !saved ? " " + qsTr("Projektu NIE zapisano.") : ""), result.ok && saved ? "info" : "error");
    reload();
    if (invalid.length === 0)
      badLayerPage.visible = false;
  }

  onVisibleChanged: {
    if (visible)
      reloadTimer.restart();
  }

  Timer {
    id: autoRepairTimer
    interval: 800
    repeat: false
    onTriggered: {
      badLayerPage.reload();
      if (badLayerPage.invalid.length > 0 && badLayerPage.otherCount === 0) {
        badLayerPage.finish(NarzedziaProjektu.repairInvalidLayers(qgisProject, false), true);
        if (badLayerPage.invalid.length > 0)
          badLayerPage.visible = true;
      } else {
        badLayerPage.visible = true;
      }
    }
  }

  // the page shows up while the project is still loading — ask a moment later
  Timer {
    id: reloadTimer
    interval: 800
    repeat: false
    onTriggered: badLayerPage.reload()
  }

  padding: 5

  width: mainWindow.width
  height: mainWindow.height

  header: QfPageHeader {
    title: qsTr('Nie udało się wczytać części warstw')

    showBackButton: false
    showApplyButton: false
    showCancelButton: true

    topMargin: mainWindow.sceneTopMargin

    onFinished: badLayerPage.visible = false
  }

  ColumnLayout {
    anchors.margins: 8
    anchors.bottomMargin: 8 + mainWindow.sceneBottomMargin
    anchors.fill: parent
    Layout.margins: 0
    spacing: 10

    Label {
      Layout.fillWidth: true
      Layout.fillHeight: false

      text: qsTr("Poniższych warstw nie udało się wczytać. Pozostałe warstwy projektu działają normalnie.") + (badLayerPage.attachmentCount > 0 ? " " + qsTr("Warstwy zdjęć (ZAL_) bez tabeli naprawisz od razu: te, których warstwa już nie istnieje, zostaną usunięte z projektu, a brakujące tabele zdjęć zostaną założone na nowo.") : "") // [WF-BAD-LAYERS]
      font: Theme.defaultFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: QfTheme.controlBackgroundColor
      border.color: QfTheme.controlBorderColor
      border.width: 1

      ListView {
        id: table
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        spacing: 2
        anchors.fill: parent

        model: QfBadLayerHandler {
          project: qgisProject

          // [WF-NO-BANNER] Repair first: when only photo layers (ZAL_) failed, they are
          // repaired right away and a toast says what was done. The page shows up only
          // when something needs a decision.
          onBadLayersFound: {
            autoRepairTimer.restart();
          }
        }

        delegate: Rectangle {
          id: rectangle
          width: parent ? parent.width : undefined
          height: line.height
          color: "transparent"

          Column {
            id: line
            width: parent.width
            spacing: 0

            Text {
              id: name
              width: rectangle.width - padding * 2
              padding: 5
              text: LayerName
              font: QfTheme.strongTipFont
              color: QfTheme.mainTextColor
              wrapMode: Text.WordWrap
            }
            Text {
              id: uri
              width: rectangle.width - padding * 2
              padding: 5
              text: DataSource
              font: QfTheme.tipFont
              color: QfTheme.secondaryTextColor
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }

    Label {
      Layout.fillWidth: true
      Layout.fillHeight: false
      Layout.topMargin: 5

      text: qsTr('You may check the %1Portable Project%2 documentation page for more help.').arg("<a href=\"https://docs.qfield.org/how-to/project-setup/data_source_and_project_paths/\">").arg("</a>")
      textFormat: Text.RichText
      font: QfTheme.tipFont
      color: QfTheme.secondaryTextColor
      wrapMode: Text.WordWrap

      onLinkActivated: link => {
        Qt.openUrlExternally(link);
      }
    }

    // [WF-BAD-LAYERS] Piotr 23.10: "MUSI być SOLUTION" — the page repairs, not only lists.
    QfDecisionButton {
      role: "confirm"
      Layout.fillWidth: true
      Layout.topMargin: 5
      visible: badLayerPage.attachmentCount > 0
      text: qsTr("Napraw warstwy zdjęć (%1)").arg(badLayerPage.attachmentCount)
      font: Theme.defaultFont
      onClicked: badLayerPage.finish(NarzedziaProjektu.repairInvalidLayers(qgisProject, false))
    }

    QfDecisionButton {
      role: "danger"
      Layout.fillWidth: true
      visible: badLayerPage.otherCount > 0
      text: qsTr("Usuń z projektu wszystkie niewczytane (%1)").arg(badLayerPage.invalid.length)
      font: Theme.defaultFont
      onClicked: badLayerPage.finish(NarzedziaProjektu.repairInvalidLayers(qgisProject, true))
    }

    QfDecisionButton {
      role: "cancel"
      Layout.fillWidth: true
      text: qsTr("Wróć do projektu")
      font: Theme.defaultFont
      onClicked: badLayerPage.visible = false
    }
  }
}
