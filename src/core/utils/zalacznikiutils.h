/***************************************************************************
  zalacznikiutils.h - ZalacznikiUtils

 ---------------------
 WorkField: dostep z QML do relacji zalacznikow N:1 (tabele ZAL_<warstwa>).

 QGIS-owy menedzer relacji nie jest wystawiony do QML, a pasek szybkiego
 przechwytu musi wiedziec, ktora tabela jest tabela zalacznikow danej warstwy
 i jakim kluczem sie do niej wchodzi. Ta klasa odpowiada na oba pytania i nic
 wiecej nie robi — sam zapis idzie przez FeatureModel, zeby zalacznik
 przechodzil ta sama droga co kazdy inny obiekt (bufor edycji, flusher GPKG,
 delty chmury, historia).

 Patrz docs/ZALACZNIKI.md.
 ***************************************************************************/

#ifndef ZALACZNIKIUTILS_H
#define ZALACZNIKIUTILS_H

#include <QObject>
#include <QVariantMap>
#include <qgsfeature.h>
#include <qgsproject.h>     // [WF-GALLERY-FROM-TABLES]
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
     * NavigationBar.qml siedzi w innym komponencie QML niz pasek i nie ma
     * jak go zawolac po id; ta klasa jest singletonem, wiec widza ja obie
     * strony. Sama nic nie robi — tylko rozglasza zadanie.
     */
    Q_INVOKABLE void zazadajZdjecia( QgsVectorLayer *warstwa, const QgsFeature &obiekt );

    /**
     * WorkField 24.10.2026 [WF-GALLERY-FROM-TABLES] — which object each photo
     * belongs to, read from the attachment tables of \a project.
     *
     * Key: the path as stored in the table (relative to the project, "/" as
     * separator, without a leading "./"). Value: { layer: name of the parent
     * layer, key: value of the foreign key (usually fid), parentUuid: the
     * PARENT_UUID when the table has it }.
     *
     * The file name is for people and may follow any convention; the link is
     * in the table. The gallery uses the name only for files no table knows.
     */
    Q_INVOKABLE QVariantMap photoIndex( QgsProject *project ) const;

    /**
     * WorkField 24.10.2026 [WF-PHOTO-NAMING] — the photo naming convention in
     * force for \a project: the project override (project variable
     * workfield_photo_naming), else the application default (QSettings
     * WorkField/photoNaming), else the built-in default. Keys: layer, number,
     * note (bool), folder ("object" | "layer" | "day" | "flat"), ascii (bool)
     * and source ("project" | "app" | "default").
     */
    Q_INVOKABLE QVariantMap photoNaming( QgsProject *project ) const;

    /**
     * WorkField 24.10.2026 [WF-PHOTO-NAMING] — the path, relative to the
     * project, for a new photo of \a feature from \a layer, e.g.
     * "DCIM/Zraszacze_104/Zraszacze_104_20261024_103130_207.{extension}".
     * The caller replaces {extension} and keeps the name unique on disk.
     * Used by the quick capture bar and the gallery in the form — one rule.
     * \a feature is a QgsFeature, or null when there is no object yet.
     */
    Q_INVOKABLE QString photoPath( QgsProject *project, QgsVectorLayer *layer, const QVariant &feature ) const;

    //! [WF-PHOTO-NAMING] An example file name for \a naming, for the settings page.
    Q_INVOKABLE QString photoPathExample( const QVariantMap &naming ) const;

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
