import io, os, sys
Z = [
 ('src/core/utils/narzedziaprojektu.h',
  '    Q_INVOKABLE QString nowyProjekt( const QString &korzen, const QString &nazwa, const QString &crsAuthId = QStringLiteral( "EPSG:2178" ) ) const;\n',
  '    Q_INVOKABLE QString nowyProjekt( const QString &korzen, const QString &nazwa, const QString &crsAuthId = QStringLiteral( "EPSG:2178" ) ) const;\n\n'
  '    /**\n'
  '     * Katalog, w ktorym rodza sie nowe zadania: <korzen>/wydania, a gdy go\n'
  '     * nie ma — <korzen>/wymiana (stare drzewa), a gdy i tego nie ma — sam\n'
  '     * korzen. Ta sama regula co ProcesyStudio::nowyZSzablonu (docs/MAGAZYN.md).\n'
  '     *\n'
  '     * Osobny czasownik, bo FileUtils::fileExists() wymaga isFile() i na\n'
  '     * katalogu zwraca false — zadanie ladowalo przez to w korzeniu magazynu.\n'
  '     */\n'
  '    Q_INVOKABLE QString katalogZadan( const QString &korzen ) const;\n',
  'QString katalogZadan('),
 ('src/core/utils/narzedziaprojektu.cpp',
  'QString NarzedziaProjektu::nowyProjekt( const QString &korzen',
  'QString NarzedziaProjektu::katalogZadan( const QString &korzen ) const\n'
  '{\n'
  '  if ( korzen.isEmpty() )\n    return QString();\n\n'
  '  const QDir k( korzen );\n'
  '  const QString wydania = k.filePath( QStringLiteral( "wydania" ) );\n'
  '  if ( QDir( wydania ).exists() )\n    return wydania;\n\n'
  '  const QString wymiana = k.filePath( QStringLiteral( "wymiana" ) );\n'
  '  if ( QDir( wymiana ).exists() )\n    return wymiana;\n\n'
  '  return QDir::cleanPath( korzen );\n'
  '}\n\n'
  'QString NarzedziaProjektu::nowyProjekt( const QString &korzen',
  'NarzedziaProjektu::katalogZadan'),
 ('src/app/qml/QfStudioSection.qml',
  '              const korzenWydan = ustawieniaStudia.korzenProjektow + "/wydania";\n'
  '              const korzenZadan = FileUtils.fileExists(korzenWydan) ? korzenWydan : ustawieniaStudia.korzenProjektow;\n',
  '              const korzenZadan = NarzedziaProjektu.katalogZadan(ustawieniaStudia.korzenProjektow);\n',
  'NarzedziaProjektu.katalogZadan('),
]
orig, plan, zrobie, pomijam = {}, {}, [], []
for p in {z[0] for z in Z}:
    if not os.path.exists(p): sys.exit('Brak pliku: ' + p)
    orig[p] = io.open(p, encoding='utf-8').read()
for plik, stare, nowe, zn in Z:
    t = plan.get(plik, orig[plik])
    if zn in t: pomijam.append(zn); continue
    n = t.count(stare)
    if n != 1: sys.exit('KONIEC BEZ ZMIAN: w %s fragment wystepuje %d razy:\n%s' % (plik, n, stare))
    plan[plik] = t.replace(stare, nowe, 1); zrobie.append('%s: %s' % (plik, zn))
for o in zrobie:  print('  ZROBIE  ', o)
for o in pomijam: print('  pomijam ', o)
if not zrobie: print('\nNic do zrobienia.'); sys.exit(0)
for plik, nowa in plan.items():
    k = plik + '.przed_wyposazeniem3'
    if not os.path.exists(k): io.open(k,'w',encoding='utf-8').write(orig[plik])
    io.open(plik,'w',encoding='utf-8').write(nowa); print('zapisano', plik)
print('\nGotowe.')
