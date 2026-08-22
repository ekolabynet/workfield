#!/bin/bash
# mapa_przemianowan.sh — WorkField, 22.08.2026
#
# Po co: upstream QField przemianował i poprzenosił prawie cały kod
# (kampania ~16 commitów: moduły org.qfield.core/gui/app, prefiks Qf,
# wydzielenie 3D). Nasze ścieżki i ich ścieżki się rozjechały, więc rebase
# widziałby ~470 fałszywych par „usuń + dodaj" zamiast prawdziwych konfliktów.
#
# Co robi: czyta ze standardowego wejścia listę NASZYCH ścieżek i wypisuje
# gotowe polecenia `git mv` na dzisiejszą strukturę upstreamu.
# Nic nie zmienia — tylko wypisuje. Wykonanie jest osobną, świadomą decyzją.
#
# Heurystyka dopasowania:
#   - ta sama nazwa pliku (także bez względu na wielkość liter),
#   - nazwa z dołożonym prefiksem qf/Qf,
#   - QField… -> Qf…
#   - ścieżki w src/app/qml_compat/ są ODRZUCANE: to warstwa zgodności dla
#     wtyczek (commit 71cb828ce, #7846), a nie implementacja.
#
# UŻYCIE
#   git fetch upstream
#   BASE=$(git merge-base HEAD upstream/master)
#   git diff --name-only --diff-filter=M "$BASE" -- src/ | bash mapa_przemianowan.sh
#
# Sprawdzone 22.08 na 12 największych plikach delty: 12/12 trafień.
# Na wszystkich 538 naszych plikach bez odpowiednika: 424 automatycznie,
# 114 do ręki — z czego 64 to nasze własne pliki Qf*, które odpowiednika
# mieć nie powinny. Realne pokrycie plików pochodzących z upstreamu: ~89%.

set -u

if ! git rev-parse --verify upstream/master >/dev/null 2>&1; then
  echo "BŁĄD: brak upstream/master. Najpierw: git fetch upstream" >&2
  exit 1
fi

UP=$(mktemp)
trap 'rm -f "$UP"' EXIT
git ls-tree -r --name-only upstream/master -- src/ | grep -v '/qml_compat/' > "$UP"

ok=0
reka=0

while read -r f; do
  [ -z "$f" ] && continue
  b=$(basename "$f")
  qfield_wariant=$(printf '%s' "$b" | sed 's/^QField/Qf/')
  hit=$(grep -iE "/($b|qf$b|$qfield_wariant)$" "$UP")
  n=$(printf '%s' "$hit" | grep -c .)

  if [ "$n" = 1 ]; then
    echo "git mv \"$f\" \"$hit\""
    ok=$((ok + 1))
  elif [ "$n" -gt 1 ]; then
    echo "# ?!  $f  ->  $(echo $hit | tr '\n' ' ')"
    reka=$((reka + 1))
  else
    echo "# BRAK  $f"
    reka=$((reka + 1))
  fi
done

echo "# ----------------------------------------------------------"
echo "# dopasowane automatycznie: $ok"
echo "# do ręki (kandydaci lub brak): $reka"
echo "#"
echo "# UWAGA: to przenosi PLIKI. Treść — importy QML (org.qfield.core/gui/app)"
echo "# i #include w C++ — to osobny krok. W C++ złapie je kompilator;"
echo "# w QML trzeba przejść ręcznie albo sed-em, bo QML milczy do uruchomienia."
