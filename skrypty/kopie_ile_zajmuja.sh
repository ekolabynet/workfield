#!/bin/bash
# WorkField 24.08.2026 — ile NAPRAWDE zajmuja migawki na nosniku.
#
# DLACZEGO OSOBNY SKRYPT: `du` na pojedynczej migawce KLAMIE. Migawka z dnia
# drugiego wyglada na pelna kopie, bo `du` liczy kazdy plik, na ktory ona
# wskazuje — takze te, ktore fizycznie leza w migawce z dnia pierwszego.
# Zeby zobaczyc prawde, trzeba zapytac o CALY zbior naraz: wtedy `du` policzy
# wspoldzielony plik raz.
#
# To jest ta sama rodzina bledu, co "-2 obiektow" i "dwa pliki po 2 609 152 B":
# narzedzie podaje liczbe, ktora wyglada na odpowiedz, a odpowiada na inne
# pytanie, niz zadalismy.
#
# Uzycie:  skrypty/kopie_ile_zajmuja.sh /run/media/piotr/4_DATA
#
# UWAGA NA SCIEZKE. Podaje sie PUNKT MONTOWANIA, a nie etykiete dysku.
# 24.08.2026 podalem Piotrowi /media/piotr/4_DATA, bo tak sie ten dysk nazywa.
# Naprawde siedzial pod /run/media/piotr/4_DATA — udisks montuje tam, gdzie
# montuje, a nazwa jest tylko nazwa. Kosztowalo to jedna runde diagnostyki
# w slepa uliczke. Punkt montowania sprawdza sie tak:
#     lsblk -o NAME,LABEL,MOUNTPOINT,FSTYPE,SIZE,FSUSED

set -u

NOSNIK="${1:-}"
if [ -z "$NOSNIK" ]; then
  echo "Uzycie: $0 /sciezka/do/nosnika" >&2
  exit 1
fi

if [ ! -d "$NOSNIK" ]; then
  echo "Nie ma katalogu $NOSNIK." >&2
  echo "To zwykle nie znaczy, ze nosnika nie ma — znaczy, ze podana sciezka" >&2
  echo "to nie jest punkt montowania. Sprawdz, gdzie naprawde jest:" >&2
  echo "    lsblk -o NAME,LABEL,MOUNTPOINT,FSTYPE,SIZE,FSUSED" >&2
  exit 1
fi

BAZA="$NOSNIK/WorkField_kopie"
if [ ! -d "$BAZA" ]; then
  echo "Nie ma $BAZA — czy na tym nosniku byla juz kopia?" >&2
  exit 1
fi

echo "=== Nosnik"
if [ -f "$NOSNIK/WF_NOSNIK.json" ]; then
  # Stempel nosnika: tozsamosc jedzie razem z rzecza, nie ze sciezka.
  grep -E '"(nazwa|id|odKiedy)"' "$NOSNIK/WF_NOSNIK.json" | sed 's/^/  /'
else
  echo "  BRAK WF_NOSNIK.json — nosnik nieostemplowany."
fi
echo

echo "=== Migawki (rozmiar POZORNY, kazda wyglada na pelna)"
for m in "$BAZA"/snap_*; do
  [ -d "$m" ] || continue
  printf '  %-42s %s\n' "$(basename "$m")" "$(du -sh "$m" 2>/dev/null | cut -f1)"
done
echo

echo "=== Zajete NAPRAWDE (wspoldzielone pliki liczone RAZ)"
du -sh "$BAZA" 2>/dev/null | sed 's/^/  razem: /'
echo
echo "  przyrost kazdej migawki — ile doszlo na dysku, gdy ona powstala:"
#
# BYLO TU `du -sh --separate-dirs` I BYLO ZLE. `--separate-dirs` nie znaczy
# "policz tylko pliki wlasne tej migawki" — znaczy "nie wliczaj podkatalogow".
# Dla migawki 89 GB wypisywalo 4 MB, czyli same pliki lezace w jej korzeniu.
# Liczba wygladala na przyrost i byla kompletna bzdura.
#
# To jest DOKLADNIE ten blad, przed ktorym ostrzega naglowek tego skryptu:
# narzedzie odpowiadajace na inne pytanie, niz zadalismy. Napisalem ostrzezenie
# i zaraz pod nim popelnilem to samo. 24.08.2026.
#
# Jak sie liczy naprawde: `du -sc` na ZBIORZE katalogow liczy kazdy i-wezel
# raz. Wiec dokladamy migawki po kolei, chronologicznie, i patrzymy, o ile
# urosla suma calego zbioru. Ta roznica to jest prawdziwy koszt migawki.
{
  poprzednia_suma=0
  zestaw=()
  for m in "$BAZA"/snap_*; do
    [ -d "$m" ] || continue
    zestaw+=( "$m" )
    suma=$(du -sc "${zestaw[@]}" 2>/dev/null | tail -1 | cut -f1)   # w kB
    przyrost=$(( suma - poprzednia_suma ))
    poprzednia_suma=$suma
    printf '    %-42s %s\n' "$(basename "$m")" \
           "$(numfmt --to=iec --from-unit=1024 "$przyrost" 2>/dev/null || echo "${przyrost}K")"
  done
}
echo

echo "=== Co mowia same migawki"
# JSON czytamy Pythonem, a nie grepem: grep na jednolinijkowym pliku wypisuje
# caly plik i wyglada, jakby cos znalazl. Narzedzie, ktore odpowiada na inne
# pytanie, niz zadalismy, jest gorsze od narzedzia, ktore milczy.
python3 - "$BAZA" <<'PYEOF'
import json, os, sys

baza = sys.argv[1]
for nazwa in sorted(os.listdir(baza)):
    katalog = os.path.join(baza, nazwa)
    opis = os.path.join(katalog, "KOPIA.json")
    if not nazwa.startswith("snap_") or not os.path.isfile(opis):
        continue
    try:
        with open(opis, encoding="utf-8") as f:
            d = json.load(f)
    except Exception as e:
        print("  %s — nie da sie odczytac KOPIA.json (%s)" % (nazwa, e))
        continue

    print("  " + nazwa)
    for klucz in ("data", "zakres", "plikow", "bajtow", "skopiowanych",
                  "dowiazanych", "pominietych", "dowiazaniaDzialaja",
                  "przerwane", "sekund", "poprzednia", "spis",
                  "dowiazaniaPowod", "dlaczegoNieDowiazano"):
        if klucz in d:
            print("    %-20s %s" % (klucz, d[klucz]))

    bazy = d.get("bazy", [])
    zle = [b for b in bazy if b.get("quick_check") != "ok"]
    print("    %-20s %d, w tym niezdrowych: %d" % ("baz sprawdzonych", len(bazy), len(zle)))
    for b in zle:
        print("      ! %s" % b.get("plik"))

    # Bledy wypisujemy W CALOSCI — to jedyna czesc, ktorej nie wolno streszczac.
    bledy = d.get("bledy", [])
    if bledy:
        print("    BLEDY (%d):" % len(bledy))
        for b in bledy:
            print("      - %s" % b)
    print()
PYEOF
echo

echo "=== Czego szukac"
echo "  dowiazaniaPowod                      -> jesli jest, to on odpowiada na wszystko ponizej"
echo "  dowiazanych = 0 w PIERWSZEJ migawce  -> tak ma byc, nie bylo z czym dowiazywac"
echo "  przerwane = True                     -> ta migawka jest NIEPELNA; nie liczy sie jako kopia"
echo "  poprzednia = migawka przerwana       -> tak wygladal blad z 24.08.2026: podstawa byla"
echo "                                          migawka z 33 plikow, wiec cala reszta poszla pelna"
echo "  dowiazaniaDzialaja = false           -> ten system plikow ich nie obsluguje (exFAT, FAT32)"
echo "  pominietych > 0                      -> patrz BLEDY: zwykle otwarte bazy, zamknij QGIS-a"
echo "  quick_check inny niz ok              -> sprawdz ORYGINAL, nie kopie:"
echo "                                          sqlite3 plik.gpkg \"PRAGMA quick_check\""
