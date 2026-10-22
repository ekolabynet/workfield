#!/bin/bash
# WorkFieldGIS 22.10.2026 [WF-EKSPORT-CAD] — kopia rdzenia WorkFieldCAD do src/core/wfcad.
#
#   bash skrypty/synchronizuj_wfcad.sh [/DATA/SOFT/GIS/WorkFieldCAD]
#
# Zrodlem rdzenia jest repozytorium WorkFieldCAD; tu leży KOPIA (jedna rzecz,
# jedna nazwa — nie poprawiac jej na miejscu, poprawka idzie do WorkFieldCAD
# i wraca tym skryptem). Odmawia, gdy WorkFieldCAD ma niezapisane zmiany
# w core/ albo lisp/ (kopia ma odpowiadac commitowi) i gdy wbudowany wf.lsp
# rozjechal sie z lisp/wf.lsp. Po kopii: WERSJA.txt z commitem i md5,
# a lista plikow .cpp porownana z src/core/CMakeLists.txt.
set -e
ZRODLO="${1:-/DATA/SOFT/GIS/WorkFieldCAD}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CEL="$REPO/src/core/wfcad"
[ -d "$ZRODLO/core/src" ] || { echo "STOP: $ZRODLO nie wygląda na repozytorium WorkFieldCAD"; exit 1; }
if [ -n "$(git -C "$ZRODLO" status --porcelain -- core lisp)" ]; then
  echo "STOP: WorkFieldCAD ma niezapisane zmiany w core/ albo lisp/ — najpierw commit:"
  git -C "$ZRODLO" status --short -- core lisp
  exit 1
fi
SPR="$(mktemp)"
python3 "$ZRODLO/narzedzia/zbuduj_lsp_inc.py" "$ZRODLO/lisp/wf.lsp" "$SPR" > /dev/null
if ! cmp -s "$SPR" "$ZRODLO/core/src/wf_lsp.inc"; then
  rm -f "$SPR"
  echo "STOP: core/src/wf_lsp.inc nie odpowiada lisp/wf.lsp — w WorkFieldCAD: python3 narzedzia/zbuduj_lsp_inc.py lisp/wf.lsp core/src/wf_lsp.inc"
  exit 1
fi
rm -f "$SPR"
rm -rf "$CEL/include" "$CEL/src"
mkdir -p "$CEL/include/wfcad" "$CEL/src"
cp "$ZRODLO"/core/include/wfcad/*.hpp "$CEL/include/wfcad/"
cp "$ZRODLO"/core/src/*.cpp "$ZRODLO"/core/src/*.inc "$CEL/src/"
{
  echo "Kopia rdzenia WorkFieldCAD — NIE EDYTOWAĆ (skrypty/synchronizuj_wfcad.sh)."
  echo "commit WorkFieldCAD: $(git -C "$ZRODLO" log -1 --format='%h %ad %s' --date=short)"
  echo
  (cd "$CEL" && find include src -type f | LC_ALL=C sort | xargs md5sum)
} > "$CEL/WERSJA.txt"
BRAK=0
for f in "$CEL"/src/*.cpp; do
  n="wfcad/src/$(basename "$f")"
  grep -q "$n" "$REPO/src/core/CMakeLists.txt" || { echo "DOPISZ do src/core/CMakeLists.txt: $n"; BRAK=1; }
done
echo "zsynchronizowano: $(ls "$CEL"/src/*.cpp | wc -l) plików .cpp, $(ls "$CEL"/include/wfcad/*.hpp | wc -l) nagłówków"
git -C "$REPO" status --short -- src/core/wfcad | head -20
exit $BRAK
