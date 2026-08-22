import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

/**
 * Ustawienia sieciowe: uwierzytelnianie i proxy.
 * `page` wskazuje na QFieldSettings — stamtąd pochodzą właściwości proxy.
 */
GridLayout {
  property var settingsPage

  function syncFromSettings() {
    const typeIdx = proxyTypeComboBox.indexOfValue(settingsPage.proxyType);
    proxyTypeComboBox.currentIndex = typeIdx >= 0 ? typeIdx : 0;
    authenticationConfigurationsListView.model = AuthUtils.authenticationConfigurationDetails();
  }

  Layout.fillWidth: true
  Layout.leftMargin: 20
  Layout.rightMargin: 20

  columns: 2
  columnSpacing: 0
  rowSpacing: 5

  Label {
    text: qsTr('Network')
    font: Theme.strongFont
    color: Theme.mainTextColor
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.topMargin: 10
    Layout.columnSpan: 2
  }

  Label {
    Layout.fillWidth: true
    Layout.columnSpan: 2
    visible: authenticationConfigurationsListView.count > 0
    text: qsTr("Available authentication configurations:")
    font: Theme.defaultFont
    color: Theme.mainTextColor
    wrapMode: Text.WordWrap
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.columnSpan: 2
    Layout.preferredHeight: 140
    visible: authenticationConfigurationsListView.count > 0
    color: Theme.controlBackgroundColor
    border.width: 1
    border.color: Theme.controlBorderColor

    ListView {
      id: authenticationConfigurationsListView
      anchors.fill: parent
      clip: true

      model: []

      delegate: Rectangle {
        width: ListView.view.width
        height: authenticationConfigurationDetailsLayout.childrenRect.height + 10
        color: "transparent"

        ColumnLayout {
          id: authenticationConfigurationDetailsLayout
          width: parent.width - 10
          anchors.horizontalCenter: parent.horizontalCenter

          Text {
            Layout.fillWidth: true
            Layout.topMargin: 5
            font: Theme.defaultFont
            color: Theme.mainTextColor
            text: modelData["name"] + ' (' + modelData["id"] + ')'
            wrapMode: Text.Wrap
          }

          Text {
            Layout.fillWidth: true
            visible: modelData["uri"] !== ""
            font: Theme.tipFont
            color: Theme.secondaryTextColor
            text: modelData["uri"]
            wrapMode: Text.Wrap
          }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          width: parent.width
          height: 1
          color: Theme.controlBorderColor
        }
      }
    }
  }

  QfButton {
    Layout.fillWidth: true
    Layout.columnSpan: 2
    visible: authenticationConfigurationsListView.count > 0

    text: qsTr("Clear authentication cache")

    onClicked: {
      AuthUtils.clearAuthenticationConfigurationCache();
      displayToast(qsTr('Authentication cache cleared'));
    }
  }

  Label {
    text: qsTr("Enable proxy")
    font: Theme.defaultFont
    color: Theme.mainTextColor
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  QfSwitch {
    id: proxyEnabledSwitch
    Layout.preferredWidth: implicitContentWidth
    Layout.alignment: Qt.AlignTop | Qt.AlignRight
    checked: settingsPage.proxyEnabled
    onCheckedChanged: settingsPage.proxyEnabled = checked
  }

  Label {
    text: qsTr("Type")
    font: Theme.defaultFont
    color: proxyEnabledSwitch.checked ? Theme.mainTextColor : Theme.secondaryTextColor
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.columnSpan: 2
    Layout.leftMargin: 8
    visible: proxyEnabledSwitch.checked
  }

  QfComboBox {
    id: proxyTypeComboBox
    enabled: proxyEnabledSwitch.checked
    visible: proxyEnabledSwitch.checked
    Layout.fillWidth: true
    Layout.columnSpan: 2
    Layout.leftMargin: 8
    Layout.alignment: Qt.AlignVCenter
    font: Theme.defaultFont

    popup.font: Theme.defaultFont
    popup.topMargin: mainWindow.sceneTopMargin
    popup.bottomMargin: mainWindow.sceneTopMargin

    model: ListModel {
      ListElement {
        name: qsTr("System default")
        value: "DefaultProxy"
      }
      ListElement {
        name: "HTTP"
        value: "HttpProxy"
      }
      ListElement {
        name: "SOCKS5"
        value: "Socks5Proxy"
      }
    }
    textRole: "name"
    valueRole: "value"

    property bool initialized: false

    onCurrentValueChanged: {
      if (initialized) {
        settingsPage.proxyType = currentValue;
      }
    }

    Component.onCompleted: {
      currentIndex = indexOfValue(settingsPage.proxyType);
      if (currentIndex < 0)
        currentIndex = 0;
      initialized = true;
    }
  }

  Label {
    text: qsTr("Host")
    font: Theme.defaultFont
    color: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy' ? Theme.mainTextColor : Theme.secondaryTextColor
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.leftMargin: 8
    visible: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
  }

  QfTextField {
    id: proxyHostField
    enabled: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
    visible: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
    font: Theme.defaultFont
    Layout.fillWidth: true
    placeholderText: qsTr("e.g. proxy.example.com")
    inputMethodHints: Qt.ImhUrlCharactersOnly
    text: settingsPage.proxyHost
    onTextChanged: settingsPage.proxyHost = text
  }

  Label {
    text: qsTr("Port")
    font: Theme.defaultFont
    color: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy' ? Theme.mainTextColor : Theme.secondaryTextColor
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.leftMargin: 8
    visible: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
  }

  QfTextField {
    id: proxyPortField
    enabled: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
    visible: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
    font: Theme.defaultFont
    Layout.fillWidth: true
    placeholderText: qsTr("e.g. 8888")
    inputMethodHints: Qt.ImhDigitsOnly
    validator: IntValidator {
      bottom: 0
      top: 65535
    }
    text: settingsPage.proxyPort > 0 ? settingsPage.proxyPort : ''
    onTextChanged: settingsPage.proxyPort = text.length > 0 ? parseInt(text) : 0
  }

  Label {
    text: qsTr("Username")
    font: Theme.defaultFont
    color: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy' ? Theme.mainTextColor : Theme.secondaryTextColor
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.leftMargin: 8
    visible: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
  }

  QfTextField {
    id: proxyUserField
    enabled: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
    visible: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
    font: Theme.defaultFont
    Layout.fillWidth: true
    placeholderText: qsTr("Optional")
    text: settingsPage.proxyUser
    onTextChanged: settingsPage.proxyUser = text
  }

  Label {
    text: qsTr("Password")
    font: Theme.defaultFont
    color: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy' ? Theme.mainTextColor : Theme.secondaryTextColor
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.leftMargin: 8
    visible: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
  }

  QfTextField {
    id: proxyPasswordField
    enabled: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
    visible: proxyEnabledSwitch.checked && settingsPage.proxyType !== 'DefaultProxy'
    font: Theme.defaultFont
    Layout.fillWidth: true
    echoMode: TextInput.Password
    placeholderText: qsTr("Optional")
    text: settingsPage.proxyPassword
    onTextChanged: settingsPage.proxyPassword = text
  }

  Label {
    text: qsTr("URLs excluded from proxy (comma-separated)")
    font: Theme.defaultFont
    color: proxyEnabledSwitch.checked ? Theme.mainTextColor : Theme.secondaryTextColor
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.columnSpan: 2
    Layout.leftMargin: 8
    visible: proxyEnabledSwitch.checked
  }

  QfTextField {
    id: proxyExcludedUrlsField
    enabled: proxyEnabledSwitch.checked
    visible: proxyEnabledSwitch.checked
    font: Theme.defaultFont
    Layout.fillWidth: true
    Layout.columnSpan: 2
    Layout.leftMargin: 8
    placeholderText: qsTr("e.g. localhost, 192.168.*")
    text: settingsPage.proxyExcludedUrls
    onTextChanged: settingsPage.proxyExcludedUrls = text
  }

  Label {
    text: qsTr("Configure a network proxy to route QField's traffic through a proxy server. Useful for corporate networks and VPNs.")
    font: Theme.tipFont
    color: Theme.secondaryTextColor
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.columnSpan: 2
  }
}
