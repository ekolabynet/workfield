import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import org.qfield.gui // [WF-BUTTONS] QfDecisionButton
import Theme

Popup {
  id: newLayerDialog

  property var t

  property string layerName: ""
  property string geometryType: "Point"
  property string crsAuthId: ""
  // [WF-NEW-LAYER] 23.10.2026 — PROJECT DATABASE (dane.gpkg) by default.
  // A separate file does not travel with the database, gets no photos and is
  // not snapped to — that is how Kran.gpkg and Przepusty.gpkg came about.
  // Modes: "database" | "gpkg" (separate file) | "geojson".
  property string targetMode: "database"
  // [WF-FIXED-RECT] Field note 10: default shape of the layer, set when it is created.
  property string defaultShape: ""
  property string defaultLength: "45"
  property string defaultWidth: "45"
  // [WF-SIZE-UNITS] the unit chosen in the size window (Settings WorkField/wymiarJednostka)
  property string sizeUnit: "cm"
  readonly property var unitFactors: ({ "m": 1.0, "cm": 0.01, "mm": 0.001, "cal": 0.0254 })
  readonly property var unitSigns: ({ "m": "m", "cm": "cm", "mm": "mm", "cal": "″" })
  readonly property bool shapesPossible: geometryType !== "Point" && geometryType !== "NoGeometry"
  property string gpkgPath: ""
  property string projectDatabase: ""

  //! Legend name — as typed, trimmed.
  readonly property string displayName: layerName.trim()
  //! TABLE name — no diacritics, no spaces.
  readonly property string tableName: typeof NarzedziaProjektu !== "undefined" ? NarzedziaProjektu.tableNameFor(displayName) : displayName
  //! A table of this name already exists in the target file — STOP, nothing is overwritten.
  readonly property bool tableTaken: targetMode !== "geojson" && displayName !== "" && typeof NarzedziaProjektu !== "undefined" && NarzedziaProjektu.tableExists(targetPath, tableName)

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
    if (targetMode !== "geojson" || !typLukowy(geometryType)) {
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
    if (targetMode === "database" && projectDatabase !== "")
      return projectDatabase;
    const safe = FileUtils.sanitizeFilePathPart(displayName === "" ? "warstwa" : tableName);
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
    projectDatabase = typeof NarzedziaProjektu !== "undefined" && qgisProject ? NarzedziaProjektu.plikDanych(qgisProject) : "";
    targetMode = projectDatabase !== "" ? "database" : "gpkg";
    defaultShape = "";
    sizeUnit = settings.value('WorkField/wymiarJednostka', 'cm');
    if (unitFactors[sizeUnit] === undefined)
      sizeUnit = "cm";
    defaultLength = String(parseFloat((0.45 / unitFactors[sizeUnit]).toFixed(3)));
    defaultWidth = defaultLength;
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
          // [WF-BUTTONS] checked chip filled with white text (was green on dark).
          highlighted: checked
          // Łuki tylko w GeoPackage — GeoJSON prostuje je bez słowa.
          // `Flow` pomija niewidoczne dzieci, więc rząd sam się zwiera.
          visible: modelData.luki !== true || newLayerDialog.targetMode !== "geojson"
          checked: newLayerDialog.geometryType === modelData.key
          onClicked: newLayerDialog.geometryType = modelData.key
        }
      }
    }

    // [WF-FIXED-RECT] Rysuj domyślnie — kształt uzbrajany od razu na tej warstwie.
    Text {
      Layout.fillWidth: true
      Layout.topMargin: 4
      visible: newLayerDialog.shapesPossible
      text: qsTr("Rysuj domyślnie")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6
      visible: newLayerDialog.shapesPossible

      Repeater {
        model: [
          { key: "", label: qsTr("Wierzchołki") },
          { key: "prostokat", label: qsTr("Prostokąt") },
          { key: "okrag", label: qsTr("Okrąg") },
          { key: "prostokatWymiar", label: qsTr("Prostokąt o wymiarze") }
        ]

        delegate: Button {
          required property var modelData
          text: modelData.label
          font.pointSize: t.tinyFont.pointSize
          checkable: true
          highlighted: checked
          checked: newLayerDialog.defaultShape === modelData.key
          onClicked: newLayerDialog.defaultShape = modelData.key
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6
      visible: newLayerDialog.shapesPossible && newLayerDialog.defaultShape === "prostokatWymiar"

      TextField {
        Layout.fillWidth: true
        font: t.defaultFont
        placeholderText: qsTr("dłuższy bok [%1]").arg(newLayerDialog.unitSigns[newLayerDialog.sizeUnit])
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        text: newLayerDialog.defaultLength
        onTextChanged: newLayerDialog.defaultLength = text
      }
      Text {
        text: "×"
        font: t.defaultFont
        color: t.mainTextColor
      }
      TextField {
        Layout.fillWidth: true
        font: t.defaultFont
        placeholderText: qsTr("krótszy bok [%1]").arg(newLayerDialog.unitSigns[newLayerDialog.sizeUnit])
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        text: newLayerDialog.defaultWidth
        onTextChanged: newLayerDialog.defaultWidth = text
      }
      Text {
        text: newLayerDialog.unitSigns[newLayerDialog.sizeUnit] // [WF-SIZE-UNITS]
        font: t.defaultFont
        color: t.mainTextColor
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
        text: qsTr("Baza projektu")
        font.pointSize: t.tinyFont.pointSize
        checkable: true
        // [WF-BUTTONS] checked chip filled with white text (was green on dark).
        highlighted: checked
        visible: newLayerDialog.projectDatabase !== ""
        checked: newLayerDialog.targetMode === "database"
        onClicked: newLayerDialog.targetMode = "database"
      }

      Button {
        text: qsTr("Osobny plik GPKG")
        font.pointSize: t.tinyFont.pointSize
        checkable: true
        // [WF-BUTTONS] checked chip filled with white text (was green on dark).
        highlighted: checked
        checked: newLayerDialog.targetMode === "gpkg"
        onClicked: newLayerDialog.targetMode = "gpkg"
      }

      Button {
        text: qsTr("GeoJSON")
        font.pointSize: t.tinyFont.pointSize
        checkable: true
        // [WF-BUTTONS] checked chip filled with white text (was green on dark).
        highlighted: checked
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

    // [WF-NEW-LAYER] table name and collision — visible BEFORE "Utwórz" is pressed.
    Text {
      Layout.fillWidth: true
      visible: newLayerDialog.targetMode !== "geojson" && newLayerDialog.displayName !== ""
      text: newLayerDialog.tableTaken ? qsTr("W tym pliku jest już tabela „%1” — zmień nazwę. Nic nie zostanie nadpisane.").arg(newLayerDialog.tableName) : qsTr("tabela w bazie: %1").arg(newLayerDialog.tableName)
      font: t.tinyFont
      color: newLayerDialog.tableTaken ? t.errorColor : t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      visible: newLayerDialog.targetMode !== "database" && newLayerDialog.projectDatabase !== ""
      text: qsTr("Osobny plik nie jedzie razem z bazą projektu, nie ma zdjęć ani przyciągania. Zwykle lepiej: „Baza projektu”.")
      font: t.tinyFont
      color: "#e08a1e"
      wrapMode: Text.WordWrap
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

      QfDecisionButton {
        role: "cancel" // [WF-BUTTONS]
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        onClicked: newLayerDialog.close()
      }

      QfDecisionButton {
        role: "confirm" // [WF-BUTTONS]
        Layout.fillWidth: true
        text: qsTr("Utwórz")
        enabled: newLayerDialog.displayName !== "" && !newLayerDialog.tableTaken

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

          const targetTable = newLayerDialog.targetMode === "geojson" ? newLayerDialog.displayName : newLayerDialog.tableName;
          const layer = LayerUtils.createEmptyLayer(newLayerDialog.targetPath, targetTable, newLayerDialog.geometryType, newLayerDialog.crsAuthId, fields);
          if (layer)
            layer.name = newLayerDialog.displayName;

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
            // [WF-NEW-LAYER] photos (ZAL_) and snapping right away, then save the project.
            let suffix = "";
            if (typeof NarzedziaProjektu !== "undefined") {
              const setUp = NarzedziaProjektu.setUpNewLayer(qgisProject, layer);
              // [WF-FIXED-RECT] default shape and size travel with the project
              if (newLayerDialog.shapesPossible && newLayerDialog.defaultShape !== "") {
                NarzedziaProjektu.wlasciwoscWarstwy(layer, "workfield/ksztaltDomyslny", newLayerDialog.defaultShape);
                if (newLayerDialog.defaultShape === "prostokatWymiar") {
                  // [WF-SIZE-UNITS] typed in the chosen unit, stored in metres
                  let dl = parseFloat(String(newLayerDialog.defaultLength).replace(",", ".")) * newLayerDialog.unitFactors[newLayerDialog.sizeUnit];
                  let sz = parseFloat(String(newLayerDialog.defaultWidth).replace(",", ".")) * newLayerDialog.unitFactors[newLayerDialog.sizeUnit];
                  if (dl > 0 && sz > 0) {
                    if (sz > dl) {
                      const tmp = dl;
                      dl = sz;
                      sz = tmp;
                    }
                    NarzedziaProjektu.wlasciwoscWarstwy(layer, "workfield/wymiarDl", dl.toFixed(3));
                    NarzedziaProjektu.wlasciwoscWarstwy(layer, "workfield/wymiarSz", sz.toFixed(3));
                  }
                }
              }
              if (setUp.attachments === true)
                suffix = qsTr(" — ze zdjęciami");
            }
            const saved = typeof ProjectUtils !== "undefined" && ProjectUtils.saveProject(qgisProject);
            if (saved)
              displayToast(qsTr("Utworzono warstwę %1%2. Projekt zapisany.").arg(newLayerDialog.displayName).arg(suffix));
            else
              displayToast(qsTr("Utworzono warstwę %1, ale projektu NIE zapisano").arg(newLayerDialog.displayName), "warning");
            newLayerDialog.layerCreated(layer);
            newLayerDialog.close();
          } else {
            displayToast(qsTr("Nie udało się utworzyć warstwy"), "error");
          }
        }
      }
    }
  }
}
