# Rysowanie płatów — mozaika bez dziur i zakładek

Jak wyznaczać płaty (FITO_PLATY) tak, żeby sąsiednie poligony stykały się
idealnie, bez ręcznego dociągania wierzchołków na granicach. Notka powstała
po sesji terenowej 2026-08-03.

---

## Zasada podstawowa: rysuj z zakładką, projekt sam przytnie

Projekt szablonu ma włączoną opcję QGIS **"unikaj nakładania"**
(avoid overlap) dla warstwy płatów. Działa ona przy **zapisie** nowej
geometrii: wszystko, co nachodzi na istniejące płaty, jest automatycznie
odcinane do ich krawędzi.

W praktyce, wyznaczając nowy płat obok już istniejących:

1. **Nie celuj w granicę sąsiada.** Rysuj wierzchołki swobodnie,
   **z wyraźną zakładką NA sąsiedni płat** (kilka metrów w głąb nie
   szkodzi — i tak zostanie odcięte).
2. Dokładnie stawiaj tylko wierzchołki na **wolnej** krawędzi płatu —
   tam, gdzie nie ma sąsiada, algorytm nie ma czego przyciąć.
3. Zapisz. Płat wypełni przestrzeń **dokładnie do ścianek sąsiadów** —
   wspólna granica jest identyczna co do milimetra, bez dziur i zakładek.

To ten sam efekt, co „Fill to Adjacent Polygons" z OpenJUMP — tylko
wbudowany w zapis geometrii.

**Wypełnianie luki między kilkoma płatami:** obrysuj lukę z grubym
zapasem na wszystkich sąsiadów — zostanie sam „korek" idealnie
dopasowany do otoczenia.

## Poprawki wspólnych granic: edycja topologiczna

Druga włączona opcja projektu — **edycja topologiczna** — działa przy
edycji istniejących geometrii: przesunięcie wierzchołka leżącego na
wspólnej granicy przesuwa go **w obu sąsiednich płatach naraz**.
Granica pozostaje wspólna; nie powstaje ani dziura, ani zakładka.

Dlatego poprawki przebiegu granicy rób **przez przesuwanie wierzchołków**,
nie przez usuwanie i rysowanie płatu od nowa.

## Czego unikać

- **Nie dociągaj ręcznie wierzchołków wzdłuż granicy sąsiada** — zamiast
  tego zakładka + automatyczne przycięcie. Ręczne dociąganie zostaw dla
  pojedynczych punktów charakterystycznych (narożniki, słupki).
- **Nie rysuj „na styk" z prześwitem** — cienka szczelina między płatami
  to najczęstsze źródło mikropoligonów i błędów w obliczeniach
  powierzchni. Zakładka jest zawsze bezpieczniejsza niż prześwit.
- **Nie przecinaj samego siebie** — jeśli aplikacja odmawia dalszej
  edycji geometrii („geometria niewłaściwa"), nie walcz w terenie:
  zapisz jak jest i dorysuj poprawkę osobnym płatem z zakładką albo
  zostaw do naprawy w biurze (konwersja przepuszcza dane przez
  `make_valid`).

## Gdzie to jest ustawione (dla porządku)

Obie opcje żyją w **pliku projektu QGIS** wchodzącym w skład szablonu —
nie w aplikacji i nie na urządzeniu:

- QGIS → pasek przyciągania → **Unikaj nakładania na aktywnej warstwie**
  (lub tryb per-warstwa z zaznaczoną warstwą płatów),
- QGIS → pasek przyciągania → **Edycja topologiczna**.

Każdy, kto pracuje na aktualnym szablonie, ma je włączone automatycznie.
Jeśli w terenie przycinanie „nie działa" — najpewniej projekt jest starszy
niż szablon z tą konfiguracją; zaktualizuj projekt z szablonu.

---

*WorkField — dokumentacja projektu. Aktualizacja: 2026-08-03.*
