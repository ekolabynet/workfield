import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import org.qgis
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * WorkField: edytor tekstowy plikow konfiguracyjnych projektu (v2).
 * Cel: niespecjalista nie moze latwo zapisac zepsutego pliku.
 * Zywa walidacja JSON z lokalizacja bledu, pasek podpowiedzi pol
 * (workfield_klawisze.json) z podgladem koloru/rozmiaru i kontrola
 * warstwy w projekcie, wzorcowy wpis klawisza. Kopia .bak przy
 * pierwszym zapisie. Plik pozostaje czystym JSON-em.
 */
Popup {
  id: textEditor

  parent: mainWindow.contentItem
  width: Math.min(760, mainWindow.width - 16)
  height: Math.min(880, mainWindow.height - 24)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  closePolicy: Popup.CloseOnEscape

  property string sciezka: ""
  property string oryginal: ""
  property bool zmieniono: false
  property bool bakZapisany: false
  property bool ladowanie: false
  property int potwierdz: 0 // 0: nic, 1: powrot do listy, 2: zamkniecie

  // walidacja: brak (nie-json) / sprawdzam / ok / blad
  property string statusJson: "brak"
  property string bladOpis: ""
  property int bladPozycja: 0
  property int bladWiersz: 1
  property var hint: null
  property bool czekamNaKolor: false
  property int koloroweMiejsce: 0

  readonly property var slownik: ({
      "klawisze": qsTr("lista klawiszy paska szybkiego zapisu"),
      "odleglosci": qsTr("presety odległości [m] dla trybu ODL (obiekt daleko)"),
      "warstwa": qsTr("nazwa warstwy w projekcie, do której trafia zapis — musi istnieć"),
      "etykieta": qsTr("napis na kafelku (najlepiej 1–2 znaki)"),
      "kolor": qsTr("kolor kafelka #RRGGBB — tapnij kwadracik obok, aby wybrać z palety"),
      "zdjecie": qsTr("false = czysty punkt / tyczenie bez aparatu; brak pola = ze zdjęciem"),
      "rozmiar": qsTr("wielkość kafelka w px, 40–120; brak pola = 56 — podgląd w ⅓ skali obok"),
      "ustawienia": qsTr("opcjonalna sekcja: zachowanie i geometria paska QuickCapture"),
      "krawedz": qsTr("strona ekranu dla paska: \"prawa\" (domyślnie) lub \"lewa\" (leworęczni)"),
      "wyrownanie": qsTr("wyrównanie przycisków w pasku: \"lewo\" / \"srodek\" (domyślnie) / \"prawo\""),
      "sekcjaUstawien": qsTr("\"zwijana\" = uchwyt ▴/▾ (domyślnie); \"stala\" = sekcja zawsze widoczna"),
      "rozmiarKafelka": qsTr("domyślny rozmiar kafelków bez własnego pola rozmiar: px 40–120 (domyślnie 56)"),
      "odstep": qsTr("pionowa przerwa między przyciskami paska: px 0–24 (domyślnie 10)"),
      "seriaMs": qsTr("interwał serii wierzchołków przy przytrzymaniu: ms 250–5000 (domyślnie 1000)"),
      "kotwicaLimitS": qsTr("ile sekund kotwica czeka na fix: 5–120 (domyślnie 30)")
    })

  background: Rectangle {
    color: "#EE263238"
    radius: 8
    border.color: "#455A64"
    border.width: 1
  }

  function nazwaPliku(fp) {
    return String(fp).split('/').pop();
  }

  function czyJson() {
    return nazwaPliku(sciezka).toLowerCase().endsWith(".json");
  }

  // ---- skaner JSON: null gdy poprawny, albo { pozycja, opis } ----
  function skanujJson(t) {
    let i = 0;
    const n = t.length;
    function blad(opis, poz) {
      return { "pozycja": poz === undefined ? Math.max(0, Math.min(i, n - 1)) : poz, "opis": opis };
    }
    function biale() {
      while (i < n && " \t\r\n".indexOf(t[i]) !== -1) i++;
    }
    function lancuch() {
      const start = i;
      i++;
      while (i < n) {
        const c = t[i];
        if (c === '\\') { i += 2; continue; }
        if (c === '"') { i++; return null; }
        if (c === '\n') return blad(qsTr("łańcuch bez zamykającego cudzysłowu"), start);
        i++;
      }
      return blad(qsTr("łańcuch bez zamykającego cudzysłowu"), start);
    }
    function liczba() {
      const start = i;
      if (t[i] === '-') i++;
      let cyfry = 0;
      while (i < n && t[i] >= '0' && t[i] <= '9') { i++; cyfry++; }
      if (cyfry === 0) return blad(qsTr("niepoprawna liczba"), start);
      if (i < n && t[i] === '.') {
        i++;
        let u = 0;
        while (i < n && t[i] >= '0' && t[i] <= '9') { i++; u++; }
        if (u === 0) return blad(qsTr("niepoprawna liczba (kropka bez cyfr)"), start);
      }
      if (i < n && (t[i] === 'e' || t[i] === 'E')) {
        i++;
        if (i < n && (t[i] === '+' || t[i] === '-')) i++;
        let u = 0;
        while (i < n && t[i] >= '0' && t[i] <= '9') { i++; u++; }
        if (u === 0) return blad(qsTr("niepoprawna liczba (wykładnik)"), start);
      }
      return null;
    }
    function wartosc() {
      biale();
      if (i >= n) return blad(qsTr("urwany zapis — brakuje wartości"));
      const c = t[i];
      if (c === '{') return obiekt();
      if (c === '[') return tablica();
      if (c === '"') return lancuch();
      if (c === '-' || (c >= '0' && c <= '9')) return liczba();
      if (t.startsWith("true", i)) { i += 4; return null; }
      if (t.startsWith("false", i)) { i += 5; return null; }
      if (t.startsWith("null", i)) { i += 4; return null; }
      if (c === '/') return blad(qsTr("komentarze nie są dozwolone w JSON"));
      return blad(qsTr("nieoczekiwany znak '%1'").arg(c));
    }
    function obiekt() {
      i++;
      biale();
      if (i < n && t[i] === '}') { i++; return null; }
      while (true) {
        biale();
        if (i >= n) return blad(qsTr("obiekt bez zamykającej }"));
        if (t[i] === ',') return blad(qsTr("nadmiarowy lub podwójny przecinek"));
        if (t[i] !== '"') return blad(t[i] === '}' ? qsTr("nadmiarowy przecinek przed }") : qsTr("oczekiwany klucz w cudzysłowie"));
        let e = lancuch();
        if (e) return e;
        biale();
        if (i >= n || t[i] !== ':') return blad(qsTr("brak dwukropka po kluczu"));
        i++;
        e = wartosc();
        if (e) return e;
        biale();
        if (i < n && t[i] === ',') {
          i++;
          biale();
          if (i < n && t[i] === '}') return blad(qsTr("nadmiarowy przecinek przed }"));
          continue;
        }
        if (i < n && t[i] === '}') { i++; return null; }
        return blad(i >= n ? qsTr("obiekt bez zamykającej }") : qsTr("brak przecinka między polami (lub brak })"));
      }
    }
    function tablica() {
      i++;
      biale();
      if (i < n && t[i] === ']') { i++; return null; }
      while (true) {
        biale();
        if (i < n && (t[i] === ',' || t[i] === ']')) return blad(qsTr("nadmiarowy przecinek w tablicy"));
        let e = wartosc();
        if (e) return e;
        biale();
        if (i < n && t[i] === ',') {
          i++;
          biale();
          if (i < n && t[i] === ']') return blad(qsTr("nadmiarowy przecinek przed ]"));
          continue;
        }
        if (i < n && t[i] === ']') { i++; return null; }
        return blad(i >= n ? qsTr("tablica bez zamykającej ]") : qsTr("brak przecinka między elementami (lub brak ])"));
      }
    }
    biale();
    if (i >= n) return blad(qsTr("pusty dokument"), 0);
    let e = wartosc();
    if (e) return e;
    biale();
    if (i < n) return blad(qsTr("treść po końcu dokumentu (nadmiarowa klamra lub znak?)"));
    return null;
  }

  function walidujTeraz() {
    if (sciezka === "" || !czyJson()) {
      statusJson = "brak";
      return;
    }
    const t = obszar.text;
    const w = skanujJson(t);
    if (w === null) {
      try {
        JSON.parse(t);
        statusJson = "ok";
        return;
      } catch (e) {
        statusJson = "blad";
        bladPozycja = 0;
        bladWiersz = 1;
        bladOpis = qsTr("błąd składni: %1").arg(e.message);
        return;
      }
    }
    statusJson = "blad";
    bladPozycja = w.pozycja;
    bladWiersz = t.substring(0, w.pozycja).split('\n').length;
    bladOpis = w.opis;
  }

  // ---- podpowiedzi kontekstowe ----
  function opisWarstwy(nazwa) {
    if (nazwa === "" || typeof quickCaptureBar === 'undefined') {
      return "";
    }
    const l = quickCaptureBar.findLayerByName(nazwa);
    if (!l) {
      return qsTr("✗ brak warstwy „%1” w projekcie — kafelek się nie pojawi").arg(nazwa);
    }
    let g = -1;
    try {
      g = l.geometryType();
    } catch (e) {
    }
    if (g === Qgis.GeometryType.Point) return qsTr("✓ warstwa istnieje (punktowa)");
    if (g === Qgis.GeometryType.Line) return qsTr("✓ istnieje (liniowa — kafelek rysowania)");
    if (g === Qgis.GeometryType.Polygon) return qsTr("✓ istnieje (poligonowa — kafelek rysowania)");
    return qsTr("✓ warstwa istnieje");
  }

  function odswiezHint() {
    if (sciezka === "" || !czyJson() || obszar.text.length > 100000) {
      hint = null;
      return;
    }
    const t = obszar.text;
    const poz = Math.min(obszar.cursorPosition, t.length);
    const start = t.lastIndexOf('\n', poz - 1) + 1;
    let koniec = t.indexOf('\n', poz);
    if (koniec === -1) {
      koniec = t.length;
    }
    const linia = t.substring(start, koniec);
    const m = linia.match(/"([A-Za-z_]+)"\s*:/);
    if (!m || !slownik[m[1]]) {
      hint = null;
      return;
    }
    const h = { "pole": m[1], "opis": slownik[m[1]], "kolor": "", "rozmiar": 0, "warstwaInfo": "" };
    if (h.pole === "kolor") {
      const mk = linia.match(/#[0-9A-Fa-f]{6}/);
      if (mk) {
        h.kolor = mk[0];
      }
    } else if (h.pole === "rozmiar" || h.pole === "rozmiarKafelka") {
      const mr = linia.match(/:\s*(\d+)/);
      if (mr) {
        h.rozmiar = parseInt(mr[1]);
      }
    } else if (h.pole === "warstwa") {
      const mw = linia.match(/:\s*"([^"]*)"/);
      if (mw) {
        h.warstwaInfo = opisWarstwy(mw[1]);
      }
    }
    hint = h;
  }

  // ---- paleta kolorow (wspolny picker aplikacji) ----
  function otworzPalete() {
    if (hint === null || hint.pole !== "kolor") {
      return;
    }
    koloroweMiejsce = obszar.cursorPosition;
    czekamNaKolor = true;
    colorPicker.allowAlpha = false;
    colorPicker.openFor(hint.kolor !== "" ? hint.kolor : "#FF7043");
  }

  function podmienKolor(chosen) {
    let hex = String(chosen);
    if (hex.length === 9) {
      hex = "#" + hex.substring(3);
    }
    hex = hex.toUpperCase();
    const t = obszar.text;
    const poz = Math.min(koloroweMiejsce, t.length);
    const start = t.lastIndexOf('\n', poz - 1) + 1;
    let koniec = t.indexOf('\n', poz);
    if (koniec === -1) {
      koniec = t.length;
    }
    const linia = t.substring(start, koniec);
    let nowa;
    if (/#[0-9A-Fa-f]{6}/.test(linia)) {
      nowa = linia.replace(/#[0-9A-Fa-f]{6}/, hex);
    } else if (/"kolor"\s*:\s*"[^"]*"/.test(linia)) {
      nowa = linia.replace(/("kolor"\s*:\s*")[^"]*(")/, "$1" + hex + "$2");
    } else {
      displayToast(qsTr("Nie znalazłem pola koloru w tej linii"), "warning");
      return;
    }
    obszar.text = t.substring(0, start) + nowa + t.substring(koniec);
    obszar.cursorPosition = Math.min(poz, obszar.text.length);
    odswiezHint();
  }

  // ---- wzorcowy wpis ----
  function pierwszaPunktowa() {
    if (typeof ProjectUtils === 'undefined' || !qgisProject) {
      return "obserwacje";
    }
    const w = ProjectUtils.mapLayers(qgisProject);
    for (const id in w) {
      const l = w[id];
      try {
        if (l && l.geometryType() === Qgis.GeometryType.Point) {
          return l.name;
        }
      } catch (e) {
      }
    }
    return "obserwacje";
  }

  function wstawWzorzec() {
    let obj = null;
    try {
      obj = obszar.text.trim() === "" ? {} : JSON.parse(obszar.text);
    } catch (e) {
      displayToast(qsTr("Najpierw popraw błąd JSON — pasek statusu wskazuje miejsce"), "warning");
      return;
    }
    if (typeof obj !== 'object' || obj === null || Array.isArray(obj)) {
      displayToast(qsTr("Ten plik nie jest obiektem { … } — wzorca nie wstawię"), "warning");
      return;
    }
    if (!obj.klawisze) {
      obj.klawisze = [];
    }
    if (!obj.odleglosci) {
      obj.odleglosci = [25, 50, 100, 200];
    }
    obj.klawisze.push({ "warstwa": pierwszaPunktowa(), "etykieta": "N", "kolor": "#FF7043", "zdjecie": false, "rozmiar": 56 });
    obszar.text = JSON.stringify(obj, null, 2);
    obszar.cursorPosition = obszar.text.length;
    displayToast(qsTr("Dodano wzorcowy wpis na końcu listy — stawiaj kursor na polach, pasek podpowie"));
  }

  // ---- wczytywanie / zapis / wyjscia ----
  function wczytaj(fp) {
    const tresc = String(FileUtils.readFileContent(fp));
    if (tresc.length > 2000000) {
      displayToast(qsTr("Plik za duży na edytor terenowy (limit 2 MB)"), "warning");
      return;
    }
    ladowanie = true;
    obszar.text = tresc;
    ladowanie = false;
    sciezka = fp;
    oryginal = tresc;
    zmieniono = false;
    bakZapisany = false;
    potwierdz = 0;
    walidujTeraz();
    odswiezHint();
  }

  function zapisz() {
    if (sciezka === "") {
      return;
    }
    if (czyJson()) {
      walidujTeraz();
      if (statusJson === "blad") {
        displayToast(qsTr("Błąd JSON, linia %1: %2 — NIE zapisano").arg(bladWiersz).arg(bladOpis), "error");
        return;
      }
    }
    if (!bakZapisany) {
      FileUtils.writeFileContent(sciezka + ".bak", oryginal);
      bakZapisany = true;
    }
    if (FileUtils.writeFileContent(sciezka, obszar.text)) {
      zmieniono = false;
      oryginal = obszar.text;
      displayToast(qsTr("Zapisano %1 (kopia: .bak)").arg(nazwaPliku(sciezka)));
      if (nazwaPliku(sciezka) === "workfield_klawisze.json" && typeof quickCaptureBar !== 'undefined') {
        quickCaptureBar.refreshLayers();
      }
    } else {
      displayToast(qsTr("Zapis nie powiódł się — plik na dysku bez zmian"), "error");
    }
  }

  function sprobujWyjsc(tryb) {
    if (!zmieniono) {
      wykonajWyjscie(tryb);
      return;
    }
    if (potwierdz === tryb) {
      potwierdz = 0;
      zegarPotwierdzenia.stop();
      wykonajWyjscie(tryb);
    } else {
      potwierdz = tryb;
      zegarPotwierdzenia.restart();
      displayToast(qsTr("Niezapisane zmiany — tapnij ponownie, aby porzucić"), "warning");
    }
  }

  function wykonajWyjscie(tryb) {
    if (tryb === 1) {
      sciezka = "";
      zmieniono = false;
      statusJson = "brak";
      hint = null;
    } else {
      textEditor.close();
    }
  }

  onClosed: {
    sciezka = "";
    zmieniono = false;
    potwierdz = 0;
    statusJson = "brak";
    hint = null;
  }

  Timer {
    id: zegarPotwierdzenia

    interval: 3000

    onTriggered: textEditor.potwierdz = 0
  }

  Timer {
    id: walidator

    interval: 400

    onTriggered: {
      textEditor.walidujTeraz();
      textEditor.odswiezHint();
    }
  }

  Connections {
    target: colorPicker
    enabled: textEditor.czekamNaKolor

    function onColorPicked(chosen) {
      textEditor.podmienKolor(chosen);
    }

    function onClosed() {
      textEditor.czekamNaKolor = false;
      colorPicker.allowAlpha = true;
    }
  }

  FolderListModel {
    id: plikiProjektu

    folder: qgisProject && qgisProject.homePath !== "" ? "file://" + qgisProject.homePath : ""
    nameFilters: ["*.json", "*.txt", "*.md", "*.csv"]
    showDirs: false
    sortField: FolderListModel.Name
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: textEditor.sciezka === "" ? qsTr("Pliki projektu — edytor") : textEditor.nazwaPliku(textEditor.sciezka) + (textEditor.zmieniono ? " \u25cf" : "")
      color: textEditor.zmieniono ? "#FFC107" : "#80CBC4"
      font: Theme.strongFont
      elide: Text.ElideMiddle
    }

    // ---------------- widok 1: lista plikow ----------------
    ListView {
      visible: textEditor.sciezka === ""
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: plikiProjektu
      spacing: 2

      delegate: ItemDelegate {
        width: ListView.view.width
        height: 52

        contentItem: RowLayout {
          spacing: 8

          Text {
            Layout.fillWidth: true
            text: fileName
            color: "white"
            font: Theme.defaultFont
            elide: Text.ElideMiddle
          }

          Text {
            text: (fileSize / 1024).toFixed(1) + " kB"
            color: "#B0BEC5"
            font: Theme.tinyFont
          }
        }

        onClicked: textEditor.wczytaj(filePath.toString().replace("file://", ""))
      }

      Text {
        anchors.centerIn: parent
        visible: parent.count === 0
        text: qgisProject && qgisProject.homePath !== "" ? qsTr("Brak plików json/txt/md/csv w katalogu projektu") : qsTr("Najpierw otwórz projekt")
        color: "#B0BEC5"
        font: Theme.tipFont
      }
    }

    // ---------------- widok 2: edycja ----------------
    ScrollView {
      visible: textEditor.sciezka !== ""
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true

      TextArea {
        id: obszar

        wrapMode: TextArea.Wrap
        selectByMouse: true
        font.family: "monospace"
        font.pointSize: Theme.tipFont.pointSize
        color: "white"
        placeholderText: qsTr("(pusty plik)")

        background: Rectangle {
          color: "#1B262C"
          radius: 4
          border.color: "#455A64"
          border.width: 1
        }

        onTextChanged: {
          if (!textEditor.ladowanie && textEditor.sciezka !== "") {
            textEditor.zmieniono = true;
          }
          if (textEditor.sciezka !== "" && textEditor.czyJson()) {
            textEditor.statusJson = "sprawdzam";
            walidator.restart();
          }
        }

        onCursorPositionChanged: textEditor.odswiezHint()
      }
    }

    // ---------------- pasek statusu walidacji ----------------
    Rectangle {
      visible: textEditor.sciezka !== "" && textEditor.czyJson()
      Layout.fillWidth: true
      implicitHeight: 30
      radius: 4
      color: textEditor.statusJson === "ok" ? "#1B5E20" : textEditor.statusJson === "blad" ? "#B71C1C" : "#37474F"

      Text {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: "white"
        font: Theme.tinyFont
        text: textEditor.statusJson === "ok" ? qsTr("✓ JSON poprawny") : textEditor.statusJson === "blad" ? qsTr("✗ linia %1: %2 — tapnij, by skoczyć").arg(textEditor.bladWiersz).arg(textEditor.bladOpis) : qsTr("… sprawdzam")
      }

      MouseArea {
        anchors.fill: parent
        enabled: textEditor.statusJson === "blad"
        onClicked: {
          obszar.cursorPosition = Math.min(textEditor.bladPozycja, obszar.text.length);
          obszar.forceActiveFocus();
        }
      }
    }

    // ---------------- pasek podpowiedzi ----------------
    Rectangle {
      visible: textEditor.sciezka !== "" && textEditor.hint !== null
      Layout.fillWidth: true
      implicitHeight: hintRow.implicitHeight + 12
      radius: 4
      color: "#1B262C"
      border.color: "#455A64"
      border.width: 1

      RowLayout {
        id: hintRow

        anchors.fill: parent
        anchors.margins: 6
        spacing: 10

        Rectangle {
          visible: textEditor.hint !== null && textEditor.hint.pole === "kolor"
          Layout.alignment: Qt.AlignVCenter
          width: 28
          height: 28
          radius: 5
          color: textEditor.hint !== null && textEditor.hint.kolor !== "" ? textEditor.hint.kolor : "transparent"
          border.color: "white"
          border.width: 1

          MouseArea {
            anchors.fill: parent
            anchors.margins: -10
            onClicked: textEditor.otworzPalete()
          }
        }

        Item {
          visible: textEditor.hint !== null && textEditor.hint.rozmiar > 0
          Layout.alignment: Qt.AlignVCenter
          width: 44
          height: 44

          Rectangle {
            anchors.centerIn: parent
            width: textEditor.hint !== null ? Math.min(44, Math.max(6, textEditor.hint.rozmiar / 3)) : 0
            height: width
            radius: width / 2
            color: "#FF7043"
            border.color: "#003D33"
            border.width: 1
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            text: textEditor.hint !== null ? textEditor.hint.pole + (textEditor.hint.rozmiar > 0 ? "  —  " + textEditor.hint.rozmiar + " px" : "") : ""
            color: "#80CBC4"
            font: Theme.strongTipFont
          }

          Text {
            Layout.fillWidth: true
            text: textEditor.hint !== null ? textEditor.hint.opis : ""
            color: "#B0BEC5"
            font: Theme.tinyFont
            wrapMode: Text.Wrap
          }

          Text {
            visible: textEditor.hint !== null && textEditor.hint.warstwaInfo !== ""
            Layout.fillWidth: true
            text: textEditor.hint !== null ? textEditor.hint.warstwaInfo : ""
            color: textEditor.hint !== null && textEditor.hint.warstwaInfo.indexOf("\u2717") === 0 ? "#FF8A80" : "#B9F6CA"
            font: Theme.tinyFont
            wrapMode: Text.Wrap
          }
        }
      }
    }

    RowLayout {
      visible: textEditor.sciezka !== ""
      Layout.fillWidth: true
      spacing: 8

      Button {
        Layout.fillWidth: true
        text: textEditor.potwierdz === 1 ? qsTr("Porzucić zmiany?") : qsTr("Wróć do listy")
        onClicked: textEditor.sprobujWyjsc(1)
      }

      Button {
        visible: textEditor.nazwaPliku(textEditor.sciezka) === "workfield_klawisze.json"
        Layout.fillWidth: true
        text: qsTr("Wzorcowy wpis")
        onClicked: textEditor.wstawWzorzec()
      }

      Button {
        Layout.fillWidth: true
        enabled: textEditor.zmieniono
        text: qsTr("Zapisz")
        onClicked: textEditor.zapisz()
      }
    }

    Button {
      Layout.fillWidth: true
      text: textEditor.potwierdz === 2 ? qsTr("Porzucić zmiany?") : qsTr("Zamknij")
      onClicked: textEditor.sciezka !== "" ? textEditor.sprobujWyjsc(2) : textEditor.close()
    }
  }
}
