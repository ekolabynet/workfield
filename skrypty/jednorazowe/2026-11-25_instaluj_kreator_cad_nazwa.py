#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[WF-CAD-NAME-TAKEN] 25.11.2026 — kreator „Projekt z rysunku CAD” przy zajętej nazwie.

FileUtils.fileExists() zwraca prawdę tylko dla pliku, a projekt to katalog —
sprawdzenie „Projekt o tej nazwie już istnieje” nigdy nie działało, więc przy
zajętej nazwie wychodziło ogólne „Nie udało się utworzyć projektu”. Do tego
czerwony komunikat zostawał po zmianie nazwy.

Domyślnie próba. Zapis: --zapisz. Test na kopii: --plik X.
Miejsce w repo: skrypty/jednorazowe/2026-11-25_instaluj_kreator_cad_nazwa.py
"""
import hashlib
import shutil
import sys
import time

PLIK = "/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfProjektZCAD.qml"
MD5_PRZED = "176f3897950820740936135d7c5df02b"
MD5_PO = "95d4ba1dfbb7a65b410afab4119139ce"

K1_STARE = '''    const cel = katalogProjektow + "/" + nazwa;
    if (FileUtils.fileExists(cel)) {
      komunikat.text = qsTr("Projekt o tej nazwie już istnieje.");
      return;
    }
'''
K1_NOWE = '''    const cel = katalogProjektow + "/" + nazwa;
    // [WF-CAD-NAME-TAKEN] 25.11.2026 — FileUtils.fileExists() mówi „tak” tylko
    // dla PLIKU, a projekt to KATALOG: sprawdzenie nigdy nie działało i przy
    // zajętej nazwie wychodziło ogólne „Nie udało się utworzyć projektu”
    // (Piotr 7:37, Adamowizna „_1”). Pytamy o pliki, które w nim leżą.
    if (FileUtils.fileExists(cel) || FileUtils.fileExists(cel + "/projekt.qgs")
        || FileUtils.fileExists(cel + "/projekt.qgz") || FileUtils.fileExists(cel + "/dane.gpkg")) {
      komunikat.text = qsTr("Projekt „%1” już istnieje. Zmień nazwę.").arg(nazwa);
      return;
    }
'''

K2_STARE = '''    if (plikProjektu === "") {
      komunikat.text = qsTr("Nie udało się utworzyć projektu.");
      return;
    }
'''
K2_NOWE = '''    if (plikProjektu === "") {
      // [WF-CAD-NAME-TAKEN] nowyProjekt() odmawia też, gdy katalog już jest
      // (np. pusty, po nieudanej próbie) — mówimy, gdzie patrzeć.
      komunikat.text = qsTr("Nie udało się utworzyć projektu. Jeśli w %1 jest już katalog „%2”, zmień nazwę.")
                         .arg(katalogProjektow).arg(nazwa);
      return;
    }
'''

K3_STARE = '''    placeholderText: qsTr("Nazwa projektu")
    font: Theme.tipFont
'''
K3_NOWE = '''    placeholderText: qsTr("Nazwa projektu")
    font: Theme.tipFont
    // [WF-CAD-NAME-TAKEN] stary komunikat znika przy zmianie nazwy — wcześniej
    // zostawał i wyglądało, że nowa nazwa też nie przeszła.
    onTextEdited: komunikat.text = ""
'''
ZMIANY = [(K1_STARE, K1_NOWE), (K2_STARE, K2_NOWE), (K3_STARE, K3_NOWE)]


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
    stan, bajty = przygotuj(plik, MD5_PRZED, MD5_PO, ZMIANY, "QfProjektZCAD.qml")
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
