#include "tabelamodel.h"

#include <qgsfeature.h>
#include <qgsfeatureiterator.h>
#include <qgsfields.h>
#include <qgsproviderregistry.h>
#include <qgsprovidersublayerdetails.h>
#include <qgsvectorlayer.h>

#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QUrl>
#include <algorithm>

TabelaModel::TabelaModel( QObject *parent )
  : QAbstractTableModel( parent )
{
}

int TabelaModel::rowCount( const QModelIndex &parent ) const
{
  return parent.isValid() ? 0 : mWidoczne.size();
}

int TabelaModel::columnCount( const QModelIndex &parent ) const
{
  return parent.isValid() ? 0 : mNaglowki.size();
}

QVariant TabelaModel::data( const QModelIndex &index, int role ) const
{
  if ( role != Qt::DisplayRole && role != Qt::EditRole )
    return QVariant();
  if ( index.row() < 0 || index.row() >= mWidoczne.size() )
    return QVariant();
  const QVector<QString> &wiersz = mDane.at( mWidoczne.at( index.row() ) );
  if ( index.column() < 0 || index.column() >= wiersz.size() )
    return QVariant();
  return wiersz.at( index.column() );
}

QVariant TabelaModel::headerData( int section, Qt::Orientation orientation, int role ) const
{
  if ( orientation == Qt::Horizontal && role == Qt::DisplayRole
       && section >= 0 && section < mNaglowki.size() )
    return mNaglowki.at( section );
  return QVariant();
}

QStringList TabelaModel::tabeleZPliku( const QString &sciezka )
{
  QStringList nazwy;
  const QFileInfo info( sciezka );
  if ( !info.exists() || !info.isFile() )
    return nazwy;
  if ( info.suffix().compare( QStringLiteral( "csv" ), Qt::CaseInsensitive ) == 0 )
  {
    nazwy << info.completeBaseName();
    return nazwy;
  }
  const QList<QgsProviderSublayerDetails> podwarstwy =
    QgsProviderRegistry::instance()->querySublayers( sciezka );
  for ( const QgsProviderSublayerDetails &p : podwarstwy )
  {
    if ( p.providerKey() == QLatin1String( "ogr" ) && !p.name().isEmpty() )
      nazwy << p.name();
  }
  nazwy.removeDuplicates();
  std::sort( nazwy.begin(), nazwy.end() );
  return nazwy;
}

bool TabelaModel::wczytaj( const QString &sciezka, const QString &tabela )
{
  beginResetModel();
  mNaglowki.clear();
  mDane.clear();
  mWidoczne.clear();
  mSzerokosci.clear();
  mFiltr.clear();
  mKomunikat.clear();
  mSortKolumna = -1;
  mSortMalejaco = false;

  QString uri;
  QString dostawca;
  const QFileInfo info( sciezka );
  if ( info.suffix().compare( QStringLiteral( "csv" ), Qt::CaseInsensitive ) == 0 )
  {
    // wykrycie separatora z pierwszej linii
    QChar separator = QLatin1Char( ',' );
    QFile plik( sciezka );
    if ( plik.open( QIODevice::ReadOnly | QIODevice::Text ) )
    {
      QTextStream strumien( &plik );
      const QString linia = strumien.readLine();
      int sredniki = linia.count( QLatin1Char( ';' ) );
      int przecinki = linia.count( QLatin1Char( ',' ) );
      int tabulatory = linia.count( QLatin1Char( '\t' ) );
      if ( sredniki >= przecinki && sredniki >= tabulatory )
        separator = QLatin1Char( ';' );
      else if ( tabulatory > przecinki )
        separator = QLatin1Char( '\t' );
    }
    uri = QUrl::fromLocalFile( sciezka ).toString()
          + QStringLiteral( "?type=csv&detectTypes=no&geomType=none&delimiter=" )
          + QString::fromLatin1( QUrl::toPercentEncoding( QString( separator ) ) );
    dostawca = QStringLiteral( "delimitedtext" );
  }
  else
  {
    uri = sciezka + QStringLiteral( "|layername=" ) + tabela;
    dostawca = QStringLiteral( "ogr" );
  }

  QgsVectorLayer warstwa( uri, tabela, dostawca );
  if ( !warstwa.isValid() )
  {
    mKomunikat = tr( "Nie udało się otworzyć tabeli %1" ).arg( tabela );
    endResetModel();
    emit zmieniona();
    return false;
  }

  const QgsFields pola = warstwa.fields();
  for ( int i = 0; i < pola.count(); i++ )
    mNaglowki << pola.at( i ).name();

  QgsFeature obiekt;
  QgsFeatureIterator iterator = warstwa.getFeatures();
  while ( iterator.nextFeature( obiekt ) )
  {
    const QgsAttributes atrybuty = obiekt.attributes();
    QVector<QString> wiersz;
    wiersz.reserve( mNaglowki.size() );
    for ( int i = 0; i < mNaglowki.size(); i++ )
    {
      const QVariant w = i < atrybuty.size() ? atrybuty.at( i ) : QVariant();
      wiersz << ( w.isNull() ? QString() : w.toString() );
    }
    mDane << wiersz;
    if ( mDane.size() >= 200000 )
    {
      mKomunikat = tr( "Pokazano pierwsze 200 000 wierszy" );
      break;
    }
  }

  // szerokosci: naglowek + probka do 100 wierszy, w znakach, 6..44
  mSzerokosci.resize( mNaglowki.size() );
  for ( int k = 0; k < mNaglowki.size(); k++ )
  {
    int szer = mNaglowki.at( k ).length();
    const int probka = std::min<int>( mDane.size(), 100 );
    for ( int r = 0; r < probka; r++ )
      szer = std::max<int>( szer, mDane.at( r ).at( k ).length() );
    mSzerokosci[k] = std::min( 44, std::max( 6, szer ) );
  }

  mWidoczne.reserve( mDane.size() );
  for ( int i = 0; i < mDane.size(); i++ )
    mWidoczne << i;
  endResetModel();
  emit zmieniona();
  return true;
}

void TabelaModel::ustawFiltr( const QString &tekst )
{
  mFiltr = tekst.trimmed().toLower();
  przelicz();
}

void TabelaModel::sortuj( int kolumna )
{
  if ( kolumna < 0 || kolumna >= mNaglowki.size() )
    return;
  if ( mSortKolumna == kolumna )
    mSortMalejaco = !mSortMalejaco;
  else
  {
    mSortKolumna = kolumna;
    mSortMalejaco = false;
  }
  przelicz();
}

void TabelaModel::przelicz()
{
  beginResetModel();
  mWidoczne.clear();
  for ( int i = 0; i < mDane.size(); i++ )
  {
    if ( mFiltr.isEmpty() )
    {
      mWidoczne << i;
      continue;
    }
    const QVector<QString> &wiersz = mDane.at( i );
    for ( const QString &komorka : wiersz )
    {
      if ( komorka.toLower().contains( mFiltr ) )
      {
        mWidoczne << i;
        break;
      }
    }
  }
  if ( mSortKolumna >= 0 )
  {
    const int k = mSortKolumna;
    const bool malejaco = mSortMalejaco;
    const QVector<QVector<QString>> &dane = mDane;
    std::stable_sort( mWidoczne.begin(), mWidoczne.end(),
                      [&dane, k, malejaco]( int a, int b ) {
                        const QString &wa = dane.at( a ).at( k );
                        const QString &wb = dane.at( b ).at( k );
                        bool la = false, lb = false;
                        const double da = wa.toDouble( &la );
                        const double db = wb.toDouble( &lb );
                        bool mniejsze;
                        if ( la && lb )
                          mniejsze = da < db;
                        else if ( la != lb )
                          mniejsze = la; // liczby przed tekstem
                        else
                          mniejsze = QString::localeAwareCompare( wa, wb ) < 0;
                        return malejaco ? !mniejsze && ( wa != wb ) : mniejsze;
                      } );
  }
  endResetModel();
  emit zmieniona();
}

int TabelaModel::szerokoscKolumny( int kolumna ) const
{
  return kolumna >= 0 && kolumna < mSzerokosci.size() ? mSzerokosci.at( kolumna ) : 12;
}

QString TabelaModel::nazwaKolumny( int kolumna ) const
{
  return kolumna >= 0 && kolumna < mNaglowki.size() ? mNaglowki.at( kolumna ) : QString();
}

QString TabelaModel::komorka( int wiersz, int kolumna ) const
{
  if ( wiersz < 0 || wiersz >= mWidoczne.size() )
    return QString();
  const QVector<QString> &dane = mDane.at( mWidoczne.at( wiersz ) );
  return kolumna >= 0 && kolumna < dane.size() ? dane.at( kolumna ) : QString();
}
