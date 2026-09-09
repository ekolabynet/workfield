import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.qgis
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * WorkField 09.09.2026 — menedzer plikow.
 *
 * Powod istnienia: od Androida 11 zaden systemowy menedzer nie widzi
 * `Android/data`. Wszystko, co aplikacja trzyma — kopie bazy, zdjecia,
 * stare wydania — jest z telefonu niedostepne inaczej niz przez nia sama.
 *
 * Czasowniki byly juz wystawione (`renameFile`, `rmFile`, `createDir`,
 * `copyRecursively`, `exportDatasetTo`, `sendCompressedFilesTo`).
 * Brakowalo wylacznie listowania katalogu — to daje FolderListModel.
 *
 * Zasady, ktore ten ekran wykonuje:
 *  - NIC NIE GINIE. Kasowanie to przeniesienie do `.kosz/` w korzeniu.
 *    Oproznianie kosza jest osobna czynnoscia, w innym miejscu.
 *  - Sciezka zrodlowa zapisana w NAZWIE pliku w koszu (`/` → `__`),
 *    a nie w osobnym spisie — `FileUtils.readFileContent` czyta tylko
 *    z katalogu otwartego projektu, wiec spis w koszu bylby nieczytelny.
 *  - Pliki otwartego projektu sa NIETYKALNE, nie ostrzegane. Aplikacja
 *    trzyma je otwarte; odmowa jest uczciwsza od pytania.
 *  - Edycja idzie na KOPII (`.roboczy`). Podmiana nie niszczy oryginalu,
 *    tylko nadaje mu nazwe `.poprzednia_RRRRMMDD_GGMM` — jest „Przywroc".
 */
Popup {
  id: menedzer

  parent: mainWindow.contentItem
  width: Math.min(760, mainWindow.width - 16)
  height: Math.min(880, mainWindow.height - 24)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: Popup.CloseOnEscape

  // --- stan ---------------------------------------------------------
  property string korzen: ""
  property string sciezka: ""
  property string schowek: ""
  property string schowekTryb: "" // "kopiuj" | "wytnij"
  property bool schowekKatalog: false
  property var historia: []
  property int wHistorii: -1
  property string komunikat: ""
  property bool blad: false

  readonly property string kosz: korzen + "/.kosz"
  readonly property bool wKoszu: sciezka.indexOf("/.kosz") >= 0

  // --- korzen z ustawien, domyslnie folder aplikacji -----------------
  function domyslnyKorzen() {
    var k = "";
    try {
      k = settings.value("WorkField/korzenPlikow", "");
    } catch (e) {
      k = "";
    }
    // appDataDirs() wskazuje na `files/QField/` — o poziom za gleboko.
    // Korzeniem jest `files`, bo jego dziecmi sa i `Imported Projects`
    // (zlecenia, zdjecia, kopie), i `QField` (auth, fonts, proj, plugins).
    // Zwraca DWA katalogi: pamiec wewnetrzna i karte SD.
    if (k === "" && platformUtilities.appDataDirs !== undefined) {
      var d = platformUtilities.appDataDirs();
      if (d && d.length > 0)
        k = String(d[0]).replace(/\/+$/, "").replace(/\/QField$/, "");
    }
    if (k === "" && qgisProject && qgisProject.homePath !== "") {
      var m = String(qgisProject.homePath).match(/^(.*\/files)\//);
      k = m ? m[1] : qgisProject.homePath;
    }
    return k;
  }

  function idzDo(nowa) {
    if (nowa === sciezka)
      return;
    historia = historia.slice(0, wHistorii + 1);
    historia.push(nowa);
    wHistorii = historia.length - 1;
    sciezka = nowa;
  }

  function otworz() {
    korzen = domyslnyKorzen();
    // Start w katalogu otwartego projektu — tam sie pracuje. Korzen jest
    // wyzej, wiec "W gore" prowadzi do pozostalych zlecen.
    sciezka = qgisProject && qgisProject.homePath !== "" ? qgisProject.homePath : korzen;
    historia = [sciezka];
    wHistorii = 0;
    komunikat = "";
    blad = false;
    open();
  }

  // --- pomocnicze ----------------------------------------------------
  function nazwaZe(s) {
    return String(s).replace(/\/+$/, "").replace(/^.*\//, "");
  }

  function rodzic(s) {
    var p = String(s).replace(/\/+$/, "");
    var i = p.lastIndexOf("/");
    return i > 0 ? p.substring(0, i) : p;
  }

  function znacznik() {
    var d = new Date();
    function dw(n) {
      return ("0" + n).slice(-2);
    }
    return "" + d.getFullYear() + dw(d.getMonth() + 1) + dw(d.getDate()) + "_" + dw(d.getHours()) + dw(d.getMinutes());
  }

  function rozmiar(b) {
    if (b === undefined || b === null)
      return "—";
    if (b < 1024)
      return b + " B";
    if (b < 1048576)
      return (b / 1024).toFixed(1) + " kB";
    if (b < 1073741824)
      return (b / 1048576).toFixed(1) + " MB";
    return (b / 1073741824).toFixed(2) + " GB";
  }

  function tekstowy(n) {
    // .qgs to zwykly XML — kopie projektu maja byc do obejrzenia.
    // .qgz odpada: to zip. .gpkg tez: binarna baza.
    return /\.(json|txt|md|csv|qml|log|xml|qgs)$/i.test(n);
  }

  /** FileUtils.readFileContent czyta TYLKO z katalogu otwartego projektu
      (bariera bezpieczenstwa QFielda, log: "outside project directory").
      Poza nim edycja jest niemozliwa — wiec nie pokazujemy jej w menu. */
  function edytowalny(nazwa, pelna) {
    return tekstowy(nazwa) && qgisProject && qgisProject.homePath !== "" && String(pelna).indexOf(qgisProject.homePath + "/") === 0;
  }

  /** Pliki, ktorych aplikacja uzywa TERAZ. Odmowa, nie ostrzezenie. */
  function zablokowany(nazwa, pelna) {
    if (!qgisProject || qgisProject.homePath === "")
      return "";
    // TYLKO pliki lezace WPROST w katalogu projektu. Kopie w `kopie/`,
    // zdjecia w `DCIM/` i stare wydania nie sa w uzyciu — pierwsza wersja
    // lapala je wzorcem `*.gpkg` i blokowala wszystko.
    if (String(pelna) !== qgisProject.homePath + "/" + nazwa)
      return "";
    if (/^dane\.gpkg(-wal|-shm)?$/i.test(nazwa))
      return qsTr("baza otwartego projektu");
    if (/^projekt\.qgs$/i.test(nazwa))
      return qsTr("plik otwartego projektu");
    return "";
  }


  function powiedz(t, jestBlad) {
    komunikat = t;
    blad = jestBlad === true;
    // NIE przestawiac plikiModel.folder — to zrywa wiazanie z `sciezka`
    // na stale i po pierwszym komunikacie lista przestaje reagowac.
    // FolderListModel sam obserwuje katalog.
  }

  // --- czasowniki -----------------------------------------------------
  function doKosza(nazwa, pelna, jestKatalogiem) {
    var powod = zablokowany(nazwa, pelna);
    if (powod !== "") {
      powiedz(qsTr("Nie usunieto — %1.").arg(powod), true);
      return;
    }
    if (!platformUtilities.createDir(korzen, ".kosz")) {
      // katalog moze juz istniec — to nie jest blad
    }
    var wzgledna = String(pelna).indexOf(korzen) === 0 ? String(pelna).substring(korzen.length + 1) : nazwa;
    var cel = kosz + "/" + znacznik() + "__" + wzgledna.replace(/\//g, "__");
    if (cel.length > 240)
      cel = kosz + "/" + znacznik() + "__" + nazwa;
    if (platformUtilities.renameFile(pelna, cel, false))
      powiedz(qsTr("Do kosza: %1").arg(nazwa));
    else
      powiedz(qsTr("Nie udalo sie przeniesc %1 do kosza.").arg(nazwa), true);
  }

  function przywroc(nazwa, pelna) {
    var i = String(nazwa).indexOf("__");
    if (i < 0) {
      powiedz(qsTr("Nie wiadomo, skad ten plik pochodzi."), true);
      return;
    }
    var cel = korzen + "/" + String(nazwa).substring(i + 2).replace(/__/g, "/");
    if (platformUtilities.renameFile(pelna, cel, false))
      powiedz(qsTr("Przywrocono do %1").arg(cel.replace(korzen + "/", "")));
    else
      powiedz(qsTr("Nie udalo sie przywrocic — czy cel juz istnieje?"), true);
  }

  function wklej() {
    if (schowek === "")
      return;
    var cel = sciezka + "/" + nazwaZe(schowek);
    if (cel === schowek) {
      powiedz(qsTr("Zrodlo i cel to to samo miejsce."), true);
      return;
    }
    // renameFile przenosi (jedno wywolanie, bez kopiowania bajtow).
    // copyRecursively radzi sobie i z plikiem, i z katalogiem; wipeDestFolder
    // MUSI byc false, inaczej wklejenie do istniejacego folderu go czysci.
    var ok = schowekTryb === "wytnij" ? platformUtilities.renameFile(schowek, cel, false) : FileUtils.copyRecursively(schowek, cel, null, false);
    if (ok) {
      powiedz(schowekTryb === "wytnij" ? qsTr("Przeniesiono.") : qsTr("Skopiowano."));
      schowek = "";
      schowekTryb = "";
    } else {
      powiedz(qsTr("Nie udalo sie. Czy plik o tej nazwie juz tu jest?"), true);
    }
  }

  function edytujKopie(nazwa, pelna) {
    var roboczy = pelna + ".roboczy";
    var tresc = "";
    try {
      tresc = FileUtils.readFileContent(pelna);
    } catch (e) {
      powiedz(qsTr("Nie udalo sie odczytac pliku."), true);
      return;
    }
    if (tresc === undefined || tresc === null) {
      powiedz(qsTr("Plik pusty albo nieczytelny."), true);
      return;
    }
    FileUtils.writeFileContent(roboczy, tresc);
    if (!FileUtils.fileExists(roboczy)) {
      powiedz(qsTr("Nie udalo sie zrobic kopii roboczej."), true);
      return;
    }
    textEditor.wczytaj(roboczy);
    textEditor.open();
  }


  function podmien(nazwa, pelna) {
    var oryginal = String(pelna).replace(/\.roboczy$/, "");
    var odlozony = oryginal + ".poprzednia_" + znacznik();
    if (!platformUtilities.renameFile(oryginal, odlozony, false)) {
      powiedz(qsTr("Nie udalo sie odlozyc oryginalu — nic nie zmieniono."), true);
      return;
    }
    if (platformUtilities.renameFile(pelna, oryginal, false))
      powiedz(qsTr("Podmieniono. Poprzednia wersja: %1").arg(nazwaZe(odlozony)));
    else {
      platformUtilities.renameFile(odlozony, oryginal, false);
      powiedz(qsTr("Podmiana nie doszla do skutku — oryginal na miejscu."), true);
    }
  }

  // --- model ----------------------------------------------------------
  FolderListModel {
    id: plikiModel
    folder: menedzer.sciezka !== "" ? "file://" + menedzer.sciezka : ""
    showDirs: true
    showDirsFirst: true
    showDotAndDotDot: false
    showHidden: true
    sortField: FolderListModel.Name
  }

  // --- widok ----------------------------------------------------------
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      ToolButton {
        text: qsTr("\u2190 Wstecz")
        font: Theme.tinyFont
        enabled: menedzer.wHistorii > 0
        onClicked: {
          menedzer.wHistorii--;
          menedzer.sciezka = menedzer.historia[menedzer.wHistorii];
        }
      }

      ToolButton {
        text: qsTr("Dalej \u2192")
        font: Theme.tinyFont
        enabled: menedzer.wHistorii >= 0 && menedzer.wHistorii < menedzer.historia.length - 1
        onClicked: {
          menedzer.wHistorii++;
          menedzer.sciezka = menedzer.historia[menedzer.wHistorii];
        }
      }

      ToolButton {
        text: qsTr("\u2191 W gore")
        font: Theme.tinyFont
        enabled: menedzer.sciezka !== menedzer.korzen
        onClicked: menedzer.idzDo(menedzer.rodzic(menedzer.sciezka))
      }

      Text {
        Layout.fillWidth: true
        text: menedzer.sciezka === menedzer.korzen ? qsTr("Pliki aplikacji") : menedzer.sciezka.replace(menedzer.korzen, "\u2026")
        color: "#80CBC4"
        font: Theme.strongFont
        elide: Text.ElideMiddle
      }

      Text {
        text: qsTr("%1 poz.").arg(plikiModel.count)
        color: "#B0BEC5"
        font: Theme.tinyFont
      }

      ToolButton {
        text: qsTr("Zamknij")
        font: Theme.tinyFont
        onClicked: menedzer.close()
      }
    }

    Text {
      Layout.fillWidth: true
      visible: menedzer.komunikat !== ""
      text: menedzer.komunikat
      color: menedzer.blad ? "#EF5350" : "#9CCC65"
      font: Theme.tipFont
      wrapMode: Text.Wrap
    }

    Rectangle {
      Layout.fillWidth: true
      visible: menedzer.schowek !== ""
      height: 40
      radius: 4
      color: "#33FFC107"

      RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: (menedzer.schowekTryb === "wytnij" ? qsTr("Do przeniesienia: ") : qsTr("Do skopiowania: ")) + menedzer.nazwaZe(menedzer.schowek)
          color: "#FFC107"
          font: Theme.tinyFont
          elide: Text.ElideMiddle
        }

        ToolButton {
          text: qsTr("Wklej tutaj")
          font: Theme.tinyFont
          onClicked: menedzer.wklej()
        }

        ToolButton {
          text: "\u2715"
          onClicked: {
            menedzer.schowek = "";
            menedzer.schowekTryb = "";
          }
        }
      }
    }

    ListView {
      id: lista
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: plikiModel
      spacing: 2

      delegate: ItemDelegate {
        width: ListView.view.width
        height: 54

        readonly property string pelna: String(filePath).replace("file://", "")
        readonly property string powodBlokady: menedzer.zablokowany(fileName, pelna)
        readonly property bool roboczy: /\.roboczy$/.test(fileName)

        contentItem: RowLayout {
          spacing: 8

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              Layout.fillWidth: true
              text: fileName + (fileIsDir ? "/" : "")
              color: fileIsDir ? "#80CBC4" : (powodBlokady !== "" ? "#78909C" : (roboczy ? "#FFC107" : "white"))
              font: Theme.defaultFont
              elide: Text.ElideMiddle
            }

            Text {
              Layout.fillWidth: true
              visible: !fileIsDir
              text: menedzer.rozmiar(fileSize) + "  \u00b7  " + Qt.formatDateTime(fileModified, "yyyy-MM-dd hh:mm") + (powodBlokady !== "" ? "  \u00b7  " + qsTr("w uzyciu") : "")
              color: "#B0BEC5"
              font: Theme.tinyFont
              elide: Text.ElideRight
            }
          }
        }

        onClicked: {
          if (fileIsDir)
            menedzer.idzDo(pelna);
          else if (powodBlokady !== "")
            menedzer.powiedz(qsTr("Nietykalne — %1.").arg(powodBlokady), true);
          else
            menu.otworz(fileName, pelna, false, roboczy);
        }

        onPressAndHold: menu.otworz(fileName, pelna, fileIsDir, roboczy)
      }

      Text {
        anchors.centerIn: parent
        visible: parent.count === 0
        text: qsTr("Pusto")
        color: "#B0BEC5"
        font: Theme.tipFont
      }
    }
  }

  // --- menu czynnosci --------------------------------------------------
  Menu {
    id: menu

    property string nazwa: ""
    property string pelna: ""
    property bool katalog: false
    property bool roboczy: false

    function otworz(n, p, k, r) {
      nazwa = n;
      pelna = p;
      katalog = k === true;
      roboczy = r === true;
      popup();
    }

    MenuItem {
      text: qsTr("Podmien oryginal")
      visible: menu.roboczy
      height: visible ? implicitHeight : 0
      onTriggered: menedzer.podmien(menu.nazwa, menu.pelna)
    }

    MenuItem {
      text: qsTr("Przywroc")
      visible: menedzer.wKoszu
      height: visible ? implicitHeight : 0
      onTriggered: menedzer.przywroc(menu.nazwa, menu.pelna)
    }

    MenuItem {
      text: qsTr("Edytuj kopie")
      visible: !menu.katalog && menedzer.edytowalny(menu.nazwa, menu.pelna)
      height: visible ? implicitHeight : 0
      onTriggered: menedzer.edytujKopie(menu.nazwa, menu.pelna)
    }

    MenuItem {
      text: qsTr("Kopiuj")
      onTriggered: {
        menedzer.schowek = menu.pelna;
        menedzer.schowekTryb = "kopiuj";
        menedzer.schowekKatalog = menu.katalog;
      }
    }

    MenuItem {
      text: qsTr("Wytnij")
      enabled: menedzer.zablokowany(menu.nazwa, menu.pelna) === ""
      onTriggered: {
        menedzer.schowek = menu.pelna;
        menedzer.schowekTryb = "wytnij";
        menedzer.schowekKatalog = menu.katalog;
      }
    }

    MenuItem {
      text: qsTr("Wyslij")
      visible: !menu.katalog
      height: visible ? implicitHeight : 0
      onTriggered: platformUtilities.sendCompressedFilesTo([menu.pelna])
    }

    MenuItem {
      text: qsTr("Do kosza")
      onTriggered: menedzer.doKosza(menu.nazwa, menu.pelna, menu.katalog)
    }
  }
}
