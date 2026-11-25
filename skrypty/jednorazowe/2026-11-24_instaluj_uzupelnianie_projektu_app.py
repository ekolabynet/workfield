#!/usr/bin/env python3
"""Instalator łatki [WF-AUTO-EQUIP] 24.11.2026 — identyfikatory (uuid) i wyposażenie
uzupełniane przy otwarciu projektu, z pytaniem przy danych; wyłącznik w Ustawieniach → Teren.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_uzupelnianie_projektu_app.py
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml'
MD5_PRZED = '290009b89bf7f12927a4e15c4fcb38cb'  # po instaluj_osm_pod_rysunkiem_cad
MD5_PO = '9723c93b12991538cd97ee72fe405d07'

ZMIANY = [
    ('\n  property string projectTitle: ""\n  function refreshProjectTitle() {',
     '\n  // [WF-AUTO-EQUIP] WorkFieldGIS 24.11.2026 — Piotr: identyfikatory (uuid)\n  // i wyposażenie projektu uzupełniane przy otwarciu; „telefon i tak ostrzega,\n  // że tego nie ma w warstwie i zostawia użytkownika ze stresem”. Warstwy bez\n  // obiektów (świeży projekt) — od razu; warstwy z danymi i moduły — po\n  // pytaniu. Wyłącznik: Ustawienia → Teren (WorkField/autoEquipProject).\n  readonly property string autoEquipSettingKey: "WorkField/autoEquipProject"\n  property var autoEquipPlan: null\n  function autoEquipModules() {\n    // Only modules the app may install itself (catalog "gdzie": teren) and\n    // that ask nothing — structure modules stay in the office (WYPOSAZENIE.md).\n    let out = [];\n    let stan = [];\n    try {\n      stan = autoEquipCatalog.sprawdz(qgisProject) || [];\n    } catch (e) {\n      stan = [];\n    }\n    for (const m of stan) {\n      if (m.stan !== "brak" && m.stan !== "starszy")\n        continue;\n      if (autoEquipCatalog.mozeZalozyc(m.modul) !== "" || autoEquipCatalog.zapowiedzModulu(m.modul) !== "")\n        continue;\n      out.push({ "modul": m.modul, "nazwa": m.nazwa, "stan": m.stan });\n    }\n    return out;\n  }\n  function autoEquipCheck() {\n    if (autoEquipDialog.visible)\n      return;\n    if (!settings.valueBool(autoEquipSettingKey, true)) {\n      console.log("WorkField [WF-AUTO-EQUIP]: wyłączone w ustawieniach");\n      return;\n    }\n    let identity = { "layers": [], "withData": [], "files": [], "projectHasData": false };\n    try {\n      identity = NarzedziaProjektu.identityFieldsPlan(qgisProject);\n    } catch (e) {\n      console.log("WorkField [WF-AUTO-EQUIP]: plan failed: " + e);\n    }\n    const modules = autoEquipModules();\n    console.log("WorkField [WF-AUTO-EQUIP]: bez uuid " + identity.layers.length + " (z danymi " + identity.withData.length + "), moduły do założenia " + modules.length);\n    if (identity.layers.length === 0 && modules.length === 0)\n      return;\n    // A project without data (fresh, from DXF): no question. With data:\n    // fields in layers with objects or a module (a new version of a module on\n    // a project with data needs a yes — workfield-obieg §6) — the question.\n    if (identity.withData.length === 0 && !(modules.length > 0 && identity.projectHasData)) {\n      autoEquipRun({ "identity": identity, "modules": modules });\n      return;\n    }\n    autoEquipPlan = { "identity": identity, "modules": modules };\n    autoEquipDialog.open();\n  }\n  function autoEquipRun(plan) {\n    let done = [];\n    let failed = [];\n    if (plan.identity.layers.length > 0) {\n      const w = NarzedziaProjektu.repairIdentityWithBackup(qgisProject);\n      (w.ok ? done : failed).push(w.opis);\n    }\n    for (const m of plan.modules) {\n      const w = autoEquipCatalog.zaloz(qgisProject, m.modul);\n      (w.ok ? done : failed).push(m.nazwa + ": " + w.opis);\n    }\n    const saved = ProjectUtils.saveProject(qgisProject);\n    console.log("WorkField [WF-AUTO-EQUIP]: zrobione: " + done.join(" | ") + (failed.length ? " BŁĘDY: " + failed.join(" | ") : "") + ", zapis " + saved);\n    if (failed.length > 0 || !saved)\n      displayToast(qsTr("Uzupełnianie projektu nie w pełni się udało: %1").arg(failed.length ? failed.join("; ") : qsTr("projektu nie zapisano")), "warning");\n    else\n      displayToast(qsTr("Uzupełniono identyfikatory i wyposażenie projektu. Możesz to wyłączyć w Ustawieniach → Teren."));\n    if (typeof dashBoard !== "undefined" && dashBoard.odswiezWyposazenie)\n      dashBoard.odswiezWyposazenie();\n  }\n\n  property string projectTitle: ""\n  function refreshProjectTitle() {'),
    ('          } else if (basemap.dodano) {\n            console.log("WorkField [WF-OSM-VECTOR]: load — projekt miał niezapisane zmiany, nie zapisuję");\n          }\n',
     '          } else if (basemap.dodano) {\n            console.log("WorkField [WF-OSM-VECTOR]: load — projekt miał niezapisane zmiany, nie zapisuję");\n          }\n          // [WF-AUTO-EQUIP] 24.11.2026 — identyfikatory i wyposażenie\n          try {\n            mainWindow.autoEquipCheck();\n          } catch (e) {\n            console.log("WorkField [WF-AUTO-EQUIP]: failed: " + e);\n          }\n'),
    ('    if (typeof NarzedziaProjektu !== "undefined")\n      NarzedziaProjektu.zapiszProjekt(qgisProject);\n',
     '    if (typeof NarzedziaProjektu !== "undefined")\n      NarzedziaProjektu.zapiszProjekt(qgisProject);\n\n    // [WF-AUTO-EQUIP] 24.11.2026 — warstwy robocze powstały PO sprawdzeniu przy\n    // otwarciu; są puste, więc identyfikatory dostają od razu, bez pytania.\n    mainWindow.autoEquipCheck();\n'),
    ('        if (!o.length)\n          return;\n        // Pierwsze ostrzezenie w calosci: sama liczba nie mowi, czy chodzi',
     '        if (!o.length)\n          return;\n        // [WF-AUTO-EQUIP] 24.11.2026 — pytanie o uzupełnienie jest otwarte:\n        // drugi komunikat o tym samym tylko by straszył.\n        if (autoEquipDialog.visible)\n          return;\n        // Pierwsze ostrzezenie w calosci: sama liczba nie mowi, czy chodzi'),
    ('  QfWyposazenie {\n    id: ekranWyposazenia\n',
     '  // [WF-AUTO-EQUIP] 24.11.2026 — ten sam katalog modułów co okno Wyposażenia.\n  Wyposazenie {\n    id: autoEquipCatalog\n  }\n\n  QfDialog {\n    id: autoEquipDialog\n    parent: mainWindow.contentItem\n    anchors.centerIn: parent\n    width: Math.min(520, mainWindow.width - 32)\n    modal: true\n    closePolicy: Popup.NoAutoClose\n    title: qsTr("Uzupełnić projekt?")\n    standardButtons: Dialog.Ok | Dialog.Cancel\n\n    function planText() {\n      const p = mainWindow.autoEquipPlan;\n      if (!p)\n        return "";\n      let lines = [];\n      if (p.identity.layers.length > 0)\n        lines.push(qsTr("• identyfikatory obiektów (pole uuid) w warstwach: %1").arg(p.identity.layers.join(", ")));\n      for (const m of p.modules)\n        lines.push(m.stan === "starszy" ? qsTr("• %1 — nowsza wersja").arg(m.nazwa) : qsTr("• %1").arg(m.nazwa));\n      return lines.join("\\n");\n    }\n\n    // QfDialog shows the answers in its title bar: ✕ = not now, ✓ + this text = yes.\n    onAboutToShow: {\n      const ok = standardButton(Dialog.Ok);\n      if (ok)\n        ok.text = qsTr("Uzupełnij");\n      _yesText = qsTr("Uzupełnij");\n    }\n    onAccepted: {\n      const p = mainWindow.autoEquipPlan;\n      mainWindow.autoEquipPlan = null;\n      if (p)\n        mainWindow.autoEquipRun(p);\n    }\n    onRejected: {\n      mainWindow.autoEquipPlan = null;\n      console.log("WorkField [WF-AUTO-EQUIP]: odłożone przez użytkownika");\n    }\n\n    Column {\n      width: parent.width\n      spacing: 10\n\n      Text {\n        width: parent.width\n        wrapMode: Text.Wrap\n        color: Theme.mainTextColor\n        font: Theme.tipFont\n        text: qsTr("W projekcie brakuje:") + "\\n" + autoEquipDialog.planText()\n      }\n\n      Text {\n        width: parent.width\n        wrapMode: Text.Wrap\n        color: Theme.secondaryTextColor\n        font: Theme.tinyFont\n        text: qsTr("Atrybuty i geometria się nie zmieniają. Przedtem powstaje kopia bazy i projektu w katalogu „kopie” obok projektu. Jeśli projekt jest też na innych telefonach, uzupełnij go na wszystkich — wtedy wszystkie mają tę samą budowę bazy. Automat wyłączysz w Ustawieniach → Teren.")\n      }\n    }\n  }\n\n  QfWyposazenie {\n    id: ekranWyposazenia\n'),
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
