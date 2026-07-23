#!/usr/bin/env bash
set -euo pipefail

SRC="src/qml/QFieldSettings.qml"
DEST_DIR="src/qml/settings"
DEST="$DEST_DIR/SettingsNetwork.qml"
QRC="src/qml/qml.qrc"

[[ -f "$SRC" ]] || { echo "Uruchom z katalogu QField."; exit 1; }
grep -q "SettingsNetwork" "$SRC" && { echo "Już zastosowane."; exit 0; }

# --- granice bloku -------------------------------------------------
NET_LABEL=$(grep -n "text: qsTr('Network')" "$SRC" | head -1 | cut -d: -f1)
ADV_LABEL=$(grep -n "text: qsTr('Advanced')" "$SRC" | head -1 | cut -d: -f1)

START=$(awk -v n="$NET_LABEL" 'NR<n && /^            GridLayout \{$/ {l=NR} END {print l}' "$SRC")
ADV_START=$(awk -v n="$ADV_LABEL" 'NR<n && /^            GridLayout \{$/ {l=NR} END {print l}' "$SRC")
END=$((ADV_START - 1))

[[ -n "$START" && "$END" -gt "$START" ]] || { echo "Nie rozpoznano granic."; exit 1; }
echo "Blok Network: $START..$END ($((END-START+1)) linii)"

mkdir -p "$DEST_DIR"

# --- nowy komponent ------------------------------------------------
{
  cat << 'EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import org.qfield
import Theme

/**
 * Ustawienia sieciowe: uwierzytelnianie i proxy.
 * `page` wskazuje na QFieldSettings — stamtąd pochodzą właściwości proxy.
 */
EOF
  sed -n "${START},${END}p" "$SRC" | sed 's/^            //'
} > "$DEST"

# wstrzyknięcie property page tuż po otwarciu GridLayout
sed -i '0,/^GridLayout {$/s//GridLayout {\n  property var page\n/' "$DEST"

# przekierowanie odwołań na page.*
sed -i -E 's/\b(proxyEnabled|proxyType|proxyHost|proxyPort|proxyUser|proxyPassword|proxyExcludedUrls|proxySettingsLoaded|applyProxySettings)\b/page.\1/g' "$DEST"
# cofnięcie tam, gdzie to własne id lub deklaracja
sed -i -E 's/id: page\./id: /g; s/page\.page\./page./g' "$DEST"

echo "Utworzono $DEST"

# --- podmiana w pliku źródłowym ------------------------------------
{
  head -n $((START - 1)) "$SRC"
  cat << 'EOF'
            SettingsNetwork {
              Layout.fillWidth: true
              page: page
            }
EOF
  tail -n +$((END + 1)) "$SRC"
} > "$SRC.tmp" && mv "$SRC.tmp" "$SRC"

# --- rejestracja ---------------------------------------------------
if [[ -f "$QRC" ]] && ! grep -q "SettingsNetwork" "$QRC"; then
  sed -i 's|<file>QFieldSettings.qml</file>|<file>QFieldSettings.qml</file>\n        <file>settings/SettingsNetwork.qml</file>|' "$QRC"
  grep -q "SettingsNetwork" "$QRC" && echo "Zarejestrowano w $QRC" || echo "UWAGA: dodaj ręcznie do $QRC"
fi

echo "Gotowe. Cofnięcie: git checkout $SRC $QRC && rm -rf $DEST_DIR"
