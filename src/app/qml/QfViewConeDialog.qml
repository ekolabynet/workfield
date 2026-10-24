import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield.core
import org.qfield.gui
import Theme

/**
 * \ingroup qml
 *
 * WorkField 24.10.2026 [WF-VIEW-CONE] — the view cone of a photo just taken:
 * shown on the map, confirmed ("Zgadza się"), corrected ("Popraw kierunek":
 * drag on the map towards where the camera looked) or skipped ("Pomiń").
 * Every answer saves the cone to WF_VIEW_CONES: confirmed or not, so the
 * evidence of what the phone measured is never lost.
 *
 * Decisions: claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md, section 7.
 */
QfDialog {
  id: viewConeDialog

  //! geometryWrapper of the renderer that draws the cone on the map
  property var renderer: null
  property var mapSettings: null

  property var layer: null
  property var photo: ({})
  property var sensor: ({})
  property var cone: ({})
  property bool correcting: false
  //! where the camera stood, in map CRS — the correction overlay aims from it
  property var standPoint: cone && cone.stand ? cone.stand : null
  property real pendingAzimuth: NaN

  parent: mainWindow.contentItem
  z: 10000
  width: Math.min(mainWindow.width - 24, 420)
  y: Math.max(12, mainWindow.height - height - Math.max(72, mainWindow.height * 0.1))
  dim: false
  modal: false
  closePolicy: Popup.NoAutoClose
  standardButtons: Dialog.NoButton
  title: qsTr("Stożek widoku")

  function absolutePath() {
    return qgisProject.homePath + "/" + photo.path;
  }

  //! Builds the cone; with \a azimuth the direction set by hand.
  function build(azimuth) {
    try {
      const built = azimuth === undefined ? ViewConeUtils.buildCone(layer, absolutePath(), sensor, mapSettings.destinationCrs) : ViewConeUtils.buildCone(layer, absolutePath(), sensor, mapSettings.destinationCrs, azimuth);
      return built;
    } catch (e) {
      console.log("WorkField [WF-VIEW-CONE]: buildCone failed: " + e);
      return ({});
    }
  }

  function displayCone(newCone) {
    cone = newCone;
    if (renderer && cone.ok) {
      renderer.qgsGeometry = cone.geometry;
      renderer.crs = mapSettings.destinationCrs;
    }
  }

  //! Asks: the cone stays on the map until an answer.
  function offer(parentLayer, photoInfo, sensorInfo) {
    layer = parentLayer;
    photo = photoInfo;
    sensor = sensorInfo;
    correcting = false;
    const built = build();
    if (!built.ok) {
      console.log("WorkField [WF-VIEW-CONE]: no cone for " + photoInfo.path + ": " + built.reason);
      return;
    }
    displayCone(built);
    open();
  }

  //! Without asking (fast mode, series, setting "show"): saved as not confirmed.
  function saveQuietly(parentLayer, photoInfo, sensorInfo) {
    layer = parentLayer;
    photo = photoInfo;
    sensor = sensorInfo;
    const built = build();
    if (!built.ok) {
      console.log("WorkField [WF-VIEW-CONE]: no cone for " + photoInfo.path + ": " + built.reason);
      return null;
    }
    const result = ViewConeUtils.saveCone(parentLayer, built, photoInfo, false);
    console.log("WorkField [WF-VIEW-CONE]: " + result.message);
    return built;
  }

  //! From the correction overlay: the direction of the drag, true north.
  function aimAt(azimuth) {
    pendingAzimuth = (azimuth % 360 + 360) % 360;
    aimTimer.restart();
  }

  function finish(confirmed) {
    const result = ViewConeUtils.saveCone(layer, cone, photo, confirmed);
    displayToast(result.message, result.ok ? "info" : "warning");
    correcting = false;
    close();
  }

  onClosed: {
    correcting = false;
    if (renderer)
      renderer.clear();
  }

  // rebuilding reads the photo again — not on every pixel of the drag
  Timer {
    id: aimTimer
    interval: 80
    onTriggered: {
      const built = viewConeDialog.build(viewConeDialog.pendingAzimuth);
      if (built.ok)
        viewConeDialog.displayCone(built);
    }
  }

  function sourceText() {
    switch (cone.source) {
    case "photo":
      return qsTr("z aparatu, w chwili zdjęcia");
    case "sensor":
      return qsTr("z kompasu po powrocie z aparatu — sprawdź");
    case "manual":
      return qsTr("poprawiony ręcznie");
    default:
      return qsTr("nieznany — popraw ręcznie");
    }
  }

  function hitsText() {
    const hits = cone.hits || [];
    if (hits.length === 0)
      return qsTr("Stożek nie trafia w żaden obiekt warstwy %1.").arg(layer ? layer.name : "");
    const parts = [];
    for (let i = 0; i < hits.length && i < 4; i++)
      parts.push(qsTr("Nr %1 (%2%)").arg(hits[i].fid).arg(hits[i].share));
    return qsTr("Trafia w: %1").arg(parts.join(", "));
  }

  //! the photo hangs on one object, the cone points mostly at another
  function mismatchText() {
    const hits = cone.hits || [];
    if (hits.length === 0 || photo.parentFid === undefined)
      return "";
    if (hits[0].fid === photo.parentFid)
      return "";
    return qsTr("Uwaga: zdjęcie jest przypięte do Nr %1, a stożek trafia głównie w Nr %2.").arg(photo.parentFid).arg(hits[0].fid);
  }

  Column {
    width: viewConeDialog.availableWidth
    spacing: 6

    // grip: drag the dialog away from the cone
    Item {
      width: parent.width
      height: 24

      Rectangle {
        anchors.centerIn: parent
        width: 56
        height: 6
        radius: 3
        color: Theme.secondaryTextColor
      }

      MouseArea {
        property point pressPoint
        property point startPosition
        anchors.fill: parent
        cursorShape: Qt.SizeAllCursor
        onPressed: mouse => {
          pressPoint = mapToItem(viewConeDialog.parent, mouse.x, mouse.y);
          startPosition = Qt.point(viewConeDialog.x, viewConeDialog.y);
        }
        onPositionChanged: mouse => {
          const now = mapToItem(viewConeDialog.parent, mouse.x, mouse.y);
          viewConeDialog.x = Math.max(0, Math.min(mainWindow.width - viewConeDialog.width, startPosition.x + now.x - pressPoint.x));
          viewConeDialog.y = Math.max(0, Math.min(mainWindow.height - viewConeDialog.height, startPosition.y + now.y - pressPoint.y));
        }
      }
    }

    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      color: Theme.mainTextColor
      font: Theme.tipFont
      text: viewConeDialog.cone.ok ? qsTr("Kierunek %1° (%2), pochylenie %3°.").arg(Math.round(viewConeDialog.cone.azimuth)).arg(viewConeDialog.sourceText()).arg(Math.round(viewConeDialog.cone.pitch)) : ""
    }

    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      color: Theme.mainTextColor
      font: Theme.tipFont
      text: viewConeDialog.cone.ok ? viewConeDialog.hitsText() : ""
    }

    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      visible: text !== ""
      color: "#ff9800"
      font: Theme.tipFont
      text: viewConeDialog.cone.ok ? viewConeDialog.mismatchText() : ""
    }

    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      visible: viewConeDialog.correcting
      color: Theme.mainTextColor
      font.bold: true
      text: qsTr("Przeciągnij palcem po mapie od miejsca stania w stronę, w którą patrzył aparat.")
    }

    Flow {
      width: parent.width
      spacing: 8

      Button {
        text: viewConeDialog.correcting ? qsTr("Gotowe") : qsTr("Zgadza się")
        font: Theme.tipFont
        Component.onCompleted: viewConeDialog.pomalujPrzycisk(this, "#43a047")
        onClicked: viewConeDialog.finish(true)
      }

      Button {
        visible: !viewConeDialog.correcting
        text: qsTr("Popraw kierunek")
        font: Theme.tipFont
        onClicked: viewConeDialog.correcting = true
      }

      Button {
        text: qsTr("Pomiń")
        font: Theme.tipFont
        Component.onCompleted: viewConeDialog.pomalujPrzycisk(this, "#fb8c00")
        onClicked: viewConeDialog.finish(false)
      }
    }
  }
}
