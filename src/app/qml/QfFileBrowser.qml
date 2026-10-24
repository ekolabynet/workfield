import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import QtQuick.Dialogs as SystemoweOkna
import Qt.labs.folderlistmodel
import org.qfield
import org.qfield.gui
import Theme

/**
 * WorkFieldGIS 24.10.2026 [WF-FILE-BROWSER] — one "Files" window, built like a
 * system file manager (Files by Google, Windows Explorer, Dolphin).
 *
 * Why: the tester got lost between five file windows and eleven start folders
 * (review "Okna plików — przegląd", 24.10). Piotr's condition: the window has
 * to look like the system file browser.
 *
 * Why not just the Android system window: since Android 11 it does not show
 * the app's own folder (Android/data/…), where the projects are. So the app
 * shows its own places itself; the system window stays for files from outside
 * (step 3: "Inne miejsce…").
 *
 * Layout: places (a column on a wide screen, chips on a phone), a breadcrumb
 * path with human names, a list with type icons and a ⋮ menu per row.
 * Step 1 = browsing. Step 2 (24.10, 22:50) = picking a file: the same
 * window, files of another kind greyed (not hidden — one sees they are
 * there), ✕ / ✓ in the title bar; on a phone "Pobrane ↗" and "Wymiana ↗" and
 * "Inne miejsce…" open the system window (the app cannot list other apps'
 * files there). Step 3 = picking a folder ("✓ Wybierz ten folder" takes
 * the folder shown; files greyed), "Nowy folder".
 *
 * File operations are the ones proven in the gallery's "Pliki" tab (09.09):
 * the bin lives IN the project, renaming / moving only inside the project,
 * copying works everywhere.
 *
 * \ingroup qml
 */
QfWindowFrame {
  id: browser

  title: mode === "browse" ? qsTr("Pliki") : pickTitle
  exitMode: mode === "browse" ? "close" : "decision"
  confirmText: pickConfirmText
  confirmEnabled: mode === "pickFolder" ? currentPath !== "" : selectedPath !== ""
  onConfirmed: finishPick(mode === "pickFolder" ? currentPath : selectedPath)
  scrollable: false
  preferredWidth: 900
  preferredHeight: 640
  resizable: true
  sizeKey: "WorkField/oknoPlikow"
  forceFullScreen: narrowScreen

  readonly property bool onPhone: Qt.platform.os === "android" || Qt.platform.os === "ios"
  readonly property string projectDir: qgisProject && qgisProject.homePath ? String(qgisProject.homePath) : ""
  readonly property string binDir: projectDir !== "" ? projectDir + "/kosz" : ""

  property var places: []
  property string currentPath: ""
  property string message: ""
  property bool messageIsError: false
  property string clipboard: ""
  property string clipboardMode: ""   // "kopiuj" | "przenies"
  property bool sortByName: false

  //! [WF-FILE-BROWSER] step 2–3: "browse" | "pickFile" | "pickFolder"
  property string mode: "browse"
  property string pickTitle: ""
  property string pickConfirmText: qsTr("Wybierz")
  property var pickPattern: null
  property var pickDone: null
  property string selectedPath: ""
  //! a system place to point at (phone): the file is probably there
  property string hintPlace: ""
  readonly property string phoneDownloads: "/storage/emulated/0/Download"
  readonly property string phoneExchange: "/storage/emulated/0/Documents/WorkField"

  readonly property var projectPattern: /\.(qgs|qgz)$/i
  readonly property var dataPattern: /\.(gpkg|shp|geojson|json|kml|kmz|gpx|csv|tif|tiff|jp2|vrt|mbtiles|sqlite|dxf)$/i
  readonly property var imagePattern: /\.(jpg|jpeg|png)$/i

  // the same key as the Magazyn section (QfStudioSection): one root for both
  Settings {
    id: storeSettings
    category: "WFGStudio"
    property string korzenProjektow: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "") + "/WorkField"
  }

  //! Opens the window on a place: "projekt", "projekty", "karta", "szablony", "magazyn", …
  function openPlace(key) {
    mode = "browse";
    buildPlaces();
    let target = null;
    for (let i = 0; i < places.length; i++) {
      if (places[i].key === key) {
        target = places[i];
        break;
      }
    }
    if (target === null && places.length > 0)
      target = places[0];
    currentPath = target ? target.path : "";
    message = "";
    open();
  }

  //! Opens the window on any folder (it must lie under one of the places).
  function openAt(path) {
    mode = "browse";
    buildPlaces();
    currentPath = String(path).replace(/\/+$/, "");
    message = "";
    open();
  }

  /**
   * [WF-FILE-BROWSER] step 2 — the same window as a file picker.
   *   fileBrowser.pickFile({ "title": qsTr("Wskaż rysunek DXF"), "pattern": /\.dxf$/i,
   *                          "place": "pobrane", "confirmText": qsTr("Wybierz"),
   *                          "done": function (path) { … } })
   * "done" runs after the window has closed.
   */
  function pickFile(opts) {
    startPick("pickFile", opts);
  }

  /**
   * Step 3 — the same window picks a FOLDER: the one shown when ✓ is pressed.
   *   fileBrowser.pickFolder({ "title": qsTr("Dokąd zapisać?"), "place": "pobrane",
   *                            "confirmText": qsTr("Zapisz tutaj"), "done": function (folder) { … } })
   */
  function pickFolder(opts) {
    startPick("pickFolder", opts);
  }

  function startPick(newMode, opts) {
    mode = newMode;
    pickTitle = opts.title || (newMode === "pickFolder" ? qsTr("Wskaż folder") : qsTr("Wskaż plik"));
    pickConfirmText = opts.confirmText || (newMode === "pickFolder" ? qsTr("Wybierz ten folder") : qsTr("Wybierz"));
    pickPattern = opts.pattern || null;
    pickDone = opts.done || null;
    selectedPath = "";
    hintPlace = "";
    buildPlaces();
    const wanted = opts.place || "projekt";
    let target = null;
    for (let i = 0; i < places.length; i++) {
      if (places[i].key === wanted)
        target = places[i];
    }
    if (target !== null && target.system === true) {
      hintPlace = target.key;
      target = null;
    }
    if (target === null) {
      for (let i = 0; i < places.length && target === null; i++) {
        if (places[i].system !== true)
          target = places[i];
      }
    }
    currentPath = target ? target.path : "";
    message = "";
    messageIsError = false;
    if (hintPlace !== "")
      say(qsTr("Plik w Pobranych albo gdzie indziej w telefonie? Dotknij „%1 ↗” — otworzy się okno systemowe.").arg(placeName(hintPlace)));
    open();
  }

  function placeName(key) {
    for (let i = 0; i < places.length; i++) {
      if (places[i].key === key)
        return places[i].name;
    }
    return key;
  }

  //! In the pick mode: does this file fit what we are looking for?
  function matches(name, isDir) {
    if (mode === "pickFolder")
      return isDir;
    return mode !== "pickFile" || isDir || pickPattern === null || pickPattern.test(name);
  }

  function finishPick(path) {
    if (path === "")
      return;
    const done = pickDone;
    pickDone = null;
    close();
    if (done)
      done(path);
  }

  //! Places the app cannot list itself (other apps' files on a phone):
  //! the system window, opened in that folder.
  function openSystemPicker(folder) {
    if (mode === "pickFolder") {
      systemFolderPicker.currentFolder = "file://" + folder;
      systemFolderPicker.open();
      return;
    }
    systemPicker.currentFolder = "file://" + folder;
    systemPicker.open();
  }

  function goToPlace(place) {
    if (place.system === true) {
      openSystemPicker(place.path);
      return;
    }
    currentPath = place.path;
    selectedPath = "";
    message = "";
  }

  onClosed: {
    mode = "browse";
    pickDone = null;
    selectedPath = "";
    hintPlace = "";
  }

  function stripUrl(u) {
    return String(u).replace(/^file:\/\//, "").replace(/\/+$/, "");
  }

  function buildPlaces() {
    const list = [];
    if (projectDir !== "")
      list.push({ "key": "projekt", "name": qsTr("Ten projekt"), "path": projectDir, "kind": "qgz" });
    const dataRoot = String(iface.dataRoot()).replace(/\/+$/, "");
    if (onPhone) {
      let places0 = [];
      try {
        places0 = iface.miejscaProjektow();
      } catch (e) {
        places0 = [];
      }
      for (let i = 0; i < places0.length; i++) {
        const card = places0[i].rodzaj === "karta";
        list.push({ "key": card ? "karta" : "projekty", "name": card ? qsTr("Karta SD") : qsTr("Projekty"), "path": stripUrl(places0[i].katalog), "kind": "folder" });
      }
      if (places0.length === 0)
        list.push({ "key": "projekty", "name": qsTr("Projekty"), "path": dataRoot + "/Imported Projects", "kind": "folder" });
    } else {
      const store = stripUrl(storeSettings.korzenProjektow);
      list.push({ "key": "projekty", "name": qsTr("Projekty"), "path": store + "/wydania", "kind": "folder" });
      list.push({ "key": "magazyn", "name": qsTr("Magazyn"), "path": store, "kind": "folder" });
    }
    list.push({ "key": "szablony", "name": qsTr("Szablony"), "path": dataRoot + "/Szablony", "kind": "folder" });
    if (!onPhone) {
      list.push({ "key": "pobrane", "name": qsTr("Pobrane"), "path": stripUrl(StandardPaths.writableLocation(StandardPaths.DownloadLocation)), "kind": "folder" });
      list.push({ "key": "wymiana", "name": qsTr("Wymiana"), "path": stripUrl(storeSettings.korzenProjektow) + "/wymiana", "kind": "folder" });
    }
    const shown = list.filter(p => p.path !== "" && FileUtils.fileExists(p.path));
    // phone, pick mode: other apps' files are visible only in the system window
    if (onPhone && mode !== "browse") {
      shown.push({ "key": "pobrane", "name": qsTr("Pobrane"), "path": phoneDownloads, "kind": "folder", "system": true });
      shown.push({ "key": "wymiana", "name": qsTr("Wymiana"), "path": phoneExchange, "kind": "folder", "system": true });
    }
    places = shown;
  }

  //! The place the current folder belongs to (the longest matching root).
  readonly property var currentPlace: {
    let best = null;
    for (let i = 0; i < places.length; i++) {
      const p = places[i].path;
      if ((currentPath === p || currentPath.indexOf(p + "/") === 0) && (best === null || p.length > best.path.length))
        best = places[i];
    }
    return best;
  }

  //! Breadcrumbs: place name, then the folders below it.
  readonly property var crumbs: {
    if (currentPlace === null)
      return currentPath === "" ? [] : [{ "name": currentPath, "path": currentPath }];
    const out = [{ "name": currentPlace.name, "path": currentPlace.path }];
    const rest = currentPath.substring(currentPlace.path.length).split("/").filter(s => s !== "");
    let p = currentPlace.path;
    for (let i = 0; i < rest.length; i++) {
      p += "/" + rest[i];
      out.push({ "name": rest[i], "path": p });
    }
    return out;
  }

  function goUp() {
    if (currentPlace === null || currentPath === currentPlace.path)
      return;
    currentPath = currentPath.substring(0, currentPath.lastIndexOf("/"));
  }

  function say(text, isError) {
    message = text;
    messageIsError = isError === true;
  }

  function kindOf(name, isDir) {
    if (isDir)
      return "folder";
    const m = /\.([A-Za-z0-9]+)$/.exec(name);
    return m ? m[1].toLowerCase() : "";
  }

  function kindLabel(name, isDir) {
    if (isDir)
      return qsTr("folder");
    if (projectPattern.test(name))
      return qsTr("projekt");
    if (imagePattern.test(name))
      return qsTr("zdjęcie");
    if (/\.dxf$/i.test(name))
      return qsTr("rysunek");
    if (/\.zip$/i.test(name))
      return qsTr("paczka");
    if (dataPattern.test(name))
      return qsTr("dane");
    return qsTr("plik");
  }

  function dateLabel(d) {
    const now = new Date();
    if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate())
      return qsTr("dziś %1").arg(Qt.formatDateTime(d, "HH:mm"));
    return Qt.formatDateTime(d, d.getFullYear() === now.getFullYear() ? "dd.MM HH:mm" : "dd.MM.yyyy");
  }

  // ── file operations (from the gallery "Pliki" tab, 09.09) ────────────────
  function insideProject(path) {
    return projectDir !== "" && String(path).indexOf(projectDir + "/") === 0;
  }

  //! Files the app is using NOW: a refusal, not a warning.
  function lockReason(name, path) {
    if (projectDir === "" || String(path) !== projectDir + "/" + name)
      return "";
    if (/^dane\.gpkg(-wal|-shm)?$/i.test(name))
      return qsTr("baza otwartego projektu");
    if (/\.qg[sz]$/i.test(name))
      return qsTr("plik otwartego projektu");
    return "";
  }

  function stamp() {
    const d = new Date();
    function two(n) {
      return ("0" + n).slice(-2);
    }
    return "" + d.getFullYear() + two(d.getMonth() + 1) + two(d.getDate()) + "_" + two(d.getHours()) + two(d.getMinutes());
  }

  function toBin(name, path) {
    const reason = lockReason(name, path);
    if (reason !== "") {
      say(qsTr("Nie usunięto — %1.").arg(reason), true);
      return;
    }
    if (!insideProject(path)) {
      say(qsTr("Do kosza można przenieść tylko pliki bieżącego projektu."), true);
      return;
    }
    // the source path is kept IN THE NAME (`/` → `__`), so it can be restored
    const relative = String(path).substring(projectDir.length + 1);
    platformUtilities.createDir(projectDir, "kosz");
    const target = binDir + "/" + stamp() + "__" + relative.replace(/\//g, "__");
    if (platformUtilities.renameFile(path, target, false))
      say(qsTr("Do kosza: %1").arg(name));
    else
      say(qsTr("Nie udało się przenieść do kosza."), true);
  }

  function restoreFromBin(name, path) {
    const i = String(name).indexOf("__");
    if (i < 0) {
      say(qsTr("Nie wiadomo, skąd ten plik pochodzi."), true);
      return;
    }
    const target = projectDir + "/" + String(name).substring(i + 2).replace(/__/g, "/");
    if (platformUtilities.renameFile(path, target, false))
      say(qsTr("Przywrócono: %1").arg(target.replace(projectDir + "/", "")));
    else
      say(qsTr("Nie udało się — czy plik o tej nazwie już tam jest?"), true);
  }

  function pasteHere() {
    if (clipboard === "")
      return;
    const target = currentPath + "/" + String(clipboard).replace(/\/+$/, "").replace(/^.*\//, "");
    if (target === clipboard) {
      say(qsTr("Źródło i cel to to samo miejsce."), true);
      return;
    }
    if (clipboardMode === "przenies" && !insideProject(clipboard)) {
      say(qsTr("Przenieść można tylko w obrębie projektu. Użyj „Kopiuj”."), true);
      return;
    }
    if (!insideProject(target)) {
      say(qsTr("Wkleić można tylko do folderu bieżącego projektu."), true);
      return;
    }
    // wipeDestFolder = false — otherwise pasting into an existing folder wipes it first
    const ok = clipboardMode === "przenies" ? platformUtilities.renameFile(clipboard, target, false) : FileUtils.copyRecursively(clipboard, target, null, false);
    if (ok) {
      say(clipboardMode === "przenies" ? qsTr("Przeniesiono.") : qsTr("Skopiowano."));
      clipboard = "";
      clipboardMode = "";
    } else {
      say(qsTr("Nie udało się. Czy plik o tej nazwie już tu jest?"), true);
    }
  }

  //! Tap on a file: the same as in the gallery — project opens, data is added
  //! to the project, anything else goes to the system viewer.
  function activate(name, path, isDir) {
    if (isDir) {
      currentPath = String(path);
      selectedPath = "";
      message = "";
      return;
    }
    if (mode === "pickFolder") {
      say(qsTr("Wybierasz folder: wejdź do niego i naciśnij „%1”.").arg(pickConfirmText));
      return;
    }
    if (mode === "pickFile") {
      if (!matches(name, false)) {
        say(qsTr("Ten plik się nie nadaje. %1.").arg(pickTitle), true);
        return;
      }
      // first tap selects (✓ in the title bar), a second tap on it confirms
      if (selectedPath === String(path))
        finishPick(String(path));
      else
        selectedPath = String(path);
      message = "";
      return;
    }
    if (projectPattern.test(name)) {
      browser.close();
      iface.loadFile(path, FileUtils.fileName(path, false));
      return;
    }
    if (dataPattern.test(name)) {
      if (iface.loadFile(path, FileUtils.fileName(path, false)))
        say(qsTr("Dodano warstwę: %1").arg(name));
      else
        say(qsTr("Nie udało się otworzyć: %1 — aplikacja nie zna tego formatu").arg(name), true);
      return;
    }
    platformUtilities.open(path);
  }

  onOpened: {
    if (places.length === 0)
      buildPlaces();
  }

  // ── small parts ──────────────────────────────────────────────────────────
  component FileIcon: Item {
    property string kind: "folder"
    implicitWidth: 36
    implicitHeight: 36

    Rectangle {
      visible: parent.kind === "folder"
      x: 2
      y: 8
      width: 32
      height: 23
      radius: 3
      color: "#FFB74D"

      Rectangle {
        x: 0
        y: -4
        width: 13
        height: 6
        radius: 2
        color: "#FFB74D"
      }
    }

    Rectangle {
      visible: parent.kind !== "folder"
      x: 6
      y: 2
      width: 24
      height: 32
      radius: 3
      color: ({
          "gpkg": "#5C6BC0",
          "qgz": "#26A69A",
          "qgs": "#26A69A",
          "jpg": "#8D6E63",
          "jpeg": "#8D6E63",
          "png": "#8D6E63",
          "dxf": "#EF6C00",
          "zip": "#78909C",
          "csv": "#7CB342",
          "pdf": "#E53935"
        })[parent.kind] || "#78909C"

      Text {
        anchors.centerIn: parent
        width: parent.width - 2
        horizontalAlignment: Text.AlignHCenter
        text: parent.parent.kind.toUpperCase().substring(0, 4)
        color: "white"
        font.pixelSize: text.length > 3 ? 7 : 8
        font.bold: true
      }
    }
  }

  component PlaceButton: Rectangle {
    id: placeButton
    property var place: null
    readonly property bool active: browser.currentPlace !== null && place !== null && browser.currentPlace.key === place.key
    Layout.fillWidth: true
    implicitHeight: 40
    radius: 20
    color: active ? Qt.rgba(0.30, 0.71, 0.67, 0.25) : (placeMouse.pressed ? Qt.rgba(1, 1, 1, 0.12) : "transparent")

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      spacing: 8

      FileIcon {
        kind: placeButton.place ? placeButton.place.kind : "folder"
        scale: 0.7
        Layout.preferredWidth: 26
        Layout.preferredHeight: 26
      }

      Text {
        Layout.fillWidth: true
        text: placeButton.place ? placeButton.place.name + (placeButton.place.system === true ? " ↗" : "") : ""
        color: placeButton.active ? "#4DB6AC" : Theme.mainTextColor
        font.pointSize: Theme.tipFont.pointSize
        font.bold: placeButton.active
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: placeMouse
      anchors.fill: parent
      onClicked: browser.goToPlace(placeButton.place)
    }
  }

  //! an outlined button in the window's own colours (the platform style
  //! painted it light on the dark window)
  component OutlineButton: Rectangle {
    id: outline
    property string text: ""
    signal clicked
    implicitHeight: 40
    radius: 6
    color: outlineMouse.pressed ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
    border.width: 1
    border.color: Theme.controlBorderColor

    Text {
      anchors.centerIn: parent
      width: parent.width - 12
      horizontalAlignment: Text.AlignHCenter
      text: outline.text
      color: Theme.mainTextColor
      font.pointSize: Theme.tipFont.pointSize
      elide: Text.ElideRight
    }

    MouseArea {
      id: outlineMouse
      anchors.fill: parent
      onClicked: outline.clicked()
    }
  }

  component PlaceChip: Rectangle {
    id: chip
    property var place: null
    readonly property bool active: browser.currentPlace !== null && place !== null && browser.currentPlace.key === place.key
    implicitHeight: 34
    implicitWidth: chipText.implicitWidth + 28
    radius: 17
    color: active ? Qt.rgba(0.30, 0.71, 0.67, 0.25) : "transparent"
    border.width: chip.place !== null && browser.hintPlace === chip.place.key ? 2 : 1
    border.color: active ? "#4DB6AC" : (chip.place !== null && browser.hintPlace === chip.place.key ? "#fb8c00" : Theme.controlBorderColor)

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.place ? chip.place.name + (chip.place.system === true ? " ↗" : "") : ""
      color: chip.active ? "#4DB6AC" : Theme.mainTextColor
      font.pointSize: Theme.tipFont.pointSize
    }

    MouseArea {
      anchors.fill: parent
      onClicked: browser.goToPlace(chip.place)
    }
  }

  // ── window body ──────────────────────────────────────────────────────────
  RowLayout {
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 10

    // wide screen: places in a column on the left, like Explorer / Dolphin
    ColumnLayout {
      visible: !browser.narrowScreen
      Layout.preferredWidth: 210
      Layout.maximumWidth: 210
      Layout.fillHeight: true
      spacing: 2

      Text {
        text: qsTr("MIEJSCA")
        color: Theme.secondaryTextColor
        font.pointSize: Theme.tinyFont.pointSize
        font.bold: true
        Layout.bottomMargin: 4
      }

      Repeater {
        model: browser.places
        delegate: PlaceButton {
          required property var modelData
          place: modelData
        }
      }

      Item {
        Layout.fillHeight: true
      }

      OutlineButton {
        visible: browser.mode !== "browse"
        Layout.fillWidth: true
        text: qsTr("Inne miejsce…")
        onClicked: browser.openSystemPicker(browser.currentPath)
      }
    }

    Rectangle {
      visible: !browser.narrowScreen
      Layout.preferredWidth: 1
      Layout.fillHeight: true
      color: Theme.controlBorderColor
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 4

      // phone: places as chips at the top
      Flow {
        visible: browser.narrowScreen
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: browser.places
          delegate: PlaceChip {
            required property var modelData
            place: modelData
          }
        }
      }

      // breadcrumbs with human names, never "Android/data/…"
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 4

        QfToolButton {
          Layout.preferredWidth: 36
          Layout.preferredHeight: 36
          enabled: browser.currentPlace !== null && browser.currentPath !== browser.currentPlace.path
          opacity: enabled ? 1 : 0.35
          iconSource: Theme.getThemeVectorIcon("ic_arrow_left_white_24dp")
          iconColor: Theme.mainTextColor
          onClicked: browser.goUp()
        }

        Flickable {
          id: crumbScroller
          Layout.fillWidth: true
          Layout.preferredHeight: 36
          clip: true
          contentWidth: crumbRow.implicitWidth
          contentX: Math.max(0, contentWidth - width)
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds

          Row {
            id: crumbRow
            height: parent.height
            spacing: 6

            Repeater {
              model: browser.crumbs
              delegate: Row {
                required property var modelData
                required property int index
                height: crumbRow.height
                spacing: 6

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: index > 0
                  text: "›"
                  color: Theme.secondaryTextColor
                  font.pointSize: Theme.tipFont.pointSize + 2
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property bool last: index === browser.crumbs.length - 1
                  text: modelData.name
                  color: last ? Theme.mainTextColor : "#4DB6AC"
                  font.pointSize: Theme.tipFont.pointSize
                  font.bold: last

                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: {
                      browser.currentPath = modelData.path;
                      browser.message = "";
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          // [WF-FILE-BROWSER] step 3 — a new folder here (export, ordering)
          text: qsTr("+ folder")
          visible: browser.currentPath !== ""
          color: "#4DB6AC"
          font.pointSize: Theme.tinyFont.pointSize
          Layout.rightMargin: 10

          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            onClicked: newFolderWindow.open()
          }
        }

        Text {
          text: browser.sortByName ? qsTr("A–Z") : qsTr("najnowsze")
          color: Theme.secondaryTextColor
          font.pointSize: Theme.tinyFont.pointSize

          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            onClicked: browser.sortByName = !browser.sortByName
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.controlBorderColor
      }

      // after an operation: without it the action stays silent
      Text {
        Layout.fillWidth: true
        visible: browser.message !== ""
        text: browser.message
        color: browser.messageIsError ? "#EF5350" : "#9CCC65"
        font.pointSize: Theme.tinyFont.pointSize
        wrapMode: Text.Wrap
      }

      // clipboard: visible only when something is in it
      Rectangle {
        Layout.fillWidth: true
        visible: browser.clipboard !== ""
        implicitHeight: 40
        radius: 4
        color: "#33FFC107"

        RowLayout {
          anchors.fill: parent
          anchors.margins: 6
          spacing: 8

          Text {
            Layout.fillWidth: true
            text: (browser.clipboardMode === "przenies" ? qsTr("Do przeniesienia: ") : qsTr("Do skopiowania: ")) + String(browser.clipboard).replace(/^.*\//, "")
            color: "#FFC107"
            font.pointSize: Theme.tinyFont.pointSize
            elide: Text.ElideMiddle
          }

          Button {
            text: qsTr("Wklej tutaj")
            font.pointSize: Theme.tinyFont.pointSize
            enabled: browser.insideProject(browser.currentPath + "/x")
            onClicked: browser.pasteHere()
          }

          Button {
            text: "✕"
            onClicked: {
              browser.clipboard = "";
              browser.clipboardMode = "";
            }
          }
        }
      }

      ListView {
        id: fileList
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 120
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: QfScrollBar {
        }

        model: FolderListModel {
          id: folderModel
          folder: browser.currentPath !== "" ? "file://" + browser.currentPath : ""
          showDirs: true
          showDirsFirst: true
          showDotAndDotDot: false
          showHidden: false
          sortField: browser.sortByName ? FolderListModel.Name : FolderListModel.Time
        }

        delegate: Rectangle {
          id: row
          required property string fileName
          required property string filePath
          required property bool fileIsDir
          required property var fileModified
          required property var fileSize

          readonly property bool fits: browser.matches(fileName, fileIsDir)
          readonly property bool chosen: browser.selectedPath !== "" && browser.selectedPath === String(filePath)

          width: fileList.width
          height: 56
          color: chosen ? Qt.rgba(0.30, 0.71, 0.67, 0.30) : (rowMouse.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
          opacity: fits ? 1.0 : 0.4

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 2
            spacing: 12

            FileIcon {
              kind: browser.kindOf(row.fileName, row.fileIsDir)
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              Text {
                Layout.fillWidth: true
                text: row.fileName
                color: Theme.mainTextColor
                font.pointSize: Theme.tipFont.pointSize
                elide: Text.ElideMiddle
              }

              Text {
                Layout.fillWidth: true
                text: browser.kindLabel(row.fileName, row.fileIsDir) + " · " + browser.dateLabel(row.fileModified) + (row.fileIsDir ? "" : " · " + FileUtils.representFileSize(row.fileSize))
                color: Theme.secondaryTextColor
                font.pointSize: Theme.tinyFont.pointSize
                elide: Text.ElideRight
              }
            }

            Text {
              text: "⋮"
              color: Theme.secondaryTextColor
              font.pixelSize: 22
              Layout.preferredWidth: 36
              horizontalAlignment: Text.AlignHCenter

              MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                onClicked: fileMenu.show(row.fileName, row.filePath, row.fileIsDir)
              }
            }
          }

          Rectangle {
            anchors.bottom: parent.bottom
            x: 54
            width: parent.width - 54
            height: 1
            color: Theme.controlBorderColor
            opacity: 0.6
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            anchors.rightMargin: 44
            onClicked: browser.activate(row.fileName, row.filePath, row.fileIsDir)
            onPressAndHold: fileMenu.show(row.fileName, row.filePath, row.fileIsDir)
          }
        }

        Text {
          anchors.centerIn: parent
          visible: fileList.count === 0
          text: browser.currentPath === "" ? qsTr("Brak miejsca do pokazania") : qsTr("Pusty folder")
          color: Theme.secondaryTextColor
          font.pointSize: Theme.tipFont.pointSize
        }
      }

      // phone, pick mode: the way out to the system window
      OutlineButton {
        visible: browser.mode !== "browse" && browser.narrowScreen
        Layout.fillWidth: true
        text: browser.onPhone ? qsTr("Inne miejsce… (okno systemowe Androida)") : qsTr("Inne miejsce…")
        onClicked: browser.openSystemPicker(browser.onPhone ? browser.phoneDownloads : browser.currentPath)
      }
    }
  }

  // ── one menu for the whole list ─────────────────────────────────────────
  Menu {
    id: fileMenu

    property string name: ""
    property string path: ""
    property bool isDir: false
    readonly property bool inProject: browser.insideProject(path)
    readonly property bool inBin: browser.binDir !== "" && String(path).indexOf(browser.binDir + "/") === 0
    readonly property string lock: browser.lockReason(name, path)

    function show(n, p, d) {
      name = n;
      path = String(p);
      isDir = d === true;
      browser.message = "";
      popup();
    }

    MenuItem {
      text: fileMenu.isDir ? qsTr("Otwórz folder") : qsTr("Otwórz")
      onTriggered: browser.activate(fileMenu.name, fileMenu.path, fileMenu.isDir)
    }

    MenuItem {
      text: qsTr("Zmień nazwę")
      enabled: fileMenu.inProject
      onTriggered: {
        renameWindow.oldName = fileMenu.name;
        renameWindow.fullPath = fileMenu.path;
        renameWindow.inUse = fileMenu.lock;
        renameWindow.open();
      }
    }

    // copying works EVERYWHERE — copyRecursively goes from the store into the project
    MenuItem {
      text: qsTr("Kopiuj")
      onTriggered: {
        browser.clipboard = fileMenu.path;
        browser.clipboardMode = "kopiuj";
        browser.say(qsTr("W schowku — wejdź, gdzie wkleić."));
      }
    }

    MenuItem {
      text: qsTr("Przenieś")
      enabled: fileMenu.inProject && fileMenu.lock === ""
      onTriggered: {
        browser.clipboard = fileMenu.path;
        browser.clipboardMode = "przenies";
        browser.say(qsTr("W schowku — wejdź, gdzie przenieść."));
      }
    }

    MenuItem {
      text: qsTr("Wyślij")
      onTriggered: {
        if (fileMenu.isDir)
          platformUtilities.sendCompressedFolderTo(fileMenu.path);
        else
          platformUtilities.sendCompressedFilesTo([fileMenu.path]);
      }
    }

    MenuItem {
      text: qsTr("Przywróć z kosza")
      visible: fileMenu.inBin
      height: visible ? implicitHeight : 0
      onTriggered: browser.restoreFromBin(fileMenu.name, fileMenu.path)
    }

    MenuItem {
      text: fileMenu.inProject ? qsTr("Do kosza") : qsTr("Do kosza — tylko w projekcie")
      visible: !fileMenu.inBin
      height: visible ? implicitHeight : 0
      enabled: fileMenu.inProject && fileMenu.lock === ""
      onTriggered: browser.toBin(fileMenu.name, fileMenu.path)
    }
  }

  // [WF-FILE-BROWSER] step 2 — the system window, only as "Inne miejsce…".
  // No extension filter: Android filters by MIME type and DXF has none, so
  // "*.dxf" hid everything (18.09). The kind is checked AFTER the choice.
  SystemoweOkna.FileDialog {
    id: systemPicker
    title: browser.pickTitle
    nameFilters: [qsTr("Wszystkie pliki (*)")]
    onAccepted: {
      const path = String(selectedFile).replace(/^file:\/\//, "");
      if (!browser.matches(FileUtils.fileName(path), false)) {
        browser.say(qsTr("Ten plik się nie nadaje: %1").arg(FileUtils.fileName(path)), true);
        return;
      }
      browser.finishPick(path);
    }
  }

  SystemoweOkna.FolderDialog {
    id: systemFolderPicker
    title: browser.pickTitle
    onAccepted: browser.finishPick(String(selectedFolder).replace(/^file:\/\//, ""))
  }

  // [WF-FILE-BROWSER] step 3 — "+ folder"
  QfWindowFrame {
    id: newFolderWindow

    title: qsTr("Nowy folder")
    confirmText: qsTr("Utwórz")
    confirmEnabled: newFolderField.text.trim() !== "" && !/[\/\\]/.test(newFolderField.text)
    preferredWidth: 520
    onConfirmed: create()

    onOpened: {
      newFolderField.text = "";
      newFolderField.forceActiveFocus();
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("W folderze: %1").arg(browser.crumbs.length > 0 ? browser.crumbs[browser.crumbs.length - 1].name : browser.currentPath)
      color: Theme.secondaryTextColor
      font: Theme.tipFont
      elide: Text.ElideMiddle
    }

    TextField {
      id: newFolderField
      Layout.fillWidth: true
      font: Theme.defaultFont
      onAccepted: newFolderWindow.create()
    }

    function create() {
      const name = newFolderField.text.trim();
      if (name === "" || /[\/\\]/.test(name))
        return;
      if (platformUtilities.createDir(browser.currentPath, name)) {
        browser.say(qsTr("Utworzono folder %1").arg(name));
        browser.currentPath = browser.currentPath + "/" + name;
      } else {
        browser.say(qsTr("Nie udało się utworzyć folderu %1").arg(name), true);
      }
      close();
    }
  }

  // a separate window, because one cannot type in a MenuItem
  QfWindowFrame {
    id: renameWindow

    property string oldName: ""
    property string fullPath: ""
    property string inUse: ""

    title: qsTr("Nowa nazwa")
    confirmText: qsTr("Zmień")
    confirmEnabled: nameField.text.trim() !== "" && nameField.text !== renameWindow.oldName
    preferredWidth: 520
    onConfirmed: apply()

    onOpened: {
      nameField.text = oldName;
      const k = oldName.lastIndexOf(".");
      nameField.select(0, k > 0 ? k : oldName.length);
      nameField.forceActiveFocus();
    }

    TextField {
      id: nameField
      Layout.fillWidth: true
      font: Theme.defaultFont
      onAccepted: renameWindow.apply()
    }

    Text {
      Layout.fillWidth: true
      visible: renameWindow.inUse !== ""
      text: qsTr("Uwaga: %1. Aplikacja może stracić do niego dostęp — zamknij projekt przed zmianą.").arg(renameWindow.inUse)
      color: "#FFC107"
      font: Theme.tipFont
      wrapMode: Text.Wrap
    }

    function apply() {
      const fresh = nameField.text.trim();
      if (fresh === "" || fresh === oldName) {
        close();
        return;
      }
      if (/[\/\\]/.test(fresh)) {
        browser.say(qsTr("Nazwa nie może zawierać ukośników."), true);
        return;
      }
      const target = String(fullPath).replace(/\/[^\/]*$/, "") + "/" + fresh;
      if (platformUtilities.renameFile(fullPath, target, false))
        browser.say(qsTr("Nazwa zmieniona na %1").arg(fresh));
      else
        browser.say(qsTr("Nie udało się — czy plik %1 już tu jest?").arg(fresh), true);
      close();
    }
  }
}
