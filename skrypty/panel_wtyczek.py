#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Panel z QR-kodami do wtyczek WorkField.

Czyta katalog `plugins/` w repo i buduje z niego stronę A4 z kartami wtyczek.
Wersja bierze się Z NAZWY PLIKU, nie z opisu — bo nazwa jest tym, co naprawdę
leży na gałęzi `plugins`, a opis bywa nieaktualny (karta z 08.09 zapowiadała
Konsolę v0.2, gdy na telefonie stała juz v0.3).

    python3 skrypty/panel_wtyczek.py                 # HTML do /tmp
    python3 skrypty/panel_wtyczek.py --pdf           # + PDF, jesli jest weasyprint
    python3 skrypty/panel_wtyczek.py --plik out.html

Opisy sa TUTAJ, nizej. Wtyczka bez opisu i tak trafi na strone — z pusta
trescia i widoczna dziura, zeby nie dalo sie o niej zapomniec.
"""

import argparse
import base64
import glob
import io
import os
import re
import sys

try:
    import qrcode
except ImportError:
    sys.exit("Brakuje biblioteki: pip install qrcode pillow --break-system-packages")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADRES = "https://raw.githubusercontent.com/ekolabynet/workfield/plugins/{}"

# rdzen nazwy pliku -> (tytul, jedno zdanie, lista punktow)
OPISY = {
    "konsola": (
        "Konsola",
        "Naprawa bazy i aplikacji z telefonu",
        [
            "zakładka <b>Baza (SQL)</b> — stan bazy, indeksy przestrzenne, dowolne zapytanie",
            "zakładka <b>Aplikacja (kod)</b> — zmiany w warstwach, style, wszystko co aplikacja umie",
            "kopia bazy i projektu przed każdą zmianą, w katalogu <code>kopie/</code>",
            "DOMYŚLNIE WYŁĄCZONA — włącz przytrzymaniem ikony",
        ],
    ),
    "gugik": (
        "GUGiK — działki",
        "Pobieranie działek ewidencyjnych z ULDK",
        [
            "tapnięcie w mapę pobiera działkę spod palca",
            "zapis do warstwy <code>REF_dzialki</code> — tworzy ją, jeśli nie ma",
            "pole <code>POW_M2</code> liczone z wierzchołków, cały wiersz w <code>SUROWE</code>",
            "wymaga zasięgu — w terenie bez sieci nie zadziała",
        ],
    ),
    "plantnet": (
        "Pl@ntNet",
        "Rozpoznawanie roślin ze zdjęcia",
        [
            "zdjęcie z aparatu albo z galerii, kandydaci z procentem pewności",
            "region i klucz API z ustawień <code>WorkFieldPlantNet/*</code>",
            "wynik dopisywany jako tag zdjęcia",
            "wymaga zasięgu i klucza API",
        ],
    ),
}

STYL = """
  @page { size: A4; margin: 12mm; }
  body { font-family: "DejaVu Sans", sans-serif; color: #1a1a1a; margin: 0; }
  h1 { font-size: 20pt; margin: 0 0 2mm 0; }
  .wstep { font-size: 9pt; color: #555; margin: 0 0 6mm 0; line-height: 1.5; }
  .karta { display: flex; gap: 6mm; border: 1px solid #bbb; border-radius: 3mm;
           padding: 4mm 5mm; margin-bottom: 4mm; page-break-inside: avoid;
           align-items: flex-start; }
  .tresc { flex: 1; }
  h2 { font-size: 13pt; margin: 0 0 1mm 0; }
  .wersja { font-size: 9pt; color: #777; font-weight: normal; }
  .opis { font-size: 10pt; margin: 0 0 2mm 0; color: #333; }
  ul { margin: 0 0 2mm 0; padding-left: 5mm; font-size: 8.5pt; line-height: 1.45; }
  li { margin-bottom: 0.6mm; }
  .brak { font-size: 9pt; color: #b00; margin: 0 0 2mm 0; }
  .url { font-family: monospace; font-size: 6.5pt; color: #888;
         word-break: break-all; margin: 0; }
  .qr img { width: 30mm; height: 30mm; }
  .stopka { font-size: 8pt; color: #666; margin-top: 5mm; line-height: 1.6;
            border-top: 1px solid #ddd; padding-top: 3mm; }
  .stopka strong { color: #333; }
"""


def kod_qr(tekst):
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,
                      box_size=10, border=2)
    q.add_data(tekst)
    q.make(fit=True)
    buf = io.BytesIO()
    q.make_image(fill_color="black", back_color="white").save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def rozbierz(nazwa):
    """workfield-konsola-v0.3.zip -> ('konsola', 'v0.3')"""
    m = re.match(r"workfield-(.+?)-(v[\d.]+)\.zip$", nazwa)
    if m:
        return m.group(1), m.group(2)
    return os.path.splitext(nazwa)[0], ""


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--katalog", default=os.path.join(REPO, "plugins"))
    a.add_argument("--plik", default="/tmp/wtyczki_workfield.html")
    a.add_argument("--pdf", action="store_true")
    args = a.parse_args()

    zipy = sorted(glob.glob(os.path.join(args.katalog, "*.zip")))
    if not zipy:
        sys.exit("Brak zipow w %s" % args.katalog)

    # jedna wtyczka moze miec kilka wersji w katalogu — bierzemy najnowsza
    najnowsze = {}
    for z in zipy:
        rdzen, wersja = rozbierz(os.path.basename(z))
        if rdzen not in najnowsze or wersja > najnowsze[rdzen][1]:
            najnowsze[rdzen] = (z, wersja)

    karty = []
    for rdzen in sorted(najnowsze):
        sciezka, wersja = najnowsze[rdzen]
        plik = os.path.basename(sciezka)
        url = ADRES.format(plik)
        tytul, opis, punkty = OPISY.get(rdzen, (rdzen, "", []))
        if opis:
            srodek = ('<p class="opis">%s</p><ul>%s</ul>'
                      % (opis, "".join("<li>%s</li>" % p for p in punkty)))
        else:
            srodek = ('<p class="brak">BRAK OPISU — dopisz w '
                      'skrypty/panel_wtyczek.py, slownik OPISY</p>')
        karty.append(
            '<div class="karta"><div class="tresc">'
            '<h2>%s <span class="wersja">%s</span></h2>%s'
            '<p class="url">%s</p></div>'
            '<div class="qr"><img src="data:image/png;base64,%s"></div></div>'
            % (tytul, wersja, srodek, url, kod_qr(url)))
        print("  %-12s %-6s %s" % (rdzen, wersja, plik))

    html = """<!DOCTYPE html>
<html lang="pl"><head><meta charset="utf-8">
<title>WorkField — wtyczki</title><style>%s</style></head><body>
<h1>WorkField — wtyczki</h1>
<p class="wstep">
Instalacja: <strong>Ustawienia → Wtyczki → Install plugin from URL</strong>,
zeskanuj kod i wklej adres. Po instalacji <strong>włącz suwakiem</strong>
na liście — sama instalacja nie wystarczy.<br>
Adresy wskazują gałąź <code>plugins</code> i niosą numer wersji w nazwie pliku,
więc ten kod prowadzi zawsze do tej samej wersji.
</p>
%s
<p class="stopka">
<strong>Gdy instalator powie „Network error"</strong> — to najczęściej 404,
czyli pliku nie ma pod tym adresem, a nie błąd sieci.
Sprawdzenie z komputera:
<code>curl -s -o /dev/null -w "%%{http_code}" ADRES</code><br>
<strong>Każda wersja to nowa nazwa pliku.</strong> Nadpisanie zipa tą samą nazwą
grozi wciągnięciem starej wersji — raw.githubusercontent cache'uje kilka minut.
</p>
</body></html>""" % (STYL, "\n".join(karty))

    with open(args.plik, "w", encoding="utf-8") as f:
        f.write(html)
    print("\nHTML: %s" % args.plik)

    if args.pdf:
        cel = os.path.splitext(args.plik)[0] + ".pdf"
        try:
            from weasyprint import HTML
            HTML(string=html).write_pdf(cel)
            print("PDF:  %s" % cel)
        except ImportError:
            print("PDF pominiety — brak weasyprint.")
            print("  pip install weasyprint --break-system-packages")
            print("  albo otworz HTML w przegladarce i wydrukuj do PDF")


if __name__ == "__main__":
    main()
