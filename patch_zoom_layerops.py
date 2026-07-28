#!/usr/bin/env python3
# Patch: "Powieksz do danych" w siatce projektu + operacje na wybranej warstwie pod lista
# Uruchom z korzenia repo: python3 patch_zoom_layerops.py
import sys

p = 'src/qml/QfMainDrawer.qml'
s = open(p).read()
if 'zoomToProjectData' in s:
    print('JUZ ZAAPLIKOWANE - nic nie robie')
    sys.exit(0)

# 1. przycisk w siatce za "Ekran startowy"
anchor = 'text: qsTr("Ekran startowy")'
assert s.count(anchor) == 1, 'kotwica ekranu startowego'
i = s.index(anchor)
btn_open = s.rindex('Button {', 0, i)
k = s.index('{', btn_open + 6); depth = 1; j = k + 1
while depth > 0:
    if s[j] == '{': depth += 1
    elif s[j] == '}': depth -= 1
    j += 1
zoom_btn = '''
        Button {
          Layout.fillWidth: true
          text: qsTr("Powi\\u0119ksz do danych")
          font.pointSize: t.tinyFont.pointSize
          onClicked: {
            if (!iface.zoomToProjectData(dashBoard.mapSettings)) {
              displayToast(qsTr("Brak warstw z danymi do powi\\u0119kszenia"), "warning");
            }
            dashBoard.close();
          }
        }
'''
s = s[:j] + zoom_btn + s[j:]

# 2. wiersz operacji po zamknieciu ListView projectLayersList
lp = s.index('id: projectLayersList')
lv = s.rindex('ListView {', 0, lp)
k = s.index('{', lv + 8); depth = 1; j = k + 1
while depth > 0:
    if s[j] == '{': depth += 1
    elif s[j] == '}': depth -= 1
    j += 1
ops = '''

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 8
          Layout.rightMargin: 8
          spacing: 8

          Button {
            Layout.fillWidth: true
            text: qsTr("Pola")
            font.pointSize: t.tinyFont.pointSize
            enabled: dashBoard.activeLayer !== null && dashBoard.activeLayer !== undefined
            onClicked: layerFieldsScreen.openFor(dashBoard.activeLayer)
          }

          Button {
            Layout.fillWidth: true
            text: qsTr("Eksportuj")
            font.pointSize: t.tinyFont.pointSize
            enabled: dashBoard.activeLayer !== null && dashBoard.activeLayer !== undefined
            onClicked: {
              dashBoard.close();
              exportDialog.openFor(dashBoard.activeLayer);
            }
          }

          Button {
            Layout.fillWidth: true
            text: qsTr("Usu\\u0144")
            font.pointSize: t.tinyFont.pointSize
            enabled: dashBoard.activeLayer !== null && dashBoard.activeLayer !== undefined
            onClicked: {
              removeLayerConfirm.targetLayer = dashBoard.activeLayer;
              removeLayerConfirm.targetName = dashBoard.activeLayer.name;
              removeLayerConfirm.open();
            }
          }
        }
'''
s = s[:j] + ops + s[j:]
open(p, 'w').write(s)
print('ok, balans:', s.count('{') - s.count('}'))
