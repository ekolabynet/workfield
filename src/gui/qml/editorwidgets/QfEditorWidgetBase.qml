import QtQuick
import QtQuick.Controls
import org.qfield.core
import org.qfield.gui

Item {
  /**
   * This property indicates whether the editor widget has been fully loaded by its Loader.
   * Note: prior to this property being true, signals emitted by the editor widget will not be
   * propagated.
   */
  property bool isLoaded: false
  property bool hasMenu: false
  readonly property bool isNull: QfFeatureUtils.attributeIsNull(value)
  readonly property bool isEmpty: value === ''

  property Menu menu: QfMenu {
    id: itemMenu
    title: qsTr("Item Menu")
    z: 10000 // 1000s are embedded feature forms, use a higher value to insure feature form popups always show above embedded feature formes

    topMargin: mainWindow.sceneTopMargin
    bottomMargin: mainWindow.sceneBottomMargin
  }

  /**
   * This signal is emmited when an editor widget has changed the value.
   */
  signal valueChangeRequested(var value, bool isNull)

  /**
   * This signal is emitted when an editor widget is in need of a digitized geometry. The
   * geometry will be returned through calling a requestedGeometryReceived(geometry) function
   * attached to editor widget which signaled the request. The corresponding
   * handler is \c onRequestGeometry.
   */
  signal requestGeometry(var item, var layer)

  /**
   * Widget prosi o rozpoznanie gatunku ze zdjęcia.
   *
   * Widget nie może zapisać do cudzego pola — ma tylko
   * `valueChangeRequested` na własną wartość. Więc zgłasza zadanie,
   * a formularz je wykonuje: pyta Pl@ntNet, pokazuje kandydatów i wpisuje
   * wybraną nazwę do pola wskazanego przez człowieka.
   *
   * Ten sam wzorzec co `requestGeometry` i `requestBarcode`.
   */
  signal requestSpeciesName(string sciezkaZdjecia)

  /**
   * This signal is emitted when an editor widget is requesting a barcode value. The
   * decoded barcode value will be returned as a string through calling a requestedBarcodeReceived(string) function
   * attached to editor widget which signaled the request. The corresponding
   * handler is \c onRequestBarcode.
   */
  signal requestBarcode(var item)

  /**
   * This signal is emitted when an editor widget is requesting to jump to a specific point on the map.
   * The corresponding handler is \c onRequestJumpToPoint.
   */
  signal requestJumpToPoint(var center, real scale, bool handleMargins)
}
