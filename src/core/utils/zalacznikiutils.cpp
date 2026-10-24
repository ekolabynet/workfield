/***************************************************************************
  zalacznikiutils.cpp - ZalacznikiUtils

 ---------------------
 WorkField: dostep z QML do relacji zalacznikow N:1. Patrz zalacznikiutils.h
 oraz docs/ZALACZNIKI.md.
 ***************************************************************************/

#include "zalacznikiutils.h"

#include <qgsfeatureiterator.h>
#include <qgsfeaturerequest.h>
#include <qgsproject.h>
#include <qgsrelation.h>
#include <qgsrelationmanager.h>
#include <qgsvariantutils.h>

#include "featureidentity.h" // [WF-PHOTO-NAMING]

#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

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

QVariantMap ZalacznikiUtils::photoIndex( QgsProject *project ) const
{
  QVariantMap index;
  if ( !project )
    return index;

  const QMap<QString, QgsMapLayer *> layers = project->mapLayers();
  for ( QgsMapLayer *mapLayer : layers )
  {
    QgsVectorLayer *parent = qobject_cast<QgsVectorLayer *>( mapLayer );
    if ( !parent || !parent->isValid() )
      continue;

    const QVariantMap description = relacjaZalacznikow( parent );
    if ( !description.value( QStringLiteral( "istnieje" ), false ).toBool() )
      continue;

    QgsVectorLayer *child = qobject_cast<QgsVectorLayer *>( description.value( QStringLiteral( "warstwa" ) ).value<QObject *>() );
    if ( !child || !child->isValid() )
      continue;

    const int pathIndex = child->fields().lookupField( description.value( QStringLiteral( "poleSciezki" ) ).toString() );
    const int keyIndex = child->fields().lookupField( description.value( QStringLiteral( "poleObce" ) ).toString() );
    const int parentUuidIndex = child->fields().lookupField( QStringLiteral( "PARENT_UUID" ) );
    if ( pathIndex < 0 )
      continue;

    QgsAttributeList wanted { pathIndex };
    if ( keyIndex >= 0 )
      wanted << keyIndex;
    if ( parentUuidIndex >= 0 )
      wanted << parentUuidIndex;

    QgsFeatureRequest request;
    request.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
    request.setSubsetOfAttributes( wanted );
    QgsFeatureIterator it = child->getFeatures( request );
    QgsFeature feature;
    while ( it.nextFeature( feature ) )
    {
      QString path = feature.attribute( pathIndex ).toString().trimmed();
      if ( path.isEmpty() )
        continue;
      path.replace( QLatin1Char( '\\' ), QLatin1Char( '/' ) );
      while ( path.startsWith( QLatin1String( "./" ) ) )
        path = path.mid( 2 );

      QVariantMap entry;
      entry.insert( QStringLiteral( "layer" ), parent->name() );
      entry.insert( QStringLiteral( "key" ), keyIndex >= 0 ? feature.attribute( keyIndex ) : QVariant() );
      if ( parentUuidIndex >= 0 )
        entry.insert( QStringLiteral( "parentUuid" ), feature.attribute( parentUuidIndex ) );
      index.insert( path, entry );
    }
  }
  return index;
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

// ===========================================================================
// [WF-PHOTO-NAMING] 24.10.2026 — one photo naming convention for the whole app
// ===========================================================================
// Decisions: claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md, section 5.
// The name of a photo file is for people; the link to the object lives in the
// ZAL_ table. So the convention is a setting: an application default
// (QSettings WorkField/photoNaming) and an optional override in the project
// (project variable workfield_photo_naming). Both hold the same JSON:
//   { "layer": true, "number": true, "note": false,
//     "folder": "object" | "layer" | "day" | "flat", "ascii": true }
// Date and time with milliseconds are ALWAYS in the name — they keep it unique.
// The default reproduces the convention used so far (Mapit compatible):
//   DCIM/<layer>_<number>/<layer>_<number>_<yyyyMMdd_HHmmss_zzz>.<ext>
// Folders are one level deep: the project gallery scans exactly one level.
namespace
{
  QVariantMap defaultPhotoNaming()
  {
    QVariantMap naming;
    naming.insert( QStringLiteral( "layer" ), true );
    naming.insert( QStringLiteral( "number" ), true );
    naming.insert( QStringLiteral( "note" ), false );
    naming.insert( QStringLiteral( "folder" ), QStringLiteral( "object" ) );
    naming.insert( QStringLiteral( "ascii" ), true );
    return naming;
  }

  //! Missing keys take the default; unknown values fall back to it too.
  QVariantMap completePhotoNaming( const QVariantMap &given )
  {
    QVariantMap naming = defaultPhotoNaming();
    for ( auto it = given.constBegin(); it != given.constEnd(); ++it )
      naming.insert( it.key(), it.value() );
    const QString folder = naming.value( QStringLiteral( "folder" ) ).toString();
    if ( folder != QLatin1String( "object" ) && folder != QLatin1String( "layer" ) && folder != QLatin1String( "day" ) && folder != QLatin1String( "flat" ) )
      naming.insert( QStringLiteral( "folder" ), QStringLiteral( "object" ) );
    return naming;
  }

  QVariantMap parsePhotoNaming( const QString &json )
  {
    if ( json.trimmed().isEmpty() )
      return QVariantMap();
    const QJsonDocument document = QJsonDocument::fromJson( json.toUtf8() );
    return document.isObject() ? document.object().toVariantMap() : QVariantMap();
  }

  //! A safe piece of a file name: no path separators, no spaces; with
  //! \a ascii also no Polish letters (Windows, ZIP and CAD tools choke on them).
  QString photoNamePart( const QString &text, bool ascii )
  {
    static const QString from = QStringLiteral( "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ" );
    static const QString to = QStringLiteral( "acelnoszzACELNOSZZ" );
    QString result;
    for ( const QChar c : text.trimmed() )
    {
      const int polish = from.indexOf( c );
      if ( ascii && polish >= 0 )
        result += to.at( polish );
      else if ( c.isLetterOrNumber() && ( !ascii || c.unicode() < 128 ) )
        result += c;
      else if ( c == QLatin1Char( '-' ) )
        result += c;
      else
        result += QLatin1Char( '_' );
    }
    while ( result.contains( QLatin1String( "__" ) ) )
      result.replace( QLatin1String( "__" ), QLatin1String( "_" ) );
    while ( result.startsWith( QLatin1Char( '_' ) ) )
      result.remove( 0, 1 );
    while ( result.endsWith( QLatin1Char( '_' ) ) )
      result.chop( 1 );
    return result;
  }

  /**
   * The number of an object, the same rule as the header of the form
   * ([WF-OBJECT-NUMBER-SETTING]): the field chosen for the layer, else the
   * application default (NR when filled, else fid). An object not saved yet
   * has no fid — then the first 8 characters of its uuid, else "nowy".
   */
  QString photoObjectNumber( QgsVectorLayer *layer, const QgsFeature &feature )
  {
    QSettings settings;
    const QString perLayer = layer ? layer->customProperty( QStringLiteral( "workfield/objectNumberField" ) ).toString() : QString();
    const QString choice = !perLayer.isEmpty() ? perLayer : settings.value( QStringLiteral( "WorkField/objectNumberDefault" ), QStringLiteral( "auto" ) ).toString();

    if ( choice != QLatin1String( "fid" ) && feature.isValid() )
    {
      const QString wanted = choice == QLatin1String( "auto" ) ? QStringLiteral( "NR" ) : choice;
      const int index = FeatureIdentity::fieldIndex( feature.fields(), wanted );
      if ( index >= 0 )
      {
        const QVariant value = feature.attribute( index );
        if ( !QgsVariantUtils::isNull( value ) && !value.toString().trimmed().isEmpty() )
          return value.toString();
      }
    }
    if ( feature.id() >= 0 )
      return QString::number( feature.id() );

    const int uuidIndex = FeatureIdentity::uuidFieldIndex( feature.fields() );
    if ( uuidIndex >= 0 )
    {
      QString uuid = feature.attribute( uuidIndex ).toString();
      uuid.remove( QLatin1Char( '{' ) ).remove( QLatin1Char( '}' ) );
      if ( !uuid.isEmpty() )
        return uuid.left( 8 );
    }
    return QStringLiteral( "nowy" );
  }

  QString photoNote( const QgsFeature &feature )
  {
    // the first of these fields that the layer has and that is filled
    for ( const QString &name : { QStringLiteral( "Uwagi" ), QStringLiteral( "Opis" ), QStringLiteral( "Notatka" ), QStringLiteral( "Komentarz" ), QStringLiteral( "Description" ) } )
    {
      const int index = FeatureIdentity::fieldIndex( feature.fields(), name );
      if ( index < 0 )
        continue;
      const QVariant value = feature.attribute( index );
      if ( !QgsVariantUtils::isNull( value ) && !value.toString().trimmed().isEmpty() )
        return value.toString().trimmed().left( 24 );
    }
    return QString();
  }

  QString buildPhotoPath( const QVariantMap &naming, const QString &layerName, const QString &number, const QString &note, const QDateTime &when )
  {
    const bool ascii = naming.value( QStringLiteral( "ascii" ), true ).toBool();
    const QString layerPart = photoNamePart( layerName, ascii );
    const QString numberPart = photoNamePart( number, ascii );
    const QString notePart = photoNamePart( note, ascii );

    QStringList parts;
    if ( naming.value( QStringLiteral( "layer" ), true ).toBool() && !layerPart.isEmpty() )
      parts << layerPart;
    if ( naming.value( QStringLiteral( "number" ), true ).toBool() && !numberPart.isEmpty() )
      parts << numberPart;
    if ( naming.value( QStringLiteral( "note" ), false ).toBool() && !notePart.isEmpty() )
      parts << notePart;
    parts << when.toString( QStringLiteral( "yyyyMMdd_HHmmss_zzz" ) );

    const QString folder = naming.value( QStringLiteral( "folder" ) ).toString();
    QString directory = QStringLiteral( "DCIM/" );
    if ( folder == QLatin1String( "object" ) )
      directory += ( layerPart.isEmpty() ? QStringLiteral( "obiekty" ) : layerPart ) + QLatin1Char( '_' ) + ( numberPart.isEmpty() ? QStringLiteral( "nowy" ) : numberPart ) + QLatin1Char( '/' );
    else if ( folder == QLatin1String( "layer" ) )
      directory += ( layerPart.isEmpty() ? QStringLiteral( "obiekty" ) : layerPart ) + QLatin1Char( '/' );
    else if ( folder == QLatin1String( "day" ) )
      directory += when.toString( QStringLiteral( "yyyy-MM-dd" ) ) + QLatin1Char( '/' );

    return directory + parts.join( QLatin1Char( '_' ) ) + QStringLiteral( ".{extension}" );
  }
} // namespace

QVariantMap ZalacznikiUtils::photoNaming( QgsProject *project ) const
{
  QVariantMap result;
  const QVariantMap inProject = project ? parsePhotoNaming( project->customVariables().value( QStringLiteral( "workfield_photo_naming" ) ).toString() ) : QVariantMap();
  QSettings settings;
  const QVariantMap inApp = parsePhotoNaming( settings.value( QStringLiteral( "WorkField/photoNaming" ) ).toString() );

  if ( !inProject.isEmpty() )
  {
    result = completePhotoNaming( inProject );
    result.insert( QStringLiteral( "source" ), QStringLiteral( "project" ) );
  }
  else if ( !inApp.isEmpty() )
  {
    result = completePhotoNaming( inApp );
    result.insert( QStringLiteral( "source" ), QStringLiteral( "app" ) );
  }
  else
  {
    result = defaultPhotoNaming();
    result.insert( QStringLiteral( "source" ), QStringLiteral( "default" ) );
  }
  return result;
}

QString ZalacznikiUtils::photoPath( QgsProject *project, QgsVectorLayer *layer, const QVariant &featureValue ) const
{
  // QML passes null when the bar has no object yet (distant mode)
  const QgsFeature feature = featureValue.userType() == qMetaTypeId<QgsFeature>() ? featureValue.value<QgsFeature>() : QgsFeature();
  const QVariantMap naming = photoNaming( project );
  return buildPhotoPath( naming,
                         layer ? layer->name() : QString(),
                         photoObjectNumber( layer, feature ),
                         photoNote( feature ),
                         QDateTime::currentDateTime() );
}

QString ZalacznikiUtils::photoPathExample( const QVariantMap &naming ) const
{
  return buildPhotoPath( completePhotoNaming( naming ), QStringLiteral( "Zraszacze" ), QStringLiteral( "104" ), QStringLiteral( "przy murku, ślad wycieku" ), QDateTime::currentDateTime() )
    .replace( QStringLiteral( "{extension}" ), QStringLiteral( "jpg" ) );
}
