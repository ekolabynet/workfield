import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

ColumnLayout {
  property var settingsPage
  property var settingsRegistry
  property var settingsModel
  property Component rowDelegate

  signal openLocatorSettings
  signal openPluginManager

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20
    Layout.bottomMargin: 0

    columns: 2
    columnSpacing: 0
    rowSpacing: 0

    Label {
      text: qsTr('Interfejs')
      font: Theme.strongFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.topMargin: 5
      Layout.columnSpan: 2
    }

    // WorkField 23.08.2026 — "Customize search bar" i "Manage plugins" stad
    // znikly. Obie byly ikonka "..." bez etykiety na TRZECIM poziomie menu,
    // obok zupelnie innych rzeczy, a wtyczki mialy do tego duplikat na
    // poziomie pierwszym. Teraz obie sa w zakladce Narzedzia prawej szuflady,
    // pod wlasnymi nazwami.
  }

  ListView {
    Layout.fillWidth: true
    Layout.preferredHeight: contentHeight
    interactive: false

    model: settingsModel

    delegate: rowDelegate
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20
    Layout.bottomMargin: 5
    Layout.topMargin: 5

    columns: 1
    columnSpacing: 0
    rowSpacing: 5

    visible: platformUtilities.capabilities & PlatformUtilities.AdjustBrightness

    Label {
      Layout.fillWidth: true

      text: qsTr('Przygaszaj ekran przy bezczynności')
      font: Theme.defaultFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
    }

    QfSlider {
      id: slider
      Layout.fillWidth: true
      value: settings ? settings.value('dimTimeoutSeconds', 60) : 60
      from: 0
      to: 180
      stepSize: 10
      suffixText: " s"
      implicitHeight: 40

      onMoved: function () {
        iface.setScreenDimmerTimeout(value);
        settings.setValue('dimTimeoutSeconds', value);
      }
    }

    Label {
      Layout.fillWidth: true
      text: qsTr('Po ilu sekundach bezczynności przygasić ekran, żeby oszczędzić baterię.')

      font: Theme.tipFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20
    Layout.bottomMargin: 10
    Layout.topMargin: 5

    columns: 1
    columnSpacing: 0
    rowSpacing: 10

    RowLayout {
      Layout.fillWidth: true
      spacing: 10

      Label {
        Layout.fillWidth: true
        text: qsTr("Motyw:")
        font: Theme.tipFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }

      QfComboBox {
        id: appearanceComboBox
        enabled: true
        Layout.preferredWidth: 240
        Layout.alignment: Qt.AlignVCenter
        font: Theme.defaultFont

        popup.font: Theme.defaultFont
        popup.topMargin: mainWindow.sceneTopMargin
        popup.bottomMargin: mainWindow.sceneTopMargin

        model: ListModel {
          ListElement {
            name: qsTr('Jak w systemie')
            value: 'system'
          }
          ListElement {
            name: qsTr('Jasny')
            value: 'light'
          }
          ListElement {
            name: qsTr('Ciemny')
            value: 'dark'
          }
        }
        textRole: "name"
        valueRole: "value"

        property bool initialized: false

        onCurrentValueChanged: {
          if (initialized) {
            Theme.appearance = currentValue;
          }
        }

        Component.onCompleted: {
          currentIndex = indexOfValue(Theme.appearance);
          initialized = true;
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 10

      Label {
        Layout.fillWidth: true
        text: qsTr("Skala czcionki:")
        font: Theme.tipFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }

      QfComboBox {
        id: fontScaleComboBox
        enabled: true
        Layout.preferredWidth: 240
        Layout.alignment: Qt.AlignVCenter
        font: Theme.defaultFont

        popup.font: Theme.defaultFont
        popup.topMargin: mainWindow.sceneTopMargin
        popup.bottomMargin: mainWindow.sceneTopMargin

        model: ListModel {
          ListElement {
            name: qsTr('Bardzo mała')
            value: 0.75
          }
          ListElement {
            name: qsTr('Normalna')
            value: 1.0
          }
          ListElement {
            name: qsTr('Duża')
            value: 1.5
          }
          ListElement {
            name: qsTr('Bardzo duża')
            value: 2.0
          }
        }
        textRole: "name"
        valueRole: "value"

        property bool initialized: false

        onCurrentValueChanged: {
          if (initialized) {
            Theme.fontScale = currentValue;
          }
        }

        Component.onCompleted: {
          currentIndex = indexOfValue(Theme.fontScale);
          initialized = true;
        }
      }
    }

    // ── WorkField 23.08.2026: wlasny wyglad interfejsu ──────────
    // Skala czcionki wyzej ("Tiny/Normal/Large") mnozy rozmiar systemowy.
    // Tu ustawia sie sam rozmiar podstawowy, rodzine i dwie barwy. Motyw
    // z pliku zostaje podkladem; to jest nadpisanie, ktore przezywa restart
    // i przelaczenie jasny/ciemny.
    Rectangle {
      Layout.fillWidth: true
      Layout.topMargin: 10
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
    }

    Label {
      Layout.fillWidth: true
      Layout.topMargin: 6
      text: qsTr("Czcionka i barwy interfejsu")
      font: Theme.strongTipFont
      color: Theme.mainTextColor
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 10

      Label {
        Layout.fillWidth: true
        text: qsTr("Rodzina czcionki:")
        font: Theme.tipFont
        color: Theme.mainTextColor
      }

      QfComboBox {
        id: rodzinaCzcionkiCombo

        Layout.preferredWidth: 240
        font: Theme.defaultFont
        popup.font: Theme.defaultFont
        popup.topMargin: mainWindow.sceneTopMargin
        popup.bottomMargin: mainWindow.sceneTopMargin

        property bool gotowy: false

        Component.onCompleted: {
          // Pusty napis = czcionka systemowa. Jest pierwszy na liscie, zeby
          // powrot do stanu wyjsciowego byl jednym klikiem, a nie szukaniem.
          model = [qsTr("systemowa")].concat(Theme.dostepneCzcionki());
          const biezaca = Theme.rodzinaCzcionki;
          currentIndex = biezaca === "" ? 0 : Math.max(0, model.indexOf(biezaca));
          gotowy = true;
        }

        onCurrentIndexChanged: {
          if (gotowy)
            Theme.rodzinaCzcionki = currentIndex === 0 ? "" : model[currentIndex];
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Label {
        Layout.fillWidth: true
        text: qsTr("Rozmiar podstawowy (pt, 0 = systemowy):")
        font: Theme.tipFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }

      SpinBox {
        id: rozmiarCzcionkiPole
        from: 0
        to: 40
        stepSize: 1
        editable: true
        font: Theme.defaultFont
        value: Math.round(Theme.rozmiarCzcionki)
        onValueModified: Theme.rozmiarCzcionki = value
      }
    }

    Repeater {
      model: [
        {
          "wlasnosc": "mainTextColor",
          "etykieta": qsTr("Barwa napisów:"),
          "proby": ["#e6e1e5", "#ffffff", "#B0BEC5", "#80CBC4", "#FFD54F", "#212121"]
        },
        {
          "wlasnosc": "mainBackgroundColor",
          "etykieta": qsTr("Barwa tła:"),
          "proby": ["#1c1b1f", "#2a2a2e", "#263238", "#37474F", "#000000", "#ECEFF1"]
        }
      ]

      ColumnLayout {
        id: wierszBarwy

        required property var modelData

        Layout.fillWidth: true
        spacing: 4

        Label {
          Layout.fillWidth: true
          Layout.topMargin: 6
          text: wierszBarwy.modelData.etykieta
          font: Theme.tipFont
          color: Theme.mainTextColor
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          Repeater {
            model: wierszBarwy.modelData.proby

            Rectangle {
              required property string modelData

              Layout.preferredWidth: 30
              Layout.preferredHeight: 30
              radius: 4
              color: modelData
              border.color: Theme.controlBorderColor
              border.width: 1

              MouseArea {
                anchors.fill: parent
                // Pole tekstowe obok ma wiazanie do barwy motywu i odswiezy
                // sie samo. Recznego przypisania NIE robimy — zerwaloby to
                // wiazanie i pole przestaloby nadazac za kolejnymi zmianami.
                onClicked: Theme.ustawBarweWlasna(wierszBarwy.modelData.wlasnosc, parent.color)
              }
            }
          }

          TextField {
            id: poleBarwy

            Layout.preferredWidth: 110
            font: Theme.tipFont
            placeholderText: "#RRGGBB"
            text: wierszBarwy.modelData.wlasnosc === "mainTextColor" ? Theme.mainTextColor.toString() : Theme.mainBackgroundColor.toString()

            // Zapisujemy dopiero na Enter — inaczej kazda wpisana litera
            // probowalaby byc barwa i interfejs migalby przy pisaniu.
            onAccepted: Theme.ustawBarweWlasna(wierszBarwy.modelData.wlasnosc, text)
          }
        }
      }
    }

    RowLayout {
      Layout.topMargin: 6
      Layout.fillWidth: true
      spacing: 6

      Button {
        text: qsTr("Przywróć barwy motywu")
        font: Theme.tipFont
        onClicked: Theme.przywrocBarwyMotywu()
      }

      /*
       * PODGLĄD STYLIZACJI — prośba Piotra z 24.08.2026.
       *
       * Zmiana barwy napisów albo tła dotyka KAŻDEGO okna w aplikacji,
       * a widać ją tylko tam, gdzie się akurat zajrzy. Ciemny napis na
       * ciemnym przycisku znajdowaliśmy dziś cztery razy, za każdym razem
       * po fakcie i w innym oknie.
       *
       * Ta strona pokazuje wszystkie kontrolki naraz i — co ważniejsze —
       * LICZY kontrast każdej pary napis/tło wedle WCAG. Nie trzeba mrużyć
       * oczu: jest liczba i werdykt.
       */
      Button {
        text: qsTr("Podgląd stylizacji")
        font: Theme.tipFont
        onClicked: podgladStylu.open()
      }

      Item {
        Layout.fillWidth: true
      }
    }

    QfPodgladStylu {
      id: podgladStylu
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.topMargin: 10
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 10

      Label {
        Layout.fillWidth: true
        text: qsTr("Język:")
        font: Theme.tipFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }

      QfComboBox {
        id: languageComboBox
        enabled: true
        Layout.preferredWidth: 240
        Layout.alignment: Qt.AlignVCenter
        font: Theme.defaultFont

        popup.font: Theme.defaultFont
        popup.topMargin: mainWindow.sceneTopMargin
        popup.bottomMargin: mainWindow.sceneBottomMargin

        property variant languageCodes: undefined
        property string currentLanguageCode: undefined

        onActivated: {
          if (currentLanguageCode != undefined) {
            var newLanguageCode = languageCodes[currentIndex];
            if (newLanguageCode !== currentLanguageCode) {
              iface.changeLanguage(newLanguageCode);
              currentLanguageCode = newLanguageCode;
            }
          }
        }

        Component.onCompleted: {
          var customLanguageCode = settings.value('customLanguage', '');
          var languages = iface.availableLanguages();
          languageCodes = [""].concat(Object.keys(languages));
          var systemLanguage = qsTr("system");
          var systemLanguageSuffix = systemLanguage !== 'system' ? ' (system)' : '';
          var items = [systemLanguage + systemLanguageSuffix];
          languageComboBox.model = items.concat(Object.values(languages));
          languageComboBox.currentIndex = languageCodes.indexOf(customLanguageCode);
          currentLanguageCode = customLanguageCode || '';
        }
      }
    }

    Label {
      text: qsTr("Found a missing or incomplete language? %1Join the translator community.%2").arg('<a href="https://explore.transifex.com/opengisch/qfield-for-qgis/">').arg('</a>')
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      textFormat: Qt.RichText
      wrapMode: Text.WordWrap
      Layout.fillWidth: true

      onLinkActivated: link => {
        Qt.openUrlExternally(link);
      }
    }
  }
}
