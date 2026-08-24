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

  ToolTip.text: pozycja.text
  ToolTip.delay: 400
  ToolTip.visible: pozycja.tylkoIkona && pozycja.hovered && pozycja.text !== ""

  background: Rectangle {
    color: pozycja.wybrana ? Qt.rgba(pozycja.t.mainColor.r, pozycja.t.mainColor.g, pozycja.t.mainColor.b, 0.45) : pozycja.down ? Qt.rgba(1, 1, 1, 0.14) : pozycja.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
    radius: 4

    Behavior on color {
      ColorAnimation {
        duration: 120
      }
    }
  }

  flat: true
  Layout.fillWidth: true
  implicitHeight: 34
  font.pointSize: t.tinyFont.pointSize

  contentItem: RowLayout {
    spacing: 10

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
      Layout.leftMargin: pozycja.tylkoIkona ? 0 : 6
      Layout.alignment: pozycja.tylkoIkona ? Qt.AlignHCenter | Qt.AlignVCenter : Qt.AlignVCenter
      Layout.preferredWidth: 22
      Layout.preferredHeight: 22
      source: obrazIkony
      visible: obrazIkony.status === Image.Ready
      color: pozycja.enabled ? t.mainTextColor : t.secondaryTextColor
    }

    Text {
      Layout.fillWidth: true
      visible: !pozycja.tylkoIkona
      text: pozycja.text
      font: pozycja.font
      color: pozycja.enabled ? t.mainTextColor : t.secondaryTextColor
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignLeft
      verticalAlignment: Text.AlignVCenter
    }
  }
}
