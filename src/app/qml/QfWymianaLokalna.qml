import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * Wymiana lokalna — wynoszenie i wnoszenie danych bez chmury i bez kabla.
 *
 * Od Androida 11 katalog aplikacji (Android/data/...) jest niewidoczny dla
 * menedżerów plików i dla komputera przez USB. Dlatego wymiana idzie przez
 * zwykły folder w przestrzeni użytkownika:
 *
 *   Documents/WorkField/do_wyslania/   ← co wynosimy z telefonu
 *   Documents/WorkField/przychodzace/  ← co wnosimy do telefonu
 *
 * Oba widać po podłączeniu telefonu do komputera i w każdym menedżerze plików,
 * więc oddanie zwrotu nie wymaga niczyjej pomocy. Systemowy wybór miejsca
 * („Wyślij do…", „Eksportuj do folderu…") zostaje jako druga droga — przydaje
 * się, gdy dane mają iść od razu do chmury albo na komunikator.
 */
Popup {
  id: wymiana

  property var t

  readonly property string projectDir: qgisProject ? qgisProject.homePath : ""
  readonly property string projectName: projectDir !== "" ? FileUtils.fileName(projectDir) : ""

  //! katalog roboczy w przestrzeni użytkownika; na komputerze bramą
  //! jest wymiana magazynu (~/WorkField/wymiana), nie ścieżka Androida
  readonly property string korzen: Qt.platform.os === "android"
    ? "/storage/emulated/0/Documents/WorkField"
    : StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "") + "/WorkField/wymiana"
  readonly property string doWyslania: korzen + "/do_wyslania"
  readonly property string przychodzace: korzen + "/przychodzace"

  property string stan: ""

  width: mainWindow.width - 16
  height: mainWindow.height - 32
  x: Math.round((mainWindow.width - width) / 2)
  y: Math.round((mainWindow.height - height) / 2)
  modal: true
  focus: true

  onOpened: {
    // katalogi tworzymy przy pierwszym otwarciu; jeśli się nie da (brak
    // uprawnienia do plików), mówimy o tym wprost zamiast milczeć
    const czesci = korzen.split("/");
    const baza = czesci.slice(0, -1).join("/");
    platformUtilities.createDir(czesci.slice(0, -2).join("/"), czesci[czesci.length - 2]);
    platformUtilities.createDir(baza, czesci[czesci.length - 1]);
    platformUtilities.createDir(korzen, "do_wyslania");
    platformUtilities.createDir(korzen, "przychodzace");
    stan = "";
    modelPrzychodzace.folder = "";
    modelPrzychodzace.folder = "file://" + przychodzace;
  }

  // ------------------------------------------------------------ działania
  //! Kopiuje bieżący projekt do katalogu wynoszenia.
  function wyniesProjekt() {
    if (projectDir === "") {
      stan = qsTr("Najpierw otwórz projekt.");
      return;
    }
    const cel = doWyslania + "/" + projectName;
    if (FileUtils.copyRecursively(projectDir, cel, null, false)) {
      stan = qsTr("Projekt skopiowany do do_wyslania/%1").arg(projectName);
      displayToast(stan);
    } else {
      stan = qsTr("Nie udało się skopiować projektu.");
    }
  }

  /**
   * WorkField 23.08.2026 — WYŚLIJ MIGAWKĘ.
   *
   * "Wynieś projekt" kopiuje CAŁY katalog razem z DCIM — cztery gigabajty,
   * raz na wyjazd. Migawka to sama baza: 2-3 MB, więc wolno ją robić kilka
   * razy dziennie. Rachunek z claude/DANE_workflow.md: 2,5 MB razy sześć =
   * 15 MB na dzień, czyli nic.
   *
   * Kopia jest ZAPIECZĘTOWANA po stronie C++: dziennik WAL wchodzi do pliku
   * przed kopiowaniem, kopia sprawdza sama siebie, a obok ląduje suma md5.
   * Kopia, która nie przejdzie sprawdzenia, jest kasowana — lepiej brak
   * migawki niż migawka, której nie da się odtworzyć.
   *
   * Nazwa niesie czas, więc historia jest append-only i kolizja jest
   * niemożliwa. Nic nigdy nie jest nadpisywane.
   */
  function wyslijMigawke() {
    if (projectDir === "") {
      stan = qsTr("Najpierw otwórz projekt.");
      return;
    }

    const baza = NarzedziaProjektu.plikDanych(qgisProject);
    if (baza === "") {
      stan = qsTr("Projekt nie ma pliku z danymi — nie ma z czego robić migawki.");
      displayToast(stan, "warning");
      return;
    }

    const wynik = NarzedziaProjektu.migawkaBazy(baza, doWyslania);
    if (!wynik.ok) {
      stan = wynik.blad !== undefined ? wynik.blad : qsTr("Migawka się nie udała.");
      displayToast(stan, "error");
      return;
    }

    stan = qsTr("Migawka: %1 (%2)").arg(wynik.nazwa).arg(FileUtils.representFileSize(wynik.bajty));
    displayToast(stan);
  }

  /**
   * Wnosi to, co leży w przychodzacych: katalog kopiujemy, paczkę rozpakowujemy.
   * Projekt trafia do Imported Projects i jest gotowy do otwarcia.
   */
  function wniesPozycje(nazwa, jestKatalogiem) {
    const zrodlo = przychodzace + "/" + nazwa;
    const projekty = iface.dataRoot() + "Imported Projects";
    if (jestKatalogiem) {
      const cel = projekty + "/" + nazwa;
      if (FileUtils.copyRecursively(zrodlo, cel, null, false)) {
        stan = qsTr("Wniesiono projekt %1").arg(nazwa);
        displayToast(stan);
      } else {
        stan = qsTr("Nie udało się skopiować %1").arg(nazwa);
      }
    } else if (/\.zip$/i.test(nazwa)) {
      if (FileUtils.unzipTo(zrodlo, projekty)) {
        stan = qsTr("Rozpakowano %1").arg(nazwa);
        displayToast(stan);
      } else {
        stan = qsTr("Nie udało się rozpakować %1").arg(nazwa);
      }
    } else {
      // pojedyncza warstwa: otwieramy ją wprost, bez kopiowania
      iface.loadFile(zrodlo, FileUtils.fileName(zrodlo, false));
      stan = qsTr("Dodano warstwę %1").arg(nazwa);
    }
  }

  background: Rectangle {
    color: t.mainBackgroundColor
    radius: 6
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 10

    RowLayout {
      Layout.fillWidth: true

      Text {
        Layout.fillWidth: true
        text: qsTr("Wymiana lokalna")
        font: wymiana.t.strongFont
        color: wymiana.t.mainTextColor
      }

      ToolButton {
        implicitWidth: 96
        implicitHeight: 48
        onClicked: wymiana.close()

        contentItem: RowLayout {
          spacing: 6

          Image {
            source: wymiana.t.getThemeVectorIcon("ic_clear_black_18dp")
            sourceSize.width: 26
            sourceSize.height: 26
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            fillMode: Image.PreserveAspectFit
          }

          Text {
            text: qsTr("Powrót")
            font: wymiana.t.tipFont
            color: wymiana.t.mainTextColor
            verticalAlignment: Text.AlignVCenter
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      text: qsTr("Folder Documents/WorkField widać po podłączeniu telefonu do komputera i w menedżerze plików.")
      font: wymiana.t.tinyFont
      color: wymiana.t.secondaryTextColor
    }

    // ---------------------------------------------------------- wynoszenie
    Text {
      text: qsTr("Wynieś z telefonu")
      font: wymiana.t.strongTipFont
      color: wymiana.t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: wymiana.projectName !== ""
            ? qsTr("bieżący projekt: %1").arg(wymiana.projectName)
            : qsTr("nie ma otwartego projektu")
      font: wymiana.t.tinyFont
      color: wymiana.t.secondaryTextColor
      elide: Text.ElideMiddle
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: 6
      rowSpacing: 6

      Button {
        Layout.fillWidth: true
        enabled: wymiana.projectDir !== ""
        text: qsTr("Wyślij migawkę bazy")
        font: wymiana.t.tipFont
        onClicked: wymiana.wyslijMigawke()
      }

      Button {
        Layout.fillWidth: true
        enabled: wymiana.projectDir !== ""
        text: qsTr("Do folderu wymiany")
        font: wymiana.t.tipFont
        onClicked: wymiana.wyniesProjekt()
      }

      Button {
        Layout.fillWidth: true
        enabled: wymiana.projectDir !== "" && (platformUtilities.capabilities & PlatformUtilities.CustomSend)
        text: qsTr("Wyślij jako paczkę…")
        font: wymiana.t.tipFont
        onClicked: {
          platformUtilities.sendCompressedFolderTo(wymiana.projectDir);
          wymiana.stan = qsTr("Wybierz, dokąd wysłać paczkę.");
        }
      }

      Button {
        Layout.fillWidth: true
        Layout.columnSpan: 2
        enabled: wymiana.projectDir !== "" && (platformUtilities.capabilities & PlatformUtilities.CustomExport)
        text: qsTr("Eksportuj do wybranego folderu…")
        font: wymiana.t.tipFont
        onClicked: {
          platformUtilities.exportFolderTo(wymiana.projectDir);
          wymiana.stan = qsTr("Wskaż folder docelowy.");
        }
      }
    }

    // ---------------------------------------------------------- wnoszenie
    Text {
      Layout.topMargin: 6
      text: qsTr("Wnieś do telefonu")
      font: wymiana.t.strongTipFont
      color: wymiana.t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("połóż projekt lub paczkę w Documents/WorkField/przychodzace")
      font: wymiana.t.tinyFont
      color: wymiana.t.secondaryTextColor
    }

    FolderListModel {
      id: modelPrzychodzace
      showDirs: true
      showDirsFirst: true
      showDotAndDotDot: false
      sortField: FolderListModel.Time
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: 2
      model: modelPrzychodzace

      ScrollBar.vertical: ScrollBar {
      }

      delegate: Rectangle {
        width: ListView.view.width
        height: 56
        color: "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 4
          anchors.rightMargin: 4
          spacing: 8

          Image {
            source: fileIsDir
                    ? wymiana.t.getThemeVectorIcon("ic_folder_open_black_24dp")
                    : (/\.zip$/i.test(fileName)
                       ? wymiana.t.getThemeVectorIcon("wf_project_template")
                       : wymiana.t.getThemeVectorIcon("ic_vectorlayer_polygon_18dp"))
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
              font: wymiana.t.tipFont
              color: wymiana.t.mainTextColor
              elide: Text.ElideMiddle
            }

            Text {
              text: fileIsDir ? qsTr("projekt w folderze") : (/\.zip$/i.test(fileName) ? qsTr("paczka") : qsTr("warstwa"))
              font: wymiana.t.tinyFont
              color: wymiana.t.secondaryTextColor
            }
          }

          Button {
            text: qsTr("Wnieś")
            font: wymiana.t.tipFont
            onClicked: wymiana.wniesPozycje(fileName, fileIsDir)
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: modelPrzychodzace.count === 0
      wrapMode: Text.WordWrap
      text: qsTr("Folder przychodzace jest pusty.")
      font: wymiana.t.tipFont
      color: wymiana.t.secondaryTextColor
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Button {
        flat: true
        visible: platformUtilities.capabilities & PlatformUtilities.CustomImport
        text: qsTr("Importuj folder…")
        font: wymiana.t.tipFont
        onClicked: platformUtilities.importProjectFolder()
      }

      Button {
        flat: true
        visible: platformUtilities.capabilities & PlatformUtilities.CustomImport
        text: qsTr("Importuj paczkę…")
        font: wymiana.t.tipFont
        onClicked: platformUtilities.importProjectArchive()
      }

      Item {
        Layout.fillWidth: true
      }

      ToolButton {
        text: qsTr("Odśwież")
        font: wymiana.t.tipFont
        onClicked: {
          modelPrzychodzace.folder = "";
          modelPrzychodzace.folder = "file://" + wymiana.przychodzace;
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: wymiana.stan !== ""
      wrapMode: Text.WordWrap
      text: wymiana.stan
      font: wymiana.t.tipFont
      color: wymiana.t.secondaryTextColor
    }
  }
}
