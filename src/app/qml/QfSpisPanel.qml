import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core
import Theme

/**
 * WorkField 23.08.2026 — panel „Spis plików".
 *
 * Pomysł Piotra: „coś w rodzaju lokalnego gita dla plików — przynajmniej dla
 * ich listy". Rozdziela dwie rzeczy, które łatwo pomylić:
 *
 *     KOPIA zapobiega stracie.   SPIS ją WYKRYWA I NAZYWA.
 *
 * Tylko druga jest tania: pięćdziesiąt tysięcy plików to kilka megabajtów
 * tekstu, więc spis z każdego dnia przez rok nie zajmie tyle, co jedno zdjęcie.
 *
 * Panel robi trzy rzeczy i nic więcej:
 *   1. „Zrób spis"       — zapisuje stan drzewa,
 *   2. „Porównaj"        — dwa ostatnie spisy: co przybyło, CO ZNIKNĘŁO,
 *                          co się zmieniło i co jest PODEJRZANE,
 *   3. „Sprawdź"         — czy drzewo nadal zgadza się z wybranym spisem.
 *
 * Trzecia pozycja to ta, dla której to wszystko powstaje: spis pojedzie razem
 * z kopią na USB, więc po pół roku da się zapytać dysku, czy nadal ma to,
 * co dostał — BEZ ORYGINAŁU.
 */
/*
 * WorkField 24.08.2026 — QfPopup, nie goly Popup.
 *
 * PIATA ODSLONA TEGO SAMEGO WZORCA, tym razem w moim wlasnym, swiezym pliku.
 * `Popup` bez wlasnego tla bierze je ZE STYLU; na komputerze styl to
 * org.kde.desktop i tlo jest jasne, a napisy sa w barwie motywu, czyli jasne.
 * Panel wyszedl bialy na bialym — dokladnie tak, jak wczoraj ekran wyboru
 * pliku, panele w QfPopup i szuflady przed nimi.
 *
 * QfPopup ma `background` zwiazane z QfTheme.mainBackgroundColor. Nie ma
 * powodu, zeby jakikolwiek nasz panel dziedziczyl po golym Popupie.
 * Pilnuje tego teraz `skrypty/sito_tla.py`.
 */
QfPopup {
  id: spisPanel

  //! Korzeń magazynu; na komputerze ~/WorkField, na telefonie katalog aplikacji.
  property string korzen: dashBoard.korzenMagazynu
  property string katalogSpisow: korzen + "/spisy"

  property var lista: []
  property var wynik: null
  property string tytulWyniku: ""
  property bool pracuje: false

  function odswiez() {
    lista = SpisPlikow.spisy(katalogSpisow);
  }

  function zrobSpis(zakres) {
    pracuje = true;
    // Obchód drzewa i sumy liczą się w C++, w tym samym wątku co interfejs.
    // Przy kilkunastu tysiącach plików to sekundy, nie minuty — ale niech
    // człowiek wie, że nie zawiesiło się na dobre.
    const w = SpisPlikow.zrob(korzen, katalogSpisow, zakres, false);
    pracuje = false;
    odswiez();
    if (!w.ok) {
      displayToast(w.blad, "error");
      return;
    }
    tytulWyniku = qsTr("Spis zrobiony");
    wynik = {
      "linie": [qsTr("plików: %1").arg(w.plikow), qsTr("razem: %1").arg(FileUtils.representFileSize(w.bajtow)), qsTr("sum kontrolnych: %1").arg(w.sum), qsTr("pominięto odtwarzalnych: %1").arg(w.pominietych), w.sciezka],
      "alarm": false
    };
  }

  function porownajDwaOstatnie() {
    if (lista.length < 2) {
      displayToast(qsTr("Potrzebne są dwa spisy — zrób jeszcze jeden."), "warning");
      return;
    }
    // lista[0] jest najnowszy, więc starszy to lista[1].
    const r = SpisPlikow.porownaj(lista[1].sciezka, lista[0].sciezka);
    if (!r.ok) {
      displayToast(r.blad, "error");
      return;
    }

    const linie = [];
    linie.push(qsTr("%1  →  %2").arg(String(r.dataA).slice(0, 16)).arg(String(r.dataB).slice(0, 16)));
    linie.push(qsTr("plików: %1 → %2").arg(r.przedPlikow).arg(r.poPlikow));
    linie.push("");

    // ZNIKNĘŁO idzie PIERWSZE i z nazwami. To jest ta odpowiedź, dla której
    // spis istnieje: 72 zgubione zdjęcia z 21.08 to nie liczba, tylko lista.
    if (r.zniknely.length > 0) {
      linie.push(qsTr("⚠ ZNIKNĘŁO: %1  (%2)").arg(r.zniknely.length).arg(FileUtils.representFileSize(r.bajtowStraconych)));
      for (let i = 0; i < Math.min(r.zniknely.length, 12); i++)
        linie.push("   − " + r.zniknely[i].sciezka);
      if (r.zniknely.length > 12)
        linie.push(qsTr("   … i jeszcze %1").arg(r.zniknely.length - 12));
      linie.push("");
    }

    // PODEJRZANE: ten sam rozmiar, inna suma. Jedyna zmiana, której NIE WIDAĆ
    // w menedżerze plików — stąd dwa pliki po 2 609 152 B z 21.08.
    if (r.podejrzane.length > 0) {
      linie.push(qsTr("⚠ TEN SAM ROZMIAR, INNA TREŚĆ: %1").arg(r.podejrzane.length));
      for (let j = 0; j < r.podejrzane.length; j++)
        linie.push("   ! " + r.podejrzane[j].sciezka);
      linie.push("");
    }

    linie.push(qsTr("przybyło: %1  (%2)").arg(r.nowe.length).arg(FileUtils.representFileSize(r.bajtowNowych)));
    for (let k = 0; k < Math.min(r.nowe.length, 8); k++)
      linie.push("   + " + r.nowe[k].sciezka);
    if (r.nowe.length > 8)
      linie.push(qsTr("   … i jeszcze %1").arg(r.nowe.length - 8));

    linie.push(qsTr("zmieniło się: %1").arg(r.zmienione.length));

    tytulWyniku = qsTr("Różnica między dwoma ostatnimi spisami");
    wynik = {
      "linie": linie,
      "alarm": r.zniknely.length > 0 || r.podejrzane.length > 0
    };
  }

  function sprawdzWobec(sciezkaSpisu, zSumami) {
    pracuje = true;
    const r = SpisPlikow.sprawdz(sciezkaSpisu, korzen, zSumami === true);
    pracuje = false;
    if (r.blad !== undefined) {
      displayToast(r.blad, "error");
      return;
    }

    const linie = [];
    linie.push(qsTr("spis z %1").arg(String(r.data).slice(0, 16)));
    linie.push(qsTr("w spisie: %1, znalezionych: %2").arg(r.wSpisie).arg(r.sprawdzonych));
    linie.push("");
    if (r.brakuje.length > 0) {
      linie.push(qsTr("⚠ BRAKUJE: %1").arg(r.brakuje.length));
      for (let i = 0; i < Math.min(r.brakuje.length, 12); i++)
        linie.push("   − " + r.brakuje[i].sciezka);
    }
    if (r.innyRozmiar.length > 0) {
      linie.push(qsTr("⚠ inny rozmiar: %1").arg(r.innyRozmiar.length));
      for (let j = 0; j < Math.min(r.innyRozmiar.length, 8); j++)
        linie.push("   ! " + r.innyRozmiar[j].sciezka);
    }
    if (r.innaSuma.length > 0) {
      linie.push(qsTr("⚠ inna treść przy tym samym rozmiarze: %1").arg(r.innaSuma.length));
      for (let k = 0; k < Math.min(r.innaSuma.length, 8); k++)
        linie.push("   ! " + r.innaSuma[k].sciezka);
    }
    if (r.nadmiarowe.length > 0)
      linie.push(qsTr("poza spisem: %1").arg(r.nadmiarowe.length));
    if (r.ok)
      linie.push(qsTr("Wszystko na miejscu."));
    if (!zSumami)
      linie.push(qsTr("(bez sum kontrolnych — sprawdzono nazwy i rozmiary)"));

    tytulWyniku = qsTr("Sprawdzenie drzewa wobec spisu");
    wynik = {
      "linie": linie,
      "alarm": !r.ok
    };
  }

  parent: mainWindow.contentItem
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  width: Math.min(560, mainWindow.width - 32)
  height: Math.min(implicitHeight, mainWindow.height - 80)

  onOpened: {
    wynik = null;
    odswiez();
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Spis plików")
      font: Theme.strongFont
      color: Theme.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Spis nie chroni danych — mówi, czego brakuje i od kiedy. Jest tani: kilkanaście tysięcy plików to kilka megabajtów tekstu.")
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      text: spisPanel.korzen
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      elide: Text.ElideMiddle
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Button {
        text: qsTr("Zrób spis")
        font: Theme.tipFont
        enabled: !spisPanel.pracuje
        highlighted: true
        onClicked: spisPanel.zrobSpis("dane")
      }
      Button {
        text: qsTr("…także podkłady")
        font: Theme.tinyFont
        flat: true
        enabled: !spisPanel.pracuje
        onClicked: spisPanel.zrobSpis("wszystko")
      }
      Item {
        Layout.fillWidth: true
      }
      Button {
        text: qsTr("Porównaj")
        font: Theme.tipFont
        flat: true
        enabled: !spisPanel.pracuje && spisPanel.lista.length >= 2
        onClicked: spisPanel.porownajDwaOstatnie()
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
    }

    Text {
      Layout.fillWidth: true
      text: spisPanel.lista.length === 0
            ? qsTr("Nie ma jeszcze żadnego spisu.")
            : qsTr("Spisy (%1) — dotknij, żeby sprawdzić drzewo wobec niego:").arg(spisPanel.lista.length)
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    ListView {
      id: listaSpisow

      Layout.fillWidth: true
      // Wielokrotnosc wysokosci wiersza: przy 150 px ostatni wpis urywal sie
      // w polowie i wygladal na uszkodzony, a nie na przewijalny.
      Layout.preferredHeight: Math.min(contentHeight, 5 * 40)
      clip: true
      model: spisPanel.lista

      delegate: ItemDelegate {
        width: listaSpisow.width
        height: 40

        contentItem: RowLayout {
          spacing: 8

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              Layout.fillWidth: true
              text: String(modelData.data).slice(0, 16).replace("T", "  ")
              font: Theme.tipFont
              color: Theme.mainTextColor
            }
            Text {
              Layout.fillWidth: true
              text: qsTr("%1 · plików: %2 · %3").arg(modelData.zakres).arg(modelData.plikow).arg(FileUtils.representFileSize(modelData.bajtow))
              font: Theme.tinyFont
              color: Theme.secondaryTextColor
              elide: Text.ElideRight
            }
          }
        }

        onClicked: spisPanel.sprawdzWobec(modelData.sciezka, false)
        // Dłuższe przytrzymanie liczy sumy: wolniej, ale to jedyne, co wykrywa
        // ciche przekłamanie bitów na dysku.
        onPressAndHold: spisPanel.sprawdzWobec(modelData.sciezka, true)
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: wynikTekst.implicitHeight + 12
      Layout.maximumHeight: 220
      visible: spisPanel.wynik !== null
      color: Qt.rgba(0, 0, 0, 0.18)
      radius: 4
      clip: true

      ScrollView {
        anchors.fill: parent
        anchors.margins: 6
        clip: true

        Text {
          id: wynikTekst
          width: parent.width
          text: spisPanel.wynik ? spisPanel.wynik.linie.join("\n") : ""
          font: Theme.tinyFont
          color: spisPanel.wynik && spisPanel.wynik.alarm ? Theme.warningColor : Theme.mainTextColor
          wrapMode: Text.WrapAnywhere
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true

      Text {
        Layout.fillWidth: true
        text: spisPanel.pracuje ? qsTr("Liczę…") : spisPanel.tytulWyniku
        font: Theme.tinyFont
        color: Theme.secondaryTextColor
        elide: Text.ElideRight
      }
      Button {
        flat: true
        text: qsTr("Zamknij")
        font: Theme.tipFont
        onClicked: spisPanel.close()
      }
    }
  }
}
