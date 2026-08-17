import io, os, sys
Z = [
 ('src/core/procesystudio.cpp',
  '  if ( !qgsy.isEmpty() || !gpkgi.isEmpty() )\n  {\n    QDateTime najnowszy;\n    for ( const QString &p : qgsy + gpkgi )\n',
  '  // WorkField: katalog z samym przepis.json tez jest szablonem.\n'
  '  const QString plikPrzepisu = dir.filePath( QStringLiteral( "przepis.json" ) );\n'
  '  const bool maPrzepis = QFileInfo::exists( plikPrzepisu );\n\n'
  '  if ( !qgsy.isEmpty() || !gpkgi.isEmpty() || maPrzepis )\n  {\n    QDateTime najnowszy;\n'
  '    if ( maPrzepis )\n      najnowszy = QFileInfo( plikPrzepisu ).lastModified();\n'
  '    for ( const QString &p : qgsy + gpkgi )\n',
  'const bool maPrzepis ='),
 ('src/core/procesystudio.cpp',
  '    const bool szablon = sciezka.toLower().contains( QLatin1String( "szablon" ) );\n',
  '    const bool szablon = maPrzepis || sciezka.toLower().contains( QLatin1String( "szablon" ) );\n',
  'maPrzepis || sciezka.toLower()'),
 ('src/core/procesystudio.cpp',
  '    wpis[QStringLiteral( "typ" )] = szablon ? QStringLiteral( "szablon" ) : QStringLiteral( "projekt" );\n',
  '    wpis[QStringLiteral( "typ" )] = szablon ? QStringLiteral( "szablon" ) : QStringLiteral( "projekt" );\n'
  '    wpis[QStringLiteral( "przepis" )] = maPrzepis ? plikPrzepisu : QString();\n',
  'wpis[QStringLiteral( "przepis" )]'),
 ('src/app/qml/qgismobileapp.qml',
  '  property string projectTitle: ""\n',
  '  //! WorkField: interpreter przepisow widoczny jako mainWindow.przepisy\n'
  '  property alias przepisy: qfPrzepis\n\n  property string projectTitle: ""\n',
  'property alias przepisy: qfPrzepis'),
 ('src/app/qml/QfStudioSection.qml',
  '            const szablon = wyborSzablonu.model[wyborSzablonu.currentIndex];\n'
  '            const w = procesy.nowyZSzablonu(szablon.sciezka, "", poleNazwy.text,\n'
  '                                            ustawieniaStudia.korzenProjektow);\n',
  '            const szablon = wyborSzablonu.model[wyborSzablonu.currentIndex];\n\n'
  '            // WorkField: szablon z przepisem budujemy od zera z aktualnego\n'
  '            // wyposazenia; kopia katalogu zostaje dla szablonow bez przepisu.\n'
  '            if (szablon.przepis && szablon.przepis !== "") {\n'
  '              const korzenWydan = ustawieniaStudia.korzenProjektow + "/wydania";\n'
  '              const korzenZadan = FileUtils.fileExists(korzenWydan) ? korzenWydan : ustawieniaStudia.korzenProjektow;\n'
  '              if (mainWindow.przepisy.noweZadanie(szablon.przepis, korzenZadan, poleNazwy.text.trim())) {\n'
  '                zapis.dopisz(qsTr("Buduje %1 z przepisu (szablon %2)...").arg(poleNazwy.text.trim()).arg(szablon.nazwa));\n'
  '                kreatorNowego.close();\n                studio.przeladuj();\n'
  '              } else {\n                zapis.dopisz(qsTr("Nie udalo sie zbudowac z przepisu."));\n              }\n'
  '              return;\n            }\n\n'
  '            const w = procesy.nowyZSzablonu(szablon.sciezka, "", poleNazwy.text,\n'
  '                                            ustawieniaStudia.korzenProjektow);\n',
  'szablon.przepis && szablon.przepis'),
]
if not os.path.exists('src/app/qml/QfPrzepis.qml'):
    sys.exit('Najpierw latka 1 — brak QfPrzepis.qml')
orig, plan, zrobie, pomijam = {}, {}, [], []
for p in {z[0] for z in Z}:
    orig[p] = io.open(p, encoding='utf-8').read()
for plik, stare, nowe, znacznik in Z:
    t = plan.get(plik, orig[plik])
    if znacznik in t:
        pomijam.append(znacznik[:45]); continue
    n = t.count(stare)
    if n != 1:
        sys.exit('KONIEC BEZ ZMIAN: w %s fragment wystepuje %d razy (oczekiwano 1):\n%s' % (plik, n, stare))
    plan[plik] = t.replace(stare, nowe); zrobie.append('%s: %s' % (plik, znacznik[:45]))
for o in zrobie:  print('  ZROBIE  ', o)
for o in pomijam: print('  pomijam ', o)
if not zrobie:
    print('\nNic do zrobienia — juz wpiete.'); sys.exit(0)
for plik, nowa in plan.items():
    k = plik + '.przed_wyposazeniem2'
    if not os.path.exists(k):
        io.open(k, 'w', encoding='utf-8').write(orig[plik])
    io.open(plik, 'w', encoding='utf-8').write(nowa)
    print('zapisano', plik)
print('\nGotowe.')
