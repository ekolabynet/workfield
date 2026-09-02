import QtQuick
import QtQuick.Controls

import org.qfield
import Theme

/**
 * Długi tekst — pole o USTALONEJ wysokości, przewijane w środku.
 *
 * Zwykły `TextEdit` z wielolinią rośnie razem z treścią. Po 600–800
 * znakach kursor schodził pod dolną krawędź i nie było widać, co się
 * pisze — bo formularz nie miał dokąd się przewinąć.
 *
 * Tutaj pole ma stałą wysokość i własny przewijacz. Treść może być
 * dowolnie długa; przewija się wewnątrz, a kursor zostaje widoczny.
 *
 * Wołany zamiast `TextEdit`, gdy w QGIS zaznaczono „Wielolinia".
 */
QfEditorWidgetBase {
  id: dlugiTekst

  //! Wysokość pola jako ułamek formularza. Z ustawień terenowych, bo
  //! przy spisie gatunkowym chce się więcej niż przy zwykłej uwadze.
  readonly property real udzial: {
    const u = settings ? settings.valueInt("WorkField/udzialDlugiegoPola", 40) : 40;
    return Math.min(80, Math.max(15, u)) / 100;
  }

  readonly property real wysokoscPola: {
    let f = dlugiTekst.parent;
    while (f && (f.height === undefined || f.height <= 0))
      f = f.parent;
    const bazowa = f && f.height > 0 ? f.height : 400;
    return Math.max(96, bazowa * udzial);
  }

  height: przewijacz.height + 4

  ScrollView {
    id: przewijacz

    anchors.left: parent.left
    anchors.right: parent.right
    height: dlugiTekst.wysokoscPola
    clip: true

    // Pasek pokazuje, ILE tekstu jest poza widokiem — przy spisie
    // gatunkowym to jedyny znak, że treść sięga dalej.
    ScrollBar.vertical.policy: pole.contentHeight > przewijacz.height
                               ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

    TextArea {
      id: pole

      enabled: isEditable
      readOnly: !isEditable
      wrapMode: TextEdit.Wrap
      font: Theme.defaultFont
      color: (!isEditable && isEditing) ? Theme.mainTextDisabledColor : Theme.mainTextColor
      selectByMouse: true
      leftPadding: isEditing ? 10 : 0

      text: isNull ? '' : String(value)

      background: Rectangle {
        visible: pole.enabled || (!isEditable && isEditing)
        color: "transparent"
        border.width: 1
        border.color: pole.activeFocus ? Theme.mainColor : Theme.controlBorderColor
        radius: 4
      }

      onTextChanged: {
        if (enabled)
          valueChangeRequested(text, text === '');
      }

      // Kursor trzymany w widocznej części POLA — nie formularza.
      //
      // Poprzedni mechanizm (`scrollCaretIntoView`) przesuwał cały
      // formularz, żeby pole było nad klawiaturą. Ale gdy kursor
      // schodził poniżej dolnej krawędzi SAMEGO POLA, to nie pomagało:
      // formularz stał dobrze, a kursor i tak był niewidoczny.
      onCursorRectangleChanged: pilnujKursora()

      function pilnujKursora() {
        if (!activeFocus)
          return;
        const r = cursorRectangle;
        const widok = przewijacz.height;
        const zapas = r.height;
        const gora = przewijacz.contentItem.contentY;
        if (r.y + r.height + zapas > gora + widok)
          przewijacz.contentItem.contentY = Math.min(
            r.y + r.height + zapas - widok,
            Math.max(0, pole.contentHeight - widok));
        else if (r.y - zapas < gora)
          przewijacz.contentItem.contentY = Math.max(0, r.y - zapas);
      }

      Component.onCompleted: Qt.callLater(pilnujKursora)
    }
  }

  //! Ile znaków — przy spisie gatunkowym warto wiedzieć, ile już jest.
  Text {
    anchors.right: parent.right
    anchors.top: przewijacz.bottom
    text: pole.text.length > 0 ? qsTr("%1 znaków").arg(pole.text.length) : ""
    visible: isEditing && pole.text.length > 200
    color: Theme.secondaryTextColor
    font.pointSize: Theme.tinyFont.pointSize
  }
}
