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
  // the system back / Esc go up a folder (back()), not close the window
  closePolicy: Popup.NoAutoClose

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
  readonly property string phoneStorage: "/storage/emulated/0"
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

  /**
   * [WF-FILE-BROWSER] 25.10.2026 (Piotr 00:06) — every window starts WHERE THE
   * PROJECTS ARE: the folder holding the open project; without a project, the
   * projects folder on the chosen storage (phone or SD card — the same choice
   * as for new projects); on a computer the WorkField folder.
   */
  function projectsHome() {
    if (projectDir !== "")
      return projectDir.substring(0, projectDir.lastIndexOf("/"));
    if (onPhone) {
      let k = "";
      try {
        k = stripUrl(iface.katalogNowychProjektow());
      } catch (e) {
        k = "";
      }
      if (k !== "" && FileUtils.folderExists(k))
        return k;
      return stripUrl(iface.dataRoot()) + "/Imported Projects";
    }
    // computer: the WorkField folder itself (Piotr 25.10, 00:13)
    const w = stripUrl(storeSettings.korzenProjektow);
    return FileUtils.folderExists(w) ? w : stripUrl(iface.dataRoot());
  }

  function desktopDownloads() {
    return stripUrl(StandardPaths.writableLocation(StandardPaths.DownloadLocation));
  }

  //! Start folder for a key: "projekt" (this project's folder), "szablony",
  //! "magazyn", "pobrane", "wymiana" (computer); anything else — the projects.
  function startFor(key) {
    const dataRoot = stripUrl(iface.dataRoot());
    if (key === "projekt" && projectDir !== "")
      return projectDir;
    if (key === "szablony" && FileUtils.folderExists(dataRoot + "/Szablony"))
      return dataRoot + "/Szablony";
    if (!onPhone) {
      if (key === "magazyn")
        return stripUrl(storeSettings.korzenProjektow);
      if (key === "pobrane" && FileUtils.folderExists(desktopDownloads()))
        return desktopDownloads();
      if (key === "wymiana" && FileUtils.folderExists(stripUrl(storeSettings.korzenProjektow) + "/wymiana"))
        return stripUrl(storeSettings.korzenProjektow) + "/wymiana";
    }
    return projectsHome();
  }

  //! Opens the window: "projekt", "projekty", "szablony", "magazyn", …
  function openPlace(key) {
    mode = "browse";
    hintPlace = "";
    buildPlaces();
    currentPath = startFor(key);
    selectedPath = "";
    message = "";
    open();
  }

  //! Opens the window on any folder.
  function openAt(path) {
    mode = "browse";
    hintPlace = "";
    buildPlaces();
    currentPath = String(path).replace(/\/+$/, "");
    selectedPath = "";
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
    // phone: Pobrane / Wymiana only through the system window — start where
    // the projects are and point at that place
    if (onPhone && (wanted === "pobrane" || wanted === "wymiana"))
      hintPlace = wanted;
    currentPath = startFor(wanted);
    message = "";
    messageIsError = false;
    if (hintPlace !== "")
      say(qsTr("Plik w Pobranych albo gdzie indziej w telefonie? Dotknij „Pamięć telefonu…” na dole — otworzy się okno systemowe."));
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
    currentPath = place.start !== undefined ? place.start : place.path;
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

  /**
   * Places (Piotr 25.10, 00:06): only the app folder on the internal storage,
   * the app folder on the SD card, the exchange space and Downloads.
   * Phone: exchange and Downloads hold other apps' files, which the app cannot
   * list (no all-files permission) — they open the system window (↗).
   * Computer: the app folder, "WorkField" (the working folder, formerly
 * "Magazyn"), exchange, Downloads.
   * `start` = where the window goes when the place is tapped.
   */
  function buildPlaces() {
    const list = [];
    const dataRoot = stripUrl(iface.dataRoot());
    if (onPhone) {
      let places0 = [];
      try {
        places0 = iface.miejscaProjektow();
      } catch (e) {
        places0 = [];
      }
      // [WF-FILE-BROWSER] 25.10.2026 (Piotr 09:58) — on a phone the places are
      // the app space only: internal storage and, separately, the SD card.
      // Everything else in the phone: „Pamięć telefonu…” at the bottom.
      for (let i = 0; i < places0.length; i++) {
        const card = places0[i].rodzaj === "karta";
        list.push({
                    "key": card ? "karta" : "telefon",
                    "name": card ? qsTr("Karta SD") : qsTr("Pamięć wewnętrzna"),
                    "path": stripUrl(places0[i].korzen),
                    "start": stripUrl(places0[i].katalog),
                    "kind": "folder"
                  });
      }
      if (places0.length === 0)
        list.push({ "key": "telefon", "name": qsTr("Pamięć wewnętrzna"), "path": dataRoot, "start": dataRoot + "/Imported Projects", "kind": "folder" });
    } else {
      const store = stripUrl(storeSettings.korzenProjektow);
      list.push({ "key": "aplikacja", "name": qsTr("Katalog aplikacji"), "path": dataRoot, "kind": "folder" });
      // Piotr 25.10: "Magazyn" is out of date; the place shows the WorkField folder itself
      list.push({ "key": "magazyn", "name": qsTr("WorkField"), "path": store, "kind": "folder" });
      list.push({ "key": "wymiana", "name": qsTr("Przestrzeń wymiany"), "path": store + "/wymiana", "kind": "folder" });
      list.push({ "key": "pobrane", "name": qsTr("Pobrane"), "path": desktopDownloads(), "kind": "folder" });
    }
    places = list.filter(p => p.system === true || FileUtils.folderExists(p.path));
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
    if (currentPath === "")
      return [];
    if (currentPlace === null) {
      // outside the places (a project kept elsewhere on a computer): the
      // last folders of the path, each one tappable
      const parts = currentPath.split("/").filter(s => s !== "");
      const all = [];
      let q = "";
      for (let i = 0; i < parts.length; i++) {
        q += "/" + parts[i];
        all.push({ "name": niceName(parts[i]), "path": q });
      }
      return all.slice(Math.max(0, all.length - 4));
    }
    const out = [{ "name": currentPlace.name, "path": currentPlace.path }];
    const rest = currentPath.substring(currentPlace.path.length).split("/").filter(s => s !== "");
    let p = currentPlace.path;
    for (let i = 0; i < rest.length; i++) {
      p += "/" + rest[i];
      out.push({ "name": niceName(rest[i]), "path": p });
    }
    return out;
  }

  //! Human names for the app's own folders (they are English on disk)
  function niceName(segment) {
    const names = {
      "Imported Projects": qsTr("Projekty"),
      "Imported Datasets": qsTr("Dane"),
      "Created Projects": qsTr("Projekty QField")
    };
    return names[segment] !== undefined ? names[segment] : segment;
  }

  //! [WF-FILE-BROWSER] 25.10 — "back did not work": the ← was off at the top
  //! of a place, and the system back closed the whole window. Now: up a folder
  //! (also outside the places), close only at the top.
  function canGoUp() {
    if (currentPath === "" || currentPath === "/")
      return false;
    if (currentPlace !== null)
      return currentPath !== currentPlace.path;
    return true;
  }

  function goUp() {
    if (!canGoUp())
      return;
    const up = currentPath.substring(0, currentPath.lastIndexOf("/"));
    currentPath = up === "" ? "/" : up;
    selectedPath = "";
    message = "";
  }

  function back() {
    if (canGoUp())
      goUp();
    else if (mode === "browse")
      close();
    else
      cancel();
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
    bodyRow.forceActiveFocus();
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
    id: bodyRow
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 10
    focus: true

    Keys.onPressed: event => {
      if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape)
        event.accepted = true;
    }
    Keys.onReleased: event => {
      if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
        event.accepted = true;
        browser.back();
      }
    }

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

        Text {
          visible: browser.onPhone
          height: 40
          verticalAlignment: Text.AlignVCenter
          text: qsTr("Przestrzeń aplikacji:")
          color: Theme.secondaryTextColor
          font: Theme.tipFont
        }

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
          enabled: browser.canGoUp()
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
                      // [WF-FILE-BROWSER] message first: a new path rebuilds the
                      // crumbs and destroys this delegate („browser is not defined”)
                      const target = modelData.path;
                      browser.message = "";
                      browser.currentPath = target;
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

      // phone: the whole phone storage through the system window (also when
      // browsing — a chosen file opens as from the list); Downloads, the
      // exchange space and other apps' files are there (Piotr 09:58)
      OutlineButton {
        visible: browser.onPhone || (browser.mode !== "browse" && browser.narrowScreen)
        Layout.fillWidth: true
        text: browser.onPhone ? qsTr("Pamięć telefonu… (okno systemowe Androida)") : qsTr("Inne miejsce…")
        onClicked: browser.openSystemPicker(browser.onPhone ? browser.phoneStorage : browser.currentPath)
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
    // [WF-FILE-BROWSER] krok 4 — cloud entries (decision 2: they do not disappear)
    property bool webdav: false
    property bool cloud: false

    function show(n, p, d) {
      name = n;
      path = String(p);
      isDir = d === true;
      const up = typeof qfieldLocalDataPickerScreen !== "undefined" ? qfieldLocalDataPickerScreen : null;
      webdav = up !== null && up.wfHasWebdav(path);
      cloud = up !== null && up.wfInCloudProject(path);
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
      text: qsTr("Wyślij na serwer WebDAV")
      visible: fileMenu.webdav
      height: visible ? implicitHeight : 0
      onTriggered: qfieldLocalDataPickerScreen.wfWebdavUpload(fileMenu.path)
    }

    MenuItem {
      text: qsTr("Pobierz z serwera WebDAV")
      visible: fileMenu.webdav && fileMenu.isDir
      height: visible ? implicitHeight : 0
      onTriggered: qfieldLocalDataPickerScreen.wfWebdavDownload(fileMenu.path)
    }

    MenuItem {
      text: qsTr("Wyślij do QFieldCloud")
      visible: fileMenu.cloud
      height: visible ? implicitHeight : 0
      onTriggered: qfieldLocalDataPickerScreen.wfPushToCloud(fileMenu.path)
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
      if (browser.mode === "browse") {
        // browsing a place the app cannot list (phone): act on the chosen file
        browser.activate(FileUtils.fileName(path), path, false);
        return;
      }
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
