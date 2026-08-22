# Kanał prywatny: NextCloud przez konto serwisowe

Ustawione i sprawdzone 22.08.2026. Realizuje kanał C z
`claude/DANE_workflow.md` („biuro → teren", publikacja migawek) i zasadę
zawartości z `docs/REPO.md` (co nie może iść do publicznego repo).

## Dlaczego osobne konto, a nie własne

Hasło aplikacji w Nextcloudzie zakresuje się do **konta**, nie do katalogu —
takiej możliwości po prostu nie ma. Pierwsza konfiguracja robiona na koncie
właściciela pokazała to wprost: `rclone lsd` wypisał **36 katalogów**, w tym
prywatne i księgowe. Plik konfiguracyjny na laptopie dawał dostęp do
wszystkiego, a skrypt, który przez pomyłkę dostałby `sync` zamiast `copy`,
mógł skasować dowolny z nich.

Konto serwisowe **`wf_desktop`** (nazwa wyświetlana: WorkField_desktop_agent)
widzi wyłącznie to, co mu udostępniono.

## Uprawnienia: maska 5, i to jest sedno

Uprawnienia udostępnienia w Nextcloudzie to maska bitowa:

| bit | znaczenie |
|---|---|
| 1 | odczyt |
| 2 | modyfikacja |
| 4 | tworzenie |
| 8 | usuwanie |
| 16 | udostępnianie dalej |

Udostępnienie `WF_nc_data` dla `wf_desktop` ma **5 = odczyt + tworzenie**.
Można dodać nowy plik, **nie można nadpisać ani skasować istniejącego**.

To nie jest tylko ograniczenie szkód. To jest **zasada z
`DANE_workflow.md` przeniesiona z konwencji do serwera**: „publikacja migawek,
wyłącznie w górę, nazwa niesie czas, nic nie jest nadpisywane". Wcześniej
pilnował tego wyłącznie kod `wyslij_do_nc.sh`; teraz pilnuje tego Nextcloud
i żaden błąd w skrypcie tego nie obejdzie.

Domyślnie udostępnienie dostaje maskę **7** (dochodzi modyfikacja) — trzeba ją
świadomie zawęzić. W interfejsie: Udostępnianie → Uprawnienia niestandardowe →
odznaczyć **Edytuj**. Albo przez API:

    curl -u WLASCICIEL -X PUT -H "OCS-APIRequest: true" \
      "https://SERWER/ocs/v2.php/apps/files_sharing/api/v1/shares/ID" \
      -d permissions=5

`ID` udostępnienia zwraca:

    curl -s -u WLASCICIEL -H "OCS-APIRequest: true" \
      "https://SERWER/ocs/v2.php/apps/files_sharing/api/v1/shares?path=/WF_nc_data" \
      | tr '>' '>\n' | grep -E "<id|<share_with|<permissions"

### Co zostało sprawdzone (nie „powinno działać")

| Test | Wynik |
|---|---|
| `rclone lsd ncwf:` | tylko `WF_nc_data` — izolacja konta działa |
| zapis nowego pliku | przechodzi |
| **nadpisanie istniejącego** | **`403 Forbidden`** — serwer odmawia |
| plik 30 MB (wysyłka w kawałkach + finalizacja) | przechodzi, 7 s |
| `wf_wskazniki.gpkg` 2,2 MB | przechodzi, 2 s, z sumą `.md5` obok |

Czwarty test był najmniej oczywisty: powyżej 10 MB rclone dzieli plik,
składa go w katalogu tymczasowym i **przenosi** na miejsce docelowe. Przy
masce bez prawa modyfikacji ta finalizacja mogła zostać odrzucona — nie
została. Gdyby kiedyś zaczęła, ratunkiem jest `--webdav-nextcloud-chunk-size 0`
(jedno żądanie zamiast kawałków).

## Konfiguracja rclone

Hasło aplikacji tworzy się **zalogowanym na koncie `wf_desktop`**
(Ustawienia → Bezpieczeństwo → Hasła aplikacji). Zrobione u właściciela
niczego by nie ograniczyło. Nazwa hasła ma nieść narzędzie i maszynę —
`rclone-piotr-TUF` — żeby dało się je unieważnić pojedynczo, gdy dojdzie
druga maszyna.

    rclone config create ncwf webdav \
      url=https://SERWER/remote.php/dav/files/wf_desktop/ \
      vendor=nextcloud user=wf_desktop
    read -rsp "Hasło aplikacji: " NCPASS; echo
    rclone config update ncwf pass "$NCPASS" --obscure
    unset NCPASS
    chmod 600 ~/.config/rclone/rclone.conf
    rclone lsd ncwf:        # ma pokazać WYŁĄCZNIE WF_nc_data

Hasło w `rclone.conf` jest **zaciemnione, nie zaszyfrowane** — stąd `chmod 600`
i bezwzględny zakaz wnoszenia tego pliku do repo.

## Użycie

    export WF_NC_REMOTE=ncwf
    bash skrypty/wyslij_do_nc.sh --sucho plik.gpkg    # próba, nic nie wysyła
    bash skrypty/wyslij_do_nc.sh plik.gpkg

Skrypt dokleja do nazwy datę i godzinę, obok kładzie sumę `md5` i **odmawia
wysłania GPKG, obok którego leży `-wal` albo `-shm`** — to znaczy, że ktoś ma
bazę otwartą, a taki plik po drugiej stronie otworzyłby się i skłamał
(lekcja z 21.08: dwa pliki o identycznym rozmiarze i różnej treści).

## Sprzątanie jest robotą właściciela

`wf_desktop` nie może niczego usunąć — i tak ma zostać. Kasowanie starych
migawek i plików testowych robi się z konta właściciela, w interfejsie.
Jeżeli kiedyś kanał zacznie puchnąć, odpowiedzią jest **przegląd i skasowanie
przez człowieka**, nie nadanie prawa usuwania automatowi.

## Pułapki z pierwszej konfiguracji

1. **Adres bez dwukropka** — `https//serwer` zapisało się jako url, rclone
   dokleił własne `https://` i wyszło `https://https//…`. Objaw: `dial tcp:
   lookup https` (DNS próbuje rozwiązać nazwę „https"). Naprawa:
   `rclone config update ncwf url https://…`.
2. **Kreator zjada komentarze.** Wklejony blok z komentarzami obok odpowiedzi
   wpisał `bearer_token = n` i `encoding = q` do konfiguracji; drugie z nich
   wysadza rclone przy każdym połączeniu. Do kreatorów wkleja się **same
   odpowiedzi**, bez objaśnień.
3. **`rclone config password` nie pyta interaktywnie** — wymaga pary
   klucz–wartość. Do wpisania hasła bez zostawiania go w historii powłoki
   służy `read -rsp` plus `rclone config update … --obscure`.
4. **`rclone config` edytuje ten zdalny, którego numer podasz** — łatwo
   przerobić własny na serwisowy i stracić hasło aplikacji właściciela.
