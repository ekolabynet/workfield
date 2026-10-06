import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Theme

/**
 * WorkField 22.08.2026 — pozycja menu w naszym stylu.
 *
 * Wyjęta z QfMainDrawer, gdzie żyła jako komponent wewnętrzny. Powód wyjęcia:
 * prawa szuflada używała zwykłego MenuItem-a i dlatego miała inną czcionkę,
 * inne odstępy i brak ikon. Jedna definicja, jeden wygląd.
 *
 * Uwaga z 18.08.2026, wciąż aktualna: własne `background` NIE jest kosmetyką.
 * Styl pulpitowy rysuje ramkę RAZEM Z NAPISEM w delegacie `background`, więc
 * sam `contentItem` nie zastępował napisu, tylko dokładał drugi obok — każda
 * pozycja menu widoczna dwa razy, z przesunięciem. Pusty `background` zabiera
 * stylowi miejsce na jego napis.
 */
Button {
  id: pozycja

  property var t: Theme
  property string ikona: ""

  //! WorkField 23.08.2026 — stan "to jest ta, na ktorej jestes". Material
  //! `highlighted` nie daje sie zobaczyc w stylu pulpitowym (sprawdzone na
  //! zrzucie z 23.08), wiec zaznaczenie rysujemy sami, w tle komponentu.
  property bool wybrana: false

  //! WorkField 23.08.2026 — na waskim ekranie zostaje sama ikona. Nazwa
  //! wraca w dymku, zeby nie trzeba bylo zgadywac, co znaczy obrazek.
  property bool tylkoIkona: false

  /**
   * WorkField 21.09.2026 — UKŁAD: "lista" | "dwie" | "kafelki" | "ikony".
   *
   * Cztery układy to nie cztery komponenty, tylko cztery rozmiary i dwa
   * ustawienia tego samego. Wcześniej prawa szuflada miała własny kafelek,
   * a lewa nie miała nic — trzy sposoby rysowania jednej rzeczy.
   *
   * Szerokość i wysokość nadaje wołający (szuflada wie, ile ma miejsca);
   * tutaj jest tylko to, co zależy od układu: gdzie stoi ikona i czy
   * widać napis.
   */
  property string uklad: "lista"

  /**
   * WorkField 6.10.2026 — PÓŁKA: "core" | "eksperymentalna".
   *
   * Jedna definicja, dwóch czytelników: tło wiersza i widoczność.
   * Gdyby tło brało się skądinąd niż widoczność, rozjechałyby się.
   *
   * Eksperymentalne: można bez nich żyć, poprawiamy spokojnie.
   * Ukryte, dopóki w Ustawieniach nie włączysz „Pokazuj funkcje
   * eksperymentalne”. Ustawienie mieszka na `mainWindow`, żeby obie
   * szuflady widziały zmianę od razu, bez restartu.
   *
   * `=== true`, bo wcześnie przy starcie `mainWindow` może jeszcze
   * nie mieć tej właściwości — a `undefined` przypisane do
   * `visible` daje ostrzeżenie zamiast wartości.
   */
  property string polka: "core"
  readonly property bool eksperymentalna: polka === "eksperymentalna"

  visible: !pozycja.eksperymentalna || mainWindow.pokazujEksperymentalne === true

  //! Ikona NAD napisem, oba wyśrodkowane.
  readonly property bool kafelek: uklad === "kafelki"

  //! Sama ikona, nazwa w dymku. `tylkoIkona` zostaje osobno, bo używa go
  //! szyna kategorii w Ustawieniach, która o układach nic nie wie.
  readonly property bool samaIkona: tylkoIkona || uklad === "ikony"

  ToolTip.text: pozycja.text
  ToolTip.delay: 400
  ToolTip.visible: pozycja.samaIkona && pozycja.hovered && pozycja.text !== ""

  background: Rectangle {
    color: pozycja.wybrana ? Qt.rgba(pozycja.t.mainColor.r, pozycja.t.mainColor.g, pozycja.t.mainColor.b, 0.45) : pozycja.down ? Qt.rgba(1, 1, 1, 0.14) : pozycja.hovered ? Qt.rgba(1, 1, 1, 0.07) : pozycja.eksperymentalna ? Qt.rgba(pozycja.t.warningColor.r, pozycja.t.warningColor.g, pozycja.t.warningColor.b, 0.13) : pozycja.kafelek ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
    radius: pozycja.kafelek ? 6 : 4

    Behavior on color {
      ColorAnimation {
        duration: 120
      }
    }
  }

  flat: true
  Layout.fillWidth: true
  // WYSOKOSC IDZIE ZA TEKSTEM (25.09.2026). Bylo zabetonowane 34 px,
  // wiec zawijanie napisu nic by nie dalo — druga linia nie miescilaby
  // sie w pozycji.
  //
  // Bez petli wiazan: `implicitHeight` zalezy od wysokosci napisu, ta od
  // jego SZEROKOSCI, a szerokosc przychodzi z zewnatrz (QfSiatkaMenu
  // rozdaje ja dzieciom, albo bierze sie z Layout.fillWidth). Wysokosc
  // nigdzie nie wraca do szerokosci.
  implicitHeight: pozycja.kafelek
                  ? 84
                  : pozycja.uklad === "ikony"
                    ? 44
                    : Math.max(34, napisPozycji.implicitHeight + 12)
  font.pointSize: t.tinyFont.pointSize

  // GridLayout, a nie dwa osobne układy: jedna kolumna kładzie ikonę NAD
  // napisem (kafelek), dwie — obok siebie (lista, dwie kolumny). Te same
  // dzieci, ta sama ikona, jeden komponent.
  contentItem: GridLayout {
    columns: pozycja.kafelek ? 1 : 2
    columnSpacing: 10
    rowSpacing: 4

    Image {
      id: obrazIkony
      source: pozycja.ikona !== "" ? t.getThemeVectorIcon(pozycja.ikona) : ""
      sourceSize: Qt.size(22, 22)
      visible: false
    }

    ColorOverlay {
      // MultiEffect.colorization BARWI, ZACHOWUJĄC JASNOŚĆ — ciemna ikona
      // Breeze zostawała ciemna także w ciemnym motywie (17.08.2026).
      // ColorOverlay zamienia piksele na podany kolor, zachowując alfę.
      Layout.leftMargin: pozycja.samaIkona || pozycja.kafelek ? 0 : 6
      Layout.alignment: pozycja.samaIkona || pozycja.kafelek ? Qt.AlignHCenter | Qt.AlignVCenter : Qt.AlignVCenter
      Layout.preferredWidth: pozycja.kafelek ? 26 : 22
      Layout.preferredHeight: pozycja.kafelek ? 26 : 22
      source: obrazIkony
      visible: obrazIkony.status === Image.Ready
      color: pozycja.enabled ? t.mainTextColor : t.secondaryTextColor
    }

    // NAPIS ZAWIJA SIE (25.09.2026) — uwaga Piotra: „czy tekst
    // odsylaczy nie moze sie po prostu zawijac". W ukladzie „dwie
    // kolumny" pozycja ma polowe szerokosci szuflady, wiec „Podklady
    // i dane wysokosciowe" konczylo sie jako „Podklady i dane …",
    // a „Powieksz do warstwy" jako „Powieksz do wa…".
    //
    // WordWrap, nie Wrap: lamiemy na spacji, NIGDY w srodku slowa.
    // `elide` zostaje jako ostatnia deska — dla pojedynczego slowa
    // dluzszego niz cala kolumna.
    Text {
      id: napisPozycji

      Layout.fillWidth: true
      Layout.fillHeight: pozycja.kafelek
      visible: !pozycja.samaIkona
      text: pozycja.text
      font: pozycja.font
      color: pozycja.enabled ? t.mainTextColor : t.secondaryTextColor
      elide: Text.ElideRight
      wrapMode: Text.WordWrap
      maximumLineCount: pozycja.kafelek ? 3 : 2
      horizontalAlignment: pozycja.kafelek ? Text.AlignHCenter : Text.AlignLeft
      verticalAlignment: Text.AlignVCenter
    }
  }
}
