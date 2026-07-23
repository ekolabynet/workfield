#!/usr/bin/env bash
set -euo pipefail

FILE="src/qml/qgismobileapp.qml"
MARKER="footer: TabBar"

[[ -f "$FILE" ]] || { echo "Brak $FILE — uruchom z katalogu QField."; exit 1; }

if grep -q "$MARKER" "$FILE"; then
  echo "Stopka już istnieje — nic nie zmieniam."
  exit 0
fi

cp "$FILE" "$FILE.bak"

awk '
  !done && /Material\.accent: Theme\.mainColor/ {
    print
    print ""
    print "  footer: TabBar {"
    print "    id: mainNav"
    print "    width: parent.width"
    print ""
    print "    TabButton {"
    print "      text: qsTr(\"Mapa\")"
    print "    }"
    print "    TabButton {"
    print "      text: qsTr(\"Warstwy\")"
    print "    }"
    print "    TabButton {"
    print "      text: qsTr(\"Dane\")"
    print "    }"
    print "  }"
    done = 1
    next
  }
  { print }
' "$FILE.bak" > "$FILE"

grep -q "$MARKER" "$FILE" || { echo "Wstawka nie powiodła się — przywracam."; mv "$FILE.bak" "$FILE"; exit 1; }

echo "Wstawiono stopkę. Kopia: $FILE.bak"
