# proba_ukladu — jedenaste sito: URUCHOM OKNO I ZMIERZ

24.08.2026. Powstało po tym, jak **trzy razy z rzędu** zepsułem rozmiar tego
samego panelu i za każdym razem „naprawiałem" go czytaniem QML-a:

1. za wąskie — tabela wychodziła bokiem na mapę
2. za wysokie — przyciski wyjeżdżały pod okno
3. zerowe — cała zawartość zniknęła, choć raport do schowka podawał
   poprawne liczby

Oba wcześniejsze sita przepuściły wszystkie trzy wersje, bo `sito_qml.sh`
czyta **składnię**, a `sito_popup.py` **strukturę**. Żadne nie liczy pikseli.
Rozmiaru nie da się sprawdzić czytaniem kodu i nie ma sensu udawać, że da.

## Co robi

Ładuje plik QML na platformie **offscreen** (bez ekranu, bez X-a) i wypisuje
geometrię drzewa: co ma jaki rozmiar, co ma rozmiar **zerowy**, co jest
**szersze niż okno**.

## Jak uruchomić

    cd skrypty/proba_ukladu
    cmake -S . -B build && cmake --build build -j4
    QT_QPA_PLATFORM=offscreen ./build/proba_ukladu ../../src/app/qml/QfPodgladStylu.qml

Potrzebne pakiety (Debian/Ubuntu):

    qt6-declarative-dev qml6-module-qtquick-controls
    qml6-module-qtquick-layouts qml6-module-qtquick-window

## Atrapy

`atrapy/Theme/` — motyw z barwami Piotra. `QfPopup.qml`, `OknoGlowne.qml` —
najprostsze zamienniki. `mainWindow`, `platformUtilities`, `settings`,
`dashBoard` są podstawiane jako właściwości kontekstu.

Pliki importujące `org.qfield` (np. `QfKopiaPanel.qml`) wymagają atrap tych
modułów — na razie ich nie ma i takie pliki trzeba badać czytaniem albo
dopisać atrapy.

## Co znalazło przy pierwszym uruchomieniu

    QQuickItem      841x84    <-- ramka wzięła rozmiar WŁASNY
    QQuickFlickable 841x0     <-- ZEROWY
      QQuickItem    841x971   <-- zawartość była, ułożona poprawnie

Okno miało 760x640, a ramka 841x84. Przyczyna: **`Popup` nie zastępuje
swojego `contentItem` zadeklarowanym dzieckiem — on je do niego WSTAWIA.**
Dziecko, które samo się nie rozciągnie (`anchors.fill: parent`), bierze
rozmiar wyliczony z zawartości zamiast rozmiaru okna.

Wcześniej problem nie istniał, bo `ColumnLayout` miał `anchors.fill` wprost.
Pojawił się, gdy wstawiłem między nie `Item` z uchwytem do rozciągania.
