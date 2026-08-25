import QtQuick
import QtQuick.Controls

import org.qfield
import Theme

/**
 * Plakietka OTWARTEJ SESJI EDYCJI.
 *
 * 20.08.2026 wtyczka zostawiła warstwę w otwartej sesji: nowe obiekty
 * przestały się dodawać, edycja była odrzucana bez słowa, kafel znikał
 * z paska. Diagnoza zajęła cały dzień — bo otwarta sesja wygląda dokładnie
 * tak samo jak zamknięta.
 *
 * TRZY STANY, nie dwa:
 *   zamknięta                 — plakietki nie ma
 *   otwarta sesja, bez zmian  — „EDYCJA"
 *   otwarta ze zmianami       — „EDYCJA N", mocniejszy odcień
 *
 * Środkowy stan jest tym, który kosztował dzień: sesja wisiała otwarta,
 * zmian nie było, więc nic nie wyglądało podejrzanie.
 *
 * Plakietka tekstowa, nie kolorowa kropka: w rękawicach i w słońcu kolor
 * bywa nieczytelny. Kolor jest tu wzmocnieniem, nie nośnikiem treści.
 *
 * Osobny komponent, bo belek jest dwie — mobilna (QgisMobileapp) i biurkowa
 * (QfDesktopChrome) — a przy trzeciej nie chcemy wklejać tego po raz trzeci.
 */
Rectangle {
  id: znacznik

  //! Warstwa do obserwowania; zwykle dashBoard.activeLayer
  property var warstwa: null

  property var stan: ({ wEdycji: false, zmian: 0 })

  function odswiez() {
    stan = warstwa ? LayerUtils.stanEdycji(warstwa) : ({ wEdycji: false, zmian: 0 });
  }

  visible: stan.wEdycji
  implicitWidth: etykieta.implicitWidth + 14
  implicitHeight: etykieta.implicitHeight + 5
  radius: 3

  // Otwarta sesja to ZAWSZE stan wymagający uwagi — stąd kolor ostrzegawczy
  // także wtedy, gdy bufor jest pusty. Niezapisane zmiany dokładają mocniejszy
  // odcień, bo tam da się stracić dane.
  color: stan.zmian > 0 ? Theme.errorColor : Theme.warningColor

  Text {
    id: etykieta
    anchors.centerIn: parent
    text: znacznik.stan.zmian > 0
          ? qsTr("EDYCJA %1").arg(znacznik.stan.zmian)
          : qsTr("EDYCJA")
    color: "white"
    font.pointSize: Theme.tinyFont.pointSize
    font.bold: true
  }

  // Sygnały mieszkają w QgsMapLayer i SĄ widoczne z QML — inaczej niż
  // isEditable(), które jest zwykłą metodą publiczną. Bez nich plakietka
  // odświeżałaby się dopiero przy przełączeniu warstwy, czyli nie wtedy,
  // kiedy trzeba.
  Connections {
    target: znacznik.warstwa
    ignoreUnknownSignals: true
    function onEditingStarted() { znacznik.odswiez(); }
    function onEditingStopped() { znacznik.odswiez(); }
    function onLayerModified() { znacznik.odswiez(); }
  }

  onWarstwaChanged: odswiez()
  Component.onCompleted: odswiez()
}
