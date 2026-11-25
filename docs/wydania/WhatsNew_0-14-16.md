# WorkFieldGIS 0.14.16 „Fractal Fir”

Wydanie z 25.11.2026 — poprawka do 0.14.15.

## Pliki z pamięci telefonu

- Pliki GPKG, GeoJSON i inne dane wybrane w oknie systemowym Androida („Pamięć telefonu…”) dają się dodać do projektu. Dotąd aplikacja dostawała od systemu odnośnik zamiast ścieżki i nie umiała pliku otworzyć.
- Taki plik jest najpierw kopiowany do folderu aplikacji „Imported Datasets” (w oknie „Pliki”: Dane), a dalej aplikacja pracuje na kopii. Oryginał zostaje tam, gdzie był.
- To samo dotyczy zakresu inwentaryzacji wskazanego plikiem, georeferencji i importu rysunku DXF.
- Pliki SHP z okna systemowego nadal nie zadziałają: system oddaje sam plik .shp, bez plików towarzyszących. Skopiuj komplet do folderu projektu i wskaż go stamtąd.

---
APK: arm64-v8a · versionCode 1416 · md5 `d05c2eaefd998491bc51ae5cb1eaa21d`
