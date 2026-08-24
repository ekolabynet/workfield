#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Zapisanie zgody Marka Snowarskiego (atlas-roslin.pl) w NOTICE.md i docs/REPO.md.

==========================================================================
DLACZEGO TO MUSI BYC W REPO, A NIE W SKRZYNCE
==========================================================================
Zgoda przyszla mailem 23.08.2026. Mail w skrzynce nie chroni przed niczym:
nie widzi go nikt, kto siegnie po repozytorium, nie przetrwa zmiany komputera
i nie odpowie na pytanie recenzenta ani wspolpracownika za rok.

Do repo trafia ZAKRES i WARUNEK. Sam PDF z korespondencja idzie kanalem
prywatnym (NextCloud) — zawiera adresy i tresc korespondencji.

==========================================================================
CO DOKLADNIE OBEJMUJE ZGODA
==========================================================================
Odpowiedz brzmi: "Mozna wykorzystac dane o ktorych Pan pisze w apce
WorkField, w sposob ktory Pan opisal."

**Zakresem zgody jest wiec TRESC PROSBY.** Stad musi byc ona zapisana
doslownie, nie streszczona — inaczej za rok nikt nie odtworzy, na co
zgoda opiewa.

Z prosby z 22.08.2026:

  CO:      dane o klasyfikacji gatunkowej i syntaksonomicznej, swobodnie
           dostepne bez zalogowania — indeksy nazw lacinskich i polskich,
           gatunki charakterystyczne, hierarchia jednostek
  DO CZEGO: informacja o gatunkach znalezionych w terenie, liczenie srednich
           wartosci wskaznikow siedliskowych, wartosci usrednione w placie
  GDZIE:   WorkField — aplikacja publiczna, GPLv2 (adres repozytorium byl
           w prosbie, wiec publiczny charakter byl jawny)
  WARUNEK: **link do strony Atlasu w KAZDYM oknie wykorzystujacym te dane**
  POZA:    materialy wizualne i inne objete explicite ochrona praw autorskich

==========================================================================
CZEGO ZGODA NIE OBEJMUJE — i to trzeba trzymac osobno
==========================================================================
**Wartosci Zarzyckiego.** Atlas ich nie udostepnia; pochodza z osobnego
opracowania i sa u nas z wlasnej digitalizacji. Jedna zgoda nie przykrywa
drugiego zrodla — w NOTICE.md musza stac osobno, inaczej wyglada to na
parasol na wszystko.

**Zdjecia i grafiki.** Wylaczone przez sama prosbe.

**Czesc platna Atlasu.** Zgoda dotyczy tego, co dostepne bez logowania.

Uruchom w korzeniu repo:  python3 zastosuj_zgode_atlas.py
Idempotentna. Kopie: NOTICE.md.przed_zgoda, docs/REPO.md.przed_zgoda
"""
import os
import shutil
import sys

MARKER = "atlas-roslin.pl"

# ------------------------------------------------------------------ NOTICE.md

N_KOTWICA = """- **Own work** — the trait matrix, abbreviations, Polish name corrections and
  the mapping of statutory Polish names to scientific names"""

N_NOWE = """- **Atlas roślin Polski / atlas-roslin.pl** (Marek Snowarski) — used **with
  the author's written permission**, granted by e-mail on 23 August 2026.
  Scope and conditions are described below.
- **Own work** — the trait matrix, abbreviations, Polish name corrections and
  the mapping of statutory Polish names to scientific names"""

N_KOTWICA2 = """Deliberately not redistributed here: IUCN Red List data (redistribution and
commercial use are prohibited by its terms), and any CC BY-NC source, which is
incompatible with GPL. Full breakdown: `taxonomy/docs/LICENCJE_audyt.md`."""

N_NOWE2 = """Deliberately not redistributed here: IUCN Red List data (redistribution and
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
repository."""

# ------------------------------------------------------------------- REPO.md

R_KOTWICA = """  (NextCloud) podróżują warstwy z klauzulą **NC** (FungalRoot, KSIB, TRY)
  i treści zastrzeżone (fitosocjologia z atlas-roslin.pl) — NC jest
  sprzeczne z GPL."""

R_NOWE = """  (NextCloud) podróżują warstwy z klauzulą **NC** (FungalRoot, KSIB, TRY)
  — NC jest sprzeczne z GPL."""

# Osobny punkt o zgodzie, dopisany po calym akapicie o kanale prywatnym.
R_KOTWICA2 = """  Kanał prywatny chodzi przez konta serwisowe NextClouda: `wf_desktop`
  publikuje bibliotekę (maska 5 — bez nadpisywania), telefony czytają ją
  z prawem odczytu i piszą wyłącznie do własnych katalogów zwrotów."""

R_NOWE2 = R_KOTWICA2 + """
- **atlas-roslin.pl — mamy pisemną zgodę autora.** Marek Snowarski,
  23.08.2026: dane o klasyfikacji gatunkowej i syntaksonomicznej z części
  dostępnej **bez logowania** (indeksy nazw, gatunki charakterystyczne
  i wyróżniające, hierarchia jednostek) mogą jechać z aplikacją. Fitosocjologia
  z Atlasu przestaje więc być treścią zastrzeżoną i **nie musi już podróżować
  kanałem prywatnym**.

  **Warunek jest wiążący: link do strony Atlasu w KAŻDYM oknie**, które te
  dane pokazuje. To nie ozdoba — to jest cena zgody. Nowy ekran bez linku
  łamie ją, więc przy dokładaniu ekranu sprawdzić link tak samo, jak sprawdza
  się wpis w `CMakeLists.txt` przy nowym pliku QML. Najbezpieczniej wstawiać
  go **z jednego miejsca**, nie powtarzać w każdym ekranie.

  Zgoda **nie** obejmuje zdjęć ani części płatnej. Zakres i pełne brzmienie:
  `NOTICE.md`, sekcja „Atlas roślin Polski". Korespondencja — kanał prywatny,
  nigdy repo (zawiera adresy)."""


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def raz(t, kotwica, p):
    n = t.count(kotwica)
    if n != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1:\n  %s"
                 % (p, n, kotwica.strip().splitlines()[0][:60]))


def zapisz(p, t):
    kopia = p + ".przed_zgoda"
    if not os.path.exists(kopia):
        shutil.copy2(p, kopia)
    open(p, "w", encoding="utf-8").write(t)
    print("  zapisano %s (kopia: %s)" % (p, os.path.basename(kopia)))


def main():
    n = czytaj("NOTICE.md")
    r = czytaj("docs/REPO.md")

    # W REPO.md atlas juz byl wymieniony jako tresc ZASTRZEZONA — znacznikiem
    # wykonania jest wiec wzmianka o zgodzie, nie sama nazwa serwisu.
    zrobione = [MARKER in n, "pisemną zgodę autora" in r]
    if all(zrobione):
        print("Wpisy juz sa — nic do zrobienia.")
        return
    if any(zrobione):
        sys.exit("STOP: wpis polowiczny %s. Przywroc kopie .przed_zgoda." % zrobione)

    raz(n, N_KOTWICA, "NOTICE.md")
    raz(n, N_KOTWICA2, "NOTICE.md")
    raz(r, R_KOTWICA, "docs/REPO.md")
    raz(r, R_KOTWICA2, "docs/REPO.md")

    print("Kotwice policzone (4/4), nakladam:")

    n = n.replace(N_KOTWICA, N_NOWE, 1)
    n = n.replace(N_KOTWICA2, N_NOWE2, 1)
    zapisz("NOTICE.md", n)

    r = r.replace(R_KOTWICA, R_NOWE, 1)
    r = r.replace(R_KOTWICA2, R_NOWE2, 1)
    zapisz("docs/REPO.md", r)

    print("""
DO ZROBIENIA POZA REPO:

  1. PDF z korespondencja -> kanal prywatny (NextCloud), z data w nazwie:
       Atlas-roslin_zgoda_2026-08-23_M_Snowarski.pdf
     NIE do repo: zawiera adresy i tresc korespondencji.

  2. Sprawdzic, ktore ekrany JUZ pokazuja te dane i czy maja link:
       grep -rn "atlas-roslin" src/ --include=*.qml --include=*.cpp

     Wiadomo, ze link jest w oknie Pl@ntNet (byl w prosbie jako fakt
     dokonany). Karta gatunku, profile siedliskowe i wzorce syntaksonow —
     do sprawdzenia.

  3. Rozwazyc, czy linku nie wstawiac Z JEDNEGO MIEJSCA (komponent QML albo
     czasownik zwracajacy adres), zamiast powtarzac go w kazdym ekranie.
     Warunek zgody jest wtedy trudniejszy do zlamania przez zapomnienie.
""")


if __name__ == "__main__":
    main()
