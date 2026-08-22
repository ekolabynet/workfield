/***************************************************************************
  zalacznikiutils.h - ZalacznikiUtils

 ---------------------
 WorkField: dostep z QML do relacji zalacznikow N:1 (tabele ZAL_<warstwa>).

 QGIS-owy menedzer relacji nie jest wystawiony do QML, a pasek szybkiego
 przechwytu musi wiedziec, ktora tabela jest tabela zalacznikow danej warstwy
 i jakim kluczem sie do niej wchodzi. Ta klasa odpowiada na oba pytania i nic
 wiecej nie robi — sam zapis idzie przez QfFeatureModel, zeby zalacznik
 przechodzil ta sama droga co kazdy inny obiekt (bufor edycji, flusher GPKG,
 delty chmury, historia).

 Patrz docs/ZALACZNIKI.md.
 ***************************************************************************/

#ifndef ZALACZNIKIUTILS_H
#define ZALACZNIKIUTILS_H

#include <QObject>
#include <QVariantMap>
#include <qgsfeature.h>
#include <qgsvectorlayer.h>

/**
 * \ingroup core
 */
class ZalacznikiUtils : public QObject
{
    Q_OBJECT

  public:
    explicit ZalacznikiUtils( QObject *parent = nullptr );

    /**
     * Opisuje relacje zalacznikow warstwy \a warstwa.
     *
     * Kandydatem jest kazda relacja, w ktorej \a warstwa jest rodzicem, a
     * warstwa-dziecko ma pole z widgetem ExternalResource — ten sam warunek,
     * po ktorym formularz podmienia edytor relacji na galerie
     * (attributeformmodelbase.cpp). Kandydatow bywa jednak wiecej niz jeden:
     * w szablonie ZZW pole FOTO ma takze spis gatunkowy. Rozstrzygamy wiec
     * konwencja nazw — wygrywa tabela ZAL_<warstwa>. Gdy takiej nie ma,
     * bierzemy jedynego kandydata; przy kilku nie zgadujemy i zwracamy brak.
     *
     * Zwraca mape:
     *   istnieje    bool            czy warstwa ma zalaczniki
     *   relacja     QString         identyfikator relacji
     *   warstwa     QgsVectorLayer* warstwa-dziecko (tabela ZAL_*)
     *   poleObce    QString         pole klucza obcego w dziecku
     *   poleRodzica QString         pole rodzica, na ktore wskazuje klucz obcy
     *   poleSciezki QString         pole ExternalResource w dziecku
     *   poleTypu    QString         pole TYP, jesli jest (inaczej puste)
     *   poleUjecia  QString         pole UJECIE, jesli jest (inaczej puste)
     *
     * Przy braku relacji zwraca mape z istnieje == false.
     */
    Q_INVOKABLE QVariantMap relacjaZalacznikow( QgsVectorLayer *warstwa ) const;

    /**
     * Zwraca wartosc klucza, ktorym obiekt \a rodzic wchodzi do swojej tabeli
     * zalacznikow (zwykle fid). Nieprawidlowy QVariant, gdy warstwa nie ma
     * relacji zalacznikow albo obiekt jest nieprawidlowy.
     */
    Q_INVOKABLE QVariant kluczRodzica( QgsVectorLayer *warstwa, const QgsFeature &rodzic ) const;

    /**
     * Prosi o zrobienie zdjecia i podpiecie go jako zalacznik obiektu
     * \a obiekt z warstwy \a warstwa.
     *
     * Most miedzy naglowkiem formularza a paskiem szybkiego przechwytu.
     * QfNavigationBar.qml siedzi w innym komponencie QML niz pasek i nie ma
     * jak go zawolac po id; ta klasa jest singletonem, wiec widza ja obie
     * strony. Sama nic nie robi — tylko rozglasza zadanie.
     */
    Q_INVOKABLE void zazadajZdjecia( QgsVectorLayer *warstwa, const QgsFeature &obiekt );

  signals:
    //! Ktos poprosil o zdjecie-zalacznik dla istniejacego obiektu
    void zazadanoZdjecia( QgsVectorLayer *warstwa, const QgsFeature &obiekt );

  private:
    //! Nazwa pierwszego pola o podanej nazwie (bez wzgledu na wielkosc liter)
    static QString polePoNazwie( const QgsVectorLayer *warstwa, const QString &nazwa );

    //! Czy warstwa wyglada na tabele zalacznikow (konwencja ZAL_<warstwa>)
    static bool czyTabelaZalacznikow( const QgsVectorLayer *warstwa );
};

#endif // ZALACZNIKIUTILS_H
