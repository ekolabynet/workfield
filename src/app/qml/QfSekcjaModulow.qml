import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core
import Theme

/**
 * \ingroup qml
 *
 * WorkField 19.09.2026 — ZAKŁADKA „MODUŁY" W SZUFLADZIE.
 * 20.09.2026: przeniesiona do PRAWEJ szuflady (narzędzia) — moduł to
 * zintegrowane narzędzie; jego zawartość (warstwy w grupie modułu) jest
 * po lewej, w Warstwach.
 *
 * Moduł dziedzinowy to sposób pracy (warstwy, styl, eksporty), nie cecha
 * projektu — decyzje w claude/MODULY_dziedzinowe.md. Ta zakładka:
 *
 *  - „W tym projekcie": moduły, których silnik rozpoznał projekt
 *    (czasownik z "rozpoznanie" w opisie modułu). Karta pokazuje, co
 *    rozpoznał, i ma przyciski z "akcje". Nic nie jest wpisane na sztywno:
 *    karta powstaje z opisu modułu (modul.json), który podaje silnik.
 *  - „Zainstalowane": wszystkie moduły, które aplikacja zna. Dziś tylko
 *    wbudowane; paczki z katalogu dojdą w tę samą listę.
 *
 *  - „Nowy projekt z modułu" (gdy opis ma "przepis"): pusty projekt w
 *    wybranym układzie, potem — PO wczytaniu, bo createEmptyLayer wpina
 *    warstwy do otwartego projektu — warstwy z polami, aliasami, listami
 *    i wartościami domyślnymi, ustawienia modułu, znacznik wfg_moduly/<id>
 *    i czynności "po_zalozeniu" (np. styl). Tak jak kreator „Projekt z DXF".
 *
 * Akcja z "potwierdz" pyta przed wykonaniem (tekst z {kluczami} z rozpoznania);
 * akcja z "tylko_z_modulu" jest widoczna tylko w projekcie założonym z modułu
 * (rozpoznanie zwraca zModulu) — "Wyczyść dane" nie może się pokazać
 * w projekcie z prawdziwą inwentaryzacją.
 *
 * Czynność niedostępna w tej wersji aplikacji (brak czasownika z
 * "wymaga_silnika") nie pokazuje martwego przycisku — moduł mówi wtedy,
 * że potrzebuje nowszej aplikacji (zasada: widoczne musi działać).
 */
Item {
  id: sekcja

  //! Szuflada, w której siedzi zakładka: na telefonie trzeba ją zamknąć
  //! PRZED komunikatem, bo komunikat ginie pod animacją zamykania.
  property var szuflada: null

  //! [{opis, brak, rozpoznanie, wProjekcie}]
  property var moduly: []
  readonly property var wProjekcie: moduly.filter(function (m) {
    return m.wProjekcie;
  })

  //! Moduł, którego przepis czeka na wczytanie nowego projektu:
  //! {opis, katalog, uklad}. Czyszczony od razu przy użyciu.
  property var oczekujacy: null

  onVisibleChanged: {
    if (visible)
      odswiez();
  }

  Connections {
    target: iface
    ignoreUnknownSignals: true
    function onLoadProjectEnded(path, name) {
      if (sekcja.oczekujacy) {
        const z = sekcja.oczekujacy;
        sekcja.oczekujacy = null;
        Qt.callLater(function () {
          sekcja.zlozZPrzepisu(z.opis, z.katalog, z.uklad);
        });
        return;
      }
      sekcja.odswiez();
    }
  }

  //! Silniki wkompilowane w aplikację: nazwa z opisu modułu -> singleton.
  //! Nowy moduł z własnym silnikiem dopisuje się TUTAJ (jedna linia).
  function silniki() {
    const s = {};
    if (typeof InwentaryzacjaDrzew !== "undefined")
      s["InwentaryzacjaDrzew"] = InwentaryzacjaDrzew;
    return s;
  }

  function czynnosc(czasownik) {
    const kropka = czasownik.indexOf(".");
    const s = silniki()[czasownik.substring(0, kropka)];
    const metoda = czasownik.substring(kropka + 1);
    return s && typeof s[metoda] === "function" ? function (projekt) {
      return s[metoda](projekt);
    } : null;
  }

  function brakujace(opis) {
    const brak = [];
    const wymaga = opis.wymaga_silnika || [];
    for (let i = 0; i < wymaga.length; i++) {
      if (!czynnosc(wymaga[i]))
        brak.push(wymaga[i]);
    }
    return brak;
  }

  function odswiez() {
    const lista = [];
    const s = silniki();
    for (const nazwa in s) {
      const opis = s[nazwa].opis();
      const brak = brakujace(opis);
      let rozpoznanie = {};
      const jestProjekt = typeof qgisProject !== "undefined" && qgisProject && qgisProject.homePath !== "";
      if (!jestProjekt)
        rozpoznanie = {
          "blad": qsTr("brak otwartego projektu")
        };
      else if (brak.length === 0 && opis.rozpoznanie)
        rozpoznanie = czynnosc(opis.rozpoznanie)(qgisProject);
      lista.push({
                   "opis": opis,
                   "brak": brak,
                   "rozpoznanie": rozpoznanie,
                   "wProjekcie": jestProjekt && brak.length === 0 && !rozpoznanie.blad
                 });
    }
    moduly = lista;
  }

  //! "{klucz}" z wyniku czynności; tablica wstawia się jako liczba elementów.
  function wypelnij(szablon, wynik) {
    return String(szablon).replace(/\{([A-Za-z_]+)\}/g, function (calosc, klucz) {
      const w = wynik[klucz];
      if (w === undefined)
        return calosc;
      return Array.isArray(w) ? String(w.length) : String(w);
    });
  }

  //! Akcja widoczna na karcie? (tylko_z_modulu -> projekt z modułu)
  function widoczna(akcja, rozpoznanie) {
    return !akcja.tylko_z_modulu || !!rozpoznanie.zModulu;
  }

  //! Przycisk na karcie: akcja z "potwierdz" najpierw pyta.
  function nacisnij(akcja, rozpoznanie) {
    if (akcja.potwierdz) {
      oknoPotwierdzenia.akcja = akcja;
      oknoPotwierdzenia.tekst = wypelnij(akcja.potwierdz, rozpoznanie);
      oknoPotwierdzenia.open();
      return;
    }
    wykonaj(akcja);
  }

  function wykonaj(akcja) {
    const uruchom = function () {
      const f = czynnosc(akcja.czasownik);
      if (!f) {
        displayToast(qsTr("Ta wersja aplikacji nie ma czynności %1").arg(akcja.czasownik), "warning");
        return;
      }
      const w = f(qgisProject);
      console.log("WFG modul " + akcja.czasownik + ": " + JSON.stringify(w));
      if (w.blad) {
        displayToast(w.blad, "warning");
        return;
      }
      if (akcja.zapisz_projekt && typeof NarzedziaProjektu !== "undefined")
        NarzedziaProjektu.zapiszProjekt(qgisProject);
      const tekst = wypelnij(akcja.komunikat || akcja.etykieta, w);
      const pliki = akcja.wyslij ? w[akcja.wyslij] : null;
      if (pliki && pliki.length > 0) {
        displayToast(tekst, "info", qsTr("Wyślij"), function () {
          platformUtilities.sendCompressedFilesTo(pliki);
        });
      } else {
        displayToast(tekst);
      }
      sekcja.odswiez();
    };
    // Na telefonie szuflada zasłania mapę i komunikat: najpierw ją zamykamy,
    // czynność rusza po sygnale closed (tak jak dotąd w szufladzie).
    if (szuflada && szuflada.modal && szuflada.opened) {
      const poZamknieciu = function () {
        szuflada.closed.disconnect(poZamknieciu);
        uruchom();
      };
      szuflada.closed.connect(poZamknieciu);
      szuflada.close();
    } else {
      uruchom();
    }
  }

  //! Pusty projekt w "Imported Projects" (tam wolno pisać na Androidzie),
  //! warstwy z przepisu dochodzą po wczytaniu (onLoadProjectEnded).
  function nowyProjekt(opis, nazwa, uklad) {
    if (typeof NarzedziaProjektu === "undefined")
      return qsTr("Brak narzędzi projektu");
    nazwa = nazwa.trim();
    if (nazwa === "")
      return qsTr("Podaj nazwę projektu.");
    const katalogProjektow = iface.dataRoot() + "Imported Projects";
    const cel = katalogProjektow + "/" + nazwa;
    if (FileUtils.fileExists(cel))
      return qsTr("Projekt o tej nazwie już istnieje.");
    const plik = NarzedziaProjektu.nowyProjekt(katalogProjektow, nazwa, uklad);
    if (plik === "")
      return qsTr("Nie udało się utworzyć projektu.");
    oczekujacy = {
      "opis": opis,
      "katalog": cel,
      "uklad": uklad
    };
    displayToast(qsTr("Tworzę projekt %1…").arg(nazwa));
    iface.loadFile(plik, nazwa);
    return "";
  }

  function zlozZPrzepisu(opis, katalog, uklad) {
    const przepis = opis.przepis || {};
    const baza = katalog + "/dane.gpkg";
    const warstwy = przepis.warstwy || [];
    const zalozone = [];
    for (const w of warstwy) {
      let warstwa = null;
      try {
        warstwa = LayerUtils.createEmptyLayer(baza, w.nazwa, w.typ, uklad, w.pola);
      } catch (e) {
        warstwa = null;
      }
      if (!warstwa) {
        console.log("WFG modul przepis: nie powstala warstwa " + w.nazwa);
        continue;
      }
      for (const pole of w.pola) {
        if (pole.alias)
          NarzedziaProjektu.alias(warstwa, pole.name, pole.alias);
        if (pole.widget)
          NarzedziaProjektu.widget(warstwa, pole.name, pole.widget, pole.opcje || {});
        if (pole.domyslna)
          NarzedziaProjektu.wartoscDomyslna(warstwa, pole.name, pole.domyslna, !!pole.przy_zmianie);
      }
      if (w.zalacznik)
        LayerUtils.setAttachmentField(warstwa, w.zalacznik);
      if (ProjectUtils.addMapLayer(qgisProject, warstwa)) {
        zalozone.push(w.nazwa);
        // Zawartość modułu po lewej: warstwy w grupie o nazwie modułu,
        // zgaszalne jednym tapnięciem (jak "Rysunek CAD").
        if (przepis.grupa)
          NarzedziaProjektu.doGrupy(qgisProject, warstwa, przepis.grupa, false, true);
      }
    }
    const ustawienia = przepis.ustawienia || {};
    for (const klucz in ustawienia) {
      const ukosnik = klucz.indexOf("/");
      NarzedziaProjektu.wlasciwosc(qgisProject, klucz.substring(0, ukosnik), klucz.substring(ukosnik + 1), ustawienia[klucz]);
    }
    // Znacznik: projekt wie, z jakiego modułu i wersji powstał.
    NarzedziaProjektu.wlasciwosc(qgisProject, "wfg_moduly", opis.id, opis.wersja || "");
    for (const czasownik of (przepis.po_zalozeniu || [])) {
      const f = czynnosc(czasownik);
      const w = f ? f(qgisProject) : { "blad": czasownik };
      console.log("WFG modul przepis " + czasownik + ": " + JSON.stringify(w));
    }
    NarzedziaProjektu.zapiszProjekt(qgisProject);
    console.log("WFG modul przepis " + opis.id + ": warstwy " + JSON.stringify(zalozone));
    // Nowy projekt ma same PUSTE warstwy - mapa nie miała czego narysować
    // i zostawał na niej obraz poprzedniego projektu (20.09.2026: wyglądało
    // to jak "dane skopiowane do nowego projektu"). Wymuszamy przerysowanie.
    if (typeof mapCanvasMap !== "undefined" && mapCanvasMap.refresh)
      mapCanvasMap.refresh(true);
    odswiez();
    if (zalozone.length === warstwy.length)
      displayToast(qsTr("Projekt gotowy: %1. Podkład dodasz w zakładce Warstwy.").arg(zalozone.join(", ")));
    else
      displayToast(qsTr("Projekt złożony częściowo: %1 z %2 warstw").arg(zalozone.length).arg(warstwy.length), "warning");
  }

  function otworzNowy(opis) {
    oknoNowego.opis = opis;
    poleNazwy.text = "";
    komunikatNowego.text = "";
    wyborUkladu.currentIndex = 0;
    const pokaz = function () {
      oknoNowego.open();
    };
    if (szuflada && szuflada.modal && szuflada.opened) {
      const poZamknieciu = function () {
        szuflada.closed.disconnect(poZamknieciu);
        pokaz();
      };
      szuflada.closed.connect(poZamknieciu);
      szuflada.close();
    } else {
      pokaz();
    }
  }

  Popup {
    id: oknoPotwierdzenia

    property var akcja: ({})
    property string tekst: ""

    parent: typeof mainWindow !== "undefined" ? mainWindow.contentItem : sekcja
    x: (parent.width - width) / 2
    y: Math.max(12, (parent.height - height) / 3)
    width: Math.min(parent.width - 24, 440)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    background: Rectangle {
      color: Theme.mainBackgroundColor
      radius: 8
      border.width: 1
      border.color: Theme.errorColor
    }

    contentItem: ColumnLayout {
      spacing: 10

      Text {
        Layout.fillWidth: true
        text: oknoPotwierdzenia.akcja.etykieta || ""
        font: Theme.strongTipFont
        color: Theme.mainTextColor
      }
      Text {
        Layout.fillWidth: true
        text: oknoPotwierdzenia.tekst
        font: Theme.tipFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Item {
          Layout.fillWidth: true
        }
        Button {
          text: qsTr("Anuluj")
          onClicked: oknoPotwierdzenia.close()
        }
        Button {
          text: oknoPotwierdzenia.akcja.etykieta || qsTr("Wykonaj")
          onClicked: {
            const a = oknoPotwierdzenia.akcja;
            oknoPotwierdzenia.close();
            sekcja.wykonaj(a);
          }
        }
      }
    }
  }

  Popup {
    id: oknoNowego

    property var opis: ({})

    parent: typeof mainWindow !== "undefined" ? mainWindow.contentItem : sekcja
    x: (parent.width - width) / 2
    y: Math.max(12, (parent.height - height) / 3)
    width: Math.min(parent.width - 24, 480)
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    background: Rectangle {
      color: Theme.mainBackgroundColor
      radius: 8
      border.width: 1
      border.color: Theme.controlBorderColor
    }

    contentItem: ColumnLayout {
      spacing: 10

      Text {
        Layout.fillWidth: true
        text: qsTr("Nowy projekt: %1").arg(oknoNowego.opis.nazwa || "")
        font: Theme.strongTipFont
        color: Theme.mainTextColor
        wrapMode: Text.WordWrap
      }
      Text {
        Layout.fillWidth: true
        text: qsTr("Warstwy: %1").arg(((oknoNowego.opis.przepis || {}).warstwy || []).map(function (w) {
          return w.nazwa;
        }).join(", "))
        font: Theme.tinyFont
        color: Theme.secondaryTextColor
        wrapMode: Text.WordWrap
      }
      TextField {
        id: poleNazwy
        Layout.fillWidth: true
        placeholderText: qsTr("Nazwa projektu")
        font: Theme.tipFont
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
          text: qsTr("Układ")
          font: Theme.tipFont
          color: Theme.mainTextColor
        }
        ComboBox {
          id: wyborUkladu
          Layout.fillWidth: true
          // jak w kreatorze "Projekt z DXF": PL-2000 strefa 7 pierwsza
          model: ["EPSG:2178", "EPSG:2179", "EPSG:2177", "EPSG:2176", "EPSG:2180"]
        }
      }
      Text {
        id: komunikatNowego
        Layout.fillWidth: true
        visible: text !== ""
        color: Theme.errorColor
        font: Theme.tipFont
        wrapMode: Text.WordWrap
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Item {
          Layout.fillWidth: true
        }
        Button {
          text: qsTr("Anuluj")
          onClicked: oknoNowego.close()
        }
        Button {
          text: qsTr("Utwórz")
          enabled: poleNazwy.text.trim() !== ""
          onClicked: {
            const blad = sekcja.nowyProjekt(oknoNowego.opis, poleNazwy.text, wyborUkladu.currentText);
            if (blad !== "") {
              komunikatNowego.text = blad;
              return;
            }
            oknoNowego.close();
          }
        }
      }
    }
  }

  Flickable {
    id: przewijanie
    anchors.fill: parent
    contentWidth: width
    contentHeight: kolumna.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    ColumnLayout {
      id: kolumna
      x: 8
      y: 8
      width: przewijanie.width - 16
      spacing: 6

      RowLayout {
        Layout.fillWidth: true

        Text {
          Layout.fillWidth: true
          text: qsTr("Moduły")
          font: Theme.strongTipFont
          color: Theme.mainTextColor
        }
        ToolButton {
          text: qsTr("Odśwież")
          font: Theme.tinyFont
          onClicked: sekcja.odswiez()
        }
      }

      Text {
        Layout.fillWidth: true
        text: qsTr("Moduł to sposób pracy: warstwy, styl, eksporty dla jednej dziedziny.")
        font: Theme.tinyFont
        color: Theme.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      // ── W tym projekcie ─────────────────────────────────────────
      Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: qsTr("W tym projekcie")
        font: Theme.tipFont
        color: Theme.mainTextColor
      }

      Text {
        Layout.fillWidth: true
        visible: sekcja.wProjekcie.length === 0
        text: qsTr("Żaden moduł nie rozpoznał tego projektu.")
        font: Theme.tinyFont
        color: Theme.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: sekcja.wProjekcie

        delegate: Rectangle {
          id: karta

          required property var modelData
          readonly property var r: modelData.rozpoznanie

          Layout.fillWidth: true
          implicitHeight: wnetrze.implicitHeight + 16
          radius: 6
          color: Theme.controlBackgroundAlternateColor
          border.color: Theme.mainColor
          border.width: 1

          ColumnLayout {
            id: wnetrze
            x: 8
            y: 8
            width: karta.width - 16
            spacing: 4

            RowLayout {
              Layout.fillWidth: true

              Text {
                Layout.fillWidth: true
                text: karta.modelData.opis.nazwa
                font: Theme.strongTipFont
                color: Theme.mainTextColor
                elide: Text.ElideRight
              }
              Text {
                text: karta.r.obiekty !== undefined ? qsTr("%1 obiektów").arg(karta.r.obiekty) : ""
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
              }
            }

            Text {
              Layout.fillWidth: true
              text: karta.r.warstwa || ""
              visible: text !== ""
              font: Theme.tinyFont
              color: Theme.mainTextColor
              wrapMode: Text.WrapAnywhere
              maximumLineCount: 2
              elide: Text.ElideRight
            }

            Repeater {
              // pola rozpoznane po roli, w kolejnosci z opisu modulu ("role")
              model: (karta.modelData.opis.role || []).filter(function (rola) {
                return !!karta.r[rola.klucz];
              })

              delegate: Text {
                required property var modelData
                Layout.fillWidth: true
                text: "· " + modelData.nazwa + ": " + karta.r[modelData.klucz]
                font: Theme.tinyFont
                color: Theme.secondaryTextColor
                elide: Text.ElideRight
              }
            }

            Repeater {
              model: (karta.modelData.opis.akcje || []).filter(function (a) {
                return sekcja.widoczna(a, karta.r);
              })

              delegate: QfPozycjaMenu {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.etykieta
                ikona: modelData.ikona || "wfg_paczka"
                onClicked: sekcja.nacisnij(modelData, karta.r)
              }
            }
          }
        }
      }

      // ── Zainstalowane ─────────────────────────────────────────
      Text {
        Layout.fillWidth: true
        Layout.topMargin: 10
        text: qsTr("Zainstalowane")
        font: Theme.tipFont
        color: Theme.mainTextColor
      }

      Repeater {
        model: sekcja.moduly

        delegate: ColumnLayout {
          id: wpis

          required property var modelData

          Layout.fillWidth: true
          spacing: 1

          RowLayout {
            Layout.fillWidth: true

            Text {
              Layout.fillWidth: true
              text: wpis.modelData.opis.nazwa + "  " + (wpis.modelData.opis.wersja || "")
              font: Theme.tipFont
              color: Theme.mainTextColor
              elide: Text.ElideRight
            }
            Text {
              text: wpis.modelData.brak.length > 0 ? qsTr("wymaga nowszej aplikacji") : wpis.modelData.wProjekcie ? qsTr("w tym projekcie") : qsTr("wbudowany")
              font: Theme.tinyFont
              color: wpis.modelData.brak.length > 0 ? Theme.warningColor : wpis.modelData.wProjekcie ? Theme.mainColor : Theme.secondaryTextColor
            }
          }
          Text {
            Layout.fillWidth: true
            text: wpis.modelData.opis.opis || ""
            visible: text !== ""
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
            wrapMode: Text.WordWrap
          }
          Text {
            // dlaczego nie ma karty wyżej — bez tego moduł "znika" bez słowa
            Layout.fillWidth: true
            visible: !wpis.modelData.wProjekcie && wpis.modelData.brak.length === 0 && !!wpis.modelData.rozpoznanie.blad
            text: qsTr("Nie w tym projekcie: %1").arg(wpis.modelData.rozpoznanie.blad || "")
            font: Theme.tinyFont
            color: Theme.secondaryTextColor
            wrapMode: Text.WordWrap
          }
          QfPozycjaMenu {
            Layout.fillWidth: true
            visible: !!wpis.modelData.opis.przepis && wpis.modelData.brak.length === 0
            text: qsTr("Nowy projekt z modułu")
            ikona: "wfg_nowe"
            onClicked: sekcja.otworzNowy(wpis.modelData.opis)
          }
        }
      }
    }
  }
}
