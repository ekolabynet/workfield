# Wyposażenie w C++ — jak to wpiąć

Paczka dokłada do forka warstwę czasowników w C++, interpreter przepisów
w QML i pierwszy przepis. Po wpięciu **nowe zadanie powstaje z przepisu,
a nie z kopii katalogu** — offline, na telefonie.

Wszystkie użyte API sprawdziłem w źródłach QGIS-a, nie z pamięci. Twój
`vcpkg/ports/qgis/portfile.cmake` przypina QGIS na `78f7d8e`; ja czytałem
dzisiejszy `master`. Użyte klasy są stabilne od lat, ale gdyby coś nie
skompilowało się na pierwszym podejściu, tu jest pierwszy trop.

## 0. Zanim cokolwiek

```bash
cd /DATA/SOFT/GIS/QFIELD_Pro/QField
git status
git log --oneline -3
git push
```

Pracuj na gałęzi, nie na `master` prosto z buta:

```bash
git checkout -b wyposazenie
```

## 1. Rozpakuj

Nowe pliki, nic nie nadpisują:

```
src/core/utils/narzedziaprojektu.h
src/core/utils/narzedziaprojektu.cpp
src/app/qml/QfPrzepis.qml
wyposazenie/przepisy/platy_roslinnosci.json
skrypty/sprawdz_przepis.py
```

## 2. Trzy wpięcia w build (po jednej linijce każde)

**`src/core/CMakeLists.txt`** — obok `utils/zalacznikiutils.cpp` (l. ~84)
i `utils/zalacznikiutils.h` (l. ~214):

```cmake
    utils/narzedziaprojektu.cpp
```
```cmake
    utils/narzedziaprojektu.h
```

**`src/core/qfieldcoreqmlregistration.cpp`** — dwie linijki, obok istniejących:

```cpp
#include "utils/narzedziaprojektu.h"
```
(przy `#include "utils/zalacznikiutils.h"`, l. ~101)

```cpp
    REGISTER_SINGLETON( "org.qfield", NarzedziaProjektu, "NarzedziaProjektu" );
```
(w bloku rejestracji, l. ~205)

**`src/app/CMakeLists.txt`** — na liście plików QML (l. ~149):

```cmake
    qml/QfPrzepis.qml
```

## 3. Jedno wpięcie w interfejsie

W **`src/app/qml/qgismobileapp.qml`**, gdzieś obok innych komponentów
najwyższego poziomu, instancja interpretera:

```qml
  QfPrzepis {
    id: qfPrzepis

    onZbudowano: function (sciezka, nazwa) {
      displayToast(qsTr("Zadanie %1 gotowe").arg(nazwa));
    }
    onPotknieto: function (komunikat) {
      displayToast(komunikat, "error");
    }
  }
```

I podmiana w `onAccepted` dialogu „kopia robocza szablonu" (l. ~5074).
**Było:**

```qml
      welcomeScreen.createProjectFromTemplate(dir, templateName + " Projekt " + new Date().toISOString().slice(0, 10));
```

**Ma być:**

```qml
      const nazwa = templateName + " Projekt " + new Date().toISOString().slice(0, 10);

      // WorkField: szablon z przepisem budujemy od zera z aktualnego
      // wyposażenia. Kopia katalogu (createProjectFromTemplate) była dotąd
      // jedynym mechanizmem — i jedynym źródłem dryfu (17.08.2026).
      if (FileUtils.fileExists(dir + "/przepis.json")) {
        qfPrzepis.noweZadanie(dir + "/przepis.json", iface.dataRoot() + "Imported Projects", nazwa);
      } else {
        welcomeScreen.createProjectFromTemplate(dir, nazwa);
      }
```

**`WelcomeScreen.qml` zostaje nietknięty** — jest plikiem upstreamowym,
a delta tam już rośnie. Wystarczy, że przechwytujemy w naszym pliku.

## 4. Zanim zbudujesz — sprawdź przepis

Build Androida trwa godziny, a literówkę w przepisie widać dopiero w terenie.
Kontrola jest darmowa i wyłapuje m.in. pułapkę z kluczem `nazwa` zamiast
`etykieta` w kaflach paska:

```bash
python3 skrypty/sprawdz_przepis.py wyposazenie/przepisy/*.json
```

Powinno wypisać „bez zastrzeżeń". Kod wyjścia 1 = są błędy.

## 5. Build i próba na komputerze

```bash
cmake -S . -B build-sys -Wno-dev
cmake --build build-sys -j$(nproc)
./build-sys/output/bin/qfield
```

Próba na sucho, bez ruszania szablonów w magazynie:

```bash
mkdir -p /tmp/proba_przepis
cp wyposazenie/przepisy/platy_roslinnosci.json /tmp/proba_przepis/przepis.json
```

W aplikacji: otwórz ten katalog jako szablon i wybierz „Utwórz kopię roboczą".
Powinno powstać zadanie z pięcioma warstwami roboczymi, trzema tabelami
`ZAL_`, kaflami P/Z/G/T, włączonym przyciąganiem i unikaniem nakładania
na warstwie `platy`.

Co obejrzeć po fakcie:

```bash
python3 skrypty/wyposazenie.py sprawdz <katalog nowego zadania> --glosno
```

Wszystkie pięć modułów ma pokazać `OK`. Jeśli któryś pokaże `!ROZJ`, to
znaczy, że przepis go stemplował, a czasownik nie zadziałał — i wtedy wiadomo
dokładnie który.

## 6. Dopiero potem Android

```bash
triplet=arm64-android ./scripts/build.sh
find build-arm64-android -name "*.apk"
adb install -r <apk>
```

## Czego ta paczka jeszcze NIE robi

1. **Doposażania istniejącego projektu z aplikacji.** `QfPrzepis.zastosuj()`
   jest napisane tak, żeby dało się je wywołać na wczytanym projekcie —
   brakuje ekranu, który to woła i pokazuje stan wyposażenia. To jest
   następny krok i nie wymaga już nowego C++.
2. **Pobierania katalogu i przepisów z sieci** (GitHub raw + NextCloud).
   Dziś przepis leży obok szablonu na karcie.
3. **Renderowania i etykiet** — nowe warstwy dostają domyślny styl QGIS-a.
   `LayerUtils` ma `setDefaultRenderer` i `setSingleSymbolRenderer`; dołożenie
   sekcji `styl` do przepisu to jeden czasownik więcej.
4. **Podkładów** (WMS GUGiK, DXF mapy zasadniczej). Osobna sprawa, osobny
   czasownik.

## Jedna rzecz, której nie mogłem sprawdzić

Nie mam jak skompilować tego kodu ani uruchomić QML-a — nie mam Twojego
środowiska. Każde API weryfikowałem po nagłówkach QGIS-a, ale pierwszy build
prawie na pewno wypluje jakieś drobiazgi (brakujący `#include`, inna nazwa
przeciążenia). To jest normalne i tanie do naprawienia — wklej mi błąd
kompilatora, nie przepisuj kodu ręcznie.
