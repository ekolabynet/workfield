import QtQuick
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

    function request(type) {
      const services = type === "NMT" ? ["https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMT/WMS/SkorowidzeUkladKRON86?", "https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMT/WMS/SkorowidzeUkladEVRF2007?"] : ["https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMPT/WMS/SkorowidzeUkladKRON86?", "https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMPT/WMS/SkorowidzeUkladEVRF2007?"];
      const points = iface.visibleExtentPointsIn2180(dashBoard.mapSettings, 2);
      if (points.length === 0) {
        displayToast(qsTr("Nie udalo sie wyznaczyc zasiegu mapy"), "warning");
        return;
      }
      displayToast(qsTr("Szukam arkuszy %1 dla obszaru mapy...").arg(type));
      queryService(services, 0, points, type);
    }

    function queryService(services, serviceIndex, points, type) {
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
          queryService(services, serviceIndex + 1, points, type);
          return;
        }
        const layerParam = encodeURIComponent(layers.join(","));
        collectUrls(serviceUrl, layerParam, points, 0, {}, type, services, serviceIndex);
      };
      capsXhr.open("GET", serviceUrl + "SERVICE=WMS&request=GetCapabilities");
      capsXhr.send();
    }

    function collectUrls(serviceUrl, layerParam, points, pointIndex, found, type, services, serviceIndex) {
      if (pointIndex >= points.length) {
        const urls = Object.keys(found);
        console.log("DEM: znaleziono URL-i:", urls.length);
        if (urls.length === 0) {
          queryService(services, serviceIndex + 1, points, type);
          return;
        }
        startDownloads(urls, type);
        return;
      }
      const pt = points[pointIndex];
      const bbox = (pt.y - 50) + "," + (pt.x - 50) + "," + (pt.y + 50) + "," + (pt.x + 50);
      const url = serviceUrl + "SERVICE=WMS&request=GetFeatureInfo&version=1.3.0&styles=&crs=EPSG:2180&width=101&height=101&format=image/png&transparent=true&i=50&j=50&INFO_FORMAT=text/html&layers=" + layerParam + "&query_layers=" + layerParam + "&bbox=" + bbox;
      const xhr = new XMLHttpRequest();
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) {
          return;
        }
        const matches = xhr.responseText.match(/https?:\/\/[^"'<>\s]+\.(asc|tif|tiff|zip)/g) || [];
        for (const u of matches) {
          found[u] = true;
        }
        collectUrls(serviceUrl, layerParam, points, pointIndex + 1, found, type, services, serviceIndex);
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
      let pairs = 0;
      let done = 0;
      for (const f of nmptFiles) {
        const g = godloOf(f);
        if (g === "" || !nmtByGodlo[g]) {
          continue;
        }
        pairs++;
        const outPath = home + "/CHM/CHM_" + g + ".tif";
        displayToast(qsTr("Liczę CHM dla arkusza %1…").arg(g));
        if (iface.rasterDifference(home + "/NMPT/" + f, home + "/NMT/" + nmtByGodlo[g], outPath)) {
          if (iface.addRasterLayerToProject(outPath, "CHM " + g, "EPSG:2180")) {
            done++;
          }
        }
      }
      if (pairs === 0) {
        displayToast(qsTr("Brak par NMT/NMPT o wspólnym godle — pobierz oba modele dla tego samego obszaru"), "warning");
      } else {
        displayToast(qsTr("CHM gotowe: %1 z %2 arkuszy").arg(done).arg(pairs));
      }
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

  Connections {
    target: iface

    function onDownloadFinished(path) {
      if (demDownloader.active <= 0) {
        return;
      }
      demDownloader.active--;
      const fileName = path.split("/").pop();
      if (iface.addRasterLayerToProject(path, fileName, "EPSG:2180")) {
        displayToast(qsTr("Wczytano %1").arg(fileName));
      } else {
        displayToast(qsTr("Pobrano, ale nie udalo sie wczytac %1").arg(fileName), "warning");
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

    StackLayout {
      id: dashStack

      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: dashTabs.currentIndex

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
      ColumnLayout {
        spacing: 0

        MenuItem {
          Layout.fillWidth: true
          icon.source: Theme.getThemeVectorIcon("ic_home_black_24dp")
          font: Theme.defaultFont
          text: qsTr("Wróć na ekran startowy")
          onClicked: returnHome()
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Theme.controlBorderColor
        }

        ListView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: 0

          model: [
            { "label": qsTr("Pomiar odległości i powierzchni"), "action": "measurement" },
            { "label": qsTr("Widok 3D"), "action": "view3d" },
            { "label": qsTr("Wydruki map"), "action": "print" },
            { "label": qsTr("Zakładki przestrzenne"), "action": "bookmarks" },
            { "label": qsTr("Wtyczki"), "action": "plugins" },
            { "label": qsTr("Zablokuj ekran"), "action": "lockScreen" },
            { "label": qsTr("Pobierz NMT (obszar mapy)"), "action": "nmt" },
            { "label": qsTr("Pobierz NMPT (obszar mapy)"), "action": "nmpt" },
            { "label": qsTr("Policz CHM (NMPT \u2212 NMT)"), "action": "chm" }
          ]

          delegate: MenuItem {
            width: ListView.view.width
            font: Theme.defaultFont
            text: modelData.label

            onClicked: {
              switch (modelData.action) {
              case "measurement":
                toggleMeasurementTool();
                break;
              case "view3d":
                toggle3DView();
                break;
              case "print":
                showPrintLayouts(mapToItem(null, 0, height));
                break;
              case "bookmarks":
                showBookmarks();
                dashBoard.close();
                break;
              case "plugins":
                showPluginManager();
                dashBoard.close();
                break;
              case "lockScreen":
                lockScreen();
                dashBoard.close();
                break;
              case "nmt":
                demDownloader.request("NMT");
                dashBoard.close();
                break;
              case "nmpt":
                demDownloader.request("NMPT");
                dashBoard.close();
                break;
              case "chm":
                demDownloader.computeChm();
                dashBoard.close();
                break;
              }
            }
          }
        }
      }

      // ── Pomoc ───────────────────────────────────────────────
      ColumnLayout {
        spacing: 0

        MenuItem {
          Layout.fillWidth: true
          font: Theme.defaultFont
          text: qsTr("Ustawienia aplikacji")
          onClicked: {
            showSettings();
            dashBoard.close();
          }
        }

        MenuItem {
          Layout.fillWidth: true
          font: Theme.defaultFont
          text: qsTr("O aplikacji WorkField")
          onClicked: {
            showAbout();
            dashBoard.close();
          }
        }

        MenuItem {
          Layout.fillWidth: true
          font: Theme.defaultFont
          text: qsTr("Dziennik komunikatów")
          onClicked: {
            showMessageLog();
            dashBoard.close();
          }
        }

        MenuItem {
          Layout.fillWidth: true
          font: Theme.defaultFont
          text: qsTr("Udostępnij dziennik (debug)")
          onClicked: {
            const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss");
            const path = iface.dataRoot() + "logs/workfield_log_" + stamp + ".txt";
            if (iface.writeTextFile(path, messageLogModel.toPlainText())) {
              displayToast(qsTr("Dziennik zapisany: %1").arg(path));
              platformUtilities.sendDatasetTo(path);
            } else {
              displayToast(qsTr("Nie udało się zapisać dziennika"), "error");
            }
            dashBoard.close();
          }
        }

        Item {
          Layout.fillHeight: true
        }
      }
    }

    TabBar {
      id: dashTabs

      Layout.fillWidth: true
      currentIndex: 0

      TabButton {
        text: qsTr("Stylizacja warstw")
        font: Theme.tipFont
      }
      TabButton {
        text: qsTr("Narzędzia")
        font: Theme.tipFont
      }
      TabButton {
        text: qsTr("Pomoc")
        font: Theme.tipFont
      }
    }
  }
}
