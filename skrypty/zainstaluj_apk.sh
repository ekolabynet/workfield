#!/bin/bash
# WorkField 21.09.2026 - INSTALACJA APK NA TELEFONIE PRZEZ ADB.
#
# Bierze najświeższy plik z `wydania/apk/` (albo ten, który wskażesz),
# sprawdza, co już siedzi na telefonie, i wgrywa nowy. Sens jest w tym,
# co robi WOKÓŁ samego `adb install`:
#
#   - mówi, KTÓRY telefon jest podpięty (przy dwóch podpiętych adb i tak
#     odmówi, więc trzeba wiedzieć od razu),
#   - mówi, CO jest zainstalowane teraz (versionCode) i co będzie po,
#     bo „zainstalowało się" bez tej liczby nic nie znaczy,
#   - rozpoznaje INSTALL_FAILED_UPDATE_INCOMPATIBLE (inny podpis) i mówi,
#     co z tym zrobić, zamiast zostawiać gołe „Failure",
#   - `-r -d`: nadpisanie z zachowaniem danych, także przy niższym numerze.
#
# DANE PROJEKTÓW SĄ POZA APLIKACJĄ (pamięć telefonu), więc nawet pełne
# odinstalowanie ich nie zabiera. Zabiera ustawienia aplikacji.
#
#   bash zainstaluj_apk.sh                      - najświeższy z wydania/apk
#   bash zainstaluj_apk.sh plik.apk             - konkretny plik
#   bash zainstaluj_apk.sh --odinstaluj         - najpierw usuń starą
#   bash zainstaluj_apk.sh --uruchom            - po instalacji odpal
#   bash zainstaluj_apk.sh --log                - odpal i pokaż logcat WFG
set -e

REPO="/DATA/SOFT/GIS/QFIELD_Pro/QField"
PLIK=""
ODINSTALUJ=0
URUCHOM=0
LOG=0
for a in "$@"; do
  case "$a" in
    --odinstaluj) ODINSTALUJ=1 ;;
    --uruchom)    URUCHOM=1 ;;
    --log)        URUCHOM=1; LOG=1 ;;
    --*)          echo "Nieznany przełącznik: $a"; exit 1 ;;
    *.apk)        PLIK="$a" ;;
    *)            REPO="$a" ;;
  esac
done

command -v adb >/dev/null || { echo "STOP: brak adb (sudo apt install android-tools-adb)"; exit 1; }

# --- który plik -------------------------------------------------------
if [ -z "$PLIK" ]; then
  PLIK=$(ls -t "$REPO"/wydania/apk/*.apk 2>/dev/null | head -1 || true)
  [ -n "$PLIK" ] || { echo "STOP: nie ma nic w $REPO/wydania/apk — puść najpierw przygotuj_apk.sh"; exit 1; }
fi
[ -f "$PLIK" ] || { echo "STOP: nie ma pliku $PLIK"; exit 1; }
echo "== plik:  $(basename "$PLIK")   ($(du -h "$PLIK" | cut -f1))"
echo "   md5:   $(md5sum "$PLIK" | cut -d' ' -f1)"

# --- nazwa pakietu i wersja Z PLIKU ----------------------------------
# Z APK, nie z pamięci: fork mógł zmienić identyfikator pakietu, a wtedy
# stara i nowa aplikacja żyją na telefonie obok siebie i łatwo pomylić,
# którą się właśnie ogląda.
AAPT=$(command -v aapt2 || command -v aapt || ls "${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)
PAKIET=""
KOD_PLIKU=""
if [ -n "$AAPT" ] && [ -x "$AAPT" ]; then
  OPIS=$("$AAPT" dump badging "$PLIK" 2>/dev/null | head -1 || true)
  PAKIET=$(echo "$OPIS" | grep -oP "package: name='\K[^']+" || true)
  KOD_PLIKU=$(echo "$OPIS" | grep -oP "versionCode='\K[0-9]+" || true)
fi
[ -n "$PAKIET" ] || PAKIET=$(grep -oP 'package="\K[^"]+' "$REPO"/platform/android/AndroidManifest.xml 2>/dev/null | head -1 || true)
[ -n "$PAKIET" ] || PAKIET="ch.opengis.qfield"
echo "   pakiet: ${PAKIET}${KOD_PLIKU:+   versionCode w pliku: ${KOD_PLIKU}}"

# --- który telefon ----------------------------------------------------
adb start-server >/dev/null 2>&1 || true
URZADZENIA=$(adb devices | sed -n '2,$p' | grep -c "device$" || true)
if [ "$URZADZENIA" = "0" ]; then
  echo
  echo "STOP: nie widzę telefonu."
  echo "  - kabel w porcie z transmisją danych (nie samo ładowanie),"
  echo "  - Opcje programisty → Debugowanie USB włączone,"
  echo "  - na telefonie potwierdź „Zezwól na debugowanie USB” dla tego komputera."
  echo "Stan wg adb:"
  adb devices | sed 's/^/  /'
  exit 1
fi
if [ "$URZADZENIA" -gt 1 ]; then
  echo "STOP: podpiętych urządzeń: ${URZADZENIA}. adb nie zgadnie, na które instalować."
  adb devices -l | sed 's/^/  /'
  echo "Odepnij zbędne albo użyj:  adb -s <serial> install -r -d \"$PLIK\""
  exit 1
fi
MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
ANDROID=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
echo "== telefon: ${MODEL} (Android ${ANDROID})"

# --- co już jest ------------------------------------------------------
STARY=$(adb shell dumpsys package "$PAKIET" 2>/dev/null | grep -m1 -oP 'versionCode=\K[0-9]+' | tr -d '\r' || true)
STARA_NAZWA=$(adb shell dumpsys package "$PAKIET" 2>/dev/null | grep -m1 -oP 'versionName=\K\S+' | tr -d '\r' || true)
if [ -n "$STARY" ]; then
  echo "   zainstalowane teraz: versionCode ${STARY}${STARA_NAZWA:+  (${STARA_NAZWA})}"
else
  echo "   zainstalowane teraz: nic (pierwsza instalacja)"
fi

# --- odinstalowanie na życzenie --------------------------------------
if [ "$ODINSTALUJ" = "1" ] && [ -n "$STARY" ]; then
  echo "== odinstalowuję ${PAKIET}"
  adb uninstall "$PAKIET" || echo "   (nie udało się — instaluję mimo to)"
fi

# --- instalacja -------------------------------------------------------
echo "== instaluję (to trwa, 110 MB idzie kablem)…"
set +e
WYNIK=$(adb install -r -d "$PLIK" 2>&1)
KOD=$?
set -e
echo "$WYNIK" | sed 's/^/   /'

if [ $KOD -ne 0 ] || echo "$WYNIK" | grep -qi 'Failure'; then
  echo
  if echo "$WYNIK" | grep -qi 'UPDATE_INCOMPATIBLE\|signatures do not match'; then
    echo "PRZYCZYNA: na telefonie siedzi wersja podpisana INNYM kluczem."
    echo "Android nie pozwoli jej nadpisać. Trzeba usunąć i zainstalować od nowa:"
    echo
    echo "  bash $(basename "$0") \"$PLIK\" --odinstaluj"
    echo
    echo "Projekty i dane w pamięci telefonu zostają — WorkField trzyma je"
    echo "poza katalogiem aplikacji. Znikną ustawienia aplikacji."
  elif echo "$WYNIK" | grep -qi 'INSUFFICIENT_STORAGE'; then
    echo "PRZYCZYNA: za mało miejsca na telefonie."
  elif echo "$WYNIK" | grep -qi 'VERSION_DOWNGRADE'; then
    echo "PRZYCZYNA: na telefonie jest NOWSZY numer. Z --odinstaluj przejdzie."
  fi
  exit 1
fi

NOWY=$(adb shell dumpsys package "$PAKIET" 2>/dev/null | grep -m1 -oP 'versionCode=\K[0-9]+' | tr -d '\r' || true)
echo
echo "== na telefonie: versionCode ${NOWY:-?}"
if [ -n "$KOD_PLIKU" ] && [ "$NOWY" != "$KOD_PLIKU" ]; then
  echo "   ! UWAGA: w pliku było ${KOD_PLIKU}. Instalacja nie weszła tak, jak myśli adb."
fi

# --- uruchomienie i log ----------------------------------------------
if [ "$URUCHOM" = "1" ]; then
  echo "== uruchamiam"
  adb shell monkey -p "$PAKIET" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 \
    || adb shell am start -n "${PAKIET}/.QFieldActivity" >/dev/null 2>&1 \
    || echo "   (nie umiem odpalić — uruchom ikoną)"
fi
if [ "$LOG" = "1" ]; then
  echo "== logcat: WFG + awarie (Ctrl-C kończy)"
  adb logcat -c 2>/dev/null || true
  adb logcat | grep --line-buffered -E 'WFG|qfield|QField|FATAL|AndroidRuntime|libc'
fi
