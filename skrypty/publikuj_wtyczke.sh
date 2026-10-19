#!/bin/bash
# WorkField — wydanie DOWOLNEJ wtyczki na gałęzi `plugins` (lista wtyczek w aplikacji).
#
#   bash publikuj_wtyczke.sh PACZKA.zip IKONA.svg            # PRÓBA: pokaże, co się zmieni
#   bash publikuj_wtyczke.sh PACZKA.zip IKONA.svg --zapisz   # commit + push na origin/plugins
#
# PACZKA: workfield-<nazwa>-v<wersja>.zip (main.qml, metadata.txt, icon.svg — płasko).
#         uuid = workfield-<nazwa>; nazwa, opis, wersja i autor — z metadata.txt w paczce.
# IKONA:  kolorowa ikona do listy wtyczek (#FB8C00); trafia na gałąź jako icon_<nazwa>.svg.
#         (Ta w paczce może być czarna — aplikacja przemalowuje ją sama.)
#
# Co robi:
#   1. sprawdza paczkę: jest main.qml, metadata.txt, icon.svg; wersja z nazwy = wersja z metadata.txt,
#   2. zakłada OSOBNY katalog roboczy na origin/plugins (git worktree) — bieżąca gałąź
#      z niezacommitowanymi zmianami zostaje nietknięta,
#   3. kładzie paczkę i ikonę, usuwa starsze paczki TEJ SAMEJ wtyczki,
#   4. dopisuje albo podmienia wpis w plugins.json (po uuid, wśród wtyczek workfield-),
#   5. z --zapisz: commit i push; bez — tylko pokazuje różnice i sprząta.
# Idempotentny: ta sama paczka drugi raz = „nic do zrobienia”.
set -e

PACZKA="${1:-}"; IKONA="${2:-}"; ZAPISZ=0
[ "${3:-}" = "--zapisz" ] && ZAPISZ=1
REPO="${WF_REPO:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
PRACA="${TMPDIR:-/tmp}/wf-plugins"

if [ -z "$PACZKA" ] || [ -z "$IKONA" ]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2
fi
PACZKA="$(readlink -f "$PACZKA")"; IKONA="$(readlink -f "$IKONA")"
[ -f "$PACZKA" ] || { echo "STOP: nie ma paczki $PACZKA"; exit 1; }
[ -f "$IKONA" ] || { echo "STOP: nie ma ikony $IKONA"; exit 1; }

NAZWA_PLIKU="$(basename "$PACZKA")"
if [[ ! "$NAZWA_PLIKU" =~ ^(workfield-[a-z0-9-]+)-v([0-9.]+)\.zip$ ]]; then
  echo "STOP: nazwa paczki ma być workfield-<nazwa>-v<wersja>.zip (jest: $NAZWA_PLIKU)"; exit 1
fi
UUID="${BASH_REMATCH[1]}"; WERSJA="${BASH_REMATCH[2]}"; KROTKA="${UUID#workfield-}"
echo "== paczka: $NAZWA_PLIKU  (uuid $UUID, wersja $WERSJA, md5 $(md5sum "$PACZKA" | cut -d' ' -f1))"

cd "$REPO"
echo "== repo: $(pwd)"
git fetch -q origin plugins
git worktree remove --force "$PRACA" 2>/dev/null || true
rm -rf "$PRACA"
ODCZEPIONY=0
if ! git worktree add -q -B plugins "$PRACA" origin/plugins 2>/dev/null; then
  git worktree add -q --detach "$PRACA" origin/plugins
  ODCZEPIONY=1
  echo "== gałąź plugins zajęta gdzie indziej — pracuję bez niej"
fi
sprzataj() { cd "$REPO"; git worktree remove --force "$PRACA" 2>/dev/null || true; }

cd "$PRACA"
set +e
python3 - "$PACZKA" "$IKONA" "$UUID" "$WERSJA" "$KROTKA" <<'PYEOF'
import configparser, glob, hashlib, json, os, shutil, sys, zipfile

paczka, ikona, uuid, wersja, krotka = sys.argv[1:6]
BAZA = "https://raw.githubusercontent.com/ekolabynet/workfield/plugins/"

with zipfile.ZipFile(paczka) as z:
    nazwy = set(z.namelist())
    brak = {"main.qml", "metadata.txt", "icon.svg"} - nazwy
    if brak:
        print("STOP: w paczce brakuje: %s" % ", ".join(sorted(brak)))
        sys.exit(1)
    meta = configparser.ConfigParser()
    meta.read_string(z.read("metadata.txt").decode("utf-8"))
g = meta["general"]
if g.get("version", "").strip() != wersja:
    print("STOP: wersja w nazwie paczki (%s) różna od metadata.txt (%s)" % (wersja, g.get("version")))
    sys.exit(1)
if not os.path.exists("plugins.json"):
    print("STOP: brak plugins.json — to nie jest gałąź plugins")
    sys.exit(1)

def poloz(zrodlo, cel, opis):
    nowe = open(zrodlo, "rb").read()
    stare = open(cel, "rb").read() if os.path.exists(cel) else None
    if stare == nowe:
        print("  %s — bez zmian" % cel)
        return False
    open(cel, "wb").write(nowe)
    print("  %s — %s (%d B, md5 %s)" % (cel, opis, len(nowe), hashlib.md5(nowe).hexdigest()))
    return True

zip_nazwa = os.path.basename(paczka)
ikona_nazwa = "icon_%s.svg" % krotka
zmiany = poloz(paczka, zip_nazwa, "paczka")
zmiany |= poloz(ikona, ikona_nazwa, "ikona")
for stara in sorted(glob.glob("%s-v*.zip" % uuid)):
    if stara != zip_nazwa:
        os.remove(stara)
        print("  %s — usunięta (starsza wersja)" % stara)
        zmiany = True

lista = json.load(open("plugins.json", encoding="utf-8"))
wpis = {
    "uuid": uuid,
    "name": g.get("name", uuid).strip(),
    "description": g.get("description", "").strip(),
    "version": wersja,
    "download": BAZA + zip_nazwa,
    "icon": BAZA + ikona_nazwa,
    "homepage": g.get("homepage", "https://github.com/ekolabynet/workfield").strip(),
    "author": g.get("author", "ekolabynet").strip(),
}
gdzie = next((i for i, w in enumerate(lista) if w.get("uuid") == uuid), None)
if gdzie is None:
    swoje = [i for i, w in enumerate(lista) if str(w.get("uuid", "")).startswith("workfield-")]
    gdzie = len(lista)
    for i in swoje:
        if str(lista[i].get("uuid", "")) > uuid:
            gdzie = i
            break
    else:
        if swoje:
            gdzie = swoje[-1] + 1
    lista.insert(gdzie, wpis)
    print("  plugins.json — nowy wpis na pozycji %d" % gdzie)
    zmiany = True
elif lista[gdzie] != wpis:
    lista[gdzie] = wpis
    print("  plugins.json — wpis podmieniony")
    zmiany = True
else:
    print("  plugins.json — bez zmian")
if zmiany:
    with open("plugins.json", "w", encoding="utf-8") as f:
        json.dump(lista, f, indent=2, ensure_ascii=False)
        f.write("\n")
print("\n  wpis: %s" % json.dumps(wpis, ensure_ascii=False))
sys.exit(0 if zmiany else 9)
PYEOF
KOD=$?
set -e

if [ "$KOD" = "9" ]; then
  echo; echo "Nic do zrobienia — ta wersja już jest na gałęzi."
  sprzataj; exit 0
fi
if [ "$KOD" != "0" ]; then
  echo "BŁĄD (kod $KOD) — nic nie wypchnięto."; sprzataj; exit 1
fi

git add -A
echo; echo "== zmiany na gałęzi plugins"
git status --short
git --no-pager diff --cached --stat

if [ "$ZAPISZ" != "1" ]; then
  echo; echo "PRÓBA — nic nie wypchnięto. Wydanie: dodaj --zapisz"
  sprzataj; exit 0
fi

git commit -q -F - <<KONIEC
Wtyczka $UUID v$WERSJA

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VeWM6rJN6RyoQt3umLcoDc
KONIEC
echo; echo "== wypycham na origin/plugins"
if [ "$ODCZEPIONY" = "1" ]; then git push origin HEAD:plugins; else git push origin plugins; fi
sprzataj
echo
echo "Gotowe. Za chwilę (raw odświeża się z opóźnieniem):"
echo "  curl -s https://raw.githubusercontent.com/ekolabynet/workfield/plugins/plugins.json | grep -A3 '\"$UUID\"'"
echo "W aplikacji: Narzędzia → Wtyczki → odśwież listę → zainstaluj."
