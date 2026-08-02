import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * Przegladarka plikow i galeria zdjec projektu (WorkField, krok 1: odczyt).
 * Zrodlo zdjec: <projekt>/DCIM, nazwy wg schematu quick capture bara:
 * <warstwa>_<yyyyMMdd_hhmmss>.jpg - z nazwy odtwarzamy warstwe do filtrowania.
 */
Popup {
  id: photoGallery

  property var t

  readonly property string projectDir: qgisProject ? qgisProject.homePath : ""
  property string layerFilter: ""
  property var layerList: []
  property var photos: []

  width: mainWindow.width - 16
  height: mainWindow.height - 32
  x: Math.round((mainWindow.width - width) / 2)
  y: Math.round((mainWindow.height - height) / 2)
  modal: true
  focus: true

  // katalog, od ktorego zaczyna zakladka Pliki; pusty = katalog projektu
  property string startowyKatalog: ""
  // ktora zakladka ma byc widoczna po otwarciu (0 zdjecia, 1 pliki)
  property int startowaZakladka: 0

  // Rozszerzenia, które QField potrafi otworzyć. Projekty i dane idą tym samym
  // wywołaniem iface.loadFile() — różni je tylko to, co dzieje się potem.
  readonly property var wzorProjektu: /\.(qgs|qgz)$/i
  readonly property var wzorDanych: /\.(gpkg|shp|geojson|json|kml|kmz|gpx|csv|tif|tiff|jp2|vrt|mbtiles|sqlite|dxf|zip)$/i
  readonly property var wzorObrazu: /\.(jpg|jpeg|png)$/i

  //! Krótka nazwa rodzaju pliku — pod nazwą, żeby nie zgadywać z ikony.
  function rodzajPliku(nazwa) {
    if (wzorProjektu.test(nazwa))
      return qsTr("projekt");
    if (wzorObrazu.test(nazwa))
      return qsTr("zdjęcie");
    if (wzorDanych.test(nazwa))
      return qsTr("dane");
    return "";
  }

  // Publiczna pula szablonów: WebDAV linku publicznego. Login to token z adresu
  // udostępnienia, hasło puste — dzięki temu pobieranie działa bez logowania.
  // Bez konta widać tylko publiczną pulę (token z adresu udostępnienia).
  // Z kontem wchodzimy zwykłym WebDAV-em i widać wszystko, do czego serwer
  // dopuszcza użytkownika — o dostępie decydują uprawnienia, nie kod aplikacji.
  readonly property string chmuraSerwer: settings.value("workfield/cloud-url", "https://ekolaby.net/cloud")
  readonly property string chmuraToken: "sDoGaZ627ATqZHp"
  readonly property string chmuraLogin: settings.value("workfield/cloud-user", "")
  readonly property string chmuraHaslo: settings.value("workfield/cloud-pass", "")
  readonly property bool chmuraKonto: chmuraLogin !== "" && chmuraHaslo !== ""
  //! katalog szablonów na serwerze przy dostępie z kontem
  readonly property string chmuraKorzen: "WorkField/szablony/"
  property var chmuraLista: []
  //! ścieżka względna w drzewie chmury ("" = korzeń udostępnienia)
  property string chmuraSciezka: ""
  property string chmuraStan: ""
  property string chmuraPobierany: ""

  //! Katalog, do którego trafiają pobrane szablony.
  function katalogSzablonow() {
    return iface.dataRoot() + "Szablony";
  }

  /**
   * Lista paczek w publicznej puli. PROPFIND zwraca XML, z którego bierzemy
   * nazwę, rozmiar i datę — tyle wystarczy, żeby wybrać właściwy szablon.
   */
  function chmuraOdswiez() {
    chmuraStan = qsTr("pobieram listę…");
    chmuraLista = [];
    const xhr = new XMLHttpRequest();
    const adres = chmuraKonto
                    ? chmuraSerwer + "/remote.php/dav/files/" + chmuraLogin + "/" + chmuraKorzen + chmuraSciezka
                    : chmuraSerwer + "/public.php/webdav/" + chmuraSciezka;
    xhr.open("PROPFIND", adres, true);
    xhr.setRequestHeader("Depth", "1");
    xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(
      chmuraKonto ? (chmuraLogin + ":" + chmuraHaslo) : (chmuraToken + ":")));
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) {
        return;
      }
      if (xhr.status !== 207 && xhr.status !== 200) {
        chmuraStan = qsTr("nie udało się połączyć (kod %1)").arg(xhr.status);
        return;
      }
      const wynik = [];
      const tekst = xhr.responseText;
      const czesci = tekst.split("<d:response>");
      for (let i = 1; i < czesci.length; i++) {
        const cz = czesci[i];
        const href = /<d:href>([^<]*)<\/d:href>/.exec(cz);
        if (!href) {
          continue;
        }
        // pierwszy wpis PROPFIND to katalog bieżący — pomijamy go
        const czesciSciezki = href[1].replace(/\/$/, "").split("/");
        const nazwaWpisu = decodeURIComponent(czesciSciezki[czesciSciezki.length - 1]);
        const jestKatalogiem = href[1].endsWith("/");
        if (jestKatalogiem && (chmuraSciezka === "" ? czesciSciezki.length <= 4
                                                    : decodeURIComponent(href[1]).indexOf(chmuraSciezka) < 0
                                                      || decodeURIComponent(href[1]).replace(/\/$/, "").endsWith(chmuraSciezka.replace(/\/$/, "")))) {
          continue;
        }
        const nazwa = decodeURIComponent(href[1].split("/").pop());
        const rozmiar = /<d:getcontentlength>(\d+)<\/d:getcontentlength>/.exec(cz);
        const data = /<d:getlastmodified>([^<]*)<\/d:getlastmodified>/.exec(cz);
        wynik.push({
          "nazwa": nazwaWpisu,
          "katalog": jestKatalogiem,
          "url": chmuraKonto
                 ? chmuraSerwer + "/remote.php/dav/files/" + chmuraLogin + "/"
                   + chmuraKorzen + chmuraSciezka + encodeURIComponent(nazwaWpisu)
                 : chmuraSerwer + "/public.php/dav/files/" + chmuraToken + "/"
                   + chmuraSciezka + encodeURIComponent(nazwaWpisu),
          "rozmiar": rozmiar ? parseInt(rozmiar[1]) : 0,
          "data": data ? data[1].substring(5, 16) : ""
        });
      }
      wynik.sort(function (x, y) {
        if (x.katalog !== y.katalog)
          return x.katalog ? -1 : 1;
        return x.nazwa.localeCompare(y.nazwa);
      });
      chmuraLista = wynik;
      chmuraStan = wynik.length > 0 ? "" : qsTr("pula jest pusta");
    };
    xhr.send();
  }

  //! Wchodzi do podkatalogu w chmurze.
  function chmuraWejdz(nazwa) {
    chmuraSciezka = chmuraSciezka === "" ? nazwa + "/" : chmuraSciezka + nazwa + "/";
    chmuraOdswiez();
  }

  //! Wraca poziom wyżej; w korzeniu nie robi nic.
  function chmuraWyzej() {
    if (chmuraSciezka === "")
      return;
    const czesci = chmuraSciezka.replace(/\/$/, "").split("/");
    czesci.pop();
    chmuraSciezka = czesci.length > 0 ? czesci.join("/") + "/" : "";
    chmuraOdswiez();
  }

  //! Pobiera paczkę i rozpakowuje do katalogu Szablony.
  function chmuraPobierz(pozycja) {
    chmuraPobierany = pozycja.nazwa;
    chmuraStan = qsTr("pobieram %1…").arg(pozycja.nazwa);
    const cel = katalogSzablonow() + "/" + pozycja.nazwa;
    if (chmuraKonto) {
      iface.downloadFileAuth(pozycja.url, cel, chmuraLogin, chmuraHaslo);
    } else {
      iface.downloadFile(pozycja.url, cel);
    }
  }

  Connections {
    target: iface

    function onDownloadFinished(sciezka) {
      if (photoGallery.chmuraPobierany === "") {
        return;
      }
      const katalog = photoGallery.katalogSzablonow();
      if (FileUtils.unzipTo(sciezka, katalog)) {
        photoGallery.chmuraStan = qsTr("gotowe: %1").arg(photoGallery.chmuraPobierany);
        displayToast(qsTr("Szablon pobrany: %1").arg(photoGallery.chmuraPobierany));
      } else {
        photoGallery.chmuraStan = qsTr("pobrano, ale nie udało się rozpakować");
      }
      photoGallery.chmuraPobierany = "";
    }

    function onDownloadFailed(blad, sciezka) {
      if (photoGallery.chmuraPobierany === "") {
        return;
      }
      photoGallery.chmuraStan = qsTr("błąd pobierania: %1").arg(blad);
      photoGallery.chmuraPobierany = "";
    }
  }

  onOpened: {
    filesPage.browsePath = startowyKatalog !== "" ? startowyKatalog : projectDir;
    galleryTabs.currentIndex = startowaZakladka;
    rebuildPhotos();
  }

  /**
   * Otwiera galerie od razu na zakladce Pliki, w podanym katalogu.
   * Dzieki temu zawartosc projektu i katalogu aplikacji oglada sie jednym
   * narzedziem, zamiast trzema roznymi przegladarkami.
   */
  function openFiles(sciezka) {
    startowyKatalog = sciezka ? sciezka : projectDir;
    startowaZakladka = 1;
    open();
  }

  //! Otwiera galerie na zdjeciach projektu (zachowanie domyslne).
  //! Otwiera galerię od razu na zakładce Chmura.
  function openCloud() {
    startowyKatalog = "";
    startowaZakladka = 2;
    open();
  }

  function openPhotos() {
    startowyKatalog = "";
    startowaZakladka = 0;
    open();
  }
  onLayerFilterChanged: rebuildPhotos()

  // <warstwa>_<yyyyMMdd_hhmmss> -> warstwa; image_0003 -> image (stary aparat)
  function extractLayer(name) {
    const base = name.replace(/\.[^.]+$/, "");
    let m = base.match(/^(.*)_\d{8}_\d{6}$/);
    if (m)
      return m[1];
    m = base.match(/^(.*)_\d+$/);
    return m ? m[1] : base;
  }

  function tagColor(t) {
    let h = 0;
    for (let i = 0; i < t.length; i++)
      h = (h * 31 + t.charCodeAt(i)) % 360;
    return Qt.hsla(h / 360, 0.55, 0.45, 1);
  }

  function rebuildPhotos() {
    const arr = [];
    const prefixes = {};
    for (let i = 0; i < dcimModel.count; i++) {
      const name = dcimModel.get(i, "fileName");
      const layer = extractLayer(name);
      prefixes[layer] = true;
      if (layerFilter === "" || layer === layerFilter) {
        arr.push({
            "path": dcimModel.get(i, "filePath"),
            "name": name,
            "layer": layer,
            "mtime": dcimModel.get(i, "fileModified")
          });
      }
    }
    photos = arr;
    const pl = Object.keys(prefixes);
    pl.sort();
    layerList = pl;
    if (layerFilter !== "" && pl.indexOf(layerFilter) < 0)
      layerFilter = "";
  }

  PhotoTagStore {
    id: tagStore
  }

  Connections {
    target: photoGallery
    function onOpened() {
      if (photoGallery.projectDir !== "") {
        tagStore.author = settings.value("workfield/podpisTerenowy", "workfield");
        const ok = tagStore.open(photoGallery.projectDir);
        console.log("PhotoTagStore:", ok ? "otwarty: " + tagStore.storagePath : "BLAD otwarcia");
      }
    }
  }

  FolderListModel {
    id: dcimModel
    // QDir::Time = najnowsze pierwsze; odwrocenie: sortReversed: true
    folder: photoGallery.projectDir !== "" ? "file://" + photoGallery.projectDir + "/DCIM" : ""
    nameFilters: ["*.jpg", "*.jpeg", "*.JPG", "*.JPEG", "*.png", "*.PNG"]
    showDirs: false
    sortField: FolderListModel.Time
    onCountChanged: photoGallery.rebuildPhotos()
  }

  contentItem: ColumnLayout {
    spacing: 6

    RowLayout {
      Layout.fillWidth: true

      Text {
        Layout.fillWidth: true
        text: qsTr("Galeria projektu")
        font: photoGallery.t.strongFont
        color: photoGallery.t.mainTextColor
        elide: Text.ElideRight
      }

      Text {
        text: qsTr("Zdjęć: %1").arg(photoGallery.photos.length)
        font: photoGallery.t.tipFont
        color: photoGallery.t.secondaryTextColor
        visible: galleryTabs.currentIndex === 0
      }

      ToolButton {
        // 48 px to minimalny wygodny cel dotyku — w rękawicach mniejszy nie działa
        implicitWidth: 96
        implicitHeight: 48
        onClicked: photoGallery.close()

        contentItem: RowLayout {
          spacing: 6

          Image {
            source: photoGallery.t.getThemeVectorIcon("ic_clear_black_18dp")
            sourceSize.width: 26
            sourceSize.height: 26
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            fillMode: Image.PreserveAspectFit
          }

          Text {
            text: qsTr("Powrót")
            font: photoGallery.t.tipFont
            color: photoGallery.t.mainTextColor
            verticalAlignment: Text.AlignVCenter
          }
        }
      }
    }

    TabBar {
      id: galleryTabs
      Layout.fillWidth: true

      TabButton {
        text: qsTr("Zdjęcia")
      }
      TabButton {
        text: qsTr("Pliki")
      }
      TabButton {
        text: qsTr("Chmura")
      }
    }

    StackLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: galleryTabs.currentIndex
      // lista z chmury pobiera się przy pierwszym wejściu na zakładkę
      onCurrentIndexChanged: {
        if (currentIndex === 2 && photoGallery.chmuraLista.length === 0) {
          photoGallery.chmuraOdswiez();
        }
      }

      // ── Zdjęcia ────────────────────────────────────────────
      ColumnLayout {
        spacing: 6

        Flow {
          Layout.fillWidth: true
          spacing: 6
          visible: photoGallery.layerList.length > 1

          Repeater {
            model: [""].concat(photoGallery.layerList)

            delegate: Rectangle {
              radius: height / 2
              height: 30
              width: chipText.width + 22
              color: photoGallery.layerFilter === modelData ? "#00695C" : "#ECEFF1"
              border.color: "#00695C"
              border.width: 1

              Text {
                id: chipText
                anchors.centerIn: parent
                text: modelData === "" ? qsTr("Wszystkie") : modelData
                color: photoGallery.layerFilter === modelData ? "white" : "#00695C"
                font: photoGallery.t.tipFont
              }

              MouseArea {
                anchors.fill: parent
                onClicked: photoGallery.layerFilter = modelData
              }
            }
          }
        }

        GridView {
          id: photoGrid
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          cellWidth: Math.floor(width / Math.max(2, Math.floor(width / 132)))
          cellHeight: cellWidth
          model: photoGallery.photos

          ScrollBar.vertical: ScrollBar {
          }

          delegate: Item {
            width: photoGrid.cellWidth
            height: photoGrid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: 2
              color: "#20000000"
            }

            Image {
              anchors.fill: parent
              anchors.margins: 2
              source: "file://" + modelData.path
              asynchronous: true
              autoTransform: true
              fillMode: Image.PreserveAspectCrop
              // klucz wydajnosci: dekodujemy miniature, nie 12 Mpix
              sourceSize.width: 256
              sourceSize.height: 256
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 2
              height: 20
              color: "#88000000"

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 4
                text: Qt.formatDateTime(modelData.mtime, "dd.MM hh:mm")
                color: "white"
                font: photoGallery.t.tinyFont
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: viewer.openList(photoGallery.photos, index)
            }
          }

          Text {
            anchors.centerIn: parent
            visible: photoGallery.photos.length === 0
            text: qsTr("Brak zdjęć w katalogu DCIM projektu")
            color: photoGallery.t.secondaryTextColor
            font: photoGallery.t.tipFont
          }
        }
      }

      // ── Pliki ──────────────────────────────────────────────
      ColumnLayout {
        id: filesPage

        property string browsePath: photoGallery.projectDir
        // korzen przegladania: wyzej sie nie wychodzi
        readonly property string korzen: photoGallery.startowyKatalog !== "" ? photoGallery.startowyKatalog : photoGallery.projectDir

        spacing: 6

        RowLayout {
          Layout.fillWidth: true

          ToolButton {
            text: "↑"
            enabled: filesPage.browsePath.length > filesPage.korzen.length
            onClicked: filesPage.browsePath = filesPage.browsePath.substring(0, filesPage.browsePath.lastIndexOf("/"))
          }

          Text {
            Layout.fillWidth: true
            text: filesPage.browsePath.length > filesPage.korzen.length ? filesPage.browsePath.substring(filesPage.korzen.length + 1) : (filesPage.korzen === photoGallery.projectDir ? qsTr("(katalog projektu)") : qsTr("(katalog aplikacji)"))
            font: photoGallery.t.tipFont
            color: photoGallery.t.secondaryTextColor
            elide: Text.ElideMiddle
          }
        }

        ListView {
          id: filesList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true

          ScrollBar.vertical: ScrollBar {
          }

          model: FolderListModel {
            folder: filesPage.browsePath !== "" ? "file://" + filesPage.browsePath : ""
            showDirs: true
            showDirsFirst: true
            showDotAndDotDot: false
            // w terenie szuka się tego, co świeże — najnowsze na górze
            sortField: FolderListModel.Time
            sortReversed: false
          }

          delegate: ItemDelegate {
            width: filesList.width
            height: 44

            contentItem: RowLayout {
              spacing: 8

              Image {
                source: {
                  if (fileIsDir)
                    return photoGallery.t.getThemeVectorIcon("ic_folder_open_black_24dp");
                  if (photoGallery.wzorProjektu.test(fileName))
                    return photoGallery.t.getThemeVectorIcon("ic_map_white_24dp");
                  if (photoGallery.wzorObrazu.test(fileName))
                    return photoGallery.t.getThemeVectorIcon("ic_camera_photo_black_24dp");
                  if (photoGallery.wzorDanych.test(fileName))
                    return photoGallery.t.getThemeVectorIcon("ic_vectorlayer_polygon_18dp");
                  return photoGallery.t.getThemeVectorIcon("ic_file_black_24dp");
                }
                sourceSize.width: 24
                sourceSize.height: 24
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                fillMode: Image.PreserveAspectFit
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                  Layout.fillWidth: true
                  text: fileName
                  font: photoGallery.t.tipFont
                  color: photoGallery.t.mainTextColor
                  elide: Text.ElideMiddle
                }

                Text {
                  Layout.fillWidth: true
                  visible: text !== ""
                  text: fileIsDir ? "" : photoGallery.rodzajPliku(fileName)
                  font: photoGallery.t.tinyFont
                  color: photoGallery.t.secondaryTextColor
                }
              }

              Text {
                text: fileIsDir ? "" : FileUtils.representFileSize(fileSize)
                font: photoGallery.t.tinyFont
                color: photoGallery.t.secondaryTextColor
              }

              Text {
                text: Qt.formatDateTime(fileModified, "yyyy-MM-dd hh:mm")
                font: photoGallery.t.tinyFont
                color: photoGallery.t.secondaryTextColor
              }
            }

            onClicked: {
              if (fileIsDir) {
                filesPage.browsePath = filePath;
              } else if (/\.(jpg|jpeg|png)$/i.test(fileName)) {
                viewer.openList([{
                      "path": filePath,
                      "name": fileName,
                      "layer": "",
                      "mtime": fileModified
                    }], 0);
              } else if (photoGallery.wzorProjektu.test(fileName)) {
                // projekt: zamykamy galerię, bo za chwilę zmieni się cały kontekst
                photoGallery.close();
                iface.loadFile(filePath, FileUtils.fileName(filePath, false));
              } else if (photoGallery.wzorDanych.test(fileName)) {
                // dane: warstwa dokłada się do bieżącego projektu, galeria zostaje
                iface.loadFile(filePath, FileUtils.fileName(filePath, false));
                displayToast(qsTr("Dodano warstwę: %1").arg(fileName));
              } else {
                displayToast(qsTr("Nie wiem, jak otworzyć ten plik"));
              }
            }
          }
        }
      }

      // ── Chmura ─────────────────────────────────────────────
      ColumnLayout {
        id: cloudPage
        spacing: 6

        RowLayout {
          Layout.fillWidth: true

          ToolButton {
            text: "↑"
            enabled: photoGallery.chmuraSciezka !== ""
            onClicked: photoGallery.chmuraWyzej()
          }

          Text {
            Layout.fillWidth: true
            text: photoGallery.chmuraStan !== ""
                  ? photoGallery.chmuraStan
                  : (photoGallery.chmuraSciezka !== ""
                     ? photoGallery.chmuraSciezka.replace(/\/$/, "")
                     : (photoGallery.chmuraKonto
                        ? qsTr("szablony zespołu — %1").arg(photoGallery.chmuraLogin)
                        : qsTr("szablony publiczne — %1").arg(photoGallery.chmuraSerwer.replace("https://", ""))))
            font: photoGallery.t.tipFont
            color: photoGallery.t.secondaryTextColor
            elide: Text.ElideRight
          }

          ToolButton {
            text: qsTr("Odśwież")
            font: photoGallery.t.tipFont
            onClicked: photoGallery.chmuraOdswiez()
          }
        }

        ListView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: 2
          model: photoGallery.chmuraLista

          ScrollBar.vertical: ScrollBar {
          }

          delegate: Rectangle {
            width: ListView.view.width
            height: 60
            color: "transparent"

            MouseArea {
              anchors.fill: parent
              enabled: modelData.katalog
              onClicked: photoGallery.chmuraWejdz(modelData.nazwa)
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 4
              anchors.rightMargin: 4
              spacing: 8

              Image {
                source: modelData.katalog
                        ? photoGallery.t.getThemeVectorIcon("ic_folder_open_black_24dp")
                        : photoGallery.t.getThemeVectorIcon("wf_project_template")
                sourceSize.width: 26
                sourceSize.height: 26
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                fillMode: Image.PreserveAspectFit
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                  Layout.fillWidth: true
                  text: modelData.katalog ? modelData.nazwa : modelData.nazwa.replace(".zip", "")
                  font: photoGallery.t.tipFont
                  color: photoGallery.t.mainTextColor
                  elide: Text.ElideMiddle
                }

                Text {
                  visible: !modelData.katalog
                  text: FileUtils.representFileSize(modelData.rozmiar) + "   " + modelData.data
                  font: photoGallery.t.tinyFont
                  color: photoGallery.t.secondaryTextColor
                }
              }

              Button {
                visible: !modelData.katalog
                text: photoGallery.chmuraPobierany === modelData.nazwa
                      ? qsTr("pobieram…") : qsTr("Pobierz")
                enabled: photoGallery.chmuraPobierany === ""
                font: photoGallery.t.tipFont
                onClicked: photoGallery.chmuraPobierz(modelData)
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: qsTr("Pobrane szablony trafiają do katalogu Szablony i są od razu dostępne w „Nowe zadanie”.")
          font: photoGallery.t.tinyFont
          color: photoGallery.t.secondaryTextColor
        }
      }
    }
  }

  // ── pelnoekranowy podglad z zoomem ───────────────────────
  Popup {
    id: viewer
    parent: Overlay.overlay
    width: parent ? parent.width : 100
    height: parent ? parent.height : 100
    modal: true
    padding: 0

    property var items: []
    property int idx: -1
    readonly property var cur: (idx >= 0 && idx < items.length) ? items[idx] : null
    readonly property string curRel: cur ? cur.path.substring(photoGallery.projectDir.length + 1) : ""
    property var curTags: []

    function relFor(i) {
      return (i >= 0 && i < items.length) ? items[i].path.substring(photoGallery.projectDir.length + 1) : "";
    }

    function refreshTags() {
      const rel = relFor(idx);
      let t = rel !== "" ? tagStore.tagsForPhoto(rel) : [];
      t.sort(function (a, b) {
        const pa = (a.pokrycie === undefined || a.pokrycie === null) ? -1 : a.pokrycie;
        const pb = (b.pokrycie === undefined || b.pokrycie === null) ? -1 : b.pokrycie;
        if (pb !== pa)
          return pb - pa;
        return a.tag.localeCompare(b.tag);
      });
      curTags = t;
    }

    property int editFid: -1

    function startEdit(m) {
      tagInput.text = m.tag;
      pokInput.text = (m.pokrycie !== undefined && m.pokrycie !== null) ? String(m.pokrycie) : "";
      editFid = m.fid;
      if (!tagPanel.visible) {
        tagPanel.visible = true;
        tagPanel.updateSuggestions();
      }
      pokInput.forceActiveFocus();
    }

    function commitPending() {
      if (tagPanel.visible && tagInput.text.trim() !== "")
        addTagButton.clicked();
    }

    function goPrev() {
      if (idx > 0) {
        commitPending();
        idx--;
      }
    }

    function goNext() {
      if (idx < items.length - 1) {
        commitPending();
        idx++;
      }
    }

    function openList(list, i) {
      items = list;
      idx = i;
      open();
      refreshTags();
      Qt.callLater(fitToScreen);
    }

    function fitToScreen() {
      flick.resizeContent(flick.width, flick.height, Qt.point(0, 0));
      flick.contentX = 0;
      flick.contentY = 0;
    }

    onIdxChanged: {
      editFid = -1;
      refreshTags();
      if (tagPanel.visible)
        tagPanel.updateSuggestions();
      Qt.callLater(fitToScreen);
    }

    onClosed: commitPending()

    Connections {
      target: tagStore
      function onTagsChanged(foto) {
        if (foto === viewer.curRel)
          viewer.refreshTags();
      }
    }

    background: Rectangle {
      color: "black"
    }

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.bottomMargin: 64
      anchors.rightMargin: tagPanel.visible ? tagPanel.width : 0
      contentWidth: width
      contentHeight: height
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentWidth > width + 5 || contentHeight > height + 5
      clip: true

      PinchArea {
        width: Math.max(flick.contentWidth, flick.width)
        height: Math.max(flick.contentHeight, flick.height)

        property real startW
        property real startH

        onPinchStarted: {
          startW = flick.contentWidth;
          startH = flick.contentHeight;
        }
        onPinchUpdated: pinch => {
          flick.contentX += pinch.previousCenter.x - pinch.center.x;
          flick.contentY += pinch.previousCenter.y - pinch.center.y;
          const w = Math.max(flick.width, Math.min(startW * pinch.scale, flick.width * 8));
          const h = Math.max(flick.height, Math.min(startH * pinch.scale, flick.height * 8));
          flick.resizeContent(w, h, pinch.center);
        }
        onPinchFinished: flick.returnToBounds()

        Image {
          id: fullImage

          // Ergonomia: zdjecie bez EXIF Orientation (typowo pionowo w dol,
          // gdzie "gora" nie istnieje) kladziemy wzdluz dluzszej osi
          // ekranu, zeby wypelnialo kadr - kierunek obrotu bez znaczenia.
          readonly property bool noExif: viewer.cur ? !tagStore.hasExifOrientation(viewer.cur.path) : false
          readonly property bool sideways: noExif && status == Image.Ready && sourceSize.width !== sourceSize.height && ((sourceSize.width > sourceSize.height) !== (flick.width > flick.height))

          width: sideways ? flick.contentHeight : flick.contentWidth
          height: sideways ? flick.contentWidth : flick.contentHeight
          anchors.centerIn: parent
          rotation: sideways ? 90 : 0
          source: viewer.cur ? "file://" + viewer.cur.path : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          autoTransform: true
        }

        MouseArea {
          anchors.fill: parent

          property real pressX: 0
          property real pressY: 0

          onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
          }
          onReleased: mouse => {
            if (!flick.interactive) {
              const dx = mouse.x - pressX;
              const dy = mouse.y - pressY;
              if (Math.abs(dx) > 60 && Math.abs(dx) > 2 * Math.abs(dy)) {
                if (dx < 0)
                  viewer.goNext();
                else
                  viewer.goPrev();
              }
            }
          }
          onDoubleClicked: mouse => {
            if (flick.contentWidth > flick.width * 1.05) {
              viewer.fitToScreen();
            } else {
              flick.resizeContent(flick.width * 2.5, flick.height * 2.5, Qt.point(mouse.x, mouse.y));
            }
          }
          onWheel: wheel => {
            const f = wheel.angleDelta.y > 0 ? 1.25 : 0.8;
            const w = Math.max(flick.width, Math.min(flick.contentWidth * f, flick.width * 8));
            const h = Math.max(flick.height, Math.min(flick.contentHeight * f, flick.height * 8));
            flick.resizeContent(w, h, Qt.point(wheel.x, wheel.y));
            flick.returnToBounds();
          }
        }
      }
    }

    BusyIndicator {
      anchors.centerIn: flick
      running: fullImage.status === Image.Loading
    }

    RoundButton {
      text: "‹"
      width: 64
      height: 64
      font.pointSize: 26
      Material.background: "#AA263238"
      Material.foreground: "white"
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: flick.verticalCenter
      visible: viewer.items.length > 1
      enabled: viewer.idx > 0
      opacity: 0.85
      onClicked: viewer.goPrev()
    }

    RoundButton {
      text: "›"
      width: 64
      height: 64
      font.pointSize: 26
      Material.background: "#AA263238"
      Material.foreground: "white"
      anchors.right: parent.right
      anchors.rightMargin: tagPanel.visible ? tagPanel.width + 8 : 8
      anchors.verticalCenter: flick.verticalCenter
      visible: viewer.items.length > 1
      enabled: viewer.idx < viewer.items.length - 1
      opacity: 0.85
      onClicked: viewer.goNext()
    }

    RoundButton {
      text: "✕"
      width: 56
      height: 56
      font.pointSize: 18
      Material.background: "#AA263238"
      Material.foreground: "white"
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 8
      anchors.topMargin: 56
      anchors.rightMargin: tagPanel.visible ? tagPanel.width + 8 : 8
      opacity: 0.85
      onClicked: viewer.close()
    }

    RoundButton {
      text: "🏷"
      width: 64
      height: 64
      font.pointSize: 22
      Material.background: tagPanel.visible ? "#AA00695C" : "#AA263238"
      Material.foreground: "white"
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: tagPanel.visible ? tagPanel.width + 8 : 8
      anchors.bottomMargin: 56
      onClicked: {
        tagPanel.visible = !tagPanel.visible;
        if (tagPanel.visible) {
          viewer.refreshTags();
          tagPanel.updateSuggestions();
          tagInput.forceActiveFocus();
        }
      }
    }

    // Usuwanie zdjecia: nie kasuje pliku, przenosi do DCIM/.kosz
    RoundButton {
      text: "🗑"
      width: 56
      height: 56
      font.pointSize: 18
      Material.background: "#AA5D4037"
      Material.foreground: "white"
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: tagPanel.visible ? tagPanel.width + 8 : 8
      anchors.bottomMargin: 128
      opacity: 0.9
      visible: viewer.cur !== null
      onClicked: potwierdzUsuniecie.open()
    }

    QfDialog {
      id: potwierdzUsuniecie
      title: qsTr("Usunąć zdjęcie?")
      parent: mainWindow.contentItem
      focus: visible
      standardButtons: Dialog.Yes | Dialog.No

      Label {
        width: parent.width
        wrapMode: Text.WordWrap
        text: viewer.cur ? qsTr("%1\n\nZdjęcie trafi do kosza projektu (DCIM/.kosz) razem z tagami. Można je stamtąd odzyskać.").arg(FileUtils.fileName(viewer.cur.path)) : ""
      }

      onAccepted: {
        if (!viewer.cur) {
          return;
        }
        const sciezka = viewer.cur.path;
        const nazwa = FileUtils.fileName(sciezka);
        const wKoszu = tagStore.moveToTrash(sciezka);
        if (wKoszu === "") {
          displayToast(qsTr("Nie udało się usunąć %1").arg(nazwa), "error");
          return;
        }
        viewer.close();
        photoGallery.rebuildPhotos();
        displayToast(qsTr("Usunięto %1 — w koszu: %2").arg(nazwa).arg(tagStore.trashCount()));
      }
    }

    Rectangle {
      id: tagPanel

      // uwaga: context property "settings" nie jest dostepne w inicjalizatorach
      // wlasciwosci (tworzenie komponentu) - czytamy je w Component.onCompleted
      property bool sortAZ: true
      property var suggestions: []
      property int maxN: 1

      onSortAZChanged: {
        settings.setValue("workfield/tagSortAZ", sortAZ);
        updateSuggestions();
      }

      Component.onCompleted: {
        sortAZ = String(settings.value("workfield/tagSortAZ", "true")) === "true";
        const w = Number(settings.value("workfield/tagPanelWidth", 320));
        if (w > 0) {
          savedWidth = w;
        }
      }

      function updateSuggestions() {
        const wzor = tagInput.text.trim().toLowerCase();
        const stats = tagStore.tagStats(500);
        const seen = ({});
        const out = [];
        const dodaj = (surowa, n) => {
          const nazwa = String(surowa).trim().replace(/\s+/g, " ");
          if (nazwa === "")
            return;
          const k = nazwa.toLowerCase();
          if (!seen[k]) {
            seen[k] = true;
            out.push({
                "name": nazwa,
                "n": n
              });
          }
        };
        for (let i = 0; i < stats.length; i++) {
          if (wzor === "" || stats[i].tag.toLowerCase().indexOf(wzor) >= 0)
            dodaj(stats[i].tag, stats[i].n);
        }
        const sp = tagStore.projectSpecies();
        for (let i = 0; i < sp.length; i++) {
          if (wzor === "" || sp[i].toLowerCase().indexOf(wzor) >= 0)
            dodaj(sp[i], 0);
        }
        const fs = tagStore.formSpecies();
        for (let i = 0; i < fs.length; i++) {
          if (wzor === "" || fs[i].toLowerCase().indexOf(wzor) >= 0)
            dodaj(fs[i], 0);
        }
        out.sort(function (a, b) {
          if (!tagPanel.sortAZ && b.n !== a.n)
            return b.n - a.n;
          return a.name.localeCompare(b.name);
        });
        let m = 1;
        for (let i = 0; i < out.length; i++)
          m = Math.max(m, out[i].n);
        maxN = m;
        suggestions = out;
      }

      visible: false
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      anchors.bottomMargin: 44

      // szerokosc: przeciaganie lewej krawedzi, ostatnia wartosc pamietana
      property real savedWidth: 320
      width: Math.max(200, Math.min(parent.width * 0.7, savedWidth))
      color: "#EE263238"

      Rectangle {
        id: panelGrip
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 14
        color: gripArea.pressed ? "#3380CBC4" : "transparent"
        z: 10

        Rectangle {
          anchors.centerIn: parent
          width: 3
          height: 36
          radius: 1.5
          color: "#607D8B"
        }

        MouseArea {
          id: gripArea
          anchors.fill: parent
          anchors.margins: -6
          cursorShape: Qt.SizeHorCursor

          property real startX: 0

          onPressed: mouse => {
            startX = mouse.x;
          }
          onPositionChanged: mouse => {
            if (pressed)
              tagPanel.savedWidth = Math.max(200, Math.min(tagPanel.parent.width * 0.7, tagPanel.width - (mouse.x - startX)));
          }
          onReleased: settings.setValue("workfield/tagPanelWidth", Math.round(tagPanel.width))
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        anchors.leftMargin: 18
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          Text {
            Layout.fillWidth: true
            text: viewer.cur ? viewer.cur.name : ""
            color: "#80CBC4"
            font: photoGallery.t.tinyFont
            elide: Text.ElideLeft
          }

          ToolButton {
            text: tagPanel.sortAZ ? "A–Z" : "№↓"
            font.pointSize: photoGallery.t.tinyFont.pointSize
            onClicked: tagPanel.sortAZ = !tagPanel.sortAZ
          }
        }

        TextField {
          id: tagInput
          Layout.fillWidth: true
          placeholderText: qsTr("Główny gatunek…")
          color: "white"
          placeholderTextColor: "#90A4AE"
          font: photoGallery.t.tipFont
          onTextChanged: tagPanel.updateSuggestions()
          onAccepted: addTagButton.clicked()
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          TextField {
            id: pokInput
            Layout.preferredWidth: 64
            placeholderText: "%"
            color: "white"
            placeholderTextColor: "#90A4AE"
            font: photoGallery.t.tipFont
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator {
              bottom: 0
              top: 100
            }
          }

          Button {
            id: addTagButton
            Layout.fillWidth: true
            text: viewer.editFid >= 0 ? qsTr("Zapisz") : qsTr("Dodaj")
            enabled: tagInput.text.trim() !== ""
            onClicked: {
              const pok = pokInput.text !== "" ? parseInt(pokInput.text) : -1;
              if (viewer.editFid >= 0) {
                tagStore.removeTag(viewer.editFid);
                viewer.editFid = -1;
              }
              const fid = tagStore.addTag(viewer.curRel, tagInput.text, pok);
              if (fid >= 0) {
                tagInput.text = "";
                pokInput.text = "";
                tagPanel.updateSuggestions();
                tagInput.forceActiveFocus();
              } else {
                displayToast(qsTr("Nie udało się zapisać tagu"));
              }
            }
          }
        }

        ListView {
          id: curTagList
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, tagPanel.height * 0.35)
          clip: true
          visible: viewer.curTags.length > 0
          model: viewer.curTags

          delegate: RowLayout {
            width: curTagList.width
            height: Math.max(28, implicitHeight + 4)
            spacing: 6

            Rectangle {
              width: 12
              height: 12
              radius: 2
              color: photoGallery.tagColor(modelData.tag)
            }

            Text {
              Layout.fillWidth: true
              text: modelData.tag
              color: "white"
              font: photoGallery.t.tipFont
              wrapMode: Text.Wrap

              MouseArea {
                anchors.fill: parent
                onClicked: viewer.startEdit(modelData)
              }
            }

            Text {
              text: modelData.pokrycie !== undefined && modelData.pokrycie !== null ? modelData.pokrycie + "%" : ""
              color: "#B0BEC5"
              font: photoGallery.t.tinyFont
            }

            Text {
              text: "✕"
              color: "#EF9A9A"
              font: photoGallery.t.tipFont

              MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                onClicked: tagStore.removeTag(modelData.fid)
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: "#455A64"
          visible: viewer.curTags.length > 0
        }

        ListView {
          id: sugList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: tagPanel.suggestions

          ScrollBar.vertical: ScrollBar {
          }

          delegate: ItemDelegate {
            width: sugList.width
            height: Math.max(34, sugText.implicitHeight + 14)

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * modelData.n / tagPanel.maxN
              color: "#2280CBC4"
              visible: !tagPanel.sortAZ && modelData.n > 0
            }

            contentItem: RowLayout {
              spacing: 6

              Rectangle {
                width: 12
                height: 12
                radius: 2
                color: photoGallery.tagColor(modelData.name)
              }

              Text {
                id: sugText
                Layout.fillWidth: true
                text: modelData.name
                color: "white"
                font: photoGallery.t.tipFont
                wrapMode: Text.Wrap
              }

              Text {
                text: modelData.n > 0 ? modelData.n : ""
                color: "#78909C"
                font: photoGallery.t.tinyFont
              }
            }

            onClicked: {
              tagInput.text = modelData.name;
              pokInput.forceActiveFocus();
            }
          }
        }
      }
    }

    Rectangle {
      id: tagStrip

      visible: viewer.curTags.length > 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 44
      anchors.rightMargin: tagPanel.visible ? tagPanel.width : 0
      height: 20
      color: "#CC000000"

      ListView {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        orientation: ListView.Horizontal
        spacing: 12
        clip: true
        model: viewer.curTags

        delegate: Item {
          width: stripRow.implicitWidth
          height: 20

          Row {
            id: stripRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
              width: 8
              height: 8
              radius: 2
              anchors.verticalCenter: parent.verticalCenter
              color: photoGallery.tagColor(modelData.tag)
            }

            Text {
              text: modelData.tag + (modelData.pokrycie !== undefined && modelData.pokrycie !== null ? " " + modelData.pokrycie + "%" : "")
              color: "white"
              font.pointSize: Math.max(6, photoGallery.t.tinyFont.pointSize - 2)
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: viewer.startEdit(modelData)
          }
        }
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 44
      color: "#CC000000"

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        Text {
          Layout.fillWidth: true
          text: viewer.cur ? viewer.cur.name : ""
          color: "white"
          font: photoGallery.t.tipFont
          elide: Text.ElideMiddle
        }

        Text {
          text: viewer.curTags.length > 0 ? "🏷 " + viewer.curTags.length : ""
          color: "#80CBC4"
          font: photoGallery.t.tinyFont
        }

        Text {
          text: viewer.cur ? Qt.formatDateTime(viewer.cur.mtime, "yyyy-MM-dd hh:mm") : ""
          color: "#B0BEC5"
          font: photoGallery.t.tinyFont
        }

        Text {
          text: viewer.items.length > 1 ? (viewer.idx + 1) + " / " + viewer.items.length : ""
          color: "#B0BEC5"
          font: photoGallery.t.tinyFont
        }
      }
    }
  }
}
