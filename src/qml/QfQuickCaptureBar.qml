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

  // WorkField: tryb odlegly - obiekt daleko (teleobiektyw, gatunki inwazyjne)
  Rectangle {
    width: 56
    height: 56
    radius: width / 2
    color: quickCaptureBar.distantMode ? "#FFC107" : "#546E7A"
    border.color: "#003D33"
    border.width: 2
    opacity: 0.92

    Text {
      anchors.centerIn: parent
      text: "ODL"
      font.pointSize: Theme.tinyFont.pointSize
      font.bold: true
      color: quickCaptureBar.distantMode ? "#3E2723" : "#ECEFF1"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        quickCaptureBar.distantMode = !quickCaptureBar.distantMode;
        displayToast(quickCaptureBar.distantMode ? qsTr("Tryb odległy: następne zdjęcie z podaniem odległości") : qsTr("Tryb odległy wyłączony"));
      }
      onPressAndHold: displayToast(quickCaptureBar.bearing1Valid ? qsTr("Czeka pierwszy namiar — zrób drugie ujęcie z innego miejsca") : qsTr("Obiekt daleko: zdjęcie + odległość albo dwa namiary"), "info")
    }
  }

  // WorkField: klawisz "dodaj" - stale miejsce pod przyciskiem trybu
  Rectangle {
    width: 56
    height: 56
    radius: width / 2
    color: "#8899A6"
    border.color: "#003D33"
    border.width: 2
    opacity: 0.92

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
      onPressAndHold: displayToast(qsTr("Dodaj klawisz szybkiego zapisu"), "info")
    }
  }

  Item {
    width: 1
    height: 28
  }


  property var resolvedLayers: []

  // WorkField: dowolna liczba wlasnych klawiszy, pamietanych per projekt,
  // obok ewentualnych warstw szablonu.
  property var customLayerNames: []
  property bool pickAfterCreate: false

  readonly property var customColors: ["#B0BEC5", "#FFAB91", "#CE93D8", "#80DEEA", "#E6EE9C", "#F48FB1"]

  // ---- tryb odlegly: obiekt daleko od obserwatora (teleobiektyw) ----
  property bool distantMode: false          // uzbrojony na nastepne zdjecie
  property bool distantFlow: false          // zdjecie robi sie wlasnie teraz
  property var distantLayer: null
  property string distantPhoto: ""
  property real distantAz: NaN              // azymut w chwili migawki
  property real distantX: 0
  property real distantY: 0
  // pierwszy namiar metody przeciecia
  property bool bearing1Valid: false
  property real bearing1X: 0
  property real bearing1Y: 0
  property real bearing1Az: NaN

  // azymut siatki mapy: kompas + poprawka do polnocy ukladu
  function currentAzimuth() {
    if (!positionSource || isNaN(positionSource.orientation)) {
      return NaN;
    }
    let az = positionSource.orientation + positionSource.bearingTrueNorth;
    while (az < 0)
      az += 360;
    return az % 360;
  }

  // przesuniecie o dystans wzdluz azymutu, we wspolrzednych mapy
  function offsetPoint(x, y, azDeg, dist) {
    const r = azDeg * Math.PI / 180;
    let d = dist;
    // Web Mercator klamie o odleglosciach - korekta przez szerokosc geograficzna
    if (String(mapCanvas.mapSettings.destinationCrs.authid) === "EPSG:3857" && positionSource.positionInformation && positionSource.positionInformation.latitudeValid) {
      d = dist / Math.cos(positionSource.positionInformation.latitude * Math.PI / 180);
    }
    return {
      "x": x + d * Math.sin(r),
      "y": y + d * Math.cos(r)
    };
  }

  // przeciecie dwoch namiarow; zwraca null, gdy kat zbyt ostry
  function intersectBearings(x1, y1, az1, x2, y2, az2) {
    const r1 = az1 * Math.PI / 180;
    const r2 = az2 * Math.PI / 180;
    const dx1 = Math.sin(r1), dy1 = Math.cos(r1);
    const dx2 = Math.sin(r2), dy2 = Math.cos(r2);
    const det = dx1 * (-dy2) - (-dx2) * dy1;
    if (Math.abs(det) < 1e-9) {
      return null;
    }
    const t = ((x2 - x1) * (-dy2) - (-dx2) * (y2 - y1)) / det;
    if (t <= 0) {
      return null; // przeciecie za plecami obserwatora
    }
    let kat = Math.abs(az1 - az2) % 360;
    if (kat > 180)
      kat = 360 - kat;
    return {
      "x": x1 + t * dx1,
      "y": y1 + t * dy1,
      "kat": kat,
      "dist": t
    };
  }

  // zapis obiektu odleglego wraz z metryczka pochodzenia
  function saveDistantFeature(px, py, dist, metoda, kat) {
    const wkt = "POINT(" + px + " " + py + ")";
    const geomMap = GeometryUtils.createGeometryFromWkt(wkt);
    const geomLayer = GeometryUtils.reprojectGeometry(geomMap, mapCanvas.mapSettings.destinationCrs, distantLayer.crs);
    let feature = FeatureUtils.createFeature(distantLayer, geomLayer, positionSource.positionInformation);
    if (!feature) {
      displayToast(qsTr("Nie udało się utworzyć obiektu"), "error");
      return;
    }
    const pola = feature.fields.names;
    const wpisz = (nazwa, wartosc) => {
      if (pola.indexOf(nazwa) >= 0) {
        feature.setAttribute(nazwa, wartosc);
      }
    };
    if (distantPhoto !== "") {
      wpisz("foto", distantPhoto);
      if (cameraSource && cameraSource.photoShotType) {
        wpisz("ujecie", cameraSource.photoShotType);
      }
    }
    wpisz("azymut", Math.round(distantAz * 10) / 10);
    wpisz("odleglosc_m", Math.round(dist * 10) / 10);
    wpisz("obs_x", Math.round(distantX * 100) / 100);
    wpisz("obs_y", Math.round(distantY * 100) / 100);
    wpisz("metoda", metoda);
    if (!isNaN(kat)) {
      wpisz("kat_przeciecia", Math.round(kat * 10) / 10);
    }
    feature = applyRasterContext(feature, distantLayer);
    overlayFeatureFormDrawer.featureModel.currentLayer = distantLayer;
    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    overlayFeatureFormDrawer.open();
    distantPhoto = "";
    distantLayer = null;
    cameraSource = null;
    distantMode = false;
  }

  function finishDistant(dist) {
    if (!distantLayer || isNaN(distantAz)) {
      displayToast(qsTr("Brak azymutu — kompas nie odpowiada"), "warning");
      return;
    }
    const cel = offsetPoint(distantX, distantY, distantAz, dist);
    saveDistantFeature(cel.x, cel.y, dist, "dystans", NaN);
  }

  // "nie wiem": pierwszy namiar czeka na drugi z innego stanowiska
  function keepBearing() {
    if (isNaN(distantAz)) {
      displayToast(qsTr("Brak azymutu — kompas nie odpowiada"), "warning");
      return;
    }
    if (!bearing1Valid) {
      bearing1Valid = true;
      bearing1X = distantX;
      bearing1Y = distantY;
      bearing1Az = distantAz;
      distantPhoto = "";
      distantLayer = null;
      displayToast(qsTr("Namiar zapisany — przejdź w bok (ok. połowy odległości) i namierz ponownie"));
      return;
    }
    const p = intersectBearings(bearing1X, bearing1Y, bearing1Az, distantX, distantY, distantAz);
    if (!p) {
      displayToast(qsTr("Namiary równoległe — przejdź dalej w bok"), "warning");
      return;
    }
    if (p.kat < 15) {
      displayToast(qsTr("Kąt przecięcia %1° — za mało, przejdź dalej w bok").arg(Math.round(p.kat)), "warning");
      return;
    }
    if (p.kat < 30) {
      displayToast(qsTr("Kąt %1° — punkt niepewny, dokładność ograniczona").arg(Math.round(p.kat)), "warning");
    }
    bearing1Valid = false;
    saveDistantFeature(p.x, p.y, p.dist, "przeciecie", p.kat);
  }
  // przeplyw "najpierw zdjecie, potem geometria" (linie i poligony)
  property string pendingGeomPhoto: ""
  property var pendingGeomLayer: null
  property bool geomFlow: false

  function projectKey() {
    return "workfield/quickCaptureLayers/" + (qgisProject ? qgisProject.fileName : "");
  }

  function loadCustomNames() {
    const raw = String(settings.value(projectKey(), ""));
    customLayerNames = raw === "" ? [] : raw.split("|").filter(n => n !== "");
  }

  function saveCustomNames() {
    settings.setValue(projectKey(), customLayerNames.join("|"));
  }

  function chooseLayer(layer) {
    if (!layer) {
      return;
    }
    const names = customLayerNames.slice();
    if (names.indexOf(layer.name) < 0) {
      names.push(layer.name);
    }
    customLayerNames = names;
    saveCustomNames();
    layerPicker.close();
    refreshLayers();
    displayToast(qsTr("Dodano klawisz: %1").arg(layer.name));
  }

  function dropLayer(name) {
    const names = customLayerNames.filter(n => n !== name);
    if (names.length === customLayerNames.length) {
      return;
    }
    customLayerNames = names;
    saveCustomNames();
    refreshLayers();
    displayToast(qsTr("Usunięto klawisz: %1 (dane nietknięte)").arg(name));
  }

  function captureGeometryFlow(layer) {
    if (!layer) {
      return;
    }
    pendingGeomLayer = layer;
    pendingGeomPhoto = "";
    geomFlow = true;
    pendingLayer = null;
    pendingFeature = null;
    openCameraFor(layer);
  }

  // przerwane rysowanie: zdjecie zostaje na dysku, obiekt nie powstaje
  function abortGeometryCapture() {
    if (pendingGeomPhoto === "") {
      return;
    }
    displayToast(qsTr("Przerwano — zdjęcie zostało w DCIM, bez obiektu"), "warning");
    pendingGeomPhoto = "";
    pendingGeomLayer = null;
    geomFlow = false;
  }

  // geometria narysowana: obiekt dostaje zdjecie i formularz
  function finishGeometryCapture(digFeature) {
    if (pendingGeomPhoto === "" || !pendingGeomLayer || !digFeature) {
      return false;
    }
    digFeature.geometry.applyRubberband();
    digFeature.applyGeometry();
    let feature = digFeature.feature;
    if (!feature) {
      return false;
    }
    const fieldNames = feature.fields.names;
    if (fieldNames.indexOf("foto") >= 0) {
      feature.setAttribute("foto", pendingGeomPhoto);
      if (cameraSource && cameraSource.photoShotType && fieldNames.indexOf("ujecie") >= 0) {
        feature.setAttribute("ujecie", cameraSource.photoShotType);
      }
    }
    feature = applyRasterContext(feature, pendingGeomLayer);
    overlayFeatureFormDrawer.featureModel.currentLayer = pendingGeomLayer;
    overlayFeatureFormDrawer.featureModel.feature = feature;
    overlayFeatureFormDrawer.state = "Add";
    overlayFeatureFormDrawer.open();
    pendingGeomPhoto = "";
    pendingGeomLayer = null;
    cameraSource = null;
    return true;
  }

  property var pendingLayer: null
  property var pendingFeature: null
  property var cameraSource: null

  spacing: 10
  visible: (resolvedLayers.length > 0 || (qgisProject && qgisProject.fileName !== "")) && !overlayFeatureFormDrawer.opened && stateMachine.state !== "measure" && stateMachine.state !== "3d"

  // czy do warstwy da sie w ogole dodac obiekt (dane w ZIP, WMS, tylko odczyt)
  function layerWritable(layer) {
    if (!layer) {
      return false;
    }
    if (layer.readOnly) {
      return false;
    }
    return !LayerUtils.isFeatureAdditionLocked(layer);
  }

  // QFieldSync nazywa warstwy "plik — warstwa", wiec obok nazwy doslownej
  // przyjmujemy tez koncowke po myslniku
  function findLayerByName(nazwa) {
    const doslownie = LayerUtils.vectorLayerByName(qgisProject, nazwa);
    if (doslownie) {
      return doslownie;
    }
    if (!qgisProject) {
      return null;
    }
    const wszystkie = ProjectUtils.mapLayers(qgisProject);
    for (const id in wszystkie) {
      const l = wszystkie[id];
      if (!l || !l.name) {
        continue;
      }
      const n = String(l.name);
      if (n === nazwa || n.endsWith("\u2014 " + nazwa) || n.endsWith("- " + nazwa)) {
        return l;
      }
    }
    return null;
  }

  function refreshLayers() {
    const found = [];
    for (const target of captureTargets) {
      const layer = findLayerByName(target.layerName);
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
    // wlasne klawisze uzytkownika - niezaleznie od warstw szablonu
    loadCustomNames();
    const zywe = [];
    for (let i = 0; i < customLayerNames.length; i++) {
      const nazwa = customLayerNames[i];
      const custom = findLayerByName(nazwa);
      if (!custom) {
        continue; // warstwa zniknela z projektu - klawisz wypada
      }
      if (!layerWritable(custom)) {
        continue; // dane tylko do odczytu (np. w archiwum ZIP) - bez klawisza
      }
      const gt = custom.geometryType();
      if (gt !== Qgis.GeometryType.Point && gt !== Qgis.GeometryType.Line && gt !== Qgis.GeometryType.Polygon) {
        continue; // tabela bez geometrii nie ma czego zapisywac
      }
      const punktowa = gt === Qgis.GeometryType.Point;
      zywe.push(nazwa);
      found.push({
          "layer": custom,
          "letter": nazwa.substring(0, 2).toUpperCase(),
          "tooltip": punktowa ? qsTr("Zapis do: %1 (przytrzymaj, aby usunąć klawisz)").arg(nazwa) : qsTr("Zdjęcie, potem rysowanie: %1 (przytrzymaj, aby usunąć klawisz)").arg(nazwa),
          "color": customColors[zywe.length % customColors.length],
          "shape": punktowa ? "circle" : gt === Qgis.GeometryType.Line ? "rounded" : "square",
          "mode": punktowa ? "capture" : "photogeom",
          "custom": true,
          "customName": nazwa
        });
    }
    if (zywe.length !== customLayerNames.length) {
      customLayerNames = zywe;
      saveCustomNames();
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
    if (distantMode) {
      const pos = positionSource.projectedPosition;
      if (!pos || !isFinite(pos.x) || !isFinite(pos.y) || (pos.x === 0 && pos.y === 0)) {
        displayToast(qsTr("Brak użytecznej pozycji obserwatora"), "warning");
        return;
      }
      distantLayer = layer;
      distantX = pos.x;
      distantY = pos.y;
      distantAz = currentAzimuth();
      distantPhoto = "";
      distantFlow = true;
      pendingLayer = null;
      pendingFeature = null;
      openCameraFor(layer);
      return;
    }
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
    openCameraFor(layer);
  }

  function openCameraFor(layer) {
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
    if (distantFlow) {
      distantFlow = false;
      if (!photoPath || photoPath === "") {
        distantLayer = null;
        return;
      }
      distantPhoto = photoPath;
      distancePicker.open();
      return;
    }
    if (geomFlow) {
      // zdjecie mamy; obiekt powstanie po narysowaniu geometrii
      geomFlow = false;
      if (!photoPath || photoPath === "") {
        pendingGeomLayer = null;
        return;
      }
      pendingGeomPhoto = photoPath;
      dashBoard.activeLayer = pendingGeomLayer;
      stateMachine.state = "digitize";
      displayToast(qsTr("Zdjęcie zapisane — obrysuj obiekt i zatwierdź"));
      return;
    }
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
          if (modelData.mode === "photogeom") {
            if (stateMachine.state === "digitize") {
              stateMachine.state = "browse";
            }
            quickCaptureBar.captureGeometryFlow(modelData.layer);
          } else if (modelData.mode === "digitize") {
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
            quickCaptureBar.dropLayer(modelData.customName);
          } else {
            displayToast(modelData.tooltip, "info");
          }
        }
      }
    }
  }

  // WorkField: ile stad do obiektu?
  Popup {
    id: distancePicker

    parent: mainWindow.contentItem
    width: Math.min(360, mainWindow.width - 32)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    modal: true
    closePolicy: Popup.CloseOnEscape

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
        text: qsTr("Jak daleko jest obiekt?")
        color: "#80CBC4"
        font: Theme.strongFont
        wrapMode: Text.Wrap
      }

      Text {
        Layout.fillWidth: true
        text: isNaN(quickCaptureBar.distantAz) ? qsTr("Brak azymutu — kompas nie odpowiada") : qsTr("Azymut %1°").arg(Math.round(quickCaptureBar.distantAz))
        color: isNaN(quickCaptureBar.distantAz) ? Theme.warningColor : "#B0BEC5"
        font: Theme.tinyFont
      }

      Flow {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
          model: [25, 50, 100, 200]

          delegate: Button {
            text: modelData + " m"
            font.pointSize: Theme.tipFont.pointSize
            onClicked: {
              distancePicker.close();
              quickCaptureBar.finishDistant(modelData);
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        TextField {
          id: customDistance
          Layout.fillWidth: true
          placeholderText: qsTr("inna, w metrach")
          color: "white"
          placeholderTextColor: "#90A4AE"
          font: Theme.tipFont
          inputMethodHints: Qt.ImhDigitsOnly
          validator: IntValidator {
            bottom: 1
            top: 5000
          }
        }

        Button {
          text: qsTr("Zapisz")
          enabled: customDistance.text !== ""
          onClicked: {
            distancePicker.close();
            quickCaptureBar.finishDistant(parseInt(customDistance.text));
            customDistance.text = "";
          }
        }
      }

      Button {
        Layout.fillWidth: true
        text: quickCaptureBar.bearing1Valid ? qsTr("Nie wiem — to drugi namiar") : qsTr("Nie wiem — zrobię drugi namiar")
        onClicked: {
          distancePicker.close();
          quickCaptureBar.keepBearing();
        }
      }
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
          readonly property bool isVector: model.LayerType === Qgis.LayerType.Vector && (model.GeometryType === Qgis.GeometryType.Point || model.GeometryType === Qgis.GeometryType.Line || model.GeometryType === Qgis.GeometryType.Polygon) && quickCaptureBar.layerWritable(model.LayerPointer) && quickCaptureBar.customLayerNames.indexOf(model.Name) < 0

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
