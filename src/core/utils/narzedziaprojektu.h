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
     * Przenosi warstwe do grupy w drzewie warstw, zakladajac grupe w razie
     * potrzeby. Grupy sluza do chowania tabel pomocniczych (Zalaczniki,
     * Slowniki), zeby nie zasmiecaly panelu w terenie.
     */
    Q_INVOKABLE bool doGrupy( QgsProject *projekt, QgsMapLayer *warstwa, const QString &grupa, bool zwinieta = true, bool widoczna = false ) const;

    //! Warstwa projektu po nazwie; nullptr, gdy nie ma.
    Q_INVOKABLE QgsVectorLayer *warstwaPoNazwie( QgsProject *projekt, const QString &nazwa ) const;

    /**
     * Dosypuje tabele z innego GeoPackage (slowniki gatunkow, taksony,
     * wskazniki). Nie rusza tabel, ktore juz sa. Zwraca liczbe skopiowanych.
     */
    Q_INVOKABLE int dosypTabele( const QString &zrodloGpkg, const QString &celGpkg, const QStringList &tabele ) const;

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
