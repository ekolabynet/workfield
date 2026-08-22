import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import QfTheme

QfPopup {
  id: exportDialog

  property var t
  property var layer: null

  readonly property var formats: [
    { ext: "gpkg", label: "GeoPackage", wgs84: false },
    { ext: "geojson", label: "GeoJSON", wgs84: true },
    { ext: "shp", label: "Shapefile", wgs84: false },
    { ext: "kml", label: "KML", wgs84: true },
    { ext: "gpx", label: "GPX", wgs84: true },
    { ext: "csv", label: "CSV", wgs84: false },
    { ext: "dxf", label: "DXF", wgs84: false }
  ]

  property int formatIndex: 1
  onFormatIndexChanged: {
    if (formats[formatIndex].wgs84 && crsChoice === "layer")
      crsChoice = "wgs84";
  }
  property string crsChoice: "layer"
  property string customCrs: ""
  property string encoding: "UTF-8"
  property string subfolder: "export"
  property string baseName: ""

  readonly property string layerCrs: layer ? layer.crs.authid : ""
  readonly property string targetCrs: {
    switch (crsChoice) {
    case "wgs84":
      return "EPSG:4326";
    case "pl1992":
      return "EPSG:2180";
    case "pl2000":
      return "EPSG:2178";
    case "custom":
      return customCrs;
    default:
      return "";
    }
  }
  readonly property string targetDir: qgisProject ? qgisProject.homePath + "/" + subfolder : ""
  readonly property string targetPath: targetDir + "/" + baseName + "." + formats[formatIndex].ext
  readonly property bool willOverwrite: baseName !== "" && QfFileUtils.fileExists(targetPath)

  parent: mainWindow.contentItem
  width: Math.min(420, mainWindow.width - 32)
  height: Math.min(implicitHeight, mainWindow.height - 64)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: QfPopup.CloseOnEscape | QfPopup.CloseOnPressOutside

  function openFor(vectorLayer) {
    layer = vectorLayer;
    baseName = vectorLayer ? QfFileUtils.sanitizeFilePathPart(vectorLayer.name) : "";
    crsChoice = "layer";
    open();
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Eksport warstwy")
      font: t.strongFont
      color: t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: exportDialog.layer ? exportDialog.layer.name : ""
      font: t.tipFont
      color: t.secondaryTextColor
      elide: Text.ElideRight
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      text: qsTr("Format")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    QfComboBox {
      Layout.fillWidth: true
      model: exportDialog.formats.map(f => f.label + " (." + f.ext + ")")
      currentIndex: exportDialog.formatIndex
      font: t.defaultFont
      onActivated: exportDialog.formatIndex = currentIndex
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      text: qsTr("Układ współrzędnych")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      visible: exportDialog.formats[exportDialog.formatIndex].wgs84 && exportDialog.targetCrs !== "EPSG:4326"
      text: qsTr("Standard tego formatu zakłada WGS84 — inny układ może nie być czytany przez wszystkie programy")
      font: t.tipFont
      color: t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      Repeater {
        model: [
          { key: "layer", label: qsTr("Warstwy") },
          { key: "wgs84", label: "WGS 84" },
          { key: "pl1992", label: "PL-1992" },
          { key: "pl2000", label: "PL-2000/21" },
          { key: "custom", label: qsTr("Inny") }
        ]

        delegate: QfButton {
          required property var modelData
          text: modelData.label
          font.pointSize: t.tinyFont.pointSize
          checkable: true
          checked: exportDialog.crsChoice === modelData.key
          onClicked: exportDialog.crsChoice = modelData.key
        }
      }
    }

    QfTextField {
      Layout.fillWidth: true
      visible: exportDialog.crsChoice === "custom"
      placeholderText: "EPSG:2177"
      text: exportDialog.customCrs
      font: t.defaultFont
      onTextChanged: exportDialog.customCrs = text
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Docelowo: %1").arg(exportDialog.targetCrs === "" ? exportDialog.layerCrs : exportDialog.targetCrs)
      font: t.tipFont
      color: t.secondaryTextColor
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      text: qsTr("Kodowanie")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      Repeater {
        model: ["UTF-8", "CP1250", "ISO-8859-2"]

        delegate: QfButton {
          required property string modelData
          text: modelData
          font.pointSize: t.tinyFont.pointSize
          checkable: true
          checked: exportDialog.encoding === modelData
          onClicked: exportDialog.encoding = modelData
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      text: qsTr("Katalog")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      Repeater {
        model: ["export", "OUT", "."]

        delegate: QfButton {
          required property string modelData
          text: modelData === "." ? qsTr("Folder projektu") : modelData + "/"
          font.pointSize: t.tinyFont.pointSize
          checkable: true
          checked: exportDialog.subfolder === modelData
          onClicked: exportDialog.subfolder = modelData
        }
      }
    }

    QfTextField {
      Layout.fillWidth: true
      text: exportDialog.baseName
      font: t.defaultFont
      placeholderText: qsTr("Nazwa pliku")
      onTextChanged: exportDialog.baseName = text
    }

    Text {
      Layout.fillWidth: true
      text: exportDialog.targetPath
      font: t.tinyFont
      color: t.secondaryTextColor
      wrapMode: Text.WrapAnywhere
    }

    Text {
      Layout.fillWidth: true
      visible: exportDialog.willOverwrite
      text: qsTr("Uwaga: plik istnieje i zostanie nadpisany")
      font: t.tipFont
      color: t.warningColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      spacing: 8

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        onClicked: exportDialog.close()
      }

      QfButton {
        Layout.fillWidth: true
        text: exportDialog.willOverwrite ? qsTr("Nadpisz") : qsTr("Eksportuj")
        highlighted: true
        enabled: exportDialog.baseName !== "" && exportDialog.layer

        onClicked: {
          if (exportDialog.subfolder !== ".")
            platformUtilities.createDir(qgisProject.homePath, exportDialog.subfolder);
          const written = QfLayerUtils.exportVectorLayer(exportDialog.layer, exportDialog.targetPath, exportDialog.targetCrs, exportDialog.encoding);
          if (written !== "")
            displayToast(qsTr("Wyeksportowano: %1").arg(written));
          else
            displayToast(qsTr("Eksport nie powiódł się"));
          exportDialog.close();
        }
      }
    }
  }
}

