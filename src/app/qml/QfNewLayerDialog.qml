import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import QfTheme

QfPopup {
  id: newLayerDialog

  property var t

  property string layerName: ""
  property string geometryType: "Point"
  property string crsAuthId: ""
  property string targetMode: "gpkg"
  property string gpkgPath: ""

  readonly property var geometryTypes: [
    { key: "Point", label: qsTr("Punkt") },
    { key: "MultiLineString", label: qsTr("Linia") },
    { key: "MultiPolygon", label: qsTr("Poligon") },
    { key: "NoGeometry", label: qsTr("Bez geometrii") }
  ]

  readonly property var fieldTypes: [
    { key: "text", label: qsTr("Tekst") },
    { key: "multiline", label: qsTr("Tekst długi") },
    { key: "integer", label: qsTr("Liczba całkowita") },
    { key: "real", label: qsTr("Liczba rzeczywista") },
    { key: "date", label: qsTr("Data") },
    { key: "datetime", label: qsTr("Data i czas") },
    { key: "bool", label: qsTr("Tak/Nie") },
    { key: "attachment", label: qsTr("Załącznik (zdjęcia)") }
  ]

  readonly property string targetPath: {
    if (!qgisProject)
      return "";
    const safe = QfFileUtils.sanitizeFilePathPart(layerName === "" ? "warstwa" : layerName);
    if (targetMode === "gpkg" && gpkgPath !== "")
      return gpkgPath;
    if (targetMode === "gpkg")
      return qgisProject.homePath + "/" + safe + ".gpkg";
    return qgisProject.homePath + "/" + safe + ".geojson";
  }

  signal layerCreated(var layer)

  parent: mainWindow.contentItem
  width: Math.min(440, mainWindow.width - 32)
  height: Math.min(implicitHeight, mainWindow.height - 64)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: QfPopup.CloseOnEscape

  function openDialog() {
    layerName = "";
    geometryType = "Point";
    crsAuthId = qgisProject && qgisProject.crs ? qgisProject.crs.authid : "EPSG:4326";
    targetMode = "gpkg";
    gpkgPath = "";
    fieldModel.clear();
    fieldModel.append({
      fieldName: "opis",
      fieldType: "text"
    });
    open();
  }

  ListModel {
    id: fieldModel
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Nowa warstwa")
      font: t.strongFont
      color: t.mainTextColor
    }

    QfTextField {
      Layout.fillWidth: true
      font: t.defaultFont
      placeholderText: qsTr("Nazwa warstwy")
      text: newLayerDialog.layerName
      onTextChanged: newLayerDialog.layerName = text
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      text: qsTr("Geometria")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      Repeater {
        model: newLayerDialog.geometryTypes

        delegate: QfButton {
          required property var modelData
          text: modelData.label
          font.pointSize: t.tinyFont.pointSize
          checkable: true
          checked: newLayerDialog.geometryType === modelData.key
          onClicked: newLayerDialog.geometryType = modelData.key
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 4
      spacing: 6

      Text {
        text: qsTr("Układ")
        font: t.defaultFont
        color: t.mainTextColor
      }

      QfTextField {
        Layout.fillWidth: true
        font: t.defaultFont
        placeholderText: "EPSG:2180"
        text: newLayerDialog.crsAuthId
        onTextChanged: newLayerDialog.crsAuthId = text
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      text: qsTr("Zapis")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      QfButton {
        text: qsTr("GeoPackage")
        font.pointSize: t.tinyFont.pointSize
        checkable: true
        checked: newLayerDialog.targetMode === "gpkg"
        onClicked: newLayerDialog.targetMode = "gpkg"
      }

      QfButton {
        text: qsTr("GeoJSON")
        font.pointSize: t.tinyFont.pointSize
        checkable: true
        checked: newLayerDialog.targetMode === "geojson"
        onClicked: newLayerDialog.targetMode = "geojson"
      }
    }

    Text {
      Layout.fillWidth: true
      text: newLayerDialog.targetPath
      font: t.tinyFont
      color: t.secondaryTextColor
      wrapMode: Text.WrapAnywhere
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      text: qsTr("Atrybuty")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    ListView {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(contentHeight, 220)
      clip: true
      model: fieldModel

      delegate: RowLayout {
        required property int index
        required property string fieldName
        required property string fieldType

        width: ListView.view.width
        height: 48
        spacing: 6

        QfTextField {
          Layout.fillWidth: true
          font: t.defaultFont
          text: fieldName
          placeholderText: qsTr("nazwa pola")
          onTextChanged: {
            if (parent.index >= 0 && parent.index < fieldModel.count)
              fieldModel.setProperty(parent.index, "fieldName", text);
          }
        }

        QfComboBox {
          Layout.preferredWidth: 150
          font: t.defaultFont
          model: newLayerDialog.fieldTypes.map(f => f.label)
          currentIndex: newLayerDialog.fieldTypes.findIndex(f => f.key === fieldType)
          onActivated: idx => fieldModel.setProperty(parent.index, "fieldType", newLayerDialog.fieldTypes[idx].key)
        }

        QfToolButton {
          Layout.preferredWidth: 34
          Layout.preferredHeight: 34
          padding: 0
          bgcolor: "transparent"
          iconSource: QfTheme.getThemeVectorIcon("ic_delete_forever_white_24dp")
          iconColor: t.errorColor
          onClicked: fieldModel.remove(parent.index)
        }
      }
    }

    QfButton {
      Layout.fillWidth: true
      text: qsTr("Dodaj pole")
      font.pointSize: t.tinyFont.pointSize
      onClicked: fieldModel.append({
        fieldName: "",
        fieldType: "text"
      })
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      spacing: 8

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        onClicked: newLayerDialog.close()
      }

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Utwórz")
        highlighted: true
        enabled: newLayerDialog.layerName !== ""

        onClicked: {
          let fields = [];
          let needsUuid = false;
          for (let i = 0; i < fieldModel.count; i++) {
            const item = fieldModel.get(i);
            if (item.fieldName.trim() === "")
              continue;
            if (item.fieldType === "attachment")
              needsUuid = true;
            fields.push({
              name: item.fieldName.trim(),
              type: item.fieldType === "attachment" ? "text" : item.fieldType
            });
          }

          if (needsUuid && !fields.some(f => f.name === "uuid"))
            fields.unshift({
              name: "uuid",
              type: "text"
            });

          const layer = QfLayerUtils.createEmptyLayer(newLayerDialog.targetPath, newLayerDialog.layerName, newLayerDialog.geometryType, newLayerDialog.crsAuthId, fields);

          if (layer) {
            let hasAttachment = false;
            for (let k = 0; k < fieldModel.count; k++) {
              if (fieldModel.get(k).fieldType === "attachment")
                hasAttachment = true;
            }
            if (hasAttachment) {
              for (let m = 0; m < fieldModel.count; m++) {
                const item = fieldModel.get(m);
                if (item.fieldType === "attachment")
                  QfLayerUtils.setAttachmentField(layer, item.fieldName.trim());
              }
            }
          }

          if (layer && QfProjectUtils.addMapLayer(qgisProject, layer)) {
            displayToast(qsTr("Utworzono warstwę %1").arg(newLayerDialog.layerName));
            newLayerDialog.layerCreated(layer);
            newLayerDialog.close();
          } else {
            displayToast(qsTr("Nie udało się utworzyć warstwy"));
          }
        }
      }
    }
  }
}
