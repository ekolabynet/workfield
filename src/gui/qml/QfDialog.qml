import QtQuick
import QtQuick.Controls
import org.qfield.core
import org.qfield.gui
import QtQuick.Controls.Material

/**
 * \ingroup qml
 */
QfDialog {
  visible: false
  modal: true
  font: QfTheme.defaultFont
  standardButtons: QfDialog.Ok | QfDialog.Cancel

  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2

  // WorkField: haptyka o sile z karty Teren (0 = wylaczona)
  function haptyka(baza) {
    const sila = typeof settings !== 'undefined' ? settings.valueInt('WorkField/haptykaSila', 3) : 3;
    if (sila > 0 && typeof platformUtilities !== 'undefined') {
      platformUtilities.vibrate(baza * sila);
    }
  }

  // WorkField: ujednolicone kolory decyzji — zielone potwierdzenie, czerwone
  // odrzucenie — spojnie we wszystkich dialogach dziedziczacych z QfDialog.
  // Malujemy dwoma kanalami: palette (style desktopowe) + Material (Android).
  function pomalujPrzycisk(przycisk, kolor) {
    if (!przycisk)
      return;
    przycisk.palette.button = kolor;
    przycisk.palette.buttonText = "white";
    przycisk.Material.background = kolor;
    przycisk.Material.foreground = "white";
  }

  // WorkField: haptyka decyzji — dziala takze, gdy dialog-potomek definiuje
  // wlasne onAccepted/onRejected (obie procedury sa wywolywane)
  onAccepted: haptyka(60)
  onRejected: haptyka(30)

  onAboutToShow: {
    const okBtn = standardButton(QfDialog.Ok);
    if (okBtn) {
      okBtn.text = qsTr("OK");
      pomalujPrzycisk(okBtn, "#43a047");
    }
    const cancelBtn = standardButton(QfDialog.Cancel);
    if (cancelBtn) {
      cancelBtn.text = qsTr("Cancel");
      pomalujPrzycisk(cancelBtn, "#e53935");
    }
    const yesBtn = standardButton(QfDialog.Yes);
    if (yesBtn) {
      yesBtn.text = qsTr("Yes");
      pomalujPrzycisk(yesBtn, "#43a047");
    }
    const noBtn = standardButton(QfDialog.No);
    if (noBtn) {
      noBtn.text = qsTr("No");
      pomalujPrzycisk(noBtn, "#e53935");
    }
    const closeBtn = standardButton(QfDialog.Close);
    if (closeBtn)
      closeBtn.text = qsTr("Close");
  }

  onClosed: {
    focusstack.forceActiveFocusOnLastTaker();
  }
}
