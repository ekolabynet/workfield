import io, os, sys, json
Z = json.loads('[["src/app/qml/QfMainDrawer.qml", "            MultiEffect {\\n              Layout.preferredWidth: 16\\n              Layout.preferredHeight: 16\\n              source: ikonaWidoku\\n              colorization: 1.0\\n              colorizationColor: przelacznikWidoku.aktywny ? \\"white\\" : Theme.mainTextColor\\n              brightness: 0.2\\n            }\\n", "            ColorOverlay {\\n              // MultiEffect.colorization zachowuje jasnosc \\u2014 ciemna ikona\\n              // Breeze zostawala ciemna takze w ciemnym motywie (17.08.2026).\\n              Layout.preferredWidth: 16\\n              Layout.preferredHeight: 16\\n              source: ikonaWidoku\\n              visible: ikonaWidoku.status === Image.Ready\\n              color: przelacznikWidoku.aktywny ? \\"white\\" : Theme.mainTextColor\\n            }\\n", "visible: ikonaWidoku.status === Image.Ready"]]')
orig, plan, zrobie, pomijam = {}, {}, [], []
for p in {z[0] for z in Z}:
    if not os.path.exists(p): sys.exit('Brak pliku: ' + p)
    orig[p] = io.open(p, encoding='utf-8').read()
for plik, stare, nowe, zn in Z:
    t = plan.get(plik, orig[plik])
    if zn in t: pomijam.append(plik + ': ' + zn); continue
    n = t.count(stare)
    if n != 1: sys.exit('KONIEC BEZ ZMIAN: w ' + plik + ' fragment wystepuje ' + str(n) + ' razy')
    plan[plik] = t.replace(stare, nowe, 1); zrobie.append(plik + ': ' + zn)
for o in zrobie:  print('  ZROBIE  ', o)
for o in pomijam: print('  pomijam ', o)
if not zrobie: print('\nNic do zrobienia.'); sys.exit(0)
for plik, nowa in plan.items():
    k = plik + '.przed_ikonami2'
    if not os.path.exists(k): io.open(k,'w',encoding='utf-8').write(orig[plik])
    io.open(plik,'w',encoding='utf-8').write(nowa); print('zapisano', plik)
print('\nGotowe.')
