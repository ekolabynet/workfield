import io, os, sys
Z = [
 ('src/app/CMakeLists.txt',
  '    qml/QfPrzepis.qml\n',
  '    qml/QfPrzepis.qml\n    qml/QfKontrolaProjektu.qml\n',
  'qml/QfKontrolaProjektu.qml'),
 ('src/app/qml/qgismobileapp.qml',
  '  QfPrzepis {\n',
  '  // WorkField: przy otwarciu projektu mowi glosno, czego mu brakuje.\n'
  '  // Etap 1 — tylko czyta. Patrz QfKontrolaProjektu.qml.\n'
  '  QfKontrolaProjektu {\n    id: kontrolaProjektu\n  }\n\n'
  '  QfPrzepis {\n',
  'QfKontrolaProjektu {'),
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
    plan[plik] = t.replace(stare, nowe, 1); zrobie.append('%s: %s' % (plik, zn))
for o in zrobie:  print('  ZROBIE  ', o)
for o in pomijam: print('  pomijam ', o)
if not zrobie: print('\nNic do zrobienia.'); sys.exit(0)
for plik, nowa in plan.items():
    k = plik + '.przed_kontrola'
    if not os.path.exists(k): io.open(k,'w',encoding='utf-8').write(orig[plik])
    io.open(plik,'w',encoding='utf-8').write(nowa); print('zapisano', plik)
print('\nGotowe.')
