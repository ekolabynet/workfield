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
      group: qsTr("GUGiK — ortofotomapa"),
      items: [
        { name: qsTr("Ortofotomapa standardowa"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/StandardResolution", layers: "Raster", crs: "EPSG:2180" },
        { name: qsTr("Ortofotomapa wysokiej rozdzielczości"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/HighResolution", layers: "Raster", crs: "EPSG:2180" }
      ]
    },
    {
      group: qsTr("GUGiK — pozostałe"),
      items: [
        { name: qsTr("Krajowa Integracja Ewidencji Gruntów"), kind: "wms", url: "https://integracja.gugik.gov.pl/cgi-bin/KrajowaIntegracjaEwidencjiGruntow", layers: "dzialki,numery_dzialek,budynki", crs: "EPSG:2180" },
        { name: qsTr("Uzbrojenie terenu (KIUT)"), kind: "wms", url: "https://integracja.gugik.gov.pl/cgi-bin/KrajowaIntegracjaUzbrojeniaTerenu", layers: "przewod_wodociagowy,przewod_kanalizacyjny,przewod_gazowy,przewod_cieplowniczy,przewod_elektroenergetyczny,przewod_telekomunikacyjny", crs: "EPSG:2180" },
        { name: qsTr("Cieniowanie NMT"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMT/GRID1/WMS/ShadedRelief", layers: "Raster", crs: "EPSG:2180" },
        { name: qsTr("Mapa topograficzna BDOT10k"), kind: "wms", url: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/BDOT/WMS/TopoMap", layers: "Raster", crs: "EPSG:2180" }
      ]
    }
  ]

  property string customKind: "xyz"
  property string customUrl: ""
  property string customName: ""
  property string customLayers: ""
  property string customCrs: "EPSG:2180"

  function addPreset(item) {
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

    TextField {
      Layout.fillWidth: true
      font: t.defaultFont
      placeholderText: qsTr("nazwa warstwy w usłudze")
      visible: basemapScreen.customKind !== "xyz"
      text: basemapScreen.customLayers
      onTextChanged: basemapScreen.customLayers = text
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
