/***************************************************************************
  QfObjectAtlas.qml - Atlas obiektów

 ---------------------
 WorkField 25.10.2026 [WF-OBJECT-ATLAS] — a tab of the gallery: one page per
 object, like a QGIS atlas (Piotr 10:07). For each object:
   - the object map (the object + 20%, its view cones),
   - the overview map (the whole layer, the object marked, the frame of
     the object map),
   - attributes as text (beside the maps on a wide screen, below on a
     phone); a tap opens the form of the object for editing,
   - photos with numbers; a tap lights the view cone of that photo.

 The maps come from ObjectAtlas (C++, the QGIS engine) WITHOUT overlays;
 the object and the cones are drawn here, on a Canvas, from coordinates in
 the map CRS — so a tapped photo lights its cone at once. The same drawing
 will carry the cone dragging (step 3); the PDF is step 2.
 ***************************************************************************/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core
import org.qfield.gui
import Theme

Item {
  id: atlas

  //! the atlasLayer shown and its objects
  property var atlasLayer: null
  property var layerList: []
  property var objectList: []
  property int index: -1
  //! ObjectAtlas.describe() of the current object
  property var page: ({})
  //! index in page.photos of the photo whose cone is lit; -1 = none
  property int selectedPhoto: -1

  // [WF-OBJECT-ATLAS] 25.10.2026 (Piotr 10:43) — working comparison: colour
  // the objects by a field, show a field as labels; "keep" makes it the
  // style of the layer on the main map (the previous style comes back)
  property string colorBy: ""
  property string labelBy: ""
  property bool keep: false
  property var legend: []
  //! the field being edited in place ("" = none)
  property string editingField: ""

  readonly property bool wide: width > 820
  readonly property var photos: page && page.photos ? page.photos : []
  readonly property string layerName: atlasLayer ? atlasLayer.name : ""

  //! the form of the object (the gallery closes and shows the feature list)
  signal editRequested(var atlasLayer, var fid)

  ObjectAtlas {
    id: engine

    onMapRendered: function (result) {
      if (result.slot === "object")
        objectMap.accept(result);
      else if (result.slot === "overview")
        overviewMap.accept(result);
    }
  }

  /**
   * Opens the atlas on \a preferredLayer (or keeps the current one, or the
   * first atlas atlasLayer) and on the object \a fid (or keeps the position).
   */
  function start(preferredLayer, fid) {
    layerList = qgisProject ? engine.layers(qgisProject) : [];
    let chosen = null;
    const wanted = preferredLayer ? preferredLayer : atlasLayer;
    for (let i = 0; i < layerList.length; i++) {
      if (wanted && layerList[i].id === wanted.id) {
        chosen = layerList[i].layer;
        layerBox.currentIndex = i;
      }
    }
    if (!chosen && layerList.length > 0) {
      chosen = layerList[0].layer;
      layerBox.currentIndex = 0;
    }
    setLayer(chosen, fid);
  }

  function setLayer(newLayer, fid) {
    const sameLayer = newLayer && atlasLayer && newLayer.id === atlasLayer.id;
    atlasLayer = newLayer;
    if (!sameLayer) {
      // a layer that keeps the atlas style shows it again; others start plain
      const kept = atlasLayer ? engine.keptStyle(qgisProject, atlasLayer) : ({});
      colorBy = kept && kept.colorBy ? kept.colorBy : "";
      labelBy = kept && kept.labelBy ? kept.labelBy : "";
      keep = !!(kept && (kept.colorBy || kept.labelBy));
      legend = [];
    }
    objectList = atlasLayer ? engine.objects(atlasLayer) : [];
    let i = sameLayer && index >= 0 && index < objectList.length ? index : 0;
    if (fid !== undefined && fid !== null) {
      for (let k = 0; k < objectList.length; k++) {
        if (Number(objectList[k].fid) === Number(fid)) {
          i = k;
          break;
        }
      }
    }
    index = objectList.length > 0 ? i : -1;
    show();
  }

  function mapStyle() {
    return {
      "colorBy": colorBy,
      "labelBy": labelBy
    };
  }

  //! the same views again (after a change of colours, labels or a value)
  function rerender() {
    objectMap.render();
    overviewMap.render();
  }

  function styleChanged() {
    if (keep && atlasLayer) {
      const r = engine.applyToLayer(qgisProject, atlasLayer, mapStyle());
      if (typeof displayToast === "function")
        displayToast(r.message);
    }
    rerender();
  }

  function toggleColor(field) {
    colorBy = colorBy === field ? "" : field;
    if (colorBy === "")
      legend = [];
    styleChanged();
  }

  function toggleLabels(field) {
    labelBy = labelBy === field ? "" : field;
    styleChanged();
  }

  function setKeep(on) {
    keep = on;
    if (!atlasLayer)
      return;
    const r = engine.applyToLayer(qgisProject, atlasLayer, on ? mapStyle() : ({}));
    if (typeof displayToast === "function")
      displayToast(r.message);
  }

  //! writes one value, then reads the object again and redraws
  function saveValue(field, value) {
    const r = engine.setValue(atlasLayer, page.fid, field, value);
    if (typeof displayToast === "function")
      displayToast(r.message, r.ok ? "info" : "error");
    if (!r.ok)
      return;
    editingField = "";
    const keepPhoto = selectedPhoto;
    page = engine.describe(qgisProject, atlasLayer, page.fid);
    selectedPhoto = keepPhoto;
    if (colorBy === field || labelBy === field)
      rerender();
  }

  function fieldName(field) {
    const list = page && page.attributes ? page.attributes : [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].field === field)
        return list[i].name;
    }
    return field;
  }

  function show() {
    selectedPhoto = -1;
    editingField = "";
    if (!atlasLayer || index < 0 || index >= objectList.length) {
      page = ({});
      objectMap.clear();
      overviewMap.clear();
      return;
    }
    objectBox.currentIndex = index;
    page = engine.describe(qgisProject, atlasLayer, objectList[index].fid);
    renderTimer.restart();
  }

  function step(delta) {
    if (objectList.length === 0)
      return;
    index = (index + delta + objectList.length) % objectList.length;
    show();
  }

  function renderMaps() {
    if (!page || !page.ok)
      return;
    objectMap.reset(page.objectExtent);
    overviewMap.reset(page.overviewExtent);
  }

  // one render after the size settles (the window opens, the screen turns)
  Timer {
    id: renderTimer
    interval: 120
    onTriggered: atlas.renderMaps()
  }

  onWidthChanged: renderTimer.restart()
  onHeightChanged: renderTimer.restart()

  // ── map pane: picture from the engine + overlay ─────────────────────────
  // [WF-OBJECT-ATLAS] 25.10.2026 (Piotr 10:37) — the object map is the place
  // to LOOK at objects: drag to move, slider / wheel / pinch to zoom, ⌖ back
  // to the object. While moving, the last picture moves and scales at once;
  // the engine renders the new view a moment after the hand stops.
  component MapPane: Rectangle {
    id: pane

    property string slot: "object"
    property string caption: ""
    property bool interactive: false
    property string source: ""
    //! extent of the picture shown (as rendered, fitted to the pane)
    property var extent: []
    property int request: -1
    property bool busy: false

    //! the base extent (the object + 20%) and the view: centre + zoom level
    //! (log2 of the magnification against the base)
    property var baseExtent: []
    property var viewCenter: [0, 0]
    property real viewLevel: 0
    //! the view the shown picture was rendered for
    property var renderedCenter: [0, 0]
    property real renderedLevel: 0
    property real pendingLevel: 0
    property var pendingCenter: [0, 0]

    readonly property real unitsPerPixel: extent && extent.length === 4 && width > 0 ? (extent[2] - extent[0]) / width : 1
    readonly property real liveScale: Math.pow(2, viewLevel - renderedLevel)

    function reset(wantedExtent) {
      if (!wantedExtent || wantedExtent.length !== 4)
        return;
      baseExtent = wantedExtent;
      viewCenter = [(wantedExtent[0] + wantedExtent[2]) / 2, (wantedExtent[1] + wantedExtent[3]) / 2];
      viewLevel = 0;
      render();
    }

    //! the extent of the current view (centre + level)
    function viewExtent() {
      if (!baseExtent || baseExtent.length !== 4)
        return [];
      const f = Math.pow(2, viewLevel);
      const hw = (baseExtent[2] - baseExtent[0]) / 2 / f;
      const hh = (baseExtent[3] - baseExtent[1]) / 2 / f;
      return [viewCenter[0] - hw, viewCenter[1] - hh, viewCenter[0] + hw, viewCenter[1] + hh];
    }

    function render() {
      const wanted = viewExtent();
      if (wanted.length !== 4 || width < 16 || height < 16)
        return;
      busy = true;
      pendingLevel = viewLevel;
      pendingCenter = viewCenter;
      request = engine.renderMap(qgisProject, atlas.atlasLayer, wanted, Math.round(width), Math.round(height), Screen.devicePixelRatio, slot, atlas.mapStyle());
    }

    function accept(result) {
      if (result.request !== request)
        return;
      busy = false;
      if (result.ok) {
        source = result.image;
        extent = result.extent;
        renderedLevel = pendingLevel;
        renderedCenter = [(result.extent[0] + result.extent[2]) / 2, (result.extent[1] + result.extent[3]) / 2];
      }
      repaint();
      if (slot === "object") {
        overviewMap.repaint();
        atlas.legend = result.legend ? result.legend : [];
      }
    }

    function clear() {
      source = "";
      extent = [];
      overlay.requestPaint();
    }

    function repaint() {
      overlay.requestPaint();
    }

    //! map coordinates → pixels of the picture (before the live move/zoom)
    function px(x, y) {
      return [(x - extent[0]) / (extent[2] - extent[0]) * width, (extent[3] - y) / (extent[3] - extent[1]) * height];
    }

    //! moved / zoomed by hand: show it at once, render after a pause
    function changed() {
      settleTimer.restart();
      if (slot === "object")
        overviewMap.repaint();
    }

    function moveBy(dx, dy) {
      const u = unitsPerPixel / liveScale;
      viewCenter = [viewCenter[0] - dx * u, viewCenter[1] + dy * u];
      changed();
    }

    function zoomTo(level) {
      viewLevel = Math.max(-3, Math.min(5, level));
      changed();
    }

    Timer {
      id: settleTimer
      interval: 350
      onTriggered: pane.render()
    }

    color: "#ECEFF1"
    border.width: 1
    border.color: Theme.controlBorderColor
    clip: true

    // picture + overlay move and scale together while the hand works
    Item {
      id: content
      width: pane.width
      height: pane.height
      transformOrigin: Item.Center
      scale: pane.liveScale
      x: pane.extent && pane.extent.length === 4 ? -(pane.viewCenter[0] - pane.renderedCenter[0]) / pane.unitsPerPixel * pane.liveScale : 0
      y: pane.extent && pane.extent.length === 4 ? (pane.viewCenter[1] - pane.renderedCenter[1]) / pane.unitsPerPixel * pane.liveScale : 0

      Image {
        anchors.fill: parent
        source: pane.source
        fillMode: Image.Stretch
        cache: false
        asynchronous: true
      }

      Canvas {
        id: overlay
        anchors.fill: parent

        onPaint: {
          const ctx = getContext("2d");
          ctx.reset();
          if (!pane.extent || pane.extent.length !== 4 || !atlas.page || !atlas.page.ok)
            return;
          if (pane.slot === "object")
            atlas.paintObjectMap(ctx, pane);
          else
            atlas.paintOverview(ctx, pane);
        }
      }
    }

    // the hand: drag moves the view; the wheel zooms (computer)
    MouseArea {
      anchors.fill: parent
      enabled: pane.interactive
      preventStealing: true
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      property real lastX: 0
      property real lastY: 0
      onPressed: function (mouse) {
        lastX = mouse.x;
        lastY = mouse.y;
      }
      onPositionChanged: function (mouse) {
        pane.moveBy(mouse.x - lastX, mouse.y - lastY);
        lastX = mouse.x;
        lastY = mouse.y;
      }
      onWheel: function (wheel) {
        pane.zoomTo(pane.viewLevel + wheel.angleDelta.y / 120 * 0.25);
      }
    }

    // two fingers zoom (phone)
    PinchHandler {
      enabled: pane.interactive
      target: null
      property real startLevel: 0
      onActiveChanged: {
        if (active)
          startLevel = pane.viewLevel;
      }
      onActiveScaleChanged: {
        if (active)
          pane.zoomTo(startLevel + Math.log(activeScale) / Math.LN2);
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.margins: 4
      width: captionText.implicitWidth + 10
      height: captionText.implicitHeight + 4
      radius: 3
      color: Qt.rgba(0, 0, 0, 0.55)

      Text {
        id: captionText
        anchors.centerIn: parent
        text: pane.caption
        color: "white"
        font: Theme.tinyFont
      }
    }

    // zoom: + / slider / − and ⌖ back to the object
    Rectangle {
      visible: pane.interactive
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: 6
      width: 44
      radius: 8
      color: Qt.rgba(1, 1, 1, 0.82)
      border.width: 1
      border.color: "#90A4AE"

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 2

        Rectangle {
          Layout.alignment: Qt.AlignHCenter
          width: 36
          height: 34
          radius: 6
          color: plusMouse.pressed ? "#CFD8DC" : "transparent"
          Text {
            anchors.centerIn: parent
            text: "+"
            color: "#263238"
            font.pointSize: Theme.defaultFont.pointSize + 6
            font.bold: true
          }
          MouseArea {
            id: plusMouse
            anchors.fill: parent
            onClicked: pane.zoomTo(pane.viewLevel + 0.5)
          }
        }

        Slider {
          id: zoomSlider
          Layout.fillHeight: true
          Layout.alignment: Qt.AlignHCenter
          orientation: Qt.Vertical
          from: -3
          to: 5
          stepSize: 0.05
          value: pane.viewLevel
          onMoved: pane.zoomTo(value)
        }

        Rectangle {
          Layout.alignment: Qt.AlignHCenter
          width: 36
          height: 34
          radius: 6
          color: minusMouse.pressed ? "#CFD8DC" : "transparent"
          Text {
            anchors.centerIn: parent
            text: "−"
            color: "#263238"
            font.pointSize: Theme.defaultFont.pointSize + 6
            font.bold: true
          }
          MouseArea {
            id: minusMouse
            anchors.fill: parent
            onClicked: pane.zoomTo(pane.viewLevel - 0.5)
          }
        }

        // back to the object: a target drawn, not a font glyph
        Rectangle {
          Layout.alignment: Qt.AlignHCenter
          width: 36
          height: 34
          radius: 6
          color: homeMouse.pressed ? "#CFD8DC" : "transparent"
          Canvas {
            anchors.centerIn: parent
            width: 24
            height: 24
            onPaint: {
              const c = getContext("2d");
              c.reset();
              c.strokeStyle = "#E65100";
              c.lineWidth = 2;
              c.beginPath();
              c.arc(12, 12, 7, 0, 2 * Math.PI);
              c.stroke();
              c.beginPath();
              c.moveTo(12, 1); c.lineTo(12, 7);
              c.moveTo(12, 17); c.lineTo(12, 23);
              c.moveTo(1, 12); c.lineTo(7, 12);
              c.moveTo(17, 12); c.lineTo(23, 12);
              c.stroke();
              c.fillStyle = "#E65100";
              c.beginPath();
              c.arc(12, 12, 2.5, 0, 2 * Math.PI);
              c.fill();
            }
          }
          MouseArea {
            id: homeMouse
            anchors.fill: parent
            onClicked: pane.reset(pane.baseExtent)
          }
        }
      }
    }

    BusyIndicator {
      anchors.centerIn: parent
      running: pane.busy
      visible: pane.busy
      width: 36
      height: 36
    }
  }

  // [WF-OBJECT-ATLAS] small icon buttons of an attribute row, drawn (no font glyphs)
  component IconChip: Rectangle {
    id: chip
    property string kind: "pencil"
    property bool active: false
    signal clicked

    Layout.preferredWidth: 34
    Layout.preferredHeight: 30
    radius: 6
    color: active ? "#FF8F00" : (chipMouse.pressed ? Qt.alpha(Theme.mainColor, 0.3) : Qt.alpha(Theme.mainColor, 0.12))
    border.width: 1
    border.color: active ? "#FFB74D" : Qt.alpha(Theme.mainColor, 0.4)

    Canvas {
      anchors.centerIn: parent
      width: 20
      height: 20
      visible: chip.kind !== "labels"
      onPaint: {
        const c = getContext("2d");
        c.reset();
        if (chip.kind === "color") {
          const colours = ["#d7191c", "#fdae61", "#abdda4", "#2b83ba"];
          for (let i = 0; i < 4; i++) {
            c.fillStyle = colours[i];
            c.fillRect((i % 2) * 10 + 1, Math.floor(i / 2) * 10 + 1, 8, 8);
          }
        } else {
          // pencil
          c.strokeStyle = chip.active ? "white" : Theme.mainTextColor;
          c.fillStyle = chip.active ? "white" : Theme.mainTextColor;
          c.lineWidth = 2;
          c.beginPath();
          c.moveTo(4, 16); c.lineTo(15, 5); c.lineTo(18, 8); c.lineTo(7, 19); c.closePath();
          c.stroke();
          c.beginPath();
          c.moveTo(2, 20); c.lineTo(4, 16); c.lineTo(7, 19); c.closePath();
          c.fill();
        }
      }
      Component.onCompleted: requestPaint()
    }
    Text {
      anchors.centerIn: parent
      visible: chip.kind === "labels"
      text: "Aa"
      color: chip.active ? "white" : Theme.mainTextColor
      font.pointSize: Theme.tipFont.pointSize
      font.bold: true
    }
    MouseArea {
      id: chipMouse
      anchors.fill: parent
      anchors.margins: -3
      onClicked: chip.clicked()
    }
    onActiveChanged: {
      for (let i = 0; i < children.length; i++)
        if (children[i].requestPaint)
          children[i].requestPaint();
    }
  }

  //! "×" that switches the colouring / labels off
  component OffChip: Rectangle {
    id: off
    signal clicked
    width: 26
    height: 24
    radius: 12
    color: offMouse.pressed ? "#FFCC80" : "#FFB74D"
    Text {
      anchors.centerIn: parent
      text: "×"
      color: "#3E2723"
      font.pointSize: Theme.tipFont.pointSize + 2
      font.bold: true
    }
    MouseArea {
      id: offMouse
      anchors.fill: parent
      anchors.margins: -4
      onClicked: off.clicked()
    }
  }

  // [WF-OBJECT-ATLAS] previous / next object: a big target, the arrow drawn
  component BigArrow: Rectangle {
    id: arrow
    property int direction: 1
    signal clicked

    width: 56
    height: 48
    radius: 8
    enabled: atlas.objectList.length > 1
    opacity: enabled ? 1 : 0.35
    color: arrowMouse.pressed ? Qt.darker(Theme.mainColor, 1.2) : Theme.mainColor

    Canvas {
      anchors.centerIn: parent
      width: 24
      height: 28
      onPaint: {
        const c = getContext("2d");
        c.reset();
        c.fillStyle = "white";
        c.beginPath();
        if (arrow.direction < 0) {
          c.moveTo(20, 2); c.lineTo(4, 14); c.lineTo(20, 26);
        } else {
          c.moveTo(4, 2); c.lineTo(20, 14); c.lineTo(4, 26);
        }
        c.closePath();
        c.fill();
      }
    }

    MouseArea {
      id: arrowMouse
      anchors.fill: parent
      onClicked: arrow.clicked()
    }
  }

  // ── drawing ──────────────────────────────────────────────────────────────
  function tracePart(ctx, pane, part, close) {
    if (!part || part.length === 0)
      return;
    const first = pane.px(part[0][0], part[0][1]);
    ctx.moveTo(first[0], first[1]);
    for (let i = 1; i < part.length; i++) {
      const p = pane.px(part[i][0], part[i][1]);
      ctx.lineTo(p[0], p[1]);
    }
    if (close)
      ctx.closePath();
  }

  function paintObject(ctx, pane, stroke, fill, lineWidth) {
    const parts = page.parts || [];
    const kind = page.geometryType;
    ctx.lineWidth = lineWidth;
    ctx.strokeStyle = stroke;
    ctx.fillStyle = fill;
    if (kind === "point") {
      for (let i = 0; i < parts.length; i++) {
        const p = pane.px(parts[i][0][0], parts[i][0][1]);
        ctx.beginPath();
        ctx.arc(p[0], p[1], 7, 0, 2 * Math.PI);
        ctx.fill();
        ctx.stroke();
      }
      return;
    }
    ctx.beginPath();
    for (let i = 0; i < parts.length; i++)
      tracePart(ctx, pane, parts[i], kind === "polygon");
    if (kind === "polygon")
      ctx.fill();
    ctx.stroke();
  }

  function paintObjectMap(ctx, pane) {
    paintObject(ctx, pane, "#FF6F00", "rgba(255,111,0,0.12)", 3);
    // view cones: all of them pale, the chosen one strong; number at the stand
    for (let i = 0; i < photos.length; i++) {
      const cone = photos[i].cone;
      // a circular sector from the stand (Piotr 10:20); the stored footprint only as a fallback
      const shape = cone ? (cone.sector && cone.sector.length > 2 ? cone.sector : cone.polygon) : null;
      if (!shape || shape.length < 3)
        continue;
      const chosen = i === selectedPhoto;
      ctx.beginPath();
      tracePart(ctx, pane, shape, true);
      ctx.fillStyle = chosen ? "rgba(255,193,7,0.45)" : "rgba(33,150,243,0.18)";
      ctx.strokeStyle = chosen ? "#FF8F00" : "rgba(25,118,210,0.85)";
      ctx.lineWidth = chosen ? 3 : 1.5;
      ctx.fill();
      ctx.stroke();
    }
    for (let i = 0; i < photos.length; i++) {
      const cone = photos[i].cone;
      if (!cone || !cone.stand)
        continue;
      const chosen = i === selectedPhoto;
      const s = pane.px(cone.stand[0], cone.stand[1]);
      ctx.beginPath();
      ctx.arc(s[0], s[1], chosen ? 12 : 10, 0, 2 * Math.PI);
      ctx.fillStyle = chosen ? "#FF8F00" : "#1976D2";
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = "white";
      ctx.stroke();
      ctx.fillStyle = "white";
      ctx.font = "bold " + (chosen ? 13 : 11) + "px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(photos[i].number), s[0], s[1]);
    }
  }

  function paintOverview(ctx, pane) {
    paintObject(ctx, pane, "#D50000", "rgba(213,0,0,0.35)", 2.5);
    // [WF-OBJECT-ATLAS] the frame of what the object map shows NOW (follows
    // the hand), clearly: white halo + orange, light fill; a small frame
    // also gets a target ring and lines to the edges of the overview
    let e = objectMap.viewExtent();
    if (!e || e.length !== 4)
      return;
    // fitted to the proportions of the object map, as the engine fits it
    if (objectMap.width > 0 && objectMap.height > 0) {
      const ex = (e[0] + e[2]) / 2, ey = (e[1] + e[3]) / 2;
      let ew = e[2] - e[0], eh = e[3] - e[1];
      const aspect = objectMap.width / objectMap.height;
      if (ew / eh < aspect)
        ew = eh * aspect;
      else
        eh = ew / aspect;
      e = [ex - ew / 2, ey - eh / 2, ex + ew / 2, ey + eh / 2];
    }
    const a = pane.px(e[0], e[3]);
    const b = pane.px(e[2], e[1]);
    const w = Math.max(6, b[0] - a[0]);
    const h = Math.max(6, b[1] - a[1]);
    const cx = a[0] + w / 2;
    const cy = a[1] + h / 2;
    ctx.fillStyle = "rgba(255,111,0,0.18)";
    ctx.fillRect(a[0], a[1], w, h);
    ctx.lineWidth = 6;
    ctx.strokeStyle = "rgba(255,255,255,0.9)";
    ctx.strokeRect(a[0], a[1], w, h);
    ctx.lineWidth = 3;
    ctx.strokeStyle = "#FF6F00";
    ctx.strokeRect(a[0], a[1], w, h);
    if (w < 40 || h < 40) {
      const r = Math.max(w, h) / 2 + 14;
      ctx.lineWidth = 3;
      ctx.strokeStyle = "#FF6F00";
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, 2 * Math.PI);
      ctx.stroke();
      ctx.lineWidth = 1.5;
      ctx.setLineDash([5, 4]);
      ctx.beginPath();
      ctx.moveTo(0, cy); ctx.lineTo(cx - r, cy);
      ctx.moveTo(cx + r, cy); ctx.lineTo(pane.width, cy);
      ctx.moveTo(cx, 0); ctx.lineTo(cx, cy - r);
      ctx.moveTo(cx, cy + r); ctx.lineTo(cx, pane.height);
      ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  onSelectedPhotoChanged: objectMap.repaint()
  onPageChanged: {
    objectMap.repaint();
    overviewMap.repaint();
  }

  // ── top: atlasLayer and object ────────────────────────────────────────────────
  ColumnLayout {
    anchors.fill: parent
    spacing: 6

    Flow {
      Layout.fillWidth: true
      spacing: 6

      ComboBox {
        id: layerBox
        width: atlas.wide ? 240 : Math.min(atlas.width, 240)
        model: atlas.layerList.map(l => l.name)
        onActivated: atlas.setLayer(atlas.layerList[currentIndex].layer)
      }

      Row {
        spacing: 4

        BigArrow {
          direction: -1
          onClicked: atlas.step(-1)
        }

        ComboBox {
          id: objectBox
          width: atlas.wide ? 280 : Math.max(120, atlas.width - 140)
          height: 48
          model: atlas.objectList.map(o => o.label)
          onActivated: {
            atlas.index = currentIndex;
            atlas.show();
          }
        }

        BigArrow {
          direction: 1
          onClicked: atlas.step(1)
        }
      }

      Text {
        height: 40
        verticalAlignment: Text.AlignVCenter
        text: atlas.objectList.length > 0 ? qsTr("%1 / %2").arg(atlas.index + 1).arg(atlas.objectList.length) : ""
        color: Theme.secondaryTextColor
        font: Theme.tipFont
      }

      QfDecisionButton {
        role: "confirm"
        visible: atlas.page && atlas.page.ok === true
        text: qsTr("Edytuj")
        onClicked: atlas.editRequested(atlas.atlasLayer, atlas.page.fid)
      }

      // [WF-OBJECT-ATLAS] colours and labels only here, or for good
      Row {
        height: 48
        spacing: 4
        visible: atlas.atlasLayer !== null

        Switch {
          id: keepSwitch
          anchors.verticalCenter: parent.verticalCenter
          checked: atlas.keep
          onToggled: atlas.setKeep(checked)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(260, atlas.width - 80)
          text: atlas.keep ? qsTr("Kolory i etykiety na stałe — także na mapie głównej") : qsTr("Kolory i etykiety tylko w atlasie")
          color: atlas.keep ? "#FFB74D" : Theme.secondaryTextColor
          font: Theme.tipFont
          wrapMode: Text.WordWrap
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: atlas.layerList.length === 0 || atlas.objectList.length === 0
      text: atlas.layerList.length === 0 ? qsTr("Projekt nie ma warstwy z obiektami, z której można zrobić atlas.")
                                         : qsTr("Warstwa „%1” nie ma obiektów.").arg(atlas.layerName)
      color: Theme.secondaryTextColor
      font: Theme.tipFont
      wrapMode: Text.WordWrap
    }

    // ── body: maps and the object's description ───────────────────────────
    Flickable {
      id: scroller
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: atlas.page && atlas.page.ok === true
      clip: true
      contentWidth: width
      contentHeight: atlas.wide ? height : body.implicitHeight
      interactive: !atlas.wide
      boundsBehavior: Flickable.StopAtBounds

      GridLayout {
        id: body
        width: scroller.width
        height: atlas.wide ? scroller.height : implicitHeight
        columns: atlas.wide ? 2 : 1
        columnSpacing: 8
        rowSpacing: 8

        ColumnLayout {
          id: mapsColumn
          Layout.preferredWidth: atlas.wide ? body.width * 0.6 : body.width
          Layout.alignment: Qt.AlignTop
          spacing: 6

          Text {
            Layout.fillWidth: true
            text: atlas.page.title !== undefined ? atlas.page.title + "  ·  " + atlas.layerName : ""
            color: Theme.mainTextColor
            font: Theme.strongTipFont
            elide: Text.ElideRight
          }

          MapPane {
            id: objectMap
            slot: "object"
            caption: qsTr("Mapa obiektu")
            interactive: true
            objectName: "atlasObjectMap"
            Layout.fillWidth: true
            Layout.preferredHeight: atlas.wide ? (scroller.height - 40) * 0.64 : width * 0.75
          }

          // what the colours mean; the active labels; × switches off
          Flow {
            Layout.fillWidth: true
            spacing: 6
            visible: atlas.colorBy !== "" || atlas.labelBy !== ""

            Text {
              visible: atlas.colorBy !== ""
              height: 24
              verticalAlignment: Text.AlignVCenter
              text: qsTr("Kolory: %1").arg(atlas.fieldName(atlas.colorBy))
              color: Theme.mainTextColor
              font: Theme.tipFont
            }
            Repeater {
              model: atlas.colorBy !== "" ? atlas.legend : []
              delegate: Row {
                required property var modelData
                height: 24
                spacing: 4
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 14
                  height: 14
                  radius: 2
                  color: modelData.color
                  border.width: 1
                  border.color: "#37474F"
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: Theme.secondaryTextColor
                  font: Theme.tinyFont
                }
              }
            }
            OffChip {
              visible: atlas.colorBy !== ""
              onClicked: atlas.toggleColor(atlas.colorBy)
            }
            Text {
              visible: atlas.labelBy !== ""
              height: 24
              verticalAlignment: Text.AlignVCenter
              text: qsTr("Etykiety: %1").arg(atlas.fieldName(atlas.labelBy))
              color: Theme.mainTextColor
              font: Theme.tipFont
            }
            OffChip {
              visible: atlas.labelBy !== ""
              onClicked: atlas.toggleLabels(atlas.labelBy)
            }
          }

          MapPane {
            id: overviewMap
            slot: "overview"
            caption: qsTr("Mapa poglądowa")
            Layout.fillWidth: true
            Layout.preferredHeight: atlas.wide ? (scroller.height - 40) * 0.36 : width * 0.55
          }
        }

        ColumnLayout {
          id: infoColumn
          Layout.fillWidth: true
          Layout.fillHeight: atlas.wide
          Layout.alignment: Qt.AlignTop
          spacing: 6

          // photos with numbers; a tap lights the cone, a second tap opens the photo
          Text {
            Layout.fillWidth: true
            text: atlas.photos.length > 0 ? qsTr("Zdjęcia (%1) — stuknij, aby pokazać stożek widoku").arg(atlas.photos.length) : qsTr("Bez zdjęć")
            color: Theme.secondaryTextColor
            font: Theme.tipFont
            wrapMode: Text.WordWrap
          }

          ListView {
            id: photoStrip
            Layout.fillWidth: true
            Layout.preferredHeight: atlas.photos.length > 0 ? 104 : 0
            visible: atlas.photos.length > 0
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            model: atlas.photos

            delegate: Item {
              required property var modelData
              required property int index
              width: 120
              height: 104

              Rectangle {
                anchors.fill: parent
                radius: 4
                color: "#263238"
                border.width: index === atlas.selectedPhoto ? 3 : 1
                border.color: index === atlas.selectedPhoto ? "#FF8F00" : Theme.controlBorderColor
              }

              Image {
                anchors.fill: parent
                anchors.margins: 3
                source: "file://" + modelData.absolutePath
                sourceSize.width: 240
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                clip: true
              }

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 5
                width: 24
                height: 24
                radius: 12
                color: index === atlas.selectedPhoto ? "#FF8F00" : "#1976D2"
                border.width: 2
                border.color: "white"

                Text {
                  anchors.centerIn: parent
                  text: String(modelData.number)
                  color: "white"
                  font.pointSize: Theme.tinyFont.pointSize
                  font.bold: true
                }
              }

              Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                visible: !modelData.cone
                text: qsTr("bez stożka")
                color: "white"
                font.pointSize: Theme.tinyFont.pointSize - 1
                style: Text.Outline
                styleColor: "black"
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  if (atlas.selectedPhoto === index)
                    platformUtilities.open(modelData.absolutePath);
                  else
                    atlas.selectedPhoto = index;
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: qsTr("Atrybuty — ołówek zmienia wartość; kolory i Aa porównują obiekt z innymi")
            color: Theme.secondaryTextColor
            font: Theme.tipFont
            wrapMode: Text.WordWrap
          }

          ListView {
            id: attributeList
            Layout.fillWidth: true
            Layout.fillHeight: atlas.wide
            Layout.preferredHeight: atlas.wide ? -1 : contentHeight
            interactive: atlas.wide
            clip: true
            spacing: 0
            model: (atlas.page.measures || []).map(m => ({ "name": m.name, "value": m.value, "measure": true })).concat(atlas.page.attributes || [])

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: attributeList.width
              id: attrRow
              readonly property bool editing: modelData.measure !== true && atlas.editingField === modelData.field
              height: row.implicitHeight + 8 + (editing ? editor.implicitHeight + 6 : 0)
              color: editing ? Qt.alpha("#FF8F00", 0.12) : (index % 2 === 1 ? Qt.alpha(Theme.mainColor, 0.06) : "transparent")

              MouseArea {
                anchors.fill: parent
                enabled: modelData.measure !== true && modelData.editable === true && !attrRow.editing
                onClicked: atlas.editingField = modelData.field
              }

              RowLayout {
                id: row
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.leftMargin: 6
                anchors.rightMargin: 4
                spacing: 6

                Text {
                  Layout.preferredWidth: Math.min(attributeList.width * 0.4, 180)
                  text: modelData.name
                  color: Theme.secondaryTextColor
                  font.pointSize: Theme.tipFont.pointSize
                  font.italic: modelData.measure === true
                  wrapMode: Text.WordWrap
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.value
                  color: Theme.mainTextColor
                  font: Theme.tipFont
                  wrapMode: Text.WordWrap
                }

                // colour the objects by this field
                IconChip {
                  visible: modelData.measure !== true
                  kind: "color"
                  active: atlas.colorBy === modelData.field
                  onClicked: atlas.toggleColor(modelData.field)
                }
                // this field as labels
                IconChip {
                  visible: modelData.measure !== true
                  kind: "labels"
                  active: atlas.labelBy === modelData.field
                  onClicked: atlas.toggleLabels(modelData.field)
                }
                // edit the value
                IconChip {
                  visible: modelData.measure !== true
                  enabled: modelData.editable === true
                  opacity: enabled ? 1 : 0.25
                  kind: "pencil"
                  active: attrRow.editing
                  onClicked: atlas.editingField = attrRow.editing ? "" : modelData.field
                }
              }

              // the editor of this value, under the row
              ColumnLayout {
                id: editor
                visible: attrRow.editing
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: row.bottom
                anchors.margins: 6
                spacing: 4

                ComboBox {
                  id: mapBox
                  visible: modelData.kind === "valuemap"
                  Layout.fillWidth: true
                  model: modelData.options ? modelData.options.map(o => o.label) : []
                  currentIndex: {
                    const o = modelData.options || [];
                    for (let i = 0; i < o.length; i++)
                      if (String(o[i].value) === String(modelData.raw))
                        return i;
                    return -1;
                  }
                }
                Switch {
                  id: boolSwitch
                  visible: modelData.kind === "bool"
                  checked: modelData.raw === "1"
                  text: checked ? qsTr("tak") : qsTr("nie")
                }
                TextField {
                  id: textField
                  visible: modelData.kind !== "valuemap" && modelData.kind !== "bool"
                  Layout.fillWidth: true
                  text: modelData.raw !== undefined ? modelData.raw : ""
                  placeholderText: modelData.kind === "date" ? qsTr("rrrr-mm-dd") : (modelData.kind === "datetime" ? qsTr("rrrr-mm-dd gg:mm") : "")
                  inputMethodHints: modelData.kind === "number" ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
                  onAccepted: saveButton.clicked()
                }
                RowLayout {
                  Layout.fillWidth: true
                  spacing: 6
                  Item {
                    Layout.fillWidth: true
                  }
                  QfDecisionButton {
                    role: "cancel"
                    text: qsTr("Anuluj")
                    onClicked: atlas.editingField = ""
                  }
                  QfDecisionButton {
                    id: saveButton
                    role: "confirm"
                    text: qsTr("Zapisz")
                    onClicked: {
                      let value;
                      if (modelData.kind === "valuemap")
                        value = mapBox.currentIndex >= 0 ? modelData.options[mapBox.currentIndex].value : "";
                      else if (modelData.kind === "bool")
                        value = boolSwitch.checked;
                      else
                        value = textField.text.trim().replace(modelData.kind === "number" ? "," : "\u0000", ".");
                      atlas.saveValue(modelData.field, value);
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
