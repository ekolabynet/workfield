import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

/**
 * WorkFieldGIS 23.10.2026 [WF-BUTTONS] — one look for every decision button.
 *
 * Piotr, 23.10 18:52: "Ujednolićmy wszystko na kolorowo."
 *   role "confirm" — green  (#43a047): OK, Utwórz, Zapisz, Przenieś…
 *   role "cancel"  — orange (#fb8c00): Anuluj, Zamknij, Później
 *   role "danger"  — red    (#e53935): Usuń — only what cannot be undone
 * Same colours as QfDialog's OK / Cancel. Every press vibrates with the
 * strength from Teren → Wibracje (0 = off).
 *
 * \ingroup qml
 */
Button {
  id: decisionButton

  property string role: "confirm"

  readonly property color fill: role === "danger" ? "#e53935" : ((role === "cancel" || role === "neutral") ? "#fb8c00" : "#43a047")

  Material.background: fill
  Material.foreground: "white"
  palette.button: fill
  palette.buttonText: "white"
  opacity: enabled ? 1.0 : 0.5

  onPressed: {
    const strength = typeof settings !== "undefined" ? settings.valueInt("WorkField/haptykaSila", 3) : 3;
    if (strength > 0 && typeof platformUtilities !== "undefined")
      platformUtilities.vibrate((role === "confirm" || role === "danger" ? 60 : 30) * strength);
    // [WF-SOUNDS] OK / Anuluj / Usuń
    if (typeof dzwieki !== "undefined")
      dzwieki.zagraj(role === "danger" ? "usun" : ((role === "cancel" || role === "neutral") ? "anuluj" : "ok"), false);
  }
}
