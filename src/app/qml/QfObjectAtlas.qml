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

 [WF-ATLAS-SHAPE] 26.10.2026 (Piotr 13:26) — micro editing of the shape, the
 counterpart of the small changes of attributes: „Popraw kształt” over the
 maps; on the object map drag a vertex (or the point), pull the dot in the
 middle of a side to add a vertex, hold a vertex to delete it, tap one to
 choose it (then „Do mojej pozycji” puts it at the GPS position). Snapping
 to the corners of the neighbours. Nothing reaches the layer before „Zapisz”;
 before it the bar shows what changes (area / length, how far a vertex went)
 and a self-crossing shape is refused, not saved.
 ***************************************************************************/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
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

  // [WF-ATLAS-SHAPE] the shape being corrected
  property bool shapeEditing: false
  property string shapeKind: ""
  //! [{ part, ring, closed, vertices: [[x, y, ox, oy, z, m, moved], …] }] — map CRS
  property var shapeRings: []
  property var shapeHistory: []
  property var shapeTargets: []
  //! the chosen vertex: ring index, vertex index (-1 = none)
  property int shapeRing: -1
  property int shapeVertex: -1
  //! ObjectAtlas.checkGeometry() of the current shape
  property var shapeInfo: ({})
  //! where the dragged vertex snapped (map CRS) — drawn as a ring
  property var shapeSnapMark: null
  property string shapeNote: ""
  readonly property bool shapeDirty: shapeHistory.length > 0

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
  //! the last edit the atlas already jumped to ("" = none yet)
  property string lastEditKey: ""

  /**
   * [WF-OBJECT-ATLAS] 25.10.2026 (Piotr 11:18) — where the atlas starts:
   *   1. the layer asked for (Tabela → „W atlasie”, „Aktywna warstwa”),
   *   2. the object edited last (WF_JOURNAL) — once per edit, so browsing
   *      is not thrown back to it at every opening,
   *   3. the layer already shown, if it has objects,
   *   4. the first layer WITH objects (an empty layer only when all are).
   */
  function start(preferredLayer, fid) {
    layerList = qgisProject ? engine.layers(qgisProject) : [];
    const find = function (id) {
      for (let i = 0; i < layerList.length; i++)
        if (layerList[i].id === id)
          return i;
      return -1;
    };
    let at = -1;
    let startFid = fid;
    if (preferredLayer)
      at = find(preferredLayer.id);
    if (at < 0 && !preferredLayer) {
      const last = qgisProject ? engine.lastEdited(qgisProject) : ({});
      const key = last && last.layerId ? last.layerId + "#" + last.fid + "#" + last.time : "";
      if (key !== "" && key !== lastEditKey) {
        at = find(last.layerId);
        if (at >= 0) {
          lastEditKey = key;
          if (startFid === undefined || startFid === null)
            startFid = last.fid;
        }
      }
    }
    if (at < 0 && atlasLayer) {
      const i = find(atlasLayer.id);
      if (i >= 0 && layerList[i].count > 0)
        at = i;
    }
    if (at < 0) {
      for (let i = 0; i < layerList.length; i++) {
        if (layerList[i].count > 0) {
          at = i;
          break;
        }
      }
    }
    if (at < 0 && layerList.length > 0)
      at = 0;
    layerBox.currentIndex = at;
    setLayer(at >= 0 ? layerList[at].layer : null, startFid);
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

  // ── [WF-ATLAS-SHAPE] micro editing of the shape ─────────────────────────
  function toast(message, kind) {
    if (typeof displayToast === "function")
      displayToast(message, kind ? kind : "info");
  }

  function startShapeEdit() {
    if (!atlasLayer || !page || !page.ok)
      return;
    const g = engine.editableGeometry(qgisProject, atlasLayer, page.fid);
    if (!g.ok) {
      toast(g.message, "warning");
      return;
    }
    shapeKind = g.kind;
    // plain JS arrays: the vertices are moved in place while the hand drags
    shapeRings = JSON.parse(JSON.stringify(g.rings));
    shapeHistory = [];
    shapeRing = -1;
    shapeVertex = -1;
    shapeSnapMark = null;
    shapeNote = "";
    // a point: the one vertex is chosen at once (ready for „Do mojej pozycji”)
    if (shapeKind === "point" && shapeRings.length === 1) {
      shapeRing = 0;
      shapeVertex = 0;
    }
    const e = page.objectExtent;
    if (e && e.length === 4) {
      const cx = (e[0] + e[2]) / 2, cy = (e[1] + e[3]) / 2;
      const hw = (e[2] - e[0]) * 1.5, hh = (e[3] - e[1]) * 1.5;
      shapeTargets = engine.snapTargets(qgisProject, atlasLayer, page.fid, [cx - hw, cy - hh, cx + hw, cy + hh]);
    } else {
      shapeTargets = [];
    }
    shapeEditing = true;
    refreshShapeInfo();
    objectMap.repaint();
  }

  //! \a save: write the shape; otherwise drop it (\a why tells the hand why)
  function endShapeEdit(save, why) {
    if (!shapeEditing)
      return;
    if (save) {
      const r = engine.saveGeometry(qgisProject, atlasLayer, page.fid, shapeRings);
      toast(r.message, r.ok ? "info" : "error");
      if (!r.ok)
        return;
    } else if (shapeDirty) {
      toast(why ? why : qsTr("Zmiana kształtu porzucona — obiekt jest taki jak przed nią."), "warning");
    }
    shapeEditing = false;
    shapeRings = [];
    shapeHistory = [];
    shapeTargets = [];
    shapeRing = -1;
    shapeVertex = -1;
    shapeSnapMark = null;
    shapeInfo = ({});
    if (save) {
      const keepPhoto = selectedPhoto;
      page = engine.describe(qgisProject, atlasLayer, page.fid);
      selectedPhoto = keepPhoto;
      rerender();
    }
    objectMap.repaint();
    overviewMap.repaint();
  }

  function rememberShape() {
    shapeHistory = shapeHistory.concat([JSON.stringify(shapeRings)]);
  }

  function undoShape() {
    if (shapeHistory.length === 0)
      return;
    const last = shapeHistory[shapeHistory.length - 1];
    shapeHistory = shapeHistory.slice(0, shapeHistory.length - 1);
    shapeRings = JSON.parse(last);
    if (shapeRing >= shapeRings.length || (shapeRing >= 0 && shapeVertex >= shapeRings[shapeRing].vertices.length)) {
      shapeRing = -1;
      shapeVertex = -1;
    }
    shapeNote = "";
    refreshShapeInfo();
    objectMap.repaint();
  }

  function refreshShapeInfo() {
    shapeInfo = engine.checkGeometry(qgisProject, atlasLayer, page.fid, shapeRings);
  }

  //! the text of the bar: what the change makes
  function shapeSummary() {
    const i = shapeInfo || {};
    if (!shapeDirty)
      return shapeKind === "point" ? qsTr("Przeciągnij punkt albo stuknij „Do mojej pozycji”.")
                                   : qsTr("Przeciągnij wierzchołek. Kropka w połowie boku dodaje wierzchołek, przytrzymanie wierzchołka go usuwa, stuknięcie go wybiera.");
    let t = "";
    if (i.measureName)
      t = qsTr("%1: było %2, będzie %3").arg(i.measureName).arg(i.before).arg(i.after);
    if (i.shift > 0)
      t += (t !== "" ? "; " : "") + qsTr("najdalej przesunięty wierzchołek: %1").arg(i.shiftText);
    if (shapeNote !== "")
      t += (t !== "" ? "; " : "") + shapeNote;
    return t;
  }

  function moveVertex(r, i, x, y) {
    const v = shapeRings[r].vertices[i];
    v[0] = x;
    v[1] = y;
    while (v.length < 7)
      v.push(null);
    v[6] = true;
  }

  //! a new vertex after \a i in ring \a r (z and m: the mean of the neighbours)
  function insertVertex(r, i, x, y) {
    const vs = shapeRings[r].vertices;
    const a = vs[i], b = vs[(i + 1) % vs.length];
    vs.splice(i + 1, 0, [x, y, null, null, (a[4] + b[4]) / 2, (a[5] + b[5]) / 2, true]);
    return i + 1;
  }

  function deleteChosenVertex() {
    if (shapeRing < 0 || shapeVertex < 0)
      return;
    const ring = shapeRings[shapeRing];
    const least = shapeKind === "polygon" ? 3 : (shapeKind === "line" ? 2 : 1);
    if (shapeKind === "point" || ring.vertices.length <= least) {
      toast(shapeKind === "point" ? qsTr("Punktu nie usuwa się tutaj — tylko przesuwa.")
                                  : qsTr("Nie usunę: %1 musi mieć co najmniej %2 wierzchołki.").arg(shapeKind === "polygon" ? qsTr("wielokąt") : qsTr("linia")).arg(least), "warning");
      return;
    }
    rememberShape();
    ring.vertices.splice(shapeVertex, 1);
    shapeRings = shapeRings.slice();
    shapeVertex = -1;
    shapeRing = -1;
    shapeNote = "";
    refreshShapeInfo();
    objectMap.repaint();
  }

  //! the chosen vertex (or the point) to the GPS / RTK position
  function vertexToMyPosition() {
    if (shapeRing < 0 || shapeVertex < 0) {
      toast(qsTr("Najpierw stuknij wierzchołek, który ma trafić w Twoją pozycję."), "warning");
      return;
    }
    const source = typeof positionSource !== "undefined" ? positionSource : null;
    if (!source) {
      toast(qsTr("Nie ma źródła pozycji w tej aplikacji."), "error");
      return;
    }
    if (!source.active) {
      toast(qsTr("GPS jest wyłączony — włącz pozycjonowanie i spróbuj ponownie."), "warning");
      return;
    }
    const pi = source.positionInformation;
    const ok = pi && isFinite(pi.latitude) && isFinite(pi.longitude) && pi.latitudeValid !== false && pi.longitudeValid !== false && !(pi.latitude === 0 && pi.longitude === 0);
    if (!ok) {
      toast(qsTr("Nie ma jeszcze pozycji — poczekaj na sygnał."), "warning");
      return;
    }
    const xy = engine.fromWgs84(qgisProject, pi.longitude, pi.latitude);
    if (!xy || xy.length !== 2) {
      toast(qsTr("Nie umiem przeliczyć pozycji do układu mapy."), "error");
      return;
    }
    const hacc = pi.haccValid !== false && isFinite(pi.hacc) ? pi.hacc : NaN;
    const fix = pi.fixStatusDescription ? String(pi.fixStatusDescription) : "";
    rememberShape();
    moveVertex(shapeRing, shapeVertex, xy[0], xy[1]);
    shapeRings = shapeRings.slice();
    shapeNote = qsTr("wierzchołek w pozycji GPS: %1%2").arg(isFinite(hacc) ? qsTr("dokładność %1 m").arg(hacc.toLocaleString(Qt.locale(), "f", 2)) : qsTr("dokładność nieznana")).arg(fix !== "" ? ", " + fix : "");
    refreshShapeInfo();
    objectMap.viewCenter = xy;
    objectMap.changed();
    objectMap.repaint();
    if (!isFinite(hacc) || hacc > 1.0)
      toast(qsTr("Uwaga: dokładność pozycji %1 — sprawdź, zanim zapiszesz.").arg(isFinite(hacc) ? qsTr("%1 m").arg(hacc.toLocaleString(Qt.locale(), "f", 1)) : qsTr("nieznana")), "warning");
  }

  //! content coordinates of a pane (the picture before the live move) to the map
  function paneToMap(pane, cx, cy) {
    const e = pane.extent;
    return [e[0] + cx / pane.width * (e[2] - e[0]), e[3] - cy / pane.height * (e[3] - e[1])];
  }

  //! what is under the finger: { kind: "vertex" | "mid" | "", ring, index }
  function shapeHit(pane, cx, cy) {
    const touch = 24 / pane.liveScale;
    let best = { "kind": "", "ring": -1, "index": -1 }, bestD = touch;
    for (let r = 0; r < shapeRings.length; r++) {
      const vs = shapeRings[r].vertices;
      for (let i = 0; i < vs.length; i++) {
        const q = pane.px(vs[i][0], vs[i][1]);
        const d = Math.hypot(q[0] - cx, q[1] - cy);
        if (d < bestD) {
          bestD = d;
          best = { "kind": "vertex", "ring": r, "index": i };
        }
      }
    }
    if (best.kind !== "" || shapeKind === "point")
      return best;
    bestD = 18 / pane.liveScale;
    for (let r = 0; r < shapeRings.length; r++) {
      const vs = shapeRings[r].vertices;
      const n = shapeRings[r].closed ? vs.length : vs.length - 1;
      for (let i = 0; i < n; i++) {
        const a = pane.px(vs[i][0], vs[i][1]);
        const b = pane.px(vs[(i + 1) % vs.length][0], vs[(i + 1) % vs.length][1]);
        if (Math.hypot(b[0] - a[0], b[1] - a[1]) * pane.liveScale < 36)
          continue;
        const d = Math.hypot((a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cy);
        if (d < bestD) {
          bestD = d;
          best = { "kind": "mid", "ring": r, "index": i };
        }
      }
    }
    return best;
  }

  //! the nearest corner of a neighbour within reach, or null
  function snapTo(pane, x, y) {
    shapeSnapMark = null;
    if (!atlasSettings.shapeSnap || shapeTargets.length === 0)
      return null;
    const here = pane.px(x, y);
    const reach = 16 / pane.liveScale;
    let best = null, bestD = reach;
    for (let i = 0; i < shapeTargets.length; i++) {
      const q = pane.px(shapeTargets[i][0], shapeTargets[i][1]);
      const d = Math.hypot(q[0] - here[0], q[1] - here[1]);
      if (d < bestD) {
        bestD = d;
        best = shapeTargets[i];
      }
    }
    shapeSnapMark = best;
    return best;
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
    if (shapeEditing)
      endShapeEdit(false, qsTr("Zmiana kształtu porzucona — przeszedłeś do innego obiektu."));
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

    // the split or the height bar moved: the same view, drawn to the new size
    onWidthChanged: if (baseExtent && baseExtent.length === 4) settleTimer.restart()
    onHeightChanged: if (baseExtent && baseExtent.length === 4) settleTimer.restart()

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
    // [WF-ATLAS-SHAPE] while the shape is corrected: a press on a vertex /
    // a side's middle drags it, a tap chooses it, a hold deletes it;
    // anywhere else the view moves as always
    MouseArea {
      anchors.fill: parent
      enabled: pane.interactive
      preventStealing: true
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      property real lastX: 0
      property real lastY: 0
      property real startX: 0
      property real startY: 0
      property var hit: ({ "kind": "" })
      property bool dragging: false
      property bool held: false
      readonly property bool shaping: pane.slot === "object" && atlas.shapeEditing
      onPressed: function (mouse) {
        lastX = mouse.x;
        lastY = mouse.y;
        startX = mouse.x;
        startY = mouse.y;
        dragging = false;
        held = false;
        hit = { "kind": "" };
        if (shaping && pane.extent && pane.extent.length === 4) {
          const c = content.mapFromItem(pane, mouse.x, mouse.y);
          hit = atlas.shapeHit(pane, c.x, c.y);
        }
      }
      onPositionChanged: function (mouse) {
        if (shaping && hit.kind !== "") {
          if (!dragging) {
            if (Math.hypot(mouse.x - startX, mouse.y - startY) < 5)
              return;
            dragging = true;
            atlas.rememberShape();
            if (hit.kind === "mid") {
              const c0 = content.mapFromItem(pane, mouse.x, mouse.y);
              const m0 = atlas.paneToMap(pane, c0.x, c0.y);
              hit = { "kind": "vertex", "ring": hit.ring, "index": atlas.insertVertex(hit.ring, hit.index, m0[0], m0[1]) };
            }
            atlas.shapeRing = hit.ring;
            atlas.shapeVertex = hit.index;
          }
          const c = content.mapFromItem(pane, mouse.x, mouse.y);
          let m = atlas.paneToMap(pane, c.x, c.y);
          const s = atlas.snapTo(pane, m[0], m[1]);
          if (s)
            m = s;
          atlas.moveVertex(hit.ring, hit.index, m[0], m[1]);
          pane.repaint();
          return;
        }
        pane.moveBy(mouse.x - lastX, mouse.y - lastY);
        lastX = mouse.x;
        lastY = mouse.y;
      }
      onReleased: function (mouse) {
        if (!shaping)
          return;
        if (dragging) {
          atlas.shapeSnapMark = null;
          atlas.shapeNote = "";
          atlas.shapeRings = atlas.shapeRings.slice();
          atlas.refreshShapeInfo();
        } else if (!held && hit.kind === "vertex") {
          atlas.shapeRing = hit.ring;
          atlas.shapeVertex = hit.index;
        } else if (!held && hit.kind === "" && Math.hypot(mouse.x - startX, mouse.y - startY) < 5 && atlas.shapeKind !== "point") {
          atlas.shapeRing = -1;
          atlas.shapeVertex = -1;
        }
        dragging = false;
        pane.repaint();
      }
      onPressAndHold: function (mouse) {
        if (shaping && !dragging && hit.kind === "vertex") {
          held = true;
          atlas.shapeRing = hit.ring;
          atlas.shapeVertex = hit.index;
          atlas.deleteChosenVertex();
        }
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
      anchors.margins: pane.width < 320 ? 3 : 6
      width: pane.width < 320 ? 34 : 44
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
          width: pane.width < 320 ? 28 : 36
          height: pane.width < 320 ? 28 : 34
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
          width: pane.width < 320 ? 28 : 36
          height: pane.width < 320 ? 28 : 34
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
          width: pane.width < 320 ? 28 : 36
          height: pane.width < 320 ? 28 : 34
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

    width: atlas.wide ? 56 : 46
    height: 44
    Layout.preferredWidth: width
    Layout.preferredHeight: height
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

  // [WF-ATLAS-SHAPE] the shape being corrected: the old one thin and dashed,
  // the new one strong; handles on the vertices, dots in the middle of the
  // sides; the corners of the neighbours as small grey dots
  function paintShape(ctx, pane) {
    const k = 1 / pane.liveScale; // sizes stay the same while the view zooms by hand
    ctx.save();
    ctx.setLineDash([6 * k, 4 * k]);
    paintObject(ctx, pane, "rgba(55,71,79,0.8)", "rgba(0,0,0,0)", 1.5 * k);
    ctx.restore();
    if (atlasSettings.shapeSnap) {
      ctx.fillStyle = "rgba(69,90,100,0.75)";
      for (let i = 0; i < shapeTargets.length; i++) {
        const q = pane.px(shapeTargets[i][0], shapeTargets[i][1]);
        ctx.fillRect(q[0] - 2 * k, q[1] - 2 * k, 4 * k, 4 * k);
      }
    }
    if (shapeKind !== "point") {
      ctx.beginPath();
      for (let r = 0; r < shapeRings.length; r++)
        tracePart(ctx, pane, shapeRings[r].vertices, shapeRings[r].closed);
      ctx.lineWidth = 3 * k;
      ctx.strokeStyle = shapeInfo && shapeInfo.valid === false ? "#D50000" : "#FF6F00";
      if (shapeKind === "polygon") {
        ctx.fillStyle = shapeInfo && shapeInfo.valid === false ? "rgba(213,0,0,0.18)" : "rgba(255,111,0,0.16)";
        ctx.fillRule = Qt.OddEvenFill;
        ctx.fill();
      }
      ctx.stroke();
      // the middles of the sides: pull to add a vertex
      for (let r = 0; r < shapeRings.length; r++) {
        const vs = shapeRings[r].vertices;
        const n = shapeRings[r].closed ? vs.length : vs.length - 1;
        for (let i = 0; i < n; i++) {
          const a = pane.px(vs[i][0], vs[i][1]);
          const b = pane.px(vs[(i + 1) % vs.length][0], vs[(i + 1) % vs.length][1]);
          if (Math.hypot(b[0] - a[0], b[1] - a[1]) * pane.liveScale < 36)
            continue;
          ctx.beginPath();
          ctx.arc((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 5 * k, 0, 2 * Math.PI);
          ctx.fillStyle = "rgba(255,255,255,0.85)";
          ctx.fill();
          ctx.lineWidth = 1.5 * k;
          ctx.strokeStyle = "#FF6F00";
          ctx.stroke();
        }
      }
    }
    for (let r = 0; r < shapeRings.length; r++) {
      const vs = shapeRings[r].vertices;
      for (let i = 0; i < vs.length; i++) {
        const q = pane.px(vs[i][0], vs[i][1]);
        const chosen = r === shapeRing && i === shapeVertex;
        ctx.beginPath();
        ctx.arc(q[0], q[1], (chosen ? 11 : (shapeKind === "point" ? 10 : 8)) * k, 0, 2 * Math.PI);
        ctx.fillStyle = chosen ? "#FF6F00" : "white";
        ctx.fill();
        ctx.lineWidth = (chosen ? 3 : 2.5) * k;
        ctx.strokeStyle = chosen ? "white" : (vs[i][6] ? "#E65100" : "#37474F");
        ctx.stroke();
      }
    }
    if (shapeSnapMark) {
      const s = pane.px(shapeSnapMark[0], shapeSnapMark[1]);
      ctx.beginPath();
      ctx.arc(s[0], s[1], 15 * k, 0, 2 * Math.PI);
      ctx.lineWidth = 3 * k;
      ctx.strokeStyle = "#D500F9";
      ctx.stroke();
    }
  }

  function paintObjectMap(ctx, pane) {
    if (shapeEditing)
      paintShape(ctx, pane);
    else
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

  // [WF-OBJECT-ATLAS] 25.10.2026 (Piotr 13:23) — sizes the hand chose stay
  Settings {
    id: atlasSettings
    category: "WorkFieldAtlas"
    //! height of the maps row on a phone; 0 = automatic
    property real mapsHeight: 0
    property real photoHeight: 90
    //! wide screen: the share of the width taken by the maps
    property real mapsRatio: 0.6
    //! [WF-ATLAS-SHAPE] snapping to the corners of the neighbours
    property bool shapeSnap: true
  }

  readonly property real mapsHeight: Math.max(120, Math.min(atlas.height * 0.7, atlasSettings.mapsHeight > 0 ? atlasSettings.mapsHeight : Math.round(atlas.width * 0.6)))
  readonly property real photoHeight: Math.max(48, Math.min(320, atlasSettings.photoHeight))
  readonly property real mapsRatio: Math.max(0.25, Math.min(0.8, atlasSettings.mapsRatio))

  // [WF-ATLAS-SHAPE] a word button of the shape bar (on / off, enabled or not)
  component TextChip: Rectangle {
    id: textChip
    property string label: ""
    property bool active: false
    property bool strong: false
    signal clicked
    implicitWidth: chipLabel.implicitWidth + (atlas.wide ? 22 : 16)
    implicitHeight: atlas.wide ? 38 : 34
    radius: 8
    opacity: enabled ? 1 : 0.4
    color: strong ? (textChipMouse.pressed ? Qt.darker(Theme.mainColor, 1.25) : Theme.mainColor)
                  : (active ? "#FF8F00" : (textChipMouse.pressed ? Qt.alpha(Theme.mainColor, 0.3) : Qt.alpha(Theme.mainColor, 0.12)))
    border.width: 1
    border.color: active ? "#FFB74D" : Qt.alpha(Theme.mainColor, 0.45)
    Text {
      id: chipLabel
      anchors.centerIn: parent
      text: textChip.label
      color: textChip.strong || textChip.active ? "white" : Theme.mainTextColor
      font.pointSize: Theme.tipFont.pointSize
      font.bold: textChip.strong || textChip.active
    }
    MouseArea {
      id: textChipMouse
      anchors.fill: parent
      onClicked: textChip.clicked()
    }
  }

  //! a bar to drag: the height of what is above it, or (across: true, a
  //! vertical bar) the width of what is on its left
  component Grip: Rectangle {
    id: grip
    property bool across: false
    signal dragged(real d)
    Layout.fillWidth: !across
    Layout.fillHeight: across
    Layout.preferredHeight: across ? -1 : 16
    Layout.preferredWidth: across ? 16 : -1
    radius: 4
    color: gripMouse.pressed ? Qt.alpha("#FF8F00", 0.35) : Qt.alpha(Theme.mainColor, 0.08)

    Grid {
      anchors.centerIn: parent
      spacing: 3
      columns: grip.across ? 2 : 1
      Repeater {
        model: 2
        Rectangle {
          width: grip.across ? 3 : 46
          height: grip.across ? 46 : 3
          radius: 1.5
          color: gripMouse.pressed ? "#FF8F00" : "#90A4AE"
        }
      }
    }

    MouseArea {
      id: gripMouse
      anchors.fill: parent
      anchors.topMargin: grip.across ? 0 : -8
      anchors.bottomMargin: grip.across ? 0 : -8
      anchors.leftMargin: grip.across ? -6 : 0
      anchors.rightMargin: grip.across ? -6 : 0
      preventStealing: true
      cursorShape: grip.across ? Qt.SizeHorCursor : Qt.SizeVerCursor
      property real last: 0
      onPressed: function (mouse) {
        const p = mapToItem(null, mouse.x, mouse.y);
        last = grip.across ? p.x : p.y;
      }
      onPositionChanged: function (mouse) {
        const p = mapToItem(null, mouse.x, mouse.y);
        const now = grip.across ? p.x : p.y;
        grip.dragged(now - last);
        last = now;
      }
    }
  }

  // ── top: two rows — layer + object; counter, form, colours switch ────────
  ColumnLayout {
    anchors.fill: parent
    spacing: 4

    RowLayout {
      Layout.fillWidth: true
      spacing: 4

      ComboBox {
        id: layerBox
        Layout.preferredWidth: atlas.wide ? 260 : Math.round(atlas.width * 0.36)
        Layout.preferredHeight: 44
        // the number of objects next to the name: an empty layer shows at once
        model: atlas.layerList.map(l => l.name + "  (" + l.count + ")")
        onActivated: atlas.setLayer(atlas.layerList[currentIndex].layer)
      }

      BigArrow {
        direction: -1
        onClicked: atlas.step(-1)
      }

      ComboBox {
        id: objectBox
        Layout.fillWidth: true
        Layout.preferredHeight: 44
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

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
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

      // [WF-ATLAS-SHAPE] micro editing of the shape on the object map
      TextChip {
        visible: atlas.page && atlas.page.ok === true
        label: atlas.wide ? qsTr("Popraw kształt") : qsTr("Kształt")
        active: atlas.shapeEditing
        onClicked: {
          if (atlas.shapeEditing)
            atlas.endShapeEdit(false);
          else
            atlas.startShapeEdit();
        }
      }

      Item {
        Layout.fillWidth: true
      }

      // [WF-OBJECT-ATLAS] colours and labels only here, or for good
      Switch {
        id: keepSwitch
        visible: atlas.atlasLayer !== null
        checked: atlas.keep
        onToggled: atlas.setKeep(checked)
      }
      Text {
        visible: atlas.atlasLayer !== null
        Layout.maximumWidth: atlas.wide ? 300 : 120
        // [WF-ATLAS-SHAPE] narrow screen: the label wraps instead of pushing the row wider
        Layout.preferredWidth: atlas.wide ? 300 : 90
        text: atlas.keep ? qsTr("Kolory i etykiety na stałe") : qsTr("Kolory i etykiety tylko w atlasie")
        color: atlas.keep ? "#FFB74D" : Theme.secondaryTextColor
        font: Theme.tinyFont
        wrapMode: Text.WordWrap
      }
    }

    // [WF-ATLAS-SHAPE] the shape bar: what the change makes, and the tools
    Rectangle {
      Layout.fillWidth: true
      visible: atlas.shapeEditing
      implicitHeight: shapeColumn.implicitHeight + 10
      radius: 8
      color: Qt.alpha("#FF8F00", 0.10)
      border.width: 1
      border.color: atlas.shapeInfo && atlas.shapeInfo.valid === false ? "#D50000" : "#FFB74D"

      ColumnLayout {
        id: shapeColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 5
        spacing: 4

        Text {
          Layout.fillWidth: true
          text: atlas.shapeSummary()
          color: Theme.mainTextColor
          font: Theme.tipFont
          wrapMode: Text.WordWrap
        }
        Text {
          Layout.fillWidth: true
          visible: atlas.shapeInfo && atlas.shapeInfo.valid === false
          text: atlas.shapeInfo && atlas.shapeInfo.problem ? atlas.shapeInfo.problem + " " + qsTr("— tak nie zapiszę; cofnij albo popraw.") : ""
          color: "#D50000"
          font.pointSize: Theme.tipFont.pointSize
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Flow {
          Layout.fillWidth: true
          spacing: 6

          // the decisions first (a phone wraps the rest below)
          TextChip {
            label: qsTr("Zapisz kształt")
            strong: true
            enabled: atlas.shapeDirty && !(atlas.shapeInfo && atlas.shapeInfo.valid === false)
            onClicked: atlas.endShapeEdit(true)
          }
          TextChip {
            label: qsTr("Cofnij")
            enabled: atlas.shapeDirty
            onClicked: atlas.undoShape()
          }
          TextChip {
            label: qsTr("Anuluj")
            onClicked: atlas.endShapeEdit(false)
          }
          // on = orange
          TextChip {
            label: qsTr("Przyciąganie")
            active: atlasSettings.shapeSnap
            onClicked: {
              atlasSettings.shapeSnap = !atlasSettings.shapeSnap;
              objectMap.repaint();
            }
          }
          TextChip {
            label: qsTr("Do mojej pozycji")
            enabled: atlas.shapeVertex >= 0
            onClicked: atlas.vertexToMyPosition()
          }
          TextChip {
            visible: atlas.shapeKind !== "point"
            label: atlas.wide ? qsTr("Usuń wierzchołek") : qsTr("Usuń")
            enabled: atlas.shapeVertex >= 0
            onClicked: atlas.deleteChosenVertex()
          }
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

    // ── body ──────────────────────────────────────────────────────────────
    // phone: the two maps SIDE BY SIDE (the split moves), a bar to drag their
    // height, the photo strip (its height drags too), the attribute table
    // scrolling below. Wide screen: maps on the left one above the other,
    // photos and attributes on the right.
    GridLayout {
      id: body
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: atlas.page && atlas.page.ok === true
      columns: atlas.wide ? 3 : 1
      columnSpacing: 8
      rowSpacing: 2

      ColumnLayout {
        id: mapsColumn
        Layout.fillWidth: !atlas.wide
        Layout.preferredWidth: atlas.wide ? Math.round(atlas.width * atlas.mapsRatio) : -1
        Layout.fillHeight: atlas.wide
        Layout.preferredHeight: atlas.wide ? -1 : atlas.mapsHeight
        spacing: 4

        Text {
          Layout.fillWidth: true
          visible: atlas.wide
          text: atlas.page.title !== undefined ? atlas.page.title + "  ·  " + atlas.layerName : ""
          color: Theme.mainTextColor
          font: Theme.strongTipFont
          elide: Text.ElideRight
        }

        SplitView {
          id: mapsSplit
          Layout.fillWidth: true
          Layout.fillHeight: true
          orientation: atlas.wide ? Qt.Vertical : Qt.Horizontal

          handle: Rectangle {
            implicitWidth: 10
            implicitHeight: 10
            color: SplitHandle.pressed ? "#FF8F00" : (SplitHandle.hovered ? "#78909C" : "#455A64")
          }

          MapPane {
            id: objectMap
            slot: "object"
            caption: qsTr("Mapa obiektu")
            interactive: true
            objectName: "atlasObjectMap"
            SplitView.preferredWidth: mapsSplit.width * 0.58
            SplitView.preferredHeight: mapsSplit.height * 0.64
            SplitView.minimumWidth: 90
            SplitView.minimumHeight: 90
          }

          MapPane {
            id: overviewMap
            slot: "overview"
            caption: qsTr("Mapa poglądowa")
            SplitView.fillWidth: true
            SplitView.fillHeight: true
            SplitView.minimumWidth: 80
            SplitView.minimumHeight: 80
          }
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
      }

      // phone: drag to make the maps taller / lower
      Grip {
        visible: !atlas.wide
        onDragged: function (dy) {
          atlasSettings.mapsHeight = Math.max(120, Math.min(atlas.height * 0.7, atlas.mapsHeight + dy));
        }
      }

      // wide screen (Piotr 13:41): drag to narrow the maps or the photos and
      // attributes on the right — each on its own
      Grip {
        across: true
        visible: atlas.wide
        onDragged: function (dx) {
          atlasSettings.mapsRatio = Math.max(0.25, Math.min(0.8, atlas.mapsRatio + dx / Math.max(1, atlas.width)));
        }
      }

      ColumnLayout {
        id: infoColumn
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 2

        // photos with numbers; a tap lights the cone, a second tap opens the photo
        Text {
          Layout.fillWidth: true
          text: atlas.photos.length > 0 ? qsTr("Zdjęcia (%1) — stuknij: stożek widoku, drugi raz: zdjęcie").arg(atlas.photos.length) : qsTr("Bez zdjęć")
          color: Theme.secondaryTextColor
          font: Theme.tinyFont
          elide: Text.ElideRight
        }

        ListView {
          id: photoStrip
          Layout.fillWidth: true
          Layout.preferredHeight: atlas.photos.length > 0 ? atlas.photoHeight : 0
          visible: atlas.photos.length > 0
          orientation: ListView.Horizontal
          spacing: 6
          clip: true
          model: atlas.photos

          delegate: Item {
            required property var modelData
            required property int index
            height: photoStrip.height
            width: Math.round(height * 1.15)

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
              sourceSize.width: 360
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

        // drag to make the photos bigger / smaller
        Grip {
          visible: atlas.photos.length > 0
          onDragged: function (dy) {
            atlasSettings.photoHeight = Math.max(48, Math.min(320, atlas.photoHeight + dy));
          }
        }

        Text {
          Layout.fillWidth: true
          text: qsTr("Atrybuty — ołówek zmienia wartość; kolory i Aa porównują obiekt z innymi")
          color: Theme.secondaryTextColor
          font: Theme.tinyFont
          wrapMode: Text.WordWrap
        }

        ListView {
          id: attributeList
          Layout.fillWidth: true
          Layout.fillHeight: true
          interactive: true
          clip: true
          spacing: 0
          boundsBehavior: Flickable.StopAtBounds
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

    // nothing to show: the controls stay at the top, not in the middle
    Item {
      Layout.fillHeight: true
      visible: !body.visible
    }
  }
}
