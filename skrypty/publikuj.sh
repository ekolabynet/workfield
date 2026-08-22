#!/bin/bash
# Publikuje zawartosc katalogow plugins/ i addins/ z galezi development
# na ich linie dystrybucyjne (galezie plugins / addins).
# Idempotentny: bez zmian w katalogu nic nie robi. Uruchamiac z dowolnego
# miejsca; dziala na lokalnym stanie development (najpierw commit + push!).
set -e
cd "$(dirname "$0")/.."

if ! git rev-parse --verify -q development >/dev/null; then
  echo "BLAD: brak galezi development" >&2
  exit 1
fi

git fetch origin plugins addins 2>/dev/null || true

for L in plugins addins; do
  T=$(git rev-parse "development:$L" 2>/dev/null) || { echo "$L: brak katalogu $L/ na development - pomijam"; continue; }
  P=""
  if git rev-parse --verify -q "origin/$L" >/dev/null; then
    if [ "$(git rev-parse "origin/$L^{tree}")" = "$T" ]; then
      echo "$L: bez zmian"
      continue
    fi
    P="-p origin/$L"
  fi
  C=$(git commit-tree $P -m "$L: aktualizacja $(date +%F_%H%M)" "$T")
  git branch -f "$L" "$C"
  git push origin "$L"
  echo "$L: OPUBLIKOWANO ($C)"
done
