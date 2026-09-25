import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

Popup {
  id: newLayerDialog

  property var t

  property string layerName: ""
  property string geometryType: "Point"
  property string crsAuthId: ""
  property string targetMode: "gpkg"
  property string gpkgPath: ""

  // WARSTWY ŁUKOWE (25.09.2026).
  //
  // Bez nich kształty łukowe (okrąg, chmurka) nie miały gdzie usiąść:
  // na zwykłym POLYGON-ie łuk ginie bez słowa — sprawdzone, okrąg
  // o pięciu wierzchołkach zapisuje się jako dziewięćdziesiąt jeden.
  //
  // Postacie MNOGIE, jak reszta listy. To nie jest tylko spójność:
  // przy zapisie `QfGeometry` woła `convertToMultiType()`, gdy warstwa
  // jest mnoga, a MultiCurve i MultiSurface to obsługują.
  //
  // `luki: true` znaczy „tylko GeoPackage" — patrz niżej.
  readonly property var geometryTypes: [
    { key: "Point", label: qsTr("Punkt") },
    { key: "MultiLineString", label: qsTr("Linia") },
    { key: "MultiPolygon", label: qsTr("Poligon") },
    { key: "MultiCurve", label: qsTr("Linia łukowa"), luki: true },
    { key: "MultiSurface", label: qsTr("Poligon łukowy"), luki: true },
    { key: "NoGeometry", label: qsTr("Bez geometrii") }
  ]

  //! Czy podany klucz typu jest łukowy — jedno miejsce, dwa pytania.
  function typLukowy(klucz) {
    for (var i = 0; i < geometryTypes.length; i++) {
      if (geometryTypes[i].key === klucz) {
        return geometryTypes[i].luki === true;
      }
    }
    return false;
  }

  // GEOJSON NIE ZNA ŁUKÓW — i nie mówi o tym ani słowa.
  //
  // Sprawdzone: okrąg zapisany do GeoJSON-a wychodzi jako zwykły
  // `Polygon` o 91 współrzędnych. Warstwa nazywałaby się „łukowa”
  // i cicho prostowała każdy kształt.
  //
  // Samo ukrycie przycisku nie wystarczy: zniknąłby przycisk,
  // a `geometryType` zostałoby „MultiSurface”. Więc wybór schodzi
  // na odpowiednik prosty i mówimy dlaczego.
  onTargetModeChanged: {
    if (targetMode === "gpkg" || !typLukowy(geometryType)) {
      return;
    }
    geometryType = geometryType === "MultiCurve" ? "MultiLineString" : "MultiPolygon";
    displayToast(qsTr("GeoJSON nie zna łuków — geometria zmieniona na prostą"), "warning");
  }

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
    const safe = FileUtils.sanitizeFilePathPart(layerName === "" ? "warstwa" : layerName);
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
  closePolicy: Popup.CloseOnEscape

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

    TextField {
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

        delegate: Button {
          required property var modelData
          text: modelData.label
          font.pointSize: t.tinyFont.pointSize
          checkable: true
          // Łuki tylko w GeoPackage — GeoJSON prostuje je bez słowa.
          // `Flow` pomija niewidoczne dzieci, więc rząd sam się zwiera.
          visible: modelData.luki !== true || newLayerDialog.targetMode === "gpkg"
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

      TextField {
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

      Button {
        text: qsTr("GeoPackage")
        font.pointSize: t.tinyFont.pointSize
        checkable: true
        checked: newLayerDialog.targetMode === "gpkg"
        onClicked: newLayerDialog.targetMode = "gpkg"
      }

      Button {
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

        TextField {
          Layout.fillWidth: true
          font: t.defaultFont
          text: fieldName
          placeholderText: qsTr("nazwa pola")
          onTextChanged: {
            if (parent.index >= 0 && parent.index < fieldModel.count)
              fieldModel.setProperty(parent.index, "fieldName", text);
          }
        }

        ComboBox {
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
          iconSource: Theme.getThemeVectorIcon("ic_delete_forever_white_24dp")
          iconColor: t.errorColor
          onClicked: fieldModel.remove(parent.index)
        }
      }
    }

    Button {
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

      Button {
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        onClicked: newLayerDialog.close()
      }

      Button {
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

          const layer = LayerUtils.createEmptyLayer(newLayerDialog.targetPath, newLayerDialog.layerName, newLayerDialog.geometryType, newLayerDialog.crsAuthId, fields);

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
                  LayerUtils.setAttachmentField(layer, item.fieldName.trim());
              }
            }
          }

          if (layer && ProjectUtils.addMapLayer(qgisProject, layer)) {
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
