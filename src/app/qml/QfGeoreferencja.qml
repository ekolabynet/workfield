import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as SystemoweOkna
import org.qfield
import Theme

/**
 * \ingroup qml
 *
 * WorkField 21.09.2026 — SZYBKIE GEOREFERENCJONOWANIE RASTRA.
 *
 * Zdjęcie mapy zrobione w terenie, skan planu, pobrany plik bez
 * georeferencji — na podkład, po którym da się chodzić.
 *
 * PUNKT POWSTAJE W DWÓCH RUCHACH, ZA KAŻDYM RAZEM TAK SAMO: krzyżyk stoi,
 * rzecz jedzie pod nim. Najpierw obraz pod krzyżykiem w ramce podglądu,
 * potem — okno zwija się do paska — mapa pod krzyżykiem na ekranie.
 * Jeden ruch ręki w obu krokach, i ten sam, który zna każdy, kto
 * digitalizuje w QField. Palec na telefonie trafia gorzej niż
 * przesunięcie obrazu pod nieruchomym celownikiem — dlatego nie ma tu
 * tapnięcia „w miejsce”.
 *
 * METODA. Siedem do wyboru, jak w Georeferencerze QGIS-a. Bierze się
 * NAJPROSTSZĄ, która wystarcza: każda następna ma więcej swobody, czyli
 * więcej sposobów na ukrycie źle wskazanego punktu. Do zdjęcia mapy
 * z ręki właściwa jest RZUTOWA i cztery rogi jej wystarczą.
 *
 * MIARA JAKOŚCI — dwie liczby, nie jedna. „Odchyłka” mówi, ile brakuje
 * w punktach, które dopasowanie widziało; przy minimalnej liczbie punktów
 * jest zerowa z definicji i nie znaczy nic. „Sprawdzian” wyjmuje każdy
 * punkt po kolei i mierzy, o ile chybia bez niego — i to jest jedyna
 * liczba mówiąca, ile wynik jest wart tam, gdzie się potem chodzi.
 *
 * PODGLĄD JEST MNIEJSZY OD PLIKU: zdjęcie z telefonu ma bok ponad 4000 px,
 * a tekstura o takim boku przekracza GL_MAX_TEXTURE_SIZE wielu Androidów
 * i nie rysuje się wtedy nic. Piksel liczy się więc z `szerokoscPliku`.
 */
Popup {
  id: oknoGeoreferencji

  property var t: Theme

  //! Ścieżka obrazu do dopasowania.
  property string obraz: ""

  //! [{px, py, x, y}] — piksel obrazu i punkt na mapie.
  property var punkty: []

  //! Piksel czekający na wskazanie miejsca na mapie ({px, py}) albo null.
  property var oczekujacy: null

  //! Indeks poprawianego punktu albo -1. Poprawianie PODMIENIA, nie dopisuje.
  property int poprawiany: -1

  //! Klucz metody przekształcenia (Georeferencja::metody).
  property string metoda: "rzutowa"

  //! Wynik oceny z silnika: odchyłki, sprawdzian krzyżowy, minimum.
  property var jakosc: ({})

  //! Rozmiar PLIKU w pikselach — podgląd jest mniejszy, patrz nagłówek.
  property int szerokoscPliku: 0
  property int wysokoscPliku: 0

  //! Uchwyt aparatu systemowego między „Zrób zdjęcie" a gotowym plikiem.
  property var zrodloAparatu: null

  property string stan: ""
  property bool zajety: false

  objectName: "oknoGeoreferencji"

  // Spis pobiera się przy OTWARCIU, nie w wiązaniu: `metodyGeoreferencji`
  // jest funkcją C++, więc wiązanie nie miałoby od czego się przeliczać
  // (skrypty/sito_wiazania.py). Otwarcie jest tu naturalnym momentem —
  // wcześniej okna i tak nie ma czym obsłużyć.
  onOpened: if (spisMetod.length === 0)
    spisMetod = iface.metodyGeoreferencji()

  //! Spis metod z silnika — JEDEN, pobrany raz przy tworzeniu okna
  //! (nie wiązaniem: to jest wartość, nie zależność). Z niego bierze się
  //! i lista w rozwijaczu, i opis, i minimum punktów.
  property var spisMetod: []

  readonly property int indeksMetody: {
    for (var i = 0; i < spisMetod.length; i++)
      if (spisMetod[i].klucz === metoda)
        return i;
    return 0;
  }
  readonly property int minimum: spisMetod.length > 0 ? spisMetod[indeksMetody].minimum : 4
  readonly property bool dosc: punkty.length >= minimum

  function otworz(szuflada) {
    if (szuflada && szuflada.modal && szuflada.opened) {
      const potem = function () {
        szuflada.closed.disconnect(potem);
        oknoGeoreferencji.open();
      };
      szuflada.closed.connect(potem);
      szuflada.close();
    } else {
      open();
    }
  }

  function zacznij(sciezka) {
    obraz = "";
    punkty = [];
    oczekujacy = null;
    poprawiany = -1;
    stan = "";
    szerokoscPliku = 0;
    wysokoscPliku = 0;
    // Wymiary PRZED przypisaniem `obraz`: podgląd zobaczy od razu właściwe
    // `sourceSize` i nie spróbuje zdekodować pełnych 12 Mpx.
    const w = iface.wymiaryObrazu(sciezka);
    if (w.blad) {
      stan = w.blad;
      return;
    }
    szerokoscPliku = w.szerokosc;
    wysokoscPliku = w.wysokosc;
    obraz = sciezka;
    ocen();
  }

  //! „Zrób zdjęcie": aparat SYSTEMOWY — idzie o pełną rozdzielczość
  //! i ostrość na drobnym druku mapy, nie o zdjęcie obiektu ze stemplem.
  function zrobZdjecie() {
    if (!(platformUtilities.capabilities & QfPlatformUtilities.NativeCamera)) {
      stan = qsTr("Aparat nie jest tu dostępny — wskaż plik obrazu.");
      return;
    }
    platformUtilities.createDir(qgisProject.homePath, "georeferencja");
    const nazwa = "georeferencja/mapa_" + Qt.formatDateTime(new Date(), "yyyyMMdd_hhmmss") + ".jpg";
    zrodloAparatu = platformUtilities.getCameraPicture(qgisProject.homePath + "/", nazwa, "jpg", oknoGeoreferencji);
    if (!zrodloAparatu)
      stan = qsTr("Nie udało się uruchomić aparatu.");
  }

  //! Ocena BEZ przeliczania obrazu — liczy się po każdej zmianie punktów
  //! i po zmianie metody, żeby wybór metody było widać, a nie zgadywać.
  function ocen() {
    jakosc = punkty.length > 0 ? iface.ocenDopasowanie(punkty, metoda) : ({});
  }

  // ── piksel pod celownikiem ───────────────────────────────────────
  // Celownik stoi w środku ramki; pod nim jest ten piksel treści, który
  // Flickable właśnie przesunął. Stąd cała arytmetyka to `contentX`.
  function pikselPodCelownikiem() {
    if (podglad.paintedWidth <= 0 || szerokoscPliku <= 0)
      return null;
    const wsp = szerokoscPliku / podglad.paintedWidth;
    const bokX = (podglad.width - podglad.paintedWidth) / 2;
    const bokY = (podglad.height - podglad.paintedHeight) / 2;
    return {
      "px": (przewijacz.contentX / podglad.skala - bokX) * wsp,
      "py": (przewijacz.contentY / podglad.skala - bokY) * wsp
    };
  }

  function ustawCelownikNa(px, py) {
    if (podglad.paintedWidth <= 0 || szerokoscPliku <= 0)
      return;
    const wsp = podglad.paintedWidth / szerokoscPliku;
    const bokX = (podglad.width - podglad.paintedWidth) / 2;
    const bokY = (podglad.height - podglad.paintedHeight) / 2;
    przewijacz.contentX = (bokX + px * wsp) * podglad.skala;
    przewijacz.contentY = (bokY + py * wsp) * podglad.skala;
  }

  //! Krok pierwszy gotowy: zapamiętaj piksel i oddaj ekran mapie.
  function wskazNaMapie() {
    const p = pikselPodCelownikiem();
    if (!p)
      return;
    oczekujacy = p;
    stan = "";
    oknoGeoreferencji.close();
  }

  //! „Dodaj" z paska nad mapą: środek mapy to drugi koniec pary.
  function dodajZeSrodka() {
    if (!oczekujacy)
      return;
    const srodek = mapCanvas.mapSettings.screenToCoordinate(Qt.point(mapCanvas.width / 2, mapCanvas.height / 2));
    const lista = punkty.slice();
    const nowy = {
      "px": oczekujacy.px,
      "py": oczekujacy.py,
      "x": srodek.x,
      "y": srodek.y
    };
    if (poprawiany >= 0 && poprawiany < lista.length)
      lista[poprawiany] = nowy;
    else
      lista.push(nowy);
    punkty = lista;
    oczekujacy = null;
    poprawiany = -1;
    ocen();
    oknoGeoreferencji.open();
  }

  //! „Popraw": celownik wraca na piksel tego punktu i para idzie od nowa.
  function popraw(index) {
    if (index < 0 || index >= punkty.length)
      return;
    poprawiany = index;
    stan = "";
    ustawCelownikNa(punkty[index].px, punkty[index].py);
  }

  function usun(index) {
    const lista = punkty.slice();
    lista.splice(index, 1);
    punkty = lista;
    if (poprawiany === index)
      poprawiany = -1;
    else if (poprawiany > index)
      poprawiany = poprawiany - 1;
    ocen();
  }

  function odchylka(i) {
    return jakosc && jakosc.odchylki && i < jakosc.odchylki.length ? jakosc.odchylki[i] : -1;
  }

  function sprawdzian(i) {
    return jakosc && jakosc.sprawdzianOdchylki && i < jakosc.sprawdzianOdchylki.length ? jakosc.sprawdzianOdchylki[i] : -1;
  }

  function dopasuj() {
    if (!dosc)
      return;
    zajety = true;
    stan = qsTr("Przeliczam obraz…");
    // Przez Qt.callLater, żeby pasek postępu ZDĄŻYŁ się narysować:
    // przeliczenie idzie na tym samym wątku co interfejs i blokuje go
    // na kilka–kilkanaście sekund. Bez tego okno po prostu zamiera.
    Qt.callLater(przelicz);
  }

  function przelicz() {
    const nazwa = FileUtils.fileName(obraz).replace(/\.[^.]+$/, "");
    const wyjscie = qgisProject.homePath + "/georeferencja/" + nazwa + ".tif";
    const w = iface.georeferuj(obraz, punkty, mapCanvas.mapSettings.destinationCrs.authid, metoda, wyjscie);
    zajety = false;
    console.log("WFG georeferencja: " + JSON.stringify(w));
    if (w.blad) {
      stan = w.blad;
      return;
    }
    jakosc = w;
    stan = w.sprawdzian !== undefined
      ? qsTr("Gotowe. Sprawdzian krzyżowy %1 m, największy %2 m.").arg(w.sprawdzian.toFixed(2)).arg(w.sprawdzianNajwiekszy.toFixed(2))
      : qsTr("Gotowe. Przy %1 punktach nie ma z czego zrobić sprawdzianu — dodaj jeszcze jeden.").arg(punkty.length);

    // NIE addRasterLayerToProject: tamto jest pisane dla NMT — liczy
    // statystyki całego pliku i zakłada na pierwsze pasmo rampę „turbo".
    // Zdjęcie mapy ma iść na mapę jako zdjęcie.
    if (!iface.dodajPodkladRastrowy(w.plik, nazwa)) {
      stan = qsTr("Dopasowane, ale warstwy nie udało się dodać: %1").arg(w.plik);
      return;
    }
    if (typeof NarzedziaProjektu !== "undefined")
      NarzedziaProjektu.zapiszProjekt(qgisProject);
    displayToast(qsTr("Podkład „%1” dopasowany").arg(nazwa));
  }

  parent: mainWindow.contentItem
  width: Math.min(520, mainWindow.width - 24)
  height: Math.min(680, mainWindow.height - 60)
  x: (mainWindow.width - width) / 2
  y: Math.max(12, (mainWindow.height - height) / 3)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape

  background: Rectangle {
    color: oknoGeoreferencji.t.mainBackgroundColor
    radius: 8
    border.width: 1
    border.color: oknoGeoreferencji.t.controlBorderColor
  }

  Connections {
    target: oknoGeoreferencji.zrodloAparatu
    ignoreUnknownSignals: true

    function onResourceReceived(sciezka) {
      oknoGeoreferencji.zrodloAparatu = null;
      if (sciezka)
        oknoGeoreferencji.zacznij(qgisProject.homePath + "/" + sciezka);
    }

    function onResourceCanceled(sciezka) {
      oknoGeoreferencji.zrodloAparatu = null;
    }
  }

  SystemoweOkna.FileDialog {
    id: wybieraczObrazu

    title: qsTr("Wskaż obraz do dopasowania")
    // Start w Pobranych — tam ląduje plik przysłany albo wgrany kablem.
    // Ta sama droga co w kreatorze „Projekt z DXF" (18.09).
    currentFolder: "file:///storage/emulated/0/Download"
    nameFilters: [qsTr("Wszystkie pliki (*)")]
    onAccepted: oknoGeoreferencji.zacznij(String(selectedFile).replace(/^file:\/\//, ""))
  }

  contentItem: ColumnLayout {
    spacing: 6

    Text {
      Layout.fillWidth: true
      text: qsTr("Dopasuj obraz do mapy")
      font: oknoGeoreferencji.t.strongFont
      color: oknoGeoreferencji.t.mainTextColor
    }

    // ── skąd obraz ───────────────────────────────────────────────
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 4
      visible: oknoGeoreferencji.punkty.length === 0

      Text {
        Layout.fillWidth: true
        visible: oknoGeoreferencji.obraz === ""
        text: qsTr("Zrób zdjęcie mapy albo planu, albo wskaż plik obrazu. Wynik będzie podkładem do orientacji w terenie — nie materiałem pomiarowym.")
        font: oknoGeoreferencji.t.tinyFont
        color: oknoGeoreferencji.t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      QfPozycjaMenu {
        Layout.fillWidth: true
        t: oknoGeoreferencji.t
        text: qsTr("Zrób zdjęcie mapy…")
        ikona: "wfg_zdjecia"
        onClicked: oknoGeoreferencji.zrobZdjecie()
      }

      QfPozycjaMenu {
        Layout.fillWidth: true
        t: oknoGeoreferencji.t
        text: oknoGeoreferencji.obraz === "" ? qsTr("Wskaż plik obrazu…") : qsTr("Inny plik obrazu…")
        ikona: "wfg_otworz"
        onClicked: wybieraczObrazu.open()
      }
    }

    // ── obraz pod celownikiem ────────────────────────────────────
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(240, oknoGeoreferencji.height * 0.36)
      visible: oknoGeoreferencji.obraz !== ""
      color: oknoGeoreferencji.t.controlBackgroundColor
      border.width: 1
      border.color: oknoGeoreferencji.t.controlBorderColor
      clip: true

      Flickable {
        id: przewijacz

        anchors.fill: parent
        contentWidth: plansza.width
        contentHeight: plansza.height
        clip: true

        Item {
          id: plansza

          // Margines szerokości całej ramki z każdej strony: bez niego
          // krzyżyk dosięgnąłby tylko środka obrazu, bo przy dopasowaniu
          // do ramki nie ma czego przesuwać.
          width: podglad.width * podglad.skala + przewijacz.width
          height: podglad.height * podglad.skala + przewijacz.height

          Image {
            id: podglad

            //! Powiększenie szczypaniem: na zdjęciu mapy trzeba trafić
            //! w konkretny narożnik działki, a nie „gdzieś tam".
            property real skala: 1.0

            x: przewijacz.width / 2
            y: przewijacz.height / 2
            // QfUrlUtils, a nie "file://" + ścieżka: zdjęcie z Pobranych
            // bywa nazwane ze spacją albo z polską literą, a tego surowy
            // sklejony adres nie koduje i obraz się nie wczytuje.
            source: oknoGeoreferencji.obraz !== "" ? QfUrlUtils.fromString(oknoGeoreferencji.obraz) : ""
            // Najwyżej 2048 px boku — pełne 12 Mpx nie mieści się w teksturze
            // na wielu Androidach i nie rysuje się WTEDY NIC. 0 = bez ścięcia.
            sourceSize.width: oknoGeoreferencji.szerokoscPliku > 2048 ? 2048 : 0
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            // Po wczytaniu celownik staje na ŚRODKU obrazu. Bez tego
            // Flickable zaczyna od contentX = 0, czyli od marginesu obok
            // obrazu - a wygląda to jak obraz zepchnięty w róg ramki.
            onStatusChanged: if (status === Image.Ready)
              oknoGeoreferencji.ustawCelownikNa(oknoGeoreferencji.szerokoscPliku / 2, oknoGeoreferencji.wysokoscPliku / 2)
            width: przewijacz.width
            height: przewijacz.height
            transform: Scale {
              origin.x: 0
              origin.y: 0
              xScale: podglad.skala
              yScale: podglad.skala
            }

            PinchHandler {
              id: szczypanie

              target: null
              minimumPointCount: 2

              property real bazowa: 1.0
              //! Piksel pod celownikiem zapamiętany na czas szczypania —
              //! powiększenie ma przybliżać TO, co się celuje, a nie
              //! uciekać na bok razem z zawartością.
              property var trzymany: null

              onActiveChanged: {
                if (active) {
                  bazowa = podglad.skala;
                  trzymany = oknoGeoreferencji.pikselPodCelownikiem();
                } else {
                  trzymany = null;
                }
              }
              onActiveScaleChanged: {
                podglad.skala = Math.max(1.0, Math.min(8.0, bazowa * activeScale));
                if (trzymany)
                  oknoGeoreferencji.ustawCelownikNa(trzymany.px, trzymany.py);
              }
            }

            Repeater {
              model: oknoGeoreferencji.punkty

              delegate: Item {
                required property int index
                required property var modelData

                readonly property real wsp: podglad.paintedWidth > 0 && oknoGeoreferencji.szerokoscPliku > 0
                                            ? podglad.paintedWidth / oknoGeoreferencji.szerokoscPliku : 0

                x: (podglad.width - podglad.paintedWidth) / 2 + modelData.px * wsp
                y: (podglad.height - podglad.paintedHeight) / 2 + modelData.py * wsp

                Rectangle {
                  x: -7
                  y: -7
                  width: 14
                  height: 14
                  radius: 7
                  color: "transparent"
                  border.width: 2
                  border.color: index === oknoGeoreferencji.poprawiany ? "#ffb300" : "#d81b60"
                }

                Text {
                  x: 8
                  y: -7
                  text: index + 1
                  font.pointSize: 7
                  color: index === oknoGeoreferencji.poprawiany ? "#ffb300" : "#d81b60"
                }
              }
            }
          }
        }
      }

      // celownik — nieruchomy, tak samo jak nad mapą
      Rectangle {
        anchors.centerIn: parent
        width: 2
        height: 28
        color: "#00b0ff"
      }

      Rectangle {
        anchors.centerIn: parent
        width: 28
        height: 2
        color: "#00b0ff"
      }

      Rectangle {
        anchors.centerIn: parent
        width: 8
        height: 8
        radius: 4
        color: "transparent"
        border.width: 2
        border.color: "#00b0ff"
      }
    }

    // Bez tego okno z nierysującym się obrazem stoi w ciszy i wygląda
    // na zawieszone — a to właśnie była usterka z terenu.
    Text {
      Layout.fillWidth: true
      visible: oknoGeoreferencji.obraz !== "" && podglad.status !== Image.Ready
      text: podglad.status === Image.Error
            ? qsTr("Nie udało się wczytać obrazu: %1").arg(oknoGeoreferencji.obraz)
            : qsTr("Wczytuję obraz…")
      font: oknoGeoreferencji.t.tinyFont
      color: podglad.status === Image.Error ? oknoGeoreferencji.t.errorColor : oknoGeoreferencji.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      visible: oknoGeoreferencji.obraz !== "" && podglad.status === Image.Ready
      spacing: 8

      Text {
        Layout.fillWidth: true
        text: oknoGeoreferencji.poprawiany >= 0
              ? qsTr("Poprawiasz punkt %1 — przesuń obraz pod krzyżyk.").arg(oknoGeoreferencji.poprawiany + 1)
              : qsTr("Przesuń obraz tak, żeby krzyżyk stanął na miejscu, które umiesz wskazać w terenie.")
        font: oknoGeoreferencji.t.tinyFont
        color: oknoGeoreferencji.poprawiany >= 0 ? "#ffb300" : oknoGeoreferencji.t.secondaryTextColor
        wrapMode: Text.WordWrap
      }

      Button {
        text: qsTr("Wskaż na mapie")
        font.pointSize: oknoGeoreferencji.t.tinyFont.pointSize
        highlighted: true
        onClicked: oknoGeoreferencji.wskazNaMapie()
      }
    }

    // ── metoda ───────────────────────────────────────────────────
    RowLayout {
      Layout.fillWidth: true
      visible: oknoGeoreferencji.obraz !== ""
      spacing: 6

      Text {
        text: qsTr("Metoda:")
        font: oknoGeoreferencji.t.tinyFont
        color: oknoGeoreferencji.t.secondaryTextColor
      }

      ComboBox {
        id: wyborMetody

        Layout.fillWidth: true
        font.pointSize: oknoGeoreferencji.t.tinyFont.pointSize
        model: oknoGeoreferencji.spisMetod
        textRole: "nazwa"
        // currentIndex NIE JEST wiązaniem: ComboBox nadpisuje je sam przy
        // zmianie modelu i wiązanie i tak by przepadło. `metoda` jest
        // jedynym źródłem prawdy, a rozwijacz ustawia się z niej jawnie —
        // przez Qt.callLater, bo ComboBox zeruje indeks PO sygnale
        // `countChanged` i przypisanie wprost przepadłoby (sprawdzone
        // w piaskownicy: rozwijacz pokazywał pierwszą metodę z listy,
        // a opis pod nim — właściwą).
        onCountChanged: Qt.callLater(ustawZMetody)
        Component.onCompleted: Qt.callLater(ustawZMetody)

        function ustawZMetody() {
          currentIndex = oknoGeoreferencji.indeksMetody;
        }
        onActivated: function (i) {
          oknoGeoreferencji.metoda = oknoGeoreferencji.spisMetod[i].klucz;
          oknoGeoreferencji.ocen();
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: oknoGeoreferencji.obraz !== ""
      text: {
        const m = oknoGeoreferencji.spisMetod;
        const i = oknoGeoreferencji.indeksMetody;
        if (i < 0 || i >= m.length)
          return "";
        return qsTr("%1 Potrzeba co najmniej %2 punktów, jest %3.").arg(m[i].opis).arg(m[i].minimum).arg(oknoGeoreferencji.punkty.length);
      }
      font: oknoGeoreferencji.t.tinyFont
      color: oknoGeoreferencji.dosc ? oknoGeoreferencji.t.secondaryTextColor : oknoGeoreferencji.t.warningColor
      wrapMode: Text.WordWrap
    }

    // ── miara jakości ────────────────────────────────────────────
    Text {
      Layout.fillWidth: true
      visible: oknoGeoreferencji.jakosc && oknoGeoreferencji.jakosc.srednie !== undefined
      text: {
        const j = oknoGeoreferencji.jakosc;
        if (!j || j.srednie === undefined)
          return "";
        if (j.sprawdzian === undefined)
          return qsTr("Odchyłka %1 m — przy minimalnej dla tej metody liczbie punktów ta liczba NIC NIE MÓWI o jakości: każda metoda przechodzi wtedy przez punkty dokładnie. Dodaj jeszcze jeden punkt, żeby dostać sprawdzian.").arg(j.srednie.toFixed(2));
        return qsTr("Odchyłka %1 m · SPRAWDZIAN %2 m, największy %3 m (punkt %4).").arg(j.srednie.toFixed(2)).arg(j.sprawdzian.toFixed(2)).arg(j.sprawdzianNajwiekszy.toFixed(2)).arg(j.sprawdzianNajgorszy + 1);
      }
      font: oknoGeoreferencji.t.tinyFont
      color: {
        const j = oknoGeoreferencji.jakosc;
        if (!j || j.sprawdzian === undefined)
          return oknoGeoreferencji.t.warningColor;
        return j.sprawdzian > 3 * Math.max(j.srednie, 0.01) + 1 ? oknoGeoreferencji.t.warningColor : oknoGeoreferencji.t.secondaryTextColor;
      }
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      visible: oknoGeoreferencji.jakosc && oknoGeoreferencji.jakosc.blad !== undefined && oknoGeoreferencji.punkty.length > 0
      text: oknoGeoreferencji.jakosc && oknoGeoreferencji.jakosc.blad !== undefined ? oknoGeoreferencji.jakosc.blad : ""
      font: oknoGeoreferencji.t.tinyFont
      color: oknoGeoreferencji.t.warningColor
      wrapMode: Text.WordWrap
    }

    // ── punkty ───────────────────────────────────────────────────
    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 60
      visible: oknoGeoreferencji.punkty.length > 0
      clip: true
      model: oknoGeoreferencji.punkty
      ScrollBar.vertical: ScrollBar {}

      delegate: RowLayout {
        required property int index
        required property var modelData

        width: ListView.view.width
        spacing: 4

        Text {
          Layout.fillWidth: true
          text: {
            const o = oknoGeoreferencji.odchylka(index);
            const s = oknoGeoreferencji.sprawdzian(index);
            let opis = qsTr("%1.  %2  %3").arg(index + 1).arg(modelData.x.toFixed(1)).arg(modelData.y.toFixed(1));
            if (o >= 0)
              opis += qsTr("  ·  %1 m").arg(o.toFixed(2));
            if (s >= 0)
              opis += qsTr("  ·  spr. %1 m").arg(s.toFixed(2));
            return opis;
          }
          font: oknoGeoreferencji.t.tinyFont
          color: index === oknoGeoreferencji.jakosc.sprawdzianNajgorszy && oknoGeoreferencji.punkty.length > 2
                 ? oknoGeoreferencji.t.warningColor : oknoGeoreferencji.t.mainTextColor
          elide: Text.ElideRight
        }

        Button {
          text: qsTr("Popraw")
          font.pointSize: oknoGeoreferencji.t.tinyFont.pointSize
          onClicked: oknoGeoreferencji.popraw(index)
        }

        Button {
          text: qsTr("Usuń")
          font.pointSize: oknoGeoreferencji.t.tinyFont.pointSize
          onClicked: oknoGeoreferencji.usun(index)
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: oknoGeoreferencji.stan !== ""
      text: oknoGeoreferencji.stan
      font: oknoGeoreferencji.t.tipFont
      color: oknoGeoreferencji.t.mainTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true

      BusyIndicator {
        implicitWidth: 20
        implicitHeight: 20
        running: oknoGeoreferencji.zajety
        visible: running
      }

      Item {
        Layout.fillWidth: true
      }

      Button {
        text: qsTr("Zamknij")
        font.pointSize: oknoGeoreferencji.t.tinyFont.pointSize
        onClicked: oknoGeoreferencji.close()
      }

      Button {
        text: qsTr("Dopasuj")
        font.pointSize: oknoGeoreferencji.t.tinyFont.pointSize
        highlighted: true
        enabled: !oknoGeoreferencji.zajety && oknoGeoreferencji.dosc
        onClicked: oknoGeoreferencji.dopasuj()
      }
    }
  }
}
