# Wersjonowanie formatu projektu WorkField — umowa

Jedna strona prawdy o tym, co znaczy numer standardu, kiedy się go podbija
i czego nie wolno zmienić po cichu. Siostra `docs/WYPOSAZENIE.md`.

**Ta strona jest wiążąca dla każdego, kto dokłada funkcje do WorkField —
człowieka i asystenta.** Jeśli zmiana dotyka tego, co siedzi w projekcie
albo obok niego, odpowiedź „czy podbijam numer i który" jest tutaj.

## Trzy poziomy wersji — nie mylić ich

| Co | Gdzie mieszka | Po co |
|---|---|---|
| **wersja modułu** | `wyposazenie/moduly/<id>/modul.json` | drobiazgi wewnątrz jednej funkcji |
| **standard projektu** | `wyposazenie/standardy.json` | jedna liczba do powiedzenia na głos |
| **wersja aplikacji** | tag `vX.Y.Z` + versionCode | co potrafi APK w telefonie |

## Standard projektu: `major.minor`

Numer **nie mierzy rozmiaru zmiany. Mierzy zgodność z aplikacją.**
To jedyne rozróżnienie, które odpowiada na pytanie zadawane w terenie:
*czy otworzę ten projekt tym, co mam w telefonie?*

**MINOR — dołożone; starsza aplikacja to zniesie.**
Nowy moduł, nowe ustawienie projektu, dodatkowa warstwa, nowe pole, nowy
alias, nowy kafel paska. Starsze APK otwiera projekt normalnie, po prostu
nie korzysta z nowości. `0.1 → 0.2`

**MAJOR — zmienione; starsza aplikacja tego nie udźwignie.**
Zmiana schematu istniejącej tabeli, przemianowane albo usunięte pole, inny
klucz relacji, przebudowany układ formularza, zmieniona konwencja nazw
plików załączników, zmieniony układ katalogów projektu. Starsze APK pokaże
śmieci albo się wywróci. `0.9 → 1.0`

Test rozstrzygający, do zadania sobie przed podbiciem:
**czy APK sprzed zmiany otworzy ten projekt i nie zrobi krzywdy danym?**
Tak → minor. Nie albo „nie wiem" → major.

`major 0` znaczy: nic nie jest jeszcze zagwarantowane. Pierwsza jedynka
będzie obietnicą — od niej starsze aplikacje mają być bezpieczne.

## Numer jest WYLICZANY, nie zapisywany

Projekt jest w **najwyższym standardzie, którego pełny zestaw modułów
spełnia**: każdy moduł ma stan zgodny (kroki przechodzą), a stempel — o ile
zna ten moduł — nie niższą wersję niż wymagana. Moduł bez zastosowania
(`dotyczy`) nie blokuje standardu.

Nie ma wiersza „standard = 0.1" w stemplu i nie ma go być. Zapisany numer
mógłby skłamać: ktoś zdejmuje moduł, a liczba zostaje. Wyliczony spada sam,
w tej samej sekundzie, bez niczyjego udziału. To ta sama zasada, co przy
stemplu: **opisujemy stan, nie zamiar.**

Sprawdzone: zdjęcie `bez_nakladania` z projektu w standardzie 0.1
natychmiast zbija go do „nie sięga 0.1".

## `wymaga_aplikacji`

Każdy standard niesie minimalny versionCode aplikacji, która go obsłuży.

Prawdziwe zagrożenie to **nie stary projekt, tylko projekt nowszy niż
aplikacja**: zadanie zbudowane w biurze ze świeżego przepisu, wysłane na
telefon ze starszym APK. Bez tego pola nic o tym nie powie, a dowiesz się
w terenie.

Kontrola przed wyjazdem porównuje **trzy** rzeczy: standard projektu,
standard katalogu i wersję aplikacji, która ma go otworzyć.

## Kiedy podbijać, a kiedy nie

**Podbij standard**, gdy w projekcie pojawia się coś, o czym warto powiedzieć
komuś, kto z niego korzysta.

**Nie podbijaj**, gdy poprawiasz drobiazg wewnątrz istniejącej funkcji —
alias, literówkę w opisie, kolor kafla, domyślną wartość. To jest wersja
modułu, nie standardu.

**Numer jest wart tyle, ile rzadkość jego zmian.** Standard podbijany co
tydzień przestaje być punktem odniesienia i wraca bałagan, tylko z liczbami.
Kilka razy w sezonie, nie kilka razy w tygodniu.

## Czego NIE WOLNO zmieniać po cichu

Poniższe siedzi w danych albo w konwencji i **każda zmiana to major**,
nawet gdy w kodzie wygląda na jedną linijkę:

1. **Schemat tabel `ZAL_`** — źródło prawdy: `skrypty/zaloz_zalaczniki.py`,
   stała `POLA_ZALACZNIKA`. `ID_RODZICA` INTEGER, reszta TEXT. Żadne pole
   nie może dostać NOT NULL. Rozjazd typu `UJECIE` kosztował 17.08 jeden
   obieg: pasek wpisuje tam nazwę presetu, a przepis mówił `integer`.
2. **Klucz relacji załączników** — `ID_RODZICA` → `fid`, siła kompozycja.
3. **Konwencja nazw plików załączników** —
   `DCIM/<warstwa>_<klucz>/<warstwa>_<klucz>_RRRRMMDD_GGMMSS_mmm.jpg`.
4. **Klucze w `workfield_klawisze.json`** — `etykieta`, `warstwa`, `kolor`,
   `zdjecie`. Klucz `nazwa` zamiast `etykieta` daje pusty pasek.
5. **Konwencja nazw katalogów zlecenia** — `zleceniodawca_obiekt_id_rodzaj_wersja`.
6. **Układ katalogów projektu** — dopóki nie ma `zrzucPrzepis()`, przeniesienie
   GPKG do podkatalogu zostawia stare projekty w starym układzie na zawsze.
7. **Tabela `WF_WYPOSAZENIE`** — kolumny `modul, wersja, data, zrodlo, przez`;
   nie rejestrowana w `gpkg_contents`.

## Przy każdej zmianie standardu

1. Nowy wpis w `wyposazenie/standardy.json` z `opis` napisanym dla człowieka
   — to on odpowiada na pytanie „co się zmienia", zanim ktoś naciśnie
   „Podnieś do standardu".
2. `wymaga_aplikacji` ustawione na versionCode wydania, które to obsługuje.
3. Wpis w `NOTICE.md`, jeśli zmiana dotyka delty względem upstreamu.
4. `python3 skrypty/sprawdz_przepis.py wyposazenie/przepisy/*.json` — przed
   buildem, nie po.

## Trzy czasowniki, nie jeden

„Regeneruj" nie znaczy nic konkretnego i **nie ma go w interfejsie**.
Operacje są trzy i mają osobne nazwy:

- **Napraw** — stempel mówi „mam", stanu nie ma. Przywraca to, co i tak miało
  być. Nie dotyka danych, nie zmienia standardu. Przycisk terenowy.
- **Podnieś do standardu N** — dokłada brakujące moduły. Tylko dodaje, nigdy
  nie zabiera. Z podglądem różnicy przed wykonaniem.
- **Zbuduj od nowa z przepisu** — wyrzuca `projekt.qgs` i składa od zera,
  zostawiając dane. Operacja magazynowa na komputerze, z kopią zapasową.
  Nie stoi obok „Napraw" w rękawicach, bo różnica między nimi jest
  niewidoczna, a skutki nie.

## Sprawdzenie

    python3 skrypty/wyposazenie.py standardy
    python3 skrypty/wyposazenie.py sprawdz ~/WorkField
