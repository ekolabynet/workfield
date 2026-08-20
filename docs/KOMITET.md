# Komitet agentów WorkField — struktura pracy w Cowork

Decyzja Piotra z 20.08.2026, po dniu w terenie, w którym awaria kosztowała
pół dnia pracy i wymusiła ratowanie danych.

## Po co to jest

Nie po to, żeby było więcej agentów. Po to, żeby **pewnych kroków nie dało
się pominąć**.

Analiza wszystkich błędów z sesji 19–20.08 pokazuje jeden wzorzec: każdy
z nich to **założenie zamiast sprawdzenia**, a nie brak wiedzy. Nagłówek
`qgscentroidfillsymbollayer.h` nie istnieje — i widać to było w grepie dwie
minuty wcześniej. `changeGeometry` bierze referencję niestałą — i widać to
w nagłówku, którego nie otworzyłem. Ekran „Kategorie" już istniał — i widać
to było w panelu warstwy, do którego nie zajrzałem.

Diagnoza jest ta sama, co w notatkach z 16.08 i 17.08 („trzy z pięciu przyczyn
to założenie zamiast sprawdzenia w kodzie"). Trzykrotne powtórzenie tej samej
diagnozy w ciągu tygodnia znaczy, że **przypomnienie nie działa i potrzebna
jest przegroda**.

**Uczciwe zastrzeżenie:** komitet agentów opartych na tym samym modelu ma te
same skłonności w każdej roli. Zysk nie bierze się z „drugiej pary oczu" —
bierze się z **wymuszonych artefaktów**: pobranego źródła, testu na kopii,
wypełnionej listy kontrolnej bezpieczeństwa danych. Rola bez artefaktu to
teatr. Każda rola poniżej ma zdefiniowane wyjście, bez którego następna się
nie zaczyna.

---

## Sześć ról

### 1. ROZPOZNANIE (Surveyor)

**Pyta: czy to w ogóle trzeba pisać, i czy API wygląda tak, jak myślę?**

Wchodzi jako pierwszy, zawsze. Nie wolno go pominąć nawet przy „drobnej
poprawce" — bo łatka 32 (wyrzucona) i zmyślony nagłówek zaczęły się właśnie
od uznania, że sprawa jest oczywista.

Wyjście: **karta faktów** — plik z odpowiedziami i odsyłaczami `plik:linia`:

- Czy ta funkcja już istnieje? Gdzie sprawdzono? *(nie „nie znalazłem pliku
  o takiej nazwie" — nieobecność pliku nie jest dowodem nieobecności funkcji)*
- Sygnatury wszystkich wołanych metod, przepisane z pobranego nagłówka.
- Czy typ jest `Q_INVOKABLE` / `Q_PROPERTY` — bo z QML widać tylko to.
- Gdzie w drzewie leżą zależności (kolejność definicji w C++).
- Czy nowy plik wymaga wpisu w `CMakeLists.txt`.

Zasada twarda: **kotwice łatek kopiuje się z pobranego pliku, nigdy nie
przepisuje z pamięci** (łatka 37 potknęła się o komentarz bez polskich znaków).

### 2. ARCHITEKT

**Pyta: gdzie to ma mieszkać?**

Rozstrzyga w kolejności rosnącego kosztu:

1. Ustawienie projektu / przepis → zero kodu
2. Wtyczka → zip, bez builda *(zasada z 17.08: workflow najpierw jako wtyczka)*
3. Nasz plik C++/QML → delta nie rośnie w plikach QFielda
4. Plik upstreamowy → **dług**, wymaga wpisu do `NOTICE.md` i rozważenia issue

Wyjście: **decyzja z uzasadnieniem** plus odpowiedź na pytanie, czy zmiana
jest kandydatem do upstreamu (punkt 3 relacji z upstreamem).

#### Druga powinność Architekta: okresowy przegląd całości

Decyzja Piotra z 20.08: **nikt nie patrzy na kod jako całość.** Każda sesja
dokłada łatki, każda z osobna uzasadniona — a nikt nie pyta, czy suma nadal
trzyma się kupy. Dryf szablonów z 17.08 wziął się dokładnie stąd: pojedyncze
ulepszenia rodziły się w projektach i nic nie wracało w górę.

Przegląd co **10 łatek albo co wydanie**, co nastąpi wcześniej. Wyjście:
`claude/PRZEGLAD_<data>.md` z liczbami, nie wrażeniami.

**Co mierzy:**

    # 1. delta wobec upstreamu — ile i gdzie
    git diff --stat $(git merge-base HEAD upstream/master) -- src/ | tail -1
    git diff --name-only $(git merge-base HEAD upstream/master) -- src/ \
      | grep -v -E 'src/(app/qml/Qf|core/utils/(narzedzia|zalaczniki))' 

    # 2. pliki upstreamowe, które ruszamy najczęściej (kandydaci na issue)
    git log --format='' --name-only $(git merge-base HEAD upstream/master)..HEAD -- src/ \
      | sort | uniq -c | sort -rn | head -15

    # 3. jak dawno rebase — dług rośnie w tle
    git log -1 --format='%ci' $(git merge-base HEAD upstream/master)

    # 4. martwy kod: nasze czasowniki bez wywołań
    for f in $(grep -o 'Q_INVOKABLE [A-Za-z:<> *]* [a-zA-Z]*(' src/core/utils/narzedziaprojektu.h \
               | grep -o '[a-zA-Z]*($' | tr -d '('); do
      n=$(grep -rc "\.$f(" src/ --include=*.qml | awk -F: '{s+=$2} END {print s+0}')
      [ "$n" = "0" ] && echo "BEZ WYWOŁAŃ: $f"
    done

    # 5. rozmiar plików — kandydaci do podziału
    wc -l src/app/qml/*.qml src/core/utils/*.cpp | sort -rn | head -10

**Na jakie pytania odpowiada — i co znaczy zła odpowiedź:**

| Pytanie | Sygnał ostrzegawczy | Co robić |
|---|---|---|
| Ile plików upstreamowych ruszamy? | rośnie z sesji na sesję | issue do QFielda albo cofnięcie do wtyczki |
| Który plik upstreamowy ruszamy najczęściej? | ten sam trzeci raz | to nie łatka, to funkcja — do upstreamu |
| Kiedy ostatni rebase? | ponad miesiąc | zaplanować osobną sesję |
| Czy są czasowniki bez wywołań? | rośnie | albo brakuje ekranu, albo kod do usunięcia |
| Czy są dwa mechanizmy do tego samego? | jakikolwiek | jeden po cichu robi mniej *(patrz `kreatorNowego`, 81 linii usuniętych 18.08)* |
| Czy `NOTICE.md` zgadza się z deltą? | zwykle nie | odświeżyć w tej samej sesji |
| Czy plugins/ rośnie szybciej niż src/? | **to dobrze** | zasada z 17.08 działa |

**Czego szuka poza liczbami:**

- **Funkcje widoczne, ale nieosiągalne** — czasownik w C++ bez ekranu.
  20.08 kosztowało to pół dnia: `unikajNakladania`, `przyciaganie` i `widget`
  istniały od 17.08, żadnego nie dało się dotknąć z telefonu.
- **Ta sama rzecz w dwóch miejscach** — dwie drogi tworzenia projektu, dwa
  kreatory, dwa mechanizmy zapisu zdjęcia.
- **Decyzje, które się rozeszły** — `docs/` mówi jedno, kod robi drugie.
- **Pliki danych mnożące się w katalogu zlecenia** — 20.08 było ich siedem.

### 3. WYKONAWCA

**Pisze łatkę.**

Nie zaczyna bez karty faktów. Związany regułami, które już są w notatkach:

- łatka jako skrypt Python z kotwicami liczonymi (`n==1 albo STOP`),
- idempotencja ze znacznikiem, który jest **definicją, nie nazwą**
  („colorRampNames" występowało już w `rampByName` i dało fałszywy alarm),
- kopia `.przed_<czym>`,
- **test na własnej kopii repo przed oddaniem**,
- bilans klamer przed i po.

Wyjście: skrypt + dowód testu na kopii.

### 4. AUDYTOR DANYCH

**Pyta: co ta zmiana może zrobić z danymi z terenu, jeśli pójdzie źle?**

To jest rola, której 20.08 zabrakło — i jedyna z prawem **weta**.

Lista kontrolna, wypełniana dla każdej zmiany dotykającej warstw:

- Czy otwiera sesję edycji? Czy sprawdza, że warstwa nie jest już edytowana?
  **Jeśli nie da się sprawdzić — czy operacja jest bezpieczna mimo to?**
- Czy zapisuje do wielu obiektów jedną transakcją? Ile ich może być?
- Czy zmienia liczbę obiektów? Czy człowiek o tym wie przed, czy po?
- Czy nowe pole zostawi `NULL`, który wypadnie z reguły stylizacji?
  *(poligon niewidoczny wygląda jak nieistniejący)*
- Czy da się to cofnąć w terenie, bez komputera?
- Czy stan sprawdzany jest **po fakcie**, czy z wartości zwracanej?

Wtyczka „Zrobione" v0.1 przeszłaby przez wszystkie inne role. Tę listę
oblałaby na pierwszym punkcie — i pół dnia terenu byłoby uratowane.

**Kapelusz terenowca:** ta sama rola pyta o rękawice, brak zasięgu, baterię
i o to, czy czynność widoczna w menu na pewno działa (zasada z 17.08:
*czynność widoczna w menu musi działać albo nie może być widoczna*).

### 5. ARCHIWISTA

**Pamięta i pilnuje spójności decyzji.**

- Czy ta zmiana nie przeczy decyzji, która już zapadła? *(dziś: `gugik.gpkg`
  osobno z 17.08 kontra „wszystko w jednej bazie" z 20.08 — sprzeczność
  wykryta w rozmowie, ale przypadkiem)*
- Czy to **major** wg `docs/WERSJONOWANIE.md`? Czy wymaga `zrzucPrzepis()`
  przed sobą?
- Czy delta wobec upstreamu urosła → `NOTICE.md`.
- Prowadzi handoff, rejestr wydań, listę otwartych pytań.

Wyjście: wpis w notatce **w tej samej sesji**, nie „przy okazji".

### 6. WYDAWCA

**Owns rytuał wydania** (`docs/WYDANIA.md`).

Numer, nazwa kodowa, tag (`git push origin vX.Y.Z`, **nigdy `--tags`** —
wypycha tagi upstreamu), build APK, weryfikacja `versionName` w manifeście
po buildzie, kopia na Nextcloud.

Pilnuje też pułapek środowiska: pliki należące do `root` po Dockerze,
wyścig łatki z buildem (`Running rcc for resource` w logu albo zmiana nie
weszła do binarki).

---

## Przepływ

    ROZPOZNANIE  →  ARCHITEKT  →  WYKONAWCA  →  AUDYTOR  →  WYDAWCA
         │                                          │
         └───────────── ARCHIWISTA ─────────────────┘
                  (towarzyszy, nie stoi w kolejce)

**Bramki — przejście dalej wymaga artefaktu, nie deklaracji:**

| Przejście | Czego wymaga |
|---|---|
| Rozpoznanie → Architekt | karta faktów z odsyłaczami `plik:linia` |
| Architekt → Wykonawca | decyzja o warstwie + ocena długu |
| Wykonawca → Audytor | skrypt + dowód testu na kopii |
| Audytor → Wydawca | wypełniona lista kontrolna, brak weta |
| cokolwiek → koniec | wpis Archiwisty |

**Ścieżka szybka** (literówka, napis, kolor): Rozpoznanie skrócone do
potwierdzenia kotwicy, Audytor pomijany **tylko gdy zmiana nie dotyka
warstw ani plików danych**. Decyzję o ścieżce szybkiej podejmuje Architekt
i zapisuje ją — żeby „to drobiazg" nie było wymówką po fakcie.

---

## Jak to złożyć w Cowork

**Skille** (`.claude/skills/`) — jedna na rolę, z listą kontrolną i wzorem
artefaktu. Skill jest ważniejszy od agenta: to on niesie treść przegrody.

**Subagenty** — dla ról, które mają czytać dużo i wracać z podsumowaniem
(Rozpoznanie: pobrać i przeczytać nagłówki; Archiwista: przeszukać notatki
pod kątem sprzeczności). Reszta może być krokami w jednej rozmowie.

**Pliki w repo** — bo agent bez pliku zapomni:

- `docs/KOMITET.md` — ten dokument,
- `docs/KONTROLA_DANYCH.md` — lista Audytora, do odhaczania,
- `claude/karty_faktow/` — karty z każdej sesji, datowane.

**Wymuszenie, które działa niezależnie od dobrej woli:** żaden skrypt łatki
nie jest oddawany bez sekcji `# KARTA FAKTÓW` w nagłówku pliku, z odsyłaczami
do sprawdzonych miejsc. Brak sekcji = łatka nie idzie dalej. To samo, co
z kotwicami: mechanizm ma **odmawiać**, nie przypominać.

---

## Czego ta struktura nie naprawi

- **Wspólnej ślepoty modelu.** Wszystkie role mają te same skłonności.
  Chronią artefakty, nie liczba głosów.
- **Braku środowiska.** Kod nadal kompiluje się dopiero u Piotra; pierwszy
  build wypluwa drobiazgi i tak zostanie.
- **Zmęczenia pod koniec sesji.** 20.08 wtyczka powstała jako ostatnia
  pozycja długiego dnia. Zasada do rozważenia: **operacje hurtowe na danych
  nie powstają po ośmiu godzinach.**

## Pierwsze zadania komitetu

1. **Przegląd architektury** — pierwszy w historii projektu. Zaległość jest
   z definicji największa właśnie teraz.
2. **Naprawa wtyczki „Zrobione"** — bo to ona pokazała, czego brakuje, i jest
   dość mała, żeby przejść pełną ścieżkę bez zmęczenia materiału.
