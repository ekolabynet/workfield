#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-CRS-REPROJECT] przeliczenie warstwy ze stopni WGS84 na jej układ (okno naprawy).

Decyzja Piotra 24.11: naprawa dostępna na telefonie, żeby złe dane nie szły dalej. Trzy
instalatory razem: narzedziaprojektu.h (deklaracja), narzedziaprojektu.cpp (funkcja
reprojectDegreesLayer i czasownik „przelicz_stopnie” przy ostrzeżeniu o stopniach),
QfNaprawaProjektu.qml (przycisk „Przelicz na EPSG:xxxx”, dwa naciśnięcia). Wszystko albo nic,
migawka bazy w „kopie” przed zmianą, jedna sesja edycji z dziennikiem WF_JOURNAL.

Użycie (z katalogu repozytorium):
  python3 instaluj_crs_przelicz_qml.py            # próba, nic nie zapisuje
  python3 instaluj_crs_przelicz_qml.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_crs_przelicz_qml.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfNaprawaProjektu.qml'
MD5_PRZED = '9be66556ae439ed2bdacf769665eec09'  # po 2026-11-24_instaluj_crs_naprawa.py
MD5_PO = '810354bf92454b0c75f75e510fae411a'

ZMIANY = [
    ('  property bool blad: false\n',
     '  property bool blad: false\n  //! [WF-CRS-REPROJECT] warstwa czekająca na drugie naciśnięcie (potwierdzenie)\n  property string pendingReproject: ""\n'),
    ('      // [WF-CRS-STATE]\n      case "ustaw_uklad":\n',
     '      // [WF-CRS-REPROJECT]\n      case "przelicz_stopnie":\n        return [{ "etykieta": qsTr("Przelicz na %1").arg(o.uklad), "co": "przelicz_stopnie" }];\n      // [WF-CRS-STATE]\n      case "ustaw_uklad":\n'),
    ('    let w = null;\n    // [WF-IDENTITY] uuid / PARENT_UUID — fields, values, project saved.\n',
     '    // WorkFieldGIS 24.11.2026 — [WF-CRS-REPROJECT] stopnie → układ warstwy.\n    // Zmienia geometrię wszystkich obiektów warstwy, więc dwa naciśnięcia:\n    // pierwsze mówi, co się stanie, drugie wykonuje.\n    if (co === "przelicz_stopnie") {\n      if (naprawa.pendingReproject !== o.warstwa) {\n        naprawa.pendingReproject = o.warstwa;\n        naprawa.komunikat = qsTr("Przeliczę WSZYSTKIE obiekty warstwy „%1” ze stopni WGS84 na %2. Przedtem zrobię kopię bazy w katalogu „kopie”. Naciśnij przycisk jeszcze raz, żeby potwierdzić.").arg(o.warstwa).arg(o.uklad);\n        naprawa.blad = false;\n        return;\n      }\n      naprawa.pendingReproject = "";\n      const przeliczenie = NarzedziaProjektu.reprojectDegreesLayer(qgisProject, o.warstwa);\n      naprawa.komunikat = przeliczenie.opis;\n      naprawa.blad = !przeliczenie.ok;\n      stanProjektu.odswiez();\n      return;\n    }\n\n    let w = null;\n    // [WF-IDENTITY] uuid / PARENT_UUID — fields, values, project saved.\n'),
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
