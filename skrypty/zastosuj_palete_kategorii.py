#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 39 — kolory kategorii przez WSPOLNY picker (256 odcieni Materialize)
oraz naprawa martwego przycisku widocznosci kategorii.

==========================================================================
KARTA FAKTÓW — sprawdzone w src/gui/qml/LayerTreeItemProperties.qml
==========================================================================

1. KOLORY KATEGORII MAJA WLASNA, WKLEJONA W KOD LISTE 13 KOLOROW (l. 1124):

     readonly property var swatches: ["#e53935", "#d81b60", "#8e24aa",
       "#3949ab", "#1e88e5", "#00897b", "#43a047", "#c0ca33", "#fdd835",
       "#fb8c00", "#6d4c41", "#212121", "#ffffff"]

   Latka 33 wymienila palete w QfColorPicker na pelny Materialize CSS
   (256 odcieni) — ale kategorie NIGDY tego pickera nie wolaly. Stad
   wrazenie Piotra (21.08), ze paleta "nie dziala przy kategoriach":
   dziala wszedzie poza tym jednym miejscem.

   Ten plik ma juz pomocnika `openColorPicker( tytul, kolor, callback )`
   (l. 62-70), uzywanego przez wypelnienie, kontur i kolor etykiet.
   Kategorie po prostu z niego nie korzystaly.

2. PRZYCISK WIDOCZNOSCI KATEGORII JEST MARTWY (l. 1105-1117):

     iconSource: Theme.getThemeVectorIcon(modelData.visible
                   ? "WŁAŚCIWA_NAZWA" : "WŁAŚCIWA_NAZWA_2")
     onClicked: { const vl = layerTree.data(index, ...VectorLayerPointer); }

   Nazwy ikon to NIEWYPELNIONE ZASLEPKI, a obsluga klikniecia pobiera
   warstwe i ja wyrzuca. Przycisk jest widoczny i nie robi nic — trzeci
   stan z zasady z 17.08 ("czynnosc widoczna w menu musi dzialac albo
   nie moze byc widoczna").

   `LayerUtils.setCategoryVisible( layer, index, bool )` istnieje i jest
   Q_INVOKABLE — brakowalo tylko wywolania. Ikony: sprawdzone w drzewie
   motywu, uzywamy tych samych co reszta panelu.

CO ROBI TA LATKA

  - kwadracik koloru kategorii otwiera wspolny picker (256 odcieni,
    siatka przewijana) zamiast rozwijac rzad trzynastu kwadracikow,
  - wywala martwy blok `Flow` z wlasna paleta,
  - przycisk oka faktycznie przelacza widocznosc kategorii.

Zero nowego C++. Uruchom w korzeniu repo:
    python3 zastosuj_palete_kategorii.py
Idempotentna. Kopia: LayerTreeItemProperties.qml.przed_paleta_kategorii
"""
import os
import shutil
import sys

Q = "src/gui/qml/LayerTreeItemProperties.qml"
MARKER = "openColorPicker(qsTr(\"Kategoria\")"

# --------------------------------------------------- kwadracik -> wspolny picker

STARE_KWADRACIK = """                  MouseArea {
                    anchors.fill: parent
                    onClicked: categoryList.editingIndex = categoryList.editingIndex === index ? -1 : index
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.label"""

NOWE_KWADRACIK = """                  MouseArea {
                    anchors.fill: parent
                    // WorkField 21.08.2026: wspólny picker (256 odcieni
                    // Materialize) zamiast trzynastu kolorów wklejonych
                    // w ten plik. Ten sam pomocnik, co przy wypełnieniu
                    // i konturze — kategorie jako jedyne go nie wołały.
                    onClicked: {
                      if (!styleTargetLayer)
                        return;
                      const nrKategorii = index;
                      openColorPicker(qsTr("Kategoria"), modelData.color, function (chosen) {
                        LayerUtils.setCategoryColor(styleTargetLayer, nrKategorii, chosen);
                        categoryEntries = LayerUtils.rendererCategories(styleTargetLayer);
                        if (styleTargetMapLayer)
                          projectInfo.saveLayerStyle(styleTargetMapLayer);
                      });
                    }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.label"""

# ------------------------------------------------ martwy przycisk widocznosci

STARE_OKO = """                QfToolButton {
                  Layout.rightMargin: 4
                  width: 32
                  height: 32
                  padding: 0
                  bgcolor: "transparent"
                  iconSource: Theme.getThemeVectorIcon(modelData.visible ? "WŁAŚCIWA_NAZWA" : "WŁAŚCIWA_NAZWA_2")
                  iconColor: Theme.mainTextColor

                  onClicked: {
                    const vl = layerTree.data(index, FlatLayerTreeModel.VectorLayerPointer);
                  }
                }"""

NOWE_OKO = """                QfToolButton {
                  Layout.rightMargin: 4
                  width: 32
                  height: 32
                  padding: 0
                  bgcolor: "transparent"
                  // WorkField 21.08.2026: nazwy ikon były niewypełnionymi
                  // zaślepkami, a obsługa kliknięcia pobierała warstwę
                  // i ją wyrzucała — przycisk widoczny, prowadzący donikąd.
                  iconSource: Theme.getThemeVectorIcon(modelData.visible ? "ic_eye_black_24dp" : "ic_eye_off_black_24dp")
                  iconColor: modelData.visible ? Theme.mainTextColor : Theme.mainTextDisabledColor

                  onClicked: {
                    if (!styleTargetLayer)
                      return;
                    LayerUtils.setCategoryVisible(styleTargetLayer, index, !modelData.visible);
                    categoryEntries = LayerUtils.rendererCategories(styleTargetLayer);
                    if (styleTargetMapLayer)
                      projectInfo.saveLayerStyle(styleTargetMapLayer);
                  }
                }"""


def read(path):
    if not os.path.exists(path):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % path)
    return open(path, encoding="utf-8").read()


def once(t, anchor, path):
    n = t.count(anchor)
    if n != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1:\n  %s"
                 % (path, n, anchor.strip().splitlines()[0]))


def usun_blok(t, znacznik_wewnatrz, poczatek="Flow {"):
    """Wycina blok zawierajacy podany znacznik, liczac klamry.

    UWAGA — tu byl blad przy pisaniu tej latki: pierwsza wersja szukala
    tablicy kolorow i trafiala w PIERWSZE jej wystapienie, czyli w komponent
    ColorGrid (l. 813), a nie w blok kategorii (l. 1127). Obie maja
    identyczna tablice. Dlatego znacznikiem musi byc cos UNIKALNEGO dla
    szukanego bloku, nie jego zawartosc wspoldzielona z innym.

    Parser klamer, nie regex — w srodku sa napisy z nawiasami i komentarze.
    """
    i = t.find(znacznik_wewnatrz)
    if i < 0:
        return t, False

    p = t.rfind(poczatek, 0, i)
    if p < 0:
        return t, False
    p = t.rfind("\n", 0, p) + 1

    # w przod, liczac klamry
    d = 0
    j = t.find("{", p)
    k = j
    while k < len(t):
        if t[k] == "{":
            d += 1
        elif t[k] == "}":
            d -= 1
            if d == 0:
                break
        k += 1
    if d != 0:
        sys.exit("STOP: blok Flow sie nie domyka")
    # zjedz koncowy znak nowej linii
    k = t.find("\n", k)
    return t[:p] + t[k + 1:], True


def main():
    t = read(Q)

    if MARKER in t:
        print("Latka 39 juz jest — nic do zrobienia.")
        return

    once(t, STARE_KWADRACIK, Q)
    if t.count(STARE_OKO) != 1:
        print("UWAGA: martwy przycisk widocznosci wyglada inaczej niz oczekiwano")
        print("       — poprawiam tylko palete kolorow.")
        oko = False
    else:
        oko = True

    print("Kotwice policzone, nakladam:")

    t = t.replace(STARE_KWADRACIK, NOWE_KWADRACIK, 1)
    if oko:
        t = t.replace(STARE_OKO, NOWE_OKO, 1)
        print("  przycisk widocznosci kategorii: podpiety do setCategoryVisible")

    # 1. blok kategorii — rozpoznawany po warunku widocznosci, ktory jest
    #    dla niego unikalny (sama tablica kolorow wystepuje takze w ColorGrid)
    t, wyciete = usun_blok(t, "visible: categoryList.editingIndex === index")
    if wyciete:
        print("  wycieta wlasna paleta 13 kolorow przy kategoriach")
    else:
        print("  UWAGA: nie znalazlem bloku palety kategorii — sprawdz recznie")

    # 2. komponent ColorGrid: zadeklarowany i NIGDZIE nieuzywany (grep: jedno
    #    wystapienie, sama deklaracja). Martwy kod z ta sama paleta 13 kolorow.
    t, martwy = usun_blok(t, "signal picked(color chosen)", "component ColorGrid")
    if martwy:
        print("  wyciety martwy komponent ColorGrid (bez wywolan)")

    kopia = Q + ".przed_paleta_kategorii"
    if not os.path.exists(kopia):
        shutil.copy2(Q, kopia)
    open(Q, "w", encoding="utf-8").write(t)
    print("  zapisano %s (kopia: %s)" % (Q, os.path.basename(kopia)))

    print("\nBuild:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'rcc|error' | head")
    print("W logu MUSI byc 'Running rcc for resource gui_qml'.")
    print("\nSprawdz po buildzie: panel warstwy -> Kategorie -> tapnij kwadracik.")
    print("Ma sie otworzyc pelna paleta, ta sama co przy Wypelnieniu.")


if __name__ == "__main__":
    main()
