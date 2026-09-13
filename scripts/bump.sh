#!/bin/bash
# WorkField — podbicie numeru buildu przed kazdym budowaniem.
#
# Trzecia pozycja numeru JEST licznikiem buildow: 0.11.50 -> 0.11.51.
# `versionCode` liczy sie z niej sama (major*10000 + minor*100 + patch),
# wiec rosnie bez osobnego pilnowania — a musi rosnac, bo inaczej Android
# widzi te sama wersje i `install -r` zachowuje sie nieprzewidywalnie.
#
# Po 0.11.99 kolejny build da 0.12.0. Kod rosnie, ale numer wyglada jak
# wydanie, ktorym nie jest. Sto buildow to okolo dwoch tygodni.
set -e
cd "$(dirname "$0")/.."
N=$(grep -oP 'APP_VERSION_NUM:-\d+\.\d+\.\K\d+' scripts/build.sh)
[ -z "$N" ] && { echo "STOP: nie znalazlem trzeciej pozycji numeru"; exit 1; }
sed -i "0,/\(APP_VERSION_NUM:-[0-9]\+\.[0-9]\+\.\)$N/s//\1$((N + 1))/" scripts/build.sh
bash -c 'source <(sed -n "1,20p" scripts/build.sh); echo "  $APP_VERSION_STR   kod $APK_VERSION_CODE"'
