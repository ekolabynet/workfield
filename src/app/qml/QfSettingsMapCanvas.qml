import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

ColumnLayout {
  property var settingsPage
  property var settingsRegistry
  property var settingsModel
  property Component rowDelegate

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20

    columns: 2
    columnSpacing: 0
    rowSpacing: 5

    Label {
      text: qsTr('Map Canvas')
      font: Theme.strongFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.topMargin: 5
      Layout.columnSpan: 2
    }
  }

  ListView {
    Layout.fillWidth: true
    Layout.preferredHeight: contentHeight
    interactive: false

    model: settingsModel

    delegate: rowDelegate
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20

    columns: 2
    columnSpacing: 0
    rowSpacing: 5

    Label {
      Layout.fillWidth: true
      Layout.columnSpan: 2
      text: qsTr("Map canvas rendering quality:")
      font: Theme.defaultFont
      color: Theme.mainTextColor

      wrapMode: Text.WordWrap
    }

    QfComboBox {
      id: renderingQualityComboBox
      enabled: true
      Layout.fillWidth: true
      Layout.columnSpan: 2
      Layout.alignment: Qt.AlignVCenter
      font: Theme.defaultFont

      popup.font: Theme.defaultFont
      popup.topMargin: mainWindow.sceneTopMargin
      popup.bottomMargin: mainWindow.sceneTopMargin

      model: ListModel {
        ListElement {
          name: qsTr('Best quality')
          value: 1.0
        }
        ListElement {
          name: qsTr('Lower quality')
          value: 0.75
        }
        ListElement {
          name: qsTr('Lowest quality')
          value: 0.5
        }
      }
      textRole: "name"
      valueRole: "value"

      property bool initialized: false

      onCurrentValueChanged: {
        if (initialized) {
          quality = currentValue;
        }
      }

      Component.onCompleted: {
        currentIndex = indexOfValue(quality);
        initialized = true;
      }
    }

    Label {
      text: qsTr("A lower quality trades rendering precision in favor of lower memory usage and rendering time.")
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      textFormat: Qt.RichText
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.columnSpan: 2

      onLinkActivated: link => {
        Qt.openUrlExternally(link);
      }
    }

    Label {
      Layout.fillWidth: true
      Layout.columnSpan: 2
      Layout.topMargin: 10
      text: qsTr("Digitizing cursor shape:")
      font: Theme.defaultFont
      color: Theme.mainTextColor

      wrapMode: Text.WordWrap
    }

    Row {
      Layout.fillWidth: true
      Layout.columnSpan: 2
      spacing: 8

      Repeater {
        model: [0, 1, 2, 3, 4]

        delegate: Rectangle {
          width: 48
          height: 48
          radius: 4
          color: "transparent"
          border.color: coordinateCursorShape === modelData ? Theme.mainColor : Theme.secondaryTextColor
          border.width: coordinateCursorShape === modelData ? 2 : 1

          Canvas {
            anchors.fill: parent
            anchors.margins: 4

            onPaint: {
              const ctx = getContext("2d");
              const w = width;
              const c = w / 2;
              ctx.clearRect(0, 0, w, w);
              const passes = [["#FFFFFF", 4], [Theme.mainTextColor, 2]];
              for (const [strokeStyle, lineWidth] of passes) {
                ctx.strokeStyle = strokeStyle;
                ctx.fillStyle = strokeStyle;
                ctx.lineWidth = lineWidth;
                ctx.beginPath();
                switch (modelData) {
                case 0:
                  ctx.arc(c, c, 5, 0, 2 * Math.PI);
                  break;
                case 1:
                case 2:
                  ctx.moveTo(c, 3);
                  ctx.lineTo(c, c - 6);
                  ctx.moveTo(c, w - 3);
                  ctx.lineTo(c, c + 6);
                  ctx.moveTo(3, c);
                  ctx.lineTo(c - 6, c);
                  ctx.moveTo(w - 3, c);
                  ctx.lineTo(c + 6, c);
                  break;
                case 3:
                  for (let a = 0; a < 4; ++a) {
                    ctx.moveTo(c + (c - 4) * Math.cos((a * 90 + 20) * Math.PI / 180), c + (c - 4) * Math.sin((a * 90 + 20) * Math.PI / 180));
                    ctx.arc(c, c, c - 4, (a * 90 + 20) * Math.PI / 180, (a * 90 + 70) * Math.PI / 180);
                  }
                  ctx.moveTo(c, c - 6);
                  ctx.lineTo(c, c + 6);
                  ctx.moveTo(c - 6, c);
                  ctx.lineTo(c + 6, c);
                  break;
                case 4:
                  ctx.moveTo(c + (c - 4), c);
                  ctx.arc(c, c, c - 4, 0, 2 * Math.PI);
                  ctx.moveTo(c + (c - 4) * 0.55, c);
                  ctx.arc(c, c, (c - 4) * 0.55, 0, 2 * Math.PI);
                  ctx.moveTo(c, 3);
                  ctx.lineTo(c, w - 3);
                  ctx.moveTo(3, c);
                  ctx.lineTo(w - 3, c);
                  break;
                }
                ctx.stroke();
                if (modelData === 0) {
                  ctx.fill();
                }
                if (modelData === 2) {
                  ctx.beginPath();
                  ctx.arc(c, c, 3, 0, 2 * Math.PI);
                  ctx.fill();
                }
                if (modelData === 4) {
                  ctx.beginPath();
                  ctx.arc(c, c, 2, 0, 2 * Math.PI);
                  ctx.fill();
                }
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              coordinateCursorShape = modelData;
            }
          }
        }
      }
    }

    Label {
      text: qsTr("From a plain dot to a full reticle — pick the digitizing cursor that suits your work.")
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.columnSpan: 2
    }
  }
}
