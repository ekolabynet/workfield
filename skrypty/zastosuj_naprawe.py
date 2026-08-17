import io, os, sys
Z = [
 ('src/core/utils/narzedziaprojektu.h',
  '    //! Warstwa projektu po nazwie; nullptr, gdy nie ma.\n',
  '    /**\n'
  '     * Warstwy ROBOCZE projektu — te, na ktorych sie zbiera dane.\n'
  '     * Pomija tabele zalacznikow (ZAL_), warstwy odniesienia (REF_),\n'
  '     * tylko-do-odczytu i bezgeometryczne. Zwraca liste map:\n'
  '     *   nazwa      QString\n'
  '     *   geometria  QString  "Punkt" | "Linia" | "Poligon"\n'
  '     *   punktowa   bool\n'
  '     *\n'
  '     * Osobny czasownik, bo QML nie ma jak bezpiecznie odroznic warstwy\n'
  '     * wektorowej od rastrowej — rzutowanie robimy po stronie C++.\n'
  '     */\n'
  '    Q_INVOKABLE QVariantList warstwyRobocze( QgsProject *projekt ) const;\n\n'
  '    //! Warstwa projektu po nazwie; nullptr, gdy nie ma.\n',
  'QVariantList warstwyRobocze('),
 ('src/core/utils/narzedziaprojektu.cpp',
  'QString NarzedziaProjektu::katalogSzablonow( const QString &korzen ) const\n',
  'QVariantList NarzedziaProjektu::warstwyRobocze( QgsProject *projekt ) const\n'
  '{\n'
  '  QVariantList wynik;\n'
  '  QgsProject *p = projekt ? projekt : QgsProject::instance();\n'
  '  if ( !p )\n    return wynik;\n\n'
  '  const QMap<QString, QgsMapLayer *> wszystkie = p->mapLayers();\n'
  '  for ( QgsMapLayer *kandydat : wszystkie )\n'
  '  {\n'
  '    QgsVectorLayer *warstwa = qobject_cast<QgsVectorLayer *>( kandydat );\n'
  '    if ( !warstwa || warstwa->readOnly() )\n      continue;\n\n'
  '    const QString nazwa = warstwa->name();\n'
  '    if ( nazwa.startsWith( QLatin1String( "ZAL_" ), Qt::CaseInsensitive )\n'
  '         || nazwa.startsWith( QLatin1String( "REF_" ), Qt::CaseInsensitive ) )\n'
  '      continue;\n\n'
  '    QString geometria;\n'
  '    switch ( warstwa->geometryType() )\n'
  '    {\n'
  '      case Qgis::GeometryType::Point:\n        geometria = QStringLiteral( "Punkt" );\n        break;\n'
  '      case Qgis::GeometryType::Line:\n        geometria = QStringLiteral( "Linia" );\n        break;\n'
  '      case Qgis::GeometryType::Polygon:\n        geometria = QStringLiteral( "Poligon" );\n        break;\n'
  '      default:\n        continue;   // bezgeometryczne to slowniki, nie warstwy robocze\n'
  '    }\n\n'
  '    QVariantMap wpis;\n'
  '    wpis.insert( QStringLiteral( "nazwa" ), nazwa );\n'
  '    wpis.insert( QStringLiteral( "geometria" ), geometria );\n'
  '    wpis.insert( QStringLiteral( "punktowa" ), geometria == QLatin1String( "Punkt" ) );\n'
  '    wynik.append( wpis );\n'
  '  }\n'
  '  return wynik;\n'
  '}\n\n'
  'QString NarzedziaProjektu::katalogSzablonow( const QString &korzen ) const\n',
  'NarzedziaProjektu::warstwyRobocze'),
 ('src/app/CMakeLists.txt',
  '    qml/QfKontrolaProjektu.qml\n',
  '    qml/QfKontrolaProjektu.qml\n    qml/QfNaprawaProjektu.qml\n',
  'qml/QfNaprawaProjektu.qml'),
 ('src/app/qml/qgismobileapp.qml',
  '  QfKontrolaProjektu {\n    id: kontrolaProjektu\n  }\n',
  '  QfKontrolaProjektu {\n    id: kontrolaProjektu\n    ekranNaprawy: naprawaProjektu\n  }\n\n'
  '  QfNaprawaProjektu {\n'
  '    id: naprawaProjektu\n'
  '    kontrola: kontrolaProjektu\n'
  '  }\n',
  'QfNaprawaProjektu {'),
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
    k = plik + '.przed_naprawa'
    if not os.path.exists(k): io.open(k,'w',encoding='utf-8').write(orig[plik])
    io.open(plik,'w',encoding='utf-8').write(nowa); print('zapisano', plik)
print('\nGotowe.')
