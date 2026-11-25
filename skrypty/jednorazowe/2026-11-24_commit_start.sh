#!/usr/bin/env bash
# WorkFieldGIS 24.11.2026 — commit refaktoryzacji okna głównego R2.1–R2.3 i pomiaru startu.
# Domyślnie PRÓBA (nic nie zmienia). Zapis: bash commit_start_2026-11-24.sh --zapisz
set -u
cd /DATA/SOFT/GIS/QFIELD_Pro/QField || exit 1

ZAPISZ=0
[ "${1:-}" = "--zapisz" ] && ZAPISZ=1

QML=src/app/qml/QgisMobileapp.qml
CPP=src/app/qgismobileapp.cpp
MD5_QML=9c3e636fdcd4da2d21a5fcc1494bb22d
MD5_CPP=03e7e0ed521a0f8a6da8b453f4f052c8
# Zmienione, ale NIE do tego commita (podbita wersja wchodzi do commita wydania):
POMIJANE="scripts/build.sh"

echo "gałąź: $(git branch --show-current)"
echo "ostatni commit: $(git log -1 --oneline)"
echo "--- zmiany w plikach śledzonych:"
git diff --stat HEAD
echo

BLAD=0
for f in $(git diff --name-only HEAD); do
  case " $QML $CPP $POMIJANE " in
    *" $f "*) ;;
    *) echo "STOP: zmieniony plik spoza listy: $f"; BLAD=1 ;;
  esac
done
for f in $QML $CPP; do
  git diff --quiet HEAD -- "$f" && { echo "STOP: $f nie ma zmian"; BLAD=1; }
done
[ "$(md5sum < $QML | cut -d' ' -f1)" = "$MD5_QML" ] || { echo "STOP: md5 $QML inne niż $MD5_QML"; BLAD=1; }
[ "$(md5sum < $CPP | cut -d' ' -f1)" = "$MD5_CPP" ] || { echo "STOP: md5 $CPP inne niż $MD5_CPP"; BLAD=1; }
grep -q 'WF-QML-PROFILE' src/app/main.cpp && { echo "STOP: w src/app/main.cpp są tymczasowe łatki profilu"; BLAD=1; }

# instalatory z dzisiaj — historia przetwarzania (skrypty/jednorazowe/)
INSTALATORY=$(ls skrypty/jednorazowe/2026-11-24_instaluj_*.py 2>/dev/null)
echo "--- instalatory do dołączenia:"
for f in $INSTALATORY; do echo "  $f"; done
[ -z "$INSTALATORY" ] && echo "  (brak)"

if [ $BLAD -ne 0 ]; then
  echo; echo "NIC NIE ZACOMMITOWANO."; exit 1
fi
if [ $ZAPISZ -eq 0 ]; then
  echo; echo "PRÓBA — wszystko się zgadza, nic nie zapisano. Zapis: dopisz --zapisz"; exit 0
fi

git add -- $QML $CPP $INSTALATORY || exit 1
git commit -F - <<'KONIEC'
Szybszy start: okno główne tworzone leniwiej, pomiar startu

Refaktoryzacja okna głównego, etap R2, i stały pomiar startu.

- [WF-PERF-START] qgismobileapp.cpp: przy każdym starcie linijka
  w dzienniku i logcat — wiek procesu, gdy okno gotowe, w tym czas przed
  konstruktorem, konstruktor do QML i tworzenie okna QML.
- [WF-LAZY-WIZARD] kreator nowego projektu (QfProjectCreationScreen)
  tworzony dopiero przy pokazaniu (w WFG nieosiągalny z menu).
- [WF-LAZY-FILE-BROWSER] okno „Pliki” tworzone przy pierwszym użyciu;
  obiekt o tym samym id przekazuje wywołania, wywołujący bez zmian.
- [WF-LAZY-SOUNDS] odtwarzacze dźwięków (RTK, przyciski) tworzone przy
  pierwszym dźwięku. Pierwszy MediaPlayer uruchamiał silnik Qt Multimedia
  przy każdym starcie (497 ms w profilu qmlprofiler); przy wyłączonych
  dźwiękach silnik nie startuje wcale.

Pomiar na laptopie (build bez optymalizacji), tworzenie okna QML,
ciepły start: przed 2 517–2 643 ms, po 1 833–1 835 ms.
Instalatory łatek w skrypty/jednorazowe/2026-11-24_*.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wt9ypZBE7Lqfns3UXekYQE
KONIEC
echo
git log -1 --stat
