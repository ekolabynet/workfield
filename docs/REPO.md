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

Początek sesji z kodem — **najpierw gałąź, potem reszta**:

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
  na redystrybucję (CC BY itp.), z atrybucją w NOTICE.md. Kanałem prywatnym
  (NextCloud) podróżują warstwy z klauzulą **NC** (FungalRoot, KSIB, TRY)
  — NC jest sprzeczne z GPL. Liczby Zarzyckiego zostają publicznie: ochrona sui
  generis wydania z 2002 wygasła z końcem 2017 (art. 10 ust. 2 ustawy
  o ochronie baz danych). Rozbiór: `taxonomy/docs/LICENCJE_audyt.md`.
  Kanał prywatny chodzi przez konta serwisowe NextClouda: `wf_desktop`
  publikuje bibliotekę (maska 5 — bez nadpisywania), telefony czytają ją
  z prawem odczytu i piszą wyłącznie do własnych katalogów zwrotów.
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
  nigdy repo (zawiera adresy).
  Opis: `docs/KANAL_NC.md`, wysyłka: `skrypty/wyslij_do_nc.sh`.
- `taxonomy/` — nazwy gatunków i przypisane im prawo: warstwy prawne jako
  CSV, skrypty budujące słownik `TAKSONY`, rejestr `taxonomy/WERSJE.md`.
  Dane jako CSV (źródło prawdy), GPKG tylko jako wydruk przy wydaniu.
  Wejście: `taxonomy/README.md`.
- Dane terenowe (GPKG z pomiarami, DCIM), sekrety, keystore — nigdy do repo
  (patrz MasterScript). Kopie zapasowe łatek `*.przed_*` nie są wersjonowane.

## Stan przejściowy

Gałąź `wyposazenie` to zabytek po dawnej strukturze — zostaje do ok.
29.08.2026 (krążące kody QR z jej adresem), potem:

    git push origin --delete wyposazenie
    git branch -d wyposazenie
