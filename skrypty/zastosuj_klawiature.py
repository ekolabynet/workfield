#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 31 — kursor nad klawiatura ekranowa.

POWOD. Metoda OpenVTA stoi na tym, ze proza jest produktem koncowym:
operator pisze opis w polu UWAGI, a Gboard rozwija skroty. Jesli przy
trzeciej linijce kursor chowa sie pod klawiatura, czlowiek pisze na
slepo do pola, ktore ma wyjechac z terenu w formie finalnej.

SPRAWDZONE W KODZIE: w calym drzewie `Qt.inputMethod` wystepuje wylacznie
jako `hide()`. `keyboardRectangle` — zero wystapien. Nikt nigdy nie liczyl
klawiatury. To nie regresja po plywajacej karcie z 15.08, tylko funkcja,
ktorej nie bylo. `platform/android/AndroidManifest.xml` nie deklaruje
`windowSoftInputMode`, wiec na przewijanie przez system tez nie liczymy.

CO ROBI:
  1. FeatureForm.qml — Flickable formularza dostaje dolny margines rowny
     zaslonietej czesci ekranu, wiec MA DOKAD przewinac. Bez tego ostatnie
     pole i tak nie wyjedzie nad klawiature, choćby ktos je przewijal.
  2. TextEdit.qml — po kazdym ruchu kursora pole dosuwa go do widocznej
     czesci. Dotyczy obu wariantow: jednolinijkowego i wielolinijkowego
     (UWAGI to ten drugi).

JEDNOSTKI keyboardRectangle — mechanizm samonaprawczy, nie zalozenie.
Qt na Androidzie bywa niejednoznaczne, czy prostokat klawiatury jest
w pikselach fizycznych czy logicznych. Zamiast wpisac jedna wersje
i czekac na teren, latka ROZPOZNAJE to po fakcie: jesli prostokat nie
miesci sie w oknie, znaczy ze przyszedl w pikselach fizycznych i dzieli
go przez devicePixelRatio. Ta sama rodzina co kolejnosc osi w ULDK.

CZEGO NIE DA SIE SPRAWDZIC NA KOMPUTERZE: desktop nie ma klawiatury
ekranowej, wiec `Qt.inputMethod.visible` jest tam zawsze false, a cala
sciezka — martwa. Build desktopowy potwierdzi wylacznie, ze nic nie
zepsulismy. Prawdziwy test to Android.

Uruchom w korzeniu repo:  python3 zastosuj_klawiature.py
Idempotentna. Kopie: <plik>.przed_klawiatura
"""
import os
import shutil
import sys

FF = "src/gui/qml/FeatureForm.qml"
TE = "src/gui/qml/editorwidgets/TextEdit.qml"

MARKER = "keyboardInset"

# --------------------------------------------------------------- FeatureForm

FF_IMPORT_OLD = """import QtQuick
import QtQuick.Controls
"""

FF_IMPORT_NEW = """import QtQuick
import QtQuick.Window
import QtQuick.Controls
"""

FF_PROP_ANCHOR = "  property double topMargin: 0.0"

FF_PROP_NEW = '''  // WorkField: how much of this form the on-screen keyboard covers.
  // Feeds the form Flickable's bottom margin, so the content has somewhere
  // to scroll to instead of hiding the caret behind the keyboard.
  //
  // Qt is ambiguous about the units of keyboardRectangle on Android
  // (physical vs logical pixels). We do not guess: a rectangle that does
  // not fit inside the window must have arrived in physical pixels.
  readonly property real keyboardInset: {
    if (!Qt.inputMethod.visible)
      return 0;
    const kr = Qt.inputMethod.keyboardRectangle;
    if (!kr || kr.height <= 0)
      return 0;
    let scale = 1;
    const windowHeight = form.Window.height;
    if (windowHeight > 0 && kr.y > windowHeight)
      scale = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1;
    const keyboardTop = kr.y / scale;
    const formBottom = form.mapToItem(null, 0, form.height).y;
    return Math.max(0, formBottom - keyboardTop);
  }

'''

FF_MARGIN_OLD = "            bottomMargin: form.bottomMargin + (form.model.isWizard ? wizardNavigationContainer.height : 0)"

FF_MARGIN_NEW = """            // WorkField: keyboardInset is read back by TextEdit.qml, which
            // needs to know how much of this Flickable is actually covered.
            property real keyboardInset: form.keyboardInset
            bottomMargin: form.bottomMargin + (form.model.isWizard ? wizardNavigationContainer.height : 0) + keyboardInset"""

# ------------------------------------------------------------------ TextEdit

TE_FUNC_ANCHOR = "  FontMetrics {"

TE_FUNC_NEW = '''  // WorkField: keep the caret above the on-screen keyboard while typing.
  // The enclosing Flickable is found by walking up the parent chain, so this
  // works in the feature form, in embedded relation forms and anywhere else
  // a text widget is placed inside a scrollable view.
  function scrollCaretIntoView(editor) {
    if (!editor || !editor.activeFocus)
      return;

    let flick = topItem.parent;
    while (flick && (flick.contentY === undefined || flick.contentHeight === undefined))
      flick = flick.parent;
    if (!flick)
      return;

    const inset = flick.keyboardInset !== undefined ? flick.keyboardInset : 0;
    const caret = editor.cursorRectangle;
    const caretTop = editor.mapToItem(flick.contentItem, 0, caret.y).y;
    const caretBottom = caretTop + caret.height;
    const margin = caret.height;

    const visibleHeight = flick.height - inset;
    if (visibleHeight <= 0)
      return;

    let target = flick.contentY;
    if (caretBottom + margin > flick.contentY + visibleHeight)
      target = caretBottom + margin - visibleHeight;
    else if (caretTop - margin < flick.contentY)
      target = caretTop - margin;

    const maxY = Math.max(0, flick.contentHeight + flick.bottomMargin - flick.height);
    flick.contentY = Math.max(0, Math.min(target, maxY));
  }

'''

TE_FIELD_OLD = """  TextField {
    id: textField"""

TE_FIELD_NEW = """  TextField {
    id: textField

    // WorkField: caret above the keyboard (patch 31)
    onCursorRectangleChanged: topItem.scrollCaretIntoView(textField)
    onActiveFocusChanged: {
      if (activeFocus)
        Qt.callLater(topItem.scrollCaretIntoView, textField);
    }"""

TE_AREA_OLD = """  TextArea {
    id: textArea"""

TE_AREA_NEW = """  TextArea {
    id: textArea

    // WorkField: caret above the keyboard (patch 31) — this is the variant
    // the UWAGI field uses, so this is the one that matters in the field.
    onCursorRectangleChanged: topItem.scrollCaretIntoView(textArea)
    onActiveFocusChanged: {
      if (activeFocus)
        Qt.callLater(topItem.scrollCaretIntoView, textArea);
    }"""

# ------------------------------------------------------------------ mechanika


def read(path):
    if not os.path.exists(path):
        sys.exit("STOP: brak pliku %s (uruchom w korzeniu repo)" % path)
    with open(path, encoding="utf-8") as f:
        return f.read()


def once(text, anchor, path):
    n = text.count(anchor)
    if n != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1:\n  %s"
                 % (path, n, anchor.strip().splitlines()[0]))


def save(path, text):
    backup = path + ".przed_klawiatura"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("  zapisano %s (kopia: %s)" % (path, os.path.basename(backup)))


def main():
    ff, te = read(FF), read(TE)

    applied = [MARKER in ff, "scrollCaretIntoView" in te]
    if all(applied):
        print("Latka 31 juz jest — nic do zrobienia.")
        return
    if any(applied):
        sys.exit("STOP: latka nalozona polowicznie %s. Przywroc kopie .przed_klawiatura." % applied)

    for anchor in (FF_IMPORT_OLD, FF_PROP_ANCHOR, FF_MARGIN_OLD):
        once(ff, anchor, FF)
    for anchor in (TE_FUNC_ANCHOR, TE_FIELD_OLD, TE_AREA_OLD):
        once(te, anchor, TE)

    print("Kotwice policzone (6/6), nakladam:")

    ff = ff.replace(FF_IMPORT_OLD, FF_IMPORT_NEW, 1)
    ff = ff.replace(FF_PROP_ANCHOR, FF_PROP_NEW + FF_PROP_ANCHOR, 1)
    ff = ff.replace(FF_MARGIN_OLD, FF_MARGIN_NEW, 1)
    save(FF, ff)

    te = te.replace(TE_FUNC_ANCHOR, TE_FUNC_NEW + TE_FUNC_ANCHOR, 1)
    te = te.replace(TE_FIELD_OLD, TE_FIELD_NEW, 1)
    te = te.replace(TE_AREA_OLD, TE_AREA_NEW, 1)
    save(TE, te)

    print("\nGotowe. Oba pliki sa UPSTREAMOWE — delta rosnie, do NOTICE.md.")
    print("Zmiana jest generyczna (nie dotyczy niczego polskiego ani terenowego)")
    print("-> kandydat na issue do QFielda.")
    print("\nBuild:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | tail -20")
    print("Szukaj w logu: 'Running rcc for resource gui_qml' — bez tego zmiana")
    print("nie weszla do binarki.")
    print("\nUWAGA: na desktopie nie ma klawiatury ekranowej, wiec build")
    print("potwierdzi tylko brak regresji. Test wlasciwy = Android.")


if __name__ == "__main__":
    main()
