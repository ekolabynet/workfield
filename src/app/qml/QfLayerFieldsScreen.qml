import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

Popup {
  id: fieldsScreen

  property var t
  property var layer: null
  property var entries: []

  readonly property var fieldTypes: [
    { key: "text", label: qsTr("Tekst") },
    { key: "multiline", label: qsTr("Tekst długi") },
    { key: "integer", label: qsTr("Liczba całkowita") },
    { key: "real", label: qsTr("Liczba rzeczywista") },
    { key: "date", label: qsTr("Data") },
    { key: "datetime", label: qsTr("Data i czas") },
    { key: "bool", label: qsTr("Tak/Nie") },
    { key: "attachment", label: qsTr("Załącznik (zdjęcia)") }
  ]

  property string newFieldName: ""
  property int newFieldTypeIndex: 0

  function openFor(vectorLayer) {
    layer = vectorLayer;
    newFieldName = "";
    newFieldTypeIndex = 0;
    reload();
    open();
  }

  function reload() {
    entries = layer ? LayerUtils.layerFields(layer) : [];
  }

  parent: mainWindow.contentItem
  width: Math.min(440, mainWindow.width - 24)
  height: Math.min(implicitHeight, mainWindow.height - 48)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: Popup.CloseOnEscape

  ColumnLayout {
    anchors.fill: parent
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Pola warstwy")
      font: t.strongFont
      color: t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: fieldsScreen.layer ? fieldsScreen.layer.name : ""
      font: t.tipFont
      color: t.secondaryTextColor
      elide: Text.ElideMiddle
    }

    Text {
      Layout.fillWidth: true
      visible: fieldsScreen.layer && !LayerUtils.canEditFields(fieldsScreen.layer)
      text: qsTr("Ta warstwa nie pozwala na zmianę struktury pól.")
      font: t.tipFont
      color: t.warningColor
      wrapMode: Text.WordWrap
    }

    ListView {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(contentHeight, 260)
      clip: true
      model: fieldsScreen.entries

      delegate: RowLayout {
        required property var modelData

        readonly property bool isSystemField: modelData.name === "uuid"

        width: ListView.view.width
        height: 44
        spacing: 8

        ColumnLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 4
          spacing: 0

          Text {
            Layout.fillWidth: true
            text: isSystemField ? qsTr("Identyfikator załączników") : modelData.name
            font: t.defaultFont
            color: isSystemField ? t.secondaryTextColor : t.mainTextColor
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            text: isSystemField ? qsTr("wymagane przez pola zdjęć") : modelData.type
            font: t.tinyFont
            color: t.secondaryTextColor
          }
        }

        QfToolButton {
          Layout.rightMargin: 4
          width: 32
          height: 32
          padding: 0
          bgcolor: "transparent"
          enabled: !isSystemField && fieldsScreen.layer && LayerUtils.canEditFields(fieldsScreen.layer)
          iconSource: t.getThemeVectorIcon("ic_delete_forever_white_24dp")
          iconColor: t.errorColor

          onClicked: {
            removeFieldConfirm.fieldName = modelData.name;
            removeFieldConfirm.open();
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Nowe pole")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      TextField {
        Layout.fillWidth: true
        font: t.defaultFont
        placeholderText: qsTr("nazwa pola")
        text: fieldsScreen.newFieldName
        onTextChanged: fieldsScreen.newFieldName = text
      }

      ComboBox {
        Layout.preferredWidth: 150
        font: t.defaultFont
        model: fieldsScreen.fieldTypes.map(f => f.label)
        currentIndex: fieldsScreen.newFieldTypeIndex
        onActivated: idx => fieldsScreen.newFieldTypeIndex = idx
      }
    }

    Button {
      Layout.fillWidth: true
      text: qsTr("Dodaj pole")
      enabled: fieldsScreen.newFieldName.trim() !== "" && fieldsScreen.layer && LayerUtils.canEditFields(fieldsScreen.layer)

      onClicked: {
        const type = fieldsScreen.fieldTypes[fieldsScreen.newFieldTypeIndex].key;
        const name = fieldsScreen.newFieldName.trim();

        if (type === "attachment") {
          const existing = LayerUtils.layerFields(fieldsScreen.layer);
          const hasUuid = existing.some(f => f.name === "uuid");
          if (!hasUuid) {
            const uuidError = LayerUtils.addLayerField(fieldsScreen.layer, "uuid", "text");
            if (uuidError !== "") {
              displayToast(uuidError);
              return;
            }
          }

          const fieldError = LayerUtils.addLayerField(fieldsScreen.layer, name, "text");
          if (fieldError !== "") {
            displayToast(fieldError);
            return;
          }

          LayerUtils.setAttachmentField(fieldsScreen.layer, name);
          displayToast(qsTr("Dodano pole zdjęć %1").arg(name));
          fieldsScreen.newFieldName = "";
          fieldsScreen.reload();
          return;
        }

        const error = LayerUtils.addLayerField(fieldsScreen.layer, name, type);
        if (error === "") {
          displayToast(qsTr("Dodano pole %1").arg(name));
          fieldsScreen.newFieldName = "";
          fieldsScreen.reload();
        } else {
          displayToast(error);
        }
      }
    }

    Button {
      Layout.fillWidth: true
      Layout.topMargin: 8
      text: qsTr("Gotowe")
      highlighted: true
      onClicked: fieldsScreen.close()
    }
  }

  Popup {
    id: removeFieldConfirm

    property string fieldName: ""

    parent: mainWindow.contentItem
    width: Math.min(360, mainWindow.width - 32)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    modal: true
    closePolicy: Popup.CloseOnEscape

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Usunąć pole %1?").arg(removeFieldConfirm.fieldName)
        font: t.strongFont
        color: t.mainTextColor
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Dane zapisane w tym polu zostaną bezpowrotnie utracone.")
        font: t.tipFont
        color: t.warningColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 8

        Button {
          Layout.fillWidth: true
          text: qsTr("Anuluj")
          onClicked: removeFieldConfirm.close()
        }

        Button {
          Layout.fillWidth: true
          text: qsTr("Usuń")
          highlighted: true

          onClicked: {
            const error = LayerUtils.removeLayerField(fieldsScreen.layer, removeFieldConfirm.fieldName);
            displayToast(error === "" ? qsTr("Usunięto pole %1").arg(removeFieldConfirm.fieldName) : error);
            fieldsScreen.reload();
            removeFieldConfirm.close();
          }
        }
      }
    }
  }
}
