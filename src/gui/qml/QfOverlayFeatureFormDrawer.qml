import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Window
import org.qfield.core
import org.qfield.gui

/**
 * \ingroup qml
 */
Drawer {
  id: overlayFeatureFormDrawer

  property bool fullScreenView: qfieldSettings.fullScreenIdentifyView
  property bool isVertical: parent.width < parent.height || parent.width < 300

  property bool isDragging: false
  property real dragHeightAdjustment: 0
  property real dragWidthAdjustment: 0

  property alias featureModel: attributeFormModel.featureModel
  property alias state: overlayFeatureForm.state
  property alias featureForm: overlayFeatureForm
  property alias digitizingToolbar: overlayFeatureForm.digitizingToolbar
  property alias codeReader: overlayFeatureForm.codeReader
  property bool isAdding: false

  signal requestJumpToPoint(var center, real scale, bool handleMargins)

  edge: parent.width < parent.height ? Qt.BottomEdge : Qt.RightEdge
  closePolicy: Popup.NoAutoClose // prevent accidental feature addition when clicking outside of the popup drawer
  focus: visible

  property real lastWidth: 0

  width: {
    if (dragWidthAdjustment != 0) {
      return lastWidth - dragWidthAdjustment;
    } else if (overlayFeatureFormDrawer.fullScreenView || parent.width <= parent.height || parent.width < 300 || width >= 0.95 * parent.width) {
      lastWidth = parent.width;
      return parent.width;
    } else {
      const newWidth = Math.min(Math.max(200, parent.width / 2.25), parent.width);
      lastWidth = newWidth;
      return newWidth;
    }
  }

  property real lastHeight

  // WorkField 28.08.2026 — formularz maksymalizowal sie sam po pojawieniu
  // klawiatury i tracil gorny pasek z przyciskami.
  //
  // Dwie usterki w jednym wyrazeniu:
  //
  // 1. `height >= 0.95 * parent.height` porownuje wysokosc ze ZMIENIAJACA
  //    SIE wartoscia. Android zmniejsza okno przy klawiaturze, wiec
  //    dotychczasowa wysokosc nagle „przekracza 95%" — szuflada uznaje sie
  //    za pelnoekranowa i maksymalizuje. Po schowaniu klawiatury lastHeight
  //    trzyma juz pelna wartosc i okno zostaje na gorze.
  //
  //    Stad `wysokoscBazowa`: wysokosc okna SPRZED klawiatury, ktora nie
  //    drga przy jej pojawianiu i chowaniu.
  //
  // 2. Galaz pelnoekranowa zwracala `parent.height` BEZ odjecia
  //    sceneTopMargin, choc galaz przeciagania odejmowala. Dlatego przy
  //    maksymalizacji naglowek wchodzil pod pasek systemowy — razem
  //    z przyciskiem zapisu i uchwytem.

  //! Wysokosc okna sprzed pojawienia sie klawiatury.
  property real wysokoscBazowa: parent ? parent.height : 0

  Connections {
    target: Qt.inputMethod
    function onVisibleChanged() {
      // Zapamietujemy tylko wtedy, gdy klawiatura ZNIKA — wtedy okno ma
      // znowu pelna wysokosc. Przy pojawieniu zostawiamy stara wartosc.
      if (!Qt.inputMethod.visible && overlayFeatureFormDrawer.parent)
        overlayFeatureFormDrawer.wysokoscBazowa = overlayFeatureFormDrawer.parent.height;
    }
  }

  height: {
    const dostepna = parent.height - mainWindow.sceneTopMargin;
    if (dragHeightAdjustment != 0) {
      return Math.min(lastHeight - dragHeightAdjustment, dostepna);
    } else if (overlayFeatureFormDrawer.fullScreenView || parent.width >= parent.height || height >= 0.95 * wysokoscBazowa) {
      lastHeight = dostepna;
      return dostepna;
    } else {
      // WorkField 28.08.2026 — bylo `parent.height / 2`, czyli polowa okna.
      // Przy wysunietej klawiaturze z tej polowy zostawal pasek na trzy
      // linijki: widac naglowek i zakladki, samego pola juz nie.
      //
      // Dwie zmiany:
      //  * 0.65 zamiast 0.5 — bo 65% zostawia miejsce na tresc,
      //  * odjecie wysokosci klawiatury, zeby 65% liczylo sie z tego,
      //    co WIDAC, a nie z calego okna.
      const klawiatura = Qt.inputMethod.visible && Qt.inputMethod.keyboardRectangle
                         ? Qt.inputMethod.keyboardRectangle.height / (Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1)
                         : 0;
      const widoczna = Math.max(200, dostepna - klawiatura);
      const newHeight = Math.min(Math.max(200, widoczna * 0.65 + klawiatura), dostepna);
      lastHeight = newHeight;
      return newHeight;
    }
  }

  topPadding: 0
  leftPadding: 0
  rightPadding: 0
  bottomPadding: 0

  interactive: false
  dragMargin: 0

  /**
   * If the save/cancel was initiated by button, the drawer needs to be closed in the end
   * If the drawer is closed by back key or integrated functionality (by Drawer) it has to save in the end
   * To make a difference between these scenarios we need position of the drawer and the isSaved flag of the QfFeatureForm
   */
  onOpened: {
    isAdding = true;
  }

  onClosed: {
    if (!digitizingToolbar.geometryRequested) {
      if (!overlayFeatureForm.isSaved) {
        overlayFeatureForm.confirm();
      } else {
        overlayFeatureForm.isSaved = false; //reset
      }
      digitizingRubberband.model.reset();
      featureModel.resetFeature();
      isAdding = false;
    }
  }

  Connections {
    target: digitizingToolbar

    function onGeometryRequestedChanged() {
      if (digitizingToolbar.geometryRequested && overlayFeatureFormDrawer.isAdding) {
        overlayFeatureFormDrawer.close(); // note: the digitizing toolbar will re-open the drawer to avoid panel stacking issues
      }
    }
  }

  QfFeatureForm {
    id: overlayFeatureForm
    anchors.fill: parent
    visible: true

    topMargin: overlayFeatureFormDrawer.y === 0 ? mainWindow.sceneTopMargin : 0.0
    leftMargin: overlayFeatureFormDrawer.x === 0 ? mainWindow.sceneLeftMargin : 0.0
    rightMargin: mainWindow.sceneRightMargin
    bottomMargin: mainWindow.sceneBottomMargin
    isVertical: overlayFeatureFormDrawer.isVertical
    isDraggable: true

    property bool isSaved: false

    model: QfAttributeFormModel {
      id: attributeFormModel
      featureModel: QfFeatureModel {
        project: qgisProject
        appExpressionContextScopesGenerator: appScopesGenerator
        topSnappingResult: coordinateLocator.topSnappingResult
      }
    }

    state: "Add"

    onCreated: {
      digitizingToolbar.digitizingLogger.writeCoordinates();
    }

    onConfirmed: {
      displayToast(qsTr("Changes saved"));
      //close drawer if still open
      if (overlayFeatureFormDrawer.position > 0) {
        overlayFeatureForm.isSaved = true; //because just saved
        overlayFeatureFormDrawer.close();
      } else {
        overlayFeatureForm.isSaved = false; //reset
      }
      resetTabs();
    }

    onCancelled: {
      displayToast(qsTr("Changes discarded"));
      //close drawer if still open
      if (overlayFeatureFormDrawer.position > 0) {
        overlayFeatureForm.isSaved = true; //because never changed
        overlayFeatureFormDrawer.close();
      } else {
        overlayFeatureForm.isSaved = false; //reset
      }
      digitizingToolbar.digitizingLogger.clearCoordinates();
      resetTabs();
    }

    onRequestJumpToPoint: function (center, scale, handleMargins) {
      overlayFeatureFormDrawer.requestJumpToPoint(center, scale, handleMargins);
    }

    onToolbarDragged: function (deltaX, deltaY) {
      fullScreenView = false;
      if (isVertical) {
        dragHeightAdjustment += deltaY;
      } else {
        dragWidthAdjustment += deltaX;
      }
    }

    onToolbarDragAcquired: {
      isDragging = true;
    }

    onToolbarDragReleased: {
      isDragging = false;
      if (isVertical) {
        if (overlayFeatureFormDrawer.height < overlayFeatureFormDrawer.parent.height * 0.3) {
          if (fullScreenView) {
            fullScreenView = false;
          } else {
            overlayFeatureFormDrawer.close();
          }
        } else if (dragHeightAdjustment < -parent.height * 0.2) {
          fullScreenView = true;
        }
      } else {
        if (overlayFeatureFormDrawer.width < overlayFeatureFormDrawer.parent.width * 0.3) {
          if (fullScreenView) {
            fullScreenView = false;
          } else {
            overlayFeatureFormDrawer.close();
          }
        } else if (dragWidthAdjustment < -parent.width * 0.2) {
          fullScreenView = true;
        }
      }
      dragHeightAdjustment = 0;
      dragWidthAdjustment = 0;
    }

    Keys.onReleased: event => {
      if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
        if (overlayFeatureForm.model.constraintsHardValid || qfieldSettings.autoSave) {
          overlayFeatureFormDrawer.close();
        } else {
          overlayFeatureForm.requestCancel();
        }
        event.accepted = true;
      }
    }
  }

  Behavior on width {
    PropertyAnimation {
      duration: parent.width > parent.height && !isDragging ? 250 : 0
      easing.type: Easing.OutQuart
    }
  }

  Behavior on height {
    PropertyAnimation {
      duration: parent.width < parent.height && !isDragging ? 250 : 0
      easing.type: Easing.OutQuart
    }
  }

  Component.onCompleted: {
    if (Material.roundedScale) {
      Material.roundedScale = Material.NotRounded;
    }
    close();
  }
}
