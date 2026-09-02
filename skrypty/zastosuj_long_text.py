#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — `QfEditorWidgetLongText`: OSOBNY widget dlugiego tekstu.

==========================================================================
PO CO
==========================================================================
Pole tekstowe w formularzu **przestawalo pokazywac kursor po 600-800
znakach**. Piszesz w ciemno, nie widzisz, co wpisujesz.

Kosztowalo to dwa dni terenu. 31.08 zmusilo Piotra do dzielenia spisu
gatunkowego na dwa pola w szesciu platach; 02.09 wracalo przy kazdym
dluzszym opisie.

**Dziewiec prob nie zdjelo problemu.** Pelna lista w
`claude/KURSOR_dlugi_tekst.md`. Najwazniejsza obserwacja stamtad:
zwiekszenie zapasu w `bottomMargin` ze 120 na 258 px NIC NIE ZMIENILO —
wiec ogranicza cos innego niz brak miejsca na przewiniecie.

Piotr, 02.09: *„LONG TEXT koniecznie."*

==========================================================================
DLACZEGO OSOBNY PLIK, A NIE KOLEJNA LATKA
==========================================================================
Trzy razy doklejalem przewijanie do `QfEditorWidgetTextEdit` i za kazdym
razem platalem sie w jego widocznosci i wysokosci — raz pole **zniknelo
z formularza w calosci**.

Ten widget obsluguje DWA tryby naraz (`TextField` i `TextArea`), przelacza
je przez `IsMultiline`, ma wlasne `scrollCaretIntoView` i sufit dolozony
31.08. Kazda nowa zmiana musi sie z tym wszystkim ulozyc.

Pusty plik nie ma tego bagazu. Jeden tryb, jedno zachowanie, jedna
wysokosc.

**Nowego TYPU widgetu nie da sie dodac** — nazwa pliku bierze sie wprost
z typu ustawionego w QGIS (`QfFeatureForm.qml:1074`), a listy typow QGIS
nie rozszerzymy bez wtyczki. Wiec przekierowujemy `TextEdit` z wlaczona
wielolinia; w projekcie nie zmienia sie nic.

==========================================================================
CZYM SIE ROZNI OD POPRZEDNICH PROB
==========================================================================
**`TextArea` w `ScrollView`, nie odwrotnie.** 01.09 wlozylem `Flickable`
do SRODKA `TextArea` — czyli na opak. `TextArea` przewija sie wylacznie
wtedy, gdy przewijacz jest jej RODZICEM.

**Wysokosc USTALONA, nie z tresci.** Pole nie rosnie, wiec formularz nie
musi za nim nadazac. Cala walka z `contentHeight` i `bottomMargin` staje
sie bezprzedmiotowa.

**Kursor pilnowany wewnatrz pola**, nie przez przewijanie formularza.
`scrollCaretIntoView` przesuwal caly formularz, zeby pole bylo nad
klawiatura — ale gdy kursor byl ponizej DOLNEJ KRAWEDZI POLA, to nie
pomagalo.

==========================================================================
SIATKA BEZPIECZENSTWA — juz istnieje
==========================================================================
`QfFeatureForm.qml:1083`: gdy plik widgetu sie nie wczyta, formularz wraca
do `QfEditorWidgetTextEdit`. Wiec **nawet blad skladni nie zabierze pola** —
wroci stary widget z jego znanymi ograniczeniami.

Cofniecie latki to jedna linia w formularzu; stary widget zostaje nietkniety.

Uruchom w korzeniu repo:  python3 zastosuj_long_text.py
Idempotentna. Kopia: QfFeatureForm.qml.przed_longtext
"""
import os
import shutil
import sys

WIDGET = "src/gui/qml/editorwidgets/QfEditorWidgetLongText.qml"
CMAKE = "src/gui/qml/CMakeLists.txt"
FF = "src/gui/qml/QfFeatureForm.qml"

TRESC = '''import QtQuick
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
'''

FF_KOTWICA = """              return 'editorwidgets/QfEditorWidget' + (widget || 'TextEdit') + '.qml';"""

FF_NOWE = """              // WorkField 02.09.2026 — dlugi tekst do OSOBNEGO widgetu.
              //
              // `TextEdit` z wielolinia rosnie razem z trescia i po 600-800
              // znakach kursor schodzi pod krawedz — nie widac, co sie pisze.
              // Dziewiec prob naprawy w miejscu nie zdjelo problemu
              // (patrz claude/KURSOR_dlugi_tekst.md).
              //
              // Nowego TYPU widgetu nie da sie dodac: nazwa pliku bierze sie
              // wprost z typu ustawionego w QGIS, a jego listy nie rozszerzymy.
              // Wiec przekierowujemy TextEdit z wlaczona wielolinia —
              // w projekcie nie zmienia sie nic.
              //
              // Gdy plik sie nie wczyta, linia 1083 wraca do TextEdit,
              // wiec pole nie zniknie nawet przy bledzie.
              if (widget === 'TextEdit' && config && config['IsMultiline'] === true) {
                return 'editorwidgets/QfEditorWidgetLongText.qml';
              }
              return 'editorwidgets/QfEditorWidget' + (widget || 'TextEdit') + '.qml';"""


def main():
    if os.path.exists(WIDGET):
        print("Widget juz jest — nic do zrobienia.")
        return
    if not os.path.exists(FF):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % FF)

    f = open(FF, encoding="utf-8").read()
    n = f.count(FF_KOTWICA)
    if n != 1:
        sys.exit("STOP: kotwica w formularzu wystepuje %d razy, oczekiwano 1" % n)

    print("Kotwica policzona, nakladam:")

    os.makedirs(os.path.dirname(WIDGET), exist_ok=True)
    open(WIDGET, "w", encoding="utf-8").write(TRESC)
    print("   %s (nowy)" % os.path.basename(WIDGET))

    kopia = FF + ".przed_longtext"
    if not os.path.exists(kopia):
        shutil.copy2(FF, kopia)
    open(FF, "w", encoding="utf-8").write(f.replace(FF_KOTWICA, FF_NOWE, 1))
    print("   przekierowanie w %s" % os.path.basename(FF))

    # --- CMakeLists: widgety siedza w podkatalogu, wiec inna konwencja
    if os.path.exists(CMAKE):
        c = open(CMAKE, encoding="utf-8").read()
        if "QfEditorWidgetLongText.qml" not in c:
            wzor = "editorwidgets/QfEditorWidgetTextEdit.qml"
            if wzor in c:
                open(CMAKE, "w", encoding="utf-8").write(
                    c.replace(wzor, "editorwidgets/QfEditorWidgetLongText.qml\n    " + wzor, 1))
                print("   dopisany do CMakeLists")
            else:
                print("   UWAGA: dopisz editorwidgets/QfEditorWidgetLongText.qml"
                      " do %s RECZNIE" % CMAKE)

    print("""
Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head -5

Sprawdzian NA DESKTOPIE (minuta zamiast kwadransa):
  1. otworz plat, wejdz w OPIS_PLATU albo ZAPIS_SUROWY_GATUNKI
  2. wklej 1500 znakow
  3. pole ma miec STALA wysokosc i pasek przewijania z prawej
  4. pisz na koncu — kursor ma zostac widoczny
  5. pod polem licznik znakow (powyzej 200)

Gdy pole nie zadziala:
  cofnij JEDNA linie w QfFeatureForm.qml (przekierowanie) — stary widget
  jest nietkniety i wroci natychmiast.

Wysokosc pola: 40% formularza. Do zmiany kluczem
`WorkField/udzialDlugiegoPola` (15-80).
""")


if __name__ == "__main__":
    main()
