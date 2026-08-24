import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Theme

/**
 * WorkField 24.08.2026 — PODGLĄD STYLIZACJI.
 *
 * Prośba Piotra: „W Wyglądzie powinno być okno z podglądem wizualizacji
 * wszystkich elementów, które występują w stylizacji, łącznie z aktywnymi
 * przyciskami". Powód był konkretny i powtarzał się przez cały dzień:
 * „niektóre napisy są ciemne na ciemnym tle i słabo je widać".
 *
 * DLACZEGO TO NIE JEST TYLKO GALERIA
 *
 * Ciemny napis na ciemnym tle wykrywało się dotąd tak: ktoś otwierał okno,
 * mrużył oczy i mówił, że coś jest nie tak. Znajdowało się to po jednym
 * oknie naraz, po fakcie, i tylko tam, gdzie ktoś zajrzał. Cztery razy
 * w ciągu jednego dnia.
 *
 * Więc ta strona nie pokazuje kolorów do oceny — ona je MIERZY. Dla każdej
 * pary napis/tło liczy kontrast wedle WCAG i mówi wprost, które pary są
 * za słabe. Barwy motywu można tu zmieniać (Wygląd → barwa napisów i tła),
 * a tabelka natychmiast pokazuje, co ta zmiana psuje, zanim zepsuje się to
 * w oknie, do którego nikt dziś nie zajrzy.
 *
 * PRÓG: 4.5:1 dla zwykłego tekstu, 3:1 dla dużego i dla obramowań —
 * tyle wymaga WCAG 2.1 AA. Poniżej 3:1 napis jest praktycznie niewidoczny
 * i to jest ten przypadek, który Piotr zgłaszał.
 */
QfPopup {
  id: podglad

  parent: mainWindow.contentItem
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  width: Math.min(760, mainWindow.width - 32)
  height: Math.min(mainWindow.height - 80, 640)

  /**
   * Względna luminancja wedle WCAG 2.1.
   *
   * Nie jest to zwykła jasność: każdy kanał przechodzi przez korektę gamma,
   * bo oko nie widzi liniowo. Wzór przepisany z definicji, nie z pamięci.
   */
  function luminancja(barwa) {
    function kanal(c) {
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * kanal(barwa.r) + 0.7152 * kanal(barwa.g) + 0.0722 * kanal(barwa.b);
  }

  /**
   * Barwa PRZEZROCZYSTA złożona na tle — bo inaczej rachunek kłamie.
   *
   * `mainTextDisabledColor` to `#73e6e1e5`: ta sama jasna barwa napisu, ale
   * z 45% krycia. Liczona wprost daje kontrast 13:1 i wygląda świetnie;
   * naprawdę widać ją znacznie słabiej, bo 55% tego, co widzi oko, to tło.
   * Pierwsza wersja tej strony liczyła właśnie tak i była narzędziem, które
   * odpowiada na inne pytanie, niż zadaliśmy.
   */
  function zloz(przod, tyl) {
    if (przod.a >= 0.999)
      return przod;
    return Qt.rgba(przod.a * przod.r + (1 - przod.a) * tyl.r,
                   przod.a * przod.g + (1 - przod.a) * tyl.g,
                   przod.a * przod.b + (1 - przod.a) * tyl.b,
                   1);
  }

  //! Stosunek kontrastu dwóch barw: od 1 (identyczne) do 21 (czarne i białe).
  //! Obie strony są najpierw składane na tle okna, żeby przezroczystość
  //! liczyła się tak, jak ją widać.
  function kontrast(a, b) {
    const tlo = zloz(b, Theme.mainBackgroundColor);
    const la = luminancja(zloz(a, tlo));
    const lb = luminancja(tlo);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  }

  function ocena(k) {
    if (k >= 4.5)
      return qsTr("dobrze");
    if (k >= 3)
      return qsTr("tylko duży tekst");
    return qsTr("ZA SŁABO");
  }

  function barwaOceny(k) {
    if (k >= 4.5)
      return Theme.goodColor;
    if (k >= 3)
      return Theme.warningColor;
    return Theme.errorColor;
  }

  //! Pary, które NAPRAWDĘ występują w interfejsie. Nie iloczyn wszystkiego
  //! ze wszystkim — takiej tabeli nikt nie przeczyta.
  readonly property var pary: [
    { "napis": qsTr("napis na tle okna"), "przod": Theme.mainTextColor, "tyl": Theme.mainBackgroundColor },
    { "napis": qsTr("napis drugorzędny na tle okna"), "przod": Theme.secondaryTextColor, "tyl": Theme.mainBackgroundColor },
    { "napis": qsTr("napis wygaszony na tle okna"), "przod": Theme.mainTextDisabledColor, "tyl": Theme.mainBackgroundColor },
    { "napis": qsTr("napis na kontrolce"), "przod": Theme.mainTextColor, "tyl": Theme.controlBackgroundColor },
    { "napis": qsTr("napis na kontrolce wygaszonej"), "przod": Theme.mainTextDisabledColor, "tyl": Theme.controlBackgroundDisabledColor },
    { "napis": qsTr("napis na przycisku"), "przod": Theme.buttonColor, "tyl": Theme.buttonBackgroundColor },
    { "napis": qsTr("napis na przycisku narzędzi"), "przod": Theme.toolButtonColor, "tyl": Theme.toolButtonBackgroundColor },
    { "napis": qsTr("napis na barwie głównej"), "przod": Theme.mainOverlayColor, "tyl": Theme.mainColor },
    { "napis": qsTr("ostrzeżenie na tle okna"), "przod": Theme.warningColor, "tyl": Theme.mainBackgroundColor },
    { "napis": qsTr("błąd na tle okna"), "przod": Theme.errorColor, "tyl": Theme.mainBackgroundColor },
    { "napis": qsTr("potwierdzenie na tle okna"), "przod": Theme.goodColor, "tyl": Theme.mainBackgroundColor },
    { "napis": qsTr("napis na tle grupy"), "przod": Theme.mainTextColor, "tyl": Theme.groupBoxBackgroundColor },
    { "napis": qsTr("obramowanie na tle okna"), "przod": Theme.controlBorderColor, "tyl": Theme.mainBackgroundColor }
  ]

  //! Ile par nie przechodzi progu 4.5:1 — liczba do nagłówka, żeby nie trzeba
  //! było przewijać tabeli, aby się dowiedzieć, czy jest problem.
  readonly property int slabych: {
    let n = 0;
    for (let i = 0; i < pary.length; i++)
      if (kontrast(pary[i].przod, pary[i].tyl) < 4.5)
        n++;
    return n;
  }

  Item {
    /*
     * ANCHORS.FILL JEST TU KONIECZNE, A NIE OZDOBNE.
     *
     * Zmierzone 24.08.2026 programem, ktory laduje ten plik i wypisuje
     * geometrie (skrypty/proba_ukladu/): bez tego ramka brala rozmiar
     * WLASNY, wyliczony z zawartosci — 841x84 — zamiast rozmiaru okna
     * 760x640. Flickable dostawal wtedy wysokosc ZERO i cala tabela znikala,
     * choc byla poprawnie ulozona na 971 pikseli.
     *
     * Popup NIE zastepuje swojego contentItem zadeklarowanym dzieckiem —
     * on je do niego WSTAWIA. Dziecko, ktore samo sie nie rozciagnie, po
     * prostu nie dostanie rozmiaru okna. Tak dziala kazde okno w tej
     * aplikacji, tylko wczesniej ColumnLayout mial anchors.fill wprost
     * i dlatego problem nie istnial, dopoki nie wsadzilem miedzy nie ramki.
     */
    anchors.fill: parent
    implicitWidth: uklad.implicitWidth
    implicitHeight: uklad.implicitHeight

    ColumnLayout {
      id: uklad

      anchors.fill: parent
      spacing: 8

      RowLayout {
        Layout.fillWidth: true

        Text {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          text: qsTr("Podgląd stylizacji")
          font: Theme.strongFont
          color: Theme.mainTextColor
        }
        Text {
          text: podglad.slabych === 0
                ? qsTr("wszystkie pary czytelne")
                : qsTr("par za słabych: %1").arg(podglad.slabych)
          font: Theme.tipFont
          color: podglad.slabych === 0 ? Theme.goodColor : Theme.errorColor
        }
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Kontrast liczony wedle WCAG 2.1. Próg 4.5:1 dla zwykłego tekstu, 3:1 dla dużego. Zmień barwy w Wyglądzie — tabela przeliczy się od razu.")
        font: Theme.tinyFont
        color: Theme.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      /*
       * FLICKABLE Z JAWNYM contentHeight, A NIE ScrollView.
       *
       * ScrollView bierze wysokosc z zawartosci, a zawartosc tej strony jest
       * dluzsza niz okno. Uklad nie zwezi sie ponizej swojego minimum, wiec
       * przyciski, pola i kroje pisma wyjechaly POD okno i rysowaly sie na
       * stronie ustawien pod spodem. Ta sama rodzina bledu, co tabela migawek
       * wychodzaca bokiem — tym razem w pionie.
       *
       * Flickable z podanym wprost `contentHeight` i `Layout.minimumHeight: 0`
       * nie ma jak urosnac: przewija, zamiast wypychac.
       */
      Flickable {
        id: przewijak

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true
        contentWidth: width
        contentHeight: kolumna.height
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
          policy: ScrollBar.AlwaysOn
        }

        ColumnLayout {
          id: kolumna

          // Minus szerokosc paska przewijania — inaczej ostatnia kolumna
          // ("dobrze" / "ZA SLABO") chowa sie pod nim i widac z niej polowe.
          width: przewijak.width - 16

          /*
           * WYSOKOSC MUSI BYC PODANA JAWNIE.
           *
           * `Flickable` nie jest ukladem i NIE nadaje rozmiaru swoim dzieciom.
           * ColumnLayout bez wlasnej wysokosci dostaje zero — wszystkie dzieci
           * uklada sie wtedy w zerowej wysokosci i po prostu nie widac ich
           * wcale. Dokladnie to sie stalo 24.08.2026: naglowek i stopka
           * rysowaly sie normalnie, a cala tabela zniknela. Raport do schowka
           * dzialal, bo liczby nie maja nic wspolnego z rysowaniem — i to
           * wlasnie ta rozbieznosc pokazala, ze to blad ukladu, nie danych.
           *
           * ScrollView tego nie wymagal, bo sam ustawia rozmiar zawartosci.
           * Flickable jest golym plotnem i trzeba mu powiedziec wszystko.
           */
          height: implicitHeight

          spacing: 10

          // ------------------------------------------------------- kontrast
          Text {
            Layout.topMargin: 4
            text: qsTr("KONTRAST PAR, KTÓRE WYSTĘPUJĄ W INTERFEJSIE")
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
          }

          Repeater {
            model: podglad.pary

            Rectangle {
              required property var modelData

              readonly property real k: podglad.kontrast(modelData.przod, modelData.tyl)

              Layout.fillWidth: true
              Layout.preferredHeight: 30
              color: modelData.tyl
              border.width: 1
              border.color: Theme.controlBorderColor
              radius: 3

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Text {
                  Layout.fillWidth: true
                  Layout.minimumWidth: 0
                  // Napis rysowany DOKŁADNIE tą parą barw, o której mowa —
                  // liczba obok mówi, ile ten kontrast wynosi, a oko widzi
                  // to samo, co liczba mierzy.
                  text: modelData.napis
                  font: Theme.tipFont
                  color: modelData.przod
                  elide: Text.ElideRight
                }
                Text {
                  Layout.preferredWidth: 54
                  horizontalAlignment: Text.AlignRight
                  text: parent.parent.k.toFixed(1) + ":1"
                  font: Theme.tinyFont
                  color: modelData.przod
                }
                Text {
                  Layout.preferredWidth: 108
                  horizontalAlignment: Text.AlignRight
                  text: podglad.ocena(parent.parent.k)
                  font: Theme.tinyFont
                  color: podglad.barwaOceny(parent.parent.k)
                }
              }
            }
          }

          // ------------------------------------------------------- przyciski
          Text {
            Layout.topMargin: 8
            text: qsTr("PRZYCISKI WE WSZYSTKICH STANACH")
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
          }

          Flow {
            Layout.fillWidth: true
            spacing: 6

            Button {
              text: qsTr("zwykły")
              font: Theme.tipFont
            }
            Button {
              text: qsTr("wyróżniony")
              font: Theme.tipFont
              highlighted: true
            }
            Button {
              text: qsTr("płaski")
              font: Theme.tipFont
              flat: true
            }
            Button {
              text: qsTr("wyłączony")
              font: Theme.tipFont
              enabled: false
            }
            Button {
              text: qsTr("płaski wyłączony")
              font: Theme.tipFont
              flat: true
              enabled: false
            }
            Button {
              text: qsTr("przełącznik wciśnięty")
              font: Theme.tipFont
              checkable: true
              checked: true
            }
          }

          // ------------------------------------------------------- kontrolki
          Text {
            Layout.topMargin: 8
            text: qsTr("POZOSTAŁE KONTROLKI")
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 10

            TextField {
              Layout.preferredWidth: 150
              font: Theme.tipFont
              text: qsTr("pole tekstowe")
            }
            TextField {
              Layout.preferredWidth: 150
              font: Theme.tipFont
              placeholderText: qsTr("podpowiedź w pustym")
            }
            CheckBox {
              text: qsTr("zaznaczone")
              font: Theme.tipFont
              checked: true
            }
            CheckBox {
              text: qsTr("puste")
              font: Theme.tipFont
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Switch {
              text: qsTr("przełącznik")
              font: Theme.tipFont
              checked: true
            }
            ComboBox {
              Layout.preferredWidth: 150
              font: Theme.tipFont
              model: [qsTr("lista rozwijana"), qsTr("druga pozycja")]
            }
            Slider {
              Layout.preferredWidth: 120
              value: 0.6
            }
            ProgressBar {
              Layout.preferredWidth: 120
              value: 0.4
            }
          }

          // ---------------------------------------------------------- napisy
          Text {
            Layout.topMargin: 8
            text: qsTr("KROJE I ROZMIARY")
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
          }

          Repeater {
            model: [
              { "opis": "strongFont", "font": Theme.strongFont, "barwa": Theme.mainTextColor },
              { "opis": "defaultFont", "font": Theme.defaultFont, "barwa": Theme.mainTextColor },
              { "opis": "strongTipFont", "font": Theme.strongTipFont, "barwa": Theme.mainTextColor },
              { "opis": "tipFont", "font": Theme.tipFont, "barwa": Theme.mainTextColor },
              { "opis": "tinyFont", "font": Theme.tinyFont, "barwa": Theme.secondaryTextColor }
            ]

            Text {
              required property var modelData

              Layout.fillWidth: true
              text: modelData.opis + " — " + qsTr("Zażółć gęślą jaźń, 0123456789")
              font: modelData.font
              color: modelData.barwa
              elide: Text.ElideRight
            }
          }

          // --------------------------------------------------------- swatche
          Text {
            Layout.topMargin: 8
            text: qsTr("BARWY MOTYWU")
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
          }

          Flow {
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            spacing: 6

            Repeater {
              model: [
                { "n": "mainColor", "b": Theme.mainColor },
                { "n": "mainOverlayColor", "b": Theme.mainOverlayColor },
                { "n": "mainBackgroundColor", "b": Theme.mainBackgroundColor },
                { "n": "mainTextColor", "b": Theme.mainTextColor },
                { "n": "mainTextDisabledColor", "b": Theme.mainTextDisabledColor },
                { "n": "secondaryTextColor", "b": Theme.secondaryTextColor },
                { "n": "controlBackgroundColor", "b": Theme.controlBackgroundColor },
                { "n": "controlBackgroundAlternateColor", "b": Theme.controlBackgroundAlternateColor },
                { "n": "controlBackgroundDisabledColor", "b": Theme.controlBackgroundDisabledColor },
                { "n": "controlBorderColor", "b": Theme.controlBorderColor },
                { "n": "buttonColor", "b": Theme.buttonColor },
                { "n": "buttonBackgroundColor", "b": Theme.buttonBackgroundColor },
                { "n": "toolButtonColor", "b": Theme.toolButtonColor },
                { "n": "toolButtonBackgroundColor", "b": Theme.toolButtonBackgroundColor },
                { "n": "groupBoxBackgroundColor", "b": Theme.groupBoxBackgroundColor },
                { "n": "groupBoxSurfaceColor", "b": Theme.groupBoxSurfaceColor },
                { "n": "goodColor", "b": Theme.goodColor },
                { "n": "warningColor", "b": Theme.warningColor },
                { "n": "errorColor", "b": Theme.errorColor }
              ]

              Rectangle {
                required property var modelData

                width: 150
                height: 34
                color: modelData.b
                border.width: 1
                border.color: Theme.controlBorderColor
                radius: 3

                Column {
                  anchors.centerIn: parent
                  spacing: 0

                  Text {
                    text: modelData.n
                    font: Theme.tinyFont
                    // Napis na próbce ma być czytelny NA NIEJ, więc bierzemy
                    // biel albo czerń — zależnie od tego, która ma większy
                    // kontrast z tą konkretną barwą. Ten sam rachunek, co wyżej.
                    color: podglad.kontrast(modelData.b, "#ffffff") > podglad.kontrast(modelData.b, "#000000")
                           ? "#ffffff" : "#000000"
                    width: 142
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                  }
                  Text {
                    text: modelData.b.toString()
                    font: Theme.tinyFont
                    color: podglad.kontrast(modelData.b, "#ffffff") > podglad.kontrast(modelData.b, "#000000")
                           ? "#ffffff" : "#000000"
                    width: 142
                    horizontalAlignment: Text.AlignHCenter
                  }
                }
              }
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true

        Text {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          text: qsTr("Motyw: %1").arg(Theme.darkTheme ? qsTr("ciemny") : qsTr("jasny"))
          font: Theme.tinyFont
          color: Theme.secondaryTextColor
        }
        Button {
          text: qsTr("Kopiuj raport")
          font: Theme.tinyFont
          flat: true
          // Ten sam powód, co przy migawkach: liczby, które program wyświetla,
          // powinny dać się wyjąć bez przepisywania ich ręcznie ze zrzutu.
          onClicked: {
            const l = [qsTr("para\tkontrast\tocena")];
            for (let i = 0; i < podglad.pary.length; i++) {
              const p = podglad.pary[i];
              const k = podglad.kontrast(p.przod, p.tyl);
              l.push([p.napis, k.toFixed(2) + ":1", podglad.ocena(k),
                      p.przod.toString(), p.tyl.toString()].join("\t"));
            }
            platformUtilities.copyTextToClipboard(l.join("\n"));
            displayToast(qsTr("Raport kontrastu skopiowany do schowka"));
          }
        }
        Button {
          text: qsTr("Zamknij")
          font: Theme.tipFont
          flat: true
          onClicked: podglad.close()
        }
      }
    }
  }
}
