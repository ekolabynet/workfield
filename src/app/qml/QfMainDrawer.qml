import QtCore
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import QtQuick.Dialogs
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import org.qgis
import Theme

/**
 * \ingroup qml
 *
 * WorkField main (left) drawer. Clean reimplementation of DashBoard with
 * bottom tabs: Legenda / Narzędzia / Ustawienia / Pomoc.
 * Keeps the public contract of DashBoard (signals, aliases) so the rest of
 * the application can keep addressing it as `dashBoard`.
 */
Drawer {
  id: dashBoard

  property var t: Theme

  onOpenedChanged: {
    if (opened) {
      projectSection.refresh();
    }
    // WorkField: dokowany panel pamięta stan między sesjami (komputer)
    if (!modal) {
      settings.setValue('WorkField/lewyPanelOtwarty', opened);
    }
  }

  property var pendingBlankCenter: null
  property bool pendingBlankSetup: false

  function requestDem(demType) {
    demDownloader.request(demType);
  }

  function computeChmAction() {
    demDownloader.computeChm();
  }
  objectName: "dashBoard"

  signal showMainMenu(point p)
  signal showBookmarks
  signal showPluginManager
  signal showSettings
  signal showMessageLog
  signal lockScreen
  signal showAbout
  signal showPrintLayouts(point p)
  signal showCloudPopup
  signal showProjectFolder
  signal toggleMeasurementTool
  signal toggle3DView
  signal returnHome

  //! WorkField: sekcja wskazywana przez menu (komputer); -1 = wg zakładek
  property int sekcjaWymuszona: -1

  function otworzSekcje(numer) {
    sekcjaWymuszona = numer;
    open();
  }

  // WorkField: przyciąganie per warstwa. UWAGA na pułapkę silnika:
  // setData dla roli SnappingEnabled IGNORUJE wartość i zawsze
  // przełącza — dlatego najpierw czytamy stan i piszemy tylko wtedy,
  // gdy trzeba go zmienić.
  function ustawMagnesWarstwy(warstwa, wlaczony) {
    const m = dashBoard.layerTree;
    for (let i = 0; i < m.rowCount(); i++) {
      const idx = m.index(i, 0);
      if (m.data(idx, FlatLayerTreeModel.VectorLayerPointer) === warstwa) {
        if ((m.data(idx, FlatLayerTreeModel.SnappingEnabled) === true) !== wlaczony) {
          m.setData(idx, wlaczony, FlatLayerTreeModel.SnappingEnabled);
          projectInfo.saveLayerSnappingConfiguration(warstwa);
        }
        return true;
      }
    }
    console.log("WorkField magnes: warstwa nie znaleziona w modelu (" + (warstwa && warstwa.name ? warstwa.name : "?") + ")");
    return false;
  }

  // tap magnesa w wierszu warstwy: pierwszy raz przełącza projekt
  // w tryb magnesów i chroni rysowaną warstwę, potem zwykły przełącznik
  function przelaczMagnesWarstwy(warstwa, nazwa) {
    let cfg = qgisProject.snappingConfig;
    if (cfg.mode !== Qgis.SnappingMode.AdvancedConfiguration) {
      cfg.mode = Qgis.SnappingMode.AdvancedConfiguration;
      cfg.enabled = true;
      qgisProject.snappingConfig = cfg;
      if (qgisProject.snappingConfig.mode !== Qgis.SnappingMode.AdvancedConfiguration) {
        // zapis trybu z QML-a nie przeszedł — plan B do osobnej decyzji
        displayToast(qsTr("Nie udało się przełączyć trybu przyciągania"), "error");
        return;
      }
      projectInfo.snappingEnabled = true;
      // QGIS przy przejściu w tryb zaawansowany zapala WSZYSTKIE
      // warstwy — sprowadzamy to jawnie do zasady WorkField:
      // rysowana warstwa + tapnięty podkład, reszta zgaszona
      const m0 = dashBoard.layerTree;
      const n0 = m0.rowCount();
      for (let i0 = 0; i0 < n0; i0++) {
        const idx0 = m0.index(i0, 0);
        const wsk0 = m0.data(idx0, FlatLayerTreeModel.VectorLayerPointer);
        if (!wsk0)
          continue;
        const chcemy = wsk0 === warstwa || wsk0 === dashBoard.activeLayer;
        if ((m0.data(idx0, FlatLayerTreeModel.SnappingEnabled) === true) !== chcemy)
          m0.setData(idx0, chcemy, FlatLayerTreeModel.SnappingEnabled);
        projectInfo.saveLayerSnappingConfiguration(wsk0);
      }
      displayToast(qsTr("Dociąganie: rysowana warstwa + %1").arg(nazwa));
      return;
    }
    if (!cfg.enabled) {
      cfg.enabled = true;
      qgisProject.snappingConfig = cfg;
      projectInfo.snappingEnabled = true;
    }
    const m = dashBoard.layerTree;
    for (let i = 0; i < m.rowCount(); i++) {
      const idx = m.index(i, 0);
      if (m.data(idx, FlatLayerTreeModel.VectorLayerPointer) === warstwa) {
        const bylo = m.data(idx, FlatLayerTreeModel.SnappingEnabled) === true;
        m.setData(idx, !bylo, FlatLayerTreeModel.SnappingEnabled);
        projectInfo.saveLayerSnappingConfiguration(warstwa);
        displayToast(!bylo ? qsTr("Dociąganie do: %1").arg(nazwa) : qsTr("Bez dociągania do: %1").arg(nazwa));
        return;
      }
    }
  }

  //! WorkField: pozycja menu panelu — ikona Breeze + etykieta z lewej.
  component QfPozycjaMenu: Button {
    id: pozycja

    property string ikona: ""

    flat: true
    Layout.fillWidth: true
    implicitHeight: 34
    font.pointSize: t.tinyFont.pointSize

    contentItem: RowLayout {
      spacing: 10

      Image {
        id: obrazIkony
        source: pozycja.ikona !== "" ? t.getThemeVectorIcon(pozycja.ikona) : ""
        sourceSize: Qt.size(22, 22)
        visible: false
      }
      MultiEffect {
        // barwienie ikony kolorem tekstu motywu: jasne w ciemnym, ciemne w jasnym
        Layout.leftMargin: 6
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        source: obrazIkony
        colorization: 1.0
        colorizationColor: t.mainTextColor
        opacity: pozycja.enabled ? 1.0 : 0.4
      }
      Text {
        Layout.fillWidth: true
        text: pozycja.text
        font: pozycja.font
        color: pozycja.enabled ? t.mainTextColor : t.secondaryTextColor
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  property bool preventFromOpening: overlayFeatureFormDrawer.visible
  property bool allowInteractive: true
  property bool shouldReturnHome: false
  /// type:bool
  property alias allowActiveLayerChange: legend.allowActiveLayerChange
  /// type:QgsVectorLayer
  property alias activeLayer: legend.activeLayer
  /// type:FlatLayerTreeModel
  property alias layerTree: legend.model
  /// type:QgsQuickMapSettings
  property MapSettings mapSettings

  Component.onCompleted: {
    if (Material.roundedScale) {
      Material.roundedScale = Material.NotRounded;
    }
  }

  width: Qt.platform.os !== "android" && Qt.platform.os !== "ios" ? Math.max(380, Math.round(mainWindow.width * 0.25)) : Math.min(Math.max(330, mainWindow.width * 0.8), mainWindow.width)
  height: parent.height
  edge: Qt.LeftEdge
  // WorkField: na komputerze panel jest DOKOWANY — nie przyciemnia mapy,
  // nie zamyka się od kliknięcia poza nim i zostaje otwarty; mapa zwęża
  // się o jego szerokość (patrz mapCanvas w qgismobileapp.qml)
  modal: Qt.platform.os === "android" || Qt.platform.os === "ios"
  dim: modal
  closePolicy: modal ? Popup.CloseOnEscape | Popup.CloseOnPressOutside : Popup.CloseOnEscape
  dragMargin: modal ? 10 : 0
  interactive: allowInteractive && modal

  onSekcjaWymuszonaChanged: {
    if (!modal && sekcjaWymuszona >= 0) {
      settings.setValue('WorkField/lewyPanelSekcja', sekcjaWymuszona);
    }
  }

  topPadding: 0
  leftPadding: 0
  rightPadding: 0
  bottomPadding: 0

  position: 0
  focus: visible
  clip: true

  QtObject {
    id: demDownloader

    property int active: 0
    property var mosaicBbox: null
    property string activeType: ""
    property string areaName: "Obszar 1"
    property int areaCounter: 1

    property string pendingType: ""

    function request(type) {
      pendingType = type;
      demScopeDialog.open();
    }

    function requestScoped(type, newestOnly) {
      const services = type === "NMT" ? ["https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMT/WMS/SkorowidzeUkladKRON86?", "https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMT/WMS/SkorowidzeUkladEVRF2007?"] : ["https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMPT/WMS/SkorowidzeUkladKRON86?", "https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMPT/WMS/SkorowidzeUkladEVRF2007?"];
      const points = iface.visibleExtentPointsIn2180(dashBoard.mapSettings, 2);
      if (points.length === 0) {
        displayToast(qsTr("Nie udalo sie wyznaczyc zasiegu mapy"), "warning");
        return;
      }
      let bx0 = points[0].x;
      let by0 = points[0].y;
      let bx1 = points[0].x;
      let by1 = points[0].y;
      for (const pt of points) {
        bx0 = Math.min(bx0, pt.x);
        by0 = Math.min(by0, pt.y);
        bx1 = Math.max(bx1, pt.x);
        by1 = Math.max(by1, pt.y);
      }
      const bufferMeters = Math.max(100, (bx1 - bx0) * 0.1);
      mosaicBbox = { "xmin": bx0 - bufferMeters, "ymin": by0 - bufferMeters, "xmax": bx1 + bufferMeters, "ymax": by1 + bufferMeters };
      activeType = type;
      displayToast(qsTr("Szukam arkuszy %1 dla obszaru mapy...").arg(type));
      queryService(services, 0, points, type, newestOnly);
    }

    function queryService(services, serviceIndex, points, type, newestOnly) {
      if (serviceIndex >= services.length) {
        displayToast(qsTr("Nie znaleziono arkuszy %1 dla tego obszaru").arg(type), "warning");
        return;
      }
      const serviceUrl = services[serviceIndex];
      const capsXhr = new XMLHttpRequest();
      capsXhr.onreadystatechange = function () {
        if (capsXhr.readyState !== XMLHttpRequest.DONE) {
          return;
        }
        const layerMatches = capsXhr.responseText.match(/<Name>([^<]+)<\/Name>/g) || [];
        const layers = layerMatches.map(m => m.replace(/<\/?Name>/g, "")).filter(n => n.indexOf("Skorowidze") === 0);
        console.log("DEM caps:", serviceUrl, "-> warstwy:", layers.join("|"));
        if (layers.length === 0) {
          queryService(services, serviceIndex + 1, points, type, newestOnly);
          return;
        }
        const layersSorted = layers.slice().sort(function (a, b) {
          const ya = parseInt((a.match(/(\d{4})/) || [0, "0"])[1]);
          const yb = parseInt((b.match(/(\d{4})/) || [0, "0"])[1]);
          return yb - ya;
        });
        collectLayered(serviceUrl, layersSorted, 0, points, 0, {}, type, services, serviceIndex, newestOnly);
      };
      capsXhr.open("GET", serviceUrl + "SERVICE=WMS&request=GetCapabilities");
      capsXhr.send();
    }

    function godloFromUrl(u) {
      const m = u.match(/[A-Z]-\d{2}-[0-9A-Za-z-]+/);
      return m ? m[0] : u;
    }

    function collectLayered(serviceUrl, layersSorted, layerIndex, points, pointIndex, found, type, services, serviceIndex, newestOnly) {
      if (layerIndex >= layersSorted.length) {
        const urls = [];
        for (const key in found) {
          urls.push(found[key]);
        }
        console.log("DEM: znaleziono URL-i:", urls.length);
        if (urls.length === 0) {
          queryService(services, serviceIndex + 1, points, type, newestOnly);
          return;
        }
        startDownloads(urls, type);
        return;
      }
      if (pointIndex >= points.length) {
        collectLayered(serviceUrl, layersSorted, layerIndex + 1, points, 0, found, type, services, serviceIndex, newestOnly);
        return;
      }
      const pt = points[pointIndex];
      const bbox = (pt.y - 50) + "," + (pt.x - 50) + "," + (pt.y + 50) + "," + (pt.x + 50);
      const layerParam = encodeURIComponent(layersSorted[layerIndex]);
      const url = serviceUrl + "SERVICE=WMS&request=GetFeatureInfo&version=1.3.0&styles=&crs=EPSG:2180&width=101&height=101&format=image/png&transparent=true&i=50&j=50&INFO_FORMAT=text/html&layers=" + layerParam + "&query_layers=" + layerParam + "&bbox=" + bbox;
      const xhr = new XMLHttpRequest();
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) {
          return;
        }
        const matches = xhr.responseText.match(/https?:\/\/[^"'<>\s]+\.(asc|tif|tiff|zip)/g) || [];
        for (const u of matches) {
          if (newestOnly) {
            const g = godloFromUrl(u);
            if (!found[g]) {
              found[g] = u;
            }
          } else {
            found[u] = u;
          }
        }
        collectLayered(serviceUrl, layersSorted, layerIndex, points, pointIndex + 1, found, type, services, serviceIndex, newestOnly);
      };
      xhr.open("GET", url);
      xhr.send();
    }
    function godloOf(fileName) {
      const m = fileName.match(/[A-Z]-\d{2}-[0-9A-Za-z-]+/);
      return m ? m[0] : "";
    }

    function computeChm() {
      const home = qgisProject.homePath;
      const nmtMosaics = iface.listFiles(home + "/NMT", "NMT_*.tif");
      const nmptMosaics = iface.listFiles(home + "/NMPT", "NMPT_*.tif");
      const nmptSet = {};
      for (const m of nmptMosaics) {
        nmptSet[m.replace("NMPT_", "")] = m;
      }
      const mosaicPairs = [];
      for (const m of nmtMosaics) {
        const suffix = m.replace("NMT_", "");
        if (nmptSet[suffix]) {
          mosaicPairs.push({ "suffix": suffix, "nmt": m, "nmpt": nmptSet[suffix] });
        }
      }
      if (mosaicPairs.length > 0) {
        displayToast(qsTr("Licze CHM z mozaik: %1 obszarow...").arg(mosaicPairs.length));
        Qt.callLater(function () {
          let doneMosaics = 0;
          for (const pair of mosaicPairs) {
            const chmOut = home + "/CHM/CHM_" + pair.suffix;
            const areaLabel = pair.suffix.replace(".tif", "").replace(/_/g, " ");
            if (iface.rasterDifference(home + "/NMPT/" + pair.nmpt, home + "/NMT/" + pair.nmt, chmOut) && iface.addRasterLayerToProject(chmOut, areaLabel + " CHM", "EPSG:2180", "chm", areaLabel)) {
              doneMosaics++;
            }
          }
          displayToast(qsTr("CHM gotowe: %1 z %2 obszarow").arg(doneMosaics).arg(mosaicPairs.length));
        });
        return;
      }
      const nmtFiles = iface.listFiles(home + "/NMT", "*.asc").concat(iface.listFiles(home + "/NMT", "*.tif"));
      const nmptFiles = iface.listFiles(home + "/NMPT", "*.asc").concat(iface.listFiles(home + "/NMPT", "*.tif"));
      if (nmtFiles.length === 0 || nmptFiles.length === 0) {
        displayToast(qsTr("Najpierw pobierz NMT i NMPT dla obszaru (foldery NMT/ i NMPT/ w projekcie)"), "warning");
        return;
      }
      const nmtByGodlo = {};
      for (const f of nmtFiles) {
        const g = godloOf(f);
        if (g !== "") {
          nmtByGodlo[g] = f;
        }
      }
      const pairsList = [];
      for (const f of nmptFiles) {
        const g = godloOf(f);
        if (g !== "" && nmtByGodlo[g]) {
          pairsList.push({ "godlo": g, "nmpt": home + "/NMPT/" + f, "nmt": home + "/NMT/" + nmtByGodlo[g], "out": home + "/CHM/CHM_" + g + ".tif" });
        }
      }
      if (pairsList.length === 0) {
        displayToast(qsTr("Brak par NMT/NMPT o wspólnym godle — pobierz oba modele dla tego samego obszaru"), "warning");
        return;
      }
      displayToast(qsTr("CHM: %1 par arkuszy w kolejce…").arg(pairsList.length));
      processChmPair(pairsList, 0, 0);
    }

    function processChmPair(pairsList, index, done) {
      if (index >= pairsList.length) {
        displayToast(qsTr("CHM gotowe: %1 z %2 arkuszy").arg(done).arg(pairsList.length));
        return;
      }
      const pair = pairsList[index];
      if (iface.listFiles(qgisProject.homePath + "/CHM", "CHM_" + pair.godlo + ".tif").length > 0) {
        displayToast(qsTr("CHM %1 już policzony — wczytuję").arg(pair.godlo));
        const okExisting = iface.addRasterLayerToProject(pair.out, "CHM " + pair.godlo, "EPSG:2180", "chm");
        Qt.callLater(function () {
          processChmPair(pairsList, index + 1, done + (okExisting ? 1 : 0));
        });
        return;
      }
      displayToast(qsTr("Liczę CHM %1 (%2/%3) — to potrwa…").arg(pair.godlo).arg(index + 1).arg(pairsList.length));
      Qt.callLater(function () {
        let ok = false;
        if (iface.rasterDifference(pair.nmpt, pair.nmt, pair.out)) {
          ok = iface.addRasterLayerToProject(pair.out, "CHM " + pair.godlo, "EPSG:2180", "chm");
        }
        Qt.callLater(function () {
          processChmPair(pairsList, index + 1, done + (ok ? 1 : 0));
        });
      });
    }
    function mergeMosaic(type) {
      if (!mosaicBbox) {
        return;
      }
      const home = qgisProject.homePath;
      const names = iface.listFiles(home + "/" + type, "*.asc").concat(iface.listFiles(home + "/" + type, "*.tif"));
      const inputs = [];
      for (const n of names) {
        if (n.indexOf("_obszar") === -1) {
          inputs.push(home + "/" + type + "/" + n);
        }
      }
      if (inputs.length === 0) {
        return;
      }
      displayToast(qsTr("Skladam mozaike %1 z %2 arkuszy...").arg(type).arg(inputs.length));
      const areaSafe = areaName.replace(/[^\w-]/g, "_");
      const outPath = home + "/" + type + "/" + type + "_" + areaSafe + ".tif";
      Qt.callLater(function () {
        if (iface.clipMergeRasters(inputs, mosaicBbox.xmin, mosaicBbox.ymin, mosaicBbox.xmax, mosaicBbox.ymax, outPath)) {
          if (iface.addRasterLayerToProject(outPath, areaName + " " + type, "EPSG:2180", "", areaName)) {
            displayToast(qsTr("%1 %2 gotowe - jedna warstwa, wspolna skala barw").arg(areaName).arg(type));
            areaCounter++;
          }
        } else {
          displayToast(qsTr("Nie udalo sie zlozyc mozaiki %1").arg(type), "error");
        }
      });
    }
    function startDownloads(urls, type) {
      const capped = urls.slice(0, 4);
      if (urls.length > 4) {
        displayToast(qsTr("Obszar obejmuje %1 arkuszy - pobieram pierwsze 4 (przybliz mape po reszte)").arg(urls.length), "warning");
      } else {
        displayToast(qsTr("Pobieram %1: %2 arkuszy (duze pliki, to potrwa)...").arg(type).arg(capped.length));
      }
      for (const u of capped) {
        const fileName = u.split("/").pop();
        active++;
        iface.downloadFile(u, qgisProject.homePath + "/" + type + "/" + fileName);
      }
    }
  }

  Dialog {
    id: demScopeDialog

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 400)
    modal: true
    title: qsTr("Zakres pobierania %1").arg(demDownloader.pendingType)

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Label {
        Layout.fillWidth: true
        text: qsTr("Skorowidze GUGiK dzielą arkusze na roczniki. Które pobrać?")
        font: Theme.defaultFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
          text: qsTr("Nazwa obszaru:")
          font: Theme.tipFont
          color: Theme.secondaryTextColor
        }

        TextField {
          id: areaNameField
          Layout.fillWidth: true
          font: Theme.defaultFont
          text: demDownloader.areaName
        }
      }
      Button {
        Layout.fillWidth: true
        text: qsTr("Najnowsze arkusze")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: {
          demDownloader.areaName = areaNameField.text.trim() !== "" ? areaNameField.text.trim() : "Obszar " + demDownloader.areaCounter;
          demScopeDialog.close();
          demDownloader.requestScoped(demDownloader.pendingType, true);
        }
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Wszystkie roczniki")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: {
          demDownloader.areaName = areaNameField.text.trim() !== "" ? areaNameField.text.trim() : "Obszar " + demDownloader.areaCounter;
          demScopeDialog.close();
          demDownloader.requestScoped(demDownloader.pendingType, false);
        }
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: demScopeDialog.close()
      }
    }
  }

  Connections {
    target: iface

    function onLoadProjectEnded(path, name) {

      if (!dashBoard.pendingBlankSetup) {
        return;
      }
      dashBoard.pendingBlankSetup = false;
      iface.setProjectCrs("EPSG:2178");
      iface.addXyzBasemap("Esri World Imagery", "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", 19);
      if (dashBoard.pendingBlankCenter) {
        const c = iface.transformPointToProjectCrs(dashBoard.pendingBlankCenter.x, dashBoard.pendingBlankCenter.y, "EPSG:2180");
        if (c.x !== undefined) {
          // extent oczekuje QgsRectangle - Qt.rect() daje QRectF i nie przechodzi
          mapCanvas.mapSettings.setExtentFromPoints([GeometryUtils.point(c.x - 50, c.y - 50), GeometryUtils.point(c.x + 50, c.y + 50)]);
        }
      }
    }

    function onDownloadFinished(path) {
      if (demDownloader.active <= 0) {
        return;
      }
      demDownloader.active--;
      const fileName = path.split("/").pop();
      displayToast(qsTr("Pobrano %1").arg(fileName));
      if (demDownloader.active === 0 && demDownloader.activeType !== "") {
        demDownloader.mergeMosaic(demDownloader.activeType);
      }
    }

    function onDownloadFailed(error, path) {
      if (demDownloader.active <= 0) {
        return;
      }
      demDownloader.active--;
      displayToast(qsTr("Blad pobierania: %1").arg(error), "error");
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.topMargin: mainWindow.sceneTopMargin
    anchors.bottomMargin: mainWindow.sceneBottomMargin
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("WorkField")
        font: Theme.strongFont
        color: Theme.mainTextColor
      }

      QfToolButton {
        width: 36
        height: 36
        padding: 0
        bgcolor: "transparent"
        iconSource: Theme.getThemeVectorIcon("ic_arrow_left_black_24dp")
        iconColor: Theme.mainTextColor
        onClicked: dashBoard.close()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
    }

    // WorkField: poziomy przełącznik widoków panelu (komputer);
    // ikona + nazwa, bo etykieta bije zgadywanie
    RowLayout {
      visible: Qt.platform.os !== "android" && Qt.platform.os !== "ios"
      Layout.fillWidth: true
      Layout.leftMargin: 4
      Layout.rightMargin: 4
      spacing: 2

      Repeater {
        model: [{ "nazwa": qsTr("Magazyn"), "ikona": "wfg_magazyn", "sekcja": 0 }, { "nazwa": qsTr("Projekt"), "ikona": "wfg_nowe", "sekcja": 1 }, { "nazwa": qsTr("Warstwy"), "ikona": "wfg_warstwy", "sekcja": 2 }, { "nazwa": qsTr("Stylizacja"), "ikona": "wfg_stylizacja", "sekcja": 3 }]

        delegate: ItemDelegate {
          id: przelacznikWidoku

          required property var modelData

          readonly property bool aktywny: dashStack.currentIndex === modelData.sekcja

          Layout.fillWidth: true
          Layout.preferredHeight: 34
          padding: 0

          background: Rectangle {
            color: przelacznikWidoku.aktywny ? Theme.mainColor : "transparent"
            radius: 5
          }

          contentItem: RowLayout {
            spacing: 5

            Item {
              Layout.fillWidth: true
            }

            Image {
              id: ikonaWidoku
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16
              fillMode: Image.PreserveAspectFit
              sourceSize.width: 16
              sourceSize.height: 16
              source: Theme.getThemeVectorIcon(przelacznikWidoku.modelData.ikona)
              visible: false
            }

            MultiEffect {
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16
              source: ikonaWidoku
              colorization: 1.0
              colorizationColor: przelacznikWidoku.aktywny ? "white" : Theme.mainTextColor
              brightness: 0.2
            }

            Text {
              text: przelacznikWidoku.modelData.nazwa
              font: Theme.tinyFont
              color: przelacznikWidoku.aktywny ? "white" : Theme.mainTextColor
            }

            Item {
              Layout.fillWidth: true
            }
          }

          onClicked: dashBoard.sekcjaWymuszona = modelData.sekcja
        }
      }
    }

    TabBar {
      id: dashTabs

      // WorkField: na komputerze sekcje wybiera menu (otworzSekcje),
      // zakładki zostają narzędziem telefonu
      visible: Qt.platform.os === "android" || Qt.platform.os === "ios"
      Layout.fillWidth: true
      Layout.preferredHeight: visible ? implicitHeight : 0
      currentIndex: 1

      TabButton {
        text: qsTr("Magazyn")
        font: Theme.tipFont
        visible: Qt.platform.os !== "android" && Qt.platform.os !== "ios"
        width: visible ? implicitWidth : 0
      }
      TabButton {
        text: qsTr("Projekt")
        font: Theme.tipFont
      }
      TabButton {
        text: qsTr("Warstwy")
        font: Theme.tipFont
      }
      TabButton {
        text: qsTr("Stylizacja")
        font: Theme.tipFont
      }
    }

    StackLayout {
      id: dashStack

      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: dashBoard.sekcjaWymuszona >= 0 ? dashBoard.sekcjaWymuszona : dashTabs.currentIndex

      // ── Magazyn (0, tylko desktop) ──────────────────────────────
      Loader {
        active: Qt.platform.os !== "android" && Qt.platform.os !== "ios"
        sourceComponent: QfStudioSection {
        }
      }

      // ── Projekt ─────────────────────────────────────────────
      ColumnLayout {
        spacing: 0

        ColumnLayout {
          id: projectSection

      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 4

      property bool dirty: false
      property string filePath: ""

      function refresh() {
        dirty = ProjectUtils.isProjectDirty(qgisProject);
        filePath = qgisProject ? ProjectUtils.projectFilePath(qgisProject) : "";
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: mainWindow.projectTitle !== "" ? mainWindow.projectTitle : qsTr("Projekt")
          font: t.strongTipFont
          color: t.mainTextColor
          elide: Text.ElideRight
        }

        Text {
          text: projectSection.dirty ? qsTr("niezapisane zmiany") : ""
          font: t.tinyFont
          color: t.warningColor
        }
      }

      Text {
        Layout.fillWidth: true
        text: projectSection.filePath !== "" ? FileUtils.fileName(projectSection.filePath) : qsTr("projekt niezapisany")
        font: t.tinyFont
        color: t.secondaryTextColor
        elide: Text.ElideMiddle
      }

      // ── aktywność: zdjęcia DCIM z ostatnich 14 dni (słupki) ──
      ColumnLayout {
        id: aktywnosc

        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 2
        visible: projectSection.filePath !== "" && aktywnosc.suma > 0

        property var slupki: []
        property int suma: 0
        property int maks: 1

        FolderListModel {
          id: dcimAktywnosc
          folder: projectSection.filePath !== ""
                  ? "file://" + FileUtils.absolutePath(projectSection.filePath) + "/DCIM"
                  : ""
          nameFilters: ["*.jpg", "*.jpeg"]
          showDirs: false
          onCountChanged: aktywnosc.przelicz()
        }

        function przelicz() {
          const dni = [];
          const klucze = {};
          const teraz = new Date();
          for (let i = 13; i >= 0; i--) {
            const d = new Date(teraz.getTime() - i * 86400000);
            const k = d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
            klucze[k] = dni.length;
            dni.push(0);
          }
          let razem = 0;
          for (let j = 0; j < dcimAktywnosc.count; j++) {
            const m = /_(20[0-9]{6})_/.exec(dcimAktywnosc.get(j, "fileName"));
            razem++;
            if (m && klucze[parseInt(m[1])] !== undefined)
              dni[klucze[parseInt(m[1])]]++;
          }
          suma = razem;
          maks = Math.max(1, Math.max.apply(null, dni));
          slupki = dni;
          plotnoAktywnosci.requestPaint();
        }

        Text {
          Layout.fillWidth: true
          text: qsTr("Aktywność · %1 zdjęć w projekcie").arg(aktywnosc.suma)
          font: t.tinyFont
          color: t.secondaryTextColor
        }
        Canvas {
          id: plotnoAktywnosci

          Layout.fillWidth: true
          Layout.preferredHeight: 34

          onWidthChanged: requestPaint()
          onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const n = aktywnosc.slupki.length;
            if (n === 0)
              return;
            const krok = width / n;
            for (let i = 0; i < n; i++) {
              const w = aktywnosc.slupki[i];
              const h = w > 0 ? Math.max(3, (height - 2) * w / aktywnosc.maks) : 1;
              ctx.fillStyle = w > 0 ? t.mainColor : "#d0d0d0";
              ctx.fillRect(i * krok + 1, height - h, Math.max(2, krok - 2), h);
            }
          }
        }
      }

      // ── Stan zleceń: dashboard nad masterem (docs/MAGAZYN.md) ──
      ColumnLayout {
        id: stanZlecen

        Layout.fillWidth: true
        Layout.topMargin: 10
        spacing: 4
        visible: Qt.platform.os !== "android" && Qt.platform.os !== "ios"

        property var stan: null

        Settings {
          id: ustawieniaStanu
          category: "WFGStudio"
          property string korzenProjektow: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/WorkField"
        }
        ProcesyStudio {
          id: procesyStanu
        }

        function odswiez() {
          const surowe = procesyStanu.czytajTekst(ustawieniaStanu.korzenProjektow + "/dziennik/stan.json");
          if (surowe === "") {
            stan = null;
            return;
          }
          try {
            stan = JSON.parse(surowe);
          } catch (e) {
            stan = null;
          }
        }

        Component.onCompleted: odswiez()

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          Text {
            Layout.fillWidth: true
            text: qsTr("Stan zleceń")
                  + (stanZlecen.stan ? "  ·  " + stanZlecen.stan.wygenerowano : "")
            font: t.strongTipFont
            color: t.mainTextColor
            elide: Text.ElideRight
          }
          Button {
            flat: true
            text: qsTr("Odśwież")
            font.pointSize: t.tinyFont.pointSize
            onClicked: stanZlecen.odswiez()
          }
        }

        Text {
          Layout.fillWidth: true
          visible: stanZlecen.stan === null
          text: qsTr("Brak dziennik/stan.json — uruchom generuj_stan.py i kliknij Odśwież")
          font: t.tinyFont
          color: t.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: stanZlecen.stan ? stanZlecen.stan.zlecenia : []

          delegate: Rectangle {
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: kolumnaKarty.implicitHeight + 12
            radius: 6
            color: modelData.w_terenie > 0 ? Qt.alpha(t.warningColor, 0.10)
                                           : Qt.alpha(t.mainColor, 0.06)
            border.color: modelData.w_terenie > 0 ? Qt.alpha(t.warningColor, 0.5)
                                                  : Qt.alpha(t.mainColor, 0.25)

            ColumnLayout {
              id: kolumnaKarty
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: 8
              spacing: 2

              RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                  Layout.fillWidth: true
                  text: modelData.zamawiajacy + " · " + modelData.obszar + " "
                        + modelData.id + " · " + modelData.zadanie
                  font: t.tipFont
                  color: t.mainTextColor
                  elide: Text.ElideRight
                }
                Text {
                  visible: modelData.w_terenie > 0
                  text: qsTr("w terenie: %1").arg(modelData.w_terenie)
                  font: t.tinyFont
                  color: t.warningColor
                }
              }
              Text {
                Layout.fillWidth: true
                text: qsTr("wydań %1 · ostatni zwrot: %2")
                      .arg(modelData.wydania.length)
                      .arg(modelData.ostatni_zwrot !== "" ? modelData.ostatni_zwrot : "—")
                font: t.tinyFont
                color: t.secondaryTextColor
                elide: Text.ElideRight
              }
              Text {
                Layout.fillWidth: true
                visible: modelData.master !== null && modelData.master.liczniki !== undefined
                         && modelData.master.liczniki.FITO_TOPOSEKTORY !== undefined
                text: modelData.master !== null && modelData.master.liczniki !== undefined
                      ? qsTr("master: topo %1 · płaty %2 · spis %3 · zdj %4")
                        .arg(modelData.master.liczniki.FITO_TOPOSEKTORY || 0)
                        .arg(modelData.master.liczniki.FITO_PLATY || 0)
                        .arg(modelData.master.liczniki.FITO_SPIS_GATUNKOWY || 0)
                        .arg(modelData.master.liczniki.FITO_ZDJECIA || 0)
                      : ""
                font: t.tinyFont
                color: t.secondaryTextColor
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6

        Text {
          Layout.fillWidth: true
          text: qsTr("Wszystkie projekty")
          font: t.tinyFont
          color: t.secondaryTextColor
        }
        ToolButton {
          // przełącznik układu: lista (menu) / siatka dwukolumnowa
          text: ustawieniaPanelu.ukladMenu === 0 ? "\u25a4" : "\u25a6"
          font.pointSize: t.tinyFont.pointSize
          implicitHeight: 24
          onClicked: ustawieniaPanelu.ukladMenu = ustawieniaPanelu.ukladMenu === 0 ? 1 : 0
        }
      }
      Settings {
        id: ustawieniaPanelu
        category: "WFGPanel"
        // 0 = lista jak klasyczne menu (decyzja 2026-08-10), 1 = siatka
        property int ukladMenu: 0
      }
      GridLayout {
        Layout.fillWidth: true
        columns: ustawieniaPanelu.ukladMenu === 0 ? 1 : 2
        columnSpacing: 4
        rowSpacing: 2

        QfPozycjaMenu {
          text: qsTr("Magazyn")
          ikona: "wfg_magazyn"
          onClicked: dashBoard.sekcjaWymuszona = 0
        }
        QfPozycjaMenu {
          text: qsTr("Nowe zadanie")
          ikona: "wfg_nowe"
          onClicked: {
            // szablon + kontekst zlecenia = nowe zadanie z własnym katalogiem
            dashBoard.close();
            noweZadanie.open();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Otwórz projekt")
          ikona: "wfg_otworz"
          onClicked: {
            dashBoard.close();
            // przepływ (docs/MAGAZYN.md): żywe projekty biurka mieszkają
            // w wydaniach magazynu; na telefonie — w domu danych aplikacji
            if (Qt.platform.os === "android" || Qt.platform.os === "ios")
              photoGallery.openFiles(iface.dataRoot() + "Imported Projects");
            else
              photoGallery.openFiles(ustawieniaStanu.korzenProjektow + "/wydania");
          }
        }
        QfPozycjaMenu {
          text: qsTr("Importuj projekt (folder)")
          ikona: "wfg_import"
          onClicked: {
            dashBoard.close();
            platformUtilities.importProjectFolder();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Importuj projekt (ZIP)")
          ikona: "wfg_paczka"
          onClicked: {
            dashBoard.close();
            platformUtilities.importProjectArchive();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Pobierz szablony")
          ikona: "wfg_chmura"
          onClicked: {
            dashBoard.close();
            photoGallery.openCloud();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Ekran startowy")
          ikona: "wfg_dom"
          onClicked: {
            dashBoard.close();
            returnHome();
          }
        }
      }
      Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: qsTr("Bieżący projekt")
        font: t.tinyFont
        color: t.secondaryTextColor
        opacity: projectSection.filePath !== "" ? 1.0 : 0.4
      }
      GridLayout {
        Layout.fillWidth: true
        columns: ustawieniaPanelu.ukladMenu === 0 ? 1 : 2
        columnSpacing: 4
        rowSpacing: 2

        QfPozycjaMenu {
          text: qsTr("Zapisz")
          ikona: "wfg_zapisz"
          enabled: projectSection.filePath !== ""
          onClicked: {
            if (ProjectUtils.saveProject(qgisProject)) {
              displayToast(qsTr("Projekt zapisany"));
              projectSection.refresh();
            } else {
              displayToast(qsTr("Nie udało się zapisać projektu"));
            }
          }
        }
        QfPozycjaMenu {
          text: qsTr("Zapisz jako…")
          ikona: "wfg_zapisz_jako"
          enabled: projectSection.filePath !== ""
          onClicked: projectNameDialog.openFor("saveas")
        }
        QfPozycjaMenu {
          text: qsTr("Powiększ do danych")
          ikona: "wfg_powieksz"
          enabled: projectSection.filePath !== ""
          onClicked: {
            if (!iface.zoomToProjectData(dashBoard.mapSettings)) {
              const c = dashBoard.mapSettings.getCenter();
              dashBoard.mapSettings.setExtentFromPoints([GeometryUtils.point(c.x - 500, c.y - 500), GeometryUtils.point(c.x + 500, c.y + 500)]);
            }
            dashBoard.close();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Pliki projektu")
          ikona: "wfg_przeglad"
          enabled: projectSection.filePath !== ""
          onClicked: {
            // nasza galeria, zakladka Pliki - jedno narzedzie do ogladania
            // zawartosci zamiast przegladarki QFielda
            dashBoard.close();
            photoGallery.openFiles(qgisProject ? qgisProject.homePath : "");
          }
        }
        QfPozycjaMenu {
          text: qsTr("Wymiana lokalna")
          ikona: "wfg_wymiana"
          onClicked: {
            dashBoard.close();
            wymianaLokalna.open();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Właściwości")
          ikona: "wfg_wlasciwosci"
          enabled: projectSection.filePath !== ""
          onClicked: projectPropertiesPopup.open()
        }
        QfPozycjaMenu {
          text: qsTr("Usuń projekt")
          ikona: "wfg_usun"
          enabled: projectSection.filePath !== ""
          onClicked: deleteProjectConfirm.open()
        }
      }
      Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: qsTr("Aplikacja")
        font: t.tinyFont
        color: t.secondaryTextColor
      }
      GridLayout {
        Layout.fillWidth: true
        columns: ustawieniaPanelu.ukladMenu === 0 ? 1 : 2
        columnSpacing: 4
        rowSpacing: 2

        QfPozycjaMenu {
          text: qsTr("Folder aplikacji")
          ikona: "wfg_magazyn"
          onClicked: {
            dashBoard.close();
            photoGallery.openFiles(iface.dataRoot());
          }
        }
        QfPozycjaMenu {
          text: qsTr("Aktualizacja aplikacji")
          ikona: "wfg_aktualizacja"
          onClicked: {
            dashBoard.close();
            Qt.openUrlExternally("https://github.com/ekolabynet/workfield/releases/latest");
          }
        }
        QfPozycjaMenu {
          text: qsTr("Zgłoś uwagę")
          ikona: "wfg_pomoc"
          onClicked: {
            // WorkField: zgloszenie z terenu — mail z gotowym kontekstem
            const adres = "workfield@ekolaby.net";
            const temat = "WorkField " + appVersionStr + " — uwaga z terenu";
            const tresc = qsTr("Opisz, co się działo (jedno zdanie wystarczy). Zrzut ekranu bardzo pomaga — dołącz go do tej wiadomości.") + "\n\n\n---\n" + "Wersja: " + appVersionStr + "\n" + "Projekt: " + (mainWindow.projectTitle !== "" ? mainWindow.projectTitle + " (" + FileUtils.fileName(projectSection.filePath) + ")" : FileUtils.fileName(projectSection.filePath)) + "\n" + "System: " + Qt.platform.os + "\n" + "Data: " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm");
            Qt.openUrlExternally("mailto:" + adres + "?subject=" + encodeURIComponent(temat) + "&body=" + encodeURIComponent(tresc));
            displayToast(qsTr("Otwieram szkic zgłoszenia…"));
          }
        }
      }
        }
      }

      // ── Warstwy ─────────────────────────────────────────────
      ColumnLayout {
        spacing: 0

      Text {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.topMargin: 10
          text: qsTr("Dane")
          font: t.strongFont
          color: t.mainTextColor
        }
      GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        columns: ustawieniaPanelu.ukladMenu === 0 ? 1 : 2
        columnSpacing: 4
        rowSpacing: 2

        QfPozycjaMenu {
          text: qsTr("Nowa warstwa")
          ikona: "wfg_warstwa_nowa"
          onClicked: {
          dashBoard.close();
          newLayerDialog.openDialog();
        }
        }
        QfPozycjaMenu {
          text: qsTr("Podkład")
          ikona: "wfg_podklad"
          onClicked: {
          dashBoard.close();
          basemapScreen.open();
        }
        }
        QfPozycjaMenu {
          text: qsTr("Dodaj z pliku")
          ikona: "wfg_import"
          onClicked: {
          dashBoard.close();
          dataDrawer.addExistingRequested();
        }
        }
        QfPozycjaMenu {
          text: qsTr("Teren")
          ikona: "wfg_teren"
          onClicked: {
          dashBoard.close();
          terenSettings.open();
        }
        }
        QfPozycjaMenu {
          text: qsTr("Galeria")
          ikona: "wfg_zdjecia"
          onClicked: {
          dashBoard.close();
          photoGallery.openPhotos();
        }
        }
        QfPozycjaMenu {
          text: qsTr("NMT")
          ikona: "wfg_rzezba"
          onClicked: demDownloader.request("NMT")
        }
        QfPozycjaMenu {
          text: qsTr("NMPT")
          ikona: "wfg_rzezba"
          onClicked: demDownloader.request("NMPT")
        }
        QfPozycjaMenu {
          text: qsTr("CHM")
          ikona: "wfg_rzezba"
          onClicked: demDownloader.computeChm()
        }
      }
      Text {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.topMargin: 6
          text: qsTr("Aktywna warstwa")
          font: t.tinyFont
          color: t.secondaryTextColor
        }
      GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        columns: ustawieniaPanelu.ukladMenu === 0 ? 1 : 2
        columnSpacing: 4
        rowSpacing: 2

        QfPozycjaMenu {
          text: qsTr("Pola")
          ikona: "wfg_pola"
          enabled: dashBoard.activeLayer
          onClicked: layerFieldsScreen.openFor(dashBoard.activeLayer)
        }
        QfPozycjaMenu {
          text: qsTr("Eksportuj")
          ikona: "wfg_eksport"
          enabled: dashBoard.activeLayer
          onClicked: {
              dashBoard.close();
              exportDialog.openFor(dashBoard.activeLayer);
            }
        }
        QfPozycjaMenu {
          text: qsTr("Usuń")
          ikona: "wfg_usun"
          enabled: dashBoard.activeLayer
          onClicked: {
              removeLayerConfirm.targetLayer = dashBoard.activeLayer;
              removeLayerConfirm.targetName = dashBoard.activeLayer.name;
              removeLayerConfirm.open();
            }
        }
      }

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qgisProject && qgisProject.crs && qgisProject.crs.authid !== "" ? qsTr("Warstwa robocza") + "  \u00b7  " + qgisProject.crs.authid : qsTr("Warstwa robocza")
        font: t.strongTipFont
        color: t.mainTextColor
      }

      // WorkField: główny włącznik przyciągania — gasi/wskrzesza całość,
      // stany magnesów per warstwa czekają nietknięte
      QfToolButton {
        id: snapMaster
        width: 30
        height: 30
        padding: 0
        round: true
        readonly property bool wl: qgisProject && qgisProject.snappingConfig.enabled
        bgcolor: wl ? t.mainColor : "transparent"
        iconSource: t.getThemeVectorIcon("ic_snapping_white_24dp")
        iconColor: wl ? "white" : t.secondaryTextColor
        opacity: wl ? 1.0 : 0.45

        onClicked: {
          let cfgM = qgisProject.snappingConfig;
          cfgM.enabled = !cfgM.enabled;
          qgisProject.snappingConfig = cfgM;
          projectInfo.snappingEnabled = cfgM.enabled;
          displayToast(cfgM.enabled ? qsTr("Przyciąganie włączone") : qsTr("Przyciąganie wyłączone"));
        }
      }
    }

    ListView {
      id: projectLayersList

      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: dashBoard.layerTree

      delegate: ItemDelegate {
        required property int index
        required property var model

        readonly property bool isVector: model.LayerType === "vectorlayer" && model.VectorLayerPointer
        readonly property var mapLayer: model.MapLayerPointer ? model.MapLayerPointer : (model.VectorLayerPointer ? model.VectorLayerPointer : null)
        readonly property string layerKind: mapLayer ? iface.layerKind(mapLayer) : ""
        readonly property bool isLayerRow: mapLayer !== null && model.Name !== undefined && model.Name !== ""
        readonly property bool isWritable: isVector && !model.VectorLayerPointer.readOnly
        readonly property bool isCurrent: isVector && model.VectorLayerPointer === dashBoard.activeLayer

        // geometria jako mikroikona - miejsce oddane nazwie warstwy
        readonly property int geomType: isVector ? model.VectorLayerPointer.geometryType() : -1
        readonly property string geomIcon: geomType === Qgis.GeometryType.Point ? "ic_vectorlayer_point_18dp" : geomType === Qgis.GeometryType.Line ? "ic_vectorlayer_line_18dp" : geomType === Qgis.GeometryType.Polygon ? "ic_vectorlayer_polygon_18dp" : "ic_vectorlayer_table_18dp"
        readonly property string featureCountText: isVector ? String(iface.layerInfoLabel(model.VectorLayerPointer)).split("\u00b7").pop().trim() : ""
        readonly property string layerCrs: isVector && model.VectorLayerPointer.crs ? model.VectorLayerPointer.crs.authid : ""
        // uklad pokazujemy TYLKO, gdy inny niz projektu - wtedy to ostrzezenie
        readonly property bool crsDiffers: layerCrs !== "" && qgisProject && qgisProject.crs && layerCrs !== qgisProject.crs.authid

        width: projectLayersList.width
        height: isLayerRow ? Math.max(44, layerNameText.implicitHeight + 16) : 0
        visible: isLayerRow

        background: Rectangle {
          color: isCurrent ? t.mainColor : "transparent"
        }

        contentItem: RowLayout {
          spacing: 8

          // olowek: wybor warstwy do edycji (zastapil przelacznik trybu)
          QfToolButton {
            Layout.leftMargin: 4
            width: 30
            height: 30
            padding: 0
            enabled: isWritable
            round: true

            // warstwa, w ktorej wlasnie rysujemy: jasnozielone kolo z olowkiem
            readonly property bool rysujemy: isCurrent && stateMachine.state === "digitize"

            iconSource: t.getThemeVectorIcon("ic_create_white_24dp")
            bgcolor: rysujemy ? "#00E676" : "transparent"
            iconColor: rysujemy ? "#062E12" : isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: !isWritable ? 0.25 : rysujemy ? 1.0 : isCurrent ? 0.9 : 0.55

            onClicked: {
              if (!isWritable) {
                displayToast(qsTr("Warstwa tylko do odczytu"), "warning");
                return;
              }
              const juz = isCurrent && stateMachine.state === "digitize";
              dashBoard.activeLayer = model.VectorLayerPointer;
              stateMachine.state = juz ? "browse" : "digitize";
              displayToast(juz ? qsTr("Przeglądanie") : qsTr("Rysowanie: %1").arg(model.Name));
              if (!juz) {
                // WorkField: zasada domyślna dociągania — rysowana warstwa
                // przyciąga sama do siebie; tryb "wszystkie warstwy"
                // sprowadzamy do "aktywnej", a w trybie magnesów sami
                // dopisujemy rysowaną warstwę
                if (qgisProject.snappingConfig.mode === Qgis.SnappingMode.AllLayers) {
                  let cfgO = qgisProject.snappingConfig;
                  cfgO.mode = Qgis.SnappingMode.ActiveLayer;
                  qgisProject.snappingConfig = cfgO;
                } else if (qgisProject.snappingConfig.mode === Qgis.SnappingMode.AdvancedConfiguration) {
                  dashBoard.ustawMagnesWarstwy(model.VectorLayerPointer, true);
                }
                dashBoard.close();
              }
            }
          }

          Text {
            id: layerNameText
            Layout.fillWidth: true
            text: model.Name
            font: t.tipFont
            color: isCurrent ? t.mainOverlayColor : t.mainTextColor
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }

          // uklad odmienny od projektu: krotkie ostrzezenie tekstem
          Text {
            visible: crsDiffers
            text: layerCrs
            font: t.tinyFont
            color: t.warningColor
          }

          QfToolButton {
            visible: isVector
            width: 18
            height: 18
            padding: 0
            enabled: false
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon(geomIcon)
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: 0.85
          }

          Text {
            text: isVector ? featureCountText : layerKind === "podklad" ? qsTr("PODKŁAD") : layerKind === "raster" ? qsTr("RASTER") : ""
            font: t.tinyFont
            color: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: 0.7
          }

          QfToolButton {
            visible: isVector && !isWritable
            width: 18
            height: 18
            padding: 0
            enabled: false
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_lock_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: 0.6
          }

          // WorkField: magnes — dociąganie do tej warstwy jako podkładu.
          // Świeci, gdy warstwa FAKTYCZNIE dociąga: w trybie magnesów wg
          // ustawienia warstwy, w trybie domyślnym — gdy właśnie w niej
          // rysujemy (rysowana warstwa zawsze dociąga sama do siebie).
          QfToolButton {
            id: snapToggle
            visible: isVector && (geomType === Qgis.GeometryType.Point || geomType === Qgis.GeometryType.Line || geomType === Qgis.GeometryType.Polygon)
            width: 30
            height: 30
            padding: 0
            round: true
            readonly property bool trybMagnesow: qgisProject && qgisProject.snappingConfig.mode === Qgis.SnappingMode.AdvancedConfiguration
            readonly property bool przyciaga: qgisProject && qgisProject.snappingConfig.enabled && (trybMagnesow ? model.SnappingEnabled === true : isCurrent && stateMachine.state === "digitize")
            bgcolor: przyciaga ? t.mainColor : "transparent"
            iconSource: t.getThemeVectorIcon("ic_snapping_white_24dp")
            iconColor: przyciaga ? "white" : isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: przyciaga ? 1.0 : 0.45

            onClicked: dashBoard.przelaczMagnesWarstwy(model.VectorLayerPointer, model.Name)
          }

          QfToolButton {
            id: selectableToggle
            width: 30
            height: 30
            padding: 0
            bgcolor: "transparent"
            property bool selectable: isVector ? iface.layerSelectable(model.VectorLayerPointer) : true
            iconSource: t.getThemeVectorIcon(selectable ? "ic_show_green_48dp" : "ic_hide_green_48dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: selectable ? 1.0 : 0.35
            onClicked: {
              const next = !selectable;
              iface.setLayerSelectable(model.VectorLayerPointer, next);
              selectable = next;
              displayToast(next ? qsTr("%1: reaguje na dotknięcie").arg(model.Name) : qsTr("%1: nie reaguje na dotknięcie").arg(model.Name));
            }
          }

          QfToolButton {
            width: 30
            height: 30
            padding: 0
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_edit_attributes_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor

            onClicked: {
              dashBoard.close();
              layerFieldsScreen.openFor(model.VectorLayerPointer);
            }
          }

          QfToolButton {
            Layout.rightMargin: 4
            width: 30
            height: 30
            padding: 0
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_delete_forever_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor

            onClicked: {
              removeLayerConfirm.targetLayer = mapLayer;
              removeLayerConfirm.targetName = model.Name;
              removeLayerConfirm.open();
            }
          }
        }

        onClicked: {
          if (isWritable)
            dashBoard.activeLayer = model.VectorLayerPointer;
        }
      }
    }

      }

      // ── Legenda ─────────────────────────────────────────────
      ColumnLayout {
        spacing: 0

        RowLayout {
          Layout.fillWidth: true
          Layout.margins: 8

          Text {
            Layout.fillWidth: true
            text: qsTr("Stylizacja warstw")
            font: Theme.strongTipFont
            color: Theme.mainTextColor
          }

          QfButton {
            visible: legend.model && legend.model.hasCollapsibleItems
            text: legend.model && legend.model.isCollapsed ? qsTr("Rozwiń") : qsTr("Zwiń")
            bgcolor: "transparent"
            color: Theme.mainTextColor
            font.pointSize: Theme.tinyFont.pointSize

            onClicked: {
              legend.model.setAllCollapsed(!legend.model.isCollapsed);
              projectInfo.saveLayerTreeState();
            }
          }
        }

        GridLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.rightMargin: 8
          columns: ustawieniaPanelu.ukladMenu === 0 ? 1 : 2
          columnSpacing: 4
          rowSpacing: 2

          QfPozycjaMenu {
            text: qsTr("Zapisz styl")
            ikona: "wfg_zapisz"
            enabled: dashBoard.activeLayer !== null && qgisProject && qgisProject.homePath !== ""
            onClicked: {
              const wynik = procesyStylu.zapiszStyl(dashBoard.activeLayer, qgisProject.homePath);
              displayToast(wynik.startsWith("BLAD") ? wynik : qsTr("Styl zapisany: %1").arg(FileUtils.fileName(wynik)));
            }
          }
          QfPozycjaMenu {
            text: qsTr("Wczytaj styl")
            ikona: "wfg_otworz"
            enabled: dashBoard.activeLayer !== null
            onClicked: dialogStylu.open()
          }
        }
        ProcesyStudio {
          id: procesyStylu
        }
        FileDialog {
          id: dialogStylu
          title: qsTr("Wczytaj styl warstwy")
          nameFilters: [qsTr("Styl QGIS (*.qml)"), qsTr("Wszystkie pliki (*)")]
          onAccepted: {
            const wynik = procesyStylu.wczytajStyl(dashBoard.activeLayer, String(selectedFile).replace(/^file:\/\//, ""));
            displayToast(wynik === "" ? qsTr("Styl wczytany") : wynik);
          }
        }

        Legend {
          id: legend
          objectName: "legend"

          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.leftMargin: mainWindow.sceneLeftMargin + 5
          Layout.rightMargin: 5
          isVisible: dashBoard.position > 0
        }
      }

    }

    
  }

  Popup {
    id: projectNameDialog

    property string mode: "blank"

    function openFor(newMode) {
      mode = newMode;
      projectNameField.text = (mode === "blank" ? qsTr("Projekt") : FileUtils.fileName(projectSection.filePath).replace(/\.(qgs|qgz)$/, "") + " kopia") + " " + new Date().toISOString().slice(0, 10);
      open();
    }

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 400)
    modal: true

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: projectNameDialog.mode === "blank" ? qsTr("Nowy pusty projekt") : qsTr("Zapisz projekt jako")
        font: t.strongFont
        color: t.mainTextColor
      }

      TextField {
        id: projectNameField
        Layout.fillWidth: true
        font: t.defaultFont
      }

      RowLayout {
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }
        Button {
          flat: true
          text: qsTr("Anuluj")
          font.pointSize: t.tinyFont.pointSize
          onClicked: projectNameDialog.close()
        }
        Button {
          flat: true
          text: qsTr("Utwórz")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            const name = projectNameField.text.trim();
            if (name === "") {
              return;
            }
            const safeName = FileUtils.sanitizeFilePathPart(name);
            const root = welcomeScreen.templatesDataRoot();
            platformUtilities.createDir(root, "Imported Projects");
            const destination = root + "Imported Projects/" + safeName;
            if (projectNameDialog.mode === "blank") {
              platformUtilities.createDir(root + "Imported Projects", safeName);
              const centerPoints = iface.visibleExtentPointsIn2180(dashBoard.mapSettings, 2);
              dashBoard.pendingBlankCenter = centerPoints.length > 4 ? centerPoints[4] : null;
              dashBoard.pendingBlankSetup = true;
              if (iface.createBlankProject(destination + "/projekt.qgs")) {
                dataDrawer.close();
                iface.loadFile(destination + "/projekt.qgs", name);
              } else {
                displayToast(qsTr("Nie udało się utworzyć projektu"));
              }
            } else {
              ProjectUtils.saveProject(qgisProject);
              const sourceDir = FileUtils.absolutePath(projectSection.filePath);
              if (FileUtils.copyRecursively(sourceDir, destination)) {
                dataDrawer.close();
                iface.loadFile(destination + "/" + FileUtils.fileName(projectSection.filePath), name);
              } else {
                displayToast(qsTr("Nie udało się skopiować projektu"));
              }
            }
            projectNameDialog.close();
          }
        }
      }
    }
  }

  Popup {
    id: deleteProjectConfirm

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 400)
    modal: true

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Usunąć projekt wraz z danymi?")
        font: t.strongFont
        color: t.mainTextColor
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Usunięty zostanie cały folder projektu, łącznie z warstwami i zdjęciami. Tej operacji nie można cofnąć.")
        font: t.tipFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }
        Button {
          flat: true
          text: qsTr("Anuluj")
          font.pointSize: t.tinyFont.pointSize
          onClicked: deleteProjectConfirm.close()
        }
        Button {
          flat: true
          text: qsTr("Usuń")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            const dir = FileUtils.absolutePath(projectSection.filePath);
            deleteProjectConfirm.close();
            dataDrawer.close();
            if (iface.removeProjectFolder(dir)) {
              displayToast(qsTr("Projekt usunięty"));
              welcomeScreen.visible = true;
            } else {
              displayToast(qsTr("Nie udało się usunąć projektu"));
            }
          }
        }
      }
    }
  }

  Popup {
    id: projectPropertiesPopup

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 440)
    modal: true

    onOpened: {
      projectTitleField.text = iface.projectTitle();
      objectNameField.text = iface.projectVariable("obiekt_nazwa");
      objectShortField.text = iface.projectVariable("obiekt_skrot");
      objectCategoryField.text = iface.projectVariable("obiekt_kategoria");
      crsCurrentLabel.refresh();
      customCrsField.text = "";
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Właściwości projektu")
        font: t.strongFont
        color: t.mainTextColor
      }

      Text {
        text: qsTr("Tytuł projektu:")
        font: t.tipFont
        color: t.secondaryTextColor
      }

      TextField {
        id: projectTitleField
        Layout.fillWidth: true
        font: t.defaultFont
      }

      Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: qsTr("Obiekt (dostępne w wyrażeniach jako @obiekt_nazwa, @obiekt_skrot, @obiekt_kategoria)")
        font: t.tipFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        TextField {
          id: objectNameField
          Layout.fillWidth: true
          font: t.defaultFont
          placeholderText: qsTr("Nazwa obiektu")
          onEditingFinished: iface.setProjectVariable("obiekt_nazwa", text.trim())
        }

        TextField {
          id: objectShortField
          Layout.preferredWidth: 90
          font: t.defaultFont
          placeholderText: qsTr("Skrót")
          onEditingFinished: iface.setProjectVariable("obiekt_skrot", text.trim().toUpperCase())
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: qsTr("Kategoria:")
          font: t.tipFont
          color: t.secondaryTextColor
        }

        TextField {
          id: objectCategoryField
          Layout.fillWidth: true
          font: t.defaultFont
          placeholderText: qsTr("APPL / SCI / …")
          onEditingFinished: iface.setProjectVariable("obiekt_kategoria", text.trim().toUpperCase())
        }
      }

      Text {
        id: crsCurrentLabel

        function refresh() {
          text = qsTr("Układ współrzędnych: %1 (%2)").arg(iface.projectCrsAuthid()).arg(iface.projectCrsDescription());
        }

        Layout.fillWidth: true
        font: t.tipFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      ComboBox {
        id: crsCombo
        Layout.fillWidth: true
        font: t.tinyFont
        textRole: "label"
        valueRole: "authid"
        model: [
          { "label": qsTr("— wybierz układ —"), "authid": "" },
          { "label": "PL-1992 (EPSG:2180)", "authid": "EPSG:2180" },
          { "label": "PL-2000 strefa 5 (EPSG:2176)", "authid": "EPSG:2176" },
          { "label": "PL-2000 strefa 6 (EPSG:2177)", "authid": "EPSG:2177" },
          { "label": "PL-2000 strefa 7 (EPSG:2178)", "authid": "EPSG:2178" },
          { "label": "PL-2000 strefa 8 (EPSG:2179)", "authid": "EPSG:2179" },
          { "label": "WGS 84 (EPSG:4326)", "authid": "EPSG:4326" },
          { "label": "Web Mercator (EPSG:3857)", "authid": "EPSG:3857" }
        ]
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: qsTr("Inny EPSG:")
          font: t.tipFont
          color: t.secondaryTextColor
        }

        TextField {
          id: customCrsField
          Layout.fillWidth: true
          font: t.tinyFont
          placeholderText: qsTr("np. 25832")
          inputMethodHints: Qt.ImhDigitsOnly
        }
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Folder projektu: %1").arg(FileUtils.absolutePath(projectSection.filePath))
        font: t.tinyFont
        color: t.secondaryTextColor
        elide: Text.ElideMiddle
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 2
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Pliki danych w folderze:")
        font: t.tipFont
        color: t.secondaryTextColor
      }

      ListView {
        id: projectFilesList
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 110)
        clip: true

        model: FolderListModel {
          id: projectFilesModel
          folder: projectPropertiesPopup.opened ? "file://" + FileUtils.absolutePath(projectSection.filePath) : ""
          nameFilters: ["*.gpkg", "*.qgs", "*.qgz"]
          showDirs: false
        }

        delegate: Text {
          width: projectFilesList.width
          text: "• " + fileName + "  (" + FileUtils.representFileSize(fileSize) + ")"
          font: t.tinyFont
          color: t.mainTextColor
          elide: Text.ElideMiddle
        }
      }

      RowLayout {
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }
        Button {
          flat: true
          text: qsTr("Zamknij")
          font.pointSize: t.tinyFont.pointSize
          onClicked: projectPropertiesPopup.close()
        }
        Button {
          flat: true
          text: qsTr("Zastosuj i zapisz")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            iface.setProjectTitle(projectTitleField.text);
            mainWindow.refreshProjectTitle();
            let requestedCrs = customCrsField.text.trim() !== "" ? "EPSG:" + customCrsField.text.trim() : crsCombo.currentValue;
            if (requestedCrs && requestedCrs !== "" && requestedCrs !== iface.projectCrsAuthid()) {
              if (!iface.setProjectCrs(requestedCrs)) {
                displayToast(qsTr("Nieprawidłowy układ: %1").arg(requestedCrs));
                return;
              }
            }
            ProjectUtils.saveProject(qgisProject);
            crsCurrentLabel.refresh();
            projectSection.refresh();
            displayToast(qsTr("Zapisano właściwości projektu"));
            projectPropertiesPopup.close();
          }
        }
      }
    }
  }

  Popup {
    id: removeLayerConfirm

    property var targetLayer: null
    property string targetName: ""

    parent: mainWindow.contentItem
    width: Math.min(380, mainWindow.width - 32)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    modal: true
    closePolicy: Popup.CloseOnEscape

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Usunąć warstwę z projektu?")
        font: t.strongFont
        color: t.mainTextColor
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: removeLayerConfirm.targetName
        font: t.tipFont
        color: t.secondaryTextColor
        elide: Text.ElideMiddle
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Plik z danymi pozostanie na dysku.")
        font: t.tinyFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 8

        Button {
          flat: true
          Layout.fillWidth: true
          text: qsTr("Anuluj")
          onClicked: removeLayerConfirm.close()
        }

        Button {
          flat: true
          Layout.fillWidth: true
          text: qsTr("Usuń")
          highlighted: true

          onClicked: {
            if (removeLayerConfirm.targetLayer) {
              iface.removeLayer(removeLayerConfirm.targetLayer);
              displayToast(qsTr("Usunięto warstwę %1").arg(removeLayerConfirm.targetName));
            }
            removeLayerConfirm.close();
          }
        }
      }
    }
  }
}
