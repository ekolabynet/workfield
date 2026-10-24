import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield.core
import org.qfield.gui

/**
 * \ingroup qml
 */
ToolBar {
  property alias title: titleLabel.text

  property bool backgroundFill: false
  property bool backAsCancel: false

  property alias showBackButton: backButton.visible
  property alias showApplyButton: applyButton.visible
  property alias showCancelButton: cancelButton.visible
  property alias showRemoveButton: removeButton.visible
  property alias showMenuButton: menuButton.visible

  property alias busyIndicatorState: busyIndicator.state
  property alias busyIndicatorValue: busyIndicator.value

  property double topMargin: 0.0

  signal cancel
  signal apply
  signal back
  signal finished
  signal remove
  signal openMenu

  height: topMargin + QfTheme.toolButtonSize

  topPadding: 0
  leftPadding: 0
  rightPadding: 0
  bottomPadding: 0

  anchors {
    top: parent.top
    left: parent.left
    right: parent.right
  }

  background: Rectangle {
    id: backgroundRect
    color: backgroundFill ? QfTheme.mainColor : "transparent"

    ProgressBar {
      id: busyIndicator
      anchors.top: parent.bottom
      anchors.left: parent.left
      width: parent.width
      height: 6
      value: 0
      indeterminate: value === 0 ? true : false

      state: "off"

      visible: opacity > 0

      states: [
        State {
          name: 'on'
          PropertyChanges {
            target: busyIndicator
            opacity: 1.0
          }
        },
        State {
          name: 'off'
          PropertyChanges {
            target: busyIndicator
            opacity: 0.0
          }
        }
      ]
      transitions: [
        Transition {
          from: "off"
          to: "on"
          SequentialAnimation {
            NumberAnimation {
              target: busyIndicator
              property: 'opacity'
              duration: 100
            }
          }
        },
        Transition {
          from: "on"
          to: "off"
          SequentialAnimation {
            PauseAnimation {
              duration: 100
            }
            NumberAnimation {
              target: busyIndicator
              property: 'opacity'
              duration: 200
            }
          }
        }
      ]
    }
  }
  Material.foreground: undefined

  // ── [WF-WINDOW-FRAME] 24.10.2026 — the same exits as QfWindowFrame ─────────
  // Tester (Samsung A7) and Piotr: leaving without saving on the LEFT in orange
  // (← when every change is already saved, ✕ when it would be thrown away),
  // confirming on the RIGHT in green (✓). Coloured backgrounds, white signs —
  // the same in the light and the dark theme and on the coloured header.
  readonly property color leaveColor: "#fb8c00"
  readonly property color confirmColor: "#43a047"

  //! "✓ Zapisano" in place of the title for a moment (settings saved at once).
  function flashSaved() {
    if (!flashEnabled)
      return;
    savedPill.opacity = 1.0;
    savedTimer.restart();
    const now = Date.now();
    if (now - _lastSavedSound > 1500 && typeof dzwieki !== "undefined" && dzwieki) {
      _lastSavedSound = now;
      dzwieki.zagraj("ok", false); // [WF-SOUNDS] respects the user's sound setting
    }
  }
  property double _lastSavedSound: 0
  //! The page binds this to its visibility: no flash for changes made elsewhere.
  property bool flashEnabled: true

  readonly property real _leftWidth: (backButton.visible ? backButton.width + 4 : 0) + (cancelButton.visible ? cancelButton.width + 4 : 0)
  readonly property real _rightWidth: (removeButton.visible ? removeButton.width + 4 : 0) + (applyButton.visible ? applyButton.width + 4 : 0) + (menuButton.visible ? menuButton.width + 4 : 0)

  //! Flash on every change of \a target's properties (a QtCore Settings
  //! object or any QObject whose properties are saved at once).
  function watchSettings(target) {
    if (!target)
      return 0;
    let count = 0;
    for (const key in target) {
      if (key.length > 7 && key.endsWith("Changed") && key !== "objectNameChanged" && target[key] && typeof target[key].connect === "function") {
        target[key].connect(flashSaved);
        count++;
      }
    }
    return count;
  }

  Timer {
    id: savedTimer
    interval: 1400
    onTriggered: savedPill.opacity = 0.0
  }

  RowLayout {
    anchors.fill: parent
    anchors.topMargin: topMargin
    anchors.leftMargin: 4
    anchors.rightMargin: 4
    Layout.margins: 0
    spacing: 4

    QfToolButton {
      id: backButton

      Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
      clip: true
      topInset: 5
      bottomInset: 5
      bgcolor: leaveColor
      iconSource: backAsCancel ? QfTheme.getThemeVectorIcon('ic_close_white_24dp') : QfTheme.getThemeVectorIcon('ic_arrow_left_white_24dp')
      iconColor: "white"

      onClicked: {
        if (backAsCancel) {
          cancel();
        } else {
          back();
        }
        finished();
      }
    }

    QfToolButton {
      id: cancelButton

      Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
      clip: true
      topInset: 5
      bottomInset: 5
      bgcolor: leaveColor
      iconSource: QfTheme.getThemeVectorIcon('ic_close_white_24dp')
      iconColor: "white"

      onClicked: {
        cancel();
        finished();
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      Label {
        id: titleLabel
        anchors.fill: parent
        // centred on the bar whatever the buttons on either side
        leftPadding: Math.max(0, _rightWidth - _leftWidth)
        rightPadding: Math.max(0, _leftWidth - _rightWidth)
        font: QfTheme.strongTitleFont
        color: backgroundFill ? QfTheme.mainOverlayColor : QfTheme.mainTextColor
        elide: Label.ElideRight
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        opacity: 1.0 - savedPill.opacity
      }

      Rectangle {
        id: savedPill
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: (titleLabel.leftPadding - titleLabel.rightPadding) / 2
        width: savedText.implicitWidth + 24
        height: Math.min(parent.height - 8, savedText.implicitHeight + 12)
        radius: height / 2
        color: confirmColor
        opacity: 0.0
        visible: opacity > 0

        Behavior on opacity {
          NumberAnimation {
            duration: 250
          }
        }

        Label {
          id: savedText
          anchors.centerIn: parent
          text: "✓ " + qsTr("Zapisano")
          font: QfTheme.strongTipFont
          color: "white"
        }
      }
    }

    QfToolButton {
      id: removeButton

      Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
      visible: false
      clip: true
      iconSource: QfTheme.getThemeVectorIcon('ic_delete_forever_white_24dp')
      iconColor: backgroundFill ? QfTheme.mainOverlayColor : QfTheme.mainTextColor

      onClicked: {
        remove();
        finished();
      }
    }

    QfToolButton {
      id: applyButton

      Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
      clip: true
      topInset: 5
      bottomInset: 5
      bgcolor: confirmColor
      iconSource: QfTheme.getThemeVectorIcon('ic_check_white_24dp')
      iconColor: "white"

      onClicked: {
        apply();
        finished();
      }
    }

    QfToolButton {
      id: menuButton

      Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
      clip: true
      visible: false

      iconSource: QfTheme.getThemeVectorIcon("ic_dot_menu_black_24dp")
      iconColor: backgroundFill ? QfTheme.mainOverlayColor : QfTheme.mainTextColor

      onClicked: {
        openMenu();
      }
    }
  }
}
