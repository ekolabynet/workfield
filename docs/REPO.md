# Organizacja repozytorium WorkField

Decyzja z 22.08.2026. Ten plik jest źródłem prawdy o liniach (gałęziach),
adresach i rytuałach aktualizacji. Zmiana tych zasad = zmiana tego pliku.

## Linie

| Linia | Rola | Kiedy się zmienia |
|---|---|---|
| `master` | stabilna, wizytówkowa | WYŁĄCZNIE przy bumpie wersji (fast-forward z development + tag) |
| `development` | praca codzienna | po każdej działającej zmianie (`add / commit / push`) |
| `plugins` | dystrybucja wtyczek — zipy w korzeniu gałęzi | przy publikacji wtyczki (`skrypty/publikuj.sh`) |
| `addins` | materiały dodatkowe (tabele danych itp.) | przy publikacji materiału (`skrypty/publikuj.sh`) |

Linie `plugins` i `addins` są budowane automatycznie z katalogów `plugins/`
i `addins/` na development — nie edytuje się ich ręcznie i nie robi na nich
checkout do pracy.

## Adresy (stałe, do QR-ów i instrukcji)

- wtyczka: `https://raw.githubusercontent.com/ekolabynet/workfield/plugins/<nazwa>.zip`
- materiał: `https://raw.githubusercontent.com/ekolabynet/workfield/addins/<nazwa>`
- kod czytany przez agentów AI: `https://raw.githubusercontent.com/ekolabynet/workfield/development/<ścieżka>`

Nazwa pliku wtyczki/materiału ZAWSZE niesie wersję (`workfield-plantnet-v0.11.zip`).
Nigdy nie nadpisujemy pliku pod tą samą nazwą — raw.githubusercontent cache'uje
kilka minut i nadpisanie grozi wciągnięciem starej wersji na telefon.

## Rytuały

### Codzienny (development)

Początek sesji z kodem: `git status`, `git log --oneline -3`, `git push`.
Po każdej działającej zmianie: `git add -A && git commit -m "opis" && git push`.
Eksperymenty w toku: prefiks `WIP:`.

### Bump wersji (przenosi master)

    git checkout master
    git merge --ff-only development
    git tag -a vX.Y.Z -m "Nazwa kodowa"      # nazwy wg docs/WYDANIA.md
    git push && git push origin vX.Y.Z
    git checkout development

Tag powstaje ZAWSZE razem z bumpem — wydanie bez taga to wydanie widmo
(lekcja v0.9.3, otagowanego wstecznie).

### Publikacja wtyczki lub materiału

1. Plik (zip z wersją w nazwie) do katalogu `plugins/` albo `addins/`
   na development; `git add / commit / push` jak zwykle.
2. `bash skrypty/publikuj.sh` — odświeża linie dystrybucyjne z zawartości
   katalogów i wypycha je. Skrypt jest idempotentny (bez zmian = nic nie robi).
3. Nowy QR koduje adres z linii `plugins`/`addins` (patrz Adresy).

## Zasady zawartości

- `addins` (i całe publiczne repo): wyłącznie treści z licencją pozwalającą
  na redystrybucję (CC BY itp.), z atrybucją w NOTICE.md. Dane bez takiej
  licencji (np. pełny `wf_wskazniki.gpkg` z wartościami Zarzyckiego
  i fitosocjologią) podróżują kanałem prywatnym (NextCloud), nigdy repo.
- Dane terenowe (GPKG z pomiarami, DCIM), sekrety, keystore — nigdy do repo
  (patrz MasterScript). Kopie zapasowe łatek `*.przed_*` nie są wersjonowane.

## Stan przejściowy

Gałąź `wyposazenie` to zabytek po dawnej strukturze — zostaje do ok.
29.08.2026 (krążące kody QR z jej adresem), potem:

    git push origin --delete wyposazenie
    git branch -d wyposazenie
