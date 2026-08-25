#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — OLOWEK I WYBOR WARSTWY takze na belce MOBILNEJ.

==========================================================================
PO CO
==========================================================================
Poprzednia latka dodala olowek i wybierak do belki biurkowej
(`QfDesktopChrome.qml`). **Ale cala rzecz byla potrzebna w TERENIE** — zeby
nie otwierac lewej szuflady przy kazdym nowym obiekcie.

W terenie dziala inna belka: `QgisMobileapp.qml`, `wierszGorny`. Tam byla
dotad tylko plakietka „EDYCJA".

==========================================================================
CZYM RZNI SIE OD WERSJI BIURKOWEJ — I DLACZEGO
==========================================================================

**1. Rozmiar celu, nie oszczednosc miejsca.**
Na biurku olowek ma 26 px i wystarcza pod myszka. Pod palcem w rekawicy
trzeba **co najmniej 44 px** — to minimum z wytycznych dotykowych i z
praktyki tego projektu (kafle paska maja tyle samo).

Zeby to zmiescic, **nazwa projektu ustepuje**: bylo 40% szerokosci, jest 28%.
Nazwa projektu jest informacyjna — czlowiek w terenie wie, w ktorym parku
stoi. Nazwa WARSTWY i olowek sa robocze.

**2. Wybierak jako arkusz od dolu, nie Menu.**
`Menu` z QtQuick.Controls daje pozycje wysokosci menu biurkowego — pod
palcem za male. Lista warstw idzie wiec jako `Dialog` z wierszami po 48 px,
tak jak reszta wyborow w aplikacji.

**3. Tapniecie w nazwe warstwy otwiera wybierak** — tak samo jak na biurku.
Podzial jest ten sam: nazwa odpowiada na „ktora warstwa", olowek na
„czy rysuje".

==========================================================================
WSPOLNA LOGIKA
==========================================================================
Olowek wola `dashBoard.przelaczRysowanie()` — te sama funkcje, ktora wola
szuflada i belka biurkowa. Trzy przyciski, jedno zachowanie; przy zmianie
nie trzeba pamietac o trzech miejscach.

Uruchom w korzeniu repo:  python3 zastosuj_olowek_mobilny.py
Idempotentna. Kopia: QgisMobileapp.qml.przed_olowkiem_mob
"""
import os
import shutil
import sys

Q = "src/app/qml/QgisMobileapp.qml"
MARKER = "wybierakWarstwMobilny"

KOTWICA = '''        Text {
          Layout.preferredWidth: parent.width * 0.4
          visible: mainWindow.projectTitle !== ""
          text: mainWindow.projectTitle
          color: Theme.mainOverlayColor
          opacity: 0.75
          font.pointSize: Theme.tinyFont.pointSize
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: dashBoard.activeLayer ? dashBoard.activeLayer.name : qsTr("Brak aktywnej warstwy")
          color: Theme.mainOverlayColor
          font.pointSize: Theme.tipFont.pointSize
          font.bold: true
          elide: Text.ElideRight
        }

        // Wskaźnik otwartej sesji edycji — wspólny komponent, bo ta sama
        // plakietka jest też na belce biurkowej (QfDesktopChrome).
        QfZnacznikEdycji {
          Layout.alignment: Qt.AlignVCenter
          warstwa: dashBoard.activeLayer
        }'''

NOWE = '''        // Nazwa projektu USTĘPUJE miejsca ołówkowi: było 0.4, jest 0.28.
        // W terenie człowiek wie, w którym parku stoi — nazwa projektu jest
        // informacyjna, a nazwa warstwy i ołówek są robocze.
        Text {
          Layout.preferredWidth: parent.width * 0.28
          visible: mainWindow.projectTitle !== ""
          text: mainWindow.projectTitle
          color: Theme.mainOverlayColor
          opacity: 0.75
          font.pointSize: Theme.tinyFont.pointSize
          elide: Text.ElideRight
        }

        Text {
          id: nazwaWarstwyMob
          Layout.fillWidth: true
          text: dashBoard.activeLayer ? dashBoard.activeLayer.name : qsTr("Brak aktywnej warstwy")
          color: Theme.mainOverlayColor
          font.pointSize: Theme.tipFont.pointSize
          font.bold: true
          elide: Text.ElideRight

          // Tapnięcie w nazwę = wybór warstwy, bez otwierania szuflady.
          MouseArea {
            anchors.fill: parent
            // Cel dotykowy sięga poza sam tekst — nazwa bywa krótka
            // („platy"), a palec w rękawicy nie jest precyzyjny.
            anchors.topMargin: -10
            anchors.bottomMargin: -10
            onClicked: {
              // Aplikacja świadomie blokuje zmianę warstwy w trakcie
              // rysowania (allowActiveLayerChange). Szanujemy to.
              if (!dashBoard.allowActiveLayerChange) {
                displayToast(qsTr("Najpierw zakończ rysowany obiekt"), "warning");
                return;
              }
              wybierakWarstwMobilny.otworz();
            }
          }
        }

        // Wskaźnik otwartej sesji edycji — wspólny komponent, bo ta sama
        // plakietka jest też na belce biurkowej (QfDesktopChrome).
        QfZnacznikEdycji {
          Layout.alignment: Qt.AlignVCenter
          warstwa: dashBoard.activeLayer
        }

        // Ołówek: przełącza rysowanie. Ta sama funkcja, którą wołają
        // szuflada i belka biurkowa — dashBoard.przelaczRysowanie().
        //
        // 44 px, nie 26 jak na biurku: pod palcem w rękawicy mniejszy cel
        // jest nietrafialny. Tyle samo mają kafle paska szybkiego przechwytu.
        QfToolButton {
          Layout.alignment: Qt.AlignVCenter
          width: 44
          height: 44
          padding: 0
          round: true

          readonly property bool rysujemy: stateMachine.state === "digitize"
          readonly property bool mozna: dashBoard.activeLayer && !dashBoard.activeLayer.readOnly

          iconSource: Theme.getThemeVectorIcon("ic_create_white_24dp")
          bgcolor: rysujemy ? "#00E676" : "transparent"
          iconColor: rysujemy ? "#062E12" : Theme.mainOverlayColor
          opacity: !mozna ? 0.3 : rysujemy ? 1.0 : 0.85

          onClicked: dashBoard.przelaczRysowanie(dashBoard.activeLayer)
        }'''

# ---------------------------------------------------------------- wybierak

WYBIERAK = '''
  // Wybór aktywnej warstwy z górnej belki — wersja terenowa.
  //
  // Arkusz z wierszami po 48 px, nie Menu: pozycje menu biurkowego są pod
  // palcem za małe. Lista FILTROWANA przez warstwyRobocze() — w projekcie
  // ZZW jest 19 warstw, roboczych dziesięć; reszta to podkłady, słownik
  // i tabele ZAL_.
  Dialog {
    id: wybierakWarstwMobilny

    parent: mainWindow.contentItem
    modal: true
    standardButtons: Dialog.Cancel
    title: qsTr("Warstwa robocza")

    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 420)

    function otworz() {
      listaWarstwMob.clear();
      const warstwy = NarzedziaProjektu.warstwyRobocze(qgisProject);
      for (let i = 0; i < warstwy.length; i++)
        listaWarstwMob.append(warstwy[i]);
      if (listaWarstwMob.count === 0) {
        displayToast(qsTr("Projekt nie ma warstw roboczych"), "warning");
        return;
      }
      open();
    }

    ListModel {
      id: listaWarstwMob
    }

    contentItem: ListView {
      implicitHeight: Math.min(contentHeight, mainWindow.height * 0.6)
      clip: true
      model: listaWarstwMob

      delegate: ItemDelegate {
        width: ListView.view.width
        height: 48

        // Warstwa właśnie aktywna — żeby nie szukać jej wzrokiem na liście.
        readonly property bool biezaca: dashBoard.activeLayer
                                        && dashBoard.activeLayer.name === model.nazwa

        contentItem: Row {
          spacing: 10
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: model.nazwa
            font.pointSize: Theme.tipFont.pointSize
            font.bold: biezaca
            color: Theme.mainTextColor
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            // Typ geometrii w nawiasie, bo „platy" i „platy_zalazki" łatwo
            // pomylić, a różnią się właśnie typem.
            text: "(" + model.geometria + ")"
            font.pointSize: Theme.tinyFont.pointSize
            color: Theme.secondaryTextColor
          }
        }

        onClicked: {
          const w = NarzedziaProjektu.warstwaPoNazwie(qgisProject, model.nazwa);
          if (w)
            dashBoard.activeLayer = w;
          else
            displayToast(qsTr("Nie znalazłem warstwy %1").arg(model.nazwa), "warning");
          wybierakWarstwMobilny.close();
        }
      }
    }
  }
'''


def main():
    if not os.path.exists(Q):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % Q)

    t = open(Q, encoding="utf-8").read()

    if MARKER in t:
        print("Latka juz jest — nic do zrobienia.")
        return

    n = t.count(KOTWICA)
    if n != 1:
        sys.exit("STOP: kotwica wystepuje %d razy, oczekiwano 1.\n"
                 "Czy poprzednie latki (wskaznik, olowek biurkowy) sa nalozone?" % n)

    print("Kotwica policzona, nakladam:")
    t = t.replace(KOTWICA, NOWE, 1)
    print("   olowek + klikalna nazwa warstwy")

    # wybierak przed ostatnia zamykajaca klamra pliku
    i = t.rstrip().rfind("}")
    if i < 0:
        sys.exit("STOP: nie znalazlem konca pliku")
    t = t[:i] + WYBIERAK + t[i:]
    print("   wybierak warstw (arkusz 48 px)")

    kopia = Q + ".przed_olowkiem_mob"
    if not os.path.exists(kopia):
        shutil.copy2(Q, kopia)
    open(Q, "w", encoding="utf-8").write(t)
    print("  zapisano %s" % os.path.basename(Q))

    print("""
Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head

Belki mobilnej NIE ZOBACZYSZ na desktopie — dziala tam QfDesktopChrome.
Sprawdzian dopiero na telefonie, po zlozeniu APK:
  1. tapnij OLOWEK obok nazwy warstwy -> tryb rysowania, olowek na zielono
  2. tapnij NAZWE warstwy             -> arkusz z warstwami roboczymi
  3. w trakcie rysowania tapnij nazwe -> ma odmowic z komunikatem
""")


if __name__ == "__main__":
    main()
