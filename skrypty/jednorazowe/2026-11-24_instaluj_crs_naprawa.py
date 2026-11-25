#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-CRS-STATE] okno naprawy: „Ustaw EPSG:xxxx” dla projektu bez układu.

Para z 2026-11-24_instaluj_crs_stan.py. Czasownik „ustaw_uklad” przy ostrzeżeniu o braku
układu: iface.setProjectCrs(układ z warstwy danych) i zapis projektu. Komunikat każe otworzyć
projekt ponownie przed pomiarem.

Użycie (z katalogu repozytorium):
  python3 instaluj_crs_naprawa.py            # próba, nic nie zapisuje
  python3 instaluj_crs_naprawa.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_crs_naprawa.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfNaprawaProjektu.qml'
MD5_PRZED = 'a96aca76a373bb182aab98f35708af78'  # GitHub development 9f2ab088b
MD5_PO = '9be66556ae439ed2bdacf769665eec09'

ZMIANY = [
    ('      // [WF-PROJECT-DATABASE]\n      case "baza_projektu":\n        return [{ "etykieta": qsTr("Dołóż bazę danych"), "co": "baza_projektu" }];\n',
     '      // [WF-PROJECT-DATABASE]\n      case "baza_projektu":\n        return [{ "etykieta": qsTr("Dołóż bazę danych"), "co": "baza_projektu" }];\n      // [WF-CRS-STATE]\n      case "ustaw_uklad":\n        return [{ "etykieta": qsTr("Ustaw %1").arg(o.uklad), "co": "ustaw_uklad" }];\n'),
    ('    let w = null;\n    // [WF-IDENTITY] uuid / PARENT_UUID — fields, values, project saved.\n',
     '    // WorkFieldGIS 24.11.2026 — [WF-CRS-STATE] układ projektu z warstwy danych.\n    // Przycisk jest potwierdzeniem: człowiek widzi w nim kod układu. Projekt\n    // zapisany od razu, bo bez zapisu po ponownym otwarciu układu znów nie ma.\n    if (co === "ustaw_uklad") {\n      if (!o.uklad || !iface.setProjectCrs(o.uklad)) {\n        naprawa.komunikat = qsTr("Nie udało się ustawić układu %1.").arg(o.uklad);\n        naprawa.blad = true;\n        return;\n      }\n      if (!ProjectUtils.saveProject(qgisProject)) {\n        naprawa.komunikat = qsTr("Układ %1 ustawiony, ale projektu NIE zapisano — po ponownym otwarciu znów go nie będzie.").arg(o.uklad);\n        naprawa.blad = true;\n      } else {\n        naprawa.komunikat = qsTr("Układ projektu: %1, projekt zapisany. Otwórz projekt ponownie, zanim zaczniesz mierzyć.").arg(o.uklad);\n        naprawa.blad = false;\n      }\n      stanProjektu.odswiez();\n      return;\n    }\n\n    let w = null;\n    // [WF-IDENTITY] uuid / PARENT_UUID — fields, values, project saved.\n'),
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
