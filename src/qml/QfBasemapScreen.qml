import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

Popup {
  id: basemapScreen

  property var t

  readonly property var presets: [
    {
      group: qsTr("Podkłady globalne"),
      items: [
        { name: "OpenStreetMap", kind: "xyz", url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", zmax: 19 },
        { name: "OpenTopoMap", kind: "xyz", url: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png", zmax: 17 },
        { name: "Esri World Imagery", kind: "xyz", url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", zmax: 19 },
        { name: "Google Satellite", kind: "xyz", url: "https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}", zmax: 20 },
        { name: "Google Hybrid", kind: "xyz", url: "https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}", zmax: 20 },
        { name: "Google Roads", kind: "xyz", url: "https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}", zmax: 20 }
      ]
    },
    {
      group: qsTr("Ortofotomapa"),
      items: [
        { name: qsTr("Ortofotomapa standardowa"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/StandardResolution", layers: "Raster", crs: "EPSG:2180" },
        { name: qsTr("Ortofotomapa wysokorozdzielcza"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/HighResolution", layers: "Raster", crs: "EPSG:2180" },
        { name: qsTr("Prawdziwa ortofotomapa"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/TrueOrtho", layers: "PrawdziwaOrtofotomapa", crs: "EPSG:2180" },
        { name: qsTr("Wskaźnik wegetacji NDVI"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/NDVI", layers: "0", crs: "EPSG:2180" }
      ]
    },
    {
      group: qsTr("Rzeźba terenu"),
      items: [
        { name: qsTr("Cieniowanie NMT"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMT/GRID1/WMS/ShadedRelief", layers: "Raster", crs: "EPSG:2180" },
        { name: qsTr("Hipsometria"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMT/GRID1/WMS/Hypsometry", layers: "Raster", crs: "EPSG:2180" }
      ]
    },
    {
      group: qsTr("Ewidencja i uzbrojenie"),
      items: [
        { name: qsTr("Działki ewidencyjne (KIEG)"), kind: "wms", url: "https://integracja.gugik.gov.pl/cgi-bin/KrajowaIntegracjaEwidencjiGruntow", layers: "dzialki", crs: "EPSG:2180" },
        { name: qsTr("Obręby ewidencyjne (KIEG)"), kind: "wms", url: "https://integracja.gugik.gov.pl/cgi-bin/KrajowaIntegracjaEwidencjiGruntow", layers: "obreby", crs: "EPSG:2180" },
        { name: qsTr("Uzbrojenie terenu (KIUT)"), kind: "wms", url: "https://integracja.gugik.gov.pl/cgi-bin/KrajowaIntegracjaUzbrojeniaTerenu", layers: "gesut", crs: "EPSG:2180" },
        { name: qsTr("Plany miejscowe (KIMP)"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/ext/KrajowaIntegracjaMiejscowychPlanowZagospodarowaniaPrzestrzennego", layers: "plany", crs: "EPSG:2180" }
      ]
    },
    {
      group: qsTr("Warszawa"),
      items: [
        { name: qsTr("Ortofotomapa Warszawy"), kind: "wms", url: "https://wms.um.warszawa.pl/serwis", layers: "ORTO", crs: "EPSG:2178" },
        { name: qsTr("Działki ewidencyjne"), kind: "wms", url: "https://wms.um.warszawa.pl/serwis", layers: "GEODEZJA_DZIALKI", crs: "EPSG:2178" },
        { name: qsTr("Budynki"), kind: "wms", url: "https://wms.um.warszawa.pl/serwis", layers: "GEODEZJA_BUDYNKI", crs: "EPSG:2178" },
        { name: qsTr("Obręby ewidencyjne"), kind: "wms", url: "https://wms.um.warszawa.pl/serwis", layers: "GEODEZJA_OBREBY", crs: "EPSG:2178" },
        { name: qsTr("Punkty adresowe"), kind: "wms", url: "https://wms.um.warszawa.pl/serwis", layers: "ENOM_PUNKTY_ADRESOWE", crs: "EPSG:2178" },
        { name: qsTr("Decyzje o warunkach zabudowy"), kind: "wms", url: "https://wms.um.warszawa.pl/serwis", layers: "DECYZJE_O_WARUNKACH_ZABUDOWY", crs: "EPSG:2178" },
        { name: qsTr("Pozwolenia na budowę"), kind: "wms", url: "https://wms.um.warszawa.pl/serwis", layers: "DECYZJE_O_POZWOLENIU_NA_BUDOWE", crs: "EPSG:2178" },
        { name: qsTr("Więcej warstw Warszawy…"), kind: "browse", url: "https://wms.um.warszawa.pl/serwis", crs: "EPSG:2178" }
      ]
    },
    {
      group: qsTr("Mapy topograficzne"),
      items: [
        { name: qsTr("BDOT10k — wybierz warstwę…"), kind: "browse", url: "https://mapy.geoportal.gov.pl/wss/service/pub/guest/kompozycja_BDOT10k_WMS/MapServer/WMSServer", crs: "EPSG:2180" },
        { name: qsTr("Mapa topograficzna rastrowa"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/img/guest/TOPO/MapServer/WMSServer", layers: "Raster", crs: "EPSG:2180" },
        { name: qsTr("Mapa glebowo-rolnicza"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/pub/guest/MapaGlebowoRolnicza/MapServer/WMSServer", layers: "0", crs: "EPSG:2180" },
        { name: qsTr("Granice administracyjne — wybierz…"), kind: "browse", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/PRG/WMS/AdministrativeBoundaries", crs: "EPSG:2180" }
      ]
    }
  ]


  property string customKind: "xyz"
  property string customUrl: ""
  property string customName: ""
  property string customLayers: ""
  property string customCrs: "EPSG:2180"

  function addPreset(item) {
    if (item.kind === "browse") {
      customKind = "wms";
      customUrl = item.url;
      customCrs = item.crs !== undefined ? item.crs : "EPSG:2180";
      customLayers = "";
      serviceLayersMenu.entries = LayerUtils.wmsLayerNames(item.url);
      if (serviceLayersMenu.entries.length === 0)
        displayToast(qsTr("Nie udało się pobrać listy warstw"));
      else
        serviceLayersMenu.popup();
      return;
    }

    let layer = null;

    if (item.kind === "xyz")
      layer = LayerUtils.createXyzLayer(item.url, item.name, item.zmax !== undefined ? item.zmax : 19);
    else if (item.kind === "wms")
      layer = LayerUtils.createWmsLayer(item.url, item.name, item.layers, item.crs !== undefined ? item.crs : "EPSG:3857");
    else if (item.kind === "wmts")
      layer = LayerUtils.createWmtsLayer(item.url, item.name, item.layer, item.tileMatrixSet, item.crs !== undefined ? item.crs : "EPSG:3857");

    if (layer && ProjectUtils.addMapLayer(qgisProject, layer)) {
      displayToast(qsTr("Dodano podkład %1").arg(item.name));
      basemapScreen.close();
    } else {
      displayToast(qsTr("Nie udało się dodać podkładu"));
    }
  }

  parent: mainWindow.contentItem
  width: Math.min(460, mainWindow.width - 24)
  height: Math.min(implicitHeight, mainWindow.height - 48)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  ColumnLayout {
    anchors.fill: parent
    spacing: 6

    Text {
      Layout.fillWidth: true
      text: qsTr("Dodaj podkład")
      font: t.strongFont
      color: t.mainTextColor
    }

    ListView {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(contentHeight, 340)
      clip: true
      model: basemapScreen.presets

      delegate: Column {
        required property var modelData

        width: ListView.view.width

        Text {
          width: parent.width
          topPadding: 8
          bottomPadding: 4
          text: modelData.group
          font: t.strongTipFont
          color: t.mainTextColor
        }

        Repeater {
          model: modelData.items

          delegate: ItemDelegate {
            required property var modelData

            width: parent.width
            height: 44

            contentItem: RowLayout {
              spacing: 8

              Text {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                text: modelData.name
                font: t.defaultFont
                color: t.mainTextColor
                elide: Text.ElideRight
              }

              Text {
                Layout.rightMargin: 8
                text: modelData.kind.toUpperCase()
                font: t.tinyFont
                color: t.secondaryTextColor
              }
            }

            onClicked: basemapScreen.addPreset(modelData)
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.topMargin: 6
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Własny adres")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      Repeater {
        model: [
          { k: "xyz", n: "XYZ" },
          { k: "wms", n: "WMS" },
          { k: "wmts", n: "WMTS" }
        ]

        delegate: Button {
          required property var modelData

          text: modelData.n
          font.pointSize: t.tinyFont.pointSize
          checkable: true
          checked: basemapScreen.customKind === modelData.k
          onClicked: basemapScreen.customKind = modelData.k
        }
      }
    }

    TextField {
      Layout.fillWidth: true
      font: t.defaultFont
      placeholderText: basemapScreen.customKind === "xyz" ? "https://…/{z}/{x}/{y}.png" : "https://…/wms"
      text: basemapScreen.customUrl
      onTextChanged: basemapScreen.customUrl = text
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6
      visible: basemapScreen.customKind !== "xyz"

      TextField {
        Layout.fillWidth: true
        font: t.defaultFont
        placeholderText: qsTr("nazwa warstwy w usłudze")
        text: basemapScreen.customLayers
        onTextChanged: basemapScreen.customLayers = text
      }

      Button {
        text: qsTr("Wykaz")
        font.pointSize: t.tinyFont.pointSize
        enabled: basemapScreen.customUrl.trim() !== ""

        onClicked: {
          serviceLayersMenu.entries = LayerUtils.wmsLayerNames(basemapScreen.customUrl.trim());
          if (serviceLayersMenu.entries.length === 0) {
            displayToast(qsTr("Nie udało się pobrać listy warstw"));
            return;
          }
          serviceLayersMenu.popup();
        }
      }
    }

    Menu {
      id: serviceLayersMenu

      property var entries: []

      width: 320
      font: t.defaultFont

      Repeater {
        model: serviceLayersMenu.entries

        delegate: MenuItem {
          required property var modelData

          text: modelData.title
          font: t.defaultFont
          onTriggered: basemapScreen.customLayers = modelData.name
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      TextField {
        Layout.fillWidth: true
        font: t.defaultFont
        placeholderText: qsTr("nazwa podkładu")
        text: basemapScreen.customName
        onTextChanged: basemapScreen.customName = text
      }

      TextField {
        Layout.preferredWidth: 120
        font: t.defaultFont
        placeholderText: "EPSG:2180"
        visible: basemapScreen.customKind !== "xyz"
        text: basemapScreen.customCrs
        onTextChanged: basemapScreen.customCrs = text
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      spacing: 8

      Button {
        Layout.fillWidth: true
        text: qsTr("Zamknij")
        onClicked: basemapScreen.close()
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Dodaj")
        highlighted: true
        enabled: basemapScreen.customUrl.trim() !== ""

        onClicked: {
          const name = basemapScreen.customName.trim() !== "" ? basemapScreen.customName.trim() : qsTr("Podkład");
          basemapScreen.addPreset({
            "name": name,
            "kind": basemapScreen.customKind,
            "url": basemapScreen.customUrl.trim(),
            "layers": basemapScreen.customLayers.trim(),
            "layer": basemapScreen.customLayers.trim(),
            "tileMatrixSet": basemapScreen.customCrs.replace(":", ""),
            "crs": basemapScreen.customCrs.trim(),
            "zmax": 19
          });
        }
      }
    }
  }
}
