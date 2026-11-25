#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[WF-CONTENT-COPY] 25.11.2026 — okno „Pliki”: plik z okna systemowego Androida.

Okno systemowe („Pamięć telefonu…”, „Pobrane ↗”) oddaje odnośnik content://,
a nie ścieżkę; GDAL/OGR go nie otworzy („OGR: Cannot open content://…”,
Piotr 10:56 — „Dodaj z pliku” GPKG/GeoJSON). Plik jest najpierw kopiowany do
„Imported Datasets” w katalogu aplikacji, dalej idzie kopia. Na komputerze
(zwykłe ścieżki) nic się nie zmienia.

Domyślnie próba. Zapis: --zapisz. Test na kopii: --plik X.
Miejsce w repo: skrypty/jednorazowe/2026-11-25_instaluj_pliki_content_kopia.py
"""
import hashlib
import shutil
import sys
import time

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfFileBrowser.qml"
MD5_PRZED = "621015d9d013f3676881771e975f17ed"
MD5_PO = "687a3f6ef4dda20b864518fb8c744f3e"

C1_STARE = '''  function stripUrl(u) {
    return String(u).replace(/^file:\\/\\//, "").replace(/\\/+$/, "");
  }
'''
C1_NOWE = C1_STARE + '''
  /**
   * [WF-CONTENT-COPY] 25.11.2026 — the Android system window gives a
   * content:// link, not a path, and GDAL/OGR cannot open it
   * („OGR: Cannot open content://…/document/2773”, Piotr 10:56: „Dodaj
   * z pliku” GPKG / GeoJSON from Pobrane). The file is copied first into the
   * app's "Imported Datasets" folder (where QField's own import puts files)
   * and the copy goes on. FileUtils.fileName() gives the document's display
   * name for a content:// link (the pattern check passed with it at 10:56).
   * Returns the local path, the same path when it is not content://, or ""
   * when copying failed.
   */
  function localCopy(path) {
    if (!/^content:/i.test(path))
      return path;
    const name = FileUtils.fileName(path);
    const root = stripUrl(iface.dataRoot());
    platformUtilities.createDir(root, "Imported Datasets");
    const dir = root + "/Imported Datasets";
    const dot = name.lastIndexOf(".");
    const base = dot > 0 ? name.substring(0, dot) : name;
    const ext = dot > 0 ? name.substring(dot) : "";
    let target = dir + "/" + name;
    for (let n = 2; FileUtils.fileExists(target) && n < 100; n++)
      target = dir + "/" + base + "_" + n + ext;
    if (!FileUtils.kopiujPlik(path, target, false)) {
      console.log("WorkField [WF-CONTENT-COPY]: kopia nie wyszła: " + path + " -> " + target);
      return "";
    }
    console.log("WorkField [WF-CONTENT-COPY]: " + path + " -> " + target);
    return target;
  }
'''

C2_STARE = '''      const path = String(selectedFile).replace(/^file:\\/\\//, "");
      if (browser.mode === "browse") {
        // browsing a place the app cannot list (phone): act on the chosen file
        browser.activate(FileUtils.fileName(path), path, false);
        return;
      }
      if (!browser.matches(FileUtils.fileName(path), false)) {
        browser.say(qsTr("Ten plik się nie nadaje: %1").arg(FileUtils.fileName(path)), true);
        return;
      }
      browser.finishPick(path);
'''
C2_NOWE = '''      const path = String(selectedFile).replace(/^file:\\/\\//, "");
      const name = FileUtils.fileName(path);
      if (browser.mode === "browse") {
        // browsing a place the app cannot list (phone): act on the chosen file;
        // data files first get a local copy [WF-CONTENT-COPY]
        if (browser.dataPattern.test(name)) {
          const copied = browser.localCopy(path);
          if (copied === "") {
            browser.say(qsTr("Nie udało się skopiować pliku z pamięci telefonu: %1").arg(name), true);
            return;
          }
          browser.activate(name, copied, false);
          return;
        }
        browser.activate(name, path, false);
        return;
      }
      if (!browser.matches(name, false)) {
        browser.say(qsTr("Ten plik się nie nadaje: %1").arg(name), true);
        return;
      }
      // [WF-CONTENT-COPY] the caller gets a real path, not content://
      const local = browser.localCopy(path);
      if (local === "") {
        browser.say(qsTr("Nie udało się skopiować pliku z pamięci telefonu: %1").arg(name), true);
        return;
      }
      browser.finishPick(local);
'''
ZMIANY = [(C1_STARE, C1_NOWE), (C2_STARE, C2_NOWE)]


def md5(dane):
    return hashlib.md5(dane).hexdigest()


def przygotuj(sciezka, przed, po, zmiany, nazwa):
    """Zwraca (stan, nowe_bajty). stan: 'gotowe', 'juz', 'stop'."""
    try:
        bajty = open(sciezka, "rb").read()
    except OSError as e:
        print("STOP: nie mogę odczytać " + sciezka + ": " + str(e))
        return "stop", None
    m = md5(bajty)
    if m == po:
        print(nazwa + ": JUŻ ZAINSTALOWANE (" + m + ")")
        return "juz", None
    if m != przed:
        print("STOP: " + nazwa + " ma md5 " + m + ", oczekiwane " + przed + ". Nie nadpisuję cudzej pracy.")
        return "stop", None
    tekst = bajty.decode("utf-8")
    for stare, _ in zmiany:
        n = tekst.count(stare)
        if n != 1:
            print("STOP: " + nazwa + ": kotwica występuje " + str(n) + " razy: " + repr(stare[:70]))
            return "stop", None
    for stare, nowe in zmiany:
        tekst = tekst.replace(stare, nowe, 1)
    nowe_bajty = tekst.encode("utf-8")
    linii = tekst.count("\n")
    print(nazwa + ": md5 po zmianie " + md5(nowe_bajty) + ", linii " + str(linii) + " (oczekiwane " + po + ")")
    return "gotowe", nowe_bajty


def main():
    arg = sys.argv[1:]
    plik = arg[arg.index("--plik") + 1] if "--plik" in arg else PLIK
    stan, bajty = przygotuj(plik, MD5_PRZED, MD5_PO, ZMIANY, "QfFileBrowser.qml")
    if stan == "stop":
        return 1
    if stan == "juz":
        return 0
    if md5(bajty) != MD5_PO:
        print("STOP: wynik różni się od oczekiwanego — nie zapisuję.")
        return 1
    if "--zapisz" not in arg:
        print("PRÓBA — nic nie zapisano. Zapis: --zapisz")
        return 0
    kopia = plik + ".przed_" + time.strftime("%Y%m%d_%H%M%S")
    shutil.copy2(plik, kopia)
    with open(plik, "wb") as f:
        f.write(bajty)
    print("ZAPISANO " + plik + " (kopia: " + kopia + ")")
    return 0


if __name__ == "__main__":
    sys.exit(main())
