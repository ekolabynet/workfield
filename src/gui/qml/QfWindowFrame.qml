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
 *   exitMode "close": only an orange ← on the left — for windows that save every
 *   change immediately, so there is nothing to confirm or throw away
 *   (Piotr 24.10, 16:39).
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
 * ✗ / ← emits cancelled() and closes; ✓ only emits confirmed() — the window
 * closes itself when the work is done (it may refuse, e.g. a bad name).
 *
 * \ingroup qml
 */
Popup {
  id: frame

  property string title: ""
  //! "decision": ✕ (leave without saving) and ✓ (confirm);
  //! "close": only ← (every change is already saved).
  //! Named exitMode, not mode: windows often have their own `mode`.
  property string exitMode: "decision"
  property string confirmText: qsTr("Zatwierdź")
  //! "confirm" (green ✓) or "danger" (red ✓ — deleting, what cannot be undone)
  property string confirmRole: "confirm"
  property bool confirmEnabled: true
  property bool busy: false
  property real preferredWidth: 440
  property string frameStyle: "classic"
  //! false: the body fills the window height and does not scroll (a canvas,
  //! an editor, a list with its own scrolling). Children then use
  //! Layout.fillHeight to take the space.
  property bool scrollable: true
  //! true: always the whole screen (editors, drawing, long lists).
  property bool forceFullScreen: false
  //! 0 = the height of the content; > 0 = this height (still capped by the screen)
  property real preferredHeight: 0
  //! true: a grip in the lower right corner resizes the window (desktop, tablet)
  property bool resizable: false
  //! a QSettings key: the size the user dragged to is remembered there
  property string sizeKey: ""
  //! Colours for windows with their own look (dark editors, the welcome
  //! window). Defaults follow the theme.
  property color backgroundColor: QfTheme.mainBackgroundColor
  property color titleBarColor: QfTheme.controlBackgroundAlternateColor
  property color titleTextColor: QfTheme.mainTextColor
  property color borderColor: QfTheme.controlBorderColor
  //! Optional function returning false to keep the window open on ✕ / ←
  //! (e.g. "unsaved changes — tap ✕ again to discard").
  property var cancelGuard: null
  //! false: no ✕ / ← at all — the user must choose in the body (e.g. "where
  //! to create projects"); set closePolicy: Popup.NoAutoClose with it.
  property bool leaveVisible: true

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
  readonly property real _wantedHeight: preferredHeight > 0 ? preferredHeight : _naturalHeight
  readonly property bool fullScreen: forceFullScreen || _wantedHeight > _windowHeight - _topInset - _bottomInset - 2 * _margin

  signal confirmed
  signal cancelled

  function cancel() {
    if (busy)
      return;
    if (typeof cancelGuard === "function" && cancelGuard() === false)
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
  height: fullScreen ? _windowHeight : _wantedHeight

  // [WF-WINDOW-FRAME] remembered size (resizable windows)
  Component.onCompleted: {
    if (sizeKey === "" || typeof settings === "undefined" || !settings)
      return;
    const w = Number(settings.value(sizeKey + "/width", 0));
    const h = Number(settings.value(sizeKey + "/height", 0));
    if (w > 200)
      preferredWidth = w;
    if (h > 160)
      preferredHeight = h;
  }
  x: Math.round((_windowWidth - width) / 2)
  y: fullScreen ? 0 : Math.round(Math.max(_topInset + _margin, (_windowHeight - height) / 2))

  onOpened: scroller.contentY = 0

  background: Rectangle {
    color: frame.backgroundColor
    radius: frame.fullScreen || frame.narrowScreen ? 0 : 8
    border.width: frame.fullScreen ? 0 : (frame.borderColor === QfTheme.controlBorderColor ? 1 : 2)
    border.color: frame.borderColor
  }

  contentItem: ColumnLayout {
    spacing: 0

    // ── title bar: ✗  title  ✓ ──────────────────────────────────────────
    Rectangle {
      id: titleBar
      Layout.fillWidth: true
      implicitHeight: Math.max(52, titleRow.implicitHeight + 12)
      color: frame.titleBarColor
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
          text: frame.exitMode === "close" ? "←" : "✕"
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
          visible: frame.leaveVisible
          // own background: the colour must not depend on the platform style
          background: Rectangle {
            radius: 6
            color: closeButton.fill
            opacity: closeButton.enabled ? 1.0 : 0.5
          }
          Accessible.name: frame.exitMode === "close" ? qsTr("Wróć") : qsTr("Wyjdź bez zapisywania")
          onClicked: frame.cancel()
        }

        Label {
          Layout.fillWidth: true
          text: frame.title
          font: QfTheme.strongFont
          color: frame.titleTextColor
          // long questions ("Usunąć projekt wraz z danymi?") wrap to a second line
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          horizontalAlignment: frame.exitMode === "close" ? Text.AlignLeft : Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        QfDecisionButton {
          id: confirmButton
          role: frame.confirmRole === "danger" ? "danger" : "confirm"
          visible: frame.exitMode === "decision"
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
        contentHeight: frame.scrollable ? body.implicitHeight + 2 * frame._bodyPadding : height
        interactive: frame.scrollable
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        readonly property bool overflows: frame.scrollable && contentHeight > height + 1

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
          height: frame.scrollable ? implicitHeight : scroller.height - 2 * frame._bodyPadding
          spacing: 8
        }
      }

      // [WF-WINDOW-FRAME] resize grip: drag the corner (desktop / tablet)
      Rectangle {
        id: grip
        visible: frame.resizable && !frame.fullScreen && !frame.narrowScreen
        z: 10
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 28
        height: 28
        radius: 4
        color: gripArea.pressed ? Qt.alpha(QfTheme.mainColor, 0.6) : Qt.alpha(QfTheme.controlBorderColor, 0.6)

        Text {
          anchors.centerIn: parent
          text: "◢"
          color: QfTheme.mainTextColor
          font.pointSize: QfTheme.tipFont.pointSize
        }

        MouseArea {
          id: gripArea
          anchors.fill: parent
          preventStealing: true
          cursorShape: Qt.SizeFDiagCursor
          property real startX: 0
          property real startY: 0
          property real startW: 0
          property real startH: 0
          onPressed: mouse => {
            const p = mapToItem(null, mouse.x, mouse.y);
            startX = p.x;
            startY = p.y;
            startW = frame.width;
            startH = frame.height;
          }
          onPositionChanged: mouse => {
            if (!pressed)
              return;
            const p = mapToItem(null, mouse.x, mouse.y);
            // the window stays centred: both edges move, so double the drag
            frame.preferredWidth = Math.max(320, Math.min(frame._windowWidth - 2 * frame._margin, startW + 2 * (p.x - startX)));
            frame.preferredHeight = Math.max(240, Math.min(frame._windowHeight - frame._topInset - frame._bottomInset - 2 * frame._margin - 1, startH + 2 * (p.y - startY)));
          }
          onReleased: {
            if (frame.sizeKey !== "" && typeof settings !== "undefined" && settings) {
              settings.setValue(frame.sizeKey + "/width", Math.round(frame.preferredWidth));
              settings.setValue(frame.sizeKey + "/height", Math.round(frame.preferredHeight));
            }
          }
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
            color: frame.backgroundColor
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
