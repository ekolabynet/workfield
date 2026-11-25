#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[WF-CRS-DETECT] 24.11.2026 — okno „układ warstwy się nie zgadza” (QML).

Silnik (NarzedziaProjektu.detectLayerCrs / checkProjectCrs / assignLayerCrs /
convertLayerToProjectDb) jest już w C++. Ta łatka dokłada w oknie głównym:
  - kolejkę zgłoszeń i okno z wyborem: „W locie” / „Konwertuj do bazy” / „Pomiń”,
  - sprawdzenie po dodaniu pliku (sygnał layerWasAdded) i po rysunku DXF
    (z przybliżeniem widoku do głównej części rysunku, bez śmieci przy 0,0),
  - sprawdzenie przy otwarciu projektu.
Oraz w prawej szufladzie (Narzędzia) pozycję „Układy warstw — sprawdź”.

Domyślnie próba. Zapis: --zapisz. Test na kopii: --plik-okna X --plik-szuflady Y.
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_crs_z_wartosci_qml.py
"""
import hashlib
import shutil
import sys
import time

REPO = "/DATA/SOFT/GIS/QFIELD_Pro/QField"
PLIK_OKNA = REPO + "/src/app/qml/QgisMobileapp.qml"
PLIK_SZUFLADY = REPO + "/src/app/qml/QfDataDrawer.qml"

OKNO_MD5_PRZED = "9de7ef3cac863d789033f90f2119cfd0"
OKNO_MD5_PO = "9846623324b94e91e83fba9b661bb78f"
SZUFLADA_MD5_PRZED = "1b68bcc086650b71e6a400d0943fc12e"
SZUFLADA_MD5_PO = "35fa4b9675464d76f53548890f13003a"

# ── okno główne ───────────────────────────────────────────────────────────────

FUNKCJE = r'''
  // [WF-CRS-DETECT] 24.11.2026 — układ warstwy rozpoznany po WARTOŚCIACH
  // współrzędnych (NarzedziaProjektu.detectLayerCrs). Piotr 23:40: kolizję
  // o rzędy wielkości pokazujemy do zatwierdzenia — transformacja w locie
  // (warstwa dostaje układ, plik bez zmian) albo konwersja (kopia w układzie
  // projektu do dane.gpkg, przedtem migawka bazy). Obiekty przy 0,0
  // i współrzędne lokalne — sam komunikat. Trzy wejścia: dodanie pliku,
  // otwarcie projektu, Narzędzia → „Układy warstw — sprawdź”.
  property var crsQueue: []
  property var crsHandled: ({})
  property var crsAddedPending: []
  property bool crsBusy: false
  property bool crsProjectLoading: false

  function crsReset() {
    crsQueue = [];
    crsHandled = ({});
    crsAddedPending = [];
  }

  // QgsRectangle nie ma w QML odczytu współrzędnych — nie da się go łączyć
  // w JS. Przy kilku warstwach rysunku bierzemy tę z największą liczbą
  // obiektów w układzie (zwykle linie). Wywnioskowane, nie zmierzone.
  function crsZoomTo(extent) {
    if (!extent)
      return;
    Qt.callLater(function () {
      mapCanvas.mapSettings.extent = extent;
      console.log("WorkField [WF-CRS-DETECT]: widok przybliżony do głównej części warstwy");
    });
  }

  function crsTake(entries, trigger, zoom) {
    let notes = [];
    let zoomEntry = null;
    for (const e of entries) {
      if (!e || !e.layerId)
        continue;
      crsHandled[e.layerId] = true;
      if (e.kind === "ok" || e.kind === "skip") {
        if (zoom && e.extent && (!zoomEntry || e.inside > zoomEntry.inside))
          zoomEntry = e;
        continue;
      }
      console.log("WorkField [WF-CRS-DETECT]: " + trigger + " — " + e.kind + " — " + e.opis);
      if (e.kind === "collision" || e.kind === "swapped") {
        if (mainWindow.crsQueue.some(q => q.layerId === e.layerId))
          continue;
        e.trigger = trigger;
        e.zoom = zoom;
        mainWindow.crsQueue.push(e);
      } else if (e.kind === "outliers") {
        notes.push(e.opis);
        if (zoom && e.extent && (!zoomEntry || e.inside > zoomEntry.inside))
          zoomEntry = e;
      } else if (e.kind === "local") {
        notes.push(e.opis);
      } else if (e.kind === "unknown" && trigger === "narzedzia") {
        // Przy otwarciu i dodaniu — tylko log: dane spoza Polski są
        // poprawne, a komunikat przy każdym otwarciu byłby szumem.
        notes.push(e.opis);
      }
    }
    if (zoomEntry)
      crsZoomTo(zoomEntry.extent);
    if (notes.length > 0)
      displayToast(notes.join("\n"), "warning");
    Qt.callLater(mainWindow.crsShowNext);
  }

  function crsCheckLayers(layerIds, trigger, zoom) {
    let entries = [];
    for (const id of layerIds) {
      try {
        entries.push(NarzedziaProjektu.detectLayerCrs(qgisProject, id));
      } catch (e) {
        console.log("WorkField [WF-CRS-DETECT]: " + trigger + " — błąd sprawdzania: " + e);
      }
    }
    crsTake(entries, trigger, zoom);
  }

  function crsCheckProject(trigger) {
    let res = { "checked": 0, "ms": 0, "entries": [] };
    try {
      res = NarzedziaProjektu.checkProjectCrs(qgisProject);
    } catch (e) {
      console.log("WorkField [WF-CRS-DETECT]: " + trigger + " — błąd sprawdzania: " + e);
    }
    const all = res.entries || [];
    // Przy otwarciu — bez warstw, o które już pytaliśmy w tej sesji projektu.
    // Z Narzędzi — wszystko, także pominięte.
    const entries = trigger === "narzedzia" ? all : all.filter(e => !crsHandled[e.layerId]);
    console.log("WorkField [WF-CRS-DETECT]: " + trigger + " — sprawdzone " + res.checked + ", do zgłoszenia " + entries.length + ", " + res.ms + " ms");
    if (trigger === "narzedzia" && entries.length === 0)
      displayToast(qsTr("Układy warstw zgodne z wartościami współrzędnych (sprawdzone: %1)").arg(res.checked));
    crsTake(entries, trigger, false);
    return res;
  }

  function crsShowNext() {
    if (crsQueue.length === 0)
      return;
    // Okno jeszcze się zamyka (animacja) albo czeka okno uzupełniania
    // projektu — dwa okna naraz zasłaniają się. Ponawiamy za chwilę.
    if (crsDialog.visible || autoEquipDialog.visible) {
      crsRetryTimer.restart();
      return;
    }
    crsDialog.entry = crsQueue.shift();
    crsDialog.open();
  }

  function crsApply(entry, action) {
    if (!entry)
      return;
    const wasDirty = ProjectUtils.isProjectDirty(qgisProject);
    let r = { "ok": false, "opis": "" };
    crsBusy = true;
    try {
      if (action === "assign") {
        r = NarzedziaProjektu.assignLayerCrs(qgisProject, entry.layerId, entry.detected);
      } else {
        // Konwersja usuwa starą warstwę i wstawia nową — lista warstw
        // zamrożona i zbudowana od nowa (lekcja z [WF-OSM-MOVE]).
        const tree = dashBoard.layerTree;
        const ownFreeze = tree && !tree.isFrozen;
        if (ownFreeze)
          tree.freeze();
        try {
          r = NarzedziaProjektu.convertLayerToProjectDb(qgisProject, entry.layerId, entry.detected, entry.swapped === true);
        } finally {
          if (ownFreeze)
            tree.unfreeze(true);
        }
      }
    } catch (e) {
      r = { "ok": false, "opis": String(e) };
    }
    crsBusy = false;
    if (r.layerId)
      crsHandled[r.layerId] = true;
    console.log("WorkField [WF-CRS-FIX]: " + action + " „" + entry.name + "” — " + (r.ok ? "ok" : "BŁĄD") + ": " + r.opis);
    if (r.ok) {
      if (entry.zoom && entry.extent)
        crsZoomTo(entry.extent);
      if (!wasDirty) {
        const saved = ProjectUtils.saveProject(qgisProject);
        console.log("WorkField [WF-CRS-FIX]: projekt zapisany: " + saved);
      }
    }
    if (r.opis)
      displayToast(r.opis, r.ok ? "info" : "warning");
    Qt.callLater(mainWindow.crsShowNext);
  }
'''

ANKIETA_KONIEC = "      dashBoard.odswiezWyposazenie();\n  }\n"

LOAD_START_STARE = ("    function onLoadProjectTriggered(path, name) {\n"
                    "      qfieldAuthRequestHandler.isProjectLoading = true;\n")
LOAD_START_NOWE = LOAD_START_STARE + (
    "      // [WF-CRS-DETECT] warstwy wczytywane z projektu nie idą przez\n"
    "      // „dodanie pliku” — sprawdza je osobno koniec wczytywania.\n"
    "      mainWindow.crsReset();\n"
    "      mainWindow.crsProjectLoading = true;\n")

LOAD_END_STARE = ("    function onLoadProjectEnded(path, name) {\n"
                  "      mainWindow.refreshProjectTitle();\n")
LOAD_END_NOWE = LOAD_END_STARE + "      mainWindow.crsProjectLoading = false; // [WF-CRS-DETECT]\n"

LOAD_CHECK_STARE = ("              mainWindow.autoEquipCheck();\n"
                    "          } catch (e) {\n"
                    "            console.log(\"WorkField [WF-AUTO-EQUIP]: failed: \" + e);\n"
                    "          }\n")
LOAD_CHECK_NOWE = LOAD_CHECK_STARE + (
    "          // [WF-CRS-DETECT] 24.11.2026 — układy warstw po wartościach. Projekt\n"
    "          // z DXF sprawdza rysunek sam (dodajRysunekCAD), z przybliżeniem.\n"
    "          try {\n"
    "            if (!cadComing)\n"
    "              mainWindow.crsCheckProject(\"load\");\n"
    "          } catch (e) {\n"
    "            console.log(\"WorkField [WF-CRS-DETECT]: load failed: \" + e);\n"
    "          }\n")

CAD_LISTA_STARE = "    let warstwyCAD = [];\n"
CAD_LISTA_NOWE = CAD_LISTA_STARE + "    let cadLayerIds = []; // [WF-CRS-DETECT]\n"

CAD_LICZ_STARE = "      podkladow++;\n"
CAD_LICZ_NOWE = CAD_LICZ_STARE + "      cadLayerIds.push(c.warstwa.id);\n"

CAD_KONIEC_STARE = ("      mainWindow.ensureOsmBasemap(\"cad\", false);\n"
                    "\n"
                    "    return podkladow;\n")
CAD_KONIEC_NOWE = ("      mainWindow.ensureOsmBasemap(\"cad\", false);\n"
                   "\n"
                   "    // [WF-CRS-DETECT] 24.11.2026 — układ rysunku po wartościach i widok na\n"
                   "    // główną część rysunku (Adamowizna: śmieci przy 0,0 rozciągały zasięg\n"
                   "    // aż po Abu Zabi). Kolizja — okno z wyborem.\n"
                   "    if (cadLayerIds.length > 0)\n"
                   "      mainWindow.crsCheckLayers(cadLayerIds, \"cad\", true);\n"
                   "\n"
                   "    return podkladow;\n")

OKNO_DIALOG_PO = 'Automat wyłączysz w Ustawieniach → Teren.")\n      }\n    }\n  }\n'

DIALOG = r'''
  // [WF-CRS-DETECT] 24.11.2026 — jedno zgłoszenie naraz; następne po decyzji.
  QfDialog {
    id: crsDialog
    property var entry: null
    parent: mainWindow.contentItem
    anchors.centerIn: parent
    width: Math.min(560, mainWindow.width - 32)
    modal: true
    closePolicy: Popup.NoAutoClose
    title: entry && entry.kind === "swapped" ? qsTr("Zamienione osie współrzędnych") : qsTr("Układ warstwy się nie zgadza")
    standardButtons: Dialog.Cancel

    function projectAuthid() {
      return qgisProject && qgisProject.crs ? qgisProject.crs.authid : "";
    }

    onAboutToShow: {
      const cancel = standardButton(Dialog.Cancel);
      if (cancel)
        cancel.text = qsTr("Pomiń");
    }
    onRejected: {
      if (entry)
        console.log("WorkField [WF-CRS-FIX]: pominięte „" + entry.name + "” (" + entry.kind + ")");
      entry = null;
      Qt.callLater(mainWindow.crsShowNext);
    }

    Column {
      width: parent.width
      spacing: 10

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        color: Theme.mainTextColor
        font: Theme.tipFont
        text: crsDialog.entry ? crsDialog.entry.opis : ""
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        color: Theme.secondaryTextColor
        font: Theme.tinyFont
        text: qsTr("W locie: warstwa dostaje układ wykryty z liczb, plik się nie zmienia — szybkie i odwracalne. Konwertuj: obiekty przeliczone do układu projektu trafiają do nowej tabeli w dane.gpkg (przedtem migawka bazy), a warstwa w projekcie zostaje podmieniona w tym samym miejscu listy.")
      }

      QfButton {
        width: parent.width
        visible: crsDialog.entry !== null && crsDialog.entry.kind === "collision"
        text: crsDialog.entry ? qsTr("W locie (ustaw %1)").arg(crsDialog.entry.detected) : ""
        onClicked: {
          const e = crsDialog.entry;
          crsDialog.entry = null;
          crsDialog.close();
          mainWindow.crsApply(e, "assign");
        }
      }

      QfButton {
        width: parent.width
        visible: crsDialog.entry !== null && crsDialog.entry.canConvert === true
        text: qsTr("Konwertuj do bazy projektu (%1)").arg(crsDialog.projectAuthid())
        onClicked: {
          const e = crsDialog.entry;
          crsDialog.entry = null;
          crsDialog.close();
          mainWindow.crsApply(e, "convert");
        }
      }
    }
  }

  Timer {
    id: crsRetryTimer
    interval: 1500
    repeat: false
    onTriggered: mainWindow.crsShowNext()
  }

  // [WF-CRS-DETECT] dodanie pliku: warstwa po warstwie, zebrane w jedną
  // paczkę (plik z kilkoma warstwami = jedno sprawdzenie). Pomijamy wczytywanie
  // projektu, własne konwersje i dokładanie przy zamrożonej liście (podkład OSM).
  Timer {
    id: crsAddedTimer
    interval: 400
    repeat: false
    onTriggered: {
      const ids = mainWindow.crsAddedPending.filter(id => !mainWindow.crsHandled[id]);
      mainWindow.crsAddedPending = [];
      if (ids.length > 0)
        mainWindow.crsCheckLayers(ids, "plik", false);
    }
  }

  Connections {
    target: qgisProject

    function onLayerWasAdded(layer) {
      if (!layer || mainWindow.crsBusy || mainWindow.crsProjectLoading)
        return;
      if (dashBoard.layerTree && dashBoard.layerTree.isFrozen)
        return;
      mainWindow.crsAddedPending.push(layer.id);
      crsAddedTimer.restart();
    }
  }
'''

# Kolejność ma znaczenie tylko dla czytelności — każda kotwica jest jednorazowa.
ZMIANY_OKNA = [
    (ANKIETA_KONIEC, ANKIETA_KONIEC + FUNKCJE),
    (LOAD_START_STARE, LOAD_START_NOWE),
    (LOAD_END_STARE, LOAD_END_NOWE),
    (LOAD_CHECK_STARE, LOAD_CHECK_NOWE),
    (CAD_LISTA_STARE, CAD_LISTA_NOWE),
    (CAD_LICZ_STARE, CAD_LICZ_NOWE),
    (CAD_KONIEC_STARE, CAD_KONIEC_NOWE),
    (OKNO_DIALOG_PO, OKNO_DIALOG_PO + DIALOG),
]

# ── prawa szuflada ────────────────────────────────────────────────────────────

SZ_CASE_STARE = '    case "klawisze":\n'
SZ_CASE_NOWE = ('    case "ukladyWarstw": // [WF-CRS-DETECT] 24.11.2026\n'
                '      dataDrawer.close();\n'
                '      mainWindow.crsCheckProject("narzedzia");\n'
                '      return;\n') + SZ_CASE_STARE

SZ_LISTA_STARE = ('    { "label": qsTr("Wyposażenie projektu"), "action": "wyposazenie", '
                  '"ikona": "wfg_wlasciwosci", "polka": "zaawansowana" },\n')
SZ_LISTA_NOWE = SZ_LISTA_STARE + (
    '    { "label": qsTr("Układy warstw \\u2014 sprawdź"), "action": "ukladyWarstw", '
    '"ikona": "wfg_lupa" }, // [WF-CRS-DETECT] 24.11.2026\n')

ZMIANY_SZUFLADY = [
    (SZ_CASE_STARE, SZ_CASE_NOWE),
    (SZ_LISTA_STARE, SZ_LISTA_NOWE),
]


def md5(dane):
    return hashlib.md5(dane).hexdigest()


def przygotuj(sciezka, przed, po, zmiany, nazwa):
    """Zwraca (stan, nowe_bajty). stan: 'gotowe', 'juz', 'stop'."""
    try:
        bajty = open(sciezka, "rb").read()
    except OSError as e:
        print("STOP: nie mogę odczytać " + sciezka + ": " + str(e))
        return "stop", None
    m = md5(bajty)
    if m == po:
        print(nazwa + ": JUŻ ZAINSTALOWANE (" + m + ")")
        return "juz", None
    if m != przed:
        print("STOP: " + nazwa + " ma md5 " + m + ", oczekiwane " + przed + ". Nie nadpisuję cudzej pracy.")
        return "stop", None
    tekst = bajty.decode("utf-8")
    for stare, _ in zmiany:
        n = tekst.count(stare)
        if n != 1:
            print("STOP: " + nazwa + ": kotwica występuje " + str(n) + " razy: " + repr(stare[:70]))
            return "stop", None
    for stare, nowe in zmiany:
        tekst = tekst.replace(stare, nowe, 1)
    nowe_bajty = tekst.encode("utf-8")
    linii = tekst.count("\n")
    print(nazwa + ": md5 po zmianie " + md5(nowe_bajty) + ", linii " + str(linii) + " (oczekiwane " + po + ")")
    return "gotowe", nowe_bajty


def main():
    arg = sys.argv[1:]
    zapisz = "--zapisz" in arg
    okno = PLIK_OKNA
    szuflada = PLIK_SZUFLADY
    if "--plik-okna" in arg:
        okno = arg[arg.index("--plik-okna") + 1]
    if "--plik-szuflady" in arg:
        szuflada = arg[arg.index("--plik-szuflady") + 1]

    s1, b1 = przygotuj(okno, OKNO_MD5_PRZED, OKNO_MD5_PO, ZMIANY_OKNA, "QgisMobileapp.qml")
    s2, b2 = przygotuj(szuflada, SZUFLADA_MD5_PRZED, SZUFLADA_MD5_PO, ZMIANY_SZUFLADY, "QfDataDrawer.qml")
    if "stop" in (s1, s2):
        return 1
    if s1 == "juz" and s2 == "juz":
        return 0
    if b1 is not None and md5(b1) != OKNO_MD5_PO:
        print("STOP: wynik okna różni się od oczekiwanego — nie zapisuję.")
        return 1
    if b2 is not None and md5(b2) != SZUFLADA_MD5_PO:
        print("STOP: wynik szuflady różni się od oczekiwanego — nie zapisuję.")
        return 1
    if not zapisz:
        print("PRÓBA — nic nie zapisano. Zapis: --zapisz")
        return 0
    znacznik = time.strftime("%Y%m%d_%H%M%S")
    for sciezka, bajty in ((okno, b1), (szuflada, b2)):
        if bajty is None:
            continue
        kopia = sciezka + ".przed_" + znacznik
        shutil.copy2(sciezka, kopia)
        with open(sciezka, "wb") as f:
            f.write(bajty)
        print("ZAPISANO " + sciezka + " (kopia: " + kopia + ")")
    return 0


if __name__ == "__main__":
    sys.exit(main())
