/**
 * phototagstore.h - WorkField
 * Magazyn tagow zdjec projektu: osobny plik foto_tagi.gpkg obok danych
 * terenowych. Swiadomie NIE dotyka glownego GPKG projektu.
 */
#ifndef PHOTOTAGSTORE_H
#define PHOTOTAGSTORE_H

#include <QObject>
#include <QVariantList>

struct sqlite3;

class PhotoTagStore : public QObject
{
    Q_OBJECT

    Q_PROPERTY( QString author READ author WRITE setAuthor NOTIFY authorChanged )
    Q_PROPERTY( QString storagePath READ storagePath NOTIFY storagePathChanged )

  public:
    explicit PhotoTagStore( QObject *parent = nullptr );
    ~PhotoTagStore() override;

    QString author() const { return mAuthor; }
    void setAuthor( const QString &author );
    QString storagePath() const { return mStoragePath; }

    //! Otwiera (tworzac w razie potrzeby) foto_tagi.gpkg w katalogu projektu.
    Q_INVOKABLE bool open( const QString &projectDir );
    Q_INVOKABLE void close();

    //! Tagi jednego zdjecia (sciezka wzgledna, np. "DCIM/gatunki_....jpg").
    Q_INVOKABLE QVariantList tagsForPhoto( const QString &foto );

    //! Dodaje tag; x,y w 0-1 albo -1 dla tagu calego zdjecia. Zwraca fid albo -1.
    Q_INVOKABLE int addTag( const QString &foto, const QString &tag, double pokrycie = -1, const QString &uwagi = QString(), double x = -1, double y = -1 );

    Q_INVOKABLE bool removeTag( int fid );
    Q_INVOKABLE int tagCount( const QString &foto );

    //! Rozne uzyte dotad tagi - do podpowiedzi.
    Q_INVOKABLE QStringList knownTags();

    //! Tagi wg swiezosci uzycia (najnowsze pierwsze).
    Q_INVOKABLE QStringList recentTags( int limit = 200 );

    //! Czestosc uzycia tagow w calym zbiorze: [{tag, n}], malejaco.
    Q_INVOKABLE QVariantList tagStats( int limit = 500 );

    //! zdjęcia oznaczone danym tagiem (ścieżki względne, bez duplikatów)
    Q_INVOKABLE QStringList photosForTag( const QString &tag );

    //! Gatunki z kolumn gatunek/GATUNEK we wszystkich GPKG projektu (odczyt).
    Q_INVOKABLE QStringList projectSpecies();

    //! Czy plik JPEG ma znacznik EXIF Orientation (True takze dla luster).
    Q_INVOKABLE bool hasExifOrientation( const QString &path ) const;

    /**
     * Przenosi zdjecie do kosza projektu (DCIM/.kosz) i usuwa jego tagi.
     * Swiadomie NIE kasuje pliku - w terenie pomylka jest tania do naprawienia
     * tylko wtedy, gdy plik jeszcze istnieje.
     * Zwraca sciezke w koszu albo pusty ciag przy niepowodzeniu.
     */
    Q_INVOKABLE QString moveToTrash( const QString &path );

    //! Ile zdjec czeka w koszu - do pokazania w interfejsie.
    Q_INVOKABLE int trashCount() const;

    //! Przywraca zdjecie z kosza na pierwotne miejsce.
    Q_INVOKABLE bool restoreFromTrash( const QString &trashPath );

    //! Slownik gatunkow tak, jak widza go formularze: z konfiguracji
    //! widzetu pola "gatunek" (ValueMap/ValueRelation) warstw projektu.
    Q_INVOKABLE QStringList formSpecies();

  signals:
    void authorChanged();
    void storagePathChanged();
    void tagsChanged( const QString &foto );

  private:
    bool ensureSchema();

    sqlite3 *mDb = nullptr;
    QString mProjectDir;
    QStringList mProjectSpecies;
    bool mSpeciesLoaded = false;
    QStringList mFormSpecies;
    bool mFormSpeciesLoaded = false;
    QString mAuthor = QStringLiteral( "workfield" );
    QString mStoragePath;
};

#endif // PHOTOTAGSTORE_H
