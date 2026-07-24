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
  property var availableFields: []
  property bool labelsOn: false
  property string labelField: ""
  property real labelSize: 10
  property color labelColor: "black"
  property bool labelBufferOn: true
  property color labelBufferColor: "white"
  property string pendingField: ""
  property int pendingClassCount: 5

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
    opacitySliderVisible = layerTree.data(index, FlatLayerTreeModel.Opacity) > -1;
    const styleLayer = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
    symbologyVisible = styleLayer ? LayerUtils.hasSimpleSymbology(styleLayer) : false;
    categoriesVisible = styleLayer ? LayerUtils.hasCategorizedSymbology(styleLayer) : false;
    categoryEntries = categoriesVisible ? LayerUtils.rendererCategories(styleLayer) : [];
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
      strokeWidthSlider.value = Math.max(0, LayerUtils.strokeWidth(styleLayer));
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
        topPadding: 10
        bottomPadding: 10
        text: ''
        font: Theme.strongFont
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WrapAnywhere
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
          bottomPadding: 15

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
              LayerUtils.setCategorizedRenderer(vl, pendingField);
            } else if (mode === "graduated") {
              if (pendingField === "")
                return;
              LayerUtils.setGraduatedRenderer(vl, pendingField, pendingClassCount);
            }
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
        }

        ColumnLayout {
          id: symbologyPanel

          Layout.fillWidth: true
          Layout.topMargin: 4
          Layout.bottomMargin: 4
          spacing: 6
          visible: symbologyVisible

          component SectionLabel: Text {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.topMargin: 6
            font: Theme.strongTipFont
            color: Theme.mainTextColor
          }

          component ColorGrid: Flow {
            id: grid
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 6

            property color currentColor: "transparent"
            signal picked(color chosen)

            readonly property var swatches: ["#e53935", "#d81b60", "#8e24aa", "#3949ab", "#1e88e5", "#00897b", "#43a047", "#c0ca33", "#fdd835", "#fb8c00", "#6d4c41", "#212121", "#ffffff"]

            Repeater {
              model: grid.swatches

              delegate: Rectangle {
                required property string modelData

                width: 30
                height: 30
                radius: 4
                color: modelData
                border.width: Qt.colorEqual(grid.currentColor, modelData) ? 3 : 1
                border.color: Qt.colorEqual(grid.currentColor, modelData) ? Theme.mainColor : Theme.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: grid.picked(parent.modelData)
                }
              }
            }
          }

          SectionLabel {
            text: symbolKind === 1 ? qsTr("Kolor linii") : qsTr("Wypełnienie")
          }

          ColorGrid {
            id: fillPalette
            onPicked: chosen => {
              const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
              if (!vl)
                return;
              LayerUtils.setFillColor(vl, chosen);
              fillPalette.currentColor = chosen;
              projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
            }
          }

          SectionLabel {
            visible: symbolKind !== 1
            text: qsTr("Kontur")
          }

          ColorGrid {
            id: strokePalette
            visible: symbolKind !== 1
            onPicked: chosen => {
              const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
              if (!vl)
                return;
              LayerUtils.setStrokeColor(vl, chosen);
              strokePalette.currentColor = chosen;
              projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 6
            visible: strokeWidthSlider.value >= 0

            Text {
              text: qsTr("Grubość")
              font: Theme.defaultFont
              color: Theme.mainTextColor
            }

            QfSlider {
              id: strokeWidthSlider
              Layout.fillWidth: true
              from: 0
              to: 5
              stepSize: 0.1
              suffixText: " mm"
              height: 40

              onMoved: function () {
                const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                if (!vl)
                  return;
                LayerUtils.setStrokeWidth(vl, value);
                projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
              }
            }
          }

          SectionLabel {
            text: qsTr("Styl linii")
          }

          Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            spacing: 6

            Repeater {
              model: [
                {
                  "s": 1,
                  "n": qsTr("Ciągła")
                },
                {
                  "s": 2,
                  "n": qsTr("Kreskowana")
                },
                {
                  "s": 3,
                  "n": qsTr("Kropkowana")
                },
                {
                  "s": 4,
                  "n": qsTr("Kreska-kropka")
                }
              ]

              delegate: QfButton {
                required property var modelData

                text: modelData.n
                font.pointSize: Theme.tinyFont.pointSize
                bgcolor: currentStrokeStyle === modelData.s ? Theme.mainColor : Theme.controlBackgroundAlternateColor
                color: currentStrokeStyle === modelData.s ? Theme.mainOverlayColor : Theme.mainTextColor

                onClicked: {
                  const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  if (!vl)
                    return;
                  LayerUtils.setStrokeStyle(vl, modelData.s);
                  currentStrokeStyle = modelData.s;
                  projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                }
              }
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
                    onClicked: categoryList.editingIndex = categoryList.editingIndex === index ? -1 : index
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
                  iconSource: Theme.getThemeVectorIcon(modelData.visible ? "WŁAŚCIWA_NAZWA" : "WŁAŚCIWA_NAZWA_2")
                  iconColor: Theme.mainTextColor

                  onClicked: {
                    const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  }
                }
              }

              Flow {
                width: parent.width - 16
                x: 8
                spacing: 5
                bottomPadding: 6
                visible: categoryList.editingIndex === index

                readonly property var swatches: ["#e53935", "#d81b60", "#8e24aa", "#3949ab", "#1e88e5", "#00897b", "#43a047", "#c0ca33", "#fdd835", "#fb8c00", "#6d4c41", "#212121", "#ffffff"]

                Repeater {
                  model: parent.swatches

                  delegate: Rectangle {
                    required property string modelData

                    width: 26
                    height: 26
                    radius: 4
                    color: modelData
                    border.width: 1
                    border.color: Theme.controlBorderColor

                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                        if (!vl)
                          return;
                        LayerUtils.setCategoryColor(vl, categoryList.editingIndex, parent.modelData);
                        categoryEntries = LayerUtils.rendererCategories(vl);
                        categoryList.editingIndex = -1;
                        projectInfo.saveLayerStyle(layerTree.data(index, FlatLayerTreeModel.MapLayerPointer));
                      }
                    }
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

          Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 5
            visible: labelsOn

            readonly property var swatches: ["#212121", "#ffffff", "#e53935", "#1e88e5", "#00897b", "#fb8c00", "#8e24aa", "#43a047"]

            Repeater {
              model: parent.swatches

              delegate: Rectangle {
                required property string modelData

                width: 28
                height: 28
                radius: 4
                color: modelData
                border.width: Qt.colorEqual(labelColor, modelData) ? 3 : 1
                border.color: Qt.colorEqual(labelColor, modelData) ? Theme.mainColor : Theme.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    const vl = labelPanel.currentLayer();
                    if (!vl)
                      return;
                    LayerUtils.setLabelColor(vl, parent.modelData);
                    labelColor = parent.modelData;
                    labelPanel.persist();
                  }
                }
              }
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

          Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 5
            visible: labelsOn && labelBufferOn

            readonly property var swatches: ["#ffffff", "#212121", "#fdd835", "#e0f2ef"]

            Repeater {
              model: parent.swatches

              delegate: Rectangle {
                required property string modelData

                width: 28
                height: 28
                radius: 4
                color: modelData
                border.width: Qt.colorEqual(labelBufferColor, modelData) ? 3 : 1
                border.color: Qt.colorEqual(labelBufferColor, modelData) ? Theme.mainColor : Theme.controlBorderColor

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    const vl = labelPanel.currentLayer();
                    if (!vl)
                      return;
                    LayerUtils.setLabelBuffer(vl, true, parent.modelData);
                    labelBufferColor = parent.modelData;
                    labelPanel.persist();
                  }
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
              return qsTr('Read-only layer');
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
