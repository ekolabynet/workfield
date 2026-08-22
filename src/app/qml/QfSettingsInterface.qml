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
      font: QfTheme.strongFont
      color: QfTheme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.topMargin: 5
      Layout.columnSpan: 2
    }

    Label {
      text: qsTr("Customize search bar")
      font: QfTheme.defaultFont
      color: QfTheme.mainTextColor
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
      Layout.preferredWidth: QfTheme.toolButtonSize
      Layout.preferredHeight: QfTheme.toolButtonSize
      Layout.alignment: Qt.AlignVCenter
      clip: true

      iconSource: QfTheme.getThemeVectorIcon("ic_ellipsis_black_24dp")
      iconColor: QfTheme.mainColor
      bgcolor: "transparent"

      onClicked: {
        openLocatorSettings();
      }
    }

    Label {
      text: qsTr("Manage plugins")
      font: QfTheme.defaultFont
      color: QfTheme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true

      MouseArea {
        anchors.fill: parent
        onClicked: showPluginManagerSettings.clicked()
      }
    }

    QfToolButton {
      id: showPluginManagerSettings
      Layout.preferredWidth: QfTheme.toolButtonSize
      Layout.preferredHeight: QfTheme.toolButtonSize
      Layout.alignment: Qt.AlignVCenter
      clip: true

      iconSource: QfTheme.getThemeVectorIcon("ic_ellipsis_black_24dp")
      iconColor: QfTheme.mainColor
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

    visible: platformUtilities.capabilities & QfPlatformUtilities.AdjustBrightness

    Label {
      Layout.fillWidth: true

      text: qsTr('Dim screen when idling')
      font: QfTheme.defaultFont
      color: QfTheme.mainTextColor
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

      font: QfTheme.tipFont
      color: QfTheme.secondaryTextColor
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
      font: QfTheme.defaultFont
      color: QfTheme.mainTextColor

      wrapMode: Text.WordWrap
    }

    QfComboBox {
      id: appearanceComboBox
      enabled: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      font: QfTheme.defaultFont

      popup.font: QfTheme.defaultFont
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
          QfTheme.appearance = currentValue;
        }
      }

      Component.onCompleted: {
        currentIndex = indexOfValue(QfTheme.appearance);
        initialized = true;
      }
    }

    Label {
      Layout.fillWidth: true
      text: qsTr("Font size:")
      font: QfTheme.defaultFont
      color: QfTheme.mainTextColor

      wrapMode: Text.WordWrap
    }

    QfComboBox {
      id: fontScaleComboBox
      enabled: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      font: QfTheme.defaultFont

      popup.font: QfTheme.defaultFont
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
          QfTheme.fontScale = currentValue;
        }
      }

      Component.onCompleted: {
        currentIndex = indexOfValue(QfTheme.fontScale);
        initialized = true;
      }
    }

    Label {
      Layout.fillWidth: true
      text: qsTr("Language:")
      font: QfTheme.defaultFont
      color: QfTheme.mainTextColor

      wrapMode: Text.WordWrap
    }

    QfComboBox {
      id: languageComboBox
      enabled: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      font: QfTheme.defaultFont

      popup.font: QfTheme.defaultFont
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
      font: QfTheme.tipFont
      color: QfTheme.secondaryTextColor
      textFormat: Qt.RichText
      wrapMode: Text.WordWrap
      Layout.fillWidth: true

      onLinkActivated: link => {
        Qt.openUrlExternally(link);
      }
    }
  }
}
