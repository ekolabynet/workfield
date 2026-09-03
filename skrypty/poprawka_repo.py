#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dopisuje do docs/REPO.md sprawdzenie galezi na wejsciu.

POWOD (22.08.2026): przez caly dzien agent dawal `git push` bez sprawdzania,
na ktorej galezi stoi. MasterScript mowil `master`, praca szla na
`wyposazenie`, a NOTICE.md wyladowal na `development` — nikt tego nie
zauwazyl, dopoki Piotr nie zapytal. Skonczylo sie dobrze tylko dlatego,
ze galezie i tak byly spojne.

Rytual bez pierwszej linijki nie odpowiada na pytanie "gdzie ja jestem",
a to jedyne pytanie, ktore przy czterech liniach naprawde ma znaczenie.
"""
import sys

P = "docs/REPO.md"
t = open(P, encoding="utf-8").read()

STARE = ("Początek sesji z kodem: `git status`, `git log --oneline -3`, `git push`.\n"
         "Po każdej działającej zmianie: `git add -A && git commit -m \"opis\" && git push`.\n"
         "Eksperymenty w toku: prefiks `WIP:`.\n")

NOWE = """Początek sesji z kodem — **najpierw gałąź, potem reszta**:

    git branch --show-current          # ma być: development
    git status --short | grep -v przed_
    git log --oneline -3
    git push

Pierwsza linijka nie jest formalnością. 22.08.2026 przez cały dzień szły
commity bez sprawdzenia, gdzie stoimy: MasterScript mówił `master`, praca
szła na `wyposazenie`, deklaracja w NOTICE.md wylądowała na `development`.
Skończyło się dobrze wyłącznie dlatego, że linie i tak były spójne.
**Pilnowanie gałęzi należy do agenta, nie do prowadzącego.**

Po każdej działającej zmianie: `git add -A && git commit -m "opis" && git push`.

`git add -A` bierze **wszystko, co leży w drzewie**. Przy pracy równoległej
(np. gdy prowadzący pisze coś obok) trzeba wymienić pliki jawnie:
`git add <plik>`. 21.08 commit „moduł bez_nakladania" zabrał ze sobą 139
linii pracy nad `PhotoTagStore`, których nazwa commita nie opisuje — i przez
to nikt ich później nie znajdzie po opisie.

Eksperymenty w toku: prefiks `WIP:`.
"""

if "najpierw gałąź" in t:
    sys.exit("juz jest")
if t.count(STARE) != 1:
    sys.exit("STOP: kotwica %d razy" % t.count(STARE))

open(P, "w", encoding="utf-8").write(t.replace(STARE, NOWE, 1))
print("dopisane do", P)
