#!/usr/bin/env python3
"""Instalator łatki [WF-AUTO-EQUIP] 24.11.2026 — identyfikatory (uuid) i wyposażenie
uzupełniane przy otwarciu projektu, z pytaniem przy danych; wyłącznik w Ustawieniach → Teren.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_uzupelnianie_projektu_cpp.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp'
MD5_PRZED = 'fc66f8bf92fff3c35c4623fac86a7683'  # po instaluj_osm_wektor_wszedzie_cpp
MD5_PO = 'd617bc4240adc443234ac5940423a166'

ZMIANY = [
    ('  result.insert( QStringLiteral( "ok" ), skipped.isEmpty() );\n  result.insert( QStringLiteral( "opis" ), text.join( QLatin1Char( \' \' ) ) );\n  result.insert( QStringLiteral( "fieldsAdded" ), fieldsAdded );\n  result.insert( QStringLiteral( "valuesWritten" ), valuesWritten );\n  return result;\n}\n',
     '  result.insert( QStringLiteral( "ok" ), skipped.isEmpty() );\n  result.insert( QStringLiteral( "opis" ), text.join( QLatin1Char( \' \' ) ) );\n  result.insert( QStringLiteral( "fieldsAdded" ), fieldsAdded );\n  result.insert( QStringLiteral( "valuesWritten" ), valuesWritten );\n  return result;\n}\n\n// WorkFieldGIS 24.11.2026 [WF-AUTO-EQUIP] — Piotr: „telefon i tak ostrzega, że\n// tego nie ma w warstwie i zostawia użytkownika ze stresem”. Okno główne pyta\n// przy otwarciu i woła repairIdentityWithBackup(); tu tylko plan i kopie.\nQVariantMap NarzedziaProjektu::identityFieldsPlan( QgsProject *project ) const\n{\n  QStringList names;\n  QStringList withData;\n  QStringList files;\n  bool projectHasData = false;\n  if ( project )\n  {\n    const auto layers = project->mapLayers();\n    for ( QgsMapLayer *mapLayer : layers )\n    {\n      QgsVectorLayer *layer = qobject_cast<QgsVectorLayer *>( mapLayer );\n      if ( !carriesIdentity( layer ) )\n        continue;\n      const bool hasObjects = layer->featureCount() > 0;\n      projectHasData = projectHasData || hasObjects;\n      const bool missingUuid = FeatureIdentity::uuidFieldIndex( layer->fields() ) < 0;\n      const bool missingParentUuid = identityParentRelation( project, layer ).isValid()\n                                     && FeatureIdentity::fieldIndex( layer->fields(), FeatureIdentity::parentUuidFieldName() ) < 0;\n      if ( !missingUuid && !missingParentUuid )\n        continue;\n      names << layer->name();\n      if ( hasObjects )\n        withData << layer->name();\n      const QString gpkg = JournalUtils::gpkgPath( layer );\n      if ( !gpkg.isEmpty() && !files.contains( gpkg ) )\n        files << gpkg;\n    }\n  }\n  QVariantMap result;\n  result.insert( QStringLiteral( "layers" ), names );\n  result.insert( QStringLiteral( "withData" ), withData );\n  result.insert( QStringLiteral( "files" ), files );\n  result.insert( QStringLiteral( "projectHasData" ), projectHasData );\n  return result;\n}\n\nQVariantMap NarzedziaProjektu::repairIdentityWithBackup( QgsProject *project )\n{\n  QVariantMap result;\n  result.insert( QStringLiteral( "ok" ), false );\n  if ( !project || project->fileName().isEmpty() )\n  {\n    result.insert( QStringLiteral( "opis" ), tr( "Brak projektu." ) );\n    return result;\n  }\n  const QFileInfo projectFile( project->fileName() );\n  const QString backupDir = projectFile.absolutePath() + QStringLiteral( "/kopie" );\n  QStringList copies;\n\n  const QStringList files = identityFieldsPlan( project ).value( QStringLiteral( "files" ) ).toStringList();\n  for ( const QString &gpkg : files )\n  {\n    const QVariantMap snapshot = migawkaBazy( gpkg, backupDir );\n    if ( !snapshot.value( QStringLiteral( "ok" ) ).toBool() )\n    {\n      result.insert( QStringLiteral( "opis" ), tr( "Nie udało się zrobić kopii bazy %1 (%2). Nic nie zmieniłem." )\n                                                 .arg( QFileInfo( gpkg ).fileName(), snapshot.value( QStringLiteral( "blad" ) ).toString() ) );\n      result.insert( QStringLiteral( "kopie" ), copies );\n      return result;\n    }\n    copies << snapshot.value( QStringLiteral( "sciezka" ) ).toString();\n  }\n\n  QDir().mkpath( backupDir );\n  const QString projectCopy = QStringLiteral( "%1/%2_przed_uuid_%3.%4" )\n                                .arg( backupDir, projectFile.completeBaseName(),\n                                      QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmmss" ) ),\n                                      projectFile.suffix() );\n  if ( !QFile::copy( projectFile.absoluteFilePath(), projectCopy ) )\n  {\n    result.insert( QStringLiteral( "opis" ), tr( "Nie udało się skopiować pliku projektu do %1. Nic nie zmieniłem." ).arg( backupDir ) );\n    result.insert( QStringLiteral( "kopie" ), copies );\n    return result;\n  }\n  copies << projectCopy;\n\n  result = repairIdentity( project );\n  result.insert( QStringLiteral( "kopie" ), copies );\n  QgsMessageLog::logMessage( QStringLiteral( "[WF-AUTO-EQUIP] %1 Kopie: %2" )\n                               .arg( result.value( QStringLiteral( "opis" ) ).toString(), copies.join( QStringLiteral( "; " ) ) ),\n                             QStringLiteral( "WorkField" ), Qgis::MessageLevel::Info );\n  return result;\n}\n'),
]


def md5(dane):
    return hashlib.md5(dane).hexdigest()


def main():
    argv = sys.argv[1:]
    zapisz = "--zapisz" in argv
    plik = PLIK
    if "--plik" in argv:
        plik = argv[argv.index("--plik") + 1]

    with open(plik, "rb") as f:
        surowe = f.read()
    teraz = md5(surowe)
    print("plik:", plik)
    print("md5 :", teraz)

    if teraz == MD5_PO:
        print("JUŻ ZAINSTALOWANE — nic nie zmieniam.")
        return 0
    if teraz != MD5_PRZED:
        print("STOP: md5 inne niż oczekiwane", MD5_PRZED)
        print("Plik różni się od wersji, na której zbudowano łatkę. Nie nadpisuję cudzej pracy.")
        print("Przyślij ten plik, zbuduję instalator na jego bajtach.")
        return 1

    tekst = surowe.decode("utf-8")
    for nr, (stare, _nowe) in enumerate(ZMIANY, 1):
        ile = tekst.count(stare)
        if ile != 1:
            print("STOP: kotwica %d występuje %d razy (ma być 1). Nic nie zapisano." % (nr, ile))
            return 1
    for stare, nowe in ZMIANY:
        tekst = tekst.replace(stare, nowe, 1)

    nowe_bajty = tekst.encode("utf-8")
    print("po zmianie md5:", md5(nowe_bajty))
    linie_przed = surowe.count(b"\n")
    linie_po = nowe_bajty.count(b"\n")
    print("linie: %d -> %d (+%d)" % (linie_przed, linie_po, linie_po - linie_przed))

    if not zapisz:
        print("PRÓBA — nic nie zapisano. Zapis: dopisz --zapisz")
        return 0

    kopia = plik + ".przed_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    nr = 1
    while os.path.exists(kopia):  # dwie łatki w tej samej sekundzie
        nr += 1
        kopia = plik + ".przed_" + datetime.now().strftime("%Y%m%d_%H%M%S") + "_%d" % nr
    shutil.copy2(plik, kopia)
    with open(plik, "wb") as f:
        f.write(nowe_bajty)
    print("ZAPISANO. Kopia:", kopia)
    return 0


if __name__ == "__main__":
    sys.exit(main())
