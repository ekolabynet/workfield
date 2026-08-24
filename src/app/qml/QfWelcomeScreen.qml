import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Particles
import QtCore
import org.qfield.core
import org.qfield.gui
import Qt.labs.folderlistmodel
import Theme

/**
 * \ingroup qml
 */
Page {
  id: welcomeScreen

  property bool firstShown: false

  property alias model: table.model

  signal showAbout
  signal showLocalDataPicker
  signal showQFieldCloudScreen
  signal showSettings
  signal showProjectCreationScreen

  visible: false
  focus: visible

  function templatesDataRoot() {
    return iface.dataRoot();
  }

  function createProjectFromTemplate(templatePath, projectName) {
    const root = templatesDataRoot();
    if (root === "") {
      return;
    }
    platformUtilities.createDir(root, "Imported Projects");
    const safeName = FileUtils.sanitizeFilePathPart(projectName);
    const destination = root + "Imported Projects/" + safeName;
    if (FileUtils.fileExists(destination + "/projekt.qgs") || FileUtils.fileExists(destination + "/projekt.qgz")) {
      displayToast(qsTr("Projekt o nazwie '%1' już istnieje").arg(safeName));
      return;
    }
    if (!FileUtils.copyRecursively(templatePath, destination)) {
      displayToast(qsTr("Nie udało się skopiować szablonu"));
      return;
    }
    if (FileUtils.fileExists(destination + "/projekt.qgs")) {
      iface.loadFile(destination + "/projekt.qgs", projectName);
    } else if (FileUtils.fileExists(destination + "/projekt.qgz")) {
      iface.loadFile(destination + "/projekt.qgz", projectName);
    } else {
      displayToast(qsTr("Szablon nie zawiera pliku projekt.qgs"));
    }
  }

  Settings {
    id: registry
    category: 'QField'

    property string baseMapProject: ''
    property string defaultProject: ''
    property bool loadProjectOnLaunch: false
  }

  Rectangle {
    id: welcomeBackground
    anchors.fill: parent
    color: Theme.darkTheme ? "#062e2a" : "#00695c"
  }

  ScrollView {
    topPadding: Math.max(mainWindow.sceneTopMargin + 58, (mainWindow.height - welcomeLayout.height) / 2 - 50)
    leftPadding: mainWindow.sceneLeftMargin
    rightPadding: mainWindow.sceneRightMargin
    bottomPadding: mainWindow.sceneBottomMargin
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical: QfScrollBar {
      opacity: active
      _maxSize: 4
      _minSize: 2

      Behavior on opacity {
        NumberAnimation {
          duration: 200
        }
      }
    }

    contentItem: welcomeLayout
    contentWidth: welcomeLayout.width
    contentHeight: welcomeLayout.height
    anchors.fill: parent
    clip: true

    ColumnLayout {
      id: welcomeLayout
      spacing: 4

      width: mainWindow.width - mainWindow.sceneLeftMargin - mainWindow.sceneRightMargin

      RowLayout {
        spacing: welcomeScreenLogo.imageSize / 4

        Layout.margins: 6
        Layout.topMargin: 0
        Layout.bottomMargin: 24
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter

        Layout.maximumWidth: Math.min(parent.width, welcomeScreenLogo.imageSize + welcomeScreenTitleMetrics.advanceWidth(welcomeScreenTitle.text) + spacing + 5)

        QfImageDial {
          id: welcomeScreenLogo
          objectName: "welcomeScreenLogo"

          property real imageSize: Math.min(96, mainWindow.width / 5)
          property real pressedValue: -1

          Layout.preferredWidth: imageSize
          Layout.preferredHeight: imageSize

          source: "qrc:/images/app_logo.svg"
          rotationOffset: 220
          value: 1

          onPressedChanged: {
            if (pressed) {
              pressedValue = -1;
            } else {
              if (pressedValue == -1 || Math.abs(value - pressedValue) < 0.05) {
                welcomeScreen.showAbout();
              }
              pressedValue = -1;
            }
          }

          onValueChanged: {
            if (pressed && pressedValue == -1) {
              pressedValue = value;
            }
          }
        }

        Text {
          id: welcomeScreenTitle
          objectName: "welcomeScreenTitle"

          Layout.fillWidth: true

          font.pointSize: 24
          font.bold: true
          color: Theme.mainOverlayColor
          text: Qfield.name
          wrapMode: Text.WordWrap
        }

        FontMetrics {
          id: welcomeScreenTitleMetrics
          font: welcomeScreenTitle.font
        }
      }

      SwipeView {
        id: feedbackView
        visible: false

        Layout.margins: 6
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        Layout.preferredWidth: Math.min(410, welcomeLayout.width - 30)
        Layout.preferredHeight: Math.max(ohno.childrenRect.height, intro.childrenRect.height, ohyeah.childrenRect.height)
        clip: true

        Behavior on Layout.preferredHeight {
          NumberAnimation {
            duration: 100
            easing.type: Easing.InQuad
          }
        }

        interactive: false
        currentIndex: 1
        Item {
          id: ohno

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: feedbackView.width - 12
              text: qsTr("We're sorry to hear that. Click on the button below to comment or seek support.")
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            RowLayout {
              spacing: 6
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              Layout.bottomMargin: 10

              QfButton {
                topPadding: 8
                bottomPadding: 8
                leftPadding: 10
                rightPadding: 10

                text: qsTr("Reach out")
                icon.source: QfTheme.getThemeVectorIcon('ic_create_white_24dp')

                onClicked: {
                  Qt.openUrlExternally("https://www.qfield.org/");
                  feedbackView.Layout.preferredHeight = 0;
                }
              }
            }
          }
        }

        Item {
          id: intro

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: feedbackView.width - 12
              text: qsTr("Hey there, how do you like your experience with %1 so far?").arg(Qfield.name)
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            RowLayout {
              spacing: 6
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              Layout.bottomMargin: 10
              QfToolButton {
                iconSource: QfTheme.getThemeVectorIcon('ic_dissatisfied_white_24dp')
                iconColor: QfTheme.mainOverlayColor
                bgcolor: QfTheme.mainColor
                round: true

                onClicked: {
                  feedbackView.currentIndex = 0;
                }
              }
              QfToolButton {
                iconSource: QfTheme.getThemeVectorIcon('ic_satisfied_white_24dp')
                iconColor: QfTheme.mainOverlayColor
                bgcolor: QfTheme.mainColor
                round: true

                onClicked: {
                  if (Qt.platform.os === "android" || Qt.platform.os === "ios" || Qt.platform.os === "windows") {
                    feedbackView.currentIndex = 2;
                  } else {
                    feedbackView.Layout.preferredHeight = 0;
                  }
                }
              }
            }
          }
        }
        Item {
          id: ohyeah

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: feedbackView.width - 12
              text: qsTr("That's great! We'd love for you to click on the button below and leave a review.")
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            RowLayout {
              spacing: 6
              Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
              Layout.margins: 6
              Layout.bottomMargin: 10
              QfButton {
                topPadding: 8
                bottomPadding: 8
                leftPadding: 10
                rightPadding: 10

                text: qsTr("Rate us")
                icon.source: QfTheme.getThemeVectorIcon('ic_star_white_24dp')

                onClicked: {
                  if (Qt.platform.os === "windows") {
                    Qt.openUrlExternally("https://apps.microsoft.com/detail/xp99h3bcx4bw7f");
                  } else if (Qt.platform.os === "android") {
                    Qt.openUrlExternally("market://details?id=ch.opengis.qfield");
                  } else if (Qt.platform.os === "ios") {
                    Qt.openUrlExternally("itms-apps://itunes.apple.com/app/qfield-for-qgis/id1531726814");
                  }
                  feedbackView.Layout.preferredHeight = 0;
                }
              }
            }
          }
        }
      }

      SwipeView {
        id: collectionView
        visible: false

        Layout.margins: 0
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        Layout.preferredWidth: Qt.platform.os !== "android" && Qt.platform.os !== "ios" ? Math.min(1160, welcomeLayout.width - 40) : Math.min(410, welcomeLayout.width - 20)
        Layout.preferredHeight: Math.max(collectionOhno.childrenRect.height, collectionIntro.childrenRect.height)
        clip: true

        Behavior on Layout.preferredHeight {
          NumberAnimation {
            duration: 100
            easing.type: Easing.InQuad
          }
        }

        interactive: false
        currentIndex: 1
        Item {
          id: collectionOhno

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: collectionView.width - 12
              text: qsTr("Anonymized metrics collection has been disabled. You can re-enable through the settings panel.")
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
        }

        Item {
          id: collectionIntro

          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.26)
              }
              GradientStop {
                position: 0.88
                color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.02)
              }
            }

            radius: 6
          }

          ColumnLayout {
            spacing: 0
            anchors.centerIn: parent

            Text {
              Layout.margins: 6
              Layout.topMargin: 12
              Layout.maximumWidth: collectionView.width - 12
              text: qsTr("To improve stability for everyone, %1 collects and sends anonymized metrics.").arg(Qfield.name)
              font: Theme.defaultFont
              color: Theme.mainOverlayColor
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            RowLayout {
              spacing: 6
              Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
              Layout.bottomMargin: 10
              QfButton {
                topPadding: 8
                bottomPadding: 8
                leftPadding: 10
                rightPadding: 10

                text: qsTr('I agree')

                onClicked: {
                  qfieldSettings.enableInfoCollection = true;
                  collectionView.visible = false;
                }
              }

              QfButton {
                topPadding: 8
                bottomPadding: 8
                leftPadding: 10
                rightPadding: 10

                text: qsTr('I prefer not')
                bgcolor: "transparent"
                color: QfTheme.mainColor

                onClicked: {
                  qfieldSettings.enableInfoCollection = false;
                  collectionView.visible = false;
                }
              }
            }
          }
        }
      }

      Text {
        id: welcomeText
        visible: !feedbackView.visible && text !== ""
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Layout.topMargin: 2
        Layout.bottomMargin: 10
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        text: ""
        font: Theme.defaultFont
        color: Theme.mainOverlayColor
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Rectangle {
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        Layout.fillWidth: true
        Layout.maximumWidth: Qt.platform.os !== "android" && Qt.platform.os !== "ios" ? 1160 : 410
        Layout.preferredHeight: welcomeActions.height
        Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        color: "transparent"

        ColumnLayout {
          id: welcomeActions
          width: parent.width
          spacing: 12

          Text {
            id: templatesText
            Layout.fillWidth: true
            visible: templatesListView.count > 0
            text: qsTr("Nowy z szablonu")
            font.pointSize: Theme.tipFont.pointSize
            font.bold: true
            color: Theme.mainOverlayColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          ListView {
            id: templatesListView
            Layout.fillWidth: true
            Layout.preferredHeight: count > 0 ? 92 : 0
            orientation: ListView.Horizontal
            spacing: 8
            clip: true
            visible: count > 0

            ScrollBar.horizontal: QfScrollBar {
              policy: templatesListView.contentWidth > templatesListView.width ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            model: FolderListModel {
              id: templatesFolderModel
              folder: ""
              showFiles: false
              showDirs: true
              showDotAndDotDot: false
            }

            delegate: Rectangle {
              width: 150
              height: 84
              radius: 8
              color: "transparent"
              border.color: Theme.mainOverlayColor
              border.width: 1

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Image {
                  Layout.alignment: Qt.AlignHCenter
                  source: Theme.getThemeVectorIcon("ic_add_white_24dp")
                  sourceSize.width: 24
                  sourceSize.height: 24
                }

                Text {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  text: fileName
                  font: Theme.tipFont
                  color: Theme.mainOverlayColor
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  wrapMode: Text.WordWrap
                  elide: Text.ElideRight
                  maximumLineCount: 2
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  templateNameDialog.templatePath = filePath;
                  templateNameDialog.templateName = fileName;
                  templateNameField.text = fileName + " Projekt " + new Date().toISOString().slice(0, 10);
                  templateNameDialog.open();
                }
              }
            }
          }

          Text {
            id: recentText
            Layout.fillWidth: true
            Layout.topMargin: 18
            visible: table.count > 0
            text: qsTr("Recently Opened")
            font.pointSize: QfTheme.tipFont.pointSize
            font.bold: true
            color: Theme.mainOverlayColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            Layout.topMargin: 14
            Layout.bottomMargin: 4
            text: qsTr("Otwórz lokalne projekty i dane…")
            font.pointSize: Theme.tipFont.pointSize
            font.underline: true
            color: Theme.mainOverlayColor
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
              anchors.fill: parent
              onClicked: {
                platformUtilities.requestStoragePermission();
                showLocalDataPicker();
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: table.height
            color: "transparent"

            GridView {
              id: table

              // WorkField: na komputerze siatka kolumn zamiast jednej listy
              readonly property int kolumny: Qt.platform.os !== "android" && Qt.platform.os !== "ios" ? Math.max(1, Math.floor(width / 360)) : 1

              ScrollBar.vertical: QfScrollBar {}
              flickableDirection: Flickable.AutoFlickIfNeeded
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              width: parent.width
              height: contentItem.childrenRect.height
              cellWidth: Math.floor(width / kolumny)
              cellHeight: 140

              delegate: QfProjectThumbnail {
                width: table.cellWidth - 8

                property string path: ProjectPath
                property var type: ProjectType
                property int changesCount: {
                  const cloudProjectId = QfCloudUtils.getProjectId(ProjectPath);
                  if (cloudProjectId !== "") {
                    const project = cloudProjectsModel.findProject(cloudProjectId);
                    if (project) {
                      return project.deltasCount;
                    }
                  }
                  return 0;
                }
                property bool isOutdated: {
                  const cloudProjectId = QfCloudUtils.getProjectId(ProjectPath);
                  if (cloudProjectId !== "") {
                    const project = cloudProjectsModel.findProject(cloudProjectId);
                    if (project) {
                      return project.isOutdated;
                    }
                  }
                  return 0;
                }
                readonly property bool showSync: isOutdated
                readonly property bool showPush: changesCount > 0

                objectName: "loadProjectItem_1" // todo, suffix with e.g. ProjectTitle
                previewImageSource: welcomeScreen.visible ? ProjectThumbnail !== "" ? QfUrlUtils.fromString(ProjectThumbnail) : 'image://projects/' + ProjectPath : ''
                showType: true

                primaryBadge.badgeText.text: changesCount > 0 ? changesCount : ''
                primaryBadge.badgeText.color: QfTheme.light
                primaryBadge.visible: showSync || showPush
                primaryBadge.color: showSync ? QfTheme.mainColor : QfTheme.cloudColor
                primaryBadge.border.color: QfTheme.mainBackgroundColor
                primaryBadge.border.width: 1
                primaryBadge.enableGradient: showSync && showPush

                projectTypeSource: switch (ProjectType) {
                case 0:
                  return QfTheme.getThemeVectorIcon('ic_map_param_48dp');     // local project
                case 1:
                  return QfTheme.getThemeVectorIcon('ic_cloud_project_param_48dp'); // cloud project
                case 2:
                  return QfTheme.getThemeVectorIcon('ic_file_param_48dp');    // local dataset
                default:
                  return '';
                }
                projectTitle.text: ProjectTitle
                projectNote: {
                  var notes = [];
                  if (index == 0) {
                    var firstRun = settings && !settings.value("/QField/FirstRunFlag", false);
                    if (!firstRun && firstShown === false)
                      notes.push(qsTr("Last session"));
                  }
                  if (ProjectPath === registry.defaultProject) {
                    notes.push(qsTr("Default project"));
                  }
                  if (ProjectPath === registry.baseMapProject) {
                    notes.push(qsTr("Base map"));
                  }
                  if (notes.length > 0) {
                    return notes.join('; ');
                  } else {
                    return "";
                  }
                }
              }

              MouseArea {
                property Item pressedItem
                anchors.fill: parent
                onClicked: mouse => {
                  var item = table.itemAt(mouse.x, mouse.y);
                  if (item) {
                    switch (item.type) {
                    case QfRecentProjectListModel.CloudProject:
                    case QfRecentProjectListModel.LocalProject:
                    case QfRecentProjectListModel.LocalDataset:
                      if (item.type === QfRecentProjectListModel.CloudProject && cloudConnection.hasToken && cloudConnection.status !== QfCloudConnection.LoggedIn) {
                        cloudConnection.login();
                      }
                      iface.loadFile(item.path, item.projectTitle.text);
                      break;
                    case QfRecentProjectListModel.LinkProject:
                      iface.importUrl(item.path, item.projectTitle.text, true);
                      break;
                    }
                  }
                }
                onPressed: mouse => {
                  var item = table.itemAt(mouse.x, mouse.y);
                  if (item) {
                    pressedItem = item;
                    pressedItem.isPressed = true;
                  }
                }
                onCanceled: {
                  if (pressedItem) {
                    pressedItem.isPressed = false;
                    pressedItem = null;
                  }
                }
                onReleased: {
                  if (pressedItem) {
                    pressedItem.isPressed = false;
                    pressedItem = null;
                  }
                }
                onPressAndHold: mouse => {
                  var item = table.itemAt(mouse.x, mouse.y);
                  if (item) {
                    recentProjectActions.recentProjectPath = item.path;
                    recentProjectActions.recentProjectType = item.type;
                    recentProjectActions.popup(mouse.x, mouse.y);
                  }
                }
              }

              QfMenu {
                id: recentProjectActions

                property string recentProjectPath: ''
                property int recentProjectType: 0

                title: qsTr('Recent Project Actions')

                topMargin: mainWindow.sceneTopMargin
                bottomMargin: mainWindow.sceneBottomMargin

                MenuItem {
                  id: defaultProject
                  visible: recentProjectActions.recentProjectType != 2

                  font: QfTheme.defaultFont
                  width: parent.width
                  height: visible ? 48 : 0
                  leftPadding: QfTheme.menuItemCheckLeftPadding
                  checkable: true
                  checked: recentProjectActions.recentProjectPath === registry.defaultProject

                  text: qsTr("Default project")
                  onTriggered: {
                    registry.defaultProject = recentProjectActions.recentProjectPath === registry.defaultProject ? '' : recentProjectActions.recentProjectPath;
                  }
                }

                MenuItem {
                  id: baseMapProject
                  visible: recentProjectActions.recentProjectType != 2

                  font: QfTheme.defaultFont
                  width: parent.width
                  height: visible ? 48 : 0
                  leftPadding: QfTheme.menuItemCheckLeftPadding
                  checkable: true
                  checked: recentProjectActions.recentProjectPath === registry.baseMapProject

                  text: qsTr("Individual datasets base map")
                  onTriggered: {
                    registry.baseMapProject = recentProjectActions.recentProjectPath === registry.baseMapProject ? '' : recentProjectActions.recentProjectPath;
                  }
                }

                MenuSeparator {
                  visible: baseMapProject.visible
                  width: parent.width
                  height: visible ? undefined : 0
                }

                MenuItem {
                  id: removeProject

                  font: QfTheme.defaultFont
                  width: parent.width
                  height: visible ? 48 : 0
                  leftPadding: QfTheme.menuItemIconlessLeftPadding

                  text: qsTr("Remove from recently opened")
                  onTriggered: {
                    model.removeRecentProject(recentProjectActions.recentProjectPath);
                    model.reloadModel();
                  }
                }
              }
            }
          }

          RowLayout {
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.bottomMargin: mainWindow.sceneBottomMargin
            Label {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              topPadding: 10
              bottomPadding: 10
              font: QfTheme.tipFont
              wrapMode: Text.WordWrap
              color: Theme.mainOverlayColor

              text: registry.defaultProject != '' ? qsTr('Load default project on launch') : qsTr('Load last opened project on launch')

              MouseArea {
                anchors.fill: parent
                onClicked: reloadOnLaunch.checked = !reloadOnLaunch.checked
              }
            }

            QfSwitch {
              id: reloadOnLaunch
              Layout.preferredWidth: implicitContentWidth
              Layout.alignment: Qt.AlignVCenter
              width: implicitContentWidth

              checked: registry.loadProjectOnLaunch
              onCheckedChanged: {
                registry.loadProjectOnLaunch = checked;
              }
            }
          }
        }
      }
    }
  }

  Column {
    spacing: 4
    anchors {
      top: parent.top
      left: parent.left
      topMargin: mainWindow.sceneTopMargin + 4
      leftMargin: mainWindow.sceneLeftMargin + 4
    }

    QfActionButton {
      id: currentProjectButton
      toolImage: QfTheme.getThemeVectorIcon('ic_arrow_left_white_24dp')
      toolText: qsTr('Return to map')
      backgroundless: true
      visible: qgisProject && !!qgisProject.homePath
      innerActionIcon.visible: false

      onClicked: {
        welcomeScreen.visible = false;
      }
    }

    QfToolButton {
      id: settingsButton
      iconSource: QfTheme.getThemeVectorIcon('ic_tune_white_24dp')
      iconColor: QfTheme.mainTextColor
      bgcolor: "transparent"
      round: true

      onClicked: {
        showSettings();
      }
    }
  }

  QfToolButton {
    id: exitButton
    visible: (Qt.platform.os === "ios" || Qt.platform.os === "android" || mainWindow.sceneBorderless)
    anchors {
      top: parent.top
      right: parent.right
      topMargin: mainWindow.sceneTopMargin + 4
      rightMargin: mainWindow.sceneRightMargin + 4
    }
    iconSource: QfTheme.getThemeVectorIcon('ic_shutdown_24dp')
    iconColor: QfTheme.mainTextColor
    bgcolor: "transparent"
    round: true

    onClicked: {
      mainWindow.closeAlreadyRequested = true;
      mainWindow.close();
    }
  }

  // Sparkles & unicorns
  Rectangle {
    anchors.fill: parent
    color: "#00000000"
    visible: welcomeScreenLogo.value < 0.1

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      propagateComposedEvents: true
      onReleased: mouse.accepted = false
      onDoubleClicked: mouse.accepted = false
      onPressAndHold: mouse.accepted = false
      onClicked: mouse => {
        burstSomeSparkles(mouse.x, mouse.y);
        mouse.accepted = false;
      }
      onPressed: mouse => {
        burstSomeSparkles(mouse.x, mouse.y);
        mouse.accepted = false;
      }
      onPositionChanged: mouse => {
        burstSomeSparkles(mouse.x, mouse.y);
        mouse.accepted = false;
      }
    }

    ParticleSystem {
      id: particles
      running: welcomeScreenLogo.value < 0.1
    }

    ParticleSystem {
      id: unicorns
      running: welcomeScreenLogo.value < 0.1
    }

    ImageParticle {
      anchors.fill: parent
      system: particles
      source: "qrc:///particleresources/star.png"
      sizeTable: "qrc:///images/sparkleSize.png"
      alpha: 1
      colorVariation: 0.3
    }

    ImageParticle {
      anchors.fill: parent
      system: unicorns
      source: "qrc:///images/icons/unicorn.png"
      alpha: 1
      redVariation: 0
      blueVariation: 0
      greenVariation: 0
      rotation: 0
      rotationVariation: 360
    }

    Emitter {
      id: emitterParticles
      x: -100
      y: -100
      system: particles
      emitRate: 60
      lifeSpan: 700
      size: 50
      sizeVariation: 10
      maximumEmitted: 100
      velocity: AngleDirection {
        angle: 0
        angleVariation: 360
        magnitude: 100
        magnitudeVariation: 50
      }
    }

    Emitter {
      id: emitterUnicorns
      x: -100
      y: -100
      system: unicorns
      emitRate: 20
      lifeSpan: 900
      size: 70
      sizeVariation: 10
      maximumEmitted: 100
      velocity: AngleDirection {
        angle: 90
        angleVariation: 20
        magnitude: 200
        magnitudeVariation: 50
      }
    }
  }

  function burstSomeSparkles(x, y) {
    emitterParticles.burst(50, x, y);
    emitterUnicorns.burst(1, x, y);
  }

  function adjustWelcomeScreen() {
    if (visible) {
      if (firstShown) {
        welcomeText.text = "";
      } else {
        var firstRun = !settings.valueBool("/QField/FirstRunDone", false);
        if (firstRun) {
          welcomeText.text = table.count > 0 ? qsTr("First time using this application? Try the sample projects listed below.") : "";
          settings.setValue("/QField/FirstRunDone", true);
          settings.setValue("/QField/showMapCanvasGuide", true);
        } else {
          welcomeText.text = "";
        }
      }
    }
  }

  Component.onCompleted: {
    const templatesRoot = templatesDataRoot();
    if (templatesRoot !== "") {
      platformUtilities.createDir(templatesRoot, "templates");
      templatesFolderModel.folder = "file://" + templatesRoot + "templates";
    }
    adjustWelcomeScreen();
    var runCount = settings.value("/QField/RunCount", 0) * 1;
    var feedbackFormShown = settings.value("/QField/FeedbackFormShown", false);
    if (!feedbackFormShown) {
      var now = new Date();
      var dt = settings.value("/QField/FirstRunDate", "");
      if (dt != "") {
        dt = new Date(dt);
        var daysToPrompt = 30;
        var runsToPrompt = 5;
        if (runCount >= runsToPrompt && (now - dt) >= (daysToPrompt * 24 * 60 * 60 * 1000)) {
          if (Qfield.name === "QField") {
            feedbackView.visible = true;
          }
          settings.setValue("/QField/FeedbackFormShown", true);
        }
      } else {
        settings.setValue("/QField/FirstRunDate", now.toISOString());
      }
    }
    if (platformUtilities.capabilities & QfPlatformUtilities.SentryFramework) {
      var collectionFormShown = settings.value("/QField/CollectionFormShownV2", false);
      if (!collectionFormShown) {
        collectionView.visible = true;
        settings.setValue("/QField/CollectionFormShownV2", true);
      }
    }
    settings.setValue("/QField/RunCount", runCount + 1);
    if (registry.defaultProject != '') {
      if (!QfFileUtils.fileExists(registry.defaultProject)) {
        registry.defaultProject = '';
      }
    }
  }

  onVisibleChanged: {
    if (!visible) {
      welcomeText.text = "";
      feedbackView.visible = false;
      collectionView.visible = false;
      firstShown = true;
    }
  }

  Keys.onReleased: event => {
    if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
      if (qgisProject.fileName != '') {
        event.accepted = true;
        visible = false;
      } else {
        event.accepted = false;
      }
    }
  }

  Dialog {
    id: templateNameDialog

    property string templatePath: ""
    property string templateName: ""

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 400)
    modal: true
    title: qsTr("Nowy projekt z szablonu")
    standardButtons: Dialog.Ok | Dialog.Cancel
    focus: visible

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Label {
        Layout.fillWidth: true
        text: qsTr("Nazwa projektu:")
        font: Theme.defaultFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }

      TextField {
        id: templateNameField
        Layout.fillWidth: true
        font: Theme.defaultFont
        selectByMouse: true
      }
    }

    onAccepted: {
      if (templateNameField.text.trim() !== "") {
        welcomeScreen.createProjectFromTemplate(templatePath, templateNameField.text.trim());
      }
    }
  }
}
