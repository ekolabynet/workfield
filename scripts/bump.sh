#!/bin/bash
# WorkField — podbicie numeru buildu przed kazdym budowaniem.
# Sufiks bN zyje w APP_VERSION_STR (CMake wymaga liczbowego APP_VERSION_NUM),
# a APK_VERSION_CODE musi rosnac, bo inaczej Android widzi te sama wersje.
set -e
cd "$(dirname "$0")/.."
N=$(grep -oP 'APP_VERSION_NUM\.b\K[0-9]+' scripts/build.sh)
[ -z "$N" ] && { echo "STOP: nie znalazlem sufiksu bN"; exit 1; }
M=$((N + 1))
K=$(grep -oP 'APK_VERSION_CODE:-\K[0-9]+' scripts/build.sh | head -1)
sed -i "s/APP_VERSION_NUM\.b$N/APP_VERSION_NUM.b$M/" scripts/build.sh
sed -i "0,/APK_VERSION_CODE:-$K/s//APK_VERSION_CODE:-$((K + 1))/" scripts/build.sh
echo "b$N -> b$M   kod $K -> $((K + 1))"
