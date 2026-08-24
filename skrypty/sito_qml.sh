#!/bin/bash
# WorkField 24.08.2026 — dziewiate sito: CZY TO SIE W OGOLE SPARSUJE.
#
# DLACZEGO POWSTALO
#
# Wyslalem Piotrowi QfKopiaPanel.qml, ktory nie przeszedl kompilacji:
#
#     QfKopiaPanel.qml:510:28: error: Expected token `)'
#
# Powod: napisalem tekst tak, jak pisze sie w C++ —
#
#     qsTr("pierwsza czesc "
#          "druga czesc")
#
# W C++ dwa literaly obok siebie sklejaja sie same. W JavaScripcie to jest
# blad skladni. Ten sam odruch, ten sam ksztalt kodu, inny jezyk — i nic
# w pliku nie wyglada podejrzanie.
#
# Sprawdzalem przedtem tylko BILANS NAWIASOW wlasnym skryptem w Pythonie.
# Bilans sie zgadzal, bo nawiasy byly w porzadku; zla byla gramatyka.
# Licznik nawiasow nie jest parserem i nigdy nim nie bedzie — a parser
# lezy w pakiecie obok:
#
#     apt-get install qt6-declarative-dev-tools     (daje /usr/lib/qt6/bin/qmllint)
#
# JAK CZYTAC WYNIK
#
# qmllint poza drzewem budowania NIE ROZWIAZUJE importow QField-a i przez to
# konczy sie kodem 255 nawet dla zdrowego pliku. Kod wyjscia jest tu wiec
# bezuzyteczny. Rozstrzygaja komunikaty PARSERA: "Unexpected token" oraz
# "Expected token" — te pojawiaja sie wylacznie przy bledzie skladni.
#
# Sprawdzone w obie strony 24.08.2026: plik z sasiadujacymi literalami daje
# "Unexpected token `string literal'", a naprawiony nie daje nic.
#
# UZYCIE
#     skrypty/sito_qml.sh                    # wszystkie pliki .qml w repo
#     skrypty/sito_qml.sh src/app/qml/X.qml  # tylko wskazane

set -u

LINT=""
for k in /usr/lib/qt6/bin/qmllint /usr/lib/qt6/libexec/qmllint "$(command -v qmllint 2>/dev/null)"; do
  [ -x "$k" ] && LINT="$k" && break
done

if [ -z "$LINT" ]; then
  echo "Nie ma qmllint. Zainstaluj:" >&2
  echo "    sudo apt-get install qt6-declarative-dev-tools" >&2
  exit 2
fi

if [ "$#" -gt 0 ]; then
  PLIKI=( "$@" )
else
  mapfile -t PLIKI < <(find src plugins -name '*.qml' -not -path '*/build*' 2>/dev/null | sort)
fi

ZLE=0
SPRAWDZONYCH=0

for plik in "${PLIKI[@]}"; do
  [ -f "$plik" ] || continue
  SPRAWDZONYCH=$((SPRAWDZONYCH + 1))
  # Tylko komunikaty parsera. Reszta to nierozwiazane importy, ktorych poza
  # drzewem budowania rozwiazac sie nie da i ktore nic nie znacza.
  bledy=$("$LINT" "$plik" 2>&1 | grep -E "Unexpected token|Expected token")
  if [ -n "$bledy" ]; then
    ZLE=$((ZLE + 1))
    echo "=== $plik"
    echo "$bledy" | sed 's/^/    /'
  fi
done

echo
echo "Sprawdzonych plikow: $SPRAWDZONYCH, z bledem skladni: $ZLE"
[ "$ZLE" -eq 0 ] && echo "Skladnia w porzadku. To NIE znaczy, ze dziala — znaczy, ze sie sparsuje."
exit $(( ZLE > 0 ? 1 : 0 ))
