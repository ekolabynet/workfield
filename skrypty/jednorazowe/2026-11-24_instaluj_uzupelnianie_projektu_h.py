#!/usr/bin/env python3
"""Instalator łatki [WF-AUTO-EQUIP] 24.11.2026 — identyfikatory (uuid) i wyposażenie
uzupełniane przy otwarciu projektu, z pytaniem przy danych; wyłącznik w Ustawieniach → Teren.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.h
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_uzupelnianie_projektu_h.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.h'
MD5_PRZED = 'a3c53c9741e31c20c6c465b89d7efcad'  # po instaluj_osm_wektor_wszedzie_h
MD5_PO = 'ccd0fe458f883209a65c2fd4d67fb2a5'

ZMIANY = [
    ('    Q_INVOKABLE QVariantMap repairIdentity( QgsProject *project );\n',
     '    Q_INVOKABLE QVariantMap repairIdentity( QgsProject *project );\n\n    /**\n     * WorkFieldGIS 24.11.2026 [WF-AUTO-EQUIP] — what repairIdentity() would add\n     * to the SCHEMA, without changing anything: layers missing the uuid field,\n     * or the PARENT_UUID field of a photo table with a parent relation.\n     * Returns { layers: [names], withData: [names of those that have objects],\n     * files: [their GeoPackages], projectHasData: any data layer has objects }. Empty values in existing fields are not\n     * here: fillMissingIdentity() fills them on every open anyway.\n     */\n    Q_INVOKABLE QVariantMap identityFieldsPlan( QgsProject *project ) const;\n\n    /**\n     * WorkFieldGIS 24.11.2026 [WF-AUTO-EQUIP] — repairIdentity() preceded by\n     * copies: a sealed snapshot (migawkaBazy) of every GeoPackage from\n     * identityFieldsPlan() and a copy of the project file, all into "kopie"\n     * next to the project. A failed copy stops before any change.\n     * Returns the map of repairIdentity() plus "kopie" (paths of the copies).\n     */\n    Q_INVOKABLE QVariantMap repairIdentityWithBackup( QgsProject *project );\n'),
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
