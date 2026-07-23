#!/usr/bin/env bash
set -euo pipefail
# użycie: bash scripts/extract-section.sh 'Advanced' SettingsAdvanced advancedSettingsModel

SECTION="$1"; COMP="$2"; MODEL="$3"
SRC="src/qml/QFieldSettings.qml"
DEST="src/qml/${COMP}.qml"
QRC="src/qml/qml.qrc"

grep -q "$COMP" "$SRC" && { echo "Już wydzielone."; exit 0; }

LABEL=$(grep -n "text: qsTr('${SECTION}')" "$SRC" | head -1 | cut -d: -f1)
START=$(awk -v n="$LABEL" 'NR<n && /^            GridLayout \{$/ {l=NR} END {print l}' "$SRC")
END=$(awk -v n="$LABEL" -v m="$MODEL" 'NR>n && $0 ~ ("model: " m) {f=1} f && /^            \}$/ {print NR; exit}' "$SRC")

[[ -n "$START" && -n "$END" && "$END" -gt "$START" ]] || { echo "Nie rozpoznano granic ($START..$END)."; exit 1; }
echo "$SECTION: $START..$END"

{
  cat << EOF
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

Column {
  property var page
  property var registry
  property var settingsModel
  property Component listItem

EOF
  sed -n "${START},${END}p" "$SRC" | sed 's/^            /  /'
  echo "}"
} > "$DEST"

sed -i "s/model: ${MODEL}/model: settingsModel/" "$DEST"

{
  head -n $((START - 1)) "$SRC"
  cat << EOF
            ${COMP} {
              Layout.fillWidth: true
              page: page
              registry: registry
              settingsModel: ${MODEL}
              listItem: listItem
            }
EOF
  tail -n +$((END + 1)) "$SRC"
} > "$SRC.tmp" && mv "$SRC.tmp" "$SRC"

grep -q "$COMP" "$QRC" || sed -i "s|<file>QFieldSettings.qml</file>|<file>QFieldSettings.qml</file>\n        <file>${COMP}.qml</file>|" "$QRC"

echo "Utworzono $DEST"
