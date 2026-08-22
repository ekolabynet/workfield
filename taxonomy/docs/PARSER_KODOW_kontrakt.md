# Parser kodów gatunków — blokada zdjęta, kontrakt ze słownikiem

Notatka z 22.08.2026, po rozstrzygnięciu kręgosłupa. Domyka wątek z
`KONTEKST_GATUNKU.md` i kierunek z `WorkField_handoff_2026-08-21.md`.

## Blokada z `KONTEKST_GATUNKU.md` jest zdjęta

Tamta notatka mówiła wprost: parser kodów, pasek podpowiedzi i typowanie
gatunków **czekają na rozstrzygnięcie backbone'u**, bo pytanie o backbone
jest pytaniem o **klucz**, a przemianowanie klucza później to major
z migracją.

Klucz jest rozstrzygnięty:

> **`(GATUNEK, KROLESTWO)`** — kanoniczna łacina jako tekst plus królestwo.
> Nie identyfikator zewnętrznej bazy: te wygasają (GBIF unieważnił własne
> `taxonKey`, identyfikatory COL XR zmieniają się między wydaniami).
> Identyfikatory obce siedzą w `TAKSONY_XREF` z wersją źródła i datą.

Czyli parser może ruszyć. Ale nie jako osobny byt — jako **konsument
słownika**, który już istnieje.

## Dwa parsery, nie jeden. I to jest dobrze

To są dwie różne rzeczy i **nie wolno ich scalać**:

| | parser kodów (OpenVTA) | normalizacja nazw |
|---|---|---|
| Co czyta | zawartość pola: `Lp C60 Fr C20` | pojedynczą nazwę: `Tilia cordata 'Greenspire'` |
| Co produkuje | **wiersze** spisu gatunkowego | rozbiór: kanoniczna, kultywar, hybryda, kwalifikator |
| Gdzie działa | **telefon**, QML/C++, na żywo | **biuro**, Python, wsadowo |
| Co zna | składnię: „kod = stała ze słownika + zmienne o typach" | morfologię nazwy botanicznej |
| Czego NIE zna | gatunków | pokrycia, składni pola |
| Plik | do napisania | `skrypty/taksony_normalizacja.py` |

Normalizacja **buduje** słownik, parser go **czyta**. Przenoszenie
normalizacji na telefon byłoby błędem: w terenie nikt nie wpisuje autorstwa
ani `subsp.`, a gdyby wpisał — surowy ciąg i tak zostaje i biuro to rozbierze.

Wspólna mają jedną zasadę, tę samą, którą ustaliłeś 21.08:

> **Surowy ciąg zapisuje się zawsze. Wiersze są z niego WYPROWADZANE.**
> Zły odczyt parsera nie kosztuje wtedy danych — przepuszczasz jeszcze raz.

## Kontrakt: co parser bierze ze słownika

`TAKSONY` jedzie w `dane.gpkg` zlecenia i ma dokładnie to, czego parser
potrzebuje:

| Kolumna | Rola w parserze |
|---|---|
| `SKROT` | **kod** — stała, po której parser rozpoznaje pozycję |
| `SKROT_ZRODLO` | `gboard` = Twój, używany w terenie; `auto` = wygenerowany, małymi literami |
| `NAZWA` | co pokazać w podglądzie rozpoznanych wierszy |
| `GATUNEK` + `KROLESTWO` | **co zapisać do wiersza** — patrz pułapka niżej |
| `IGO`, `OCHRONA`, `PROG_CM` | alert w terenie (pomysł nr 1 z `KONTEKST_GATUNKU.md`) |

**Parser nie ma własnej listy gatunków.** To nie jest wygoda, tylko warunek:
lista w dwóch miejscach rozjeżdża się przy pierwszym zleceniu, w którym
dopiszesz gatunek w terenie.

Unikalność skrótów w obrębie zlecenia gwarantuje już `zbuduj_taksony.py` —
`Lp` może wskazywać tylko jeden takson, kolejne dostają `lp2`, `lp3`.

## Pułapka, o której trzeba wiedzieć przed pisaniem

**Wiersz spisu musi zapisywać `GATUNEK`, nie sam skrót.**

Skrót jest unikalny **w obrębie zlecenia**, nie globalnie. `TAKSONY` jadą ze
zleceniem i wracają ze zwrotem — więc w następnym zleceniu ten sam `Lp` może
wskazywać na co innego (u Ciebie *Lolium perenne*, ale *Lonicera
periclymenum* to też „Lp"). Jeżeli wiersz zapisze tylko kod, to po scaleniu
dwóch zleceń do mastera **dane zmienią znaczenie po cichu** — czyli
dokładnie ten rodzaj awarii, który kosztował pół dnia 20 i 21 sierpnia.

Minimalny zestaw pól wiersza:

    SUROWY_CIAG      tekst pola, dosłownie (na obiekcie, nie na wierszu)
    SKROT_UZYTY      co człowiek wpisał
    GATUNEK          rozwinięcie ze słownika — TO jest klucz
    KROLESTWO        druga połowa klucza
    POKRYCIE         wartość zmiennej z kodu
    POZYCJA          offset w ciągu — żeby usunięcie kodu skasowało WŁAŚCIWY wiersz
    ZRODLO_WIERSZA   pasek | parser | kreator
    WERSJA_SLOWNIKA  z WF_ZRODLA — czym rozwinięto skrót

`ZRODLO_WIERSZA` jest tanie, a rozstrzyga spór, którego inaczej nie da się
rozstrzygnąć: **pasek podpowiedzi wie, co wstawił** (pewność 100%), a parser
zgadł z tekstu (do sprawdzenia). Bez tej kolumny obie sytuacje wyglądają
w bazie identycznie.

## Kolejność, którą proponuję

`KONTEKST_GATUNKU.md` sam ostrzega przed „dziesiątą ciekawą funkcją, gdy
podstawy mają dziury" — cofanie zmian i Centrum wyposażenia wiszą od 20.08.
Ale jeżeli parser ma iść, to w tej kolejności:

1. **Pasek podpowiedzi** (czyta `SKROT` → wstawia `NAZWA`, tworzy wiersz
   z pewnym kodem). Tańszy niż parser, niezależny od klawiatury, i zdejmuje
   większość problemu — bo większość wpisów idzie przez pasek.
2. **Parser** tylko dla tego, co człowiek dopisał ręcznie — czyli dla
   sekwencji pokrycia, gdzie właśnie zdarzają się pomyłki.
3. **Alert prawny** przy roślinie (`IGO`, `OCHRONA`) — to już jest złączenie
   po `GATUNEK`, dane są w słowniku, nic nowego nie trzeba zbierać.

## Co zrobić z tym, co już powstało w tamtym czacie

Nie wyrzucać — przejrzeć pod kątem trzech pytań:

1. **Czy ma własną listę gatunków?** Jeśli tak — wymienić na odczyt
   z `TAKSONY`. To jedyna zmiana, która jest obowiązkowa.
2. **Czy zapisuje surowy ciąg?** Jeśli nie — dołożyć, zanim cokolwiek
   pojedzie w teren.
3. **Czy wiersz niesie `GATUNEK`, czy tylko skrót?** Patrz pułapka wyżej.

Do sprawdzenia po stronie danych: schemat `FITO_SPIS_GATUNKOWY` (867 wierszy
z terenu) — czy da się do niego dołożyć te kolumny bez migracji, czy trzeba
nowej tabeli. **To jest pierwsza rzecz do obejrzenia**, przed pisaniem
czegokolwiek.
