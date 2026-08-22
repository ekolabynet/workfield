import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qgis
import org.qfield
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
  height: Math.min(popupLayout.childrenRect.height + headerLayout.childrenRect.height + 20, mainWindow.height - Math.max(Theme.popupScreenEdgeVerticalMargin * 2, mainWindow.sceneTopMargin * 2 + 4, mainWindow.sceneBottomMargin * 2 + 4))
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  focus: visible

  onClosed: {
    index = undefined;
  }

  onIndexChanged: {
    if (index === undefined)
      return;
    updateTitle();
    updateCredits();
    itemVisibleCheckBox.checked = layerTree.data(index, FlatLayerTreeModel.Visible);
    itemLabelsVisibleCheckBox.checked = layerTree.data(index, FlatLayerTreeModel.LabelsVisible);
    expandCheckBox.text = layerTree.data(index, FlatLayerTreeModel.Type) === FlatLayerTreeModel.Group ? qsTr('Expand group') : qsTr('Expand legend item');
    expandCheckBox.checked = !layerTree.data(index, FlatLayerTreeModel.IsCollapsed);
    reloadDataButtonVisible = layerTree.data(index, FlatLayerTreeModel.CanReloadData);
    zoomToButtonVisible = layerTree.data(index, FlatLayerTreeModel.HasSpatialExtent);
    showFeaturesListButtonVisible = isShowFeaturesListButtonVisible();
    showVisibleFeaturesListDropdownVisible = isShowVisibleFeaturesListDropdownVisible();
    trackingButtonVisible = isTrackingButtonVisible();
    trackingButtonText = trackingModel.layerInActiveTracking(layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer)) ? qsTr('Stop tracking') : qsTr('Setup tracking');

    // the layer tree model returns -1 for items that do not support the opacity setting
    opacitySliderVisible = layerTree.data(index, FlatLayerTreeModel.Opacity) > -1 && !LayerUtils.hasSimpleSymbology(layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer));
    const styleLayer = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
    symbologyVisible = styleLayer ? LayerUtils.hasSimpleSymbology(styleLayer) : false;
    categoriesVisible = styleLayer ? LayerUtils.hasCategorizedSymbology(styleLayer) : false;
    categoryEntries = categoriesVisible ? LayerUtils.rendererCategories(styleLayer) : [];
    styleTargetLayer = styleLayer;
    styleTargetMapLayer = layerTree.data(index, FlatLayerTreeModel.MapLayerPointer);
    availableFields = styleLayer ? LayerUtils.layerFields(styleLayer) : [];

    if (styleLayer) {
      const ls = LayerUtils.labelSettings(styleLayer);
      labelsOn = ls.enabled === true;
      labelField = ls.field !== undefined ? ls.field : "";
      labelSize = ls.size > 0 ? ls.size : 10;
      labelColor = ls.color !== undefined ? ls.color : "black";
      labelBufferOn = ls.bufferEnabled === true;
      labelBufferColor = ls.bufferColor !== undefined ? ls.bufferColor : "white";
    }
    pendingField = "";
    if (symbologyVisible) {
      symbolKind = LayerUtils.symbolType(styleLayer);
      symbolSizeSlider.value = Math.max(0, LayerUtils.symbolSize(styleLayer));
      strokeWidthValue = Math.max(0, LayerUtils.strokeWidth(styleLayer));
      fillPalette.currentColor = LayerUtils.fillColor(styleLayer);
      strokePalette.currentColor = LayerUtils.strokeColor(styleLayer);
      currentStrokeStyle = LayerUtils.strokeStyle(styleLayer);
      currentMarkerShape = LayerUtils.markerShape(styleLayer);
    }
  }

  Page {
    id: popupContent
    width: parent.width
    height: parent.height
    padding: 0
    header: RowLayout {
      id: headerLayout
      spacing: 2

      Label {
        id: titleLabel
        Layout.fillWidth: true
        Layout.leftMargin: reloadDataButtonVisible ? zoomInButton.width + headerLayout.spacing : 0
        topPadding: 6
        bottomPadding: 6
        text: ''
        font: Theme.strongFont
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
        maximumLineCount: 1
      }
      QfToolButton {
        id: zoomInButton
        Layout.alignment: Qt.AlignTop
        Layout.rightMargin: 0
        round: true
        visible: reloadDataButtonVisible

        bgcolor: "transparent"
        iconSource: Theme.getThemeVectorIcon('refresh_24dp')
        iconColor: Theme.mainTextColor

        onClicked: {
          layerTree.data(index, FlatLayerTreeModel.MapLayerPointer).reload();
          close();
          dashBoard.visible = false;
          displayToast(qsTr('Reload of layer %1 triggered').arg(layerTree.data(index, Qt.DisplayName)));
        }
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
          font: Theme.tipFont
          color: Theme.errorColor
        }

        CheckBox {
          id: expandCheckBox
          Layout.fillWidth: true
          topPadding: 5
          bottomPadding: 5
          text: qsTr('Expand legend item')
          font: Theme.defaultFont
          visible: index && layerTree.data(index, FlatLayerTreeModel.HasChildren) ? true : false

          onClicked: {
            layerTree.setData(index, checkState === Qt.Unchecked, FlatLayerTreeModel.IsCollapsed);
            close();
          }
        }

        CheckBox {
          id: itemVisibleCheckBox
          Layout.fillWidth: true
          topPadding: 5
          bottomPadding: 5
          text: qsTr('Show on map')
          font: Theme.defaultFont
          // visible for all layer tree items but nonspatial layers
          visible: index && layerTree.data(index, FlatLayerTreeModel.Checkable) && layerTree.data(index, FlatLayerTreeModel.HasSpatialExtent) ? true : false
          indicator.height: 16
          indicator.width: 16
          indicator.implicitHeight: 24
          indicator.implicitWidth: 24

          onClicked: {
            layerTree.setData(index, checkState === Qt.Checked, FlatLayerTreeModel.Visible);
            flatLayerTree.mapTheme = '';
            projectInfo.saveLayerTreeState();
            close();
          }
        }

        CheckBox {
          id: itemLabelsVisibleCheckBox
          Layout.fillWidth: true
          topPadding: 5
          bottomPadding: 5
          text: qsTr('Show labels')
          font: Theme.defaultFont
          visible: index && layerTree.data(index, FlatLayerTreeModel.HasLabels) ? true : false
          indicator.height: 16
          indicator.width: 16
          indicator.implicitHeight: 24
          indicator.implicitWidth: 24

          onClicked: {
            layerTree.setData(index, checkState === Qt.Checked, FlatLayerTreeModel.LabelsVisible);
            projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
            close();
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

            icon.source: Theme.getThemeVectorIcon("ic_opacity_black_24dp")
            icon.color: Theme.mainTextColor
          }

          Text {
            Layout.alignment: Qt.AlignVCenter
            text: qsTr("Opacity")
            font: Theme.defaultFont
            color: Theme.mainTextColor
          }

          QfSlider {
            id: slider
            Layout.fillWidth: true
            Layout.rightMargin: 5
            Layout.alignment: Qt.AlignVCenter
            value: index !== undefined ? layerTree.data(index, FlatLayerTreeModel.Opacity) * 100 : 0
            from: 0
            to: 100
            stepSize: 1
            suffixText: " %"
            height: 40

            onMoved: function () {
              layerTree.setData(index, value / 100, FlatLayerTreeModel.Opacity);
              projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
            }
          }
        }

        ColumnLayout {
          id: rendererModeRow

          Layout.fillWidth: true
          Layout.topMargin: 6
          spacing: 4
          visible: index !== undefined && layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer) ? true : false

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
            projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
          }

          Text {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: qsTr("Sposób wyświetlania")
            font: Theme.strongTipFont
            color: Theme.mainTextColor
          }

          Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            spacing: 6

            QfButton {
              text: qsTr("Pojedynczy")
              font.pointSize: Theme.tinyFont.pointSize
              bgcolor: symbologyVisible ? Theme.mainColor : Theme.controlBackgroundAlternateColor
              color: symbologyVisible ? Theme.mainOverlayColor : Theme.mainTextColor
              onClicked: rendererModeRow.applyMode("single")
            }

            QfButton {
              text: qsTr("Kategorie")
              font.pointSize: Theme.tinyFont.pointSize
              bgcolor: categoriesVisible ? Theme.mainColor : Theme.controlBackgroundAlternateColor
              color: categoriesVisible ? Theme.mainOverlayColor : Theme.mainTextColor
              enabled: pendingField !== ""
              onClicked: rendererModeRow.applyMode("categorized")
            }

            QfButton {
              text: qsTr("Przedziały")
              font.pointSize: Theme.tinyFont.pointSize
              bgcolor: Theme.controlBackgroundAlternateColor
              color: Theme.mainTextColor
              enabled: pendingField !== "" && fieldCombo.currentNumeric
              onClicked: rendererModeRow.applyMode("graduated")
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 4
            spacing: 6

            Text {
              text: qsTr("Pole")
              font: Theme.defaultFont
              color: Theme.mainTextColor
            }

            ComboBox {
              id: fieldCombo

              Layout.fillWidth: true
              font: Theme.defaultFont
              model: availableFields.map(f => f.name)
              currentIndex: -1
              displayText: currentIndex < 0 ? qsTr("wybierz…") : currentText

              readonly property bool currentNumeric: currentIndex >= 0 && currentIndex < availableFields.length ? availableFields[currentIndex].numeric : false

              onActivated: pendingField = availableFields[currentIndex].name
            }

            SpinBox {
              Layout.preferredWidth: 96
              visible: fieldCombo.currentNumeric
              from: 2
              to: 12
              value: pendingClassCount
              font: Theme.defaultFont
              onValueChanged: pendingClassCount = value
            }
          }

          // WorkField 19.08.2026: wybor rampy kolorow. Rampa jest AUTOMATEM —
          // daje sensowny start przy kilkudziesieciu kategoriach; pojedyncze
          // kategorie poprawia sie potem paleta Materialize.
          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 4
            spacing: 6
            visible: categoriesVisible || fieldCombo.currentNumeric

            Text {
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
                  color: Theme.mainTextColor
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

          // WorkField 19.08.2026: warstwy symbolu. Znacznik stanu i wierzchołki
          // to jeden byt w dwóch wariantach — dokładane DO symbolu warstwy,
          // więc kolorowanie kategorii zostaje nietknięte.
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

          // pasek podgladu wybranej rampy
          Row {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            visible: rampCombo.visible
            spacing: 0

            Repeater {
              model: LayerUtils.colorRampPreview(pendingRamp, 24)

              delegate: Rectangle {
                required property var modelData
                width: (rampCombo.width) / 24
                height: 10
                color: modelData
              }
            }
          }
        }

        ColumnLayout {
          id: symbologyPanel

          Layout.fillWidth: true
          Layout.topMargin: 4
          Layout.bottomMargin: 4
          spacing: 6
          visible: symbologyVisible

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
                  text: modelData.label
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
                  iconSource: Theme.getThemeVectorIcon(modelData.visible ? "ic_eye_black_24dp" : "ic_eye_off_black_24dp")
                  iconColor: modelData.visible ? Theme.mainTextColor : Theme.mainTextDisabledColor

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
              text: qsTr("Etykiety")
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

        QfButton {
          id: doneButton
          Layout.fillWidth: true
          Layout.topMargin: 5
          text: qsTr("Gotowe")
          icon.source: Theme.getThemeVectorIcon("ic_check_white_24dp")
          onClicked: close()
        }

        QfButton {
          id: zoomToButton
          Layout.fillWidth: true
          Layout.topMargin: 5
          text: index ? layerTree.data(index, FlatLayerTreeModel.Type) === FlatLayerTreeModel.Group ? qsTr('Zoom to group') : layerTree.data(index, FlatLayerTreeModel.Type) === FlatLayerTreeModel.Legend && layerTree.data(index, FlatLayerTreeModel.LayerType) === "vectorlayer" ? qsTr('Zoom to parent layer') : qsTr('Zoom to layer') : ''
          visible: zoomToButtonVisible
          icon.source: Theme.getThemeVectorIcon('zoom_out_map_24dp')

          onClicked: {
            mapCanvas.mapSettings.extent = layerTree.nodeExtent(index, mapCanvas.mapSettings);
            close();
            dashBoard.visible = false;
          }
        }

        QfButton {
          id: showFeaturesList
          Layout.fillWidth: true
          Layout.topMargin: 5
          dropdown: showVisibleFeaturesListDropdownVisible
          text: qsTr('Show features list')
          visible: showFeaturesListButtonVisible
          icon.source: Theme.getThemeVectorIcon('ic_list_black_24dp')

          onClicked: {
            if (parseInt(layerTree.data(index, FlatLayerTreeModel.FeatureCount)) === 0) {
              displayToast(qsTr("The layer has no features"));
            } else {
              var vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
              var filter = layerTree.data(index, FlatLayerTreeModel.FilterExpression);
              featureListForm.model.setFeatures(vl, filter);
              if (layerTree.data(index, FlatLayerTreeModel.HasSpatialExtent)) {
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

        QfButton {
          id: trackingButton
          Layout.fillWidth: true
          Layout.topMargin: 5
          text: trackingButtonText
          visible: trackingButtonVisible
          icon.source: Theme.getThemeVectorIcon('directions_walk_24dp')

          onClicked: {
            const layer = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
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

        Text {
          id: lockText

          property var padlockIcon: Theme.getThemeVectorIcon('ic_lock_black_24dp')
          property real padlockSize: fontMetrics.height - 5

          property bool isReadOnly: index !== undefined && layerTree.data(index, FlatLayerTreeModel.ReadOnly)
          property bool isFeatureAdditionLocked: index !== undefined && layerTree.data(index, FlatLayerTreeModel.FeatureAdditionLocked)
          property bool isAttributeEditingLocked: index !== undefined && layerTree.data(index, FlatLayerTreeModel.AttributeEditingLocked)
          property bool isGeometryEditingLocked: index !== undefined && layerTree.data(index, FlatLayerTreeModel.GeometryEditingLocked)
          property bool isFeatureDeletionLocked: index !== undefined && layerTree.data(index, FlatLayerTreeModel.FeatureDeletionLocked)

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
          font: Theme.tipFont
          color: Theme.secondaryTextColor
        }

        Text {
          id: creditsText
          Layout.fillWidth: true
          Layout.topMargin: 5
          wrapMode: Text.WordWrap
          textFormat: Text.RichText
          text: ''
          font.pointSize: Theme.tipFont.pointSize
          font.italic: true
          color: Theme.secondaryTextColor

          onLinkActivated: link => {
            Qt.openUrlExternally(link);
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

      font: Theme.defaultFont
      height: 48
      leftPadding: Theme.menuItemLeftPadding

      onTriggered: {
        if (parseInt(layerTree.data(index, FlatLayerTreeModel.FeatureCount)) === 0) {
          displayToast(qsTr("The layer has no features"));
        } else {
          var vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
          var filter = layerTree.data(index, FlatLayerTreeModel.FilterExpression);
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
      if (roles.includes(FlatLayerTreeModel.FeatureCount)) {
        updateTitle();
      }
    }
  }

  function updateTitle() {
    if (index === undefined)
      return;
    const type = layerTree.data(index, FlatLayerTreeModel.Type);
    const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
    let title = layerTree.data(index, Qt.Name);
    if (vl) {
      if (type === FlatLayerTreeModel.Legend) {
        title += ' (' + vl.name + ')';
      } else if (type === FlatLayerTreeModel.Layer && layerTree.data(index, FlatLayerTreeModel.IsValid)) {
        var count = layerTree.data(index, FlatLayerTreeModel.FeatureCount);
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
      credits = StringUtils.insertLinks(layerTree.data(index, FlatLayerTreeModel.Credits));
    } else {
      credits = '';
    }
    creditsText.text = credits;
    creditsText.visible = credits !== '';
  }

  function isTrackingButtonVisible() {
    if (!index)
      return false;
    return layerTree.data(index, FlatLayerTreeModel.Type) === FlatLayerTreeModel.Layer && !layerTree.data(index, FlatLayerTreeModel.ReadOnly) && layerTree.data(index, FlatLayerTreeModel.Trackable);
  }

  function isShowFeaturesListButtonVisible() {
    return layerTree.data(index, FlatLayerTreeModel.IsValid) && layerTree.data(index, FlatLayerTreeModel.LayerType) === 'vectorlayer';
  }

  function isShowVisibleFeaturesListDropdownVisible() {
    return isShowFeaturesListButtonVisible() && layerTree.data(index, FlatLayerTreeModel.HasSpatialExtent);
  }
}
