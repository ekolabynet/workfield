import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import QfTheme

/**
 * \ingroup qml
 *
 * WorkField: karta "Teren" — ustawienia terenowe zebrane w jednym miejscu.
 * Sekcja 1: przyciski edycji geometrii (rozmiar, okraglosc, sila haptyki).
 * Sekcja 2: skrot do klawiszy szybkiego zapisu.
 * Wartosci trzymane w ustawieniach aplikacji (klucze WorkField/*).
 */
QfPopup {
  id: terenSettings

  parent: mainWindow.contentItem
  width: Math.min(520, mainWindow.width - 24)
  height: Math.min(mainWindow.height - 48, przewijak.contentHeight + 2)
  padding: 0
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: QfPopup.CloseOnEscape

  background: Rectangle {
    color: "#EE263238"
    radius: 8
    border.color: "#455A64"
    border.width: 1
  }

  function haptykaTest(baza) {
    const sila = settings.valueInt('WorkField/haptykaSila', 3);
    if (sila > 0) {
      platformUtilities.vibrate(baza * sila);
    }
  }

  Flickable {
    id: przewijak
    anchors.fill: parent
    contentWidth: width
    contentHeight: tresc.implicitHeight + 24
    clip: true
    flickableDirection: Flickable.VerticalFlick

    QfScrollBar.vertical: QfScrollBar {
    }

    ColumnLayout {
      id: tresc
      x: 12
      y: 12
      width: przewijak.width - 24
      spacing: 10

    Text {
      Layout.fillWidth: true
      text: qsTr("Teren — ustawienia WorkField")
      color: "#80CBC4"
      font: QfTheme.strongFont
      wrapMode: Text.Wrap
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Przyciski edycji geometrii")
      color: "#B0BEC5"
      font: QfTheme.strongTipFont
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Rozmiar")
        color: "white"
        font: QfTheme.tipFont
      }

      QfSlider {
        id: suwakRozmiar
        Layout.fillWidth: true
        from: 100
        to: 150
        stepSize: 10
        snapMode: QfSlider.SnapAlways
        value: settings.valueInt('WorkField/przyciskiSkala', 100)
        onMoved: settings.setValue('WorkField/przyciskiSkala', Math.round(value))
      }

      Text {
        text: Math.round(suwakRozmiar.value) + "%"
        color: "white"
        font: QfTheme.tipFont
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      QfSwitch {
        id: przelacznikOkragle
        checked: settings.valueBool('WorkField/przyciskiOkragle', true)
        onToggled: settings.setValue('WorkField/przyciskiOkragle', checked)
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Okrągłe przyciski")
        color: "white"
        font: QfTheme.tipFont
        wrapMode: Text.Wrap
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Wibracje")
        color: "white"
        font: QfTheme.tipFont
      }

      QfSlider {
        id: suwakHaptyka
        Layout.fillWidth: true
        from: 0
        to: 5
        stepSize: 1
        snapMode: QfSlider.SnapAlways
        value: settings.valueInt('WorkField/haptykaSila', 3)
        onMoved: {
          settings.setValue('WorkField/haptykaSila', Math.round(value));
          terenSettings.haptykaTest(15);
        }
      }

      Text {
        text: Math.round(suwakHaptyka.value) === 0 ? qsTr("wył.") : "×" + Math.round(suwakHaptyka.value)
        color: "white"
        font: QfTheme.tipFont
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        text: qsTr("Testuj tony:")
        color: "#B0BEC5"
        font: QfTheme.tinyFont
      }

      QfButton {
        text: qsTr("dodaj")
        font.pointSize: QfTheme.tinyFont.pointSize
        onClicked: terenSettings.haptykaTest(15)
      }

      QfButton {
        text: qsTr("usuń")
        font.pointSize: QfTheme.tinyFont.pointSize
        onClicked: terenSettings.haptykaTest(45)
      }

      QfButton {
        text: qsTr("zapisz")
        font.pointSize: QfTheme.tinyFont.pointSize
        onClicked: terenSettings.haptykaTest(80)
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Rozmiar i okrągłość zaczną działać po ponownym uruchomieniu aplikacji. Siła wibracji działa od razu.")
      color: "#B0BEC5"
      font: QfTheme.tinyFont
      wrapMode: Text.Wrap
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 6
      text: qsTr("Panele akcji")
      color: "#B0BEC5"
      font: QfTheme.strongTipFont
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Gęstość")
        color: "white"
        font: QfTheme.tipFont
      }

      QfComboBox {
        id: wyborGestosci
        Layout.fillWidth: true
        model: [qsTr("Zwarta"), qsTr("Standardowa"), qsTr("Rękawice")]
        currentIndex: settings.valueInt('WorkField/gestosc', 1)
        onActivated: {
          settings.setValue('WorkField/gestosc', currentIndex);
          QfTheme.gestosc = currentIndex;
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Układ")
        color: "white"
        font: QfTheme.tipFont
      }

      QfComboBox {
        id: wyborUkladu
        Layout.fillWidth: true
        model: [qsTr("Lista wierszy"), qsTr("Kafle")]
        currentIndex: settings.valueInt('WorkField/ukladAkcji', 0)
        onActivated: {
          settings.setValue('WorkField/ukladAkcji', currentIndex);
          QfTheme.ukladAkcji = currentIndex;
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Zmiana działa od razu. Gęstość „Rękawice” powiększa przyciski i odstępy do pracy w rękawicach.")
      color: "#B0BEC5"
      font: QfTheme.tinyFont
      wrapMode: Text.Wrap
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 6
      visible: Qt.platform.os !== "android" && Qt.platform.os !== "ios"
      spacing: 8

      QfSwitch {
        checked: settings.valueBool('WorkField/quickCaptureNaKomputerze', false)
        onToggled: {
          settings.setValue('WorkField/quickCaptureNaKomputerze', checked);
          if (typeof quickCaptureBar !== 'undefined') {
            quickCaptureBar.naKomputerze = checked;
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Pasek szybkiego zapisu na komputerze")
        color: "white"
        font: QfTheme.tipFont
        wrapMode: Text.Wrap
      }
    }

    Rectangle {
      Layout.fillWidth: true
      height: 1
      color: "#455A64"
    }

    QfButton {
      Layout.fillWidth: true
      text: qsTr("Pliki projektu (edytor)…")
      onClicked: {
        terenSettings.close();
        textEditor.open();
      }
    }

    QfButton {
      Layout.fillWidth: true
      text: qsTr("Klawisze szybkiego zapisu…")
      onClicked: {
        terenSettings.close();
        captureSettings.openDialog();
      }
    }

    Item {
      Layout.fillHeight: true
    }

    QfButton {
      Layout.fillWidth: true
      text: qsTr("Zamknij")
      onClicked: terenSettings.close()
    }
    }
  }
}
