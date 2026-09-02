#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — `QfPlantNet`: rozpoznawanie gatunku jako KOMPONENT.

==========================================================================
PO CO
==========================================================================
Piotr, 01.09.2026, z terenu:

  „To sie przydaje przy dzialaniu z uzyciem paska QCapture:
   klikamy G, robimy zdjecie, otwiera sie formularz gdzie mozna wpisac
   nazwe, warstwe i pokrycie. Gdybysmy tu mieli mozliwosc od razu
   oznaczenia gatunku z Pl@ntNet, mozna by bylo umiescic nazwe w polu."

Zdjecie jest juz zrobione i podpiete do obiektu. Rozpoznanie ma czego
dotyczyc, a wynik ma gdzie trafic — wprost do pola `GATUNEK`.

==========================================================================
DLACZEGO KOMPONENT, A NIE DRUGA KOPIA
==========================================================================
Mechanizm ISTNIEJE w `QfPhotoGallery.qml` — klucz API, wybor flory,
organ, kadrowanie, szesc wynikow, dopasowanie do slownika. Ale jest
**spleciony z galeria**: czyta `viewer.cur` (biezace zdjecie w podgladzie),
`suggestions` (slownik galerii) i `tagStore`.

Napisanie tego drugi raz dalo by dwie kopie rozjezdzajace sie przy pierwszej
zmianie — a takie rozjazdy sa najgorsze, bo obie drogi wygladaja identycznie.

Stad **bezglowy komponent**: sama rozmowa z API, bez interfejsu. Przyjmuje
sciezke do zdjecia, oddaje liste kandydatow.

==========================================================================
CZEGO TA LATKA NIE ROBI — swiadomie
==========================================================================
**Nie rusza galerii.** Galeria dziala i jest sprawdzona w terenie; przepisanie
jej na komponent, gdy Piotr jest w polu, to ryzyko bez potrzeby. Zostaje jako
druga sciezka do czasu, az formularz sie potwierdzi — potem migracja.

To swiadoma duplikacja na czas przejsciowy, nie przeoczenie. Wpisana tutaj,
zeby za miesiac bylo wiadomo, ze to nie jest stan docelowy.

**Nie dopasowuje do slownika.** Galeria robi to przez `suggestions`, ktore
sa jej wlasne. W formularzu slownik przychodzi inaczej — to nastepny krok,
po sprawdzeniu, ze samo rozpoznawanie dziala.

==========================================================================
USTAWIENIA — WSPOLNE Z GALERIA I WTYCZKA
==========================================================================
Klucz API, flora i organ czytane z tych samych kluczy `WorkFieldPlantNet/*`.
Czlowiek ustawia je RAZ; trzy miejsca korzystaja z jednego zrodla.

Uruchom w korzeniu repo:  python3 zastosuj_plantnet_komponent.py
Idempotentna.
"""
import os
import shutil
import sys

KOMPONENT = "src/gui/qml/QfPlantNet.qml"
CMAKE = "src/gui/qml/CMakeLists.txt"

TRESC = '''import QtQuick

import org.qfield
import Theme

/**
 * Rozpoznawanie gatunku przez Pl@ntNet — bez interfejsu.
 *
 * Przyjmuje ścieżkę do zdjęcia, oddaje listę kandydatów. Kto go używa,
 * ten rysuje wyniki po swojemu — galeria inaczej niż formularz.
 *
 * Ustawienia (klucz API, flora, organ) wspólne z galerią i wtyczką:
 * człowiek wpisuje klucz RAZ, trzy miejsca czytają z `WorkFieldPlantNet/*`.
 *
 * Użycie:
 *
 *     QfPlantNet {
 *       id: rozpoznanie
 *       onGotowe: (kandydaci) => { ... }
 *       onBlad: (tekst) => displayToast(tekst, "warning")
 *     }
 *     rozpoznanie.identyfikuj(sciezkaZdjecia);
 */
Item {
  id: pn

  //! Trwa zapytanie — do wyszarzenia przycisku i pokazania kręcioła.
  property bool pracuje: false

  //! Ostatni komunikat dla człowieka (także przy powodzeniu: pusty).
  property string stan: ""

  //! Lista kandydatów: [{ score, lacina, ludowa }], najlepszy pierwszy.
  property var kandydaci: []

  //! Organy honorowane przez API. Przełączane z zewnątrz.
  readonly property var organy: ["leaf", "flower", "fruit", "bark"]
  readonly property var organyPL: ({
      "leaf": qsTr("liść"),
      "flower": qsTr("kwiat"),
      "fruit": qsTr("owoc"),
      "bark": qsTr("kora")
    })

  signal gotowe(var kandydaci)
  signal blad(string tekst)

  function klucz() {
    return String(settings.value("WorkFieldPlantNet/apiKey", "")).trim();
  }

  function organ() {
    return String(settings.value("WorkFieldPlantNet/organ", "leaf"));
  }

  /**
   * Flora do zapytania. `auto-geo` znaczy „ta, którą wtyczka ustaliła dziś
   * z pozycji" — bo ustalenie z GPS jest dobre przez cały dzień w tym samym
   * terenie. Bez niej bezpieczny domysł dla Polski.
   */
  function flora() {
    const tryb = String(settings.value("WorkFieldPlantNet/flora", "auto-geo"));
    if (tryb !== "auto-geo")
      return tryb;
    const d = new Date();
    const dzis = d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    if (String(settings.value("WorkFieldPlantNet/autoFloraDay", "")) === dzis) {
      const id = String(settings.value("WorkFieldPlantNet/autoFloraId", ""));
      if (id !== "")
        return id;
    }
    return "k-middle-europe";
  }

  function _bajty(txt) {
    const u = unescape(encodeURIComponent(txt));
    const arr = new Uint8Array(u.length);
    for (let i = 0; i < u.length; i++)
      arr[i] = u.charCodeAt(i);
    return arr;
  }

  /**
   * Wysyła zdjęcie do rozpoznania.
   *
   * Odmawia GŁOŚNO, gdy nie ma klucza albo zdjęcia — cicha odmowa
   * wyglądałaby jak zawieszenie, a w terenie to strata minuty na
   * sprawdzanie, czy w ogóle działa.
   */
  function identyfikuj(sciezka) {
    if (pracuje)
      return;
    if (!sciezka || String(sciezka) === "") {
      stan = qsTr("Nie ma zdjęcia do rozpoznania.");
      blad(stan);
      return;
    }
    if (klucz() === "") {
      stan = qsTr("Brak klucza API Pl@ntNet — wpisz go w ustawieniach (konto: my.plantnet.org).");
      blad(stan);
      return;
    }

    pracuje = true;
    kandydaci = [];
    stan = qsTr("Czytam zdjęcie…");

    const zawartosc = FileUtils.readFileContent(sciezka);
    const dlugosc = (zawartosc && zawartosc.byteLength !== undefined) ? zawartosc.byteLength : -1;
    if (dlugosc <= 0) {
      pracuje = false;
      stan = qsTr("Zdjęcie nieczytelne: ") + sciezka;
      blad(stan);
      return;
    }

    const org = organ();
    const granica = "----WorkFieldPlantNet" + Date.now();
    const czesci = [];
    czesci.push(_bajty("--" + granica + "\\r\\n"
                       + \'Content-Disposition: form-data; name="organs"\\r\\n\\r\\n\'
                       + org + "\\r\\n"
                       + "--" + granica + "\\r\\n"
                       + \'Content-Disposition: form-data; name="images"; filename="\'
                       + FileUtils.fileName(sciezka) + \'"\\r\\n\'
                       + "Content-Type: image/jpeg\\r\\n\\r\\n"));
    czesci.push(new Uint8Array(zawartosc));
    czesci.push(_bajty("\\r\\n--" + granica + "--\\r\\n"));

    let suma = 0;
    for (let i = 0; i < czesci.length; i++)
      suma += czesci[i].length;
    const cialo = new Uint8Array(suma);
    let od = 0;
    for (let i = 0; i < czesci.length; i++) {
      cialo.set(czesci[i], od);
      od += czesci[i].length;
    }

    stan = qsTr("Pytam Pl@ntNet (%1 KB, %2, %3)…")
           .arg(Math.round(dlugosc / 1024)).arg(organyPL[org]).arg(flora());

    const url = "https://my-api.plantnet.org/v2/identify/"
              + encodeURIComponent(flora())
              + "?api-key=" + encodeURIComponent(klucz())
              + "&lang=pl&nb-results=6";

    const xhr = new XMLHttpRequest();
    xhr.open("POST", url);
    xhr.timeout = 60000;
    xhr.ontimeout = function () {
      pn.pracuje = false;
      pn.stan = qsTr("Serwer nie odpowiedział w 60 s — sprawdź zasięg.");
      pn.blad(pn.stan);
    };
    xhr.setRequestHeader("Content-Type", "multipart/form-data; boundary=" + granica);
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return;
      pn.pracuje = false;
      if (xhr.status === 200) {
        pn._rozbierz(xhr.responseText);
        return;
      }
      // Każdy kod mówi co innego i wymaga czego innego od człowieka —
      // stąd osobne komunikaty zamiast jednego „błąd".
      if (xhr.status === 401)
        pn.stan = qsTr("Błędny klucz API (401) — sprawdź na my.plantnet.org.");
      else if (xhr.status === 404)
        pn.stan = qsTr("Brak dopasowania w tej florze (404).");
      else if (xhr.status === 413)
        pn.stan = qsTr("Zdjęcie za duże (413).");
      else if (xhr.status === 429)
        pn.stan = qsTr("Wyczerpany dzienny limit zapytań (429).");
      else if (xhr.status === 0)
        pn.stan = qsTr("Brak sieci — spróbuj przy zasięgu.");
      else
        pn.stan = qsTr("Błąd serwera: ") + xhr.status;
      pn.blad(pn.stan);
    };
    xhr.send(cialo.buffer);
  }

  function _rozbierz(tekst) {
    try {
      const json = JSON.parse(tekst);
      const wyniki = json.results || [];
      if (wyniki.length === 0) {
        stan = qsTr("Brak wyników.");
        blad(stan);
        return;
      }
      const out = [];
      for (let i = 0; i < wyniki.length && i < 6; i++) {
        const r = wyniki[i];
        const gat = r.species || ({});
        out.push({
            "score": Math.round((r.score || 0) * 100),
            "lacina": String(gat.scientificNameWithoutAuthor || "").trim(),
            "ludowa": (gat.commonNames || []).slice(0, 2).join(", ")
          });
      }
      stan = "";
      kandydaci = out;
      gotowe(out);
    } catch (e) {
      stan = qsTr("Nieczytelna odpowiedź serwera.");
      blad(stan);
    }
  }
}
'''


def main():
    if os.path.exists(KOMPONENT):
        print("Komponent juz jest — nic do zrobienia.")
        return

    os.makedirs(os.path.dirname(KOMPONENT), exist_ok=True)
    open(KOMPONENT, "w", encoding="utf-8").write(TRESC)
    print("   %s (nowy)" % os.path.basename(KOMPONENT))

    if os.path.exists(CMAKE):
        c = open(CMAKE, encoding="utf-8").read()
        if "QfPlantNet.qml" not in c:
            linie = c.splitlines(keepends=True)
            gdzie = -1
            for nr, linia in enumerate(linie):
                nazwa = linia.strip().rstrip(")")
                if nazwa.startswith("Qf") and nazwa.endswith(".qml") \
                        and "/" not in nazwa and nazwa > "QfPlantNet.qml":
                    gdzie = nr
                    break
            if gdzie < 0:
                for nr in range(len(linie) - 1, -1, -1):
                    nazwa = linie[nr].strip().rstrip(")")
                    if nazwa.startswith("Qf") and nazwa.endswith(".qml") and "/" not in nazwa:
                        gdzie = nr + 1
                        break
            if gdzie >= 0:
                linie.insert(gdzie, "    QfPlantNet.qml\n")
                kopia = CMAKE + ".przed_plantnet"
                if not os.path.exists(kopia):
                    shutil.copy2(CMAKE, kopia)
                open(CMAKE, "w", encoding="utf-8").write("".join(linie))
                print("   dopisany do CMakeLists")
            else:
                print("   UWAGA: dopisz QfPlantNet.qml do %s RECZNIE" % CMAKE)

    print("""
Sam komponent NICZEGO JESZCZE NIE ROBI — to tylko silnik. Wpiecie
w formularz to osobny krok i wymaga dwoch decyzji:

  1. GDZIE przycisk — przy polu FOTO czy w gornym pasku formularza?
  2. DO KTOREGO POLA wpisac wynik — `GATUNEK` na sztywno, czy z ustawien
     warstwy, zeby dzialalo takze w `zdjecia_fito` i `platy_zalazki`?

Build (sam komponent nie zmienia zachowania):
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head -3
""")


if __name__ == "__main__":
    main()
