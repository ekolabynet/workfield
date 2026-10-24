import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield.core
import org.qfield.gui
import Theme

/**
 * \ingroup qml
 *
 * WorkField 24.10.2026 [WF-SPLIT-HEIR] — after a split: which part is the old
 * object, and where each of its photos goes.
 *
 * Decisions of Piotr (claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md,
 * section 7): the split tools ask who inherits the identity (fid, uuid,
 * number), and for every photo of the object which part it belongs to.
 * Opened by SplitHeirUtils.choiceRequested after both split tools (line on
 * the map, multipart object into objects). The default is what the split
 * did anyway — the old record keeps its part and all photos — so "OK" without
 * any change leaves everything as it is.
 */
QfDialog {
  id: splitHeirDialog

  //! geometryWrapper of the map highlighter: a tapped part flashes on the map
  property var highlighter: null
  //! map settings: the numbers of the parts are drawn on the map
  property var mapSettings: null

  property var layer: null
  property var originalFid: -1
  property var parts: []
  property var photos: []
  property var crs: null
  property var heirFid: -1
  //! photo key (layerId + "/" + fid) → part fid
  property var photoTargets: ({})

  parent: mainWindow.contentItem
  z: 10000
  width: Math.min(mainWindow.width - 24, 460)
  // the map stays visible above: the chosen part flashes there.
  // 24.10.2026: on the desktop the status bar (X / Namiar) covered the bottom
  // of the dialog — keep clear of the lowest ~10% of the window.
  y: Math.max(12, mainWindow.height - height - Math.max(72, mainWindow.height * 0.1))
  dim: false
  // 24.10.2026: the dialog covered the parts and could not be moved. Now the
  // map stays usable underneath (move, zoom) and the dialog is dragged by
  // the bar at its top.
  modal: false
  closePolicy: Popup.NoAutoClose
  // short: a long title is cut with "…" on a phone
  title: qsTr("Podział obiektu")

  function openFor(targetLayer, fid, newUuids) {
    let info = {};
    try {
      info = SplitHeirUtils.partsInfo(targetLayer, fid, newUuids, mapSettings ? mapSettings.destinationCrs : null);
    } catch (e) {
      console.log("WorkField [WF-SPLIT-HEIR]: partsInfo failed: " + e);
      return;
    }
    if (!info.parts || info.parts.length < 2) {
      console.log("WorkField [WF-SPLIT-HEIR]: fewer than 2 parts found, no dialog");
      return;
    }
    layer = targetLayer;
    originalFid = fid;
    parts = info.parts;
    photos = info.photos || [];
    crs = info.crs;
    heirFid = fid;
    const targets = {};
    for (let i = 0; i < photos.length; i++)
      targets[photoKey(photos[i])] = fid;
    photoTargets = targets;
    console.log("WorkField [WF-SPLIT-HEIR]: dialog for " + targetLayer.name + " fid " + fid + ", parts " + parts.length + ", photos " + photos.length);
    open();
    flash(fid);
  }

  function photoKey(photo) {
    return photo.layerId + "/" + photo.fid;
  }

  function partIndex(fid) {
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].fid === fid)
        return i;
    }
    return 0;
  }

  function partLabel(index) {
    const part = parts[index];
    let text = qsTr("Kawałek %1").arg(index + 1);
    if (part.sizeText !== "")
      text += " — " + part.sizeText;
    return text;
  }

  //! [WF-SPLIT-HEIR] 24.10.2026, Piotr: the part is chosen by its number —
  //! the same number stands on the map in a circle
  function choose(fid) {
    // photos that went with the old object follow the new choice
    const previous = heirFid;
    heirFid = fid;
    const targets = Object.assign({}, photoTargets);
    for (const key in targets) {
      if (targets[key] === previous)
        targets[key] = fid;
    }
    photoTargets = targets;
    flash(fid);
  }

  function flash(fid) {
    if (!highlighter)
      return;
    const part = parts[partIndex(fid)];
    highlighter.qgsGeometry = part.geometry;
    highlighter.crs = crs;
  }

  function setPhotoTarget(photo, fid) {
    const targets = Object.assign({}, photoTargets);
    targets[photoKey(photo)] = fid;
    photoTargets = targets;
  }

  // 24.10.2026: the dialog sizes itself from IMPLICIT sizes — a Flickable
  // has none of its own, so the list was cut off below the first line.
  Flickable {
    implicitWidth: splitHeirDialog.availableWidth
    implicitHeight: Math.min(contentColumn.implicitHeight, mainWindow.height * 0.5)
    width: parent.width
    height: implicitHeight
    contentHeight: contentColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: contentColumn
      width: parent.width
      spacing: 6

      // grip: drag the dialog away from the parts
      Item {
        width: parent.width
        height: 24

        Rectangle {
          anchors.centerIn: parent
          width: 56
          height: 6
          radius: 3
          color: Theme.secondaryTextColor
        }

        MouseArea {
          property point pressPoint
          property point startPosition
          anchors.fill: parent
          cursorShape: Qt.SizeAllCursor
          onPressed: mouse => {
            pressPoint = mapToItem(splitHeirDialog.parent, mouse.x, mouse.y);
            startPosition = Qt.point(splitHeirDialog.x, splitHeirDialog.y);
          }
          onPositionChanged: mouse => {
            const now = mapToItem(splitHeirDialog.parent, mouse.x, mouse.y);
            splitHeirDialog.x = Math.max(0, Math.min(mainWindow.width - splitHeirDialog.width, startPosition.x + now.x - pressPoint.x));
            splitHeirDialog.y = Math.max(0, Math.min(mainWindow.height - splitHeirDialog.height, startPosition.y + now.y - pressPoint.y));
          }
        }
      }

      Label {
        width: parent.width
        wrapMode: Text.WordWrap
        font.bold: true
        color: Theme.mainTextColor
        text: qsTr("Który kawałek jest dawnym obiektem?")
      }

      Label {
        width: parent.width
        wrapMode: Text.WordWrap
        font: Theme.tipFont
        color: Theme.secondaryTextColor
        text: qsTr("Numery kawałków są na mapie. Dawny obiekt zachowuje numer, identyfikator i zdjęcia; pozostałe kawałki to nowe obiekty.")
      }

      Flow {
        width: parent.width
        spacing: 8

        Repeater {
          model: splitHeirDialog.parts

          // same look as the numbers on the map: green = the old object
          delegate: Rectangle {
            id: numberButton
            required property var modelData
            required property int index
            readonly property bool chosen: modelData.fid === splitHeirDialog.heirFid
            width: 52
            height: 52
            radius: 26
            color: chosen ? "#43a047" : "#37474f"
            border.color: "white"
            border.width: chosen ? 3 : 1

            Text {
              anchors.centerIn: parent
              text: String(numberButton.index + 1)
              color: "white"
              font.pixelSize: 22
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: splitHeirDialog.choose(numberButton.modelData.fid)
            }
          }
        }
      }

      Label {
        width: parent.width
        wrapMode: Text.WordWrap
        font: Theme.tipFont
        color: Theme.mainTextColor
        text: {
          const index = splitHeirDialog.partIndex(splitHeirDialog.heirFid);
          if (splitHeirDialog.parts.length === 0)
            return "";
          return qsTr("Dawny obiekt: %1").arg(splitHeirDialog.partLabel(index)) + (splitHeirDialog.parts[index].original ? " " + qsTr("(tu był do tej pory)") : "");
        }
      }

      Label {
        width: parent.width
        topPadding: 6
        visible: splitHeirDialog.photos.length > 0
        wrapMode: Text.WordWrap
        font.bold: true
        color: Theme.mainTextColor
        text: qsTr("Zdjęcia — do którego kawałka należą?")
      }

      Repeater {
        model: splitHeirDialog.photos

        delegate: RowLayout {
          id: photoRow
          required property var modelData
          width: parent.width
          spacing: 8

          Image {
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 112
            sourceSize.height: 112
            source: photoRow.modelData.absolutePath !== "" ? UrlUtils.fromString(photoRow.modelData.absolutePath) : ""
          }

          Label {
            Layout.fillWidth: true
            text: String(photoRow.modelData.path).split("/").pop()
            font: Theme.tinyFont
            color: Theme.mainTextColor
            elide: Text.ElideMiddle
          }

          ComboBox {
            Layout.preferredWidth: 150
            font: Theme.tipFont
            model: splitHeirDialog.parts.map((part, i) => qsTr("Kawałek %1").arg(i + 1))
            currentIndex: splitHeirDialog.partIndex(splitHeirDialog.photoTargets[splitHeirDialog.photoKey(photoRow.modelData)])
            onActivated: {
              const fid = splitHeirDialog.parts[currentIndex].fid;
              splitHeirDialog.setPhotoTarget(photoRow.modelData, fid);
              splitHeirDialog.flash(fid);
            }
          }
        }
      }
    }
  }

  onAccepted: {
    const list = [];
    for (let i = 0; i < photos.length; i++) {
      list.push({
          "layerId": photos[i].layerId,
          "fid": photos[i].fid,
          "target": photoTargets[photoKey(photos[i])]
        });
    }
    const result = SplitHeirUtils.applyChoice(layer, originalFid, heirFid, list);
    displayToast(result.message, result.ok ? "info" : "warning");
  }

  onRejected: {
    displayToast(qsTr("Bez zmian: dawny obiekt i zdjęcia zostały przy kawałku, przy którym były."));
  }
}
