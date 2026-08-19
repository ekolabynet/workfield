/***************************************************************************
  narzedziaprojektu.h - NarzedziaProjektu

 ---------------------
 WorkField: czasowniki do budowania i doposazania projektu, wystawione do QML.

 Powod istnienia. Do 17.08.2026 kazda zmiana struktury projektu — warstwa,
 tabela zalacznikow, relacja, zakladka formularza, widget pola — byla
 skryptem PyQGIS uruchamianym w konsoli QGIS Desktop. W terenie oznaczalo to
 „wracaj do biura". WorkField jest budowany bez Pythona (vcpkg/ports/qgis:
 -DWITH_PYTHON=OFF, brak cechy bindings), ale CALE API, ktorego te skrypty
 uzywaly, jest w QGIS core — a QGIS core siedzi w aplikacji. Brakowalo
 wylacznie Q_INVOKABLE.

 Ta klasa jest tym brakujacym kawalkiem: cienka warstwa czasownikow, bez
 wlasnej logiki i bez wiedzy o tym, po co ktos ich uzywa. Sens skladaja
 dopiero przepisy — pliki JSON czytane z karty (patrz docs/WYPOSAZENIE.md).
 Dzieki temu nowe narzedzie jest plikiem, a nie kolejnym buildem Androida.

 Inwentarz czasownikow powstal z przejrzenia skryptow w skrypty/ i zamyka
 sie w okolicach dwudziestu pozycji.

 Patrz docs/WYPOSAZENIE.md.
 ***************************************************************************/

#ifndef NARZEDZIAPROJEKTU_H
#define NARZEDZIAPROJEKTU_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

#include <qgsproject.h>
#include <qgsvectorlayer.h>

/**
 * \ingroup core
 */
class NarzedziaProjektu : public QObject
{
    Q_OBJECT

  public:
    explicit NarzedziaProjektu( QObject *parent = nullptr );

    // ------------------------------------------------------------- pola i formularz

    //! Alias (opis) pola widoczny w formularzu i na wydruku.
    Q_INVOKABLE bool alias( QgsVectorLayer *warstwa, const QString &pole, const QString &tekst ) const;

    /**
     * Widget edycyjny pola: \a typ to nazwa widgetu QGIS ("TextEdit", "Hidden",
     * "ValueMap", "ExternalResource", "DateTime", "CheckBox", "Range"...),
     * \a opcje to jego konfiguracja.
     */
    Q_INVOKABLE bool widget( QgsVectorLayer *warstwa, const QString &pole, const QString &typ, const QVariantMap &opcje = QVariantMap() ) const;

    /**
     * Wartosc domyslna pola jako wyrazenie QGIS. \a przyAktualizacji = true
     * przelicza ja przy kazdej edycji obiektu (tak liczy sie SZEROKOSC_M).
     */
    Q_INVOKABLE bool wartoscDomyslna( QgsVectorLayer *warstwa, const QString &pole, const QString &wyrazenie, bool przyAktualizacji = false ) const;

    /**
     * Ograniczenie MIEKKIE: ostrzega, nie blokuje zapisu. Twarde ograniczenia
     * w terenie sa zakazane — rekord ma wyjsc z pola nawet niedoskonaly.
     */
    Q_INVOKABLE bool ograniczenieMiekkie( QgsVectorLayer *warstwa, const QString &pole, const QString &wyrazenie, const QString &opis ) const;

    //! Wyrazenie wyswietlania obiektu (podpis na liscie i w tytule formularza).
    Q_INVOKABLE bool wyrazenieWyswietlania( QgsVectorLayer *warstwa, const QString &wyrazenie ) const;

    /**
     * Uklad formularza z zakladkami. \a zakladki to lista map:
     *   { "tytul": "Pomiary", "pola": ["OBW_5", "OBW_130"] }
     *   { "tytul": "Zalaczniki", "relacja": "<id relacji>" }
     * Pola nieistniejace sa pomijane po cichu — przepis moze byc szerszy
     * niz warstwa, na ktora go zakladamy.
     */
    Q_INVOKABLE bool ukladFormularza( QgsVectorLayer *warstwa, const QVariantList &zakladki ) const;

    //! Ukrywa formularz potwierdzenia po zapisie (QGIS pyta, QField nie ma gdzie).
    Q_INVOKABLE bool bezPotwierdzenia( QgsVectorLayer *warstwa ) const;

    // ------------------------------------------------------------------- relacje

    /**
     * Zaklada relacje rodzic -> dziecko. \a opis:
     *   id           QString  identyfikator relacji (nadawany, nie losowany)
     *   nazwa        QString  tytul widoczny w formularzu
     *   rodzic       QString  nazwa albo id warstwy-rodzica
     *   dziecko      QString  nazwa albo id warstwy-dziecka
     *   poleDziecka  QString  klucz obcy w dziecku (np. ID_RODZICA)
     *   poleRodzica  QString  pole rodzica, na ktore wskazuje (np. fid)
     *   kompozycja   bool     true = kasowanie rodzica kasuje dzieci
     *
     * Zwraca identyfikator relacji albo pusty string. Idempotentna: relacja
     * o tym samym id nie jest zakladana drugi raz.
     */
    Q_INVOKABLE QString relacja( QgsProject *projekt, const QVariantMap &opis ) const;

    // ---------------------------------------------------------------- projekt

    //! Wlasciwosc projektu, np. ("Digitizing", "AvoidIntersectionsMode", 2).
    Q_INVOKABLE bool wlasciwosc( QgsProject *projekt, const QString &grupa, const QString &klucz, const QVariant &wartosc ) const;

    //! Odczyt wlasciwosci projektu; nieprawidlowy QVariant, gdy brak.
    Q_INVOKABLE QVariant czytajWlasciwosc( QgsProject *projekt, const QString &grupa, const QString &klucz ) const;

    //! Zmienna projektu widoczna w wyrazeniach jako @nazwa.
    Q_INVOKABLE bool zmiennaProjektu( QgsProject *projekt, const QString &nazwa, const QVariant &wartosc ) const;

    //! Wlasciwosc niestandardowa warstwy — tedy idzie m.in. konwencja nazw zdjec.
    Q_INVOKABLE bool wlasciwoscWarstwy( QgsMapLayer *warstwa, const QString &klucz, const QVariant &wartosc ) const;

    /**
     * Przyciaganie. \a ustawienia: wlaczone(bool), tryb(int: 1 aktywna,
     * 2 wszystkie, 3 zaawansowane), typ(int: flagi 1 wierzcholek, 2 odcinek,
     * 4 obszar), tolerancja(double), jednostka(int: 0 warstwa, 1 piksele,
     * 2 projekt), przeciecia(bool).
     */
    Q_INVOKABLE bool przyciaganie( QgsProject *projekt, const QVariantMap &ustawienia ) const;

    /**
     * Unikanie nakladania poligonow. \a tryb: 0 wolno, 1 warstwa aktywna,
     * 2 lista warstw. \a nazwyWarstw pusta przy trybie 2 = wszystkie
     * edytowalne warstwy poligonowe projektu.
     */
    Q_INVOKABLE bool unikajNakladania( QgsProject *projekt, int tryb, const QStringList &nazwyWarstw = QStringList() ) const;

    // ---------------------------------------------------------------- warstwy

    /**
     * Zaklada pusty projekt: katalog \a korzen/\a nazwa, w nim projekt.qgs
     * z ustawionym ukladem wspolrzednych i tytulem. Zwraca sciezke pliku
     * projektu albo pusty string.
     *
     * To jest rusztowanie pod przepis: aplikacja wczytuje ten pusty projekt
     * (iface.loadFile), a po sygnale loadProjectEnded interpreter przepisu
     * dokłada do niego warstwy, relacje i ustawienia. Nie uzywamy
     * ProjectUtils::createProject, bo ono narzuca wlasny katalog
     * ("Created Projects") i EPSG:3857 — obok konwencji magazynu.
     */
    Q_INVOKABLE QString nowyProjekt( const QString &korzen, const QString &nazwa, const QString &crsAuthId = QStringLiteral( "EPSG:2178" ) ) const;

    /**
     * Katalog, w ktorym rodza sie nowe zadania: <korzen>/wydania, a gdy go
     * nie ma — <korzen>/wymiana (stare drzewa), a gdy i tego nie ma — sam
     * korzen. Ta sama regula co ProcesyStudio::nowyZSzablonu (docs/MAGAZYN.md).
     *
     * Osobny czasownik, bo FileUtils::fileExists() wymaga isFile() i na
     * katalogu zwraca false — zadanie ladowalo przez to w korzeniu magazynu.
     */
    Q_INVOKABLE QString katalogZadan( const QString &korzen ) const;

    /**
     * Katalog z szablonami: pierwszy istniejacy z "Szablony", "szablony",
     * "templates" pod \a korzen; gdy zadnego nie ma — pusty string.
     * Na telefonie korzen narzuca system, a nazwa katalogu bywa rozna
     * w zaleznosci od tego, czym magazyn byl zakladany.
     */
    Q_INVOKABLE QString katalogSzablonow( const QString &korzen ) const;

    /**
     * Przenosi warstwe do grupy w drzewie warstw, zakladajac grupe w razie
     * potrzeby. Grupy sluza do chowania tabel pomocniczych (Zalaczniki,
     * Slowniki), zeby nie zasmiecaly panelu w terenie.
     */
    Q_INVOKABLE bool doGrupy( QgsProject *projekt, QgsMapLayer *warstwa, const QString &grupa, bool zwinieta = true, bool widoczna = false ) const;

    /**
     * Warstwy ROBOCZE projektu — te, na ktorych sie zbiera dane.
     * Pomija tabele zalacznikow (ZAL_), warstwy odniesienia (REF_),
     * tylko-do-odczytu i bezgeometryczne. Zwraca liste map:
     *   nazwa      QString
     *   geometria  QString  "Punkt" | "Linia" | "Poligon"
     *   punktowa   bool
     *
     * Osobny czasownik, bo QML nie ma jak bezpiecznie odroznic warstwy
     * wektorowej od rastrowej — rzutowanie robimy po stronie C++.
     */
    Q_INVOKABLE QVariantList warstwyRobocze( QgsProject *projekt ) const;

    //! Warstwa projektu po nazwie; nullptr, gdy nie ma.
    Q_INVOKABLE QgsVectorLayer *warstwaPoNazwie( QgsProject *projekt, const QString &nazwa ) const;

    /**
     * Dosypuje tabele z innego GeoPackage (slowniki gatunkow, taksony,
     * wskazniki). Nie rusza tabel, ktore juz sa. Zwraca liczbe skopiowanych.
     */
    Q_INVOKABLE int dosypTabele( const QString &zrodloGpkg, const QString &celGpkg, const QStringList &tabele ) const;

    // -------------------------------------------------------------- geometria

    /**
     * Scala czesci obiektu wieloczesciowego w jedna (unia). Zwraca mape:
     *   ok           bool
     *   partsBefore  int
     *   partsAfter   int
     *   message      QString
     *
     * Gdy czesci sie nie stykaja, unia nadal ma wiecej niz jedna czesc —
     * wtedy nic nie zapisujemy i mowimy to wprost.
     */
    Q_INVOKABLE QVariantMap mergeParts( QgsVectorLayer *layer, QgsFeatureId fid, bool write = true ) const;

    /**
     * Rozdziela obiekt wieloczesciowy na osobne obiekty. Pierwsza czesc
     * zostaje na istniejacym fid, pozostale staja sie nowymi obiektami
     * z kopia atrybutow (klucze glowne wyzerowane). Zwraca mape:
     *   ok       bool
     *   parts    int           na ile czesci rozdzielono
     *   created  QVariantList  fid nowych obiektow
     *   message  QString
     *
     * Zalaczniki zostaja przy pierwotnym obiekcie.
     */
    Q_INVOKABLE QVariantMap splitParts( QgsVectorLayer *layer, QgsFeatureId fid, bool write = true ) const;


    /**
     * Diagnoza geometrii obiektu. Zwraca mape:
     *   ok              bool   udalo sie sprawdzic (obiekt istnieje, ma geometrie)
     *   wazna           bool   geometria poprawna wg GEOS
     *   wieloczesciowa  bool
     *   czesci          int
     *   bledy           lista map { opis, maMiejsce, x, y }
     *   opis            QString  zdanie do pokazania czlowiekowi
     *
     * Miejsce bledu (x, y w ukladzie warstwy) jest tu najwazniejsze:
     * pozwala pokazac, GDZIE geometria sie przecina, zamiast informowac,
     * ze cos jest nie tak. Osemki na malym ekranie nie widac.
     */
    Q_INVOKABLE QVariantMap sprawdzGeometrie( QgsVectorLayer *warstwa, QgsFeatureId fid ) const;

    /**
     * Naprawa geometrii obiektu (makeValid). Zwraca mape:
     *   ok             bool   naprawiono i zapisano
     *   bylaWazna      bool   nie bylo czego naprawiac
     *   czesciPrzed    int
     *   czesciPo       int
     *   wymagaPodzialu bool   naprawa daje wiecej czesci, niz warstwa przyjmie
     *   opis           QString
     *
     * \a zapisz = false liczy skutek bez dotykania danych — do pokazania
     * w pytaniu "naprawic?" zanim czlowiek sie zgodzi.
     */
    Q_INVOKABLE QVariantMap naprawGeometrie( QgsVectorLayer *warstwa, QgsFeatureId fid, bool zapisz = true ) const;

    /**
     * Zlaczenie obiektow w jeden. Geometrie sumuje (combine), atrybuty
     * zostaja z PIERWSZEGO fid na liscie, pozostale obiekty sa kasowane.
     * Zwraca mape:
     *   ok        bool
     *   fid       QgsFeatureId  obiekt, ktory zostal
     *   zlaczono  int           ile obiektow weszlo
     *   czesci    int           ile czesci ma wynik
     *   opis      QString
     *
     * Gdy obiekty sie nie stykaja, a warstwa jest jednoczesciowa —
     * nie zapisujemy nic i mowimy dlaczego.
     */
    Q_INVOKABLE QVariantMap polaczObiekty( QgsVectorLayer *warstwa, const QVariantList &fidy, bool zapisz = true ) const;

    // ---------------------------------------------------------------- stempel

    /**
     * Stempel wyposazenia z GeoPackage: mapa modul -> { wersja, data, zrodlo }.
     * Tabela WF_WYPOSAZENIE nie jest rejestrowana w gpkg_contents, wiec nie
     * pokazuje sie jako warstwa. Jedzie w teren z danymi i wraca ze zwrotem.
     */
    Q_INVOKABLE QVariantMap stempel( const QString &gpkg ) const;

    //! Wpisuje albo aktualizuje wpis stempla.
    Q_INVOKABLE bool stempluj( const QString &gpkg, const QString &modul, int wersja, const QString &zrodlo, const QString &przez = QString() ) const;

    //! Usuwa wpis stempla (zdjecie modulu).
    Q_INVOKABLE bool odstempluj( const QString &gpkg, const QString &modul ) const;

    // ------------------------------------------------------------------ pliki

    /**
     * Kopia zapasowa pliku obok oryginalu, z sufiksem .bak_RRRRMMDD_GGMMSS.
     * Zwraca sciezke kopii albo pusty string. Kopiujemy, nie przenosimy.
     */
    Q_INVOKABLE QString kopiaZapasowa( const QString &sciezka ) const;

    //! Zapisuje plik projektu na dysk (opakowanie na QgsProject::write).
    Q_INVOKABLE bool zapiszProjekt( QgsProject *projekt ) const;

    /**
     * Czyta plik tekstowy jako UTF-8. Osobny czasownik, bo
     * FileUtils::readFileContent zwraca QByteArray, ktore w QML jest
     * ArrayBufferem — a przepisy maja w sobie polskie znaki i ida przez
     * JSON.parse.
     */
    Q_INVOKABLE QString czytajTekst( const QString &sciezka ) const;

    /**
     * ODWROCENIE INTERPRETERA: czyta wczytany projekt i zwraca przepis.
     *
     * Dzieki temu szablon przestaje byc katalogiem do skopiowania, a staje
     * sie odczytanym opisem dobrego projektu — i dryf znika u zrodla, bo
     * nie ma czego kopiowac. Zwraca mape o ksztalcie, ktory konsumuje
     * QfPrzepis.zastosuj(); do JSON-a zamienia ja QML.
     *
     * Pomija podklady i rastry (to dane, nie struktura) oraz warstwy REF_,
     * ktore zaklada wtyczka. Pola `fid` nie wypisuje — zaklada je GeoPackage.
     */
    Q_INVOKABLE QVariantMap zrzucPrzepis( QgsProject *projekt ) const;

    //! Zapisuje tekst jako UTF-8 (np. workfield_klawisze.json obok projektu).
    Q_INVOKABLE bool zapiszTekst( const QString &sciezka, const QString &tresc ) const;

  private:
    //! Indeks pola albo -1.
    static int indeksPola( const QgsVectorLayer *warstwa, const QString &pole );

    //! Warstwa po nazwie albo po identyfikatorze.
    static QgsVectorLayer *znajdzWarstwe( QgsProject *projekt, const QString &nazwaLubId );

    //! Zaklada tabele stempla, jesli jej nie ma. Zwraca powodzenie.
    static bool zapewnijTabeleStempla( const QString &gpkg );
};

#endif // NARZEDZIAPROJEKTU_H
