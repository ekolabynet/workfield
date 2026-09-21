import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as SystemoweOkna
import org.qfield
import org.qfield.core
import Theme

/**
 * \ingroup qml
 *
 * WorkField 21.09.2026 — IMPORT Z RYSUNKU DXF, W JEDNYM OKNIE.
 *
 * Do 21.09 karta modułu CAD miała cztery osobne pozycje: warstwy rysunku,
 * bloki, opisy i warstwice. Każda otwierała własne okno, każde zamykało
 * się po swojemu, a człowiek, który dostaje rysunek i chce z niego zrobić
 * projekt terenowy, przechodził tę samą drogę cztery razy. To jest JEDNA
 * czynność — „weź z rysunku to, co mi potrzebne" — więc jest jedno okno
 * i jeden przycisk.
 *
 * KOLEJNOŚĆ NIE JEST DOWOLNA i dlatego „Wykonaj" robi wszystko sam:
 *
 *   1. filtr warstw i kropki      — co w ogóle widać
 *   2. bloki jako obiekty         — muszą być, zanim będzie do czego
 *   3. opisy do obiektów          — dociąga wartości do tego, co powstało
 *   4. warstwice z rzędnych       — liczy z kolumny, którą dopiero co
 *                                   wypełnił krok 3
 *
 * Ręcznie łatwo tę kolejność odwrócić i dostać pusty wynik bez żadnego
 * błędu — „warstwice z rzędnych" przed „dociągnij opisy" nie mają z czego
 * liczyć. Tu kolejność jest w kodzie, a nie w pamięci użytkownika.
 *
 * ZAKŁADKI, NIE JEDNA DŁUGA KOLUMNA: dwie listy (warstwy rysunku bywa ich
 * sto, bloków trzydzieści) nie zmieszczą się razem na telefonie.
 */
Popup {
  id: oknoImportuCAD

  property var t: Theme

  //! [{nazwa, klucz, obiekty, widoczna}] — warstwy rysunku.
  property var warstwy: []

  //! [{nazwa, obiekty, wczytane, warstwy, atrybuty}] — bloki rysunku.
  property var bloki: []

  //! Zaznaczone bloki, PO NAZWIE i osobno od modelu listy: podmiana
  //! modelu przy każdym tapnięciu odsyłała ListView na górę.
  property var wybrane: ({})

  //! [{pole, obiekty}] — kolumny z wysokością w warstwie symboli.
  property var pola: []

  //! Rysunki znalezione w projekcie: [{nazwa, plik, warstwy, wybrany}].
  property var rysunki: []

  property string blad: ""
  property string stan: ""
  property bool zajety: false

  objectName: "oknoImportuCAD"

  readonly property int wybranych: Object.keys(wybrane).length
  readonly property int ukrytych: {
    var n = 0;
    for (var i = 0; i < warstwy.length; i++)
      if (!warstwy[i].widoczna)
        n++;
    return n;
  }

  function otworz(szuflada) {
    if (szuflada && szuflada.modal && szuflada.opened) {
      const potem = function () {
        szuflada.closed.disconnect(potem);
        oknoImportuCAD.open();
      };
      szuflada.closed.connect(potem);
      szuflada.close();
    } else {
      open();
    }
  }

  function odswiez() {
    blad = "";
    stan = "";
    if (typeof CAD === "undefined" || typeof qgisProject === "undefined") {
      warstwy = [];
      bloki = [];
      pola = [];
      rysunki = [];
      return;
    }
    rysunki = CAD.rysunki(qgisProject) || [];
    warstwy = CAD.warstwyRysunku(qgisProject) || [];
    const w = CAD.bloki(qgisProject) || {};
    // „Nie udało się otworzyć rysunku" i „rysunek nie ma bloków" to DWIE
    // różne rzeczy — pierwsza wersja mówiła jedno i drugie tak samo.
    blad = w.blad !== undefined ? w.blad : "";
    bloki = w.bloki !== undefined ? w.bloki : [];
    wybrane = ({});
    pola = CAD.polaZWysokoscia(qgisProject) || [];
  }

  function wybierzRysunek(plik) {
    const w = CAD.wybierzRysunek(qgisProject, plik);
    if (w.blad) {
      displayToast(w.blad, "warning");
      return;
    }
    odswiez();
  }

  function dodajRysunek(sciezka) {
    if (FileUtils.fileSuffix(sciezka).toLowerCase() !== "dxf") {
      stan = qsTr("To nie jest rysunek DXF: %1").arg(FileUtils.fileName(sciezka));
      return;
    }
    zajety = true;
    // Ta sama droga, którą idzie kreator „Projekt z DXF" — rysunek
    // najpierw KOPIUJE się do projektu, bo zostawiony w Pobranych nie
    // pojedzie ani w wydaniu, ani w kopii na nośnik.
    const cel = qgisProject.homePath + "/" + FileUtils.fileName(sciezka);
    if (sciezka !== cel && !FileUtils.kopiujPlik(sciezka, cel, false)) {
      zajety = false;
      stan = qsTr("Nie udało się skopiować rysunku do projektu.");
      return;
    }
    const ile = mainWindow.dodajRysunekCAD(cel);
    zajety = false;
    if (ile === 0) {
      stan = qsTr("Nie udało się wczytać rysunku.");
      return;
    }
    if (typeof NarzedziaProjektu !== "undefined")
      NarzedziaProjektu.zapiszProjekt(qgisProject);
    wybierzRysunek(cel);
    stan = qsTr("Dodano rysunek „%1” (%2 warstw).").arg(FileUtils.fileName(cel)).arg(ile);
  }

  function przelacz(nazwa, wybrany) {
    const kopia = Object.assign({}, wybrane);
    if (wybrany)
      kopia[nazwa] = true;
    else
      delete kopia[nazwa];
    wybrane = kopia;
  }

  function zaznaczWszystkie(tak) {
    const kopia = {};
    if (tak) {
      for (let i = 0; i < bloki.length; i++)
        kopia[bloki[i].nazwa] = true;
    }
    wybrane = kopia;
  }

  function przelaczWarstwe(index, widoczna) {
    // Podmiana CAŁEJ tablicy, bo `property var` nie zgłasza zmiany
    // pojedynczego pola i widok został by na starym zaznaczeniu.
    const kopia = warstwy.slice();
    kopia[index] = {
      "nazwa": warstwy[index].nazwa,
      "klucz": warstwy[index].klucz,
      "obiekty": warstwy[index].obiekty,
      "widoczna": widoczna
    };
    warstwy = kopia;
  }

  function wszystkieWarstwy(widoczne) {
    const kopia = [];
    for (let i = 0; i < warstwy.length; i++)
      kopia.push({
                   "nazwa": warstwy[i].nazwa,
                   "klucz": warstwy[i].klucz,
                   "obiekty": warstwy[i].obiekty,
                   "widoczna": widoczne
                 });
    warstwy = kopia;
  }

  function promien() {
    const v = parseFloat(String(polePromienia.text).replace(",", "."));
    return isNaN(v) || v <= 0 ? 3.0 : v;
  }

  function odstep() {
    const v = parseFloat(String(poleOdstepu.text).replace(",", "."));
    return isNaN(v) || v <= 0 ? 0.5 : v;
  }

  //! Wszystko naraz, W KOLEJNOŚCI — patrz nagłówek.
  function wykonaj() {
    zajety = true;
    stan = qsTr("Pracuję…");
    // Przez Qt.callLater, żeby napis zdążył się narysować: rachunek idzie
    // na wątku interfejsu i przy dużym rysunku trwa kilka sekund.
    Qt.callLater(krokiImportu);
  }

  function krokiImportu() {
    const zrobione = [];

    // 1. co widać
    const ukryte = [];
    for (let i = 0; i < warstwy.length; i++) {
      if (!warstwy[i].widoczna)
        ukryte.push(warstwy[i].klucz);
    }
    const w1 = CAD.pokazWarstwy(qgisProject, ukryte);
    console.log("WFG import: pokazWarstwy " + JSON.stringify(w1));
    if (w1.blad) {
      zajety = false;
      stan = w1.blad;
      return;
    }
    if (ukryte.length > 0)
      zrobione.push(qsTr("ukryte warstwy: %1").arg(ukryte.length));

    const w2 = CAD.kropkiNapisow(qgisProject, przelacznikKropek.checked);
    console.log("WFG import: kropkiNapisow " + JSON.stringify(w2));

    // 2. bloki jako obiekty
    if (wybranych > 0) {
      const nazwy = [];
      for (let i = 0; i < bloki.length; i++) {
        if (wybrane[bloki[i].nazwa])
          nazwy.push(bloki[i].nazwa);
      }
      const w3 = CAD.zBlokow(qgisProject, nazwy);
      console.log("WFG import: zBlokow " + JSON.stringify(w3));
      if (w3.blad) {
        zajety = false;
        stan = w3.blad;
        return;
      }
      zrobione.push(qsTr("obiekty: %1").arg(w3.dodane));
      if (w3.pominiete > 0)
        zrobione.push(qsTr("już było: %1").arg(w3.pominiete));
    }

    // 3. opisy do obiektów
    if (przelacznikOpisow.checked) {
      const w4 = CAD.dociagnijOpisy(qgisProject, promien(), true);
      console.log("WFG import: dociagnijOpisy " + JSON.stringify(w4));
      if (w4.blad) {
        zajety = false;
        stan = w4.blad;
        return;
      }
      zrobione.push(qsTr("opisy: %1").arg(w4.wpisane !== undefined ? w4.wpisane : w4.dopasowane));
    }

    // 4. warstwice z rzędnych — z kolumny, którą wypełnił krok 3,
    //    więc spis pól odświeżamy TERAZ, a nie przy otwarciu okna.
    if (przelacznikWarstwic.checked) {
      pola = CAD.polaZWysokoscia(qgisProject) || [];
      if (pola.length === 0) {
        zajety = false;
        stan = qsTr("Warstwice: nie ma kolumny z wysokością. Najpierw dociągnij opisy.");
        return;
      }
      const indeks = Math.min(wyborPola.currentIndex < 0 ? 0 : wyborPola.currentIndex, pola.length - 1);
      const w5 = CAD.warstwiceZRzednych(qgisProject, pola[indeks].pole, odstep(),
                                        przelacznikMetody.checked ? "wiernie" : "gladko");
      console.log("WFG import: warstwiceZRzednych " + JSON.stringify(w5));
      if (w5.blad) {
        zajety = false;
        stan = w5.blad;
        return;
      }
      zrobione.push(qsTr("warstwice: %1").arg(w5.linie));
    }

    zajety = false;
    if (typeof NarzedziaProjektu !== "undefined")
      NarzedziaProjektu.zapiszProjekt(qgisProject);
    oknoImportuCAD.close();
    displayToast(zrobione.length > 0
                 ? qsTr("Z rysunku: %1").arg(zrobione.join(", "))
                 : qsTr("Nic nie było zaznaczone — nic nie zmieniono"));
  }

  onOpened: odswiez()

  parent: mainWindow.contentItem
  width: Math.min(520, mainWindow.width - 24)
  height: Math.min(700, mainWindow.height - 60)
  x: (mainWindow.width - width) / 2
  y: Math.max(12, (mainWindow.height - height) / 4)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape

  background: Rectangle {
    color: oknoImportuCAD.t.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: oknoImportuCAD.t.controlBorderColor
  }

  SystemoweOkna.FileDialog {
    id: wybieraczRysunku

    title: qsTr("Wskaż rysunek DXF")
    // Start w Pobranych — tam ląduje rysunek przysłany albo wgrany kablem.
    // Bez filtra rozszerzeń: systemowe okno Androida filtruje po typie MIME,
    // a DXF nie ma zarejestrowanego typu, więc „*.dxf" chowało wszystko.
    currentFolder: "file:///storage/emulated/0/Download"
    nameFilters: [qsTr("Wszystkie pliki (*)")]
    onAccepted: oknoImportuCAD.dodajRysunek(String(selectedFile).replace(/^file:\/\//, ""))
  }

  contentItem: ColumnLayout {
    spacing: 6

    Text {
      Layout.fillWidth: true
      text: qsTr("Import z rysunku DXF")
      font: oknoImportuCAD.t.strongFont
      color: oknoImportuCAD.t.mainTextColor
    }

    TabBar {
      id: zakladki

      Layout.fillWidth: true

      TabButton {
        text: qsTr("Rysunek")
        font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
      }

      TabButton {
        text: qsTr("Co widać")
        font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
      }

      TabButton {
        text: qsTr("Obiekty")
        font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
      }

      TabButton {
        text: qsTr("Wartości")
        font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
      }
    }

    StackLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: zakladki.currentIndex

      // ── 1. RYSUNEK ─────────────────────────────────────────────
      ColumnLayout {
        spacing: 6

        Text {
          Layout.fillWidth: true
          text: qsTr("Wszystkie czynności biorą się z JEDNEGO rysunku. Gdy w projekcie jest ich kilka, wybierz ten, z którego mają iść bloki i opisy.")
          font: oknoImportuCAD.t.tinyFont
          color: oknoImportuCAD.t.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        ListView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: oknoImportuCAD.rysunki
          ScrollBar.vertical: ScrollBar {}

          delegate: RadioButton {
            required property int index
            required property var modelData

            width: ListView.view.width
            text: qsTr("%1  ·  %2 warstw").arg(modelData.nazwa).arg(modelData.warstwy)
            font.pointSize: oknoImportuCAD.t.tipFont.pointSize
            checked: modelData.wybrany
            onToggled: if (checked)
              oknoImportuCAD.wybierzRysunek(modelData.plik)
          }
        }

        QfPozycjaMenu {
          Layout.fillWidth: true
          t: oknoImportuCAD.t
          text: qsTr("Dodaj kolejny rysunek DXF…")
          ikona: "wfg_import"
          onClicked: wybieraczRysunku.open()
        }
      }

      // ── 2. CO WIDAĆ ────────────────────────────────────────────
      ColumnLayout {
        spacing: 6

        CheckBox {
          id: przelacznikKropek

          Layout.fillWidth: true
          // Napis w DXF-ie jest encją PUNKTOWĄ, więc QGIS rysuje mu znacznik
          // w miejscu zakorzenienia tekstu — obok obiektu, którego napis
          // dotyczy. Przy kilku tysiącach napisów mapa tonie w kropkach.
          text: qsTr("Kropki pod napisami rysunku")
          font.pointSize: oknoImportuCAD.t.tipFont.pointSize
          checked: typeof iface !== "undefined"
                   ? iface.readProjectNumEntry("wfg_cad", "/kropkiNapisow", 1) !== 0
                   : true
        }

        RowLayout {
          Layout.fillWidth: true
          visible: oknoImportuCAD.warstwy.length > 0
          spacing: 6

          Button {
            text: oknoImportuCAD.ukrytych > 0 ? qsTr("Pokaż wszystkie") : qsTr("Ukryj wszystkie")
            font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
            onClicked: oknoImportuCAD.wszystkieWarstwy(oknoImportuCAD.ukrytych > 0)
          }

          Text {
            Layout.fillWidth: true
            text: qsTr("widać %1 z %2").arg(oknoImportuCAD.warstwy.length - oknoImportuCAD.ukrytych).arg(oknoImportuCAD.warstwy.length)
            font: oknoImportuCAD.t.tinyFont
            color: oknoImportuCAD.t.secondaryTextColor
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }
        }

        ListView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: oknoImportuCAD.warstwy
          ScrollBar.vertical: ScrollBar {}

          delegate: CheckBox {
            required property int index
            required property var modelData

            width: ListView.view.width
            text: modelData.obiekty > 0
                  ? qsTr("%1  ·  %2").arg(modelData.nazwa).arg(modelData.obiekty)
                  : modelData.nazwa
            font.pointSize: oknoImportuCAD.t.tipFont.pointSize
            checked: modelData.widoczna
            onToggled: oknoImportuCAD.przelaczWarstwe(index, checked)
          }
        }
      }

      // ── 3. OBIEKTY Z BLOKÓW ────────────────────────────────────
      ColumnLayout {
        spacing: 6

        Text {
          Layout.fillWidth: true
          text: oknoImportuCAD.blad !== ""
                ? oknoImportuCAD.blad
                : oknoImportuCAD.bloki.length === 0
                  ? qsTr("Ten rysunek nie ma wstawionych bloków.")
                  : qsTr("Symbole wstawione w rysunku wejdą jako obiekty do warstwy „Symbole z rysunku”. Powtórne wczytanie niczego nie zdubluje.")
          font: oknoImportuCAD.t.tinyFont
          color: oknoImportuCAD.blad !== "" ? oknoImportuCAD.t.warningColor : oknoImportuCAD.t.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        RowLayout {
          Layout.fillWidth: true
          visible: oknoImportuCAD.bloki.length > 0
          spacing: 6

          Button {
            text: oknoImportuCAD.wybranych < oknoImportuCAD.bloki.length
                  ? qsTr("Zaznacz wszystkie")
                  : qsTr("Odznacz wszystkie")
            font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
            onClicked: oknoImportuCAD.zaznaczWszystkie(oknoImportuCAD.wybranych < oknoImportuCAD.bloki.length)
          }

          Text {
            Layout.fillWidth: true
            text: qsTr("zaznaczono %1 z %2").arg(oknoImportuCAD.wybranych).arg(oknoImportuCAD.bloki.length)
            font: oknoImportuCAD.t.tinyFont
            color: oknoImportuCAD.t.secondaryTextColor
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }
        }

        ListView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: oknoImportuCAD.bloki
          ScrollBar.vertical: ScrollBar {}

          delegate: Item {
            required property int index
            required property var modelData

            width: ListView.view.width
            implicitHeight: kolumnaWpisu.implicitHeight + 10

            CheckBox {
              id: znacznik

              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              checked: !!oknoImportuCAD.wybrane[modelData.nazwa]
              onToggled: oknoImportuCAD.przelacz(modelData.nazwa, checked)
            }

            ColumnLayout {
              id: kolumnaWpisu

              anchors.left: znacznik.right
              anchors.leftMargin: 4
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                Layout.fillWidth: true
                text: modelData.wczytane > 0
                      ? qsTr("%1  ·  %2  (wczytane: %3)").arg(modelData.nazwa).arg(modelData.obiekty).arg(modelData.wczytane)
                      : qsTr("%1  ·  %2").arg(modelData.nazwa).arg(modelData.obiekty)
                font: oknoImportuCAD.t.tipFont
                color: oknoImportuCAD.t.mainTextColor
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                visible: modelData.atrybuty !== undefined && modelData.atrybuty !== ""
                // Blok potrafi nieść własne wartości (numer studzienki,
                // rzędna). Wejdą jako OSOBNE KOLUMNY warstwy.
                text: qsTr("z wartościami: %1").arg(modelData.atrybuty || "")
                font: oknoImportuCAD.t.tinyFont
                color: oknoImportuCAD.t.mainColor
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                visible: modelData.warstwy !== ""
                // Nazwa bloku to kod (PW01, OP021); co to JEST, mówi
                // warstwa rysunku, na której symbol stoi.
                text: modelData.warstwy
                font: oknoImportuCAD.t.tinyFont
                color: oknoImportuCAD.t.secondaryTextColor
                elide: Text.ElideRight
              }
            }

            // Cały wiersz przełącza — na telefonie trafienie w sam
            // kwadracik jest zadaniem dla cierpliwych.
            MouseArea {
              anchors.fill: kolumnaWpisu
              onClicked: oknoImportuCAD.przelacz(modelData.nazwa, !oknoImportuCAD.wybrane[modelData.nazwa])
            }
          }
        }
      }

      // ── 4. WARTOŚCI: OPISY I WARSTWICE ─────────────────────────
      ColumnLayout {
        spacing: 6

        CheckBox {
          id: przelacznikOpisow

          Layout.fillWidth: true
          text: qsTr("Dociągnij opisy i rzędne do obiektów")
          font.pointSize: oknoImportuCAD.t.tipFont.pointSize
          checked: true
        }

        Text {
          Layout.fillWidth: true
          text: qsTr("Rzędne i opisy stoją w rysunku jako osobne teksty, obok symbolu. Dociąganie wpisuje je do obiektu jako kolumny.")
          font: oknoImportuCAD.t.tinyFont
          color: oknoImportuCAD.t.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        RowLayout {
          Layout.fillWidth: true
          enabled: przelacznikOpisow.checked

          Text {
            text: qsTr("Szukaj w promieniu [m]")
            font: oknoImportuCAD.t.tipFont
            color: oknoImportuCAD.t.mainTextColor
          }

          TextField {
            id: polePromienia

            Layout.preferredWidth: 80
            text: "3"
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            font.pointSize: oknoImportuCAD.t.tipFont.pointSize
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: oknoImportuCAD.t.controlBorderColor
        }

        CheckBox {
          id: przelacznikWarstwic

          Layout.fillWidth: true
          text: qsTr("Dodaj warstwice z rzędnych")
          font.pointSize: oknoImportuCAD.t.tipFont.pointSize
          checked: false
        }

        RowLayout {
          Layout.fillWidth: true
          enabled: przelacznikWarstwic.checked

          Text {
            text: qsTr("Kolumna")
            font: oknoImportuCAD.t.tipFont
            color: oknoImportuCAD.t.mainTextColor
          }

          ComboBox {
            id: wyborPola

            Layout.fillWidth: true
            model: oknoImportuCAD.pola
            textRole: "pole"
            font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
          }
        }

        RowLayout {
          Layout.fillWidth: true
          enabled: przelacznikWarstwic.checked

          Text {
            text: qsTr("Cięcie [m]")
            font: oknoImportuCAD.t.tipFont
            color: oknoImportuCAD.t.mainTextColor
          }

          TextField {
            id: poleOdstepu

            Layout.preferredWidth: 80
            text: "0,5"
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            font.pointSize: oknoImportuCAD.t.tipFont.pointSize
          }

          Item {
            Layout.fillWidth: true
          }
        }

        CheckBox {
          id: przelacznikMetody

          Layout.fillWidth: true
          enabled: przelacznikWarstwic.checked
          // Zmierzone 21.09: surowa triangulacja daje warstwice kanciaste
          // i z promieniami rozchodzącymi się od punktów. Gładko to
          // `invdistnn` i to jest właściwy domyślny wybór.
          text: qsTr("Wiernie przez punkty (zamiast gładko)")
          font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
          checked: false
        }

        Text {
          Layout.fillWidth: true
          visible: oknoImportuCAD.pola.length === 0
          text: qsTr("Nie ma jeszcze kolumny z wysokością — powstanie przy dociąganiu opisów. Spis odświeża się po wykonaniu.")
          font: oknoImportuCAD.t.tinyFont
          color: oknoImportuCAD.t.secondaryTextColor
          wrapMode: Text.WordWrap
        }

        Item {
          Layout.fillHeight: true
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: oknoImportuCAD.stan !== ""
      text: oknoImportuCAD.stan
      font: oknoImportuCAD.t.tipFont
      color: oknoImportuCAD.t.mainTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true

      BusyIndicator {
        implicitWidth: 20
        implicitHeight: 20
        running: oknoImportuCAD.zajety
        visible: running
      }

      Item {
        Layout.fillWidth: true
      }

      Button {
        text: qsTr("Zamknij")
        font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
        onClicked: oknoImportuCAD.close()
      }

      Button {
        text: qsTr("Wykonaj")
        font.pointSize: oknoImportuCAD.t.tinyFont.pointSize
        highlighted: true
        enabled: !oknoImportuCAD.zajety
        onClicked: oknoImportuCAD.wykonaj()
      }
    }
  }
}
