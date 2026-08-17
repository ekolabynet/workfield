import io, os, sys
Z = [
 # 1. Jeden kreator dla obu platform — desktop przestaje otwierac Magazyn.
 ('src/app/qml/qgismobileapp.qml',
  '    nowyZSzablonu: function () {\n'
  '      if (Qt.platform.os === "android" || Qt.platform.os === "ios")\n'
  '        noweZadanie.open();\n'
  '      else\n'
  '        dashBoard.otworzSekcje(0);\n'
  '    }\n',
  '    // WorkField: jeden kreator na obu platformach. Wczesniej komputer\n'
  '    // otwieral sekcje Magazyn i trzeba bylo szukac dalej.\n'
  '    nowyZSzablonu: function () { noweZadanie.open(); }\n',
  'jeden kreator na obu platformach'),
 # 2. Jeden korzen zadan — regula magazynu zamiast "Imported Projects".
 ('src/app/qml/QfNoweZadanie.qml',
  '    if (katalogProjektow === "")\n      katalogProjektow = iface.dataRoot() + "Imported Projects";\n',
  '    if (katalogProjektow === "")\n'
  '      katalogProjektow = NarzedziaProjektu.katalogZadan(iface.dataRoot());\n'
  '    if (katalogProjektow === "")\n'
  '      katalogProjektow = iface.dataRoot() + "Imported Projects";\n',
  'NarzedziaProjektu.katalogZadan(iface.dataRoot())'),
 # 3. Koniec czynnosci opartych na procesach zewnetrznych (decyzja 17.08).
 ('src/app/qml/QfStudioSection.qml',
  '''    QfPozycjaMenu {
      text: qsTr("Zbuduj projekt")
      ikona: "wfg_zbuduj"
      enabled: studio.wybrany && !procesy.dziala
      onClicked: {
        zapis.dopisz(qsTr("Buduję %1 ...").arg(studio.wybrany.nazwa));
        procesy.uruchomPyQgis(studio.wybrany.sciezka + "/zbuduj_projekt.py");
      }
    }
''',
  '''    // WorkField 17.08.2026: "Zbuduj projekt" USUNIETE. Uruchamialo
    // zbuduj_projekt.py z katalogu szablonu — drugi krok starego swiata,
    // wymagajacy QGIS-a z Pythonem. Projekt z przepisu powstaje kompletny
    // od razu, wiec ta czynnosc nie ma juz czego robic. docs/WYPOSAZENIE.md
''',
  'Zbuduj projekt" USUNIETE'),
 ('src/app/qml/QfStudioSection.qml',
  '''    QfPozycjaMenu {
      text: qsTr("Wyślij na telefon")
      ikona: "wfg_wyslij"
      enabled: studio.wybrany && !procesy.dziala
      onClicked: {
        // droga udowodniona na obecnym APK: zip -> karta -> import z przeglądarki
        const p = studio.wybrany.sciezka;
        const n = studio.wybrany.nazwa;
        zapis.dopisz(qsTr("Pakuję i wysyłam %1 ...").arg(n));
        procesy.uruchomPowloke("set -e; cd '" + p + "'"
          + " && zip -qr '/tmp/" + n + ".zip' . -x 'archiwum/*' '.kosz/*'"
          + " && adb push '/tmp/" + n + ".zip' '" + ustawieniaStudia.telefonKarta + "'"
          + " && echo 'Na telefonie: przeglądarka plików -> WorkField/data -> " + n + ".zip -> import.'");
      }
    }
''',
  '''    // WorkField 17.08.2026: "Wyslij na telefon" USUNIETE. Pakowalo zipem
    // przez powloke i wolalo adb — zalezne od zainstalowanego adb, wpietego
    // kabla i sciezki do karty. Dublowalo natywne "Wyslij w teren"
    // (QfWymianaLokalna), ktore dziala bez zadnego z tych trzech warunkow.
''',
  'Wyslij na telefon" USUNIETE'),
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
    k = plik + '.przed_sprzataniem'
    if not os.path.exists(k): io.open(k,'w',encoding='utf-8').write(orig[plik])
    io.open(plik,'w',encoding='utf-8').write(nowa); print('zapisano', plik)
print('\nGotowe.')
