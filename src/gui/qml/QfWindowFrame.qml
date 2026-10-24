import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.Material
import org.qfield.core
import org.qfield.gui

/**
 * WorkFieldGIS 24.10.2026 [WF-WINDOW-FRAME] — one frame for the large windows.
 *
 * Tester remark (Marcin, Samsung A7 2018, 24.10): "Nowy projekt" did not fit
 * on the screen and could not be scrolled; leaving a window should be
 * "✗ = without saving" and "✓ = confirm", not an arrow.
 *
 * - Title bar: ✗ on the left, title, ✓ on the right (mode "decision").
 *   Mode "close": only ✗ — for settings that are saved immediately.
 * - The body scrolls, with a wide bar that is always visible when the body
 *   does not fit, and a "more below" hint at the bottom edge.
 * - On a narrow screen the window takes the full width; when the body does
 *   not fit in height, the window takes the whole screen.
 * - frameStyle is reserved for selectable frame styles (later: compact,
 *   classic, high contrast for sunlight) — one place to change every window.
 *
 * Usage: children go into the scrolling column (Layout.* works as usual).
 *   QfWindowFrame {
 *     title: qsTr("Nowy projekt"); confirmText: qsTr("Utwórz")
 *     onConfirmed: create()
 *     TextField { Layout.fillWidth: true }
 *   }
 * ✗ emits cancelled() and closes; ✓ only emits confirmed() — the window
 * closes itself when the work is done (it may refuse, e.g. a bad name).
 *
 * \ingroup qml
 */
Popup {
  id: frame

  property string title: ""
  property string mode: "decision"
  property string confirmText: qsTr("Zatwierdź")
  property bool confirmEnabled: true
  property bool busy: false
  property real preferredWidth: 440
  property string frameStyle: "classic"

  default property alias content: body.data
  property alias bodySpacing: body.spacing
  property alias flickable: scroller

  readonly property real _margin: 12
  readonly property real _bodyPadding: 12
  readonly property real _topInset: typeof mainWindow !== "undefined" ? mainWindow.sceneTopMargin : 0
  readonly property real _bottomInset: typeof mainWindow !== "undefined" ? mainWindow.sceneBottomMargin : 0
  readonly property real _windowWidth: parent ? parent.width : 400
  readonly property real _windowHeight: parent ? parent.height : 600
  readonly property bool narrowScreen: _windowWidth < preferredWidth + 2 * _margin
  readonly property real _naturalHeight: titleBar.implicitHeight + body.implicitHeight + 2 * _bodyPadding
  readonly property bool fullScreen: _naturalHeight > _windowHeight - _topInset - _bottomInset - 2 * _margin

  signal confirmed
  signal cancelled

  function cancel() {
    if (busy)
      return;
    cancelled();
    close();
  }

  parent: typeof mainWindow !== "undefined" ? mainWindow.contentItem : Overlay.overlay
  modal: true
  focus: true
  padding: 0
  topPadding: fullScreen ? _topInset : 0
  bottomPadding: fullScreen ? _bottomInset : 0
  closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape

  // Width never depends on the height decision — no binding loop with wrapped text.
  width: narrowScreen ? _windowWidth : preferredWidth
  height: fullScreen ? _windowHeight : _naturalHeight
  x: Math.round((_windowWidth - width) / 2)
  y: fullScreen ? 0 : Math.round(Math.max(_topInset + _margin, (_windowHeight - height) / 2))

  onOpened: scroller.contentY = 0

  background: Rectangle {
    color: QfTheme.mainBackgroundColor
    radius: frame.fullScreen || frame.narrowScreen ? 0 : 8
    border.width: frame.fullScreen ? 0 : 1
    border.color: QfTheme.controlBorderColor
  }

  contentItem: ColumnLayout {
    spacing: 0

    // ── title bar: ✗  title  ✓ ──────────────────────────────────────────
    Rectangle {
      id: titleBar
      Layout.fillWidth: true
      implicitHeight: Math.max(52, titleRow.implicitHeight + 12)
      color: QfTheme.controlBackgroundAlternateColor
      radius: frame.background.radius

      Rectangle {
        // square off the lower corners of the rounded bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.radius
        color: parent.color
        visible: parent.radius > 0
      }
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: QfTheme.controlBorderColor
      }

      RowLayout {
        id: titleRow
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 8

        QfDecisionButton {
          id: closeButton
          role: "cancel"
          text: "✕"
          font.pointSize: QfTheme.strongFont.pointSize
          font.bold: true
          Layout.preferredWidth: 48
          Layout.preferredHeight: 44
          contentItem: Label {
            text: closeButton.text
            font: closeButton.font
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
          enabled: !frame.busy
          // own background: the colour must not depend on the platform style
          background: Rectangle {
            radius: 6
            color: closeButton.fill
            opacity: closeButton.enabled ? 1.0 : 0.5
          }
          Accessible.name: frame.mode === "close" ? qsTr("Zamknij") : qsTr("Wyjdź bez zapisywania")
          onClicked: frame.cancel()
        }

        Label {
          Layout.fillWidth: true
          text: frame.title
          font: QfTheme.strongFont
          color: QfTheme.mainTextColor
          elide: Text.ElideRight
          horizontalAlignment: frame.mode === "close" ? Text.AlignLeft : Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        QfDecisionButton {
          id: confirmButton
          role: "confirm"
          visible: frame.mode === "decision"
          text: "✓  " + frame.confirmText
          font.pointSize: QfTheme.tipFont.pointSize
          font.bold: true
          Layout.preferredHeight: 44
          Layout.maximumWidth: frame.width * 0.45
          enabled: frame.confirmEnabled && !frame.busy
          background: Rectangle {
            radius: 6
            color: confirmButton.fill
            opacity: confirmButton.enabled ? 1.0 : 0.5
          }
          contentItem: Label {
            text: confirmButton.text
            font: confirmButton.font
            color: "white"
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
          onClicked: frame.confirmed()
        }
      }
    }

    // ── scrolling body ──────────────────────────────────────────────────
    Item {
      id: bodyArea
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: body.implicitHeight + 2 * frame._bodyPadding

      Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight + 2 * frame._bodyPadding
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        readonly property bool overflows: contentHeight > height + 1

        ScrollBar.vertical: QfScrollBar {
          // wide and always visible when needed: easy to see and to grab
          _maxSize: 16
          _minSize: 16
          policy: scroller.overflows ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          minimumSize: 0.1
        }

        ColumnLayout {
          id: body
          x: frame._bodyPadding
          y: frame._bodyPadding
          width: scroller.width - 2 * frame._bodyPadding - (scroller.overflows ? 18 : 0)
          spacing: 8
        }
      }

      // "more below" hint: fades the bottom edge until the end is reached
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: scroller.overflows ? 18 : 0
        anchors.bottom: parent.bottom
        height: 34
        visible: scroller.overflows && scroller.contentY + scroller.height < scroller.contentHeight - 4
        gradient: Gradient {
          GradientStop {
            position: 0.0
            color: "transparent"
          }
          GradientStop {
            position: 1.0
            color: QfTheme.mainBackgroundColor
          }
        }

        Label {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 2
          text: "▼ " + qsTr("dalej")
          font: QfTheme.tinyFont
          color: QfTheme.secondaryTextColor
        }

        MouseArea {
          anchors.fill: parent
          onClicked: scroller.contentY = Math.min(scroller.contentHeight - scroller.height, scroller.contentY + scroller.height * 0.8)
        }
      }
    }
  }
}
