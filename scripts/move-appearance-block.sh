#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="src/qml/QFieldSettings.qml"
DEST="src/qml/QfSettingsInterface.qml"

grep -q "Dim screen when idling" "$DEST" && { echo "Już przeniesione."; exit 0; }

START=$(grep -n "^            GridLayout {$" "$SRC" | awk -F: '$1>420 {print $1; exit}')
END=$(awk -v s="$START" 'NR>s && /^            SettingsNetwork \{$/ {print NR-2; exit}' "$SRC")

[[ -n "$START" && -n "$END" && "$END" -gt "$START" ]] || { echo "Nie rozpoznano granic ($START..$END)."; exit 1; }
echo "Blok: $START..$END"

BLOCK=$(sed -n "${START},${END}p" "$SRC" | sed 's/^            /  /')

# wstaw przed ostatnią klamrą pliku docelowego
python3 - "$DEST" << PY
import sys
p = sys.argv[1]
lines = open(p).read().rstrip().split('\n')
assert lines[-1].strip() == '}', lines[-1]
block = '''$BLOCK'''
open(p,'w').write('\n'.join(lines[:-1]) + '\n\n' + block + '\n}\n')
PY

# usuń z pliku źródłowego
{ head -n $((START-1)) "$SRC"; tail -n +$((END+1)) "$SRC"; } > "$SRC.tmp" && mv "$SRC.tmp" "$SRC"

echo "Przeniesiono. Sprawdź languageComboBox w onLoad()."
grep -n "languageComboBox" "$SRC"
