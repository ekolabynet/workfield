#!/usr/bin/env bash
# WorkFieldGIS 24.11.2026 — cztery commity z dnia: pomiar [WF-PERF], zgodność z QGIS 4.4,
# łatka A [WF-SCAN-GEOMETRY], łatka B [WF-SCAN-SCOPE]. Każdy z własnym instalatorem.
#
# narzedziaprojektu.cpp niesie trzy łatki naraz, więc skrypt odtwarza kolejne stany tymi
# samymi instalatorami, zaczynając od wersji z HEAD, i sprawdza md5 każdego kroku.
# Gdy coś się nie zgodzi: STOP, a plik wraca do stanu sprzed uruchomienia.
#
#   bash commit_wydajnosc_2026-11-24.sh            # próba — nic nie zmienia
#   bash commit_wydajnosc_2026-11-24.sh --zapisz   # cztery commity (bez push)
set -u
REPO=/DATA/SOFT/GIS/QFIELD_Pro/QField
ZAPISZ=0
[ "${1:-}" = "--zapisz" ] && ZAPISZ=1
[ "${2:-}" = "--repo" ] && REPO="$3"   # tylko do testu
cd "$REPO" || { echo "STOP: nie ma $REPO"; exit 1; }

J=skrypty/jednorazowe
N=src/core/utils/narzedziaprojektu.cpp
INST_PERF=$J/2026-11-24_instaluj_pomiar_stanu_projektu.py
INST_Q44=$J/2026-11-24_instaluj_zgodnosc_qgis44.py
INST_A=$J/2026-11-24_instaluj_skan_bez_atrybutow.py
INST_B=$J/2026-11-24_instaluj_skan_tylko_dane.py
Q44_PLIKI="src/core/moduly/inwentaryzacjadrzew.cpp src/core/positioning/qfgeofencer.cpp src/core/utils/qflayerutils.cpp src/core/utils/qfprojectutils.cpp"

N_HEAD=e2e8fae4a42e1b189c006d3f75fe7c94
N_PERF=9b592a956b3a2ac8cd5df7c5eeefb85c
N_A=0128b9492ad364400e03c7eb4e8428da
N_B=048288804022368ec36ff6f31b9a2cda
declare -A Q44_HEAD=(
  [src/core/moduly/inwentaryzacjadrzew.cpp]=36c492b1826201b83fafdeaacb36e8a3
  [src/core/positioning/qfgeofencer.cpp]=8924f2132fbfb93dc31b01de258081ea
  [src/core/utils/qflayerutils.cpp]=5da9eb3e8d058cc238788a4a2b4a4651
  [src/core/utils/qfprojectutils.cpp]=dac3695dddb6c61e4d804df866e5e6a4 )
declare -A Q44_PO=(
  [src/core/moduly/inwentaryzacjadrzew.cpp]=3532a3326b74b26584fa852c7cfbf7fa
  [src/core/positioning/qfgeofencer.cpp]=134dced980844b533120b26d13bf8a71
  [src/core/utils/qflayerutils.cpp]=047a3027cb606adf942f54b4550d22a3
  [src/core/utils/qfprojectutils.cpp]=9227bdb49aa85187d06e1e4b132e7691 )

STOPKA='Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wt9ypZBE7Lqfns3UXekYQE'

md5() { md5sum "$1" | cut -d' ' -f1; }
md5_head() { git show "HEAD:$1" | md5sum | cut -d' ' -f1; }
stop() { echo "STOP: $*"; exit 1; }

echo "== gałąź: $(git rev-parse --abbrev-ref HEAD)"
echo "== ostatni commit: $(git log -1 --format='%h %ci %s')"
echo "== zmiany względem HEAD:"
git diff --stat HEAD

# ---------------------------------------------------------------- sprawdzenia
OCZEKIWANE="$N $Q44_PLIKI"
for f in $(git diff --name-only HEAD); do
  case " $OCZEKIWANE " in *" $f "*) ;; *) stop "zmieniony plik spoza listy: $f — nie commituję w ciemno";; esac
done
[ -n "$(git diff --cached --name-only)" ] && stop "w indeksie (git add) już coś czeka — najpierw: git status"
for f in "$INST_PERF" "$INST_Q44" "$INST_A" "$INST_B"; do [ -f "$f" ] || stop "brak instalatora $f"; done

[ "$(md5_head $N)" = "$N_HEAD" ] || stop "$N w HEAD ma md5 $(md5_head $N), oczekiwane $N_HEAD"
[ "$(md5 $N)" = "$N_B" ] || stop "$N na dysku ma md5 $(md5 $N), oczekiwane $N_B (po A i B)"
for f in $Q44_PLIKI; do
  [ "$(md5_head $f)" = "${Q44_HEAD[$f]}" ] || stop "$f w HEAD ma md5 $(md5_head $f), oczekiwane ${Q44_HEAD[$f]}"
  [ "$(md5 $f)" = "${Q44_PO[$f]}" ] || stop "$f na dysku ma md5 $(md5 $f), oczekiwane ${Q44_PO[$f]}"
done

# Kolejne stany narzedziaprojektu.cpp — liczone na kopii, bez dotykania repo.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git show "HEAD:$N" > "$TMP/n.cpp"
python3 "$INST_PERF" --plik "$TMP/n.cpp" --zapisz >/dev/null || stop "instalator pomiaru nie przeszedł"
cp "$TMP/n.cpp" "$TMP/n_perf.cpp"; [ "$(md5 $TMP/n_perf.cpp)" = "$N_PERF" ] || stop "stan po pomiarze: zła suma"
python3 "$INST_A" --plik "$TMP/n.cpp" --zapisz >/dev/null || stop "instalator A nie przeszedł"
cp "$TMP/n.cpp" "$TMP/n_a.cpp"; [ "$(md5 $TMP/n_a.cpp)" = "$N_A" ] || stop "stan po A: zła suma"
python3 "$INST_B" --plik "$TMP/n.cpp" --zapisz >/dev/null || stop "instalator B nie przeszedł"
[ "$(md5 $TMP/n.cpp)" = "$N_B" ] || stop "stan po B: zła suma"
cmp -s "$TMP/n.cpp" "$N" || stop "odtworzony stan po B różni się od pliku na dysku"
echo "== wszystkie sumy się zgadzają; kolejne stany $N odtworzone (pomiar → A → B)."

if [ $ZAPISZ -eq 0 ]; then
  echo "PRÓBA — nic nie zmieniono. Cztery commity: dopisz --zapisz"
  exit 0
fi

# ---------------------------------------------------------------- commity
cp "$N" "$TMP/n_final.cpp"
przywroc() { cp "$TMP/n_final.cpp" "$N"; echo "STOP: $* — $N przywrócony do stanu sprzed skryptu"; exit 1; }

# 1. zgodność z QGIS 4.4 (nie dotyczy narzedziaprojektu.cpp)
git add $Q44_PLIKI "$INST_Q44" || przywroc "git add (QGIS 4.4)"
git commit -q -F - <<KONIEC || przywroc "commit QGIS 4.4"
Zgodność z QGIS 4.4 w buildzie desktopowym

21.11.2026 systemowy libqgis-dev przeszedł z 4.2.3 na 4.4.0. W QGIS 4.4
około 260 funkcji zwraca std::unique_ptr zamiast zwykłego wskaźnika
i build-sys przestał się kompilować (10 błędów w 4 plikach).

- qfgeofencer.cpp, QfLayerUtils::setDefaultRenderer: tekst upstreamu
  QField (fb95e5eed, aa3f81694; #if _QGIS_VERSION_INT >= 40300),
  żeby przyszłe scalenie nie dało konfliktu;
- qfprojectutils.cpp (5 miejsc), rampByName, inwentaryzacjadrzew.cpp:
  std::unique_ptr<T>( wywołanie ) — działa z QGIS 4.2 i 4.4.
- Android (QGIS 4.2.1 z vcpkg) bez zmian w działaniu.
- Instalator: $INST_Q44

Sprawdzone: build-sys z QGIS 4.4.0 — KONIEC_BUILDA_RC=0. Zmiany
w qfprojectutils.cpp są w kreatorze QField, do którego WFG nie ma
przycisku — tylko kompilacja.

$STOPKA
KONIEC

# 2. pomiar [WF-PERF]
cp "$TMP/n_perf.cpp" "$N"
git add "$N" "$INST_PERF" || przywroc "git add (pomiar)"
git commit -q -F - <<KONIEC || przywroc "commit pomiaru"
Pomiar NarzedziaProjektu::stanProjektu() [WF-PERF]

Tester zgłosił, że WFG jest wolny na starszym telefonie. stanProjektu()
czyta wszystkie obiekty warstw poligonowych na wątku interfejsu,
przy każdym otwarciu menu bocznego. Ta zmiana niczego nie przyspiesza —
mierzy: jedna linijka w dzienniku komunikatów (czas, liczba obiektów,
najdłuższe warstwy; od 300 ms poziom Warning). Szczegóły per warstwa:
QT_LOGGING_RULES="workfield.performance=true". Punkt pomiarowy zostaje.

Zmierzone (laptop): Nakło 260 obiektów — 4–5 ms; ZZW PGRS3D 29 432
obiektów — mediana 127 ms, 14 wywołań w sesji.

Instalator: $INST_PERF

$STOPKA
KONIEC

# 3. łatka A [WF-SCAN-GEOMETRY]
cp "$TMP/n_a.cpp" "$N"
git add "$N" "$INST_A" || przywroc "git add (A)"
git commit -q -F - <<KONIEC || przywroc "commit A"
stanProjektu() czyta same geometrie [WF-SCAN-GEOMETRY]

Skan pustych i zwiniętych geometrii czytał wszystkie atrybuty każdego
obiektu, choć potrzebuje tylko kształtu. Żądanie ma teraz
setNoAttributes(). Ostrzeżenia bez zmian.

Instalator: $INST_A

$STOPKA
KONIEC

# 4. łatka B [WF-SCAN-SCOPE]
cp "$TMP/n_final.cpp" "$N"
git add "$N" "$INST_B" || przywroc "git add (B)"
git commit -q -F - <<KONIEC || przywroc "commit B"
Skan geometrii tylko w pliku danych projektu [WF-SCAN-SCOPE]

Puste i zwinięte geometrie są szukane tylko w pliku danych projektu
(plikDanych(): data.gpkg, dane.gpkg, inaczej GeoPackage z największą
liczbą warstw). Wyniki analiz z biura i podkłady wypadają ze skanu.
Bez pliku danych — skan wszystkiego, jak dotąd. Próg przyciągania
liczy się z najmniejszego obiektu w danych terenowych. Linijka
[WF-PERF] podaje liczbę pominiętych warstw. Zgoda Piotra 24.11 13:09.

Zmierzone (laptop): PGRS3D 29 432 obiektów, 127 ms → 3 ms (18 warstw
pominiętych, plik danych bez poligonów); duży projekt ZZW 142 warstwy
→ 4 w skanie (1 217 obiektów), 13–23 ms; nowe projekty WFG — warstwy
z dane.gpkg w skanie. Telefon — jeszcze nie mierzony.

Instalator: $INST_B

$STOPKA
KONIEC

[ "$(md5 $N)" = "$N_B" ] || stop "po commitach $N ma md5 $(md5 $N) zamiast $N_B"
[ -z "$(git diff --name-only HEAD)" ] || stop "po commitach zostały niezacommitowane zmiany: $(git diff --name-only HEAD | tr '\n' ' ')"
echo "== gotowe, cztery commity (bez push):"
git log --oneline -4
