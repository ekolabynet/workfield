import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * WorkField: karta "Teren" — ustawienia terenowe zebrane w jednym miejscu.
 * Sekcja 1: przyciski edycji geometrii (rozmiar, okraglosc, sila haptyki).
 * Sekcja 2: skrot do klawiszy szybkiego zapisu.
 * Wartosci trzymane w ustawieniach aplikacji (klucze WorkField/*).
 */
Popup {
  id: terenSettings

  parent: mainWindow.contentItem
  width: Math.min(520, mainWindow.width - 24)
  height: Math.min(560, mainWindow.height - 48)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: Popup.CloseOnEscape

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

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 10

    Text {
      Layout.fillWidth: true
      text: qsTr("Teren — ustawienia WorkField")
      color: "#80CBC4"
      font: Theme.strongFont
      wrapMode: Text.Wrap
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Przyciski edycji geometrii")
      color: "#B0BEC5"
      font: Theme.strongTipFont
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Rozmiar")
        color: "white"
        font: Theme.tipFont
      }

      Slider {
        id: suwakRozmiar
        Layout.fillWidth: true
        from: 100
        to: 150
        stepSize: 10
        snapMode: Slider.SnapAlways
        value: settings.valueInt('WorkField/przyciskiSkala', 100)
        onMoved: settings.setValue('WorkField/przyciskiSkala', Math.round(value))
      }

      Text {
        text: Math.round(suwakRozmiar.value) + "%"
        color: "white"
        font: Theme.tipFont
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Switch {
        id: przelacznikOkragle
        checked: settings.valueBool('WorkField/przyciskiOkragle', true)
        onToggled: settings.setValue('WorkField/przyciskiOkragle', checked)
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Okrągłe przyciski")
        color: "white"
        font: Theme.tipFont
        wrapMode: Text.Wrap
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Wibracje")
        color: "white"
        font: Theme.tipFont
      }

      Slider {
        id: suwakHaptyka
        Layout.fillWidth: true
        from: 0
        to: 5
        stepSize: 1
        snapMode: Slider.SnapAlways
        value: settings.valueInt('WorkField/haptykaSila', 3)
        onMoved: {
          settings.setValue('WorkField/haptykaSila', Math.round(value));
          terenSettings.haptykaTest(15);
        }
      }

      Text {
        text: Math.round(suwakHaptyka.value) === 0 ? qsTr("wył.") : "×" + Math.round(suwakHaptyka.value)
        color: "white"
        font: Theme.tipFont
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        text: qsTr("Testuj tony:")
        color: "#B0BEC5"
        font: Theme.tinyFont
      }

      Button {
        text: qsTr("dodaj")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: terenSettings.haptykaTest(15)
      }

      Button {
        text: qsTr("usuń")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: terenSettings.haptykaTest(45)
      }

      Button {
        text: qsTr("zapisz")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: terenSettings.haptykaTest(80)
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Rozmiar i okrągłość zaczną działać po ponownym uruchomieniu aplikacji. Siła wibracji działa od razu.")
      color: "#B0BEC5"
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }

    Rectangle {
      Layout.fillWidth: true
      height: 1
      color: "#455A64"
    }

    Button {
      Layout.fillWidth: true
      text: qsTr("Pliki projektu (edytor)…")
      onClicked: {
        terenSettings.close();
        textEditor.open();
      }
    }

    Button {
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

    Button {
      Layout.fillWidth: true
      text: qsTr("Zamknij")
      onClicked: terenSettings.close()
    }
  }
}
