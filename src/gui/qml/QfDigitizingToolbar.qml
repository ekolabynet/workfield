import QtQuick
import QtQuick.Controls
import org.qgis
import org.qfield.core
import org.qfield.gui

/**
 * \ingroup qml
 */
QfVisibilityFadingRow {
  id: digitizingToolbar

  property QfRubberbandModel rubberbandModel
  property MapSettings mapSettings

  property bool cogoEnabled: false
  property var cogoOperationSettings: undefined
  property alias cogoExecutor: cogoExecutor

  property bool showConfirmButton: true //<! if the geometry type is point, it will never be shown
  //! [WF-FIXED-RECT] A rectangle of a fixed size needs one point (its centre),
  //! so the check mark shows up after the first tap.
  property bool onePointShape: false
  onOnePointShapeChanged: checkGeometryValidity()
  property bool screenHovering: false //<! if the stylus pen is used, one should not use the add button

  property bool geometryRequested: false
  property var geometryRequestedItem
  property VectorLayer geometryRequestedLayer

  property alias digitizingLogger: digitizingLogger
  property alias cancelDialog: cancelDialog

  readonly property bool isDigitizing: rubberbandModel ? rubberbandModel.vertexCount > 1 : false //!< Readonly

  property bool geometryValid: false

  signal requestJumpToPoint(var center, real scale, bool handleMargins)
  signal requestPosition(var item, bool fromCoordinateLocator)

  spacing: 16

  /* This signal is emitted when the digitized geometry has been confirmed.
   * The correspoding handler is \c onConfirmed.
   */
  signal confirmed
  /* This signal is emitted when the user cancels geometry digitizing.
   * The correspoding handler is \c onCancel.
   */
  signal cancel
  signal vertexCountChanged

  Connections {
    target: rubberbandModel

    function onVertexCountChanged() {
      // check whether geometry is valid and can be confirmed
      checkGeometryValidity();

      // emit the signal of digitizingToolbar
      vertexCountChanged();
    }
  }

  QfDigitizingLogger {
    id: digitizingLogger

    project: qgisProject
    mapSettings: digitizingToolbar.mapSettings
    digitizingLayer: rubberbandModel ? rubberbandModel.vectorLayer : null

    positionInformation: positionSource.positionInformation
    positionLocked: coordinateLocator.positionLocked
    topSnappingResult: coordinateLocator.topSnappingResult
    cloudUserInformation: projectInfo.cloudUserInformation
  }

  QfToolButton {
    id: cancelButton

    width: Math.round(44 * skalaPrzyciskow)
    height: width
    iconSource: Theme.getThemeVectorIcon("ic_clear_white_24dp")
    visible: rubberbandModel && rubberbandModel.vertexCount > 1
    round: true
    bgcolor: QfTheme.darkRed

    onClicked: {
      // WorkField: średni impuls — anulowanie
      haptyka(30);
      if (typeof dzwieki !== "undefined")
        dzwieki.zagraj("anuluj", false); // [WF-SOUNDS]
      dashBoard.shouldReturnHome = false;
      if (stateMachine.state !== "measure") {
        cancelDialog.open();
      } else {
        digitizingLogger.clearCoordinates();
        rubberbandModel.reset();
        cancel();
      }
    }
  }

  QfToolButton {
    id: confirmButton

    width: Math.round(56 * skalaPrzyciskow)
    height: width
    iconSource: Theme.getThemeVectorIcon("ic_check_white_24dp")
    visible: {
      if (!showConfirmButton) {
        false;
      } else {
        geometryValid;
      }
    }
    round: true
    bgcolor: !enabled ? QfTheme.toolButtonBackgroundSemiOpaqueColor : QfTheme.mainColor

    onClicked: {
      dashBoard.shouldReturnHome = false;
      confirm();
    }
  }

  QfCogoOperations {
    id: cogoOperations
    enabled: digitizingToolbar.cogoEnabled

    mapSettings: digitizingToolbar.mapSettings
    cogoOperationSettings: digitizingToolbar.cogoOperationSettings

    onEnabledChanged: {
      digitizingToolbar.cogoOperationSettings.visible = enabled;
      checkGeometryValidity();
    }

    onRequestJumpToPoint: function (center, scale, handleMargins) {
      digitizingToolbar.requestJumpToPoint(center, scale, handleMargins);
    }

    onRequestPosition: function (item, fromCoordinateLocator) {
      digitizingToolbar.requestPosition(item, fromCoordinateLocator);
    }

    QfCogoExecutor {
      id: cogoExecutor

      name: digitizingToolbar.cogoOperationSettings ? digitizingToolbar.cogoOperationSettings.name : ""
      parameterValues: digitizingToolbar.cogoOperationSettings ? digitizingToolbar.cogoOperationSettings.parameterValues : {}

      mapSettings: digitizingToolbar.mapSettings
      rubberbandModel: digitizingToolbar.rubberbandModel

      onParametersChanged: {
        cogoOperationSettings.parameters = parameters;
        cogoOperationSettings.clear();
      }
    }
  }

  Timer {
    id: removeVertexTimer
    interval: 700
    repeat: true

    onTriggered: {
      if (!rubberbandModel || rubberbandModel.vertexCount === 0) {
        stop();
      }
      removeVertex();
      if (interval > 100)
        interval = interval * 0.8;
    }
  }

  QfToolButton {
    id: removeVertexButton

    width: Math.round(48 * skalaPrzyciskow)
    height: width
    iconSource: Theme.getThemeVectorIcon("ic_remove_white_24dp")
    iconColor: Theme.toolButtonColor
    visible: rubberbandModel && rubberbandModel.vertexCount > 1
    round: true
    bgcolor: QfTheme.toolButtonBackgroundColor

    onPressed: {
      removeVertex();
      removeVertexTimer.interval = 700;
      removeVertexTimer.restart();
    }
    onReleased: {
      removeVertexTimer.stop();
    }
    onCanceled: {
      removeVertexTimer.stop();
    }
  }

  QfToolButton {
    id: addVertexButton
    round: true
    width: Math.round(72 * skalaPrzyciskow)
    height: width
    enabled: (cogoEnabled && cogoExecutor.isReady) || (!cogoEnabled && !screenHovering)
    // WorkField: sygnałowa czerwień dla widoczności w terenie (rękawice, słońce);
    // celowo jaśniejsza niż Theme.darkRed przycisku anulowania
    bgcolor: enabled ? "#d32f2f" : Theme.toolButtonBackgroundSemiOpaqueColor
    iconSource: Theme.getThemeVectorIcon("ic_add_white_24dp")
    iconColor: enabled ? Theme.toolButtonColor : Theme.toolButtonBackgroundSemiOpaqueColor

    property bool lastAdditionAveraged: false
    property bool averagedPositionPressAndHeld: false
    property bool averagedPositionAutoRelease: false

    Connections {
      target: positionSource

      function onAveragedPositionCountChanged() {
        if (addVertexButton.averagedPositionAutoRelease && positionSource.averagedPosition && positionSource.averagedPositionCount >= positioningSettings.averagedPositioningMinimumCount && positioningSettings.averagedPositioningAutomaticStop) {
          addVertexButton.averagedPositionPressAndHeld = true;
          addVertexButton.released();
        }
      }
    }

    onPressAndHold: {
      if (!cogoEnabled && coordinateLocator && coordinateLocator.positionLocked) {
        if (!checkAccuracyRequirement()) {
          return;
        }
        averagedPositionPressAndHeld = true;
        positionSource.averagedPosition = true;
      }
    }

    onReleased: {
      if (!averagedPositionPressAndHeld) {
        return;
      }
      averagedPositionPressAndHeld = false;
      averagedPositionAutoRelease = false;
      if (coordinateLocator && coordinateLocator.positionLocked) {
        if (positioningSettings.averagedPositioning && positioningSettings.averagedPositioningMinimumCount > positionSource.averagedPositionCount) {
          displayToast(qsTr("The collected positions count does not meet the requirement"), 'warning');
          positionSource.averagedPosition = false;
          return;
        }
        if (!checkAccuracyRequirement()) {
          positionSource.averagedPosition = false;
          return;
        }
        lastAdditionAveraged = true;
        addVertex();
        if (Number(rubberbandModel.geometryType) === Qgis.GeometryType.Point || Number(rubberbandModel.geometryType) === Qgis.GeometryType.Null) {
          confirm();
        }
        positionSource.averagedPosition = false;
      }
    }

    onCanceled: {
      if (coordinateLocator.positionLocked) {
        positionSource.averagedPosition = false;
      }
    }

    onClicked: {
      if (cogoEnabled) {
        if (cogoExecutor.isReady) {
          const success = cogoExecutor.execute();
          if (success) {
            cogoOperationSettings.clear();
            // Recenter to last added vertex
            mapSettings.setCenter(rubberbandModel.lastCoordinate, true);
            if (Number(rubberbandModel.geometryType) === Qgis.GeometryType.Point) {
              confirm();
            }
          }
        }
        return;
      }
      if (!checkAccuracyRequirement()) {
        return;
      }
      if (coordinateLocator && coordinateLocator.positionLocked && positioningSettings.averagedPositioning && (positioningSettings.averagedPositioningMinimumCount > 1 || !positioningSettings.averagedPositioningAutomaticStop)) {
        if (!positionSource.averagedPosition) {
          averagedPositionAutoRelease = true;
          positionSource.averagedPosition = true;
        } else {
          addVertexButton.averagedPositionPressAndHeld = true;
          addVertexButton.released();
        }
        return;
      }
      lastAdditionAveraged = false;
      // [WF-GNSS-SNAP] First GNSS vertex near an existing one in this session:
      // ask first, then take the point (snapped or not, as answered).
      digitizingToolbar.withGnssSnapDecision(function () {
        if (Number(rubberbandModel.geometryType) === Qgis.GeometryType.Point || Number(rubberbandModel.geometryType) === Qgis.GeometryType.Null) {
          confirm();
        } else {
          addVertex();
        }
      });
    }
  }

  // [WF-GNSS-SNAP] "Dociągać pomiar RTK do istniejących wierzchołków?" — asked once
  // per session, at the first GNSS vertex that has an existing vertex in tolerance.
  QfDialog {
    id: gnssSnapQuestion

    property var pendingAction: null
    property string detail: ""

    parent: mainWindow.contentItem
    width: Math.min(420, mainWindow.width - 32)
    closePolicy: Popup.NoAutoClose
    title: qsTr("Dociągać pomiar RTK?")
    standardButtons: Dialog.Yes | Dialog.No

    onOpened: {
      const yesButton = standardButton(Dialog.Yes);
      if (yesButton)
        yesButton.text = qsTr("Tak, w tej sesji");
      const noButton = standardButton(Dialog.No);
      if (noButton)
        noButton.text = qsTr("Nie");
    }

    function decide(snap) {
      coordinateLocator.gnssSnapSession = snap ? 1 : 0;
      if (gnssSnapRemember.checked) {
        settings.setValue('WorkField/snapGnssPosition', snap);
        settings.setValue('WorkField/snapGnssAsk', false);
        if (typeof qfieldSettings !== "undefined" && qfieldSettings) {
          qfieldSettings.snapGnssPosition = snap;
          qfieldSettings.snapGnssAsk = false;
        }
      }
      gnssSnapRemember.checked = false;
      const action = pendingAction;
      pendingAction = null;
      if (action)
        action();
    }

    onAccepted: decide(true)
    onRejected: decide(false)

    Column {
      width: parent.width
      spacing: 8

      Label {
        width: parent.width
        wrapMode: Text.WordWrap
        text: gnssSnapQuestion.detail + "\n\n" + qsTr("Dociągać pomiar z odbiornika do istniejących wierzchołków w tej sesji? „Nie” — punkt zostaje tam, gdzie zmierzono.")
      }

      CheckBox {
        id: gnssSnapRemember
        width: parent.width
        text: qsTr("Zapamiętaj (zmienisz w Ustawienia → Teren)")
      }
    }
  }

  //! [WF-GNSS-SNAP] "8 cm" / "1.25 m".
  function distanceText(d) {
    return d < 1 ? qsTr("%1 cm").arg(Math.round(d * 100)) : qsTr("%1 m").arg(d.toFixed(2));
  }

  //! [WF-SOUNDS] Vertex taken: a short tick; with the position locked to the
  //! receiver and no RTK FIX — a warning sound and one sentence instead.
  function zagrajWierzcholek() {
    if (typeof dzwieki === "undefined")
      return;
    const pi = positionSource.positionInformation;
    if (coordinateLocator && coordinateLocator.gnssLocked && pi && pi.quality > 0 && pi.quality !== 4) {
      dzwieki.zdarzenie("bezFix", qsTr("Punkt zapisany BEZ FIX (%1) — sprawdź go później.").arg(pi.quality === 5 ? "FLOAT" : (pi.quality === 2 ? "DGPS" : qsTr("pozycja pojedyncza"))), "warning");
      return;
    }
    dzwieki.zagraj("wierzcholek", false);
  }

  //! [WF-GNSS-SNAP] Run `action` now, or after the session question.
  function withGnssSnapDecision(action) {
    if (coordinateLocator && coordinateLocator.gnssLocked && coordinateLocator.gnssSnapDistance >= 0 && coordinateLocator.gnssSnapSession < 0 && coordinateLocator.snapGnssAsk) {
      gnssSnapQuestion.pendingAction = action;
      gnssSnapQuestion.detail = qsTr("Pomiar jest %1 od wierzchołka warstwy „%2”.").arg(distanceText(coordinateLocator.gnssSnapDistance)).arg(coordinateLocator.gnssSnapLayerName);
      gnssSnapQuestion.open();
      return;
    }
    action();
  }

  //! [WF-GNSS-SNAP] Note for a GNSS vertex near an existing vertex: snapped or not.
  function noteGnssSnap() {
    if (!coordinateLocator || !coordinateLocator.gnssLocked || coordinateLocator.gnssSnapDistance < 0)
      return;
    const d = coordinateLocator.gnssSnapDistance;
    const layerName = coordinateLocator.gnssSnapLayerName;
    if (coordinateLocator.gnssSnapActive) {
      console.log("WFG gnss snap: snapped to " + layerName + ", offset " + d.toFixed(3) + " m");
      haptyka(30);
      if (typeof dzwieki !== "undefined")
        dzwieki.zagraj("magnes", false); // [WF-SOUNDS]
      displayToast(qsTr("Dociągnięto do „%1” — przesunięcie %2").arg(layerName).arg(distanceText(d)));
    } else {
      console.log("WFG gnss snap: NOT snapped, " + d.toFixed(3) + " m from " + layerName);
      haptyka(30);
      displayToast(qsTr("Pomiar %1 od wierzchołka „%2” — nie dociągnięty").arg(distanceText(d)).arg(layerName), "warning");
    }
  }

  QfDialog {
    id: cancelDialog
    parent: mainWindow.contentItem
    title: qsTr("Cancel digitizing")
    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      text: qsTr("Should the digitized geometry be discarded?")
    }
    onAccepted: {
      digitizingLogger.clearCoordinates();
      rubberbandModel.reset();
      cancel();
      visible = false;
    }
    onRejected: {
      visible = false;
    }
  }

  function checkAccuracyRequirement() {
    if (coordinateLocator && coordinateLocator.positionLocked && positioningSettings.accuracyIndicator && positioningSettings.accuracyRequirement) {
      if (positioningSettings.accuracyBad > 0 && (!coordinateLocator.positionInformation || !coordinateLocator.positionInformation.haccValid || coordinateLocator.positionInformation.hacc >= positioningSettings.accuracyBad)) {
        displayToast(qsTr("Position accuracy doesn't meet the minimum requirement, vertex not added"), 'warning');
        return false;
      }
    }
    return true;
  }

  function checkGeometryValidity() {
    var extraVertexNeed = cogoEnabled || (coordinateLocator && coordinateLocator.positionLocked && positioningSettings.averagedPositioning && positioningSettings.averagedPositioningMinimumCount > 1) ? 1 : 0;

    // set geometry valid
    if (Number(rubberbandModel ? rubberbandModel.geometryType : 0) === 0) {
      geometryValid = false;
    } else if (Number(rubberbandModel.geometryType) === 1) {
      // Line: at least 2 points
      geometryValid = rubberbandModel.vertexCount > 1 + extraVertexNeed;
    } else if (Number(rubberbandModel.geometryType) === 2) {
      // Polygon: at least 3 points
      geometryValid = rubberbandModel.vertexCount > 2 + extraVertexNeed;
    } else {
      geometryValid = false;
    }
    // [WF-FIXED-RECT]
    if (onePointShape && rubberbandModel && rubberbandModel.vertexCount > 1)
      geometryValid = true;
  }

  function triggerAddVertex() {
    addVertexButton.clicked();
  }

  // WorkField: haptyka o regulowanej sile (Teren -> Wibracje); 0 = wylaczona
  function haptyka(baza) {
    const sila = typeof settings !== 'undefined' ? settings.valueInt('WorkField/haptykaSila', 3) : 3;
    if (sila > 0 && typeof platformUtilities !== 'undefined') {
      platformUtilities.vibrate(baza * sila);
    }
  }

  // WorkField: skala rozmiaru przyciskow (Teren -> Rozmiar), stosowana przy starcie
  readonly property real skalaPrzyciskow: (typeof settings !== 'undefined' ? settings.valueInt('WorkField/przyciskiSkala', 100) : 100) / 100.0

  function addVertex() {
    // WorkField: krótki impuls — "wierzchołek dodany" (częsta operacja, subtelny ton)
    haptyka(15);
    noteGnssSnap(); // [WF-GNSS-SNAP]
    zagrajWierzcholek(); // [WF-SOUNDS]
    digitizingLogger.addCoordinate(coordinateLocator.currentCoordinate);
    coordinateLocator.flash();
    rubberbandModel.addVertex();
  }

  function removeVertex() {
    // WorkField: wyraźnie dłuższy impuls — "coś zostało usunięte"
    haptyka(45);
    if (typeof dzwieki !== "undefined")
      dzwieki.zagraj("cofnij", false); // [WF-SOUNDS]
    digitizingLogger.removeLastCoordinate();
    rubberbandModel.removeVertex();
    mapSettings.setCenter(rubberbandModel.currentCoordinate, true);
  }

  function confirm() {
    // WorkField: długi impuls — "geometria zapisana"
    haptyka(80);
    if (Number(rubberbandModel.geometryType) === Qgis.GeometryType.Point) {
      noteGnssSnap(); // [WF-GNSS-SNAP]
      zagrajWierzcholek(); // [WF-SOUNDS] a point measured without FIX is warned about
    }
    if (typeof dzwieki !== "undefined")
      dzwieki.zagraj("ok", false); // [WF-SOUNDS]
    rubberbandModel.frozen = true;
    if (addVertexButton.lastAdditionAveraged) {
      rubberbandModel.removeVertex();
    } else {
      digitizingLogger.addCoordinate(coordinateLocator.currentCoordinate);
    }
    confirmed();
  }
}
