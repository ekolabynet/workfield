
#!/usr/bin/env bash
set -euo pipefail
SM="src/qml/SideMenu.qml"

sed -i \
  -e 's/^        action: /        actionId: /' \
  -e 's/^        icon: /        iconName: /' \
  -e 's/required property string action$/required property string actionId/' \
  -e 's/required property string icon$/required property string iconName/' \
  -e 's/entry\.action/entry.actionId/g' \
  -e 's/entry\.icon/entry.iconName/g' \
  "$SM"

grep -n "actionId\|iconName" "$SM"
