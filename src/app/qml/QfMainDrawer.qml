import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Effects
import Qt.labs.folderlistmodel
import QtQuick.Dialogs
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import org.qgis
import Theme

/**
 * \ingroup qml
 *
 * WorkField main (left) drawer. Clean reimplementation of DashBoard with
 * bottom tabs: Legenda / Narzędzia / Ustawienia / Pomoc.
 * Keeps the public contract of DashBoard (signals, aliases) so the rest of
 * the application can keep addressing it as `dashBoard`.
 */
Drawer {
  id: dashBoard

  property var t: Theme

  /**
   * WorkField 8.10.2026 [WF-EKSPORT-PROJEKTU] — eksport bieżącego projektu.
   *   "paczka": ZIP + systemowe okno udostępniania (telefon),
   *   "dysk":   katalog w wybrane miejsce.
   * Na komputerze nie ma systemowego „udostępnij”: paczka zapisuje plik .zip
   * we wskazanym folderze [WF-EKSPORT-PACZKA-KOMPUTER], „na dysk” kopiuje
   * katalog przez zwykłe okno folderu.
   *
   * [WF-EKSPORT-DANYCH] Przed eksportem pytanie: „Cały projekt” czy „Tylko
   * dane” (bazy z obiektami, zdjęcia, projekt, ODGIK/DOMIARY/style/klawisze —
   * bez ortofotomap, kopii .przed_*, katalogów IN i kopie, miniatur,
   * wf_wskazniki). „Tylko dane” składa C++ (NarzedziaProjektu.
   * eksportDanychProjektu): bazy kopiowane przez API SQLite, więc z ostatnimi
   * zapisami, i sprawdzane quick_check. Na telefonie składamy je w
   * Documents/WorkField/do_wyslania/<projekt>_dane_<czas> i stamtąd wysyłamy.
   */
  function eksportujProjekt(rodzaj) {
    const katalog = qgisProject ? qgisProject.homePath : "";
    if (katalog === "") {
      displayToast(qsTr("Najpierw otwórz projekt."), "warning");
      return;
    }
    // zapis przed pakowaniem: inaczej poleciałby stan sprzed ostatnich zmian
    let zapisano = false;
    try {
      zapisano = ProjectUtils.saveProject(qgisProject);
    } catch (e) {
      zapisano = false;
    }
    if (!zapisano)
      displayToast(qsTr("Nie udało się zapisać projektu — eksportuję stan z dysku."), "warning");

    let rozmiary = null;
    try {
      rozmiary = NarzedziaProjektu.eksportDanychProjektu(katalog, "", true);
    } catch (e) {
      rozmiary = null;
    }
    pytanieEksportu.otworz(rodzaj, katalog, rozmiary);
  }

  function rozmiarCzytelny(bajty) {
    if (bajty === undefined || bajty === null)
      return "";
    if (bajty >= 1073741824)
      return (bajty / 1073741824).toFixed(1).replace(".", ",") + " GB";
    if (bajty >= 1048576)
      return Math.round(bajty / 1048576) + " MB";
    return Math.max(1, Math.round(bajty / 1024)) + " kB";
  }

  //! Czy system ma własne okno dla tego rodzaju eksportu (telefon), czy robimy to sami (komputer).
  //! Rozstrzyga system, nie same zdolności: wersja na komputer też zgłasza
  //! CustomSend, a ścieżka telefonu (Documents/WorkField) tam nie istnieje
  //! — 8.10.2026 u Piotra „Nie da się utworzyć katalogu /storage/emulated/0/…”.
  function systemoweOkno(rodzaj) {
    if (Qt.platform.os !== "android" && Qt.platform.os !== "ios")
      return false;
    return rodzaj === "paczka"
        ? (platformUtilities.capabilities & PlatformUtilities.CustomSend) !== 0
        : (platformUtilities.capabilities & PlatformUtilities.CustomExport) !== 0;
  }

  function eksportujCaly(rodzaj, katalog) {
    if (rodzaj === "paczka") {
      if (systemoweOkno("paczka")) {
        platformUtilities.sendCompressedFolderTo(katalog);
      } else {
        // [WF-EKSPORT-PACZKA-KOMPUTER] komputer: plik .zip we wskazanym folderze
        oknoFolderuEksportu.tryb = "paczka";
        oknoFolderuEksportu.open();
      }
      return;
    }
    if (platformUtilities.capabilities & PlatformUtilities.CustomExport) {
      platformUtilities.exportFolderTo(katalog);
      return;
    }
    oknoFolderuEksportu.tryb = "caly";
    oknoFolderuEksportu.open();
  }

  //! Składa „Tylko dane” w katalogu cel; zwraca true, gdy wszystko się udało.
  function zlozDane(katalog, cel) {
    let w = null;
    try {
      w = NarzedziaProjektu.eksportDanychProjektu(katalog, cel, false);
    } catch (e) {
      w = { "ok": false, "blad": String(e) };
    }
    if (!w || !w.ok) {
      displayToast(qsTr("Nie udało się przygotować danych: %1").arg(w && w.blad ? w.blad : "?"), "error");
      return false;
    }
    return true;
  }

  function nazwaEksportuDanych(katalog) {
    return FileUtils.fileName(katalog) + "_dane_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HHmmss");
  }

  function eksportujDane(rodzaj, katalog) {
    if (!systemoweOkno(rodzaj)) {
      oknoFolderuEksportu.tryb = rodzaj === "paczka" ? "paczkaDane" : "dane";
      oknoFolderuEksportu.open();
      return;
    }
    // telefon: najpierw do do_wyslania (ta sama brama co „Wymiana lokalna”)
    const cel = "/storage/emulated/0/Documents/WorkField/do_wyslania/" + nazwaEksportuDanych(katalog);
    if (!zlozDane(katalog, cel))
      return;
    if (rodzaj === "paczka")
      platformUtilities.sendCompressedFolderTo(cel);
    else
      platformUtilities.exportFolderTo(cel);
  }

  FolderDialog {
    id: oknoFolderuEksportu
    property string tryb: "caly"
    title: tryb === "paczka" || tryb === "paczkaDane" ? qsTr("Gdzie zapisać paczkę ZIP?")
         : tryb === "dane" ? qsTr("Dokąd wyeksportować dane projektu?") : qsTr("Dokąd wyeksportować projekt?")
    onAccepted: {
      const katalog = qgisProject ? qgisProject.homePath : "";
      if (katalog === "")
        return;
      const folder = String(selectedFolder).replace(/^file:\/\//, "");
      if (tryb === "paczka" || tryb === "paczkaDane") {
        const tylkoDane = tryb === "paczkaDane";
        const zip = folder + "/" + (tylkoDane ? dashBoard.nazwaEksportuDanych(katalog)
                                              : FileUtils.fileName(katalog) + "_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HHmmss")) + ".zip";
        pytanieEksportu.pracujPotem(function () {
          let w = null;
          try {
            w = NarzedziaProjektu.spakujProjekt(katalog, zip, tylkoDane);
          } catch (e) {
            w = { "ok": false, "blad": String(e) };
          }
          if (w && w.ok)
            displayToast(qsTr("Paczka zapisana: %1 (%2)").arg(zip).arg(dashBoard.rozmiarCzytelny(w.rozmiarZip)));
          else
            displayToast(qsTr("Nie udało się spakować projektu: %1").arg(w && w.blad ? w.blad : "?"), "error");
        }, qsTr("Pakuję projekt do ZIP… Przy dużej ortofotomapie to może potrwać kilka minut."));
        return;
      }
      if (tryb === "dane") {
        const cel = folder + "/" + dashBoard.nazwaEksportuDanych(katalog);
        pytanieEksportu.pracujPotem(function () {
          if (dashBoard.zlozDane(katalog, cel))
            displayToast(qsTr("Dane wyeksportowane: %1").arg(cel));
        });
        return;
      }
      const cel = folder + "/" + FileUtils.fileName(katalog);
      if (FileUtils.copyRecursively(katalog, cel, null, false))
        displayToast(qsTr("Projekt wyeksportowany: %1").arg(cel));
      else
        displayToast(qsTr("Nie udało się skopiować projektu do %1").arg(cel), "error");
    }
  }

  //! Pytanie „Cały projekt / Tylko dane” (Piotr 8.10.2026: przy obu eksportach).
  Popup {
    id: pytanieEksportu

    property string rodzaj: "dysk"
    property string katalog: ""
    property var rozmiary: null
    property bool pracuje: false
    property var zadanie: null
    property string opisPracy: ""

    function otworz(nowyRodzaj, nowyKatalog, noweRozmiary) {
      rodzaj = nowyRodzaj;
      katalog = nowyKatalog;
      rozmiary = noweRozmiary;
      pracuje = false;
      open();
    }

    //! Kopiowanie zdjęć chwilę trwa — najpierw pokazujemy „Przygotowuję…”,
    //! dopiero w następnej klatce ruszamy z robotą (inaczej ekran zamarza bez słowa).
    function pracujPotem(funkcja, opis) {
      zadanie = funkcja;
      opisPracy = opis || qsTr("Przygotowuję dane… Bazy i zdjęcia są kopiowane, to może chwilę potrwać.");
      pracuje = true;
      if (!opened)
        open();
      opoznienie.restart();
    }

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 420)
    modal: true
    closePolicy: pracuje ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 16

    background: Rectangle {
      color: t.mainBackgroundColor
      radius: 10
      border.width: 1
      border.color: t.controlBorderColor
    }

    Timer {
      id: opoznienie
      interval: 150
      onTriggered: {
        const f = pytanieEksportu.zadanie;
        pytanieEksportu.zadanie = null;
        try {
          if (f)
            f();
        } finally {
          pytanieEksportu.pracuje = false;
          pytanieEksportu.close();
        }
      }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 10

      Text {
        Layout.fillWidth: true
        text: pytanieEksportu.rodzaj === "paczka" ? qsTr("Eksportuj paczkę") : qsTr("Eksportuj na dysk")
        font: t.strongFont
        color: t.mainTextColor
      }

      RowLayout {
        Layout.fillWidth: true
        visible: pytanieEksportu.pracuje
        spacing: 10
        BusyIndicator {
          running: pytanieEksportu.pracuje
          Layout.preferredWidth: 40
          Layout.preferredHeight: 40
        }
        Text {
          Layout.fillWidth: true
          text: pytanieEksportu.opisPracy
          font: t.tipFont
          color: t.mainTextColor
          wrapMode: Text.WordWrap
        }
      }

      Text {
        Layout.fillWidth: true
        visible: !pytanieEksportu.pracuje
        text: qsTr("Co wyeksportować?")
        font: t.defaultFont
        color: t.mainTextColor
      }

      Button {
        id: przyciskCaly
        Layout.fillWidth: true
        padding: 12
        background: Rectangle {
          radius: 8
          color: parent.down ? Qt.rgba(t.mainColor.r, t.mainColor.g, t.mainColor.b, 0.30) : Qt.rgba(t.mainColor.r, t.mainColor.g, t.mainColor.b, 0.12)
          border.width: 1
          border.color: t.mainColor
          opacity: parent.enabled ? 1 : 0.4
        }
        visible: !pytanieEksportu.pracuje
        contentItem: ColumnLayout {
          spacing: 2
          Text {
            Layout.fillWidth: true
            text: qsTr("Cały projekt")
            font: t.strongFont
            color: t.mainTextColor
          }
          Text {
            Layout.fillWidth: true
            text: pytanieEksportu.rozmiary
                  ? qsTr("Wszystko z katalogu projektu, razem z ortofotomapą — %1").arg(dashBoard.rozmiarCzytelny(pytanieEksportu.rozmiary.calosc))
                  : qsTr("Wszystko z katalogu projektu, razem z ortofotomapą")
            font: t.tinyFont
            color: t.secondaryTextColor
            wrapMode: Text.WordWrap
          }
        }
        onClicked: {
          const r = pytanieEksportu.rodzaj;
          const k = pytanieEksportu.katalog;
          pytanieEksportu.close();
          dashBoard.eksportujCaly(r, k);
        }
      }

      Button {
        id: przyciskDane
        Layout.fillWidth: true
        padding: 12
        background: Rectangle {
          radius: 8
          color: parent.down ? Qt.rgba(t.mainColor.r, t.mainColor.g, t.mainColor.b, 0.30) : Qt.rgba(t.mainColor.r, t.mainColor.g, t.mainColor.b, 0.12)
          border.width: 1
          border.color: t.mainColor
          opacity: parent.enabled ? 1 : 0.4
        }
        visible: !pytanieEksportu.pracuje
        enabled: pytanieEksportu.rozmiary !== null
        contentItem: ColumnLayout {
          spacing: 2
          Text {
            Layout.fillWidth: true
            text: qsTr("Tylko dane")
            font: t.strongFont
            color: t.mainTextColor
          }
          Text {
            Layout.fillWidth: true
            text: pytanieEksportu.rozmiary
                  ? qsTr("Bazy z obiektami, zdjęcia, projekt, ODGIK, domiary, style — %1. Bez ortofotomap i kopii.").arg(dashBoard.rozmiarCzytelny(pytanieEksportu.rozmiary.bajty))
                  : qsTr("Niedostępne")
            font: t.tinyFont
            color: t.secondaryTextColor
            wrapMode: Text.WordWrap
          }
        }
        onClicked: {
          const r = pytanieEksportu.rodzaj;
          const k = pytanieEksportu.katalog;
          if (dashBoard.systemoweOkno(r)) {
            pytanieEksportu.pracujPotem(function () {
              dashBoard.eksportujDane(r, k);
            });
          } else {
            pytanieEksportu.close();
            dashBoard.eksportujDane(r, k);
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: !pytanieEksportu.pracuje
        Item {
          Layout.fillWidth: true
        }
        Button {
          flat: true
          font.pointSize: t.tinyFont.pointSize
          contentItem: Text {
            text: qsTr("Anuluj")
            font: parent.font
            color: t.mainTextColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
          onClicked: pytanieEksportu.close()
        }
      }
    }
  }

  onOpenedChanged: {
    if (opened) {
      projectSection.refresh();
    }
    // WorkField: dokowany panel pamięta stan między sesjami (komputer)
    if (!modal) {
      settings.setValue('WorkField/lewyPanelOtwarty', opened);
    }
  }

  property var pendingBlankCenter: null
  property bool pendingBlankSetup: false

  /**
   * WorkField 6.10.2026 [WF-NOWY-PROJEKT] — PROJEKT OD RAZU KOMPLETNY.
   *
   * Po wczytaniu pustego projektu: przepis uniwersalny (sześć warstw
   * w dane.gpkg), wszystkie moduły wyposażenia, ładne nazwy w legendzie,
   * metryczka ZADANIE.json. Wyposażenie zakładane PRZY NARODZINACH
   * projektu — w pustym projekcie nie ma czego zdublować (awaria PGRS
   * 2.10 wzięła się z doposażania projektu z danymi).
   *
   * Tabele mają nazwy ASCII (punkty, linie_krzywe…), legenda — polskie.
   * Szablony i doposażanie znają warstwy po tabeli, więc ładna nazwa
   * niczego nie psuje (czwarta reguła znajdzWarstwe).
   */
  property var pendingMetryczka: null

  readonly property var nazwyUniwersalne: ({
      "punkty": "Punkty",
      "linie": "Linie",
      "linie_krzywe": "Linie krzywe",
      "poligony": "Poligony",
      "poligony_krzywe": "Poligony krzywe",
      "zasieg_opracowania": "Zasięg opracowania"
    })

  function przepisUniwersalny() {
    const pola = [
      { "name": "NAZWA", "type": "text" },
      { "name": "OPIS", "type": "text" },
      { "name": "DATA", "type": "datetime" }
    ];
    function warstwa(nazwa, geometria) {
      return {
        "nazwa": nazwa,
        "geometria": geometria,
        "pola": pola,
        "aliasy": { "NAZWA": "Nazwa", "OPIS": "Opis", "DATA": "Data" },
        "widgety": { "OPIS": { "typ": "TextEdit", "opcje": { "IsMultiline": true, "UseHtml": false } } },
        "domyslne": { "DATA": "now()" }
      };
    }
    // kolejność = kolejność dokładania; ostatnia ląduje na wierzchu legendy
    return {
      "id": "uniwersalny",
      "wersja": 1,
      "uklad": "EPSG:2178",
      "dane": "dane.gpkg",
      "zrodlo": "wbudowany",
      "warstwy": [
        warstwa("zasieg_opracowania", "Polygon"),
        warstwa("poligony", "Polygon"),
        warstwa("poligony_krzywe", "CurvePolygon"),
        warstwa("linie", "LineString"),
        warstwa("linie_krzywe", "CompoundCurve"),
        warstwa("punkty", "Point")
      ]
    };
  }

  function urzadzNowyProjekt(sciezka, nazwa) {
    const przepis = przepisUniwersalny();
    if (!mainWindow.przepisy.zastosuj(przepis, sciezka)) {
      displayToast(qsTr("Projekt %1 powstał, ale warstw uniwersalnych nie udało się założyć").arg(nazwa), "error");
      return;
    }

    // Wyposażenie: wszystkie moduły, dwie rundy — moduł, który czeka na
    // inny (pole „wymaga”), dostaje drugą szansę po pierwszym przejściu.
    // WorkField 7.10.2026 [WF-KAFLE-KOLEJNOSC] — kafle w kolejności legendy
    // (od góry). Przepis dokłada od dołu, więc odwracamy.
    const tabele = przepis.warstwy.map(function (x) { return x.nazwa; }).reverse();
    let zostaly = ["przyciaganie", "bez_nakladania", "zalaczniki", "klawisze", "tyczenie"];
    let bledy = {};
    for (let runda = 0; runda < 2 && zostaly.length > 0; runda++) {
      const nastepne = [];
      bledy = {};
      for (let i = 0; i < zostaly.length; i++) {
        const modul = zostaly[i];
        const w = wyposazenieProjektu.zaloz(qgisProject, modul, modul === "klawisze" ? { "warstwy": tabele } : {});
        if (!w.ok) {
          nastepne.push(modul);
          bledy[modul] = w.opis;
        }
      }
      zostaly = nastepne;
    }

    // WorkField 7.10.2026 [WF-TYCZENIE-GRUPA] — `tyczenie` to warstwa
    // techniczna modułu: do zwiniętej grupy „Techniczne” na dole drzewa.
    // Dalej się rysuje — chowamy ją z oczu, nie wyłączamy.
    const tyczenie = NarzedziaProjektu.warstwaPoNazwie(qgisProject, "tyczenie");
    if (tyczenie) {
      NarzedziaProjektu.doGrupy(qgisProject, tyczenie, qsTr("Techniczne"), true, true);
      NarzedziaProjektu.grupaNaDol(qgisProject, qsTr("Techniczne"));
    }

    for (const tabela in nazwyUniwersalne) {
      const l = NarzedziaProjektu.warstwaPoNazwie(qgisProject, tabela);
      if (l)
        l.name = nazwyUniwersalne[tabela];
    }

    const katalog = sciezka.substring(0, sciezka.lastIndexOf("/"));
    const m = pendingMetryczka || {};
    pendingMetryczka = null;
    NarzedziaProjektu.zapiszTekst(katalog + "/ZADANIE.json", JSON.stringify({
        "nazwa": nazwa,
        "utworzono": new Date().toISOString(),
        "szablon": "uniwersalny",
        "zrodlo_szablonu": "wbudowany: uniwersalny v1",
        "zleceniodawca": m.zleceniodawca || "",
        "teren": m.teren || "",
        "zlecenie": m.zlecenie || ""
      }, null, 2));

    const zapisano = ProjectUtils.saveProject(qgisProject);
    if (zostaly.length === 0 && zapisano) {
      displayToast(qsTr("Projekt %1 gotowy: 6 warstw, wyposażenie 5/5").arg(nazwa));
    } else {
      const opis = zostaly.map(function (x) { return x + ": " + bledy[x]; }).join("; ");
      displayToast(qsTr("Projekt %1: wyposażenie %2/5%3%4").arg(nazwa).arg(5 - zostaly.length)
                   .arg(opis !== "" ? " — " + opis : "")
                   .arg(zapisano ? "" : qsTr(" — projektu NIE zapisano")), "error");
    }
  }

  function requestDem(demType) {
    demDownloader.request(demType);
  }

  function computeChmAction() {
    demDownloader.computeChm();
  }

  /**
   * Pobranie arkuszy dla nazwanego obszaru - wywolywane z okna danych
   * wysokosciowych (QfDaneWysokosciowe.qml). Pusta nazwa daje "Obszar N".
   */
  function pobierzDemZakres(rodzaj, nazwa, najnowsze) {
    demDownloader.areaName = nazwa !== undefined && nazwa !== "" ? nazwa : "Obszar " + demDownloader.areaCounter;
    demDownloader.requestScoped(rodzaj, najnowsze);
  }

  //! Nazwa ostatniego obszaru - CHM dobiera NMT i NMPT po tej samej nazwie.
  function nazwaObszaru() {
    return demDownloader.areaName;
  }
  objectName: "dashBoard"

  signal showMainMenu(point p)
  signal showBookmarks
  signal showPluginManager
  //! WorkField 22.09.2026 — ekran „Jak zacząć?”. Sygnał, a nie
  //! bezpośrednie wołanie okna: szuflada nie zna id-ków z QgisMobileapp.qml.
  signal pokazJakZaczac
  signal showSettings
  signal showMessageLog
  signal lockScreen
  signal showAbout
  signal showPrintLayouts(point p)
  signal showCloudPopup
  signal showProjectFolder
  signal toggleMeasurementTool
  signal toggle3DView
  signal returnHome

  //! WorkField 23.08.2026 — korzen magazynu wystawiony na zewnatrz.
  //! Panel spisu potrzebuje tej samej sciezki, ktora widzi zakladka Zlecenia;
  //! alias, a nie kopia ustawienia, zeby nie bylo dwoch zrodel prawdy.
  readonly property alias korzenMagazynu: drzewoZlecen.korzen

  //! WorkField: sekcja wskazywana przez menu (komputer); -1 = wg zakładek
  property int sekcjaWymuszona: -1

  //! WorkField 18.08.2026: która sekcja jest NAPRAWDĘ widoczna. Górna belka
  //! podświetla po tym aktywną zakładkę; sekcjaWymuszona nie wystarczy, bo
  //! przy -1 o wyborze decydują zakładki telefonu.
  readonly property int sekcjaAktywna: dashStack.currentIndex

  function otworzSekcje(numer) {
    sekcjaWymuszona = numer;
    open();
  }

  // WorkField: przyciąganie per warstwa. UWAGA na pułapkę silnika:
  // setData dla roli SnappingEnabled IGNORUJE wartość i zawsze
  // przełącza — dlatego najpierw czytamy stan i piszemy tylko wtedy,
  // gdy trzeba go zmienić.
  function ustawMagnesWarstwy(warstwa, wlaczony) {
    const m = dashBoard.layerTree;
    for (let i = 0; i < m.rowCount(); i++) {
      const idx = m.index(i, 0);
      if (m.data(idx, FlatLayerTreeModel.VectorLayerPointer) === warstwa) {
        if ((m.data(idx, FlatLayerTreeModel.SnappingEnabled) === true) !== wlaczony) {
          m.setData(idx, wlaczony, FlatLayerTreeModel.SnappingEnabled);
          projectInfo.saveLayerSnappingConfiguration(warstwa);
        }
        return true;
      }
    }
    console.log("WorkField magnes: warstwa nie znaleziona w modelu (" + (warstwa && warstwa.name ? warstwa.name : "?") + ")");
    return false;
  }

  /**
   * Przełącza rysowanie na warstwie — JEDNO miejsce z tym zachowaniem.
   *
   * Wołane i ze szuflady, i z ołówka na górnej belce. Gdyby belka miała
   * własną kopię, oba przyciski rozjechałyby się przy pierwszej zmianie —
   * i wyglądałyby przy tym identycznie, więc nikt by nie zauważył.
   *
   * Zwraca true, gdy tryb się zmienił.
   */
  function przelaczRysowanie(warstwa, nazwa) {
    if (!warstwa) {
      displayToast(qsTr("Najpierw wybierz warstwę"), "warning");
      return false;
    }
    if (warstwa.readOnly) {
      displayToast(qsTr("Warstwa tylko do odczytu"), "warning");
      return false;
    }

    const juz = dashBoard.activeLayer === warstwa && stateMachine.state === "digitize";
    dashBoard.activeLayer = warstwa;
    stateMachine.state = juz ? "browse" : "digitize";
    displayToast(juz ? qsTr("Przeglądanie")
                     : qsTr("Rysowanie: %1").arg(nazwa || warstwa.name));

    if (!juz) {
      // WorkField: zasada domyślna dociągania — rysowana warstwa przyciąga
      // sama do siebie; tryb "wszystkie warstwy" sprowadzamy do "aktywnej",
      // a w trybie magnesów sami dopisujemy rysowaną warstwę.
      if (qgisProject.snappingConfig.mode === Qgis.SnappingMode.AllLayers) {
        let cfgO = qgisProject.snappingConfig;
        cfgO.mode = Qgis.SnappingMode.ActiveLayer;
        qgisProject.snappingConfig = cfgO;
      } else if (qgisProject.snappingConfig.mode === Qgis.SnappingMode.AdvancedConfiguration) {
        dashBoard.ustawMagnesWarstwy(warstwa, true);
      }
      dashBoard.close();
    }
    return true;
  }

  // tap magnesa w wierszu warstwy: pierwszy raz przełącza projekt
  // w tryb magnesów i chroni rysowaną warstwę, potem zwykły przełącznik
  function przelaczMagnesWarstwy(warstwa, nazwa) {
    let cfg = qgisProject.snappingConfig;
    if (cfg.mode !== Qgis.SnappingMode.AdvancedConfiguration) {
      cfg.mode = Qgis.SnappingMode.AdvancedConfiguration;
      cfg.enabled = true;
      qgisProject.snappingConfig = cfg;
      if (qgisProject.snappingConfig.mode !== Qgis.SnappingMode.AdvancedConfiguration) {
        // zapis trybu z QML-a nie przeszedł — plan B do osobnej decyzji
        displayToast(qsTr("Nie udało się przełączyć trybu przyciągania"), "error");
        return;
      }
      projectInfo.snappingEnabled = true;
      // QGIS przy przejściu w tryb zaawansowany zapala WSZYSTKIE
      // warstwy — sprowadzamy to jawnie do zasady WorkField:
      // rysowana warstwa + tapnięty podkład, reszta zgaszona
      const m0 = dashBoard.layerTree;
      const n0 = m0.rowCount();
      for (let i0 = 0; i0 < n0; i0++) {
        const idx0 = m0.index(i0, 0);
        const wsk0 = m0.data(idx0, FlatLayerTreeModel.VectorLayerPointer);
        if (!wsk0)
          continue;
        const chcemy = wsk0 === warstwa || wsk0 === dashBoard.activeLayer;
        if ((m0.data(idx0, FlatLayerTreeModel.SnappingEnabled) === true) !== chcemy)
          m0.setData(idx0, chcemy, FlatLayerTreeModel.SnappingEnabled);
        projectInfo.saveLayerSnappingConfiguration(wsk0);
      }
      displayToast(qsTr("Dociąganie: rysowana warstwa + %1").arg(nazwa));
      return;
    }
    if (!cfg.enabled) {
      cfg.enabled = true;
      qgisProject.snappingConfig = cfg;
      projectInfo.snappingEnabled = true;
    }
    const m = dashBoard.layerTree;
    for (let i = 0; i < m.rowCount(); i++) {
      const idx = m.index(i, 0);
      if (m.data(idx, FlatLayerTreeModel.VectorLayerPointer) === warstwa) {
        const bylo = m.data(idx, FlatLayerTreeModel.SnappingEnabled) === true;
        m.setData(idx, !bylo, FlatLayerTreeModel.SnappingEnabled);
        projectInfo.saveLayerSnappingConfiguration(warstwa);
        displayToast(!bylo ? qsTr("Dociąganie do: %1").arg(nazwa) : qsTr("Bez dociągania do: %1").arg(nazwa));
        return;
      }
    }
  }

  // WorkField 23.08.2026 — komponent QfPozycjaMenu STAL TU JAKO KOPIA i cieniowal
  // plik QfPozycjaMenu.qml, wyjety 22.08 wlasnie po to, zeby kopii nie bylo.
  // Skutek: zmiana wygladu w pliku nie robila nic po lewej stronie, a prawa
  // szuflada wygladala inaczej mimo "wspolnego" komponentu. Kopia usunieta;
  // od teraz jedna definicja, w src/app/qml/QfPozycjaMenu.qml.

  property bool preventFromOpening: overlayFeatureFormDrawer.visible
  property bool allowInteractive: true
  property bool shouldReturnHome: false
  /// type:bool
  property alias allowActiveLayerChange: legend.allowActiveLayerChange
  /// type:QgsVectorLayer
  property alias activeLayer: legend.activeLayer
  /// type:FlatLayerTreeModel
  property alias layerTree: legend.model
  /// type:QgsQuickMapSettings
  property MapSettings mapSettings

  Component.onCompleted: {
    if (Material.roundedScale) {
      Material.roundedScale = Material.NotRounded;
    }
  }

  width: Qt.platform.os !== "android" && Qt.platform.os !== "ios" ? Math.max(380, Math.round(mainWindow.width * 0.25)) : Math.min(Math.max(330, mainWindow.width * 0.8), mainWindow.width)
  height: parent.height
  edge: Qt.LeftEdge
  // WorkField: na komputerze panel jest DOKOWANY — nie przyciemnia mapy,
  // nie zamyka się od kliknięcia poza nim i zostaje otwarty; mapa zwęża
  // się o jego szerokość (patrz mapCanvas w qgismobileapp.qml)
  modal: Qt.platform.os === "android" || Qt.platform.os === "ios"
  dim: modal
  closePolicy: modal ? Popup.CloseOnEscape | Popup.CloseOnPressOutside : Popup.CloseOnEscape
  dragMargin: modal ? 10 : 0
  interactive: allowInteractive && modal

  onSekcjaWymuszonaChanged: {
    if (!modal && sekcjaWymuszona >= 0) {
      settings.setValue('WorkField/lewyPanelSekcja', sekcjaWymuszona);
    }
  }

  topPadding: 0
  leftPadding: 0
  rightPadding: 0
  bottomPadding: 0

  position: 0
  focus: visible
  clip: true

  QtObject {
    id: demDownloader

    property int active: 0
    property var mosaicBbox: null
    property string activeType: ""
    property string areaName: "Obszar 1"
    property int areaCounter: 1

    property string pendingType: ""

    /**
     * WorkField 23.08.2026 — metryczki arkuszy: nazwa pliku → { data, piksel,
     * uklad, kolor }. Skorowidz GUGiK odpowiada tabelą, z której dotąd braliśmy
     * wyłącznie adres pliku, wyrzucając resztę wiersza. A tam stoi ROCZNIK
     * modelu — bez niego wynik horyzontu z NMPT jest liczbą bez daty ważności
     * (claude/PRZESLONIECIE_nieba.md).
     */
    property var opisyPlikow: ({})

    /**
     * Rozpoznaje pola PO ROLI, nie po nazwie kolumny — bo skorowidze NMT, NMPT
     * i ortofoto mają różne nagłówki, a data zawsze wygląda jak data.
     * (Reguła z docs/NAZEWNICTWO.md, złamana raz 22.08 i to wystarczy.)
     * Gdy odpowiedź nie jest tabelą, zwraca puste pola i nikt nie ucierpi.
     */
    function metryczkaZWiersza(wiersz) {
      const komorki = (wiersz.match(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi) || []).map(function (c) {
        return c.replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " ").trim();
      }).filter(function (c) {
        return c !== "";
      });
      const opis = {
        "data": "",
        "piksel": "",
        "uklad": "",
        "kolor": ""
      };
      for (const k of komorki) {
        if (opis.data === "" && /^\d{4}-\d{2}-\d{2}$/.test(k)) {
          opis.data = k;
        } else if (opis.kolor === "" && /^(RGB|CIR|PAN)$/i.test(k)) {
          opis.kolor = k.toUpperCase();
        } else if (opis.uklad === "" && /^PL-[0-9A-Za-z:.]+$/.test(k)) {
          opis.uklad = k;
        } else if (opis.piksel === "" && /^\d+([.,]\d+)?\s?m?$/.test(k)) {
          const v = parseFloat(k.replace(",", "."));
          // rocznik ("2025") i skala ("1:5000") odpadają same: piksel modelu
          // wysokościowego to ułamki metra do kilku metrów, nigdy tysiące
          if (v > 0 && v <= 50) {
            opis.piksel = k;
          }
        }
      }
      return opis;
    }

    //! Jedno zdanie o zestawie arkuszy — do dymka i do nazwy warstwy
    function streszczenieMetryczek(nazwy) {
      let data = "";
      let piksel = "";
      for (const n of nazwy) {
        const o = opisyPlikow[n];
        if (!o) {
          continue;
        }
        if (o.data !== "" && o.data > data) {
          data = o.data;
        }
        if (o.piksel !== "") {
          const v = parseFloat(o.piksel.replace(",", "."));
          const dotad = piksel === "" ? 1e9 : parseFloat(piksel.replace(",", "."));
          // najgrubszy piksel w zestawie, bo mozaika jest tak dobra jak
          // jej najsłabszy arkusz
          if (v > dotad || piksel === "") {
            piksel = o.piksel;
          }
        }
      }
      const czesci = [];
      if (data !== "") {
        czesci.push(data);
      }
      if (piksel !== "") {
        czesci.push(piksel.indexOf("m") === -1 ? piksel + " m" : piksel);
      }
      return czesci.join(" · ");
    }

    function request(type) {
      // WorkField 21.09.2026 - dawne okno "Zakres pobierania" bylo druga kopia
      // tego samego wyboru; teraz jest jedno okno na NMT, NMPT i CHM.
      pendingType = type;
      if (typeof oknoDaneWysokosciowe === "undefined") {
        displayToast(qsTr("Ta wersja aplikacji nie ma okna danych wysokościowych"), "warning");
        return;
      }
      oknoDaneWysokosciowe.rodzaj = type;
      oknoDaneWysokosciowe.otworz(dashBoard);
    }

    function requestScoped(type, newestOnly) {
      const services = type === "NMT" ? ["https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMT/WMS/SkorowidzeUkladKRON86?", "https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMT/WMS/SkorowidzeUkladEVRF2007?"] : ["https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMPT/WMS/SkorowidzeUkladKRON86?", "https://mapy.geoportal.gov.pl/wss/service/PZGIK/NMPT/WMS/SkorowidzeUkladEVRF2007?"];
      const points = iface.visibleExtentPointsIn2180(dashBoard.mapSettings, 2);
      if (points.length === 0) {
        displayToast(qsTr("Nie udalo sie wyznaczyc zasiegu mapy"), "warning");
        return;
      }
      let bx0 = points[0].x;
      let by0 = points[0].y;
      let bx1 = points[0].x;
      let by1 = points[0].y;
      for (const pt of points) {
        bx0 = Math.min(bx0, pt.x);
        by0 = Math.min(by0, pt.y);
        bx1 = Math.max(bx1, pt.x);
        by1 = Math.max(by1, pt.y);
      }
      const bufferMeters = Math.max(100, (bx1 - bx0) * 0.1);
      mosaicBbox = { "xmin": bx0 - bufferMeters, "ymin": by0 - bufferMeters, "xmax": bx1 + bufferMeters, "ymax": by1 + bufferMeters };
      activeType = type;
      opisyPlikow = {};
      displayToast(qsTr("Szukam arkuszy %1 dla obszaru mapy...").arg(type));
      queryService(services, 0, points, type, newestOnly);
    }

    function queryService(services, serviceIndex, points, type, newestOnly) {
      if (serviceIndex >= services.length) {
        displayToast(qsTr("Nie znaleziono arkuszy %1 dla tego obszaru").arg(type), "warning");
        return;
      }
      const serviceUrl = services[serviceIndex];
      const capsXhr = new XMLHttpRequest();
      capsXhr.onreadystatechange = function () {
        if (capsXhr.readyState !== XMLHttpRequest.DONE) {
          return;
        }
        const layerMatches = capsXhr.responseText.match(/<Name>([^<]+)<\/Name>/g) || [];
        const layers = layerMatches.map(m => m.replace(/<\/?Name>/g, "")).filter(n => n.indexOf("Skorowidze") === 0);
        console.log("DEM caps:", serviceUrl, "-> warstwy:", layers.join("|"));
        if (layers.length === 0) {
          queryService(services, serviceIndex + 1, points, type, newestOnly);
          return;
        }
        const layersSorted = layers.slice().sort(function (a, b) {
          const ya = parseInt((a.match(/(\d{4})/) || [0, "0"])[1]);
          const yb = parseInt((b.match(/(\d{4})/) || [0, "0"])[1]);
          return yb - ya;
        });
        collectLayered(serviceUrl, layersSorted, 0, points, 0, {}, type, services, serviceIndex, newestOnly);
      };
      capsXhr.open("GET", serviceUrl + "SERVICE=WMS&request=GetCapabilities");
      capsXhr.send();
    }

    function godloFromUrl(u) {
      const m = u.match(/[A-Z]-\d{2}-[0-9A-Za-z-]+/);
      return m ? m[0] : u;
    }

    function collectLayered(serviceUrl, layersSorted, layerIndex, points, pointIndex, found, type, services, serviceIndex, newestOnly) {
      if (layerIndex >= layersSorted.length) {
        const urls = [];
        for (const key in found) {
          urls.push(found[key]);
        }
        console.log("DEM: znaleziono URL-i:", urls.length);
        if (urls.length === 0) {
          queryService(services, serviceIndex + 1, points, type, newestOnly);
          return;
        }
        startDownloads(urls, type);
        return;
      }
      if (pointIndex >= points.length) {
        collectLayered(serviceUrl, layersSorted, layerIndex + 1, points, 0, found, type, services, serviceIndex, newestOnly);
        return;
      }
      const pt = points[pointIndex];
      const bbox = (pt.y - 50) + "," + (pt.x - 50) + "," + (pt.y + 50) + "," + (pt.x + 50);
      const layerParam = encodeURIComponent(layersSorted[layerIndex]);
      const url = serviceUrl + "SERVICE=WMS&request=GetFeatureInfo&version=1.3.0&styles=&crs=EPSG:2180&width=101&height=101&format=image/png&transparent=true&i=50&j=50&INFO_FORMAT=text/html&layers=" + layerParam + "&query_layers=" + layerParam + "&bbox=" + bbox;
      const xhr = new XMLHttpRequest();
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) {
          return;
        }
        const matches = xhr.responseText.match(/https?:\/\/[^"'<>\s]+\.(asc|tif|tiff|zip)/g) || [];

        // Metryczki zbieramy OBOK dotychczasowego szukania adresów, a nie
        // zamiast niego: gdyby odpowiedź przestała być tabelą, adresy nadal
        // się znajdą, a metryczki po prostu wyjdą puste.
        const wiersze = xhr.responseText.split(/<tr[^>]*>/i);
        for (const w of wiersze) {
          const trafienie = w.match(/https?:\/\/[^"'<>\s]+\.(asc|tif|tiff|zip)/);
          if (trafienie) {
            demDownloader.opisyPlikow[trafienie[0].split("/").pop()] = demDownloader.metryczkaZWiersza(w);
          }
        }

        for (const u of matches) {
          if (newestOnly) {
            const g = godloFromUrl(u);
            if (!found[g]) {
              found[g] = u;
            }
          } else {
            found[u] = u;
          }
        }
        collectLayered(serviceUrl, layersSorted, layerIndex, points, pointIndex + 1, found, type, services, serviceIndex, newestOnly);
      };
      xhr.open("GET", url);
      xhr.send();
    }
    function godloOf(fileName) {
      const m = fileName.match(/[A-Z]-\d{2}-[0-9A-Za-z-]+/);
      return m ? m[0] : "";
    }

    function computeChm() {
      const home = qgisProject.homePath;
      const nmtMosaics = iface.listFiles(home + "/NMT", "NMT_*.tif");
      const nmptMosaics = iface.listFiles(home + "/NMPT", "NMPT_*.tif");
      const nmptSet = {};
      for (const m of nmptMosaics) {
        nmptSet[m.replace("NMPT_", "")] = m;
      }
      const mosaicPairs = [];
      for (const m of nmtMosaics) {
        const suffix = m.replace("NMT_", "");
        if (nmptSet[suffix]) {
          mosaicPairs.push({ "suffix": suffix, "nmt": m, "nmpt": nmptSet[suffix] });
        }
      }
      if (mosaicPairs.length > 0) {
        displayToast(qsTr("Licze CHM z mozaik: %1 obszarow...").arg(mosaicPairs.length));
        Qt.callLater(function () {
          let doneMosaics = 0;
          for (const pair of mosaicPairs) {
            const chmOut = home + "/CHM/CHM_" + pair.suffix;
            const areaLabel = pair.suffix.replace(".tif", "").replace(/_/g, " ");
            if (iface.rasterDifference(home + "/NMPT/" + pair.nmpt, home + "/NMT/" + pair.nmt, chmOut) && iface.addRasterLayerToProject(chmOut, areaLabel + " CHM", "EPSG:2180", "chm", areaLabel)) {
              doneMosaics++;
            }
          }
          displayToast(qsTr("CHM gotowe: %1 z %2 obszarow").arg(doneMosaics).arg(mosaicPairs.length));
        });
        return;
      }
      const nmtFiles = iface.listFiles(home + "/NMT", "*.asc").concat(iface.listFiles(home + "/NMT", "*.tif"));
      const nmptFiles = iface.listFiles(home + "/NMPT", "*.asc").concat(iface.listFiles(home + "/NMPT", "*.tif"));
      if (nmtFiles.length === 0 || nmptFiles.length === 0) {
        displayToast(qsTr("Najpierw pobierz NMT i NMPT dla obszaru (foldery NMT/ i NMPT/ w projekcie)"), "warning");
        return;
      }
      const nmtByGodlo = {};
      for (const f of nmtFiles) {
        const g = godloOf(f);
        if (g !== "") {
          nmtByGodlo[g] = f;
        }
      }
      const pairsList = [];
      for (const f of nmptFiles) {
        const g = godloOf(f);
        if (g !== "" && nmtByGodlo[g]) {
          pairsList.push({ "godlo": g, "nmpt": home + "/NMPT/" + f, "nmt": home + "/NMT/" + nmtByGodlo[g], "out": home + "/CHM/CHM_" + g + ".tif" });
        }
      }
      if (pairsList.length === 0) {
        displayToast(qsTr("Brak par NMT/NMPT o wspólnym godle — pobierz oba modele dla tego samego obszaru"), "warning");
        return;
      }
      displayToast(qsTr("CHM: %1 par arkuszy w kolejce…").arg(pairsList.length));
      processChmPair(pairsList, 0, 0);
    }

    function processChmPair(pairsList, index, done) {
      if (index >= pairsList.length) {
        displayToast(qsTr("CHM gotowe: %1 z %2 arkuszy").arg(done).arg(pairsList.length));
        return;
      }
      const pair = pairsList[index];
      if (iface.listFiles(qgisProject.homePath + "/CHM", "CHM_" + pair.godlo + ".tif").length > 0) {
        displayToast(qsTr("CHM %1 już policzony — wczytuję").arg(pair.godlo));
        const okExisting = iface.addRasterLayerToProject(pair.out, "CHM " + pair.godlo, "EPSG:2180", "chm");
        Qt.callLater(function () {
          processChmPair(pairsList, index + 1, done + (okExisting ? 1 : 0));
        });
        return;
      }
      displayToast(qsTr("Liczę CHM %1 (%2/%3) — to potrwa…").arg(pair.godlo).arg(index + 1).arg(pairsList.length));
      Qt.callLater(function () {
        let ok = false;
        if (iface.rasterDifference(pair.nmpt, pair.nmt, pair.out)) {
          ok = iface.addRasterLayerToProject(pair.out, "CHM " + pair.godlo, "EPSG:2180", "chm");
        }
        Qt.callLater(function () {
          processChmPair(pairsList, index + 1, done + (ok ? 1 : 0));
        });
      });
    }
    /**
     * WorkField 23.08.2026 — arkusze GUGiK bywaja spakowane. Regula zbierajaca
     * adresy przyjmuje .zip, pobieranie je zapisuje, a skladanie mozaiki
     * szukalo tylko .asc i .tif — spakowany arkusz lezal w katalogu i nie
     * wchodzil do mozaiki. Objaw niemy: mozaika po prostu mniejsza.
     * Zwraca liste nazw archiwow, ktore udalo sie rozpakowac.
     */
    function rozpakujArchiwa(type) {
      const home = qgisProject.homePath;
      const archiwa = iface.listFiles(home + "/" + type, "*.zip");
      const rozpakowane = [];
      for (const z of archiwa) {
        if (FileUtils.unzipTo(home + "/" + type + "/" + z, home + "/" + type)) {
          rozpakowane.push(z);
        }
      }
      if (rozpakowane.length > 0) {
        displayToast(qsTr("Rozpakowano %1 archiwów %2").arg(rozpakowane.length).arg(type));
      }
      return rozpakowane;
    }

    /**
     * Zapisuje metryczkę mozaiki obok niej, jako CSV z nagłówkiem.
     * CSV, a nie JSON, bo ten plik ma się otwierać w arkuszu bez tłumacza.
     */
    function zapiszMetryczke(type, areaSafe, nazwy, streszczenie) {
      const linie = ["plik;data;piksel;uklad;kolor"];
      for (const n of nazwy) {
        const o = opisyPlikow[n] || {
          "data": "",
          "piksel": "",
          "uklad": "",
          "kolor": ""
        };
        linie.push([n, o.data, o.piksel, o.uklad, o.kolor].join(";"));
      }
      linie.push("");
      linie.push("# mozaika: " + type + "_" + areaSafe + ".tif");
      linie.push("# obszar: " + areaName);
      linie.push("# streszczenie: " + (streszczenie !== "" ? streszczenie : "brak metryczek w skorowidzu"));
      linie.push("# zlozono: " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm"));
      const sciezka = qgisProject.homePath + "/" + type + "/" + type + "_" + areaSafe + ".metryczka.csv";
      if (!FileUtils.writeFileContent(sciezka, linie.join("\n") + "\n")) {
        displayToast(qsTr("Nie udało się zapisać metryczki %1").arg(type), "warning");
      }
    }

    function mergeMosaic(type) {
      if (!mosaicBbox) {
        return;
      }
      const home = qgisProject.homePath;
      const archiwa = rozpakujArchiwa(type);
      const names = iface.listFiles(home + "/" + type, "*.asc").concat(iface.listFiles(home + "/" + type, "*.tif"));
      const arkusze = [];
      const inputs = [];
      for (const n of names) {
        // Wykluczamy WCZESNIEJSZE MOZAIKI, a nie nazwy zawierajace "_obszar".
        // Stary warunek szukal malej litery, a plik nazywa sie "NMT_Obszar_1.tif"
        // — czyli poprzednia mozaika wchodzila jako wsad do nastepnej.
        if (n.toUpperCase().indexOf(type.toUpperCase() + "_") === 0) {
          continue;
        }
        arkusze.push(n);
        inputs.push(home + "/" + type + "/" + n);
      }
      if (inputs.length === 0) {
        return;
      }
      displayToast(qsTr("Skladam mozaike %1 z %2 arkuszy...").arg(type).arg(inputs.length));
      const areaSafe = areaName.replace(/[^\w-]/g, "_");
      const outPath = home + "/" + type + "/" + type + "_" + areaSafe + ".tif";
      const metryczka = streszczenieMetryczek(arkusze);

      Qt.callLater(function () {
        if (iface.clipMergeRasters(inputs, mosaicBbox.xmin, mosaicBbox.ymin, mosaicBbox.xmax, mosaicBbox.ymax, outPath)) {
          const nazwaWarstwy = metryczka !== "" ? areaName + " " + type + " (" + metryczka + ")" : areaName + " " + type;
          if (iface.addRasterLayerToProject(outPath, nazwaWarstwy, "EPSG:2180", "", areaName)) {
            displayToast(qsTr("%1 %2 gotowe - jedna warstwa, wspolna skala barw").arg(areaName).arg(type));
            areaCounter++;
          }

          // Metryczka MUSI wylądować w pliku ZANIM skasujemy arkusze — inaczej
          // za rok zostanie mozaika bez daty, a model wysokościowy bez rocznika
          // jest systematycznie zbyt optymistyczny i nie da się tego zobaczyć.
          zapiszMetryczke(type, areaSafe, arkusze, metryczka);

          // Sprzatamy DOPIERO po udanym zlozeniu. Arkusze sa odtwarzalne
          // (da sie je pobrac ponownie), ale kasowanie ich przed sprawdzeniem
          // wyniku zamienialoby jeden nieudany warp w utracone pol godziny.
          const usuniete = iface.usunArkuszeDem(type, arkusze.concat(archiwa));
          if (usuniete > 0) {
            displayToast(qsTr("Usunięto %1 arkuszy źródłowych %2 — zostaje mozaika").arg(usuniete).arg(type));
          }
        } else {
          displayToast(qsTr("Nie udalo sie zlozyc mozaiki %1 — arkusze zostaja").arg(type), "error");
        }
      });
    }
    function startDownloads(urls, type) {
      const capped = urls.slice(0, 4);
      const nazwy = capped.map(function (u) {
        return u.split("/").pop();
      });
      const metryczka = streszczenieMetryczek(nazwy);
      const dopisek = metryczka !== "" ? "  ·  " + metryczka : "";
      if (urls.length > 4) {
        displayToast(qsTr("Obszar obejmuje %1 arkuszy - pobieram pierwsze 4 (przybliz mape po reszte)").arg(urls.length) + dopisek, "warning");
      } else {
        displayToast(qsTr("Pobieram %1: %2 arkuszy (duze pliki, to potrwa)...").arg(type).arg(capped.length) + dopisek);
      }
      for (const u of capped) {
        const fileName = u.split("/").pop();
        active++;
        iface.downloadFile(u, qgisProject.homePath + "/" + type + "/" + fileName);
      }
    }
  }

  Connections {
    target: iface

    function onLoadProjectEnded(path, name) {

      if (!dashBoard.pendingBlankSetup) {
        return;
      }
      dashBoard.pendingBlankSetup = false;
      iface.setProjectCrs("EPSG:2178");
      iface.addXyzBasemap("Esri World Imagery", "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", 19);
      // WorkField 6.10.2026 [WF-NOWY-PODKLADY] — OSM POD ESRI: addXyzBasemap
      // dokłada na sam dół legendy, więc drugi dodany ląduje pod pierwszym.
      iface.addXyzBasemap("OpenStreetMap", "https://tile.openstreetmap.org/{z}/{x}/{y}.png", 19);
      dashBoard.urzadzNowyProjekt(path, name);
      if (dashBoard.pendingBlankCenter) {
        const c = iface.transformPointToProjectCrs(dashBoard.pendingBlankCenter.x, dashBoard.pendingBlankCenter.y, "EPSG:2180");
        if (c.x !== undefined) {
          // extent oczekuje QgsRectangle - Qt.rect() daje QRectF i nie przechodzi
          mapCanvas.mapSettings.setExtentFromPoints([GeometryUtils.point(c.x - 50, c.y - 50), GeometryUtils.point(c.x + 50, c.y + 50)]);
        }
      }
    }

    function onDownloadFinished(path) {
      if (demDownloader.active <= 0) {
        return;
      }
      demDownloader.active--;
      const fileName = path.split("/").pop();
      displayToast(qsTr("Pobrano %1").arg(fileName));
      if (demDownloader.active === 0 && demDownloader.activeType !== "") {
        demDownloader.mergeMosaic(demDownloader.activeType);
      }
    }

    function onDownloadFailed(error, path) {
      if (demDownloader.active <= 0) {
        return;
      }
      demDownloader.active--;
      displayToast(qsTr("Blad pobierania: %1").arg(error), "error");
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.topMargin: mainWindow.sceneTopMargin
    anchors.bottomMargin: mainWindow.sceneBottomMargin
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        // TYTUL SZUFLADY (25.09.2026) — patrz blizniak w QfDataDrawer.
        // Sama nazwa programu tu byla; brakowalo roli, czyli tego, czym
        // ta szuflada rozni sie od prawej.
        //
        // `elide` nie bylo tu wcale — dluzszy tytul wychodzilby poza
        // szuflade, na przycisk zamkniecia.
        Text {
          Layout.fillWidth: true
          text: qsTr("WorkFieldGIS — Dane")
          font: Theme.strongFont
          fontSizeMode: Text.HorizontalFit
          minimumPointSize: Theme.tipFont.pointSize
          color: Theme.mainTextColor
          elide: Text.ElideRight
        }

        // Wersja pod nazwa, mala czcionka. Do 17.09.2026 sprawdzalo sie ja
        // przez `adb shell dumpsys package` — a naglowek stal pusty.
        Text {
          id: wersjaAplikacji

          Layout.fillWidth: true
          // NIE wiazanie `text: appVersionStr` — ta nazwa nie jest widoczna
          // przy budowie komponentu (ReferenceError w linii 796), choc dziala
          // WEWNATRZ funkcji, bo te wykonuja sie pozniej, gdy kontekst jest
          // juz zbudowany.
          text: ""
          font: Theme.tinyFont
          color: Theme.secondaryTextColor
          elide: Text.ElideRight

          Component.onCompleted: {
            try {
              wersjaAplikacji.text = appVersionStr;
            } catch (e) {
              wersjaAplikacji.text = "";
            }
          }

          // Nota wydania z GitHuba — `QfChangelogContents` pobiera ja
          // z API wydan, a `QfChangelog` pokazuje jako Markdown. Oba byly
          // w aplikacji od zawsze, wolane TYLKO z ekranu "O programie",
          // do ktorego nikt nie zaglada.
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            onClicked: {
              dashBoard.close();
              if (typeof changelogPopup !== "undefined")
                changelogPopup.open();
            }
          }
        }
      }

      // WFG-JAK-ZACZAC-PRZYCISK — WorkField 22.09.2026.
      // Ekran „Jak zacząć?” pokazywał się raz, przy pierwszym uruchomieniu,
      // i po pierwszym kliknięciu nie było do niego powrotu (uwaga
      // z telefonu, 22.09). Przycisk stoi w nagłówku szuflady, czyli
      // ponad zakładkami — widać go w każdej sekcji.
      QfToolButton {
        width: 36
        height: 36
        padding: 0
        bgcolor: "transparent"
        iconSource: Theme.getThemeVectorIcon("wfg_pytanie")
        iconColor: Theme.mainTextColor
        ToolTip.text: qsTr("Jak zacząć?")
        ToolTip.delay: 400
        ToolTip.visible: hovered && ToolTip.text !== ""
        onClicked: {
          dashBoard.close();
          dashBoard.pokazJakZaczac();
        }
      }

      QfToolButton {
        width: 36
        height: 36
        padding: 0
        bgcolor: "transparent"
        iconSource: Theme.getThemeVectorIcon("ic_arrow_left_black_24dp")
        iconColor: Theme.mainTextColor
        onClicked: dashBoard.close()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
    }

    // PRZELACZNIK UKLADU W NAGLOWKU (25.09.2026).
    //
    // Stal w sekcji „Projekt". A `QfSiatkaMenu` jest w tej szufladzie
    // szesc razy: w „Projekcie", w „Warstwach" (osobno „Dane" i „Aktywna
    // warstwa") i w „Stylizacji". Czyli na karcie „Warstwy" uklad
    // dzialal, a zmienic go stamtad nie bylo jak.
    //
    // Tu jest ponad zakladkami, czyli nad wszystkimi sekcjami, ktorych
    // dotyczy. W prawej szufladzie rozwiazanie jest INNE — tam uklad
    // rzadzi jedna zakladka, wiec przelacznik zostal w niej.
    QfPrzelacznikUkladu {
      t: dashBoard.t
      Layout.fillWidth: true
      Layout.leftMargin: 6
      Layout.rightMargin: 6
      Layout.topMargin: 4
      Layout.bottomMargin: 4
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
    }

    // WorkField: poziomy przełącznik widoków panelu (komputer);
    // ikona + nazwa, bo etykieta bije zgadywanie
    RowLayout {
      visible: Qt.platform.os !== "android" && Qt.platform.os !== "ios"
      Layout.fillWidth: true
      Layout.leftMargin: 4
      Layout.rightMargin: 4
      spacing: 2

      Repeater {
        model: [{ "nazwa": qsTr("Projekt"), "ikona": "wfg_nowe", "sekcja": 1 }, { "nazwa": qsTr("Warstwy"), "ikona": "wfg_warstwy", "sekcja": 2 }, { "nazwa": qsTr("Stylizacja"), "ikona": "wfg_stylizacja", "sekcja": 3 }].filter(function (z) {
          // WorkField 6.10.2026 — zakładka niesie swoją półkę jak pozycja menu.
          // Numery sekcji się nie przesuwają: każda zakładka trzyma swój.
          return z.polka !== "eksperymentalna" || mainWindow.pokazujEksperymentalne === true;
        })

        delegate: ItemDelegate {
          id: przelacznikWidoku

          required property var modelData


          readonly property bool aktywny: dashStack.currentIndex === modelData.sekcja

          Layout.fillWidth: true
          Layout.preferredHeight: 34
          padding: 0

          // ── ZAKŁADKI JAK W PRAWEJ SZUFLADZIE (25.09.2026) ─────────
          //
          // Zmierzone na zrzucie Piotra: tło obu szuflad jest takie samo
          // (55, 71, 79), ale aktywna zakładka po lewej dostawała PEŁNY
          // BLOK w kolorze marki (0, 105, 92), a po prawej — sam napis
          // w tym kolorze i kreskę pod spodem.
          //
          // Powód rozjazdu: prawa szuflada używa stylowego `TabBar`-a,
          // a lewa na komputerze ma własny rząd `ItemDelegate`
          // (`TabBar` poniżej jest widoczny tylko na telefonie).
          // Dwie różne kontrolki robiły to samo na dwa sposoby.
          //
          // Kolor zaznaczenia się NIE zmienia — to nadal `Theme.mainColor`,
          // czyli dokładnie ta barwa, która wypełniała blok. Przestaje
          // tylko być plamą.
          background: Rectangle {
            color: "transparent"

            // WorkField 7.10.2026 [WF-JASNA-ZAKLADKA] — teal na ciemnym tle
            // szuflady był nieczytelny (ok. 1,6:1). Jasna plakietka pod
            // aktywną zakładką daje ten sam teal przy kontraście ok. 7:1.
            Rectangle {
              anchors.fill: parent
              anchors.margins: 3
              radius: 4
              color: Qt.rgba(1, 1, 1, 0.9)
              visible: przelacznikWidoku.aktywny
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: 6
              anchors.rightMargin: 6
              height: 2
              color: Theme.mainColor
              visible: przelacznikWidoku.aktywny
            }
          }

          contentItem: RowLayout {
            spacing: 5

            Item {
              Layout.fillWidth: true
            }

            Image {
              id: ikonaWidoku
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16
              fillMode: Image.PreserveAspectFit
              sourceSize.width: 16
              sourceSize.height: 16
              source: Theme.getThemeVectorIcon(przelacznikWidoku.modelData.ikona)
              visible: false
            }

            ColorOverlay {
              // MultiEffect.colorization zachowuje jasnosc — ciemna ikona
              // Breeze zostawala ciemna takze w ciemnym motywie (17.08.2026).
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16
              source: ikonaWidoku
              visible: ikonaWidoku.status === Image.Ready
              color: przelacznikWidoku.aktywny ? Theme.mainColor : Theme.mainTextColor
            }

            Text {
              text: przelacznikWidoku.modelData.nazwa
              font: Theme.tinyFont
              color: przelacznikWidoku.aktywny ? Theme.mainColor : Theme.mainTextColor
            }

            Item {
              Layout.fillWidth: true
            }
          }

          onClicked: dashBoard.sekcjaWymuszona = modelData.sekcja
        }
      }
    }

    TabBar {
      id: dashTabs

      // WorkField: na komputerze sekcje wybiera menu (otworzSekcje),
      // zakładki zostają narzędziem telefonu
      visible: Qt.platform.os === "android" || Qt.platform.os === "ios"
      Layout.fillWidth: true
      Layout.preferredHeight: visible ? implicitHeight : 0
      currentIndex: 1

      // WorkField: menu (otworzSekcje) wymusza sekcje przez sekcjaWymuszona,
      // ale na telefonie NIC jej nie zerowalo — stos zostawal na wymuszonej
      // sekcji na zawsze i zakladki przestawaly cokolwiek zmieniac.
      // Tapniecie zakladki zwalnia wymuszenie. Na komputerze ten TabBar
      // jest niewidoczny i nigdy sie nie zmienia, wiec zmiana jest tam bezczynna.
      onCurrentIndexChanged: dashBoard.sekcjaWymuszona = -1

      // WorkField 24.09.2026 — ZAKLADKA „ZLECENIA" ZNIKNELA.
      //
      // Wpis „Zlecenia" stoi juz jako pierwszy w „Wszystkich projektach"
      // w tej wlasnie zakladce, wiec osobna byla powtorzeniem — a przez
      // nia czwarty tytul nie miescil sie w szerokosci telefonu
      // („Stylizacja" pokazywala sie jako „Stylizac…").
      //
      // TRESC SEKCJI ZOSTAJE. Wpis w „Projekcie" robi
      // `sekcjaWymuszona = 0`, czyli przelacza na TA sekcje — gdyby
      // wyciac ja ze stosu, jedyna droga do zlecen prowadzilaby donikad.
      TabButton {
        text: qsTr("Projekt")
        font: Theme.tipFont
      }
      TabButton {
        text: qsTr("Warstwy")
        font: Theme.tipFont
      }
      TabButton {
        text: qsTr("Stylizacja")
        font: Theme.tipFont
      }
    }

    StackLayout {
      id: dashStack

      Layout.fillWidth: true
      Layout.fillHeight: true
      // Zakladek jest trzy, a sekcji cztery: sekcja 0 („Zlecenia") nie
      // ma juz swojego przycisku i wchodzi sie do niej wylacznie przez
      // `sekcjaWymuszona` — z wpisu w „Projekcie" albo z menu. Stad
      // przesuniecie o jeden: zakladka 0 to sekcja 1.
      currentIndex: dashBoard.sekcjaWymuszona >= 0 ? dashBoard.sekcjaWymuszona : dashTabs.currentIndex + 1

      // ── Zlecenia (0, komputer i telefon) ────────────────────────
      // WorkField 18.08.2026: strona = samo drzewo. „Stan zleceń” wtopiony
      // w wiersze drzewa (konsolidacja), osobne kafle zlikwidowane.
      QfStudioSection {
        // WorkField 18.08.2026: id, bo zakładka Projekt woła stąd
        // zamienNaSzablonDla() — dialog i silnik mieszkają w tym komponencie.
        id: drzewoZlecen
        Layout.fillWidth: true
        Layout.fillHeight: true
      }


      // ── Projekt ─────────────────────────────────────────────
      ColumnLayout {
        spacing: 0

        ColumnLayout {
          id: projectSection

      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 4

      property bool dirty: false
      property string filePath: ""

      function refresh() {
        dirty = ProjectUtils.isProjectDirty(qgisProject);
        filePath = qgisProject ? ProjectUtils.projectFilePath(qgisProject) : "";
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: mainWindow.projectTitle !== "" ? mainWindow.projectTitle : qsTr("Projekt")
          font: t.strongTipFont
          color: t.mainTextColor
          elide: Text.ElideRight
        }

        Text {
          text: projectSection.dirty ? qsTr("niezapisane zmiany") : ""
          font: t.tinyFont
          color: t.warningColor
        }
      }

      Text {
        Layout.fillWidth: true
        text: projectSection.filePath !== "" ? FileUtils.fileName(projectSection.filePath) : qsTr("projekt niezapisany")
        font: t.tinyFont
        color: t.secondaryTextColor
        elide: Text.ElideMiddle
      }

      // ── aktywność: zdjęcia DCIM z ostatnich 14 dni (słupki) ──
      ColumnLayout {
        id: aktywnosc

        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 2
        visible: projectSection.filePath !== "" && aktywnosc.suma > 0

        property var slupki: []
        property int suma: 0
        property int maks: 1

        FolderListModel {
          id: dcimAktywnosc
          folder: projectSection.filePath !== ""
                  ? "file://" + FileUtils.absolutePath(projectSection.filePath) + "/DCIM"
                  : ""
          nameFilters: ["*.jpg", "*.jpeg"]
          showDirs: false
          onCountChanged: aktywnosc.przelicz()
        }

        function przelicz() {
          const dni = [];
          const klucze = {};
          const teraz = new Date();
          for (let i = 13; i >= 0; i--) {
            const d = new Date(teraz.getTime() - i * 86400000);
            const k = d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
            klucze[k] = dni.length;
            dni.push(0);
          }
          let razem = 0;
          for (let j = 0; j < dcimAktywnosc.count; j++) {
            const m = /_(20[0-9]{6})_/.exec(dcimAktywnosc.get(j, "fileName"));
            razem++;
            if (m && klucze[parseInt(m[1])] !== undefined)
              dni[klucze[parseInt(m[1])]]++;
          }
          suma = razem;
          maks = Math.max(1, Math.max.apply(null, dni));
          slupki = dni;
          plotnoAktywnosci.requestPaint();
        }

        Text {
          Layout.fillWidth: true
          text: qsTr("Aktywność · %1 zdjęć w projekcie").arg(aktywnosc.suma)
          font: t.tinyFont
          color: t.secondaryTextColor
        }
        Canvas {
          id: plotnoAktywnosci

          Layout.fillWidth: true
          Layout.preferredHeight: 34

          onWidthChanged: requestPaint()
          onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const n = aktywnosc.slupki.length;
            if (n === 0)
              return;
            const krok = width / n;
            for (let i = 0; i < n; i++) {
              const w = aktywnosc.slupki[i];
              const h = w > 0 ? Math.max(3, (height - 2) * w / aktywnosc.maks) : 1;
              ctx.fillStyle = w > 0 ? t.mainColor : "#d0d0d0";
              ctx.fillRect(i * krok + 1, height - h, Math.max(2, krok - 2), h);
            }
          }
        }
      }

      // ── wyposazenie i ostrzezenia: jedna linia, szczegoly na zadanie ──
      QtObject {
        id: stanWyposazenia

        property int zgodnych: 0
        property int wszystkich: 0
        //! Liczy TYLKO prewencję: ustawienia i skład projektu. Błędy
        //! w danych mają własny wiersz i własny licznik.
        property int ostrzezen: 0
        property var moduly: []
        property var uwagi: []

        // ====================================================================
        // TRZY KUBEŁKI, NIE JEDEN — 23.09.2026
        // ====================================================================
        // Do dziś wszystkie ostrzeżenia szły jednym ciągiem pod wyposażeniem.
        // Czerwona linijka „obiekt o obwiedni 0.09 m — to nie jest płat"
        // wyglądała tam jak awaria CAŁEGO projektu, a jest uwagą o jednym
        // obiekcie — i naprawa wymaga zupełnie innych narzędzi niż założenie
        // brakującego modułu.
        //
        //   uwagiUstawien   ustawienie złe DLA TYCH danych. Szkody jeszcze
        //                   nie ma. Wiesza się PRZY MODULE, którego dotyczy.
        //   uwagiProjektu   czegoś brakuje w składzie projektu.
        //   bledyDanych     błąd już popełniony, z adresem obiektu.
        //                   Osobny wiersz, osobne okno, osobne narzędzia.
        property var uwagiUstawien: []
        property var uwagiProjektu: []
        property var bledyDanych: []

        //! Ostrzeżenia przypięte do TEGO modułu.
        function uwagiModulu(id) {
            const out = [];
            for (let j = 0; j < uwagiUstawien.length; j++)
                if (uwagiUstawien[j].modul === id)
                    out.push(uwagiUstawien[j]);
            return out;
        }

        //! Ostrzeżenia prewencyjne bez modułu — pod listą, nie przy niczym.
        function uwagiBezModulu() {
            const out = [];
            for (let j = 0; j < uwagiUstawien.length; j++)
                if (!uwagiUstawien[j].modul)
                    out.push(uwagiUstawien[j]);
            for (let j = 0; j < uwagiProjektu.length; j++)
                out.push(uwagiProjektu[j]);
            return out;
        }

        function odswiez() {
          if (!qgisProject || qgisProject.homePath === "") {
            moduly = [];
            uwagi = [];
            uwagiUstawien = [];
            uwagiProjektu = [];
            bledyDanych = [];
            zgodnych = 0;
            wszystkich = 0;
            ostrzezen = 0;
            return;
          }
          // `sprawdz` zwraca LISTE modulow, nie mape z kluczem `moduly`.
          let m = [];
          try {
            m = wyposazenieProjektu.sprawdz(qgisProject) || [];
          } catch (e) {
            m = [];
          }
          let zg = 0;
          for (let i = 0; i < m.length; i++)
            if (m[i].stan === "zgodny")
              zg++;
          moduly = m;
          wszystkich = m.length;
          zgodnych = zg;

          let u = [];
          try {
            const st = NarzedziaProjektu.stanProjektu(qgisProject);
            u = (st && st.ostrzezenia) ? st.ostrzezenia : [];
          } catch (e) {
            u = [];
          }
          uwagi = u;

          const uU = [];
          const uP = [];
          const uD = [];
          for (let j = 0; j < u.length; j++) {
            const r = u[j].rodzaj;
            if (r === "dane")
              uD.push(u[j]);
            else if (r === "ustawienie")
              uU.push(u[j]);
            else
              // „projekt" ORAZ wszystko, czego nie znamy. Starsza aplikacja
              // bez pola `rodzaj` ma pokazać wszystko, a nie zgubić po cichu.
              uP.push(u[j]);
          }
          uwagiUstawien = uU;
          uwagiProjektu = uP;
          bledyDanych = uD;
          ostrzezen = uU.length + uP.length;
        }
      }

      Wyposazenie {
        id: wyposazenieProjektu
      }

      Rectangle {
        id: paskaWyposazenia

        property bool rozwiniety: false

        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.preferredHeight: wierszPaska.implicitHeight + 10
        radius: 4
        color: t.controlBackgroundColor
        border.width: 1
        // Ten pasek mówi o PREWENCJI: czy projekt jest przygotowany.
        // Błędy w danych mają własny wiersz niżej i własną czerwień —
        // do 23.09.2026 zapalały tę ramkę na czerwono, przez co brak
        // modułu i zlepiony wierzchołek wyglądały tak samo.
        border.color: stanWyposazenia.ostrzezen > 0
                      ? t.warningColor
                      : (stanWyposazenia.zgodnych < stanWyposazenia.wszystkich
                         ? t.warningColor : t.controlBorderColor)

        RowLayout {
          id: wierszPaska

          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: 8
          spacing: 6

          Text {
            Layout.fillWidth: true
            text: stanWyposazenia.wszystkich === 0
                  ? qsTr("Wyposażenie · brak danych")
                  : (stanWyposazenia.ostrzezen > 0
                     ? qsTr("Wyposażenie · %1 z %2 · %3 uwag")
                         .arg(stanWyposazenia.zgodnych)
                         .arg(stanWyposazenia.wszystkich)
                         .arg(stanWyposazenia.ostrzezen)
                     : qsTr("Wyposażenie · %1 z %2")
                         .arg(stanWyposazenia.zgodnych)
                         .arg(stanWyposazenia.wszystkich))
            font: t.tinyFont
            color: stanWyposazenia.ostrzezen > 0 ? t.warningColor : t.secondaryTextColor
            elide: Text.ElideRight
          }

          Text {
            text: paskaWyposazenia.rozwiniety ? "\u25b2" : "\u25bc"
            font: t.tinyFont
            color: t.secondaryTextColor
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: {
            if (!paskaWyposazenia.rozwiniety)
              stanWyposazenia.odswiez();
            paskaWyposazenia.rozwiniety = !paskaWyposazenia.rozwiniety;
          }
        }
      }

      Flickable {
        id: przewijaczWyposazenia

        Layout.fillWidth: true
        // Sufit 30% szuflady: pod spodem jest siatka czasownikow i to ona
        // jest glowna trescia zakladki. Rozwiniete wyposazenie nie moze
        // zepchnac jej pod krawedz.
        Layout.preferredHeight: paskaWyposazenia.rozwiniety
                                ? Math.min(trescWyposazenia.implicitHeight,
                                           mainWindow.height * 0.30)
                                : 0
        visible: paskaWyposazenia.rozwiniety
        contentHeight: trescWyposazenia.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
          id: trescWyposazenia

          width: przewijaczWyposazenia.width
          spacing: 2

          Repeater {
            model: stanWyposazenia.moduly

            // Moduł i jego ostrzeżenia w jednej kolumnie: „przyciąganie
            // łapie segment przy obiektach 0.1 m" ma wisieć POD
            // „Przyciąganie w metrach", a nie luzem na dole listy. Tak
            // widać, co przestawić — a to było jedyne pytanie, na które
            // ta linijka miała odpowiedzieć.
            ColumnLayout {
              id: wierszModulu

              Layout.fillWidth: true
              spacing: 1

              readonly property var uwagiTegoModulu:
                stanWyposazenia.uwagiModulu(modelData.modul)

              RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 6

                Rectangle {
                  Layout.preferredWidth: 8
                  Layout.preferredHeight: 8
                  radius: 4
                  color: modelData.stan === "zgodny" ? t.goodColor
                       : modelData.stan === "starszy" ? t.warningColor
                       : modelData.stan === "nowszy" ? t.warningColor
                       : t.errorColor
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.nazwa !== undefined ? modelData.nazwa : modelData.modul
                  font: t.tinyFont
                  // Moduł założony, ale z ostrzeżeniem, nie jest „w porządku”
                  // — zielona kropka mówiłaby wtedy nieprawdę.
                  color: wierszModulu.uwagiTegoModulu.length > 0
                         ? t.warningColor : t.mainTextColor
                  elide: Text.ElideRight
                }
              }

              Repeater {
                model: wierszModulu.uwagiTegoModulu

                // Objaw i czasownik w dwóch linijkach. „Przyciąganie łapie
                // segment" opisuje, co się dzieje; dopiero „zejdź z tolerancją
                // do 0.05 m" mówi, co z tym zrobić — a o to chodzi w terenie.
                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.leftMargin: 22
                  Layout.rightMargin: 8
                  Layout.bottomMargin: 2
                  spacing: 0

                  Text {
                    Layout.fillWidth: true
                    text: "↳ " + modelData.opis
                    font: t.tinyFont
                    color: t.warningColor
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    Layout.fillWidth: true
                    visible: modelData.rada !== undefined && modelData.rada !== ""
                    text: modelData.rada !== undefined ? modelData.rada : ""
                    font: t.tinyFont
                    color: t.secondaryTextColor
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }
          }

          // Pelny ekran zostaje: ma miejsce na czternascie warstw, dlugie
          // opisy i przyciski naprawy. Pasek jest skrotem, nie zamiennikiem.
          ToolButton {
            Layout.alignment: Qt.AlignRight
            Layout.rightMargin: 8
            text: qsTr("Zmień") + " \u2192"
            font.pointSize: t.tinyFont.pointSize
            implicitHeight: 24
            onClicked: {
              dashBoard.close();
              if (typeof ekranWyposazenia !== "undefined")
                ekranWyposazenia.otworz();
            }
          }

          // Prewencja bez modułu: ustawienia, których katalog nie opisuje
          // (edycja topologiczna), i braki w składzie projektu.
          // BŁĘDY W DANYCH TU NIE WCHODZĄ — mają własny wiersz niżej.
          Repeater {
            model: stanWyposazenia.uwagiBezModulu()

            ColumnLayout {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              spacing: 0

              Text {
                Layout.fillWidth: true
                text: "· " + (modelData.opis !== undefined ? modelData.opis : String(modelData))
                font: t.tinyFont
                color: modelData.waga === "brak" ? t.errorColor : t.warningColor
                wrapMode: Text.WordWrap
              }

              Text {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                visible: modelData.rada !== undefined && modelData.rada !== ""
                text: modelData.rada !== undefined ? modelData.rada : ""
                font: t.tinyFont
                color: t.secondaryTextColor
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }

      // ── błędy w danych: osobno, bo to inna robota ───────────
      //
      // „Tu powinny być sprawy prewencyjne. Analiza błędów post hoc i ich
      // naprawa wymaga innych narzędzi" (uwaga Piotra, 23.09.2026).
      //
      // Wiersz jest WIDOCZNY NIEZALEŻNIE od tego, czy wyposażenie jest
      // rozwinięte: błąd w danych to praca, która może być stracona, a nie
      // szczegół do rozwinięcia na żądanie. I nie chowa się pod nagłówkiem
      // „Wyposażenie", bo z wyposażeniem nie ma nic wspólnego.
      Rectangle {
        id: paskaBledow

        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.preferredHeight: wierszBledow.implicitHeight + 10
        visible: stanWyposazenia.bledyDanych.length > 0
        radius: 4
        color: t.controlBackgroundColor
        border.width: 1
        border.color: t.errorColor

        RowLayout {
          id: wierszBledow

          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: 8
          spacing: 6

          Text {
            Layout.fillWidth: true
            text: qsTr("Błędy w danych · %1").arg(stanWyposazenia.bledyDanych.length)
            font: t.tinyFont
            color: t.errorColor
            elide: Text.ElideRight
          }

          Text {
            text: "\u2192"
            font: t.tinyFont
            color: t.errorColor
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: {
            dashBoard.close();
            if (typeof wfAkcje !== 'undefined' && wfAkcje.stanProjektu)
              wfAkcje.stanProjektu();
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Wszystkie projekty")
        font: t.tinyFont
        color: t.secondaryTextColor
      }
      QfSiatkaMenu {
        Layout.fillWidth: true
        t: dashBoard.t
        szerokosc: dashBoard.width

        QfPozycjaMenu {
          // WorkField 7.10.2026 [WF-PRZEGLAD-PROJEKTOW] — dawne „Zlecenia”.
          // Piotr: „to teraz po prostu przegląd projektów”. Osobnej
          // zakładki już nie ma; jedyne wejście do sekcji 0 jest tutaj.
          text: qsTr("Przegląd projektów")
          polka: "eksperymentalna"
          ikona: "wfg_magazyn"
          onClicked: dashBoard.sekcjaWymuszona = 0
        }
        QfPozycjaMenu {
          // WorkField 7.10.2026 [WF-OTWORZ-Z-DYSKU-CORE] — z menu „⋯” belki
          // komputera. Na komputerze: systemowe okno wyboru pliku; obok
          // „Otwórz projekty” — przeglądarka katalogu projektów. CORE
          // (decyzja Piotra, 7.10).
          text: qsTr("Otwórz z dysku…")
          ikona: "wfg_otworz"
          onClicked: {
            dashBoard.close();
            wfAkcje.otworzProjekt();
          }
        }
        QfPozycjaMenu {
          // WorkField 6.10.2026 [WF-NOWY-PROJEKT-MENU] — „Nowy projekt” to
          // CORE: jedno obowiązkowe pole (nazwa), metryczka nieobowiązkowa,
          // projekt od razu kompletny (warstwy uniwersalne, całe wyposażenie,
          // podkłady). Decyzja Piotra z 6.10: zleceniodawca/teren/zlecenie
          // nie są warunkiem założenia — są metadanymi do grupowania.
          text: qsTr("Nowy projekt")
          ikona: "wfg_nowe"
          onClicked: {
            dashBoard.close();
            projectNameDialog.openFor("blank");
          }
        }
        QfPozycjaMenu {
          // Dawny „Nowy projekt”: kaskada zleceniodawca → teren → zlecenie
          // z istniejących zleceń (18.08.2026). Zostaje, ale na półce
          // eksperymentalnej, razem ze Zleceniami, z których wyrasta.
          text: qsTr("Nowy projekt w zleceniu")
          polka: "eksperymentalna"
          ikona: "wfg_nowe"
          onClicked: {
            dashBoard.close();
            nowyProjekt.open();
          }
        }
        QfPozycjaMenu {
          // WorkField 18.09.2026 — wejscie dla projektanta CAD: wskazuje
          // rysunek, dostaje projekt z podkladem i warstwami roboczymi.
          // Osobno od "Nowego projektu", bo tam sa cztery listy rozwijane
          // (zleceniodawca, teren, zlecenie, rodzaj), a CADowiec zaczyna
          // od pliku, nie od zlecenia.
          text: qsTr("Projekt z DXF")
          polka: "zaawansowana" // [WF-POLKA-ZAAWANSOWANE]
          ikona: "wfg_nowe"
          onClicked: {
            dashBoard.close();
            if (typeof kreatorCAD !== "undefined")
              kreatorCAD.otworz();
          }
        }
        QfPozycjaMenu {
          // WorkField 19.09.2026 - droga powrotna dla projektanta CAD.
          // Czasownik NarzedziaProjektu.eksportujDxf robi to samo co
          // "Eksportuj projekt do DXF" w QGIS i czyta te same ustawienia.
          text: qsTr("Eksport do DXF")
          polka: "zaawansowana" // [WF-POLKA-ZAAWANSOWANE]
          ikona: "wfg_paczka"
          enabled: qgisProject && qgisProject.homePath !== ""
          onClicked: {
            // WFG-po-zamknieciu: komunikat pokazany w trakcie zamykania
            // szuflady ginal pod jej animacja - eksport rusza po sygnale closed.
            const wykonaj = function () {
              dashBoard.closed.disconnect(wykonaj);
              if (typeof NarzedziaProjektu === "undefined")
                return;
              const w = NarzedziaProjektu.eksportujDxf(qgisProject, "", false);
              console.log("WFG eksport DXF: " + JSON.stringify(w));
              if (w.blad) {
                displayToast(w.blad, "warning");
                return;
              }
              const plik = w.plik;
              displayToast(qsTr("DXF: %1 obiektów z %2 warstw").arg(w.obiekty).arg(w.warstwy.length),
                           "info", qsTr("Wyślij"), function () {
                             platformUtilities.sendDatasetTo(plik);
                           });
            };
            dashBoard.closed.connect(wykonaj);
            dashBoard.close();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Zapisz jako szablon")
          polka: "eksperymentalna"
          ikona: "wfg_paczka"
          enabled: qgisProject && qgisProject.homePath !== ""
          onClicked: {
            // Odwrocenie interpretera: projekt -> przepis. Szablon przestaje
            // byc katalogiem do skopiowania, a staje sie ODCZYTANYM opisem
            // dobrego projektu. docs/WYPOSAZENIE.md
            projectNameDialog.openFor("szablon");
          }
        }
        QfPozycjaMenu {
          text: qsTr("Otwórz projekty") // WF-OTWORZ-PROJEKTY: otwiera katalog projektów
          ikona: "wfg_otworz"
          onClicked: {
            dashBoard.close();
            // przepływ (docs/MAGAZYN.md): żywe projekty biurka mieszkają
            // w wydaniach magazynu; na telefonie — w domu danych aplikacji
            if (Qt.platform.os === "android" || Qt.platform.os === "ios")
              photoGallery.openFiles(iface.dataRoot() + "Imported Projects");
            else
              // WorkField 23.08.2026 — bylo `ustawieniaStanu.korzenProjektow`.
              // Obiekt `ustawieniaStanu` zniknal z tego pliku dawno temu
              // (istnial jeszcze w f50ae148b), a DWA wywolania zostaly.
              // Kazde konczylo sie ReferenceError i przerywalo caly handler,
              // wiec "Otworz projekt" na komputerze nie robilo NIC.
              // Korzen magazynu wystawia QfStudioSection jako `korzen`.
              photoGallery.openFiles(drzewoZlecen.korzen + "/wydania");
          }
        }
        QfPozycjaMenu {
          text: qsTr("Importuj projekt (folder)")
          ikona: "wfg_import"
          onClicked: {
            dashBoard.close();
            platformUtilities.importProjectFolder();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Importuj projekt (ZIP)")
          polka: "zaawansowana" // [WF-POLKA-ZAAWANSOWANE] było eksperymentalna
          ikona: "wfg_paczka"
          onClicked: {
            dashBoard.close();
            platformUtilities.importProjectArchive();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Pobierz szablony")
          polka: "eksperymentalna"
          ikona: "wfg_chmura"
          onClicked: {
            dashBoard.close();
            photoGallery.openCloud();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Ekran startowy")
          polka: "eksperymentalna"
          ikona: "wfg_dom"
          onClicked: {
            dashBoard.close();
            returnHome();
          }
        }
      }
      Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: qsTr("Bieżący projekt")
        font: t.tinyFont
        color: t.secondaryTextColor
        opacity: projectSection.filePath !== "" ? 1.0 : 0.4
      }
      QfSiatkaMenu {
        Layout.fillWidth: true
        t: dashBoard.t
        szerokosc: dashBoard.width

        QfPozycjaMenu {
          // WorkField 18.08.2026: przyszło ze Zleceń — dotyczy projektu
          // OTWARTEGO. Wymaga projektu zapisanego na dysku, bo kopiujemy katalog.
          text: qsTr("Zamień na szablon")
          polka: "eksperymentalna"
          ikona: "wfg_paczka"
          enabled: projectSection.filePath !== "" && qgisProject && qgisProject.homePath !== ""
          onClicked: {
            dashBoard.close();
            drzewoZlecen.zamienNaSzablonDla(qgisProject.homePath,
                                            FileUtils.fileName(qgisProject.homePath));
          }
        }
        QfPozycjaMenu {
          text: qsTr("Zapisz")
          ikona: "wfg_zapisz"
          enabled: projectSection.filePath !== ""
          onClicked: {
            if (ProjectUtils.saveProject(qgisProject)) {
              displayToast(qsTr("Projekt zapisany"));
              projectSection.refresh();
            } else {
              displayToast(qsTr("Nie udało się zapisać projektu"));
            }
          }
        }
        QfPozycjaMenu {
          text: qsTr("Zapisz jako…")
          polka: "eksperymentalna"
          ikona: "wfg_zapisz_jako"
          enabled: projectSection.filePath !== ""
          onClicked: projectNameDialog.openFor("saveas")
        }
        QfPozycjaMenu {
          text: qsTr("Powiększ do danych")
          ikona: "wfg_powieksz"
          enabled: projectSection.filePath !== ""
          onClicked: {
            if (!iface.zoomToProjectData(dashBoard.mapSettings)) {
              const c = dashBoard.mapSettings.getCenter();
              dashBoard.mapSettings.setExtentFromPoints([GeometryUtils.point(c.x - 500, c.y - 500), GeometryUtils.point(c.x + 500, c.y + 500)]);
            }
            dashBoard.close();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Pliki projektu")
          polka: "zaawansowana" // [WF-POLKA-ZAAWANSOWANE]
          ikona: "wfg_przeglad"
          enabled: projectSection.filePath !== ""
          onClicked: {
            // nasza galeria, zakladka Pliki - jedno narzedzie do ogladania
            // zawartosci zamiast przegladarki QFielda
            dashBoard.close();
            photoGallery.openFiles(qgisProject ? qgisProject.homePath : "");
          }
        }
        // WorkField 8.10.2026 [WF-EKSPORT-PROJEKTU] — dwie pozycje CORE, wyjęte
        // z „Wymiany lokalnej” (półka eksperymentalna). Piotr: „to muszą być
        // opcje CORE, a paczka na telefonie ma od razu otwierać wysyłanie”.
        // Obie najpierw ZAPISUJĄ projekt — paczka bez ostatnich zmian byłaby
        // gorsza niż żadna. Działanie rusza po zamknięciu szuflady (komunikat
        // ginął pod jej animacją — lekcja z eksportu DXF).
        QfPozycjaMenu {
          text: qsTr("Eksportuj paczkę")
          ikona: "wfg_paczka"
          enabled: projectSection.filePath !== ""
          onClicked: {
            const wykonaj = function () {
              dashBoard.closed.disconnect(wykonaj);
              dashBoard.eksportujProjekt("paczka");
            };
            dashBoard.closed.connect(wykonaj);
            dashBoard.close();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Eksportuj na dysk")
          ikona: "wfg_eksport"
          enabled: projectSection.filePath !== ""
          onClicked: {
            const wykonaj = function () {
              dashBoard.closed.disconnect(wykonaj);
              dashBoard.eksportujProjekt("dysk");
            };
            dashBoard.closed.connect(wykonaj);
            dashBoard.close();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Wymiana lokalna")
          polka: "eksperymentalna"
          ikona: "wfg_wymiana"
          onClicked: {
            dashBoard.close();
            wymianaLokalna.open();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Właściwości")
          ikona: "wfg_wlasciwosci"
          enabled: projectSection.filePath !== ""
          onClicked: projectPropertiesPopup.open()
        }
        // WorkField 26.08.2026 — „jak ten projekt jest ustawiony".
        //
        // Sąsiaduje z „Właściwościami" świadomie: tamto mówi, CO projekt
        // zawiera, to — JAK jest ustawiony (przyciąganie, unikanie
        // nakładania, edycja topologiczna) i czy z danymi jest wszystko
        // w porządku.
        //
        // Wpis RĘCZNY, mimo że akcja jest w rejestrze QfAkcje: szuflada
        // ma własną listę i nie czyta z rejestru. To dług — patrz handoff.
        QfPozycjaMenu {
          text: qsTr("Stan projektu")
          polka: "eksperymentalna"
          ikona: "wfg_lupa"
          enabled: projectSection.filePath !== ""
          onClicked: {
            dashBoard.close();
            if (typeof wfAkcje !== 'undefined' && wfAkcje.stanProjektu)
              wfAkcje.stanProjektu();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Usuń projekt")
          ikona: "wfg_usun"
          enabled: projectSection.filePath !== ""
          onClicked: deleteProjectConfirm.open()
        }
      }
      Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: qsTr("Aplikacja")
        font: t.tinyFont
        color: t.secondaryTextColor
      }
      QfSiatkaMenu {
        Layout.fillWidth: true
        t: dashBoard.t
        szerokosc: dashBoard.width

        // WFG-JAK-ZACZAC-POZYCJA — WorkField 22.09.2026.
        // Druga droga do ekranu: wpis w menu, tam gdzie już stoi
        // „Zgłoś uwagę”. Pierwszy w sekcji, bo dotyczy pierwszego dnia.
        QfPozycjaMenu {
          text: qsTr("Jak zacząć?")
          ikona: "wfg_pytanie"
          onClicked: {
            dashBoard.close();
            dashBoard.pokazJakZaczac();
          }
        }
        QfPozycjaMenu {
          text: qsTr("Folder aplikacji")
          polka: "zaawansowana" // [WF-POLKA-ZAAWANSOWANE]
          ikona: "wfg_magazyn"
          onClicked: {
            dashBoard.close();
            photoGallery.openFiles(iface.dataRoot());
          }
        }
        QfPozycjaMenu {
          text: qsTr("Aktualizacja aplikacji")
          ikona: "wfg_aktualizacja"
          onClicked: {
            dashBoard.close();
            Qt.openUrlExternally("https://github.com/ekolabynet/workfield/releases/latest");
          }
        }
        QfPozycjaMenu {
          text: qsTr("Zgłoś uwagę")
          ikona: "wfg_pomoc"
          onClicked: {
            // WorkField: zgloszenie z terenu — mail z gotowym kontekstem
            const adres = "workfield@ekolaby.net";
            const temat = "WorkFieldGIS " + appVersionStr + " — uwaga z terenu";
            const tresc = qsTr("Opisz, co się działo (jedno zdanie wystarczy). Zrzut ekranu bardzo pomaga — dołącz go do tej wiadomości.") + "\n\n\n---\n" + "Wersja: " + appVersionStr + "\n" + "Projekt: " + (mainWindow.projectTitle !== "" ? mainWindow.projectTitle + " (" + FileUtils.fileName(projectSection.filePath) + ")" : FileUtils.fileName(projectSection.filePath)) + "\n" + "System: " + Qt.platform.os + "\n" + "Data: " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm");
            Qt.openUrlExternally("mailto:" + adres + "?subject=" + encodeURIComponent(temat) + "&body=" + encodeURIComponent(tresc));
            displayToast(qsTr("Otwieram szkic zgłoszenia…"));
          }
        }
      }
        }
      }

      // ── Warstwy ─────────────────────────────────────────────
      ColumnLayout {
        spacing: 0

      Text {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.topMargin: 10
          text: qsTr("Dane")
          font: t.strongFont
          color: t.mainTextColor
        }
      QfSiatkaMenu {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        t: dashBoard.t
        szerokosc: dashBoard.width - 16

        QfPozycjaMenu {
          text: qsTr("Nowa warstwa")
          ikona: "wfg_warstwa_nowa"
          onClicked: {
          dashBoard.close();
          newLayerDialog.openDialog();
        }
        }
        QfPozycjaMenu {
          // WorkField 21.09.2026 - jedno wejscie: ekran podkladow i dane
          // wysokosciowe (NMT, NMPT, CHM) za jednymi drzwiami.
          text: qsTr("Podkłady i dane wysokościowe")
          ikona: "wfg_podklad"
          onClicked: oknoPodkladow.otworz(dashBoard)
        }
        QfPozycjaMenu {
          text: qsTr("Dodaj z pliku")
          ikona: "wfg_import"
          onClicked: {
          dashBoard.close();
          dataDrawer.addExistingRequested();
        }
        }
        // WorkField 23.08.2026 — "Teren" stad ZNIKA. Byl w obu szufladach:
        // dodany po prawej w zakladce "Narzedzia", nieusuniety z lewej.
        // Zostaje po prawej, bo tam trafil swiadomie i tam jest w towarzystwie
        // Nieba, edytora i ustawien GNSS. Tutaj byl obcy: sekcja "Dane" mowi
        // o warstwach i plikach, a ustawienia terenowe nie sa ani jednym,
        // ani drugim. Dwa wejscia do tego samego okna to nie wygoda, tylko
        // dwa miejsca, w ktorych trzeba pamietac o zmianie.
        QfPozycjaMenu {
          text: qsTr("Galeria")
          ikona: "wfg_zdjecia"
          onClicked: {
          dashBoard.close();
          photoGallery.openPhotos();
        }
        }
      }
      Text {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.topMargin: 6
          text: qsTr("Aktywna warstwa")
          font: t.tinyFont
          color: t.secondaryTextColor
        }
      QfSiatkaMenu {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        t: dashBoard.t
        szerokosc: dashBoard.width - 16

        QfPozycjaMenu {
          // WorkField 20.09.2026 - "Powieksz do danych" obejmuje caly projekt;
          // tu jedna, aktywna warstwa.
          text: qsTr("Powiększ do warstwy")
          ikona: "wfg_powieksz"
          enabled: dashBoard.activeLayer
          onClicked: {
            const warstwa = dashBoard.activeLayer;
            dashBoard.close();
            if (!iface.zoomToLayer(warstwa, dashBoard.mapSettings))
              displayToast(qsTr("Warstwa %1 nie ma jeszcze obiektów").arg(warstwa.name));
          }
        }
        QfPozycjaMenu {
          text: qsTr("Pola")
          ikona: "wfg_pola"
          enabled: dashBoard.activeLayer
          onClicked: layerFieldsScreen.openFor(dashBoard.activeLayer)
        }
        QfPozycjaMenu {
          text: qsTr("Eksportuj")
          ikona: "wfg_eksport"
          enabled: dashBoard.activeLayer
          onClicked: {
              dashBoard.close();
              exportDialog.openFor(dashBoard.activeLayer);
            }
        }
        QfPozycjaMenu {
          text: qsTr("Usuń")
          ikona: "wfg_usun"
          enabled: dashBoard.activeLayer
          onClicked: {
              removeLayerConfirm.targetLayer = dashBoard.activeLayer;
              removeLayerConfirm.targetName = dashBoard.activeLayer.name;
              removeLayerConfirm.open();
            }
        }
      }

    RowLayout {
      Layout.fillWidth: true
      Layout.margins: 8
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qgisProject && qgisProject.crs && qgisProject.crs.authid !== "" ? qsTr("Warstwa robocza") + "  \u00b7  " + qgisProject.crs.authid : qsTr("Warstwa robocza")
        font: t.strongTipFont
        color: t.mainTextColor
      }

      // WorkField: główny włącznik przyciągania — gasi/wskrzesza całość,
      // stany magnesów per warstwa czekają nietknięte
      QfToolButton {
        id: snapMaster
        width: 30
        height: 30
        padding: 0
        round: true
        readonly property bool wl: qgisProject && qgisProject.snappingConfig.enabled
        bgcolor: wl ? t.mainColor : "transparent"
        iconSource: t.getThemeVectorIcon("ic_snapping_white_24dp")
        iconColor: wl ? "white" : t.secondaryTextColor
        opacity: wl ? 1.0 : 0.45

        onClicked: {
          let cfgM = qgisProject.snappingConfig;
          cfgM.enabled = !cfgM.enabled;
          qgisProject.snappingConfig = cfgM;
          projectInfo.snappingEnabled = cfgM.enabled;
          displayToast(cfgM.enabled ? qsTr("Przyciąganie włączone") : qsTr("Przyciąganie wyłączone"));
        }
      }

      // WorkField 16.09.2026 — TOLERANCJA I JEDNOSTKA.
      //
      // Zwykle `Text` w `MouseArea`, nie QfToolButton: tamten ma tylko
      // ikone i podanie mu `text` wywala okno przy starcie.
      // Stan trzymamy U SIEBIE: `snappingConfig` nie wystawia tolerancji
      // do QML, a odczyt przez czasownik C++ przy kazdym odswiezeniu
      // wiazania bylby marnotrawstwem.
      QtObject {
        id: snapStan

        property real tolerancja: 12
        property int jednostka: 1

        function odswiez() {
          if (!qgisProject || typeof NarzedziaProjektu === "undefined")
            return;
          const u = NarzedziaProjektu.ustawieniaPrzyciagania(qgisProject);
          if (u && u.tolerancja !== undefined) {
            tolerancja = u.tolerancja;
            jednostka = u.jednostka;
          }
        }

        function zapisz(tol, jedn) {
          NarzedziaProjektu.przyciaganie(qgisProject,
                                         { "tolerancja": tol, "jednostka": jedn });
          // `przyciaganie()` zmienia konfiguracje W PAMIECI. Bez zapisu
          // pliku ustawienie ginie przy zamknieciu projektu — a wtedy
          // przelacznik wyglada, jakby dzialal, i nie dziala.
          NarzedziaProjektu.zapiszProjekt(qgisProject);
          odswiez();
        }

        // `Component.onCompleted` odpala sie przy budowie szuflady, a
        // projekt moze byc wtedy jeszcze nie wczytany — wartosci zostawaly
        // domyslne (12 px), choc w pliku bylo co innego. Odswiezamy takze
        // po wczytaniu projektu i przy otwarciu szuflady.
        Component.onCompleted: odswiez()

        property Connections polaczenia: Connections {
          target: iface
          function onLoadProjectEnded(path, name) { snapStan.odswiez(); }
        }
      }

      Text {
        id: snapJednostka
        visible: snapMaster.wl
        text: snapStan.jednostka === 2 ? "m" : "px"
        color: t.mainColor
        font: t.strongFont

        MouseArea {
          anchors.fill: parent
          anchors.margins: -12
          onClicked: {
            // Przy zmianie jednostki dobieramy sensowna wartosc: 12 pikseli
            // i 0,5 metra to progi, przy ktorych przyciaganie pomaga,
            // a nie zlepia.
            if (snapStan.jednostka === 2)
              snapStan.zapisz(12, 1);      // metry -> piksele
            else
              snapStan.zapisz(0.5, 2);     // piksele -> metry mapy
            displayToast(snapStan.jednostka === 2
                         ? qsTr("Przyciąganie w metrach — próg nie zmienia się przy oddalaniu mapy")
                         : qsTr("Przyciąganie w pikselach ekranu"));
          }
        }
      }

      Text {
        visible: snapMaster.wl
        text: snapStan.jednostka === 2
              ? snapStan.tolerancja.toFixed(2)
              : Math.round(snapStan.tolerancja)
        color: t.mainTextColor
        font: t.strongFont

        MouseArea {
          anchors.fill: parent
          anchors.margins: -12

          // Progi dobrane pod TEREN, nie pod ekran: w metrach od 10 cm
          // (wierzcholek do wierzcholka) do 5 m (granica sasiada widziana
          // z daleka). W pikselach jak dotad, bo tam nawyk juz jest.
          readonly property var progiM: [0.1, 0.25, 0.5, 1, 2, 5]
          readonly property var progiPx: [4, 8, 12, 20, 30]

          onClicked: {
            const p = snapStan.jednostka === 2 ? progiM : progiPx;
            let i = 0;
            for (let j = 0; j < p.length; j++)
              if (Math.abs(p[j] - snapStan.tolerancja) < Math.abs(p[i] - snapStan.tolerancja))
                i = j;
            snapStan.zapisz(p[(i + 1) % p.length], snapStan.jednostka);
          }

          // Przytrzymanie wraca do domyslnej — zeby dalo sie wyjsc
          // z eksperymentu jednym gestem, bez liczenia tapniec.
          onPressAndHold: {
            snapStan.zapisz(snapStan.jednostka === 2 ? 0.5 : 12, snapStan.jednostka);
            displayToast(qsTr("Tolerancja domyślna"));
          }
        }
      }
    }

    ListView {
      id: projectLayersList

      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: dashBoard.layerTree

      delegate: ItemDelegate {
        required property int index
        required property var model

        readonly property bool isVector: model.LayerType === "vectorlayer" && model.VectorLayerPointer
        readonly property var mapLayer: model.MapLayerPointer ? model.MapLayerPointer : (model.VectorLayerPointer ? model.VectorLayerPointer : null)
        readonly property string layerKind: mapLayer ? iface.layerKind(mapLayer) : ""
        readonly property bool isLayerRow: mapLayer !== null && model.Name !== undefined && model.Name !== ""
        readonly property bool isWritable: isVector && !model.VectorLayerPointer.readOnly
        readonly property bool isCurrent: isVector && model.VectorLayerPointer === dashBoard.activeLayer

        // geometria jako mikroikona - miejsce oddane nazwie warstwy
        readonly property int geomType: isVector ? model.VectorLayerPointer.geometryType() : -1
        readonly property string geomIcon: geomType === Qgis.GeometryType.Point ? "ic_vectorlayer_point_18dp" : geomType === Qgis.GeometryType.Line ? "ic_vectorlayer_line_18dp" : geomType === Qgis.GeometryType.Polygon ? "ic_vectorlayer_polygon_18dp" : "ic_vectorlayer_table_18dp"
        readonly property string featureCountText: isVector ? String(iface.layerInfoLabel(model.VectorLayerPointer)).split("\u00b7").pop().trim() : ""
        readonly property string layerCrs: isVector && model.VectorLayerPointer.crs ? model.VectorLayerPointer.crs.authid : ""
        // uklad pokazujemy TYLKO, gdy inny niz projektu - wtedy to ostrzezenie
        readonly property bool crsDiffers: layerCrs !== "" && qgisProject && qgisProject.crs && layerCrs !== qgisProject.crs.authid

        width: projectLayersList.width
        height: isLayerRow ? Math.max(44, layerNameText.implicitHeight + 16) : 0
        visible: isLayerRow

        background: Rectangle {
          color: isCurrent ? t.mainColor : "transparent"
        }

        contentItem: RowLayout {
          // 25.09.2026 — odstep 8 -> 4. Osiem przerw miedzy olowkiem,
          // nazwa, ikona geometrii, licznikiem, magnesem, okiem,
          // etykietami i koszem zjadalo 64 px z 350 px szuflady.
          // Same przyciski brały 202 px, wiec nazwie zostawalo 84 —
          // siedem znakow. Po zmianie 116, czyli dziesiec.
          //
          // Nizej niz 4 nie schodzic: przyciski maja po 30 px i sa
          // celami dotyku; zetkniete krawedziami zaczyna sie mylic
          // sasiadow, a to sie robi w rekawicy.
          spacing: 4

          // olowek: wybor warstwy do edycji (zastapil przelacznik trybu)
          QfToolButton {
            Layout.leftMargin: 4
            width: 30
            height: 30
            padding: 0
            enabled: isWritable
            round: true

            // warstwa, w ktorej wlasnie rysujemy: jasnozielone kolo z olowkiem
            readonly property bool rysujemy: isCurrent && stateMachine.state === "digitize"

            iconSource: t.getThemeVectorIcon("ic_create_white_24dp")
            bgcolor: rysujemy ? "#00E676" : "transparent"
            iconColor: rysujemy ? "#062E12" : isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: !isWritable ? 0.25 : rysujemy ? 1.0 : isCurrent ? 0.9 : 0.55

            // Cała logika mieszka w dashBoard.przelaczRysowanie() — ten sam
            // kod obsługuje ołówek na górnej belce.
            onClicked: dashBoard.przelaczRysowanie(model.VectorLayerPointer, model.Name)
          }

          // NAZWA WARSTWY (25.09.2026) — jedna linia, skrot w SRODKU.
          //
          // Bylo: `Text.Wrap` + dwie linie + `ElideRight`, czyli lamanie
          // w srodku slowa ORAZ ucinanie konca naraz („Symb / ole z…").
          // `Text.Wrap` znaczy „lam na spacjach, a jak sie nie da, to
          // gdziekolwiek" — przy ~84 px na nazwe „nie da sie" bylo regula.
          //
          // ElideMiddle, a nie ElideRight, bo w projekcie CAD sa warstwy
          // roznaice sie WYLACZNIE koncowka („Rysunek — linie" kontra
          // „Rysunek — poligony"). ElideRight pokazywal obie identycznie.
          // Qt przy `maximumLineCount` dopuszcza tylko ElideRight, wiec
          // dwulinijkowosc i skrot w srodku sie wykluczaja — wybor padl
          // na to, zeby dalo sie odroznic warstwy od siebie.
          //
          // Skutek uboczny: wiersz nie rosnie juz do dwoch linii, wiec
          // `Math.max(44, ...)` daje rowne 44 px dla kazdej warstwy.
          Text {
            id: layerNameText
            Layout.fillWidth: true
            text: model.Name
            font: t.tipFont
            color: isCurrent ? t.mainOverlayColor : t.mainTextColor
            elide: Text.ElideMiddle
          }

          // uklad odmienny od projektu: krotkie ostrzezenie tekstem
          Text {
            visible: crsDiffers
            text: layerCrs
            font: t.tinyFont
            color: t.warningColor
          }

          QfToolButton {
            visible: isVector
            width: 18
            height: 18
            padding: 0
            enabled: false
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon(geomIcon)
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: 0.85
          }

          Text {
            text: isVector ? featureCountText : layerKind === "podklad" ? qsTr("PODKŁAD") : layerKind === "raster" ? qsTr("RASTER") : ""
            font: t.tinyFont
            color: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: 0.7
          }

          QfToolButton {
            visible: isVector && !isWritable
            width: 18
            height: 18
            padding: 0
            enabled: false
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_lock_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: 0.6
          }

          // WorkField: magnes — dociąganie do tej warstwy jako podkładu.
          // Świeci, gdy warstwa FAKTYCZNIE dociąga: w trybie magnesów wg
          // ustawienia warstwy, w trybie domyślnym — gdy właśnie w niej
          // rysujemy (rysowana warstwa zawsze dociąga sama do siebie).
          QfToolButton {
            id: snapToggle
            visible: isVector && (geomType === Qgis.GeometryType.Point || geomType === Qgis.GeometryType.Line || geomType === Qgis.GeometryType.Polygon)
            width: 30
            height: 30
            padding: 0
            round: true
            readonly property bool trybMagnesow: qgisProject && qgisProject.snappingConfig.mode === Qgis.SnappingMode.AdvancedConfiguration
            readonly property bool przyciaga: qgisProject && qgisProject.snappingConfig.enabled && (trybMagnesow ? model.SnappingEnabled === true : isCurrent && stateMachine.state === "digitize")
            bgcolor: przyciaga ? t.mainColor : "transparent"
            iconSource: t.getThemeVectorIcon("ic_snapping_white_24dp")
            iconColor: przyciaga ? "white" : isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: przyciaga ? 1.0 : 0.45

            onClicked: dashBoard.przelaczMagnesWarstwy(model.VectorLayerPointer, model.Name)
          }

          QfToolButton {
            id: selectableToggle
            width: 30
            height: 30
            padding: 0
            bgcolor: "transparent"
            property bool selectable: isVector ? iface.layerSelectable(model.VectorLayerPointer) : true
            iconSource: t.getThemeVectorIcon(selectable ? "ic_show_green_48dp" : "ic_hide_green_48dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor
            opacity: selectable ? 1.0 : 0.35
            onClicked: {
              const next = !selectable;
              iface.setLayerSelectable(model.VectorLayerPointer, next);
              selectable = next;
              displayToast(next ? qsTr("%1: reaguje na dotknięcie").arg(model.Name) : qsTr("%1: nie reaguje na dotknięcie").arg(model.Name));
            }
          }

          QfToolButton {
            width: 30
            height: 30
            padding: 0
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_edit_attributes_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor

            onClicked: {
              dashBoard.close();
              layerFieldsScreen.openFor(model.VectorLayerPointer);
            }
          }

          QfToolButton {
            Layout.rightMargin: 4
            width: 30
            height: 30
            padding: 0
            bgcolor: "transparent"
            iconSource: t.getThemeVectorIcon("ic_delete_forever_white_24dp")
            iconColor: isCurrent ? t.mainOverlayColor : t.secondaryTextColor

            onClicked: {
              removeLayerConfirm.targetLayer = mapLayer;
              removeLayerConfirm.targetName = model.Name;
              removeLayerConfirm.open();
            }
          }
        }

        onClicked: {
          if (isWritable)
            dashBoard.activeLayer = model.VectorLayerPointer;
        }
      }
    }

      }

      // ── Legenda ─────────────────────────────────────────────
      ColumnLayout {
        spacing: 0

        RowLayout {
          Layout.fillWidth: true
          Layout.margins: 8

          Text {
            Layout.fillWidth: true
            text: qsTr("Stylizacja warstw")
            font: Theme.strongTipFont
            color: Theme.mainTextColor
          }

          QfButton {
            visible: legend.model && legend.model.hasCollapsibleItems
            text: legend.model && legend.model.isCollapsed ? qsTr("Rozwiń") : qsTr("Zwiń")
            bgcolor: "transparent"
            color: Theme.mainTextColor
            font.pointSize: Theme.tinyFont.pointSize

            onClicked: {
              legend.model.setAllCollapsed(!legend.model.isCollapsed);
              projectInfo.saveLayerTreeState();
            }
          }
        }

        QfSiatkaMenu {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.rightMargin: 8
          t: dashBoard.t
          szerokosc: dashBoard.width - 16

          QfPozycjaMenu {
            text: qsTr("Zapisz styl")
            polka: "zaawansowana" // [WF-POLKA-ZAAWANSOWANE]
            ikona: "wfg_zapisz"
            enabled: dashBoard.activeLayer !== null && qgisProject && qgisProject.homePath !== ""
            onClicked: {
              const wynik = procesyStylu.zapiszStyl(dashBoard.activeLayer, qgisProject.homePath);
              displayToast(wynik.startsWith("BLAD") ? wynik : qsTr("Styl zapisany: %1").arg(FileUtils.fileName(wynik)));
            }
          }
          QfPozycjaMenu {
            text: qsTr("Wczytaj styl")
            polka: "zaawansowana" // [WF-POLKA-ZAAWANSOWANE]
            ikona: "wfg_otworz"
            enabled: dashBoard.activeLayer !== null
            onClicked: dialogStylu.open()
          }
        }
        ProcesyStudio {
          id: procesyStylu
        }
        FileDialog {
          id: dialogStylu
          title: qsTr("Wczytaj styl warstwy")
          nameFilters: [qsTr("Styl QGIS (*.qml)"), qsTr("Wszystkie pliki (*)")]
          onAccepted: {
            const wynik = procesyStylu.wczytajStyl(dashBoard.activeLayer, String(selectedFile).replace(/^file:\/\//, ""));
            displayToast(wynik === "" ? qsTr("Styl wczytany") : wynik);
          }
        }

        QfLegend {
          id: legend
          objectName: "legend"

          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.leftMargin: mainWindow.sceneLeftMargin + 5
          Layout.rightMargin: 5
          isVisible: dashBoard.position > 0
        }
      }

    }

    
  }

  Popup {
    id: projectNameDialog

    property string mode: "blank"

    function openFor(newMode) {
      mode = newMode;
      metZleceniodawca.text = ""; // WF-METRYCZKA-CZYSC
      metTeren.text = "";
      metZlecenie.text = "";
      projectNameField.text = (mode === "blank" ? qsTr("Projekt") : FileUtils.fileName(projectSection.filePath).replace(/\.(qgs|qgz)$/, "") + " kopia") + " " + new Date().toISOString().slice(0, 10);
      open();
    }

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 400)
    modal: true

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: projectNameDialog.mode === "blank" ? qsTr("Nowy projekt") /* WF-NOWY-TYTUL */
            : projectNameDialog.mode === "szablon" ? qsTr("Zapisz jako szablon")
            : qsTr("Zapisz projekt jako")
        font: t.strongFont
        color: t.mainTextColor
      }

      TextField {
        id: projectNameField
        Layout.fillWidth: true
        font: t.defaultFont
      }

      // WorkField 6.10.2026 [WF-METRYCZKA] — nieobowiązkowa. Wypełniona
      // trafia do ZADANIE.json i posłuży do grupowania projektów.
      Text {
        Layout.fillWidth: true
        visible: projectNameDialog.mode === "blank"
        text: qsTr("Metryczka — nieobowiązkowa. Wypełniona pozwoli później grupować projekty.")
        font: t.tipFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }
      TextField {
        id: metZleceniodawca
        Layout.fillWidth: true
        visible: projectNameDialog.mode === "blank"
        font: t.defaultFont
        placeholderText: qsTr("Zleceniodawca")
      }
      TextField {
        id: metTeren
        Layout.fillWidth: true
        visible: projectNameDialog.mode === "blank"
        font: t.defaultFont
        placeholderText: qsTr("Teren")
      }
      TextField {
        id: metZlecenie
        Layout.fillWidth: true
        visible: projectNameDialog.mode === "blank"
        font: t.defaultFont
        placeholderText: qsTr("Zlecenie")
      }

      RowLayout {
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }
        Button {
          flat: true
          text: qsTr("Anuluj")
          font.pointSize: t.tinyFont.pointSize
          onClicked: projectNameDialog.close()
        }
        Button {
          flat: true
          text: qsTr("Utwórz")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            const name = projectNameField.text.trim();
            if (name === "") {
              return;
            }
            const safeName = FileUtils.sanitizeFilePathPart(name);
            const root = welcomeScreen.templatesDataRoot();
            platformUtilities.createDir(root, "Imported Projects");
            const destination = root + "Imported Projects/" + safeName;
            // ---- zapis jako szablon: sam przepis, bez danych i bez zdjec
            if (projectNameDialog.mode === "szablon") {
              // korzeniem jest magazyn, nie katalog aplikacji — patrz QfNoweZadanie
              // to samo martwe odwolanie co przy "Otworz projekt" — przez nie
              // "Zapisz jako szablon" przerywalo sie w pierwszej linijce
              const korzenSzablonow = NarzedziaProjektu.katalogSzablonow(drzewoZlecen.korzen);
              if (korzenSzablonow === "") {
                displayToast(qsTr("Nie znalazłem katalogu szablonów"), "error");
                return;
              }
              const celSzablonu = korzenSzablonow + "/" + safeName;
              if (FileUtils.fileExists(celSzablonu + "/przepis.json")) {
                displayToast(qsTr("Szablon %1 już istnieje").arg(safeName), "error");
                return;
              }
              const przepis = NarzedziaProjektu.zrzucPrzepis(qgisProject);
              if (!przepis || !przepis.warstwy || przepis.warstwy.length === 0) {
                displayToast(qsTr("Nie udało się odczytać struktury projektu"), "error");
                return;
              }
              przepis.id = safeName;
              // kafle paska to tresc branzowa — jada w przepisie, zeby szablon
              // byl samowystarczalny (dziesiec kilobajtow zamiast gigabajtow)
              const trescKlawiszy = NarzedziaProjektu.czytajTekst(qgisProject.homePath + "/workfield_klawisze.json");
              if (trescKlawiszy !== "") {
                try {
                  przepis.pliki = [{
                    "nazwa": "workfield_klawisze.json",
                    "tresc": JSON.parse(trescKlawiszy)
                  }];
                } catch (e) {}
              }
              platformUtilities.createDir(korzenSzablonow, safeName);
              if (NarzedziaProjektu.zapiszTekst(celSzablonu + "/przepis.json", JSON.stringify(przepis, null, 2))) {
                displayToast(qsTr("Szablon %1 zapisany — %2 warstw").arg(safeName).arg(przepis.warstwy.length));
              } else {
                displayToast(qsTr("Nie udało się zapisać przepisu"), "error");
              }
              projectNameDialog.close();
              return;
            }

            if (projectNameDialog.mode === "blank") {
              // WorkField 6.10.2026 [WF-NOWY-KATALOG] — ta sama reguła co
              // „Nowe zlecenie” po poprawce z 29.09: na Androidzie „Imported
              // Projects” (lista projektów, menedżer plików, kabel), na
              // komputerze katalog zadań magazynu (~/WorkField/wydania).
              // Dotąd pusty projekt szedł zawsze do iface.dataRoot().
              let katalogNowych = Qt.platform.os === "android"
                ? root + "Imported Projects"
                : NarzedziaProjektu.katalogZadan(drzewoZlecen.korzen);
              if (katalogNowych === "")
                katalogNowych = root + "Imported Projects";
              const celNowego = katalogNowych + "/" + safeName;
              if (FileUtils.fileExists(celNowego + "/projekt.qgs")) {
                displayToast(qsTr("Projekt %1 już istnieje — zmień nazwę").arg(safeName), "error");
                return;
              }
              platformUtilities.createDir(katalogNowych, safeName);
              const centerPoints = iface.visibleExtentPointsIn2180(dashBoard.mapSettings, 2);
              dashBoard.pendingBlankCenter = centerPoints.length > 4 ? centerPoints[4] : null;
              dashBoard.pendingBlankSetup = true;
              dashBoard.pendingMetryczka = {
                "zleceniodawca": metZleceniodawca.text.trim(),
                "teren": metTeren.text.trim(),
                "zlecenie": metZlecenie.text.trim()
              };
              if (iface.createBlankProject(celNowego + "/projekt.qgs")) {
                dataDrawer.close();
                iface.loadFile(celNowego + "/projekt.qgs", name);
              } else {
                displayToast(qsTr("Nie udało się utworzyć projektu"));
              }
            } else {
              // Zapis PRZED kopiowaniem — inaczej kopia dostaje stara
              // tresc, a czlowiek komunikat o sukcesie. Nie kopiujemy,
              // gdy zapis zawiodl: lepiej nic niz cicha polowa.
              if (!ProjectUtils.saveProject(qgisProject)) {
                displayToast(qsTr("Nie zapisano projektu — kopia nie powstala"), "error");
                return;
              }
              const sourceDir = FileUtils.absolutePath(projectSection.filePath);
              if (FileUtils.copyRecursively(sourceDir, destination)) {
                dataDrawer.close();
                iface.loadFile(destination + "/" + FileUtils.fileName(projectSection.filePath), name);
              } else {
                displayToast(qsTr("Nie udało się skopiować projektu"));
              }
            }
            projectNameDialog.close();
          }
        }
      }
    }
  }

  Popup {
    id: deleteProjectConfirm

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 400)
    modal: true

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Usunąć projekt wraz z danymi?")
        font: t.strongFont
        color: t.mainTextColor
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Usunięty zostanie cały folder projektu, łącznie z warstwami i zdjęciami. Tej operacji nie można cofnąć.")
        font: t.tipFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }
        Button {
          flat: true
          text: qsTr("Anuluj")
          font.pointSize: t.tinyFont.pointSize
          onClicked: deleteProjectConfirm.close()
        }
        Button {
          flat: true
          text: qsTr("Usuń")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            const dir = FileUtils.absolutePath(projectSection.filePath);
            deleteProjectConfirm.close();
            dataDrawer.close();
            if (iface.removeProjectFolder(dir)) {
              displayToast(qsTr("Projekt usunięty"));
              welcomeScreen.visible = true;
            } else {
              displayToast(qsTr("Nie udało się usunąć projektu"));
            }
          }
        }
      }
    }
  }

  Popup {
    id: projectPropertiesPopup

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 440)
    modal: true

    onOpened: {
      projectTitleField.text = iface.projectTitle();
      objectNameField.text = iface.projectVariable("obiekt_nazwa");
      objectShortField.text = iface.projectVariable("obiekt_skrot");
      objectCategoryField.text = iface.projectVariable("obiekt_kategoria");
      crsCurrentLabel.refresh();
      customCrsField.text = "";
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Właściwości projektu")
        font: t.strongFont
        color: t.mainTextColor
      }

      Text {
        text: qsTr("Tytuł projektu:")
        font: t.tipFont
        color: t.secondaryTextColor
      }

      TextField {
        id: projectTitleField
        Layout.fillWidth: true
        font: t.defaultFont
      }

      Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: qsTr("Obiekt (dostępne w wyrażeniach jako @obiekt_nazwa, @obiekt_skrot, @obiekt_kategoria)")
        font: t.tipFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        TextField {
          id: objectNameField
          Layout.fillWidth: true
          font: t.defaultFont
          placeholderText: qsTr("Nazwa obiektu")
          onEditingFinished: iface.setProjectVariable("obiekt_nazwa", text.trim())
        }

        TextField {
          id: objectShortField
          Layout.preferredWidth: 90
          font: t.defaultFont
          placeholderText: qsTr("Skrót")
          onEditingFinished: iface.setProjectVariable("obiekt_skrot", text.trim().toUpperCase())
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: qsTr("Kategoria:")
          font: t.tipFont
          color: t.secondaryTextColor
        }

        TextField {
          id: objectCategoryField
          Layout.fillWidth: true
          font: t.defaultFont
          placeholderText: qsTr("APPL / SCI / …")
          onEditingFinished: iface.setProjectVariable("obiekt_kategoria", text.trim().toUpperCase())
        }
      }

      Text {
        id: crsCurrentLabel

        function refresh() {
          text = qsTr("Układ współrzędnych: %1 (%2)").arg(iface.projectCrsAuthid()).arg(iface.projectCrsDescription());
        }

        Layout.fillWidth: true
        font: t.tipFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      ComboBox {
        id: crsCombo
        Layout.fillWidth: true
        font: t.tinyFont
        textRole: "label"
        valueRole: "authid"
        model: [
          { "label": qsTr("— wybierz układ —"), "authid": "" },
          { "label": "PL-1992 (EPSG:2180)", "authid": "EPSG:2180" },
          { "label": "PL-2000 strefa 5 (EPSG:2176)", "authid": "EPSG:2176" },
          { "label": "PL-2000 strefa 6 (EPSG:2177)", "authid": "EPSG:2177" },
          { "label": "PL-2000 strefa 7 (EPSG:2178)", "authid": "EPSG:2178" },
          { "label": "PL-2000 strefa 8 (EPSG:2179)", "authid": "EPSG:2179" },
          { "label": "WGS 84 (EPSG:4326)", "authid": "EPSG:4326" },
          { "label": "Web Mercator (EPSG:3857)", "authid": "EPSG:3857" }
        ]
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: qsTr("Inny EPSG:")
          font: t.tipFont
          color: t.secondaryTextColor
        }

        TextField {
          id: customCrsField
          Layout.fillWidth: true
          font: t.tinyFont
          placeholderText: qsTr("np. 25832")
          inputMethodHints: Qt.ImhDigitsOnly
        }
      }

      /**
       * WorkField 23.08.2026 — sciezka projektu do skopiowania.
       *
       * Byla tu zwykla etykieta z ElideMiddle: sciezka, ktorej nie da sie ani
       * zaznaczyc, ani nawet przeczytac w calosci. A jest to dokladnie ten
       * napis, ktory czlowiek chce wkleic do terminala albo do wiadomosci.
       * Zaznaczanie myszka dziala na komputerze, przyciski dzialaja wszedzie.
       */
      Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: qsTr("Plik projektu:")
        font: t.tipFont
        color: t.secondaryTextColor
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 4

        TextEdit {
          Layout.fillWidth: true
          text: projectSection.filePath
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.WrapAnywhere
          font: t.tinyFont
          color: t.mainTextColor
        }

        QfToolButton {
          Layout.alignment: Qt.AlignTop
          round: true
          bgcolor: "transparent"
          iconSource: t.getThemeVectorIcon("ic_copy_black_24dp")
          iconColor: t.mainTextColor
          onClicked: {
            platformUtilities.copyTextToClipboard(projectSection.filePath);
            displayToast(qsTr("Skopiowano ścieżkę projektu"));
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
          Layout.fillWidth: true
          text: qsTr("Folder: %1").arg(FileUtils.absolutePath(projectSection.filePath))
          font: t.tinyFont
          color: t.secondaryTextColor
          elide: Text.ElideMiddle
        }

        QfToolButton {
          round: true
          bgcolor: "transparent"
          iconSource: t.getThemeVectorIcon("ic_copy_black_24dp")
          iconColor: t.secondaryTextColor
          onClicked: {
            platformUtilities.copyTextToClipboard(FileUtils.absolutePath(projectSection.filePath));
            displayToast(qsTr("Skopiowano ścieżkę folderu"));
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Pliki danych w folderze:")
        font: t.tipFont
        color: t.secondaryTextColor
      }

      ListView {
        id: projectFilesList
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 110)
        clip: true

        model: FolderListModel {
          id: projectFilesModel
          folder: projectPropertiesPopup.opened ? "file://" + FileUtils.absolutePath(projectSection.filePath) : ""
          nameFilters: ["*.gpkg", "*.qgs", "*.qgz"]
          showDirs: false
        }

        delegate: Text {
          width: projectFilesList.width
          text: "• " + fileName + "  (" + FileUtils.representFileSize(fileSize) + ")"
          font: t.tinyFont
          color: t.mainTextColor
          elide: Text.ElideMiddle
        }
      }

      RowLayout {
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }
        Button {
          flat: true
          text: qsTr("Zamknij")
          font.pointSize: t.tinyFont.pointSize
          onClicked: projectPropertiesPopup.close()
        }
        Button {
          flat: true
          text: qsTr("Zastosuj i zapisz")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            iface.setProjectTitle(projectTitleField.text);
            mainWindow.refreshProjectTitle();
            let requestedCrs = customCrsField.text.trim() !== "" ? "EPSG:" + customCrsField.text.trim() : crsCombo.currentValue;
            if (requestedCrs && requestedCrs !== "" && requestedCrs !== iface.projectCrsAuthid()) {
              if (!iface.setProjectCrs(requestedCrs)) {
                displayToast(qsTr("Nieprawidłowy układ: %1").arg(requestedCrs));
                return;
              }
            }
            // Zapis pliku potrafi zawiesc: brak miejsca, plik tylko do
            // odczytu, nosnik odlaczony. Do 18.09.2026 wynik szedl w
            // proznie, a toast mowil "Zapisano" bezwarunkowo.
            const zapisano = ProjectUtils.saveProject(qgisProject);
            crsCurrentLabel.refresh();
            projectSection.refresh();
            if (zapisano) {
              displayToast(qsTr("Zapisano właściwości projektu"));
              projectPropertiesPopup.close();
            } else {
              displayToast(qsTr("NIE zapisano właściwości — projekt został bez zmian"), "error");
            }
          }
        }
      }
    }
  }

  Popup {
    id: removeLayerConfirm

    property var targetLayer: null
    property string targetName: ""

    parent: mainWindow.contentItem
    width: Math.min(380, mainWindow.width - 32)
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    modal: true
    closePolicy: Popup.CloseOnEscape

    ColumnLayout {
      anchors.fill: parent
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: qsTr("Usunąć warstwę z projektu?")
        font: t.strongFont
        color: t.mainTextColor
        wrapMode: Text.WordWrap
      }

      Text {
        Layout.fillWidth: true
        text: removeLayerConfirm.targetName
        font: t.tipFont
        color: t.secondaryTextColor
        elide: Text.ElideMiddle
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Plik z danymi pozostanie na dysku.")
        font: t.tinyFont
        color: t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 8

        Button {
          flat: true
          Layout.fillWidth: true
          text: qsTr("Anuluj")
          onClicked: removeLayerConfirm.close()
        }

        Button {
          flat: true
          Layout.fillWidth: true
          text: qsTr("Usuń")
          highlighted: true

          onClicked: {
            if (removeLayerConfirm.targetLayer) {
              iface.removeLayer(removeLayerConfirm.targetLayer);
              displayToast(qsTr("Usunięto warstwę %1").arg(removeLayerConfirm.targetName));
            }
            removeLayerConfirm.close();
          }
        }
      }
    }
  }
}
