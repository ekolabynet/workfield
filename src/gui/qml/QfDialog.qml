import QtQuick
import QtQuick.Controls
import org.qfield.core
import org.qfield.gui
import QtQuick.Controls.Material
import QtQuick.Layouts

/**
 * \ingroup qml
 */
Dialog {
  id: qfDialog

  visible: false
  modal: true
  font: QfTheme.defaultFont
  standardButtons: Dialog.Ok | Dialog.Cancel

  x: (mainWindow.width - width) / 2
  y: Math.max(mainWindow.sceneTopMargin + 8, (mainWindow.height - height) / 2)

  // ── [WF-WINDOW-FRAME] 24.10.2026 — the same exits as every window ─────────
  // Simple questions (OK / Cancel, Yes / No, a single OK, Cancel or Close)
  // show their answers in the title bar: orange ✕ on the LEFT = no / cancel,
  // green ✓ on the RIGHT = yes / OK (red when it deletes). A lone OK, Cancel
  // or Close becomes the orange ←. The button row at the bottom is hidden.
  // Dialogs with other buttons (Save / Discard…) keep their bottom row.
  //! "" = automatic (red when the question deletes / discards), "confirm", "danger"
  property string confirmRole: ""

  readonly property int _simpleMask: Dialog.Ok | Dialog.Cancel | Dialog.Yes | Dialog.No | Dialog.Close
  readonly property bool _simpleButtons: standardButtons !== Dialog.NoButton && (standardButtons & ~_simpleMask) === 0
  readonly property bool _hasYes: _simpleButtons && (standardButtons & (Dialog.Ok | Dialog.Yes)) !== 0
  readonly property bool _hasNo: _simpleButtons && (standardButtons & (Dialog.Cancel | Dialog.No | Dialog.Close)) !== 0
  property string _yesText: ""
  readonly property bool _danger: confirmRole === "danger" || (confirmRole === "" && /usu[nń]|delet|remov|discard|odrzu|reset|uninstall|odinstal|porzu/i.test(_yesText + " " + title))

  height: Math.min(implicitHeight, mainWindow.height - mainWindow.sceneTopMargin - mainWindow.sceneBottomMargin - 16)

  header: Rectangle {
    implicitHeight: Math.max(52, headerRow.implicitHeight + 12)
    color: QfTheme.controlBackgroundAlternateColor
    radius: 4

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: QfTheme.controlBorderColor
    }

    RowLayout {
      id: headerRow
      anchors.fill: parent
      anchors.leftMargin: 6
      anchors.rightMargin: 6
      spacing: 8

      Button {
        id: noButton
        // ✕ = no / cancel; a lone button (OK, Cancel or Close) = ←
        visible: qfDialog._hasNo
        Layout.preferredWidth: 48
        Layout.preferredHeight: 44
        text: qfDialog._hasYes ? "✕" : "←"
        font.pointSize: QfTheme.strongFont.pointSize
        font.bold: true
        background: Rectangle {
          radius: 6
          color: "#fb8c00"
        }
        contentItem: Label {
          text: noButton.text
          font: noButton.font
          color: "white"
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
        onClicked: qfDialog.reject()
      }

      Button {
        id: aloneOkButton
        // a lone OK (information) leaves with ← too, but accepts
        visible: qfDialog._hasYes && !qfDialog._hasNo
        Layout.preferredWidth: 48
        Layout.preferredHeight: 44
        text: "←"
        font.pointSize: QfTheme.strongFont.pointSize
        font.bold: true
        background: Rectangle {
          radius: 6
          color: "#fb8c00"
        }
        contentItem: Label {
          text: aloneOkButton.text
          font: aloneOkButton.font
          color: "white"
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
        onClicked: qfDialog.accept()
      }

      Label {
        Layout.fillWidth: true
        text: qfDialog.title
        font: QfTheme.strongFont
        color: QfTheme.mainTextColor
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        horizontalAlignment: qfDialog._hasYes && qfDialog._hasNo ? Text.AlignHCenter : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
      }

      Button {
        id: yesButton
        visible: qfDialog._hasYes && qfDialog._hasNo
        Layout.preferredHeight: 44
        Layout.maximumWidth: qfDialog.width * 0.45
        text: "✓  " + qfDialog._yesText
        font.pointSize: QfTheme.tipFont.pointSize
        font.bold: true
        background: Rectangle {
          radius: 6
          color: qfDialog._danger ? "#e53935" : "#43a047"
        }
        contentItem: Label {
          text: yesButton.text
          font: yesButton.font
          color: "white"
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
        onClicked: qfDialog.accept()
      }
    }
  }

  Component.onCompleted: _syncFrame()

  function _syncFrame() {
    const yes = standardButton(Dialog.Ok) || standardButton(Dialog.Yes);
    _yesText = yes ? yes.text : "";
    if (footer)
      footer.visible = !_simpleButtons;
  }

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
  onAccepted: {
    haptyka(60);
    if (typeof dzwieki !== "undefined")
      dzwieki.zagraj("ok", false); // [WF-SOUNDS]
  }
  onRejected: {
    haptyka(30);
    if (typeof dzwieki !== "undefined")
      dzwieki.zagraj("anuluj", false); // [WF-SOUNDS]
  }

  onAboutToShow: {
    const okBtn = standardButton(Dialog.Ok);
    if (okBtn) {
      okBtn.text = qsTr("OK");
      pomalujPrzycisk(okBtn, "#43a047");
    }
    const cancelBtn = standardButton(Dialog.Cancel);
    if (cancelBtn) {
      cancelBtn.text = qsTr("Cancel");
      pomalujPrzycisk(cancelBtn, "#fb8c00"); // [WF-BUTTONS] red is for deleting only
    }
    const yesBtn = standardButton(Dialog.Yes);
    if (yesBtn) {
      yesBtn.text = qsTr("Yes");
      pomalujPrzycisk(yesBtn, "#43a047");
    }
    const noBtn = standardButton(Dialog.No);
    if (noBtn) {
      noBtn.text = qsTr("No");
      pomalujPrzycisk(noBtn, "#fb8c00"); // [WF-BUTTONS]
    }
    const closeBtn = standardButton(Dialog.Close);
    if (closeBtn)
      closeBtn.text = qsTr("Close");
    // [WF-WINDOW-FRAME] after the dialogs' own onAboutToShow (they may rename OK)
    Qt.callLater(_syncFrame);
  }

  onClosed: {
    focusstack.forceActiveFocusOnLastTaker();
  }
}
