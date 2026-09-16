import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qgis
import org.qfield
import org.qfield.core
import Theme

/**
 * \ingroup qml
 *
 * WorkField 15.09.2026 — CZY PROJEKT NADĄŻA ZA APLIKACJĄ.
 *
 * ======================================================================
 * PO CO
 * ======================================================================
 * Mechanizm porównywania stempla z katalogiem działa od 13.09 i przez dwa
 * dni MILCZAŁ — dało się go zapytać wyłącznie z konsoli. To jest dokładnie
 * ta klasa długu, którą nazwaliśmy przy sygnale `geometriaZniszczona`:
 * kod wykrywa, nikt się nie dowiaduje.
 *
 * ======================================================================
 * CO WOLNO Z TEGO EKRANU
 * ======================================================================
 * Zakładanie modułów TERENOWYCH — tych, które zmieniają ustawienia
 * projektu i nic nie mogą zepsuć w danych. Reszta zostaje w biurze,
 * gdzie jest kopia bazy i widać wynik przed wysyłką.
 *
 * Zasada z 09.09: **sprawdzać wolno wszędzie, naprawiać nie wszędzie.**
 *
 * Przycisk przy module biurowym jest NIECZYNNY I PODAJE POWÓD. Przycisk
 * widoczny i milczący jest gorszy od braku przycisku — to zasada z 17.08,
 * ta sama, przez którą zniknęły „Magazyn" i „Nowy z szablonu" z telefonu.
 */
Popup {
  id: ekranWyposazenia

  parent: mainWindow.contentItem
  width: Math.min(720, mainWindow.width - 16)
  height: Math.min(860, mainWindow.height - 24)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: Popup.CloseOnEscape

  property var pozycje: []
  property string komunikat: ""
  property bool blad: false

  Wyposazenie {
    id: wyposazenie
  }

  function odswiez() {
    pozycje = wyposazenie.sprawdz(qgisProject);
  }

  function otworz() {
    komunikat = "";
    blad = false;
    odswiez();
    open();
  }

  //! Barwa stanu. `nowszy` celowo INNA niż `brak` — znaczy coś
  //! odwrotnego: to aplikacja jest przestarzała, nie projekt.
  function barwa(stan) {
    if (stan === "zgodny")
      return "#81C784";
    if (stan === "nowszy")
      return "#CE93D8";
    if (stan === "starszy")
      return "#FFC107";
    return "#EF5350";
  }

  function opisStanu(m) {
    if (m.stan === "zgodny")
      return qsTr("wersja %1 — zgodna").arg(m.wAplikacji);
    if (m.stan === "nowszy")
      return qsTr("projekt ma %1, aplikacja oczekuje %2 — TO APLIKACJA JEST STARSZA")
               .arg(m.wProjekcie).arg(m.wAplikacji);
    if (m.stan === "starszy")
      return qsTr("projekt ma %1, aplikacja oczekuje %2").arg(m.wProjekcie).arg(m.wAplikacji);
    return qsTr("nie ma — aplikacja oczekuje wersji %1").arg(m.wAplikacji);
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Wyposażenie projektu")
        color: "#80CBC4"
        font: Theme.strongFont
        elide: Text.ElideRight
      }

      ToolButton {
        text: qsTr("Odśwież")
        font: Theme.tinyFont
        onClicked: ekranWyposazenia.odswiez()
      }

      ToolButton {
        text: qsTr("Zamknij")
        font: Theme.tinyFont
        onClicked: ekranWyposazenia.close()
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Katalog modułów jedzie w aplikacji, więc nie może się z nią rozjechać. Stempel siedzi w tabeli WF_WYPOSAZENIE w bazie projektu.")
      color: "#B0BEC5"
      font: Theme.tipFont
      wrapMode: Text.Wrap
    }

    Text {
      Layout.fillWidth: true
      visible: ekranWyposazenia.komunikat !== ""
      text: ekranWyposazenia.komunikat
      color: ekranWyposazenia.blad ? "#EF5350" : "#9CCC65"
      font: Theme.tipFont
      wrapMode: Text.Wrap
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: 6
      model: ekranWyposazenia.pozycje

      delegate: Rectangle {
        width: ListView.view.width
        height: tresc.implicitHeight + 16
        radius: 4
        color: "#14FFFFFF"

        readonly property string powodOdmowy: wyposazenie.mozeZalozyc(modelData.modul)

        ColumnLayout {
          id: tresc

          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: 8
          spacing: 3

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
              width: 10
              height: 10
              radius: 5
              color: ekranWyposazenia.barwa(modelData.stan)
            }

            Text {
              Layout.fillWidth: true
              text: modelData.nazwa
              color: "white"
              font: Theme.defaultFont
              elide: Text.ElideRight
            }

            Button {
              text: qsTr("Załóż")
              font: Theme.tinyFont
              visible: modelData.stan !== "zgodny" && modelData.stan !== "nowszy"
              enabled: powodOdmowy === ""
              onClicked: {
                const w = wyposazenie.zaloz(qgisProject, modelData.modul);
                ekranWyposazenia.komunikat = w.opis;
                ekranWyposazenia.blad = !w.ok;
                ekranWyposazenia.odswiez();
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: ekranWyposazenia.opisStanu(modelData)
            color: ekranWyposazenia.barwa(modelData.stan)
            font: Theme.tinyFont
            wrapMode: Text.Wrap
          }

          // Powód odmowy PRZY przycisku, nie w osobnym okienku: człowiek
          // w rękawicach nie będzie szukał, czemu nie da się kliknąć.
          Text {
            Layout.fillWidth: true
            visible: powodOdmowy !== "" && modelData.stan !== "zgodny"
            text: qsTr("nie założę tego z telefonu — %1").arg(powodOdmowy)
            color: "#90A4AE"
            font: Theme.tinyFont
            wrapMode: Text.Wrap
          }

          Text {
            Layout.fillWidth: true
            visible: modelData.opis !== ""
            text: modelData.opis
            color: "#78909C"
            font: Theme.tipFont
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: modelData.data !== undefined && String(modelData.data) !== ""
            text: qsTr("ostatnio: %1").arg(String(modelData.data).replace("T", " "))
            color: "#607D8B"
            font: Theme.tinyFont
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: parent.count === 0
        text: qsTr("Nie udało się odczytać katalogu wyposażenia.")
        color: "#EF5350"
        font: Theme.tipFont
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Zakładanie modułów, które zmieniają strukturę bazy, odbywa się w biurze — tam jest kopia i widać wynik przed wysyłką.")
      color: "#78909C"
      font: Theme.tinyFont
      wrapMode: Text.Wrap
    }
  }
}
