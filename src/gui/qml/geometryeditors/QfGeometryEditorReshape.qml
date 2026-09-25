import QtQuick
import org.qgis
import org.qfield.core
import org.qfield.gui

QfGeometryEditorBase {
  id: reshapeToolbar

  property bool screenHovering: false //<! if the stylus pen is used, one should not use the add button

  // Wlasny silnik ksztaltow: ten plik nie widzi tego z paska.
  // `Ksztalty` nie trzyma zadnego stanu poza ustawieniami gestosci,
  // wiec drugi egzemplarz nic nie kosztuje.
  Ksztalty {
    id: silnikKsztaltowEdytora
  }

  readonly property bool blocking: drawPolygonToolbar.isDigitizing

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
    objectName: "reshapeDigitizingToolbar"
    showConfirmButton: true
    screenHovering: reshapeToolbar.screenHovering

    digitizingLogger.type: 'edit_reshape'

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
        // ZMIANA OBRYSU CHCE LINII OTWARTEJ, nie pierscienia.
        //
        // `reshapeFromRubberband` bierze punkty gumki jako linie —
        // `pointSequence(..., Point, false)`, czyli BEZ domykania —
        // i podaje ja do `reshapeGeometry`. Gumka jest tu jednak
        // zadeklarowana jako WIELOKATOWA, wiec ksztalt wchodzil do niej
        // jako pierscien, a `setDataFromGeometry` zdejmuje z pierscienia
        // wierzcholek domykajacy. Do reshape trafiala przez to petla
        // PRAWIE domknieta i QGIS slusznie odmawial.
        //
        // Przestawiamy gumke na LINIE. Operacji to nie rusza (typ jest
        // tam podany osobno), a krzywa zostaje OTWARTA — i o nia tu
        // chodzi: zmiana obrysu to poprowadzenie kawalka granicy na nowo.
        // `init()` i tak ustawia wielokat przy kazdym otwarciu edytora.
        rubberbandModel.geometryType = Qgis.GeometryType.Line;
        silnikKsztaltowEdytora.zamien(rubberbandModel, trybKsztaltu);
      }
      digitizingLogger.writeCoordinates();
      rubberbandModel.frozen = true;
      if (!featureModel.currentLayer.editBuffer())
        featureModel.currentLayer.startEditing();
      var result = QfGeometryUtils.reshapeFromRubberband(featureModel.currentLayer, featureModel.feature.id, rubberbandModel);
      if (result !== QfGeometryUtils.Success) {
        displayToast(qsTr('The geometry could not be reshaped'), 'error');
        featureModel.currentLayer.rollBack();
        rubberbandModel.reset();
      } else {
        featureModel.currentLayer.commitChanges();
        rubberbandModel.reset();
        featureModel.refresh();
        featureModel.applyGeometryToVertexModel();
      }
    }

    onCancel: {
      rubberbandModel.reset();
    }
  }

  function init(featureModel, mapSettings, editorRubberbandModel, editorRenderer) {
    reshapeToolbar.featureModel = featureModel;
    drawPolygonToolbar.digitizingLogger.digitizingLayer = featureModel.currentLayer;
    drawPolygonToolbar.rubberbandModel = editorRubberbandModel;
    drawPolygonToolbar.rubberbandModel.geometryType = Qgis.GeometryType.Polygon;
    drawPolygonToolbar.mapSettings = mapSettings;
    drawPolygonToolbar.stateVisible = true;
  }

  function cancel() {
    drawPolygonToolbar.cancel();
  }
}
