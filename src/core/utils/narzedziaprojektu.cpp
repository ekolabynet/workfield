/***************************************************************************
  narzedziaprojektu.cpp - NarzedziaProjektu

 ---------------------
 WorkField: czasowniki do budowania i doposazania projektu, wystawione do QML.
 Patrz narzedziaprojektu.h i docs/WYPOSAZENIE.md.
 ***************************************************************************/

#include "narzedziaprojektu.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>

#include <sqlite3.h>

#include <qgslayertreeregistrybridge.h>
#include <qgslayertreelayer.h>
#include <qgscoordinatereferencesystem.h>
#include <qgsproject.h>
#include <qgsvectorlayer.h>
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

// CSLAddString i CSLDestroy siedza w cpl_string.h. Do 23.08.2026 dojezdzaly tu
// przypadkiem, wciagane przez naglowki QGIS-a — w qfappinterface.cpp dziala to
// nadal, bo ten plik wciaga pol biblioteki. Tutaj przestalo dzialac w chwili,
// gdy doszedl import warstwy. Naglowek, z ktorego bierzemy nazwe, wlaczamy sami.
#include <cpl_conv.h>
#include <cpl_string.h>
#include <gdal.h>
#include <gdal_utils.h>
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

QVariantMap NarzedziaProjektu::ustawieniaPrzyciagania( QgsProject *projekt ) const
{
  QVariantMap w;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
    return w;

  const QgsSnappingConfig k = p->snappingConfig();
  w.insert( QStringLiteral( "wlaczone" ), k.enabled() );
  w.insert( QStringLiteral( "tryb" ), static_cast<int>( k.mode() ) );
  w.insert( QStringLiteral( "typ" ), static_cast<int>( k.typeFlag() ) );
  w.insert( QStringLiteral( "tolerancja" ), k.tolerance() );
  w.insert( QStringLiteral( "jednostka" ), static_cast<int>( k.units() ) );
  w.insert( QStringLiteral( "przeciecia" ), k.intersectionSnapping() );
  return w;
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

bool NarzedziaProjektu::przesunWarstwe( QgsProject *projekt, QgsMapLayer *warstwa, bool wGore ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || !warstwa )
    return false;

  QgsLayerTreeLayer *wezel = p->layerTreeRoot()->findLayer( warstwa->id() );
  if ( !wezel )
    return false;
  QgsLayerTreeNode *rodzic = wezel->parent();
  if ( !rodzic )
    return false;

  const int gdzie = rodzic->children().indexOf( wezel );
  const int cel = wGore ? gdzie - 1 : gdzie + 1;
  if ( cel < 0 || cel >= rodzic->children().count() )
    return false; // kraniec — nie ma dokad

  QgsLayerTreeGroup *grupa = qobject_cast<QgsLayerTreeGroup *>( rodzic );
  if ( !grupa )
    return false;

  // MOST DRZEWO-REJESTR TRZEBA WYLACZYC.
  //
  // `QgsLayerTreeRegistryBridge` pilnuje, zeby drzewo i rejestr warstw
  // projektu mowily to samo: gdy wezel znika z drzewa, most USUWA warstwe
  // z projektu. Przy przestawianiu wezel znika na ulamek sekundy — i to
  // wystarczylo, zeby warstwa przepadla na dobre (18.09.2026, dwie proby:
  // `clone`+`remove` dublowal, samo `takeChild` kasowalo).
  //
  // Most wraca w KAZDYM wyjsciu, takze przy bledzie.
  QgsLayerTreeRegistryBridge *most = p->layerTreeRegistryBridge();
  const bool bylWlaczony = most && most->isEnabled();
  if ( most )
    most->setEnabled( false );

  // KLON, NIE PRZENIESIENIE. Tak robi QGIS przy przeciaganiu w legendzie
  // (`QgsLayerTreeModel::dropMimeData`): serializuje wezel, tworzy NOWY
  // i wstawia, a stary usuwa osobno. Nigdy nie wypina i nie wklada tego
  // samego wskaznika — osierocony wezel nie przezywa podrozy.
  //
  // Klon wskazuje TE SAMA warstwe (ten sam identyfikator), wiec bez
  // wylaczonego mostu usuniecie oryginalu zabieralo ja z projektu.
  QgsLayerTreeNode *kopia = wezel->clone();
  // STAN ROZWINIECIA nie przechodzi przez `clone()`. `buildMap` pokazuje
  // podglad stylu tylko dla wezlow ROZWINIETYCH, wiec po przestawieniu
  // znikaly symbole kolorow — warstwa wracala zwinieta (19.09.2026).
  if ( kopia )
    kopia->setExpanded( wezel->isExpanded() );
  bool ok = false;
  if ( kopia )
  {
    // KOLEJNOSC MA ZNACZENIE. Przy ruchu W GORE klon wchodzi PRZED
    // oryginalem, wiec `cel` jest dobry. Przy ruchu W DOL klon ma stanac
    // ZA sasiadem — a ten jest jeszcze na swoim miejscu, bo oryginalu
    // nie usunelismy. Stad `cel + 1`.
    grupa->insertChildNode( wGore ? cel : cel + 1, kopia );
    grupa->removeChildNode( wezel );
    ok = true;
  }

  if ( most && bylWlaczony )
    most->setEnabled( true );
  return ok;
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

// ---------------------------------------------------------------- migawka

namespace
{
  //! `type=3` nic nie mowi. "wierzcholek i segment" mowi wszystko.
  QString typySlownie( Qgis::SnappingTypes typy )
  {
    QStringList czesci;
    if ( typy & Qgis::SnappingType::Vertex )
      czesci << QObject::tr( "wierzchołek" );
    if ( typy & Qgis::SnappingType::Segment )
      czesci << QObject::tr( "segment" );
    if ( typy & Qgis::SnappingType::Area )
      czesci << QObject::tr( "obszar" );
    if ( typy & Qgis::SnappingType::Centroid )
      czesci << QObject::tr( "środek ciężkości" );
    if ( typy & Qgis::SnappingType::MiddleOfSegment )
      czesci << QObject::tr( "środek segmentu" );
    if ( typy & Qgis::SnappingType::LineEndpoint )
      czesci << QObject::tr( "koniec linii" );
    return czesci.isEmpty() ? QObject::tr( "nic" ) : czesci.join( QStringLiteral( " + " ) );
  }

  QString trybSlownie( Qgis::SnappingMode tryb )
  {
    switch ( tryb )
    {
      case Qgis::SnappingMode::ActiveLayer:
        return QObject::tr( "warstwa aktywna" );
      case Qgis::SnappingMode::AllLayers:
        return QObject::tr( "wszystkie warstwy" );
      case Qgis::SnappingMode::AdvancedConfiguration:
        return QObject::tr( "ustawienia per warstwa" );
    }
    return QObject::tr( "nieznany" );
  }

  QString jednostkaSlownie( Qgis::MapToolUnit jednostka )
  {
    switch ( jednostka )
    {
      case Qgis::MapToolUnit::Layer:
        return QObject::tr( "jednostki warstwy" );
      case Qgis::MapToolUnit::Project:
        return QObject::tr( "jednostki mapy" );
      case Qgis::MapToolUnit::Pixels:
        return QObject::tr( "piksele ekranu" );
    }
    return QObject::tr( "nieznane" );
  }

  QString geometriaSlownie( Qgis::GeometryType typ )
  {
    switch ( typ )
    {
      case Qgis::GeometryType::Point:
        return QObject::tr( "punkt" );
      case Qgis::GeometryType::Line:
        return QObject::tr( "linia" );
      case Qgis::GeometryType::Polygon:
        return QObject::tr( "poligon" );
      case Qgis::GeometryType::Unknown:
        return QObject::tr( "nieznana" );
      case Qgis::GeometryType::Null:
        return QObject::tr( "tabela" );
    }
    return QObject::tr( "nieznana" );
  }
}

QVariantMap NarzedziaProjektu::stanProjektu( QgsProject *projekt ) const
{
  QVariantMap wynik;
  if ( !projekt )
    return wynik;

  QVariantList warstwy;
  QVariantList ostrzezenia;

  auto ostrzez = [&ostrzezenia]( const QString &waga, const QString &tekst ) {
    QVariantMap o;
    o.insert( QStringLiteral( "waga" ), waga );
    o.insert( QStringLiteral( "opis" ), tekst );
    ostrzezenia.append( o );
  };

  const QString katalog = QFileInfo( projekt->fileName() ).absolutePath();
  double najmniejszaObwiednia = -1.0;
  QString najmniejszyObiekt;

  const auto mapaWarstw = projekt->mapLayers();
  for ( auto it = mapaWarstw.constBegin(); it != mapaWarstw.constEnd(); ++it )
  {
    QgsVectorLayer *wektor = qobject_cast<QgsVectorLayer *>( it.value() );
    if ( !wektor )
      continue;

    QVariantMap w;
    w.insert( QStringLiteral( "nazwa" ), wektor->name() );
    w.insert( QStringLiteral( "geometria" ), geometriaSlownie( wektor->geometryType() ) );
    w.insert( QStringLiteral( "obiektow" ), static_cast<qlonglong>( wektor->featureCount() ) );

    // isEditable() NIE jest Q_INVOKABLE — z QML tego nie widać. Stąd cała
    // ta klasa: to jest odpowiedź na wskaźnik edycji na górnej belce.
    w.insert( QStringLiteral( "edytowalna" ), wektor->isEditable() );
    w.insert( QStringLiteral( "wEdycji" ), wektor->isEditable() && wektor->isModified() );

    const QString zrodlo = wektor->source().section( QLatin1Char( '|' ), 0, 0 );
    const QString tabela = wektor->source().contains( QLatin1String( "layername=" ) )
                             ? wektor->source().section( QLatin1String( "layername=" ), 1, 1 ).section( QLatin1Char( '|' ), 0, 0 )
                             : QString();
    w.insert( QStringLiteral( "plik" ), QFileInfo( zrodlo ).fileName() );
    w.insert( QStringLiteral( "tabela" ), tabela );

    // Warstwa wskazująca poza katalog projektu nie pojedzie ze zleceniem —
    // na telefonie będzie pusta i nikt tego nie zauważy przed wyjazdem.
    const bool wKatalogu = !katalog.isEmpty()
                           && QFileInfo( zrodlo ).absolutePath().startsWith( katalog );
    w.insert( QStringLiteral( "wKatalogu" ), wKatalogu || zrodlo.isEmpty() );
    if ( !zrodlo.isEmpty() && !wKatalogu && wektor->providerType() == QLatin1String( "ogr" ) )
      ostrzez( QStringLiteral( "uwaga" ),
               tr( "warstwa „%1” wskazuje poza katalog projektu — nie pojedzie w teren" )
                 .arg( wektor->name() ) );

    // Obiekty zwinięte do punktu i puste geometrie. Liczone Z DANYCH,
    // bo z samych ustawień tego nie widać.
    if ( wektor->geometryType() == Qgis::GeometryType::Polygon )
    {
      int puste = 0;
      QgsFeature obiekt;
      QgsFeatureIterator iterator = wektor->getFeatures();
      while ( iterator.nextFeature( obiekt ) )
      {
        const QgsGeometry geom = obiekt.geometry();
        if ( geom.isNull() )
          continue;
        if ( geom.isEmpty() )
        {
          ++puste;
          continue;
        }
        const QgsRectangle obw = geom.boundingBox();
        const double bok = std::max( obw.width(), obw.height() );
        if ( najmniejszaObwiednia < 0 || bok < najmniejszaObwiednia )
        {
          najmniejszaObwiednia = bok;
          najmniejszyObiekt = QStringLiteral( "%1 / fid %2" ).arg( wektor->name() ).arg( obiekt.id() );
        }
      }
      if ( puste > 0 )
        ostrzez( QStringLiteral( "brak" ),
                 tr( "„%1”: %2 obiektów z PUSTĄ geometrią — istnieją, "
                     "ale nie widać ich na mapie i nie da się ich zaznaczyć" )
                   .arg( wektor->name() ).arg( puste ) );
    }

    warstwy.append( w );
  }

  // --------------------------------------------------------------- pomiar
  const QgsSnappingConfig snap = projekt->snappingConfig();
  QVariantMap pomiar;
  pomiar.insert( QStringLiteral( "przyciaganieWlaczone" ), snap.enabled() );
  pomiar.insert( QStringLiteral( "tryb" ), trybSlownie( snap.mode() ) );
  pomiar.insert( QStringLiteral( "typ" ), typySlownie( snap.typeFlag() ) );
  pomiar.insert( QStringLiteral( "tolerancja" ), snap.tolerance() );
  pomiar.insert( QStringLiteral( "jednostka" ), jednostkaSlownie( snap.units() ) );
  pomiar.insert( QStringLiteral( "przeciecia" ), snap.intersectionSnapping() );
  pomiar.insert( QStringLiteral( "wlasnyObiekt" ), snap.selfSnapping() );
  pomiar.insert( QStringLiteral( "edycjaTopologiczna" ), projekt->topologicalEditing() );

  // W trybie "ustawienia per warstwa" wartosc GLOBALNA jest ignorowana.
  // Ostrzezenie czytajace ja przy tym trybie krzyczy o czyms, czego nie ma —
  // a narzedzie, ktore straszy bez powodu, uczy ludzi je ignorowac.
  Qgis::SnappingTypes typyObowiazujace = snap.typeFlag();
  if ( snap.mode() == Qgis::SnappingMode::AdvancedConfiguration )
  {
    typyObowiazujace = Qgis::SnappingTypes();
    const auto ustawieniaWarstw = snap.individualLayerSettings();
    for ( auto it = ustawieniaWarstw.constBegin(); it != ustawieniaWarstw.constEnd(); ++it )
    {
      if ( it.value().enabled() )
        typyObowiazujace |= it.value().typeFlag();
    }
    pomiar.insert( QStringLiteral( "typObowiazujacy" ), typySlownie( typyObowiazujace ) );
  }

  const int trybNakladania = projekt->readNumEntry( QStringLiteral( "Digitizing" ),
                                                    QStringLiteral( "/AvoidIntersectionsMode" ), 0 );
  const QStringList listaNakladania = projekt->readListEntry( QStringLiteral( "Digitizing" ),
                                                              QStringLiteral( "/AvoidIntersectionsList" ) );
  QStringList nazwyNakladania;
  for ( const QString &id : listaNakladania )
  {
    if ( QgsMapLayer *w = projekt->mapLayer( id ) )
      nazwyNakladania << w->name();
  }
  pomiar.insert( QStringLiteral( "unikanieNakladania" ), trybNakladania == 2 );
  pomiar.insert( QStringLiteral( "warstwyNakladania" ), nazwyNakladania );

  // Zestawienie USTAWIENIA z DANYMI — sam zrzut stanu nie złapałby awarii
  // z 25.08, bo type=3 jest poprawnym ustawieniem. Dopiero razem z rozmiarem
  // najmniejszego obiektu widać, że coś jest nie tak.
  if ( snap.enabled() && ( typyObowiazujace & Qgis::SnappingType::Segment )
       && najmniejszaObwiednia >= 0 && najmniejszaObwiednia < 2.0 )
    ostrzez( QStringLiteral( "uwaga" ),
             tr( "przyciąganie łapie segment, a najmniejszy obiekt ma %1 m (%2) — "
                 "przy takich rozmiarach wierzchołki zlepiają się w jeden punkt" )
               .arg( najmniejszaObwiednia, 0, 'f', 1 ).arg( najmniejszyObiekt ) );

  // Edycja topologiczna przy malych obiektach. TO odpowiedzialoby na pytanie
  // z 25.08 w sekunde: przy VertexMove wszystkie wierzcholki znalezione
  // w promieniu laduja w JEDNYM punkcie (qffeaturemodel.cpp:1489-1494),
  // wiec przy malym placie obrys zwija sie do zera.
  //
  // Promien bierze sie z GLOBALNYCH ustawien QGIS-a, nie z tolerancji
  // przyciagania w projekcie — mowimy o tym wprost, zeby nikt nie szukal
  // tam, gdzie nie ma czego znalezc.
  if ( projekt->topologicalEditing() && najmniejszaObwiednia >= 0
       && najmniejszaObwiednia < 5.0 )
    ostrzez( QStringLiteral( "uwaga" ),
             tr( "edycja topologiczna WŁĄCZONA, a najmniejszy obiekt ma %1 m (%2). "
                 "Przy przesuwaniu wierzchołka wszystkie sąsiednie w promieniu "
                 "trafiają w ten sam punkt — obrys małego obiektu zwija się do zera. "
                 "Działa też przy TWORZENIU, nie tylko przy poprawianiu. "
                 "Promień jest ustawieniem aplikacji, nie projektu." )
               .arg( najmniejszaObwiednia, 0, 'f', 1 ).arg( najmniejszyObiekt ) );

  if ( najmniejszaObwiednia >= 0 && najmniejszaObwiednia < 0.5 )
    ostrzez( QStringLiteral( "brak" ),
             tr( "obiekt o obwiedni %1 m (%2) — to nie jest płat, tylko zlepione wierzchołki" )
               .arg( najmniejszaObwiednia, 0, 'f', 2 ).arg( najmniejszyObiekt ) );

  // ----------------------------------------------------------------- dane
  QVariantMap dane;
  const QString plik = plikDanych( projekt );
  dane.insert( QStringLiteral( "plikDanych" ), QFileInfo( plik ).fileName() );
  dane.insert( QStringLiteral( "katalog" ), katalog );

  const bool maWskazniki = !katalog.isEmpty()
                           && QFileInfo::exists( katalog + QStringLiteral( "/wf_wskazniki.gpkg" ) );
  dane.insert( QStringLiteral( "wskazniki" ), maWskazniki );
  if ( !maWskazniki )
    ostrzez( QStringLiteral( "brak" ),
             tr( "brak wf_wskazniki.gpkg — metadane gatunków i podpowiadanie nie zadziałają" ) );

  if ( plik.isEmpty() )
    ostrzez( QStringLiteral( "brak" ),
             tr( "projekt nie ma pliku z danymi — dziennik Nieba nie ma dokąd pisać" ) );

  wynik.insert( QStringLiteral( "warstwy" ), warstwy );
  wynik.insert( QStringLiteral( "pomiar" ), pomiar );
  wynik.insert( QStringLiteral( "dane" ), dane );
  wynik.insert( QStringLiteral( "ostrzezenia" ), ostrzezenia );
  return wynik;
}

QString NarzedziaProjektu::plikDanych( QgsProject *projekt ) const
{
  if ( !projekt )
    return QString();

  QHash<QString, int> licznik;
  QString zNazwy;

  const auto warstwy = projekt->mapLayers();
  for ( auto it = warstwy.constBegin(); it != warstwy.constEnd(); ++it )
  {
    QgsVectorLayer *wektor = qobject_cast<QgsVectorLayer *>( it.value() );
    if ( !wektor || wektor->providerType() != QLatin1String( "ogr" ) )
      continue;

    const QString plik = wektor->source().section( QLatin1Char( '|' ), 0, 0 );
    if ( !plik.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive ) )
      continue;

    const QString nazwa = QFileInfo( plik ).fileName().toLower();
    if ( nazwa == QLatin1String( "data.gpkg" ) )
      return plik;
    if ( nazwa == QLatin1String( "dane.gpkg" ) && zNazwy.isEmpty() )
      zNazwy = plik;

    // podklady i slownik nie sa danymi nieodtwarzalnymi
    if ( nazwa == QLatin1String( "support.gpkg" ) || nazwa.startsWith( QLatin1String( "wf_wskazniki" ) ) )
      continue;

    licznik[plik] += 1;
  }

  if ( !zNazwy.isEmpty() )
    return zNazwy;

  QString najlepszy;
  int najwiecej = 0;
  for ( auto it = licznik.constBegin(); it != licznik.constEnd(); ++it )
  {
    if ( it.value() > najwiecej )
    {
      najwiecej = it.value();
      najlepszy = it.key();
    }
  }
  return najlepszy;
}

QVariantMap NarzedziaProjektu::migawkaBazy( const QString &gpkg, const QString &katalogDocelowy ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );

  if ( gpkg.isEmpty() || !QFile::exists( gpkg ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma pliku z danymi." ) );
    return wynik;
  }

  // 1. Dziennik WAL do pliku glownego. Bez tego kopia gubi najswiezsze
  //    transakcje — te, ktore uzytkownik wlasnie zapisal i ktore uwaza
  //    za bezpieczne.
  {
    sqlite3 *baza = nullptr;
    if ( sqlite3_open( gpkg.toUtf8().constData(), &baza ) == SQLITE_OK )
    {
      sqlite3_busy_timeout( baza, 5000 );
      sqlite3_exec( baza, "PRAGMA wal_checkpoint(TRUNCATE)", nullptr, nullptr, nullptr );
    }
    if ( baza )
      sqlite3_close( baza );
  }

  const QString katalog = katalogDocelowy.isEmpty()
                            ? QFileInfo( gpkg ).absolutePath()
                            : katalogDocelowy;
  if ( !QDir().mkpath( katalog ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się utworzyć katalogu %1" ).arg( katalog ) );
    return wynik;
  }

  const QString podstawa = QFileInfo( gpkg ).completeBaseName();
  const QString znacznik = QDateTime::currentDateTime().toString( QStringLiteral( "yyyy-MM-dd_HHmm" ) );
  QString nazwa = QStringLiteral( "%1_%2.gpkg" ).arg( podstawa, znacznik );
  QString cel = katalog + QLatin1Char( '/' ) + nazwa;

  // Nazwa niesie czas, wiec kolizja znaczy dwie migawki w tej samej minucie.
  // Nie nadpisujemy: historia migawek jest append-only (claude/DANE_workflow.md).
  int kolejna = 2;
  while ( QFile::exists( cel ) )
  {
    nazwa = QStringLiteral( "%1_%2_%3.gpkg" ).arg( podstawa, znacznik ).arg( kolejna++ );
    cel = katalog + QLatin1Char( '/' ) + nazwa;
  }

  if ( !QFile::copy( gpkg, cel ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Kopiowanie nie powiodło się." ) );
    return wynik;
  }

  // 2. Migawka sprawdza SAMA SIEBIE. Kopia zrobiona w trakcie zapisu bywa
  //    rozdarta i wyglada normalnie do chwili, w ktorej jest potrzebna.
  bool zdrowa = false;
  {
    sqlite3 *baza = nullptr;
    if ( sqlite3_open_v2( cel.toUtf8().constData(), &baza, SQLITE_OPEN_READONLY, nullptr ) == SQLITE_OK )
    {
      sqlite3_stmt *zapytanie = nullptr;
      if ( sqlite3_prepare_v2( baza, "PRAGMA quick_check", -1, &zapytanie, nullptr ) == SQLITE_OK
           && sqlite3_step( zapytanie ) == SQLITE_ROW )
      {
        const QString odpowiedz = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( zapytanie, 0 ) ) );
        zdrowa = odpowiedz.compare( QLatin1String( "ok" ), Qt::CaseInsensitive ) == 0;
      }
      sqlite3_finalize( zapytanie );
    }
    if ( baza )
      sqlite3_close( baza );
  }

  if ( !zdrowa )
  {
    QFile::remove( cel );
    wynik.insert( QStringLiteral( "blad" ), tr( "Kopia nie przeszła sprawdzenia i została skasowana. Spróbuj ponownie, gdy nic się nie zapisuje." ) );
    return wynik;
  }

  // 3. Suma kontrolna obok pliku — po drugiej stronie widac, czy dojechalo
  //    w calosci, bez otwierania bazy.
  QString suma;
  {
    QFile plik( cel );
    if ( plik.open( QIODevice::ReadOnly ) )
    {
      QCryptographicHash skrot( QCryptographicHash::Md5 );
      if ( skrot.addData( &plik ) )
        suma = QString::fromLatin1( skrot.result().toHex() );
      plik.close();
    }
  }

  if ( !suma.isEmpty() )
  {
    QFile opis( cel + QStringLiteral( ".md5" ) );
    if ( opis.open( QIODevice::WriteOnly | QIODevice::Text ) )
    {
      opis.write( QStringLiteral( "%1  %2\n" ).arg( suma, nazwa ).toUtf8() );
      opis.close();
    }
  }

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "sciezka" ), cel );
  wynik.insert( QStringLiteral( "nazwa" ), nazwa );
  wynik.insert( QStringLiteral( "md5" ), suma );
  wynik.insert( QStringLiteral( "bajty" ), QFileInfo( cel ).size() );
  return wynik;
}

QVariantMap NarzedziaProjektu::importujWarstwe( const QString &zrodloUri,
                                                const QString &celGpkg,
                                                const QString &nazwaDocelowa ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );

  if ( zrodloUri.isEmpty() || celGpkg.isEmpty() || nazwaDocelowa.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Brak źródła albo celu." ) );
    return wynik;
  }

  // Adres warstwy OGR bywa postaci "/a/b.gpkg|layername=x". GDALOpenEx tego
  // sufiksu nie rozumie — rozdzielamy sami.
  const QString plikZrodla = zrodloUri.section( QLatin1Char( '|' ), 0, 0 );
  QString warstwaZrodlowa;
  for ( const QString &czesc : zrodloUri.split( QLatin1Char( '|' ), Qt::SkipEmptyParts ) )
  {
    if ( czesc.startsWith( QLatin1String( "layername=" ) ) )
      warstwaZrodlowa = czesc.mid( 10 );
  }

  if ( !QFile::exists( plikZrodla ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma pliku %1" ).arg( plikZrodla ) );
    return wynik;
  }

  GDALAllRegister();

  // NIE NADPISUJEMY. Warstwa o tej nazwie w celu znaczy, ze ktos juz cos tam
  // ma — podmiana bylaby cicha utrata danych, a to jest dokladnie ten rodzaj
  // bledu, ktorego pilnujemy w calym obiegu.
  if ( QFile::exists( celGpkg ) )
  {
    GDALDatasetH cel = GDALOpenEx( celGpkg.toUtf8().constData(), GDAL_OF_VECTOR, nullptr, nullptr, nullptr );
    if ( cel )
    {
      const bool zajete = GDALDatasetGetLayerByName( cel, nazwaDocelowa.toUtf8().constData() ) != nullptr;
      GDALClose( cel );
      if ( zajete )
      {
        wynik.insert( QStringLiteral( "blad" ), tr( "W bazie jest już warstwa „%1”. Zmień nazwę." ).arg( nazwaDocelowa ) );
        return wynik;
      }
    }
  }

  GDALDatasetH zrodlo = GDALOpenEx( plikZrodla.toUtf8().constData(), GDAL_OF_VECTOR, nullptr, nullptr, nullptr );
  if ( !zrodlo )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się otworzyć %1 jako danych wektorowych." ).arg( QFileInfo( plikZrodla ).fileName() ) );
    return wynik;
  }

  char **argv = nullptr;
  argv = CSLAddString( argv, "-f" );
  argv = CSLAddString( argv, "GPKG" );
  argv = CSLAddString( argv, "-nln" );
  argv = CSLAddString( argv, nazwaDocelowa.toUtf8().constData() );
  if ( QFile::exists( celGpkg ) )
    argv = CSLAddString( argv, "-update" );
  if ( !warstwaZrodlowa.isEmpty() )
    argv = CSLAddString( argv, warstwaZrodlowa.toUtf8().constData() );

  GDALVectorTranslateOptions *opcje = GDALVectorTranslateOptionsNew( argv, nullptr );
  CSLDestroy( argv );
  if ( !opcje )
  {
    GDALClose( zrodlo );
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się przygotować importu." ) );
    return wynik;
  }

  int bladUzycia = FALSE;
  GDALDatasetH wyjscie = GDALVectorTranslate( celGpkg.toUtf8().constData(), nullptr,
                                              1, &zrodlo, opcje, &bladUzycia );
  GDALVectorTranslateOptionsFree( opcje );
  GDALClose( zrodlo );
  if ( wyjscie )
    GDALClose( wyjscie );

  // SPRAWDZAMY PO FAKCIE, a nie z wartosci zwracanej: interesuje nas, czy
  // warstwa jest w pliku i ile ma obiektow. Liczbe oddajemy, zeby dalo sie
  // ja porownac z oryginalem zamiast uwierzyc na slowo.
  qint64 obiektow = -1;
  GDALDatasetH sprawdzenie = GDALOpenEx( celGpkg.toUtf8().constData(), GDAL_OF_VECTOR, nullptr, nullptr, nullptr );
  if ( sprawdzenie )
  {
    OGRLayerH warstwa = GDALDatasetGetLayerByName( sprawdzenie, nazwaDocelowa.toUtf8().constData() );
    if ( warstwa )
      obiektow = OGR_L_GetFeatureCount( warstwa, TRUE );
    GDALClose( sprawdzenie );
  }

  if ( obiektow < 0 )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Import się nie udał — w bazie nie ma warstwy „%1”." ).arg( nazwaDocelowa ) );
    return wynik;
  }

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "nazwa" ), nazwaDocelowa );
  wynik.insert( QStringLiteral( "obiektow" ), obiektow );
  wynik.insert( QStringLiteral( "gpkg" ), celGpkg );
  return wynik;
}

QVariantMap NarzedziaProjektu::zrodloWarstwy( QgsMapLayer *warstwa ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );
  wynik.insert( QStringLiteral( "plik" ), QString() );
  wynik.insert( QStringLiteral( "warstwa" ), QString() );
  wynik.insert( QStringLiteral( "pelny" ), QString() );
  wynik.insert( QStringLiteral( "istnieje" ), false );
  wynik.insert( QStringLiteral( "wBazieProjektu" ), false );

  if ( !warstwa )
    return wynik;

  const QString zrodlo = warstwa->source();
  if ( zrodlo.isEmpty() )
    return wynik;

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "pelny" ), zrodlo );

  const QString plik = zrodlo.section( QLatin1Char( '|' ), 0, 0 );

  QString nazwaTabeli;
  const QStringList czesci = zrodlo.split( QLatin1Char( '|' ), Qt::SkipEmptyParts );
  for ( const QString &czesc : czesci )
  {
    if ( czesc.startsWith( QLatin1String( "layername=" ) ) )
      nazwaTabeli = czesc.mid( 10 );
  }
  wynik.insert( QStringLiteral( "warstwa" ), nazwaTabeli );

  // Sprawdzamy ISTNIENIE, a nie ksztalt napisu: adres WMS-a albo PostGIS-a
  // tez wyglada jak tekst ze sciezka w srodku, a sciezka nie jest.
  const QFileInfo info( plik );
  if ( !info.exists() || !info.isFile() )
    return wynik;

  wynik.insert( QStringLiteral( "istnieje" ), true );
  wynik.insert( QStringLiteral( "plik" ), QDir::toNativeSeparators( info.absoluteFilePath() ) );

  const QString dane = plikDanych( QgsProject::instance() );
  if ( !dane.isEmpty() )
  {
    const QString a = info.canonicalFilePath();
    const QString b = QFileInfo( dane ).canonicalFilePath();
    wynik.insert( QStringLiteral( "wBazieProjektu" ), !a.isEmpty() && a == b );
  }

  return wynik;
}


// ---------------------------------------------------------------------------
// Eksport do DXF - WorkField 19.09.2026 (wersja 2, wzorowana na QGIS desktop)
// Zrodla: src/app/qgisapp.cpp QgisApp::dxfExport()
//         src/app/qgsdxfexportdialog.cpp (klucze i wartosci domyslne)
//
// Te same klucze projektu co okno QGIS, wiec projekt ustawiony w biurze
// eksportuje sie w terenie tak samo, a to, co zapiszemy tutaj, QGIS
// w biurze odczyta. Zmienione tylko domyslne (gdy projekt ich nie ma):
//   skala symboli 1:1000 zamiast 1:50000 - przy 1:50000 symbol 1 mm
//     zamienia sie w 50 m terenu,
//   polilinie 2D - pomiar GNSS niesie Z, a CADowiec chce plaski rysunek,
//   kodowanie CP1250 zamiast CP1252 - polskie litery.
// ---------------------------------------------------------------------------
#include <QRegularExpression>
#include <QStringDecoder>
#include <algorithm>
#include <qgsdxfexport.h>
#include <qgsmapsettings.h>
#include <qgsmapthemecollection.h>

namespace
{
  QString dxfWpis( QgsProject *p, const QString &klucz, const QString &domyslnie )
  {
    return p->readEntry( QStringLiteral( "dxf" ), QStringLiteral( "/" ) + klucz, domyslnie );
  }

  bool dxfFlaga( QgsProject *p, const QString &klucz, bool domyslnie )
  {
    // QGIS porownuje z "false" - robimy dokladnie tak samo
    return dxfWpis( p, klucz, domyslnie ? QStringLiteral( "true" ) : QStringLiteral( "false" ) ) != QLatin1String( "false" );
  }

  // QgsDxfExport::writeToFile w Qt6 ustawia strumien przez
  // QStringConverter::encodingForName(), ktory zna tylko UTF-8/16/32
  // i Latin1 - dla CP1250 cicho pisze UTF-8, a w naglowku deklaruje
  // $DWGCODEPAGE ANSI_1250. Polskie litery wychodza wtedy jako krzaki.
  // Przekodowujemy plik po zapisie; tablica wygenerowana z codecs.cp1250.
  QByteArray doCp1250( const QString &tekst )
  {
    static const QHash<ushort, char> tablica = [] {
      QHash<ushort, char> t;
      const ushort pary[][2] = {
        {0x20AC,0x80}, {0x201A,0x82}, {0x201E,0x84}, {0x2026,0x85}, {0x2020,0x86}, {0x2021,0x87}, {0x2030,0x89}, {0x0160,0x8A}, {0x2039,0x8B}, {0x015A,0x8C}, {0x0164,0x8D}, {0x017D,0x8E}, {0x0179,0x8F}, {0x2018,0x91}, {0x2019,0x92}, {0x201C,0x93}, {0x201D,0x94}, {0x2022,0x95}, {0x2013,0x96}, {0x2014,0x97}, {0x2122,0x99}, {0x0161,0x9A}, {0x203A,0x9B}, {0x015B,0x9C}, {0x0165,0x9D}, {0x017E,0x9E}, {0x017A,0x9F}, {0x00A0,0xA0}, {0x02C7,0xA1}, {0x02D8,0xA2}, {0x0141,0xA3}, {0x00A4,0xA4}, {0x0104,0xA5}, {0x00A6,0xA6}, {0x00A7,0xA7}, {0x00A8,0xA8}, {0x00A9,0xA9}, {0x015E,0xAA}, {0x00AB,0xAB}, {0x00AC,0xAC}, {0x00AD,0xAD}, {0x00AE,0xAE}, {0x017B,0xAF}, {0x00B0,0xB0}, {0x00B1,0xB1}, {0x02DB,0xB2}, {0x0142,0xB3}, {0x00B4,0xB4}, {0x00B5,0xB5}, {0x00B6,0xB6}, {0x00B7,0xB7}, {0x00B8,0xB8}, {0x0105,0xB9}, {0x015F,0xBA}, {0x00BB,0xBB}, {0x013D,0xBC}, {0x02DD,0xBD}, {0x013E,0xBE}, {0x017C,0xBF}, {0x0154,0xC0}, {0x00C1,0xC1}, {0x00C2,0xC2}, {0x0102,0xC3}, {0x00C4,0xC4}, {0x0139,0xC5}, {0x0106,0xC6}, {0x00C7,0xC7}, {0x010C,0xC8}, {0x00C9,0xC9}, {0x0118,0xCA}, {0x00CB,0xCB}, {0x011A,0xCC}, {0x00CD,0xCD}, {0x00CE,0xCE}, {0x010E,0xCF}, {0x0110,0xD0}, {0x0143,0xD1}, {0x0147,0xD2}, {0x00D3,0xD3}, {0x00D4,0xD4}, {0x0150,0xD5}, {0x00D6,0xD6}, {0x00D7,0xD7}, {0x0158,0xD8}, {0x016E,0xD9}, {0x00DA,0xDA}, {0x0170,0xDB}, {0x00DC,0xDC}, {0x00DD,0xDD}, {0x0162,0xDE}, {0x00DF,0xDF}, {0x0155,0xE0}, {0x00E1,0xE1}, {0x00E2,0xE2}, {0x0103,0xE3}, {0x00E4,0xE4}, {0x013A,0xE5}, {0x0107,0xE6}, {0x00E7,0xE7}, {0x010D,0xE8}, {0x00E9,0xE9}, {0x0119,0xEA}, {0x00EB,0xEB}, {0x011B,0xEC}, {0x00ED,0xED}, {0x00EE,0xEE}, {0x010F,0xEF}, {0x0111,0xF0}, {0x0144,0xF1}, {0x0148,0xF2}, {0x00F3,0xF3}, {0x00F4,0xF4}, {0x0151,0xF5}, {0x00F6,0xF6}, {0x00F7,0xF7}, {0x0159,0xF8}, {0x016F,0xF9}, {0x00FA,0xFA}, {0x0171,0xFB}, {0x00FC,0xFC}, {0x00FD,0xFD}, {0x0163,0xFE}, {0x02D9,0xFF}
      };
      for ( const auto &para : pary )
        t.insert( para[0], static_cast<char>( para[1] ) );
      return t;
    }();

    QByteArray wynik;
    wynik.reserve( tekst.size() );
    for ( const QChar znak : tekst )
    {
      const ushort u = znak.unicode();
      if ( u < 0x80 )
        wynik.append( static_cast<char>( u ) );
      else
        wynik.append( tablica.value( u, '?' ) );
    }
    return wynik;
  }

  // Dopracowanie pliku pod CAD - WorkField 19.09.2026. Dziala na tekscie DXF
  // po eksporcie (pary: kod grupy / wartosc), niczego nie dodaje do OBJECTS
  // i nie tworzy nowych uchwytow:
  //  1. KOLOR PRZY WARSTWIE. QGIS daje kazdej warstwie kolor 1 (czerwony),
  //     a prawdziwy kolor zapisuje przy kazdym obiekcie (420). Warstwa
  //     dostaje dominujacy kolor swoich obiektow (62 = najblizszy ACI,
  //     420 = dokladny RGB), a obiekty w tym kolorze traca wlasny kolor,
  //     czyli sa "wg warstwy" - projektant przemaluje warstwe jednym
  //     kliknieciem. Inne kolory (np. wypelnienie HATCH) zostaja przy obiekcie.
  //     Punkt (INSERT) liczy sie kolorem wypelnienia swojego bloku.
  //  2. TEKST CZARNY (420 = 0) -> ACI 7: czarny na jasnym tle, bialy na
  //     ciemnym - czarny tekst na czarnym tle CAD-a bylby niewidoczny.
  //  3. CZCIONKA: Roboto z telefonu -> Arial, ktory CAD ma na pewno.
  //  4. HATCH: brakujace 230 w wektorze wyciagniecia (patrz nizej).
  QString dopracujDxf( const QString &tekst, QStringList *uwagi )
  {
    QStringList linie = tekst.split( QLatin1Char( '\n' ) );
    const bool nowaLiniaNaKoncu = tekst.endsWith( QLatin1Char( '\n' ) );
    if ( nowaLiniaNaKoncu )
      linie.removeLast();
    if ( linie.size() % 2 != 0 )
    {
      if ( uwagi )
        *uwagi << QStringLiteral( "DXF: nieparzysta liczba linii - pominieto dopracowanie kolorow" );
      return tekst;
    }
    const int par = static_cast<int>( linie.size() / 2 );
    auto kod = [&linie]( int i ) { return linie.at( 2 * i ).trimmed(); };
    auto wart = [&linie]( int i ) { return linie.at( 2 * i + 1 ).trimmed(); };

    // --- sekcje --------------------------------------------------------
    QVector<QString> sekcja( par );
    QString biezaca;
    for ( int i = 0; i < par; ++i )
    {
      if ( kod( i ) == QLatin1String( "0" ) && wart( i ) == QLatin1String( "SECTION" ) && i + 1 < par && kod( i + 1 ) == QLatin1String( "2" ) )
        biezaca = wart( i + 1 );
      sekcja[i] = biezaca;
      if ( kod( i ) == QLatin1String( "0" ) && wart( i ) == QLatin1String( "ENDSEC" ) )
        biezaca.clear();
    }

    const QSet<QString> liniowe = { QStringLiteral( "LWPOLYLINE" ), QStringLiteral( "POLYLINE" ), QStringLiteral( "LINE" ), QStringLiteral( "POINT" ), QStringLiteral( "CIRCLE" ), QStringLiteral( "ARC" ), QStringLiteral( "SPLINE" ), QStringLiteral( "ELLIPSE" ) };
    const QSet<QString> tekstowe = { QStringLiteral( "MTEXT" ), QStringLiteral( "TEXT" ) };

    // --- kolory blokow (wypelnienie, a bez niego pierwszy kolor) ----------
    QHash<QString, int> kolorBloku;
    {
      QString blok, typ;
      int wypelnienie = -1, inny = -1;
      auto zamknijBlok = [&]() {
        if ( !blok.isEmpty() )
        {
          const int k = wypelnienie >= 0 ? wypelnienie : inny;
          if ( k >= 0 )
            kolorBloku.insert( blok, k );
        }
      };
      for ( int i = 0; i < par; ++i )
      {
        if ( sekcja[i] != QLatin1String( "BLOCKS" ) )
          continue;
        if ( kod( i ) == QLatin1String( "0" ) )
        {
          typ = wart( i );
          if ( typ == QLatin1String( "BLOCK" ) )
          {
            zamknijBlok();
            blok.clear();
            wypelnienie = inny = -1;
          }
        }
        else if ( kod( i ) == QLatin1String( "2" ) && typ == QLatin1String( "BLOCK" ) && blok.isEmpty() )
          blok = wart( i );
        else if ( kod( i ) == QLatin1String( "420" ) )
        {
          const int k = wart( i ).toInt();
          if ( typ == QLatin1String( "HATCH" ) && wypelnienie < 0 )
            wypelnienie = k;
          else if ( inny < 0 )
            inny = k;
        }
      }
      zamknijBlok();
    }

    // --- obiekty w ENTITIES --------------------------------------------
    struct Obiekt
    {
        QString typ, warstwa, blok;
        int para420 = -1;
        int kolor = -1;
    };
    QVector<Obiekt> obiekty;
    for ( int i = 0; i < par; ++i )
    {
      if ( sekcja[i] != QLatin1String( "ENTITIES" ) )
        continue;
      if ( kod( i ) == QLatin1String( "0" ) )
      {
        if ( wart( i ) == QLatin1String( "SECTION" ) || wart( i ) == QLatin1String( "ENDSEC" ) )
          continue;
        Obiekt o;
        o.typ = wart( i );
        obiekty << o;
        continue;
      }
      if ( obiekty.isEmpty() )
        continue;
      Obiekt &o = obiekty.last();
      if ( kod( i ) == QLatin1String( "8" ) )
        o.warstwa = wart( i );
      else if ( kod( i ) == QLatin1String( "420" ) && o.para420 < 0 )
      {
        o.para420 = i;
        o.kolor = wart( i ).toInt();
      }
      else if ( kod( i ) == QLatin1String( "2" ) && o.typ == QLatin1String( "INSERT" ) )
        o.blok = wart( i );
    }

    // --- dominujacy kolor warstwy ----------------------------------------
    QHash<QString, QHash<int, int>> glosy;
    for ( const Obiekt &o : std::as_const( obiekty ) )
    {
      if ( liniowe.contains( o.typ ) && o.kolor >= 0 )
        glosy[o.warstwa][o.kolor] += 2;
      else if ( o.typ == QLatin1String( "HATCH" ) && o.kolor >= 0 )
        glosy[o.warstwa][o.kolor] += 1;
      else if ( o.typ == QLatin1String( "INSERT" ) && kolorBloku.contains( o.blok ) )
        glosy[o.warstwa][kolorBloku.value( o.blok )] += 2;
    }
    QHash<QString, int> kolorWarstwy;
    for ( auto it = glosy.constBegin(); it != glosy.constEnd(); ++it )
    {
      int najlepszy = -1, ile = 0;
      for ( auto k = it.value().constBegin(); k != it.value().constEnd(); ++k )
      {
        if ( k.value() > ile || ( k.value() == ile && k.key() < najlepszy ) )
        {
          najlepszy = k.key();
          ile = k.value();
        }
      }
      if ( najlepszy >= 0 )
        kolorWarstwy.insert( it.key(), najlepszy );
    }

    // --- zmiany: tabela LAYER --------------------------------------------
    QSet<int> usun;
    QHash<int, QStringList> dopiszPo;
    {
      QString typ, nazwa;
      int para62 = -1;
      bool ma420 = false;
      auto zamknijWarstwe = [&]() {
        if ( typ == QLatin1String( "LAYER" ) && para62 >= 0 && kolorWarstwy.contains( nazwa ) )
        {
          const int rgb = kolorWarstwy.value( nazwa );
          const int aci = QgsDxfExport::closestColorMatch( 0xff000000u | static_cast<unsigned int>( rgb ) );
          linie[2 * para62 + 1] = QStringLiteral( "%1" ).arg( aci, 6 );
          if ( !ma420 )
            dopiszPo.insert( para62, QStringList() << QStringLiteral( "420" ) << QString::number( rgb ) );
        }
      };
      for ( int i = 0; i < par; ++i )
      {
        if ( sekcja[i] != QLatin1String( "TABLES" ) )
          continue;
        if ( kod( i ) == QLatin1String( "0" ) )
        {
          zamknijWarstwe();
          typ = wart( i );
          nazwa.clear();
          para62 = -1;
          ma420 = false;
        }
        else if ( typ == QLatin1String( "LAYER" ) && kod( i ) == QLatin1String( "2" ) )
          nazwa = wart( i );
        else if ( typ == QLatin1String( "LAYER" ) && kod( i ) == QLatin1String( "62" ) )
          para62 = i;
        else if ( typ == QLatin1String( "LAYER" ) && kod( i ) == QLatin1String( "420" ) )
          ma420 = true;
      }
      zamknijWarstwe();
    }

    // --- zmiany: obiekty -------------------------------------------------
    int wgWarstwy = 0, tekstyAci7 = 0;
    for ( const Obiekt &o : std::as_const( obiekty ) )
    {
      if ( o.para420 < 0 )
        continue;
      if ( tekstowe.contains( o.typ ) )
      {
        if ( o.kolor == 0 )
        {
          linie[2 * o.para420] = QStringLiteral( " 62" );
          linie[2 * o.para420 + 1] = QStringLiteral( "     7" );
          ++tekstyAci7;
        }
      }
      else if ( kolorWarstwy.contains( o.warstwa ) && kolorWarstwy.value( o.warstwa ) == o.kolor )
      {
        usun.insert( o.para420 );
        ++wgWarstwy;
      }
    }

    // --- czcionka w tekstach -----------------------------------------------
    int czcionki = 0;
    for ( int i = 0; i < par; ++i )
    {
      if ( sekcja[i] == QLatin1String( "ENTITIES" ) && ( kod( i ) == QLatin1String( "1" ) || kod( i ) == QLatin1String( "3" ) ) && linie.at( 2 * i + 1 ).contains( QLatin1String( "\\fRoboto|" ) ) )
      {
        linie[2 * i + 1].replace( QLatin1String( "\\fRoboto|" ), QLatin1String( "\\fArial|" ) );
        ++czcionki;
      }
    }

    // --- HATCH bez skladowej Z wektora wyciagniecia --------------------------
    // QGIS pisze 210/220 = 0/0 i pomija 230, co daje wektor zerowy (0,0,0).
    // ezdxf/AutoCAD naprawiaja to przy wczytaniu ("Fixed extrusion vector"),
    // ale inne programy moga HATCH odrzucic. Dopisujemy 230 = 1.0.
    int hatchZ = 0;
    {
      QString typ;
      for ( int i = 0; i < par; ++i )
      {
        if ( kod( i ) == QLatin1String( "0" ) )
          typ = wart( i );
        else if ( typ == QLatin1String( "HATCH" ) && kod( i ) == QLatin1String( "220" ) && ( i + 1 >= par || kod( i + 1 ) != QLatin1String( "230" ) ) )
        {
          dopiszPo[i] << QStringLiteral( "230" ) << QStringLiteral( "1.0" );
          ++hatchZ;
        }
      }
    }

    // --- zlozenie ------------------------------------------------------------
    QStringList wynik;
    wynik.reserve( linie.size() + 2 * dopiszPo.size() );
    for ( int i = 0; i < par; ++i )
    {
      if ( usun.contains( i ) )
        continue;
      wynik << linie.at( 2 * i ) << linie.at( 2 * i + 1 );
      if ( dopiszPo.contains( i ) )
        wynik << dopiszPo.value( i );
    }
    if ( uwagi )
      *uwagi << QStringLiteral( "DXF: kolor przy %1 warstwach, %2 obiektow wg warstwy, %3 tekstow ACI 7, %4 czcionek Arial, %5 HATCH z wektorem Z" ).arg( kolorWarstwy.size() ).arg( wgWarstwy ).arg( tekstyAci7 ).arg( czcionki ).arg( hatchZ );
    QString zlozony = wynik.join( QLatin1Char( '\n' ) );
    if ( nowaLiniaNaKoncu )
      zlozony += QLatin1Char( '\n' );
    return zlozony;
  }
} // namespace

QVariantMap NarzedziaProjektu::eksportujDxf( QgsProject *projekt, const QString &sciezka, bool zRysunkiem ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || !p->layerTreeRoot() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }

  QString plik = sciezka;
  if ( plik.isEmpty() )
  {
    QString nazwa = p->title().trimmed();
    if ( nazwa.isEmpty() )
      nazwa = QFileInfo( p->homePath() ).fileName();
    if ( nazwa.isEmpty() )
      nazwa = QStringLiteral( "projekt" );
    nazwa.replace( QRegularExpression( QStringLiteral( "[\\\\/:*?\"<>|\\s]+" ) ), QStringLiteral( "_" ) ); // WFG-nazwa-dxf
    plik = QStringLiteral( "%1/export/%2_%3.dxf" ).arg( p->homePath(), nazwa, QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmm" ) ) );
  }
  if ( !plik.endsWith( QLatin1String( ".dxf" ), Qt::CaseInsensitive ) )
    plik += QLatin1String( ".dxf" );
  QDir().mkpath( QFileInfo( plik ).absolutePath() );

  // --- ustawienia: klucze i indeksy jak w qgsdxfexportdialog.cpp ---------
  Qgis::FeatureSymbologyExport symbologia = Qgis::FeatureSymbologyExport::PerSymbolLayer;
  switch ( dxfWpis( p, QStringLiteral( "lastDxfSymbologyMode" ), QStringLiteral( "2" ) ).toInt() )
  {
    case 0:
      symbologia = Qgis::FeatureSymbologyExport::NoSymbology;
      break;
    case 1:
      symbologia = Qgis::FeatureSymbologyExport::PerFeature;
      break;
    default:
      break;
  }
  // QGIS zapisuje skale jako 1/mianownik
  double odwrotnoscSkali = dxfWpis( p, QStringLiteral( "lastSymbologyExportScale" ), QStringLiteral( "0.001" ) ).toDouble();
  if ( odwrotnoscSkali <= 0 )
    odwrotnoscSkali = 0.001;
  const double skala = 1.0 / odwrotnoscSkali;

  const QString kodowanie = dxfWpis( p, QStringLiteral( "lastDxfEncoding" ), QStringLiteral( "CP1250" ) );
  const bool mtext = dxfFlaga( p, QStringLiteral( "lastDxfUseMText" ), true );
  const bool plasko = dxfFlaga( p, QStringLiteral( "lastDxfForce2d" ), true );
  const bool tytulJakoNazwa = dxfFlaga( p, QStringLiteral( "lastDxfLayerTitleAsName" ), false );
  const bool wlosowe = dxfFlaga( p, QStringLiteral( "lastDxfHairlineWidthExport" ), false );
  const QgsCoordinateReferenceSystem crs = p->crs();

  // Motyw mapy ("Visibility preset") - jesli ustawiony w biurze, decyduje
  // o warstwach i stylach, dokladnie jak w QGIS.
  const QString motyw = dxfWpis( p, QStringLiteral( "lastVisibilityPreset" ), QString() );
  const bool jestMotyw = !motyw.isEmpty() && p->mapThemeCollection()->hasMapTheme( motyw );
  QSet<QgsMapLayer *> wMotywie;
  if ( jestMotyw )
  {
    const QList<QgsMapLayer *> widoczne = p->mapThemeCollection()->mapThemeVisibleLayers( motyw );
    for ( QgsMapLayer *l : widoczne )
      wMotywie.insert( l );
  }

  // --- warstwy: w kolejnosci rysowania, jak layersInROrder w QGIS ---------
  QList<QgsDxfExport::DxfLayer> warstwy;
  QStringList nazwy;
  long long obiekty = 0;
  const QList<QgsMapLayer *> kolejnosc = p->layerTreeRoot()->layerOrder();
  for ( QgsMapLayer *ml : kolejnosc )
  {
    QgsVectorLayer *vl = qobject_cast<QgsVectorLayer *>( ml );
    if ( !vl || !vl->isValid() || !vl->isSpatial() )
      continue;
    QgsLayerTreeLayer *wezel = p->layerTreeRoot()->findLayer( vl );
    if ( !wezel )
      continue;
    if ( jestMotyw ? !wMotywie.contains( vl ) : !wezel->isVisible() )
      continue;

    const QString nazwa = vl->name();
    if ( nazwa.startsWith( QLatin1String( "ZAL_" ), Qt::CaseInsensitive )
         || nazwa.startsWith( QLatin1String( "REF_" ), Qt::CaseInsensitive ) )
      continue;

    // Rysunek zrodlowy projektant juz ma - nie odsylamy go w dublu.
    bool wRysunku = nazwa.startsWith( QLatin1String( "Rysunek CAD" ) );
    for ( QgsLayerTreeNode *rodzic = wezel->parent(); rodzic && !wRysunku; rodzic = rodzic->parent() )
    {
      if ( QgsLayerTree::isGroup( rodzic ) && QgsLayerTree::toGroup( rodzic )->name() == QLatin1String( "Rysunek CAD" ) )
        wRysunku = true;
    }
    if ( wRysunku && !zRysunkiem )
      continue;

    // Ustawienia per warstwa - te same wlasciwosci, ktore zapisuje okno QGIS:
    // atrybut dzielacy na warstwy DXF i bloki z symboli zaleznych od danych.
    const int atrybut = vl->fields().lookupField( vl->customProperty( QStringLiteral( "lastDxfOutputAttribute" ), QString() ).toString() );
    const bool bloki = vl->customProperty( QStringLiteral( "lastAllowDataDefinedBlocks" ), DEFAULT_DXF_DATA_DEFINED_BLOCKS ).toBool();
    const int maksBlokow = vl->customProperty( QStringLiteral( "lastMaximumNumberOfBlocks" ), -1 ).toInt();

    warstwy << QgsDxfExport::DxfLayer( vl, atrybut, bloki, maksBlokow );
    nazwy << nazwa;
    obiekty += std::max<long long>( 0, vl->featureCount() );
  }

  if ( warstwy.isEmpty() || obiekty == 0 )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie ma czego eksportować — widoczne warstwy nie mają obiektów" ) );
    return wynik;
  }

  // --- ustawienia mapy: QGIS bierze je z plotna; tu skladamy z projektu -----
  QgsMapSettings ustawienia;
  ustawienia.setDestinationCrs( crs );
  ustawienia.setTransformContext( p->transformContext() );
  ustawienia.setEllipsoid( p->ellipsoid() );
  ustawienia.setLabelingEngineSettings( p->labelingEngineSettings() );
  if ( jestMotyw )
    ustawienia.setLayerStyleOverrides( p->mapThemeCollection()->mapThemeStyleOverrides( motyw ) );

  QgsDxfExport dxf;
  dxf.setMapSettings( ustawienia );
  dxf.addLayers( warstwy );
  dxf.setSymbologyScale( skala );
  dxf.setSymbologyExport( symbologia );
  dxf.setLayerTitleAsName( tytulJakoNazwa );
  dxf.setDestinationCrs( crs );
  dxf.setForce2d( plasko );

  QgsDxfExport::Flags flagi = QgsDxfExport::Flags();
  if ( !mtext )
    flagi = flagi | QgsDxfExport::FlagNoMText;
  if ( wlosowe )
    flagi = flagi | QgsDxfExport::FlagHairlineWidthExport;
  dxf.setFlags( flagi );

  QFile f( plik );
  const QgsDxfExport::ExportResult r = dxf.writeToFile( &f, kodowanie );
  if ( f.isOpen() )
    f.close();

  if ( r != QgsDxfExport::ExportResult::Success )
  {
    QString opis;
    switch ( r )
    {
      case QgsDxfExport::ExportResult::EmptyExtentError:
        opis = QStringLiteral( "nie da się ustalić zasięgu" );
        break;
      case QgsDxfExport::ExportResult::DeviceNotWritableError:
        opis = QStringLiteral( "nie można zapisać pliku" );
        break;
      default:
        opis = QStringLiteral( "nieprawidłowy plik docelowy" );
        break;
    }
    QFile::remove( plik );
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Eksport DXF nie powiódł się: %1" ).arg( opis ) );
    return wynik;
  }

  // --- dopracowanie pod CAD i kodowanie (patrz dopracujDxf, doCp1250) ----
  // Plik jest juz kompletny: f.close() oddal bufor QTextStream (aboutToClose).
  QStringList uwagi;
  if ( !dxf.feedbackMessage().isEmpty() )
    uwagi << dxf.feedbackMessage();
  {
    QFile g( plik );
    if ( g.open( QIODevice::ReadOnly ) )
    {
      const QByteArray bajty = g.readAll();
      g.close();
      QStringDecoder dekoder( QStringDecoder::Utf8 );
      QString tekst = dekoder( bajty );
      // Nie-UTF-8 znaczy, ze QGIS (inna wersja Qt) zapisal juz we wlasciwym
      // kodowaniu - wtedy nie ruszamy pliku wcale.
      if ( dekoder.hasError() )
      {
        uwagi << QStringLiteral( "DXF nie jest w UTF-8 - pominieto dopracowanie i przekodowanie" );
      }
      else
      {
        tekst = dopracujDxf( tekst, &uwagi );
        QByteArray wyjscie;
        if ( kodowanie.compare( QLatin1String( "CP1250" ), Qt::CaseInsensitive ) == 0 )
        {
          wyjscie = doCp1250( tekst );
        }
        else
        {
          wyjscie = tekst.toUtf8();
          if ( kodowanie.compare( QLatin1String( "UTF-8" ), Qt::CaseInsensitive ) != 0 && wyjscie.size() != tekst.size() )
            uwagi << QStringLiteral( "Kodowanie %1 nieobsługiwane w Qt6 - znaki spoza ASCII mogą być błędne; użyj CP1250 albo UTF-8" ).arg( kodowanie );
        }
        if ( g.open( QIODevice::WriteOnly | QIODevice::Truncate ) )
        {
          g.write( wyjscie );
          g.close();
        }
        else
        {
          uwagi << QStringLiteral( "Nie mogę zapisać dopracowanego DXF: %1" ).arg( plik );
        }
      }
    }
  }

  // Zapis ustawien - jak QGIS po udanym eksporcie; biuro zobaczy to samo.
  p->writeEntry( QStringLiteral( "dxf" ), QStringLiteral( "/lastDxfSymbologyMode" ), symbologia == Qgis::FeatureSymbologyExport::NoSymbology ? 0 : ( symbologia == Qgis::FeatureSymbologyExport::PerFeature ? 1 : 2 ) );
  p->writeEntry( QStringLiteral( "dxf" ), QStringLiteral( "/lastSymbologyExportScale" ), odwrotnoscSkali );
  p->writeEntry( QStringLiteral( "dxf" ), QStringLiteral( "/lastDxfEncoding" ), kodowanie );
  p->writeEntry( QStringLiteral( "dxf" ), QStringLiteral( "/lastDxfUseMText" ), mtext );
  p->writeEntry( QStringLiteral( "dxf" ), QStringLiteral( "/lastDxfForce2d" ), plasko );

  wynik.insert( QStringLiteral( "plik" ), plik );
  wynik.insert( QStringLiteral( "warstwy" ), nazwy );
  wynik.insert( QStringLiteral( "obiekty" ), obiekty );
  wynik.insert( QStringLiteral( "uwagi" ), uwagi.join( QStringLiteral( "\n" ) ) );
  return wynik;
}
