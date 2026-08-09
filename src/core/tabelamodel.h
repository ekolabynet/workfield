/**
 * tabelamodel.h - przegladarka tabel danych (WorkField)
 * Model tabeli dla QML TableView: czyta tabele GPKG (przez OGR) oraz
 * pliki CSV (provider delimitedtext), z filtrem pelnotekstowym
 * i sortowaniem swiadomym liczb. Dane trzymane w pamieci (odczyt).
 */
#pragma once

#include <QAbstractTableModel>
#include <QStringList>
#include <QVector>

class TabelaModel : public QAbstractTableModel
{
    Q_OBJECT

    Q_PROPERTY( int liczbaWierszy READ liczbaWierszy NOTIFY zmieniona )
    Q_PROPERTY( int liczbaWszystkich READ liczbaWszystkich NOTIFY zmieniona )
    Q_PROPERTY( int liczbaKolumn READ liczbaKolumn NOTIFY zmieniona )
    Q_PROPERTY( QString komunikat READ komunikat NOTIFY zmieniona )
    Q_PROPERTY( int kolumnaSortowania READ kolumnaSortowania NOTIFY zmieniona )
    Q_PROPERTY( bool sortMalejaco READ sortMalejaco NOTIFY zmieniona )

  public:
    explicit TabelaModel( QObject *parent = nullptr );

    int rowCount( const QModelIndex &parent = QModelIndex() ) const override;
    int columnCount( const QModelIndex &parent = QModelIndex() ) const override;
    QVariant data( const QModelIndex &index, int role = Qt::DisplayRole ) const override;
    QVariant headerData( int section, Qt::Orientation orientation, int role = Qt::DisplayRole ) const override;

    //! Nazwy tabel w pliku GPKG; dla CSV zwraca jedna pozycje (nazwe pliku).
    Q_INVOKABLE QStringList tabeleZPliku( const QString &sciezka );
    //! Wczytuje tabele do pamieci. Zwraca false i ustawia komunikat przy bledzie.
    Q_INVOKABLE bool wczytaj( const QString &sciezka, const QString &tabela );
    Q_INVOKABLE void ustawFiltr( const QString &tekst );
    //! Klik w naglowek: pierwszy raz rosnaco, drugi malejaco.
    Q_INVOKABLE void sortuj( int kolumna );
    //! Szerokosc kolumny w znakach (naglowek + probka wierszy), 6..44.
    Q_INVOKABLE int szerokoscKolumny( int kolumna ) const;
    Q_INVOKABLE QString nazwaKolumny( int kolumna ) const;
    Q_INVOKABLE QString komorka( int wiersz, int kolumna ) const;

    int liczbaWierszy() const { return mWidoczne.size(); }
    int liczbaWszystkich() const { return mDane.size(); }
    int liczbaKolumn() const { return mNaglowki.size(); }
    QString komunikat() const { return mKomunikat; }
    int kolumnaSortowania() const { return mSortKolumna; }
    bool sortMalejaco() const { return mSortMalejaco; }

  signals:
    void zmieniona();

  private:
    void przelicz();

    QStringList mNaglowki;
    QVector<QVector<QString>> mDane;
    QVector<int> mWidoczne;
    QVector<int> mSzerokosci;
    QString mFiltr;
    QString mKomunikat;
    int mSortKolumna = -1;
    bool mSortMalejaco = false;
};
