#!/usr/bin/env bash
set -euo pipefail

FILE="src/qml/qgismobileapp.qml"
[[ -f "$FILE" ]] || { echo "Uruchom z katalogu QField."; exit 1; }

grep -q "id: mainToolBar" "$FILE" || { echo "Brak mainToolBar — najpierw dodaj górny pasek."; exit 1; }
grep -q "mainToolBar.*visible:" "$FILE" && { echo "Warunek już istnieje."; exit 0; }

# ekrany, które mają własny QfPageHeader
CANDIDATES="qfieldSettings qfieldLocalDataPickerScreen qfieldCloudScreen welcomeScreen aboutDialog codeReader sketcher"

COND=""
for id in $CANDIDATES; do
  if grep -q "id: $id$" "$FILE"; then
    COND="${COND}${COND:+ && }!${id}.visible"
    echo "  uwzględniam: $id"
  fi
done

[[ -n "$COND" ]] || { echo "Nie znaleziono żadnego ekranu."; exit 1; }

python3 - "$FILE" "$COND" << 'PY'
import sys
path, cond = sys.argv[1], sys.argv[2]
s = open(path).read()
old = "    id: mainToolBar\n    height: 64\n"
new = f"    id: mainToolBar\n    visible: {cond}\n    height: visible ? 64 : 0\n"
if old not in s:
    print("Nie dopasowano bloku mainToolBar — sprawdź ręcznie.")
    sys.exit(1)
open(path, 'w').write(s.replace(old, new, 1))
print("Dodano warunek widoczności.")
PY

grep -n "id: mainToolBar" -A3 "$FILE"
