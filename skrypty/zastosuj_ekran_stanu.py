#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — STAN PROJEKTU widoczny w terenie.

==========================================================================
PO CO
==========================================================================
25.08.2026 punkty nie siadaly na miejscu przy malych platach. Przyczyne
znalezlismy wieczorem, przy komputerze, grepujac XML projektu. **W terenie
nie bylo jak sprawdzic, co jest ustawione.**

Czasownik `NarzedziaProjektu.stanProjektu()` powstal tego samego wieczora
i dziala — brakowalo widoku.

==========================================================================
GDZIE I DLACZEGO TAM
==========================================================================
`QfKontrolaProjektu` **nie ma interfejsu** — to `Item` bez widoku, ktory
sprawdza i pokazuje toast z przyciskiem „Pokaz". Ekranem jest
`QfNaprawaProjektu` (Popup) i tam trafia sekcja.

Zaden nowy ekran: czlowiek w terenie ma jedno miejsce, w ktorym pyta
„czy z tym projektem wszystko gra", a nie dwa do zapamietania.

==========================================================================
KOLEJNOSC ODWROCONA WOBEC CZASOWNIKA — swiadomie
==========================================================================
`stanProjektu()` zwraca `warstwy`, `pomiar`, `dane`, `ostrzezenia`.
Na ekranie kolejnosc jest **odwrotna**:

  1. OSTRZEZENIA   — zwykle zero do trzech pozycji; to one odpowiadaja
                     na pytanie „czy cos jest nie tak"
  2. POMIAR i DANE — krotkie podsumowanie, slownie
  3. WARSTWY       — najdluzsze i najrzadziej potrzebne, ZWINIETE

Pelny zrzut na telefonie bylby sciana tekstu do przewijania. Otwierasz
i pierwsze, co widzisz, to ODPOWIEDZ, a nie dane do przeczytania.

Sekcja jest **tylko do odczytu** — nic nie zapisuje i nie zmienia. Stopka
ekranu mowi „zapisuje wylacznie pliki obok projektu"; ta sekcja nie
zapisuje nawet tego.

Uruchom w korzeniu repo:  python3 zastosuj_ekran_stanu.py
Idempotentna. Kopia: QfNaprawaProjektu.qml.przed_stanem
"""
import os
import shutil
import sys

Q = "src/app/qml/QfNaprawaProjektu.qml"
MARKER = "stanProjektu"

KOTWICA = '''    Text {
      Layout.fillWidth: true
      text: qsTr("Ten ekran zapisuje wyłącznie pliki obok projektu. Nie zmienia danych w dane.gpkg.")
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
    }'''

NOWE = '''    // ------------------------------------------------------ stan projektu
    //
    // 25.08.2026: punkty nie siadały na miejscu przy małych płatach,
    // a przyczynę (`type=3`, edycja topologiczna) znaleźliśmy dopiero
    // wieczorem, grepując XML. W terenie nie było jak sprawdzić, co jest
    // ustawione. Ta sekcja odpowiada na to pytanie na miejscu.
    //
    // Kolejność ODWROTNA wobec tego, co zwraca czasownik: najpierw
    // ostrzeżenia, bo to one mówią, czy coś jest nie tak. Warstwy na końcu
    // i zwinięte — najdłuższe i najrzadziej potrzebne.

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
      opacity: 0.4
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Jak ten projekt jest ustawiony")
      font: Theme.strongTipFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
    }

    Item {
      id: stanProjektu

      property var dane: ({})

      function odswiez() {
        dane = qgisProject ? NarzedziaProjektu.stanProjektu(qgisProject) : ({});
      }

      // Odświeżamy przy każdym otwarciu ekranu, nie raz przy starcie:
      // ustawienia zmieniają się w trakcie pracy, a nieaktualny zrzut
      // jest gorszy niż jego brak.
      Connections {
        target: naprawa
        function onOpened() { stanProjektu.odswiez(); }
      }

      Component.onCompleted: odswiez()
    }

    // --- ostrzeżenia: liczone z DANYCH, nie z ustawień

    Repeater {
      model: stanProjektu.dane.ostrzezenia !== undefined
             ? stanProjektu.dane.ostrzezenia : []

      delegate: Text {
        required property var modelData
        Layout.fillWidth: true
        text: (modelData.waga === "brak" ? "✗  " : "!  ") + modelData.opis
        font: Theme.tipFont
        color: modelData.waga === "brak" ? Theme.errorColor : Theme.warningColor
        wrapMode: Text.WordWrap
      }
    }

    Text {
      Layout.fillWidth: true
      visible: stanProjektu.dane.ostrzezenia !== undefined
               && stanProjektu.dane.ostrzezenia.length === 0
      text: qsTr("Nic nie budzi wątpliwości.")
      font: Theme.tipFont
      color: Theme.secondaryTextColor
    }

    // --- pomiar: słownie, bo `type=3` nic nie mówi człowiekowi
    //     (a to właśnie ta liczba kosztowała dzień terenu)

    Text {
      Layout.fillWidth: true
      visible: stanProjektu.dane.pomiar !== undefined
      font: Theme.tipFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      text: {
        const p = stanProjektu.dane.pomiar;
        if (p === undefined)
          return "";
        const w = [];
        if (p.przyciaganieWlaczone) {
          const typ = p.typObowiazujacy !== undefined ? p.typObowiazujacy : p.typ;
          w.push(qsTr("Przyciąganie: %1, tolerancja %2 %3")
                 .arg(typ).arg(p.tolerancja).arg(p.jednostka));
          if (p.tryb !== undefined)
            w.push(qsTr("   tryb: %1").arg(p.tryb));
          if (p.przeciecia)
            w.push(qsTr("   także do przecięć"));
        } else {
          w.push(qsTr("Przyciąganie: wyłączone"));
        }
        if (p.unikanieNakladania)
          w.push(qsTr("Unikanie nakładania: %1")
                 .arg(p.warstwyNakladania.length > 0
                      ? p.warstwyNakladania.join(", ")
                      : qsTr("bez warstw")));
        else
          w.push(qsTr("Unikanie nakładania: wyłączone"));
        if (p.edycjaTopologiczna)
          w.push(qsTr("Edycja topologiczna: WŁĄCZONA"));
        return w.join("\\n");
      }
    }

    // --- dane: gdzie zapisuje i czy jest słownik

    Text {
      Layout.fillWidth: true
      visible: stanProjektu.dane.dane !== undefined
      font: Theme.tipFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
      text: {
        const d = stanProjektu.dane.dane;
        if (d === undefined)
          return "";
        const w = [];
        w.push(qsTr("Zapisuje do: %1")
               .arg(d.plikDanych !== "" ? d.plikDanych : qsTr("— brak pliku danych!")));
        w.push(qsTr("Słownik gatunków: %1")
               .arg(d.wskazniki ? qsTr("jest") : qsTr("BRAK")));
        return w.join("\\n");
      }
    }

    // --- warstwy: zwinięte, bo to najdłuższa i najrzadziej potrzebna część

    Button {
      Layout.fillWidth: true
      flat: true
      visible: stanProjektu.dane.warstwy !== undefined
      text: listaWarstw.visible
            ? qsTr("Ukryj warstwy")
            : qsTr("Pokaż warstwy (%1)").arg(stanProjektu.dane.warstwy !== undefined
                                             ? stanProjektu.dane.warstwy.length : 0)
      onClicked: listaWarstw.visible = !listaWarstw.visible
    }

    ColumnLayout {
      id: listaWarstw
      Layout.fillWidth: true
      spacing: 2
      visible: false

      Repeater {
        model: stanProjektu.dane.warstwy !== undefined ? stanProjektu.dane.warstwy : []

        delegate: Text {
          required property var modelData
          Layout.fillWidth: true
          font: Theme.tinyFont
          wrapMode: Text.WordWrap
          // Warstwa wskazująca poza katalog projektu nie pojedzie w teren —
          // na telefonie będzie pusta i nikt tego nie zauważy przed wyjazdem.
          color: modelData.wKatalogu ? Theme.secondaryTextColor : Theme.warningColor
          text: {
            let s = modelData.nazwa + "  ·  " + modelData.geometria
                  + "  ·  " + modelData.obiektow;
            if (modelData.plik !== "")
              s += "  ·  " + modelData.plik;
            if (modelData.wEdycji)
              s += qsTr("  ·  W EDYCJI");
            if (!modelData.wKatalogu)
              s += qsTr("  ·  POZA KATALOGIEM");
            return s;
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
      opacity: 0.4
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Ten ekran zapisuje wyłącznie pliki obok projektu. Nie zmienia danych w dane.gpkg.")
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      wrapMode: Text.WordWrap
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
    print("   sekcja stanu projektu (ostrzezenia, pomiar, dane, warstwy)")

    kopia = Q + ".przed_stanem"
    if not os.path.exists(kopia):
        shutil.copy2(Q, kopia)
    open(Q, "w", encoding="utf-8").write(t)
    print("  zapisano %s" % os.path.basename(Q))

    print("""
Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head

W logu MUSI byc 'Running rcc for resource'.

Sprawdzian na desktopie — ekran otwiera sie z toasta kontroli projektu
albo przez ekranNaprawy.open(). Na projekcie 10_0 spodziewane:
  * ostrzezenie o pustych geometriach (jesli jeszcze sa)
  * „Przyciaganie: wierzcholek, tolerancja 12 piksele ekranu"
  * „Unikanie nakladania: platy"
  * „Zapisuje do: dane.gpkg", „Slownik gatunkow: jest"
  * po rozwinieciu: 19 warstw z liczba obiektow
""")


if __name__ == "__main__":
    main()
