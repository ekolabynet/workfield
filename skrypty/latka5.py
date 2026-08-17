import io, os, sys
Z = [
 ('src/app/qml/QfMainDrawer.qml',
  '      Layout.preferredHeight: visible ? implicitHeight : 0\n      currentIndex: 1\n',
  '      Layout.preferredHeight: visible ? implicitHeight : 0\n      currentIndex: 1\n\n'
  '      // WorkField: menu (otworzSekcje) wymusza sekcje przez sekcjaWymuszona,\n'
  '      // ale na telefonie NIC jej nie zerowalo — stos zostawal na wymuszonej\n'
  '      // sekcji na zawsze i zakladki przestawaly cokolwiek zmieniac.\n'
  '      // Tapniecie zakladki zwalnia wymuszenie. Na komputerze ten TabBar\n'
  '      // jest niewidoczny i nigdy sie nie zmienia, wiec zmiana jest tam bezczynna.\n'
  '      onCurrentIndexChanged: dashBoard.sekcjaWymuszona = -1\n',
  'onCurrentIndexChanged: dashBoard.sekcjaWymuszona = -1'),
 ('src/app/qml/qgismobileapp.qml',
  '    otworzZMagazynu: function () { dashBoard.otworzSekcje(0); }\n',
  '    // WorkField: sekcja Magazyn (0) istnieje tylko na komputerze\n'
  '    // (QfMainDrawer: Loader active tylko poza Androidem). Na telefonie\n'
  '    // ta czynnosc otwiera przegladarke projektow, zamiast pustej sekcji.\n'
  '    otworzZMagazynu: function () {\n'
  '      if (Qt.platform.os === "android" || Qt.platform.os === "ios") {\n'
  '        qfieldLocalDataPickerScreen.projectFolderView = false;\n'
  '        qfieldLocalDataPickerScreen.visible = true;\n'
  '      } else {\n'
  '        dashBoard.otworzSekcje(0);\n'
  '      }\n'
  '    }\n',
  'sekcja Magazyn (0) istnieje tylko na komputerze'),
]
orig, plan, zrobie, pomijam = {}, {}, [], []
for p in {z[0] for z in Z}:
    if not os.path.exists(p): sys.exit('Brak pliku: ' + p)
    orig[p] = io.open(p, encoding='utf-8').read()
for plik, stare, nowe, zn in Z:
    t = plan.get(plik, orig[plik])
    if zn in t: pomijam.append(zn); continue
    n = t.count(stare)
    if n != 1: sys.exit('KONIEC BEZ ZMIAN: w %s fragment wystepuje %d razy:\n---\n%s---' % (plik, n, stare))
    plan[plik] = t.replace(stare, nowe, 1); zrobie.append('%s: %s' % (plik, zn[:50]))
for o in zrobie:  print('  ZROBIE  ', o)
for o in pomijam: print('  pomijam ', o)
if not zrobie: print('\nNic do zrobienia.'); sys.exit(0)
for plik, nowa in plan.items():
    k = plik + '.przed_wyposazeniem5'
    if not os.path.exists(k): io.open(k,'w',encoding='utf-8').write(orig[plik])
    io.open(plik,'w',encoding='utf-8').write(nowa); print('zapisano', plik)
print('\nGotowe.')
