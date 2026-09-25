import QtQuick
import QtQuick.Controls
import org.qgis
import org.qfield.core
import org.qfield.gui

QfGeometryEditorBase {
  id: fillRingToolbar

  property bool screenHovering: false //<! if the stylus pen is used, one should not use the add button

  // Wlasny silnik ksztaltow: ten plik nie widzi tego z paska.
  // `Ksztalty` nie trzyma zadnego stanu poza ustawieniami gestosci,
  // wiec drugi egzemplarz nic nie kosztuje.
  Ksztalty {
    id: silnikKsztaltowEdytora
  }

  readonly property bool blocking: drawPolygonToolbar.isDigitizing

  property alias addPolygonDialog: addPolygonDialog
  property alias formPopupLoader: formPopupLoader

  spacing: 4

  function canvasClicked(point, type) {
    if (type === "stylus") {
      drawPolygonToolbar.addVertex();
      return true;
    }
    return false;
  }

  function canvasLongPressed(point, type) {
    if (type === "stylus") {
      drawPolygonToolbar.confirm();
      return true;
    }
    return false;
  }

  QfDigitizingToolbar {
    id: drawPolygonToolbar
    objectName: "fillRingDigitizingToolbar"
    showConfirmButton: true
    screenHovering: fillRingToolbar.screenHovering

    digitizingLogger.type: 'edit_fillring'

    QfEmbeddedFeatureForm {
      id: formPopupLoader
      state: 'Add'
      onRequestJumpToPoint: function (center, scale, handleMargins) {
        fillRingToolbar.requestJumpToPoint(center, scale, handleMargins);
      }
    }

    onConfirmed: {
      // KSZTALT TEZ TUTAJ (WorkField 24.09.2026).
      //
      // Ten edytor czyta z gumki i wola `...FromRubberband`. Jesli pasek
      // ksztaltow jest uzbrojony, zamieniamy lamana na ksztalt ZANIM
      // edytor zdazy ja przeczytac — dalej plynie juz przetarta droga
      // QFielda, bez zadnej zmiany.
      //
      // Nazwa ksztaltu idzie przez USTAWIENIA, bo ten plik nie widzi
      // ani paska ksztaltow, ani jego silnika: identyfikatory nie
      // przechodza miedzy plikami `.qml`. `settings` widzi kazdy.
      //
      // `zamien()` bierze typ geometrii Z SAMEJ GUMKI, wiec ciecie
      // dostaje linie, a zmiana obrysu wielokat — bez rozgalezien tutaj.
      const trybKsztaltu = settings.value('WorkField/trybKsztaltu', '');
      if (trybKsztaltu !== '') {
        silnikKsztaltowEdytora.zamien(rubberbandModel, trybKsztaltu);
      }
      digitizingLogger.writeCoordinates();
      rubberbandModel.frozen = true;
      var result = QfGeometryUtils.addRingFromRubberband(featureModel.currentLayer, featureModel.feature.id, rubberbandModel);
      if (result !== QfGeometryUtils.Success) {
        if (result === QfGeometryUtils.AddRingNotClosed)
          displayToast(qsTr('The ring is not closed'), 'error');
        else if (result === QfGeometryUtils.AddRingNotValid)
          displayToast(qsTr('The ring is not valid'), 'error');
        else if (result === QfGeometryUtils.AddRingCrossesExistingRings)
          displayToast(qsTr('The ring crosses existing rings (it is not disjoint)'), 'error');
        else if (result === QfGeometryUtils.AddRingNotInExistingFeature)
          displayToast(qsTr('The ring doesn\'t have any existing ring to fit into'), 'error');
        else
          displayToast(qsTr('Unknown error when creating the ring'), 'error');
        drawPolygonToolbar.rubberbandModel.reset();
      } else {
        addPolygonDialog.open();
      }
    }

    onCancel: {
      rubberbandModel.reset();
    }
  }

  QfDialog {
    id: addPolygonDialog
    parent: mainWindow.contentItem
    title: qsTr("Fill ring")
    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      text: qsTr("Would you like to fill the ring with a new polygon?")
    }

    standardButtons: Dialog.Yes | Dialog.No

    onAccepted: {
      fillWithPolygon();
    }

    onRejected: {
      drawPolygonToolbar.rubberbandModel.reset();
    }
  }

  function init(featureModel, mapSettings, editorRubberbandModel, editorRenderer) {
    fillRingToolbar.featureModel = featureModel;
    drawPolygonToolbar.digitizingLogger.digitizingLayer = featureModel.currentLayer;
    drawPolygonToolbar.rubberbandModel = editorRubberbandModel;
    drawPolygonToolbar.rubberbandModel.geometryType = Qgis.GeometryType.Polygon;
    drawPolygonToolbar.mapSettings = mapSettings;
    drawPolygonToolbar.stateVisible = true;
  }

  function cancel() {
    drawPolygonToolbar.cancel();
  }

  function commitRingFeature() {
    featureModel.currentLayer.commitChanges();
    drawPolygonToolbar.rubberbandModel.reset();
  }

  function cancelRingFeature() {
    featureModel.currentLayer.rollBack();
    drawPolygonToolbar.rubberbandModel.reset();
  }

  function fillWithPolygon() {
    var polygonGeometry = QfGeometryUtils.polygonFromRubberband(drawPolygonToolbar.rubberbandModel, featureModel.currentLayer.crs, featureModel.currentLayer.wkbType());
    var feature = QfFeatureUtils.createBlankFeature(featureModel.currentLayer.fields, polygonGeometry);

    // ODPINAMY, ZANIM PODEPNIEMY (WorkField 24.09.2026).
    //
    // Bylo tu samo `connect`, przy KAZDYM wypelnieniu i ani jednego
    // `disconnect`. Drugie wypelnienie wolalo wiec `commitRingFeature`
    // dwa razy, trzecie trzy — a drugi `commitChanges()` idzie juz do
    // warstwy bez bufora edycji. Stad „wypelnienie udalo sie tylko za
    // pierwszym razem".
    //
    // Nasze wlasne miejsca w tym repozytorium robia to parami
    // (QfWarstwiceCAD, QfOpisyCAD, QfWarstwyRysunku) — tutaj para sie
    // rozjechala. `disconnect` na niepodpietym uchwycie rzuca
    // wyjatkiem, wiec w `try`.
    try {
      formPopupLoader.onFeatureSaved.disconnect(commitRingFeature);
    } catch (e) {}
    try {
      formPopupLoader.onFeatureCancelled.disconnect(cancelRingFeature);
    } catch (e) {}

    formPopupLoader.onFeatureSaved.connect(commitRingFeature);
    formPopupLoader.onFeatureCancelled.connect(cancelRingFeature);

    formPopupLoader.currentLayer = fillRingToolbar.featureModel.currentLayer;
    formPopupLoader.feature = feature;
    formPopupLoader.open();
  }
}
