# Magazyn WorkField — słownik i umowa

Jedna strona prawdy o katalogach, bramach i cyklu życia zadania.
Kod i interfejs mają się do niej stosować; zmiany tylko świadomą decyzją.

## Katalogi (dysk: krótkie, techniczne)

| Katalog     | Rola                                              | Brama w interfejsie |
|-------------|---------------------------------------------------|---------------------|
| `szablony/` | wzorce projektów (dane.gpkg, projekt.qgs)         | Szablony            |
| `master/`   | stan scalony zadania — jedyne źródło prawdy       | Master              |
| `wydania/`  | paczki wychodzące w teren (zip / folder)          | Wydane w teren      |
| `zwroty/`   | paczki wracające z terenu — historia, nie kasować | Przyjęte z terenu   |
| `archiwum/` | zadania zamknięte                                 | Archiwum            |
| `dziennik/` | zapisy operacji                                   | (wewnętrzne)        |

W drzewie magazynu Szablony stoją nad projektami (są uniwersalne).
„Stan zleceń" to osobny widok raportowy nad masterem (stopień realizacji,
wydania wiszące w terenie) — nie gałąź drzewa; w budowie.

Użytkownik nigdy nie wybiera katalogu — wybiera czynność (bramę),
a czynność zna swój katalog. Korzeń: `~/WorkField` (zmienialny w
ustawieniach na komputerze); na telefonie narzucony przez system.

## Konwencja nazw projektów (kontrakt)

    zleceniodawca_obiekt_id_zadanie_wersja
    np. zzw_pze_2605_inw_v3

- człony rozdziela `_`; wersja ma postać `vN`;
- pełne nazwy członów daje `rejestr_skrotow.csv`
  (zzw → Zarząd Zieleni Warszawy, pze → Park Żerański, inw → inwentaryzacja);
- nazwa niespełniająca konwencji trafia w interfejsie do gałęzi „Inne" —
  nic nie znika, ale nie wchodzi do drzewa hierarchii.

Drzewo w menu Projekt: Zleceniodawca → Obiekt → Zadanie → Wersja,
budowane wyłącznie z parsowania nazw (bez bazy metadanych).

## Cykl życia zadania

    szablon → nowe zadanie (w wydania/) → teren → zwrot (do zwroty/)
            → przyjęcie zwrotu → master → ... kolejne wydania i zwroty
            → zamknięcie → archiwum/

Master zadania powstaje przy pierwszym przyjęciu zwrotu i od tej pory
raportuje stan realizacji (data ostatniego zwrotu, wydania wiszące
w terenie, liczniki z warstw roboczych).

## Niezmienniki

1. Master zmienia się WYŁĄCZNIE przez czasownik „Przyjmij zwrot" —
   nigdy przez ręczną edycję ani pracę terenową na masterze.
2. Kopiujemy, nie przenosimy: każda operacja zostawia oryginał;
   zwrot po scaleniu zostaje w `zwroty/` jako zapis historii.
3. Wydanie bez późniejszego zwrotu = „w terenie" — to jest miara
   tego, co jest u ludzi.
4. Kabel (zip przez kartę) i chmura (NextCloud) to dwa transporty
   tych samych bram Wydane w teren / Przyjęte z terenu — nie osobne mechanizmy.
