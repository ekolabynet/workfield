#!/bin/bash
# WorkFieldGIS 22.09.2026 - POPRAWKA skrypty/wydaj.sh: DWA ZABEZPIECZENIA.
#
# CO POSZLO ZLE, NA ZYWYM REPO
# ----------------------------
# Wydanie 0.12.1 zostalo zrobione DWA RAZY. Przy drugim uruchomieniu:
#
#   1. Punkt odniesienia dla noty to najswiezszy tag — a najswiezszym
#      tagiem byl juz `v0.12.1`, czyli tag TEJ WLASNIE wydawanej wersji.
#      Nota wyszla „zmiany od 0.12.1” z jednym wpisem, ktorym byl komit
#      wydania. Opisywala sama siebie.
#
#   2. `gh release create` padlo na „Release.tag_name already exists”,
#      a zapasowe `gh release edit` PO CICHU NADPISALO dobra note ta
#      degeneracja. I to jest dokladnie ta tresc, ktora uzytkownik widzi
#      w oknie „Co nowego” — okno czyta wydania z GitHuba.
#
# CO SIE ZMIENIA
# --------------
#   1. Gdy najswiezszy tag to tag wydawanej wersji, punkt odniesienia
#      cofa sie o JEDEN tag i skrypt to mowi na ekranie.
#   2. `--wykonaj` na istniejacym tagu ZATRZYMUJE sie i podaje trzy wyjscia:
#      poprawic note istniejacego wydania, nadpisac je swiadomie
#      (`--nadpisz`), albo zbudowac i wydac nowy numer.
#
# Nadpisanie wydania przestalo byc czyms, co zdarza sie samo.
#
# Uruchom w katalogu repo. Idempotentny.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"
[ -f skrypty/wydaj.sh ] || { echo "STOP: nie ma skrypty/wydaj.sh"; exit 1; }

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64, os, zlib

LADUNEK = """\
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
+h5LBNNUsP4fPE8OqQ=="""

tresc = zlib.decompress(base64.b64decode(''.join(LADUNEK.split())))
cel = 'skrypty/wydaj.sh'
stara = open(cel, 'rb').read()
if stara == tresc:
    print('  bez zmian: %s (poprawka juz jest)' % cel)
else:
    open(cel, 'wb').write(tresc)
    os.chmod(cel, 0o755)
    print('  %s — poprawiony' % cel)
KONIEC_PY

echo
echo "=============================================================="
echo "NAPRAWA NOTY WYDANIA 0.12.1"
echo "=============================================================="
echo
echo "Nota na GitHubie jest teraz zdegenerowana. Zloz ja od nowa"
echo "od poprzedniego wydania i wyslij — BEZ tagowania:"
echo
echo "  bash skrypty/wydaj.sh --od=v0.12.0"
echo "  less docs/wydania/WhatsNew_0-12-1.md      # przeczytaj"
echo "  gh release edit v0.12.1 --notes-file docs/wydania/WhatsNew_0-12-1.md"
echo
echo "Potem sprawdz, co zobaczy aplikacja:"
echo "  curl -s https://api.github.com/repos/ekolabynet/workfield/releases/tags/v0.12.1 | head -30"
