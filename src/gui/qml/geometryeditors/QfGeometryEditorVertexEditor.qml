import QtQuick
import org.qgis
import org.qfield.core
import org.qfield.gui

QfGeometryEditorBase {
  id: vertexEditorToolbar

  property bool screenHovering: false //<! if the stylus pen is used, one should not use the add button
  property bool vertexRubberbandVisible: true
  property int currentVertexId: -1
  property bool currentVertexModified: false

  readonly property bool blocking: featureModel ? featureModel.vertexModel.dirty : false

  spacing: 4

  // WorkField: haptyka o regulowanej sile (Teren -> Wibracje); 0 = wylaczona
  function haptyka(baza) {
    const sila = typeof settings !== 'undefined' ? settings.valueInt('WorkField/haptykaSila', 3) : 3;
    if (sila > 0 && typeof platformUtilities !== 'undefined') {
      platformUtilities.vibrate(baza * sila);
    }
  }

  function init(featureModel, mapSettings, editorRubberbandModel, editorRenderer) {
    featureModel.vertexModel.currentVertexIndex = -1;
    vertexEditorToolbar.featureModel = featureModel;
    vertexEditorToolbar.mapSettings = mapSettings;
    digitizingLogger.digitizingLayer = featureModel.currentLayer;
  }

  function cancel() {
    featureModel.vertexModel.editingMode = QfVertexModel.NoEditing;
    featureModel.vertexModel.reset();
  }

  function applyChanges(apply) {
    if (apply && featureModel.vertexModel.dirty) {
      featureModel.applyGeometry(true);
      if (!featureModel.save()) {
        displayToast(qsTr("Failed to save feature!"), 'error');
      }

      //set the vertexModel original geometry to the one of the updated feature
      featureModel.vertexModel.updateGeometry(featureModel.feature.geometry);
    }
  }

  function canvasClicked(point, type) {
    if (type === "stylus") {
      if (featureModel.vertexModel.currentVertexIndex == -1)
        featureModel.vertexModel.selectVertexAtPosition(point, 14);
      else {
        digitizingLogger.addCoordinate(featureModel.vertexModel.currentPoint);
        featureModel.vertexModel.currentVertexIndex = -1;
        vertexEditorToolbar.currentVertexModified = false;
      }
    } else {
      featureModel.vertexModel.selectVertexAtPosition(point, 14, false);
    }
    return true;
  }

  QfToolButton {
    id: undoButton
    iconSource: QfTheme.getThemeVectorIcon("ic_undo_black_24dp")
    iconColor: QfTheme.toolButtonColor
    round: true
    visible: featureModel && featureModel.vertexModel.canUndo
    bgcolor: QfTheme.toolButtonBackgroundColor
    onClicked: {
      // WorkField: średni impuls — cofnięcie
      haptyka(30);
      featureModel.vertexModel.undoHistory();
      mapSettings.setCenter(featureModel.vertexModel.currentPoint, true);
    }
  }

  QfToolButton {
    id: cancelButton
    objectName: "vertexEditorCancelButton"
    iconSource: QfTheme.getThemeVectorIcon("ic_clear_white_24dp")
    round: true
    visible: featureModel && featureModel.vertexModel.dirty && !qfieldSettings.autoSave
    bgcolor: QfTheme.darkRed
    onClicked: {
      // WorkField: średni impuls — anulowanie zmian
      haptyka(30);
      digitizingLogger.clearCoordinates();
      cancel();
      finished();
    }
  }

  QfToolButton {
    id: applyButton
    objectName: "vertexEditorApplyButton"
    iconSource: QfTheme.getThemeVectorIcon("ic_check_white_24dp")
    iconColor: QfTheme.toolButtonColor
    round: true
    visible: featureModel && featureModel.vertexModel.dirty
    bgcolor: !qfieldSettings.autoSave ? QfTheme.mainColor : QfTheme.toolButtonBackgroundColor

    onClicked: {
      // WorkField: długi impuls — zmiany zapisane
      haptyka(80);
      if (vertexEditorToolbar.currentVertexModified) {
        digitizingLogger.addCoordinate(featureModel.vertexModel.currentPoint);
      }
      digitizingLogger.writeCoordinates();
      applyChanges(true);
      finished();
    }
  }

  QfToolButton {
    id: removeVertexButton
    objectName: "vertexEditorRemoveVertexButton"
    iconSource: QfTheme.getThemeVectorIcon("ic_remove_white_24dp")
    iconColor: QfTheme.toolButtonColor
    round: true
    visible: featureModel && featureModel.vertexModel.canRemoveVertex
    bgcolor: QfTheme.toolButtonBackgroundColor

    onClicked: {
      // WorkField: dłuższy impuls — usunięcie wierzchołka
      haptyka(45);
      if (featureModel.vertexModel.canRemoveVertex) {
        featureModel.vertexModel.removeCurrentVertex();
        if (screenHovering) {
          featureModel.vertexModel.currentVertexIndex = -1;
        }
      }
      applyChanges(qfieldSettings.autoSave);
    }
  }

  QfToolButton {
    id: addVertexButton
    round: true
    enabled: !screenHovering && featureModel && featureModel.vertexModel.canAddVertex && featureModel.vertexModel.editingMode !== QfVertexModel.AddVertex
    bgcolor: enabled ? QfTheme.darkGray : QfTheme.darkGraySemiOpaque
    iconSource: QfTheme.getThemeVectorIcon("ic_add_white_24dp")
    iconColor: enabled ? QfTheme.toolButtonColor : QfTheme.toolButtonBackgroundSemiOpaqueColor

    onClicked: {
      // WorkField: krótki impuls — dodawanie wierzchołka
      haptyka(15);
      applyChanges(qfieldSettings.autoSave);
      if (featureModel.vertexModel.currentVertexIndex != -1) {
        if (featureModel.vertexModel.editingMode === QfVertexModel.AddVertex) {
          featureModel.vertexModel.editingMode = QfVertexModel.EditVertex;
        } else {
          featureModel.vertexModel.editingMode = QfVertexModel.AddVertex;
        }
      } else {
        featureModel.vertexModel.addVertexNearestToPosition(coordinateLocator.currentCoordinate);
        applyChanges(qfieldSettings.autoSave);
      }
    }
  }

  QfToolButton {
    id: previousVertexButton
    round: true
    enabled: !screenHovering
    visible: featureModel && (featureModel.vertexModel.canAddVertex || featureModel.vertexModel.editingMode === QfVertexModel.AddVertex)
    bgcolor: enabled && featureModel && featureModel.vertexModel.canPreviousVertex ? QfTheme.toolButtonBackgroundColor : QfTheme.toolButtonBackgroundSemiOpaqueColor
    iconSource: QfTheme.getThemeVectorIcon("ic_chevron_left_white_24dp")
    iconColor: enabled && featureModel && featureModel.vertexModel.canPreviousVertex ? QfTheme.toolButtonColor : QfTheme.toolButtonBackgroundSemiOpaqueColor

    onClicked: {
      if (vertexEditorToolbar.currentVertexModified) {
        digitizingLogger.addCoordinate(featureModel.vertexModel.currentPoint);
      }
      applyChanges(qfieldSettings.autoSave);
      // WorkField: tyknięcie — krok po wierzchołkach
      haptyka(10);
      featureModel.vertexModel.previous();
    }
  }

  QfToolButton {
    id: nextVertexButton
    round: true
    enabled: !screenHovering
    visible: featureModel && (featureModel.vertexModel.canAddVertex || featureModel.vertexModel.editingMode === QfVertexModel.AddVertex)
    bgcolor: enabled && featureModel && featureModel.vertexModel.canNextVertex ? QfTheme.darkGray : QfTheme.darkGraySemiOpaque
    iconSource: QfTheme.getThemeVectorIcon("ic_chevron_right_white_24dp")
    iconColor: enabled && featureModel && featureModel.vertexModel.canNextVertex ? QfTheme.toolButtonColor : QfTheme.toolButtonBackgroundSemiOpaqueColor

    onClicked: {
      if (vertexEditorToolbar.currentVertexModified) {
        digitizingLogger.addCoordinate(featureModel.vertexModel.currentPoint);
      }
      applyChanges(qfieldSettings.autoSave);
      // WorkField: tyknięcie — krok po wierzchołkach
      haptyka(10);
      featureModel.vertexModel.next();
    }
  }

  QfDigitizingLogger {
    id: digitizingLogger
    type: 'edit_vertex'

    project: qgisProject
    mapSettings: mapSettings

    positionInformation: positionSource.positionInformation
    positionLocked: coordinateLocator.positionLocked
    topSnappingResult: coordinateLocator.topSnappingResult
    cloudUserInformation: projectInfo.cloudUserInformation
  }

  Connections {
    target: geometryEditingVertexModel

    function onCurrentVertexIndexChanged() {
      if (featureModel.vertexModel.currentVertexIndex != -1 && vertexEditorToolbar.currentVertexId !== featureModel.vertexModel.currentVertexIndex && !screenHovering && featureModel.vertexModel.editingMode !== QfVertexModel.NoEditing) {
        mapSettings.setCenter(featureModel.vertexModel.currentPoint, true);
        vertexEditorToolbar.currentVertexId = featureModel.vertexModel.currentVertexIndex;
        vertexEditorToolbar.currentVertexModified = false;
      }
    }

    function onCurrentPointChanged() {
      vertexEditorToolbar.currentVertexModified = true;
    }
  }
}
