# gugik v0.3

_2026-09-17 11:58_

Instalacja: **Ustawienia → Wtyczki → Install plugin from URL**

```
https://raw.githubusercontent.com/ekolabynet/workfield/plugins/workfield-gugik-v0.3.zip
```

## Co się zmieniło

- Wtyczka workfield-gugik v0.2: diagnostyka na stdout + test polaczenia
- Wtyczka workfield-gugik v0.1: dzialki z ULDK na tapniecie
- Wtyczka workfield-gugik v0.1: dzialki z ULDK na tapniecie
- GUGiK DEM download: NMT/NMPT sheets for map extent via skorowidz GetFeatureInfo, turbo pseudocolor rendering (#GUGiK slice 4)
- WFS layers: GUGiK and Warsaw presets, bbox-restricted download

## Do sprawdzenia po instalacji

- **Zrestartuj aplikację.** Sama instalacja z URL podmienia plik, ale QField
  trzyma stary kod w pamięci do końca sesji.
- **Wyczyść pole „plik GPKG" w ustawieniach wtyczki.** `Settings` przeżywa
  aktualizację: wartość `gugik.gpkg` zapamiętana przez v0.2 nadpisuje nową
  wartość domyślną z kodu. Puste pole znaczy „baza projektu".
- **Usuń starą warstwę `REF_dzialki` z projektu**, jeśli wskazuje na
  nieistniejący `gugik.gpkg`. Zostaje w `projekt.qgs` w trzech miejscach:
  blok `<maplayer>`, wpis w drzewie warstw i ustawienie przyciągania —
  a przy każdym otwarciu projektu wywołuje ekran o brakujących źródłach.
