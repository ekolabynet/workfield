#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""W11 debug: tymczasowe logi przejsc stanu i przeplywu geometrii."""
import sys, os
PLIK = "src/app/qml/QfQuickCaptureBar.qml"
E = []
def edycja(s, n): E.append((s, n))

edycja("""    function onStateChanged() {
      quickCaptureBar.materializujOdroczone();
    }
""",
"""    function onStateChanged() {
      console.log("W11 stan:", stateMachine.state, "| activeLayer:", typeof dashBoard !== 'undefined' && dashBoard.activeLayer ? dashBoard.activeLayer.name : "null", "| geomFlow:", quickCaptureBar.geomFlow, "| pendingGeom:", quickCaptureBar.pendingGeomLayer ? quickCaptureBar.pendingGeomLayer.name : "null");
      quickCaptureBar.materializujOdroczone();
    }
""")

edycja("""          if (modelData.mode === "photogeom") {
            if (stateMachine.state === "digitize") {
              stateMachine.state = "browse";
            }
""",
"""          if (modelData.mode === "photogeom") {
            console.log("W11 tap P-photogeom:", modelData.letter, "state przed=", stateMachine.state, "geomFlow=", quickCaptureBar.geomFlow);
            if (stateMachine.state === "digitize") {
              stateMachine.state = "browse";
            }
""")

edycja("""            quickCaptureBar.captureInto(modelData.layer, modelData.bezZdjecia === true);
""",
"""            console.log("W11 tap capture:", modelData.letter, "bezZdjecia=", modelData.bezZdjecia === true, "state przed=", stateMachine.state);
            quickCaptureBar.captureInto(modelData.layer, modelData.bezZdjecia === true);
""")

edycja("""    if (geomFlow) {
""",
"""    if (geomFlow) {
      console.log("W11 foto->geomFlow:", photoPath, "state=", stateMachine.state);
""")

edycja("""  function finishGeometryCapture(digFeature) {
""",
"""  function finishGeometryCapture(digFeature) {
    console.log("W11 finishGeometryCapture, state=", stateMachine.state);
""")

edycja("""  function abortGeometryCapture() {
""",
"""  function abortGeometryCapture() {
    console.log("W11 abortGeometryCapture, state=", stateMachine.state, "geomFlow=", geomFlow);
""")

if not os.path.exists(PLIK):
    print("BRAK PLIKU:", PLIK); sys.exit(1)
s = open(PLIK, encoding="utf-8").read()
bledy = [st[:90] for st, _ in E if s.count(st) != 1]
if bledy:
    print("NIC NIE ZMIENIONO:\n" + "\n\n".join(bledy)); sys.exit(1)
for st, nw in E:
    s = s.replace(st, nw)
open(PLIK, "w", encoding="utf-8").write(s)
print("OK - %d logow W11." % len(E))
