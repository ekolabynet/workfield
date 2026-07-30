import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * Przegladarka plikow i galeria zdjec projektu (WorkField, krok 1: odczyt).
 * Zrodlo zdjec: <projekt>/DCIM, nazwy wg schematu quick capture bara:
 * <warstwa>_<yyyyMMdd_hhmmss>.jpg - z nazwy odtwarzamy warstwe do filtrowania.
 */
Popup {
  id: photoGallery

  property var t

  readonly property string projectDir: qgisProject ? qgisProject.homePath : ""
  property string layerFilter: ""
  property var layerList: []
  property var photos: []

  width: mainWindow.width - 16
  height: mainWindow.height - 32
  x: Math.round((mainWindow.width - width) / 2)
  y: Math.round((mainWindow.height - height) / 2)
  modal: true
  focus: true

  onOpened: {
    filesPage.browsePath = projectDir;
    rebuildPhotos();
  }
  onLayerFilterChanged: rebuildPhotos()

  // <warstwa>_<yyyyMMdd_hhmmss> -> warstwa; image_0003 -> image (stary aparat)
  function extractLayer(name) {
    const base = name.replace(/\.[^.]+$/, "");
    let m = base.match(/^(.*)_\d{8}_\d{6}$/);
    if (m)
      return m[1];
    m = base.match(/^(.*)_\d+$/);
    return m ? m[1] : base;
  }

  function rebuildPhotos() {
    const arr = [];
    const prefixes = {};
    for (let i = 0; i < dcimModel.count; i++) {
      const name = dcimModel.get(i, "fileName");
      const layer = extractLayer(name);
      prefixes[layer] = true;
      if (layerFilter === "" || layer === layerFilter) {
        arr.push({
            "path": dcimModel.get(i, "filePath"),
            "name": name,
            "layer": layer,
            "mtime": dcimModel.get(i, "fileModified")
          });
      }
    }
    photos = arr;
    const pl = Object.keys(prefixes);
    pl.sort();
    layerList = pl;
    if (layerFilter !== "" && pl.indexOf(layerFilter) < 0)
      layerFilter = "";
  }

  PhotoTagStore {
    id: tagStore
  }

  Connections {
    target: photoGallery
    function onOpened() {
      if (photoGallery.projectDir !== "") {
        tagStore.author = settings.value("workfield/podpisTerenowy", "workfield");
        const ok = tagStore.open(photoGallery.projectDir);
        console.log("PhotoTagStore:", ok ? "otwarty: " + tagStore.storagePath : "BLAD otwarcia");
      }
    }
  }

  FolderListModel {
    id: dcimModel
    // QDir::Time = najnowsze pierwsze; odwrocenie: sortReversed: true
    folder: photoGallery.projectDir !== "" ? "file://" + photoGallery.projectDir + "/DCIM" : ""
    nameFilters: ["*.jpg", "*.jpeg", "*.JPG", "*.JPEG", "*.png", "*.PNG"]
    showDirs: false
    sortField: FolderListModel.Time
    onCountChanged: photoGallery.rebuildPhotos()
  }

  contentItem: ColumnLayout {
    spacing: 6

    RowLayout {
      Layout.fillWidth: true

      Text {
        Layout.fillWidth: true
        text: qsTr("Galeria projektu")
        font: photoGallery.t.strongFont
        color: photoGallery.t.mainTextColor
        elide: Text.ElideRight
      }

      Text {
        text: qsTr("Zdjęć: %1").arg(photoGallery.photos.length)
        font: photoGallery.t.tipFont
        color: photoGallery.t.secondaryTextColor
        visible: galleryTabs.currentIndex === 0
      }

      ToolButton {
        text: "✕"
        onClicked: photoGallery.close()
      }
    }

    TabBar {
      id: galleryTabs
      Layout.fillWidth: true

      TabButton {
        text: qsTr("Zdjęcia")
      }
      TabButton {
        text: qsTr("Pliki")
      }
    }

    StackLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: galleryTabs.currentIndex

      // ── Zdjęcia ────────────────────────────────────────────
      ColumnLayout {
        spacing: 6

        Flow {
          Layout.fillWidth: true
          spacing: 6
          visible: photoGallery.layerList.length > 1

          Repeater {
            model: [""].concat(photoGallery.layerList)

            delegate: Rectangle {
              radius: height / 2
              height: 30
              width: chipText.width + 22
              color: photoGallery.layerFilter === modelData ? "#00695C" : "#ECEFF1"
              border.color: "#00695C"
              border.width: 1

              Text {
                id: chipText
                anchors.centerIn: parent
                text: modelData === "" ? qsTr("Wszystkie") : modelData
                color: photoGallery.layerFilter === modelData ? "white" : "#00695C"
                font: photoGallery.t.tipFont
              }

              MouseArea {
                anchors.fill: parent
                onClicked: photoGallery.layerFilter = modelData
              }
            }
          }
        }

        GridView {
          id: photoGrid
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          cellWidth: Math.floor(width / Math.max(2, Math.floor(width / 132)))
          cellHeight: cellWidth
          model: photoGallery.photos

          ScrollBar.vertical: ScrollBar {
          }

          delegate: Item {
            width: photoGrid.cellWidth
            height: photoGrid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: 2
              color: "#20000000"
            }

            Image {
              anchors.fill: parent
              anchors.margins: 2
              source: "file://" + modelData.path
              asynchronous: true
              autoTransform: true
              fillMode: Image.PreserveAspectCrop
              // klucz wydajnosci: dekodujemy miniature, nie 12 Mpix
              sourceSize.width: 256
              sourceSize.height: 256
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 2
              height: 20
              color: "#88000000"

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 4
                text: Qt.formatDateTime(modelData.mtime, "dd.MM hh:mm")
                color: "white"
                font: photoGallery.t.tinyFont
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: viewer.openList(photoGallery.photos, index)
            }
          }

          Text {
            anchors.centerIn: parent
            visible: photoGallery.photos.length === 0
            text: qsTr("Brak zdjęć w katalogu DCIM projektu")
            color: photoGallery.t.secondaryTextColor
            font: photoGallery.t.tipFont
          }
        }
      }

      // ── Pliki ──────────────────────────────────────────────
      ColumnLayout {
        id: filesPage

        property string browsePath: photoGallery.projectDir

        spacing: 6

        RowLayout {
          Layout.fillWidth: true

          ToolButton {
            text: "↑"
            enabled: filesPage.browsePath.length > photoGallery.projectDir.length
            onClicked: filesPage.browsePath = filesPage.browsePath.substring(0, filesPage.browsePath.lastIndexOf("/"))
          }

          Text {
            Layout.fillWidth: true
            text: filesPage.browsePath.length > photoGallery.projectDir.length ? filesPage.browsePath.substring(photoGallery.projectDir.length + 1) : qsTr("(katalog projektu)")
            font: photoGallery.t.tipFont
            color: photoGallery.t.secondaryTextColor
            elide: Text.ElideMiddle
          }
        }

        ListView {
          id: filesList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true

          ScrollBar.vertical: ScrollBar {
          }

          model: FolderListModel {
            folder: filesPage.browsePath !== "" ? "file://" + filesPage.browsePath : ""
            showDirs: true
            showDirsFirst: true
            showDotAndDotDot: false
          }

          delegate: ItemDelegate {
            width: filesList.width
            height: 44

            contentItem: RowLayout {
              spacing: 8

              Text {
                text: fileIsDir ? "📁" : (/\.(jpg|jpeg|png)$/i.test(fileName) ? "🖼" : "📄")
                font.pointSize: 14
              }

              Text {
                Layout.fillWidth: true
                text: fileName
                font: photoGallery.t.tipFont
                color: photoGallery.t.mainTextColor
                elide: Text.ElideMiddle
              }

              Text {
                text: fileIsDir ? "" : FileUtils.representFileSize(fileSize)
                font: photoGallery.t.tinyFont
                color: photoGallery.t.secondaryTextColor
              }

              Text {
                text: Qt.formatDateTime(fileModified, "yyyy-MM-dd hh:mm")
                font: photoGallery.t.tinyFont
                color: photoGallery.t.secondaryTextColor
              }
            }

            onClicked: {
              if (fileIsDir) {
                filesPage.browsePath = filePath;
              } else if (/\.(jpg|jpeg|png)$/i.test(fileName)) {
                viewer.openList([{
                      "path": filePath,
                      "name": fileName,
                      "layer": "",
                      "mtime": fileModified
                    }], 0);
              } else {
                displayToast(qsTr("Podgląd na razie tylko dla obrazów"));
              }
            }
          }
        }
      }
    }
  }

  // ── pelnoekranowy podglad z zoomem ───────────────────────
  Popup {
    id: viewer
    parent: Overlay.overlay
    width: parent ? parent.width : 100
    height: parent ? parent.height : 100
    modal: true
    padding: 0

    property var items: []
    property int idx: -1
    readonly property var cur: (idx >= 0 && idx < items.length) ? items[idx] : null
    readonly property string curRel: cur ? cur.path.substring(photoGallery.projectDir.length + 1) : ""
    property var curTags: []

    function refreshTags() {
      curTags = curRel !== "" ? tagStore.tagsForPhoto(curRel) : [];
    }

    function openList(list, i) {
      items = list;
      idx = i;
      open();
      refreshTags();
      Qt.callLater(fitToScreen);
    }

    function fitToScreen() {
      flick.resizeContent(flick.width, flick.height, Qt.point(0, 0));
      flick.contentX = 0;
      flick.contentY = 0;
    }

    onIdxChanged: {
      Qt.callLater(fitToScreen);
      refreshTags();
    }

    Connections {
      target: tagStore
      function onTagsChanged(foto) {
        if (foto === viewer.curRel)
          viewer.refreshTags();
      }
    }

    background: Rectangle {
      color: "black"
    }

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.bottomMargin: 44
      contentWidth: width
      contentHeight: height
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentWidth > width + 5 || contentHeight > height + 5
      clip: true

      PinchArea {
        width: Math.max(flick.contentWidth, flick.width)
        height: Math.max(flick.contentHeight, flick.height)

        property real startW
        property real startH

        onPinchStarted: {
          startW = flick.contentWidth;
          startH = flick.contentHeight;
        }
        onPinchUpdated: pinch => {
          flick.contentX += pinch.previousCenter.x - pinch.center.x;
          flick.contentY += pinch.previousCenter.y - pinch.center.y;
          const w = Math.max(flick.width, Math.min(startW * pinch.scale, flick.width * 8));
          const h = Math.max(flick.height, Math.min(startH * pinch.scale, flick.height * 8));
          flick.resizeContent(w, h, pinch.center);
        }
        onPinchFinished: flick.returnToBounds()

        Image {
          id: fullImage
          width: flick.contentWidth
          height: flick.contentHeight
          source: viewer.cur ? "file://" + viewer.cur.path : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          autoTransform: true
        }

        MouseArea {
          anchors.fill: parent

          property real pressX: 0
          property real pressY: 0

          onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
          }
          onReleased: mouse => {
            if (!flick.interactive) {
              const dx = mouse.x - pressX;
              const dy = mouse.y - pressY;
              if (Math.abs(dx) > 60 && Math.abs(dx) > 2 * Math.abs(dy)) {
                if (dx < 0 && viewer.idx < viewer.items.length - 1)
                  viewer.idx++;
                else if (dx > 0 && viewer.idx > 0)
                  viewer.idx--;
              }
            }
          }
          onDoubleClicked: mouse => {
            if (flick.contentWidth > flick.width * 1.05) {
              viewer.fitToScreen();
            } else {
              flick.resizeContent(flick.width * 2.5, flick.height * 2.5, Qt.point(mouse.x, mouse.y));
            }
          }
          onWheel: wheel => {
            const f = wheel.angleDelta.y > 0 ? 1.25 : 0.8;
            const w = Math.max(flick.width, Math.min(flick.contentWidth * f, flick.width * 8));
            const h = Math.max(flick.height, Math.min(flick.contentHeight * f, flick.height * 8));
            flick.resizeContent(w, h, Qt.point(wheel.x, wheel.y));
            flick.returnToBounds();
          }
        }
      }
    }

    BusyIndicator {
      anchors.centerIn: flick
      running: fullImage.status === Image.Loading
    }

    RoundButton {
      text: "‹"
      width: 64
      height: 64
      font.pointSize: 26
      Material.background: "#AA263238"
      Material.foreground: "white"
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: flick.verticalCenter
      visible: viewer.items.length > 1
      enabled: viewer.idx > 0
      opacity: 0.85
      onClicked: viewer.idx--
    }

    RoundButton {
      text: "›"
      width: 64
      height: 64
      font.pointSize: 26
      Material.background: "#AA263238"
      Material.foreground: "white"
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: flick.verticalCenter
      visible: viewer.items.length > 1
      enabled: viewer.idx < viewer.items.length - 1
      opacity: 0.85
      onClicked: viewer.idx++
    }

    RoundButton {
      text: "✕"
      width: 56
      height: 56
      font.pointSize: 18
      Material.background: "#AA263238"
      Material.foreground: "white"
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 8
      anchors.topMargin: 56
      opacity: 0.85
      onClicked: viewer.close()
    }

    RoundButton {
      text: "🏷"
      width: 64
      height: 64
      font.pointSize: 22
      Material.background: tagPanel.visible ? "#AA00695C" : "#AA263238"
      Material.foreground: "white"
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: 8
      anchors.bottomMargin: 56
      onClicked: {
        tagPanel.visible = !tagPanel.visible;
        if (tagPanel.visible) {
          viewer.refreshTags();
          tagPanel.updateSuggestions();
          tagInput.forceActiveFocus();
        }
      }
    }

    Rectangle {
      id: tagPanel

      property var suggestions: []

      function updateSuggestions() {
        const wzor = tagInput.text.trim().toLowerCase();
        const all = tagStore.knownTags();
        const out = [];
        for (let i = 0; i < all.length && out.length < 8; i++) {
          if (wzor === "" || all[i].toLowerCase().indexOf(wzor) === 0)
            out.push(all[i]);
        }
        suggestions = out;
      }

      visible: false
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 44
      color: "#DD263238"
      height: panelCol.implicitHeight + 20

      ColumnLayout {
        id: panelCol
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Flow {
          Layout.fillWidth: true
          spacing: 6
          visible: viewer.curTags.length > 0

          Repeater {
            model: viewer.curTags

            delegate: Rectangle {
              radius: height / 2
              height: 34
              width: tagChipRow.implicitWidth + 20
              color: "#00695C"

              RowLayout {
                id: tagChipRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                  text: modelData.tag + (modelData.pokrycie !== undefined && modelData.pokrycie !== null ? " " + modelData.pokrycie + "%" : "")
                  color: "white"
                  font: photoGallery.t.tipFont
                }

                Text {
                  text: "✕"
                  color: "#FFCDD2"
                  font: photoGallery.t.tipFont

                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: tagStore.removeTag(modelData.fid)
                  }
                }
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          TextField {
            id: tagInput
            Layout.fillWidth: true
            placeholderText: qsTr("Gatunek lub etykieta…")
            color: "white"
            placeholderTextColor: "#90A4AE"
            onTextChanged: tagPanel.updateSuggestions()
            onAccepted: addTagButton.clicked()
          }

          TextField {
            id: pokInput
            Layout.preferredWidth: 70
            placeholderText: "%"
            color: "white"
            placeholderTextColor: "#90A4AE"
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator {
              bottom: 0
              top: 100
            }
          }

          Button {
            id: addTagButton
            text: qsTr("Dodaj")
            enabled: tagInput.text.trim() !== ""
            onClicked: {
              const pok = pokInput.text !== "" ? parseInt(pokInput.text) : -1;
              const fid = tagStore.addTag(viewer.curRel, tagInput.text, pok);
              if (fid >= 0) {
                tagInput.text = "";
                pokInput.text = "";
                tagInput.forceActiveFocus();
              } else {
                displayToast(qsTr("Nie udało się zapisać tagu"));
              }
            }
          }
        }

        Flow {
          Layout.fillWidth: true
          spacing: 6
          visible: tagPanel.suggestions.length > 0

          Repeater {
            model: tagPanel.suggestions

            delegate: Rectangle {
              radius: height / 2
              height: 30
              width: sugText.width + 20
              color: "#455A64"

              Text {
                id: sugText
                anchors.centerIn: parent
                text: modelData
                color: "white"
                font: photoGallery.t.tipFont
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  tagInput.text = modelData;
                  pokInput.forceActiveFocus();
                }
              }
            }
          }
        }
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 44
      color: "#CC000000"

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        Text {
          Layout.fillWidth: true
          text: viewer.cur ? viewer.cur.name : ""
          color: "white"
          font: photoGallery.t.tipFont
          elide: Text.ElideMiddle
        }

        Text {
          text: viewer.curTags.length > 0 ? "🏷 " + viewer.curTags.length : ""
          color: "#80CBC4"
          font: photoGallery.t.tinyFont
        }

        Text {
          text: viewer.cur ? Qt.formatDateTime(viewer.cur.mtime, "yyyy-MM-dd hh:mm") : ""
          color: "#B0BEC5"
          font: photoGallery.t.tinyFont
        }

        Text {
          text: viewer.items.length > 1 ? (viewer.idx + 1) + " / " + viewer.items.length : ""
          color: "#B0BEC5"
          font: photoGallery.t.tinyFont
        }
      }
    }
  }
}
