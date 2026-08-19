/***************************************************************************
  narzedziaprojektu.cpp - NarzedziaProjektu

 ---------------------
 WorkField: czasowniki do budowania i doposazania projektu, wystawione do QML.
 Patrz narzedziaprojektu.h i docs/WYPOSAZENIE.md.
 ***************************************************************************/

#include "narzedziaprojektu.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>

#include <qgscoordinatereferencesystem.h>
#include <qgsprojectmetadata.h>

#include <qgsabstractgeometry.h>
#include <qgsattributeeditorcontainer.h>
#include <qgsattributeeditorfield.h>
#include <qgsattributeeditorrelation.h>
#include <qgsdefaultvalue.h>
#include <qgseditformconfig.h>
#include <qgseditorwidgetsetup.h>
#include <qgsexpressioncontextutils.h>
#include <qgsfieldconstraints.h>
#include <qgsgeometry.h>
#include <qgslayertree.h>
#include <qgslayertreegroup.h>
#include <qgsrelation.h>
#include <qgsrelationcontext.h>
#include <qgsrelationmanager.h>
#include <qgssnappingconfig.h>
#include <qgswkbtypes.h>

#include <gdal.h>
#include <ogr_api.h>

NarzedziaProjektu::NarzedziaProjektu( QObject *parent )
  : QObject( parent )
{
}

// ---------------------------------------------------------------------- pomoce

int NarzedziaProjektu::indeksPola( const QgsVectorLayer *warstwa, const QString &pole )
{
  if ( !warstwa )
    return -1;

  return warstwa->fields().lookupField( pole );
}

QgsVectorLayer *NarzedziaProjektu::znajdzWarstwe( QgsProject *projekt, const QString &nazwaLubId )
{
  if ( !projekt || nazwaLubId.isEmpty() )
    return nullptr;

  if ( QgsVectorLayer *warstwa = qobject_cast<QgsVectorLayer *>( projekt->mapLayer( nazwaLubId ) ) )
    return warstwa;

  const QList<QgsMapLayer *> znalezione = projekt->mapLayersByName( nazwaLubId );
  for ( QgsMapLayer *kandydat : znalezione )
  {
    if ( QgsVectorLayer *warstwa = qobject_cast<QgsVectorLayer *>( kandydat ) )
      return warstwa;
  }

  return nullptr;
}

QgsVectorLayer *NarzedziaProjektu::warstwaPoNazwie( QgsProject *projekt, const QString &nazwa ) const
{
  return znajdzWarstwe( projekt ? projekt : QgsProject::instance(), nazwa );
}

// ------------------------------------------------------------- pola i formularz

bool NarzedziaProjektu::alias( QgsVectorLayer *warstwa, const QString &pole, const QString &tekst ) const
{
  const int indeks = indeksPola( warstwa, pole );
  if ( indeks < 0 )
    return false;

  warstwa->setFieldAlias( indeks, tekst );
  return true;
}

bool NarzedziaProjektu::widget( QgsVectorLayer *warstwa, const QString &pole, const QString &typ, const QVariantMap &opcje ) const
{
  const int indeks = indeksPola( warstwa, pole );
  if ( indeks < 0 )
    return false;

  warstwa->setEditorWidgetSetup( indeks, QgsEditorWidgetSetup( typ, opcje ) );
  return true;
}

bool NarzedziaProjektu::wartoscDomyslna( QgsVectorLayer *warstwa, const QString &pole, const QString &wyrazenie, bool przyAktualizacji ) const
{
  const int indeks = indeksPola( warstwa, pole );
  if ( indeks < 0 )
    return false;

  warstwa->setDefaultValueDefinition( indeks, QgsDefaultValue( wyrazenie, przyAktualizacji ) );
  return true;
}

bool NarzedziaProjektu::ograniczenieMiekkie( QgsVectorLayer *warstwa, const QString &pole, const QString &wyrazenie, const QString &opis ) const
{
  const int indeks = indeksPola( warstwa, pole );
  if ( indeks < 0 )
    return false;

  warstwa->setConstraintExpression( indeks, wyrazenie, opis );
  warstwa->setFieldConstraint( indeks, QgsFieldConstraints::ConstraintExpression, QgsFieldConstraints::ConstraintStrengthSoft );
  return true;
}

bool NarzedziaProjektu::wyrazenieWyswietlania( QgsVectorLayer *warstwa, const QString &wyrazenie ) const
{
  if ( !warstwa )
    return false;

  warstwa->setDisplayExpression( wyrazenie );
  return true;
}

bool NarzedziaProjektu::ukladFormularza( QgsVectorLayer *warstwa, const QVariantList &zakladki ) const
{
  if ( !warstwa || zakladki.isEmpty() )
    return false;

  QgsEditFormConfig konfiguracja = warstwa->editFormConfig();
  konfiguracja.setLayout( Qgis::AttributeFormLayout::DragAndDrop );

  QgsAttributeEditorContainer *korzen = konfiguracja.invisibleRootContainer();
  korzen->clear();

  for ( const QVariant &wpis : zakladki )
  {
    const QVariantMap opis = wpis.toMap();
    const QString tytul = opis.value( QStringLiteral( "tytul" ) ).toString();
    if ( tytul.isEmpty() )
      continue;

    QgsAttributeEditorContainer *zakladka = new QgsAttributeEditorContainer( tytul, korzen );
    zakladka->setIsGroupBox( false );

    const QString idRelacji = opis.value( QStringLiteral( "relacja" ) ).toString();
    if ( !idRelacji.isEmpty() )
    {
      // Zakladka relacji — galeria zalacznikow albo spis gatunkowy.
      QgsAttributeEditorRelation *element = new QgsAttributeEditorRelation( idRelacji, zakladka );
      element->setLabel( tytul );
      zakladka->addChildElement( element );
    }
    else
    {
      const QStringList pola = opis.value( QStringLiteral( "pola" ) ).toStringList();
      for ( const QString &pole : pola )
      {
        const int indeks = indeksPola( warstwa, pole );
        if ( indeks < 0 )
          continue; // przepis bywa szerszy niz warstwa — to nie jest blad

        zakladka->addChildElement( new QgsAttributeEditorField( pole, indeks, zakladka ) );
      }
    }

    korzen->addChildElement( zakladka );
  }

  warstwa->setEditFormConfig( konfiguracja );
  return true;
}

bool NarzedziaProjektu::bezPotwierdzenia( QgsVectorLayer *warstwa ) const
{
  if ( !warstwa )
    return false;

  QgsEditFormConfig konfiguracja = warstwa->editFormConfig();
  konfiguracja.setSuppress( Qgis::AttributeFormSuppression::On );
  warstwa->setEditFormConfig( konfiguracja );
  return true;
}

// ----------------------------------------------------------------------- relacje

QString NarzedziaProjektu::relacja( QgsProject *projekt, const QVariantMap &opis ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
    return QString();

  const QString identyfikator = opis.value( QStringLiteral( "id" ) ).toString();
  if ( identyfikator.isEmpty() )
    return QString();

  // Idempotencja: relacja o tym samym identyfikatorze nie powstaje drugi raz.
  if ( p->relationManager()->relation( identyfikator ).isValid() )
    return identyfikator;

  QgsVectorLayer *rodzic = znajdzWarstwe( p, opis.value( QStringLiteral( "rodzic" ) ).toString() );
  QgsVectorLayer *dziecko = znajdzWarstwe( p, opis.value( QStringLiteral( "dziecko" ) ).toString() );
  if ( !rodzic || !dziecko )
    return QString();

  const QString poleDziecka = opis.value( QStringLiteral( "poleDziecka" ) ).toString();
  const QString poleRodzica = opis.value( QStringLiteral( "poleRodzica" ), QStringLiteral( "fid" ) ).toString();
  if ( poleDziecka.isEmpty() )
    return QString();

  QgsRelationContext kontekst( p );
  QgsRelation relacja( kontekst );
  relacja.setId( identyfikator );
  relacja.setName( opis.value( QStringLiteral( "nazwa" ), identyfikator ).toString() );
  relacja.setReferencingLayer( dziecko->id() );
  relacja.setReferencedLayer( rodzic->id() );
  relacja.addFieldPair( poleDziecka, poleRodzica );
  relacja.setStrength( opis.value( QStringLiteral( "kompozycja" ), true ).toBool()
                         ? Qgis::RelationshipStrength::Composition
                         : Qgis::RelationshipStrength::Association );

  if ( !relacja.isValid() )
    return QString();

  p->relationManager()->addRelation( relacja );
  return identyfikator;
}

// ----------------------------------------------------------------------- projekt

bool NarzedziaProjektu::wlasciwosc( QgsProject *projekt, const QString &grupa, const QString &klucz, const QVariant &wartosc ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || grupa.isEmpty() || klucz.isEmpty() )
    return false;

  const QString sciezka = klucz.startsWith( '/' ) ? klucz : QStringLiteral( "/%1" ).arg( klucz );

  switch ( wartosc.userType() )
  {
    case QMetaType::Bool:
      return p->writeEntry( grupa, sciezka, wartosc.toBool() );
    case QMetaType::Int:
    case QMetaType::UInt:
    case QMetaType::LongLong:
      return p->writeEntry( grupa, sciezka, wartosc.toInt() );
    case QMetaType::Double:
      return p->writeEntry( grupa, sciezka, wartosc.toDouble() );
    case QMetaType::QStringList:
    case QMetaType::QVariantList:
      return p->writeEntry( grupa, sciezka, wartosc.toStringList() );
    default:
      return p->writeEntry( grupa, sciezka, wartosc.toString() );
  }
}

QVariant NarzedziaProjektu::czytajWlasciwosc( QgsProject *projekt, const QString &grupa, const QString &klucz ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
    return QVariant();

  const QString sciezka = klucz.startsWith( '/' ) ? klucz : QStringLiteral( "/%1" ).arg( klucz );

  bool jest = false;
  const QString tekst = p->readEntry( grupa, sciezka, QString(), &jest );
  if ( jest )
    return tekst;

  const QStringList lista = p->readListEntry( grupa, sciezka, QStringList(), &jest );
  if ( jest )
    return lista;

  const int liczba = p->readNumEntry( grupa, sciezka, 0, &jest );
  if ( jest )
    return liczba;

  return QVariant();
}

bool NarzedziaProjektu::zmiennaProjektu( QgsProject *projekt, const QString &nazwa, const QVariant &wartosc ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || nazwa.isEmpty() )
    return false;

  QgsExpressionContextUtils::setProjectVariable( p, nazwa, wartosc );
  return true;
}

bool NarzedziaProjektu::wlasciwoscWarstwy( QgsMapLayer *warstwa, const QString &klucz, const QVariant &wartosc ) const
{
  if ( !warstwa || klucz.isEmpty() )
    return false;

  warstwa->setCustomProperty( klucz, wartosc );
  return true;
}

bool NarzedziaProjektu::przyciaganie( QgsProject *projekt, const QVariantMap &ustawienia ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
    return false;

  QgsSnappingConfig konfiguracja = p->snappingConfig();

  if ( ustawienia.contains( QStringLiteral( "wlaczone" ) ) )
    konfiguracja.setEnabled( ustawienia.value( QStringLiteral( "wlaczone" ) ).toBool() );

  if ( ustawienia.contains( QStringLiteral( "tryb" ) ) )
    konfiguracja.setMode( static_cast<Qgis::SnappingMode>( ustawienia.value( QStringLiteral( "tryb" ) ).toInt() ) );

  if ( ustawienia.contains( QStringLiteral( "typ" ) ) )
    konfiguracja.setTypeFlag( static_cast<Qgis::SnappingTypes>( ustawienia.value( QStringLiteral( "typ" ) ).toInt() ) );

  if ( ustawienia.contains( QStringLiteral( "tolerancja" ) ) )
    konfiguracja.setTolerance( ustawienia.value( QStringLiteral( "tolerancja" ) ).toDouble() );

  if ( ustawienia.contains( QStringLiteral( "jednostka" ) ) )
    konfiguracja.setUnits( static_cast<Qgis::MapToolUnit>( ustawienia.value( QStringLiteral( "jednostka" ) ).toInt() ) );

  if ( ustawienia.contains( QStringLiteral( "przeciecia" ) ) )
    konfiguracja.setIntersectionSnapping( ustawienia.value( QStringLiteral( "przeciecia" ) ).toBool() );

  p->setSnappingConfig( konfiguracja );
  return true;
}

bool NarzedziaProjektu::unikajNakladania( QgsProject *projekt, int tryb, const QStringList &nazwyWarstw ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
    return false;

  p->setAvoidIntersectionsMode( static_cast<Qgis::AvoidIntersectionsMode>( tryb ) );

  if ( tryb != static_cast<int>( Qgis::AvoidIntersectionsMode::AvoidIntersectionsLayers ) )
    return true;

  QList<QgsVectorLayer *> warstwy;
  if ( nazwyWarstw.isEmpty() )
  {
    // Domyslnie: wszystkie edytowalne warstwy poligonowe projektu.
    const QMap<QString, QgsMapLayer *> wszystkie = p->mapLayers();
    for ( QgsMapLayer *kandydat : wszystkie )
    {
      QgsVectorLayer *warstwa = qobject_cast<QgsVectorLayer *>( kandydat );
      if ( !warstwa || warstwa->readOnly() )
        continue;
      if ( warstwa->geometryType() == Qgis::GeometryType::Polygon )
        warstwy << warstwa;
    }
  }
  else
  {
    for ( const QString &nazwa : nazwyWarstw )
    {
      if ( QgsVectorLayer *warstwa = znajdzWarstwe( p, nazwa ) )
        warstwy << warstwa;
    }
  }

  p->setAvoidIntersectionsLayers( warstwy );
  return true;
}

// ----------------------------------------------------------------------- warstwy

QVariantList NarzedziaProjektu::warstwyRobocze( QgsProject *projekt ) const
{
  QVariantList wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
    return wynik;

  const QMap<QString, QgsMapLayer *> wszystkie = p->mapLayers();
  for ( QgsMapLayer *kandydat : wszystkie )
  {
    QgsVectorLayer *warstwa = qobject_cast<QgsVectorLayer *>( kandydat );
    if ( !warstwa || warstwa->readOnly() )
      continue;

    const QString nazwa = warstwa->name();
    if ( nazwa.startsWith( QLatin1String( "ZAL_" ), Qt::CaseInsensitive )
         || nazwa.startsWith( QLatin1String( "REF_" ), Qt::CaseInsensitive ) )
      continue;

    QString geometria;
    switch ( warstwa->geometryType() )
    {
      case Qgis::GeometryType::Point:
        geometria = QStringLiteral( "Punkt" );
        break;
      case Qgis::GeometryType::Line:
        geometria = QStringLiteral( "Linia" );
        break;
      case Qgis::GeometryType::Polygon:
        geometria = QStringLiteral( "Poligon" );
        break;
      default:
        continue;   // bezgeometryczne to slowniki, nie warstwy robocze
    }

    QVariantMap wpis;
    wpis.insert( QStringLiteral( "nazwa" ), nazwa );
    wpis.insert( QStringLiteral( "geometria" ), geometria );
    wpis.insert( QStringLiteral( "punktowa" ), geometria == QLatin1String( "Punkt" ) );
    wynik.append( wpis );
  }
  return wynik;
}

QString NarzedziaProjektu::katalogSzablonow( const QString &korzen ) const
{
  if ( korzen.isEmpty() )
    return QString();

  const QDir k( korzen );
  const QStringList kandydaci = { QStringLiteral( "Szablony" ), QStringLiteral( "szablony" ),
                                  QStringLiteral( "templates" ) };
  for ( const QString &nazwa : kandydaci )
  {
    const QString sciezka = k.filePath( nazwa );
    if ( QDir( sciezka ).exists() )
      return sciezka;
  }
  return QString();
}

QString NarzedziaProjektu::katalogZadan( const QString &korzen ) const
{
  if ( korzen.isEmpty() )
    return QString();

  const QDir k( korzen );
  const QString wydania = k.filePath( QStringLiteral( "wydania" ) );
  if ( QDir( wydania ).exists() )
    return wydania;

  const QString wymiana = k.filePath( QStringLiteral( "wymiana" ) );
  if ( QDir( wymiana ).exists() )
    return wymiana;

  return QDir::cleanPath( korzen );
}

QString NarzedziaProjektu::nowyProjekt( const QString &korzen, const QString &nazwa, const QString &crsAuthId ) const
{
  if ( korzen.isEmpty() || nazwa.isEmpty() )
    return QString();

  QDir katalogKorzenia( korzen );
  const QString katalogZadania = QDir::cleanPath( katalogKorzenia.filePath( nazwa ) );
  if ( QFileInfo::exists( katalogZadania ) )
    return QString(); // nie nadpisujemy cudzej roboty — o nazwe pyta warstwa wyzej

  if ( !katalogKorzenia.mkpath( katalogZadania ) )
    return QString();

  const QString sciezkaProjektu = QStringLiteral( "%1/projekt.qgs" ).arg( katalogZadania );

  QgsProject projekt;
  QgsCoordinateReferenceSystem uklad( crsAuthId );
  if ( uklad.isValid() )
    projekt.setCrs( uklad );

  QgsProjectMetadata metadane = projekt.metadata();
  metadane.setTitle( nazwa );
  projekt.setMetadata( metadane );
  projekt.setTitle( nazwa );

  if ( !projekt.write( sciezkaProjektu ) )
    return QString();

  return sciezkaProjektu;
}

bool NarzedziaProjektu::doGrupy( QgsProject *projekt, QgsMapLayer *warstwa, const QString &grupa, bool zwinieta, bool widoczna ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || !warstwa || grupa.isEmpty() )
    return false;

  QgsLayerTree *korzen = p->layerTreeRoot();
  if ( !korzen )
    return false;

  QgsLayerTreeGroup *cel = korzen->findGroup( grupa );
  if ( !cel )
  {
    cel = korzen->addGroup( grupa );
    cel->setExpanded( !zwinieta );
  }

  QgsLayerTreeLayer *wezel = korzen->findLayer( warstwa->id() );
  if ( !wezel )
    return false;

  if ( wezel->parent() == cel )
    return true;

  QgsLayerTreeLayer *kopia = cel->addLayer( warstwa );
  kopia->setItemVisibilityChecked( widoczna );

  if ( QgsLayerTreeGroup *rodzic = qobject_cast<QgsLayerTreeGroup *>( wezel->parent() ) )
    rodzic->removeChildNode( wezel );

  return true;
}

int NarzedziaProjektu::dosypTabele( const QString &zrodloGpkg, const QString &celGpkg, const QStringList &tabele ) const
{
  if ( !QFile::exists( zrodloGpkg ) || !QFile::exists( celGpkg ) || tabele.isEmpty() )
    return 0;

  GDALDatasetH zrodlo = GDALOpenEx( zrodloGpkg.toUtf8().constData(), GDAL_OF_VECTOR | GDAL_OF_READONLY, nullptr, nullptr, nullptr );
  if ( !zrodlo )
    return 0;

  GDALDatasetH cel = GDALOpenEx( celGpkg.toUtf8().constData(), GDAL_OF_VECTOR | GDAL_OF_UPDATE, nullptr, nullptr, nullptr );
  if ( !cel )
  {
    GDALClose( zrodlo );
    return 0;
  }

  int skopiowane = 0;
  for ( const QString &tabela : tabele )
  {
    if ( GDALDatasetGetLayerByName( cel, tabela.toUtf8().constData() ) )
      continue; // juz jest — nie ruszamy

    OGRLayerH warstwaZrodlowa = GDALDatasetGetLayerByName( zrodlo, tabela.toUtf8().constData() );
    if ( !warstwaZrodlowa )
      continue;

    if ( GDALDatasetCopyLayer( cel, warstwaZrodlowa, tabela.toUtf8().constData(), nullptr ) )
      ++skopiowane;
  }

  GDALClose( cel );
  GDALClose( zrodlo );
  return skopiowane;
}

// ----------------------------------------------------------------------- stempel

bool NarzedziaProjektu::zapewnijTabeleStempla( const QString &gpkg )
{
  if ( !QFile::exists( gpkg ) )
    return false;

  GDALDatasetH baza = GDALOpenEx( gpkg.toUtf8().constData(), GDAL_OF_VECTOR | GDAL_OF_UPDATE, nullptr, nullptr, nullptr );
  if ( !baza )
    return false;

  // Celowo NIE rejestrujemy tabeli w gpkg_contents — stempel jest metadanymi
  // projektu, nie warstwa, i nie ma sie pokazywac w panelu warstw.
  const char *sql = "CREATE TABLE IF NOT EXISTS WF_WYPOSAZENIE ("
                    "modul TEXT PRIMARY KEY, wersja INTEGER NOT NULL, "
                    "data TEXT NOT NULL, zrodlo TEXT, przez TEXT)";
  GDALDatasetExecuteSQL( baza, sql, nullptr, nullptr );
  GDALClose( baza );
  return true;
}

QVariantMap NarzedziaProjektu::stempel( const QString &gpkg ) const
{
  QVariantMap wynik;
  if ( !QFile::exists( gpkg ) )
    return wynik;

  GDALDatasetH baza = GDALOpenEx( gpkg.toUtf8().constData(), GDAL_OF_VECTOR | GDAL_OF_READONLY, nullptr, nullptr, nullptr );
  if ( !baza )
    return wynik;

  OGRLayerH odpowiedz = GDALDatasetExecuteSQL( baza, "SELECT modul, wersja, data, zrodlo FROM WF_WYPOSAZENIE", nullptr, nullptr );
  if ( odpowiedz )
  {
    OGR_L_ResetReading( odpowiedz );
    while ( OGRFeatureH wiersz = OGR_L_GetNextFeature( odpowiedz ) )
    {
      QVariantMap wpis;
      wpis.insert( QStringLiteral( "wersja" ), OGR_F_GetFieldAsInteger( wiersz, 1 ) );
      wpis.insert( QStringLiteral( "data" ), QString::fromUtf8( OGR_F_GetFieldAsString( wiersz, 2 ) ) );
      wpis.insert( QStringLiteral( "zrodlo" ), QString::fromUtf8( OGR_F_GetFieldAsString( wiersz, 3 ) ) );
      wynik.insert( QString::fromUtf8( OGR_F_GetFieldAsString( wiersz, 0 ) ), wpis );
      OGR_F_Destroy( wiersz );
    }
    GDALDatasetReleaseResultSet( baza, odpowiedz );
  }

  GDALClose( baza );
  return wynik;
}

bool NarzedziaProjektu::stempluj( const QString &gpkg, const QString &modul, int wersja, const QString &zrodlo, const QString &przez ) const
{
  if ( modul.isEmpty() || !zapewnijTabeleStempla( gpkg ) )
    return false;

  GDALDatasetH baza = GDALOpenEx( gpkg.toUtf8().constData(), GDAL_OF_VECTOR | GDAL_OF_UPDATE, nullptr, nullptr, nullptr );
  if ( !baza )
    return false;

  auto bezpieczny = []( const QString &tekst ) { return QString( tekst ).replace( '\'', QLatin1String( "''" ) ); };

  const QString sql = QStringLiteral(
                        "INSERT INTO WF_WYPOSAZENIE (modul, wersja, data, zrodlo, przez) "
                        "VALUES ('%1', %2, '%3', '%4', '%5') "
                        "ON CONFLICT(modul) DO UPDATE SET wersja=excluded.wersja, "
                        "data=excluded.data, zrodlo=excluded.zrodlo, przez=excluded.przez" )
                        .arg( bezpieczny( modul ) )
                        .arg( wersja )
                        .arg( QDateTime::currentDateTime().toString( Qt::ISODate ),
                              bezpieczny( zrodlo ),
                              bezpieczny( przez ) );

  GDALDatasetExecuteSQL( baza, sql.toUtf8().constData(), nullptr, nullptr );
  GDALClose( baza );
  return true;
}

bool NarzedziaProjektu::odstempluj( const QString &gpkg, const QString &modul ) const
{
  if ( modul.isEmpty() || !QFile::exists( gpkg ) )
    return false;

  GDALDatasetH baza = GDALOpenEx( gpkg.toUtf8().constData(), GDAL_OF_VECTOR | GDAL_OF_UPDATE, nullptr, nullptr, nullptr );
  if ( !baza )
    return false;

  const QString sql = QStringLiteral( "DELETE FROM WF_WYPOSAZENIE WHERE modul = '%1'" )
                        .arg( QString( modul ).replace( '\'', QLatin1String( "''" ) ) );
  GDALDatasetExecuteSQL( baza, sql.toUtf8().constData(), nullptr, nullptr );
  GDALClose( baza );
  return true;
}

// ------------------------------------------------------------------------- pliki

QString NarzedziaProjektu::kopiaZapasowa( const QString &sciezka ) const
{
  if ( !QFile::exists( sciezka ) )
    return QString();

  const QString cel = QStringLiteral( "%1.bak_%2" )
                        .arg( sciezka, QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmmss" ) ) );

  if ( QFile::exists( cel ) )
    return cel;

  return QFile::copy( sciezka, cel ) ? cel : QString();
}

bool NarzedziaProjektu::zapiszProjekt( QgsProject *projekt ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || p->fileName().isEmpty() )
    return false;

  return p->write();
}

QVariantMap NarzedziaProjektu::zrzucPrzepis( QgsProject *projekt ) const
{
  QVariantMap przepis;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
    return przepis;

  // ------------------------------------------------------------- nagłówek
  const QString nazwaProjektu = p->baseName().isEmpty() ? p->title() : p->baseName();
  przepis.insert( QStringLiteral( "id" ), nazwaProjektu );
  przepis.insert( QStringLiteral( "wersja" ), 1 );
  przepis.insert( QStringLiteral( "nazwa" ), p->title().isEmpty() ? nazwaProjektu : p->title() );
  przepis.insert( QStringLiteral( "opis" ), tr( "Przepis odczytany z projektu %1." ).arg( nazwaProjektu ) );
  przepis.insert( QStringLiteral( "uklad" ), p->crs().authid() );
  przepis.insert( QStringLiteral( "zrodlo" ), QStringLiteral( "zrzut" ) );

  // ---------------------------------------------------------------- warstwy
  QVariantList warstwy;
  QString plikDanych;
  const QMap<QString, QgsMapLayer *> wszystkie = p->mapLayers();
  for ( QgsMapLayer *kandydat : wszystkie )
  {
    QgsVectorLayer *w = qobject_cast<QgsVectorLayer *>( kandydat );
    if ( !w )
      continue;   // podkłady i rastry to dane, nie struktura — muszą przyjechać

    const QString nazwa = w->name();
    if ( nazwa.startsWith( QLatin1String( "REF_" ), Qt::CaseInsensitive ) )
      continue;   // warstwy odniesienia zakłada wtyczka, nie przepis

    // plik danych bierzemy z pierwszej warstwy w GeoPackage
    if ( plikDanych.isEmpty() )
    {
      const QString zrodlo = w->source().section( QLatin1Char( '|' ), 0, 0 );
      if ( zrodlo.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive ) )
        plikDanych = QFileInfo( zrodlo ).fileName();
    }

    QVariantMap opis;
    opis.insert( QStringLiteral( "nazwa" ), nazwa );
    opis.insert( QStringLiteral( "geometria" ),
                 w->geometryType() == Qgis::GeometryType::Null
                   ? QStringLiteral( "NoGeometry" )
                   : QgsWkbTypes::displayString( w->wkbType() ) );

    // ---- pola (fid pomijamy — zakłada je GeoPackage)
    QVariantList pola;
    QVariantMap aliasy, widgety, domyslne, ograniczenia;
    const QgsFields poleLista = w->fields();
    for ( int i = 0; i < poleLista.count(); ++i )
    {
      const QgsField f = poleLista.at( i );
      if ( f.name().compare( QLatin1String( "fid" ), Qt::CaseInsensitive ) == 0 )
        continue;

      const QgsEditorWidgetSetup ustawienieWidgetu = w->editorWidgetSetup( i );

      QString typ;
      switch ( f.type() )
      {
        case QMetaType::Int:
        case QMetaType::UInt:
        case QMetaType::LongLong:
          typ = QStringLiteral( "integer" );
          break;
        case QMetaType::Double:
          typ = QStringLiteral( "real" );
          break;
        case QMetaType::QDate:
          typ = QStringLiteral( "date" );
          break;
        case QMetaType::QDateTime:
          typ = QStringLiteral( "datetime" );
          break;
        case QMetaType::Bool:
          typ = QStringLiteral( "bool" );
          break;
        default:
          // TextEdit z IsMultiline zapisuje sie jako osobny typ przepisu
          typ = ( ustawienieWidgetu.type() == QLatin1String( "TextEdit" )
                  && ustawienieWidgetu.config().value( QStringLiteral( "IsMultiline" ) ).toBool() )
                  ? QStringLiteral( "multiline" )
                  : QStringLiteral( "text" );
          break;
      }

      QVariantMap pole;
      pole.insert( QStringLiteral( "name" ), f.name() );
      pole.insert( QStringLiteral( "type" ), typ );
      pola.append( pole );

      if ( !f.alias().isEmpty() )
        aliasy.insert( f.name(), f.alias() );

      // widget zapisujemy tylko wtedy, gdy NIE wynika juz z typu pola —
      // inaczej przepis puchnie od oczywistosci
      const QString typWidgetu = ustawienieWidgetu.type();
      if ( !typWidgetu.isEmpty()
           && typWidgetu != QLatin1String( "TextEdit" )
           && typWidgetu != QLatin1String( "Range" )
           && typWidgetu != QLatin1String( "DateTime" ) )
      {
        QVariantMap widget;
        widget.insert( QStringLiteral( "typ" ), typWidgetu );
        if ( !ustawienieWidgetu.config().isEmpty() )
          widget.insert( QStringLiteral( "opcje" ), ustawienieWidgetu.config() );
        widgety.insert( f.name(), widget );
      }

      const QgsDefaultValue domyslna = w->defaultValueDefinition( i );
      if ( !domyslna.expression().isEmpty() )
      {
        if ( domyslna.applyOnUpdate() )
        {
          QVariantMap d;
          d.insert( QStringLiteral( "wyrazenie" ), domyslna.expression() );
          d.insert( QStringLiteral( "przyAktualizacji" ), true );
          domyslne.insert( f.name(), d );
        }
        else
        {
          domyslne.insert( f.name(), domyslna.expression() );
        }
      }

      const QString wyrOgraniczenia = w->constraintExpression( i );
      if ( !wyrOgraniczenia.isEmpty() )
      {
        QVariantMap o;
        o.insert( QStringLiteral( "wyrazenie" ), wyrOgraniczenia );
        o.insert( QStringLiteral( "opis" ), w->constraintDescription( i ) );
        ograniczenia.insert( f.name(), o );
      }
    }
    opis.insert( QStringLiteral( "pola" ), pola );
    if ( !aliasy.isEmpty() )
      opis.insert( QStringLiteral( "aliasy" ), aliasy );
    if ( !widgety.isEmpty() )
      opis.insert( QStringLiteral( "widgety" ), widgety );
    if ( !domyslne.isEmpty() )
      opis.insert( QStringLiteral( "domyslne" ), domyslne );
    if ( !ograniczenia.isEmpty() )
      opis.insert( QStringLiteral( "ograniczenia" ), ograniczenia );

    if ( !w->displayExpression().isEmpty() )
      opis.insert( QStringLiteral( "wyswietlanie" ), w->displayExpression() );

    const QgsEditFormConfig konfiguracja = w->editFormConfig();
    if ( konfiguracja.suppress() == Qgis::AttributeFormSuppression::On )
      opis.insert( QStringLiteral( "bezPotwierdzenia" ), true );

    // ---- zakladki formularza (tylko uklad DragAndDrop cokolwiek znaczy)
    if ( konfiguracja.layout() == Qgis::AttributeFormLayout::DragAndDrop )
    {
      QVariantList zakladki;
      const QList<QgsAttributeEditorElement *> gorne = konfiguracja.tabs();
      for ( QgsAttributeEditorElement *element : gorne )
      {
        if ( element->type() != Qgis::AttributeEditorType::Container )
          continue;
        QgsAttributeEditorContainer *pojemnik = dynamic_cast<QgsAttributeEditorContainer *>( element );
        if ( !pojemnik )
          continue;

        QVariantMap zakladka;
        zakladka.insert( QStringLiteral( "tytul" ), pojemnik->name() );

        QStringList polaZakladki;
        QString idRelacji;
        const QList<QgsAttributeEditorElement *> dzieci = pojemnik->children();
        for ( QgsAttributeEditorElement *dziecko : dzieci )
        {
          if ( dziecko->type() == Qgis::AttributeEditorType::Field )
          {
            QgsAttributeEditorField *poleElement = dynamic_cast<QgsAttributeEditorField *>( dziecko );
            if ( poleElement && poleElement->idx() >= 0 && poleElement->idx() < poleLista.count() )
              polaZakladki << poleLista.at( poleElement->idx() ).name();
          }
          else if ( dziecko->type() == Qgis::AttributeEditorType::Relation )
          {
            QgsAttributeEditorRelation *relElement = dynamic_cast<QgsAttributeEditorRelation *>( dziecko );
            if ( relElement )
              idRelacji = relElement->relation().id();
          }
        }

        if ( !idRelacji.isEmpty() )
          zakladka.insert( QStringLiteral( "relacja" ), idRelacji );
        else if ( !polaZakladki.isEmpty() )
          zakladka.insert( QStringLiteral( "pola" ), polaZakladki );
        else
          continue;   // pusta zakladka nie niesie informacji

        zakladki.append( zakladka );
      }
      if ( !zakladki.isEmpty() )
        opis.insert( QStringLiteral( "zakladki" ), zakladki );
    }

    // ---- grupa w drzewie warstw
    if ( QgsLayerTree *korzen = p->layerTreeRoot() )
    {
      if ( QgsLayerTreeLayer *wezel = korzen->findLayer( w->id() ) )
      {
        if ( QgsLayerTreeGroup *rodzic = qobject_cast<QgsLayerTreeGroup *>( wezel->parent() ) )
        {
          if ( !rodzic->name().isEmpty() )
          {
            opis.insert( QStringLiteral( "grupa" ), rodzic->name() );
            opis.insert( QStringLiteral( "widoczna" ), wezel->itemVisibilityChecked() );
          }
        }
      }
    }

    // ---- wlasciwosci niestandardowe warstwy (tedy idzie konwencja nazw zdjec)
    QVariantMap wlasciwosciWarstwy;
    const QStringList klucze = w->customPropertyKeys();
    for ( const QString &klucz : klucze )
    {
      if ( klucz.startsWith( QLatin1String( "QFieldSync/" ) ) )
        wlasciwosciWarstwy.insert( klucz, w->customProperty( klucz ) );
    }
    if ( !wlasciwosciWarstwy.isEmpty() )
      opis.insert( QStringLiteral( "wlasciwosci" ), wlasciwosciWarstwy );

    warstwy.append( opis );
  }
  przepis.insert( QStringLiteral( "warstwy" ), warstwy );
  przepis.insert( QStringLiteral( "dane" ), plikDanych.isEmpty() ? QStringLiteral( "dane.gpkg" ) : plikDanych );

  // ---------------------------------------------------------------- relacje
  QVariantList relacje;
  const QList<QgsRelation> wszystkieRelacje = p->relationManager()->relations().values();
  for ( const QgsRelation &r : wszystkieRelacje )
  {
    if ( !r.isValid() )
      continue;
    QgsVectorLayer *rodzic = r.referencedLayer();
    QgsVectorLayer *dziecko = r.referencingLayer();
    if ( !rodzic || !dziecko )
      continue;
    const QList<QgsRelation::FieldPair> pary = r.fieldPairs();
    if ( pary.isEmpty() )
      continue;

    QVariantMap opisRelacji;
    opisRelacji.insert( QStringLiteral( "id" ), r.id() );
    opisRelacji.insert( QStringLiteral( "nazwa" ), r.name() );
    opisRelacji.insert( QStringLiteral( "rodzic" ), rodzic->name() );
    opisRelacji.insert( QStringLiteral( "dziecko" ), dziecko->name() );
    opisRelacji.insert( QStringLiteral( "poleDziecka" ), pary.first().referencingField() );
    opisRelacji.insert( QStringLiteral( "poleRodzica" ), pary.first().referencedField() );
    opisRelacji.insert( QStringLiteral( "kompozycja" ),
                        r.strength() == Qgis::RelationshipStrength::Composition );
    relacje.append( opisRelacji );
  }
  if ( !relacje.isEmpty() )
    przepis.insert( QStringLiteral( "relacje" ), relacje );

  // ------------------------------------------------------------- ustawienia
  QVariantMap ustawienia;

  const QgsSnappingConfig snap = p->snappingConfig();
  QVariantMap przyciaganie;
  przyciaganie.insert( QStringLiteral( "wlaczone" ), snap.enabled() );
  przyciaganie.insert( QStringLiteral( "tryb" ), static_cast<int>( snap.mode() ) );
  przyciaganie.insert( QStringLiteral( "typ" ), static_cast<int>( snap.typeFlag() ) );
  przyciaganie.insert( QStringLiteral( "tolerancja" ), snap.tolerance() );
  przyciaganie.insert( QStringLiteral( "jednostka" ), static_cast<int>( snap.units() ) );
  przyciaganie.insert( QStringLiteral( "przeciecia" ), snap.intersectionSnapping() );
  ustawienia.insert( QStringLiteral( "przyciaganie" ), przyciaganie );

  QVariantMap nakladanie;
  nakladanie.insert( QStringLiteral( "tryb" ), static_cast<int>( p->avoidIntersectionsMode() ) );
  QStringList nazwyUnikania;
  const QList<QgsVectorLayer *> unikane = p->avoidIntersectionsLayers();
  for ( QgsVectorLayer *u : unikane )
  {
    if ( u )
      nazwyUnikania << u->name();
  }
  nakladanie.insert( QStringLiteral( "warstwy" ), nazwyUnikania );
  ustawienia.insert( QStringLiteral( "unikajNakladania" ), nakladanie );

  przepis.insert( QStringLiteral( "projekt" ), ustawienia );

  return przepis;
}

QString NarzedziaProjektu::czytajTekst( const QString &sciezka ) const
{
  QFile plik( sciezka );
  if ( !plik.open( QIODevice::ReadOnly | QIODevice::Text ) )
    return QString();

  const QString tresc = QString::fromUtf8( plik.readAll() );
  plik.close();
  return tresc;
}

bool NarzedziaProjektu::zapiszTekst( const QString &sciezka, const QString &tresc ) const
{
  QFile plik( sciezka );
  if ( !plik.open( QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text ) )
    return false;

  const bool ok = plik.write( tresc.toUtf8() ) >= 0;
  plik.close();
  return ok;
}

// ------------------------------------------------------------------ geometria

QVariantMap NarzedziaProjektu::sprawdzGeometrie( QgsVectorLayer *warstwa, QgsFeatureId fid ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );
  wynik.insert( QStringLiteral( "wazna" ), false );
  wynik.insert( QStringLiteral( "wieloczesciowa" ), false );
  wynik.insert( QStringLiteral( "czesci" ), 0 );
  wynik.insert( QStringLiteral( "bledy" ), QVariantList() );
  wynik.insert( QStringLiteral( "opis" ), QString() );

  if ( !warstwa )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Brak warstwy." ) );
    return wynik;
  }

  const QgsFeature obiekt = warstwa->getFeature( fid );
  const QgsGeometry geom = obiekt.geometry();
  if ( geom.isNull() || geom.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Obiekt nie ma geometrii." ) );
    return wynik;
  }

  const bool wazna = geom.isGeosValid();
  const bool wielo = geom.isMultipart();
  const int czesci = geom.constGet() ? geom.constGet()->partCount() : 0;

  QVector<QgsGeometry::Error> bledy;
  geom.validateGeometry( bledy, Qgis::GeometryValidationEngine::QgisInternal );

  QVariantList listaBledow;
  for ( int i = 0; i < bledy.size(); ++i )
  {
    const QgsGeometry::Error &blad = bledy.at( i );
    QVariantMap m;
    m.insert( QStringLiteral( "opis" ), blad.what() );
    m.insert( QStringLiteral( "maMiejsce" ), blad.hasWhere() );
    if ( blad.hasWhere() )
    {
      m.insert( QStringLiteral( "x" ), blad.where().x() );
      m.insert( QStringLiteral( "y" ), blad.where().y() );
    }
    listaBledow << m;
  }

  QString opis;
  if ( wazna && !wielo )
    opis = tr( "Geometria poprawna." );
  else if ( wazna && wielo )
    opis = tr( "Geometria poprawna, ale obiekt ma %1 części." ).arg( czesci );
  else if ( !bledy.isEmpty() )
    opis = tr( "Geometria niepoprawna: %1" ).arg( bledy.at( 0 ).what() );
  else
    opis = tr( "Geometria niepoprawna." );

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "wazna" ), wazna );
  wynik.insert( QStringLiteral( "wieloczesciowa" ), wielo );
  wynik.insert( QStringLiteral( "czesci" ), czesci );
  wynik.insert( QStringLiteral( "bledy" ), listaBledow );
  wynik.insert( QStringLiteral( "opis" ), opis );
  return wynik;
}

QVariantMap NarzedziaProjektu::naprawGeometrie( QgsVectorLayer *warstwa, QgsFeatureId fid, bool zapisz ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );
  wynik.insert( QStringLiteral( "bylaWazna" ), false );
  wynik.insert( QStringLiteral( "czesciPrzed" ), 0 );
  wynik.insert( QStringLiteral( "czesciPo" ), 0 );
  wynik.insert( QStringLiteral( "wymagaPodzialu" ), false );
  wynik.insert( QStringLiteral( "opis" ), QString() );

  if ( !warstwa )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Brak warstwy." ) );
    return wynik;
  }

  const QgsFeature obiekt = warstwa->getFeature( fid );
  const QgsGeometry geom = obiekt.geometry();
  if ( geom.isNull() || geom.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Obiekt nie ma geometrii." ) );
    return wynik;
  }

  const int czesciPrzed = geom.constGet() ? geom.constGet()->partCount() : 0;
  wynik.insert( QStringLiteral( "czesciPrzed" ), czesciPrzed );

  if ( geom.isGeosValid() )
  {
    wynik.insert( QStringLiteral( "ok" ), true );
    wynik.insert( QStringLiteral( "bylaWazna" ), true );
    wynik.insert( QStringLiteral( "czesciPo" ), czesciPrzed );
    wynik.insert( QStringLiteral( "opis" ), tr( "Geometria była poprawna — nic nie zmieniono." ) );
    return wynik;
  }

  const QgsGeometry naprawiona = geom.makeValid();
  if ( naprawiona.isNull() || naprawiona.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Nie udało się naprawić geometrii." ) );
    return wynik;
  }

  // Czy warstwa w ogole przyjmie taki ksztalt? coerceToType tnie wynik na
  // tyle geometrii, ile potrzeba, zeby zmiescic go w typie warstwy.
  const QVector<QgsGeometry> dopasowane = naprawiona.coerceToType( warstwa->wkbType() );
  if ( dopasowane.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Naprawiona geometria nie pasuje do typu warstwy." ) );
    return wynik;
  }

  if ( dopasowane.size() > 1 )
  {
    // Swiadomie nie zapisujemy: to zmiana LICZBY obiektow, nie ksztaltu.
    wynik.insert( QStringLiteral( "wymagaPodzialu" ), true );
    wynik.insert( QStringLiteral( "czesciPo" ), dopasowane.size() );
    wynik.insert( QStringLiteral( "opis" ),
                  tr( "Naprawa rozdziela obiekt na %1 osobne obiekty, a warstwa przyjmuje pojedyncze. "
                      "Popraw wierzchołki ręcznie albo rozdziel obiekt świadomie." )
                    .arg( dopasowane.size() ) );
    return wynik;
  }

  QgsGeometry docelowa = dopasowane.at( 0 );
  const int czesciPo = docelowa.constGet() ? docelowa.constGet()->partCount() : 0;
  wynik.insert( QStringLiteral( "czesciPo" ), czesciPo );

  if ( !zapisz )
  {
    wynik.insert( QStringLiteral( "ok" ), true );
    wynik.insert( QStringLiteral( "opis" ), czesciPo > czesciPrzed
                                              ? tr( "Naprawa da obiekt z %1 częściami." ).arg( czesciPo )
                                              : tr( "Naprawa da poprawną geometrię." ) );
    return wynik;
  }

  // Cudzej sesji edycji nie zamykamy — piszemy do jej bufora.
  const bool bylaEdycja = warstwa->isEditable();
  if ( !bylaEdycja && !warstwa->startEditing() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Nie udało się otworzyć warstwy do edycji." ) );
    return wynik;
  }

  warstwa->changeGeometry( fid, docelowa );

  if ( !bylaEdycja && !warstwa->commitChanges() )
  {
    warstwa->rollBack();
    wynik.insert( QStringLiteral( "opis" ), tr( "Zapis naprawionej geometrii nie powiódł się." ) );
    return wynik;
  }

  // Stan sprawdzamy PO fakcie, nie z wartosci zwracanej.
  const QgsGeometry poZapisie = warstwa->getFeature( fid ).geometry();
  const bool udalo = !poZapisie.isNull() && poZapisie.isGeosValid();

  wynik.insert( QStringLiteral( "ok" ), udalo );
  wynik.insert( QStringLiteral( "opis" ), udalo
                                            ? ( czesciPo > czesciPrzed
                                                  ? tr( "Naprawiono — obiekt ma teraz %1 części." ).arg( czesciPo )
                                                  : tr( "Naprawiono." ) )
                                            : tr( "Po zapisie geometria nadal jest niepoprawna." ) );
  return wynik;
}

QVariantMap NarzedziaProjektu::polaczObiekty( QgsVectorLayer *warstwa, const QVariantList &fidy, bool zapisz ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );
  wynik.insert( QStringLiteral( "fid" ), static_cast<qlonglong>( -1 ) );
  wynik.insert( QStringLiteral( "zlaczono" ), 0 );
  wynik.insert( QStringLiteral( "czesci" ), 0 );
  wynik.insert( QStringLiteral( "opis" ), QString() );

  if ( !warstwa )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Brak warstwy." ) );
    return wynik;
  }

  if ( fidy.size() < 2 )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Do złączenia potrzebne są co najmniej dwa obiekty." ) );
    return wynik;
  }

  QList<QgsFeatureId> lista;
  for ( int i = 0; i < fidy.size(); ++i )
  {
    const QgsFeatureId f = static_cast<QgsFeatureId>( fidy.at( i ).toLongLong() );
    if ( !lista.contains( f ) )
      lista << f;
  }

  QgsGeometry suma;
  for ( int i = 0; i < lista.size(); ++i )
  {
    const QgsGeometry g = warstwa->getFeature( lista.at( i ) ).geometry();
    if ( g.isNull() || g.isEmpty() )
      continue;

    // Niepoprawne skladniki psuja wynik combine — prostujemy je po drodze.
    const QgsGeometry skladnik = g.isGeosValid() ? g : g.makeValid();
    if ( skladnik.isNull() || skladnik.isEmpty() )
      continue;

    suma = suma.isNull() ? skladnik : suma.combine( skladnik );
    if ( suma.isNull() )
    {
      wynik.insert( QStringLiteral( "opis" ), tr( "Nie udało się złączyć geometrii." ) );
      return wynik;
    }
  }

  if ( suma.isNull() || suma.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Wskazane obiekty nie mają geometrii." ) );
    return wynik;
  }

  const QVector<QgsGeometry> dopasowane = suma.coerceToType( warstwa->wkbType() );
  if ( dopasowane.isEmpty() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Wynik złączenia nie pasuje do typu warstwy." ) );
    return wynik;
  }

  if ( dopasowane.size() > 1 )
  {
    wynik.insert( QStringLiteral( "czesci" ), dopasowane.size() );
    wynik.insert( QStringLiteral( "opis" ),
                  tr( "Obiekty nie stykają się — złączenie dałoby %1 osobnych obiektów, "
                      "a warstwa przyjmuje pojedyncze." )
                    .arg( dopasowane.size() ) );
    return wynik;
  }

  QgsGeometry docelowa = dopasowane.at( 0 );
  const QgsFeatureId zostaje = lista.at( 0 );
  wynik.insert( QStringLiteral( "fid" ), static_cast<qlonglong>( zostaje ) );
  wynik.insert( QStringLiteral( "zlaczono" ), lista.size() );
  wynik.insert( QStringLiteral( "czesci" ), docelowa.constGet() ? docelowa.constGet()->partCount() : 0 );

  if ( !zapisz )
  {
    wynik.insert( QStringLiteral( "ok" ), true );
    wynik.insert( QStringLiteral( "opis" ), tr( "Złączenie %1 obiektów jest możliwe." ).arg( lista.size() ) );
    return wynik;
  }

  const bool bylaEdycja = warstwa->isEditable();
  if ( !bylaEdycja && !warstwa->startEditing() )
  {
    wynik.insert( QStringLiteral( "opis" ), tr( "Nie udało się otworzyć warstwy do edycji." ) );
    return wynik;
  }

  warstwa->changeGeometry( zostaje, docelowa );
  for ( int i = 1; i < lista.size(); ++i )
    warstwa->deleteFeature( lista.at( i ) );

  if ( !bylaEdycja && !warstwa->commitChanges() )
  {
    warstwa->rollBack();
    wynik.insert( QStringLiteral( "opis" ), tr( "Zapis złączenia nie powiódł się." ) );
    return wynik;
  }

  const QgsGeometry poZapisie = warstwa->getFeature( zostaje ).geometry();
  const bool udalo = !poZapisie.isNull() && !poZapisie.isEmpty();

  wynik.insert( QStringLiteral( "ok" ), udalo );
  wynik.insert( QStringLiteral( "opis" ), udalo
                                            ? tr( "Złączono %1 obiektów w jeden." ).arg( lista.size() )
                                            : tr( "Po zapisie obiekt nie ma geometrii." ) );
  return wynik;
}

QVariantMap NarzedziaProjektu::mergeParts( QgsVectorLayer *layer, QgsFeatureId fid, bool write ) const
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  result.insert( QStringLiteral( "partsBefore" ), 0 );
  result.insert( QStringLiteral( "partsAfter" ), 0 );
  result.insert( QStringLiteral( "message" ), QString() );

  if ( !layer )
  {
    result.insert( QStringLiteral( "message" ), tr( "Brak warstwy." ) );
    return result;
  }

  const QgsGeometry geom = layer->getFeature( fid ).geometry();
  if ( geom.isNull() || geom.isEmpty() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Obiekt nie ma geometrii." ) );
    return result;
  }

  const int partsBefore = geom.constGet() ? geom.constGet()->partCount() : 0;
  result.insert( QStringLiteral( "partsBefore" ), partsBefore );

  if ( partsBefore < 2 )
  {
    result.insert( QStringLiteral( "ok" ), true );
    result.insert( QStringLiteral( "partsAfter" ), partsBefore );
    result.insert( QStringLiteral( "message" ), tr( "Obiekt ma jedną część — nie ma czego scalać." ) );
    return result;
  }

  const QVector<QgsGeometry> parts = geom.asGeometryCollection();
  QgsGeometry merged;
  for ( int i = 0; i < parts.size(); ++i )
  {
    const QgsGeometry &part = parts.at( i );
    if ( part.isNull() || part.isEmpty() )
      continue;

    const QgsGeometry piece = part.isGeosValid() ? part : part.makeValid();
    if ( piece.isNull() || piece.isEmpty() )
      continue;

    merged = merged.isNull() ? piece : merged.combine( piece );
    if ( merged.isNull() )
    {
      result.insert( QStringLiteral( "message" ), tr( "Nie udało się scalić części." ) );
      return result;
    }
  }

  if ( merged.isNull() || merged.isEmpty() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Nie udało się scalić części." ) );
    return result;
  }

  const int partsAfter = merged.constGet() ? merged.constGet()->partCount() : 0;
  result.insert( QStringLiteral( "partsAfter" ), partsAfter );

  if ( partsAfter > 1 )
  {
    result.insert( QStringLiteral( "message" ),
                   tr( "Części nie stykają się — scalenie nadal dałoby %1 części. "
                       "Użyj rozdzielenia albo dociągnij granice." )
                     .arg( partsAfter ) );
    return result;
  }

  const QVector<QgsGeometry> fitted = merged.coerceToType( layer->wkbType() );
  if ( fitted.size() != 1 )
  {
    result.insert( QStringLiteral( "message" ), tr( "Scalona geometria nie pasuje do typu warstwy." ) );
    return result;
  }

  if ( !write )
  {
    result.insert( QStringLiteral( "ok" ), true );
    result.insert( QStringLiteral( "message" ), tr( "Scalenie %1 części jest możliwe." ).arg( partsBefore ) );
    return result;
  }

  QgsGeometry target = fitted.at( 0 );

  const bool wasEditing = layer->isEditable();
  if ( !wasEditing && !layer->startEditing() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Nie udało się otworzyć warstwy do edycji." ) );
    return result;
  }

  layer->changeGeometry( fid, target );

  if ( !wasEditing && !layer->commitChanges() )
  {
    layer->rollBack();
    result.insert( QStringLiteral( "message" ), tr( "Zapis scalenia nie powiódł się." ) );
    return result;
  }

  const QgsGeometry after = layer->getFeature( fid ).geometry();
  const int reallyAfter = ( !after.isNull() && after.constGet() ) ? after.constGet()->partCount() : 0;
  const bool done = reallyAfter == 1;

  result.insert( QStringLiteral( "ok" ), done );
  result.insert( QStringLiteral( "partsAfter" ), reallyAfter );
  result.insert( QStringLiteral( "message" ), done
                                                ? tr( "Scalono %1 części w jedną." ).arg( partsBefore )
                                                : tr( "Po zapisie obiekt nadal ma %1 części." ).arg( reallyAfter ) );
  return result;
}

QVariantMap NarzedziaProjektu::splitParts( QgsVectorLayer *layer, QgsFeatureId fid, bool write ) const
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  result.insert( QStringLiteral( "parts" ), 0 );
  result.insert( QStringLiteral( "created" ), QVariantList() );
  result.insert( QStringLiteral( "message" ), QString() );

  if ( !layer )
  {
    result.insert( QStringLiteral( "message" ), tr( "Brak warstwy." ) );
    return result;
  }

  const QgsFeature source = layer->getFeature( fid );
  const QgsGeometry geom = source.geometry();
  if ( geom.isNull() || geom.isEmpty() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Obiekt nie ma geometrii." ) );
    return result;
  }

  const QVector<QgsGeometry> parts = geom.asGeometryCollection();
  result.insert( QStringLiteral( "parts" ), parts.size() );

  if ( parts.size() < 2 )
  {
    result.insert( QStringLiteral( "message" ), tr( "Obiekt ma jedną część — nie ma czego rozdzielać." ) );
    return result;
  }

  if ( !write )
  {
    result.insert( QStringLiteral( "ok" ), true );
    result.insert( QStringLiteral( "message" ), tr( "Rozdzielenie da %1 osobnych obiektów." ).arg( parts.size() ) );
    return result;
  }

  const bool wasEditing = layer->isEditable();
  if ( !wasEditing && !layer->startEditing() )
  {
    result.insert( QStringLiteral( "message" ), tr( "Nie udało się otworzyć warstwy do edycji." ) );
    return result;
  }

  // Pierwsza czesc zostaje na istniejacym obiekcie.
  const QVector<QgsGeometry> firstFitted = parts.at( 0 ).coerceToType( layer->wkbType() );
  if ( firstFitted.size() != 1 )
  {
    if ( !wasEditing )
      layer->rollBack();
    result.insert( QStringLiteral( "message" ), tr( "Część geometrii nie pasuje do typu warstwy." ) );
    return result;
  }

  QgsGeometry firstGeometry = firstFitted.at( 0 );
  layer->changeGeometry( fid, firstGeometry );

  // Pozostale czesci — nowe obiekty z kopia atrybutow.
  const QgsAttributeList keys = layer->primaryKeyAttributes();
  QVariantList created;

  for ( int i = 1; i < parts.size(); ++i )
  {
    const QVector<QgsGeometry> fitted = parts.at( i ).coerceToType( layer->wkbType() );
    if ( fitted.size() != 1 )
      continue;

    QgsFeature copy( layer->fields() );
    copy.setAttributes( source.attributes() );
    for ( int k = 0; k < keys.size(); ++k )
      copy.setAttribute( keys.at( k ), QVariant() );
    copy.setGeometry( fitted.at( 0 ) );

    if ( layer->addFeature( copy ) )
      created << QVariant::fromValue( static_cast<qlonglong>( copy.id() ) );
  }

  if ( !wasEditing && !layer->commitChanges() )
  {
    layer->rollBack();
    result.insert( QStringLiteral( "message" ), tr( "Zapis rozdzielenia nie powiódł się." ) );
    return result;
  }

  // Stan sprawdzamy po fakcie.
  const QgsGeometry after = layer->getFeature( fid ).geometry();
  const int stillParts = ( !after.isNull() && after.constGet() ) ? after.constGet()->partCount() : 0;
  const bool done = stillParts == 1 && created.size() == parts.size() - 1;

  result.insert( QStringLiteral( "ok" ), done );
  result.insert( QStringLiteral( "created" ), created );
  result.insert( QStringLiteral( "message" ), done
                                                ? tr( "Rozdzielono na %1 obiektów. Załączniki zostały przy pierwszym." ).arg( parts.size() )
                                                : tr( "Rozdzielenie częściowe: powstało %1 z %2 obiektów." ).arg( created.size() + 1 ).arg( parts.size() ) );
  return result;
}
