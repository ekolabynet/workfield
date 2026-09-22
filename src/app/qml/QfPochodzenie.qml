import QtQuick
import QtQuick.Layouts

/**
 * WorkFieldGIS 22.09.2026 — skąd się ten program wziął.
 *
 * JEDNA definicja, dwa miejsca użycia: ekran „Jak zacząć?" i okno
 * „Co nowego". Powód wyjęcia do osobnego pliku jest ten sam co przy
 * QfPozycjaMenu: zdanie o pochodzeniu musi brzmieć tak samo w obu
 * miejscach, a dwie kopie rozjeżdżają się przy pierwszej poprawce.
 *
 * NIE IMPORTUJE ANI MOTYWU, ANI `org.qfield.core`. Numer QGIS-a i barwy
 * dostaje z zewnątrz — dzięki temu ten sam komponent wchodzi w ciemną
 * skórę powitania i w jasny motyw okna zmian, i daje się obejrzeć osobno.
 *
 * Wersja QFielda jest WPISANA przy instalacji łatki (policzona z gita:
 * `git describe --tags` na `git merge-base HEAD upstream/master`), bo
 * w gotowej aplikacji nie ma już z czego jej odczytać. Pusta = zdanie
 * mówi po prostu „fork QFielda", bez numeru — lepiej bez liczby niż
 * z liczbą zmyśloną.
 */
Text {
  id: pochodzenie

  //! Wersja upstreamowego QFielda, na której stoi ten fork. Pusta = pomiń.
  //! WPISYWANA PRZY INSTALACJI ŁATKI — nie da się jej odczytać w działającej
  //! aplikacji, a `id` z QgisMobileapp.qml nie sięga do wnętrza tego pliku
  //! (zasięg identyfikatorów kończy się na granicy komponentu).
  property string wersjaQField: "z 22.08.2026 (tuż przed wydaniem 4.3)"
  //! Wersja silnika QGIS — z `Qfield.qgisVersion`, podawana przez wołającego.
  property string wersjaQGIS: ""
  property color barwaTekstu: "#9FC3BE"
  property color barwaLinku: "#A8E86A"
  property int rozmiar: 11

  Layout.fillWidth: true
  wrapMode: Text.WordWrap
  textFormat: Text.RichText
  color: barwaTekstu
  font.pointSize: rozmiar
  lineHeight: 1.15

  //! `<a>` bierze kolor z `linkColor`, nie z `color` — bez tego odsyłacze
  //! zostają niebieskie z przeglądarki i na ciemnym tle prawie ich nie widać.
  linkColor: barwaLinku

  onLinkActivated: link => Qt.openUrlExternally(link)

  text: {
    const qf = pochodzenie.wersjaQField !== "" ? " " + pochodzenie.wersjaQField : "";
    const qgis = pochodzenie.wersjaQGIS !== "" ? " " + pochodzenie.wersjaQGIS : "";
    return qsTr("<b>WorkFieldGIS</b> jest forkiem <a href=\"https://qfield.org/\">QFielda</a>%1 — mobilnego GIS-u firmy OPENGIS.ch — a ten stoi na silniku <a href=\"https://qgis.org/\">QGIS</a>%2. Wszystko, co tu widać, jest nadbudową nad ich pracą.<br><br>WorkFieldGIS <b>nie jest tworzony ani wspierany przez projekt QField</b>. Uwagi o tej aplikacji zgłaszaj do nas, nigdy do nich. Jeśli sam QField wystarcza do Twojej pracy — używaj QFielda, jest dojrzalszy i szerzej sprawdzony.").arg(qf).arg(qgis);
  }
}
