import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import QtQuick.Dialogs
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
  //
  // WorkField 23.08.2026 — TE TRZY BYLY `readonly` I ZAMROZONE.
  // `settings.value()` to funkcja C++: silnik QML nie widzi, co ona czyta,
  // wiec wiazanie liczylo sie raz, przy tworzeniu galerii, i nie zmienialo
  // sie NIGDY. Kto wpisal dane logowania w Ustawieniach po otwarciu galerii
  // choc raz, ten do konca sesji wysylal je z pustym loginem — bez zadnego
  // komunikatu, bo pusty login to poprawny ciag znakow. Znalezione sitem
  // `skrypty/sito_wiazania.py`.
  property string chmuraSerwer: settings.value("workfield/cloud-url", "https://ekolaby.net/cloud")
  readonly property string chmuraToken: "sDoGaZ627ATqZHp"
  property string chmuraLogin: settings.value("workfield/cloud-user", "")
  property string chmuraHaslo: settings.value("workfield/cloud-pass", "")

  //! Odczyt ustawien chmury w chwili otwarcia — patrz komentarz wyzej.
  function odswiezChmure() {
    chmuraSerwer = settings.value("workfield/cloud-url", "https://ekolaby.net/cloud");
    chmuraLogin = settings.value("workfield/cloud-user", "");
    chmuraHaslo = settings.value("workfield/cloud-pass", "");
  }
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
        // Brama chmurowa: paczka z projekt.qgs/qgz to PROJEKT - kierujemy go
        // do Imported Projects, zeby byl widoczny w "Otworz projekt".
        // Szablony (bez pliku projektu o tej nazwie) zostaja w Szablonach.
        const nazwa = FileUtils.fileName(sciezka, false);
        const rozpakowane = katalog + "/" + nazwa;
        const jestProjektem = FileUtils.fileExists(rozpakowane + "/projekt.qgs") || FileUtils.fileExists(rozpakowane + "/projekt.qgz");
        if (jestProjektem) {
          const celProjektu = iface.dataRoot() + "Imported Projects/" + nazwa;
          if (iface.movePath(rozpakowane, celProjektu)) {
            photoGallery.chmuraStan = qsTr("projekt gotowy: %1").arg(nazwa);
            displayToast(qsTr("Projekt %1 pobrany — znajdziesz go w \"Otwórz projekt\"").arg(nazwa));
          } else {
            photoGallery.chmuraStan = qsTr("pobrano: %1 (w Szablonach)").arg(nazwa);
            displayToast(qsTr("Projekt %1 istnieje już na liście — pobrana kopia została w Szablonach").arg(nazwa), "warning");
          }
        } else {
          photoGallery.chmuraStan = qsTr("gotowe: %1").arg(photoGallery.chmuraPobierany);
          displayToast(qsTr("Szablon pobrany: %1").arg(photoGallery.chmuraPobierany));
        }
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
    odswiezChmure();
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

  //! Otwiera galerie na przegladarce tabel danych.
  function openTables() {
    startowyKatalog = "";
    startowaZakladka = 4;
    open();
  }
  onLayerFilterChanged: rebuildPhotos()

  // <warstwa>_<yyyyMMdd_hhmmss>[_zzz] -> warstwa; image_0003 -> image (stary aparat)
  // Konwencja załączników dokłada klucz obiektu: <warstwa>_<fid>_<data>_<ms>,
  // a plik leży w podkatalogu o nazwie <warstwa>_<fid>. Klucz obcinamy tylko
  // wtedy, gdy katalog to potwierdza — dzięki temu warstwa nazwana "dzialki_2"
  // nie gubi swojej dwójki.
  function extractLayer(name, katalog) {
    const base = name.replace(/\.[^.]+$/, "");
    let m = base.match(/^(.*)_\d{8}_\d{6}(_\d{1,3})?$/);
    if (m) {
      if (katalog && katalog === m[1]) {
        const bezKlucza = m[1].match(/^(.*)_\d+$/);
        return bezKlucza ? bezKlucza[1] : m[1];
      }
      return m[1];
    }
    m = base.match(/^(.*)_\d+$/);
    return m ? m[1] : base;
  }

  //! podbijany przy każdej zmianie tagów — odświeża kropki na miniaturach
  property int wersjaTagow: 0

  //! wskazywanie gatunków wprost na miniaturach (siatka Zdjęcia)
  property bool trybMasowy: false

  //! rozmiar kafli w siatkach; Ctrl+kółko zmienia, wartość zapamiętywana
  property int rozmiarKafla: 132

  function tagColor(t) {
    let h = 0;
    for (let i = 0; i < t.length; i++)
      h = (h * 31 + t.charCodeAt(i)) % 360;
    return Qt.hsla(h / 360, 0.55, 0.45, 1);
  }

  //! zbiera zdjecia z jednego modelu katalogu do wspolnej listy
  function zbierzZKatalogu(model, katalog, arr, prefixes) {
    for (let i = 0; i < model.count; i++) {
      const name = model.get(i, "fileName");
      const layer = extractLayer(name, katalog);
      prefixes[layer] = true;
      if (layerFilter === "" || layer === layerFilter) {
        arr.push({
            "path": model.get(i, "filePath"),
            "name": name,
            "layer": layer,
            "mtime": model.get(i, "fileModified")
          });
      }
    }
  }

  function rebuildPhotos() {
    const arr = [];
    const prefixes = {};
    zbierzZKatalogu(dcimModel, "", arr, prefixes);
    // zdjecia w podkatalogach obiektow (konwencja zalacznikow N:1)
    for (let p = 0; p < podkatalogiDcim.count; p++) {
      const poz = podkatalogiDcim.itemAt(p);
      if (poz && poz.modelPlikow)
        zbierzZKatalogu(poz.modelPlikow, poz.nazwaKatalogu, arr, prefixes);
    }
    // kolejnosc: najnowsze pierwsze. Wczesniej wystarczalo sortowanie samego
    // FolderListModel, ale listy z kilku katalogow trzeba scalic recznie.
    arr.sort(function (a, b) {
      return b.mtime - a.mtime;
    });
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

  CaptureAttitude {
    id: pozaAparatu
  }

  Connections {
    target: photoGallery
    function onOpened() {
      if (photoGallery.projectDir !== "") {
        tagStore.author = settings.value("workfield/podpisTerenowy", "workfield");
        const ok = tagStore.open(photoGallery.projectDir);
        console.log("PhotoTagStore:", ok ? "otwarty: " + tagStore.storagePath : "BLAD otwarcia");
        photoGallery.wersjaTagow++;
        photoGallery.rozmiarKafla = Number(settings.value('WorkField/galeriaKafel', 132));
        viewer.siatkaN = Number(settings.value('WorkField/siatkaN', 5));
      }
    }
  }

  // ---- WorkField: panel METATAGOW — pelna karta metadanych gatunku ----
  Popup {
    id: metaPanelOkno
    parent: Overlay.overlay
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width - 32, 520)
    height: Math.min(parent.height - 64, 620)
    padding: 14

    property var m: ({})
    property string nazwa: ""

    function pokaz(gatunek, meta) {
      nazwa = String(gatunek || "").trim();
      m = (meta && meta.GATUNEK !== undefined) ? meta : tagStore.speciesMeta(nazwa);
      open();
    }

    function w(v) {
      return (v === undefined || v === null || String(v).trim() === "") ? "—" : String(v).trim();
    }

    function z2(v) {
      const n = Number(v);
      return (v === undefined || v === null || String(v).trim() === "" || isNaN(n)) ? "—" : n.toFixed(2);
    }

    background: Rectangle {
      color: "#F0263238"
      radius: 10
    }

    contentItem: Flickable {
      contentHeight: metaKol.implicitHeight
      clip: true

      Column {
        id: metaKol
        width: parent.width
        spacing: 8

        Label {
          width: parent.width
          wrapMode: Text.WordWrap
          font.bold: true
          font.italic: true
          color: "#39ff14"
          text: metaPanelOkno.m.GATUNEK !== undefined ? metaPanelOkno.w(metaPanelOkno.m.GATUNEK) : (metaPanelOkno.nazwa + qsTr(" — brak w słowniku"))
        }

        Label {
          visible: metaPanelOkno.m.NAZWA_POLSKA !== undefined && metaPanelOkno.w(metaPanelOkno.m.NAZWA_POLSKA) !== "—"
          width: parent.width
          wrapMode: Text.WordWrap
          color: "#B0BEC5"
          text: metaPanelOkno.w(metaPanelOkno.m.NAZWA_POLSKA)
        }

        Label {
          visible: text !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          color: "#FFCC80"
          font.bold: true
          text: {
            const st = [];
            if (metaPanelOkno.m.CHRONIONY === "TAK")
              st.push(qsTr("CHRONIONY"));
            if (metaPanelOkno.m.CENNY === "TAK")
              st.push(qsTr("CENNY / RZADKI"));
            if (metaPanelOkno.m.IGO !== undefined && metaPanelOkno.w(metaPanelOkno.m.IGO) !== "—" && metaPanelOkno.m.IGO !== "NIE")
              st.push(String(metaPanelOkno.m.IGO));
            return st.join("  ·  ");
          }
        }

        Rectangle { width: parent.width; height: 1; color: "#455A64" }

        Label { color: "#80DEEA"; font.bold: true; text: qsTr("Zarzycki — liczby wskaźnikowe (PL)") }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "white"
          text: qsTr("światło Ś:") + metaPanelOkno.w(metaPanelOkno.m.L_N)
              + qsTr("   temp. T:") + metaPanelOkno.w(metaPanelOkno.m.T_N)
              + qsTr("   wilg. W:") + metaPanelOkno.w(metaPanelOkno.m.W_N)
              + qsTr("   trofizm Tr:") + metaPanelOkno.w(metaPanelOkno.m.TR_N)
              + qsTr("   odczyn R:") + metaPanelOkno.w(metaPanelOkno.m.R_N)
        }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "#B0BEC5"
          text: qsTr("granulom. D:") + metaPanelOkno.w(metaPanelOkno.m.D_N)
              + qsTr("   humus H:") + metaPanelOkno.w(metaPanelOkno.m.H_N)
              + qsTr("   mat.org. M:") + metaPanelOkno.w(metaPanelOkno.m.M_N)
              + qsTr("   kontynent. K:") + metaPanelOkno.w(metaPanelOkno.m.K_N)
              + qsTr("   zasol. S:") + metaPanelOkno.w(metaPanelOkno.m.S_N)
        }

        Rectangle { width: parent.width; height: 1; color: "#455A64" }

        Label { color: "#80DEEA"; font.bold: true; text: qsTr("Ellenberg EIV (Tichý/Chytrý 2023) — źródło: ") + metaPanelOkno.w(metaPanelOkno.m.EIV_ZRODLO) }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "white"
          text: qsTr("światło L:") + metaPanelOkno.w(metaPanelOkno.m.EIV_L)
              + qsTr("   temp. T:") + metaPanelOkno.w(metaPanelOkno.m.EIV_T)
              + qsTr("   wilg. M:") + metaPanelOkno.w(metaPanelOkno.m.EIV_M)
              + qsTr("   odczyn R:") + metaPanelOkno.w(metaPanelOkno.m.EIV_R)
              + qsTr("   żyzność N:") + metaPanelOkno.w(metaPanelOkno.m.EIV_N)
              + qsTr("   zasol. S:") + metaPanelOkno.w(metaPanelOkno.m.EIV_S)
        }

        Rectangle { width: parent.width; height: 1; color: "#455A64" }

        Label { color: "#80DEEA"; font.bold: true; text: qsTr("Zaburzenia (Midolo 2023)") }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "white"
          text: qsTr("nasilenie: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_SEVERITY)
              + qsTr("   częstość: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_FREQUENCY)
              + qsTr("   koszenie: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_MOWING)
              + qsTr("   wypas: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_GRAZING)
              + qsTr("   gleba: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_SOIL)
        }

        Rectangle { width: parent.width; height: 1; color: "#455A64" }

        Label { color: "#80DEEA"; font.bold: true; text: qsTr("Fitosocjologia (atlas-roslin.pl)") }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "white"
          text: qsTr("Klasa: ") + metaPanelOkno.w(metaPanelOkno.m.UP_CL)
              + qsTr("\nRząd: ") + metaPanelOkno.w(metaPanelOkno.m.UP_O)
              + qsTr("\nZwiązek: ") + metaPanelOkno.w(metaPanelOkno.m.UP_ALL)
              + qsTr("\nZespół: ") + metaPanelOkno.w(metaPanelOkno.m.UP_ASS)
        }
        Label {
          visible: metaPanelOkno.w(metaPanelOkno.m.NAWIAZANIE_FITOSOCJOLOGICZNE) !== "—"
          width: parent.width; wrapMode: Text.WordWrap; color: "#B0BEC5"
          text: metaPanelOkno.w(metaPanelOkno.m.NAWIAZANIE_FITOSOCJOLOGICZNE)
        }

        Row {
          spacing: 8

          Button {
            visible: metaPanelOkno.m.GATUNEK !== undefined
            text: qsTr("🌐 atlas-roslin.pl")
            onClicked: Qt.openUrlExternally("https://atlas-roslin.pl/gatunki/"
                + String(metaPanelOkno.m.GATUNEK).trim().replace(/ /g, "_") + ".htm")
          }

          Button {
            text: qsTr("Zamknij")
            onClicked: metaPanelOkno.close()
          }
        }
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

  // Podkatalogi DCIM: konwencja zalacznikow trzyma pliki obiektu w katalogu
  // <warstwa>_<klucz>. Kosz (.kosz) jest ukryty, wiec nie wchodzi do modelu.
  FolderListModel {
    id: katalogiDcim
    folder: photoGallery.projectDir !== "" ? "file://" + photoGallery.projectDir + "/DCIM" : ""
    showDirs: true
    showFiles: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
    onCountChanged: photoGallery.rebuildPhotos()
  }

  Item {
    visible: false
    Repeater {
      id: podkatalogiDcim
      model: katalogiDcim
      delegate: Item {
        required property string fileName
        required property string filePath
        property string nazwaKatalogu: fileName
        property alias modelPlikow: plikiPodkatalogu
        FolderListModel {
          id: plikiPodkatalogu
          folder: "file://" + filePath
          nameFilters: ["*.jpg", "*.jpeg", "*.JPG", "*.JPEG", "*.png", "*.PNG"]
          showDirs: false
          sortField: FolderListModel.Time
          onCountChanged: photoGallery.rebuildPhotos()
        }
      }
    }
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

      // WorkField: zakładki zbite do lewej — miejsce na kolejne
      // przeglądarki (Gatunki, Analizy) zamiast rozciągania trzech
      Layout.alignment: Qt.AlignLeft

      TabButton {
        text: qsTr("Zdjęcia")
        width: implicitWidth
      }
      TabButton {
        text: qsTr("Pliki")
        width: implicitWidth
      }
      TabButton {
        text: qsTr("Chmura")
        width: implicitWidth
      }
      TabButton {
        text: qsTr("Tagi")
        width: implicitWidth
      }
      TabButton {
        text: qsTr("Tabele")
        width: implicitWidth
      }
    }

    // WorkField: masowe wskazywanie gatunków na miniaturach
    RowLayout {
      Layout.fillWidth: true
      visible: galleryTabs.currentIndex === 0
      spacing: 8

      Button {
        checkable: true
        checked: photoGallery.trybMasowy
        text: checked ? qsTr("Wskazywanie na miniaturach — klikaj w zdjęcia") : qsTr("Wskazuj na miniaturach")
        font: photoGallery.t.tinyFont
        Material.background: checked ? "#00695C" : undefined
        onToggled: photoGallery.trybMasowy = checked
      }

      Rectangle {
        visible: photoGallery.trybMasowy && tagInput.text.trim() !== ""
        width: 12
        height: 12
        radius: 6
        color: photoGallery.tagColor(tagInput.text.trim())
        border.color: "white"
        border.width: 1
      }

      TextField {
        Layout.fillWidth: true
        visible: photoGallery.trybMasowy
        placeholderText: qsTr("Gatunek pędzla…")
        text: tagInput.text
        font: photoGallery.t.tipFont
        onTextEdited: tagInput.text = text
      }
    }

    // WorkField: podręczna lista gatunków dla trybu masowego —
    // klik ustawia pędzel, bez otwierania zdjęcia
    ListView {
      id: masowaLista

      Layout.fillWidth: true
      Layout.preferredHeight: visible ? 140 : 0
      visible: photoGallery.trybMasowy && galleryTabs.currentIndex === 0
      clip: true
      model: tagPanel.suggestions

      onVisibleChanged: {
        if (visible)
          tagPanel.updateSuggestions();
      }

      ScrollBar.vertical: ScrollBar {
      }

      delegate: ItemDelegate {
        required property var modelData

        width: masowaLista.width
        height: 30

        background: Rectangle {
          color: tagInput.text.trim() === modelData.name ? photoGallery.t.mainColor : "transparent"
          radius: 4
        }

        contentItem: RowLayout {
          spacing: 6

          Rectangle {
            Layout.leftMargin: 6
            width: 10
            height: 10
            radius: 5
            color: photoGallery.tagColor(modelData.name)
            border.color: "white"
            border.width: 1
          }

          Text {
            Layout.fillWidth: true
            text: modelData.name
            font: photoGallery.t.tipFont
            color: tagInput.text.trim() === modelData.name ? "white" : photoGallery.t.mainTextColor
            elide: Text.ElideRight
          }

          Text {
            Layout.rightMargin: 8
            text: modelData.n > 0 ? modelData.n : ""
            font: photoGallery.t.tinyFont
            color: photoGallery.t.secondaryTextColor
          }
        }

        onClicked: tagInput.text = modelData.name
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
        if (currentIndex === 3) {
          widokTagow.odswiez();
        }
        if (currentIndex === 4) {
          zakladkaTabele.inicjuj();
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
          cellWidth: Math.floor(width / Math.max(2, Math.floor(width / photoGallery.rozmiarKafla)))
          cellHeight: cellWidth
          model: photoGallery.photos

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
              if (wheel.modifiers & Qt.ControlModifier) {
                photoGallery.rozmiarKafla = Math.max(96, Math.min(360, photoGallery.rozmiarKafla + (wheel.angleDelta.y > 0 ? 16 : -16)));
                settings.setValue('WorkField/galeriaKafel', photoGallery.rozmiarKafla);
              } else {
                wheel.accepted = false;
              }
            }
          }

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
              id: miniatura

              anchors.fill: parent
              anchors.margins: 2
              source: "file://" + modelData.path
              asynchronous: true
              autoTransform: true
              // w trybie masowym dopasowanie: kadrowana miniatura
              // kłamałaby o współrzędnych kliknięcia
              fillMode: photoGallery.trybMasowy ? Image.PreserveAspectFit : Image.PreserveAspectCrop
              // klucz wydajnosci: dekodujemy miniature, nie 12 Mpix
              sourceSize.width: 256
              sourceSize.height: 256

              readonly property string wzglednaSciezka: modelData.path.substring(photoGallery.projectDir.length + 1)
              readonly property real kadrX: (width - paintedWidth) / 2
              readonly property real kadrY: (height - paintedHeight) / 2

              // znaczniki wskazań na miniaturze (tryb masowy)
              Repeater {
                model: {
                  if (!photoGallery.trybMasowy)
                    return [];
                  const wersja = photoGallery.wersjaTagow;
                  return tagStore.tagsForPhoto(miniatura.wzglednaSciezka).filter(t => t.x !== undefined && t.x !== null && t.x >= 0);
                }

                delegate: Rectangle {
                  required property var modelData

                  x: miniatura.kadrX + modelData.x * miniatura.paintedWidth - 5
                  y: miniatura.kadrY + modelData.y * miniatura.paintedHeight - 5
                  width: 10
                  height: 10
                  radius: 5
                  color: photoGallery.tagColor(modelData.tag)
                  border.color: "white"
                  border.width: 1.5

                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      tagStore.removeTag(parent.modelData.fid);
                      photoGallery.wersjaTagow++;
                    }
                  }
                }
              }
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

            // WorkField: pasek kropek — kolory gatunków otagowanych na zdjęciu
            Row {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.margins: 4
              spacing: 3

              Repeater {
                model: {
                  const wersja = photoGallery.wersjaTagow;
                  const rel = modelData.path.substring(photoGallery.projectDir.length + 1);
                  const tagi = tagStore.tagsForPhoto(rel);
                  const rozne = [];
                  for (let i = 0; i < tagi.length && rozne.length < 6; i++) {
                    if (rozne.indexOf(tagi[i].tag) < 0)
                      rozne.push(tagi[i].tag);
                  }
                  return rozne;
                }

                delegate: Rectangle {
                  required property string modelData

                  width: 9
                  height: 9
                  radius: 4.5
                  color: photoGallery.tagColor(modelData)
                  border.color: "white"
                  border.width: 1
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              z: -1
              cursorShape: photoGallery.trybMasowy && tagInput.text.trim() !== "" ? Qt.CrossCursor : Qt.ArrowCursor

              onClicked: mouse => {
                if (!photoGallery.trybMasowy) {
                  viewer.openList(photoGallery.photos, index);
                  return;
                }
                // wskazanie w punkcie kliknięcia, przez prostokąt kadru
                const gat = tagInput.text.trim();
                if (gat === "" || miniatura.paintedWidth <= 0)
                  return;
                const p = miniatura.mapFromItem(parent, mouse.x, mouse.y);
                const nx = (p.x - miniatura.kadrX) / miniatura.paintedWidth;
                const ny = (p.y - miniatura.kadrY) / miniatura.paintedHeight;
                if (nx < 0 || nx > 1 || ny < 0 || ny > 1)
                  return;
                if (tagStore.addTag(miniatura.wzglednaSciezka, gat, -1, "", nx, ny) >= 0) {
                  photoGallery.wersjaTagow++;
                  tagPanel.updateSuggestions();
                }
              }

              onDoubleClicked: {
                if (photoGallery.trybMasowy)
                  viewer.openList(photoGallery.photos, index);
              }
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

        // ---- Zwrot biezacego projektu na chmure (plik po pliku, WebDAV) ----
        QtObject {
          id: zwrot

          property bool wToku: false
          property var katalogi: []
          property var pliki: []
          property int indeksKatalogu: 0
          property int indeksPliku: 0
          property string bazaLokalna: ""
          property string bazaZdalna: ""
          property string oczekiwany: ""

          function start() {
            if (wToku) {
              return;
            }
            if (!photoGallery.chmuraKonto) {
              displayToast(qsTr("Zwrot wymaga konta zespołowego (login i hasło aplikacji w ustawieniach chmury)"), "warning");
              return;
            }
            if (!qgisProject || photoGallery.projectDir === "") {
              displayToast(qsTr("Brak otwartego projektu"), "warning");
              return;
            }
            bazaLokalna = photoGallery.projectDir;
            const teraz = new Date();
            const znacznik = Qt.formatDateTime(teraz, "yyyy-MM-dd_HHmm");
            const nazwa = FileUtils.fileName(bazaLokalna) + "_" + znacznik + "_zwrot";
            bazaZdalna = photoGallery.chmuraSerwer + "/remote.php/dav/files/" + photoGallery.chmuraLogin + "/WorkField/Kopie/" + photoGallery.chmuraLogin + "/" + nazwa;
            katalogi = iface.listDirsRecursively(bazaLokalna);
            pliki = iface.listFilesRecursively(bazaLokalna);
            if (pliki.length === 0) {
              displayToast(qsTr("Katalog projektu jest pusty — nie ma czego wysyłać"), "warning");
              return;
            }
            wToku = true;
            indeksKatalogu = -3;
            indeksPliku = 0;
            // struktura firmowa pod /WorkField: kolejno WorkField, Kopie,
            // Kopie/<login>, baza zwrotu, podkatalogi
            oczekiwany = photoGallery.chmuraSerwer + "/remote.php/dav/files/" + photoGallery.chmuraLogin + "/WorkField";
            photoGallery.chmuraStan = qsTr("zwrot: przygotowuję katalogi…");
            iface.webdavMkcolAuth(oczekiwany, photoGallery.chmuraLogin, photoGallery.chmuraHaslo);
          }

          function nastepnyKatalog() {
            indeksKatalogu += 1;
            if (indeksKatalogu === -2) {
              oczekiwany = photoGallery.chmuraSerwer + "/remote.php/dav/files/" + photoGallery.chmuraLogin + "/WorkField/Kopie";
            } else if (indeksKatalogu === -1) {
              oczekiwany = photoGallery.chmuraSerwer + "/remote.php/dav/files/" + photoGallery.chmuraLogin + "/WorkField/Kopie/" + photoGallery.chmuraLogin;
            } else if (indeksKatalogu === 0) {
              oczekiwany = bazaZdalna;
            } else if (indeksKatalogu <= katalogi.length) {
              oczekiwany = bazaZdalna + "/" + katalogi[indeksKatalogu - 1];
            } else {
              nastepnyPlik();
              return;
            }
            iface.webdavMkcolAuth(oczekiwany, photoGallery.chmuraLogin, photoGallery.chmuraHaslo);
          }

          function nastepnyPlik() {
            if (indeksPliku >= pliki.length) {
              wToku = false;
              photoGallery.chmuraStan = "";
              displayToast(qsTr("Zwrot wysłany na chmurę: %1 plików → WorkField/Kopie/%2").arg(pliki.length).arg(photoGallery.chmuraLogin));
              if (typeof quickCaptureBar !== 'undefined') {
                quickCaptureBar.haptyka(80);
              }
              return;
            }
            const wzgledna = pliki[indeksPliku];
            oczekiwany = bazaLokalna + "/" + wzgledna;
            photoGallery.chmuraStan = qsTr("zwrot: %1 / %2 — %3").arg(indeksPliku + 1).arg(pliki.length).arg(wzgledna);
            iface.uploadFileAuth(bazaZdalna + "/" + wzgledna, oczekiwany, photoGallery.chmuraLogin, photoGallery.chmuraHaslo);
          }

          function porazka(gdzie, blad) {
            wToku = false;
            photoGallery.chmuraStan = "";
            displayToast(qsTr("Zwrot przerwany (%1): %2 — częściowy folder pozostał na chmurze, ponowna wysyłka nadpisze").arg(gdzie).arg(blad), "error");
          }
        }

        Connections {
          target: iface
          enabled: zwrot.wToku

          function onMkcolFinished(url) {
            if (url === zwrot.oczekiwany) {
              zwrot.nastepnyKatalog();
            }
          }

          function onMkcolFailed(blad, url) {
            if (url === zwrot.oczekiwany) {
              zwrot.porazka(qsTr("katalog"), blad);
            }
          }

          function onUploadFinished(path) {
            if (path === zwrot.oczekiwany) {
              zwrot.indeksPliku += 1;
              zwrot.nastepnyPlik();
            }
          }

          function onUploadFailed(blad, path) {
            if (path === zwrot.oczekiwany) {
              zwrot.porazka(qsTr("plik"), blad);
            }
          }
        }

        QfButton {
          Layout.fillWidth: true
          visible: photoGallery.chmuraKonto
          enabled: !zwrot.wToku
          text: zwrot.wToku ? qsTr("Wysyłanie zwrotu…") : qsTr("Wyślij zwrot bieżącego projektu na chmurę")
          onClicked: zwrot.start()
        }

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

      // ── Tagi ───────────────────────────────────────────────
      RowLayout {
        id: widokTagow

        spacing: 8

        property var statystyki: []
        property string wybranyTag: ""
        property var zdjeciaTagu: []

        function odswiez() {
          statystyki = tagStore.tagStats(500);
          if (wybranyTag !== "") {
            zdjeciaTagu = tagStore.photosForTag(wybranyTag);
          }
        }

        function wybierz(tag) {
          wybranyTag = tag;
          zdjeciaTagu = tagStore.photosForTag(tag);
        }

        function absolutna(wzgledna) {
          return photoGallery.projectDir + "/" + wzgledna;
        }

        ColumnLayout {
          Layout.preferredWidth: 230
          Layout.fillHeight: true
          spacing: 4

          RowLayout {
            Layout.fillWidth: true

            Text {
              Layout.fillWidth: true
              text: qsTr("Tagi projektu (%1)").arg(widokTagow.statystyki.length)
              font: photoGallery.t.strongTipFont
              color: photoGallery.t.mainTextColor
            }

            ToolButton {
              text: qsTr("Wycinki")
              font: photoGallery.t.tinyFont
              ToolTip.visible: hovered
              ToolTip.text: qsTr("Wytnij kwadraty 500 px wokół wszystkich wskazań do WFG_Trening/ (zbiór treningowy)")
              onClicked: {
                const w = tagStore.exportujWycinki(500);
                displayToast(qsTr("Wycinki: %1 z %2 zdjęć → %3").arg(w.wycinkow).arg(w.zdjec).arg(w.katalog));
              }
            }
          }

          ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: widokTagow.statystyki
            ScrollBar.vertical: QfScrollBar {
            }

            delegate: ItemDelegate {
              required property var modelData

              width: ListView.view.width
              height: 34
              padding: 0

              background: Rectangle {
                color: widokTagow.wybranyTag === modelData.tag ? photoGallery.t.mainColor : "transparent"
                radius: 5
              }

              contentItem: RowLayout {
                spacing: 6

                Text {
                  Layout.fillWidth: true
                  Layout.leftMargin: 8
                  text: modelData.tag
                  font: photoGallery.t.tipFont
                  color: widokTagow.wybranyTag === modelData.tag ? "white" : photoGallery.t.mainTextColor
                  elide: Text.ElideRight
                }

                Text {
                  Layout.rightMargin: 8
                  text: modelData.n
                  font: photoGallery.t.tinyFont
                  color: widokTagow.wybranyTag === modelData.tag ? "white" : photoGallery.t.secondaryTextColor
                }
              }

              onClicked: widokTagow.wybierz(modelData.tag)
            }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 4

          Text {
            Layout.fillWidth: true
            text: widokTagow.wybranyTag === "" ? qsTr("Wybierz tag z listy, aby zobaczyć zdjęcia") : qsTr("„%1” — zdjęć: %2").arg(widokTagow.wybranyTag).arg(widokTagow.zdjeciaTagu.length)
            font: photoGallery.t.tipFont
            color: photoGallery.t.secondaryTextColor
            elide: Text.ElideRight
          }

          GridView {
            id: siatkaTagu

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: widokTagow.zdjeciaTagu
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / Math.max(130, photoGallery.rozmiarKafla))))
            cellHeight: Math.round(cellWidth * 0.75)

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.NoButton
              onWheel: wheel => {
                if (wheel.modifiers & Qt.ControlModifier) {
                  photoGallery.rozmiarKafla = Math.max(96, Math.min(360, photoGallery.rozmiarKafla + (wheel.angleDelta.y > 0 ? 16 : -16)));
                  settings.setValue('WorkField/galeriaKafel', photoGallery.rozmiarKafla);
                } else {
                  wheel.accepted = false;
                }
              }
            }
            ScrollBar.vertical: QfScrollBar {
            }

            delegate: ItemDelegate {
              required property string modelData
              required property int index

              width: siatkaTagu.cellWidth - 6
              height: siatkaTagu.cellHeight - 6

              background: Rectangle {
                color: "#22000000"
                radius: 5
              }

              contentItem: Item {
                Image {
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  autoTransform: true
                  sourceSize.width: 340
                  source: "file://" + widokTagow.absolutna(modelData)
                }

                Row {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.margins: 4
                  spacing: 3

                  Repeater {
                    model: {
                      const wersja = photoGallery.wersjaTagow;
                      const tagi = tagStore.tagsForPhoto(modelData);
                      const rozne = [];
                      for (let i = 0; i < tagi.length && rozne.length < 6; i++) {
                        if (rozne.indexOf(tagi[i].tag) < 0)
                          rozne.push(tagi[i].tag);
                      }
                      return rozne;
                    }

                    delegate: Rectangle {
                      required property string modelData

                      width: 9
                      height: 9
                      radius: 4.5
                      color: photoGallery.tagColor(modelData)
                      border.color: "white"
                      border.width: 1
                    }
                  }
                }
              }

              onClicked: viewer.openList(widokTagow.zdjeciaTagu.map(w => ({
                    "path": widokTagow.absolutna(w)
                  })), index)
            }
          }
        }
      }

      // ── Tabele: przegladarka tabel danych (WorkField) ─────────
      ColumnLayout {
        id: zakladkaTabele
        spacing: 6

        property string plik: ""
        property var listaTabel: []
        property int aktywnyWiersz: -1

        function szer(k) {
          return Math.min(360, Math.max(90, modelTabeli.szerokoscKolumny(k) * 7 + 26));
        }

        //! przy pierwszym wejsciu: sprobuj dane.gpkg biezacego projektu
        function inicjuj() {
          if (plik !== "")
            return;
          const kandydat = photoGallery.projectDir + "/dane.gpkg";
          const t = modelTabeli.tabeleZPliku(kandydat);
          if (t.length > 0)
            ustawPlik(kandydat, t);
        }

        function ustawPlik(p, gotoweTabele) {
          plik = p;
          aktywnyWiersz = -1;
          listaTabel = gotoweTabele !== undefined ? gotoweTabele : modelTabeli.tabeleZPliku(p);
          if (listaTabel.length === 0)
            return;
          let i = listaTabel.indexOf("taksony");
          if (i < 0)
            i = 0;
          wyborTabeli.currentIndex = i;
          poleFiltra.text = "";
          modelTabeli.wczytaj(plik, listaTabel[i]);
        }

        TabelaModel {
          id: modelTabeli
        }

        FileDialog {
          id: dialogTabel
          title: qsTr("Wybierz plik z tabelami")
          nameFilters: [qsTr("Tabele danych (*.gpkg *.csv)"), qsTr("Wszystkie pliki (*)")]
          onAccepted: zakladkaTabele.ustawPlik(String(selectedFile).replace(/^file:\/\//, ""))
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          Button {
            text: qsTr("Plik…")
            onClicked: dialogTabel.open()
          }
          ComboBox {
            id: wyborTabeli
            Layout.preferredWidth: 250
            model: zakladkaTabele.listaTabel
            onActivated: {
              zakladkaTabele.aktywnyWiersz = -1;
              poleFiltra.text = "";
              modelTabeli.wczytaj(zakladkaTabele.plik, currentText);
            }
          }
          TextField {
            id: poleFiltra
            Layout.fillWidth: true
            placeholderText: qsTr("Filtr — szuka we wszystkich kolumnach")
            onTextChanged: {
              zakladkaTabele.aktywnyWiersz = -1;
              modelTabeli.ustawFiltr(text);
            }
          }
          Text {
            text: modelTabeli.liczbaWierszy === modelTabeli.liczbaWszystkich
                  ? qsTr("%1 wierszy").arg(modelTabeli.liczbaWszystkich)
                  : qsTr("%1 / %2").arg(modelTabeli.liczbaWierszy).arg(modelTabeli.liczbaWszystkich)
            font: photoGallery.t.tipFont
            color: Theme.secondaryTextColor
          }
        }

        Text {
          Layout.fillWidth: true
          text: modelTabeli.komunikat !== "" ? modelTabeli.komunikat
              : (zakladkaTabele.plik !== "" ? zakladkaTabele.plik
                 : qsTr("Wybierz plik GPKG lub CSV — np. dane.gpkg projektu albo tabele z szablony/wskazniki"))
          font: photoGallery.t.tinyFont
          color: Theme.secondaryTextColor
          elide: Text.ElideMiddle
        }

        // naglowek: klik sortuje (drugi klik odwraca), przewija sie razem z tabela
        Flickable {
          Layout.fillWidth: true
          Layout.preferredHeight: 32
          contentX: widokTabeli.contentX
          interactive: false
          clip: true

          Row {
            Repeater {
              model: modelTabeli.liczbaKolumn

              delegate: Rectangle {
                required property int index
                // zależność od liczbaWszystkich wymusza przeliczenie po wczytaniu
                width: (modelTabeli.liczbaWszystkich, zakladkaTabele.szer(index))
                height: 32
                color: Theme.mainColor
                border.color: Qt.darker(Theme.mainColor, 1.15)

                Text {
                  anchors.fill: parent
                  anchors.leftMargin: 6
                  anchors.rightMargin: 6
                  verticalAlignment: Text.AlignVCenter
                  text: modelTabeli.nazwaKolumny(parent.index)
                        + (modelTabeli.kolumnaSortowania === parent.index
                           ? (modelTabeli.sortMalejaco ? " ▾" : " ▴") : "")
                  color: "white"
                  font: photoGallery.t.strongTipFont
                  elide: Text.ElideRight
                }
                TapHandler {
                  onTapped: modelTabeli.sortuj(parent.index)
                }
              }
            }
          }
        }

        TableView {
          id: widokTabeli
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: modelTabeli
          columnSpacing: 0
          rowSpacing: 0
          Connections {
            target: modelTabeli
            function onZmieniona() {
              widokTabeli.forceLayout();
            }
          }
          columnWidthProvider: function (k) {
            return zakladkaTabele.szer(k);
          }
          rowHeightProvider: function (r) {
            return 30;
          }
          ScrollBar.vertical: ScrollBar {
          }
          ScrollBar.horizontal: ScrollBar {
          }

          delegate: Rectangle {
            required property int row
            required property int column
            required property var display

            implicitHeight: 30
            color: row === zakladkaTabele.aktywnyWiersz ? Qt.alpha(Theme.mainColor, 0.25)
                 : (row % 2 === 1 ? Qt.alpha(Theme.mainColor, 0.05) : "transparent")

            Text {
              anchors.fill: parent
              anchors.leftMargin: 6
              anchors.rightMargin: 6
              verticalAlignment: Text.AlignVCenter
              text: parent.display !== undefined && parent.display !== null ? parent.display : ""
              font: photoGallery.t.tipFont
              color: Theme.mainTextColor
              elide: Text.ElideRight
            }
            TapHandler {
              onTapped: zakladkaTabele.aktywnyWiersz = parent.row
              onDoubleTapped: {
                const wartosc = modelTabeli.komorka(parent.row, parent.column);
                platformUtilities.copyTextToClipboard(wartosc);
                displayToast(qsTr("Skopiowano: %1").arg(wartosc));
                zakladkaTabele.aktywnyWiersz = parent.row;
              }
            }
          }
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
    //! WorkField: klik na zdjęciu zapisuje tag ze współrzędnymi (0..1)
    property bool trybWskazywania: false
    //! tryb siatki pokrycia (point-quadrat): klik przypisuje gatunek komórce
    property bool trybSiatki: false
    property bool zrzutKadru: false
    //! pędzel pusty: komórka oceniona bez roślinności (mianownik 100%)
    property bool pedzelPusty: false

    //! aktywny pędzel: nazwa gatunku, "(pusta)" albo "" (gumka)
    function aktywnyPedzel() {
      return pedzelPusty ? "(pusta)" : tagInput.text.trim();
    }
    //! bok siatki: 5/7/10 => komórka 4%/~2%/1%; wybór zapamiętywany
    property int siatkaN: 5

    //! zbieg perspektywy 0..0.75: 0 = nadir (siatka prosta); z kąta
    //! nachylenia aparatu zapisanego w zdjęciu
    property real zbieg: 0
    //! obrót siatki w stopniach (±30): z Roll zdjęcia, suwak koryguje
    property real obrot: 0

    function wczytajZbieg() {
      zbieg = 0;
      obrot = 0;
      if (!cur)
        return;
      const poza = pozaAparatu.readPose(cur.path);
      if (poza.roll !== undefined)
        obrot = Math.max(-30, Math.min(30, -poza.roll));
      if (poza.pitch === undefined)
        return;
      // pitch: -90 = nadir, 0 = poziomo; im bliżej poziomu, tym
      // silniejszy zbieg rzutu równych pól terenu
      const odNadiru = Math.min(90, Math.abs(90 - Math.abs(poza.pitch)));
      zbieg = Math.min(0.75, Math.max(0, odNadiru / 90 * 0.75));
    }

    //! pozycja linii między wierszami: t=0 góra kadru, t=1 dół;
    //! równe pasy terenu gęstnieją ku górze przy zbiegu > 0
    function liniaY(t) {
      const s = 1 - zbieg;
      return 1 - (1 - t) * s / (1 - (1 - s) * (1 - t));
    }

    //! szerokość trapezu na wysokości linii t (część szerokości kadru)
    function liniaSzer(t) {
      return 1 - zbieg * (1 - t);
    }

    //! środek komórki (k, w) w współrzędnych kadru 0..1, PO rzucie
    function srodekKomorki(k, w) {
      const yA = liniaY(w / siatkaN);
      const yB = liniaY((w + 1) / siatkaN);
      const szA = liniaSzer(w / siatkaN);
      const szB = liniaSzer((w + 1) / siatkaN);
      const xA = (1 - szA) / 2 + szA * (k + 0.5) / siatkaN;
      const xB = (1 - szB) / 2 + szB * (k + 0.5) / siatkaN;
      // środek w układzie prostym -> piksele -> obrót siatki -> kadr
      const px = (xA + xB) / 2 * fullImage.width;
      const py = (yA + yB) / 2 * fullImage.height;
      const scS = Math.tan(obrot * Math.PI / 180);
      const ox = px + scS * (py - fullImage.height / 2);
      const oy = py;
      return {
        "x": ox / fullImage.width,
        "y": oy / fullImage.height
      };
    }

    //! tagi-węzły siatki bieżącego zdjęcia
    readonly property var tagiSiatki: curTags.filter(t => t.uwagi !== undefined && t.uwagi !== null && String(t.uwagi).indexOf("siatka " + siatkaN + " ") === 0)

    //! wszystkie wpisy komórki (kolumna k, wiersz w) — warstwy gatunków
    function wpisyWKomorce(k, w) {
      const wzor = "siatka " + siatkaN + " " + w + " " + k;
      return tagiSiatki.filter(t => String(t.uwagi) === wzor);
    }

    //! wpis danego gatunku w komórce albo null
    function wpisGatunku(k, w, gatunek) {
      const lista = wpisyWKomorce(k, w);
      for (let i = 0; i < lista.length; i++) {
        if (lista[i].tag === gatunek)
          return lista[i];
      }
      return null;
    }

    //! otwiera zdjęcie w systemowym edytorze; nasz plik i EXIF nietknięte
    function edytujZewnetrznie() {
      if (cur) {
        Qt.openUrlExternally("file://" + cur.path);
      }
    }

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
      photoGallery.wersjaTagow++;
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
      interactive: (contentWidth > width + 5 || contentHeight > height + 5) && (Qt.platform.os === "android" || Qt.platform.os === "ios")
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

          // Pozycję kadru liczymy SAMI: element ma dokładnie rozmiar
          // narysowanego zdjęcia i jest centrowany — wyrównanie wewnątrz
          // Image przy autoTransform bywa liczone przed obrotem EXIF
          // (objaw: kadr przyklejony do prawej, czarny pas z lewej)
          readonly property real skala: status == Image.Ready && implicitWidth > 0 ? Math.min((sideways ? flick.contentHeight : flick.contentWidth) / implicitWidth, (sideways ? flick.contentWidth : flick.contentHeight) / implicitHeight) : 1

          width: implicitWidth * skala
          height: implicitHeight * skala
          anchors.centerIn: parent
          rotation: sideways ? 90 : 0
          source: viewer.cur ? "file://" + viewer.cur.path : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          autoTransform: true

          // plakietka pędzla: aktywny gatunek + zbieg; klik = zmiana gatunku
          Rectangle {
            id: plakietkaPedzla

            visible: (viewer.trybSiatki || viewer.trybWskazywania) && viewer.aktywnyPedzel() !== "" && !viewer.zrzutKadru
            x: 10
            y: 10
            z: 50
            width: pedzelWiersz.implicitWidth + 18
            height: 30
            radius: 15
            color: "#D9000000"

            Row {
              id: pedzelWiersz

              anchors.centerIn: parent
              spacing: 7

              Rectangle {
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                color: viewer.pedzelPusty ? "#9E9E9E" : photoGallery.tagColor(tagInput.text.trim())
                border.color: "white"
                border.width: 1.5
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (viewer.pedzelPusty ? qsTr("∅ pusta") : tagInput.text.trim()) + (viewer.trybSiatki && viewer.zbieg > 0 ? qsTr("  ·  zbieg %1%").arg(Math.round(viewer.zbieg * 100)) : "")
                color: "white"
                font: photoGallery.t.tipFont
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                color: "#B0BEC5"
                font: photoGallery.t.tipFont
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                tagInput.text = "";
                tagInput.forceActiveFocus();
              }
            }
          }

          // nakładka siatki pokrycia: jasne linie z perspektywą,
          // zajęte komórki wypełnione półprzezroczystym kolorem gatunku
          Canvas {
            id: siatkaCanvas

            anchors.fill: parent
            visible: viewer.trybSiatki && !viewer.zrzutKadru

            onPaint: {
              const ctx = getContext("2d");
              ctx.clearRect(0, 0, width, height);
              const N = viewer.siatkaN;
              ctx.save();
              // ścinanie: x' = x + s*(y - H/2); poziome linie zostają poziome
              const pochyl = Math.tan(viewer.obrot * Math.PI / 180);
              ctx.transform(1, 0, pochyl, 1, -pochyl * height / 2, 0);

              // wypełnienia zajętych komórek (czworokąty trapezu)
              for (let w = 0; w < N; w++) {
                const yG = viewer.liniaY(w / N) * height;
                const yD = viewer.liniaY((w + 1) / N) * height;
                const szG = viewer.liniaSzer(w / N) * width;
                const szD = viewer.liniaSzer((w + 1) / N) * width;
                for (let k = 0; k < N; k++) {
                  const wpisy = viewer.wpisyWKomorce(k, w);
                  if (wpisy.length === 0)
                    continue;
                  // pionowe pasy: po jednym na gatunek w komórce
                  const x0G = (width - szG) / 2 + szG * k / N;
                  const x1G = (width - szG) / 2 + szG * (k + 1) / N;
                  const x0D = (width - szD) / 2 + szD * k / N;
                  const x1D = (width - szD) / 2 + szD * (k + 1) / N;
                  ctx.globalAlpha = 0.35;
                  for (let p = 0; p < wpisy.length; p++) {
                    const a = p / wpisy.length;
                    const b = (p + 1) / wpisy.length;
                    // zagęszczenie: pas wypełniony od dołu w u częściach
                    const pokP = wpisy[p].pokrycie;
                    const u = (wpisy[p].tag === "(pusta)" || pokP === undefined || pokP === null || pokP < 0 || pokP > 100) ? 1 : pokP / 100;
                    const yF = yD + (yG - yD) * u;
                    const x0F = x0D + (x0G - x0D) * u;
                    const x1F = x1D + (x1G - x1D) * u;
                    ctx.fillStyle = wpisy[p].tag === "(pusta)" ? "#9E9E9E" : photoGallery.tagColor(wpisy[p].tag);
                    ctx.beginPath();
                    ctx.moveTo(x0F + (x1F - x0F) * a, yF);
                    ctx.lineTo(x0F + (x1F - x0F) * b, yF);
                    ctx.lineTo(x0D + (x1D - x0D) * b, yD);
                    ctx.lineTo(x0D + (x1D - x0D) * a, yD);
                    ctx.closePath();
                    ctx.fill();
                  }
                  ctx.globalAlpha = 1.0;
                }
              }

              // linie siatki
              ctx.strokeStyle = "#C8FFFFFF";
              ctx.lineWidth = 1.2;
              for (let w = 0; w <= N; w++) {
                const y = viewer.liniaY(w / N) * height;
                const sz = viewer.liniaSzer(w / N) * width;
                ctx.beginPath();
                ctx.moveTo((width - sz) / 2, y);
                ctx.lineTo((width + sz) / 2, y);
                ctx.stroke();
              }
              for (let k = 0; k <= N; k++) {
                const szG = viewer.liniaSzer(0) * width;
                const szD = viewer.liniaSzer(1) * width;
                ctx.beginPath();
                ctx.moveTo((width - szG) / 2 + szG * k / N, viewer.liniaY(0) * height);
                ctx.lineTo((width - szD) / 2 + szD * k / N, viewer.liniaY(1) * height);
                ctx.stroke();
              }
              ctx.restore();
            }

            Connections {
              target: viewer
              function onCurTagsChanged() {
                siatkaCanvas.requestPaint();
              }
              function onTrybSiatkiChanged() {
                viewer.wczytajZbieg();
                siatkaCanvas.requestPaint();
              }
              function onIdxChanged() {
                viewer.wczytajZbieg();
                siatkaCanvas.requestPaint();
              }
              function onZbiegChanged() {
                siatkaCanvas.requestPaint();
              }
              function onSiatkaNChanged() {
                siatkaCanvas.requestPaint();
              }
              function onObrotChanged() {
                siatkaCanvas.requestPaint();
              }
            }
          }

          // znaczniki wskazań (tagi z zapisanymi współrzędnymi);
          // w trybie wskazywania klik w znacznik usuwa wskazanie
          Repeater {
            model: viewer.curTags

            delegate: Item {
              id: znacznik

              required property var modelData

              visible: !viewer.zrzutKadru && modelData.x !== undefined && modelData.x !== null && modelData.x >= 0 && modelData.y >= 0 && !(viewer.trybSiatki && modelData.uwagi !== undefined && modelData.uwagi !== null && String(modelData.uwagi).indexOf("siatka") === 0)
              x: modelData.x * fullImage.width - 8
              y: modelData.y * fullImage.height - 8
              width: 16
              height: 16

              Rectangle {
                anchors.fill: parent
                radius: 8
                color: photoGallery.tagColor(znacznik.modelData.tag)
                border.color: "white"
                border.width: 2
              }

              Text {
                anchors.left: parent.right
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: viewer.trybWskazywania
                text: znacznik.modelData.tag
                font: photoGallery.t.tinyFont
                color: "white"
                style: Text.Outline
                styleColor: "black"
              }

              MouseArea {
                anchors.fill: parent
                enabled: viewer.trybWskazywania
                onClicked: {
                  tagStore.removeTag(znacznik.modelData.fid);
                  viewer.refreshTags();
                }
              }
            }
          }
        }

        MouseArea {
          id: obszarPodgladu

          anchors.fill: parent
          cursorShape: viewer.trybWskazywania || viewer.trybSiatki ? Qt.CrossCursor : Qt.ArrowCursor
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton

          property real pressX: 0
          property real pressY: 0

          onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
          }
          //! ostatnio zamalowana komórka podczas przeciągania ("w:k")
          property string ostatniaKomorka: ""

          onPositionChanged: mouse => {
            // WorkField: malowanie siatki przeciągnięciem (lewy przycisk)
            if (viewer.trybSiatki && (mouse.buttons & Qt.LeftButton) && viewer.aktywnyPedzel() !== "") {
              const pm = fullImage.mapFromItem(obszarPodgladu, mouse.x, mouse.y);
              if (pm.x >= 0 && pm.x <= fullImage.width && pm.y >= 0 && pm.y <= fullImage.height) {
                const scM = Math.tan(viewer.obrot * Math.PI / 180);
                const rxM = pm.x - scM * (pm.y - fullImage.height / 2);
                const ryM = pm.y;
                const sM = 1 - viewer.zbieg;
                const ynM = ryM / fullImage.height;
                const tWM = 1 - (1 - ynM) / (sM + (1 - sM) * (1 - ynM));
                const wM = Math.min(viewer.siatkaN - 1, Math.max(0, Math.floor(tWM * viewer.siatkaN)));
                const szWM = viewer.liniaSzer(tWM) * fullImage.width;
                const xwM = (rxM - (fullImage.width - szWM) / 2) / szWM;
                const kM = Math.min(viewer.siatkaN - 1, Math.max(0, Math.floor(xwM * viewer.siatkaN)));
                const kluczK = wM + ":" + kM;
                if (kluczK !== ostatniaKomorka) {
                  ostatniaKomorka = kluczK;
                  if (viewer.wpisGatunku(kM, wM, viewer.aktywnyPedzel()) === null) {
                    const cM = viewer.srodekKomorki(kM, wM);
                    if (tagStore.addTag(viewer.curRel, viewer.aktywnyPedzel(), viewer.aktywnyPedzel() === "(pusta)" ? -1 : 100, "siatka " + viewer.siatkaN + " " + wM + " " + kM, cM.x, cM.y) >= 0) {
                      viewer.refreshTags();
                    }
                  }
                }
              }
              return;
            }
            // WorkField: środkowy przycisk przesuwa powiększone zdjęcie
            if (mouse.buttons & Qt.MiddleButton) {
              flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - (mouse.x - pressX)));
              flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - (mouse.y - pressY)));
              pressX = mouse.x;
              pressY = mouse.y;
            }
          }
          onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton) {
              return;
            }
            if (viewer.trybSiatki) {
              obszarPodgladu.ostatniaKomorka = "";
            }
            // WorkField: siatka pokrycia — klik przypisuje/zwalnia węzeł
            if (viewer.trybSiatki && Math.abs(mouse.x - pressX) < 8 && Math.abs(mouse.y - pressY) < 8) {
              const ps = fullImage.mapFromItem(obszarPodgladu, mouse.x, mouse.y);
              if (ps.x >= 0 && ps.x <= fullImage.width && ps.y >= 0 && ps.y <= fullImage.height) {
                // odwrotność ścinania: x = x' - s*(y - H/2), y bez zmian
                const sc = Math.tan(viewer.obrot * Math.PI / 180);
                const rx = ps.x - sc * (ps.y - fullImage.height / 2);
                const ry = ps.y;
                // odwrócenie rzutu: z piksela do wiersza/kolumny trapezu
                const s = 1 - viewer.zbieg;
                const yn = ry / fullImage.height;
                const tW = 1 - (1 - yn) / (s + (1 - s) * (1 - yn));
                const w = Math.min(viewer.siatkaN - 1, Math.max(0, Math.floor(tW * viewer.siatkaN)));
                const szW = viewer.liniaSzer(tW) * fullImage.width;
                const xw = (rx - (fullImage.width - szW) / 2) / szW;
                const k = Math.min(viewer.siatkaN - 1, Math.max(0, Math.floor(xw * viewer.siatkaN)));
                const gat = viewer.aktywnyPedzel();
                if (gat === "") {
                  // gumka: pusty pędzel czyści całą komórkę
                  const lista = viewer.wpisyWKomorce(k, w);
                  for (let i = 0; i < lista.length; i++)
                    tagStore.removeTag(lista[i].fid);
                  if (lista.length > 0)
                    viewer.refreshTags();
                } else {
                  const istn = viewer.wpisGatunku(k, w, gat);
                  if (gat === "(pusta)") {
                    // pusta bez cyklu: jest albo nie ma
                    if (istn !== null) {
                      tagStore.removeTag(istn.fid);
                      viewer.refreshTags();
                    } else {
                      const cP = viewer.srodekKomorki(k, w);
                      if (tagStore.addTag(viewer.curRel, gat, -1, "siatka " + viewer.siatkaN + " " + w + " " + k, cP.x, cP.y) >= 0)
                        viewer.refreshTags();
                    }
                  } else {
                    // cykl zagęszczenia: 0 -> 25 -> 50 -> 75 -> 100 -> 0
                    let stare = 0;
                    if (istn !== null) {
                      const pokI = istn.pokrycie;
                      stare = (pokI === undefined || pokI === null || pokI < 0 || pokI > 100) ? 100 : pokI;
                      tagStore.removeTag(istn.fid);
                    }
                    const nowe = stare >= 100 ? 0 : stare + 25;
                    if (nowe > 0) {
                      const c = viewer.srodekKomorki(k, w);
                      if (tagStore.addTag(viewer.curRel, gat, nowe, "siatka " + viewer.siatkaN + " " + w + " " + k, c.x, c.y) >= 0)
                        tagPanel.updateSuggestions();
                    }
                    viewer.refreshTags();
                  }
                }
              }
              return;
            }
            if (viewer.trybSiatki) {
              // po malowaniu przeciągnięciem nie zmieniamy zdjęcia gestem
              return;
            }
            // WorkField: wskazanie gatunku — klik (nie przeciągnięcie)
            // zapisuje tag w miejscu kliknięcia, względem kadru zdjęcia
            if (viewer.trybWskazywania && tagInput.text.trim() !== "" && Math.abs(mouse.x - pressX) < 8 && Math.abs(mouse.y - pressY) < 8) {
              const punkt = fullImage.mapFromItem(obszarPodgladu, mouse.x, mouse.y);
              if (punkt.x >= 0 && punkt.x <= fullImage.width && punkt.y >= 0 && punkt.y <= fullImage.height) {
                const pok = pokInput.text !== "" ? parseInt(pokInput.text) : -1;
                const fid = tagStore.addTag(viewer.curRel, tagInput.text.trim(), pok, "", punkt.x / fullImage.width, punkt.y / fullImage.height);
                if (fid >= 0) {
                  viewer.refreshTags();
                  tagPanel.updateSuggestions();
                } else {
                  displayToast(qsTr("Nie udało się zapisać wskazania"));
                }
              }
              return;
            }
            if (!flick.interactive && (Qt.platform.os === "android" || Qt.platform.os === "ios")) {
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

      // ---- Pl@ntNet w tagowaniu (wspolne ustawienia z wtyczka) ----
      property bool pnBusy: false
      property string pnStatus: ""
      property var pnResults: []
      // organy honorowane przez API; przelaczane przyciskiem obok
      readonly property var pnOrgany: ["leaf", "flower", "fruit", "bark"]
      readonly property var pnOrganPL: ({
          "leaf": qsTr("liść"),
          "flower": qsTr("kwiat"),
          "fruit": qsTr("owoc"),
          "bark": qsTr("kora")
        })

      function pnKlucz() {
        return String(settings.value("WorkFieldPlantNet/apiKey", "")).trim();
      }

      function pnStr2bytes(txt) {
        const u = unescape(encodeURIComponent(txt));
        const arr = new Uint8Array(u.length);
        for (let i = 0; i < u.length; i++)
          arr[i] = u.charCodeAt(i);
        return arr;
      }

      // dopasowanie do slownika projektu: kanonicznie po czlonie lacinskim
      // ("Abies alba" == "Abies alba - jodla pospolita [aba]"); pelniejsza
      // forma ze slownika wygrywa; brak w slowniku -> nazwa z Pl@ntNet
      function pnDopasujDoSlownika(lacina) {
        const k = String(lacina).trim().toLowerCase();
        for (let i = 0; i < suggestions.length; i++) {
          const s = suggestions[i].name;
          if (s.split(" - ")[0].trim().toLowerCase() === k)
            return s;
        }
        return String(lacina).trim();
      }

      function pnFlora() {
        const tryb = String(settings.value("WorkFieldPlantNet/flora", "auto-geo"));
        if (tryb !== "auto-geo")
          return tryb;
        const d = new Date();
        const dzis = d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
        // flora ustalona dzis przez wtyczke (auto-geo z pozycji) jest dobra
        // i dla galerii; bez niej bezpieczny domysl dla naszego terenu
        if (String(settings.value("WorkFieldPlantNet/autoFloraDay", "")) === dzis) {
          const id = String(settings.value("WorkFieldPlantNet/autoFloraId", ""));
          if (id !== "")
            return id;
        }
        return "k-middle-europe";
      }

      function pnIdentify(sciezkaKadru) {
        if (!viewer.cur)
          return;
        const sciezkaFoto = (typeof sciezkaKadru === "string" && sciezkaKadru !== "") ? sciezkaKadru : viewer.cur.path;
        const czyKadr = sciezkaFoto !== viewer.cur.path;
        if (pnKlucz() === "") {
          pnStatus = qsTr("Wpisz klucz API Pl@ntNet poniżej (konto: my.plantnet.org)");
          return;
        }
        pnBusy = true;
        pnResults = [];
        pnStatus = qsTr("Czytam zdjęcie…");
        const zawartosc = FileUtils.readFileContent(sciezkaFoto);
        const dlugosc = (zawartosc && zawartosc.byteLength !== undefined) ? zawartosc.byteLength : -1;
        if (dlugosc <= 0) {
          pnBusy = false;
          pnStatus = qsTr("Zdjęcie nieczytelne: ") + viewer.curRel;
          return;
        }
        const organ = String(settings.value("WorkFieldPlantNet/organ", "leaf"));
        const boundary = "----WorkFieldPlantNetGaleria" + Date.now();
        const czesci = [];
        czesci.push(pnStr2bytes("--" + boundary + "\r\n" + 'Content-Disposition: form-data; name="organs"\r\n\r\n' + organ + "\r\n" + "--" + boundary + "\r\n" + 'Content-Disposition: form-data; name="images"; filename="' + FileUtils.fileName(sciezkaFoto) + '"\r\n' + "Content-Type: image/jpeg\r\n\r\n"));
        czesci.push(new Uint8Array(zawartosc));
        czesci.push(pnStr2bytes("\r\n--" + boundary + "--\r\n"));
        let suma = 0;
        for (let i = 0; i < czesci.length; i++)
          suma += czesci[i].length;
        const cialo = new Uint8Array(suma);
        let od = 0;
        for (let i = 0; i < czesci.length; i++) {
          cialo.set(czesci[i], od);
          od += czesci[i].length;
        }
        pnStatus = (czyKadr ? qsTr("Kadr → ") : "") + qsTr("Pytam Pl@ntNet (") + Math.round(dlugosc / 1024) + " KB, " + pnOrganPL[organ] + ", " + pnFlora() + ")…";
        const url = "https://my-api.plantnet.org/v2/identify/" + encodeURIComponent(pnFlora()) + "?api-key=" + encodeURIComponent(pnKlucz()) + "&lang=pl&nb-results=6";
        const xhr = new XMLHttpRequest();
        xhr.open("POST", url);
        xhr.timeout = 60000;
        xhr.ontimeout = function () {
          pnBusy = false;
          pnStatus = qsTr("Serwer nie odpowiedział w 60 s — sprawdź zasięg.");
        };
        xhr.setRequestHeader("Content-Type", "multipart/form-data; boundary=" + boundary);
        xhr.onreadystatechange = function () {
          if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
          pnBusy = false;
          if (xhr.status === 200) {
            pnPokazWyniki(xhr.responseText);
          } else if (xhr.status === 401) {
            pnStatus = qsTr("Błędny klucz API (401) — sprawdź na my.plantnet.org.");
          } else if (xhr.status === 404) {
            pnStatus = qsTr("Brak dopasowania w tej florze (404).");
          } else if (xhr.status === 413) {
            pnStatus = qsTr("Zdjęcie za duże (413).");
          } else if (xhr.status === 429) {
            pnStatus = qsTr("Wyczerpany dzienny limit zapytań (429).");
          } else if (xhr.status === 0) {
            pnStatus = qsTr("Brak sieci — spróbuj przy zasięgu.");
          } else {
            pnStatus = qsTr("Błąd serwera: ") + xhr.status;
          }
        };
        xhr.send(cialo.buffer);
      }

      function pnPokazWyniki(tekst) {
        try {
          const json = JSON.parse(tekst);
          const wyniki = json.results || [];
          if (wyniki.length === 0) {
            pnStatus = qsTr("Brak wyników.");
            return;
          }
          const out = [];
          for (let i = 0; i < wyniki.length && i < 6; i++) {
            const r = wyniki[i];
            const gat = r.species || ({});
            out.push({
                "score": Math.round((r.score || 0) * 100),
                "lacina": String(gat.scientificNameWithoutAuthor || "").trim(),
                "ludowa": (gat.commonNames || []).slice(0, 2).join(", ")
              });
          }
          pnStatus = "";
          pnResults = out;
        } catch (e) {
          pnStatus = qsTr("Nieczytelna odpowiedź serwera.");
        }
      }

      function skrocNazwe(n) {
        const cz = String(n).split(" ");
        return cz.length > 1 ? cz[0][0] + ". " + cz.slice(1).join(" ") : n;
      }

      // Porownuje cechy kandydatow Pl@ntNet obecnych w WF_CECHY.
      // Zwraca wiersze: {naglowek, tekst}. Najpierw cechy kluczowe,
      // potem maks. 3 kolumny, w ktorych kandydaci sie ROZNIA.
      function zbudujCechy(results) {
        if (!results || results.length === 0)
          return [];
        const kolejnosc = ["JEZYCZEK", "POCHWY", "BLASZKA", "OSCI", "ROZLOGI", "KWIATOSTAN", "POKROJ", "KLOSKI", "USZKA", "WYSOKOSC_CM", "SIEDLISKO", "KWITNIENIE"];
        const kand = [];
        for (let i = 0; i < results.length && kand.length < 3; i++) {
          const c = tagStore.speciesCechy(results[i].lacina);
          if (c && c.GATUNEK !== undefined)
            kand.push({ nazwa: String(c.GATUNEK), rob: String(c.WERYFIKACJA || "").trim() === "", c: c });
        }
        if (kand.length === 0)
          return [];
        const out = [];
        for (const k of kand) {
          const v = String(k.c.CECHA_KLUCZOWA || "").trim();
          if (v !== "")
            out.push({ naglowek: skrocNazwe(k.nazwa) + (k.rob ? " (rob.)" : ""), tekst: v });
        }
        if (kand.length >= 2) {
          let dodane = 0;
          for (const kn of kolejnosc) {
            const vals = kand.map(k => String(k.c[kn] || "").trim());
            if (vals.filter(v => v !== "").length < 2)
              continue;
            let rozne = false;
            for (let i = 1; i < vals.length; i++)
              if (vals[i] !== "" && vals[0] !== "" && vals[i] !== vals[0])
                rozne = true;
            if (!rozne)
              continue;
            out.push({ naglowek: "≠ " + kn.toLowerCase(), tekst: kand.map((k, i) => skrocNazwe(k.nazwa) + ": " + (vals[i] || "—")).join("   •   ") });
            if (++dodane >= 3)
              break;
          }
        }
        return out;
      }

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
          // klucz kanoniczny: człon łaciński przed " - " — "Abies alba"
          // i "Abies alba - jodła pospolita [aba]" to jeden gatunek;
          // wygrywa forma pełniejsza, liczniki użyć się sumują
          const k = nazwa.split(" - ")[0].trim().toLowerCase();
          if (seen[k] === undefined) {
            seen[k] = out.length;
            out.push({
                "name": nazwa,
                "n": n
              });
          } else {
            const w = out[seen[k]];
            w.n += n;
            if (nazwa.length > w.name.length)
              w.name = nazwa;
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
          onTextChanged: {
            tagPanel.updateSuggestions();
            // wybór gatunku sam wyłącza pędzel "∅ Pusta"
            if (text.trim() !== "")
              viewer.pedzelPusty = false;
          }
          onAccepted: addTagButton.clicked()
        }

        // WorkField: metadane gatunku — skrot; dotkniecie otwiera panel
        Label {
          id: metaLinia
          Layout.fillWidth: true
          visible: text !== ""
          font.pointSize: photoGallery.t.tinyFont.pointSize
          color: "#80DEEA"
          elide: Text.ElideRight

          property var meta: ({})

          text: {
            const m = metaLinia.meta;
            if (!m || m.GATUNEK === undefined)
              return "";
            const cz = [];
            if (m.L_N) cz.push("Ś" + m.L_N);
            if (m.W_N) cz.push("W" + m.W_N);
            if (m.TR_N) cz.push("Tr" + m.TR_N);
            if (m.R_N) cz.push("R" + m.R_N);
            let t = cz.join(" ");
            let zb = "";
            if (m.UP_ALL && String(m.UP_ALL).trim() !== "")
              zb = m.UP_ALL;
            else if (m.UP_O && String(m.UP_O).trim() !== "")
              zb = m.UP_O;
            else if (m.UP_CL && String(m.UP_CL).trim() !== "")
              zb = m.UP_CL;
            if (zb !== "")
              t += (t !== "" ? "  ·  " : "") + zb;
            return t === "" ? "" : "≡ " + t;
          }

          Timer {
            id: metaTimer
            interval: 350
            onTriggered: metaLinia.meta = tagInput.text.trim() !== "" ? tagStore.speciesMeta(tagInput.text) : ({})
          }

          Connections {
            target: tagInput
            function onTextChanged() {
              metaTimer.restart();
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: metaPanelOkno.pokaz(tagInput.text, metaLinia.meta)
          }
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

        // ---- Pl@ntNet: weryfikacja biezacego zdjecia (punkt 5a) ----
        RowLayout {
          Layout.fillWidth: true
          visible: viewer.cur !== null && viewer.cur !== undefined
          spacing: 6

          Button {
            Layout.fillWidth: true
            text: tagPanel.pnBusy ? qsTr("Pl@ntNet…") : qsTr("Sprawdź w Pl@ntNet")
            font: photoGallery.t.tipFont
            enabled: !tagPanel.pnBusy
            onClicked: tagPanel.pnIdentify()
          }

          Button {
            text: qsTr("Kadr")
            font: photoGallery.t.tipFont
            enabled: !tagPanel.pnBusy
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Rozpoznaj tylko widoczny wycinek — przybliż roślinę i kliknij")
            onClicked: {
              viewer.zrzutKadru = true;
              const ok = flick.grabToImage(function (wynik) {
                viewer.zrzutKadru = false;
                const sciezka = photoGallery.projectDir + "/DCIM/.wf_kadr.jpg";
                if (wynik.saveToFile(sciezka))
                  tagPanel.pnIdentify(sciezka);
                else
                  tagPanel.pnStatus = qsTr("Nie udało się zapisać kadru.");
              });
              if (!ok) {
                viewer.zrzutKadru = false;
                tagPanel.pnStatus = qsTr("Nie udało się pobrać kadru z podglądu.");
              }
            }
          }

          ToolButton {
            text: tagPanel.pnOrganPL[String(settings.value("WorkFieldPlantNet/organ", "leaf"))] || qsTr("liść")
            font: photoGallery.t.tipFont
            onClicked: {
              const teraz = String(settings.value("WorkFieldPlantNet/organ", "leaf"));
              const i = tagPanel.pnOrgany.indexOf(teraz);
              settings.setValue("WorkFieldPlantNet/organ", tagPanel.pnOrgany[(i + 1) % tagPanel.pnOrgany.length]);
              text = tagPanel.pnOrganPL[String(settings.value("WorkFieldPlantNet/organ", "leaf"))];
            }
          }
        }

        TextField {
          Layout.fillWidth: true
          visible: viewer.cur !== null && viewer.cur !== undefined && tagPanel.pnKlucz() === ""
          placeholderText: qsTr("Klucz API Pl@ntNet…")
          color: "white"
          placeholderTextColor: "#90A4AE"
          font: photoGallery.t.tipFont
          echoMode: TextInput.Password
          onEditingFinished: settings.setValue("WorkFieldPlantNet/apiKey", text.trim())
        }

        Label {
          Layout.fillWidth: true
          visible: tagPanel.pnStatus !== ""
          text: tagPanel.pnStatus
          color: "#FFCC80"
          font: photoGallery.t.tinyFont
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: tagPanel.pnResults

          delegate: ItemDelegate {
            required property var modelData

            Layout.fillWidth: true
            height: 40

            background: Rectangle {
              color: "#33455A64"
              radius: 4
            }

            contentItem: RowLayout {
              spacing: 8

              Text {
                Layout.leftMargin: 6
                text: modelData.score + "%"
                font: photoGallery.t.tipFont
                color: modelData.score >= 50 ? "#A5D6A7" : "#FFCC80"
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                  Layout.fillWidth: true
                  text: tagPanel.pnDopasujDoSlownika(modelData.lacina)
                  font: photoGallery.t.tipFont
                  color: "white"
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  visible: modelData.ludowa !== ""
                  text: modelData.ludowa
                  font: photoGallery.t.tinyFont
                  color: photoGallery.t.secondaryTextColor
                  elide: Text.ElideRight
                }
              }
            }

            onClicked: {
              const nazwa = tagPanel.pnDopasujDoSlownika(modelData.lacina);
              const fid = tagStore.addTag(viewer.curRel, nazwa, -1, "Pl@ntNet " + modelData.score + "%");
              if (fid >= 0) {
                tagInput.text = nazwa;
                tagPanel.pnResults = [];
                tagPanel.pnStatus = qsTr("Dodano: ") + nazwa + " (" + modelData.score + "%)";
                tagPanel.updateSuggestions();
              } else {
                displayToast(qsTr("Nie udało się zapisać tagu"));
              }
            }
          }
        }

        // ---- WorkField: czym rozroznic kandydatow Pl@ntNet ----
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          visible: cechyLista.count > 0

          Label {
            text: qsTr("Czym je rozróżnić:")
            color: "#80DEEA"
            font: photoGallery.t.tipFont
          }

          Repeater {
            id: cechyLista
            model: tagPanel.zbudujCechy(tagPanel.pnResults)

            delegate: ColumnLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 0

              Label {
                Layout.fillWidth: true
                text: modelData.naglowek
                color: "#A5D6A7"
                font: photoGallery.t.tinyFont
                wrapMode: Text.WordWrap
              }

              Label {
                Layout.fillWidth: true
                text: modelData.tekst
                color: "white"
                font: photoGallery.t.tinyFont
                wrapMode: Text.WordWrap
              }
            }
          }
        }

        Button {
          id: wyczyscTagiButton

          Layout.fillWidth: true
          visible: viewer.curTags.length > 0
          text: qsTr("Wyczyść tagi zdjęcia (%1)").arg(viewer.curTags.length)
          Material.background: "#7f3b30"
          onClicked: potwierdzenieCzyszczenia.open()

          Dialog {
            id: potwierdzenieCzyszczenia

            parent: Overlay.overlay
            anchors.centerIn: parent
            modal: true
            title: qsTr("Usunąć wszystkie tagi tego zdjęcia?")
            standardButtons: Dialog.Yes | Dialog.No
            onAccepted: {
              const kopie = viewer.curTags.slice();
              for (let i = 0; i < kopie.length; i++) {
                tagStore.removeTag(kopie[i].fid);
              }
              viewer.refreshTags();
              tagPanel.updateSuggestions();
            }
          }
        }

        Button {
          id: trybWskazButton

          Layout.fillWidth: true
          checkable: true
          checked: viewer.trybWskazywania
          enabled: tagInput.text.trim() !== "" || checked
          text: checked ? qsTr("Wskazywanie włączone — klikaj na zdjęciu") : qsTr("Wskaż gatunek na zdjęciu")
          Material.background: checked ? "#00695C" : undefined
          onToggled: {
            viewer.trybWskazywania = checked;
            if (checked)
              viewer.trybSiatki = false;
          }
        }

        Button {
          id: trybSiatkiButton

          Layout.fillWidth: true
          checkable: true
          checked: viewer.trybSiatki
          enabled: tagInput.text.trim() !== "" || checked
          text: checked ? qsTr("Siatka %1×%1 — klikaj w węzły").arg(viewer.siatkaN) : qsTr("Siatka pokrycia (%1×%1)").arg(viewer.siatkaN)
          Material.background: checked ? "#00695C" : undefined
          onToggled: {
            viewer.trybSiatki = checked;
            if (checked)
              viewer.trybWskazywania = false;
          }
        }

        // gęstość siatki: 5/7/10 (komórka 4% / ~2% / 1%)
        RowLayout {
          Layout.fillWidth: true
          visible: viewer.trybSiatki
          spacing: 4

          Text {
            text: qsTr("Gęstość:")
            font: photoGallery.t.tinyFont
            color: photoGallery.t.secondaryTextColor
          }

          Repeater {
            model: [5, 7, 10]

            delegate: Button {
              required property int modelData

              Layout.fillWidth: true
              checkable: true
              checked: viewer.siatkaN === modelData
              text: modelData + "×" + modelData
              font: photoGallery.t.tinyFont
              Material.background: checked ? "#00695C" : undefined
              onClicked: {
                viewer.siatkaN = modelData;
                settings.setValue('WorkField/siatkaN', modelData);
              }
            }
          }
        }

        // pędzel pusty + ręczny zbieg
        RowLayout {
          Layout.fillWidth: true
          visible: viewer.trybSiatki
          spacing: 6

          Button {
            checkable: true
            checked: viewer.pedzelPusty
            text: qsTr("∅ Pusta")
            font: photoGallery.t.tinyFont
            Material.background: checked ? "#616161" : undefined
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Maluj komórki ocenione bez roślinności — wyznaczają mianownik 100%")
            onToggled: viewer.pedzelPusty = checked
          }

          Text {
            text: qsTr("Zbieg:")
            font: photoGallery.t.tinyFont
            color: photoGallery.t.secondaryTextColor
          }

          Slider {
            id: suwakZbiegu

            Layout.fillWidth: true
            from: 0
            to: 0.75
            value: viewer.zbieg
            onMoved: viewer.zbieg = value
          }

          Text {
            text: Math.round(viewer.zbieg * 100) + "%"
            font: photoGallery.t.tinyFont
            color: photoGallery.t.secondaryTextColor
          }

          Text {
            text: qsTr("Pochył:")
            font: photoGallery.t.tinyFont
            color: photoGallery.t.secondaryTextColor
          }

          Slider {
            Layout.fillWidth: true
            from: -30
            to: 30
            value: viewer.obrot
            onMoved: viewer.obrot = value
          }

          Text {
            text: Math.round(viewer.obrot) + "°"
            font: photoGallery.t.tinyFont
            color: photoGallery.t.secondaryTextColor
          }
        }

        // pokrycie z siatki, na żywo, per gatunek
        Text {
          Layout.fillWidth: true
          visible: viewer.trybSiatki && viewer.tagiSiatki.length > 0
          wrapMode: Text.Wrap
          font: photoGallery.t.tinyFont
          color: "#80CBC4"
          text: {
            const grupy = {};
            const ocenione = {};
            let saPuste = false;
            for (let i = 0; i < viewer.tagiSiatki.length; i++) {
              const wpis = viewer.tagiSiatki[i];
              ocenione[String(wpis.uwagi)] = true;
              if (wpis.tag === "(pusta)") {
                saPuste = true;
              } else {
                const pokL = wpis.pokrycie;
                const uL = (pokL === undefined || pokL === null || pokL < 0 || pokL > 100) ? 1 : pokL / 100;
                if (grupy[wpis.tag] === undefined)
                  grupy[wpis.tag] = {
                    "suma": 0,
                    "n": 0
                  };
                grupy[wpis.tag].suma += uL;
                grupy[wpis.tag].n += 1;
              }
            }
            // mianownik: komórki ocenione (gatunek lub pusta), jeśli
            // oznaczono choć jedną pustą; inaczej cała siatka N×N
            const mianownik = saPuste ? Object.keys(ocenione).length : viewer.siatkaN * viewer.siatkaN;
            const czesci = Object.keys(grupy).sort().map(t => t + ": " + Math.round(100 * grupy[t].suma / mianownik) + "% (" + grupy[t].n + " kom.)");
            if (saPuste)
              czesci.push(qsTr("ocenione: %1 z %2").arg(Object.keys(ocenione).length).arg(viewer.siatkaN * viewer.siatkaN));
            return czesci.join("   ");
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

        ToolButton {
          id: edytujButton

          ToolTip.visible: hovered
          ToolTip.text: qsTr("Otwórz w zewnętrznym edytorze obrazów")

          contentItem: Text {
            text: qsTr("Edytuj…")
            color: "white"
            font: photoGallery.t.tinyFont
            verticalAlignment: Text.AlignVCenter
          }

          background: Rectangle {
            color: "white"
            opacity: edytujButton.hovered ? 0.2 : 0.08
            radius: 4
          }

          onClicked: viewer.edytujZewnetrznie()
        }

        // WorkField: legenda gatunków bieżącego zdjęcia (kolor = znacznik)
        Row {
          spacing: 10
          Layout.maximumWidth: parent.width * 0.6

          Repeater {
            model: {
              const grupy = {};
              for (let i = 0; i < viewer.curTags.length; i++) {
                const t = viewer.curTags[i].tag;
                if (t === "(pusta)")
                  continue;
                grupy[t] = (grupy[t] || 0) + 1;
              }
              return Object.keys(grupy).sort().map(t => ({
                    "tag": t,
                    "n": grupy[t]
                  }));
            }

            delegate: Row {
              required property var modelData

              spacing: 4

              Rectangle {
                width: 10
                height: 10
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: photoGallery.tagColor(parent.modelData.tag)
                border.color: "white"
                border.width: 1
              }

              Text {
                text: parent.modelData.tag + " (" + parent.modelData.n + ")"
                color: "white"
                font: photoGallery.t.tinyFont
              }
            }
          }
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
