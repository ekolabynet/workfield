#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — TRZY PRZYCISKI przy wychodzeniu z formularza.

==========================================================================
CO BYLO
==========================================================================
Wyjscie z formularza przyciskiem wstecz otwiera `cancelDialog`. Ten ma
**dwa przyciski** i tekst po angielsku:

    „You are about to leave editing state, any changes will be lost.
     Proceed?"                                    [Cancel]  [OK]

**„OK" kasuje wszystko.** Przycisk, ktorego nazwa mowi „zgadzam sie",
a dzialanie znaczy „wyrzuc moja prace". Po godzinie wpisywania w terenie
to strata danych z jednego tapniecia — a slowo „OK" nie ostrzega przed
niczym.

Nie ma przy tym **zadnej drogi „zapisz i wyjdz"**. Trzeba albo wrocic do
formularza i szukac zapisu, albo stracic prace.

Piotr, 28.08.2026 z terenu: *„w oknie wyskakujacym po nacisnieciu wstecz
powinny byc 3 przyciski: Powrot do edycji, Zapis i Anulowanie. A w tej
chwili OK kasuje wszystkie zmiany."*

==========================================================================
CO JEST TERAZ
==========================================================================
       [Wróć do edycji]   [Zapisz i wyjdź]   [Porzuć zmiany]
        (bezpieczne)         (główne)         (niszczące)

**Kolejnosc nie jest przypadkowa.** Bezpieczne po lewej, niszczace po
prawej i **z dala od kciuka** trzymajacego telefon. Nazwy mowia, co sie
stanie — „Porzuc zmiany", nie „OK".

Domyslnym (`Dialog.Save`) jest zapis, wiec Enter i przypadkowe potwierdzenie
prowadza do **zachowania pracy**, nie do jej utraty.

==========================================================================
GDY ZAPIS SIE NIE UDA
==========================================================================
`save()` zaczyna od `if (!model.constraintsHardValid) return false`
(QfFeatureForm.qml:1019-1021) — przy nowym obiekcie bez wymaganych pol
zapis odmowi.

Wtedy **wracamy do formularza z komunikatem**, zamiast zamykac okno
i udawac, ze sie udalo. To znaczy, ze „Zapisz i wyjdz" czasem nie zamyka —
i wlasnie dlatego mowi o tym glosno, zeby nie wygladalo na zawieszenie.

Cicha odmowa byla by tu **fałszywa obecnoscia**: przycisk, ktory wyglada
na wykonany i nie zrobil nic.

Uruchom w korzeniu repo:  python3 zastosuj_trzy_przyciski.py
Idempotentna. Kopia: QfFeatureForm.qml.przed_trzema
"""
import os
import shutil
import sys

Q = "src/gui/qml/QfFeatureForm.qml"
MARKER = "Porzuć zmiany"

KOTWICA = '''  QfDialog {
    id: cancelDialog
    parent: mainWindow.contentItem
    z: 10000 // 1000s are embedded feature forms, user a higher value to insure the dialog will always show above embedded feature forms
    title: qsTr("Cancel")
    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      text: {
        if (setupOnly) {
          return qsTr("You are about to cancel the feature setup, proceed?");
        } else if (form.state === 'Add') {
          return qsTr("You are about to dismiss the new feature, proceed?");
        }
        return qsTr("You are about to leave editing state, any changes will be lost. Proceed?");
      }
    }
    onAccepted: {
      form.cancel();
    }
  }'''

NOWE = '''  QfDialog {
    id: cancelDialog
    parent: mainWindow.contentItem
    z: 10000 // 1000s are embedded feature forms, user a higher value to insure the dialog will always show above embedded feature forms
    title: qsTr("Wyjście z formularza")

    // WorkField 28.08.2026 — było DWA przyciski, a „OK" kasowało wszystko.
    // Przycisk, którego nazwa mówi „zgadzam się", a działanie znaczy
    // „wyrzuć moją pracę". Po godzinie wpisywania w terenie to strata
    // danych z jednego tapnięcia — i nie było żadnej drogi „zapisz i wyjdź".
    //
    // Kolejność nie jest przypadkowa: bezpieczne po lewej, niszczące po
    // prawej i z dala od kciuka. Domyślny jest ZAPIS, więc przypadkowe
    // potwierdzenie prowadzi do zachowania pracy, nie do jej utraty.
    standardButtons: Dialog.Cancel | Dialog.Save | Dialog.Discard

    Component.onCompleted: {
      const b = cancelDialog.footer;
      if (b && b.standardButton) {
        const c = b.standardButton(Dialog.Cancel);
        if (c)
          c.text = qsTr("Wróć do edycji");
        const s = b.standardButton(Dialog.Save);
        if (s)
          s.text = qsTr("Zapisz i wyjdź");
        const d = b.standardButton(Dialog.Discard);
        if (d)
          d.text = qsTr("Porzuć zmiany");
      }
    }

    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      text: {
        if (setupOnly) {
          return qsTr("Przerwać zakładanie obiektu?");
        } else if (form.state === 'Add') {
          return qsTr("Nowy obiekt nie został jeszcze zapisany.");
        }
        return qsTr("Masz niezapisane zmiany.");
      }
    }

    // Save = zachowaj i wyjdź.
    onAccepted: {
      if (form.save()) {
        form.cancel();
        return;
      }
      // save() zwraca false przy niespełnionych ograniczeniach twardych
      // (QfFeatureForm.qml:1019). Wracamy do formularza i MÓWIMY dlaczego —
      // ciche zamknięcie udawałoby, że zapis się udał.
      displayToast(qsTr("Nie mogę zapisać: brakuje wymaganych pól. Uzupełnij je albo porzuć zmiany."), "warning");
    }

    // Discard = porzuć. Ta sama czynność, którą wcześniej robiło „OK" —
    // ale teraz nazwana tym, czym jest.
    onDiscarded: {
      form.cancel();
      cancelDialog.close();
    }
  }'''


def main():
    if not os.path.exists(Q):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % Q)

    t = open(Q, encoding="utf-8").read()

    if MARKER in t:
        print("Latka juz jest — nic do zrobienia.")
        return

    n = t.count(KOTWICA)
    if n != 1:
        sys.exit("STOP: kotwica wystepuje %d razy, oczekiwano 1" % n)

    print("Kotwica policzona, nakladam:")
    t = t.replace(KOTWICA, NOWE, 1)
    print("   trzy przyciski + polskie nazwy + obsluga nieudanego zapisu")

    kopia = Q + ".przed_trzema"
    if not os.path.exists(kopia):
        shutil.copy2(Q, kopia)
    open(Q, "w", encoding="utf-8").write(t)
    print("  zapisano %s" % os.path.basename(Q))

    print("""
UWAGA — `standardButton()` na stopce dialogu:
  Nazwy przyciskow podmieniamy w Component.onCompleted, bo QtQuick.Controls
  nie pozwala ustawic ich deklaratywnie. Jesli stopka okaze sie innego typu
  niz DialogButtonBox, przyciski zostana po angielsku — ALE BEDA DZIALAC
  poprawnie. Sprawdz wygladem.

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head -3

Sprawdzian:
  1. otworz plat, zmien cos, wstecz -> trzy przyciski po polsku
  2. „Wroc do edycji"  -> okno znika, zmiany zostaja
  3. „Zapisz i wyjdz"  -> zapis i zamkniecie
  4. nowy obiekt bez wymaganych pol -> „Zapisz" ODMAWIA z komunikatem
  5. „Porzuc zmiany"   -> to, co wczesniej robilo OK
""")


if __name__ == "__main__":
    main()
