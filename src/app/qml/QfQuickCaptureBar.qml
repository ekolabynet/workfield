import QtQuick
import QtQuick.Controls
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
      "layerName": "platy_zalazki",
      "letter": "Z",
      "tooltip": qsTr("Zalążek płatu"),
      "color": "#FF4081"
    },
    {
      "layerName": "zdjecia_fito",
      "letter": "F",
      "tooltip": qsTr("Zdjęcie fitosocjologiczne"),
      "color": "#FF2E75"
    },
    {
      "layerName": "gatunki",
      "letter": "G",
      "tooltip": qsTr("Obserwacja gatunku"),
      "color": "#69F0AE"
    },
    {
      "layerName": "obserwacje",
      "letter": "O",
      "tooltip": qsTr("Szybka obserwacja"),
      "color": "#C6FF00"
    }
  ]

  property var resolvedLayers: []

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
            "color": target.color
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

    // celowo bez dotykania dashBoard.activeLayer - przypisanie imperatywne,
    // binding do warstwy aktywnej odtwarzany przy zamknieciu szuflady
    overlayFeatureFormDrawer.featureModel.currentLayer = layer;
    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    overlayFeatureFormDrawer.open();
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
      radius: width / 2
      color: modelData.color
      border.color: "#003D33"
      border.width: 2
      opacity: 0.92

      Text {
        anchors.centerIn: parent
        text: modelData.letter
        font.pointSize: Theme.strongFont.pointSize + 4
        font.bold: true
        color: "#003D33"
      }

      MouseArea {
        anchors.fill: parent
        onClicked: quickCaptureBar.captureInto(modelData.layer)
        onPressAndHold: displayToast(modelData.tooltip, "info")
      }
    }
  }
}
