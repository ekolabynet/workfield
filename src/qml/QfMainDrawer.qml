import QtQuick
import Qt.labs.folderlistmodel
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

  width: Math.min(Math.max(330, mainWindow.width * 0.8), mainWindow.width)
  height: parent.height
  edge: Qt.LeftEdge
  dragMargin: 10
  interactive: allowInteractive

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
          mapCanvas.mapSettings.extent = Qt.rect(c.x - 50, c.y - 50, 100, 100);
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

    TabBar {
      id: dashTabs

      Layout.fillWidth: true
      currentIndex: 0

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
      currentIndex: dashTabs.currentIndex

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

      GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 4
        rowSpacing: 4

        Button {
          Layout.fillWidth: true
          text: qsTr("Nowy pusty")
          icon.source: t.getThemeVectorIcon("wf_project_new")
          icon.color: "transparent"
          icon.width: 26
          icon.height: 26
          font.pointSize: t.tinyFont.pointSize
          onClicked: projectNameDialog.openFor("blank")
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Nowy z szablonu")
          icon.source: t.getThemeVectorIcon("wf_project_template")
          icon.color: "transparent"
          icon.width: 26
          icon.height: 26
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            dashBoard.close();
            welcomeScreen.visible = true;
          }
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Zapisz")
          icon.source: t.getThemeVectorIcon("wf_project_save")
          icon.color: "transparent"
          icon.width: 26
          icon.height: 26
          font.pointSize: t.tinyFont.pointSize
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
        Button {
          Layout.fillWidth: true
          text: qsTr("Zapisz jako…")
          icon.source: t.getThemeVectorIcon("wf_project_saveas")
          icon.color: "transparent"
          icon.width: 26
          icon.height: 26
          font.pointSize: t.tinyFont.pointSize
          enabled: projectSection.filePath !== ""
          onClicked: projectNameDialog.openFor("saveas")
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Usuń projekt")
          icon.source: t.getThemeVectorIcon("wf_project_delete")
          icon.color: "transparent"
          icon.width: 26
          icon.height: 26
          font.pointSize: t.tinyFont.pointSize
          enabled: projectSection.filePath !== ""
          onClicked: deleteProjectConfirm.open()
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Otwórz projekt")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            dashBoard.close();
            qfieldLocalDataPickerScreen.projectFolderView = false;
            qfieldLocalDataPickerScreen.model.resetToPath(iface.dataRoot() + "Imported Projects");
            qfieldLocalDataPickerScreen.visible = true;
          }
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Ekran startowy")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            dashBoard.close();
            returnHome();
          }
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Powiększ do danych")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            if (!iface.zoomToProjectData(dashBoard.mapSettings)) {
              const e = dashBoard.mapSettings.extent;
              const cx = e.x + e.width / 2;
              const cy = e.y + e.height / 2;
              dashBoard.mapSettings.extent = Qt.rect(cx - 500, cy - 500, 1000, 1000);
            }
            dashBoard.close();
          }
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Importuj projekt (folder)")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            dashBoard.close();
            platformUtilities.importProjectFolder();
          }
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Importuj projekt (ZIP)")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            dashBoard.close();
            platformUtilities.importProjectArchive();
          }
        }


        Button {
          Layout.fillWidth: true
          text: qsTr("Folder projektu")
          font.pointSize: t.tinyFont.pointSize
          icon.source: t.getThemeVectorIcon("wf_folder_project")
          icon.color: "transparent"
          icon.width: 26
          icon.height: 26
          enabled: projectSection.filePath !== ""
          onClicked: {
            dashBoard.close();
            dashBoard.showProjectFolder();
          }
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Folder aplikacji")
          font.pointSize: t.tinyFont.pointSize
          icon.source: t.getThemeVectorIcon("wf_folder_app")
          icon.color: "transparent"
          icon.width: 26
          icon.height: 26
          onClicked: {
            dashBoard.close();
            qfieldLocalDataPickerScreen.projectFolderView = true;
            qfieldLocalDataPickerScreen.model.resetToPath(iface.dataRoot());
            qfieldLocalDataPickerScreen.visible = true;
          }
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Właściwości")
          icon.source: t.getThemeVectorIcon("wf_project_properties")
          icon.color: "transparent"
          icon.width: 26
          icon.height: 26
          font.pointSize: t.tinyFont.pointSize
          enabled: projectSection.filePath !== ""
          onClicked: projectPropertiesPopup.open()
        }
        Button {
          Layout.fillWidth: true
          text: qsTr("Zgłoś uwagę")
          icon.source: t.getThemeVectorIcon("ic_send_white_24dp")
          icon.width: 26
          icon.height: 26
          font.pointSize: t.tinyFont.pointSize
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

    Flow {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      Button {
        id: newLayerButton
        text: qsTr("Nowa warstwa")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dashBoard.close();
          newLayerDialog.openDialog();
        }
      }

      Button {
        id: addBasemapButton
        text: qsTr("Podkład")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dashBoard.close();
          basemapScreen.open();
        }
      }

      Button {
        id: addLayerButton
        text: qsTr("Dodaj z pliku")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dashBoard.close();
          dataDrawer.addExistingRequested();
        }
      }

      Button {
        id: captureSettingsButton
        text: qsTr("Klawisze")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dashBoard.close();
          captureSettings.openDialog();
        }
      }

      Button {
        id: photoGalleryButton
        text: qsTr("Galeria")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dashBoard.close();
          photoGallery.open();
        }
      }
    }

        Flow {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.rightMargin: 8
          spacing: 8

          Button {
            text: qsTr("NMT")
            font.pointSize: t.tinyFont.pointSize
            onClicked: demDownloader.request("NMT")
          }

          Button {
            text: qsTr("NMPT")
            font.pointSize: t.tinyFont.pointSize
            onClicked: demDownloader.request("NMPT")
          }

          Button {
            text: qsTr("CHM")
            font.pointSize: t.tinyFont.pointSize
            onClicked: demDownloader.computeChm()
          }
        }

    Text {
      Layout.fillWidth: true
      Layout.margins: 8
      text: qgisProject && qgisProject.crs && qgisProject.crs.authid !== "" ? qsTr("Warstwa robocza") + "  \u00b7  " + qgisProject.crs.authid : qsTr("Warstwa robocza")
      font: t.strongTipFont
      color: t.mainTextColor
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

          QfToolButton {
            Layout.leftMargin: 4
            width: 22
            height: 22
            padding: 0
            enabled: false
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_create_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: isCurrent ? 1.0 : 0.3
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

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.rightMargin: 8
          spacing: 8

          Button {
            Layout.fillWidth: true
            text: qsTr("Pola")
            font.pointSize: t.tinyFont.pointSize
            enabled: dashBoard.activeLayer !== null && dashBoard.activeLayer !== undefined
            onClicked: layerFieldsScreen.openFor(dashBoard.activeLayer)
          }

          Button {
            Layout.fillWidth: true
            text: qsTr("Eksportuj")
            font.pointSize: t.tinyFont.pointSize
            enabled: dashBoard.activeLayer !== null && dashBoard.activeLayer !== undefined
            onClicked: {
              dashBoard.close();
              exportDialog.openFor(dashBoard.activeLayer);
            }
          }

          Button {
            Layout.fillWidth: true
            text: qsTr("Usuń")
            font.pointSize: t.tinyFont.pointSize
            enabled: dashBoard.activeLayer !== null && dashBoard.activeLayer !== undefined
            onClicked: {
              removeLayerConfirm.targetLayer = dashBoard.activeLayer;
              removeLayerConfirm.targetName = dashBoard.activeLayer.name;
              removeLayerConfirm.open();
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

      // ── Narzędzia ───────────────────────────────────────────
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
          text: qsTr("Anuluj")
          font.pointSize: t.tinyFont.pointSize
          onClicked: projectNameDialog.close()
        }
        Button {
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
          text: qsTr("Anuluj")
          font.pointSize: t.tinyFont.pointSize
          onClicked: deleteProjectConfirm.close()
        }
        Button {
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
          text: qsTr("Zamknij")
          font.pointSize: t.tinyFont.pointSize
          onClicked: projectPropertiesPopup.close()
        }
        Button {
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
          Layout.fillWidth: true
          text: qsTr("Anuluj")
          onClicked: removeLayerConfirm.close()
        }

        Button {
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
