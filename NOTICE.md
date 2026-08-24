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

## AI-assisted development

Most of the code in this fork is written with the help of AI assistants
(Anthropic's Claude), working from field requirements described by the
maintainer. This is stated openly because the repository is public and
because parts of this work are intended as upstream contributions.

What this means in practice:

- **Responsibility is human.** Design decisions, data-model choices and
  acceptance are made by the maintainer. Every change is applied, built and
  tested on real devices in real fieldwork before it is kept.
- **Changes are applied as scripted patches**, not pasted by hand. Each patch
  counts its anchors and refuses to write when the surrounding code differs
  from what it expects, so a change either lands exactly where intended or
  not at all.
- **Verification is documented.** `docs/KOMITET.md` describes the working
  process: what has to be read in the source before anything is written,
  what has to be checked against the data before a change is accepted, and
  which steps cannot be skipped. It exists because skipping them has cost
  real field days.
- **Mistakes are recorded, not hidden.** The same document lists failures
  that reached the field, with their causes.

Contributions offered upstream are, and will be, plain patches judged on
their merits — small, reviewable and accompanied by the reasoning behind
them.

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
- **Config editor**: in-app text editor for project configuration
  files (live JSON validation with error location, format-aware field
  hints, automatic safety backups) — so that non-programmers can make
  safe config changes in the field.
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

## Reference data / Dane referencyjne

WorkField templates may bundle species reference tables derived from
open datasets (all CC-BY 4.0, see ATRYBUCJE_DANYCH.txt next to each
template): Ellenberg-type indicator values (Tichy et al. 2023,
doi:10.5281/zenodo.7427088), disturbance indicator values (Midolo et
al. 2023, doi:10.5281/zenodo.7116957) and the GBIF Backbone Taxonomy
(doi:10.15468/39omei). Original data remain under their licenses.

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


### Praca z asystentami AI

Większość kodu w tym forku powstaje z pomocą asystentów AI (Claude firmy
Anthropic), na podstawie wymagań zebranych w terenie. Piszemy to wprost,
bo repozytorium jest publiczne, a część zmian ma trafić do QFielda.

Odpowiedzialność jest ludzka: decyzje projektowe, wybór modelu danych
i przyjęcie zmiany należą do prowadzącego. Każda zmiana jest budowana
i sprawdzana na sprzęcie, w prawdziwej pracy terenowej.

Zmiany nakładane są skryptami z kotwicami, które **odmawiają zapisu**,
gdy kod wokół różni się od oczekiwanego — łatka albo trafia dokładnie tam,
gdzie miała, albo nie wchodzi wcale. Tryb pracy, wymagane sprawdzenia
i kroki, których nie wolno pominąć, opisuje `docs/KOMITET.md`. Ten dokument
powstał dlatego, że pomijanie ich kosztowało realne dni w terenie —
i wymienia też błędy, które do terenu dotarły.

## Ikony Breeze

Katalog `images/themes/workfield/` (oraz źródłowo `brand/ikony/`) zawiera
ikony pochodzące z motywu Breeze projektu KDE
(https://invent.kde.org/frameworks/breeze-icons), rozpowszechniane na
licencji LGPL-3.0-or-later. Zmieniono wyłącznie nazwy plików (przedrostek
`wfg_`); zawartość grafik bez zmian. Pełna nota: `brand/ikony/LICENCJA_IKON.txt`.

## Data sources

Species dictionaries and the legal layers attached to them live in
`taxonomy/`. Data files are kept as CSV (the source of truth); GeoPackage
files are build outputs, produced at release time.

- **WFO Plant List** (World Flora Online) — CC0
- **Catalogue of Life / COL XR** — CC BY 4.0, cite the release DOI
- **GBIF** name matching and backbone data — CC BY 4.0
- **Wikidata** — CC0 (Polish vernacular names)
- **Polish legal acts** (Dz.U.) — not subject to copyright under art. 4 of the
  Polish Copyright Act; thresholds, fee groups, protected and invasive species
- **Atlas roślin Polski / atlas-roslin.pl** (Marek Snowarski) — used **with
  the author's written permission**, granted by e-mail on 23 August 2026.
  Scope and conditions are described below.
- **Own work** — the trait matrix, abbreviations, Polish name corrections and
  the mapping of statutory Polish names to scientific names

Deliberately not redistributed here: IUCN Red List data (redistribution and
commercial use are prohibited by its terms), and any CC BY-NC source, which is
incompatible with GPL. Full breakdown: `taxonomy/docs/LICENCJE_audyt.md`.

### Atlas roślin Polski (atlas-roslin.pl) — permission and its conditions

Marek Snowarski, the author of *Atlas roślin Polski* (atlas-roslin.pl, ©
2002–2026), gave written permission on **23 August 2026** for WorkField to use
classification data from the freely accessible part of the atlas.

**Scope**, as stated in the request the permission refers to:

- indexes of scientific and Polish plant names,
- characteristic and differential species of syntaxa (`Ch`/`D`, with rank),
- the hierarchy of syntaxonomic units,
- used to inform about species recorded in the field, and to compute mean
  habitat indicator values for a species record and averages within a plot.

**Condition, and it is binding:** every screen that presents these data
carries a **link to the corresponding page of the atlas**. This is not a
courtesy — it is the term on which the permission was given. Any new screen
using this data must carry the link as well.

**Not covered:** photographs and other material explicitly under copyright,
and the paid part of the atlas. Indicator values after Zarzycki come from a
different source and are listed separately above — this permission does not
extend to them.

The permission concerns redistribution within WorkField, which is a public
GPLv2 application; the repository address was part of the request, so its
public nature was explicit. Correspondence is archived outside this
repository.
