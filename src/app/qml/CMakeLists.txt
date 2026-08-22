set(QFIELD_APP_QML_FILES
    qml/QfAbout.qml
    qml/QfAkcje.qml
    qml/QfBadLayerItem.qml
    qml/QfBasemapScreen.qml
    qml/QfCaptureSettings.qml
    qml/QfChangelog.qml
    qml/QfCloudDangerZone.qml
    qml/QfCloudDeltaHistory.qml
    qml/QfCloudLogin.qml
    qml/QfCloudPackageLayersFeedback.qml
    qml/QfCloudPendingChanges.qml
    qml/QfCloudPopup.qml
    qml/QfCloudProjectDetails.qml
    qml/QfCloudProjectFilter.qml
    qml/QfCloudScreen.qml
    qml/QfCloudSettings.qml
    qml/QfCloudStatusBanner.qml
    qml/QfColorPicker.qml
    qml/QfCoordinateLocator.qml
    qml/QfDashBoard.qml
    qml/QfDataDrawer.qml
    qml/QfDesktopChrome.qml
    qml/QfDummy.qml
    qml/QfFeatureListSelectionHighlight.qml
    qml/QfGuide.qml
    qml/QfKontrolaProjektu.qml
    qml/QfLayerExportDialog.qml
    qml/QfLayerFieldsScreen.qml
    qml/QfLegendScreen.qml
    qml/QfLocalDataPickerScreen.qml
    qml/QfMainDrawer.qml
    qml/QfMeasuringTool.qml
    qml/QfNaprawaProjektu.qml
    qml/QfNewLayerDialog.qml
    qml/QfNoweZadanie.qml
    qml/QfNowyProjekt.qml
    qml/QfNyuki.qml
    qml/QfPanelAkcji.qml
    qml/QfPhotoGallery.qml
    qml/QfPluginItem.qml
    qml/QfPluginManagerSettings.qml
    qml/QfPositioningSettings.qml
    qml/QfPrzepis.qml
    qml/QfQuickCaptureBar.qml
    qml/QfScreenLocker.qml
    qml/QfSettings.qml
    qml/QfSettingsAdvanced.qml
    qml/QfSettingsDigitizing.qml
    qml/QfSettingsIndex.qml
    qml/QfSettingsInterface.qml
    qml/QfSettingsMapCanvas.qml
    qml/QfSketcher.qml
    qml/QfStudioSection.qml
    qml/QfSubLayerPicker.qml
    qml/QfTerenSettings.qml
    qml/QfTextEditor.qml
    qml/QfTrackerSettings.qml
    qml/QfWelcomeScreen.qml
    qml/QfWymianaLokalna.qml
    qml/QgisMobileapp.qml
    qml/SettingsNetwork.qml
    qml/SideMenu.qml)

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
