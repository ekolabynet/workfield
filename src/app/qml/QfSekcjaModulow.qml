import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core
import Theme

/**
 * \ingroup qml
 *
 * WorkField 19.09.2026 — ZAKŁADKA „MODUŁY" W SZUFLADZIE.
 *
 * Moduł dziedzinowy to sposób pracy (warstwy, styl, eksporty), nie cecha
 * projektu — decyzje w claude/MODULY_dziedzinowe.md. Ta zakładka:
 *
 *  - „W tym projekcie": moduły, których silnik rozpoznał projekt
 *    (czasownik z "rozpoznanie" w opisie modułu). Karta pokazuje, co
 *    rozpoznał, i ma przyciski z "akcje". Nic nie jest wpisane na sztywno:
 *    karta powstaje z opisu modułu (modul.json), który podaje silnik.
 *  - „Zainstalowane": wszystkie moduły, które aplikacja zna. Dziś tylko
 *    wbudowane; paczki z katalogu dojdą w tę samą listę.
 *
 * Czynność niedostępna w tej wersji aplikacji (brak czasownika z
 * "wymaga_silnika") nie pokazuje martwego przycisku — moduł mówi wtedy,
 * że potrzebuje nowszej aplikacji (zasada: widoczne musi działać).
 */
Item {
  id: sekcja

  //! Szuflada, w której siedzi zakładka: na telefonie trzeba ją zamknąć
  //! PRZED komunikatem, bo komunikat ginie pod animacją zamykania.
  property var szuflada: null

  //! [{opis, brak, rozpoznanie, wProjekcie}]
  property var moduly: []
  readonly property var wProjekcie: moduly.filter(function (m) {
    return m.wProjekcie;
  })

  onVisibleChanged: {
    if (visible)
      odswiez();
  }

  Connections {
    target: iface
    ignoreUnknownSignals: true
    function onLoadProjectEnded(path, name) {
      sekcja.odswiez();
    }
  }

  //! Silniki wkompilowane w aplikację: nazwa z opisu modułu -> singleton.
  //! Nowy moduł z własnym silnikiem dopisuje się TUTAJ (jedna linia).
  function silniki() {
    const s = {};
    if (typeof InwentaryzacjaDrzew !== "undefined")
      s["InwentaryzacjaDrzew"] = InwentaryzacjaDrzew;
    return s;
  }

  function czynnosc(czasownik) {
    const kropka = czasownik.indexOf(".");
    const s = silniki()[czasownik.substring(0, kropka)];
    const metoda = czasownik.substring(kropka + 1);
    return s && typeof s[metoda] === "function" ? function (projekt) {
      return s[metoda](projekt);
    } : null;
  }

  function brakujace(opis) {
    const brak = [];
    const wymaga = opis.wymaga_silnika || [];
    for (let i = 0; i < wymaga.length; i++) {
      if (!czynnosc(wymaga[i]))
        brak.push(wymaga[i]);
    }
    return brak;
  }

  function odswiez() {
    const lista = [];
    const s = silniki();
    for (const nazwa in s) {
      const opis = s[nazwa].opis();
      const brak = brakujace(opis);
      let rozpoznanie = {};
      const jestProjekt = typeof qgisProject !== "undefined" && qgisProject && qgisProject.homePath !== "";
      if (!jestProjekt)
        rozpoznanie = {
          "blad": qsTr("brak otwartego projektu")
        };
      else if (brak.length === 0 && opis.rozpoznanie)
        rozpoznanie = czynnosc(opis.rozpoznanie)(qgisProject);
      lista.push({
                   "opis": opis,
                   "brak": brak,
                   "rozpoznanie": rozpoznanie,
                   "wProjekcie": jestProjekt && brak.length === 0 && !rozpoznanie.blad
                 });
    }
    moduly = lista;
  }

  //! "{klucz}" z wyniku czynności; tablica wstawia się jako liczba elementów.
  function wypelnij(szablon, wynik) {
    return String(szablon).replace(/\{([A-Za-z_]+)\}/g, function (calosc, klucz) {
      const w = wynik[klucz];
      if (w === undefined)
        return calosc;
      return Array.isArray(w) ? String(w.length) : String(w);
    });
  }

  function wykonaj(akcja) {
    const uruchom = function () {
      const f = czynnosc(akcja.czasownik);
      if (!f) {
        displayToast(qsTr("Ta wersja aplikacji nie ma czynności %1").arg(akcja.czasownik), "warning");
        return;
      }
      const w = f(qgisProject);
      console.log("WFG modul " + akcja.czasownik + ": " + JSON.stringify(w));
      if (w.blad) {
        displayToast(w.blad, "warning");
        return;
      }
      if (akcja.zapisz_projekt && typeof NarzedziaProjektu !== "undefined")
        NarzedziaProjektu.zapiszProjekt(qgisProject);
      const tekst = wypelnij(akcja.komunikat || akcja.etykieta, w);
      const pliki = akcja.wyslij ? w[akcja.wyslij] : null;
      if (pliki && pliki.length > 0) {
        displayToast(tekst, "info", qsTr("Wyślij"), function () {
          platformUtilities.sendCompressedFilesTo(pliki);
        });
      } else {
        displayToast(tekst);
      }
      sekcja.odswiez();
    };
    // Na telefonie szuflada zasłania mapę i komunikat: najpierw ją zamykamy,
    // czynność rusza po sygnale closed (tak jak dotąd w szufladzie).
    if (szuflada && szuflada.modal && szuflada.opened) {
      const poZamknieciu = function () {
        szuflada.closed.disconnect(poZamknieciu);
        uruchom();
      };
      szuflada.closed.connect(poZamknieciu);
      szuflada.close();
    } else {
      uruchom();
    }
  }

  Flickable {
    id: przewijanie
    anchors.fill: parent
    contentWidth: width
    contentHeight: kolumna.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    ColumnLayout {
      id: kolumna
      x: 8
      y: 8
      width: przewijanie.width - 16
      spacing: 6

      RowLayout {
        Layout.fillWidth: true

        Text {
          Layout.fillWidth: true
          text: qsTr("Moduły")
          font: Theme.strongTipFont
          color: Theme.mainTextColor
        }
        ToolButton {
          text: qsTr("Odśwież")
          font: Theme.tinyFont
          onClicked: sekcja.odswiez()
        }
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Moduł to sposób pracy: warstwy, styl, eksporty dla jednej dziedziny.")
        font: Theme.tinyFont
        color: Theme.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      // ── W tym projekcie ─────────────────────────────────────────
      Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: qsTr("W tym projekcie")
        font: Theme.tipFont
        color: Theme.mainTextColor
      }

      Text {
        Layout.fillWidth: true
        visible: sekcja.wProjekcie.length === 0
        text: qsTr("Żaden moduł nie rozpoznał tego projektu.")
        font: Theme.tinyFont
        color: Theme.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: sekcja.wProjekcie

        delegate: Rectangle {
          id: karta

          required property var modelData
          readonly property var r: modelData.rozpoznanie

          Layout.fillWidth: true
          implicitHeight: wnetrze.implicitHeight + 16
          radius: 6
          color: Theme.controlBackgroundAlternateColor
          border.color: Theme.mainColor
          border.width: 1

          ColumnLayout {
            id: wnetrze
            x: 8
            y: 8
            width: karta.width - 16
            spacing: 4

            RowLayout {
              Layout.fillWidth: true

              Text {
                Layout.fillWidth: true
                text: karta.modelData.opis.nazwa
                font: Theme.strongTipFont
                color: Theme.mainTextColor
                elide: Text.ElideRight
              }
              Text {
                text: karta.r.obiekty !== undefined ? qsTr("%1 obiektów").arg(karta.r.obiekty) : ""
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
              }
            }

            Text {
              Layout.fillWidth: true
              text: karta.r.warstwa || ""
              visible: text !== ""
              font: Theme.tinyFont
              color: Theme.mainTextColor
              wrapMode: Text.WrapAnywhere
              maximumLineCount: 2
              elide: Text.ElideRight
            }

            Repeater {
              // pola rozpoznane po roli, w kolejnosci z opisu modulu ("role")
              model: (karta.modelData.opis.role || []).filter(function (rola) {
                return !!karta.r[rola.klucz];
              })

              delegate: Text {
                required property var modelData
                Layout.fillWidth: true
                text: "· " + modelData.nazwa + ": " + karta.r[modelData.klucz]
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
                elide: Text.ElideRight
              }
            }

            Repeater {
              model: karta.modelData.opis.akcje || []

              delegate: QfPozycjaMenu {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.etykieta
                ikona: modelData.ikona || "wfg_paczka"
                onClicked: sekcja.wykonaj(modelData)
              }
            }
          }
        }
      }

      // ── Zainstalowane ─────────────────────────────────────────
      Text {
        Layout.fillWidth: true
        Layout.topMargin: 10
        text: qsTr("Zainstalowane")
        font: Theme.tipFont
        color: Theme.mainTextColor
      }

      Repeater {
        model: sekcja.moduly

        delegate: ColumnLayout {
          id: wpis

          required property var modelData

          Layout.fillWidth: true
          spacing: 1

          RowLayout {
            Layout.fillWidth: true

            Text {
              Layout.fillWidth: true
              text: wpis.modelData.opis.nazwa + "  " + (wpis.modelData.opis.wersja || "")
              font: Theme.tipFont
              color: Theme.mainTextColor
              elide: Text.ElideRight
            }
            Text {
              text: wpis.modelData.brak.length > 0 ? qsTr("wymaga nowszej aplikacji") : wpis.modelData.wProjekcie ? qsTr("w tym projekcie") : qsTr("wbudowany")
              font: Theme.tinyFont
              color: wpis.modelData.brak.length > 0 ? Theme.warningColor : wpis.modelData.wProjekcie ? Theme.mainColor : Theme.secondaryTextColor
            }
          }
          Text {
            Layout.fillWidth: true
            text: wpis.modelData.opis.opis || ""
            visible: text !== ""
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
            wrapMode: Text.WordWrap
          }
          Text {
            // dlaczego nie ma karty wyżej — bez tego moduł "znika" bez słowa
            Layout.fillWidth: true
            visible: !wpis.modelData.wProjekcie && wpis.modelData.brak.length === 0 && !!wpis.modelData.rozpoznanie.blad
            text: qsTr("Nie w tym projekcie: %1").arg(wpis.modelData.rozpoznanie.blad || "")
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
