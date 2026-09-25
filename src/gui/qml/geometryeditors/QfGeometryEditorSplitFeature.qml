import QtQuick
import org.qgis
import org.qfield.core
import org.qfield.gui

QfGeometryEditorBase {
  id: splitFeatureToolbar

  property bool screenHovering: false //<! if the stylus pen is used, one should not use the add button

  // Wlasny silnik ksztaltow: ten plik nie widzi tego z paska.
  // `Ksztalty` nie trzyma zadnego stanu poza ustawieniami gestosci,
  // wiec drugi egzemplarz nic nie kosztuje.
  Ksztalty {
    id: silnikKsztaltowEdytora
  }
  readonly property bool blocking: drawLineToolbar.isDigitizing

  spacing: 4

  function canvasClicked(point, type) {
    if (type === "stylus") {
      drawLineToolbar.addVertex();
      return true;
    }
    return false;
  }

  function canvasLongPressed(point, type) {
    if (type === "stylus") {
      drawLineToolbar.confirm();
      return true;
    }
    return false;
  }

  QfDigitizingToolbar {
    id: drawLineToolbar
    objectName: "splitDigitizingToolbar"
    showConfirmButton: true
    screenHovering: splitFeatureToolbar.screenHovering

    digitizingLogger.type: 'edit_split'

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
      const result = QfGeometryUtils.splitFeatureFromRubberband(featureModel.currentLayer, featureModel.feature.id, drawLineToolbar.rubberbandModel);
      if (result !== QfGeometryUtils.Success) {
        displayToast(qsTr('Feature could not be split'), 'error');
      }
      rubberbandModel.reset();
      cancel();
      finished();
    }

    onCancel: {
      rubberbandModel.reset();
    }
  }

  function init(featureModel, mapSettings, editorRubberbandModel, editorRenderer) {
    splitFeatureToolbar.featureModel = featureModel;
    drawLineToolbar.digitizingLogger.digitizingLayer = featureModel.currentLayer;
    drawLineToolbar.rubberbandModel = editorRubberbandModel;
    drawLineToolbar.rubberbandModel.geometryType = Qgis.GeometryType.Line;
    drawLineToolbar.mapSettings = mapSettings;
    drawLineToolbar.stateVisible = true;
  }

  function cancel() {
    drawLineToolbar.cancel();
  }
}
