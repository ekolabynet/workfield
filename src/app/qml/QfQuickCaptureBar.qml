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
      haptyka(30);
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
        haptyka(30);
        quickCaptureBar.distantMode = !quickCaptureBar.distantMode;
        displayToast(quickCaptureBar.distantMode ? qsTr("Tryb odległy: następne zdjęcie z podaniem odległości") : qsTr("Tryb odległy wyłączony"));
      }
      onPressAndHold: displayToast(quickCaptureBar.bearing1Valid ? qsTr("Czeka pierwszy namiar — zrób drugie ujęcie z innego miejsca") : qsTr("Obiekt daleko: zdjęcie + odległość albo dwa namiary"), "info")
    }
  }

  // Kotwica czasowa: przelacznik trybu + licznik oczekujacych
  Rectangle {
    width: 56
    height: 56
    radius: width / 2
    color: quickCaptureBar.kotwicaTryb ? "#1565C0" : "#546E7A"
    border.color: "#0D2C4F"
    border.width: 2
    opacity: 0.95

    Column {
      anchors.centerIn: parent
      spacing: -2

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("KTW")
        font.pointSize: Theme.tinyFont.pointSize
        font.bold: true
        color: "white"
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: quickCaptureBar.kotwice.length > 0 ? quickCaptureBar.kotwice.length : (quickCaptureBar.kotwicaTryb ? qsTr("wł") : qsTr("wył"))
        font.pointSize: Theme.tinyFont.pointSize
        font.bold: true
        color: "white"
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        quickCaptureBar.haptyka(30);
        quickCaptureBar.kotwicaTryb = !quickCaptureBar.kotwicaTryb;
        displayToast(quickCaptureBar.kotwicaTryb ? qsTr("Kotwica czasowa WŁĄCZONA: tap w marszu, punkt z pozycji z chwili tapnięcia") : qsTr("Kotwica czasowa wyłączona"));
      }
    }
  }

  // QuickCapture 2.0: licznik wpisow czekajacych na materializacje
  Rectangle {
    visible: quickCaptureBar.odroczone.length > 0
    width: 56
    height: 56
    radius: width / 2
    color: "#FFC107"
    border.color: "#3E2723"
    border.width: 2
    opacity: 0.95

    Column {
      anchors.centerIn: parent
      spacing: -2

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("ODR")
        font.pointSize: Theme.tinyFont.pointSize
        font.bold: true
        color: "#3E2723"
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: quickCaptureBar.odroczone.length
        font.pointSize: Theme.strongFont.pointSize
        font.bold: true
        color: "#3E2723"
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: displayToast(qsTr("Wpisy odroczone: %1 — zapiszą się po zamknięciu edycji geometrii").arg(quickCaptureBar.odroczone.length))
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
      onClicked: {
        haptyka(15);
        layerPicker.open();
      }
      onPressAndHold: captureSettings.openDialog()
    }
  }

  Item {
    width: 1
    height: 28
  }


  // ---- QuickCapture 2.0: kolejka wpisow odroczonych ----
  // Foto tapniete W TRAKCIE tyczenia geometrii nie dotyka sesji edycji GPKG:
  // wpis (warstwa + gotowy obiekt z pozycja i zdjeciem) czeka w kolejce
  // i materializuje sie zaraz po wyjsciu z trybu rysowania.
  property var odroczone: []
  // decyzja "odraczamy" zapada przy tapnieciu kafelka; aparat zewnetrzny
  // potrafi zresetowac stan aplikacji, wiec stanu nie czytamy po powrocie
  property bool odroczenieFlow: false

  // ---- Kotwica czasowa (v1) ----
  // Tap w marszu: zapamietujemy CZAS tapniecia, a obiekt tworzymy dopiero,
  // gdy przyplynie fix GPS zmierzony w tamtej chwili (utcDateTime zdania
  // NMEA >= czas tapniecia). Latencja przestaje wymagac zatrzymywania sie.
  property bool kotwicaTryb: settings.valueBool('WorkField/kotwicaTryb', false)
  property var kotwice: []
  property double tapUtcMs: 0

  onKotwicaTrybChanged: settings.setValue('WorkField/kotwicaTryb', kotwicaTryb)

  function obsluzKotwice() {
    if (kotwice.length === 0) {
      return;
    }
    const pi = positionSource.positionInformation;
    const pos = positionSource.projectedPosition;
    const swiezyFix = pi && pi.utcDateTime;
    const fixMs = swiezyFix ? pi.utcDateTime.getTime() : 0;
    const pozycjaOk = pos && isFinite(pos.x) && isFinite(pos.y) && !(pos.x === 0 && pos.y === 0);
    const terazMs = Date.now();
    const zostaja = [];
    for (let i = 0; i < kotwice.length; ++i) {
      const k = kotwice[i];
      // faza 1: zamrozenie pozycji pierwszym fixem z czasu >= tapniecia
      if (!k.pozycja && swiezyFix && pozycjaOk && fixMs >= k.tapUtcMs) {
        k.pozycja = ({
            "x": pos.x,
            "y": pos.y
          });
        k.pi = pi;
      }
      if (k.pozycja && !k.czekaNaFoto) {
        zapiszKotwice(k, false);
      } else if (!k.czekaNaFoto && terazMs > k.deadlineMs) {
        // timeout bez zamrozonej pozycji: ostatnia deska — pozycja biezaca
        if (!k.pozycja && pozycjaOk) {
          k.pozycja = ({
              "x": pos.x,
              "y": pos.y
            });
          k.pi = pi;
        }
        zapiszKotwice(k, true);
      } else {
        // czekaNaFoto: aparat wciaz otwarty — cierpliwie, bez terminu
        zostaja.push(k);
      }
    }
    if (zostaja.length !== kotwice.length) {
      kotwice = zostaja;
    }
  }

  function zapiszKotwice(k, timeout) {
    if (!k.layer || !k.pozycja) {
      displayToast(qsTr("Kotwica: brak użytecznej pozycji — wpis utracony (zdjęcie w DCIM)"), "error");
      return;
    }
    if (k.typ === "wierzcholek") {
      if (typeof digitizingRubberband !== 'undefined' && digitizingRubberband.model && digitizingRubberband.model.vertexCount >= 1) {
        const pkt = GeometryUtils.reprojectPoint(GeometryUtils.point(k.pozycja.x, k.pozycja.y), mapCanvas.mapSettings.destinationCrs, digitizingRubberband.model.crs);
        digitizingRubberband.model.addVertexFromPoint(pkt);
        haptyka(10);
        if (timeout) {
          displayToast(qsTr("Kotwica: wierzchołek z pozycji bieżącej (fix z chwili tapnięcia nie nadszedł)"), "warning");
        }
        return;
      }
      // ksztalt juz zamkniety/porzucony — spozniona kotwica jako punkt ratunkowy
    }
    const wkt = "POINT(" + k.pozycja.x + " " + k.pozycja.y + ")";
    const geomMap = GeometryUtils.createGeometryFromWkt(wkt);
    const geomLayer = GeometryUtils.reprojectGeometry(geomMap, mapCanvas.mapSettings.destinationCrs, k.layer.crs);
    let feature = FeatureUtils.createFeature(k.layer, geomLayer, k.pi);
    if (k.foto !== "") {
      feature.setAttribute("foto", k.foto);
      if (k.ujecie !== undefined && k.ujecie !== "") {
        feature.setAttribute("ujecie", k.ujecie);
      }
    }
    feature = applyRasterContext(feature, k.layer);
    silentFeatureModel.currentLayer = k.layer;
    silentFeatureModel.feature = feature;
    if (silentFeatureModel.create()) {
      if (timeout) {
        displayToast(qsTr("Kotwica: fix z chwili tapnięcia nie nadszedł — zapisano pozycję bieżącą (%1)").arg(k.layer.name), "warning");
        haptyka(45);
      } else {
        haptyka(10);
      }
    } else {
      displayToast(qsTr("Kotwica: zapis do %1 nie powiódł się").arg(k.layer.name), "error");
    }
  }

  Connections {
    target: positionSource

    function onPositionInformationChanged() {
      quickCaptureBar.obsluzKotwice();
    }
  }

  // WorkField: haptyka o sile z karty Teren (0 = wylaczona)
  function haptyka(baza) {
    const sila = typeof settings !== 'undefined' ? settings.valueInt('WorkField/haptykaSila', 3) : 3;
    if (sila > 0 && typeof platformUtilities !== 'undefined') {
      platformUtilities.vibrate(baza * sila);
    }
  }

  function materializujOdroczone() {
    if (odroczone.length === 0) {
      return;
    }
    // nie walczymy o edycje GPKG: czekamy na koniec rysowania i formularza
    if (stateMachine.state === "digitize") {
      return;
    }
    if (typeof overlayFeatureFormDrawer !== 'undefined' && overlayFeatureFormDrawer.opened) {
      return;
    }
    const kolejka = odroczone;
    odroczone = [];
    let zapisane = 0;
    let nieudane = 0;
    const wgWarstw = {};
    for (let i = 0; i < kolejka.length; ++i) {
      const wpis = kolejka[i];
      if (!wpis.layer || !wpis.feature) {
        nieudane += 1;
        continue;
      }
      silentFeatureModel.currentLayer = wpis.layer;
      silentFeatureModel.feature = wpis.feature;
      if (silentFeatureModel.create()) {
        zapisane += 1;
        wgWarstw[wpis.layer.name] = (wgWarstw[wpis.layer.name] || 0) + 1;
      } else {
        nieudane += 1;
      }
    }
    if (zapisane > 0) {
      haptyka(80);
      const czesci = [];
      for (const nazwa in wgWarstw) {
        czesci.push(nazwa + ": " + wgWarstw[nazwa]);
      }
      displayToast(qsTr("Wpisy odroczone zapisane — %1").arg(czesci.join(", ")));
    }
    if (nieudane > 0) {
      displayToast(qsTr("Nie zapisano %1 wpisów odroczonych (zdjęcia ocalone w DCIM)").arg(nieudane), "error");
    }
  }

  Connections {
    target: stateMachine

    function onStateChanged() {
      quickCaptureBar.materializujOdroczone();
    }
  }

  Connections {
    target: typeof overlayFeatureFormDrawer !== 'undefined' ? overlayFeatureFormDrawer : null

    function onOpenedChanged() {
      quickCaptureBar.materializujOdroczone();
    }
  }

  property var resolvedLayers: []

  // WorkField: dowolna liczba wlasnych klawiszy, pamietanych per projekt,
  // obok ewentualnych warstw szablonu.
  property var customLayerNames: []
  property bool pickAfterCreate: false

  property var distancePresets: [25, 50, 100, 200]

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

  // ---- definicje klawiszy: plik w katalogu projektu ----
  function defsPath() {
    return qgisProject && qgisProject.homePath !== "" ? qgisProject.homePath + "/workfield_klawisze.json" : "";
  }

  function loadDefinitions() {
    const sciezka = defsPath();
    if (sciezka === "" || !FileUtils.fileExists(sciezka)) {
      return null;
    }
    try {
      const tresc = String(FileUtils.readFileContent(sciezka));
      const dane = JSON.parse(tresc);
      return dane && dane.klawisze ? dane : null;
    } catch (e) {
      console.log("Klawisze: plik definicji nieczytelny -", e);
      return null;
    }
  }

  function saveDefinitions(dane) {
    const sciezka = defsPath();
    if (sciezka === "") {
      return false;
    }
    const ok = FileUtils.writeFileContent(sciezka, JSON.stringify(dane, null, 2));
    if (ok) {
      refreshLayers();
    }
    return ok;
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
    haptyka(15);
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
    stateMachine.state = "browse";
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
    // rysowanie skonczone - wracamy do przegladania (nie ma juz przelacznika)
    stateMachine.state = "browse";
    return true;
  }

  // Poza aparatu przy migawce. Wbudowany aparat zapisuje ja sam
  // (QFieldCamera), ale sciezka aparatu systemowego omijala ten krok -
  // przez co zdjecia z niego nie mialy ani azymutu, ani pochylenia.
  CaptureAttitude {
    id: captureAttitude
  }

  // Uzupelnienie metadanych po powrocie z APARATU ZEWNETRZNEGO.
  //
  // Pozy tu NIE zapisujemy: czujniki orientacji spia, gdy aplikacja jest w tle,
  // wiec odczyt zamrozony przed przejsciem do aparatu klamie (test 1.08.2026:
  // zdjecia pionowo w dol i poziomo dostawaly ten sam przypadkowy pitch, a
  // azymut rozjezdzal sie z aparatowym nawet o 50 stopni). Prawdziwa poze
  // zapisuje sama OpenCamera - tej nie wolno tknac.
  //
  // Dopisujemy natomiast POZYCJE, gdy aparat jej nie zapisal (aparat systemowy
  // Samsunga nie geotaguje) - nasza jest i tak dokladniejsza, bo z odbiornika RTK.
  function uzupelnijMetadane(sciezka) {
    if (!sciezka || sciezka === "") {
      return;
    }
    const poz = positionSource.positionInformation;
    if (poz && poz.latitudeValid && poz.longitudeValid) {
      captureAttitude.fillMissingPosition(sciezka, poz.latitude, poz.longitude,
                                          poz.elevationValid ? poz.elevation : NaN);
    }
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

    // definicje z pliku projektu maja pierwszenstwo przed automatem
    const defs = loadDefinitions();
    if (defs) {
      distancePresets = defs.odleglosci && defs.odleglosci.length > 0 ? defs.odleglosci : [25, 50, 100, 200];
      for (let i = 0; i < defs.klawisze.length; i++) {
        const d = defs.klawisze[i];
        const l = findLayerByName(d.warstwa);
        if (!l || !layerWritable(l)) {
          continue;
        }
        const g = l.geometryType();
        const punkt = g === Qgis.GeometryType.Point;
        found.push({
            "layer": l,
            "letter": d.etykieta,
            "tooltip": qsTr("Zapis do: %1").arg(d.warstwa),
            "color": d.kolor,
            "shape": punkt ? "circle" : g === Qgis.GeometryType.Line ? "rounded" : "square",
            "mode": punkt ? "capture" : (d.zdjecie === false ? "digitize" : "photogeom"),
            "bezZdjecia": punkt && d.zdjecie === false,
            "custom": false
          });
      }
      resolvedLayers = found;
      console.log("QuickCapture: definicje z pliku,", found.length, "klawiszy");
      return;
    }

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

  function captureInto(layer, bezZdjecia) {
    haptyka(15);
    tapUtcMs = Date.now();

    // Kotwica dwufazowa — faza 1: lapacz uzbraja sie JUZ przy tapnieciu.
    // Pierwszy fix o czasie >= tapniecia zamrozi pozycje (obsluzKotwice),
    // zwykle zanim uzytkownik skonczy kadrowac zdjecie.
    if (kotwicaTryb && !distantMode) {
      const wierzcholekKsztaltu = bezZdjecia === true && typeof digitizingRubberband !== 'undefined' && digitizingRubberband.model && digitizingRubberband.model.vertexCount > 1;
      kotwice.push({
          "typ": wierzcholekKsztaltu ? "wierzcholek" : "punkt",
          "layer": layer,
          "foto": "",
          "ujecie": "",
          "tapUtcMs": tapUtcMs,
          "deadlineMs": tapUtcMs + 30000,
          "pozycja": null,
          "pi": null,
          "czekaNaFoto": bezZdjecia === true ? false : true
        });
      kotwice = kotwice;
    }

    // B: czysty punkt bez aparatu (tyczenie ciagow) — koniec przeplywu tutaj
    if (bezZdjecia === true) {
      if (!kotwicaTryb) {
        if (typeof digitizingRubberband !== 'undefined' && digitizingRubberband.model && digitizingRubberband.model.vertexCount > 1) {
          const pos0 = positionSource.projectedPosition;
          if (pos0 && isFinite(pos0.x) && isFinite(pos0.y) && !(pos0.x === 0 && pos0.y === 0)) {
            const pkt0 = GeometryUtils.reprojectPoint(GeometryUtils.point(pos0.x, pos0.y), mapCanvas.mapSettings.destinationCrs, digitizingRubberband.model.crs);
            digitizingRubberband.model.addVertexFromPoint(pkt0);
          } else {
            displayToast(qsTr("Brak użytecznej pozycji — wierzchołek nie powstał"), "warning");
          }
        } else {
          const feature = makeFeatureAt(layer);
          if (!feature) {
            displayToast(qsTr("Brak użytecznej pozycji — punkt nie powstał"), "warning");
            return;
          }
          silentFeatureModel.currentLayer = layer;
          silentFeatureModel.feature = feature;
          if (!silentFeatureModel.create()) {
            displayToast(qsTr("Nie udało się zapisać punktu do %1").arg(layer.name), "error");
          }
        }
      }
      // tapniecie kafelka zgasilo stan rysowania — jesli w modelu czeka
      // niedokonczona geometria, wracamy do niej (pasek zatwierdzania wraca)
      if (typeof digitizingRubberband !== 'undefined' && digitizingRubberband.model && digitizingRubberband.model.vertexCount > 1 && stateMachine.state !== "digitize") {
        stateMachine.state = "digitize";
      }
      return;
    }

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

    // QuickCapture 2.0: decyzje o odroczeniu podejmujemy JUZ TERAZ —
    // stan "digitize" moze nie przezyc wycieczki do aparatu zewnetrznego
    // stan potrafi zgasnac od samego tapniecia kafelka — pytamy wiec o FAKT:
    // czy w modelu rysowania czeka niedokonczona geometria (wierzcholki)
    const wierzcholki = typeof digitizingRubberband !== 'undefined' && digitizingRubberband.model ? digitizingRubberband.model.vertexCount : 0;
    odroczenieFlow = stateMachine.state === "digitize" || wierzcholki > 1;

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
    uzupelnijMetadane(photoPath ? qgisProject.homePath + "/" + photoPath : "");
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
    // QuickCapture 2.0: w trakcie tyczenia nie ruszamy sesji edycji GPKG —
    // wpis czeka w kolejce i zapisze sie po zamknieciu geometrii
    if (odroczenieFlow || stateMachine.state === "digitize") {
      odroczenieFlow = false;
      odroczone.push({
          "layer": pendingLayer,
          "feature": feature
        });
      odroczone = odroczone;
      haptyka(15);
      displayToast(qsTr("Odroczono do %1 — w kolejce: %2").arg(pendingLayer.name).arg(odroczone.length));
      pendingLayer = null;
      pendingFeature = null;
      if (stateMachine.state !== "digitize") {
        // aparat wybil nas z rysowania — wracamy; niedokonczona geometria
        // zwykle czeka nietknieta w modelu rysowania
        stateMachine.state = "digitize";
      }
      return;
    }
    if (qfieldSettings.fastMode) {
      if (kotwicaTryb) {
        // faza 2: zdjecie dokleja sie do lapacza uzbrojonego przy tapnieciu;
        // jesli pozycja juz zamrozona — punkt powstaje natychmiast
        let zwiazano = false;
        for (let i = kotwice.length - 1; i >= 0; --i) {
          if (kotwice[i].czekaNaFoto) {
            kotwice[i].foto = photoPath;
            kotwice[i].ujecie = typeof cameraSource !== 'undefined' && cameraSource ? cameraSource.photoShotType : "";
            kotwice[i].czekaNaFoto = false;
            kotwice[i].deadlineMs = Date.now() + 30000;
            zwiazano = true;
            break;
          }
        }
        if (!zwiazano) {
          // asekuracja: lapacza nie bylo (np. tryb wlaczony w trakcie) — jak v1
          kotwice.push({
              "layer": pendingLayer,
              "foto": photoPath,
              "ujecie": typeof cameraSource !== 'undefined' && cameraSource ? cameraSource.photoShotType : "",
              "tapUtcMs": tapUtcMs > 0 ? tapUtcMs : Date.now(),
              "deadlineMs": Date.now() + 30000,
              "pozycja": null,
              "pi": null,
              "czekaNaFoto": false
            });
        }
        kotwice = kotwice;
        haptyka(15);
        pendingLayer = null;
        pendingFeature = null;
        obsluzKotwice();
        return;
      }
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
      quickCaptureBar.odroczenieFlow = false;
      // kotwica: porzucone zdjecie = porzucony lapacz (najnowszy czekajacy)
      for (let i = quickCaptureBar.kotwice.length - 1; i >= 0; --i) {
        if (quickCaptureBar.kotwice[i].czekaNaFoto) {
          quickCaptureBar.kotwice.splice(i, 1);
          quickCaptureBar.kotwice = quickCaptureBar.kotwice;
          break;
        }
      }
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
      quickCaptureBar.kotwice = [];
      if (quickCaptureBar.odroczone.length > 0) {
        displayToast(qsTr("Kolejka odroczeń wyczyszczona przy zamknięciu projektu (%1) — zdjęcia zostały w DCIM").arg(quickCaptureBar.odroczone.length), "warning");
        quickCaptureBar.odroczone = [];
      }
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
            if (stateMachine.state === "digitize" && dashBoard.activeLayer === modelData.layer) {
              // drugie tapniecie tego samego kafla = powrot do przegladania
              stateMachine.state = "browse";
              displayToast(qsTr("Przeglądanie"), "info");
            } else {
              dashBoard.activeLayer = modelData.layer;
              stateMachine.state = "digitize";
              displayToast(modelData.tooltip, "info");
            }
          } else {
            if (stateMachine.state === "digitize") {
              stateMachine.state = "browse";
            }
            quickCaptureBar.captureInto(modelData.layer, modelData.bezZdjecia === true);
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
          model: quickCaptureBar.distancePresets

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
      onClicked: photoGallery.openPhotos()
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
