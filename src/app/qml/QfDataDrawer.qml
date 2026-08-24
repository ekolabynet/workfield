import QtQuick
import Qt.labs.folderlistmodel
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

Drawer {
  id: dataDrawer

  property var t
  property var layerTree
  property var activeLayer

  signal layerActivated(var layer)
  signal addExistingRequested

  //! Ktora zakladka jest widoczna — czyta chrom desktopowy, zeby podswietlic
  //! swoja pozycje tak samo, jak robi to dla zakladek lewej szuflady.
  readonly property int zakladkaAktywna: drawerTabs.currentIndex

  //! WorkField 23.08.2026 — maska elewacji jako WLASNOSC, nie odczyt
  //! z ustawien w wiazaniu. `settings.valueInt()` to wywolanie funkcji:
  //! wiazanie policzy sie raz i nie drgnie po zmianie, wiec podswietlenie
  //! zostawaloby na starej wartosci az do przebudowy szuflady.
  property int maskaElewacji: settings.valueInt('WorkField/maskaElewacji', 0)

  /**
   * WorkField 23.08.2026 — otwiera szuflade na wskazanej zakladce.
   * Na komputerze zakladki prawej szuflady siedza w pasku gornym po prawej;
   * klikniecie ma dzialac tak samo jak przelaczenie zakladki w srodku.
   */
  function otworzZakladke(numer) {
    drawerTabs.currentIndex = numer;
    if (!dataDrawer.opened)
      dataDrawer.open();
  }

  //! Czy aplikacja jest teraz w tym trybie — pozycja menu ma to pokazac,
  //! bo to ona jest jedynym wyjsciem z trybu na komputerze.
  function trybAktywny(tryb) {
    return tryb !== undefined && stateMachine.state === tryb;
  }

  /**
   * WorkField 23.08.2026 — jedno miejsce, w ktorym pozycja "Narzedzi" zamienia
   * sie w czynnosc. Wczesniej byl to `switch` wewnatrz delegata; wtedy dodanie
   * pozycji do modelu bez dopisania `case` nie bylo bledem — pozycja po prostu
   * milczala. Tak wlasnie zniknelo "Policz CHM".
   *
   * Tu brak galezi konczy sie ostrzezeniem, ktore widac.
   */
  function wykonajNarzedzie(czynnosc) {
    switch (czynnosc) {
    case "measurement":
      mainWindow.przelaczPomiar();
      dataDrawer.close();
      return;
    case "view3d":
      mainWindow.przelaczWidok3D();
      dataDrawer.close();
      return;
    case "print":
      // Drawer to Popup, nie Item — mapToItem na nim NIE ISTNIEJE i konczylo
      // sie "TypeError: Property 'mapToItem' ... is not a function", czyli
      // pozycja "Wydruk" nie robila nic. Punkt bierzemy z elementu tresci,
      // ktory Itemem juz jest, i liczymy go tak samo jak SideMenu — wzgledem
      // mainWindow.contentItem, bo w tych wspolrzednych printMenu sie otwiera.
      dashBoard.showPrintLayouts(dataDrawer.contentItem.mapToItem(mainWindow.contentItem, 0, 0));
      return;
    case "bookmarks":
      dashBoard.showBookmarks();
      dataDrawer.close();
      return;
    case "lokalizator":
      // Bylo: Ustawienia > Wyglad > ikonka "..." bez etykiety. Poziom trzeci,
      // bez nazwy, obok zupelnie innych rzeczy.
      dataDrawer.close();
      mainWindow.pokazUstawieniaLokalizatora();
      return;
    case "niebo":
      nieboPanel.open();
      return;
    case "gnssDiag":
      gnssDiagPopup.open();
      return;
    case "gnssSettings":
      dataDrawer.close();
      mainWindow.pokazUstawienia("positioning");
      return;
    case "teren":
      dataDrawer.close();
      terenSettings.open();
      return;
    case "klawisze":
      dataDrawer.close();
      captureSettings.openDialog();
      return;
    case "editor":
      dataDrawer.close();
      textEditor.open();
      return;
    case "kopia":
      panelKopii.open();
      return;
    case "spis":
      // WorkField 24.08.2026 — BEZ dataDrawer.close() przed open().
      // Szuflada jest modalna; jej przyciemnienie gasnie z opoznieniem
      // i przez chwile lezy NA panelu, ktory wlasnie sie otworzyl. Panel
      // wychodzi przez to caly wyblakly — nie tylko napisy, ale i ramki
      // przyciskow. "Niebo" robi to poprawnie i wyglada dobrze: otwiera
      // panel i zostawia szuflade samej sobie.
      panelSpisu.open();
      return;
    case "chm":
      dataDrawer.close();
      dashBoard.computeChmAction();
      return;
    case "plugins":
      dashBoard.showPluginManager();
      dataDrawer.close();
      return;
    case "lockScreen":
      dashBoard.lockScreen();
      dataDrawer.close();
      return;
    }
    displayToast(qsTr("Czynność „%1” nie ma jeszcze obsługi").arg(czynnosc), "warning");
  }

  edge: Qt.RightEdge
  width: Math.min(360, mainWindow.width * 0.85)
  height: parent.height
  dragMargin: 10
  interactive: opened || !overlayFeatureFormDrawer.opened


  // WorkField 22.08: bez wlasnego tla — Drawer bierze wtedy to samo, co lewa
  // szuflada. Wczesniej mainBackgroundColor dawalo czern obok szarosci.

  ColumnLayout {
    anchors.fill: parent
    anchors.topMargin: mainWindow.sceneTopMargin
    anchors.bottomMargin: mainWindow.sceneBottomMargin
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Narzędzia")
        font: t.strongFont
        color: t.mainTextColor
      }

      QfToolButton {
        width: 36
        height: 36
        padding: 0
        bgcolor: "transparent"
        iconSource: t.getThemeVectorIcon("ic_arrow_right_black_24dp")
        iconColor: t.mainTextColor
        onClicked: dataDrawer.close()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    TabBar {
      id: drawerTabs

      Layout.fillWidth: true
      currentIndex: 0

      TabButton {
        text: qsTr("Narzędzia")
        font: t.tipFont
      }
      TabButton {
        text: qsTr("Algorytmy")
        font: t.tipFont
      }
      TabButton {
        text: qsTr("Ustawienia")
        font: t.tipFont
      }
    }

    StackLayout {
      id: drawerStack

      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: drawerTabs.currentIndex


      // ── Narzędzia ───────────────────────────────────────────
      ColumnLayout {
        spacing: 0

        // WorkField 23.08.2026 — zakladka przebudowana z trzech powodow naraz:
        //
        //  1. Delegatem byl goly MenuItem: inna czcionka, inna wysokosc i ZERO
        //     ikon, mimo ze sasiednia zakladka ma ikone przy kazdej pozycji.
        //  2. Pozycja "Policz CHM" nie miala odpowiadajacego `case` w switchu —
        //     czynnosc widoczna w menu, ktora nie robila NIC. Zasada z 17.08:
        //     czynnosc widoczna w menu musi dzialac albo nie moze byc widoczna.
        //  3. Niebo, Teren i edytor plikow byly osiagalne wylacznie z trzeciego
        //     poziomu (Niebo: Narzedzia > Diagnostyka > stopka; Teren i edytor:
        //     LEWA szuflada > Dane > Teren > na sam dol). Wchodza na poziom 1.
        Repeater {
          model: [
            { "naglowek": qsTr("Na mapie") },
            { "label": qsTr("Pomiar odległości i powierzchni"), "action": "measurement", "ikona": "wfg_pomiar", "tryb": "measure" },
            { "label": qsTr("Widok 3D"), "action": "view3d", "ikona": "wfg_kostka", "tryb": "3d" },
            { "label": qsTr("Wydruki map"), "action": "print", "ikona": "wfg_wydruk" },
            { "label": qsTr("Zakładki przestrzenne"), "action": "bookmarks", "ikona": "wfg_zakladka" },
            { "label": qsTr("Pasek wyszukiwania"), "action": "lokalizator", "ikona": "wfg_lupa" },
            { "naglowek": qsTr("Niebo i pozycja") },
            { "label": qsTr("Niebo \u2014 satelity"), "action": "niebo", "ikona": "wfg_niebo" },
            { "label": qsTr("Diagnostyka GNSS / NTRIP"), "action": "gnssDiag", "ikona": "wfg_sprzet" },
            { "label": qsTr("Ustawienia pozycjonowania"), "action": "gnssSettings", "ikona": "wfg_ustawienia" },
            { "naglowek": qsTr("Teren i pliki") },
            { "label": qsTr("Ustawienia terenowe"), "action": "teren", "ikona": "wfg_teren" },
            { "label": qsTr("Klawisze szybkiego zapisu"), "action": "klawisze", "ikona": "wfg_zapisz" },
            { "label": qsTr("Edytor plików projektu"), "action": "editor", "ikona": "wfg_wlasciwosci" },
            { "label": qsTr("Spis plików \u2014 co zniknęło"), "action": "spis", "ikona": "wfg_przeglad" },
            { "label": qsTr("Kopia na nośnik"), "action": "kopia", "ikona": "wfg_paczka" },
            { "naglowek": qsTr("Aplikacja") },
            { "label": qsTr("Wtyczki"), "action": "plugins", "ikona": "wfg_paczka" },
            { "label": qsTr("Zablokuj ekran"), "action": "lockScreen", "ikona": "wfg_zamek" }
          ]

          // Naglowki i pozycje w JEDNYM modelu — kolejnosc widac w jednym
          // miejscu, a nie w czterech osobnych Repeaterach.
          Loader {
            Layout.fillWidth: true
            property var wpis: modelData
            sourceComponent: modelData.naglowek !== undefined ? naglowekSekcjiNarzedzi : pozycjaNarzedzia
          }
        }

        Item {
          Layout.fillHeight: true
        }
      }

      // ── Algorytmy ───────────────────────────────────────────
      ColumnLayout {
        spacing: 0

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

        // WorkField 23.08.2026 — CHM to rachunek na rastrach, a nie czynnosc
        // na mapie: NMPT minus NMT. Stalo w "Narzedziach" tylko dlatego, ze
        // tam trafilo z lewej szuflady. Tu ma sasiadow.
        //
        // Ta sekcja NIE zalezy od warstwy roboczej — lista algorytmow QGIS-a
        // ponizej zalezy, i dlatego stoi osobno, nad nia.
        Text {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.topMargin: 6
          text: qsTr("Rastry terenu")
          font: t.tipFont
          color: t.secondaryTextColor
        }

        QfPozycjaMenu {
          Layout.fillWidth: true
          t: dataDrawer.t
          text: qsTr("Policz CHM (NMPT \u2212 NMT)")
          ikona: "wfg_rzezba"
          onClicked: dataDrawer.wykonajNarzedzie("chm")
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.topMargin: 6
          Layout.preferredHeight: 1
          color: t.controlBorderColor
        }


    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: 8
      Layout.rightMargin: 8
      spacing: 8

      Label {
        Layout.fillWidth: true
        text: dataDrawer.activeLayer ? qsTr("Warstwa robocza: %1").arg(dataDrawer.activeLayer.name) : qsTr("Nie wybrano warstwy roboczej")
        font: t.defaultFont
        color: t.mainTextColor
        elide: Text.ElideMiddle
      }

      Button {
        text: qsTr("Zmień…")
        font.pointSize: t.tinyFont.pointSize
        onClicked: layerPickerDialog.open()
      }
    }


    Text {
      Layout.fillWidth: true
      Layout.leftMargin: 8
      Layout.rightMargin: 8
      visible: !dataDrawer.activeLayer
      text: qsTr("Wybierz warstwę roboczą, aby zobaczyć dostępne algorytmy.")
      font: t.tipFont
      color: t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

        QfProcessingAlgorithmsList {
          id: algorithmsList

          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: dataDrawer.activeLayer !== null && dataDrawer.activeLayer !== undefined
          inPlaceLayer: dataDrawer.activeLayer
        }

      }

      // ── Ustawienia ──────────────────────────────────────────
      // WorkField 22.08: sekcje ustawien wprost tutaj. Wczesniej droga do
      // "Pozycji" prowadzila przez zebatke, System, Ustawienia aplikacji
      // i ekran z indeksem — piec krokow i trzy jezyki wizualne. Teraz dwa.
      ColumnLayout {
        spacing: 0

        // WorkField 23.08.2026 — DOKLADNIE ta sama lista, co po lewej stronie
        // okna ustawien (QfSettings.kategorie). Wczesniej byly to dwie
        // niezalezne listy i po polaczeniu kategorii szuflada zostala przy
        // starym podziale: osiem pozycji prowadzacych do pieciu ekranow.
        //
        // Ikony ic_* to zestaw QFielda; nasze menu jedzie na Breeze (wfg_*),
        // wiec tu tez.
        Repeater {
          model: [
            {
              "id": "positioning",
              "nazwa": qsTr("Pozycja"),
              "ikona": "wfg_sprawdz"
            },
            {
              "id": "mapaRysowanie",
              "nazwa": qsTr("Mapa i rysowanie"),
              "ikona": "wfg_warstwy"
            },
            {
              "id": "interface",
              "nazwa": qsTr("Wygląd"),
              "ikona": "wfg_stylizacja"
            },
            {
              "id": "chmuraSiec",
              "nazwa": qsTr("Chmura i sieć"),
              "ikona": "wfg_chmura"
            },
            {
              "id": "advanced",
              "nazwa": qsTr("Zaawansowane"),
              "ikona": "wfg_ustawienia"
            }
          ]

          QfPozycjaMenu {
            t: dataDrawer.t
            text: modelData.nazwa
            ikona: modelData.ikona
            onClicked: {
              mainWindow.pokazUstawienia(modelData.id);
              dataDrawer.close();
            }
          }
        }

        // separator: nizej rzeczy, ktore nie sa ustawieniami
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          Layout.topMargin: 6
          Layout.bottomMargin: 6
          color: t.controlBorderColor
        }

        QfPozycjaMenu {
          t: dataDrawer.t
          ikona: "ic_info_white_24dp"
          text: qsTr("O aplikacji WorkField")
          onClicked: {
            dashBoard.showAbout();
            dataDrawer.close();
          }
        }

        QfPozycjaMenu {
          t: dataDrawer.t
          ikona: "ic_message_log_black_24dp"
          // WorkField 23.08.2026 — licznik nieprzeczytanych wedrowal razem
          // z pozycja. W menu "..." siedziala przy niej plakietka; gdyby
          // zostala tam, a pozycja tutaj, sygnal "cos sie stalo" znikalby
          // z pola widzenia dokladnie wtedy, gdy jest potrzebny.
          text: messageLog.unreadMessages ? qsTr("Dziennik komunikatów (%1)").arg(messageLog.unreadMessagesCount >= 10 ? "10+" : messageLog.unreadMessagesCount) : qsTr("Dziennik komunikatów")
          onClicked: {
            dashBoard.showMessageLog();
            dataDrawer.close();
          }
        }

        QfPozycjaMenu {
          t: dataDrawer.t
          ikona: "ic_send_white_24dp"
          text: qsTr("Udostępnij dziennik (debug)")
          onClicked: {
            const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss");
            const path = iface.dataRoot() + "logs/workfield_log_" + stamp + ".txt";
            if (iface.writeTextFile(path, messageLogModel.toPlainText())) {
              displayToast(qsTr("Dziennik zapisany: %1").arg(path));
              platformUtilities.sendDatasetTo(path);
            } else {
              displayToast(qsTr("Nie udało się zapisać dziennika"), "error");
            }
            dataDrawer.close();
          }
        }

        Item {
          Layout.fillHeight: true
        }
      }
    }

    
  }

  // ── delegaty zakladki "Narzedzia" ───────────────────────────
  // Osobne komponenty, bo Loader w Repeaterze musi umiec wybrac jeden z dwoch.

  Component {
    id: pozycjaNarzedzia

    QfPozycjaMenu {
      readonly property bool wTrybie: dataDrawer.trybAktywny(wpis.tryb)

      t: dataDrawer.t
      // Tryb wlaczony? Pozycja mowi wprost, ze druga klikniecie go wylaczy.
      text: wTrybie ? wpis.label + qsTr("  ·  wyłącz") : wpis.label
      ikona: wpis.ikona !== undefined ? wpis.ikona : ""
      wybrana: wTrybie
      onClicked: dataDrawer.wykonajNarzedzie(wpis.action)
    }
  }

  Component {
    id: naglowekSekcjiNarzedzi

    Item {
      implicitHeight: 30

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        height: 1
        color: dataDrawer.t.controlBorderColor
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        text: wpis.naglowek
        font: dataDrawer.t.tipFont
        color: dataDrawer.t.secondaryTextColor
      }
    }
  }

  Dialog {
    id: layerPickerDialog

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 420)
    height: Math.min(mainWindow.height - 120, 520)
    modal: true
    title: qsTr("Wybierz warstwę roboczą")

    ListView {
      anchors.fill: parent
      clip: true
      model: dataDrawer.layerTree

      delegate: ItemDelegate {
        width: ListView.view.width
        visible: model.LayerType === "vectorlayer" && model.VectorLayerPointer && !model.VectorLayerPointer.readOnly
        height: visible ? implicitHeight : 0
        font: t.defaultFont
        text: model.Name !== undefined ? model.Name : ""

        onClicked: {
          dataDrawer.layerActivated(model.VectorLayerPointer);
          layerPickerDialog.close();
        }
      }
    }
  }

  Popup {
    id: gnssDiagPopup

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 400)
    modal: true

    property double nowMs: Date.now()

    readonly property var posInfo: positionSource.active ? positionSource.positionInformation : null
    readonly property double rtcmAge: {
      const dt = positionSource.ntripLastBytesReceivedUtcDateTime;
      if (!dt || isNaN(dt.getTime()))
        return -1;
      return Math.max(0, (nowMs - dt.getTime()) / 1000);
    }

    function fmtBytes(b) {
      if (b < 1024)
        return b + " B";
      if (b < 1048576)
        return (b / 1024).toFixed(1) + " KB";
      return (b / 1048576).toFixed(2) + " MB";
    }

    Timer {
      running: gnssDiagPopup.visible
      interval: 1000
      repeat: true
      onTriggered: gnssDiagPopup.nowMs = Date.now()
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Diagnostyka GNSS / NTRIP")
        font: t.strongFont
        color: t.mainTextColor
      }

      GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 12
        rowSpacing: 4

        Text { text: qsTr("Odbiornik"); font: t.tipFont; color: t.secondaryTextColor }
        Text {
          Layout.fillWidth: true
          text: positionSource.deviceId === "" ? qsTr("wewnętrzny (telefon)") : positionSource.deviceId
          font: t.tipFont; color: t.mainTextColor; elide: Text.ElideMiddle
        }

        Text { text: qsTr("Połączenie"); font: t.tipFont; color: t.secondaryTextColor }
        Text {
          Layout.fillWidth: true
          text: positionSource.deviceSocketStateString + (positionSource.deviceLastError !== "" ? " — " + positionSource.deviceLastError : "")
          font: t.tipFont
          color: positionSource.deviceLastError !== "" ? "#EF5350" : t.mainTextColor
          wrapMode: Text.WordWrap
        }

        Text { text: qsTr("Fix"); font: t.tipFont; color: t.secondaryTextColor }
        Text {
          Layout.fillWidth: true
          text: gnssDiagPopup.posInfo ? gnssDiagPopup.posInfo.fixStatusDescription : "—"
          font: t.tipFont; color: t.mainTextColor
        }

        Text { text: qsTr("Satelity w użyciu"); font: t.tipFont; color: t.secondaryTextColor }
        Text {
          text: gnssDiagPopup.posInfo ? gnssDiagPopup.posInfo.satellitesUsed : "—"
          font: t.tipFont; color: t.mainTextColor
        }

        Text { text: qsTr("DOP (P/H/V)"); font: t.tipFont; color: t.secondaryTextColor }
        Text {
          text: gnssDiagPopup.posInfo ? gnssDiagPopup.posInfo.pdop.toFixed(1) + " / " + gnssDiagPopup.posInfo.hdop.toFixed(1) + " / " + gnssDiagPopup.posInfo.vdop.toFixed(1) : "—"
          font: t.tipFont; color: t.mainTextColor
        }

        Text { text: qsTr("Dokładność pozioma"); font: t.tipFont; color: t.secondaryTextColor }
        Text {
          text: gnssDiagPopup.posInfo && gnssDiagPopup.posInfo.haccValid ? (gnssDiagPopup.posInfo.hacc < 1 ? "±" + (gnssDiagPopup.posInfo.hacc * 100).toFixed(0) + " cm" : "±" + gnssDiagPopup.posInfo.hacc.toFixed(1) + " m") : "—"
          font: t.tipFont; color: t.mainTextColor
        }

        Text { text: qsTr("NTRIP"); font: t.tipFont; color: t.secondaryTextColor }
        Text {
          text: !positionSource.enableNtrip ? qsTr("wyłączony") : gnssDiagPopup.rtcmAge < 0 ? qsTr("łączenie…") : qsTr("aktywny")
          font: t.tipFont; color: t.mainTextColor
        }

        Text { text: qsTr("Wiek poprawek"); font: t.tipFont; color: t.secondaryTextColor }
        Text {
          text: !positionSource.enableNtrip ? "—" : gnssDiagPopup.rtcmAge < 0 ? "—" : Math.round(gnssDiagPopup.rtcmAge) + " s"
          font.family: t.tipFont.family
          font.pointSize: t.tipFont.pointSize
          font.bold: true
          color: gnssDiagPopup.rtcmAge < 0 ? t.mainTextColor : gnssDiagPopup.rtcmAge <= 5 ? "#00C853" : gnssDiagPopup.rtcmAge <= 15 ? "#F9A825" : "#EF5350"
        }

        Text { text: qsTr("Dane NTRIP"); font: t.tipFont; color: t.secondaryTextColor }
        Text {
          text: "\u2193 " + gnssDiagPopup.fmtBytes(positionSource.ntripBytesReceived) + "    \u2191 " + gnssDiagPopup.fmtBytes(positionSource.ntripBytesSent)
          font: t.tipFont; color: t.mainTextColor
        }

        Text { text: qsTr("Maska elewacji"); font: t.tipFont; color: t.secondaryTextColor }
        RowLayout {
          spacing: 6

          // WorkField 23.08.2026 — bylo [10, 15, 20]: maskę dało się zalozyc
          // i NIE DALO SIE ZDJAC. Zero wraca, tak jak w panelu Niebo, i tak
          // samo jak tam pierscien jest NASZ (zawsze da sie przestawic),
          // a komende wysylamy tylko wtedy, gdy jest komu.
          Repeater {
            model: [0, 10, 15, 20]

            Button {
              text: modelData === 0 ? qsTr("brak") : modelData + "\u00b0"
              font.pointSize: t.tinyFont.pointSize
              highlighted: dataDrawer.maskaElewacji === modelData
              onClicked: {
                dataDrawer.maskaElewacji = modelData;
                settings.setValue('WorkField/maskaElewacji', modelData);
                if (modelData > 0 && positionSource.active && positionSource.deviceId !== "") {
                  positionSource.setGnssMinimumElevation(modelData);
                  displayToast(qsTr("Maska elewacji %1° wysłana (obowiązuje do restartu odbiornika)").arg(modelData));
                } else if (modelData === 0) {
                  displayToast(qsTr("Maska zdjęta po naszej stronie; w odbiorniku zostaje do restartu"));
                }
              }
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8

        Button {
          text: qsTr("Połącz NTRIP ponownie")
          font.pointSize: t.tinyFont.pointSize
          enabled: positionSource.enableNtrip
          onClicked: {
            positionSource.enableNtrip = false;
            positionSource.enableNtrip = true;
            displayToast(qsTr("Restartuję połączenie NTRIP…"));
          }
        }

        Item {
          Layout.fillWidth: true
        }

        Button {
          text: qsTr("Ustawienia")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            gnssDiagPopup.close();
            dataDrawer.close();
            qfieldSettings.currentPanel = "positioning";
            qfieldSettings.visible = true;
          }
        }

        Button {
          // WorkField 22.08: Niebo przed Zamknij — wazniejsze, wiec blizej kciuka
          text: qsTr("Niebo")
          font.pointSize: t.tinyFont.pointSize
          highlighted: true
          onClicked: {
            gnssDiagPopup.close();
            nieboPanel.open();
          }
        }

        Button {
          text: qsTr("Zamknij")
          font.pointSize: t.tinyFont.pointSize
          onClicked: gnssDiagPopup.close()
        }
      }
    }
  }

  QfNiebo {
    id: nieboPanel
  }

  QfSpisPanel {
    id: panelSpisu
  }

  QfKopiaPanel {
    id: panelKopii
  }
}
