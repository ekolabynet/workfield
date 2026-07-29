import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import org.qgis
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * Template-aware quick capture bar (WorkField).
 * Shows one round button per known template layer found in the project.
 * Each button adds a point feature at the current GNSS position directly
 * to its fixed target layer, WITHOUT changing the active layer, then opens
 * the feature form so default values (name, time, accuracy) apply and the
 * user can attach a photo.
 */
Column {
  id: quickCaptureBar

  // rozpoznawane warstwy szablonow: nazwa -> etykieta, litera, kolor
  readonly property var captureTargets: [
    {
      "layerName": "platy",
      "letter": "P",
      "tooltip": qsTr("Rysuj płat (warstwa aktywna)"),
      "color": "#69F0AE",
      "shape": "polygon",
      "mode": "digitize"
    },
    {
      "layerName": "platy_zalazki",
      "letter": "PZ",
      "tooltip": qsTr("Zalążek płatu"),
      "color": "#AB47BC",
      "shape": "rounded",
      "mode": "capture"
    },
    {
      "layerName": "zdjecia_fito",
      "letter": "ZF",
      "tooltip": qsTr("Zdjęcie fitosocjologiczne"),
      "color": "#FF9800",
      "shape": "square",
      "mode": "capture"
    },
    {
      "layerName": "gatunki",
      "letter": "G",
      "tooltip": qsTr("Obserwacja gatunku"),
      "color": "#18FFFF",
      "shape": "circle",
      "mode": "capture"
    },
    {
      "layerName": "obserwacje",
      "letter": "O",
      "tooltip": qsTr("Szybka obserwacja"),
      "color": "#C6FF00",
      "shape": "circle",
      "mode": "capture"
    }
  ]

  QfToolButton {
    id: fastModeButton

    width: 48
    height: 48
    round: true
    anchors.horizontalCenter: parent.horizontalCenter

    bgcolor: qfieldSettings.fastMode ? "#FFC107" : Theme.toolButtonBackgroundSemiOpaqueColor
    iconSource: Theme.getThemeVectorIcon(qfieldSettings.fastMode ? "ic_flash_on_black_24dp" : "ic_flash_off_black_24dp")
    iconColor: qfieldSettings.fastMode ? "#3E2723" : Theme.toolButtonColor

    onClicked: {
      qfieldSettings.fastMode = !qfieldSettings.fastMode;
      displayToast(qfieldSettings.fastMode ? qsTr("Tryb szybki: bez potwierdzeń, kontekst z automatu") : qsTr("Tryb dokładny: formularze i potwierdzenia"));
    }
  }

  Item {
    width: 1
    height: 28
  }


  property var resolvedLayers: []
  property var pendingLayer: null
  property var pendingFeature: null
  property var cameraSource: null

  spacing: 10
  visible: resolvedLayers.length > 0 && !overlayFeatureFormDrawer.opened && stateMachine.state !== "measure" && stateMachine.state !== "3d"

  function refreshLayers() {
    const found = [];
    for (const target of captureTargets) {
      const layer = LayerUtils.vectorLayerByName(qgisProject, target.layerName);
      if (layer) {
        found.push({
            "layer": layer,
            "letter": target.letter,
            "tooltip": target.tooltip,
            "color": target.color,
            "shape": target.shape,
            "mode": target.mode
          });
      }
    }
    resolvedLayers = found;
    console.log("QuickCapture refresh:", qgisProject ? qgisProject.fileName : "brak projektu", "| znaleziono warstw:", found.length);
  }

  function captureInto(layer) {
    if (!positionSource.active || !positionSource.positionInformation || !positionSource.positionInformation.latitudeValid) {
      displayToast(qsTr("Brak pozycji GNSS — włącz pozycjonowanie"), "warning");
      return;
    }
    const pos = positionSource.projectedPosition;
    const wkt = "POINT(" + pos.x + " " + pos.y + ")";
    const geometryInMapCrs = GeometryUtils.createGeometryFromWkt(wkt);
    const geometryInLayerCrs = GeometryUtils.reprojectGeometry(geometryInMapCrs, mapCanvas.mapSettings.destinationCrs, layer.crs);
    const feature = FeatureUtils.createFeature(layer, geometryInLayerCrs, positionSource.positionInformation);

    // najpierw aparat, formularz otwiera sie po zdjeciu (lub po anulowaniu, bez foto)
    pendingLayer = layer;
    pendingFeature = feature;
    const fileName = "DCIM/" + layer.name.replace(/[^\w]/g, "_") + "_" + Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss") + ".jpg";
    if (!(platformUtilities.capabilities & PlatformUtilities.NativeCamera) || !settings.valueBool("nativeCamera2", true)) {
      // wbudowany aparat: ujecia, seria ciagla, blysk i wibracja
      platformUtilities.createDir(qgisProject.homePath, "DCIM");
      qfCameraLoader.active = true;
      return;
    }
    cameraSource = platformUtilities.getCameraPicture(qgisProject.homePath + "/", fileName, "jpg", quickCaptureBar);
    console.log("QuickCapture camera source:", cameraSource);
    if (!cameraSource) {
      openPendingForm("");
    }
  }

  // uzupelnia pola kontekstowe wartosciami z rastrow (dopasowanie po prefiksie w C++)
  function applyRasterContext(feature, layer) {
    if (!layer || !feature) {
      return feature;
    }
    const pos = positionSource.projectedPosition;
    if (!pos || !pos.x) {
      return feature;
    }
    const context = iface.rasterContextFor(layer, pos.x, pos.y);
    let filled = [];
    for (const fieldName in context) {
      feature.setAttribute(fieldName, context[fieldName]);
      filled.push(fieldName + "=" + context[fieldName]);
    }
    if (filled.length > 0) {
      console.log("Kontekst rastrowy:", filled.join(", "));
    }
    return feature;
  }

  function openPendingForm(photoPath) {
    if (!pendingLayer) {
      return;
    }
    let feature = pendingFeature;
    if (photoPath && photoPath !== "") {
      feature.setAttribute("foto", photoPath);
      if (cameraSource && cameraSource.photoShotType) {
        feature.setAttribute("ujecie", cameraSource.photoShotType);
      }
    }
    feature = applyRasterContext(feature, pendingLayer);
    // celowo bez dotykania dashBoard.activeLayer - przypisanie imperatywne,
    // binding do warstwy aktywnej odtwarzany przy zamknieciu szuflady
    overlayFeatureFormDrawer.featureModel.currentLayer = pendingLayer;
    overlayFeatureFormDrawer.featureModel.feature = feature;
    if (qfieldSettings.fastMode) {
      // tryb szybki: zapis bez otwierania formularza
      if (overlayFeatureFormDrawer.featureModel.create()) {
        displayToast(qsTr("Zapisano: %1").arg(pendingLayer.name));
      } else {
        displayToast(qsTr("Nie udało się zapisać obiektu"), "error");
      }
      overlayFeatureFormDrawer.featureModel.currentLayer = Qt.binding(() => dashBoard.activeLayer);
      pendingLayer = null;
      pendingFeature = null;
      cameraSource = null;
      return;
    }
    overlayFeatureFormDrawer.state = "Add";
    overlayFeatureFormDrawer.open();
    pendingLayer = null;
    pendingFeature = null;
    cameraSource = null;
  }

  Connections {
    target: quickCaptureBar.cameraSource
    ignoreUnknownSignals: true

    function onResourceReceived(path) {
      quickCaptureBar.openPendingForm(path);
    }

    function onResourceCanceled(path) {
      quickCaptureBar.openPendingForm("");
    }
  }

  Connections {
    target: overlayFeatureFormDrawer

    function onClosed() {
      overlayFeatureFormDrawer.featureModel.currentLayer = Qt.binding(() => dashBoard.activeLayer);
    }
  }

  Connections {
    target: qgisProject

    function onFileNameChanged() {
      quickCaptureBar.refreshLayers();
    }

    function onLayersAdded(layers) {
      quickCaptureBar.refreshLayers();
    }
  }

  Connections {
    target: iface

    function onLoadProjectEnded(path, name) {
      quickCaptureBar.refreshLayers();
    }
  }

  Component.onCompleted: refreshLayers()

  Repeater {
    model: quickCaptureBar.resolvedLayers

    delegate: Rectangle {
      width: 56
      height: 56
      radius: modelData.shape === "circle" ? width / 2 : modelData.shape === "rounded" ? 16 : 6
      color: modelData.shape === "polygon" ? "transparent" : modelData.color
      border.color: modelData.shape === "polygon" ? "transparent" : "#003D33"
      border.width: 2
      opacity: 0.92

      Shape {
        anchors.fill: parent
        visible: modelData.shape === "polygon"

        ShapePath {
          strokeColor: "#003D33"
          strokeWidth: 3
          fillColor: modelData.color

          // wielokat pomiarowy z logo WorkField, przeskalowany do 56px
          PathMove { x: 12.5; y: 20.9 }
          PathLine { x: 39.1; y: 10.7 }
          PathLine { x: 51.6; y: 31.9 }
          PathLine { x: 40.6; y: 53.0 }
          PathLine { x: 10.9; y: 47.5 }
          PathLine { x: 12.5; y: 20.9 }
        }
      }

      Text {
        anchors.centerIn: parent
        text: modelData.letter
        font.pointSize: Theme.strongFont.pointSize + 4
        font.bold: true
        color: "#003D33"
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (modelData.mode === "digitize") {
            dashBoard.activeLayer = modelData.layer;
            stateMachine.state = "digitize";
            displayToast(modelData.tooltip, "info");
          } else {
            if (stateMachine.state === "digitize") {
              stateMachine.state = "browse";
            }
            quickCaptureBar.captureInto(modelData.layer);
          }
        }
        onPressAndHold: displayToast(modelData.tooltip, "info")
      }
    }
  }

  Loader {
    id: qfCameraLoader

    active: false
    sourceComponent: qfCameraComponent
  }

  Component {
    id: qfCameraComponent

    QFieldCamera {
      id: quickCaptureCamera

      visible: false
      allowCaptureModeToggle: false

      Component.onCompleted: {
        state = "PhotoCapture";
        open();
      }

      onFinished: path => {
        quickCaptureBar.cameraSource = quickCaptureCamera;
        quickCaptureBar.openPendingForm(path);
        if (!qfieldSettings.fastMode) {
          qfCameraLoader.active = false;
        }
      }

      onCanceled: {
        quickCaptureBar.cameraSource = null;
        qfCameraLoader.active = false;
        quickCaptureBar.pendingLayer = null;
        quickCaptureBar.pendingFeature = null;
      }
    }
  }
}
