import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Theme

Popup {
  id: colorPicker

  property var t
  property color currentColor: "#000000"
  property bool allowAlpha: true
  property string title: qsTr("Wybierz kolor")

  signal colorPicked(color chosen)

  readonly property var palette: [
    ["#ffebee", "#ffcdd2", "#ef9a9a", "#e57373", "#ef5350", "#f44336", "#e53935", "#d32f2f", "#c62828", "#b71c1c"],
    ["#fce4ec", "#f8bbd0", "#f48fb1", "#f06292", "#ec407a", "#e91e63", "#d81b60", "#c2185b", "#ad1457", "#880e4f"],
    ["#f3e5f5", "#e1bee7", "#ce93d8", "#ba68c8", "#ab47bc", "#9c27b0", "#8e24aa", "#7b1fa2", "#6a1b9a", "#4a148c"],
    ["#e8eaf6", "#c5cae9", "#9fa8da", "#7986cb", "#5c6bc0", "#3f51b5", "#3949ab", "#303f9f", "#283593", "#1a237e"],
    ["#e3f2fd", "#bbdefb", "#90caf9", "#64b5f6", "#42a5f5", "#2196f3", "#1e88e5", "#1976d2", "#1565c0", "#0d47a1"],
    ["#e0f2f1", "#b2dfdb", "#80cbc4", "#4db6ac", "#26a69a", "#009688", "#00897b", "#00796b", "#00695c", "#004d40"],
    ["#e8f5e9", "#c8e6c9", "#a5d6a7", "#81c784", "#66bb6a", "#4caf50", "#43a047", "#388e3c", "#2e7d32", "#1b5e20"],
    ["#fffde7", "#fff9c4", "#fff59d", "#fff176", "#ffee58", "#ffeb3b", "#fdd835", "#fbc02d", "#f9a825", "#f57f17"],
    ["#fff3e0", "#ffe0b2", "#ffcc80", "#ffb74d", "#ffa726", "#ff9800", "#fb8c00", "#f57c00", "#ef6c00", "#e65100"],
    ["#efebe9", "#d7ccc8", "#bcaaa4", "#a1887f", "#8d6e63", "#795548", "#6d4c41", "#5d4037", "#4e342e", "#3e2723"],
    ["#ffffff", "#f5f5f5", "#e0e0e0", "#bdbdbd", "#9e9e9e", "#757575", "#616161", "#424242", "#212121", "#000000"]
  ]

  property real alphaValue: 1.0

  property bool showStrokeOptions: false
  property real strokeWidth: 0.26
  property int strokeStyle: 1

  signal strokeWidthPicked(real width)
  signal strokeStylePicked(int style)

  function openFor(color) {
    currentColor = color;
    alphaValue = color.a !== undefined ? color.a : 1.0;
    open();
  }

  parent: mainWindow.contentItem
  width: Math.min(420, mainWindow.width - 24)
  height: Math.min(implicitHeight, mainWindow.height - 48)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  ColumnLayout {
    anchors.fill: parent
    spacing: 8

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: colorPicker.title
        font: t.strongFont
        color: t.mainTextColor
      }

      Rectangle {
        width: 40
        height: 28
        radius: 4
        color: colorPicker.currentColor
        border.width: 1
        border.color: t.controlBorderColor
      }
    }

    Column {
      Layout.fillWidth: true
      spacing: 3

      Repeater {
        model: colorPicker.palette

        delegate: Row {
          required property var modelData

          spacing: 3

          Repeater {
            model: parent.modelData

            delegate: Rectangle {
              required property string modelData

              width: (colorPicker.width - 24 - 27) / 10
              height: width
              radius: 3
              color: modelData
              border.width: Qt.colorEqual(colorPicker.currentColor, modelData) ? 2 : 0
              border.color: t.mainTextColor

              MouseArea {
                anchors.fill: parent
                onClicked: colorPicker.currentColor = parent.modelData
              }
            }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 6
      spacing: 8
      visible: colorPicker.allowAlpha

      Text {
        text: qsTr("Krycie")
        font: t.defaultFont
        color: t.mainTextColor
      }

      Slider {
        Layout.fillWidth: true
        from: 0
        to: 1
        value: colorPicker.alphaValue
        onMoved: colorPicker.alphaValue = value
      }

      Text {
        text: Math.round(colorPicker.alphaValue * 100) + " %"
        font: t.tipFont
        color: t.secondaryTextColor
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.topMargin: 6
      Layout.preferredHeight: 1
      color: t.controlBorderColor
      visible: colorPicker.showStrokeOptions
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6
      visible: colorPicker.showStrokeOptions

      Text {
        Layout.fillWidth: true
        text: qsTr("Grubość")
        font: t.defaultFont
        color: t.mainTextColor
      }

      Button {
        text: "−"
        implicitWidth: 46
        onClicked: {
          colorPicker.strokeWidth = Math.max(0, colorPicker.strokeWidth - 0.1);
          colorPicker.strokeWidthPicked(colorPicker.strokeWidth);
        }
      }

      Text {
        Layout.preferredWidth: 74
        horizontalAlignment: Text.AlignHCenter
        text: colorPicker.strokeWidth.toFixed(1) + " mm"
        font: t.strongTipFont
        color: t.mainTextColor
      }

      Button {
        text: "+"
        implicitWidth: 46
        onClicked: {
          colorPicker.strokeWidth = Math.min(10, colorPicker.strokeWidth + 0.1);
          colorPicker.strokeWidthPicked(colorPicker.strokeWidth);
        }
      }
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6
      visible: colorPicker.showStrokeOptions

      Repeater {
        model: [
          {
            "s": 1,
            "n": qsTr("Ciągła")
          },
          {
            "s": 2,
            "n": qsTr("Kreskowana")
          },
          {
            "s": 3,
            "n": qsTr("Kropkowana")
          },
          {
            "s": 4,
            "n": qsTr("Kreska-kropka")
          }
        ]

        delegate: Button {
          required property var modelData

          text: modelData.n
          font.pointSize: t.tinyFont.pointSize
          checkable: true
          checked: colorPicker.strokeStyle === modelData.s

          onClicked: {
            colorPicker.strokeStyle = modelData.s;
            colorPicker.strokeStylePicked(modelData.s);
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      spacing: 8

      Button {
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        onClicked: colorPicker.close()
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Wybierz")
        highlighted: true

        onClicked: {
          const c = colorPicker.currentColor;
          const result = colorPicker.allowAlpha ? Qt.rgba(c.r, c.g, c.b, colorPicker.alphaValue) : c;
          colorPicker.colorPicked(result);
          colorPicker.close();
        }
      }
    }
  }
}

