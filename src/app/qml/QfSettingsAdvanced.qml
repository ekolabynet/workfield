import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import QfTheme

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
      text: qsTr('Advanced')
      font: QfTheme.strongFont
      color: QfTheme.mainTextColor
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
    columnSpacing: 10
    rowSpacing: 5

    Label {
      text: qsTr("Autozapis projektu")
      font: QfTheme.strongFont
      color: QfTheme.mainTextColor
      Layout.fillWidth: true
      Layout.topMargin: 10
      Layout.columnSpan: 2
    }

    Label {
      text: qsTr("Zapisuj projekt automatycznie co (minuty, 0 = wyłączone):")
      font: QfTheme.defaultFont
      color: QfTheme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    SpinBox {
      from: 0
      to: 120
      editable: true
      font: QfTheme.defaultFont
      value: settingsRegistry ? settingsRegistry.projectAutoSaveInterval : 5
      onValueModified: {
        if (settingsRegistry) {
          settingsRegistry.projectAutoSaveInterval = value;
        }
      }
    }

    Label {
      text: qsTr("Aparat")
      font: QfTheme.strongFont
      color: QfTheme.mainTextColor
      Layout.fillWidth: true
      Layout.topMargin: 10
      Layout.columnSpan: 2
    }

    Label {
      text: qsTr("Korekta obrotu podglądu i zdjęć (gdy obraz jest odwrócony):")
      font: QfTheme.defaultFont
      color: QfTheme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    QfComboBox {
      font: QfTheme.defaultFont
      model: ["0°", "90°", "180°", "270°"]
      currentIndex: settingsRegistry ? settingsRegistry.cameraRotationOffset / 90 : 0
      onActivated: {
        if (settingsRegistry) {
          settingsRegistry.cameraRotationOffset = currentIndex * 90;
        }
      }
    }

    Label {
      text: qsTr("Katalog danych")
      font: QfTheme.strongFont
      color: QfTheme.mainTextColor
      Layout.fillWidth: true
      Layout.topMargin: 10
      Layout.columnSpan: 2
    }

    Label {
      text: qsTr("Miejsce przechowywania projektów, szablonów i pobranych danych. Dotknij lokalizacji (także zaznaczonej), aby przenieść, skopiować lub zacząć od nowa. Po zmianie uruchom aplikację ponownie.")
      font: QfTheme.tipFont
      color: QfTheme.secondaryTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.columnSpan: 2
    }

    Column {
      Layout.fillWidth: true
      Layout.columnSpan: 2
      spacing: 2

      ButtonGroup {
        id: dirButtonGroup
      }

      Repeater {
        model: platformUtilities.appDataDirs()

        delegate: Column {
          width: parent.width

          RadioButton {
            id: dirRadio
            ButtonGroup.group: dirButtonGroup
            width: parent.width
            font: QfTheme.defaultFont
            text: (modelData.indexOf("emulated") !== -1 ? qsTr("Pamięć wewnętrzna") : modelData.indexOf("/storage/") === 0 ? qsTr("Karta SD") : qsTr("Dysk lokalny")) + " — " + iface.storageFreeGb(modelData).toFixed(1) + qsTr(" GB wolne")
          checked: iface.preferredDataDir() === "" ? index === 0 : modelData.indexOf(iface.preferredDataDir()) === 0 || iface.preferredDataDir().indexOf(modelData) === 0

            onClicked: {
              storageMigrateDialog.targetDir = modelData.endsWith("/") ? modelData : modelData + "/";
              storageMigrateDialog.open();
            }
          }

          Label {
            width: parent.width
            leftPadding: 40
            text: modelData
            font: QfTheme.tinyFont
            color: QfTheme.secondaryTextColor
            elide: Text.ElideMiddle
          }
        }
      }
    }
  }

  QfDialog {
    id: storageMigrateDialog

    property string targetDir: ""

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 420)
    modal: true
    title: qsTr("Zmiana katalogu danych")

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Label {
        Layout.fillWidth: true
        text: qsTr("Co zrobić z obecnymi danymi? Przenoszenie i kopiowanie może potrwać kilka minut przy dużych plikach — nie zamykaj aplikacji w trakcie.")
        font: QfTheme.defaultFont
        color: QfTheme.mainTextColor
        wrapMode: Text.WordWrap
      }

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Przenieś dane do nowej lokalizacji")
        font.pointSize: QfTheme.tinyFont.pointSize
        onClicked: storageMigrateDialog.apply(true, true)
      }

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Skopiuj dane (oryginały zostają)")
        font.pointSize: QfTheme.tinyFont.pointSize
        onClicked: storageMigrateDialog.apply(true, false)
      }

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Zacznij z pustym katalogiem")
        font.pointSize: QfTheme.tinyFont.pointSize
        onClicked: storageMigrateDialog.apply(false, false)
      }

      QfButton {
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        font.pointSize: QfTheme.tinyFont.pointSize
        onClicked: storageMigrateDialog.close()
      }
    }

    function apply(migrate, removeSource) {
      const sourceDir = iface.dataRoot();
      let ok = true;
      if (migrate && sourceDir !== targetDir) {
        displayToast(qsTr("Trwa przenoszenie danych…"));
        ok = iface.migrateDataDir(sourceDir, targetDir, removeSource);
      }
      if (ok) {
        iface.setPreferredDataDir(targetDir);
        displayToast(qsTr("Katalog danych: %1. Uruchom aplikację ponownie.").arg(targetDir));
      } else {
        displayToast(qsTr("Migracja nie powiodła się — katalog pozostaje bez zmian"), "error");
      }
      storageMigrateDialog.close();
    }
  }
}
