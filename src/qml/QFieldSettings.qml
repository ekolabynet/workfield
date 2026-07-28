import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import org.qfield
import Theme

/**
 * \ingroup qml
 */
Page {
  id: page

  signal finished

  readonly property var categoryTitles: ({
      "mapCanvas": qsTr("Obszar mapy"),
      "digitizing": qsTr("Digitalizacja i edycja"),
      "interface": qsTr("Interfejs"),
      "positioning": qsTr("Lokalizacja"),
      "network": qsTr("Sieć"),
      "advanced": qsTr("Zaawansowane"),
      "variables": qsTr("Zmienne")
    })

  property var networkSettingsItem: null
  property var positioningModelItem: null
  property var positioningComboItem: null
  property var variableEditorItem: null

  property string currentPanel: ""
  onCurrentPanelChanged: if (currentPanel !== "")
    openCategory(currentPanel)

  property alias projectAutoSaveInterval: registry.projectAutoSaveInterval
  property alias showScaleBar: registry.showScaleBar
  property alias showZoomControls: registry.showZoomControls
  property alias fullScreenIdentifyView: registry.fullScreenIdentifyView
  property alias locatorKeepScale: registry.locatorKeepScale
  property alias autoOpenFormSingleIdentify: registry.autoOpenFormSingleIdentify
  property alias autoZoomToIdentifiedFeature: registry.autoZoomToIdentifiedFeature
  property alias numericalDigitizingInformation: registry.numericalDigitizingInformation
  property alias showBookmarks: registry.showBookmarks
  property alias nativeCamera2: registry.nativeCamera2
  property alias digitizingVolumeKeys: registry.digitizingVolumeKeys
  property alias autoSave: registry.autoSave
  property alias fingerTapDigitizing: registry.fingerTapDigitizing
  property alias mouseAsTouchScreen: registry.mouseAsTouchScreen
  property alias enableInfoCollection: registry.enableInfoCollection
  property alias enableMapRotation: registry.enableMapRotation
  property alias quality: registry.quality
  property alias coordinateCursorShape: registry.coordinateCursorShape
  property alias previewJobsEnabled: registry.previewJobsEnabled
  property alias snapToCommonAngleIsEnabled: registry.snapToCommonAngleIsEnabled
  property alias snapToCommonAngleIsRelative: registry.snapToCommonAngleIsRelative
  property alias snapToCommonAngleDegrees: registry.snapToCommonAngleDegrees
  property alias snapToCommonAngleTolerance: registry.snapToCommonAngleTolerance

  property alias enableNavigation: registry.enableNavigation

  property bool proxyEnabled: false
  property string proxyType: "DefaultProxy"
  property string proxyHost: ""
  property int proxyPort: 0
  property string proxyUser: ""
  property string proxyPassword: ""
  property string proxyExcludedUrls: ""

  // Guard to avoid writing back to QSettings during the initial load from QSettings.
  property bool proxySettingsLoaded: false

  onProxyEnabledChanged: {
    if (proxySettingsLoaded) {
      settings.setValue('proxy/proxy-enabled', proxyEnabled);
    }
  }
  onProxyTypeChanged: {
    if (proxySettingsLoaded) {
      settings.setValue('proxy/proxy-type', proxyType);
    }
  }
  onProxyHostChanged: {
    if (proxySettingsLoaded) {
      settings.setValue('proxy/proxy-host', proxyHost);
    }
  }
  onProxyPortChanged: {
    if (proxySettingsLoaded) {
      settings.setValue('proxy/proxy-port', proxyPort);
    }
  }
  onProxyUserChanged: {
    if (proxySettingsLoaded) {
      settings.setValue('proxy/proxy-user', proxyUser);
    }
  }
  onProxyPasswordChanged: {
    if (proxySettingsLoaded) {
      settings.setValue('proxy/proxy-password', proxyPassword);
    }
  }
  onProxyExcludedUrlsChanged: {
    if (proxySettingsLoaded) {
      settings.setValue('proxy/proxy-excluded-urls', proxyExcludedUrls);
    }
  }

  leftPadding: mainWindow.sceneLeftMargin
  rightPadding: mainWindow.sceneRightMargin

  visible: false
  focus: visible

  Component.onCompleted: {
    if (settings.valueBool('nativeCameraLaunched', false)) {
      // a crash occured while the native camera was launched, disable it
      nativeCamera2 = false;
    }
    proxyEnabled = settings.valueBool('proxy/proxy-enabled', false);
    proxyType = settings.value('proxy/proxy-type', 'DefaultProxy');
    proxyHost = settings.value('proxy/proxy-host', '');
    proxyPort = settings.valueInt('proxy/proxy-port', 0);
    proxyUser = settings.value('proxy/proxy-user', '');
    proxyPassword = settings.value('proxy/proxy-password', '');
    const excludedRaw = settings.value('proxy/proxy-excluded-urls', '');
    proxyExcludedUrls = Array.isArray(excludedRaw) ? excludedRaw.join(', ') : (excludedRaw || '');
    proxySettingsLoaded = true;

    if (networkSettingsItem)
      networkSettingsItem.syncFromSettings();
  }

  function reset() {
    if (variableEditorItem)
      variableEditorItem.reset();
  }

  function applyProxySettings() {
    iface.setupNetworkProxy();
  }

  Settings {
    id: registry
    property bool enableNavigation: false
    property bool showScaleBar: true
    property bool showZoomControls: false
    property bool fullScreenIdentifyView: false
    property bool locatorKeepScale: false
    property bool autoOpenFormSingleIdentify: true
    property bool autoZoomToIdentifiedFeature: false
    property bool numericalDigitizingInformation: false
    property bool showBookmarks: true
    property bool nativeCamera2: false
    property bool digitizingVolumeKeys: platformUtilities.capabilities & PlatformUtilities.VolumeKeys
    property bool autoSave: false
    property bool fingerTapDigitizing: false
    property bool mouseAsTouchScreen: false
    property bool enableInfoCollection: true
    property bool enableMapRotation: true
    property double quality: 1.0
    property int coordinateCursorShape: 3
    property int projectAutoSaveInterval: 5
    property bool previewJobsEnabled: true

    property bool snapToCommonAngleIsEnabled: false
    property bool snapToCommonAngleIsRelative: true
    property double snapToCommonAngleDegrees: 45.0// = settings.valueInt("/QField/Digitizing/SnapToCommonAngleDegrees", 45);
    property int snapToCommonAngleTolerance: 1// = settings.valueInt("/QField/Digitizing/SnappingTolerance", 1);

    onEnableInfoCollectionChanged: {
      if (enableInfoCollection) {
        iface.initiateSentry();
      } else {
        iface.closeSentry();
      }
    }

    onDigitizingVolumeKeysChanged: {
      platformUtilities.setHandleVolumeKeys(digitizingVolumeKeys && stateMachine.state != 'browse');
    }

    onFingerTapDigitizingChanged: {
      coordinateLocator.sourceLocation = undefined;
    }
  }

  ListModel {
    id: canvasSettingsModel
    ListElement {
      title: qsTr("Show scale bar")
      description: ''
      settingAlias: "showScaleBar"
      isVisible: true
    }
    ListElement {
      title: qsTr("Show zoom controls")
      description: ''
      settingAlias: "showZoomControls"
      isVisible: true
    }
    ListElement {
      title: qsTr("Show bookmarks")
      description: qsTr("When switched on, user's saved and currently opened project bookmarks will be displayed on the map.")
      settingAlias: "showBookmarks"
      isVisible: true
    }
    ListElement {
      title: qsTr("Enable map rotation")
      description: qsTr("When switched on, the map can be rotated by the user.")
      settingAlias: "enableMapRotation"
      isVisible: true
    }
  }

  ListModel {
    id: digitizingEditingSettingsModel
    ListElement {
      title: qsTr("Show digitizing information")
      description: qsTr("When switched on, coordinate information, such as latitude and longitude, is overlayed onto the map while digitizing new features or using the measure tool.")
      settingAlias: "numericalDigitizingInformation"
      isVisible: true
    }
    ListElement {
      title: qsTr("Use volume keys to digitize")
      description: qsTr("If enabled, pressing the device's volume up key will add a vertex while pressing volume down key will remove the last entered vertex during digitizing sessions.")
      settingAlias: "digitizingVolumeKeys"
      isVisible: true
    }
    ListElement {
      title: qsTr("Allow finger tap on canvas to add vertices")
      description: qsTr("When enabled, tapping on the map canvas with a finger moves the coordinate cursor while double tapping adds a vertex.")
      settingAlias: "fingerTapDigitizing"
      isVisible: true
    }
    ListElement {
      title: qsTr("Consider mouse as a touchscreen device")
      description: qsTr("When enabled, the mouse will act as if it was a finger. When disabled, the mouse will match the stylus behavior.")
      settingAlias: "mouseAsTouchScreen"
      isVisible: true
    }
    Component.onCompleted: {
      for (var i = 0; i < count; i++) {
        if (get(i).settingAlias === 'digitizingVolumeKeys') {
          setProperty(i, 'isVisible', platformUtilities.capabilities & PlatformUtilities.VolumeKeys ? true : false);
        } else {
          setProperty(i, 'isVisible', true);
        }
      }
    }
  }

  ListModel {
    id: interfaceSettingsModel

    ListElement {
      title: qsTr("Nawigacja do obiektu")
      description: qsTr("Pokazuje kierunek i odległość do wybranego obiektu.")
      settingAlias: "enableNavigation"
      isVisible: true
    }
    ListElement {
      title: qsTr("Maximize feature form")
      description: ''
      settingAlias: "fullScreenIdentifyView"
      isVisible: true
    }
    ListElement {
      title: qsTr("Open feature form for single feature identification")
      description: qsTr("When enabled, the feature form will open automatically if only one feature is identified, skipping the feature list.")
      settingAlias: "autoOpenFormSingleIdentify"
      isVisible: true
    }
    ListElement {
      title: qsTr("Fixed scale navigation")
      description: qsTr("When fixed scale navigation is active, focusing on a search result will pan to the feature. With fixed scale navigation disabled it will pan and zoom to the feature.")
      settingAlias: "locatorKeepScale"
      isVisible: true
    }
    ListElement {
      title: qsTr("Auto-zoom to identified feature(s)")
      description: qsTr("When enabled, the map will automatically zoom to show all identified features, as well as the individual selected feature when the feature form is opened.")
      settingAlias: "autoZoomToIdentifiedFeature"
      isVisible: true
    }
  }

  ListModel {
    id: advancedSettingsModel
    ListElement {
      title: qsTr("Render preview content around visible map canvas")
      description: qsTr("If enabled, areas just outside of the visible map canvas extent will be partially rendered to allow preview when zooming and panning.")
      settingAlias: "previewJobsEnabled"
      isVisible: true
    }
    ListElement {
      title: qsTr("Enable auto-save mode")
      description: qsTr("If enabled, newly-added features are stored as soon as it has having a valid geometry and the constraints are fulfilled and edited atributes are commited immediately.")
      settingAlias: "autoSave"
      isVisible: true
    }
    ListElement {
      title: qsTr("Use native camera")
      description: qsTr("If enabled, the native camera provided by the operating system will be used.")
      settingAlias: "nativeCamera2"
      isVisible: true
    }
    ListElement {
      title: qsTr("Send anonymized metrics")
      description: qsTr("If enabled, anonymized metrics will be collected and sent to help improve the user experience for everyone.")
      settingAlias: "enableInfoCollection"
      isVisible: true
    }
    Component.onCompleted: {
      for (var i = 0; i < count; i++) {
        if (get(i).settingAlias === 'nativeCamera2') {
          setProperty(i, 'isVisible', platformUtilities.capabilities & PlatformUtilities.NativeCamera ? true : false);
        } else if (get(i).settingAlias === 'enableInfoCollection') {
          setProperty(i, 'isVisible', platformUtilities.capabilities & PlatformUtilities.SentryFramework ? true : false);
        } else {
          setProperty(i, 'isVisible', true);
        }
      }
    }
  }

  Rectangle {
    color: Theme.mainBackgroundColor
    anchors.fill: parent
  }

  ColumnLayout {
    id: barColumn
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
      bottom: parent.bottom
    }

    Component {
      id: listItem

      Rectangle {
        width: parent ? parent.width - 16 : undefined
        height: isVisible ? line.height : 0
        color: "transparent"
        clip: true

        Row {
          id: line
          width: parent.width

          Column {
            width: parent.width - toggle.width

            Label {
              width: parent.width
              padding: 8
              leftPadding: 20
              text: title
              font: Theme.defaultFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              MouseArea {
                anchors.fill: parent
                onClicked: toggle.toggle()
              }
            }

            Label {
              width: parent.width
              visible: description !== ''
              padding: description !== '' ? 8 : 0
              topPadding: 0
              leftPadding: 20
              text: description
              font: Theme.tipFont
              color: Theme.secondaryTextColor
              wrapMode: Text.WordWrap
            }
          }

          QfSwitch {
            id: toggle
            width: implicitContentWidth
            checked: registry[settingAlias]
            Layout.alignment: Qt.AlignTop | Qt.AlignRight
            onCheckedChanged: registry[settingAlias] = checked
          }
        }
      }
    }

    StackView {
      id: settingsStack
      Layout.fillHeight: true
      Layout.fillWidth: true
      clip: true

      initialItem: QfSettingsIndex {
        t: Theme
        onCategorySelected: categoryId => page.openCategory(categoryId)
      }
    }
  }

  PositioningDeviceSettings {
    id: positioningDeviceSettings

    property string originalName: ''

    onApply: {
      if (originalName != '') {
        positioningModelItem.removeDevice(originalName);
      }
      var name = positioningDeviceSettings.name;
      var type = positioningDeviceSettings.type;
      var settings = positioningDeviceSettings.getSettings();
      if (name === '') {
        name = positioningDeviceSettings.generateName();
      }
      if (!positioningModelItem)
        return;
      var index = positioningModelItem.addDevice(type, name, settings);
      if (positioningComboItem)
        positioningComboItem.currentIndex = index;
    }
  }

  PositioningNtripSettings {
    id: positioningNtripSettings

    onApply: {
      positioningSettings.ntripSettings = createSettingsMap();
    }
  }

  Component {
    id: positioningPage
    Item {
      ScrollView {
        topPadding: 5
        leftPadding: 20
        rightPadding: 20
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: QfScrollBar {}
        contentWidth: positioningGrid.width
        contentHeight: positioningGrid.height
        anchors.fill: parent
        clip: true

        ColumnLayout {
          id: positioningGrid
          width: parent.parent.width
          spacing: 10

          GridLayout {
            Layout.fillWidth: true

            columns: 2
            columnSpacing: 0
            rowSpacing: 5

            Label {
              text: qsTr('Positioning Device')
              font: Theme.strongFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              Layout.topMargin: 5
              Layout.bottomMargin: 5
              Layout.columnSpan: 2
            }

            Label {
              Layout.fillWidth: true
              Layout.columnSpan: 2
              text: qsTr("Positioning device in use:")
              font: Theme.defaultFont
              color: Theme.mainTextColor

              wrapMode: Text.WordWrap
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.columnSpan: 2

              QfComboBox {
                id: positioningDeviceComboBox
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                font: Theme.defaultFont

                popup.font: Theme.defaultFont
                popup.topMargin: mainWindow.sceneTopMargin
                popup.bottomMargin: mainWindow.sceneTopMargin

                textRole: 'DeviceName'
                valueRole: 'DeviceType'
                model: PositioningDeviceModel {
                  id: positioningDeviceModel
                  Component.onCompleted: page.positioningModelItem = positioningDeviceModel
                }

                delegate: ItemDelegate {
                  width: positioningDeviceComboBox.width
                  height: 36
                  icon.source: {
                    switch (DeviceType) {
                    case PositioningDeviceModel.InternalDevice:
                      return Theme.getThemeVectorIcon('ic_internal_receiver_black_24dp');
                    case PositioningDeviceModel.FileDevice:
                      return Theme.getThemeVectorIcon("ic_file_black_24dp");
                    case PositioningDeviceModel.BluetoothDevice:
                      return Theme.getThemeVectorIcon('ic_bluetooth_receiver_black_24dp');
                    case PositioningDeviceModel.TcpDevice:
                      return Theme.getThemeVectorIcon('ic_tcp_receiver_black_24dp');
                    case PositioningDeviceModel.UdpDevice:
                      return Theme.getThemeVectorIcon('ic_udp_receiver_black_24dp');
                    case PositioningDeviceModel.SerialPortDevice:
                      return Theme.getThemeVectorIcon('ic_serial_port_receiver_black_24dp');
                    case PositioningDeviceModel.EgenioussDevice:
                      return Theme.getThemeVectorIcon('ic_egeniouss_receiver_black_24dp');
                    }
                    return '';
                  }
                  icon.width: 24
                  icon.height: 24
                  text: DeviceName
                  font: Theme.defaultFont
                  highlighted: positioningDeviceComboBox.highlightedIndex === index
                }

                contentItem: MenuItem {
                  width: positioningDeviceComboBox.width
                  height: 36

                  icon.source: {
                    switch (positioningDeviceComboBox.currentValue) {
                    case PositioningDeviceModel.InternalDevice:
                      return Theme.getThemeVectorIcon('ic_internal_receiver_black_24dp');
                    case PositioningDeviceModel.FileDevice:
                      return Theme.getThemeVectorIcon("ic_file_black_24dp");
                    case PositioningDeviceModel.BluetoothDevice:
                      return Theme.getThemeVectorIcon('ic_bluetooth_receiver_black_24dp');
                    case PositioningDeviceModel.TcpDevice:
                      return Theme.getThemeVectorIcon('ic_tcp_receiver_black_24dp');
                    case PositioningDeviceModel.UdpDevice:
                      return Theme.getThemeVectorIcon('ic_udp_receiver_black_24dp');
                    case PositioningDeviceModel.SerialPortDevice:
                      return Theme.getThemeVectorIcon('ic_serial_port_receiver_black_24dp');
                    case PositioningDeviceModel.EgenioussDevice:
                      return Theme.getThemeVectorIcon('ic_egeniouss_receiver_black_24dp');
                    }
                    return '';
                  }
                  icon.width: 24
                  icon.height: 24

                  text: positioningDeviceComboBox.currentText
                  font: Theme.defaultFont

                  onClicked: positioningDeviceComboBox.popup.open()
                }

                Connections {
                  target: positionSource

                  function onDeviceIdChanged() {
                    verticalGridShiftComboBox.reload();
                  }
                }

                property bool loaded: false

                onCurrentIndexChanged: {
                  if (loaded && currentIndex !== -1) {
                    const modelIndex = positioningDeviceModel.index(currentIndex, 0);
                    positioningSettings.positioningDevice = positioningDeviceModel.data(modelIndex, PositioningDeviceModel.DeviceId);
                    positioningSettings.positioningDeviceName = positioningDeviceModel.data(modelIndex, PositioningDeviceModel.DeviceName);
                  }
                }

                Component.onCompleted: {
                  page.positioningComboItem = positioningDeviceComboBox;
                  currentIndex = positioningDeviceModel.findIndexFromDeviceId(positioningSettings.positioningDevice);
                  loaded = true;
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.columnSpan: 2

              QfButton {
                leftPadding: 10
                rightPadding: 10
                text: qsTr('Add')

                onClicked: {
                  positioningDeviceSettings.originalName = '';
                  positioningDeviceSettings.name = '';
                  positioningDeviceSettings.open();
                }
              }

              Item {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
              }

              QfButton {
                leftPadding: 10
                rightPadding: 10
                text: qsTr('Edit')
                enabled: positioningDeviceComboBox.currentIndex > 0

                onClicked: {
                  var modelIndex = positioningDeviceModel.index(positioningDeviceComboBox.currentIndex, 0);
                  var name = positioningDeviceModel.data(modelIndex, PositioningDeviceModel.DeviceName);
                  positioningDeviceSettings.originalName = name;
                  positioningDeviceSettings.name = name;
                  positioningDeviceSettings.setType(positioningDeviceModel.data(modelIndex, PositioningDeviceModel.DeviceType));
                  positioningDeviceSettings.setSettings(positioningDeviceModel.data(modelIndex, PositioningDeviceModel.DeviceSettings));
                  positioningDeviceSettings.open();
                }
              }

              QfButton {
                leftPadding: 10
                rightPadding: 10
                text: qsTr('Remove')
                enabled: positioningDeviceComboBox.currentIndex > 0

                onClicked: {
                  var modelIndex = positioningDeviceModel.index(positioningDeviceComboBox.currentIndex, 0);
                  positioningDeviceComboBox.currentIndex = 0;
                  positioningDeviceModel.removeDevice(positioningDeviceModel.data(modelIndex, PositioningDeviceModel.DeviceName));
                }
              }
            }

            QfButton {
              id: connectButton
              Layout.fillWidth: true
              Layout.columnSpan: 2
              Layout.topMargin: 5
              text: {
                switch (positionSource.deviceSocketState) {
                case QAbstractSocket.ConnectedState:
                case QAbstractSocket.BoundState:
                  return qsTr('Connected to %1').arg(positioningSettings.positioningDeviceName.trim());
                case QAbstractSocket.UnconnectedState:
                  return qsTr('Connect to %1').arg(positioningSettings.positioningDeviceName.trim());
                default:
                  return qsTr('Connecting to %1').arg(positioningSettings.positioningDeviceName.trim());
                }
              }
              enabled: positionSource.deviceSocketState === QAbstractSocket.UnconnectedState
              visible: positionSource.deviceId !== ''

              onClicked: {
                // make sure positioning is active when connecting to the bluetooth device
                if (!positioningSettings.positioningActivated) {
                  positioningSettings.positioningActivated = true;
                } else {
                  positionSource.triggerConnectDevice();
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.columnSpan: 2
              visible: positionSource.deviceCapabilities & AbstractGnssReceiver.NtripCorrection

              Label {
                text: qsTr("Enable NTRIP corrections")
                font: Theme.defaultFont
                color: Theme.mainTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true

                MouseArea {
                  anchors.fill: parent
                  onClicked: enableNtripClient.toggle()
                }
              }

              QfToolButton {
                id: showNtripSettings
                Layout.preferredWidth: Theme.toolButtonSize
                Layout.preferredHeight: Theme.toolButtonSize
                Layout.alignment: Qt.AlignVCenter

                iconSource: Theme.getThemeVectorIcon("ic_tune_white_24dp")
                iconColor: Theme.mainTextColor
                bgcolor: "transparent"
                clip: true

                onClicked: {
                  positioningNtripSettings.updateFromNtripSettings(PositioningUtils.createNtripSettings(positioningSettings.ntripSettings));
                  positioningNtripSettings.open();
                }
              }

              QfSwitch {
                id: enableNtripClient
                Layout.preferredWidth: implicitContentWidth
                Layout.alignment: Qt.AlignVCenter
                checked: positioningSettings.enableNtrip && positionSource.ntripState !== Positioning.NtripState.Disconnected
                visible: enabled

                onClicked: {
                  if (positioningSettings.enableNtrip) {
                    if (positionSource.ntripSettings.isValid && positionSource.ntripState === Positioning.NtripState.Disconnected) {
                      // The server has disconnected, tapping on the toggle must indicate an intent to reconnect
                      positioningSettings.enableNtrip = false;
                      positioningSettings.enableNtrip = true;
                    } else {
                      positioningSettings.enableNtrip = false;
                    }
                  } else {
                    positioningSettings.enableNtrip = true;
                  }
                }
              }
            }

            GridLayout {
              id: ntripFeedbackLayout
              Layout.fillWidth: true
              Layout.rightMargin: 6
              Layout.columnSpan: 2
              columns: 2
              columnSpacing: 2
              rowSpacing: 2
              visible: positioningSettings.enableNtrip && positionSource.deviceCapabilities & AbstractGnssReceiver.NtripCorrection

              Label {
                Layout.fillWidth: true
                font: Theme.tipFont
                color: Theme.secondaryTextColor
                wrapMode: Text.WordWrap
                text: {
                  if (positionSource.ntripSettings.isValid) {
                    switch (positionSource.ntripState) {
                    case Positioning.NtripState.Disconnected:
                      return qsTr("NTRIP client disconnected");
                    case Positioning.NtripState.Connecting:
                      return qsTr("NTRIP client connecting");
                    case Positioning.NtripState.Connected:
                      return qsTr("NTRIP client connected");
                    }
                  } else {
                    return qsTr("Please provide valid NTRIP settings");
                  }
                }
              }

              RowLayout {
                Layout.alignment: Qt.AlignRight

                Label {
                  visible: positionSource.ntripState === Positioning.NtripState.Connected
                  font: Theme.tipFont
                  color: Theme.secondaryTextColor
                  wrapMode: Text.WordWrap
                  text: {
                    if (page.visible && positionSource.ntripState === Positioning.NtripState.Connected) {
                      return "↑" + positionSource.ntripBytesSent + " ↓" + positionSource.ntripBytesReceived;
                    }
                    return '';
                  }
                }

                Rectangle {
                  id: ntripIndicator
                  Layout.alignment: Qt.AlignVCenter
                  Layout.bottomMargin: 1
                  Layout.preferredWidth: 12
                  Layout.preferredHeight: 12
                  radius: height / 2
                  opacity: 1
                  color: {
                    if (positionSource.ntripState === Positioning.NtripState.Connected) {
                      return positionSource.ntripCurrentness ? Theme.positionColor : Theme.warningColor;
                    }
                    return Theme.secondaryTextColor;
                  }

                  SequentialAnimation {
                    running: page.visible && positionSource.ntripState === Positioning.NtripState.Connected && !positionSource.ntripCurrentness
                    loops: Animation.Infinite

                    onStopped: ntripIndicator.opacity = 1.0

                    NumberAnimation {
                      target: ntripIndicator
                      property: "opacity"
                      to: 0.0
                      duration: 1000
                      easing.type: Easing.InOutQuad
                    }

                    NumberAnimation {
                      target: ntripIndicator
                      property: "opacity"
                      to: 1.0
                      duration: 1000
                      easing.type: Easing.InOutQuad
                    }
                  }
                }
              }

              Label {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                visible: positionSource.ntripState === Positioning.NtripState.Connected
                font: Theme.tipFont
                color: Theme.secondaryTextColor
                wrapMode: Text.WordWrap
                text: positionSource.ntripSettings.mountPoint
              }
            }
          }

          GridLayout {
            Layout.fillWidth: true

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
              Layout.bottomMargin: 2
              Layout.columnSpan: 2
            }

            Label {
              text: qsTr("Show position information")
              font: Theme.defaultFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true

              MouseArea {
                anchors.fill: parent
                onClicked: showPositionInformation.toggle()
              }
            }

            QfSwitch {
              id: showPositionInformation
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignTop
              checked: positioningSettings.showPositionInformation
              onCheckedChanged: {
                positioningSettings.showPositionInformation = checked;
              }
            }

            Label {
              id: positionFollowModeLabel
              Layout.fillWidth: true
              Layout.columnSpan: 2
              text: qsTr("Behavior when locked to position:")
              font: Theme.defaultFont
              color: Theme.mainTextColor

              wrapMode: Text.WordWrap
            }

            QfComboBox {
              id: positionFollowModeComboBox
              Layout.fillWidth: true
              Layout.columnSpan: 2
              Layout.alignment: Qt.AlignVCenter
              font: Theme.defaultFont
              model: [qsTr("Follow position only"), qsTr("Follow position and compass orientation"), qsTr("Follow position and movement direction")]

              popup.font: Theme.defaultFont
              popup.topMargin: mainWindow.sceneTopMargin
              popup.bottomMargin: mainWindow.sceneTopMargin

              property bool loaded: false

              Component.onCompleted: {
                positionFollowModeComboBox.currentIndex = positioningSettings.positionFollowMode;
                loaded = true;
              }

              onCurrentIndexChanged: {
                if (loaded) {
                  positioningSettings.positionFollowMode = currentIndex;
                }
              }
            }

            Label {
              id: positionFollowModeTipLabel
              Layout.fillWidth: true
              text: qsTr("When the map canvas is following or locked to position, it can also rotate to match compass orientation or movement direction.")
              font: Theme.tipFont
              color: Theme.secondaryTextColor

              wrapMode: Text.WordWrap
            }

            Label {
              text: qsTr('Digitizing & Editing')
              font: Theme.strongFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              Layout.topMargin: 10
              Layout.bottomMargin: 5
              Layout.columnSpan: 2
            }

            Label {
              id: measureLabel
              Layout.fillWidth: true
              Layout.columnSpan: 2
              text: qsTr("Measure (M) value attached to vertices:")
              font: Theme.defaultFont
              color: Theme.mainTextColor

              wrapMode: Text.WordWrap
            }

            QfComboBox {
              id: measureComboBox
              Layout.fillWidth: true
              Layout.columnSpan: 2
              Layout.alignment: Qt.AlignVCenter
              font: Theme.defaultFont

              popup.font: Theme.defaultFont
              popup.topMargin: mainWindow.sceneTopMargin
              popup.bottomMargin: mainWindow.sceneTopMargin

              property bool loaded: false
              Component.onCompleted: {
                // This list matches the Tracker::MeasureType enum, with SecondsSinceStart removed
                var measurements = [qsTr("Timestamp (seconds since epoch)"), qsTr("Ground speed"), qsTr("Bearing"), qsTr("Horizontal accuracy"), qsTr("Vertical accuracy"), qsTr("PDOP"), qsTr("HDOP"), qsTr("VDOP")];
                measureComboBox.model = measurements;
                measureComboBox.currentIndex = positioningSettings.digitizingMeasureType - 1;
                loaded = true;
              }

              onCurrentIndexChanged: {
                if (loaded) {
                  positioningSettings.digitizingMeasureType = currentIndex + 1;
                }
              }
            }

            Label {
              id: measureTipLabel
              Layout.fillWidth: true
              text: qsTr("When digitizing features with the coordinate cursor locked to the current position, the measurement type selected above will be added to the geometry provided it has an M dimension.")
              font: Theme.tipFont
              color: Theme.secondaryTextColor

              wrapMode: Text.WordWrap
            }

            Item {
              // spacer item
              Layout.fillWidth: true
              Layout.fillHeight: true
            }

            Label {
              text: qsTr("Activate accuracy indicator")
              font: Theme.defaultFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true

              MouseArea {
                anchors.fill: parent
                onClicked: accuracyIndicator.toggle()
              }
            }

            QfSwitch {
              id: accuracyIndicator
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignTop
              checked: positioningSettings.accuracyIndicator
              onCheckedChanged: {
                positioningSettings.accuracyIndicator = checked;
              }
            }

            RowLayout {
              Layout.columnSpan: 2
              Layout.fillWidth: true
              visible: accuracyIndicator.checked
              enabled: accuracyIndicator.checked

              Label {
                text: qsTr("Bad accuracy threshold")
                font: Theme.defaultFont
                color: Theme.mainTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }

              QfTextField {
                id: accuracyBadInput
                font: Theme.defaultFont
                horizontalAlignment: TextInput.AlignRight
                suffixText: qsTr("m")
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: DoubleValidator {
                  locale: 'C'
                }

                Component.onCompleted: {
                  text = isNaN(positioningSettings.accuracyBad) ? '' : positioningSettings.accuracyBad;
                }

                onTextChanged: {
                  if (text.length === 0 || isNaN(text)) {
                    positioningSettings.accuracyBad = NaN;
                  } else {
                    positioningSettings.accuracyBad = parseFloat(text);
                  }
                }
              }
            }

            RowLayout {
              Layout.columnSpan: 2
              Layout.fillWidth: true
              visible: accuracyIndicator.checked
              enabled: accuracyIndicator.checked

              Label {
                text: qsTr("Excellent accuracy threshold")
                font: Theme.defaultFont
                color: Theme.mainTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }

              QfTextField {
                id: accuracyExcellentInput
                font: Theme.defaultFont
                horizontalAlignment: TextInput.AlignRight
                suffixText: qsTr("m")
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: DoubleValidator {
                  locale: 'C'
                }

                Component.onCompleted: {
                  text = isNaN(positioningSettings.accuracyExcellent) ? '' : positioningSettings.accuracyExcellent;
                }

                onTextChanged: {
                  if (text.length === 0 || isNaN(text)) {
                    positioningSettings.accuracyExcellent = NaN;
                  } else {
                    positioningSettings.accuracyExcellent = parseFloat(text);
                  }
                }
              }
            }

            Label {
              text: qsTr("Enforce accuracy requirement")
              font: Theme.defaultFont
              color: Theme.mainTextColor
              enabled: accuracyIndicator.checked
              visible: accuracyIndicator.checked
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              Layout.leftMargin: 8

              MouseArea {
                anchors.fill: parent
                onClicked: accuracyIndicator.toggle()
              }
            }

            QfSwitch {
              id: accuracyRequirement
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignTop
              enabled: accuracyIndicator.checked
              visible: accuracyIndicator.checked
              checked: positioningSettings.accuracyRequirement
              onCheckedChanged: {
                positioningSettings.accuracyRequirement = checked;
              }
            }

            Label {
              text: qsTr("When the accuracy indicator is enabled, a badge is attached to the location button and colored <span %1>red</span> if the accuracy value is worse than <i>bad</i>, <span %2>yellow</span> if it falls short of <i>excellent</i>, or <span %3>green</span>.<br><br>In addition, an accuracy restriction mode can be toggled on, which restricts vertex addition when locked to coordinate cursor to positions with an accuracy value worse than the bad threshold.").arg("style='%1'".arg(Theme.toInlineStyles({
                "color": Theme.accuracyBad
              }))).arg("style='%1'".arg(Theme.toInlineStyles({
                "color": Theme.accuracyTolerated
              }))).arg("style='%1'".arg(Theme.toInlineStyles({
                "color": Theme.accuracyExcellent
              })))
              font: Theme.tipFont
              color: Theme.secondaryTextColor
              textFormat: Qt.RichText
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item {
              // empty cell in grid layout
              width: 1
            }

            Label {
              text: qsTr("Enable averaged positioning requirement")
              font: Theme.defaultFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true

              MouseArea {
                anchors.fill: parent
                onClicked: averagedPositioning.toggle()
              }
            }

            QfSwitch {
              id: averagedPositioning
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignTop
              checked: positioningSettings.averagedPositioning
              onCheckedChanged: {
                positioningSettings.averagedPositioning = checked;
              }
            }

            RowLayout {
              Layout.columnSpan: 2
              Layout.fillWidth: true
              visible: averagedPositioning.checked
              enabled: averagedPositioning.checked

              Label {
                text: qsTr("Minimum positions count")
                font: Theme.defaultFont
                color: Theme.mainTextColor
                Layout.fillWidth: true
              }

              QfTextField {
                id: averagedPositioningMinimumCount
                font: Theme.defaultFont
                horizontalAlignment: TextInput.AlignRight
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator {
                  locale: 'C'
                }

                Component.onCompleted: {
                  text = isNaN(positioningSettings.averagedPositioningMinimumCount) ? '' : positioningSettings.averagedPositioningMinimumCount;
                }

                onTextChanged: {
                  if (text.length === 0 || isNaN(text)) {
                    positioningSettings.averagedPositioningMinimumCount = NaN;
                  } else {
                    positioningSettings.averagedPositioningMinimumCount = parseInt(text);
                  }
                }
              }
            }

            Label {
              text: qsTr("Automatically end collection when minimum number is met")
              font: Theme.defaultFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              enabled: averagedPositioning.checked
              visible: averagedPositioning.checked
              Layout.leftMargin: 8

              MouseArea {
                anchors.fill: parent
                onClicked: averagedPositioningAutomaticEnd.toggle()
              }
            }

            QfSwitch {
              id: averagedPositioningAutomaticEnd
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignTop
              enabled: averagedPositioning.checked
              visible: averagedPositioning.checked
              checked: positioningSettings.averagedPositioningAutomaticStop
              onCheckedChanged: {
                positioningSettings.averagedPositioningAutomaticStop = checked;
              }
            }

            Label {
              text: qsTr("When enabled, digitizing vertices with a cursor locked to position will only accepted an averaged position from a minimum number of collected positions. Digitizing using averaged positions is done by pressing and holding the add vertex button, which will collect positions until the press is released. Accuracy requirement settings are respected when enabled.")
              font: Theme.tipFont
              color: Theme.secondaryTextColor
              textFormat: Qt.RichText
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item {
              // empty cell in grid layout
              width: 1
            }

            Label {
              text: qsTr('Elevation Adjustment')
              font: Theme.strongFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              Layout.topMargin: 10
              Layout.bottomMargin: 5
              Layout.columnSpan: 2
            }

            Label {
              text: qsTr("Antenna height compensation")
              font: Theme.defaultFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true

              MouseArea {
                anchors.fill: parent
                onClicked: antennaHeightActivated.toggle()
              }
            }

            QfSwitch {
              id: antennaHeightActivated
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignTop
              checked: positioningSettings.antennaHeightActivated
              onCheckedChanged: {
                positioningSettings.antennaHeightActivated = checked;
              }
            }

            RowLayout {
              Layout.columnSpan: 2
              Layout.fillWidth: true
              visible: antennaHeightActivated.checked
              enabled: antennaHeightActivated.checked

              Label {
                text: qsTr("Antenna height")
                font: Theme.defaultFont
                color: Theme.mainTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }

              QfTextField {
                id: antennaHeightInput
                font: Theme.defaultFont
                horizontalAlignment: TextInput.AlignRight
                suffixText: qsTr("m")
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: DoubleValidator {
                  locale: 'C'
                }

                Component.onCompleted: {
                  text = isNaN(positioningSettings.antennaHeight) ? '' : positioningSettings.antennaHeight;
                }

                onTextChanged: {
                  if (text.length === 0 || isNaN(text)) {
                    positioningSettings.antennaHeight = NaN;
                  } else {
                    positioningSettings.antennaHeight = parseFloat(text);
                  }
                }
              }
            }

            Label {
              text: qsTr("This value will correct the Z values recorded from the positioning device. If a value of 1.6 is entered, the system will automatically subtract 1.6 from each recorded value. Make sure to insert the effective antenna height, i.e. pole length + antenna phase center offset.")
              font: Theme.tipFont
              color: Theme.secondaryTextColor

              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item {
              // empty cell in grid layout
              width: 1
            }

            Label {
              text: qsTr("Skip altitude correction")
              font: Theme.defaultFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true

              MouseArea {
                anchors.fill: parent
                onClicked: skipAltitudeCorrectionSwitch.toggle()
              }
            }

            QfSwitch {
              id: skipAltitudeCorrectionSwitch
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignTop
              checked: positioningSettings.skipAltitudeCorrection
              onCheckedChanged: {
                positioningSettings.skipAltitudeCorrection = checked;
              }
            }

            Label {
              topPadding: 0
              text: qsTr("Use the altitude as reported by the positioning device. Skip any altitude correction that may be implied by the coordinate system transformation.")
              font: Theme.tipFont
              color: Theme.secondaryTextColor

              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Item {
              // empty cell in grid layout
              width: 1
            }

            Label {
              text: qsTr("Vertical grid shift in use:")
              font: Theme.defaultFont
              color: Theme.mainTextColor

              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              Layout.columnSpan: 2
            }

            QfComboBox {
              id: verticalGridShiftComboBox
              Layout.fillWidth: true
              Layout.columnSpan: 2
              font: Theme.defaultFont

              popup.font: Theme.defaultFont
              popup.topMargin: mainWindow.sceneTopMargin
              popup.bottomMargin: mainWindow.sceneTopMargin

              textRole: "text"
              valueRole: "value"

              model: ListModel {
                id: verticalGridShiftModel
              }

              onCurrentValueChanged: {
                if (reloading || currentValue == undefined) {
                  return;
                }
                positioningSettings.elevationCorrectionMode = currentValue;
                if (positioningSettings.elevationCorrectionMode === Positioning.ElevationCorrectionMode.OrthometricFromGeoidFile) {
                  positioningSettings.verticalGrid = currentText;
                } else {
                  positioningSettings.verticalGrid = "";
                }
              }

              Component.onCompleted: reload()

              property bool reloading: false
              function reload() {
                reloading = true;
                verticalGridShiftComboBox.model.clear();
                verticalGridShiftComboBox.model.append({
                  "text": qsTr("None"),
                  "value": Positioning.ElevationCorrectionMode.None
                });
                if ((positionSource.deviceCapabilities & AbstractGnssReceiver.OrthometricAltitude) != 0) {
                  verticalGridShiftComboBox.model.append({
                    "text": qsTr("Orthometric from device"),
                    "value": Positioning.ElevationCorrectionMode.OrthometricFromDevice
                  });
                }

                // Add geoid files to combobox
                var geoidFiles = platformUtilities.availableGrids();
                for (var i = 0; i < geoidFiles.length; i++)
                  verticalGridShiftComboBox.model.append({
                    "text": geoidFiles[i],
                    "value": Positioning.ElevationCorrectionMode.OrthometricFromGeoidFile
                  });
                if (positioningSettings.elevationCorrectionMode === Positioning.ElevationCorrectionMode.None) {
                  verticalGridShiftComboBox.currentIndex = indexOfValue(positioningSettings.elevationCorrectionMode);
                  positioningSettings.verticalGrid = "";
                } else if (positioningSettings.elevationCorrectionMode === Positioning.ElevationCorrectionMode.OrthometricFromDevice) {
                  if ((positionSource.deviceCapabilities & AbstractGnssReceiver.OrthometricAltitude) != 0)
                    verticalGridShiftComboBox.currentIndex = verticalGridShiftComboBox.indexOfValue(positioningSettings.elevationCorrectionMode);
                  else
                    // Orthometric not available -> fallback to None
                    verticalGridShiftComboBox.currentIndex = verticalGridShiftComboBox.indexOfValue(Positioning.ElevationCorrectionMode.None);
                  positioningSettings.verticalGrid = "";
                } else if (positioningSettings.elevationCorrectionMode === Positioning.ElevationCorrectionMode.OrthometricFromGeoidFile) {
                  var currentVerticalGridFileIndex = verticalGridShiftComboBox.find(positioningSettings.verticalGrid);
                  if (currentVerticalGridFileIndex < 1)
                    // Vertical index file not found -> fallback to None
                    verticalGridShiftComboBox.currentIndex = verticalGridShiftComboBox.indexOfValue(Positioning.ElevationCorrectionMode.None);
                  else
                    verticalGridShiftComboBox.currentIndex = currentVerticalGridFileIndex;
                } else {
                  console.log("Warning unknown elevationCorrectionMode: '%1'".arg(positioningSettings.elevationCorrectionMode));

                  // Unknown mode -> fallback to None
                  verticalGridShiftComboBox.currentIndex = verticalGridShiftComboBox.indexOfValue(Positioning.ElevationCorrectionMode.None);
                }
                reloading = false;
              }
            }

            Label {
              topPadding: 0
              rightPadding: antennaHeightActivated.width
              text: qsTr("Vertical grid shift is used to increase the altitude accuracy.")
              font: Theme.tipFont
              color: Theme.secondaryTextColor

              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              Layout.columnSpan: 2
            }

            Label {
              text: qsTr('Advanced')
              font: Theme.strongFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              Layout.topMargin: 10
              Layout.bottomMargin: 5
              Layout.columnSpan: 2
              visible: positionSource.deviceCapabilities & AbstractGnssReceiver.Logging
            }

            Label {
              text: qsTr("Log NMEA sentences from device to file")
              font: Theme.defaultFont
              color: Theme.mainTextColor
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              visible: positionSource.deviceCapabilities & AbstractGnssReceiver.Logging

              MouseArea {
                anchors.fill: parent
                onClicked: positionLogging.toggle()
              }
            }

            QfSwitch {
              id: positionLogging
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignTop
              visible: positionSource.deviceCapabilities & AbstractGnssReceiver.Logging
              checked: positioningSettings.logging
              onCheckedChanged: {
                positioningSettings.logging = checked;
              }
            }
          }

          Item {
            // spacer item
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: mainWindow.sceneBottomMargin + 20
          }
        }
      }
    }
  }
  Component {
    id: variablesPage
    Item {
      VariableEditor {
        id: variableEditor
        anchors.fill: parent
        anchors.margins: 4
        anchors.bottomMargin: 4 + mainWindow.sceneBottomMargin
      }
    }
  }

  function openCategory(id) {
    settingsStack.push(categoryPage, {
      "categoryId": id
    });
  }

  Component {
    id: categoryPage
    Item {
      property string categoryId
      ScrollView {
        anchors.fill: parent
        topPadding: 5
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: QfScrollBar {}
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
          width: settingsStack.width

          QfSettingsMapCanvas {
            visible: categoryId === "mapCanvas"
            Layout.fillWidth: true
            settingsPage: page
            settingsRegistry: registry
            settingsModel: canvasSettingsModel
            rowDelegate: listItem
          }
          QfSettingsDigitizing {
            visible: categoryId === "digitizing"
            Layout.fillWidth: true
            settingsPage: page
            settingsRegistry: registry
            settingsModel: digitizingEditingSettingsModel
            rowDelegate: listItem
          }
          QfSettingsInterface {
            visible: categoryId === "interface"
            Layout.fillWidth: true
            settingsPage: page
            settingsRegistry: registry
            settingsModel: interfaceSettingsModel
            rowDelegate: listItem
            onOpenLocatorSettings: {
              locatorSettings.open();
              locatorSettings.focus = true;
            }
            onOpenPluginManager: pluginManagerSettings.open()
          }
          SettingsNetwork {
            id: networkSettings
            Component.onCompleted: page.networkSettingsItem = networkSettings
            visible: categoryId === "network"
            Layout.fillWidth: true
            settingsPage: page
          }
          QfSettingsAdvanced {
            visible: categoryId === "advanced"
            Layout.fillWidth: true
            settingsPage: page
            settingsRegistry: registry
            settingsModel: advancedSettingsModel
            rowDelegate: listItem
          }
          Loader {
            active: categoryId === "positioning"
            Layout.fillWidth: true
            Layout.preferredHeight: settingsStack.height
            sourceComponent: positioningPage
          }
          Loader {
            active: categoryId === "variables"
            Layout.fillWidth: true
            Layout.preferredHeight: settingsStack.height
            sourceComponent: variablesPage
          }
        }
      }
    }
  }

  header: QfPageHeader {
    title: settingsStack.depth > 1 && settingsStack.currentItem && settingsStack.currentItem.categoryId ? page.categoryTitles[settingsStack.currentItem.categoryId] : qsTr("%1 Settings").arg(appName)

    showBackButton: true
    showApplyButton: false
    showCancelButton: false

    topMargin: mainWindow.sceneTopMargin

    onFinished: {
      if (settingsStack.depth > 1) {
        settingsStack.pop();
        return;
      }
      parent.finished();
      if (variableEditorItem)
        variableEditorItem.apply();
      applyProxySettings();
    }
  }

  Keys.onReleased: event => {
    if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
      event.accepted = true;
      if (variableEditorItem)
        variableEditorItem.apply();
      applyProxySettings();
      finished();
    }
  }
}
