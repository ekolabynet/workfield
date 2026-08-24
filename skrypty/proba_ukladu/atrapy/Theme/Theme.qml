pragma Singleton
import QtQuick

// Atrapa motywu z barwami PIOTRA (24.08.2026) — te same, ktore dal raport.
QtObject {
  property bool darkTheme: true
  property color mainColor: "#00695c"
  property color mainOverlayColor: "#ffffff"
  property color mainBackgroundColor: "#37474f"
  property color mainTextColor: "#e6e1e5"
  property color mainTextDisabledColor: "#73e6e1e5"
  property color secondaryTextColor: "#bdbdbd"
  property color controlBackgroundColor: "#202020"
  property color controlBackgroundAlternateColor: "#2a2a2e"
  property color controlBackgroundDisabledColor: "#33555555"
  property color controlBorderColor: "#404040"
  property color buttonColor: "#202020"
  property color buttonBackgroundColor: "#00695c"
  property color toolButtonColor: "#ffffff"
  property color toolButtonBackgroundColor: "#00463c"
  property color groupBoxBackgroundColor: "#2a2a2e"
  property color groupBoxSurfaceColor: "#2a2a2e"
  property color goodColor: "#00695c"
  property color warningColor: "#ffa500"
  property color errorColor: "#df3422"
  property font strongFont: Qt.font({ pointSize: 13, bold: true })
  property font defaultFont: Qt.font({ pointSize: 12 })
  property font strongTipFont: Qt.font({ pointSize: 11, bold: true })
  property font tipFont: Qt.font({ pointSize: 11 })
  property font tinyFont: Qt.font({ pointSize: 9 })
}
