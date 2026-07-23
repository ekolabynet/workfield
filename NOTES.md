
## Konfiguracja buildu
cmake -S . -B build-sys -Wno-dev
-DAPP_NAME=WorkFieldGIS
-DAPP_THEME_PATH=$HOME/qfield-theme/material3.json
-DAPP_ICON_PATH=$HOME/workfield-brand
-DAPP_ICON=workfieldgis
Zasoby marki poza repo: `~/qfield-theme/`, `~/workfield-brand/`.
