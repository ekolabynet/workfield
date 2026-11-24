# WorkFieldGIS 0.14.13 „Fractal Fir”

Wydanie z 24.11.2026 — zmiany od 0.14.12.

## Szybsze menu w dużych projektach

Przy każdym otwarciu menu aplikacja sprawdza projekt: czy w danych nie ma obiektów o pustym albo zwiniętym kształcie. Dotąd przeglądała przy tym **wszystkie** warstwy poligonowe projektu — także wyniki analiz z biura (korony, klasy wysokości, budynki 3D) i podkłady, w których w terenie nic nie powstaje. Na starszych telefonach mogło to zatrzymywać ekran przy każdym otwarciu menu.

Teraz sprawdzane są tylko warstwy z pliku danych projektu (`dane.gpkg`) i tylko ich kształty. Na laptopie, w projekcie z 29 tys. obiektów, sprawdzenie skróciło się ze 127 ms do 3 ms; w projekcie ze 142 warstwami poligonowymi sprawdzane są 4, z danymi terenowymi.

Ostrzeżenia o pustych i zwiniętych kształtach dotyczą teraz danych terenowych. Próg przyciągania jest porównywany z najmniejszym obiektem w tych danych.

## Pomiar w dzienniku komunikatów

Po każdym sprawdzeniu projektu w dzienniku komunikatów pojawia się linijka `WorkField [WF-PERF]` z czasem sprawdzenia i liczbą przejrzanych obiektów (od 300 ms jako ostrzeżenie). **Jeśli aplikacja wydaje się wolna — prześlij tę linijkę razem z modelem telefonu.**

---
APK: arm64-v8a · versionCode 1413 · md5 `510d722d338d15205ca57c258845c392`
