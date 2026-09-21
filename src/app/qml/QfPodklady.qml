import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * WorkField 21.09.2026 — PODKŁADY I DANE WYSOKOŚCIOWE: jedno wejście.
 *
 * „Dołóż tło pod swoje dane” to jedna czynność, a była rozsypana po trzech
 * miejscach: ekran podkładów w lewej szufladzie, NMT i NMPT osobnymi
 * pozycjami, CHM jeszcze gdzie indziej. To okno niczego nie robi samo —
 * tylko ROZDZIELA: otwiera okna, które już są.
 *
 * Dzięki temu wejść może być kilka (lewa szuflada, karta modułu, prawa
 * szuflada), a okno pozostaje jedno. Zasada z 23.08.2026: dwa wejścia to
 * nie problem, dwie KOPIE są.
 */
Popup {
  id: oknoPodkladow

  property var t: Theme

  /**
   * Otwarcie z szuflady. Szuflada na telefonie jest modalna i jej
   * przyciemnienie gaśnie z opóźnieniem — okno otwarte spod niej wychodzi
   * wyblakłe (notatka z 24.08.2026). Dlatego najpierw zamknięcie szuflady,
   * potem okno.
   */
  function otworz(szuflada) {
    if (szuflada && szuflada.modal && szuflada.opened) {
      const potem = function () {
        szuflada.closed.disconnect(potem);
        oknoPodkladow.open();
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
  y: Math.max(12, (mainWindow.height - height) / 3)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  background: Rectangle {
    color: oknoPodkladow.t.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: oknoPodkladow.t.controlBorderColor
  }

  contentItem: ColumnLayout {
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: qsTr("Podkłady i dane wysokościowe")
      font: oknoPodkladow.t.strongFont
      color: oknoPodkladow.t.mainTextColor
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Wszystko, co kładzie się POD dane zebrane w terenie. Nowy podkład wchodzi na sam dół listy warstw.")
      font: oknoPodkladow.t.tinyFont
      color: oknoPodkladow.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    QfPozycjaMenu {
      Layout.fillWidth: true
      t: oknoPodkladow.t
      text: qsTr("Podkład mapowy: ortofoto, mapy, XYZ, WMS…")
      ikona: "wfg_podklad"
      onClicked: {
        oknoPodkladow.close();
        basemapScreen.open();
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: 8
      text: qsTr("Rysuje się z sieci i nie zostaje w telefonie — bez zasięgu zniknie.")
      font: oknoPodkladow.t.tinyFont
      color: oknoPodkladow.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    QfPozycjaMenu {
      Layout.fillWidth: true
      t: oknoPodkladow.t
      text: qsTr("Dane wysokościowe: NMT, NMPT, CHM…")
      ikona: "wfg_rzezba"
      onClicked: {
        oknoPodkladow.close();
        oknoDaneWysokosciowe.open();
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: 8
      text: qsTr("Pobierają się arkuszami do projektu i działają bez zasięgu.")
      font: oknoPodkladow.t.tinyFont
      color: oknoPodkladow.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    QfPozycjaMenu {
      Layout.fillWidth: true
      t: oknoPodkladow.t
      text: qsTr("Zdjęcie mapy lub plan bez georeferencji…")
      ikona: "wfg_zdjecia"
      onClicked: {
        oknoPodkladow.close();
        oknoGeoreferencji.otworz(null);
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: 8
      text: qsTr("Dopasowanie po punktach. Podkład do orientacji w terenie, nie materiał pomiarowy.")
      font: oknoPodkladow.t.tinyFont
      color: oknoPodkladow.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true

      Item {
        Layout.fillWidth: true
      }

      Button {
        text: qsTr("Zamknij")
        font.pointSize: oknoPodkladow.t.tinyFont.pointSize
        onClicked: oknoPodkladow.close()
      }
    }
  }
}
