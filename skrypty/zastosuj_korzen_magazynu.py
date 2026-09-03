import io, os, sys, json
Z = json.loads('[["src/app/qml/QfNoweZadanie.qml", "import QtQuick\\nimport QtQuick.Controls\\n", "import QtQuick\\nimport QtCore\\nimport QtQuick.Controls\\n", "import QtCore"], ["src/app/qml/QfNoweZadanie.qml", "  signal utworzono(string sciezka)\\n", "  signal utworzono(string sciezka)\\n\\n  // WorkField: korzeniem jest MAGAZYN (~/WorkField), nie katalog aplikacji.\\n  // iface.dataRoot() na desktopie wskazuje \\"Dokumenty/QField Documents\\" \\u2014\\n  // zadania ladowaly tam zamiast w wydania/ (18.08.2026). Ta sama nastawa\\n  // co w Studiu, wiec \\"Zmien...\\" w magazynie zmienia oba naraz.\\n  Settings {\\n    id: ustawieniaMagazynu\\n    category: \\"WFGStudio\\"\\n    property string korzenProjektow: StandardPaths.writableLocation(StandardPaths.HomeLocation) + \\"/WorkField\\"\\n  }\\n\\n  function korzenMagazynu() {\\n    return ustawieniaMagazynu.korzenProjektow !== \\"\\" ? ustawieniaMagazynu.korzenProjektow : iface.dataRoot();\\n  }\\n", "function korzenMagazynu()"], ["src/app/qml/QfNoweZadanie.qml", "      katalogSzablonow = NarzedziaProjektu.katalogSzablonow(iface.dataRoot());\\n    if (katalogSzablonow === \\"\\")\\n      katalogSzablonow = iface.dataRoot() + \\"Szablony\\";\\n", "      katalogSzablonow = NarzedziaProjektu.katalogSzablonow(korzenMagazynu());\\n    if (katalogSzablonow === \\"\\")\\n      katalogSzablonow = NarzedziaProjektu.katalogSzablonow(iface.dataRoot());\\n    if (katalogSzablonow === \\"\\")\\n      katalogSzablonow = korzenMagazynu() + \\"/szablony\\";\\n", "katalogSzablonow(korzenMagazynu())"], ["src/app/qml/QfNoweZadanie.qml", "      katalogProjektow = NarzedziaProjektu.katalogZadan(iface.dataRoot());\\n    if (katalogProjektow === \\"\\")\\n      katalogProjektow = iface.dataRoot() + \\"Imported Projects\\";\\n", "      katalogProjektow = NarzedziaProjektu.katalogZadan(korzenMagazynu());\\n    if (katalogProjektow === \\"\\")\\n      katalogProjektow = iface.dataRoot() + \\"Imported Projects\\";\\n", "katalogZadan(korzenMagazynu())"], ["src/app/qml/QfMainDrawer.qml", "              const korzenSzablonow = NarzedziaProjektu.katalogSzablonow(iface.dataRoot());\\n", "              // korzeniem jest magazyn, nie katalog aplikacji \\u2014 patrz QfNoweZadanie\\n              const korzenSzablonow = NarzedziaProjektu.katalogSzablonow(ustawieniaStanu.korzenProjektow);\\n", "katalogSzablonow(ustawieniaStanu.korzenProjektow)"]]')
orig, plan, zrobie, pomijam = {}, {}, [], []
for p in {z[0] for z in Z}:
    if not os.path.exists(p): sys.exit('Brak pliku: ' + p)
    orig[p] = io.open(p, encoding='utf-8').read()
for plik, stare, nowe, zn in Z:
    t = plan.get(plik, orig[plik])
    if zn in t: pomijam.append(plik + ': ' + zn); continue
    n = t.count(stare)
    if n != 1: sys.exit('KONIEC BEZ ZMIAN: w ' + plik + ' fragment wystepuje ' + str(n) + ' razy:\n---\n' + stare + '---')
    plan[plik] = t.replace(stare, nowe, 1); zrobie.append(plik + ': ' + zn)
for o in zrobie:  print('  ZROBIE  ', o)
for o in pomijam: print('  pomijam ', o)
if not zrobie: print('\nNic do zrobienia.'); sys.exit(0)
for plik, nowa in plan.items():
    k = plik + '.przed_korzeniem'
    if not os.path.exists(k): io.open(k,'w',encoding='utf-8').write(orig[plik])
    io.open(plik,'w',encoding='utf-8').write(nowa); print('zapisano', plik)
print('\nGotowe.')
