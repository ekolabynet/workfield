import QtQuick
import QtQuick.Controls

import org.qfield
import Theme

/**
 * Cofnij i przywróć — para przycisków na górną belkę.
 *
 * Mechanizm (`QfFeatureHistory`) istnieje w upstreamie i działa, ale siedzi
 * w menu kontekstowym mapy, po angielsku. 20.08.2026 ratunkiem po awarii
 * był eksport warstwy i import z powrotem — pół dnia terenu — mimo że
 * cofanie było pod ręką.
 *
 * HISTORIA ŻYJE DO ZAMKNIĘCIA APLIKACJI: QfFeatureHistory nie zapisuje nic
 * na dysk. Po restarcie nie ma czego cofać. To założenie upstreamu, którego
 * świadomie nie ruszamy.
 *
 * Rozmiar przycisków zależny od platformy: w rękawicy mniejszy niż 40 px
 * jest nietrafialny.
 */
Row {
  id: para

  readonly property bool naTelefonie: Qt.platform.os === "android"
                                      || Qt.platform.os === "ios"
  readonly property int bok: naTelefonie ? 40 : 26

  spacing: 2

  QfToolButton {
    id: przyciskCofnij
    width: para.bok
    height: para.bok
    padding: 0
    round: true

    readonly property bool mozna: featureHistory && featureHistory.isUndoAvailable

    iconSource: Theme.getThemeVectorIcon("ic_undo_black_24dp")
    // Tło TYLKO gdy jest co cofnąć: przycisk sam mówi, że coś się wydarzyło,
    // bez czytania. Przy przezroczystym tle i przygaszeniu strzałka ginie
    // na belce — sprawdzone 26.08, trzeba było jej szukać wzrokiem.
    //
    // Dwa RÓŻNE kolory, nie jeden: pod pośpiechem myli się kierunek,
    // a cofnięcie cofnięcia to nie to samo co przywrócenie.
    iconColor: mozna ? "#062E12" : "white"
    bgcolor: mozna ? "#FFB300" : "transparent"
    opacity: mozna ? 1.0 : 0.3

    onClicked: {
      // Wyszarzony przycisk, który milczy, nie odróżnia „nie ma czego
      // cofnąć" od „zepsuło się". W terenie to różnica między spokojem
      // a szukaniem awarii.
      if (!mozna) {
        displayToast(qsTr("Nie ma czego cofnąć"), "warning");
        return;
      }
      const opis = featureHistory.undoMessage();
      if (featureHistory.undo())
        displayToast(opis !== "" ? qsTr("Cofnięto: %1").arg(opis) : qsTr("Cofnięto"));
      else
        displayToast(qsTr("Nie udało się cofnąć"), "warning");
    }
  }

  QfToolButton {
    id: przyciskPrzywroc
    width: para.bok
    height: para.bok
    padding: 0
    round: true

    readonly property bool mozna: featureHistory && featureHistory.isRedoAvailable

    iconSource: Theme.getThemeVectorIcon("ic_redo_black_24dp")
    // Zielone, nie pomarańczowe — patrz uwaga przy „Cofnij".
    iconColor: mozna ? "#062E12" : "white"
    bgcolor: mozna ? "#00E676" : "transparent"
    opacity: mozna ? 1.0 : 0.3

    onClicked: {
      if (!mozna) {
        displayToast(qsTr("Nie ma czego przywrócić"), "warning");
        return;
      }
      const opis = featureHistory.redoMessage();
      if (featureHistory.redo())
        displayToast(opis !== "" ? qsTr("Przywrócono: %1").arg(opis) : qsTr("Przywrócono"));
      else
        displayToast(qsTr("Nie udało się przywrócić"), "warning");
    }
  }
}
