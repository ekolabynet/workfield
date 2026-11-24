#!/usr/bin/env python3
"""WorkFieldGIS 24.11.2026 — [WF-LAZY-SOUNDS] odtwarzacz dźwięków tworzony przy pierwszym dźwięku.

Refaktoryzacja okna głównego, krok R2.3, pierwszy wynikający z profilu startu (qmlprofiler,
laptop, 24.11.2026): pierwszy MediaPlayer w bloku [WF-SOUNDS] kosztował 497 ms z ok. 2,45 s
tworzenia okna QML, bo uruchamia silnik Qt Multimedia. Teraz oba odtwarzacze (RTK i przyciski)
siedzą w Loaderach i powstają przy pierwszym zagraniu. Przy wyłączonych dźwiękach silnik nie
startuje wcale. Pierwszy dźwięk w sesji zagra z jednorazowym opóźnieniem.

Użycie (z katalogu repozytorium):
  python3 instaluj_dzwieki_leniwie.py            # próba, nic nie zapisuje
  python3 instaluj_dzwieki_leniwie.py --zapisz   # zapis (z kopią .przed_*)
  python3 instaluj_dzwieki_leniwie.py --plik X   # inny plik (test)
"""
import hashlib
import os
import shutil
import sys
from datetime import datetime

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QgisMobileapp.qml"
MD5_PRZED = "60550e49d019713abbcf31084a0db7ec"  # po łatce R2.2 (2026-11-24_instaluj_pliki_leniwie.py)
MD5_PO = "9c3e636fdcd4da2d21a5fcc1494bb22d"

ZMIANY = [
    ('      gracz.zatrzymaj();\n      gracz.wyjscie.volume = Math.max(0, Math.min(100, settings.valueInt(\'WorkField/dzwiekiGlosnosc\', 70))) / 100;\n      gracz.odtwarzacz.source = "qrc:/sounds/wtk/" + pliki[nazwa] + ".mp3";\n      gracz.odtwarzacz.play();\n',
     '      gracz.zatrzymaj();\n      const player = gracz.player(); // [WF-LAZY-SOUNDS]\n      player.audioOutput.volume = Math.max(0, Math.min(100, settings.valueInt(\'WorkField/dzwiekiGlosnosc\', 70))) / 100;\n      player.source = "qrc:/sounds/wtk/" + pliki[nazwa] + ".mp3";\n      player.play();\n'),
    ('    component Gracz: Item {\n      property alias odtwarzacz: mp\n      property alias wyjscie: out\n\n      function zatrzymaj() {\n        wyciszanie.stop();\n        zegar.stop();\n        mp.stop();\n      }\n',
     '    // WorkFieldGIS 24.11.2026 — [WF-LAZY-SOUNDS] odtwarzacz powstaje przy pierwszym dźwięku,\n    // nie przy starcie. Pierwszy MediaPlayer uruchamia silnik Qt Multimedia: w profilu startu\n    // (qmlprofiler, laptop) kosztowało to ok. 0,5 s, czyli ok. 20% tworzenia okna. Przy\n    // wyłączonych dźwiękach silnik nie startuje wcale. Pierwszy dźwięk w sesji zagra z tym\n    // jednorazowym opóźnieniem.\n    component Gracz: Item {\n      function player() {\n        playerLoader.active = true;\n        return playerLoader.item;\n      }\n\n      function zatrzymaj() {\n        wyciszanie.stop();\n        zegar.stop();\n        if (playerLoader.item)\n          playerLoader.item.stop();\n      }\n'),
    ('      MediaPlayer {\n        id: mp\n        audioOutput: AudioOutput {\n          id: out\n        }\n      }\n',
     '      Loader {\n        id: playerLoader\n        active: false\n        sourceComponent: Component {\n          MediaPlayer {\n            audioOutput: AudioOutput {}\n          }\n        }\n      }\n'),
    ('        id: wyciszanie\n        target: out\n        property: "volume"\n        to: 0\n        duration: 600\n        onFinished: mp.stop()\n',
     '        id: wyciszanie\n        target: playerLoader.item ? playerLoader.item.audioOutput : null\n        property: "volume"\n        to: 0\n        duration: 600\n        onFinished: {\n          if (playerLoader.item)\n            playerLoader.item.stop();\n        }\n'),
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
