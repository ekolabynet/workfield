# NOTICE

## About this repository

**WorkField** is an independent derivative work (fork) of
[**QField**](https://github.com/opengisch/QField), the mobile GIS application
developed by [OPENGIS.ch](https://www.opengis.ch/) and its community.

WorkField is **not created, endorsed, supported, or maintained by the QField
project or OPENGIS.ch**. For the official application, please use the
**Official Packages** available at [qfield.org](https://qfield.org/) and in
the app stores — they are professionally maintained, widely tested, and
regularly updated. If QField meets your needs, use QField.

## Why this fork exists

WorkField adapts QField to a specific niche: **field vegetation inventory and
surveying workflows in Poland**, including presets for Polish national
geoportal services (GUGiK WMS/WMTS) and a capture-focused interface designed
for one-handed, gloved outdoor use. These are deliberate, opinionated choices
for a narrow use case — not improvements to QField, which serves a much
broader audience with different priorities.

## Main differences from upstream QField

- **Camera**: built-in camera with shot presets (lens selection + zoom),
  continuous shooting series with no lost frames, Android orientation
  correction for preview and saved files, flash and haptic feedback in fast
  capture mode, relative photo paths.
- **Capture workflow**: quick capture bar, fast mode taking positions
  directly from the GNSS source, series counter, project variables
  (`obiekt_*`), buffered raster value sampling.
- **Interface**: Material 3 based theme, status bar with GNSS coordinates and
  quality class (FIX/FLOAT/GPS), layout tuned for large touch targets.
- **Basemaps**: WMS/WMTS presets for Polish national services (GUGiK).
- **Branding**: distinct name, icon, and splash screen to avoid any confusion
  with official QField packages.
- Assorted fixes for issues encountered in this configuration (storage
  directory handling, duplicate feature creation on commit, location marker
  compass cone scaling).

For the exact and current delta, compare this repository against
[opengisch/QField](https://github.com/opengisch/QField) — the full history is
preserved and the fork is periodically synchronized with upstream. Fixes that
are not specific to WorkField are offered back to the QField project.

## License

Like QField, WorkField is licensed under the
**GNU General Public License, version 2 or later (GPL-2.0-or-later)** —
see [`LICENSE`](LICENSE). Original copyright remains with OPENGIS.ch and the
QField contributors; WorkField-specific changes are © their respective
authors, under the same license.

## Support and issues

Please report problems with WorkField **in this repository only** — never to
the QField project, whose maintainers are not responsible for anything that
happens here. Conversely, this fork cannot help with issues in official
QField packages.

## Acknowledgements

WorkField exists only because OPENGIS.ch and the QField community build and
share an excellent open-source field GIS — and because the QGIS project
underneath it makes all of this possible. Thank you.

---

## Nota po polsku

**WorkField** to niezależna pochodna (fork) aplikacji **QField** firmy
OPENGIS.ch, dostosowana do terenowej inwentaryzacji zieleni i pomiarów w
Polsce (presety usług GUGiK, interfejs pod pracę w rękawicach). WorkField
**nie jest tworzony ani autoryzowany przez projekt QField** — oficjalną
aplikację znajdziesz na [qfield.org](https://qfield.org/). Licencja:
GPL-2.0-or-later. Błędy WorkField zgłaszaj wyłącznie w tym repozytorium.
