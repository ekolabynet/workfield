import io, os, sys
BLOK_DRAWER = '''      MultiEffect {
        // barwienie ikony kolorem tekstu motywu: jasne w ciemnym, ciemne w jasnym
        Layout.leftMargin: 6
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        source: obrazIkony
        colorization: 1.0
        colorizationColor: t.mainTextColor
        opacity: pozycja.enabled ? 1.0 : 0.4
      }
'''
NOWY_DRAWER = '''      ColorOverlay {
        // MultiEffect.colorization BARWI, ZACHOWUJAC JASNOSC — ciemna ikona
        // Breeze zostawala ciemna takze w ciemnym motywie (17.08.2026).
        // ColorOverlay zamienia piksele na podany kolor, zachowujac alfe.
        Layout.leftMargin: 6
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        source: obrazIkony
        color: pozycja.enabled ? t.mainTextColor : t.secondaryTextColor
      }
'''
BLOK_STUDIO = '''      MultiEffect {
        // barwienie ikony kolorem tekstu motywu: jasne w ciemnym, ciemne w jasnym
        Layout.leftMargin: 6
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        source: obrazIkony
        colorization: 1.0
        colorizationColor: Theme.mainTextColor
        opacity: pozycja.enabled ? 1.0 : 0.4
      }
'''
NOWY_STUDIO = NOWY_DRAWER.replace('t.mainTextColor', 'Theme.mainTextColor').replace('t.secondaryTextColor', 'Theme.secondaryTextColor')
Z = [
 ('src/app/qml/QfMainDrawer.qml', 'import QtQuick\n', 'import QtQuick\nimport Qt5Compat.GraphicalEffects\n', 'Qt5Compat.GraphicalEffects'),
 ('src/app/qml/QfMainDrawer.qml', BLOK_DRAWER, NOWY_DRAWER, 'ColorOverlay {'),
 ('src/app/qml/QfStudioSection.qml', 'import QtQuick\n', 'import QtQuick\nimport Qt5Compat.GraphicalEffects\n', 'Qt5Compat.GraphicalEffects'),
 ('src/app/qml/QfStudioSection.qml', BLOK_STUDIO, NOWY_STUDIO, 'ColorOverlay {'),
]
orig, plan, zrobie, pomijam = {}, {}, [], []
for p in {z[0] for z in Z}:
    if not os.path.exists(p): sys.exit('Brak pliku: ' + p)
    orig[p] = io.open(p, encoding='utf-8').read()
for plik, stare, nowe, zn in Z:
    t = plan.get(plik, orig[plik])
    if zn in t: pomijam.append('%s: %s' % (plik, zn)); continue
    n = t.count(stare)
    if n != 1: sys.exit('KONIEC BEZ ZMIAN: w %s fragment wystepuje %d razy:\n---\n%s---' % (plik, n, stare))
    plan[plik] = t.replace(stare, nowe, 1); zrobie.append('%s: %s' % (plik, zn))
for o in zrobie:  print('  ZROBIE  ', o)
for o in pomijam: print('  pomijam ', o)
if not zrobie: print('\nNic do zrobienia.'); sys.exit(0)
for plik, nowa in plan.items():
    k = plik + '.przed_ikonami'
    if not os.path.exists(k): io.open(k,'w',encoding='utf-8').write(orig[plik])
    io.open(plik,'w',encoding='utf-8').write(nowa); print('zapisano', plik)
print('\nGotowe.')
