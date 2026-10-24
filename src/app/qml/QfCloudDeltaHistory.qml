import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qgis
import org.qfield.core
import org.qfield.gui

/**
 * \ingroup qml
 */
// [WF-WINDOW-FRAME] 24.10.2026 — common frame: ← in the title bar; the list scrolls by itself
QfWindowFrame {
  id: popup

  property alias model: deltaListModel

  title: qsTr("Upload History")
  exitMode: "close"
  // the list pages on overshoot, so it keeps its own scrolling; the window
  // grows with the list and goes full screen when it no longer fits
  scrollable: false
  focus: visible

  onAboutToShow: {
    if (model.cloudProjectId != "") {
      model.refresh();
    }
  }

  Item {
    id: loadingIndicator
    Layout.fillWidth: true
    Layout.preferredHeight: loadingContent.height + 30
    visible: popup.model.isRefreshing

    Column {
      id: loadingContent
      anchors.centerIn: parent
      width: parent.width
      spacing: 10

      BusyIndicator {
        id: busyIndicator
        anchors.horizontalCenter: parent.horizontalCenter
        width: 48
        height: 48
      }

      Label {
        width: parent.width
        font: QfTheme.tipFont
        color: QfTheme.secondaryTextColor
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: qsTr("Fetching upload history…")
      }
    }
  }

  Label {
    id: emptyLabel
    Layout.fillWidth: true
    leftPadding: 48
    rightPadding: 48
    visible: !popup.model.isRefreshing && deltaList.count === 0

    font: QfTheme.tipFont
    color: QfTheme.mainTextDisabledColor
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: qsTr("No changes have been uploaded yet!")
  }

  ListView {
    id: deltaList

    property bool overshootFetchNextPage: false

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredHeight: contentHeight
    visible: count !== 0
    clip: true
    spacing: 5
    ScrollBar.vertical: QfScrollBar {}

    model: QfDeltaListModel {
      id: deltaListModel
    }

    delegate: QfCollapsibleMessage {
      width: parent ? parent.width : undefined
      color: popup.deltaStatusColor(Status)
      detailsColor: QfTheme.secondaryTextColor
      font: QfTheme.tipFont
      iconSource: popup.deltaStatusIcon(Status)
      titleText: Summary + "\n" + qsTr("Uploaded by %1 on %2").arg(CreatedBy).arg(CreatedAt.toLocaleString(Qt.locale(), Locale.ShortFormat))
      detailsText: Output
    }

    onMovingChanged: {
      if (!moving && overshootFetchNextPage && deltaListModel.hasNextPage) {
        deltaListModel.fetchNextPage();
      }
      overshootFetchNextPage = false;
    }

    onVerticalOvershootChanged: {
      if (verticalOvershoot > 10) {
        overshootFetchNextPage = true;
      }
    }
  }

  function deltaStatusColor(status) {
    switch (status) {
    case QfCloudDelta.AppliedStatus:
      return QfTheme.mainColor;
    case QfCloudDelta.PendingStatus:
    case QfCloudDelta.BusyStatus:
      return QfTheme.cloudColor;
    case QfCloudDelta.ConflictStatus:
    case QfCloudDelta.NotAppliedStatus:
      return QfTheme.warningColor;
    case QfCloudDelta.ErrorStatus:
    case QfCloudDelta.UnpermittedStatus:
      return QfTheme.errorColor;
    default:
      return QfTheme.secondaryTextColor;
    }
  }

  function deltaStatusLabel(status) {
    switch (status) {
    case QfCloudDelta.AppliedStatus:
      return qsTr('Applied');
    case QfCloudDelta.PendingStatus:
      return qsTr('Pending');
    case QfCloudDelta.BusyStatus:
      return qsTr('Busy');
    case QfCloudDelta.ConflictStatus:
      return qsTr('Conflict');
    case QfCloudDelta.NotAppliedStatus:
      return qsTr('Not applied');
    case QfCloudDelta.ErrorStatus:
      return qsTr('Error');
    case QfCloudDelta.IgnoredStatus:
      return qsTr('Ignored');
    case QfCloudDelta.UnpermittedStatus:
      return qsTr('Unpermitted');
    default:
      return qsTr('Unknown');
    }
  }

  function deltaStatusIcon(status) {
    switch (status) {
    case QfCloudDelta.AppliedStatus:
      return QfTheme.getThemeVectorIcon('ic_check_white_24dp');
    case QfCloudDelta.PendingStatus:
    case QfCloudDelta.BusyStatus:
      return QfTheme.getThemeVectorIcon('ic_hourglass_black_24dp');
    default:
      return QfTheme.getThemeVectorIcon('ic_error_outline_24dp');
    }
  }
}
