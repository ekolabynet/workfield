import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * WorkField: sekcja „Teren" w Ustawieniach.
 *
 * Bylo to osobne okno (`QfTerenSettings.qml`, Popup nad mapa). Przeniesione
 * 24.09.2026, bo to sa USTAWIENIA i nie ma powodu, zeby mialy wlasna droge,
 * wlasny wyglad i wlasny przycisk „Zamknij". Panelem zostaje to, co jest
 * CZYNNOSCIA (kopia, wymiana, studio); ustawienie idzie do Ustawien.
 *
 * Skrot z szuflady nie zginal: wola teraz `pokazUstawienia("teren")`,
 * dokladnie tak, jak robi to od dawna wpis GNSS.
 *
 * Wartosci siedza w ustawieniach aplikacji (klucze WorkField/*), a dwie
 * z nich — `ksztaltBok` i `ksztaltMaks` — trzyma KORZEN strony ustawien,
 * bo czyta je silnik ksztaltow w `QgisMobileapp.qml`. Identyfikatory nie
 * przechodza miedzy plikami `.qml`, wiec droga jest w gore: sekcja pisze
 * do `settingsPage`, a `QgisMobileapp` podpina sie do `qfieldSettings`.
 */
ColumnLayout {
  id: sekcjaTeren

  property var settingsPage
  property var settingsRegistry
  property var settingsModel
  property Component rowDelegate

  function haptykaTest(baza) {
    const sila = settings.valueInt('WorkField/haptykaSila', 3);
    if (sila > 0) {
      platformUtilities.vibrate(baza * sila);
    }
  }

  //! Ile wierzcholkow dostanie okrag o danym promieniu — zeby bylo widac
  //! SKUTEK liczby, ktora czlowiek wlasnie ustawil, zanim zacznie rysowac.
  function wierzcholkowOkregu(promien) {
    const bok = settingsPage ? settingsPage.ksztaltBok : 0.25;
    const sufit = settingsPage ? settingsPage.ksztaltMaks : 512;
    if (!(bok > 0) || !(promien > 0)) {
      return 72;
    }
    const polowa = bok / (2 * promien);
    if (polowa >= 1) {
      return 8;
    }
    const ile = Math.ceil(2 * Math.PI / (2 * Math.asin(polowa)));
    return Math.max(8, Math.min(sufit, ile));
  }

  ColumnLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20
    spacing: 10

    Label {
      Layout.fillWidth: true
      Layout.topMargin: 5
      text: qsTr("Teren")
      font: Theme.strongFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Przyciski edycji geometrii")
      color: Theme.secondaryTextColor
      font: Theme.strongTipFont
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Rozmiar")
        color: Theme.mainTextColor
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
        color: Theme.mainTextColor
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
        color: Theme.mainTextColor
        font: Theme.tipFont
        wrapMode: Text.Wrap
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Wibracje")
        color: Theme.mainTextColor
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
          sekcjaTeren.haptykaTest(15);
        }
      }

      Text {
        text: Math.round(suwakHaptyka.value) === 0 ? qsTr("wył.") : "×" + Math.round(suwakHaptyka.value)
        color: Theme.mainTextColor
        font: Theme.tipFont
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        text: qsTr("Testuj tony:")
        color: Theme.secondaryTextColor
        font: Theme.tinyFont
      }

      Button {
        text: qsTr("dodaj")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: sekcjaTeren.haptykaTest(15)
      }

      Button {
        text: qsTr("usuń")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: sekcjaTeren.haptykaTest(45)
      }

      Button {
        text: qsTr("zapisz")
        font.pointSize: Theme.tinyFont.pointSize
        onClicked: sekcjaTeren.haptykaTest(80)
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Rozmiar i okrągłość zaczną działać po ponownym uruchomieniu aplikacji. Siła wibracji działa od razu.")
      color: Theme.secondaryTextColor
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 6
      text: qsTr("Kształty: gęstość łuków")
      color: Theme.secondaryTextColor
      font: Theme.strongTipFont
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Bok")
        color: Theme.mainTextColor
        font: Theme.tipFont
      }

      Slider {
        id: suwakBoku
        Layout.fillWidth: true
        from: 0.05
        to: 2.0
        stepSize: 0.05
        value: settingsPage && settingsPage.ksztaltBok > 0 ? settingsPage.ksztaltBok : 0.25
        onMoved: {
          const bok = Math.round(value * 100) / 100;
          if (settingsPage) {
            settingsPage.ksztaltBok = bok;
          }
          settings.setValue('WorkField/ksztaltBok', bok.toFixed(2));
        }
      }

      Text {
        text: (settingsPage ? settingsPage.ksztaltBok : 0.25).toFixed(2) + " m"
        color: Theme.mainTextColor
        font: Theme.strongTipFont
      }
    }

    // Liczba w metrach niewiele mowi, dopoki nie widac, ile z niej wyjdzie
    // wierzcholkow. Korona i staw to dwa konce tej samej skali.
    Text {
      Layout.fillWidth: true
      text: qsTr("Korona 3 m: %1 wierzchołków. Staw 50 m: %2. Odchyłka od łuku przy koronie: %3 cm.").arg(sekcjaTeren.wierzcholkowOkregu(3)).arg(sekcjaTeren.wierzcholkowOkregu(50)).arg((((settingsPage ? settingsPage.ksztaltBok : 0.25) * (settingsPage ? settingsPage.ksztaltBok : 0.25)) / 24 * 100).toFixed(1))
      color: Theme.secondaryTextColor
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Najwyżej")
        color: Theme.mainTextColor
        font: Theme.tipFont
      }

      ComboBox {
        id: wyborSufitu
        Layout.fillWidth: true
        model: [128, 256, 512, 1024, 2048]
        currentIndex: Math.max(0, model.indexOf(settingsPage ? settingsPage.ksztaltMaks : 512))
        onActivated: {
          if (settingsPage) {
            settingsPage.ksztaltMaks = model[currentIndex];
          }
          settings.setValue('WorkField/ksztaltMaks', model[currentIndex]);
        }
      }

      Text {
        text: qsTr("wierzchołków")
        color: Theme.secondaryTextColor
        font: Theme.tipFont
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Bok to długość jednego odcinka, na jakie dzielone są okręgi i krzywe. Mniejszy bok to gładszy kształt i większy plik. Ogranicznik pilnuje, żeby duży obiekt nie urósł do kilku tysięcy wierzchołków.")
      color: Theme.secondaryTextColor
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 6
      spacing: 8

      Switch {
        id: przelacznikPrzezPunkty
        checked: settingsPage ? settingsPage.krzywaPrzezPunkty : false
        onToggled: {
          if (settingsPage) {
            settingsPage.krzywaPrzezPunkty = checked;
          }
          settings.setValue('WorkField/krzywaPrzezPunkty', checked);
        }
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Krzywa przechodzi przez wskazane punkty")
        color: Theme.mainTextColor
        font: Theme.tipFont
        wrapMode: Text.Wrap
      }
    }

    // Roznica jest realna i warto ja nazwac liczbami, a nie przymiotnikami.
    // Na pieciokacie o promieniu 10 m: B-sklejana biegnie srednio 2,3 m
    // OBOK tapnietych punktow i obejmuje 184 m kw., krzywa przez punkty
    // obejmuje 297 m kw. — przy prawdziwym kole 314 m kw.
    Text {
      Layout.fillWidth: true
      text: przelacznikPrzezPunkty.checked ? qsTr("Obrys trafia w każdy tapnięty punkt. Przy punktach postawionych blisko siebie potrafi między nimi zafalować. Do inwentaryzacji, gdzie każde tapnięcie jest pomiarem.") : qsTr("Obrys biegnie OBOK tapniętych punktów — one go tylko przyciągają. Gładziej, ale mniej wiernie: na koronie o promieniu 10 m mija je nawet o 2 m. Do obrysów „na oko”.")
      color: Theme.secondaryTextColor
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 6
      text: qsTr("Panele akcji")
      color: Theme.secondaryTextColor
      font: Theme.strongTipFont
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Gęstość")
        color: Theme.mainTextColor
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
        color: Theme.mainTextColor
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
      color: Theme.secondaryTextColor
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
        color: Theme.mainTextColor
        font: Theme.tipFont
        wrapMode: Text.Wrap
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
    }

    Button {
      Layout.fillWidth: true
      text: qsTr("Klawisze szybkiego zapisu…")
      // Okno klawiszy otwiera sie NAD ustawieniami. Wczesniej trzeba bylo
      // najpierw zamknac karte „Teren", bo byla osobnym oknem modalnym —
      // teraz nie ma czego zamykac.
      onClicked: {
        if (typeof captureSettings !== 'undefined') {
          captureSettings.openDialog();
        }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: mainWindow.sceneBottomMargin + 20
    }
  }
}
