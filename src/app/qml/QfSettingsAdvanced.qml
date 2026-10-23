import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import org.qfield.gui // [WF-BUTTONS] QfDecisionButton
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
      text: qsTr('Zaawansowane')
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
      text: qsTr("Aparat")
      font: Theme.strongFont
      color: Theme.mainTextColor
      Layout.fillWidth: true
      Layout.topMargin: 10
      Layout.columnSpan: 2
    }

    Label {
      text: qsTr("Korekta obrotu podglądu i zdjęć (gdy obraz jest odwrócony):")
      font: Theme.defaultFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    ComboBox {
      font: Theme.defaultFont
      model: ["0°", "90°", "180°", "270°"]
      currentIndex: settingsRegistry ? settingsRegistry.cameraRotationOffset / 90 : 0
      onActivated: {
        if (settingsRegistry) {
          settingsRegistry.cameraRotationOffset = currentIndex * 90;
        }
      }
    }

    // WorkFieldGIS 22.10.2026 — „Nowe projekty zakładaj”: pamięć telefonu albo karta SD.
    // Zastępuje stare przenoszenie całego katalogu danych (wyłączone 22.10, commit 4b061777b).
    // Tu NIC nie jest przenoszone. Sekcja widoczna tylko, gdy są dwa miejsca (telefon z kartą).
    ColumnLayout {
      id: miejscaSekcja

      property var miejsca: iface.miejscaProjektow()

      visible: miejsca.length > 1
      Layout.fillWidth: true
      Layout.columnSpan: 2
      Layout.topMargin: 10
      spacing: 2

      Label {
        text: qsTr("Nowe projekty zakładaj")
        font: Theme.strongFont
        color: Theme.mainTextColor
        Layout.fillWidth: true
      }

      Label {
        text: qsTr("Dotyczy nowych projektów i importów. Istniejących projektów nic tu nie przenosi. Na karcie jest zwykle więcej miejsca, ale bywa wolniejsza, a po jej wyjęciu projekty są niedostępne. Odinstalowanie aplikacji kasuje projekty w obu miejscach.")
        font: Theme.tipFont
        color: Theme.secondaryTextColor
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      ButtonGroup {
        id: miejscaGrupa
      }

      Repeater {
        model: miejscaSekcja.miejsca

        delegate: ColumnLayout {
          required property var modelData

          Layout.fillWidth: true
          spacing: 0

          RadioButton {
            ButtonGroup.group: miejscaGrupa
            Layout.fillWidth: true
            font: Theme.defaultFont
            text: modelData.nazwa + " — " + Number(modelData.wolneGb).toFixed(1) + qsTr(" GB wolne") + " · " + qsTr("projektów: %1").arg(modelData.projektow)
            checked: (iface.miejsceDomyslne() === "" ? "telefon" : iface.miejsceDomyslne()) === modelData.rodzaj
            onClicked: {
              iface.ustawMiejsceDomyslne(modelData.rodzaj);
              displayToast(modelData.rodzaj === "karta" ? qsTr("Nowe projekty: na karcie SD") : qsTr("Nowe projekty: w pamięci telefonu"));
            }
          }

          Label {
            Layout.fillWidth: true
            leftPadding: 40
            text: modelData.katalog
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

      QfDecisionButton {
        role: "confirm" // [WF-BUTTONS]
        Layout.fillWidth: true
        text: qsTr("Przenieś dane do nowej lokalizacji")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: storageMigrateDialog.apply(true, true)
      }

      QfDecisionButton {
        role: "confirm" // [WF-BUTTONS]
        Layout.fillWidth: true
        text: qsTr("Skopiuj dane (oryginały zostają)")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: storageMigrateDialog.apply(true, false)
      }

      QfDecisionButton {
        role: "confirm" // [WF-BUTTONS]
        Layout.fillWidth: true
        text: qsTr("Zacznij z pustym katalogiem")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: storageMigrateDialog.apply(false, false)
      }

      QfDecisionButton {
        role: "cancel" // [WF-BUTTONS]
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
