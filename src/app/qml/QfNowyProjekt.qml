/***************************************************************************
  QfNowyProjekt.qml - nowy projekt w ISTNIEJĄCYM zleceniu

 ---------------------
 WorkField 18.08.2026. Drugi z dwóch czasowników tworzenia (pierwszy:
 QfNoweZadanie = „Nowe zlecenie"). Model Zlecenie → Projekt, decyzja Piotra:
 zlecenie jest WYWNIOSKOWANE ze stanu na dysku, nie zapisane osobno. Projekt
 rodzi się WEWNĄTRZ istniejącego zlecenia i dziedziczy jego tożsamość.

 DLACZEGO OSOBNE OKNO. „Nowe zlecenie" wpisuje się od zera (zleceniodawca,
 teren). „Nowy projekt" nie wpisuje — WYBIERA z tego, co już w systemie jest:
 zleceniodawca → teren → zlecenie. Trzy listy, każda zawężona przez wybór
 z poprzedniej. Wpisywanie z palca tego, co już istnieje, rodzi literówki,
 a literówka w zleceniodawcy zakłada drugie, bliźniacze zlecenie.

 SKĄD LISTY. Ten sam skan co drzewo w zakładce Zlecenia
 (procesy.znajdzProjekty). Zlecenie nie ma własnego pliku — jego tożsamość
 czytamy z nazwy katalogu (zleceniodawca_teren_id_rodzaj_wersja) i z ZADANIE.json
 sąsiednich projektów. Świeże zlecenie bez żadnego projektu tu się nie pojawi;
 to celowe — najpierw „Nowe zlecenie" zakłada pierwszy projekt, potem ten kreator
 dokłada kolejne aspekty.

 CO POWSTAJE. Nazwa nowego projektu = <prefiks zlecenia>_<rodzaj>, czyli ten sam
 zleceniodawca_teren_id co wybrane zlecenie, plus nowy rodzaj. Metryczka
 ZADANIE.json dostaje odziedziczonego zleceniodawcę i teren (formy czytelne
 z JSON-a wybranego projektu), a nie skróty z nazwy.

 Patrz claude/MODEL_ZLECENIA.md i claude/ZAKLADKI_przebudowa.md.
 ***************************************************************************/

import QtQuick
import QtCore
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.qfield
import Theme

Popup {
  id: kreator

  property var t

  signal utworzono(string sciezka)

  // ── korzeń: ten sam co Studio i QfNoweZadanie ──────────────────────────
  Settings {
    id: ustawieniaMagazynu
    category: "WFGStudio"
    property string korzenProjektow: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/WorkField"
  }

  ProcesyStudio {
    id: procesy
  }

  function korzenMagazynu() {
    return ustawieniaMagazynu.korzenProjektow !== "" ? ustawieniaMagazynu.korzenProjektow : iface.dataRoot();
  }

  property string katalogSzablonow: ""
  property string katalogProjektow: ""

  // ── stan wyboru ────────────────────────────────────────────────────────
  //! wszystkie sparsowane projekty: { zlecKod, terenKod, id, rodzaj, prefiks,
  //! zleceniodawca, teren }
  property var projekty: []
  property string wybZleceniodawca: ""   // kod, np. "zzw"
  property string wybTeren: ""           // kod, np. "pze"
  property string wybZlecenie: ""        // prefiks, np. "zzw_pze_2605"
  property string szablonWybrany: ""

  readonly property string bezSzablonu: qsTr("(pusty projekt — bez szablonu)")

  width: Math.min(mainWindow.width - 32, 520)
  height: Math.min(mainWindow.height - 64, 620)
  x: Math.round((mainWindow.width - width) / 2)
  y: Math.round((mainWindow.height - height) / 2)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape

  background: Rectangle {
    color: t.mainBackgroundColor
    radius: 8
    border.color: t.controlBorderColor
  }

  onOpened: {
    if (katalogSzablonow === "")
      katalogSzablonow = NarzedziaProjektu.katalogSzablonow(korzenMagazynu());
    if (katalogSzablonow === "")
      katalogSzablonow = NarzedziaProjektu.katalogSzablonow(iface.dataRoot());
    if (katalogSzablonow === "")
      katalogSzablonow = korzenMagazynu() + "/szablony";
    if (katalogProjektow === "")
      katalogProjektow = NarzedziaProjektu.katalogZadan(korzenMagazynu());
    if (katalogProjektow === "")
      katalogProjektow = iface.dataRoot() + "Imported Projects";
    komunikat.text = "";
    wybZleceniodawca = "";
    wybTeren = "";
    wybZlecenie = "";
    szablonWybrany = "";
    skanuj();
  }

  // ── skan istniejących projektów ────────────────────────────────────────
  // Ten sam regeks co QfStudioSection.parsujCzlony: człony z nazwy katalogu.
  function skanuj() {
    const wynik = [];
    const wszystkie = procesy.znajdzProjekty(korzenMagazynu(), 4);
    const re = /^([a-z0-9]+)_([a-z]+)_([0-9]+)_([a-z0-9]+?)(?:_v[0-9]+)?$/;
    for (const p of wszystkie) {
      if (p.typ === "szablon")
        continue;
      const segmenty = String(p.gdzie || "").split("/").filter(x => x !== "");
      const kandydaci = [String(p.nazwa || "")].concat(segmenty.slice().reverse());
      let m = null;
      for (const k of kandydaci) {
        m = re.exec(k);
        if (m)
          break;
      }
      if (!m)
        continue;

      // formy czytelne z metryczki, jeśli jest
      let ludzkiZlec = "";
      let ludzkiTeren = "";
      const surowe = procesy.czytajTekst(String(p.sciezka || "") + "/ZADANIE.json");
      if (surowe !== "") {
        try {
          const z = JSON.parse(surowe);
          ludzkiZlec = z.zleceniodawca !== undefined ? z.zleceniodawca : "";
          ludzkiTeren = z.teren !== undefined ? z.teren : "";
        } catch (e) {
          // zła metryczka: zostają same kody
        }
      }

      wynik.push({
        "zlecKod": m[1],
        "terenKod": m[2],
        "id": m[3],
        "rodzaj": m[4],
        "prefiks": m[1] + "_" + m[2] + "_" + m[3],
        "zleceniodawca": ludzkiZlec,
        "teren": ludzkiTeren
      });
    }
    kreator.projekty = wynik;
  }

  // ── listy kaskadowe ────────────────────────────────────────────────────
  function unikalne(pary) {
    // pary: [{kod, etykieta}] → bez powtórzeń kodu, etykieta pierwsza niepusta
    const widziane = {};
    const lista = [];
    for (const x of pary) {
      if (widziane[x.kod] === undefined) {
        widziane[x.kod] = lista.length;
        lista.push({ "kod": x.kod, "etykieta": x.etykieta !== "" ? x.etykieta : x.kod });
      } else if (lista[widziane[x.kod]].etykieta === x.kod && x.etykieta !== "") {
        lista[widziane[x.kod]].etykieta = x.etykieta;
      }
    }
    return lista;
  }

  readonly property var listaZleceniodawcow: unikalne(
    projekty.map(p => ({ "kod": p.zlecKod, "etykieta": p.zleceniodawca })))

  readonly property var listaTerenow: unikalne(
    projekty.filter(p => p.zlecKod === wybZleceniodawca)
            .map(p => ({ "kod": p.terenKod, "etykieta": p.teren })))

  readonly property var listaZlecen: unikalne(
    projekty.filter(p => p.zlecKod === wybZleceniodawca && p.terenKod === wybTeren)
            .map(p => ({ "kod": p.prefiks, "etykieta": p.prefiks })))

  //! rodzaje już użyte w tym zleceniu — żeby nie założyć drugiego „inw"
  readonly property var rodzajeWZleceniu: projekty
    .filter(p => p.prefiks === wybZlecenie)
    .map(p => p.rodzaj)

  function etykietaKodu(lista, kod) {
    for (const x of lista)
      if (x.kod === kod)
        return x.etykieta;
    return kod;
  }

  // ── podgląd nazwy nowego projektu ──────────────────────────────────────
  function nazwaProjektu() {
    const rodzaj = poleRodzaj.currentText.trim().toLowerCase();
    if (wybZlecenie === "" || rodzaj === "")
      return "";
    return wybZlecenie + "_" + rodzaj;
  }

  // ── szablony ───────────────────────────────────────────────────────────
  property var listaSzablonow: [bezSzablonu]

  function przebudujListe() {
    const lista = [bezSzablonu];
    for (let i = 0; i < modelSzablonow.count; i++)
      lista.push(modelSzablonow.get(i, "fileName"));
    listaSzablonow = lista;
  }

  FolderListModel {
    id: modelSzablonow
    folder: kreator.katalogSzablonow !== "" ? "file://" + kreator.katalogSzablonow : ""
    showFiles: false
    showDirs: true
    showDotAndDotDot: false
    onCountChanged: kreator.przebudujListe()
  }

  // ── utworzenie ─────────────────────────────────────────────────────────
  function utworz() {
    const nazwa = nazwaProjektu();
    if (nazwa === "") {
      komunikat.text = qsTr("Wybierz zlecenie i podaj rodzaj.");
      return;
    }
    const cel = katalogProjektow + "/" + nazwa;
    if (FileUtils.fileExists(cel)) {
      komunikat.text = qsTr("Projekt %1 już istnieje w tym zleceniu — zmień rodzaj.").arg(nazwa);
      return;
    }

    const zrodlo = szablonWybrany !== "" ? katalogSzablonow + "/" + szablonWybrany : "";

    // szablon z przepisem: interpreter sam wczytuje gotowy projekt, więc NIE
    // emitujemy utworzono() (inaczej wczytałby się dwa razy) — tak jak w
    // QfNoweZadanie.
    if (szablonWybrany !== "" && FileUtils.fileExists(zrodlo + "/przepis.json")) {
      if (!mainWindow.przepisy.noweZadanie(zrodlo + "/przepis.json", katalogProjektow, nazwa)) {
        komunikat.text = qsTr("Nie udało się zbudować projektu z przepisu.");
        return;
      }
      zapiszMetryczke(cel, nazwa);
      kreator.close();
      return;
    }

    if (szablonWybrany === "") {
      platformUtilities.createDir(katalogProjektow, nazwa);
      if (!iface.createBlankProject(cel + "/projekt.qgs")) {
        komunikat.text = qsTr("Nie udało się utworzyć pustego projektu.");
        return;
      }
    } else if (!FileUtils.copyRecursively(zrodlo, cel, null, false)) {
      komunikat.text = qsTr("Nie udało się skopiować szablonu.");
      return;
    }

    zapiszMetryczke(cel, nazwa);
    displayToast(qsTr("Utworzono projekt %1").arg(nazwa));
    kreator.utworzono(cel);
    kreator.close();
  }

  // Metryczka dziedziczy zleceniodawcę i teren po wybranym zleceniu —
  // formy czytelne, nie skróty z nazwy. Rodzaj z pola.
  function zapiszMetryczke(cel, nazwa) {
    const rodzaj = poleRodzaj.currentText.trim().toLowerCase();
    const zadanie = {
      "id_zadania": nazwa,
      "rola": "wydanie",
      "szablon": rodzaj,
      "zleceniodawca": ludzkiZleceniodawca(),
      "teren": ludzkiTeren(),
      "data_rozpoczecia": new Date().toLocaleDateString(Qt.locale(), "yyyy-MM-dd"),
      "tagi": [],
      "zrodlo_szablonu": szablonWybrany !== "" ? szablonWybrany : "brak",
      "utworzono": new Date().toISOString().substring(0, 19).replace("T", " ")
    };
    FileUtils.writeFileContent(cel + "/ZADANIE.json", JSON.stringify(zadanie, null, 2));
  }

  function ludzkiZleceniodawca() {
    for (const p of projekty)
      if (p.prefiks === wybZlecenie && p.zleceniodawca !== "")
        return p.zleceniodawca;
    return wybZleceniodawca;
  }

  function ludzkiTeren() {
    for (const p of projekty)
      if (p.prefiks === wybZlecenie && p.teren !== "")
        return p.teren;
    return wybTeren;
  }

  // ── widok ──────────────────────────────────────────────────────────────
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 14
    spacing: 10

    Label {
      text: qsTr("Nowy projekt w zleceniu")
      font: t.strongTipFont
      color: t.mainTextColor
    }

    Label {
      Layout.fillWidth: true
      visible: kreator.projekty.length === 0
      text: qsTr("Nie ma jeszcze żadnego zlecenia. Załóż je w zakładce Zlecenia („Nowe zlecenie”), potem wróć tu po kolejne aspekty.")
      font: t.tipFont
      color: t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    // ── zleceniodawca ──
    Label {
      text: qsTr("Zleceniodawca")
      font: t.tinyFont
      color: t.secondaryTextColor
    }
    ComboBox {
      id: poleZleceniodawca
      Layout.fillWidth: true
      enabled: kreator.projekty.length > 0
      model: kreator.listaZleceniodawcow
      textRole: "etykieta"
      valueRole: "kod"
      onActivated: {
        kreator.wybZleceniodawca = currentValue;
        kreator.wybTeren = "";
        kreator.wybZlecenie = "";
      }
    }

    // ── teren ──
    Label {
      text: qsTr("Teren")
      font: t.tinyFont
      color: t.secondaryTextColor
    }
    ComboBox {
      id: poleTeren
      Layout.fillWidth: true
      enabled: kreator.wybZleceniodawca !== ""
      model: kreator.listaTerenow
      textRole: "etykieta"
      valueRole: "kod"
      onActivated: {
        kreator.wybTeren = currentValue;
        kreator.wybZlecenie = "";
      }
    }

    // ── zlecenie ──
    Label {
      text: qsTr("Zlecenie")
      font: t.tinyFont
      color: t.secondaryTextColor
    }
    ComboBox {
      id: poleZlecenie
      Layout.fillWidth: true
      enabled: kreator.wybTeren !== ""
      model: kreator.listaZlecen
      textRole: "etykieta"
      valueRole: "kod"
      onActivated: kreator.wybZlecenie = currentValue
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: t.controlBorderColor
    }

    // ── rodzaj nowego projektu ──
    Label {
      text: qsTr("Rodzaj (aspekt) nowego projektu")
      font: t.tinyFont
      color: t.secondaryTextColor
    }
    ComboBox {
      id: poleRodzaj
      Layout.fillWidth: true
      editable: true
      enabled: kreator.wybZlecenie !== ""
      model: ["inw", "obs", "ciecia", "rekonesans"]
    }
    Label {
      Layout.fillWidth: true
      visible: kreator.wybZlecenie !== "" && kreator.rodzajeWZleceniu.indexOf(poleRodzaj.currentText.trim().toLowerCase()) !== -1
      text: qsTr("Uwaga: rodzaj „%1” już jest w tym zleceniu.").arg(poleRodzaj.currentText.trim().toLowerCase())
      font: t.tinyFont
      color: t.warningColor
      wrapMode: Text.WordWrap
    }

    // ── szablon ──
    Label {
      text: qsTr("Szablon")
      font: t.tinyFont
      color: t.secondaryTextColor
    }
    ComboBox {
      id: wyborSzablonu
      Layout.fillWidth: true
      model: kreator.listaSzablonow
      onCurrentTextChanged: kreator.szablonWybrany = (currentText === kreator.bezSzablonu ? "" : currentText)
    }

    // ── podgląd nazwy ──
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      radius: 6
      color: "transparent"
      border.color: t.controlBorderColor
      visible: kreator.nazwaProjektu() !== ""

      Label {
        anchors.centerIn: parent
        text: kreator.nazwaProjektu()
        font: t.strongTipFont
        color: t.mainTextColor
      }
    }

    Label {
      id: komunikat
      Layout.fillWidth: true
      color: t.warningColor
      font: t.tinyFont
      wrapMode: Text.WordWrap
      visible: text !== ""
    }

    Item { Layout.fillHeight: true }

    RowLayout {
      Layout.fillWidth: true
      Item { Layout.fillWidth: true }
      Button {
        text: qsTr("Anuluj")
        flat: true
        onClicked: kreator.close()
      }
      Button {
        text: qsTr("Utwórz projekt")
        enabled: kreator.nazwaProjektu() !== ""
        onClicked: kreator.utworz()
      }
    }
  }
}
