import QtQuick
import Qt.labs.folderlistmodel
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

Drawer {
  id: dataDrawer

  property var t
  property var layerTree
  property var activeLayer

  signal layerActivated(var layer)
  signal modeToggled(bool digitize)
  signal addExistingRequested

  edge: Qt.RightEdge
  width: Math.min(360, mainWindow.width * 0.85)
  height: parent.height
  dragMargin: 10
  interactive: opened || !overlayFeatureFormDrawer.opened

  onOpenedChanged: {
    if (opened)
      projectSection.refresh();
  }

  background: Rectangle {
    color: t.mainBackgroundColor
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
        text: qsTr("Dane")
        font: t.strongFont
        color: t.mainTextColor
      }

      QfToolButton {
        width: 36
        height: 36
        padding: 0
        bgcolor: "transparent"
        iconSource: t.getThemeVectorIcon("ic_arrow_right_black_24dp")
        iconColor: t.mainTextColor
        onClicked: dataDrawer.close()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    StackLayout {
      id: drawerStack

      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: drawerTabs.currentIndex

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
          text: qsTr("Projekt")
          font: t.strongTipFont
          color: t.mainTextColor
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
            dataDrawer.close();
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
          text: qsTr("Właściwości")
          icon.source: t.getThemeVectorIcon("wf_project_properties")
          icon.color: "transparent"
          icon.width: 26
          icon.height: 26
          font.pointSize: t.tinyFont.pointSize
          enabled: projectSection.filePath !== ""
          onClicked: projectPropertiesPopup.open()
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text {
          text: qsTr("Tryb pracy")
          font: t.strongTipFont
          color: t.mainTextColor
        }

        Text {
          text: modeToggle.checked ? qsTr("Digitalizacja") : qsTr("Przeglądanie")
          font: t.tipFont
          color: modeToggle.checked ? t.mainColor : t.secondaryTextColor
        }
      }

      Switch {
        id: modeToggle
        checked: stateMachine.state === "digitize"
        onToggled: dataDrawer.modeToggled(checked)
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      Button {
        id: newLayerButton
        Layout.fillWidth: true
        text: qsTr("Nowa warstwa")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dataDrawer.close();
          newLayerDialog.openDialog();
        }
      }

      Button {
        id: addBasemapButton
        Layout.fillWidth: true
        text: qsTr("Podkład")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dataDrawer.close();
          basemapScreen.open();
        }
      }

      Button {
        id: addLayerButton
        Layout.fillWidth: true
        text: qsTr("Dodaj z pliku")
        font.pointSize: t.tinyFont.pointSize
        onClicked: {
          dataDrawer.close();
          dataDrawer.addExistingRequested();
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.margins: 8
      text: qsTr("Warstwa robocza")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    ListView {
      id: editableLayers

      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(contentHeight, 240)
      clip: true
      model: dataDrawer.layerTree

      delegate: ItemDelegate {
        required property int index
        required property var model

        readonly property bool isVector: model.LayerType === "vectorlayer" && model.VectorLayerPointer
        readonly property bool isWritable: isVector && !model.VectorLayerPointer.readOnly
        readonly property bool isCurrent: isVector && model.VectorLayerPointer === dataDrawer.activeLayer

        width: editableLayers.width
        height: isWritable ? 44 : 0
        visible: isWritable

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
            Layout.fillWidth: true
            text: model.Name
            font: t.defaultFont
            color: isCurrent ? t.mainOverlayColor : t.mainTextColor
            elide: Text.ElideRight
          }

          Text {
            text: isVector ? model.VectorLayerPointer.crs.authid : ""
            font: t.tinyFont
            color: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: 0.7
          }

          QfToolButton {
            width: 30
            height: 30
            padding: 0
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_edit_attributes_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor

            onClicked: {
              dataDrawer.close();
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
              removeLayerConfirm.targetLayer = model.VectorLayerPointer;
              removeLayerConfirm.targetName = model.Name;
              removeLayerConfirm.open();
            }
          }
        }

        onClicked: {
          if (isWritable)
            dataDrawer.layerActivated(model.VectorLayerPointer);
        }
      }
    }

      }

      ColumnLayout {
        spacing: 0

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: 8
      Layout.rightMargin: 8
      visible: !dataDrawer.activeLayer
      text: qsTr("Wybierz warstwę roboczą, aby zobaczyć dostępne algorytmy.")
      font: t.tipFont
      color: t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

        ProcessingAlgorithmsList {
          id: algorithmsList

          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: dataDrawer.activeLayer !== null && dataDrawer.activeLayer !== undefined
          inPlaceLayer: dataDrawer.activeLayer
        }
      }
    }

    TabBar {
      id: drawerTabs

      Layout.fillWidth: true
      currentIndex: 0

      TabButton {
        text: qsTr("Projekty")
        font: t.tipFont
      }
      TabButton {
        text: qsTr("Algorytmy")
        font: t.tipFont
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
              ProjectUtils.removeMapLayer(qgisProject, removeLayerConfirm.targetLayer);
              displayToast(qsTr("Usunięto warstwę %1").arg(removeLayerConfirm.targetName));
            }
            removeLayerConfirm.close();
          }
        }
      }
    }
  }
}
