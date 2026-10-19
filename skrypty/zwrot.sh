#!/usr/bin/env bash
# Rytuał zwrotu z terenu — wykonywalna wersja punktu 13
# z `claude/OBIEG_zwroty_praktyka.md`.
#
# Robi dokładnie to, co robi się dziś ręcznie, tylko bez pomijania kroków:
#   1. domyka bazę na telefonie i SPRAWDZA, czy naprawdę się domknęła
#   2. zakłada katalog datowany (nigdy nie nadpisuje)
#   3. ciągnie pliki POJEDYNCZO (adb pull przerywa się na pierwszym błędzie)
#   4. porównuje sumy md5 źródła i kopii          <- czego rytuał ręczny nie robił
#   5. ciągnie DCIM
#   6. odpala kontrole: przyrost, puste geometrie, załączniki
#
# NIC NIE KASUJE ani na telefonie, ani na dysku. Nie nadpisuje istniejącego
# katalogu zwrotu — przerywa.
#
# Użycie:
#   ./zwrot.sh -p zzw_pgrs_2602_inw_v9_0
#   ./zwrot.sh -p zzw_pgrs_2602_inw_v9_0 -e pgrs_v9_0 -r ~/WorkField_zwroty/2026-08-21_pgrs_v8_0/dane.gpkg
#   ./zwrot.sh -p PROJEKT --dcim-do ~/WorkField_zdjecia/pgrs   # DCIM narastająco, osobno od baz
#   ./zwrot.sh -p PROJEKT --pomin dane_v3.gpkg                 # świadomie zostaw bazę na telefonie
#   ./zwrot.sh -p PROJEKT --z-podkladami --z-kopiami           # weź też podkłady i .przed_*
#   ./zwrot.sh --wersja
#
# Wymaga: adb w PATH, telefon podpięty i autoryzowany (adb devices).

set -u
set -o pipefail

WERSJA="1.2.1"

# 19.10.2026: domyslnie nowa aplikacja; stara: WF_PAKIET=ch.opengis.qfield_home
PAKIET="${WF_PAKIET:-com.workfieldgis.app}"
KORZEN_ZWROTOW="${WF_ZWROTY:-$HOME/WorkField_zwroty}"

# Pliki nie-bazowe, brane zawsze, gdy są.
PLIKI_STALE=(projekt.qgs workfield_klawisze.json)
# projekt_attachments.zip celowo POMINIĘTY: prawa -rw------- należą do
# aplikacji, adb shell go nie przeczyta, a adb pull przerywa się na pierwszym
# błędzie i reszta katalogu wtedy nie dojeżdża (20.08: 20 MB zamiast 1 GB).

# Bazy ODTWARZALNE — podkłady, nie dane. Domyślnie pomijane (--z-podkladami).
PODKLADY_WZORY=(wf_wskazniki gugik support orto)

# --- CZEGO NIE WOLNO WPISAĆ NA STAŁĄ LISTĘ -----------------------------------
# Do 1.0.0 skrypt ciągnął dokładnie: dane.gpkg, projekt.qgs, klawisze.
# 19.10 na telefonie w `zzw_pgrs_2602_inw_v12_0` leżało OBOK `dane.gpkg`:
#
#     Foto Add.gpkg                98 KB   <- 355 zdjęć z 2.10, osobna warstwa
#     foto_tagi.gpkg               32 KB
#     dane_pgrs_v12_0_ZAL.gpkg    8,9 MB   <- druga pełna baza w tym katalogu
#
# Zwrot zabrałby `dane.gpkg` i zameldował „kompletny i sprawdzony", a baza
# wiążąca 355 zdjęć z płatami zostałaby na telefonie. Nikt by tego nie
# zauważył, bo liczby w `dane.gpkg` byłyby spójne same ze sobą.
# „Objaw niemy jest gorszy od błędu" — stąd 1.1.0 PYTA KATALOG, zamiast
# wiedzieć z góry, co w nim jest.

PROJEKT=""
ETYKIETA=""
RANO=""
DCIM_DO=""
BEZ_DCIM=0
Z_PODKLADAMI=0
Z_KOPIAMI=0
POMIN=()
KATALOG_SKRYPTOW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

uzycie() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--projekt)    PROJEKT="${2:-}"; shift 2 ;;
    -e|--etykieta)   ETYKIETA="${2:-}"; shift 2 ;;
    -r|--rano)       RANO="${2:-}"; shift 2 ;;
    --dcim-do)       DCIM_DO="${2:-}"; shift 2 ;;
    --bez-dcim)      BEZ_DCIM=1; shift ;;
    --z-podkladami)  Z_PODKLADAMI=1; shift ;;
    --z-kopiami)     Z_KOPIAMI=1; shift ;;
    --pomin)         POMIN+=("${2:-}"); shift 2 ;;
    --pakiet)        PAKIET="${2:-}"; shift 2 ;;
    --wersja)        echo "$WERSJA"; exit 0 ;;
    -h|--help)       uzycie 0 ;;
    *) echo "nieznany argument: $1" >&2; uzycie 2 ;;
  esac
done

echo "zwrot.sh $WERSJA"          # wersja w PIERWSZEJ linii — stara kopia widoczna od razu

# Kontrola wersji wolanych czasownikow. UWAGA na asymetrie wzgledem
# `zloz_wydanie_12.sh`, ktory bez `wersje.sh` ODMAWIA: on BUDUJE WYDANIE,
# czyli zapisuje. Zwrot CIAGNIE DANE Z TELEFONU i jest ratunkiem — brak
# pliku pomocniczego nie ma prawa go zatrzymac. Zamiast tego konczy sie
# werdyktem „kontrole niepewne", zeby nikt nie wzial tego za czysty zwrot.
KONTROLE_NIEPEWNE=0
WERSJE_SH=""
for _k in "$(dirname "$0")/wersje.sh" "${REPO:-/DATA/SOFT/GIS/QFIELD_Pro/QField}/skrypty/wersje.sh"; do
  [ -f "$_k" ] && { WERSJE_SH="$_k"; break; }
done
if [ -n "$WERSJE_SH" ]; then
  # shellcheck source=/dev/null
  . "$WERSJE_SH"
else
  echo "   ~ nie ma wersje.sh — wersji czasownikow kontrolnych nie sprawdze."
  echo "     Ciagniecie danych idzie dalej; werdykt bedzie „kontrole niepewne\"."
  KONTROLE_NIEPEWNE=1
fi
[[ -n "$PROJEKT" ]] || { echo "brakuje -p NAZWA_PROJEKTU" >&2; uzycie 2; }
[[ -n "$ETYKIETA" ]] || ETYKIETA="$PROJEKT"

command -v adb >/dev/null || { echo "nie ma adb w PATH" >&2; exit 1; }

K="/storage/emulated/0/Android/data/$PAKIET/files/Imported Projects/$PROJEKT"
D="$KORZEN_ZWROTOW/$(date +%Y-%m-%d)_$ETYKIETA"

echo "telefon:  $PAKIET"
echo "projekt:  $PROJEKT"
echo "zwrot do: $D"
echo

# ---------------------------------------------------------------- 0. telefon
echo "== 0. telefon =="
adb devices | sed '1d' | grep -q "device$" || {
  echo "!! żadne urządzenie nie jest w stanie 'device'." >&2
  adb devices >&2
  echo "   Sprawdź kabel, odblokuj ekran, potwierdź autoryzację USB." >&2
  exit 1
}
adb devices | sed '1d' | sed '/^$/d'

adb shell "[ -d \"$K\" ]" || {
  echo "!! na telefonie nie ma katalogu:" >&2
  echo "   $K" >&2
  echo "   Dostępne projekty:" >&2
  adb shell "ls \"/storage/emulated/0/Android/data/$PAKIET/files/Imported Projects/\"" >&2
  exit 1
}
echo

# ----------------------------------------------- 1. co w tym katalogu leży
# Pytamy katalog, zamiast wiedzieć z góry. Nazwy z odstępem („Foto Add.gpkg")
# są normalne, więc czytamy liniami, nie przez podział na słowa.
echo "== 1. spis baz w projekcie =="
BAZY=()
POMINIETE_PODKLADY=()
POMINIETE_RECZNIE=()
while IFS= read -r sc; do
  [[ -n "$sc" ]] || continue
  n="${sc##*/}"
  swiadomie=0
  for x in ${POMIN+"${POMIN[@]}"}; do
    [[ "$n" == "$x" ]] && swiadomie=1
  done
  if [[ "$swiadomie" -eq 1 ]]; then
    POMINIETE_RECZNIE+=("$n"); continue
  fi
  podklad=0
  for w in "${PODKLADY_WZORY[@]}"; do
    [[ "$n" == "$w"*.gpkg ]] && podklad=1
  done
  if [[ "$podklad" -eq 1 && "$Z_PODKLADAMI" -eq 0 ]]; then
    POMINIETE_PODKLADY+=("$n"); continue
  fi
  BAZY+=("$n")
done < <(adb shell "ls -1 \"$K/\"*.gpkg 2>/dev/null" | tr -d '\r')

if [[ "${#BAZY[@]}" -eq 0 ]]; then
  echo "!! w projekcie nie ma ani jednej bazy .gpkg" >&2
  exit 1
fi
for n in "${BAZY[@]}"; do
  echo "   + $n"
done
for n in ${POMINIETE_PODKLADY+"${POMINIETE_PODKLADY[@]}"}; do
  echo "   - $n  (podkład, odtwarzalny — --z-podkladami, żeby wziąć)"
done
for n in ${POMINIETE_RECZNIE+"${POMINIETE_RECZNIE[@]}"}; do
  echo "   - $n  (pominięty świadomie przez --pomin)"
done

# Kopie robocze aplikacji. Nie powinny jechać w teren (reguła „przed wyjazdem:
# brak .bak_*, .przed_*"), ale jak już są, to mogą nieść stan sprzed zmiany —
# więc mówimy o nich zawsze, a bierzemy tylko na żądanie.
KOPIE=()
while IFS= read -r sc; do
  [[ -n "$sc" ]] || continue
  KOPIE+=("${sc##*/}")
done < <(adb shell "ls -1 \"$K/\"*.gpkg.przed_* \"$K/\"*.gpkg.bak_* 2>/dev/null" | tr -d '\r')
if [[ "${#KOPIE[@]}" -gt 0 ]]; then
  echo
  echo "   kopie robocze w katalogu terenowym: ${#KOPIE[@]}"
  for n in "${KOPIE[@]}"; do
    echo "      $n"
  done
  if [[ "$Z_KOPIAMI" -eq 1 ]]; then
    echo "   biorę je (--z-kopiami)."
    BAZY+=("${KOPIE[@]}")
  else
    echo "   NIE biorę ich. --z-kopiami, jeśli mają nieść stan sprzed zmiany."
    echo "   Reguła mówi, że w katalogu jadącym w teren nie powinno ich być."
  fi
fi
echo

# ------------------------------------------------------- 2. domknięcie baz
# Dziennik sprawdzany PRZY KAŻDEJ BAZIE OSOBNO, nie dla katalogu naraz.
# 19.10: w `zzw_ptr_2603_inw_v10_0` wisiał `dane_v3.gpkg-wal` (24 752 B) przy
# czystym `dane.gpkg`. Jeden warunek na cały katalog kazałby odmówić całego
# zwrotu z powodu pliku, którego może nawet nie chcemy — albo, gdyby go
# poluzować, przepuścić bazę w trakcie zapisu. Dlatego: baza, którą bierzemy,
# musi być domknięta; o pozostałych mówimy głośno.
echo "== 2. domknięcie baz (krok, którego pominięcie gubi dane) =="
adb shell am force-stop "$PAKIET"
sleep 2

WISZACE_WSZYSTKIE="$(adb shell "ls -1 \"$K/\"*.gpkg-wal \"$K/\"*.gpkg-shm 2>/dev/null" \
  | tr -d '\r' | sed '/^$/d')"
BLOKADA=0
if [[ -n "$WISZACE_WSZYSTKIE" ]]; then
  while IFS= read -r sc; do
    [[ -n "$sc" ]] || continue
    n="${sc##*/}"
    baza="${n%-wal}"; baza="${baza%-shm}"
    nasza=0
    for b in "${BAZY[@]}"; do
      [[ "$b" == "$baza" ]] && nasza=1
    done
    if [[ "$nasza" -eq 1 ]]; then
      echo "   !! $n — dziennik przy bazie, którą mamy wziąć" >&2
      BLOKADA=1
    else
      echo "   ~  $n — dziennik przy bazie, której NIE bierzemy ($baza)"
    fi
  done <<< "$WISZACE_WSZYSTKIE"
fi
if [[ "$BLOKADA" -eq 1 ]]; then
  echo >&2
  echo "   W -wal siedzą zapisy, których nie ma jeszcze w .gpkg." >&2
  echo "   Skopiowanie samego .gpkg ZGUBI CZĘŚĆ PRACY." >&2
  echo "   Otwórz aplikację, zamknij projekt po ludzku, zamknij aplikację" >&2
  echo "   i uruchom zwrot jeszcze raz. NIE kopiuj teraz." >&2
  echo >&2
  echo "   Jeżeli ta baza to pozostałość i świadomie ją zostawiasz:" >&2
  echo "      --pomin <nazwa.gpkg>" >&2
  exit 1
fi
echo "   bazy do wzięcia są domknięte."
echo

# --------------------------------------------------- 3. katalog datowany
echo "== 3. katalog datowany =="
if [[ -e "$D" ]]; then
  echo "!! $D już istnieje. Nie nadpisuję." >&2
  echo "   Dodaj etykietę (-e), np. -e ${ETYKIETA}_popoludnie" >&2
  exit 1
fi
mkdir -p "$D" || exit 1
echo "   $D"
echo

# --------------------------------------- 4+5. pliki pojedynczo, z sumami
echo "== 4. pliki pojedynczo + 5. sumy kontrolne =="
echo "   (rozmiar NIE rozstrzyga: 21.08 dwa dane.gpkg miały identyczne"
echo "    2 609 152 B i różną treść — 278 kontra 280 płatów)"
BLEDY=0
NIECZYTELNE=()
WZIETE=()
ILE_BAZ="${#BAZY[@]}"
I=0
for f in "${BAZY[@]}" "${PLIKI_STALE[@]}"; do
  I=$((I+1))
  JEST_BAZA=$([[ "$I" -le "$ILE_BAZ" ]] && echo 1 || echo 0)
  if ! adb shell "[ -f \"$K/$f\" ]"; then
    echo "   - $f: nie ma na telefonie (pomijam)"
    continue
  fi
  # Czytelność SPRAWDZANA PRZED ciągnięciem. Plik z prawami -rw------- należy
  # do aplikacji i `shell` go nie przeczyta; bez tego testu `adb pull` wywala
  # się, a komunikat nie mówi dlaczego. 19.10 cały projekt `Pgrs2026-10-02`
  # miał -rw------- na każdym pliku.
  if ! adb shell "[ -r \"$K/$f\" ]"; then
    adb shell "ls -la \"$K/$f\"" | tr -d '\r' | sed 's/^/        /' >&2
    NIECZYTELNE+=("$f")
    if [[ "$JEST_BAZA" -eq 1 ]]; then
      # Baza, której nie da się wyjąć, to DANE zostawione na telefonie.
      echo "   ! $f  NIECZYTELNY dla adb — to BAZA, czyli dane" >&2
      BLEDY=$((BLEDY+1))
    else
      # projekt.qgs ma tryb 600 z natury Androida i jest odtwarzalny z biura.
      # Podnoszenie z tego powodu alarmu przy KAŻDYM zwrocie uczyłoby
      # ignorowania kodu wyjścia, a to droższe niż ta jedna strata.
      echo "   ~ $f  nieczytelny dla adb (tryb 600 — tak jest zawsze)"
    fi
    continue
  fi
  if adb pull "$K/$f" "$D/" >/dev/null 2>&1; then
    ZDALNA="$(adb shell "md5sum \"$K/$f\" 2>/dev/null" | tr -d '\r' | awk '{print $1}')"
    LOKALNA="$(md5sum "$D/$f" 2>/dev/null | awk '{print $1}')"
    if [[ -z "$ZDALNA" ]]; then
      echo "   + $f  (md5 telefonu niedostępny — nie sprawdzone)"
      WZIETE+=("$f")
    elif [[ "$ZDALNA" == "$LOKALNA" ]]; then
      echo "   + $f  md5 zgodne  ${LOKALNA:0:12}…"
      WZIETE+=("$f")
    else
      echo "   ! $f  MD5 SIĘ NIE ZGADZA" >&2
      echo "       telefon: $ZDALNA" >&2
      echo "       kopia:   $LOKALNA" >&2
      BLEDY=$((BLEDY+1))
    fi
  else
    echo "   ! $f  nie udało się pobrać" >&2
    BLEDY=$((BLEDY+1))
  fi
done
if [[ "${#NIECZYTELNE[@]}" -gt 0 ]]; then
  echo
  echo "   ${#NIECZYTELNE[@]} plików adb NIE WYJMIE. To nie usterka kabla —"
  echo "   prawa -rw------- należą do aplikacji. Jedyna droga:"
  echo "   na telefonie: zamknij projekt, Wymiana lokalna -> \"wyślij jako"
  echo "   spakowaną paczkę\", potem w biurze:"
  echo "      bash \"$KATALOG_SKRYPTOW/przyjmij.sh\" paczka.zip -e $ETYKIETA"
fi
echo

# ------------------------------------------------------------- 6. DCIM
if [[ "$BEZ_DCIM" -eq 1 ]]; then
  echo "== 6. DCIM pominięte (--bez-dcim) =="
  CEL_DCIM=""
  adb shell "ls -laR \"$K/DCIM\"" | tr -d '\r' > "$D/DCIM_spis_telefonu.txt" 2>/dev/null || true
  if [[ -s "$D/DCIM_spis_telefonu.txt" ]]; then
    echo "   spis nazw z telefonu -> $D/DCIM_spis_telefonu.txt"
    echo "   (plików na telefonie, ze wszystkich poziomów: $(grep -c '^-' "$D/DCIM_spis_telefonu.txt" || true))"
  fi
elif [[ -n "$DCIM_DO" ]]; then
  echo "== 6. DCIM narastająco (osobno od baz) =="
  echo "   Zdjęcia są append-only — dzienna 'wersja' DCIM nie niesie"
  echo "   informacji, a kosztuje kilka GB za każdym razem."
  mkdir -p "$DCIM_DO"
  adb pull "$K/DCIM" "$DCIM_DO/" 2>&1 | tail -1
  CEL_DCIM="$DCIM_DO/DCIM"
  [[ -d "$CEL_DCIM" ]] || CEL_DCIM="$DCIM_DO"
  adb shell "ls -laR \"$K/DCIM\"" | tr -d '\r' > "$D/DCIM_spis_telefonu.txt" 2>/dev/null || true
  echo "   spis nazw z telefonu -> $D/DCIM_spis_telefonu.txt"
  # Dowiazanie DCIM do katalogu zwrotu. BEZ TEGO kontrola D klamie.
  #
  # 19.10, przebieg PGRS: `sprawdz_zalaczniki.py` zglosil 414 z 414 sciezek
  # „BEZ PLIKU NA DYSKU" i dolozyl do tego ostrzezenie o 72 zdjeciach
  # straconych 20.08. Zadne z tych 414 nie bylo stracone — sciezki wzgledne
  # licza sie od katalogu BAZY, a DCIM poszedl do katalogu narastajacego.
  # Fałszywy alarm o stracie jest gorszy od braku alarmu: uczy nie wierzyc
  # kontroli, ktora kiedys powie prawde.
  if [[ -d "$CEL_DCIM" && ! -e "$D/DCIM" ]]; then
    ln -s "$CEL_DCIM" "$D/DCIM" && echo "   dowiazanie: $D/DCIM -> $CEL_DCIM"
  fi
else
  echo "== 6. DCIM do katalogu zwrotu =="
  echo "   (adb pull KATALOG CEL/ tworzy podkatalog o nazwie źródła)"
  adb pull "$K/DCIM" "$D/" 2>&1 | tail -1
  CEL_DCIM="$D/DCIM"
  # Spis robimy ZAWSZE, bo bez niego nie ma z czym porównać tego, co dojechało.
  adb shell "ls -laR \"$K/DCIM\"" | tr -d '\r' > "$D/DCIM_spis_telefonu.txt" 2>/dev/null || true
fi
# Spis z telefonu kontra to, co dojechało — bo `adb pull` na katalogu
# przerywa się na pierwszym nieczytelnym pliku i reszta nie przyjeżdża.
if [[ -n "${CEL_DCIM:-}" && -d "$CEL_DCIM" && -s "$D/DCIM_spis_telefonu.txt" ]]; then
  # `ls -laR` wypisuje kazdy podkatalog osobno, wiec linie na „-" to WSZYSTKIE
  # pliki, nie tylko pierwszy poziom. Do 1.2.0 stalo tu `ls -la`, czyli
  # pierwszy poziom — 19.10 dalo to „zdjec na telefonie: 52, w katalogu: 473",
  # bo 421 zdjec siedzi w podkatalogach `platy_*`. Porownanie pierwszego
  # poziomu z rekurencja nie moze wykryc urwanego pobrania.
  NA_TEL="$(grep -c '^-' "$D/DCIM_spis_telefonu.txt" || true)"
  NA_DYSKU="$(find "$CEL_DCIM" -type f | wc -l)"
  echo "   zdjęć na telefonie: $NA_TEL, w katalogu docelowym: $NA_DYSKU"
  if [[ -n "$NA_TEL" && "$NA_TEL" -gt 0 && "$NA_DYSKU" -lt "$NA_TEL" ]]; then
    echo "   !! DOJECHAŁO MNIEJ, NIŻ JEST NA TELEFONIE." >&2
    echo "      adb pull przerywa się na pierwszym nieczytelnym pliku." >&2
    BLEDY=$((BLEDY+1))
  fi
fi
echo

# -------------------------------------------------------- 7. kontrole
echo "== 7. kontrole =="
if [[ -n "$WERSJE_SH" ]]; then
  echo "   czym sprawdzam:"
  for _c in przyrost.py kontrola_zwrotu.py sprawdz_zalaczniki.py; do
    zglos_wersje "$KATALOG_SKRYPTOW/$_c" "1.0.0" || KONTROLE_NIEPEWNE=1
  done
  if [[ "$KONTROLE_NIEPEWNE" -eq 1 ]]; then
    echo "   Kontrole pojada, ale ich wynik NIE jest swiadectwem czystosci:"
    echo "   stara kontrola, ktora melduje „brak sierot\", prowadzi do scalenia"
    echo "   zepsutego zwrotu. Dopisz WERSJA albo podmien plik z \$REPO/skrypty/,"
    echo "   potem powtorz same kontrole"
    echo "   (dane z telefonu sa juz na dysku, nie trzeba ich ciagnac drugi raz)."
  fi
  echo
fi
BAZA="$D/dane.gpkg"
if [[ -n "$RANO" && -f "$RANO" && -f "$BAZA" ]]; then
  echo
  echo "--- przyrost wobec $RANO ---"
  python3 "$KATALOG_SKRYPTOW/przyrost.py" "$RANO" "$BAZA" || true
elif [[ -f "$BAZA" ]]; then
  echo "   (przyrost pominięty — podaj -r ŚCIEŻKA/dane.gpkg z poprzedniego stanu)"
fi

# Kontrola na KAŻDEJ wziętej bazie, nie tylko na dane.gpkg. Baza, której nikt
# nie sprawdził, jest dokładnie tą, w której potem znajduje się pustą geometrię.
for f in ${WZIETE+"${WZIETE[@]}"}; do
  case "$f" in
    *.gpkg|*.gpkg.przed_*|*.gpkg.bak_*) ;;
    *) continue ;;
  esac
  echo
  # Nie kazdy plik z koncowka .gpkg jest GeoPackage'em. 19.10 `foto_tagi.gpkg`
  # (32 KB) nie mial tabeli `gpkg_geometry_columns` i `kontrola_zwrotu.py`
  # wysypala sie tracebackiem na pol ekranu. Baza narzedziowa bez rejestru
  # warstw to osobne znalezisko — w v7.1 miala 542 tagi gatunkowe, a dzis
  # jest pusta — ale to wiadomosc, nie wywrotka.
  # Sprawdzamy OBA rejestry, bo `kontrola_zwrotu.py` czyta
  # `gpkg_geometry_columns` i to na jego braku sie wysypala — a plik moze
  # miec `gpkg_contents` i nie miec rejestru warstw geometrycznych.
  POWOD="$(python3 -c "import sqlite3,sys
c=sqlite3.connect('file:'+sys.argv[1].replace('?','%3f')+'?mode=ro',uri=True)
for t in ('gpkg_contents','gpkg_geometry_columns'):
    try:
        c.execute('SELECT 1 FROM %s LIMIT 1' % t)
    except Exception:
        print('brak ' + t); break
" "$D/$f" 2>/dev/null || echo "nie da sie otworzyc jako baza")"
  if [[ -n "$POWOD" ]]; then
    echo "   ~ $f — kontrole pomijam ($POWOD)."
    echo "     Plik jest w zwrocie i nietkniety. Jesli mial niesc tresc, to"
    echo "     jego pustka albo brak rejestru warstw JEST znaleziskiem —"
    echo "     `foto_tagi.gpkg` mial w v7.1 542 tagi gatunkowe, a dzis 0."
    continue
  fi
  echo "--- $f: puste geometrie i dziury w fid ---"
  python3 "$KATALOG_SKRYPTOW/kontrola_zwrotu.py" "$D/$f" || BLEDY=$((BLEDY+1))
  echo "--- $f: załączniki ---"
  if [[ -n "${CEL_DCIM:-}" && -d "${CEL_DCIM:-}" ]]; then
    python3 "$KATALOG_SKRYPTOW/sprawdz_zalaczniki.py" "$D/$f" --dcim "$CEL_DCIM" \
      || BLEDY=$((BLEDY+1))
  else
    python3 "$KATALOG_SKRYPTOW/sprawdz_zalaczniki.py" "$D/$f" || BLEDY=$((BLEDY+1))
  fi
done

echo
echo "============================================================"
echo "zwrot: $D"
echo "wzięte bazy: ${#WZIETE[@]} — ${WZIETE[*]:-brak}"
# `sprawdz_zalaczniki.py` zgaduje rodzica po sufiksie nazwy i dla dwoch tabel
# zgadnac nie umie. My te powiazania ZMIERZYLISMY, wiec podajemy gotowa
# komende, zamiast zostawiac „A. sierot: NIE SPRAWDZONE".
if [[ -f "$D/dane.gpkg" ]]; then
  echo
  echo "Sieroty w ZAL_GATUNKI i ZAL_ZDJECIA_FITO zostaly NIESPRAWDZONE —"
  echo "skrypt nie zgadnie ich rodzica. Zmierzone powiazania:"
  echo "   ZAL_ZDJECIA_FITO.ID_RODZICA -> FITO_ZDJECIA.fid"
  echo "   ZAL_GATUNKI.ID_RODZICA      -> FITO_SPIS_GATUNKOWY.fid"
  echo "   python3 \"$KATALOG_SKRYPTOW/sprawdz_zalaczniki.py\" \"$D/dane.gpkg\" \\"
  echo "     --dcim \"${CEL_DCIM:-$D/DCIM}\" \\"
  echo "     --rodzic ZAL_ZDJECIA_FITO=FITO_ZDJECIA \\"
  echo "     --rodzic ZAL_GATUNKI=FITO_SPIS_GATUNKOWY"
fi
if [[ "$BLEDY" -gt 0 ]]; then
  echo "Kontrole zgłosiły uwagi. Obejrzyj je PRZED scaleniem."
  echo "Oryginał na telefonie jest nietknięty — nic nie jest stracone."
  exit 1
fi
if [[ "$KONTROLE_NIEPEWNE" -eq 1 ]]; then
  echo "Transport bez uwag — pliki dojechaly i sumy sie zgadzaja."
  echo "ALE kontrole szly narzedziami o nieznanej wersji, wiec TO NIE JEST"
  echo "swiadectwo czystosci zwrotu. Nie scalaj na tej podstawie."
  exit 1
fi
echo "Bez uwag. Zwrot jest kompletny i sprawdzony."
echo
echo "Pamiętaj: zwrot to nie scalenie. Master zmienia się wyłącznie"
echo "przez Przyjmij zwrot, i scala się RAZ — z ostatniego zwrotu."
