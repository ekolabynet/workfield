/***************************************************************************
  zalacznikiutils.cpp - ZalacznikiUtils

 ---------------------
 WorkField: dostep z QML do relacji zalacznikow N:1. Patrz zalacznikiutils.h
 oraz docs/ZALACZNIKI.md.
 ***************************************************************************/

#include "zalacznikiutils.h"

#include <qgsproject.h>
#include <qgsrelation.h>
#include <qgsrelationmanager.h>

ZalacznikiUtils::ZalacznikiUtils( QObject *parent )
  : QObject( parent )
{
}

QString ZalacznikiUtils::polePoNazwie( const QgsVectorLayer *warstwa, const QString &nazwa )
{
  if ( !warstwa )
    return QString();

  const QgsFields pola = warstwa->fields();
  for ( int i = 0; i < pola.count(); ++i )
  {
    if ( pola.at( i ).name().compare( nazwa, Qt::CaseInsensitive ) == 0 )
      return pola.at( i ).name();
  }
  return QString();
}

QVariantMap ZalacznikiUtils::relacjaZalacznikow( QgsVectorLayer *warstwa ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "istnieje" ), false );

  if ( !warstwa || !warstwa->isValid() )
    return wynik;

  QgsProject *projekt = QgsProject::instance();
  if ( !projekt )
    return wynik;

  // Warstwa miewa wiele relacji potomnych, a pole ExternalResource ma nie
  // tylko tabela zalacznikow — w szablonie ZZW ma je takze spis gatunkowy
  // (relacja platy_gatunki). "Pierwsza z brzegu" podpinala wiec zdjecia jako
  // obserwacje gatunkow. Rozstrzyga konwencja nazw: tabela ZAL_<warstwa>.
  QVariantMap zKonwencji;
  QList<QVariantMap> pozostale;

  const QList<QgsRelation> relacje = projekt->relationManager()->referencedRelations( warstwa );
  for ( const QgsRelation &relacja : relacje )
  {
    if ( !relacja.isValid() )
      continue;

    QgsVectorLayer *dziecko = relacja.referencingLayer();
    if ( !dziecko || !dziecko->isValid() )
      continue;

    // Pole zalacznika = pierwsze pole z widgetem ExternalResource. Ten sam
    // warunek stosuje ReferencingFeatureListModel::updateAttachmentFieldInfo,
    // wiec galeria w formularzu i pasek widza to samo pole.
    QString poleSciezki;
    const QgsFields pola = dziecko->fields();
    for ( int i = 0; i < pola.count(); ++i )
    {
      if ( dziecko->editorWidgetSetup( i ).type() == QLatin1String( "ExternalResource" ) )
      {
        poleSciezki = pola.at( i ).name();
        break;
      }
    }
    if ( poleSciezki.isEmpty() )
      continue;

    const QList<QgsRelation::FieldPair> pary = relacja.fieldPairs();
    if ( pary.isEmpty() )
      continue;

    QVariantMap kandydat;
    kandydat.insert( QStringLiteral( "istnieje" ), true );
    kandydat.insert( QStringLiteral( "relacja" ), relacja.id() );
    kandydat.insert( QStringLiteral( "warstwa" ), QVariant::fromValue( static_cast<QObject *>( dziecko ) ) );
    kandydat.insert( QStringLiteral( "poleObce" ), pary.first().referencingField() );
    kandydat.insert( QStringLiteral( "poleRodzica" ), pary.first().referencedField() );
    kandydat.insert( QStringLiteral( "poleSciezki" ), poleSciezki );
    kandydat.insert( QStringLiteral( "poleTypu" ), polePoNazwie( dziecko, QStringLiteral( "TYP" ) ) );
    kandydat.insert( QStringLiteral( "poleUjecia" ), polePoNazwie( dziecko, QStringLiteral( "UJECIE" ) ) );

    if ( czyTabelaZalacznikow( dziecko ) )
    {
      if ( zKonwencji.isEmpty() )
        zKonwencji = kandydat;
    }
    else
    {
      pozostale.append( kandydat );
    }
  }

  // 1. tabela zgodna z konwencja ZAL_<warstwa> — jedyny pewny wybor
  if ( !zKonwencji.isEmpty() )
    return zKonwencji;

  // 2. brak takiej tabeli: bierzemy jedynego kandydata, ale tylko jesli jest
  //    JEDEN. Przy dwoch nie zgadujemy — lepiej nie zapisac nic i powiedziec
  //    o tym glosno, niz wpisac zdjecie do cudzej tabeli.
  if ( pozostale.size() == 1 )
    return pozostale.first();

  return wynik;
}

void ZalacznikiUtils::zazadajZdjecia( QgsVectorLayer *warstwa, const QgsFeature &obiekt )
{
  if ( !warstwa || !obiekt.isValid() )
    return;

  emit zazadanoZdjecia( warstwa, obiekt );
}

bool ZalacznikiUtils::czyTabelaZalacznikow( const QgsVectorLayer *warstwa )
{
  if ( !warstwa )
    return false;

  if ( warstwa->name().startsWith( QLatin1String( "zal_" ), Qt::CaseInsensitive ) )
    return true;

  // nazwa warstwy w projekcie bywa zmieniona; tabela w GeoPackage nie
  return warstwa->source().contains( QLatin1String( "layername=ZAL_" ), Qt::CaseInsensitive );
}

QVariant ZalacznikiUtils::kluczRodzica( QgsVectorLayer *warstwa, const QgsFeature &rodzic ) const
{
  if ( !rodzic.isValid() )
    return QVariant();

  const QVariantMap opis = relacjaZalacznikow( warstwa );
  if ( !opis.value( QStringLiteral( "istnieje" ), false ).toBool() )
    return QVariant();

  const QString pole = opis.value( QStringLiteral( "poleRodzica" ) ).toString();

  // GPKG: klucz glowny to fid. W swiezo zapisanym obiekcie atrybut fid bywa
  // pusty (provider nadal go po zapisie), a prawda siedzi w identyfikatorze.
  if ( pole.compare( QStringLiteral( "fid" ), Qt::CaseInsensitive ) == 0 )
  {
    const QVariant zAtrybutu = rodzic.attribute( pole );
    if ( zAtrybutu.isValid() && !zAtrybutu.isNull() )
      return zAtrybutu;
    return rodzic.id() >= 0 ? QVariant( rodzic.id() ) : QVariant();
  }

  return rodzic.attribute( pole );
}
