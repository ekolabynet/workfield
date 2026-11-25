#!/usr/bin/env python3
"""Instalator łatki [WF-OSM-VECTOR] 24.11.2026 — podkład wektorowy OSM w każdym
projekcie, przełącznik w Ustawieniach → Teren, ortofoto Esri zgaszone, bez rastrowego OSM.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_osm_wektor_wszedzie_cpp.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.cpp'
MD5_PRZED = '11fc430622b413167dd277b6b669f3d2'  # po instaluj_osm_wektor_cpp
MD5_PO = 'fc66f8bf92fff3c35c4623fac86a7683'

ZMIANY = [
    ('    static QElapsedTimer age;\n    if ( !cached.isEmpty() && age.isValid() && age.elapsed() < 6LL * 3600 * 1000 )\n      return cached;\n',
     '    static QElapsedTimer age;\n    // WorkFieldGIS 24.11.2026 — podkład sprawdzany przy każdym otwarciu projektu:\n    // bez sieci nie pytamy ponownie przez 10 minut (każde pytanie to do 4 s czekania).\n    static QElapsedTimer lastFailure;\n    static QString lastError;\n    if ( !cached.isEmpty() && age.isValid() && age.elapsed() < 6LL * 3600 * 1000 )\n      return cached;\n    if ( cached.isEmpty() && lastFailure.isValid() && lastFailure.elapsed() < 10LL * 60 * 1000 )\n    {\n      if ( error )\n        *error = lastError;\n      return cached;\n    }\n'),
    ('        *error = blocking.errorMessage();\n      return cached;\n',
     '        *error = blocking.errorMessage();\n      lastError = blocking.errorMessage();\n      lastFailure.start();\n      return cached;\n'),
    ('        *error = QStringLiteral( "TileJSON bez adresu kafli" );\n      return cached;\n',
     '        *error = QStringLiteral( "TileJSON bez adresu kafli" );\n      lastError = QStringLiteral( "TileJSON bez adresu kafli" );\n      lastFailure.start();\n      return cached;\n'),
    ('} // namespace\n\nQVariantMap NarzedziaProjektu::ensureOsmVectorBasemap',
     '} // namespace\n\n// [WF-ESRI-HIDDEN] WorkFieldGIS 24.11.2026\nint NarzedziaProjektu::setLayerVisibleByName( QgsProject *project, const QString &layerName, bool visible )\n{\n  if ( !project )\n    return 0;\n  int changed = 0;\n  const QList<QgsMapLayer *> layers = project->mapLayersByName( layerName );\n  for ( QgsMapLayer *layer : layers )\n  {\n    QgsLayerTreeLayer *node = project->layerTreeRoot()->findLayer( layer->id() );\n    if ( node && node->itemVisibilityChecked() != visible )\n    {\n      node->setItemVisibilityChecked( visible );\n      ++changed;\n    }\n  }\n  return changed;\n}\n\nQVariantMap NarzedziaProjektu::ensureOsmVectorBasemap'),
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
