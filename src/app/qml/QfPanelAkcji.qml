import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import QfTheme

/**
 * \ingroup qml
 *
 * WorkField — PANEL AKCJI. Jedna forma prezentacji dla wszystkich sekcji.
 *
 * Dostaje listę akcji (z QfAkcje) i sam decyduje o układzie:
 *   QfTheme.ukladAkcji 0 → lista wierszy (ikona + nazwa w wierszu)
 *   QfTheme.ukladAkcji 1 → kafle w kolumnach (ikona nad nazwą)
 * Wysokości i odstępy pochodzą WYŁĄCZNIE z QfTheme (gęstość), więc żadna
 * sekcja nie ma własnych liczb i nic nie może się rozjechać.
 */
ColumnLayout {
  id: panel

  //! lista akcji do pokazania (format z QfAkcje.wGrupie)
  property var akcje: []
  //! nagłówek sekcji; pusty = bez nagłówka
  property string tytul: ""
  //! sprawdzanie dostępności — funkcja(akcja) -> bool
  property var dostepna: function (a) { return true; }

  signal wybrano(var akcja)

  spacing: QfTheme.odstepAkcji

  Text {
    Layout.fillWidth: true
    Layout.bottomMargin: 2
    visible: panel.tytul !== "" && panel.akcje.length > 0
    text: panel.tytul
    font: QfTheme.strongTipFont
    color: QfTheme.secondaryTextColor
  }

  // ── forma: lista wierszy ────────────────────────────────────────
  ColumnLayout {
    Layout.fillWidth: true
    visible: QfTheme.ukladAkcji === 0
    spacing: QfTheme.odstepAkcji

    Repeater {
      model: QfTheme.ukladAkcji === 0 ? panel.akcje : []

      delegate: ItemDelegate {
        required property var modelData

        Layout.fillWidth: true
        Layout.preferredHeight: QfTheme.wysokoscWiersza
        enabled: panel.dostepna(modelData)
        opacity: enabled ? 1.0 : 0.4
        padding: 0

        background: Rectangle {
          color: parent.pressed ? QfTheme.mainColor : QfTheme.controlBackgroundAlternateColor
          radius: 6
        }

        contentItem: RowLayout {
          spacing: 10

          Image {
            Layout.leftMargin: 10
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            fillMode: Image.PreserveAspectFit
            source: QfTheme.getThemeVectorIcon(modelData.ikona)
          }

          Text {
            Layout.fillWidth: true
            text: modelData.nazwa
            font: QfTheme.tipFont
            color: QfTheme.mainTextColor
            elide: Text.ElideRight
          }
        }

        onClicked: panel.wybrano(modelData)
      }
    }
  }

  // ── forma: kafle ────────────────────────────────────────────────
  GridLayout {
    Layout.fillWidth: true
    visible: QfTheme.ukladAkcji === 1
    columns: QfTheme.kolumnyKafli
    columnSpacing: QfTheme.odstepAkcji
    rowSpacing: QfTheme.odstepAkcji

    Repeater {
      model: QfTheme.ukladAkcji === 1 ? panel.akcje : []

      delegate: ItemDelegate {
        required property var modelData

        Layout.fillWidth: true
        Layout.preferredHeight: QfTheme.wysokoscKafla
        enabled: panel.dostepna(modelData)
        opacity: enabled ? 1.0 : 0.4
        padding: 0

        background: Rectangle {
          color: parent.pressed ? QfTheme.mainColor : QfTheme.controlBackgroundAlternateColor
          radius: 6
        }

        contentItem: ColumnLayout {
          spacing: 4

          Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            fillMode: Image.PreserveAspectFit
            source: QfTheme.getThemeVectorIcon(modelData.ikona)
          }

          Text {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            text: modelData.nazwa
            font: QfTheme.tinyFont
            color: QfTheme.mainTextColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
        }

        onClicked: panel.wybrano(modelData)
      }
    }
  }
}
