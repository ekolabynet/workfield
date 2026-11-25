# WorkFieldGIS 0.14.15 „Fractal Fir”

Wydanie z 25.11.2026 — zmiany od 0.14.13. Numer 0.14.14 nosiły wewnętrzne buildy testowe; takiego wydania nie było.

## Układ współrzędnych rozpoznawany z samych liczb

Aplikacja patrzy na wartości współrzędnych warstwy i rozpoznaje, w jakim są układzie: PL-2000 (strefy 5–8), PL-1992, stopnie WGS84 albo Web Mercator. Rozpoznaje też zamienione osie X i Y oraz współrzędne lokalne rysunku (blisko punktu 0,0). Sprawdzenie odbywa się po dodaniu pliku, przy otwarciu projektu i na żądanie: **Narzędzia → „Układy warstw — sprawdź”**.

- Gdy zapisany układ nie pasuje do liczb, pojawia się okno z wyborem: **„W locie”** (warstwa dostaje właściwy układ, plik się nie zmienia), **„Konwertuj do bazy projektu”** (obiekty przeliczone do układu projektu trafiają do bazy projektu, a przedtem powstaje kopia bazy) albo **„Pomiń”**. Przy zamienionych osiach pomaga tylko konwersja.
- Rysunek CAD zachowuje po konwersji swoje kolory i grubości linii.
- Rysunek DXF bez zapisanego układu, którego liczby pasują do układu projektu, dostaje ten układ sam, bez pytania.
- Obiekty leżące przy punkcie 0,0, częste w rysunkach CAD, nie rozciągają już widoku. Po wczytaniu rysunku mapa pokazuje jego właściwą część, a aplikacja mówi, ile obiektów leży poza obszarem układu.

## Podkład OpenStreetMap

- Każdy projekt ma wektorowy podkład OpenStreetMap na dole listy warstw. Ortofotomapa Esri jest w projekcie, ale zgaszona; włącza się ją na liście warstw.
- Naprawiono zamykanie się aplikacji przy otwieraniu projektu z rysunkiem DXF.
- „Powiększ do całości” pomija podkłady i pokazuje dane.

## Projekt

- Nowy pusty projekt zawsze ma układ współrzędnych (domyślnie PL-2000 strefa 7).
- Okno naprawy projektu proponuje „Ustaw EPSG:…” dla projektu bez układu i przelicza warstwę zapisaną w stopniach.
- Przy otwarciu projektu brakujące identyfikatory obiektów i wyposażenie uzupełniają się same; w projekcie z danymi aplikacja najpierw pyta. Wyłącznik: Ustawienia → Teren.
- „Zapisz jako” zapisuje kopię z obiektami i zdjęciami albo pusty wzór projektu.
- Kreator „Projekt z rysunku CAD” mówi wprost, że projekt o podanej nazwie już istnieje.
- Z katalogu wyposażenia usunięto moduły przyciągania.

## Pasek szybkiego zapisu

- Nowe okno opcji paska, dostępne także z karty w Narzędziach.
- Kafle mieszczą się na ekranie.

## Szybszy start

Część okien powstaje dopiero przy pierwszym użyciu, więc aplikacja startuje szybciej. Czas startu zapisuje się w dzienniku komunikatów.

---
APK: arm64-v8a · versionCode 1415 · md5 `40ee297ed31136ad13df0a371be635c7`
