import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Layouts
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
  objectName: 'quickCaptureBar'

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
    objectName: 'fastModeButton'

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

  // WorkField: projekt bez warstw szablonu dostaje jeden "pusty" klawisz,
  // ktoremu uzytkownik sam wskazuje warstwe docelowa (pamietana per projekt).
  property string customLayerName: ""
  property bool pickAfterCreate: false

  function projectKey() {
    return "workfield/quickCaptureLayer/" + (qgisProject ? qgisProject.fileName : "");
  }

  function chooseLayer(layer) {
    if (!layer) {
      return;
    }
    customLayerName = layer.name;
    settings.setValue(projectKey(), customLayerName);
    layerPicker.close();
    refreshLayers();
    displayToast(qsTr("Klawisz szybkiego zapisu: %1").arg(customLayerName));
  }

  property var pendingLayer: null
  property var pendingFeature: null
  property var cameraSource: null

  spacing: 10
  visible: (resolvedLayers.length > 0 || (qgisProject && qgisProject.fileName !== "")) && !overlayFeatureFormDrawer.opened && stateMachine.state !== "measure" && stateMachine.state !== "3d"

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
    if (found.length === 0) {
      // brak warstw szablonu: sprobuj warstwe wskazana recznie dla tego projektu
      customLayerName = String(settings.value(projectKey(), ""));
      const custom = customLayerName !== "" ? LayerUtils.vectorLayerByName(qgisProject, customLayerName) : null;
      if (custom) {
        found.push({
            "layer": custom,
            "letter": customLayerName.substring(0, 2).toUpperCase(),
            "tooltip": qsTr("Zapis do: %1 (przytrzymaj, aby zmienić)").arg(customLayerName),
            "color": "#B0BEC5",
            "shape": "circle",
            "mode": "capture",
            "custom": true
          });
      } else {
        customLayerName = "";
      }
    }
    resolvedLayers = found;
    console.log("QuickCapture refresh:", qgisProject ? qgisProject.fileName : "brak projektu", "| znaleziono warstw:", found.length);
  }

  // warstwa aktywnej serii zdjec (tryb ciagly)
  property var seriesLayer: null
  property int seriesCount: 0

  // buduje obiekt w biezacej pozycji GNSS
  // JEDYNE miejsce liczenia pozycji: pelne strazniki na wspolrzedne-smieci.
  // Nie wymagamy fixa (decyzja projektowa): bierzemy to, co daje projectedPosition,
  // odrzucamy tylko wartosci bezuzyteczne (brak zrodla, NaN, dokladnie 0,0).
  function makeFeatureAt(layer) {
    if (!layer) {
      return null;
    }
    const pos = positionSource.projectedPosition;
    if (!pos || !isFinite(pos.x) || !isFinite(pos.y) || (pos.x === 0 && pos.y === 0)) {
      return null;
    }
    const wkt = "POINT(" + pos.x + " " + pos.y + ")";
    const geomMap = GeometryUtils.createGeometryFromWkt(wkt);
    const geomLayer = GeometryUtils.reprojectGeometry(geomMap, mapCanvas.mapSettings.destinationCrs, layer.crs);
    return FeatureUtils.createFeature(layer, geomLayer, positionSource.positionInformation);
  }

  function captureInto(layer) {
    const feature = makeFeatureAt(layer);
    if (!feature) {
      displayToast(qsTr("Brak użytecznej pozycji — punkt nie powstanie"), "warning");
      return;
    }
    if (!positionSource.positionInformation || !positionSource.positionInformation.latitudeValid) {
      // zapisujemy mimo braku fixa, ale uczciwie ostrzegamy
      displayToast(qsTr("Pozycja bez fixa — dokładność ograniczona"), "warning");
    }

    // najpierw aparat, formularz otwiera sie po zdjeciu (lub po anulowaniu, bez foto)
    pendingLayer = layer;
    seriesLayer = layer;
    seriesCount = 0;
    pendingFeature = feature;
    const fileName = "DCIM/" + layer.name.replace(/[^\w]/g, "_") + "_" + Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss") + ".jpg";
    if (!(platformUtilities.capabilities & PlatformUtilities.NativeCamera) || !settings.valueBool("nativeCamera2", true)) {
      // wbudowany aparat: ujecia, seria ciagla, blysk i wibracja
      platformUtilities.createDir(qgisProject.homePath, "DCIM");
      if (qfCameraLoader.active && qfCameraLoader.item) {
        // pas i szelki: Loader nie powinien przezyc onClosed, ale gdyby -
        // otwieramy wprost, bo onCompleted juz nie strzeli
        qfCameraLoader.item.state = "PhotoCapture";
        qfCameraLoader.item.open();
      } else {
        qfCameraLoader.active = true;
      }
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
    // tryb szybki: geometria ZAWSZE z chwili nadejscia zdjecia, nie z chwili
    // tapniecia kafelka - dotyczy takze pierwszego zdjecia serii (wczesniej
    // pierwsze dostawalo pozycje sprzed kilkudziesieciu sekund marszu)
    if (qfieldSettings.fastMode) {
      const targetLayer = pendingLayer || seriesLayer;
      if (targetLayer) {
        const fresh = makeFeatureAt(targetLayer);
        if (fresh) {
          pendingLayer = targetLayer;
          pendingFeature = fresh;
        }
        // fresh == null: zostaje obiekt z chwili tapniecia (lepszy niz zaden)
      }
    }
    if (!pendingLayer || !pendingFeature) {
      displayToast(qsTr("Zdjęcie zapisane, ale bez obiektu (brak pozycji?)"), "warning");
      return;
    }
    let feature = pendingFeature;
    const fieldNames = feature.fields.names;
    if (photoPath && photoPath !== "" && fieldNames.indexOf("foto") >= 0) {
      feature.setAttribute("foto", photoPath);
      if (cameraSource && cameraSource.photoShotType && fieldNames.indexOf("ujecie") >= 0) {
        feature.setAttribute("ujecie", cameraSource.photoShotType);
      }
    }
    feature = applyRasterContext(feature, pendingLayer);
    if (qfieldSettings.fastMode) {
      // cichy zapis WLASNYM modelem: create() sam otwiera i domyka sesje
      // edycji, a szuflada formularza i jej bindingi zostaja nietkniete
      silentFeatureModel.currentLayer = pendingLayer;
      silentFeatureModel.feature = feature;
      if (silentFeatureModel.create()) {
        seriesCount += 1;
        displayToast(qsTr("Zapisano: %1 (%2. w serii)").arg(pendingLayer.name).arg(seriesCount));
      } else {
        displayToast(qsTr("NIE zapisano obiektu — zdjęcie ocalone: %1").arg(photoPath), "error");
      }
      pendingLayer = null;
      pendingFeature = null;
      // cameraSource zostaje: seria trwa, kolejne zdjecia niosa photoShotType
      return;
    }
    // tryb dokladny: formularz przez szuflade
    // celowo bez dotykania dashBoard.activeLayer - przypisanie imperatywne,
    // binding do warstwy aktywnej odtwarzany przy zamknieciu szuflady
    overlayFeatureFormDrawer.featureModel.currentLayer = pendingLayer;
    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    overlayFeatureFormDrawer.open();
    pendingLayer = null;
    pendingFeature = null;
    cameraSource = null;
  }

  // model do cichego zapisu w trybie szybkim - niezalezny od szuflady formularza
  FeatureModel {
    id: silentFeatureModel
    project: qgisProject
  }

  Connections {
    target: quickCaptureBar.cameraSource
    ignoreUnknownSignals: true

    function onResourceReceived(path) {
      quickCaptureBar.openPendingForm(path);
    }

    function onResourceCanceled(path) {
      if (qfieldSettings.fastMode) {
        // tryb szybki: anulowanie aparatu = swiadoma rezygnacja, bez zapisu
        // (wczesniej powstawal punkt bez zdjecia)
        quickCaptureBar.pendingLayer = null;
        quickCaptureBar.pendingFeature = null;
        quickCaptureBar.cameraSource = null;
        displayToast(qsTr("Anulowano — bez zapisu"));
        return;
      }
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

    function onLayersRemoved(layerIds) {
      // bez tego resolvedLayers trzyma wiszace wskazniki po zmianie projektu
      quickCaptureBar.refreshLayers();
    }

    function onCleared() {
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
      color: modelData.color
      border.color: "#003D33"
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
        onPressAndHold: {
          if (modelData.custom === true) {
            layerPicker.open();
          } else {
            displayToast(modelData.tooltip, "info");
          }
        }
      }
    }
  }

  // WorkField: pusty klawisz - projekt bez rozpoznanych warstw szablonu
  Rectangle {
    width: 56
    height: 56
    radius: width / 2
    color: "#CFD8DC"
    border.color: "#003D33"
    border.width: 2
    opacity: 0.92
    visible: quickCaptureBar.resolvedLayers.length === 0

    Text {
      anchors.centerIn: parent
      text: "+"
      font.pointSize: Theme.strongFont.pointSize + 8
      font.bold: true
      color: "#003D33"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: layerPicker.open()
      onPressAndHold: displayToast(qsTr("Wskaż warstwę dla szybkiego zapisu"), "info")
    }
  }

  // WorkField: wybor warstwy docelowej dla pustego klawisza
  Popup {
    id: layerPicker

    parent: mainWindow.contentItem
    width: Math.min(420, mainWindow.width - 32)
    height: Math.min(520, mainWindow.height - 96)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
      color: "#EE263238"
      radius: 8
      border.color: "#455A64"
      border.width: 1
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Warstwa dla szybkiego zapisu")
        color: "#80CBC4"
        font: Theme.strongFont
        wrapMode: Text.Wrap
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Ten projekt nie ma warstw szablonu. Wskaż warstwę punktową, do której ma trafiać szybki zapis.")
        color: "#B0BEC5"
        font: Theme.tinyFont
        wrapMode: Text.Wrap
      }

      ListView {
        id: pickerList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        model: MapLayerModel {
          project: qgisProject
        }

        ScrollBar.vertical: ScrollBar {
        }

        delegate: ItemDelegate {
          // MapLayerModel nie przyjmuje filtrow z QML (Qgis.LayerFilter nie
          // jest wystawione), wiec odsiewamy warstwy nie-wektorowe tutaj
          readonly property bool isVector: model.LayerType === Qgis.LayerType.Vector

          width: pickerList.width
          height: isVector ? 48 : 0
          visible: isVector

          contentItem: Text {
            text: model.Name
            color: "white"
            font: Theme.tipFont
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }

          onClicked: quickCaptureBar.chooseLayer(model.LayerPointer)
        }
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Nowa pusta warstwa…")
        onClicked: {
          quickCaptureBar.pickAfterCreate = true;
          layerPicker.close();
          newLayerDialog.openDialog();
        }
      }
    }
  }

  Connections {
    target: newLayerDialog
    ignoreUnknownSignals: true

    function onLayerCreated(layer) {
      if (quickCaptureBar.pickAfterCreate) {
        quickCaptureBar.pickAfterCreate = false;
        quickCaptureBar.chooseLayer(layer);
      }
    }
  }

  // WorkField: wejscie do galerii zdjec projektu
  Rectangle {
    width: 56
    height: 56
    radius: 6
    color: "#FFFFFF"
    border.color: "#003D33"
    border.width: 2
    opacity: 0.92
    visible: quickCaptureBar.resolvedLayers && quickCaptureBar.resolvedLayers.length > 0

    Text {
      anchors.centerIn: parent
      text: "FOTO"
      font.pointSize: Theme.tinyFont.pointSize
      font.bold: true
      color: "#003D33"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: photoGallery.open()
      onPressAndHold: displayToast(qsTr("Galeria zdjęć projektu"), "info")
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
        // pole "foto" oczekuje sciezki wzglednej wobec katalogu projektu
        let relativePhotoPath = path;
        const home = qgisProject.homePath;
        if (home !== "" && relativePhotoPath.indexOf(home) === 0) {
          relativePhotoPath = relativePhotoPath.substring(home.length);
          while (relativePhotoPath.startsWith("/")) {
            relativePhotoPath = relativePhotoPath.substring(1);
          }
        }
        quickCaptureBar.openPendingForm(relativePhotoPath);
        if (!qfieldSettings.fastMode) {
          // tryb dokladny: jedno zdjecie, zamykamy; dezaktywacja w onClosed
          close();
        }
        // tryb szybki: aparat zostaje otwarty na serie
      }

      onCanceled: {
        quickCaptureBar.pendingLayer = null;
        quickCaptureBar.pendingFeature = null;
        close();
      }

      onClosed: {
        // JEDYNE miejsce dezaktywacji Loadera. Kazda sciezka zamkniecia
        // (finished, cancel, systemowy back) przechodzi tedy, wiec kolejne
        // otwarcie zawsze startuje od zera i przechodzi przez onCompleted.
        // To byl terenowy bug "aparat nie otwiera sie ponownie po wyjsciu".
        quickCaptureBar.cameraSource = null;
        qfCameraLoader.active = false;
      }
    }
  }
}
