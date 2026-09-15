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

  //! Doraznie zmieniona wysokosc; 0 = bierzemy z ustawien.
  //! NIE ZAPISUJEMY jej nigdzie: uchwyt jest narzedziem na chwile, a nie
  //! ustawieniem, o ktorym trzeba pamietac, ze sie je zmienilo.
  property real wysokoscDorazna: 0

  readonly property real wysokoscTeraz: wysokoscDorazna > 0
                                        ? wysokoscDorazna : wysokoscPola

  height: przewijacz.height + uchwyt.height + 4

  ScrollView {
    id: przewijacz

    anchors.left: parent.left
    anchors.right: parent.right
    height: dlugiTekst.wysokoscTeraz
    clip: true

    // Pasek pokazuje, ILE tekstu jest poza widokiem — przy spisie
    // gatunkowym to jedyny znak, że treść sięga dalej.
    ScrollBar.vertical.policy: pole.contentHeight > przewijacz.height
                               ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

    TextArea {
      id: pole

      enabled: isEditable && isEditing
      readOnly: !isEditable || !isEditing
      wrapMode: TextEdit.Wrap
      font: Theme.defaultFont
      color: (!isEditable && isEditing) ? Theme.mainTextDisabledColor : Theme.mainTextColor
      selectByMouse: true
      leftPadding: isEditing ? 10 : 0

      text: isNull ? '' : String(value)

      // Bez wlasnego tla — obrys rysuje `ramka` NA ZEWNATRZ przewijacza.
      // Tlo w `TextArea` wedrowalo razem z trescia i rozjezdzalo sie
      // z polem (14.09.2026).
      background: null

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

  // Ramka POLA, nie tresci. Rysowana na zewnatrz przewijacza, wiec
  // zostaje na miejscu niezaleznie od tego, jak przewijacz ulozy tekst.
  Rectangle {
    id: ramka

    anchors.fill: przewijacz
    visible: pole.enabled || (!isEditable && isEditing)
    color: "transparent"
    border.width: 1
    border.color: pole.activeFocus ? Theme.mainColor : Theme.controlBorderColor
    radius: 4
    z: -1
  }

  // Uchwyt: przeciagniecie w dol powieksza pole, w gore zmniejsza.
  // Granice te same co dla wartosci z ustawien — 15-80% formularza.
  Item {
    id: uchwyt

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: przewijacz.bottom
    height: isEditing ? 18 : 0
    visible: isEditing

    Rectangle {
      anchors.centerIn: parent
      width: 44
      height: 4
      radius: 2
      color: obszar.ciagne ? Theme.mainColor : Theme.controlBorderColor
    }

    MouseArea {
      id: obszar

      anchors.fill: parent
      cursorShape: Qt.SizeVerCursor
      // Bez tego ruch przechwytuje `ScrollView` nad uchwytem: `onPressed`
      // dochodzi (uchwyt zmienia kolor), a `onPositionChanged` juz nie.
      preventStealing: true

      property real odY: 0
      property real odWys: 0
      property bool ciagne: false

      onPressed: mouse => {
        odY = mouse.y;
        odWys = dlugiTekst.wysokoscTeraz;
        ciagne = true;
        // Krotkie drgniecie zamiast komunikatu: w rekawicach nie widac,
        // czy uchwyt zlapal. Drugie przy puszczeniu zamyka gest.
        if (typeof platformUtilities !== "undefined" && platformUtilities.vibrate)
          platformUtilities.vibrate(15);
      }
      onReleased: {
        ciagne = false;
        if (typeof platformUtilities !== "undefined" && platformUtilities.vibrate)
          platformUtilities.vibrate(25);
      }
      onCanceled: ciagne = false
      // PRZYROSTOWO, nie od punktu chwytu.
      //
      // Uchwyt przesuwa sie RAZEM z polem: gdy pole rosnie o `d`, uchwyt
      // schodzi o `d`, palec zostaje w tym samym miejscu ekranu i `mouse.y`
      // WRACA do wartosci z chwili chwytu. Liczenie `odWys + (y - odY)`
      // dawalo wiec zero — pole drgalo i wracalo, a z zewnatrz wygladalo,
      // jakby uchwyt nie dzialal wcale.
      onPositionChanged: mouse => {
        if (!ciagne)
          return;
        const d = mouse.y - odY;
        if (d === 0)
          return;
        const nowa = dlugiTekst.wysokoscTeraz + d;
        // Ten sam sufit i podloga co przy wartosci z ustawien: pole
        // wieksze niz 80% formularza zaslania reszte, mniejsze niz 96 px
        // nie miesci nawet dwoch wierszy.
        // Sufit z WYSOKOSCI OKNA, nie z rodzica.
        //
        // Pierwszy rodzic o niezerowej wysokosci to wiersz formularza,
        // a jego wysokosc zalezy od wysokosci POLA. Liczenie sufitu z niego
        // bylo sprzezeniem zwrotnym: kazde zdarzenie dociskalo wynik w dol
        // (94,4 -> 93,1 -> 92,1 -> ...), wiec pole nie roslo, tylko malalo.
        const gorne = (typeof mainWindow !== "undefined" && mainWindow.height > 0)
                      ? mainWindow.height * 0.7 : 600;
        dlugiTekst.wysokoscDorazna = Math.min(gorne, Math.max(96, nowa));
      }
    }
  }

  //! Ile znaków — przy spisie gatunkowym warto wiedzieć, ile już jest.
  Text {
    anchors.right: parent.right
    anchors.top: uchwyt.bottom
    text: pole.text.length > 0 ? qsTr("%1 znaków").arg(pole.text.length) : ""
    visible: isEditing && pole.text.length > 200
    color: Theme.secondaryTextColor
    font.pointSize: Theme.tinyFont.pointSize
  }
}
