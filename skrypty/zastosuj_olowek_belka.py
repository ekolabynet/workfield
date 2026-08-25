#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — OLOWEK I WYBOR WARSTWY na gornej belce.

==========================================================================
PO CO
==========================================================================
Zeby dodac obiekt, trzeba dzis otworzyc lewa szuflade, znalezc warstwe
i tapnac olowek. Przy stu obiektach dziennie to sto otwarc szuflady.

Piotr, 25.08.2026: *„tapniecie w nazwe warstwy pozwala zmienic aktywna
warstwe, a tapniecie w olowek na belce zamyka i otwiera edycje"*.

Ten podzial jest lepszy niz przycisk z lista pod przytrzymaniem, bo
**kazdy element robi to, co obiecuje**: nazwa odpowiada na „ktora warstwa",
olowek na „czy rysuje". Nie trzeba pamietac o ukrytym gescie.

==========================================================================
NIC NOWEGO NIE PISZEMY — PRZENOSIMY SPRAWDZONE
==========================================================================
Taki przycisk **juz istnieje** w szufladzie (`QfMainDrawer.qml:1451-1491`),
z pelna logika: ikona `ic_create_white_24dp`, jasnozielone tlo przy
rysowaniu, ostrzezenie przy warstwie tylko do odczytu, przelaczanie
`browse`/`digitize`, komunikat i **ustawienie przyciagania**.

Ten ostatni blok przesadza, ze wspolna funkcja jest KONIECZNA, nie tylko
wygodna: gdyby belka ustawiala tryb bez niego, rysowanie z belki i ze
szuflady zachowywalyby sie ROZNIE — a takie rozjazdy sa najgorsze do
wysledzenia, bo obie drogi wygladaja identycznie.

Stad: `dashBoard.przelaczRysowanie(warstwa, nazwa)` z cala logika w jednym
miejscu; szuflada zaczyna ja wolac zamiast trzymac wlasna kopie.

==========================================================================
DWIE RZECZY, KTORE APLIKACJA JUZ ROZSTRZYGNELA — I SZANUJEMY JE
==========================================================================
1. **`allowActiveLayerChange: !digitizingToolbar.isDigitizing`**
   (QgisMobileapp.qml:4047) — zmiana warstwy w trakcie rysowania jest
   swiadomie zablokowana. Wybierak na belce musi to uszanowac, inaczej
   dalo by sie przelaczyc warstwe z niedokonczonym obrysem na ekranie.

2. **Warstwa tylko do odczytu** — olowek wyszarzony, ale po tapnieciu MOWI,
   czemu nie dziala. Zasada z 17.08: czynnosc widoczna w menu musi dzialac
   albo nie moze byc widoczna; wyszarzona bez wyjasnienia to trzeci stan.

Lista warstw jest FILTROWANA przez `NarzedziaProjektu.warstwyRobocze()` —
w projekcie ZZW jest 19 warstw, a roboczych szesc. Reszta to podklady,
slownik i tabele ZAL_. Lista z dziewietnastoma pozycjami bylaby gorsza
niz szuflada.

Uruchom w korzeniu repo:  python3 zastosuj_olowek_belka.py
Idempotentna. Kopie: <plik>.przed_olowkiem
"""
import os
import shutil
import sys

MOBIL = "src/app/qml/QgisMobileapp.qml"
DESKTOP = "src/app/qml/QfDesktopChrome.qml"
SZUFLADA = "src/app/qml/QfMainDrawer.qml"
MARKER = "przelaczRysowanie"

# ------------------------------------------------- wspolna funkcja w szufladzie

SZ_KOTWICA = "  // tap magnesa w wierszu warstwy: pierwszy raz przełącza projekt"

SZ_NOWE = '''  /**
   * Przełącza rysowanie na warstwie — JEDNO miejsce z tym zachowaniem.
   *
   * Wołane i ze szuflady, i z ołówka na górnej belce. Gdyby belka miała
   * własną kopię, oba przyciski rozjechałyby się przy pierwszej zmianie —
   * i wyglądałyby przy tym identycznie, więc nikt by nie zauważył.
   *
   * Zwraca true, gdy tryb się zmienił.
   */
  function przelaczRysowanie(warstwa, nazwa) {
    if (!warstwa) {
      displayToast(qsTr("Najpierw wybierz warstwę"), "warning");
      return false;
    }
    if (warstwa.readOnly) {
      displayToast(qsTr("Warstwa tylko do odczytu"), "warning");
      return false;
    }

    const juz = dashBoard.activeLayer === warstwa && stateMachine.state === "digitize";
    dashBoard.activeLayer = warstwa;
    stateMachine.state = juz ? "browse" : "digitize";
    displayToast(juz ? qsTr("Przeglądanie")
                     : qsTr("Rysowanie: %1").arg(nazwa || warstwa.name));

    if (!juz) {
      // WorkField: zasada domyślna dociągania — rysowana warstwa przyciąga
      // sama do siebie; tryb "wszystkie warstwy" sprowadzamy do "aktywnej",
      // a w trybie magnesów sami dopisujemy rysowaną warstwę.
      if (qgisProject.snappingConfig.mode === Qgis.SnappingMode.AllLayers) {
        let cfgO = qgisProject.snappingConfig;
        cfgO.mode = Qgis.SnappingMode.ActiveLayer;
        qgisProject.snappingConfig = cfgO;
      } else if (qgisProject.snappingConfig.mode === Qgis.SnappingMode.AdvancedConfiguration) {
        dashBoard.ustawMagnesWarstwy(warstwa, true);
      }
      dashBoard.close();
    }
    return true;
  }

  // tap magnesa w wierszu warstwy: pierwszy raz przełącza projekt'''

# ----------------------------------------- szuflada wola wspolna funkcje

SZ_PRZYCISK_STARY = '''            onClicked: {
              if (!isWritable) {
                displayToast(qsTr("Warstwa tylko do odczytu"), "warning");
                return;
              }
              const juz = isCurrent && stateMachine.state === "digitize";
              dashBoard.activeLayer = model.VectorLayerPointer;
              stateMachine.state = juz ? "browse" : "digitize";
              displayToast(juz ? qsTr("Przeglądanie") : qsTr("Rysowanie: %1").arg(model.Name));
              if (!juz) {
                // WorkField: zasada domyślna dociągania — rysowana warstwa
                // przyciąga sama do siebie; tryb "wszystkie warstwy"
                // sprowadzamy do "aktywnej", a w trybie magnesów sami
                // dopisujemy rysowaną warstwę
                if (qgisProject.snappingConfig.mode === Qgis.SnappingMode.AllLayers) {
                  let cfgO = qgisProject.snappingConfig;
                  cfgO.mode = Qgis.SnappingMode.ActiveLayer;
                  qgisProject.snappingConfig = cfgO;
                } else if (qgisProject.snappingConfig.mode === Qgis.SnappingMode.AdvancedConfiguration) {
                  dashBoard.ustawMagnesWarstwy(model.VectorLayerPointer, true);
                }
                dashBoard.close();
              }
            }'''

SZ_PRZYCISK_NOWY = '''            // Cała logika mieszka w dashBoard.przelaczRysowanie() — ten sam
            // kod obsługuje ołówek na górnej belce.
            onClicked: dashBoard.przelaczRysowanie(model.VectorLayerPointer, model.Name)'''

# ------------------------------------------------------- belka biurkowa

D_KOTWICA = '''    QfZnacznikEdycji {
      anchors.verticalCenter: parent.verticalCenter
      warstwa: dashBoard.activeLayer
    }'''

D_NOWE = '''    // Ołówek: przełącza rysowanie na aktywnej warstwie. Ta sama funkcja,
    // którą woła szuflada — patrz dashBoard.przelaczRysowanie().
    QfToolButton {
      anchors.verticalCenter: parent.verticalCenter
      width: 26
      height: 26
      padding: 0
      round: true

      readonly property bool rysujemy: stateMachine.state === "digitize"
      readonly property bool mozna: dashBoard.activeLayer && !dashBoard.activeLayer.readOnly

      iconSource: Theme.getThemeVectorIcon("ic_create_white_24dp")
      bgcolor: rysujemy ? "#00E676" : "transparent"
      iconColor: rysujemy ? "#062E12" : "white"
      opacity: !mozna ? 0.3 : rysujemy ? 1.0 : 0.8

      // Wyszarzony, ale MÓWI czemu nie działa. Wyszarzony bez wyjaśnienia
      // to trzeci stan: widoczny i prowadzący donikąd (zasada z 17.08).
      onClicked: dashBoard.przelaczRysowanie(dashBoard.activeLayer)
    }

    QfZnacznikEdycji {
      anchors.verticalCenter: parent.verticalCenter
      warstwa: dashBoard.activeLayer
    }'''

# --- nazwa warstwy klikalna: wybierak warstw roboczych

D_TYTUL_STARY = '''    Text {
      id: tytulBelki
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, chrom.width - 760)
      visible: width > 60
      horizontalAlignment: Text.AlignHCenter
      text: {
        const czesci = [];
        if (mainWindow.projectTitle !== "")
          czesci.push(mainWindow.projectTitle);
        if (dashBoard.activeLayer)
          czesci.push(dashBoard.activeLayer.name);
        else
          czesci.push(qsTr("brak aktywnej warstwy"));
        return czesci.join("  ·  ");
      }
      font: Theme.tipFont
      color: "white"
      opacity: 0.85
      elide: Text.ElideMiddle
    }'''

D_TYTUL_NOWY = '''    Text {
      id: tytulBelki
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, chrom.width - 800)
      visible: width > 60
      horizontalAlignment: Text.AlignHCenter
      text: {
        const czesci = [];
        if (mainWindow.projectTitle !== "")
          czesci.push(mainWindow.projectTitle);
        if (dashBoard.activeLayer)
          czesci.push(dashBoard.activeLayer.name);
        else
          czesci.push(qsTr("brak aktywnej warstwy"));
        return czesci.join("  ·  ");
      }
      font: Theme.tipFont
      color: "white"
      opacity: 0.85
      elide: Text.ElideMiddle

      // Tapnięcie w nazwę = wybór aktywnej warstwy, bez otwierania szuflady.
      MouseArea {
        anchors.fill: parent
        onClicked: {
          // Aplikacja świadomie blokuje zmianę warstwy w trakcie rysowania
          // (QgisMobileapp: allowActiveLayerChange). Szanujemy to — inaczej
          // dałoby się przełączyć warstwę z niedokończonym obrysem na ekranie.
          if (!dashBoard.allowActiveLayerChange) {
            displayToast(qsTr("Najpierw zakończ rysowany obiekt"), "warning");
            return;
          }
          wybierakWarstw.otworz();
        }
      }
    }'''

# --- sam wybierak, dopisany na koncu pliku przed ostatnia klamra

D_WYBIERAK = '''
  // Wybór aktywnej warstwy z górnej belki — bez otwierania szuflady.
  //
  // Lista jest FILTROWANA: w projekcie ZZW jest 19 warstw, a roboczych sześć.
  // Reszta to podkłady, słownik i tabele ZAL_. Lista z dziewiętnastoma
  // pozycjami byłaby gorsza niż szuflada, po którą i tak nie chcemy sięgać.
  Menu {
    id: wybierakWarstw

    function otworz() {
      lista.clear();
      const warstwy = NarzedziaProjektu.warstwyRobocze(qgisProject);
      for (let i = 0; i < warstwy.length; i++)
        lista.append(warstwy[i]);
      if (lista.count === 0) {
        displayToast(qsTr("Projekt nie ma warstw roboczych"), "warning");
        return;
      }
      popup();
    }

    ListModel {
      id: lista
    }

    Repeater {
      model: lista
      MenuItem {
        // warstwyRobocze() zwraca mapy z kluczami: nazwa, geometria, punktowa.
        // Geometria w nawiasie, bo w projekcie ZZW sa warstwy o podobnych
        // nazwach i roznych typach — „platy" i „platy_zalazki".
        text: model.nazwa + "   (" + model.geometria + ")"
        onTriggered: {
          const w = NarzedziaProjektu.warstwaPoNazwie(qgisProject, model.nazwa);
          if (w)
            dashBoard.activeLayer = w;
          else
            displayToast(qsTr("Nie znalazłem warstwy %1").arg(model.nazwa), "warning");
        }
      }
    }
  }
'''


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def raz(t, kotwica, p, opis):
    n = t.count(kotwica)
    if n != 1:
        sys.exit("STOP: kotwica '%s' w %s wystepuje %d razy, oczekiwano 1"
                 % (opis, os.path.basename(p), n))


def zapisz(p, t, opis):
    kopia = p + ".przed_olowkiem"
    if not os.path.exists(kopia):
        shutil.copy2(p, kopia)
    open(p, "w", encoding="utf-8").write(t)
    print("   %-30s %s" % (opis, os.path.basename(p)))


def main():
    sz = czytaj(SZUFLADA)
    d = czytaj(DESKTOP)

    if MARKER in sz and MARKER in d:
        print("Latka juz jest — nic do zrobienia.")
        return
    if MARKER in sz or MARKER in d:
        sys.exit("STOP: latka polowiczna. Przywroc kopie .przed_olowkiem.")

    raz(sz, SZ_KOTWICA, SZUFLADA, "miejsce na funkcje")
    raz(sz, SZ_PRZYCISK_STARY, SZUFLADA, "przycisk w szufladzie")
    raz(d, D_KOTWICA, DESKTOP, "znacznik na belce")
    raz(d, D_TYTUL_STARY, DESKTOP, "tytul belki")

    print("Kotwice policzone (4/4), nakladam:")

    sz = sz.replace(SZ_KOTWICA, SZ_NOWE, 1)
    sz = sz.replace(SZ_PRZYCISK_STARY, SZ_PRZYCISK_NOWY, 1)
    d = d.replace(D_TYTUL_STARY, D_TYTUL_NOWY, 1)
    d = d.replace(D_KOTWICA, D_NOWE, 1)

    # wybierak przed ostatnia zamykajaca klamra pliku
    i = d.rstrip().rfind("}")
    if i < 0:
        sys.exit("STOP: nie znalazlem konca pliku %s" % DESKTOP)
    d = d[:i] + D_WYBIERAK + d[i:]

    zapisz(SZUFLADA, sz, "wspolna funkcja + przycisk")
    zapisz(DESKTOP, d, "olowek, wybierak, tytul")

    print("""
Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head

Sprawdzian na desktopie:
  1. tapnij OLOWEK obok tytulu   -> tryb rysowania, olowek na zielono
  2. tapnij ponownie             -> przegladanie
  3. tapnij NAZWE warstwy        -> lista warstw roboczych
  4. w trakcie rysowania obiektu tapnij nazwe -> ma odmowic z komunikatem
  5. sprawdz, czy przycisk W SZUFLADZIE nadal dziala tak samo
""")


if __name__ == "__main__":
    main()
