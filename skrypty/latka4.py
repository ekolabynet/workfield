import io, os, sys
Z = [
 ('src/core/utils/narzedziaprojektu.h',
  '    Q_INVOKABLE QString katalogZadan( const QString &korzen ) const;\n',
  '    Q_INVOKABLE QString katalogZadan( const QString &korzen ) const;\n\n'
  '    /**\n'
  '     * Katalog z szablonami: pierwszy istniejacy z "Szablony", "szablony",\n'
  '     * "templates" pod \\a korzen; gdy zadnego nie ma — pusty string.\n'
  '     * Na telefonie korzen narzuca system, a nazwa katalogu bywa rozna\n'
  '     * w zaleznosci od tego, czym magazyn byl zakladany.\n'
  '     */\n'
  '    Q_INVOKABLE QString katalogSzablonow( const QString &korzen ) const;\n',
  'QString katalogSzablonow('),
 ('src/core/utils/narzedziaprojektu.cpp',
  'QString NarzedziaProjektu::katalogZadan( const QString &korzen ) const\n',
  'QString NarzedziaProjektu::katalogSzablonow( const QString &korzen ) const\n'
  '{\n'
  '  if ( korzen.isEmpty() )\n    return QString();\n\n'
  '  const QDir k( korzen );\n'
  '  const QStringList kandydaci = { QStringLiteral( "Szablony" ), QStringLiteral( "szablony" ),\n'
  '                                  QStringLiteral( "templates" ) };\n'
  '  for ( const QString &nazwa : kandydaci )\n'
  '  {\n'
  '    const QString sciezka = k.filePath( nazwa );\n'
  '    if ( QDir( sciezka ).exists() )\n      return sciezka;\n'
  '  }\n'
  '  return QString();\n'
  '}\n\n'
  'QString NarzedziaProjektu::katalogZadan( const QString &korzen ) const\n',
  'NarzedziaProjektu::katalogSzablonow'),
 ('src/app/qml/qgismobileapp.qml',
  '    nowyZSzablonu: function () { dashBoard.otworzSekcje(0); }\n',
  '    // WorkField: Studio jest na razie tylko desktopowe (QfStudioSection),\n'
  '    // wiec na telefonie ta sama czynnosc otwiera dialog QfNoweZadanie.\n'
  '    nowyZSzablonu: function () {\n'
  '      if (Qt.platform.os === "android" || Qt.platform.os === "ios")\n'
  '        noweZadanie.open();\n'
  '      else\n'
  '        dashBoard.otworzSekcje(0);\n'
  '    }\n',
  'Studio jest na razie tylko desktopowe'),
 ('src/app/qml/QfNoweZadanie.qml',
  '      katalogSzablonow = iface.dataRoot() + "Szablony";\n',
  '      katalogSzablonow = NarzedziaProjektu.katalogSzablonow(iface.dataRoot());\n'
  '    if (katalogSzablonow === "")\n'
  '      katalogSzablonow = iface.dataRoot() + "Szablony";\n',
  'NarzedziaProjektu.katalogSzablonow('),
 ('src/app/qml/QfNoweZadanie.qml',
  '    if (szablonWybrany === "") {\n',
  '    // WorkField: szablon z przepisem budujemy od zera z aktualnego\n'
  '    // wyposazenia. Interpreter sam wczytuje gotowy projekt, wiec NIE\n'
  '    // emitujemy utworzono() — inaczej wczytalby sie dwa razy.\n'
  '    if (szablonWybrany !== "" && FileUtils.fileExists(zrodlo + "/przepis.json")) {\n'
  '      if (!mainWindow.przepisy.noweZadanie(zrodlo + "/przepis.json", katalogProjektow, nazwa)) {\n'
  '        komunikat.text = qsTr("Nie udało się zbudować zadania z przepisu.");\n'
  '        return;\n'
  '      }\n'
  '      kreator.zapiszMetryczke(cel, nazwa);\n'
  '      kreator.close();\n'
  '      return;\n'
  '    }\n\n'
  '    if (szablonWybrany === "") {\n',
  'FileUtils.fileExists(zrodlo + "/przepis.json")'),
 ('src/app/qml/QfNoweZadanie.qml',
  '    // Metryczka zadania: po niej rozpoznaje się, dokąd wracają dane z terenu.\n',
  '    zapiszMetryczke(cel, nazwa);\n\n'
  '    displayToast(qsTr("Utworzono zadanie %1").arg(nazwa));\n'
  '    kreator.utworzono(cel);\n'
  '    kreator.close();\n'
  '  }\n\n'
  '  // Metryczka zadania: po niej rozpoznaje się, dokąd wracają dane z terenu.\n'
  '  function zapiszMetryczke(cel, nazwa) {\n',
  'function zapiszMetryczke('),
 ('src/app/qml/QfNoweZadanie.qml',
  '    FileUtils.writeFileContent(cel + "/ZADANIE.json",\n'
  '                               JSON.stringify(zadanie, null, 2));\n\n'
  '    displayToast(qsTr("Utworzono zadanie %1").arg(nazwa));\n'
  '    kreator.utworzono(cel);\n'
  '    kreator.close();\n'
  '  }\n',
  '    FileUtils.writeFileContent(cel + "/ZADANIE.json",\n'
  '                               JSON.stringify(zadanie, null, 2));\n'
  '  }\n',
  'JSON.stringify(zadanie, null, 2));\n  }'),
]
orig, plan, zrobie, pomijam = {}, {}, [], []
for p in {z[0] for z in Z}:
    if not os.path.exists(p): sys.exit('Brak pliku: ' + p)
    orig[p] = io.open(p, encoding='utf-8').read()
for plik, stare, nowe, zn in Z:
    t = plan.get(plik, orig[plik])
    if zn in t:
        pomijam.append(zn); continue
    n = t.count(stare)
    if n != 1: sys.exit('KONIEC BEZ ZMIAN: w %s fragment wystepuje %d razy:\n---\n%s---' % (plik, n, stare))
    plan[plik] = t.replace(stare, nowe, 1); zrobie.append('%s: %s' % (plik, zn))
for o in zrobie:  print('  ZROBIE  ', o)
for o in pomijam: print('  pomijam ', o)
if not zrobie: print('\nNic do zrobienia.'); sys.exit(0)
for plik, nowa in plan.items():
    k = plik + '.przed_wyposazeniem4'
    if not os.path.exists(k): io.open(k,'w',encoding='utf-8').write(orig[plik])
    io.open(plik,'w',encoding='utf-8').write(nowa); print('zapisano', plik)
print('\nGotowe.')
