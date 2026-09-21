import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Theme

/**
 * WorkField 21.09.2026 — PRZEŁĄCZNIK UKŁADU POZYCJI, wspólny dla obu szuflad.
 *
 * Wyjęty z prawej szuflady, bo lewa miała własny — dwa znaki (▤/▦), dwa stany
 * i własne ustawienie WFGPanel/ukladMenu. Wybór jest jeden
 * (mainWindow.ukladPozycji), więc i przełącznik ma być jeden.
 *
 * Nazwy układów nie giną: schodzą do dymków, tak jak w samym układzie „ikony".
 */
RowLayout {
  id: przelacznik

  property var t: Theme

  spacing: 6

  Repeater {
    model: [
      {
        "etykieta": qsTr("Lista"),
        "ikona": "wfg_uklad_lista",
        "uklad": "lista"
      },
      {
        "etykieta": qsTr("Dwie kolumny"),
        "ikona": "wfg_uklad_dwie",
        "uklad": "dwie"
      },
      {
        "etykieta": qsTr("Kafelki"),
        "ikona": "wfg_uklad_kafelki",
        "uklad": "kafelki"
      },
      {
        "etykieta": qsTr("Same ikony"),
        "ikona": "wfg_uklad_ikony",
        "uklad": "ikony"
      }
    ]

    delegate: Button {
      required property var modelData

      readonly property bool wybrany: mainWindow.ukladPozycji === modelData.uklad

      Layout.fillWidth: true
      display: AbstractButton.IconOnly
      icon.source: przelacznik.t.getThemeVectorIcon(modelData.ikona)
      icon.width: 22
      icon.height: 22
      // Ikony motywu sa CIEMNE w pliku; `icon.color` je przemalowuje
      // (ta sama droga co QfToolButton). Wybrany jasniej niz reszta —
      // Material `highlighted` gubi sie w stylu pulpitowym (23.08).
      icon.color: wybrany ? przelacznik.t.mainTextColor : przelacznik.t.secondaryTextColor
      highlighted: wybrany
      // Nazwa nie ginie, tylko przenosi sie do dymka.
      ToolTip.text: modelData.etykieta
      ToolTip.visible: hovered
      ToolTip.delay: 400
      onClicked: mainWindow.ukladPozycji = modelData.uklad
    }
  }
}
