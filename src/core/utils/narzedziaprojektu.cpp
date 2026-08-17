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

#include <qgsattributeeditorcontainer.h>
#include <qgsattributeeditorfield.h>
#include <qgsattributeeditorrelation.h>
#include <qgsdefaultvalue.h>
#include <qgseditformconfig.h>
#include <qgseditorwidgetsetup.h>
#include <qgsexpressioncontextutils.h>
#include <qgsfieldconstraints.h>
#include <qgslayertree.h>
#include <qgslayertreegroup.h>
#include <qgsrelation.h>
#include <qgsrelationcontext.h>
#include <qgsrelationmanager.h>
#include <qgssnappingconfig.h>

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
