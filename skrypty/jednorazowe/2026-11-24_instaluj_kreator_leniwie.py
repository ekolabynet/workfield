#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-LAZY-WIZARD] kreator projektu QField tworzony dopiero przy otwarciu.

Refaktoryzacja okna głównego, krok R2.1. QfProjectCreationScreen (kreator QField
z notatkami i śladami) trafia do Loadera z active: false. W WFG nie ma przycisku,
który go otwiera, więc w praktyce przestaje powstawać przy starcie. Gdyby przycisk
wrócił — kreator utworzy się przy pierwszym otwarciu i działa jak dotąd.
Zachowanie aplikacji bez zmian.

Użycie (z katalogu repozytorium):
  python3 instaluj_kreator_leniwie.py            # próba, nic nie zapisuje
  python3 instaluj_kreator_leniwie.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_kreator_leniwie.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml"
MD5_PRZED = "da273e690a0cb6ee0c7e2168a673e61d"  # GitHub development, v0.14.12 = v0.14.13 (plik bez zmian)
MD5_PO = "300fa4295e42ccbbca48d14ffb2c66cc"

ZMIANY = [
    ('\n      projectCreationScreen.visible = false;\n      projectCreationScreen.focus = false;\n',
     '\n      if (projectCreationScreenLoader.item) { // [WF-LAZY-WIZARD]\n        projectCreationScreenLoader.item.visible = false;\n        projectCreationScreenLoader.item.focus = false;\n      }\n'),
    ('\n    onShowProjectCreationScreen: {\n      projectCreationScreen.show();\n    }\n',
     '\n    onShowProjectCreationScreen: {\n      projectCreationScreenLoader.active = true; // [WF-LAZY-WIZARD]\n      projectCreationScreenLoader.item.show();\n    }\n'),
    ('\n  QfProjectCreationScreen {\n    id: projectCreationScreen\n    objectName: "projectCreationScreen"\n\n    visible: false\n    focus: visible\n    width: parent.width\n    height: parent.height\n\n    onTriggerConnection: {\n      qfieldCloudPopup.pendingAction = "connect";\n      qfieldCloudPopup.show();\n    }\n\n    onTriggerCloudify: (title, path) => {\n      iface.clearProject();\n      cloudProjectsModel.currentProjectId = "";\n      qfieldCloudPopup.cloudify(title, QfFileUtils.absolutePath(path));\n    }\n\n    onTriggerProjectLoad: (title, path) => {\n      iface.loadFile(path, title);\n    }\n\n    Component.onCompleted: focusstack.addFocusTaker(this)\n  }\n',
     '\n  // WorkFieldGIS 24.11.2026 — [WF-LAZY-WIZARD] kreator „Utwórz nowy projekt” z QField\n  // powstaje dopiero przy pierwszym otwarciu. W WFG nie ma do niego przycisku\n  // (QfWelcomeScreen nie emituje showProjectCreationScreen), a dotąd jego 632 linie\n  // QML tworzyły się przy każdym starcie aplikacji. Pierwszy krok refaktoryzacji\n  // okna głównego (claude/REFAKTOR_okno_glowne_plan_2026-11-24.md, R2.1).\n  Loader {\n    id: projectCreationScreenLoader\n    active: false\n    width: parent.width\n    height: parent.height\n    sourceComponent: Component {\n      QfProjectCreationScreen {\n        id: projectCreationScreen\n        objectName: "projectCreationScreen"\n\n        visible: false\n        focus: visible\n        width: parent.width\n        height: parent.height\n\n        onTriggerConnection: {\n          qfieldCloudPopup.pendingAction = "connect";\n          qfieldCloudPopup.show();\n        }\n\n        onTriggerCloudify: (title, path) => {\n          iface.clearProject();\n          cloudProjectsModel.currentProjectId = "";\n          qfieldCloudPopup.cloudify(title, QfFileUtils.absolutePath(path));\n        }\n\n        onTriggerProjectLoad: (title, path) => {\n          iface.loadFile(path, title);\n        }\n\n        Component.onCompleted: focusstack.addFocusTaker(this)\n      }\n    }\n  }\n'),
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
