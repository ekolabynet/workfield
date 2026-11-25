#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-CRS-REPROJECT] przeliczenie warstwy ze stopni WGS84 na jej układ (deklaracja).

Decyzja Piotra 24.11: naprawa dostępna na telefonie, żeby złe dane nie szły dalej. Trzy
instalatory razem: narzedziaprojektu.h (deklaracja), narzedziaprojektu.cpp (funkcja
reprojectDegreesLayer i czasownik „przelicz_stopnie” przy ostrzeżeniu o stopniach),
QfNaprawaProjektu.qml (przycisk „Przelicz na EPSG:xxxx”, dwa naciśnięcia). Wszystko albo nic,
migawka bazy w „kopie” przed zmianą, jedna sesja edycji z dziennikiem WF_JOURNAL.

Użycie (z katalogu repozytorium):
  python3 instaluj_crs_przelicz_h.py            # próba, nic nie zapisuje
  python3 instaluj_crs_przelicz_h.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_crs_przelicz_h.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/core/utils/narzedziaprojektu.h'
MD5_PRZED = '35160bc936daab4e96670833cee69c58'  # GitHub development 9f2ab088b
MD5_PO = '71238bab9ee817bace9371260a5f2592'

ZMIANY = [
    ('    Q_INVOKABLE QVariantMap stanProjektu( QgsProject *projekt ) const;\n',
     '    Q_INVOKABLE QVariantMap stanProjektu( QgsProject *projekt ) const;\n\n    /**\n     * WorkFieldGIS 24.11.2026 — [WF-CRS-REPROJECT] przelicza warstwę, do której\n     * przy pustym układzie projektu trafiły stopnie WGS84 zamiast metrów\n     * (SOŁTYKA CZWARTEK). Wszystko albo nic: każda geometria musi być w zakresie\n     * stopni i po przeliczeniu leżeć w obszarze układu warstwy, inaczej nic się\n     * nie zmienia. Przedtem migawka bazy w katalogu „kopie”, potem jedna sesja\n     * edycji (dziennik WF_JOURNAL zapisuje stare geometrie). Wymaga prawidłowego\n     * układu projektu. Zwraca { ok, opis, przeliczone, kopia }.\n     */\n    Q_INVOKABLE QVariantMap reprojectDegreesLayer( QgsProject *project, const QString &layerName );\n'),
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
