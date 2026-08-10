
## Model wersjonowania (decyzja 2026-08-10)

- `master` jest jedyną linią rozwojową — obecnie linia 0.9.
- Wydania na telefon powstają WYŁĄCZNIE z otagowanych commitów
  (`vX.Y.Z`), po teście dymnym na urządzeniu.
- Każdy zainstalowany APK ma kopię w `~/WorkField/aplikacja/`
  jako `workfield-vX.Y.Z.apk` — powrót do poprzedniej wersji to
  `adb install -r` starego pliku, bez dotykania repozytorium.
- Gałąź stabilizacyjną (`stab/0.8` itd.) powołujemy z taga dopiero
  przy pierwszej realnej potrzebie łatki starej linii — nie „na zapas".
