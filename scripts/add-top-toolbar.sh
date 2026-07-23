#!/usr/bin/env bash
set -euo pipefail

FILE="src/qml/qgismobileapp.qml"
MARKER="header: ToolBar"

[[ -f "$FILE" ]] || { echo "Brak $FILE — uruchom z katalogu QField."; exit 1; }

if grep -q "$MARKER" "$FILE"; then
  echo "Pasek już istnieje — nic nie zmieniam."
  exit 0
fi

# --- wykrycie ikon -------------------------------------------------
pick_icon() {
  local pattern="$1" fallback="$2" found
  found=$(find images -name "ic_*${pattern}*white*24dp.svg" -printf '%f\n' 2>/dev/null | head -1)
  [[ -n "$found" ]] && echo "${found%.svg}" || echo "$fallback"
}

ICON_LEFT=$(pick_icon "layers" "ic_baseline-list_white_24dp")
ICON_RIGHT=$(pick_icon "settings" "ic_baseline-list_white_24dp")

echo "Ikona lewa:  $ICON_LEFT"
echo "Ikona prawa: $ICON_RIGHT"

BACKUP="/tmp/qgismobileapp.qml.$(date +%s).bak"
cp "$FILE" "$BACKUP"

# --- import QtQuick.Layouts ----------------------------------------
if ! grep -q "^import QtQuick.Layouts$" "$FILE"; then
  sed -i '0,/^import QtQuick.Controls$/s//import QtQuick.Controls\nimport QtQuick.Layouts/' "$FILE"
  echo "Dopisano import QtQuick.Layouts"
fi

# --- wstawka header: ToolBar ---------------------------------------
awk -v il="$ICON_LEFT" -v ir="$ICON_RIGHT" '
  !done && /Material\.accent: Theme\.mainColor/ {
    print
    print ""
    print "  header: ToolBar {"
    print "    id: mainToolBar"
    print "    height: 64"
    print "    Material.background: Theme.mainColor"
    print ""
    print "    RowLayout {"
    print "      anchors.fill: parent"
    print "      spacing: 0"
    print ""
    print "      ToolButton {"
    print "        Layout.preferredWidth: 64"
    print "        Layout.preferredHeight: 64"
    print "        icon.source: Theme.getThemeVectorIcon(\"" il "\")"
    print "        icon.width: 32"
    print "        icon.height: 32"
    print "        icon.color: \"white\""
    print "        onClicked: dashBoard.opened ? dashBoard.close() : dashBoard.open()"
    print "      }"
    print ""
    print "      Item {"
    print "        Layout.fillWidth: true"
    print "      }"
    print ""
    print "      ToolButton {"
    print "        Layout.preferredWidth: 64"
    print "        Layout.preferredHeight: 64"
    print "        icon.source: Theme.getThemeVectorIcon(\"" ir "\")"
    print "        icon.width: 32"
    print "        icon.height: 32"
    print "        icon.color: \"white\""
    print "      }"
    print "    }"
    print "  }"
    done = 1
    next
  }
  { print }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

if grep -q "$MARKER" "$FILE"; then
  echo "Wstawiono górny pasek. Kopia: $BACKUP"
else
  echo "Wstawka nie powiodła się — przywracam."
  cp "$BACKUP" "$FILE"
  exit 1
fi
