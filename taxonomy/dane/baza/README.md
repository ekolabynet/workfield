# `dane/baza/` — zbudowany słownik jako CSV

To jest **wynik pracy**, nie półprodukt: sprawdzone nazwy, przypisane progi,
poprawione literówki, decyzje o dopasowaniu. Trzymamy go tutaj jako tekst,
żeby dało się go przejrzeć w PR, poprawić jedną linijką i zobaczyć diff.

    taksony_baza_RRRR-MM-DD.csv        słownik (kolumny jak tabela TAKSONY)
    taksony_baza_RRRR-MM-DD_xref.csv   klucze obce z wersją źródła i datą

Powstaje przez:

    python3 ../../skrypty/zbuduj_taksony.py --zrodlo … --kolumna GATUNEK \
        --csv-out dane/baza/taksony_baza_$(date +%F).csv

GPKG dla telefonu jest **wydrukiem** z tego pliku — powstaje w sekundy,
więc nie wersjonujemy go w gicie, tylko przypinamy do wydania.
