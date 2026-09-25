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

  // WorkField 24.09.2026 — GESTOSC LUKOW, czytana przez silnik ksztaltow.
  //
  // Wlasnosci na korzeniu, a nie odwolanie do `silnikKsztaltow` w srodku:
  // identyfikatory z `QgisMobileapp.qml` NIE sa widoczne w osobnym pliku
  // `.qml`, bo kazdy komponent ma wlasny zakres nazw. To `QgisMobileapp`
  // podpina sie pod te wlasnosci, nie odwrotnie.
  //
  // Poczatkowa wartosc jest WIAZANIEM do ustawien; suwak ponizej
  // przypisuje wprost i tym samym je zrywa — o to chodzi.
  property real ksztaltBok: parseFloat(settings.value('WorkField/ksztaltBok', '0.25'))
  property int ksztaltMaks: settings.valueInt('WorkField/ksztaltMaks', 512)

  //! Ile wierzcholkow dostanie okrag o danym promieniu — do pokazania
  //! czlowiekowi SKUTKU liczby, ktora wlasnie ustawil.
  function wierzcholkowOkregu(promien) {
    if (!(ksztaltBok > 0) || !(promien > 0)) {
      return 72;
    }
    const polowa = ksztaltBok / (2 * promien);
    if (polowa >= 1) {
      return 8;
    }
    const ile = Math.ceil(2 * Math.PI / (2 * Math.asin(polowa)));
    return Math.max(8, Math.min(ksztaltMaks, ile));
  }

  parent: mainWindow.contentItem
  width: Math.min(520, mainWindow.width - 24)
  height: Math.min(mainWindow.height - 48, przewijak.contentHeight + 2)
  padding: 0
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

  Flickable {
    id: przewijak
    anchors.fill: parent
    contentWidth: width
    contentHeight: tresc.implicitHeight + 24
    clip: true
    flickableDirection: Flickable.VerticalFlick

    ScrollBar.vertical: ScrollBar {
    }

    ColumnLayout {
      id: tresc
      x: 12
      y: 12
      width: przewijak.width - 24
      spacing: 10

    Text {
      Layout.fillWidth: true
      text: qsTr("Teren — ustawienia WorkFieldGIS")
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

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 6
      text: qsTr("Kształty: gęstość łuków")
      color: "#B0BEC5"
      font: Theme.strongTipFont
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Bok")
        color: "white"
        font: Theme.tipFont
      }

      Slider {
        id: suwakBoku
        Layout.fillWidth: true
        from: 0.05
        to: 2.0
        stepSize: 0.05
        value: terenSettings.ksztaltBok > 0 ? terenSettings.ksztaltBok : 0.25
        onMoved: {
          const bok = Math.round(value * 100) / 100;
          terenSettings.ksztaltBok = bok;
          settings.setValue('WorkField/ksztaltBok', bok.toFixed(2));
        }
      }

      Text {
        text: terenSettings.ksztaltBok.toFixed(2) + " m"
        color: "white"
        font: Theme.strongTipFont
      }
    }

    // Liczba w metrach niewiele mowi, dopoki nie widac, ile z niej wyjdzie
    // wierzcholkow. Korona i staw to dwa konce tej samej skali.
    Text {
      Layout.fillWidth: true
      text: qsTr("Korona 3 m: %1 wierzchołków. Staw 50 m: %2. Odchyłka od łuku przy koronie: %3 cm.").arg(terenSettings.wierzcholkowOkregu(3)).arg(terenSettings.wierzcholkowOkregu(50)).arg((terenSettings.ksztaltBok * terenSettings.ksztaltBok / (8 * 3) * 100).toFixed(1))
      color: "#B0BEC5"
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Najwyżej")
        color: "white"
        font: Theme.tipFont
      }

      ComboBox {
        id: wyborSufitu
        Layout.fillWidth: true
        model: [128, 256, 512, 1024, 2048]
        currentIndex: Math.max(0, model.indexOf(terenSettings.ksztaltMaks))
        onActivated: {
          terenSettings.ksztaltMaks = model[currentIndex];
          settings.setValue('WorkField/ksztaltMaks', model[currentIndex]);
        }
      }

      Text {
        text: qsTr("wierzchołków")
        color: "#B0BEC5"
        font: Theme.tipFont
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Bok to długość jednego odcinka, na jakie dzielone są okręgi i krzywe. Mniejszy bok to gładszy kształt i większy plik. Ogranicznik pilnuje, żeby duży obiekt nie urósł do kilku tysięcy wierzchołków.")
      color: "#B0BEC5"
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 6
      text: qsTr("Panele akcji")
      color: "#B0BEC5"
      font: Theme.strongTipFont
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Gęstość")
        color: "white"
        font: Theme.tipFont
      }

      ComboBox {
        id: wyborGestosci
        Layout.fillWidth: true
        model: [qsTr("Zwarta"), qsTr("Standardowa"), qsTr("Rękawice")]
        currentIndex: settings.valueInt('WorkField/gestosc', 1)
        onActivated: {
          settings.setValue('WorkField/gestosc', currentIndex);
          Theme.gestosc = currentIndex;
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Układ")
        color: "white"
        font: Theme.tipFont
      }

      ComboBox {
        id: wyborUkladu
        Layout.fillWidth: true
        model: [qsTr("Lista wierszy"), qsTr("Kafle")]
        currentIndex: settings.valueInt('WorkField/ukladAkcji', 0)
        onActivated: {
          settings.setValue('WorkField/ukladAkcji', currentIndex);
          Theme.ukladAkcji = currentIndex;
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Zmiana działa od razu. Gęstość „Rękawice” powiększa przyciski i odstępy do pracy w rękawicach.")
      color: "#B0BEC5"
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 6
      visible: Qt.platform.os !== "android" && Qt.platform.os !== "ios"
      spacing: 8

      Switch {
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
        font: Theme.tipFont
        wrapMode: Text.Wrap
      }
    }

    Rectangle {
      Layout.fillWidth: true
      height: 1
      color: "#455A64"
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
}
