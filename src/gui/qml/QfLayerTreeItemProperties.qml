import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import org.qgis
import org.qfield.core
import org.qfield.gui
import Theme

/**
 * \ingroup qml
 */
QfPopup {
  id: popup

  property var layerTree
  property var index

  property bool zoomToButtonVisible: false
  property bool showFeaturesListButtonVisible: false
  property bool showVisibleFeaturesListDropdownVisible: false
  property bool reloadDataButtonVisible: false

  property bool trackingButtonVisible: false
  property var trackingButtonText

  property bool opacitySliderVisible: false
  property bool symbologyVisible: false
  property int symbolKind: -1
  property int currentStrokeStyle: -1
  property int currentMarkerShape: -1
  property bool categoriesVisible: false
  property var categoryEntries: []
  property real strokeWidthValue: 0
  property var styleTargetLayer: null
  property var styleTargetMapLayer: null

  function openStrokePicker(current, width, style, colorCallback, widthCallback, styleCallback) {
    colorPicker.title = qsTr("Kontur");
    colorPicker.showStrokeOptions = true;
    colorPicker.strokeWidth = width;
    colorPicker.strokeStyle = style;

    colorPicker.colorPicked.connect(function ch(chosen) {
      colorPicker.colorPicked.disconnect(ch);
      colorCallback(chosen);
    });
    colorPicker.strokeWidthPicked.connect(function wh(w) {
      widthCallback(w);
    });
    colorPicker.strokeStylePicked.connect(function sh(st) {
      styleCallback(st);
    });
    colorPicker.closed.connect(function cl() {
      colorPicker.closed.disconnect(cl);
      colorPicker.showStrokeOptions = false;
      colorPicker.strokeWidthPicked.disconnect(widthCallback);
      colorPicker.strokeStylePicked.disconnect(styleCallback);
    });

    colorPicker.openFor(current);
  }

  function openColorPicker(title, current, callback) {
    colorPicker.title = title;
    colorPicker.showStrokeOptions = false;
    colorPicker.colorPicked.connect(function handler(chosen) {
      colorPicker.colorPicked.disconnect(handler);
      callback(chosen);
    });
    colorPicker.openFor(current);
  }
  property var availableFields: []
  property bool labelsOn: false
  property string labelField: ""
  property real labelSize: 10
  property color labelColor: "black"
  property bool labelBufferOn: true
  property color labelBufferColor: "white"
  property string pendingField: ""
  property int pendingClassCount: 5
  /**
   * WorkField 07.10.2026 [WF-PANEL-UKLAD] — panel w trzech grupach (Warstwa / Styl /
   * Etykiety), pokazywanych jako ZAKŁADKI albo ROZWIJANE SEKCJE — do wyboru, z pamięcią.
   * Wcześniej: jedna kolumna z kilkunastoma sekcjami i długie przewijanie.
   */
  Settings {
    id: ukladUstawienia
    category: "WorkFieldPanelWarstwy"
    property string uklad: "zakladki"
    property int zakladka: 1
    property bool otwartaWarstwa: false
    property bool otwartyStyl: true
    property bool otwarteEtykiety: false
    //! [WF-SZYBKIE-STYLE] własne style {"0": [...], "1": [...], "2": [...]} i ukryte gotowe ["2:Woda", ...]
    property string wlasneStyle: "{}"
    property string ukryteStyle: "[]"
  }

  readonly property bool jestWektor: index !== undefined && layerTree.data(index, QfFlatLayerTreeModel.VectorLayerPointer) ? true : false
  readonly property bool ukladZakladki: ukladUstawienia.uklad === "zakladki"

  //! Co pokazuje przełącznik „Sposób”: single | categorized | graduated | other (styl spoza panelu)
  property string trybWidoku: "single"
  //! Pola, które da się wybrać w bieżącym trybie (przedziały: tylko liczbowe).
  readonly property var polaTrybu: trybWidoku === "graduated" ? availableFields.filter(f => f.numeric) : availableFields

  /**
   * WorkField 07.10.2026 [WF-SZYBKIE-STYLE] — gotowe style do jednego dotknięcia,
   * jak „Ulubione” w QGIS. Klucz = symbolKind (0 punkt, 1 linia, 2 poligon).
   * wyp — wypełnienie (dla linii: kolor linii), kon — kontur, gr — grubość [mm],
   * st — styl linii (1 ciągła, 2 kreski, 3 kropki, 4 kreska-kropka),
   * ks — kształt punktu, r — rozmiar punktu [mm]. Kolor #AARRGGBB = z przezroczystością.
   */
  readonly property var szybkieStyle: ({
      "2": [
        { "n": qsTr("Czerwony obrys"), "wyp": "#00000000", "kon": "#e53935", "gr": 0.8, "st": 1 },
        { "n": qsTr("Żółty obrys (orto)"), "wyp": "#00000000", "kon": "#ffeb3b", "gr": 1.2, "st": 1 },
        { "n": qsTr("Biały obrys (orto)"), "wyp": "#00000000", "kon": "#ffffff", "gr": 1.0, "st": 1 },
        { "n": qsTr("Zieleń"), "wyp": "#8043a047", "kon": "#1b5e20", "gr": 0.4, "st": 1 },
        { "n": qsTr("Woda"), "wyp": "#a064b5f6", "kon": "#1565c0", "gr": 0.4, "st": 1 },
        { "n": qsTr("Zabudowa"), "wyp": "#c0bdbdbd", "kon": "#424242", "gr": 0.3, "st": 1 },
        { "n": qsTr("Pole uprawne"), "wyp": "#a0fff176", "kon": "#9e9d24", "gr": 0.3, "st": 1 },
        { "n": qsTr("Obszar chroniony"), "wyp": "#00000000", "kon": "#8e24aa", "gr": 0.8, "st": 2 },
        { "n": qsTr("Do sprawdzenia"), "wyp": "#60ff9800", "kon": "#e65100", "gr": 0.6, "st": 2 },
        { "n": qsTr("Niebieski obrys"), "wyp": "#00000000", "kon": "#1e88e5", "gr": 0.8, "st": 1 },
        { "n": qsTr("Turkusowy obrys (orto)"), "wyp": "#00000000", "kon": "#00e5ff", "gr": 1.0, "st": 1 },
        { "n": qsTr("Czerwony półprzezr."), "wyp": "#66e53935", "kon": "#b71c1c", "gr": 0.5, "st": 1 },
        { "n": qsTr("Las"), "wyp": "#a02e7d32", "kon": "#1b5e20", "gr": 0.4, "st": 1 },
        { "n": qsTr("Mokradło"), "wyp": "#8026a69a", "kon": "#00695c", "gr": 0.4, "st": 2 },
        { "n": qsTr("Łąka"), "wyp": "#90c5e1a5", "kon": "#689f38", "gr": 0.3, "st": 1 },
        { "n": qsTr("Gleba odsłonięta"), "wyp": "#a0a1887f", "kon": "#5d4037", "gr": 0.3, "st": 1 },
        { "n": qsTr("Wykluczenie"), "wyp": "#40000000", "kon": "#212121", "gr": 0.6, "st": 2 },
        { "n": qsTr("Szary bez obrysu"), "wyp": "#a09e9e9e", "kon": "#009e9e9e", "gr": 0.1, "st": 1 }
      ],
      "1": [
        { "n": qsTr("Czerwona"), "wyp": "#e53935", "gr": 0.8, "st": 1 },
        { "n": qsTr("Żółta gruba (orto)"), "wyp": "#ffeb3b", "gr": 1.4, "st": 1 },
        { "n": qsTr("Rzeka"), "wyp": "#1e88e5", "gr": 0.8, "st": 1 },
        { "n": qsTr("Droga"), "wyp": "#6d4c41", "gr": 1.0, "st": 1 },
        { "n": qsTr("Kreskowana"), "wyp": "#212121", "gr": 0.5, "st": 2 },
        { "n": qsTr("Kropkowana"), "wyp": "#212121", "gr": 0.6, "st": 3 },
        { "n": qsTr("Granica"), "wyp": "#8e24aa", "gr": 0.7, "st": 4 },
        { "n": qsTr("Biała gruba (orto)"), "wyp": "#ffffff", "gr": 1.4, "st": 1 },
        { "n": qsTr("Pomarańczowa"), "wyp": "#fb8c00", "gr": 0.9, "st": 1 },
        { "n": qsTr("Czerwona kreskowana"), "wyp": "#e53935", "gr": 0.8, "st": 2 },
        { "n": qsTr("Rów"), "wyp": "#1e88e5", "gr": 0.6, "st": 2 },
        { "n": qsTr("Żywopłot"), "wyp": "#2e7d32", "gr": 1.0, "st": 3 },
        { "n": qsTr("Ścieżka"), "wyp": "#8d6e63", "gr": 0.5, "st": 2 },
        { "n": qsTr("Cienka czarna"), "wyp": "#212121", "gr": 0.26, "st": 1 }
      ],
      "0": [
        { "n": qsTr("Czerwone koło"), "wyp": "#e53935", "kon": "#ffffff", "gr": 0.4, "ks": 6, "r": 3 },
        { "n": qsTr("Duże koło"), "wyp": "#ff9800", "kon": "#000000", "gr": 0.4, "ks": 6, "r": 5 },
        { "n": qsTr("Żółty trójkąt"), "wyp": "#fdd835", "kon": "#000000", "gr": 0.4, "ks": 3, "r": 4 },
        { "n": qsTr("Niebieski kwadrat"), "wyp": "#1e88e5", "kon": "#ffffff", "gr": 0.4, "ks": 0, "r": 3 },
        { "n": qsTr("Gwiazda"), "wyp": "#43a047", "kon": "#ffffff", "gr": 0.4, "ks": 12, "r": 5 },
        { "n": qsTr("Krzyż"), "wyp": "#212121", "kon": "#212121", "gr": 0.5, "ks": 8, "r": 4 },
        { "n": qsTr("Biały kwadrat (orto)"), "wyp": "#ffffff", "kon": "#000000", "gr": 0.4, "ks": 0, "r": 3 },
        { "n": qsTr("Czerwony krzyż"), "wyp": "#e53935", "kon": "#e53935", "gr": 0.6, "ks": 8, "r": 5 },
        { "n": qsTr("Fioletowa gwiazda"), "wyp": "#8e24aa", "kon": "#ffffff", "gr": 0.4, "ks": 12, "r": 5 },
        { "n": qsTr("Mały punkt"), "wyp": "#212121", "kon": "#ffffff", "gr": 0.3, "ks": 6, "r": 1.6 },
        { "n": qsTr("Niebieskie koło"), "wyp": "#1e88e5", "kon": "#ffffff", "gr": 0.4, "ks": 6, "r": 3.5 },
        { "n": qsTr("Pomarańczowy trójkąt"), "wyp": "#fb8c00", "kon": "#000000", "gr": 0.4, "ks": 3, "r": 4.5 },
        { "n": qsTr("Drzewo (zielone koło)"), "wyp": "#802e7d32", "kon": "#1b5e20", "gr": 0.6, "ks": 6, "r": 6 }
      ]
    })

  //! Sekcja panelu: w układzie zakładek pokazuje sam środek, w układzie sekcji — nagłówek
  //! ze stanem i środek po rozwinięciu. Jeden kod, dwa wyglądy.
  component Sekcja: ColumnLayout {
    id: sekcja

    property string tytul: ""
    property string stan: ""
    property int nr: 0
    property bool otwarta: false
    property bool zakladki: true
    property int aktywna: 0
    property bool dostepna: true
    property bool jedyna: false
    signal przelacz

    default property alias tresc: wnetrze.data

    Layout.fillWidth: true
    spacing: 4
    visible: dostepna && (!zakladki || aktywna === nr || jedyna)

    Rectangle {
      Layout.fillWidth: true
      Layout.topMargin: 2
      visible: !sekcja.zakladki
      implicitHeight: 46
      radius: 6
      color: Theme.controlBackgroundAlternateColor

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8

        Text {
          text: (sekcja.otwarta ? "▼  " : "▶  ") + sekcja.tytul
          font: Theme.strongFont
          color: Theme.mainTextColor
        }

        Text {
          Layout.fillWidth: true
          text: sekcja.stan
          font: Theme.tipFont
          color: Theme.secondaryTextColor
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideRight
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: sekcja.przelacz()
      }
    }

    ColumnLayout {
      id: wnetrze
      Layout.fillWidth: true
      Layout.leftMargin: sekcja.zakladki ? 0 : 4
      spacing: 4
      visible: sekcja.zakladki || sekcja.otwarta
    }
  }

  //! Oko rysowane — ikony ic_eye_* nie ma w motywie (pusty przycisk na zrzucie 07.10).
  component OkoIkona: Canvas {
    id: oko
    property color kolor: "white"
    property bool przekreslone: false
    width: 24
    height: 24
    onKolorChanged: requestPaint()
    onPrzekresloneChanged: requestPaint()
    onPaint: {
      const c = getContext("2d");
      c.reset();
      c.strokeStyle = oko.kolor;
      c.fillStyle = oko.kolor;
      c.lineWidth = 2;
      c.beginPath();
      c.moveTo(2, 12);
      c.quadraticCurveTo(12, 2, 22, 12);
      c.quadraticCurveTo(12, 22, 2, 12);
      c.closePath();
      c.stroke();
      c.beginPath();
      c.arc(12, 12, 3.5, 0, 2 * Math.PI);
      c.fill();
      if (oko.przekreslone) {
        c.lineWidth = 2.5;
        c.beginPath();
        c.moveTo(4, 21);
        c.lineTo(20, 3);
        c.stroke();
      }
    }
  }

  function opisStylu() {
    if (trybWidoku === "single")
      return qsTr("pojedynczy");
    if (trybWidoku === "categorized")
      return categoriesVisible ? qsTr("kategorie (%1)").arg(categoryEntries.length) : qsTr("kategorie — wybierz pole");
    if (trybWidoku === "graduated")
      return pendingField !== "" ? qsTr("przedziały: %1").arg(pendingField) : qsTr("przedziały — wybierz pole");
    return qsTr("inny (z QGIS)");
  }

  //! Klik w „Pojedynczy / Kategorie / Przedziały”. Pojedynczy działa od razu,
  //! dwa pozostałe — od razu, jeśli pole już wybrane; inaczej czekają na pole.
  function wybierzTryb(tryb) {
    if (tryb === "single") {
      rendererModeRow.applyMode("single");
      return;
    }
    trybWidoku = tryb;
    if (pendingField !== "" && polaTrybu.findIndex(f => f.name === pendingField) < 0)
      pendingField = "";
    fieldCombo.currentIndex = pendingField !== "" ? polaTrybu.findIndex(f => f.name === pendingField) : -1;
    if (pendingField !== "")
      rendererModeRow.applyMode(tryb);
  }

  //! Lista kafelków dla bieżącego rodzaju warstwy: gotowe (bez ukrytych) + własne.
  property var stylyBiezace: []
  property int rodzajStylu: 2
  property bool edycjaStylow: false
  property bool dodawanieStylu: false

  function czytajJson(t, domyslne) {
    try {
      const v = JSON.parse(t);
      return v === null ? domyslne : v;
    } catch (e) {
      return domyslne;
    }
  }

  function odswiezListeStylow() {
    // Rodzaj z GEOMETRII warstwy (0 punkt, 1 linia, 2 poligon). symbolType odpowiada
    // tylko przy stylu pojedynczym — przy kategoriach kafelki znikały (zrzut 07.10).
    let g = -1;
    if (styleTargetLayer) {
      try { g = styleTargetLayer.geometryType(); } catch (e) { g = -1; }
      if (g < 0 || g > 2)
        g = LayerUtils.symbolType(styleTargetLayer);
    }
    rodzajStylu = (g >= 0 && g <= 2) ? g : -1;
    const k = String(rodzajStylu);
    const ukryte = czytajJson(ukladUstawienia.ukryteStyle, []);
    const wlasne = czytajJson(ukladUstawienia.wlasneStyle, {});
    const lista = [];
    (szybkieStyle[k] || []).forEach(function (s) {
      if (ukryte.indexOf(k + ":" + s.n) < 0)
        lista.push(Object.assign({ "wlasny": false }, s));
    });
    (wlasne[k] || []).forEach(function (s) {
      lista.push(Object.assign({ "wlasny": true }, s));
    });
    stylyBiezace = lista;
  }

  //! Kolor -> "#AARRGGBB" (z przezroczystością, żeby półprzezroczyste wypełnienie przeżyło zapis).
  function hexA(c) {
    function d(v) {
      const h = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
      return h.length < 2 ? "0" + h : h;
    }
    return "#" + d(c.a) + d(c.r) + d(c.g) + d(c.b);
  }

  //! „+ Dodaj bieżący”: zapamiętuje obecny symbol warstwy jako własny kafelek.
  function dodajBiezacyStyl(nazwa) {
    const vl = styleTargetLayer;
    nazwa = String(nazwa).trim();
    if (!vl || nazwa === "")
      return;
    if (!LayerUtils.hasSimpleSymbology(vl)) {
      displayToast(qsTr("Zapisać da się tylko styl pojedynczy — przełącz „Sposób” na Pojedynczy."));
      return;
    }
    const rodzaj = LayerUtils.symbolType(vl);
    const s = { "n": nazwa, "wyp": hexA(LayerUtils.fillColor(vl)), "st": LayerUtils.strokeStyle(vl) };
    if (rodzaj === 1) {
      s.gr = LayerUtils.symbolSize(vl);
    } else {
      s.kon = hexA(LayerUtils.strokeColor(vl));
      s.gr = LayerUtils.strokeWidth(vl);
    }
    if (rodzaj === 0) {
      s.ks = (typeof LayerUtils.markerShape === "function") ? LayerUtils.markerShape(vl) : 6;
      s.r = LayerUtils.symbolSize(vl);
    }
    const wlasne = czytajJson(ukladUstawienia.wlasneStyle, {});
    const k = String(rodzaj);
    wlasne[k] = (wlasne[k] || []).filter(function (x) { return x.n !== nazwa; });
    wlasne[k].push(s);
    ukladUstawienia.wlasneStyle = JSON.stringify(wlasne);
    dodawanieStylu = false;
    odswiezListeStylow();
    kafelkiStylow.positionViewAtEnd();
    displayToast(qsTr("Dodano do szybkich stylów: %1").arg(nazwa));
  }

  //! Własny — usuwa; gotowy — ukrywa (wraca przez „Przywróć gotowe”).
  function usunStyl(s) {
    const k = String(rodzajStylu);
    if (s.wlasny) {
      const wlasne = czytajJson(ukladUstawienia.wlasneStyle, {});
      wlasne[k] = (wlasne[k] || []).filter(function (x) { return x.n !== s.n; });
      ukladUstawienia.wlasneStyle = JSON.stringify(wlasne);
    } else {
      const ukryte = czytajJson(ukladUstawienia.ukryteStyle, []);
      if (ukryte.indexOf(k + ":" + s.n) < 0)
        ukryte.push(k + ":" + s.n);
      ukladUstawienia.ukryteStyle = JSON.stringify(ukryte);
    }
    odswiezListeStylow();
  }

  function przywrocGotoweStyle() {
    const k = String(rodzajStylu) + ":";
    const ukryte = czytajJson(ukladUstawienia.ukryteStyle, []).filter(function (x) { return x.indexOf(k) !== 0; });
    ukladUstawienia.ukryteStyle = JSON.stringify(ukryte);
    odswiezListeStylow();
  }

  function zastosujSzybkiStyl(s) {
    const vl = styleTargetLayer;
    if (!vl)
      return;
    if (!LayerUtils.hasSimpleSymbology(vl))
      LayerUtils.setSingleSymbolRenderer(vl);
    const rodzaj = LayerUtils.symbolType(vl);
    LayerUtils.setFillColor(vl, s.wyp);
    if (rodzaj === 1) {
      LayerUtils.setSymbolSize(vl, s.gr);
    } else {
      LayerUtils.setStrokeColor(vl, s.kon);
      LayerUtils.setStrokeWidth(vl, s.gr);
    }
    if (s.st !== undefined)
      LayerUtils.setStrokeStyle(vl, s.st);
    if (rodzaj === 0) {
      if (s.ks !== undefined)
        LayerUtils.setMarkerShape(vl, s.ks);
      if (s.r !== undefined)
        LayerUtils.setSymbolSize(vl, s.r);
    }
    wczytajStanStylu();
    if (styleTargetMapLayer)
      projectInfo.saveLayerStyle(styleTargetMapLayer);
    displayToast(qsTr("Styl: %1").arg(s.n));
  }

  //! WorkField: rampa uzywana przy zakladaniu i przemalowywaniu klasyfikacji
  property string pendingRamp: "Turbo"
  //! WorkField: stan znaczników wierzchołka, odświeżany po każdej zmianie.
  property var vertexCfg: ({
      "present": false,
      "color": "#ffffff",
      "size": 1.6,
      "shape": "square"
    })

  parent: mainWindow.contentItem
  width: Math.min(childrenRect.width, mainWindow.width - Theme.popupScreenEdgeHorizontalMargin)
  height: Math.min(popupLayout.childrenRect.height + headerLayout.childrenRect.height + (zakladkiPanelu.visible ? zakladkiPanelu.height + 26 : 0) + stopka.implicitHeight + 30, mainWindow.height - Math.max(Theme.popupScreenEdgeVerticalMargin * 2, mainWindow.sceneTopMargin * 2 + 4, mainWindow.sceneBottomMargin * 2 + 4))
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  focus: visible

  onClosed: {
    index = undefined;
    edycjaNazwy.visible = false; // WF-NAZWA-ZAMKNIJ
    panelDuplikatu.visible = false; // WF-DUPLIKAT-ZAMKNIJ
  }

  onIndexChanged: {
    if (index === undefined)
      return;
    updateTitle();
    updateCredits();
    itemVisibleCheckBox.checked = layerTree.data(index, QfFlatLayerTreeModel.Visible);
    itemLabelsVisibleCheckBox.checked = layerTree.data(index, QfFlatLayerTreeModel.LabelsVisible);
    expandCheckBox.text = layerTree.data(index, QfFlatLayerTreeModel.Type) === QfFlatLayerTreeModel.Group ? qsTr('Expand group') : qsTr('Expand legend item');
    expandCheckBox.checked = !layerTree.data(index, QfFlatLayerTreeModel.IsCollapsed);
    reloadDataButtonVisible = layerTree.data(index, QfFlatLayerTreeModel.CanReloadData);
    zoomToButtonVisible = layerTree.data(index, QfFlatLayerTreeModel.HasSpatialExtent);
    showFeaturesListButtonVisible = isShowFeaturesListButtonVisible();
    showVisibleFeaturesListDropdownVisible = isShowVisibleFeaturesListDropdownVisible();
    trackingButtonVisible = isTrackingButtonVisible();
    trackingButtonText = trackingModel.layerInActiveTracking(layerTree.data(index, QfFlatLayerTreeModel.VectorLayerPointer)) ? qsTr('Stop tracking') : qsTr('Setup tracking');

    // the layer tree model returns -1 for items that do not support the opacity setting
    opacitySliderVisible = layerTree.data(index, QfFlatLayerTreeModel.Opacity) > -1;
    wczytajStanStylu(); // WF-STYL-STAN
  }

  Page {
    // WorkField 23.08.2026 — Page rysowal WLASNE tlo ze stylu Material,
    // nieprzezroczyste i niezalezne od motywu, tuz nad tlem QfPopup, ktore
    // juz bralo QfTheme.mainBackgroundColor. Skutek: panele wtyczek i paska
    // wyszukiwania zostawaly jasne, kiedy reszta aplikacji byla ciemna.
    background: null
    id: popupContent
    width: parent.width
    height: parent.height
    padding: 0
    header: ColumnLayout {
      spacing: 2

    RowLayout {
      id: headerLayout
      Layout.fillWidth: true
      spacing: 2

      Label {
        id: titleLabel
        visible: !edycjaNazwy.visible // WF-NAZWA-NAPIS
        Layout.fillWidth: true
        Layout.leftMargin: reloadDataButtonVisible ? zoomInButton.width + headerLayout.spacing : 0
        topPadding: 6
        bottomPadding: 6
        text: ''
        font: Theme.strongFont
        color: QfTheme.mainTextColor // WF 07.10: tytuł był ciemny na ciemnym
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
        maximumLineCount: 1
      }
      // WorkField 6.10.2026 [WF-NAZWA-POLE] — pole nazwy i trzy przyciski:
      // pisaczek otwiera pole, ptaszek zatwierdza, krzyżyk porzuca.
      TextField {
        id: edycjaNazwy
        visible: false
        Layout.fillWidth: true
        font: Theme.strongFont
        selectByMouse: true
        onAccepted: zatwierdzNazwe()
      }
      QfToolButton {
        Layout.alignment: Qt.AlignTop
        round: true
        visible: !edycjaNazwy.visible && index !== undefined && layerTree.data(index, QfFlatLayerTreeModel.Type) === QfFlatLayerTreeModel.Layer
        bgcolor: "transparent"
        iconSource: QfTheme.getThemeVectorIcon('ic_create_white_24dp')
        iconColor: QfTheme.mainTextColor
        onClicked: zacznijZmianeNazwy()
      }
      Button {
        visible: edycjaNazwy.visible
        flat: true
        text: qsTr("Zapisz") // WF-NAZWA-NAPIS-ZAPISZ
        font: QfTheme.tipFont
        onClicked: zatwierdzNazwe()
      }
      Button {
        visible: edycjaNazwy.visible
        flat: true
        text: qsTr("Anuluj") // WF-NAZWA-NAPIS-ANULUJ
        font: QfTheme.tipFont
        onClicked: edycjaNazwy.visible = false
      }
      QfToolButton {
        id: zoomInButton
        Layout.alignment: Qt.AlignTop
        Layout.rightMargin: 0
        round: true
        visible: reloadDataButtonVisible && !edycjaNazwy.visible

        bgcolor: "transparent"
        iconSource: QfTheme.getThemeVectorIcon('refresh_24dp')
        iconColor: QfTheme.mainTextColor

        onClicked: {
          layerTree.data(index, QfFlatLayerTreeModel.MapLayerPointer).reload();
          close();
          dashBoard.visible = false;
          displayToast(qsTr('Reload of layer %1 triggered').arg(layerTree.data(index, Qt.DisplayName)));
        }
      }
    }

      // WorkField 07.10.2026 [WF-PANEL-UKLAD] — zakładki. Jasna plakietka pod aktywną
      // (ciemny motyw: teal na ciemnym tle jest nieczytelny — lekcja z szuflad).
      TabBar {
        id: zakladkiPanelu
        Layout.fillWidth: true
        Layout.leftMargin: 6
      Layout.rightMargin: 6
        visible: ukladZakladki && jestWektor
        currentIndex: ukladUstawienia.zakladka
        onCurrentIndexChanged: ukladUstawienia.zakladka = currentIndex

        Repeater {
          model: [qsTr("Warstwa"), qsTr("Styl"), qsTr("Etykiety")]

          delegate: TabButton {
            id: przyciskZakladki
            required property var modelData
            text: modelData
            font: Theme.defaultFont
            contentItem: Text {
              text: przyciskZakladki.text
              font: przyciskZakladki.font
              color: przyciskZakladki.checked ? Theme.mainColor : Theme.mainTextColor
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
              color: "transparent"
              Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: 4
                color: Qt.rgba(1, 1, 1, 0.9)
                visible: przyciskZakladki.checked
              }
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        visible: ukladZakladki && jestWektor
        text: ukladUstawienia.zakladka === 0 ? sekcjaWarstwa.stan : ukladUstawienia.zakladka === 1 ? sekcjaStyl.stan : sekcjaEtykiety.stan
        font: Theme.tipFont
        color: Theme.secondaryTextColor
        elide: Text.ElideRight
      }

    }


    // WorkField 07.10.2026 [WF-PANEL-STOPKA] — stały pasek na dole: zawsze pod ręką,
    // bez przewijania. „Oko” — przytrzymaj, a panel zniknie i widać mapę ze zmianą.
    footer: RowLayout {
      id: stopka
      spacing: 6

      QfToolButton {
        id: zoomToButton
        visible: zoomToButtonVisible
        round: true
        bgcolor: QfTheme.toolButtonBackgroundColor
        iconSource: QfTheme.getThemeVectorIcon('zoom_out_map_24dp')
        iconColor: QfTheme.mainOverlayColor
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Pokaż całą warstwę")

        onClicked: {
          mapCanvas.mapSettings.extent = layerTree.nodeExtent(index, mapCanvas.mapSettings);
          close();
          dashBoard.visible = false;
        }
      }

      QfButton {
        id: showFeaturesList
        Layout.fillWidth: true
        dropdown: showVisibleFeaturesListDropdownVisible
        text: qsTr('Obiekty')
        visible: showFeaturesListButtonVisible
        icon.source: QfTheme.getThemeVectorIcon('ic_list_black_24dp')

        onClicked: {
          if (parseInt(layerTree.data(index, QfFlatLayerTreeModel.FeatureCount)) === 0) {
            displayToast(qsTr("The layer has no features"));
          } else {
            var vl = layerTree.data(index, QfFlatLayerTreeModel.VectorLayerPointer);
            var filter = layerTree.data(index, QfFlatLayerTreeModel.FilterExpression);
            featureListForm.model.setFeatures(vl, filter);
            if (layerTree.data(index, QfFlatLayerTreeModel.HasSpatialExtent)) {
              mapCanvas.mapSettings.extent = layerTree.nodeExtent(index, mapCanvas.mapSettings);
            }
          }
          close();
          dashBoard.visible = false;
        }

        onDropdownClicked: {
          showFeaturesMenu.popup(showFeaturesList.width - showFeaturesMenu.width + 10, showFeaturesList.y + 10);
        }
      }

      QfToolButton {
        id: podgladMapy
        visible: jestWektor || opacitySliderVisible
        round: true
        bgcolor: QfTheme.toolButtonBackgroundColor
        iconSource: ""

        OkoIkona {
          anchors.centerIn: parent
          kolor: QfTheme.mainOverlayColor
        }
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Przytrzymaj, aby zobaczyć mapę")

        onPressed: {
          popup.opacity = 0.0;
          popup.dim = false;
        }
        onReleased: {
          popup.opacity = 1.0;
          popup.dim = true;
        }
        onCanceled: {
          popup.opacity = 1.0;
          popup.dim = true;
        }
      }

      QfButton {
        id: doneButton
        Layout.fillWidth: true
        text: qsTr("Gotowe")
        icon.source: Theme.getThemeVectorIcon("ic_check_white_24dp")
        onClicked: close()
      }
    }

    ScrollView {
      anchors.fill: parent
      padding: 5
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical: QfScrollBar {}
      contentWidth: popupLayout.childrenRect.width
      contentHeight: popupLayout.childrenRect.height
      clip: true

      ColumnLayout {
        id: popupLayout
        width: popupContent.width - 10
        spacing: 4

        // WorkField 6.10.2026 [WF-NAZWA-PODPIS] — w trakcie edycji nazwy
        // jedno zdanie: co ta zmiana robi, a czego nie.
        Text {
          visible: edycjaNazwy.visible
          Layout.fillWidth: true
          Layout.bottomMargin: 6
          wrapMode: Text.WordWrap
          font: QfTheme.tipFont
          color: QfTheme.secondaryTextColor
          text: zrodloDanych.opis && zrodloDanych.opis.warstwa !== ""
                ? qsTr("Zmieniasz nazwę w legendzie. Tabela %1 w bazie zostaje bez zmian.").arg(zrodloDanych.opis.warstwa)
                : qsTr("Zmieniasz nazwę w legendzie. Dane warstwy zostają bez zmian.")
        }
        FontMetrics {
          id: fontMetrics
          font: lockText.font
        }

        Text {
          id: invalidText
          visible: index !== undefined && !layerTree.data(index, FlatLayerTreeModel.IsValid)
          Layout.fillWidth: true
          Layout.preferredHeight: visible ? implicitHeight : 0
          bottomPadding: visible ? 15 : 0

          wrapMode: Text.WordWrap
          textFormat: Text.RichText
          text: qsTr('This layer is invalid. This might be due to a network issue, a missing file or a misconfiguration of the project.')
          font: QfTheme.tipFont
          color: QfTheme.errorColor
        }

        Sekcja {
          id: sekcjaWarstwa
          nr: 0
          tytul: qsTr("Warstwa")
          stan: ((index !== undefined && layerTree.data(index, QfFlatLayerTreeModel.Checkable)) ? (itemVisibleCheckBox.checked ? qsTr("na mapie") : qsTr("ukryta")) : "") + (opacitySliderVisible ? " · " + qsTr("krycie %1 %").arg(Math.round(slider.value)) : "")
          zakladki: ukladZakladki
          aktywna: ukladUstawienia.zakladka
          otwarta: ukladUstawienia.otwartaWarstwa
          dostepna: true
          jedyna: !jestWektor
          onPrzelacz: ukladUstawienia.otwartaWarstwa = !ukladUstawienia.otwartaWarstwa
          /**
           * WorkField 23.08.2026 — SKAD ta warstwa bierze dane.
           *
           * Odkad "Dodaj z pliku" importuje do bazy projektu, pytanie "czy ta
           * warstwa siedzi juz w data.gpkg, czy nadal wisi na pliku z karty"
           * pada przy kazdym zleceniu — a odpowiedz byla wylacznie w QGIS-ie
           * na komputerze, czyli w terenie nie bylo jej wcale. Warstwa wisząca
           * na pliku spoza projektu znika po wyjeciu karty i nie jedzie ze
           * zwrotem; to jest ostrzezenie, nie ozdoba, stad barwa.
           *
           * Sciezke da sie zaznaczyc myszka ORAZ skopiowac przyciskiem —
           * na telefonie zaznaczanie jest niewykonalne, na komputerze
           * przycisk bywa zbedny.
           */
          ColumnLayout {
            id: zrodloDanych

            property var opis: index !== undefined ? NarzedziaProjektu.zrodloWarstwy(layerTree.data(index, QfFlatLayerTreeModel.MapLayerPointer)) : null

            Layout.fillWidth: true
            Layout.bottomMargin: visible ? 8 : 0
            spacing: 1
            visible: opis !== null && opis.ok === true

            RowLayout {
              Layout.fillWidth: true
              spacing: 4

              Text {
                Layout.fillWidth: true
                text: !zrodloDanych.opis ? "" : zrodloDanych.opis.wBazieProjektu ? qsTr("Dane: baza projektu") : zrodloDanych.opis.istnieje ? qsTr("Dane: osobny plik") : qsTr("Dane: źródło zdalne")
                font: QfTheme.tipFont
                color: zrodloDanych.opis && zrodloDanych.opis.istnieje && !zrodloDanych.opis.wBazieProjektu ? QfTheme.warningColor : QfTheme.mainTextColor
                elide: Text.ElideRight
              }

              QfToolButton {
                round: true
                bgcolor: "transparent"
                iconSource: QfTheme.getThemeVectorIcon("ic_copy_black_24dp")
                iconColor: QfTheme.mainTextColor
                onClicked: {
                  platformUtilities.copyTextToClipboard(zrodloDanych.opis.pelny);
                  displayToast(qsTr("Skopiowano ścieżkę"));
                }
              }
            }

            TextEdit {
              Layout.fillWidth: true
              text: !zrodloDanych.opis ? "" : zrodloDanych.opis.plik !== "" ? zrodloDanych.opis.plik : zrodloDanych.opis.pelny
              readOnly: true
              selectByMouse: true
              wrapMode: TextEdit.WrapAnywhere
              font: QfTheme.tinyFont
              color: QfTheme.secondaryTextColor
            }

            Text {
              Layout.fillWidth: true
              visible: zrodloDanych.opis && zrodloDanych.opis.warstwa !== ""
              text: qsTr("tabela: %1").arg(zrodloDanych.opis ? zrodloDanych.opis.warstwa : "")
              font: QfTheme.tinyFont
              color: QfTheme.secondaryTextColor
              elide: Text.ElideRight
            }
          }

          // WorkField 6.10.2026 [WF-DUPLIKAT-PANEL] — „Duplikuj warstwę”.
          // Tylko dla warstw z bazy projektu: z pliku spoza projektu
          // duplikat bylby kopia czegos, co i tak nie jedzie ze zwrotem.
          QfButton {
            Layout.fillWidth: true
            visible: !panelDuplikatu.visible && zrodloDanych.visible && zrodloDanych.opis !== null && zrodloDanych.opis.wBazieProjektu === true
            text: qsTr("Duplikuj warstwę")
            onClicked: otworzDuplikat()
          }

          ColumnLayout {
            id: panelDuplikatu
            visible: false
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 4

            Text {
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              font: QfTheme.tipFont
              color: QfTheme.mainTextColor
              text: qsTr("Nowa tabela w bazie projektu: te same pola, styl i formularz. Relacje (np. załączniki) nie są kopiowane.")
            }

            TextField {
              id: nazwaDuplikatu
              Layout.fillWidth: true
              selectByMouse: true
              placeholderText: qsTr("nazwa_tabeli")
              onAccepted: duplikuj()
            }

            Text {
              Layout.fillWidth: true
              visible: text !== ""
              wrapMode: Text.WordWrap
              font: QfTheme.tipFont
              color: QfTheme.errorColor
              text: panelDuplikatu.visible ? bladNazwyDuplikatu(nazwaDuplikatu.text.trim()) : ""
            }

            CheckBox {
              id: zObiektamiBox
              text: qsTr("Razem z obiektami")
              font: QfTheme.tipFont
            }

            RowLayout {
              Layout.fillWidth: true
              Item {
                Layout.fillWidth: true
              }
              Button {
                flat: true
                text: qsTr("Anuluj")
                font: QfTheme.tipFont
                onClicked: panelDuplikatu.visible = false
              }
              Button {
                flat: true
                text: qsTr("Duplikuj")
                font: QfTheme.tipFont
                enabled: bladNazwyDuplikatu(nazwaDuplikatu.text.trim()) === ""
                opacity: enabled ? 1.0 : 0.35
                onClicked: duplikuj()
              }
            }
          }
          CheckBox {
            id: expandCheckBox
            Layout.fillWidth: true
            topPadding: 5
            bottomPadding: 5
            text: qsTr('Expand legend item')
            font: QfTheme.defaultFont
            visible: index && layerTree.data(index, QfFlatLayerTreeModel.HasChildren) ? true : false

            onClicked: {
              layerTree.setData(index, checkState === Qt.Unchecked, QfFlatLayerTreeModel.IsCollapsed);
              close();
            }
          }

          CheckBox {
            id: itemVisibleCheckBox
            Layout.fillWidth: true
            topPadding: 5
            bottomPadding: 5
            text: qsTr('Show on map')
            font: QfTheme.defaultFont
            // visible for all layer tree items but nonspatial layers
            visible: index && layerTree.data(index, QfFlatLayerTreeModel.Checkable) && layerTree.data(index, QfFlatLayerTreeModel.HasSpatialExtent) ? true : false
            indicator.height: 16
            indicator.width: 16
            indicator.implicitHeight: 24
            indicator.implicitWidth: 24

            onClicked: {
              layerTree.setData(index, checkState === Qt.Checked, QfFlatLayerTreeModel.Visible);
              flatLayerTree.mapTheme = '';
              projectInfo.saveLayerTreeState();
            }
          }
          RowLayout {
            id: opacitySlider

            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            spacing: 4
            visible: opacitySliderVisible

            QfToolButton {
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              Layout.preferredWidth: 24
              Layout.leftMargin: 4
              width: 24
              height: 24
              padding: 0
              enabled: false
              bgcolor: "transparent"

              icon.source: QfTheme.getThemeVectorIcon("ic_opacity_black_24dp")
              icon.color: QfTheme.mainTextColor
            }

            Text {
              Layout.alignment: Qt.AlignVCenter
              text: qsTr("Opacity")
              font: QfTheme.defaultFont
              color: QfTheme.mainTextColor
            }

            QfSlider {
              id: slider
              Layout.fillWidth: true
              Layout.rightMargin: 5
              Layout.alignment: Qt.AlignVCenter
              value: index !== undefined ? layerTree.data(index, QfFlatLayerTreeModel.Opacity) * 100 : 0
              from: 0
              to: 100
              stepSize: 1
              suffixText: " %"
              height: 40

              onMoved: function () {
                layerTree.setData(index, value / 100, QfFlatLayerTreeModel.Opacity);
                projectInfo.saveLayerStyle(layerTree.data(index, QfFlatLayerTreeModel.MapLayerPointer));
              }
            }
          }
          QfButton {
            id: trackingButton
            Layout.fillWidth: true
            Layout.topMargin: 5
            text: trackingButtonText
            visible: trackingButtonVisible
            icon.source: QfTheme.getThemeVectorIcon('directions_walk_24dp')

            onClicked: {
              const layer = layerTree.data(index, QfFlatLayerTreeModel.VectorLayerPointer);
              popup.close();
              if (trackingModel.layerInActiveTracking(layer)) {
                trackingModel.stopTracker(layer);
                displayToast(qsTr('Tracking on layer %1 stopped').arg(layer.name));
              } else {
                trackerSettings.prepareSettings(layer);
                trackerSettings.open();
              }
            }
          }
          QfButton {
            id: exportLayerButton
            Layout.fillWidth: true
            Layout.topMargin: 5
            text: qsTr("Eksportuj jako…")
            visible: index !== undefined && layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer) ? true : false
            onClicked: {
              const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
              if (vl) {
                exportDialog.openFor(vl);
                close();
              }
            }
          }
          Text {
            id: lockText

            property var padlockIcon: QfTheme.getThemeVectorIcon('ic_lock_black_24dp')
            property real padlockSize: fontMetrics.height - 5

            property bool isReadOnly: index !== undefined && layerTree.data(index, QfFlatLayerTreeModel.ReadOnly)
            property bool isFeatureAdditionLocked: index !== undefined && layerTree.data(index, QfFlatLayerTreeModel.FeatureAdditionLocked)
            property bool isAttributeEditingLocked: index !== undefined && layerTree.data(index, QfFlatLayerTreeModel.AttributeEditingLocked)
            property bool isGeometryEditingLocked: index !== undefined && layerTree.data(index, QfFlatLayerTreeModel.GeometryEditingLocked)
            property bool isFeatureDeletionLocked: index !== undefined && layerTree.data(index, QfFlatLayerTreeModel.FeatureDeletionLocked)

            visible: isReadOnly || isFeatureAdditionLocked || isAttributeEditingLocked || isGeometryEditingLocked || isFeatureDeletionLocked
            Layout.fillWidth: true
            topPadding: 5

            wrapMode: Text.WordWrap
            textFormat: Text.RichText
            text: {
              if (isReadOnly) {
                return qsTr('Warstwa tylko do odczytu');
              } else if (isFeatureAdditionLocked || isAttributeEditingLocked || isGeometryEditingLocked || isFeatureDeletionLocked) {
                let locks = [];
                if (isFeatureAdditionLocked) {
                  locks.push(qsTr('feature addition'));
                }
                if (isAttributeEditingLocked) {
                  locks.push(qsTr('attribute editing'));
                }
                if (isGeometryEditingLocked) {
                  locks.push(qsTr('geometry editing'));
                }
                if (isFeatureDeletionLocked) {
                  locks.push(qsTr('feature deletion'));
                }
                return qsTr('Disabled layer permissions: %1').arg(locks.join(', '));
              }
              return '';
            }
            font: QfTheme.tipFont
            color: QfTheme.secondaryTextColor
          }

          Text {
            id: creditsText
            Layout.fillWidth: true
            Layout.topMargin: 5
            wrapMode: Text.WordWrap
            textFormat: Text.RichText
            text: ''
            font.pointSize: QfTheme.tipFont.pointSize
            font.italic: true
            color: QfTheme.secondaryTextColor

            onLinkActivated: link => {
              Qt.openUrlExternally(link);
            }
          }
        }


        Sekcja {
          id: sekcjaStyl
          nr: 1
          tytul: qsTr("Styl")
          stan: opisStylu()
          zakladki: ukladZakladki
          aktywna: ukladUstawienia.zakladka
          otwarta: ukladUstawienia.otwartyStyl
          dostepna: jestWektor
          jedyna: false
          onPrzelacz: ukladUstawienia.otwartyStyl = !ukladUstawienia.otwartyStyl

          ColumnLayout {
            id: rendererModeRow

            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 6

            function applyMode(mode) {
              const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
              if (!vl)
                return;
              if (mode === "single") {
                LayerUtils.setSingleSymbolRenderer(vl);
              } else if (mode === "categorized") {
                if (pendingField === "")
                  return;
                LayerUtils.setCategorizedRenderer(vl, pendingField, pendingRamp);
              } else if (mode === "graduated") {
                if (pendingField === "")
                  return;
                LayerUtils.setGraduatedRenderer(vl, pendingField, pendingClassCount, pendingRamp);
              }
              // WorkField: rampy syntetyczne (losowe, zloty kat) nie przechodza
              // przez setCategorizedRenderer — malowanie trzeba dolozyc osobno.
              // Dla ramp zwyklych to powtorzenie tego samego, wiec nieszkodliwe.
              if (mode !== "single")
                LayerUtils.applyColorRamp(vl, pendingRamp);
              symbologyVisible = LayerUtils.hasSimpleSymbology(vl);
              categoriesVisible = LayerUtils.hasCategorizedSymbology(vl);
              categoryEntries = categoriesVisible ? LayerUtils.rendererCategories(vl) : [];
              if (symbologyVisible) {
                symbolKind = LayerUtils.symbolType(vl);
                fillPalette.currentColor = LayerUtils.fillColor(vl);
                strokePalette.currentColor = LayerUtils.strokeColor(vl);
              }
              trybWidoku = mode;
              projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
            }

            // WorkField 07.10.2026 [WF-SZYBKIE-STYLE] — kafelki gotowych stylów.
            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              spacing: 6
              visible: rodzajStylu >= 0

              Text {
                Layout.fillWidth: true
                text: qsTr("Szybkie style")
                font: Theme.strongTipFont
                color: Theme.mainTextColor
              }

              QfButton {
                visible: edycjaStylow
                text: qsTr("Przywróć gotowe")
                font.pointSize: Theme.tinyFont.pointSize
                implicitHeight: 34
                bgcolor: Theme.controlBackgroundAlternateColor
                color: Theme.mainTextColor
                onClicked: przywrocGotoweStyle()
              }

              QfButton {
                text: edycjaStylow ? qsTr("Zakończ") : qsTr("Edytuj")
                font.pointSize: Theme.tinyFont.pointSize
                implicitHeight: 34
                bgcolor: edycjaStylow ? Theme.mainColor : Theme.controlBackgroundAlternateColor
                color: edycjaStylow ? Theme.mainOverlayColor : Theme.mainTextColor
                onClicked: {
                  edycjaStylow = !edycjaStylow;
                  dodawanieStylu = false;
                }
              }
            }

            // Jeden rząd przesuwany palcem — nie zjada połowy ekranu.
            ListView {
              id: kafelkiStylow
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.preferredHeight: 86
              orientation: ListView.Horizontal
              spacing: 6
              clip: true
              visible: rodzajStylu >= 0
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                model: stylyBiezace

                // „+ Dodaj bieżący” — ostatni kafelek, jak „Dodaj do ulubionych” w QGIS
                footer: Item {
                  width: 84
                  height: 82
                  Rectangle {
                    x: 6
                    width: 78
                    height: 82
                    radius: 8
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.controlBorderColor
                    opacity: symbologyVisible ? 1.0 : 0.4
                    Text {
                      anchors.centerIn: parent
                      width: parent.width - 8
                      text: "+
  " + qsTr("Dodaj bieżący")
                      font: Theme.tinyFont
                      color: Theme.mainTextColor
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.WordWrap
                    }
                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        if (!symbologyVisible) {
                          displayToast(qsTr("Zapisać da się tylko styl pojedynczy — przełącz „Sposób” na Pojedynczy."));
                          return;
                        }
                        edycjaStylow = false;
                        dodawanieStylu = true;
                        nazwaStylu.text = "";
                        nazwaStylu.forceActiveFocus();
                      }
                    }
                  }
                }

                delegate: Rectangle {
                  id: kafelek
                  required property var modelData
                  readonly property int rodzaj: rodzajStylu

                  width: 78
                  height: 82
                  radius: 8
                  color: Theme.controlBackgroundAlternateColor
                  border.width: mysz.pressed ? 2 : 1
                  border.color: mysz.pressed ? Theme.mainColor : Theme.controlBorderColor

                  Canvas {
                    id: probka
                    Connections {
                      target: Theme
                      ignoreUnknownSignals: true
                      function onMainBackgroundColorChanged() { probka.requestPaint() }
                    }
                    x: 7
                    y: 7
                    width: 64
                    height: 40
                    onPaint: {
                      const c = getContext("2d");
                      c.reset();
                      // tło neutralne, z motywu (prośba Piotra 07.10: symbol ma być
                      // czytelny sam w sobie, nie na udawanym ortofoto)
                      c.fillStyle = Theme.mainBackgroundColor;
                      c.fillRect(0, 0, width, height);
                      const s = kafelek.modelData;
                      const kreski = { 1: [], 2: [6, 3], 3: [1.5, 3], 4: [6, 3, 1.5, 3] };
                      function kolor(hex) {
                        if (hex.length === 9) {
                          const a = parseInt(hex.substr(1, 2), 16) / 255;
                          return Qt.rgba(parseInt(hex.substr(3, 2), 16) / 255, parseInt(hex.substr(5, 2), 16) / 255, parseInt(hex.substr(7, 2), 16) / 255, a);
                        }
                        return hex;
                      }
                      // Obwódka w kolorze napisów motywu (z przezroczystością) pod symbolem:
                      // czarny krzyż czy czarna kreska nie znikają na ciemnym tle,
                      // a biały obrys — na jasnym.
                      const t = Theme.mainTextColor;
                      const obwodka = Qt.rgba(t.r, t.g, t.b, 0.35);
                      function rysuj(sciezka, wyp, kon, gr, kreska) {
                        c.setLineDash([]);
                        c.strokeStyle = obwodka;
                        c.lineWidth = gr + 2.5;
                        c.beginPath(); sciezka(); c.stroke();
                        if (wyp) {
                          c.fillStyle = wyp;
                          c.beginPath(); sciezka(); c.fill();
                        }
                        c.setLineDash(kreska);
                        c.strokeStyle = kon;
                        c.lineWidth = gr;
                        c.beginPath(); sciezka(); c.stroke();
                      }
                      const kreska = kreski[s.st || 1];
                      if (kafelek.rodzaj === 2) {
                        rysuj(function () { c.rect(10, 7, 44, 26); },
                              kolor(s.wyp), kolor(s.kon), Math.max(1, s.gr * 2.5), kreska);
                      } else if (kafelek.rodzaj === 1) {
                        rysuj(function () { c.moveTo(8, 20); c.lineTo(56, 20); },
                              null, kolor(s.wyp), Math.max(1, s.gr * 2.5), kreska);
                      } else {
                        const r = Math.max(4, s.r * 2.4);
                        const x = 32, y = 20;
                        if (s.ks === 8) {
                          rysuj(function () { c.moveTo(x - r, y); c.lineTo(x + r, y); c.moveTo(x, y - r); c.lineTo(x, y + r); },
                                null, kolor(s.wyp), Math.max(2, r / 2.5), []);
                        } else {
                          rysuj(function () {
                            if (s.ks === 0) {
                              c.rect(x - r, y - r, 2 * r, 2 * r);
                            } else if (s.ks === 3) {
                              c.moveTo(x, y - r); c.lineTo(x + r, y + r * 0.8); c.lineTo(x - r, y + r * 0.8); c.closePath();
                            } else if (s.ks === 12) {
                              for (let i = 0; i < 10; i++) {
                                const k = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 === 0 ? r : r / 2.3;
                                if (i === 0) c.moveTo(x + rr * Math.cos(k), y + rr * Math.sin(k));
                                else c.lineTo(x + rr * Math.cos(k), y + rr * Math.sin(k));
                              }
                              c.closePath();
                            } else {
                              c.arc(x, y, r, 0, 2 * Math.PI);
                            }
                          }, kolor(s.wyp), kolor(s.kon), 1.5, []);
                        }
                      }
                    }
                  }

                  Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    height: 28
                    text: kafelek.modelData.n
                    font: Theme.tinyFont
                    color: Theme.mainTextColor
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                  }

                  MouseArea {
                    id: mysz
                    anchors.fill: parent
                    onClicked: edycjaStylow ? usunStyl(kafelek.modelData) : zastosujSzybkiStyl(kafelek.modelData)
                  }

                  // własny styl: mała gwiazdka w rogu
                  Text {
                    visible: kafelek.modelData.wlasny === true && !edycjaStylow
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 2
                    text: "★"
                    font: Theme.tinyFont
                    color: Theme.mainColor
                  }

                  // tryb edycji: czerwony krzyżyk — dotknięcie usuwa (gotowy: ukrywa)
                  Rectangle {
                    visible: edycjaStylow
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 2
                    width: 24
                    height: 24
                    radius: 12
                    color: Theme.errorColor
                    Text {
                      anchors.centerIn: parent
                      text: "×"
                      color: "white"
                      font.pixelSize: 18
                      font.bold: true
                    }
                  }
                }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              spacing: 6
              visible: dodawanieStylu

              TextField {
                id: nazwaStylu
                Layout.fillWidth: true
                placeholderText: qsTr("Nazwa stylu, np. Płaty — obrys")
                font: Theme.defaultFont
                onAccepted: dodajBiezacyStyl(text)
              }
              QfButton {
                text: qsTr("Zapisz")
                implicitHeight: 38
                enabled: nazwaStylu.text.trim() !== ""
                opacity: enabled ? 1.0 : 0.4
                onClicked: dodajBiezacyStyl(nazwaStylu.text)
              }
              QfButton {
                text: "×"
                implicitHeight: 38
                implicitWidth: 40
                bgcolor: Theme.controlBackgroundAlternateColor
                color: Theme.mainTextColor
                onClicked: dodawanieStylu = false
              }
            }

            Text {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              visible: rodzajStylu >= 0
              wrapMode: Text.WordWrap
              text: edycjaStylow
                    ? qsTr("Dotknij krzyżyka, aby usunąć. Własne style (★) znikają na stałe, gotowe tylko się chowają — wracają przez „Przywróć gotowe”.")
                    : qsTr("Przesuń, aby zobaczyć więcej. Dotknięcie zmienia styl od razu; „+ Dodaj bieżący” zapisuje obecny wygląd warstwy jako nowy kafelek.")
              font: Theme.tipFont
              color: Theme.secondaryTextColor
            }

            Text {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.topMargin: 6
              text: qsTr("Sposób wyświetlania")
              font: Theme.strongTipFont
              color: Theme.mainTextColor
            }

            // Kolejność kroków: sposób → pole → klasy → rampa. Wybór pola stosuje styl od razu.
            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.rightMargin: 4
              spacing: 4

              Repeater {
                model: [
                  { "k": "single", "n": qsTr("Pojedynczy") },
                  { "k": "categorized", "n": qsTr("Kategorie") },
                  { "k": "graduated", "n": qsTr("Przedziały") }
                ]

                delegate: QfButton {
                  required property var modelData
                  Layout.fillWidth: true
                  text: modelData.n
                  font.pointSize: Theme.tipFont.pointSize
                  bgcolor: trybWidoku === modelData.k ? Theme.mainColor : Theme.controlBackgroundAlternateColor
                  color: trybWidoku === modelData.k ? Theme.mainOverlayColor : Theme.mainTextColor
                  onClicked: wybierzTryb(modelData.k)
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 6
              visible: trybWidoku === "categorized" || trybWidoku === "graduated"

              Text {
                Layout.preferredWidth: 52
                text: qsTr("Pole")
                font: Theme.defaultFont
                color: Theme.mainTextColor
              }

              ComboBox {
                id: fieldCombo

                Layout.fillWidth: true
                font: Theme.defaultFont
                model: polaTrybu.map(f => f.name)
                currentIndex: -1
                displayText: currentIndex < 0 ? qsTr("wybierz…") : currentText

                readonly property bool currentNumeric: currentIndex >= 0 && currentIndex < polaTrybu.length ? polaTrybu[currentIndex].numeric : false

                onActivated: function (i) {
                  if (i < 0 || i >= polaTrybu.length)
                    return;
                  pendingField = polaTrybu[i].name;
                  rendererModeRow.applyMode(trybWidoku);
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 6
              visible: trybWidoku === "graduated"

              Text {
                Layout.preferredWidth: 52
                text: qsTr("Klasy")
                font: Theme.defaultFont
                color: Theme.mainTextColor
              }

              SpinBox {
                Layout.fillWidth: true
                from: 2
                to: 12
                value: pendingClassCount
                font: Theme.defaultFont
                onValueModified: {
                  pendingClassCount = value;
                  if (pendingField !== "")
                    rendererModeRow.applyMode("graduated");
                }
              }
            }

            // WorkField 19.08.2026: wybor rampy kolorow. Rampa jest AUTOMATEM —
            // daje sensowny start przy kilkudziesieciu kategoriach; pojedyncze
            // kategorie poprawia sie potem paleta Materialize.
            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 6
              visible: trybWidoku === "categorized" || trybWidoku === "graduated"

              Text {
                Layout.preferredWidth: 52
                text: qsTr("Rampa")
                font: Theme.defaultFont
                color: Theme.mainTextColor
              }

              ComboBox {
                            id: rampCombo

                            Layout.fillWidth: true
                            font: Theme.defaultFont
                            model: LayerUtils.colorRampNames()
                            currentIndex: Math.max(0, model.indexOf(pendingRamp))

                            // WorkField 19.08.2026: nazwa rampy nic nie mowi o tym, jak
                            // rampa wyglada ("Mako", "PuBuGn", "RdYlBu"). Kazda pozycja
                            // niesie wiec wlasny gradient — wybiera sie okiem, nie pamiecia.
                            component RampSwatch: Row {
                              id: rampSwatch

                              property string rampName: ""
                              property int cells: 12
                              property real cellWidth: 5
                              property real cellHeight: 14

                              spacing: 0

                              Repeater {
                                model: LayerUtils.colorRampPreview(rampSwatch.rampName, rampSwatch.cells)

                                delegate: Rectangle {
                                  required property var modelData
                                  width: rampSwatch.cellWidth
                                  height: rampSwatch.cellHeight
                                  color: modelData
                                }
                              }
                            }

                            delegate: ItemDelegate {
                              id: rampItem

                              required property var modelData
                              required property int index

                              width: rampCombo.width
                              highlighted: rampCombo.highlightedIndex === index

                              contentItem: RowLayout {
                                spacing: 8

                                RampSwatch {
                                  rampName: rampItem.modelData
                                }

                                Text {
                                  Layout.fillWidth: true
                                  text: rampItem.modelData
                                  font: Theme.defaultFont
                                  // WorkField: liste rozwijana rysuje STYL, nie Theme — kolor
                                  // tekstu musi pochodzic z tego samego zrodla co tlo popupu,
                                  // inaczej wychodzi jasne na jasnym (notatka z 18.08).
                                  color: rampItem.highlighted ? rampItem.palette.highlightedText : rampItem.palette.text
                                  elide: Text.ElideRight
                                  verticalAlignment: Text.AlignVCenter
                                }
                              }
                            }

                            // zwiniete pole: gradient wybranej rampy zamiast samego napisu
                            contentItem: RowLayout {
                              spacing: 8

                              RampSwatch {
                                Layout.leftMargin: 8
                                rampName: rampCombo.currentText
                              }

                              Text {
                                Layout.fillWidth: true
                                text: rampCombo.currentText
                                font: Theme.defaultFont
                                color: rampCombo.palette.text
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                              }
                            }

                            onActivated: {
                              pendingRamp = currentText;
                              const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                              if (!vl)
                                return;
                              // Przemalowanie, nie odtworzenie klasyfikacji: recznie
                              // poprawione kategorie przezywaja zmiane rampy tylko wtedy,
                              // gdy nie przechodzimy przez setCategorizedRenderer.
                              if (LayerUtils.applyColorRamp(vl, pendingRamp)) {
                                categoryEntries = LayerUtils.rendererCategories(vl);
                                projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                              }
                            }
                          }
            }

            Text {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              visible: text !== ""
              wrapMode: Text.WordWrap
              font: Theme.tipFont
              color: QfTheme.warningColor
              text: ((trybWidoku === "categorized" && !categoriesVisible) || trybWidoku === "graduated") && pendingField === ""
                    ? (trybWidoku === "graduated" && polaTrybu.length === 0 ? qsTr("Warstwa nie ma pól liczbowych — przedziały niemożliwe.") : qsTr("Wybierz pole — styl zmieni się od razu."))
                    : (trybWidoku === "other" ? qsTr("Warstwa ma styl z QGIS, którego ten panel nie edytuje (np. reguły lub przedziały). Wybierz sposób powyżej albo szybki styl, aby go zastąpić.") : "")
            }
          }

          ColumnLayout {
            id: symbologyPanel

            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            spacing: 6
            visible: symbologyVisible && trybWidoku === "single"

            component StepperRow: RowLayout {
              id: stepper

              property string label: ""
              property real value: 0
              property real step: 0.1
              property real minimum: 0
              property real maximum: 20
              property string suffix: " mm"
              property int decimals: 1

              signal valueEdited(real newValue)

              function bump(delta) {
                const next = Math.min(maximum, Math.max(minimum, value + delta));
                if (Math.abs(next - value) < 0.0001)
                  return;
                value = next;
                valueEdited(next);
              }

              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 6

              Text {
                Layout.fillWidth: true
                text: stepper.label
                font: Theme.defaultFont
                color: Theme.mainTextColor
              }

              QfButton {
                text: "−"
                font.pointSize: Theme.defaultFont.pointSize + 2
                implicitWidth: 46
                bgcolor: Theme.toolButtonBackgroundColor
                color: Theme.mainOverlayColor
                onClicked: stepper.bump(-stepper.step)
                onPressAndHold: stepper.bump(-stepper.step * 10)
              }

              Text {
                Layout.preferredWidth: 74
                horizontalAlignment: Text.AlignHCenter
                text: stepper.value.toFixed(stepper.decimals) + stepper.suffix
                font: Theme.strongTipFont
                color: Theme.mainTextColor
              }

              QfButton {
                text: "+"
                font.pointSize: Theme.defaultFont.pointSize + 2
                implicitWidth: 46
                bgcolor: Theme.toolButtonBackgroundColor
                color: Theme.mainOverlayColor
                onClicked: stepper.bump(stepper.step)
                onPressAndHold: stepper.bump(stepper.step * 10)
              }
            }

            component SectionLabel: Text {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              Layout.topMargin: visible ? 6 : 0
              Layout.preferredHeight: visible ? implicitHeight : 0
              font: Theme.strongTipFont
              color: Theme.mainTextColor
            }


            SectionLabel {
              text: symbolKind === 1 ? qsTr("Kolor linii") : qsTr("Wypełnienie")
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 8

              Rectangle {
                id: fillPalette
                property color currentColor: "transparent"

                width: 44
                height: 30
                radius: 4
                color: currentColor
                border.width: 1
                border.color: Theme.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: openColorPicker(qsTr("Wypełnienie"), fillPalette.currentColor, function (chosen) {
                    const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                    if (!vl)
                      return;
                    LayerUtils.setFillColor(vl, chosen);
                    fillPalette.currentColor = chosen;
                    projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                  })
                }
              }

              Text {
                Layout.fillWidth: true
                text: qsTr("Dotknij, aby zmienić")
                font: Theme.tipFont
                color: Theme.secondaryTextColor
              }
            }

            SectionLabel {
              visible: symbolKind !== 1
              text: qsTr("Kontur")
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 8
              visible: symbolKind !== 1

              Rectangle {
                id: strokePalette
                property color currentColor: "transparent"

                width: 44
                height: 30
                radius: 4
                color: currentColor
                border.width: 1
                border.color: Theme.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: openStrokePicker(strokePalette.currentColor, strokeWidthValue, currentStrokeStyle, function (chosen) {
                    if (!styleTargetLayer)
                      return;
                    LayerUtils.setStrokeColor(styleTargetLayer, chosen);
                    strokePalette.currentColor = chosen;
                    if (styleTargetMapLayer)
                      projectInfo.saveLayerStyle(styleTargetMapLayer);
                  }, function (w) {
                    if (!styleTargetLayer)
                      return;
                    LayerUtils.setStrokeWidth(styleTargetLayer, w);
                    strokeWidthValue = w;
                    if (styleTargetMapLayer)
                      projectInfo.saveLayerStyle(styleTargetMapLayer);
                  }, function (st) {
                    if (!styleTargetLayer)
                      return;
                    LayerUtils.setStrokeStyle(styleTargetLayer, st);
                    currentStrokeStyle = st;
                    if (styleTargetMapLayer)
                      projectInfo.saveLayerStyle(styleTargetMapLayer);
                  })
                }
              }

              Text {
                Layout.fillWidth: true
                text: qsTr("Dotknij, aby zmienić")
                font: Theme.tipFont
                color: Theme.secondaryTextColor
              }
            }



            SectionLabel {
              visible: symbolKind === 0
              text: qsTr("Kształt")
            }

            Flow {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              spacing: 6
              visible: symbolKind === 0

              Repeater {
                model: [
                  {
                    "s": 0,
                    "n": qsTr("Kwadrat")
                  },
                  {
                    "s": 3,
                    "n": qsTr("Trójkąt")
                  },
                  {
                    "s": 6,
                    "n": qsTr("Koło")
                  },
                  {
                    "s": 8,
                    "n": qsTr("Krzyż")
                  },
                  {
                    "s": 12,
                    "n": qsTr("Gwiazda")
                  }
                ]

                delegate: QfButton {
                  required property var modelData

                  text: modelData.n
                  font.pointSize: Theme.tinyFont.pointSize
                  bgcolor: currentMarkerShape === modelData.s ? Theme.mainColor : Theme.controlBackgroundAlternateColor
                  color: currentMarkerShape === modelData.s ? Theme.mainOverlayColor : Theme.mainTextColor

                  onClicked: {
                    const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                    if (!vl)
                      return;
                    LayerUtils.setMarkerShape(vl, modelData.s);
                    currentMarkerShape = modelData.s;
                    projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 6
              visible: symbolKind !== 2 && symbolSizeSlider.value > 0

              Text {
                text: symbolKind === 1 ? qsTr("Szerokość") : qsTr("Rozmiar")
                font: Theme.defaultFont
                color: Theme.mainTextColor
              }

              QfSlider {
                id: symbolSizeSlider
                Layout.fillWidth: true
                from: 0.5
                to: 12
                stepSize: 0.5
                suffixText: " mm"
                height: 40

                onMoved: function () {
                  const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  if (!vl)
                    return;
                  LayerUtils.setSymbolSize(vl, value);
                  projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                }
              }
            }
          }
          ColumnLayout {
            id: categoryPanel

            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            spacing: 4
            visible: categoriesVisible

            Text {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              text: qsTr("Kategorie (%1)").arg(categoryEntries.length)
              font: Theme.strongTipFont
              color: Theme.mainTextColor
            }

            ListView {
              id: categoryList

              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(contentHeight, 260)
              clip: true
              model: categoryEntries

              property int editingIndex: -1

              delegate: Column {
                required property int index
                required property var modelData

                width: categoryList.width
                spacing: 0

                RowLayout {
                  width: parent.width
                  height: 40
                  spacing: 8

                  Rectangle {
                    Layout.leftMargin: 4
                    width: 26
                    height: 26
                    radius: 4
                    color: modelData.color
                    border.width: 1
                    border.color: Theme.controlBorderColor
                    opacity: modelData.visible ? 1.0 : 0.35

                    MouseArea {
                      anchors.fill: parent
                      // WorkField 21.08.2026: wspólny picker (256 odcieni
                      // Materialize) zamiast trzynastu kolorów wklejonych
                      // w ten plik. Ten sam pomocnik, co przy wypełnieniu
                      // i konturze — kategorie jako jedyne go nie wołały.
                      onClicked: {
                        if (!styleTargetLayer)
                          return;
                        const nrKategorii = index;
                        openColorPicker(qsTr("Kategoria"), modelData.color, function (chosen) {
                          LayerUtils.setCategoryColor(styleTargetLayer, nrKategorii, chosen);
                          categoryEntries = LayerUtils.rendererCategories(styleTargetLayer);
                          if (styleTargetMapLayer)
                            projectInfo.saveLayerStyle(styleTargetMapLayer);
                        });
                      }
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    text: modelData.label !== "" ? modelData.label : qsTr("(puste)")
                    font: Theme.defaultFont
                    color: Theme.mainTextColor
                    opacity: modelData.visible ? 1.0 : 0.5
                    elide: Text.ElideRight

                    MouseArea {
                      anchors.fill: parent
                      onClicked: categoryList.editingIndex = categoryList.editingIndex === index ? -1 : index
                    }
                  }

                  QfToolButton {
                    Layout.rightMargin: 4
                    width: 32
                    height: 32
                    padding: 0
                    bgcolor: "transparent"
                    // WorkField 21.08.2026: nazwy ikon były niewypełnionymi
                    // zaślepkami, a obsługa kliknięcia pobierała warstwę
                    // i ją wyrzucała — przycisk widoczny, prowadzący donikąd.
                    iconSource: ""

                    OkoIkona {
                      anchors.centerIn: parent
                      kolor: modelData.visible ? Theme.mainTextColor : Theme.secondaryTextColor
                      przekreslone: !modelData.visible
                    }

                    onClicked: {
                      if (!styleTargetLayer)
                        return;
                      LayerUtils.setCategoryVisible(styleTargetLayer, index, !modelData.visible);
                      categoryEntries = LayerUtils.rendererCategories(styleTargetLayer);
                      if (styleTargetMapLayer)
                        projectInfo.saveLayerStyle(styleTargetMapLayer);
                    }
                  }
                }

              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 6
            spacing: 4
            visible: index !== undefined && layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer) ? true : false

            Text {
              Layout.fillWidth: true
              text: qsTr("Znaczniki")
              font: Theme.strongTipFont
              color: Theme.mainTextColor
            }

            Flow {
              Layout.fillWidth: true
              spacing: 6

              QfButton {
                text: qsTr("Stan w środku")
                font.pointSize: Theme.tinyFont.pointSize
                bgcolor: Theme.controlBackgroundAlternateColor
                color: Theme.mainTextColor
                onClicked: {
                  const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  if (!vl)
                    return;
                  if (LayerUtils.addStatusMarker(vl, "ZROBIONE")) {
                    projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                    displayToast(qsTr("Znacznik stanu dodany."));
                  } else {
                    // Uczciwie: najczęstsza przyczyna to brak pola, a nie awaria.
                    displayToast(qsTr("Nie dodano — warstwa musi być poligonowa i mieć pole ZROBIONE."), 'warning');
                  }
                }
              }

              QfButton {
                text: qsTr("Wierzchołki")
                font.pointSize: Theme.tinyFont.pointSize
                bgcolor: Theme.controlBackgroundAlternateColor
                color: Theme.mainTextColor
                onClicked: {
                  const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  if (!vl)
                    return;
                  if (LayerUtils.addVertexMarkers(vl)) {
                    vertexCfg = LayerUtils.vertexMarkerConfig(vl);
                    projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                    displayToast(qsTr("Znaczniki wierzchołków dodane."));
                  } else {
                    displayToast(qsTr("Nie dodano — to działa na poligonach i liniach."), 'warning');
                  }
                }
              }

              QfButton {
                text: qsTr("Zdejmij dodatki")
                font.pointSize: Theme.tinyFont.pointSize
                bgcolor: Theme.controlBackgroundAlternateColor
                color: Theme.mainTextColor
                onClicked: {
                  const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  if (!vl)
                    return;
                  displayToast(LayerUtils.removeExtraSymbolLayers(vl)
                               ? qsTr("Zdjęte.")
                               : qsTr("Nie było czego zdejmować."));
                  vertexCfg = LayerUtils.vertexMarkerConfig(vl);
                  projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                }
              }
            }

            // Regulacja wierzchołków — te same trzy pokrętła, co dla symbolu
            // pojedynczego. Widoczne dopiero, gdy jest co regulować.
            RowLayout {
              Layout.fillWidth: true
              Layout.topMargin: 2
              spacing: 8
              visible: vertexCfg.present

              function zapisz(kolor, rozmiar, ksztalt) {
                const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                if (!vl)
                  return;
                LayerUtils.setVertexMarker(vl, kolor, rozmiar, ksztalt);
                vertexCfg = LayerUtils.vertexMarkerConfig(vl);
                projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
              }

              Rectangle {
                width: 44
                height: 30
                radius: 4
                color: vertexCfg.color
                border.width: 1
                border.color: Theme.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: openColorPicker(qsTr("Wierzchołki"), vertexCfg.color, function (chosen) {
                    parent.parent.zapisz(chosen, vertexCfg.size, vertexCfg.shape);
                  })
                }
              }

              ComboBox {
                Layout.preferredWidth: 116
                font: Theme.defaultFont
                model: [qsTr("kwadrat"), qsTr("kółko"), qsTr("romb"), qsTr("krzyżyk")]
                readonly property var klucze: ["square", "circle", "diamond", "cross"]
                currentIndex: Math.max(0, klucze.indexOf(vertexCfg.shape))
                onActivated: parent.zapisz(vertexCfg.color, vertexCfg.size, klucze[currentIndex])
              }

              Slider {
                Layout.fillWidth: true
                from: 0.4
                to: 5.0
                stepSize: 0.2
                value: vertexCfg.size
                // dopiero po puszczeniu: przy każdym drgnięciu przebudowa
                // symbolu na kilkuset wierzchołkach zamula płótno
                onPressedChanged: {
                  if (!pressed)
                    parent.zapisz(vertexCfg.color, value, vertexCfg.shape);
                }
              }

              Text {
                text: vertexCfg.size.toFixed(1) + " mm"
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
              }
            }

            Text {
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              font: Theme.tipFont
              color: Theme.secondaryTextColor
              text: qsTr("Znaczniki dokładają się do symbolu warstwy — kolory kategorii zostają. „Zdejmij dodatki” zostawia sam symbol podstawowy.")
            }
          }
          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 6
            visible: index !== undefined && layerTree.data(index, FlatLayerTreeModel.MapLayerPointer) ? true : false

            QfButton {
              Layout.fillWidth: true
              text: qsTr("Wczytaj styl")
              font.pointSize: Theme.tinyFont.pointSize

              onClicked: {
                const ml = layerTree.data(index, FlatLayerTreeModel.MapLayerPointer);
                if (!ml)
                  return;
                styleFileMenu.entries = LayerUtils.availableStyleFiles(ml);
                if (styleFileMenu.entries.length === 0) {
                  displayToast(qsTr("Nie znaleziono plików .qml obok warstwy ani w folderze projektu"));
                  return;
                }
                styleFileMenu.popup();
              }
            }

            QfButton {
              Layout.fillWidth: true
              text: qsTr("Zapisz styl")
              font.pointSize: Theme.tinyFont.pointSize

              onClicked: {
                const ml = layerTree.data(index, FlatLayerTreeModel.MapLayerPointer);
                if (!ml)
                  return;
                platformUtilities.createDir(qgisProject.homePath, "styles");
                const target = qgisProject.homePath + "/styles/" + FileUtils.sanitizeFilePathPart(ml.name) + ".qml";
                const error = LayerUtils.saveStyleToFile(ml, target);
                displayToast(error === "" ? qsTr("Zapisano styl: %1").arg(FileUtils.fileName(target)) : error);
              }
            }
          }

          Menu {
            id: styleFileMenu

            property var entries: []

            width: 300
            font: Theme.defaultFont

            Repeater {
              model: styleFileMenu.entries

              delegate: MenuItem {
                required property var modelData

                text: modelData.name
                font: Theme.defaultFont

                onTriggered: {
                  const ml = layerTree.data(index, FlatLayerTreeModel.MapLayerPointer);
                  if (!ml)
                    return;
                  const error = LayerUtils.loadStyleFromFile(ml, modelData.path);
                  if (error === "") {
                    displayToast(qsTr("Wczytano styl: %1").arg(modelData.name));
                    projectInfo.saveLayerStyle(ml);
                    refresh();
                  } else {
                    displayToast(error);
                  }
                }
              }
            }
          }
        }


        Sekcja {
          id: sekcjaEtykiety
          nr: 2
          tytul: qsTr("Etykiety")
          stan: labelsOn ? (labelField !== "" ? qsTr("z pola %1").arg(labelField) : qsTr("włączone")) : qsTr("wyłączone")
          zakladki: ukladZakladki
          aktywna: ukladUstawienia.zakladka
          otwarta: ukladUstawienia.otwarteEtykiety
          dostepna: jestWektor
          jedyna: false
          onPrzelacz: ukladUstawienia.otwarteEtykiety = !ukladUstawienia.otwarteEtykiety
          CheckBox {
            id: itemLabelsVisibleCheckBox
            Layout.fillWidth: true
            topPadding: 5
            bottomPadding: 5
            text: qsTr('Show labels')
            font: QfTheme.defaultFont
            visible: index && layerTree.data(index, QfFlatLayerTreeModel.HasLabels) ? true : false
            indicator.height: 16
            indicator.width: 16
            indicator.implicitHeight: 24
            indicator.implicitWidth: 24

            onClicked: {
              layerTree.setData(index, checkState === Qt.Checked, QfFlatLayerTreeModel.LabelsVisible);
              projectInfo.saveLayerStyle(layerTree.data(index, QfFlatLayerTreeModel.MapLayerPointer));
            }
          }
          ColumnLayout {
            id: labelPanel

            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 4
            visible: index !== undefined && layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer) ? true : false

            function currentLayer() {
              return layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
            }

            function persist() {
              projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              spacing: 8

              Text {
                Layout.fillWidth: true
                text: qsTr("Etykiety z pola")
                font: Theme.strongTipFont
                color: Theme.mainTextColor
              }

              QfSwitch {
                checked: labelsOn
                onCheckedChanged: {
                  if (checked === labelsOn)
                    return;
                  const vl = labelPanel.currentLayer();
                  if (!vl)
                    return;
                  LayerUtils.setLabelsEnabled(vl, checked, labelField);
                  labelsOn = checked;
                  const ls = LayerUtils.labelSettings(vl);
                  labelField = ls.field !== undefined ? ls.field : "";
                  labelPanel.persist();
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 6
              visible: labelsOn

              Text {
                text: qsTr("Pole")
                font: Theme.defaultFont
                color: Theme.mainTextColor
              }

              ComboBox {
                Layout.fillWidth: true
                font: Theme.defaultFont
                model: availableFields.map(f => f.name)
                currentIndex: availableFields.findIndex(f => f.name === labelField)

                onActivated: idx => {
                  const vl = labelPanel.currentLayer();
                  if (!vl)
                    return;
                  labelField = availableFields[idx].name;
                  LayerUtils.setLabelField(vl, labelField);
                  labelPanel.persist();
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 6
              visible: labelsOn

              Text {
                text: qsTr("Rozmiar")
                font: Theme.defaultFont
                color: Theme.mainTextColor
              }

              QfSlider {
                Layout.fillWidth: true
                from: 6
                to: 30
                stepSize: 1
                value: labelSize
                suffixText: " pt"
                height: 40

                onMoved: function () {
                  const vl = labelPanel.currentLayer();
                  if (!vl)
                    return;
                  labelSize = value;
                  LayerUtils.setLabelSize(vl, value);
                  labelPanel.persist();
                }
              }
            }

            Text {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              visible: labelsOn
              text: qsTr("Kolor tekstu")
              font: Theme.tipFont
              color: Theme.secondaryTextColor
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 8
              visible: labelsOn

              Rectangle {
                width: 44
                height: 30
                radius: 4
                color: labelColor
                border.width: 1
                border.color: Theme.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: openColorPicker(qsTr("Kolor tekstu"), labelColor, function (chosen) {
                    const vl = labelPanel.currentLayer();
                    if (!vl)
                      return;
                    LayerUtils.setLabelColor(vl, chosen);
                    labelColor = chosen;
                    labelPanel.persist();
                  })
                }
              }

              Text {
                Layout.fillWidth: true
                text: qsTr("Dotknij, aby zmienić")
                font: Theme.tipFont
                color: Theme.secondaryTextColor
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 4
              spacing: 8
              visible: labelsOn

              Text {
                Layout.fillWidth: true
                text: qsTr("Otoczka")
                font: Theme.tipFont
                color: Theme.secondaryTextColor
              }

              QfSwitch {
                checked: labelBufferOn
                onCheckedChanged: {
                  if (checked === labelBufferOn)
                    return;
                  const vl = labelPanel.currentLayer();
                  if (!vl)
                    return;
                  LayerUtils.setLabelBuffer(vl, checked, labelBufferColor);
                  labelBufferOn = checked;
                  labelPanel.persist();
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 8
              visible: labelsOn && labelBufferOn

              Rectangle {
                width: 44
                height: 30
                radius: 4
                color: labelBufferColor
                border.width: 1
                border.color: Theme.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: openColorPicker(qsTr("Kolor otoczki"), labelBufferColor, function (chosen) {
                    const vl = labelPanel.currentLayer();
                    if (!vl)
                      return;
                    LayerUtils.setLabelBuffer(vl, true, chosen);
                    labelBufferColor = chosen;
                    labelPanel.persist();
                  })
                }
              }

              Text {
                Layout.fillWidth: true
                text: qsTr("Dotknij, aby zmienić")
                font: Theme.tipFont
                color: Theme.secondaryTextColor
              }
            }
          }
        }


        // WorkField 07.10.2026 [WF-PANEL-UKLAD] — wybór wyglądu panelu, zapamiętany.
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: 10
          spacing: 6
          visible: jestWektor

          Text {
            text: qsTr("Układ panelu:")
            font: Theme.tipFont
            color: Theme.secondaryTextColor
          }

          Repeater {
            model: [
              { "k": "zakladki", "n": qsTr("Zakładki") },
              { "k": "sekcje", "n": qsTr("Sekcje") }
            ]

            delegate: QfButton {
              required property var modelData
              Layout.fillWidth: true
              text: modelData.n
              font.pointSize: Theme.tinyFont.pointSize
              bgcolor: ukladUstawienia.uklad === modelData.k ? Theme.mainColor : Theme.controlBackgroundAlternateColor
              color: ukladUstawienia.uklad === modelData.k ? Theme.mainOverlayColor : Theme.mainTextColor
              onClicked: ukladUstawienia.uklad = modelData.k
            }
          }
        }

      }
    }
  }

  QfMenu {
    id: showFeaturesMenu
    title: qsTr("Show Features Menu")

    MenuItem {
      text: qsTr('Show visible features list')

      font: QfTheme.defaultFont
      height: 48
      leftPadding: QfTheme.menuItemLeftPadding

      onTriggered: {
        if (parseInt(layerTree.data(index, QfFlatLayerTreeModel.FeatureCount)) === 0) {
          displayToast(qsTr("The layer has no features"));
        } else {
          var vl = layerTree.data(index, QfFlatLayerTreeModel.VectorLayerPointer);
          var filter = layerTree.data(index, QfFlatLayerTreeModel.FilterExpression);
          featureListForm.model.setFeatures(vl, filter, mapCanvas.mapSettings.visibleExtent);
        }
        close();
        dashBoard.visible = false;
      }
    }
  }

  Connections {
    target: layerTree

    function onDataChanged(topleft, bottomright, roles) {
      if (index === undefined)
        return;
      if (roles.includes(QfFlatLayerTreeModel.FeatureCount)) {
        updateTitle();
      }
    }
  }

  /**
   * WorkField 6.10.2026 — ZMIANA NAZWY WARSTWY [WF-NAZWA-FUNKCJE].
   *
   * Zmienia nazwę warstwy w PROJEKCIE (to, co widać w legendzie).
   * Tabela w dane.gpkg zostaje, jak była. Okno samo niczego nie
   * zapisuje do projektu, więc zapis jest tu jawny — i jego wynik
   * idzie na ekran, bo zmiana bez zapisu znika po zamknięciu.
   */
  function zacznijZmianeNazwy() {
    const ml = index !== undefined ? layerTree.data(index, QfFlatLayerTreeModel.MapLayerPointer) : null;
    if (!ml)
      return;
    edycjaNazwy.text = String(ml.name);
    edycjaNazwy.visible = true;
    edycjaNazwy.forceActiveFocus();
    edycjaNazwy.selectAll();
  }

  function zatwierdzNazwe() {
    const ml = index !== undefined ? layerTree.data(index, QfFlatLayerTreeModel.MapLayerPointer) : null;
    const nowa = edycjaNazwy.text.trim();
    edycjaNazwy.visible = false;
    if (!ml || nowa === "" || nowa === String(ml.name))
      return;
    ml.name = nowa;
    if (String(ml.name) !== nowa) {
      displayToast(qsTr("Nie udało się zmienić nazwy warstwy"), "error");
      return;
    }
    updateTitle();
    const zapisano = typeof ProjectUtils !== "undefined" && ProjectUtils.saveProject(qgisProject);
    if (zapisano)
      displayToast(qsTr("Nowa nazwa: %1 — projekt zapisany").arg(nowa));
    else
      displayToast(qsTr("Nazwa zmieniona, ale projektu NIE zapisano — zniknie po zamknięciu"), "error");
  }

  // WorkField 6.10.2026 [WF-DUPLIKAT-JS] — duplikat warstwy.
  function otworzDuplikat() {
    const tabela = zrodloDanych.opis ? String(zrodloDanych.opis.warstwa) : "";
    nazwaDuplikatu.text = tabela !== "" ? tabela + "_kopia" : "";
    zObiektamiBox.checked = false;
    panelDuplikatu.visible = true;
    nazwaDuplikatu.forceActiveFocus();
    nazwaDuplikatu.selectAll();
  }

  function bladNazwyDuplikatu(n) {
    if (n === "")
      return qsTr("Podaj nazwę tabeli.");
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(n))
      return qsTr("Tylko litery bez polskich znaków, cyfry i _. Bez spacji, nie od cyfry.");
    return "";
  }

  function duplikuj() {
    const vl = index !== undefined ? layerTree.data(index, QfFlatLayerTreeModel.VectorLayerPointer) : null;
    const n = nazwaDuplikatu.text.trim();
    if (!vl || bladNazwyDuplikatu(n) !== "")
      return;
    const w = NarzedziaProjektu.duplikujWarstwe(qgisProject, vl, n, zObiektamiBox.checked);
    if (!w.ok) {
      displayToast(w.blad || qsTr("Nie udało się zduplikować warstwy"), "error");
      return;
    }
    panelDuplikatu.visible = false;
    const zapisano = typeof ProjectUtils !== "undefined" && ProjectUtils.saveProject(qgisProject);
    if (zapisano)
      displayToast(qsTr("Nowa warstwa %1 — obiektów: %2. Projekt zapisany.").arg(n).arg(w.obiektow));
    else
      displayToast(qsTr("Nowa warstwa %1 jest, ale projektu NIE zapisano — zniknie po zamknięciu").arg(n), "error");
  }

  /**
   * WorkField 07.10.2026 [WF-STYL-STAN] — stan panelu stylizacji z warstwy.
   *
   * Ten blok był w onIndexChanged (commit 9873d579a) i wypadł przy przenosinach
   * na strukturę upstreamu. Bez niego lista pól była pusta, więc „Kategorie”
   * i „Przedziały” nie dawały się włączyć, kolory i widoczność kategorii nie
   * miały warstwy docelowej, a etykiety nie pokazywały stanu warstwy.
   */
  function wczytajStanStylu() {
    if (index === undefined)
      return;
    const styleLayer = layerTree.data(index, QfFlatLayerTreeModel.VectorLayerPointer);
    symbologyVisible = styleLayer ? LayerUtils.hasSimpleSymbology(styleLayer) : false;
    categoriesVisible = styleLayer ? LayerUtils.hasCategorizedSymbology(styleLayer) : false;
    categoryEntries = categoriesVisible ? LayerUtils.rendererCategories(styleLayer) : [];
    styleTargetLayer = styleLayer;
    styleTargetMapLayer = layerTree.data(index, QfFlatLayerTreeModel.MapLayerPointer);
    availableFields = styleLayer ? LayerUtils.layerFields(styleLayer) : [];
    pendingField = "";
    fieldCombo.currentIndex = -1;
    trybWidoku = categoriesVisible ? "categorized" : (symbologyVisible ? "single" : "other");
    edycjaStylow = false;
    dodawanieStylu = false;
    odswiezListeStylow();

    if (styleLayer) {
      const ls = LayerUtils.labelSettings(styleLayer);
      labelsOn = ls.enabled === true;
      labelField = ls.field !== undefined ? ls.field : "";
      labelSize = ls.size > 0 ? ls.size : 10;
      labelColor = ls.color !== undefined ? ls.color : "black";
      labelBufferOn = ls.bufferEnabled === true;
      labelBufferColor = ls.bufferColor !== undefined ? ls.bufferColor : "white";
      vertexCfg = LayerUtils.vertexMarkerConfig(styleLayer);
    }
    if (symbologyVisible) {
      symbolKind = LayerUtils.symbolType(styleLayer);
      symbolSizeSlider.value = Math.max(0, LayerUtils.symbolSize(styleLayer));
      strokeWidthValue = Math.max(0, LayerUtils.strokeWidth(styleLayer));
      fillPalette.currentColor = LayerUtils.fillColor(styleLayer);
      strokePalette.currentColor = LayerUtils.strokeColor(styleLayer);
      currentStrokeStyle = LayerUtils.strokeStyle(styleLayer);
      // markerShape: gdyby getter zniknął z C++, panel ma działać dalej
      if (typeof LayerUtils.markerShape === "function")
        currentMarkerShape = LayerUtils.markerShape(styleLayer);
    }
  }

  //! WorkField 07.10.2026 [WF-STYL-STAN] — wołane po „Wczytaj styl”; wcześniej
  //! nie istniało i wczytanie stylu kończyło się błędem w logu.
  function refresh() {
    wczytajStanStylu();
  }

  function updateTitle() {
    if (index === undefined)
      return;
    const type = layerTree.data(index, QfFlatLayerTreeModel.Type);
    const vl = layerTree.data(index, QfFlatLayerTreeModel.VectorLayerPointer);
    let title = layerTree.data(index, Qt.Name);
    if (vl) {
      if (type === QfFlatLayerTreeModel.Legend) {
        title += ' (' + vl.name + ')';
      } else if (type === QfFlatLayerTreeModel.Layer && layerTree.data(index, QfFlatLayerTreeModel.IsValid)) {
        var count = layerTree.data(index, QfFlatLayerTreeModel.FeatureCount);
        if (count !== undefined && count >= 0) {
          var countSuffix = ' [' + count + ']';
          if (!title.endsWith(countSuffix))
            title += countSuffix;
        }
      }
    }
    titleLabel.text = title !== undefined ? title : "";
  }

  function updateCredits() {
    var credits = '';
    if (index !== undefined) {
      credits = QfStringUtils.insertLinks(layerTree.data(index, QfFlatLayerTreeModel.Credits));
    } else {
      credits = '';
    }
    creditsText.text = credits;
    creditsText.visible = credits !== '';
  }

  function isTrackingButtonVisible() {
    if (!index)
      return false;
    return layerTree.data(index, QfFlatLayerTreeModel.Type) === QfFlatLayerTreeModel.Layer && !layerTree.data(index, QfFlatLayerTreeModel.ReadOnly) && layerTree.data(index, QfFlatLayerTreeModel.Trackable);
  }

  function isShowFeaturesListButtonVisible() {
    return layerTree.data(index, QfFlatLayerTreeModel.IsValid) && layerTree.data(index, QfFlatLayerTreeModel.LayerType) === 'vectorlayer';
  }

  function isShowVisibleFeaturesListDropdownVisible() {
    return isShowFeaturesListButtonVisible() && layerTree.data(index, QfFlatLayerTreeModel.HasSpatialExtent);
  }
}
