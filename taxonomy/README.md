# `taxonomy/` — nazwy gatunków i to, co prawo do nich przypina

Kto tu trafia pierwszy raz, czyta trzy akapity niżej i wie, gdzie iść.
Kto szuka konkretnego pliku — patrzy w tabelę.

**Po co to jest.** Aplikacja musi w terenie wiedzieć trzy rzeczy o wpisanym
gatunku: czy nazwa jest poprawna, jak brzmi po polsku i jakie progi prawne
się z nią wiążą. Wszystkie trzy odpowiedzi jadą ze zleceniem w pliku, bo
w terenie nie ma sieci. Ten katalog produkuje ten plik.

**Czego tu nie ma.** Nie ma tu kręgosłupa taksonomicznego jako takiego —
1,6 mln nazw WFO nie jedzie ani do repo, ani na telefon. Kręgosłup jest
narzędziem biura: służy do rozstrzygnięcia naszych kilku tysięcy nazw, a do
projektu trafia tylko wynik. Nie ma tu też niczego na licencji, która nie
pozwala na redystrybucję — szczegóły w `docs/LICENCJE_audyt.md`.

**Zasada, na której to stoi.** Kluczem jest para `(nazwa kanoniczna,
królestwo)`, a nie identyfikator zewnętrznej bazy. Identyfikatory obce
wozimy jako kolumny z wersją i datą, bo wygasają — GBIF unieważnił własne
`taxonKey` w 2026 r. Każda warstwa danych ma datę w nazwie pliku.

---

## Mapa katalogu

| Ścieżka | Co to jest |
|---|---|
| `docs/KREGOSLUP.md` | **zacznij tutaj** — co możemy mieć, co powinniśmy, co jest tabelą, co linkiem, co API. Decyzje i pułapki |
| `docs/OCHRONA_ZWIERZAT.md` | warstwa zwierzęca: co z niej wynika dla pracy przy drzewach (okno na gniazda, strefy) |
| `docs/LICENCJE_audyt.md` | **co wolno w publicznym repo**, a co nie — z podstawami, nie z przeczuciami |
| `docs/OBIEG_SLOWNIKA.md` | **jak to krąży**: master w biurze, snapshot na telefonie, dopiski z terenu; trzy poziomy wniosków |
| `docs/PARSER_KODOW_kontrakt.md` | umowa między parserem kodów gatunków a słownikiem: co czyta, co zapisuje, czego nie wolno |
| `docs/ZRODLA_I_LICENCJE.md` | fragment do `NOTICE.md`: skąd dane, na jakiej licencji, czego świadomie nie bierzemy |
| `docs/ZACZEPY_w_repo.md` | jak ten katalog wstawić do repo i czym go zaczepić, żeby nie zniknął z pola widzenia |
| `WERSJE.md` | **rejestr wydań warstw** — co, kiedy, z czego, co się zmieniło |
| `dane/prawo/prawo_gatunki_RRRR-MM-DD.csv` | rośliny: progi 83f, grupy stawek, pomniki, zwolnienia, IGO, ochrona gatunkowa |
| `dane/prawo/ochrona_zwierzat_2016-2183.csv` | zwierzęta: 805 gatunków chronionych (zał. 1–3) |
| `dane/prawo/strefy_ochrony_2016-2183.csv` | strefy ochrony ostoi i gniazd (zał. 4), z promieniami i terminami |
| `dane/baza/` | **zbudowany słownik jako CSV** — to jest wynik pracy, nie półprodukt |
| `dane/nazwy/` | nazwy polskie — produkt `pobierz_nazwy_pl.py` plus ręczna korekta |
| `dane/prywatne/` | warstwy CC BY-NC i zastrzeżone — w `.gitignore`, nakładka spoza repo |
| `skrypty/` | cały łańcuch budowy, opis niżej |

## Łańcuch budowy — kolejność ma znaczenie

```
    słownik z terenu (CSV albo tabela w GPKG)
              │
              ▼
  1. taksony_normalizacja.py     rozbiór nazwy: autor, kultywar, ×, sp., cf.
              │                  (uruchomiony sam = autotest na 20 przypadkach)
              ▼
  2. zbuduj_taksony.py           dopasowanie + warstwa prawna + skróty
              │                  → TAKSONY, TAKSONY_XREF, WF_ZRODLA w GPKG
              ├── --nazwy-pl ◄── 3. pobierz_nazwy_pl.py   (Wikidata, CC0)
              ├── --skroty   ◄── istniejący słownik Gboarda
              └── --prawo    ◄── dane/prawo/prawo_gatunki_*.csv (bierze najnowszy)
              │
              ▼
  4. wepnij_taksony_w_formularz.py   konsola QGIS: kontrola miękka + pola
                                     wirtualne _PROG, _IGO, _OCHRONA
```

Osobno, poza łańcuchem: **`parsuj_ochrona_zwierzat.py`** — wyciąga załączniki
rozporządzenia o ochronie gatunkowej zwierząt z oryginalnego PDF-a Dziennika
Ustaw. Uruchamiany raz na akt, nie przy każdej budowie.

Pierwszy krok zawsze na sucho:

    python3 skrypty/zbuduj_taksony.py --sucho \
        --zrodlo /DATA/WorkField/szablony/wskazniki/slownik_gatunkow.csv \
        --kolumna GATUNEK

`--sucho` nic nie zapisuje i wypisuje listę „do obejrzenia okiem".

## Trzy tabele, które z tego wychodzą

- **`TAKSONY`** — słownik: tożsamość, nazwa polska, skrót, progi prawne.
  Jedzie w `dane.gpkg` zlecenia, wraca ze zwrotem. **Nieodtwarzalna** —
  człowiek dopisuje w terenie.
- **`TAKSONY_XREF`** — klucze obce (GBIF, COL, iNat, NCBI) z wersją źródła
  i datą rozstrzygnięcia. Odtwarzalna.
- **`WF_ZRODLA`** — pięć wierszy mówiących, z czego zbudowano tę bazę.
  To jest odpowiedź na pytanie zadane za rok: „skąd wzięła się ta liczba".

## Czego ten katalog nie rozstrzyga

- **Kultywarów nie ma w żadnym kręgosłupie** — ani WFO, ani COL, ani IPNI.
  Jadą osobną kolumną, odcinane przed dopasowaniem.
- **Nazwy polskie to nasze opracowanie**, nie nomenklatura urzędowa.
  Źródła otwarte są dziurawe: GBIF nie ma polskiej nazwy dla *Quercus robur*.
- **Warstwa prawna to nie porada prawna.** Nazwy łacińskie przy przepisach są
  naszym mapowaniem — akty posługują się wyłącznie polskimi, często
  rodzajowymi („topoli", „wierzb").

Pusta kolumna `WERYFIKACJA` w każdym pliku znaczy jedno: **nikt tego jeszcze
nie sprawdził okiem.**
