#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 << 'PY'
import re
p = 'src/qml/QFieldSettings.qml'
src = open(p).read().split('\n')

def close_of(start):
    """zwraca indeks linii zamykającej blok otwarty w linii start (0-based)"""
    depth = 0
    for i in range(start, len(src)):
        depth += src[i].count('{') - src[i].count('}')
        if depth == 0 and i > start:
            return i
    raise RuntimeError('brak klamry')

# indeksy 0-based
tab_start = next(i for i,l in enumerate(src) if l.strip().startswith('QfTabBar {'))
tab_end   = close_of(tab_start)
sw_start  = next(i for i,l in enumerate(src) if l.strip() == 'SwipeView {')
sw_end    = close_of(sw_start)

items = [i for i in range(sw_start, sw_end) if src[i] == '      Item {']
assert len(items) == 3, items
gen, pos, var = items
pos_block = src[pos:close_of(pos)+1]
var_block = src[var:close_of(var)+1]

def as_component(name, block):
    body = '\n'.join('    ' + l.strip() if l.strip() else '' for l in block[1:-1])
    return f'''  Component {{
    id: {name}
    Item {{
{body}
    }}
  }}
'''

stack = '''    StackView {
      id: settingsStack
      Layout.fillHeight: true
      Layout.fillWidth: true
      clip: true

      initialItem: QfSettingsIndex {
        t: Theme
        onCategorySelected: categoryId => page.openCategory(categoryId)
      }
    }
'''

out = src[:tab_start] + src[tab_end+1:sw_start] + stack.split('\n') + src[sw_end+1:]

# wstaw komponenty tuż przed nagłówkiem header:
hdr = next(i for i,l in enumerate(out) if l.startswith('  header: QfPageHeader'))
comps = (as_component('positioningPage', pos_block) +
         as_component('variablesPage', var_block)).split('\n')
out = out[:hdr] + comps + out[hdr:]

# funkcja nawigacji
fn = '''  function openCategory(id) {
    settingsStack.push(categoryPage, {
      "categoryId": id
    });
  }

  Component {
    id: categoryPage
    Item {
      property string categoryId
      ScrollView {
        anchors.fill: parent
        topPadding: 5
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: QfScrollBar {}
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
          width: settingsStack.width

          QfSettingsMapCanvas {
            visible: categoryId === "mapCanvas"
            Layout.fillWidth: true
            settingsPage: page
            settingsRegistry: registry
            settingsModel: canvasSettingsModel
            rowDelegate: listItem
          }
          QfSettingsDigitizing {
            visible: categoryId === "digitizing"
            Layout.fillWidth: true
            settingsPage: page
            settingsRegistry: registry
            settingsModel: digitizingEditingSettingsModel
            rowDelegate: listItem
          }
          QfSettingsInterface {
            visible: categoryId === "interface"
            Layout.fillWidth: true
            settingsPage: page
            settingsRegistry: registry
            settingsModel: interfaceSettingsModel
            rowDelegate: listItem
            onOpenLocatorSettings: {
              locatorSettings.open();
              locatorSettings.focus = true;
            }
            onOpenPluginManager: pluginManagerSettings.open()
          }
          SettingsNetwork {
            id: networkSettings
            visible: categoryId === "network"
            Layout.fillWidth: true
            settingsPage: page
          }
          QfSettingsAdvanced {
            visible: categoryId === "advanced"
            Layout.fillWidth: true
            settingsPage: page
            settingsRegistry: registry
            settingsModel: advancedSettingsModel
            rowDelegate: listItem
          }
          Loader {
            active: categoryId === "positioning"
            Layout.fillWidth: true
            Layout.preferredHeight: settingsStack.height
            sourceComponent: positioningPage
          }
          Loader {
            active: categoryId === "variables"
            Layout.fillWidth: true
            Layout.preferredHeight: settingsStack.height
            sourceComponent: variablesPage
          }
        }
      }
    }
  }
'''
hdr = next(i for i,l in enumerate(out) if l.startswith('  header: QfPageHeader'))
out = out[:hdr] + fn.split('\n') + out[hdr:]

# nagłówek: pop zamiast finished, gdy stos głębszy
txt = '\n'.join(out)
txt = txt.replace('''    onFinished: {
      parent.finished();''', '''    onFinished: {
      if (settingsStack.depth > 1) {
        settingsStack.pop();
        return;
      }
      parent.finished();''')

open(p,'w').write(txt)
print('gotowe')
PY

grep -n "StackView\|Component {" src/qml/QFieldSettings.qml | head
