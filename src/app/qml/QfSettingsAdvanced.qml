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
      text: qsTr('Advanced')
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
    columnSpacing: 10
    rowSpacing: 5

    Label {
      text: qsTr("Autozapis projektu")
      font: Theme.strongFont
      color: Theme.mainTextColor
      Layout.fillWidth: true
      Layout.topMargin: 10
      Layout.columnSpan: 2
    }

    Label {
      text: qsTr("Zapisuj projekt automatycznie co (minuty, 0 = wyłączone):")
      font: Theme.defaultFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    SpinBox {
      from: 0
      to: 120
      editable: true
      font: Theme.defaultFont
      value: settingsRegistry ? settingsRegistry.projectAutoSaveInterval : 5
      onValueModified: {
        if (settingsRegistry) {
          settingsRegistry.projectAutoSaveInterval = value;
        }
      }
    }

    Label {
      text: qsTr("Katalog danych")
      font: Theme.strongFont
      color: Theme.mainTextColor
      Layout.fillWidth: true
      Layout.topMargin: 10
      Layout.columnSpan: 2
    }

    Label {
      text: qsTr("Miejsce przechowywania projektów, szablonów i pobranych danych. Dotknij lokalizacji (także zaznaczonej), aby przenieść, skopiować lub zacząć od nowa. Po zmianie uruchom aplikację ponownie.")
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.columnSpan: 2
    }

    Column {
      Layout.fillWidth: true
      Layout.columnSpan: 2
      spacing: 2

      Repeater {
        model: platformUtilities.appDataDirs()

        delegate: Column {
          width: parent.width

          RadioButton {
            id: dirRadio
            width: parent.width
            font: Theme.defaultFont
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
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
            elide: Text.ElideMiddle
          }
        }
      }
    }
  }

  Dialog {
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
        font: Theme.defaultFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Przenieś dane do nowej lokalizacji")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: storageMigrateDialog.apply(true, true)
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Skopiuj dane (oryginały zostają)")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: storageMigrateDialog.apply(true, false)
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Zacznij z pustym katalogiem")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: storageMigrateDialog.apply(false, false)
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Anuluj")
        font.pointSize: Theme.tinyFont.pointSize
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
