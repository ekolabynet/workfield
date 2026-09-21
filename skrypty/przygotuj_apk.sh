#!/bin/bash
# WorkField 21.09.2026 - PRZYGOTOWANIE APK DLA TESTERÓW.
#
# =====================================================================
#  PO CO TO JEST
# =====================================================================
#
# `scripts/build.sh` zostawia APK gdzieś w drzewie budowania, pod nazwą,
# która o niczym nie mówi (`android-build-release-signed.apk` wygląda
# tak samo dla 0.11.84 i dla 0.12.0). Tester dostaje plik na komunikator,
# zapisuje go w Pobranych obok trzech poprzednich i za tydzień nikt —
# ani on, ani my — nie wie, co właściwie ma zainstalowane.
#
# Ten skrypt robi jedną rzecz: bierze ŚWIEŻO ZBUDOWANY APK i odkłada go
# pod nazwą, która sama się tłumaczy:
#
#     WorkField-0.12.0-1200-arm64-20260921.apk
#                \     \    \       \
#                 \     \    \       `- dzień budowania
#                  \     \    `- architektura (triplet)
#                   \     `- versionCode, ten sam, który widzi Android
#                    `- numer wersji, ten sam, co w „O programie"
#
# Drugi APK tej samej wersji tego samego dnia dostaje `-t2`, trzeci `-t3`.
# To jest ta „numeracja”: tester może powiedzieć „mam t2”, a my wiemy,
# co dokładnie ma, bo obok leży notatka z sumą MD5.
#
# =====================================================================
#  CZEGO PILNUJE
# =====================================================================
#
#   1. czy APK jest PODPISANY — niepodpisany nie zainstaluje się z pliku,
#   2. czy versionCode W ŚRODKU APK zgadza się z tym z `scripts/build.sh`
#      — to łapie najczęstszy błąd: wysłanie wczorajszego builda po
#      podbiciu numeru wersji,
#   3. czy APK jest MŁODSZY od ostatniego commita — jeśli nie, to znaczy,
#      że build się nie przeszedł po ostatniej zmianie.
#
# Każdy z tych trzech punktów to ostrzeżenie, nie zatrzymanie — czasem
# świadomie wysyła się starszy plik. Ale musi paść na ekran, zanim plik
# pójdzie dalej.
#
# =====================================================================
#  UŻYCIE
# =====================================================================
#
#   bash przygotuj_apk.sh                     # katalog domyślny, arm64
#   bash przygotuj_apk.sh /ścieżka/do/repo
#   bash przygotuj_apk.sh --apk=/ścieżka/plik.apk     # wskaż plik sam
#   bash przygotuj_apk.sh --triplet=arm-android
#   bash przygotuj_apk.sh --wyslij            # + doczep do wydania na GitHubie
#
# Wynik ląduje w `wydania/apk/` w repozytorium, razem z notatką `.txt`
# gotową do wklejenia testerowi.
set -e

REPO="/DATA/SOFT/GIS/QFIELD_Pro/QField"
TRIPLET=""
APK_RECZNIE=""
WYSLIJ=0

for a in "$@"; do
  case "$a" in
    --triplet=*) TRIPLET="${a#--triplet=}" ;;
    --apk=*)     APK_RECZNIE="${a#--apk=}" ;;
    --wyslij)    WYSLIJ=1 ;;
    --*)         echo "Nieznany przełącznik: $a"; exit 1 ;;
    *)           REPO="$a" ;;
  esac
done

cd "$REPO"
[ -f scripts/build.sh ] || { echo "STOP: brak scripts/build.sh — to nie jest katalog WorkFielda"; exit 1; }
echo "== repo: $(pwd)"

# --- numer wersji, prosto ze źródła prawdy ----------------------------
# Jedno miejsce, z którego liczy się wszystko: napis w „O programie",
# versionCode w manifeście i nazwa pliku tutaj. Jak w build.sh.
WERSJA=$(grep -oP 'APP_VERSION_NUM:-\K[0-9.]+' scripts/build.sh | head -1)
[ -n "$WERSJA" ] || { echo "STOP: nie umiem odczytać APP_VERSION_NUM z scripts/build.sh"; exit 1; }
# APP_CODENAME bywa zapisane jako ${APP_CODENAME:-Nazwa} albo wprost —
# bierzemy pierwszą formę, która się trafi, bez znaków powłoki w środku.
NAZWA_KODOWA=$(grep -oP 'APP_CODENAME:-\s*\K[^}\n]+' scripts/build.sh | head -1)
[ -n "$NAZWA_KODOWA" ] || NAZWA_KODOWA=$(grep -oP 'APP_CODENAME=\s*"\K[^"\n]*' scripts/build.sh | head -1)
NAZWA_KODOWA=$(echo "$NAZWA_KODOWA" | sed 's/[[:space:]]*$//')
MAJOR=${WERSJA%%.*}
RESZTA=${WERSJA#*.}
MINOR=${RESZTA%%.*}
PATCH=${RESZTA#*.}
[ "$MINOR" = "$WERSJA" ] && MINOR=0
[ "$PATCH" = "$RESZTA" ] && PATCH=0
KOD=$(( MAJOR * 10000 + MINOR * 100 + PATCH ))
TRIPLET="${TRIPLET:-${triplet:-arm64-android}}"
ARCH="${TRIPLET%%-*}"
DZIEN=$(date +%Y%m%d)

echo "== wersja: ${WERSJA} ${NAZWA_KODOWA:+„${NAZWA_KODOWA}”}   versionCode: ${KOD}   triplet: ${TRIPLET}"

DOCELOWY_KAT="wydania/apk"
mkdir -p "$DOCELOWY_KAT"
# APK do repozytorium nie wchodzi — 100 MB na build, a git tego nie zapomina.
# Plik dystrybucyjny mieszka w wydaniu na GitHubie albo na NextCloudzie.
[ -f "${DOCELOWY_KAT}/.gitignore" ] || printf '*.apk\n*.txt\n' > "${DOCELOWY_KAT}/.gitignore"

# --- znalezienie APK --------------------------------------------------
# Nie zgaduję ścieżki. Ścieżka wyjściowa androiddeployqt zmieniała się
# między wersjami Qt i między wariantami `bundle`, więc pytam dysk:
# najświeższy .apk w drzewie budowania, z pominięciem tego, co sam już
# tu odłożyłem (inaczej przy drugim uruchomieniu kopiowałbym kopię).
if [ -n "$APK_RECZNIE" ]; then
  APK="$APK_RECZNIE"
  [ -f "$APK" ] || { echo "STOP: nie ma pliku $APK"; exit 1; }
else
  echo "== szukam APK w drzewie budowania…"
  APK=$(find . -type f -name '*.apk' \
          -not -path "./${DOCELOWY_KAT}/*" \
          -not -path './.git/*' \
          -printf '%T@\t%p\n' 2>/dev/null \
        | sort -rn \
        | awk -F'\t' '{print $2}' \
        | grep -i 'sign' \
        | head -1 || true)
  # Jeśli żaden nie ma „sign" w nazwie, bierz po prostu najświeższy —
  # o podpis i tak pytam niżej, osobno.
  if [ -z "$APK" ]; then
    APK=$(find . -type f -name '*.apk' \
            -not -path "./${DOCELOWY_KAT}/*" \
            -not -path './.git/*' \
            -printf '%T@\t%p\n' 2>/dev/null \
          | sort -rn | awk -F'\t' '{print $2}' | head -1)
  fi
  [ -n "$APK" ] || {
    echo "STOP: nie znalazłem żadnego .apk. Zbuduj najpierw:"
    echo "      triplet=${TRIPLET} ./scripts/build.sh"
    exit 1
  }
fi

echo "== znaleziony: $APK"
echo "   zbudowany:  $(date -r "$APK" '+%Y-%m-%d %H:%M')   $(du -h "$APK" | cut -f1)"

OSTRZEZENIA=()

# --- 1. czy podpisany -------------------------------------------------
PODPIS="nie wiem"
APKSIGNER=$(command -v apksigner || ls "${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)
if [ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ]; then
  if "$APKSIGNER" verify "$APK" >/dev/null 2>&1; then
    PODPIS="tak ($("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | grep -m1 -i 'DN:' | sed 's/.*CN=//; s/,.*//'))"
  else
    PODPIS="NIE"
    OSTRZEZENIA+=("APK nie jest podpisany — nie zainstaluje się z pliku. Sprawdź scripts/signing.env (STOREPASS/KEYPASS, KEYNAME=workfield).")
  fi
elif command -v unzip >/dev/null; then
  if unzip -l "$APK" 2>/dev/null | grep -qiE 'META-INF/.*\.(RSA|DSA|EC)$'; then
    PODPIS="tak (po zawartości META-INF; brak apksigner do sprawdzenia certyfikatu)"
  else
    PODPIS="NIE"
    OSTRZEZENIA+=("W APK nie widać podpisu w META-INF — prawdopodobnie niepodpisany.")
  fi
fi
echo "   podpis:     $PODPIS"

# --- 2. czy to TEN numer wersji --------------------------------------
# Najczęstszy błąd przy wysyłce: podbiliśmy numer, build padł, a w drzewie
# leży wczorajszy APK ze starym kodem. Manifest wie lepiej niż nazwa pliku.
AAPT=$(command -v aapt2 || command -v aapt || ls "${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)
KOD_W_APK=""
if [ -n "$AAPT" ] && [ -x "$AAPT" ]; then
  OPIS=$("$AAPT" dump badging "$APK" 2>/dev/null | head -1 || true)
  KOD_W_APK=$(echo "$OPIS" | grep -oP "versionCode='\K[0-9]+" || true)
  NAZWA_W_APK=$(echo "$OPIS" | grep -oP "versionName='\K[^']+" || true)
  if [ -n "$KOD_W_APK" ]; then
    echo "   w manifeście: versionCode=${KOD_W_APK}  versionName=${NAZWA_W_APK:-?}"
    if [ "$KOD_W_APK" != "$KOD" ]; then
      OSTRZEZENIA+=("versionCode w APK (${KOD_W_APK}) ≠ wyliczony z build.sh (${KOD}). To jest APK sprzed podbicia wersji — zbuduj jeszcze raz.")
    fi
  fi
fi

# --- 3. czy nie starszy od ostatniego commita -------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then
  CZAS_COMMITA=$(git log -1 --format=%ct 2>/dev/null || echo 0)
  CZAS_APK=$(stat -c %Y "$APK")
  if [ "$CZAS_APK" -lt "$CZAS_COMMITA" ]; then
    OSTRZEZENIA+=("APK jest STARSZY od ostatniego commita ($(git log -1 --format='%h %s' | cut -c1-60)) — nie zawiera ostatnich zmian.")
  fi
fi

# --- numeracja w nazwie -----------------------------------------------
PODSTAWA="WorkField-${WERSJA}-${KOD}-${ARCH}-${DZIEN}"
CEL="${DOCELOWY_KAT}/${PODSTAWA}.apk"
N=1
while [ -e "$CEL" ]; do
  N=$(( N + 1 ))
  CEL="${DOCELOWY_KAT}/${PODSTAWA}-t${N}.apk"
done

cp -p "$APK" "$CEL"
MD5=$(md5sum "$CEL" | cut -d' ' -f1)
ROZMIAR=$(du -h "$CEL" | cut -f1)
echo
echo "== odłożony: $CEL   (${ROZMIAR})"
echo "   md5: $MD5"

# --- notatka dla testera ----------------------------------------------
# Gotowa do wklejenia — tester nie musi wiedzieć, skąd się to wzięło,
# ale musi wiedzieć, CO instaluje i CO ma odesłać, jak nie zadziała.
NOTATKA="${CEL%.apk}.txt"
LINK_WYDANIE="https://github.com/ekolabynet/workfield/releases/tag/v${WERSJA}"
{
  echo "WorkField ${WERSJA}${NAZWA_KODOWA:+ „${NAZWA_KODOWA}”}  (build ${KOD}, ${ARCH}, $(date '+%Y-%m-%d'))"
  echo
  echo "Plik:  $(basename "$CEL")"
  echo "MD5:   ${MD5}"
  echo "Waga:  ${ROZMIAR}"
  echo
  echo "Co nowego:  ${LINK_WYDANIE}"
  echo "            (to samo widać w aplikacji: lewa szuflada → numer wersji na górze)"
  echo
  echo "Instalacja:"
  echo "  1. Skopiuj plik na telefon i otwórz go menedżerem plików."
  echo "  2. Android zapyta o zgodę na instalację z tego źródła — zgódź się."
  echo "  3. Jeśli instalacja odmówi („aplikacja nie została zainstalowana”),"
  echo "     odinstaluj poprzednią wersję i spróbuj ponownie. Projekty i dane"
  echo "     w pamięci telefonu zostają — WorkField trzyma je poza aplikacją."
  echo
  echo "Zgłaszanie uwag: podaj numer wersji z powyższej linijki (${WERSJA}, build ${KOD})."
  if [ ${#OSTRZEZENIA[@]} -gt 0 ]; then
    echo
    echo "--- UWAGI WEWNĘTRZNE (nie wysyłaj testerowi) ---"
    for o in "${OSTRZEZENIA[@]}"; do echo "  ! $o"; done
  fi
} > "$NOTATKA"
echo "   notatka: $NOTATKA"

# --- doczepienie do wydania -------------------------------------------
if [ "$WYSLIJ" = "1" ]; then
  if command -v gh >/dev/null; then
    echo
    echo "== doczepiam do wydania v${WERSJA}"
    gh release upload "v${WERSJA}" "$CEL" --clobber && echo "   OK: ${LINK_WYDANIE}"
  else
    echo "   BRAK gh — doczep ręcznie: ${LINK_WYDANIE}"
  fi
fi

echo
if [ ${#OSTRZEZENIA[@]} -gt 0 ]; then
  echo "=============================================================="
  echo "UWAGA — plik jest gotowy, ale coś się nie zgadza:"
  for o in "${OSTRZEZENIA[@]}"; do echo "  ! $o"; done
  echo "=============================================================="
else
  echo "Wszystko się zgadza: podpisany, numer wersji ten sam w APK i w repo."
fi
echo
echo "Do wysłania:  $CEL"
echo "Co nowego:    ${LINK_WYDANIE}"
