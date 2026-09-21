import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * WorkField 21.09.2026 — NMT, NMPT i CHM w JEDNYM oknie.
 *
 * Wcześniej były trzy osobne pozycje menu i do tego osobne okno „Zakres
 * pobierania”, choć to jedna czynność w trzech odmianach: pobierz model
 * terenu, pobierz model pokrycia, odejmij jeden od drugiego. Wybór odmiany
 * stoi na górze, a niżej zmienia się tylko to, co dla niej istotne.
 *
 * Samo pobieranie zostaje tam, gdzie było (pobieracz w QfMainDrawer) — tutaj
 * jest wybór i jedno wywołanie: dashBoard.pobierzDemZakres().
 *
 * Nazwa obszaru wchodzi wstępnie z poprzedniego pobrania i to jest celowe:
 * CHM dobiera arkusze NMT i NMPT po TEJ SAMEJ nazwie obszaru. Zmiana nazwy
 * między jednym pobraniem a drugim rozrywa parę.
 */
Popup {
  id: oknoDaneWysokosciowe

  property var t: Theme

  //! "NMT", "NMPT" albo "CHM"
  property string rodzaj: "NMT"

  //! Skorowidze GUGiK dzielą arkusze na roczniki; domyślnie tylko najnowsze.
  property bool najnowsze: true

  //! Otwarcie z szuflady — patrz QfPodklady.otworz().
  /**
   * Warstwice z arkuszy NMT, ktore JUZ sa w projekcie.
   *
   * Nie pobieramy tu niczego: pobieranie ma wlasna odmiane tego okna
   * i wlasny pasek postepu. Jesli nie ma z czego liczyc, mowimy to wprost,
   * zamiast po cichu nic nie zrobic.
   *
   * Rachunek jest wspolny z modulem CAD (utils/warstwice.h) - tam z rzednych
   * z rysunku, tu z modelu terenu.
   */
  function policzWarstwice(odstep) {
    const dom = qgisProject.homePath;
    const pliki = iface.listFiles(dom + "/NMT", "NMT_*.tif")
                    .concat(iface.listFiles(dom + "/NMT", "*.asc"))
                    .concat(iface.listFiles(dom + "/NMT", "*.tif").filter(function (f) {
                      return f.indexOf("NMT_") !== 0;
                    }));
    if (pliki.length === 0) {
      displayToast(qsTr("Najpierw pobierz NMT dla obszaru — nie ma z czego liczyć warstwic"), "warning");
      return;
    }
    displayToast(qsTr("Liczę warstwice z %1 arkuszy…").arg(pliki.length));
    Qt.callLater(function () {
      let linii = 0;
      let zrobione = 0;
      for (const plik of pliki) {
        const nazwa = plik.replace(/\.(tif|asc)$/i, "").replace("NMT_", "");
        const w = iface.warstwiceZRastra(dom + "/NMT/" + plik,
                                         dom + "/NMT/warstwice_" + nazwa + ".gpkg",
                                         odstep,
                                         qsTr("Warstwice %1").arg(nazwa));
        console.log("WFG warstwice NMT: " + plik + " -> " + JSON.stringify(w));
        if (w.blad)
          continue;
        linii += w.linie;
        zrobione++;
      }
      if (typeof NarzedziaProjektu !== "undefined")
        NarzedziaProjektu.zapiszProjekt(qgisProject);
      displayToast(zrobione > 0
                   ? qsTr("Warstwice co %1 m: %2 linii z %3 arkuszy").arg(odstep).arg(linii).arg(zrobione)
                   : qsTr("Nie udało się policzyć warstwic — szczegóły w logu"), zrobione > 0 ? "info" : "warning");
    });
  }

  function otworz(szuflada) {
    if (szuflada && szuflada.modal && szuflada.opened) {
      const potem = function () {
        szuflada.closed.disconnect(potem);
        oknoDaneWysokosciowe.open();
      };
      szuflada.closed.connect(potem);
      szuflada.close();
    } else {
      open();
    }
  }

  parent: mainWindow.contentItem
  width: Math.min(460, mainWindow.width - 24)
  x: (mainWindow.width - width) / 2
  y: Math.max(12, (mainWindow.height - height) / 4)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape

  onOpened: poleObszaru.text = typeof dashBoard !== "undefined" ? dashBoard.nazwaObszaru() : ""

  background: Rectangle {
    color: oknoDaneWysokosciowe.t.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: oknoDaneWysokosciowe.t.controlBorderColor
  }

  contentItem: ColumnLayout {
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Dane wysokościowe")
      font: oknoDaneWysokosciowe.t.strongFont
      color: oknoDaneWysokosciowe.t.mainTextColor
    }

    // ── wybór odmiany ────────────────────────────────────────────────
    RowLayout {
      Layout.fillWidth: true
      spacing: 4

      Repeater {
        model: [
          {
            "klucz": "NMT",
            "etykieta": qsTr("NMT")
          },
          {
            "klucz": "NMPT",
            "etykieta": qsTr("NMPT")
          },
          {
            "klucz": "CHM",
            "etykieta": qsTr("CHM")
          },
          {
            "klucz": "WARSTWICE",
            "etykieta": qsTr("Warstwice")
          }
        ]

        delegate: Button {
          required property var modelData

          Layout.fillWidth: true
          text: modelData.etykieta
          font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
          font.bold: oknoDaneWysokosciowe.rodzaj === modelData.klucz
          highlighted: oknoDaneWysokosciowe.rodzaj === modelData.klucz
          onClicked: oknoDaneWysokosciowe.rodzaj = modelData.klucz
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: oknoDaneWysokosciowe.rodzaj === "NMT" ? qsTr("Numeryczny model terenu: grunt bez drzew i budynków. Arkusze GUGiK dla widocznego zakresu mapy.") : oknoDaneWysokosciowe.rodzaj === "NMPT" ? qsTr("Numeryczny model pokrycia terenu: wierzchołki drzew i dachy. Arkusze GUGiK dla widocznego zakresu mapy.") : oknoDaneWysokosciowe.rodzaj === "CHM" ? qsTr("CHM to różnica NMPT − NMT, czyli wysokość samych drzew. Liczy się z arkuszy już pobranych dla tej samej nazwy obszaru.") : qsTr("Warstwice z pobranego NMT. Liczą się z arkuszy, które już są w projekcie — najpierw pobierz NMT dla obszaru.")
      font: oknoDaneWysokosciowe.t.tinyFont
      color: oknoDaneWysokosciowe.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    // ── nazwa obszaru: wspólna dla NMT, NMPT i CHM ───────────────────
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: qsTr("Obszar")
        font: oknoDaneWysokosciowe.t.tipFont
        color: oknoDaneWysokosciowe.t.mainTextColor
      }

      TextField {
        id: poleObszaru

        Layout.fillWidth: true
        font: oknoDaneWysokosciowe.t.tipFont
        placeholderText: qsTr("np. Bruzdowa")
        enabled: oknoDaneWysokosciowe.rodzaj === "NMT" || oknoDaneWysokosciowe.rodzaj === "NMPT"
      }
    }

    // ── odstęp warstwic: tylko przy warstwicach ─────────────────────
    RowLayout {
      Layout.fillWidth: true
      spacing: 6
      visible: oknoDaneWysokosciowe.rodzaj === "WARSTWICE"

      Text {
        text: qsTr("Co ile metrów")
        font: oknoDaneWysokosciowe.t.tipFont
        color: oknoDaneWysokosciowe.t.mainTextColor
      }

      TextField {
        id: poleOdstepu

        Layout.preferredWidth: 70
        text: "0,5"
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        font.pointSize: oknoDaneWysokosciowe.t.tipFont.pointSize
      }

      Item {
        Layout.fillWidth: true
      }
    }

    // ── roczniki: tylko przy pobieraniu arkuszy ──────────────────────
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 4
      visible: oknoDaneWysokosciowe.rodzaj === "NMT" || oknoDaneWysokosciowe.rodzaj === "NMPT"

      Text {
        Layout.fillWidth: true
        text: qsTr("Skorowidze GUGiK dzielą arkusze na roczniki.")
        font: oknoDaneWysokosciowe.t.tinyFont
        color: oknoDaneWysokosciowe.t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Button {
          Layout.fillWidth: true
          text: qsTr("Najnowsze arkusze")
          font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
          font.bold: oknoDaneWysokosciowe.najnowsze
          highlighted: oknoDaneWysokosciowe.najnowsze
          onClicked: oknoDaneWysokosciowe.najnowsze = true
        }

        Button {
          Layout.fillWidth: true
          text: qsTr("Wszystkie roczniki")
          font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
          font.bold: !oknoDaneWysokosciowe.najnowsze
          highlighted: !oknoDaneWysokosciowe.najnowsze
          onClicked: oknoDaneWysokosciowe.najnowsze = false
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Item {
        Layout.fillWidth: true
      }

      Button {
        text: qsTr("Zamknij")
        font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
        onClicked: oknoDaneWysokosciowe.close()
      }

      Button {
        highlighted: true
        text: oknoDaneWysokosciowe.rodzaj === "CHM" ? qsTr("Policz CHM") : oknoDaneWysokosciowe.rodzaj === "WARSTWICE" ? qsTr("Policz warstwice") : qsTr("Pobierz %1").arg(oknoDaneWysokosciowe.rodzaj)
        font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
        onClicked: {
          const rodzaj = oknoDaneWysokosciowe.rodzaj;
          const nazwa = poleObszaru.text.trim();
          const najnowsze = oknoDaneWysokosciowe.najnowsze;
          const odstep = parseFloat(String(poleOdstepu.text).replace(",", "."));
          oknoDaneWysokosciowe.close();
          if (rodzaj === "CHM")
            dashBoard.computeChmAction();
          else if (rodzaj === "WARSTWICE")
            oknoDaneWysokosciowe.policzWarstwice(isNaN(odstep) || odstep <= 0 ? 0.5 : odstep);
          else
            dashBoard.pobierzDemZakres(rodzaj, nazwa, najnowsze);
        }
      }
    }
  }
}
