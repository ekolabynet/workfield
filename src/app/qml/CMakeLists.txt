set(QFIELD_APP_QML_FILES
    QfAbout.qml
    QfAkcje.qml
    QfBadLayerItem.qml
    QfBasemapScreen.qml
    QfCaptureSettings.qml
    QfChangelog.qml
    QfCloudDangerZone.qml
    QfCloudDeltaHistory.qml
    QfCloudLogin.qml
    QfCloudPackageLayersFeedback.qml
    QfCloudPendingChanges.qml
    QfCloudPopup.qml
    QfCloudProjectDetails.qml
    QfCloudProjectFilter.qml
    QfCloudScreen.qml
    QfCloudSettings.qml
    QfCloudStatusBanner.qml
    QfColorPicker.qml
    QfCoordinateLocator.qml
    QfDashBoard.qml
    QfDataDrawer.qml
    QfDesktopChrome.qml
    QfDummy.qml
    QfFeatureListSelectionHighlight.qml
    QfGuide.qml
    QfKontrolaProjektu.qml
    QfLayerExportDialog.qml
    QfLayerFieldsScreen.qml
    QfLegendScreen.qml
    QfLocalDataPickerScreen.qml
    QfMainDrawer.qml
    QfMeasuringTool.qml
    QfNaprawaProjektu.qml
    QfNewLayerDialog.qml
    QfNoweZadanie.qml
    QfNowyProjekt.qml
    QfNyuki.qml
    QfPanelAkcji.qml
    QfPhotoGallery.qml
    QfPluginItem.qml
    QfPluginManagerSettings.qml
    QfPositioningSettings.qml
    QfPrzepis.qml
    QfQuickCaptureBar.qml
    QfScreenLocker.qml
    QfSettings.qml
    QfSettingsAdvanced.qml
    QfSettingsDigitizing.qml
    QfSettingsIndex.qml
    QfSettingsInterface.qml
    QfSettingsMapCanvas.qml
    QfSketcher.qml
    QfStudioSection.qml
    QfSubLayerPicker.qml
    QfTerenSettings.qml
    QfTextEditor.qml
    QfTrackerSettings.qml
    QfWelcomeScreen.qml
    QfWymianaLokalna.qml
    QgisMobileapp.qml
    SettingsNetwork.qml
    SideMenu.qml)

# Type registration stays imperative, in QfApp::registerQmlTypes().
qt_add_qml_module(
  qfield_app
  URI
  org.qfield.app
  VERSION
  1.0
  NO_PLUGIN
  NO_GENERATE_QMLTYPES
  RESOURCE_PREFIX
  "/qt/qml"
  QML_FILES
  ${QFIELD_APP_QML_FILES})

qt_import_qml_plugins(qfield_app)

# Absolute, because src/app and test copy these from another directory.
set(QFIELD_APP_QML_FILES_ABS "")
foreach(qml_file ${QFIELD_APP_QML_FILES})
  list(APPEND QFIELD_APP_QML_FILES_ABS
       "${CMAKE_CURRENT_SOURCE_DIR}/${qml_file}")
endforeach()
set_property(TARGET qfield_app PROPERTY QML_FILES ${QFIELD_APP_QML_FILES_ABS})
