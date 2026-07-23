#!/usr/bin/env bash
set -euo pipefail

DB="src/qml/DashBoard.qml"
SM="src/qml/SideMenu.qml"
QRC="src/qml/qml.qrc"

[[ -f "$DB" ]] || { echo "Uruchom z katalogu QField."; exit 1; }
grep -q "SideMenu {" "$DB" && { echo "Już zastosowane."; exit 0; }

# ---------- 1. nowy komponent ----------
cat > "$SM" << 'EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Theme

/**
 * Pionowe menu boczne: ikona + podpis.
 */
Column {
  id: sideMenu

  signal actionTriggered(string action, point origin)

  spacing: 0

  Repeater {
    model: ListModel {
      ListElement {
        action: "measurement"
        icon: "ic_measurement_black_24dp"
      }
      ListElement {
        action: "view3d"
        icon: "ic_3d_white_24dp"
      }
      ListElement {
        action: "print"
        icon: "ic_print_black_24dp"
      }
      ListElement {
        action: "projectFolder"
        icon: "ic_project_folder_black_24dp"
      }
      ListElement {
        action: "mainMenu"
        icon: "ic_dot_menu_black_24dp"
      }
    }

    delegate: ItemDelegate {
      id: entry
      width: sideMenu.width
      height: 52

      required property string action
      required property string icon

      contentItem: RowLayout {
        spacing: 16

        Image {
          Layout.preferredWidth: 28
          Layout.preferredHeight: 28
          Layout.leftMargin: 8
          source: Theme.getThemeVectorIcon(entry.icon)
          sourceSize.width: 28
          sourceSize.height: 28
          fillMode: Image.PreserveAspectFit
        }

        Text {
          Layout.fillWidth: true
          text: {
            switch (entry.action) {
            case "measurement":
              return qsTr("Pomiar");
            case "view3d":
              return qsTr("Widok 3D");
            case "print":
              return qsTr("Wydruki");
            case "projectFolder":
              return qsTr("Folder projektu");
            case "mainMenu":
              return qsTr("Menu główne");
            }
            return "";
          }
          font: Theme.defaultFont
          color: Theme.mainTextColor
          elide: Text.ElideRight
        }
      }

      onClicked: {
        const p = entry.mapToItem(mainWindow.contentItem, entry.width, 0);
        sideMenu.actionTriggered(entry.action, p);
      }
    }
  }
}
EOF
echo "Utworzono $SM"

# ---------- 2. rejestracja w qrc ----------
if [[ -f "$QRC" ]] && ! grep -q "SideMenu.qml" "$QRC"; then
  sed -i '0,#<file>DashBoard.qml</file>#s##<file>DashBoard.qml</file>\n        <file>SideMenu.qml</file>#' "$QRC" 2>/dev/null \
    || sed -i 's|<file>DashBoard.qml</file>|<file>DashBoard.qml</file>\n        <file>SideMenu.qml</file>|' "$QRC"
  grep -q "SideMenu.qml" "$QRC" && echo "Zarejestrowano w $QRC" || echo "UWAGA: dodaj SideMenu.qml do $QRC ręcznie"
fi

# ---------- 3. wyznaczenie granic bloku ----------
COL=$(grep -n "^  ColumnLayout {" "$DB" | head -1 | cut -d: -f1)
START=$(awk -v c="$COL" 'NR>c && /^    Rectangle \{/ {print NR; exit}' "$DB")
PIL=$(grep -n "id: projectInformationLayout" "$DB" | head -1 | cut -d: -f1)
END=$((PIL - 2))

[[ -n "$START" && "$END" -gt "$START" ]] || { echo "Nie rozpoznano granic bloku."; exit 1; }
echo "Podmieniam linie $START..$END"

# ---------- 4. podmiana ----------
{
  head -n $((START - 1)) "$DB"
  cat << 'EOF'
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: mainWindow.sceneTopMargin + 56
      color: "transparent"

      QfToolButton {
        id: closeButton
        anchors.left: parent.left
        anchors.leftMargin: mainWindow.sceneLeftMargin
        anchors.bottom: parent.bottom
        iconSource: Theme.getThemeVectorIcon('ic_arrow_left_white_24dp')
        iconColor: Theme.mainTextColor
        bgcolor: "transparent"
        onClicked: close()
      }
    }

    SideMenu {
      id: sideMenu
      Layout.fillWidth: true
      Layout.leftMargin: mainWindow.sceneLeftMargin

      onActionTriggered: (action, origin) => {
        switch (action) {
        case "measurement":
          toggleMeasurementTool();
          break;
        case "view3d":
          toggle3DView();
          break;
        case "print":
          showPrintLayouts(origin);
          break;
        case "projectFolder":
          showProjectFolder();
          break;
        case "mainMenu":
          showMainMenu(origin);
          break;
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Theme.controlBorderColor
    }
EOF
  tail -n +$((END + 1)) "$DB"
} > "$DB.tmp" && mv "$DB.tmp" "$DB"

# ---------- 5. gest przeciągania ----------
sed -i 's|^  interactive: allowInteractive && buttonsRowContainer.width >= buttonsRow.width$|  interactive: allowInteractive|' "$DB"

echo "Gotowe. Cofnięcie: git checkout $DB \&\& rm $SM"
