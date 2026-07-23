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

  signal openLocatorSettings
  signal openPluginManager

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20
    Layout.bottomMargin: 0

    columns: 2
    columnSpacing: 0
    rowSpacing: 0

    Label {
      text: qsTr('User Interface')
      font: Theme.strongFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.topMargin: 5
      Layout.columnSpan: 2
    }

    Label {
      text: qsTr("Customize search bar")
      font: Theme.defaultFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.topMargin: 5

      MouseArea {
        anchors.fill: parent
        onClicked: showSearchBarSettings.clicked()
      }
    }

    QfToolButton {
      id: showSearchBarSettings
      Layout.preferredWidth: Theme.toolButtonSize
      Layout.preferredHeight: Theme.toolButtonSize
      Layout.alignment: Qt.AlignVCenter
      clip: true

      iconSource: Theme.getThemeVectorIcon("ic_ellipsis_black_24dp")
      iconColor: Theme.mainColor
      bgcolor: "transparent"

      onClicked: {
        openLocatorSettings();
      }
    }

    Label {
      text: qsTr("Manage plugins")
      font: Theme.defaultFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true

      MouseArea {
        anchors.fill: parent
        onClicked: showPluginManagerSettings.clicked()
      }
    }

    QfToolButton {
      id: showPluginManagerSettings
      Layout.preferredWidth: Theme.toolButtonSize
      Layout.preferredHeight: Theme.toolButtonSize
      Layout.alignment: Qt.AlignVCenter
      clip: true

      iconSource: Theme.getThemeVectorIcon("ic_ellipsis_black_24dp")
      iconColor: Theme.mainColor
      bgcolor: "transparent"

      onClicked: {
        openPluginManager();
      }
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
    Layout.bottomMargin: 5
    Layout.topMargin: 5

    columns: 1
    columnSpacing: 0
    rowSpacing: 5

    visible: platformUtilities.capabilities & PlatformUtilities.AdjustBrightness

    Label {
      Layout.fillWidth: true

      text: qsTr('Dim screen when idling')
      font: Theme.defaultFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
    }

    QfSlider {
      id: slider
      Layout.fillWidth: true
      value: settings ? settings.value('dimTimeoutSeconds', 60) : 60
      from: 0
      to: 180
      stepSize: 10
      suffixText: " s"
      implicitHeight: 40

      onMoved: function () {
        iface.setScreenDimmerTimeout(value);
        settings.setValue('dimTimeoutSeconds', value);
      }
    }

    Label {
      Layout.fillWidth: true
      text: qsTr('Time of inactivity in seconds before the screen brightness get be dimmed to preserve battery.')

      font: Theme.tipFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20
    Layout.bottomMargin: 10
    Layout.topMargin: 5

    columns: 1
    columnSpacing: 0
    rowSpacing: 10

    Label {
      Layout.fillWidth: true
      text: qsTr("Appearance:")
      font: Theme.defaultFont
      color: Theme.mainTextColor

      wrapMode: Text.WordWrap
    }

    QfComboBox {
      id: appearanceComboBox
      enabled: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      font: Theme.defaultFont

      popup.font: Theme.defaultFont
      popup.topMargin: mainWindow.sceneTopMargin
      popup.bottomMargin: mainWindow.sceneTopMargin

      model: ListModel {
        ListElement {
          name: qsTr('Follow system appearance')
          value: 'system'
        }
        ListElement {
          name: qsTr('Light theme')
          value: 'light'
        }
        ListElement {
          name: qsTr('Dark theme')
          value: 'dark'
        }
      }
      textRole: "name"
      valueRole: "value"

      property bool initialized: false

      onCurrentValueChanged: {
        if (initialized) {
          Theme.appearance = currentValue;
        }
      }

      Component.onCompleted: {
        currentIndex = indexOfValue(Theme.appearance);
        initialized = true;
      }
    }

    Label {
      Layout.fillWidth: true
      text: qsTr("Font size:")
      font: Theme.defaultFont
      color: Theme.mainTextColor

      wrapMode: Text.WordWrap
    }

    QfComboBox {
      id: fontScaleComboBox
      enabled: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      font: Theme.defaultFont

      popup.font: Theme.defaultFont
      popup.topMargin: mainWindow.sceneTopMargin
      popup.bottomMargin: mainWindow.sceneTopMargin

      model: ListModel {
        ListElement {
          name: qsTr('Tiny')
          value: 0.75
        }
        ListElement {
          name: qsTr('Normal')
          value: 1.0
        }
        ListElement {
          name: qsTr('Large')
          value: 1.5
        }
        ListElement {
          name: qsTr('Extra-large')
          value: 2.0
        }
      }
      textRole: "name"
      valueRole: "value"

      property bool initialized: false

      onCurrentValueChanged: {
        if (initialized) {
          Theme.fontScale = currentValue;
        }
      }

      Component.onCompleted: {
        currentIndex = indexOfValue(Theme.fontScale);
        initialized = true;
      }
    }

    Label {
      Layout.fillWidth: true
      text: qsTr("Language:")
      font: Theme.defaultFont
      color: Theme.mainTextColor

      wrapMode: Text.WordWrap
    }

    QfComboBox {
      id: languageComboBox
      enabled: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      font: Theme.defaultFont

      popup.font: Theme.defaultFont
      popup.topMargin: mainWindow.sceneTopMargin
      popup.bottomMargin: mainWindow.sceneBottomMargin

      property variant languageCodes: undefined
      property string currentLanguageCode: undefined

      onActivated: {
        if (currentLanguageCode != undefined) {
          var newLanguageCode = languageCodes[currentIndex];
          if (newLanguageCode !== currentLanguageCode) {
            iface.changeLanguage(newLanguageCode);
            currentLanguageCode = newLanguageCode;
          }
        }
      }

      Component.onCompleted: {
        var customLanguageCode = settings.value('customLanguage', '');
        var languages = iface.availableLanguages();
        languageCodes = [""].concat(Object.keys(languages));
        var systemLanguage = qsTr("system");
        var systemLanguageSuffix = systemLanguage !== 'system' ? ' (system)' : '';
        var items = [systemLanguage + systemLanguageSuffix];
        languageComboBox.model = items.concat(Object.values(languages));
        languageComboBox.currentIndex = languageCodes.indexOf(customLanguageCode);
        currentLanguageCode = customLanguageCode || '';
      }
    }

    Label {
      text: qsTr("Found a missing or incomplete language? %1Join the translator community.%2").arg('<a href="https://explore.transifex.com/opengisch/qfield-for-qgis/">').arg('</a>')
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      textFormat: Qt.RichText
      wrapMode: Text.WordWrap
      Layout.fillWidth: true

      onLinkActivated: link => {
        Qt.openUrlExternally(link);
      }
    }
  }
}
