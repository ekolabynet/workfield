import QtQuick
import QtQuick.Controls
import QtCore
import Theme

/**
 * Uchwyt zmiany rozmiaru w prawym dolnym rogu okna.
 *
 * Okna mają rozmiar wpisany w kod. Przy zmianie zawartości trzeba go
 * poprawiać w źródle — a to, co mieści się na biurku, nie mieści się
 * na telefonie i odwrotnie.
 *
 * TYLKO NA BIURKU: palcem nie trafisz w uchwyt 16 px, a miejsce zajmuje.
 *
 * Rozmiar jest ZAPAMIĘTYWANY per okno (klucz w nazwie), bo galeria zdjęć
 * i ekran stanu mają różne potrzeby — jeden wspólny rozmiar byłby gorszy
 * niż brak zapamiętywania.
 *
 * Użycie — jako ostatni element w Popup:
 *
 *     QfUchwytRozmiaru {
 *       okno: nazwaOkna
 *       klucz: "stanProjektu"
 *     }
 */
Item {
  id: uchwyt

  //! Okno do zmiany rozmiaru; zwykle rodzic-Popup
  property var okno: null

  //! Nazwa pod jaką zapamiętać rozmiar. Pusta = bez zapamiętywania.
  property string klucz: ""

  property int minSzerokosc: 320
  property int minWysokosc: 200

  // Palcem nie trafisz, a na małym ekranie i tak nie ma czego powiększać.
  readonly property bool naBiurku: Qt.platform.os !== "android"
                                   && Qt.platform.os !== "ios"

  visible: naBiurku && okno !== null
  width: 18
  height: 18
  anchors.right: parent ? parent.right : undefined
  anchors.bottom: parent ? parent.bottom : undefined
  anchors.margins: 2

  // QQmlSettings z QtCore NIE MA valueInt/setValue — to metody QfSettings
  // (tego wstrzykiwanego jako `settings`). Tu zapisuje się inaczej:
  // deklarujesz właściwości, a one same trafiają do ustawień pod kluczem
  // złożonym z `category` i nazwy.
  Settings {
    id: zapamietane
    category: "WorkField/okna/" + uchwyt.klucz
    property int szerokosc: 0
    property int wysokosc: 0
  }

  function wczytaj() {
    if (klucz === "" || !okno)
      return;
    const w = zapamietane.szerokosc;
    const h = zapamietane.wysokosc;
    // Zero znaczy „nigdy nie zapisano" — zostawiamy rozmiar z kodu.
    if (w >= minSzerokosc)
      okno.width = Math.min(w, mainWindow.width - 20);
    if (h >= minWysokosc)
      okno.height = Math.min(h, mainWindow.height - 20);
  }

  function zapisz() {
    if (klucz === "" || !okno)
      return;
    zapamietane.szerokosc = Math.round(okno.width);
    zapamietane.wysokosc = Math.round(okno.height);
  }

  Component.onCompleted: wczytaj()

  // Trzy kreski pod kątem — ten sam znak, co w oknach systemowych.
  Canvas {
    anchors.fill: parent
    opacity: obszar.containsMouse || obszar.drag.active ? 0.9 : 0.4

    onPaint: {
      const ctx = getContext("2d");
      ctx.reset();
      ctx.strokeStyle = Theme.secondaryTextColor;
      ctx.lineWidth = 1.5;
      for (let i = 0; i < 3; i++) {
        const p = 5 + i * 5;
        ctx.beginPath();
        ctx.moveTo(width - p, height - 2);
        ctx.lineTo(width - 2, height - p);
        ctx.stroke();
      }
    }
  }

  MouseArea {
    id: obszar
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.SizeFDiagCursor

    property real startX: 0
    property real startY: 0
    property real startW: 0
    property real startH: 0

    onPressed: function (mouse) {
      startX = mouse.x;
      startY = mouse.y;
      startW = uchwyt.okno.width;
      startH = uchwyt.okno.height;
    }

    onPositionChanged: function (mouse) {
      if (!pressed || !uchwyt.okno)
        return;
      // Granice: bez nich da się zwinąć okno do zera — i już go nie złapiesz,
      // bo uchwyt zniknie razem z oknem.
      uchwyt.okno.width = Math.max(uchwyt.minSzerokosc,
                                   Math.min(mainWindow.width - 20,
                                            startW + (mouse.x - startX)));
      uchwyt.okno.height = Math.max(uchwyt.minWysokosc,
                                    Math.min(mainWindow.height - 20,
                                             startH + (mouse.y - startY)));
    }

    onReleased: uchwyt.zapisz()
  }
}
