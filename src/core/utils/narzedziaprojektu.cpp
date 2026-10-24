/***************************************************************************
  narzedziaprojektu.cpp - NarzedziaProjektu

 ---------------------
 WorkField: czasowniki do budowania i doposazania projektu, wystawione do QML.
 Patrz narzedziaprojektu.h i docs/WYPOSAZENIE.md.
 ***************************************************************************/

#include "narzedziaprojektu.h"
#include "featureidentity.h" // [WF-SPLIT-IDENTITY]
#include "splitheirutils.h"  // [WF-SPLIT-HEIR]
#include <QSet>                    // [WF-IDENTITY]
#include <qgsfeaturerequest.h>     // [WF-IDENTITY]
#include <qgsproviderregistry.h>   // [WF-IDENTITY]
#include <qgsvariantutils.h>       // [WF-IDENTITY]
#include <qgsvectordataprovider.h> // [WF-IDENTITY]

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QDomDocument> // WF-DUPLIKAT
#include <QRegularExpression> // WF-DUPLIKAT

#include <sqlite3.h>
#include "wfcad/eksport.hpp" // WF-EKSPORT-CAD
#include "zalaczniki.h"        // WF-NEW-LAYER

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
#include <qgsreadwritecontext.h> // WF-DUPLIKAT
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

  // Identyfikator jest jednoznaczny — jesli pasuje, nie ma o czym mowic.
  if ( QgsVectorLayer *warstwa = qobject_cast<QgsVectorLayer *>( projekt->mapLayer( nazwaLubId ) ) )
    return warstwa;

  // KONWENCJA QFieldSync. Po synchronizacji warstwa nazywa sie
  // „plik — warstwa", wiec „tyczenie" staje sie „projekt — tyczenie".
  //
  // Pasek szybkiego zapisu wiedzial o tym od dawna
  // (`QfQuickCaptureBar.findLayerByName`), a kontrola projektu nie —
  // i 24.09.2026 zglosila „brak warstwy tyczenia" przy warstwie, ktora
  // byla na miejscu i z ktorej kafel spokojnie korzystal. Dwa miejsca,
  // dwa sposoby szukania tego samego: to musialo kiedys wyjsc.
  //
  // Kolejnosc jest OD NAJSCISLEJSZEJ, zeby luzniejsza regula nigdy nie
  // wygrala z dokladna — inaczej „drzewa" mogloby trafic w „stare drzewa"
  // przy dwoch warstwach o podobnych nazwach.
  const QString szukana = nazwaLubId.trimmed();
  QgsVectorLayer *koncowka = nullptr;
  QgsVectorLayer *bezWielkosci = nullptr;
  QgsVectorLayer *koncowkaBezWielkosci = nullptr;

  const QString mysllnik = QStringLiteral( "\u2014 " ) + szukana;  // em dash + spacja
  const QString dywiz = QStringLiteral( "- " ) + szukana;

  const QList<QgsMapLayer *> wszystkie = projekt->mapLayers().values();
  for ( QgsMapLayer *kandydat : wszystkie )
  {
    QgsVectorLayer *warstwa = qobject_cast<QgsVectorLayer *>( kandydat );
    if ( !warstwa )
      continue;

    const QString nazwa = warstwa->name().trimmed();

    if ( nazwa == szukana )
      return warstwa;

    if ( !koncowka && ( nazwa.endsWith( mysllnik ) || nazwa.endsWith( dywiz ) ) )
      koncowka = warstwa;

    if ( !bezWielkosci && nazwa.compare( szukana, Qt::CaseInsensitive ) == 0 )
      bezWielkosci = warstwa;

    if ( !koncowkaBezWielkosci
         && ( nazwa.endsWith( mysllnik, Qt::CaseInsensitive )
              || nazwa.endsWith( dywiz, Qt::CaseInsensitive ) ) )
      koncowkaBezWielkosci = warstwa;
  }

  if ( koncowka )
    return koncowka;
  if ( bezWielkosci )
    return bezWielkosci;
  if ( koncowkaBezWielkosci )
    return koncowkaBezWielkosci;

  // WorkField 6.10.2026 [WF-NAZWA-TABELI] — OSTATNIA, NAJLUZNIEJSZA REGULA:
  // po nazwie TABELI w GeoPackage (`layername=` w zrodle warstwy).
  //
  // Od 6.10 nazwe w legendzie mozna zmienic w oknie wlasciwosci warstwy,
  // a przepisy szablonow znaja warstwy po nazwie tabeli („punkty”). Bez
  // tej reguly doposazanie nie poznaloby przemianowanej warstwy i probowaloby
  // zalozyc tabele, ktora juz jest — z danymi w srodku. Tabela sie nie
  // zmienia razem z legenda, wiec po niej warstwe poznajemy zawsze.
  for ( QgsMapLayer *kandydat : wszystkie )
  {
    QgsVectorLayer *warstwa = qobject_cast<QgsVectorLayer *>( kandydat );
    if ( !warstwa || warstwa->providerType() != QLatin1String( "ogr" ) )
      continue;

    const QStringList czesci = warstwa->source().split( QLatin1Char( '|' ), Qt::SkipEmptyParts );
    for ( const QString &czesc : czesci )
    {
      if ( czesc.startsWith( QLatin1String( "layername=" ) ) && czesc.mid( 10 ) == szukana )
        return warstwa;
    }
  }

  // Cisza jest najgorszym objawem — niech w logu zostanie, CZEGO szukano.
  // Bez tego „brak warstwy X" nie mowi, czy warstwy nie ma, czy nazywa sie
  // inaczej, niz ktokolwiek zakladal.
  qWarning( "WorkField/NarzedziaProjektu: nie znalazlem warstwy \"%s\" wsrod %d warstw projektu",
            szukana.toUtf8().constData(), static_cast<int>( wszystkie.size() ) );

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

namespace
{
  /**
   * Wezel na SAM DOL swojego rodzica - ta sama droga co przesunWarstwe:
   * most drzewo-rejestr wylaczony, klon wstawiony na koncu, oryginal usuniety
   * (samo przeniesienie wskaznika gubi warstwe - 18.09.2026).
   */
  bool wezelNaDol( QgsProject *p, QgsLayerTreeNode *wezel )
  {
    if ( !p || !wezel )
      return false;
    QgsLayerTreeGroup *rodzic = qobject_cast<QgsLayerTreeGroup *>( wezel->parent() );
    if ( !rodzic )
      return false;
    if ( rodzic->children().indexOf( wezel ) == rodzic->children().count() - 1 )
      return true; // juz na dole
    QgsLayerTreeRegistryBridge *most = p->layerTreeRegistryBridge();
    const bool bylWlaczony = most && most->isEnabled();
    if ( most )
      most->setEnabled( false );
    bool ok = false;
    if ( QgsLayerTreeNode *kopia = wezel->clone() )
    {
      kopia->setExpanded( wezel->isExpanded() );
      rodzic->addChildNode( kopia );
      rodzic->removeChildNode( wezel );
      ok = true;
    }
    if ( most && bylWlaczony )
      most->setEnabled( true );
    return ok;
  }
} // namespace

bool NarzedziaProjektu::naDol( QgsProject *projekt, QgsMapLayer *warstwa ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || !warstwa )
    return false;
  return wezelNaDol( p, p->layerTreeRoot()->findLayer( warstwa->id() ) );
}

bool NarzedziaProjektu::grupaNaDol( QgsProject *projekt, const QString &nazwaGrupy ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || nazwaGrupy.isEmpty() )
    return false;
  return wezelNaDol( p, p->layerTreeRoot()->findGroup( nazwaGrupy ) );
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
  QStringList newUuids; // [WF-SPLIT-HEIR]
  const int uuidIndex = FeatureIdentity::uuidFieldIndex( layer->fields() );

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
    FeatureIdentity::assignNewUuid( copy ); // [WF-SPLIT-IDENTITY] a new part is a new object

    if ( layer->addFeature( copy ) )
    {
      created << QVariant::fromValue( static_cast<qlonglong>( copy.id() ) );
      if ( uuidIndex >= 0 )
        newUuids << copy.attribute( uuidIndex ).toString();
    }
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
  // [WF-SPLIT-HEIR] the user picks the heir and the photos in a dialog
  if ( done )
    SplitHeirUtils::announceSplit( layer, fid, newUuids );
  result.insert( QStringLiteral( "message" ), done
                                                ? tr( "Rozdzielono na %1 obiektów." ).arg( parts.size() )
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

// ---------------------------------------------------------------------------
// [WF-BAD-LAYERS] Layers that did not load
// ---------------------------------------------------------------------------
namespace
{
  //! Table name from "file.gpkg|layername=TABLE" (empty when there is none).
  QString tableFromSource( const QString &source )
  {
    const int i = source.indexOf( QStringLiteral( "layername=" ), 0, Qt::CaseInsensitive );
    return i < 0 ? QString() : source.mid( i + 10 ).section( '|', 0, 0 );
  }

  //! A photo (attachment) layer: table ZAL_… or layer name zal_….
  bool isAttachmentLayer( const QgsMapLayer *layer )
  {
    return tableFromSource( layer->source() ).startsWith( QStringLiteral( "ZAL_" ), Qt::CaseInsensitive )
           || layer->name().startsWith( QStringLiteral( "zal_" ), Qt::CaseInsensitive );
  }

  //! The valid layer this photo layer belongs to (via a relation), or nullptr.
  QgsVectorLayer *attachmentParent( QgsProject *project, const QgsMapLayer *layer )
  {
    const QMap<QString, QgsRelation> relations = project->relationManager()->relations();
    for ( auto it = relations.constBegin(); it != relations.constEnd(); ++it )
    {
      if ( it.value().referencingLayerId() != layer->id() )
        continue;
      QgsVectorLayer *parent = qobject_cast<QgsVectorLayer *>( project->mapLayer( it.value().referencedLayerId() ) );
      if ( parent && parent->isValid() )
        return parent;
    }
    return nullptr;
  }

  //! Removes every relation the layer takes part in, then the layer itself.
  void removeLayerWithRelations( QgsProject *project, const QString &layerId )
  {
    const QMap<QString, QgsRelation> relations = project->relationManager()->relations();
    for ( auto it = relations.constBegin(); it != relations.constEnd(); ++it )
    {
      if ( it.value().referencingLayerId() == layerId || it.value().referencedLayerId() == layerId )
        project->relationManager()->removeRelation( it.key() );
    }
    project->removeMapLayer( layerId );
  }
} // namespace

bool NarzedziaProjektu::usesPhytosociology( QgsProject *project ) const
{
  if ( !project )
    return false;
  static const QStringList moduleLayers = { QStringLiteral( "gatunki" ), QStringLiteral( "zdjecia_fito" ), QStringLiteral( "platy" ), QStringLiteral( "platy_zalazki" ) };
  const QMap<QString, QgsMapLayer *> layers = project->mapLayers();
  for ( QgsMapLayer *layer : layers )
  {
    if ( !layer )
      continue;
    if ( moduleLayers.contains( layer->name().trimmed().toLower() ) || moduleLayers.contains( tableFromSource( layer->source() ).toLower() ) )
      return true;
  }
  return false;
}

QVariantList NarzedziaProjektu::invalidLayers( QgsProject *project ) const
{
  QVariantList out;
  if ( !project )
    return out;
  const QMap<QString, QgsMapLayer *> layers = project->mapLayers();
  for ( QgsMapLayer *layer : layers )
  {
    if ( !layer || layer->isValid() )
      continue;
    QVariantMap m;
    m.insert( QStringLiteral( "name" ), layer->name() );
    m.insert( QStringLiteral( "id" ), layer->id() );
    m.insert( QStringLiteral( "source" ), layer->publicSource() );
    m.insert( QStringLiteral( "table" ), tableFromSource( layer->source() ) );
    QString kind = QStringLiteral( "other" );
    if ( isAttachmentLayer( layer ) )
    {
      QgsVectorLayer *parent = attachmentParent( project, layer );
      kind = parent ? QStringLiteral( "attachments_missing" ) : QStringLiteral( "attachments_orphan" );
      if ( parent )
        m.insert( QStringLiteral( "parent" ), parent->name() );
    }
    m.insert( QStringLiteral( "kind" ), kind );
    out << m;
  }
  return out;
}

QVariantMap NarzedziaProjektu::repairInvalidLayers( QgsProject *project, bool removeOthers )
{
  QVariantMap result;
  QStringList removed, recreated, left, errors;
  if ( !project )
  {
    result.insert( QStringLiteral( "ok" ), false );
    result.insert( QStringLiteral( "opis" ), tr( "Brak projektu." ) );
    return result;
  }

  QStringList parentIds;
  const QVariantList bad = invalidLayers( project );
  for ( const QVariant &v : bad )
  {
    const QVariantMap m = v.toMap();
    const QString kind = m.value( QStringLiteral( "kind" ) ).toString();
    const QString name = m.value( QStringLiteral( "name" ) ).toString();
    const QString id = m.value( QStringLiteral( "id" ) ).toString();
    if ( kind == QLatin1String( "attachments_missing" ) )
    {
      QgsVectorLayer *parent = attachmentParent( project, project->mapLayer( id ) );
      removeLayerWithRelations( project, id );
      if ( parent && !parentIds.contains( parent->id() ) )
        parentIds << parent->id();
    }
    else if ( kind == QLatin1String( "attachments_orphan" ) || removeOthers )
    {
      removeLayerWithRelations( project, id );
      removed << name;
    }
    else
    {
      left << name;
    }
  }

  for ( const QString &parentId : std::as_const( parentIds ) )
  {
    QgsVectorLayer *parent = qobject_cast<QgsVectorLayer *>( project->mapLayer( parentId ) );
    if ( !parent )
      continue;
    const ModulZalacznikow::Wynik w = ModulZalacznikow::setUp( project, parent );
    if ( w.ok )
      recreated << parent->name();
    else
      errors << QStringLiteral( "%1: %2" ).arg( parent->name(), w.opis );
  }

  QStringList parts;
  if ( !removed.isEmpty() )
    parts << tr( "Usunięto z projektu warstwy, które nie działały (nie było ich tabel w bazie): %1." ).arg( removed.join( QStringLiteral( ", " ) ) );
  if ( !recreated.isEmpty() )
    parts << tr( "Założono nową, pustą tabelę zdjęć dla warstw: %1." ).arg( recreated.join( QStringLiteral( ", " ) ) );
  if ( !left.isEmpty() )
    parts << tr( "Do decyzji (źródło do poprawienia albo usunięcia): %1." ).arg( left.join( QStringLiteral( ", " ) ) );
  if ( !errors.isEmpty() )
    parts << tr( "Nie wyszło: %1." ).arg( errors.join( QStringLiteral( "; " ) ) );
  if ( parts.isEmpty() )
    parts << tr( "Wszystkie warstwy projektu się wczytały — nie ma czego naprawiać." );

  qInfo() << "WFG bad layers: removed" << removed << "recreated" << recreated << "left" << left << "errors" << errors;
  result.insert( QStringLiteral( "ok" ), errors.isEmpty() );
  result.insert( QStringLiteral( "removed" ), removed );
  result.insert( QStringLiteral( "recreated" ), recreated );
  result.insert( QStringLiteral( "left" ), left );
  result.insert( QStringLiteral( "opis" ), parts.join( QLatin1Char( ' ' ) ) );
  return result;
}

QVariantMap NarzedziaProjektu::removeInvalidLayer( QgsProject *project, const QString &layerName )
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !project )
    return result;
  const QList<QgsMapLayer *> found = project->mapLayersByName( layerName );
  for ( QgsMapLayer *layer : found )
  {
    if ( layer && !layer->isValid() )
    {
      removeLayerWithRelations( project, layer->id() );
      result.insert( QStringLiteral( "ok" ), true );
      result.insert( QStringLiteral( "opis" ), tr( "Warstwa „%1” usunięta z projektu." ).arg( layerName ) );
      return result;
    }
  }
  result.insert( QStringLiteral( "opis" ), tr( "Nie ma w projekcie niewczytanej warstwy „%1”." ).arg( layerName ) );
  return result;
}

// ===========================================================================
// [WF-IDENTITY] 24.10.2026 — uuid of objects, PARENT_UUID of children
// ===========================================================================
// Decisions: claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md (Piotr).
// `fid` is the row number inside one file; it drifts when returns are merged.
// `uuid` is the identity of a row (object or attachment), `PARENT_UUID` in
// a child table (ZAL_*, species list) points at the uuid of its parent —
// a second key, so a link broken by drifting fid can be found and rebuilt.
//
// Three verbs, different weight:
//   identityIssues      reads only; goes into stanProjektu() as "dane"
//   fillMissingIdentity fills EMPTY values where the fields exist; no schema
//                       change; runs on every project load
//   repairIdentity      the button: adds missing fields (schema change, so
//                       only on request), configures them, fills values,
//                       renews repeated uuids
// A PARENT_UUID that DISAGREES with the relation is never overwritten here:
// one of the two keys is wrong and only a human can tell which.
namespace
{
  QString identityTableName( const QgsVectorLayer *layer )
  {
    const QVariantMap parts = QgsProviderRegistry::instance()->decodeUri( layer->providerType(), layer->source() );
    const QString name = parts.value( QStringLiteral( "layerName" ) ).toString();
    return name.isEmpty() ? layer->name() : name;
  }

  //! Working layers of the project: editable GeoPackage tables, without the
  //! technical ones (WF_*: our own bookkeeping, NIEBO_*: 70 000 rows of GNSS
  //! epochs, REF_*: reference layers nobody edits).
  bool carriesIdentity( const QgsVectorLayer *layer )
  {
    if ( !layer || !layer->isValid() || layer->readOnly() || layer->providerType() != QLatin1String( "ogr" ) )
      return false;
    const QString path = QgsProviderRegistry::instance()->decodeUri( layer->providerType(), layer->source() ).value( QStringLiteral( "path" ) ).toString();
    if ( !path.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive ) )
      return false;
    const QString table = identityTableName( layer ).toUpper();
    for ( const QString &prefix : { QStringLiteral( "WF_" ), QStringLiteral( "NIEBO_" ), QStringLiteral( "REF_" ) } )
    {
      if ( table.startsWith( prefix ) )
        return false;
    }
    return true;
  }

  //! The one relation in which \a child is the child. Invalid when there is
  //! none or more than one (one PARENT_UUID cannot serve two parents).
  QgsRelation identityParentRelation( QgsProject *project, QgsVectorLayer *child )
  {
    QList<QgsRelation> found;
    const QList<QgsRelation> relations = project->relationManager()->referencingRelations( child );
    for ( const QgsRelation &relation : relations )
    {
      if ( relation.isValid() && relation.referencedLayer() && relation.referencedLayer() != child && carriesIdentity( relation.referencedLayer() ) )
        found << relation;
    }
    return found.size() == 1 ? found.first() : QgsRelation();
  }

  QString identityKey( const QgsFeature &feature, const QList<int> &indexes )
  {
    QStringList parts;
    for ( const int index : indexes )
    {
      const QVariant value = index >= 0 ? feature.attribute( index ) : QVariant();
      if ( QgsVariantUtils::isNull( value ) )
        return QString();
      parts << value.toString();
    }
    return parts.join( QChar( 0x1f ) );
  }

  bool isEmptyValue( const QVariant &value )
  {
    return QgsVariantUtils::isNull( value ) || value.toString().trimmed().isEmpty();
  }

  //! Parent key (referenced fields) → parent uuid.
  QHash<QString, QString> identityParentMap( const QgsRelation &relation )
  {
    QHash<QString, QString> result;
    QgsVectorLayer *parent = relation.referencedLayer();
    const int uuidIndex = FeatureIdentity::uuidFieldIndex( parent->fields() );
    if ( uuidIndex < 0 )
      return result;
    QList<int> keyIndexes;
    for ( const QgsRelation::FieldPair &pair : relation.fieldPairs() )
      keyIndexes << parent->fields().lookupField( pair.referencedField() );

    QgsAttributeList wanted = keyIndexes;
    wanted << uuidIndex;
    QgsFeatureRequest request;
    request.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
    request.setSubsetOfAttributes( wanted );
    QgsFeatureIterator it = parent->getFeatures( request );
    QgsFeature feature;
    while ( it.nextFeature( feature ) )
    {
      const QString key = identityKey( feature, keyIndexes );
      const QVariant uuid = feature.attribute( uuidIndex );
      if ( !key.isEmpty() && !isEmptyValue( uuid ) )
        result.insert( key, uuid.toString() );
    }
    return result;
  }

  struct IdentityCounts
  {
    int emptyUuid = 0;
    int repeatedUuid = 0;
    int emptyParentUuid = 0;
    int disagreeingParentUuid = 0;
  };

  /**
   * Walks the rows of \a layer once. With \a write, fills what is empty
   * (uuid, and PARENT_UUID from the relation) and, with \a renewRepeated,
   * gives a new uuid to every repeat but the oldest (lowest fid) row.
   * \a ambiguous collects uuids that were repeated (and renewed); a child
   * whose PARENT_UUID is one of them was filled from an ambiguous value,
   * so there — and only there — the relation (fid) decides.
   * Returns the number of values written.
   */
  int identityPass( QgsProject *project, QgsVectorLayer *layer, bool write, bool renewRepeated, IdentityCounts &counts, QSet<QString> *ambiguous = nullptr )
  {
    const int uuidIndex = FeatureIdentity::uuidFieldIndex( layer->fields() );
    const int parentUuidIndex = FeatureIdentity::fieldIndex( layer->fields(), FeatureIdentity::parentUuidFieldName() );
    if ( uuidIndex < 0 && parentUuidIndex < 0 )
      return 0;

    const QgsRelation relation = parentUuidIndex >= 0 ? identityParentRelation( project, layer ) : QgsRelation();
    QHash<QString, QString> parents;
    QList<int> childKeyIndexes;
    if ( relation.isValid() )
    {
      parents = identityParentMap( relation );
      for ( const QgsRelation::FieldPair &pair : relation.fieldPairs() )
        childKeyIndexes << layer->fields().lookupField( pair.referencingField() );
    }

    QgsAttributeList wanted = childKeyIndexes;
    if ( uuidIndex >= 0 )
      wanted << uuidIndex;
    if ( parentUuidIndex >= 0 )
      wanted << parentUuidIndex;
    QgsFeatureRequest request;
    request.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
    request.setSubsetOfAttributes( wanted );
    request.addOrderBy( QStringLiteral( "$id" ), true );

    QHash<QString, int> seen;
    QgsChangedAttributesMap changes;
    QgsFeatureIterator it = layer->getFeatures( request );
    QgsFeature feature;
    while ( it.nextFeature( feature ) )
    {
      QgsAttributeMap rowChanges;
      if ( uuidIndex >= 0 )
      {
        const QVariant uuid = feature.attribute( uuidIndex );
        if ( isEmptyValue( uuid ) )
        {
          counts.emptyUuid++;
          rowChanges.insert( uuidIndex, FeatureIdentity::newUuid() );
        }
        else if ( seen.contains( uuid.toString() ) )
        {
          counts.repeatedUuid++;
          if ( renewRepeated )
          {
            rowChanges.insert( uuidIndex, FeatureIdentity::newUuid() );
            if ( ambiguous )
              ambiguous->insert( uuid.toString() );
          }
        }
        else
        {
          seen.insert( uuid.toString(), 1 );
        }
      }
      if ( parentUuidIndex >= 0 && relation.isValid() )
      {
        const QString expected = parents.value( identityKey( feature, childKeyIndexes ) );
        const QVariant current = feature.attribute( parentUuidIndex );
        if ( isEmptyValue( current ) )
        {
          if ( !expected.isEmpty() )
          {
            counts.emptyParentUuid++;
            rowChanges.insert( parentUuidIndex, expected );
          }
        }
        else if ( !expected.isEmpty() && current.toString() != expected )
        {
          if ( ambiguous && ambiguous->contains( current.toString() ) )
            rowChanges.insert( parentUuidIndex, expected );
          else
            counts.disagreeingParentUuid++;
        }
      }
      if ( !rowChanges.isEmpty() )
        changes.insert( feature.id(), rowChanges );
    }

    if ( !write || changes.isEmpty() )
      return 0;
    if ( layer->isEditable() || !( layer->dataProvider()->capabilities() & Qgis::VectorProviderCapability::ChangeAttributeValues ) )
      return 0;
    if ( !layer->dataProvider()->changeAttributeValues( changes ) )
      return 0;
    int written = 0;
    for ( auto it2 = changes.constBegin(); it2 != changes.constEnd(); ++it2 )
      written += it2.value().size();
    return written;
  }

  //! Field configuration: default given once, hidden, new value on split
  //! and on duplicate (QGIS on the desktop as well), Polish alias.
  void configureIdentityField( QgsVectorLayer *layer, int index, const QString &defaultExpression, const QString &alias )
  {
    layer->setDefaultValueDefinition( index, QgsDefaultValue( defaultExpression, false ) );
    layer->setEditorWidgetSetup( index, QgsEditorWidgetSetup( QStringLiteral( "Hidden" ), QVariantMap() ) );
    layer->setFieldAlias( index, alias );
    layer->setFieldSplitPolicy( index, Qgis::FieldDomainSplitPolicy::DefaultValue );
#if _QGIS_VERSION_INT >= 33800
    layer->setFieldDuplicatePolicy( index, Qgis::FieldDuplicatePolicy::DefaultValue );
#endif
  }

  //! Adds a TEXT field when missing. Returns its index, -1 when impossible.
  int ensureTextField( QgsVectorLayer *layer, const QString &name, bool &added )
  {
    added = false;
    int index = FeatureIdentity::fieldIndex( layer->fields(), name );
    if ( index >= 0 )
      return index;
    if ( layer->isEditable() || !( layer->dataProvider()->capabilities() & Qgis::VectorProviderCapability::AddAttributes ) )
      return -1;
    if ( !layer->dataProvider()->addAttributes( { QgsField( name, QMetaType::Type::QString, QStringLiteral( "TEXT" ) ) } ) )
      return -1;
    layer->updateFields();
    added = true;
    return FeatureIdentity::fieldIndex( layer->fields(), name );
  }
} // namespace

static bool isAttachmentTable( const QgsVectorLayer *layer );
static int parentRelationCount( QgsProject *project, QgsVectorLayer *layer );

QVariantList NarzedziaProjektu::identityIssues( QgsProject *project ) const
{
  QVariantList result;
  if ( !project )
    return result;

  auto issue = [&result]( const QString &kind, const QString &layer, int count ) {
    QVariantMap m;
    m.insert( QStringLiteral( "kind" ), kind );
    m.insert( QStringLiteral( "layer" ), layer );
    m.insert( QStringLiteral( "count" ), count );
    result << m;
  };

  const auto layers = project->mapLayers();
  for ( QgsMapLayer *mapLayer : layers )
  {
    QgsVectorLayer *layer = qobject_cast<QgsVectorLayer *>( mapLayer );
    if ( !carriesIdentity( layer ) )
      continue;

    if ( FeatureIdentity::uuidFieldIndex( layer->fields() ) < 0 )
      issue( QStringLiteral( "missing_uuid_field" ), layer->name(), 0 );
    // [WF-IDENTITY] a photo table nobody points at: its photos never show
    if ( isAttachmentTable( layer ) && parentRelationCount( project, layer ) == 0 )
      issue( QStringLiteral( "attachments_without_parent" ), layer->name(), static_cast<int>( layer->featureCount() ) );
    if ( identityParentRelation( project, layer ).isValid() && FeatureIdentity::fieldIndex( layer->fields(), FeatureIdentity::parentUuidFieldName() ) < 0 )
      issue( QStringLiteral( "missing_parent_uuid_field" ), layer->name(), 0 );

    IdentityCounts counts;
    identityPass( project, layer, false, false, counts );
    if ( counts.emptyUuid > 0 )
      issue( QStringLiteral( "empty_uuid" ), layer->name(), counts.emptyUuid );
    if ( counts.repeatedUuid > 0 )
      issue( QStringLiteral( "repeated_uuid" ), layer->name(), counts.repeatedUuid );
    if ( counts.emptyParentUuid > 0 )
      issue( QStringLiteral( "empty_parent_uuid" ), layer->name(), counts.emptyParentUuid );
    if ( counts.disagreeingParentUuid > 0 )
      issue( QStringLiteral( "disagreeing_parent_uuid" ), layer->name(), counts.disagreeingParentUuid );
  }
  return result;
}

int NarzedziaProjektu::fillMissingIdentity( QgsProject *project )
{
  if ( !project )
    return 0;
  int written = 0;
  const auto layers = project->mapLayers();
  // Objects first, children after: PARENT_UUID is copied from a filled uuid.
  // Children twice — a child can be a parent itself (species list → its photos).
  for ( int round = 0; round < 3; ++round )
  {
    for ( QgsMapLayer *mapLayer : layers )
    {
      QgsVectorLayer *layer = qobject_cast<QgsVectorLayer *>( mapLayer );
      if ( !carriesIdentity( layer ) )
        continue;
      const bool isChild = identityParentRelation( project, layer ).isValid();
      if ( ( round > 0 ) != isChild )
        continue;
      IdentityCounts counts;
      written += identityPass( project, layer, true, false, counts );
    }
  }
  return written;
}

//! [WF-IDENTITY] One layer: fields (added when missing), their configuration,
//! values. Shared by the button (whole project) and by a new layer.
static void repairLayerIdentity( QgsProject *project, QgsVectorLayer *layer, int &fieldsAdded, int &valuesWritten, int &renewed, QStringList &skipped, QSet<QString> &ambiguous )
{
  if ( layer->isEditable() )
  {
    skipped << NarzedziaProjektu::tr( "„%1” — warstwa jest w trakcie edycji" ).arg( layer->name() );
    return;
  }

  bool added = false;
  const int uuidIndex = ensureTextField( layer, FeatureIdentity::uuidFieldName(), added );
  if ( uuidIndex < 0 )
  {
    skipped << NarzedziaProjektu::tr( "„%1” — nie da się dopisać pola" ).arg( layer->name() );
    return;
  }
  fieldsAdded += added ? 1 : 0;
  configureIdentityField( layer, uuidIndex, QStringLiteral( "uuid()" ), NarzedziaProjektu::tr( "Identyfikator obiektu" ) );

  if ( identityParentRelation( project, layer ).isValid() )
  {
    const int parentIndex = ensureTextField( layer, FeatureIdentity::parentUuidFieldName(), added );
    if ( parentIndex >= 0 )
    {
      fieldsAdded += added ? 1 : 0;
      configureIdentityField( layer, parentIndex, QStringLiteral( "current_parent_value('uuid')" ), NarzedziaProjektu::tr( "Identyfikator obiektu nadrzędnego" ) );
    }
  }

  IdentityCounts counts;
  valuesWritten += identityPass( project, layer, true, true, counts, &ambiguous );
  renewed += counts.repeatedUuid;
}

QVariantMap NarzedziaProjektu::repairIdentity( QgsProject *project )
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !project )
  {
    result.insert( QStringLiteral( "opis" ), tr( "Brak projektu." ) );
    return result;
  }

  int fieldsAdded = 0;
  int valuesWritten = 0;
  int renewed = 0;
  QSet<QString> ambiguous;
  QStringList skipped;
  const auto layers = project->mapLayers();

  // Objects first, children after (twice, as in fillMissingIdentity).
  for ( int round = 0; round < 3; ++round )
  {
    for ( QgsMapLayer *mapLayer : layers )
    {
      QgsVectorLayer *layer = qobject_cast<QgsVectorLayer *>( mapLayer );
      if ( !carriesIdentity( layer ) )
        continue;
      if ( ( round > 0 ) != identityParentRelation( project, layer ).isValid() )
        continue;
      repairLayerIdentity( project, layer, fieldsAdded, valuesWritten, renewed, skipped, ambiguous );
    }
  }

  // After the repair: what is still wrong (disagreeing PARENT_UUID is left alone on purpose).
  int disagreeing = 0;
  const QVariantList left = identityIssues( project );
  for ( const QVariant &v : left )
  {
    const QVariantMap m = v.toMap();
    if ( m.value( QStringLiteral( "kind" ) ).toString() == QLatin1String( "disagreeing_parent_uuid" ) )
      disagreeing += m.value( QStringLiteral( "count" ) ).toInt();
  }

  QStringList text;
  text << tr( "Dopisane pola: %1. Uzupełnione identyfikatory: %2." ).arg( fieldsAdded ).arg( valuesWritten );
  if ( renewed > 0 )
    text << tr( "Obiekty z powtórzonym identyfikatorem: %1 — najstarszy w każdej grupie zachował swój, pozostałe dostały nowy." ).arg( renewed );
  if ( disagreeing > 0 )
    text << tr( "Załączniki wskazujące innego rodzica numerem niż identyfikatorem: %1 — tego nie poprawiam automatycznie, trzeba obejrzeć." ).arg( disagreeing );
  if ( !skipped.isEmpty() )
    text << tr( "Pominięte: %1." ).arg( skipped.join( QStringLiteral( "; " ) ) );

  result.insert( QStringLiteral( "ok" ), skipped.isEmpty() );
  result.insert( QStringLiteral( "opis" ), text.join( QLatin1Char( ' ' ) ) );
  result.insert( QStringLiteral( "fieldsAdded" ), fieldsAdded );
  result.insert( QStringLiteral( "valuesWritten" ), valuesWritten );
  return result;
}

//! [WF-IDENTITY] A table of photos: ZAL_* by name, or the attachment fields.
static bool isAttachmentTable( const QgsVectorLayer *layer )
{
  if ( identityTableName( layer ).startsWith( QLatin1String( "ZAL_" ), Qt::CaseInsensitive ) )
    return true;
  return FeatureIdentity::fieldIndex( layer->fields(), QStringLiteral( "SCIEZKA" ) ) >= 0
         && FeatureIdentity::fieldIndex( layer->fields(), QStringLiteral( "ID_RODZICA" ) ) >= 0;
}

//! Number of valid relations in which the layer is the child.
static int parentRelationCount( QgsProject *project, QgsVectorLayer *layer )
{
  int count = 0;
  const QList<QgsRelation> relations = project->relationManager()->referencingRelations( layer );
  for ( const QgsRelation &relation : relations )
  {
    if ( relation.isValid() )
      ++count;
  }
  return count;
}

static QString identityFilePath( const QgsVectorLayer *layer )
{
  const QString path = QgsProviderRegistry::instance()->decodeUri( layer->providerType(), layer->source() ).value( QStringLiteral( "path" ) ).toString();
  const QFileInfo info( path );
  return info.exists() ? info.canonicalFilePath() : info.absoluteFilePath();
}

QVariantMap NarzedziaProjektu::linkAttachmentTables( QgsProject *project )
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  if ( !project )
  {
    result.insert( QStringLiteral( "opis" ), tr( "Brak projektu." ) );
    return result;
  }

  QStringList linked;
  QStringList removed;
  QStringList removedIds;
  QStringList left;
  const auto layers = project->mapLayers();
  for ( QgsMapLayer *mapLayer : layers )
  {
    QgsVectorLayer *child = qobject_cast<QgsVectorLayer *>( mapLayer );
    if ( !carriesIdentity( child ) || !isAttachmentTable( child ) || parentRelationCount( project, child ) > 0 )
      continue;

    // The parent is the layer whose photo table — by the rule of the
    // attachments module — is exactly this table, in the same file.
    const QString childFile = identityFilePath( child );
    const QString childTable = identityTableName( child );
    QList<QgsVectorLayer *> parents;
    for ( QgsMapLayer *other : layers )
    {
      QgsVectorLayer *candidate = qobject_cast<QgsVectorLayer *>( other );
      if ( !candidate || candidate == child || !carriesIdentity( candidate ) || isAttachmentTable( candidate ) )
        continue;
      if ( identityFilePath( candidate ) != childFile )
        continue;
      if ( ModulZalacznikow::attachmentTableFor( candidate ).compare( childTable, Qt::CaseInsensitive ) == 0 )
        parents << candidate;
    }

    const long long photos = child->featureCount();
    if ( parents.size() == 1 )
    {
      // The attachments module is idempotent: it finds this table and this
      // layer and only adds what is missing (relation, form tab, naming).
      const ModulZalacznikow::Wynik w = ModulZalacznikow::setUp( project, parents.first() );
      if ( w.ok )
        linked << tr( "%1 → %2" ).arg( child->name(), parents.first()->name() );
      else
        left << tr( "%1 (%2)" ).arg( child->name(), w.opis );
    }
    else if ( parents.isEmpty() && photos == 0 )
    {
      // removed after the loop: `layers` still holds this pointer
      removed << child->name();
      removedIds << child->id();
    }
    else
    {
      left << ( parents.isEmpty() ? tr( "%1 — zdjęć: %2, nie ma warstwy, do której pasuje" ).arg( child->name() ).arg( photos )
                                  : tr( "%1 — pasuje do kilku warstw" ).arg( child->name() ) );
    }
  }

  for ( const QString &id : std::as_const( removedIds ) )
    removeLayerWithRelations( project, id );

  // Linked tables get PARENT_UUID now (and the values).
  if ( !linked.isEmpty() )
    repairIdentity( project );

  QStringList text;
  if ( !linked.isEmpty() )
    text << tr( "Powiązane: %1. Zdjęcia pokażą się w formularzach obiektów." ).arg( linked.join( QStringLiteral( ", " ) ) );
  if ( !removed.isEmpty() )
    text << tr( "Usunięte z projektu puste tabele bez warstwy: %1 (w pliku zostały)." ).arg( removed.join( QStringLiteral( ", " ) ) );
  if ( !left.isEmpty() )
    text << tr( "Do obejrzenia w QGIS: %1." ).arg( left.join( QStringLiteral( "; " ) ) );
  if ( text.isEmpty() )
    text << tr( "Wszystkie tabele zdjęć są już powiązane." );

  result.insert( QStringLiteral( "ok" ), left.isEmpty() );
  result.insert( QStringLiteral( "opis" ), text.join( QLatin1Char( ' ' ) ) );
  return result;
}

QVariantMap NarzedziaProjektu::stanProjektu( QgsProject *projekt ) const
{
  QVariantMap wynik;
  if ( !projekt )
    return wynik;

  QVariantList warstwy;
  QVariantList ostrzezenia;

  // ========================================================================
  // KAZDE OSTRZEZENIE MOWI, CZEGO DOTYCZY — 23.09.2026
  // ========================================================================
  // Do dzis szly jedna lista i szuflada rysowala je jednym ciagiem pod
  // wyposazeniem — czerwona linijka bez adresata, wygladajaca jak awaria
  // calego projektu. A sa to trzy rozne rzeczy i wymagaja trzech roznych
  // narzedzi:
  //
  //   "ustawienie"  ustawienie zle DLA TYCH danych. Szkody jeszcze nie ma,
  //                 ale bedzie. Naprawa: przestawic ustawienie. PREWENCJA —
  //                 wiesza sie przy module wyposazenia, ktorego dotyczy.
  //   "dane"        blad JUZ POPELNIONY, z adresem obiektu. Naprawa wymaga
  //                 innych narzedzi (poprawa geometrii) i zapisu do
  //                 `dane.gpkg`. POST HOC — nie miesza sie z prewencja.
  //   "projekt"     czegos brakuje w skladzie projektu (plik, sciezka).
  //
  // `modul` wskazuje modul wyposazenia, przy ktorym ostrzezenie ma wisiec.
  // `warstwa` i `fid` adresuja obiekt — pod „Pokaz na mapie”, ktorego
  // jeszcze nie ma, ale bez tych dwoch pol nie da sie go napisac.
  // KAZDE OSTRZEZENIE MOWI TEZ, CO Z TYM ZROBIC (23.09.2026, uwaga Piotra:
  // „ostrzezenia nie mowia konkretnie, co trzeba zrobic, zeby naprawic").
  // Zdanie „przyciaganie lapie segment" opisuje objaw. Czlowiek w terenie
  // potrzebuje czasownika: co przestawic, gdzie i na ile. `rada` niesie
  // wlasnie to — osobno od opisu, bo opis tlumaczy, a rada kaze.
  // CZASOWNIK PRZY OSTRZEZENIU, NIE ZGADYWANY Z TRESCI (23.09.2026).
  //
  // Okno naprawy musi wiedziec, KTORY przycisk pokazac przy ktorym wpisie.
  // Rozpoznawanie tego po tresci zdania („czy zawiera slowo przyciaganie")
  // dziala do pierwszej poprawki jezykowej — a te robimy co kilka dni.
  //
  //   ""              nie ma czasownika w terenie; zostaje notatka
  //   "pokaz_obiekt"  przybliz mape do obiektu i zaznacz go (warstwa + fid)
  //   "pokaz_warstwe" przybliz mape do warstwy (sama warstwa)
  //   "przyciaganie"  przestaw prog / typ; `parametr` niesie zalecany prog
  //   "topologia"     wylacz edycje topologiczna
  //   "slownik"       pobierz wf_wskazniki.gpkg (Wyposazenie umie to od dzis)
  auto ostrzez = [&ostrzezenia]( const QString &waga, const QString &rodzaj,
                                 const QString &tekst, const QString &rada,
                                 const QString &czasownik = QString(),
                                 double parametr = 0.0,
                                 const QString &modul = QString(),
                                 const QString &warstwa = QString(),
                                 qlonglong fid = -1 ) {
    QVariantMap o;
    o.insert( QStringLiteral( "waga" ), waga );
    o.insert( QStringLiteral( "rodzaj" ), rodzaj );
    o.insert( QStringLiteral( "opis" ), tekst );
    o.insert( QStringLiteral( "rada" ), rada );
    o.insert( QStringLiteral( "czasownik" ), czasownik );
    if ( parametr > 0 )
      o.insert( QStringLiteral( "parametr" ), parametr );
    if ( !modul.isEmpty() )
      o.insert( QStringLiteral( "modul" ), modul );
    if ( !warstwa.isEmpty() )
      o.insert( QStringLiteral( "warstwa" ), warstwa );
    if ( fid >= 0 )
      o.insert( QStringLiteral( "fid" ), fid );
    ostrzezenia.append( o );
  };

  const QString katalog = QFileInfo( projekt->fileName() ).absolutePath();
  double najmniejszaObwiednia = -1.0;
  QString najmniejszyObiekt;
  // Rozbite na czesci skladowe OBOK gotowego napisu: napis idzie do
  // komunikatu, te dwa do przyszlego przyblizenia mapy. Wyciaganie fid
  // z powrotem z tekstu „warstwa / fid 2253” bylo by proszeniem sie
  // o klopoty przy pierwszej warstwie z ukosnikiem w nazwie.
  QString najmniejszaWarstwa;
  qlonglong najmniejszyFid = -1;

  // [WF-COLLAPSED] First polygon that really collapsed (size < 5 cm or
  // area < 4 cm²). Kept apart from the smallest object: a small object is
  // not an error, a collapsed one is.
  constexpr double kCollapsedSize = 0.05;  // m
  constexpr double kCollapsedArea = 0.0004; // m²
  double collapsedSize = -1.0;
  double collapsedArea = -1.0;
  QString collapsedObject;
  QString collapsedLayer;
  qlonglong collapsedFid = -1;

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
      ostrzez( QStringLiteral( "uwaga" ), QStringLiteral( "projekt" ),
               tr( "warstwa „%1” wskazuje poza katalog projektu — nie pojedzie w teren" )
                 .arg( wektor->name() ),
               tr( "Skopiuj plik warstwy do katalogu projektu i podepnij ją "
                   "od nowa, albo złóż projekt jeszcze raz w biurze. Tak jak "
                   "jest, po przewiezieniu na telefon warstwa będzie pusta." ),
               QString(), 0.0, QString(), wektor->name() );

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
        if ( collapsedFid < 0 )
        {
          const double area = qAbs( geom.area() );
          if ( bok < kCollapsedSize || area < kCollapsedArea )
          {
            collapsedSize = bok;
            collapsedArea = area;
            collapsedObject = QStringLiteral( "%1 / fid %2" ).arg( wektor->name() ).arg( obiekt.id() );
            collapsedLayer = wektor->name();
            collapsedFid = obiekt.id();
          }
        }
        if ( najmniejszaObwiednia < 0 || bok < najmniejszaObwiednia )
        {
          najmniejszaObwiednia = bok;
          najmniejszyObiekt = QStringLiteral( "%1 / fid %2" ).arg( wektor->name() ).arg( obiekt.id() );
          najmniejszaWarstwa = wektor->name();
          najmniejszyFid = obiekt.id();
        }
      }
      if ( puste > 0 )
        ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),
                 tr( "„%1”: %2 obiektów z PUSTĄ geometrią — istnieją, "
                     "ale nie widać ich na mapie i nie da się ich zaznaczyć" )
                   .arg( wektor->name() ).arg( puste ),
                 tr( "Otwórz tabelę atrybutów warstwy „%1” i przejrzyj wiersze "
                     "bez geometrii: albo narysuj im kształt, albo skasuj. "
                     "Same nie znikną i pojadą do eksportu." ).arg( wektor->name() ),
                 QStringLiteral( "pokaz_warstwe" ), 0.0, QString(), wektor->name() );
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
    ostrzez( QStringLiteral( "uwaga" ), QStringLiteral( "ustawienie" ),
             tr( "przyciąganie łapie segment, a najmniejszy obiekt ma %1 m (%2) — "
                 "przy takich rozmiarach wierzchołki zlepiają się w jeden punkt" )
               .arg( najmniejszaObwiednia, 0, 'f', 1 ).arg( najmniejszyObiekt ),
             tr( "Zejdź z tolerancją przyciągania do najwyżej %1 m — połowy "
                 "najmniejszego obiektu — albo zostaw przyciąganie tylko "
                 "do WIERZCHOŁKA, bez odcinka. Teraz próg obejmuje cały ten "
                 "obiekt, więc każde dotknięcie zlepia go w punkt." )
               .arg( std::max( 0.05, najmniejszaObwiednia / 2.0 ), 0, 'f', 2 ),
             QStringLiteral( "przyciaganie" ), std::max( 0.05, najmniejszaObwiednia / 2.0 ),
             QStringLiteral( "przyciaganie" ), najmniejszaWarstwa, najmniejszyFid );

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
    // Bez `modul`: edycja topologiczna jest ustawieniem QGIS-a, ktorego
    // katalog wyposazenia nie opisuje. Wiesza sie wiec pod lista modulow,
    // nie przy zadnym z nich.
    ostrzez( QStringLiteral( "uwaga" ), QStringLiteral( "ustawienie" ),
             tr( "edycja topologiczna WŁĄCZONA, a najmniejszy obiekt ma %1 m (%2). "
                 "Przy przesuwaniu wierzchołka wszystkie sąsiednie w promieniu "
                 "trafiają w ten sam punkt — obrys małego obiektu zwija się do zera. "
                 "Działa też przy TWORZENIU, nie tylko przy poprawianiu. "
                 "Promień jest ustawieniem aplikacji, nie projektu." )
               .arg( najmniejszaObwiednia, 0, 'f', 1 ).arg( najmniejszyObiekt ),
             tr( "Wyłącz edycję topologiczną na czas pracy przy tych obiektach. "
                 "Przy %1 m pilnuje wspólnych granic kosztem samego kształtu — "
                 "zysk jest żaden, strata trwała." )
               .arg( najmniejszaObwiednia, 0, 'f', 1 ),
             QStringLiteral( "topologia" ), 0.0, QString(),
             najmniejszaWarstwa, najmniejszyFid );

  // [WF-BAD-LAYERS] Layers that did not load: each one with a solution.
  const QVariantList badLayers = invalidLayers( projekt );
  for ( const QVariant &v : badLayers )
  {
    const QVariantMap m = v.toMap();
    const QString kind = m.value( QStringLiteral( "kind" ) ).toString();
    const QString name = m.value( QStringLiteral( "name" ) ).toString();
    const QString table = m.value( QStringLiteral( "table" ) ).toString();
    if ( kind == QLatin1String( "attachments_orphan" ) )
      ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),
               tr( "warstwa zdjęć „%1” się nie wczytuje — w bazie nie ma tabeli %2, a jej warstwy w projekcie już nie ma" ).arg( name, table ),
               tr( "„Napraw” usunie ją z projektu. Żadne dane nie przepadną — tej tabeli w bazie i tak nie ma." ),
               QStringLiteral( "napraw_zal" ), 0.0, QString(), name );
    else if ( kind == QLatin1String( "attachments_missing" ) )
      ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),
               tr( "warstwa zdjęć „%1” się nie wczytuje — w bazie nie ma tabeli %2" ).arg( name, table ),
               tr( "„Napraw” założy pustą tabelę zdjęć dla warstwy „%1”." ).arg( m.value( QStringLiteral( "parent" ) ).toString() ),
               QStringLiteral( "napraw_zal" ), 0.0, QString(), name );
    else
      ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),
               tr( "warstwa „%1” się nie wczytuje — nie ma źródła %2" ).arg( name, m.value( QStringLiteral( "source" ) ).toString() ),
               tr( "Jeśli jest niepotrzebna — „Usuń z projektu”. Jeśli potrzebna — popraw źródło w QGIS." ),
               QStringLiteral( "usun_zla" ), 0.0, QString(), name );
  }

  // [WF-IDENTITY] 24.10.2026 — identity of objects and attachments. Missing
  // fields and empty values: one entry with the "Uzupełnij identyfikatory"
  // button. Repeated uuid: the same button. A PARENT_UUID disagreeing with the
  // relation: only shown — one of the two keys is wrong, a human decides.
  {
    const QVariantList identity = identityIssues( projekt );
    QStringList missingIn;
    QStringList withoutParent;
    int emptyValues = 0;
    for ( const QVariant &v : identity )
    {
      const QVariantMap m = v.toMap();
      const QString kind = m.value( QStringLiteral( "kind" ) ).toString();
      const QString layerName = m.value( QStringLiteral( "layer" ) ).toString();
      const int count = m.value( QStringLiteral( "count" ) ).toInt();
      if ( kind == QLatin1String( "missing_uuid_field" ) || kind == QLatin1String( "missing_parent_uuid_field" ) )
      {
        if ( !missingIn.contains( layerName ) )
          missingIn << layerName;
      }
      else if ( kind == QLatin1String( "empty_uuid" ) || kind == QLatin1String( "empty_parent_uuid" ) )
      {
        emptyValues += count;
      }
      else if ( kind == QLatin1String( "attachments_without_parent" ) )
      {
        withoutParent << tr( "%1 (zdjęć: %2)" ).arg( layerName ).arg( count );
      }
      else if ( kind == QLatin1String( "repeated_uuid" ) )
      {
        ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),
                 tr( "warstwa „%1”: obiekty z takim samym identyfikatorem jak inny obiekt: %2 — najpewniej skopiowane przed 24.10.2026" ).arg( layerName ).arg( count ),
                 tr( "„Uzupełnij identyfikatory” zostawi identyfikator najstarszemu obiektowi w każdej grupie, a pozostałym nada nowy. Atrybuty i geometria się nie zmieniają." ),
                 QStringLiteral( "tozsamosc" ), 0.0, QString(), layerName );
      }
      else if ( kind == QLatin1String( "disagreeing_parent_uuid" ) )
      {
        ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),
                 tr( "warstwa „%1”: załączniki wskazujące innego rodzica numerem (ID_RODZICA) niż identyfikatorem (PARENT_UUID): %2" ).arg( layerName ).arg( count ),
                 tr( "Najpewniej numery fid rozjechały się przy scalaniu albo powiązanie zmieniono ręcznie. Aplikacja tego nie poprawia sama, bo nie wie, który klucz jest dobry — porównaj te dwa pola w QGIS." ),
                 QStringLiteral( "pokaz_warstwe" ), 0.0, QString(), layerName );
      }
    }
    if ( !withoutParent.isEmpty() )
    {
      ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),
               tr( "tabele zdjęć niepowiązane z żadną warstwą obiektów — ich zdjęcia nie pokazują się w formularzach (razem %1): %2" )
                 .arg( withoutParent.size() )
                 .arg( withoutParent.join( QStringLiteral( ", " ) ) ),
               tr( "„Powiąż tabele zdjęć” podłączy każdą tabelę do jej warstwy (np. ZAL_ZRASZACZE → Zraszacze), dołoży zakładkę zdjęć w formularzu "
                   "i identyfikatory. Pustą tabelę, do której nie pasuje żadna warstwa, usunie z projektu (w pliku zostaje). "
                   "Czego nie da się dopasować, wymieni z nazwy." ),
               QStringLiteral( "powiaz_zal" ) );
    }
    if ( !missingIn.isEmpty() || emptyValues > 0 )
    {
      const QString what = !missingIn.isEmpty()
                             ? tr( "warstwy bez identyfikatora obiektów (uuid), razem %1: %2" ).arg( missingIn.size() ).arg( missingIn.join( QStringLiteral( ", " ) ) )
                             : tr( "obiekty albo załączniki bez identyfikatora: %1" ).arg( emptyValues );
      ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ), what,
               tr( "„Uzupełnij identyfikatory” dopisze pole uuid (a w tabelach zdjęć także PARENT_UUID), nada identyfikator każdemu obiektowi i ukryje te pola w formularzach. "
                   "Atrybuty i geometria się nie zmieniają. Najlepiej zrobić to w biurze, przed wydaniem w teren — wtedy wszystkie telefony mają tę samą budowę bazy." ),
               QStringLiteral( "tozsamosc" ) );
    }
  }

  // [WF-COLLAPSED] Was "smallest object < 0.5 m" — flagged real small objects
  // (Wodomierze fid 3, 0.28 m, Pasymska 23.10).
  if ( collapsedFid >= 0 )
    ostrzez( QStringLiteral( "brak" ), QStringLiteral( "dane" ),
             tr( "obiekt %1 ma %2 cm długości i %3 cm² pola — wierzchołki zlepione w punkt albo w linię" )
               .arg( collapsedObject )
               .arg( collapsedSize * 100.0, 0, 'f', 1 )
               .arg( collapsedArea * 10000.0, 0, 'f', 1 ),
             tr( "Obejrzyj ten obiekt na mapie. Jeżeli to pomyłka — skasuj go. "
                 "Jeżeli miał być powierzchnią — narysuj od nowa; ratowanie zlepionych "
                 "wierzchołków przez przeciąganie kończy się drugim takim samym. "
                 "Zostawiony pójdzie do eksportu jako powierzchnia zero." ),
             QStringLiteral( "pokaz_obiekt" ), 0.0, QString(),
             collapsedLayer, collapsedFid );

  // ----------------------------------------------------------------- dane
  QVariantMap dane;
  const QString plik = plikDanych( projekt );
  dane.insert( QStringLiteral( "plikDanych" ), QFileInfo( plik ).fileName() );
  dane.insert( QStringLiteral( "katalog" ), katalog );

  const bool maWskazniki = !katalog.isEmpty()
                           && QFileInfo::exists( katalog + QStringLiteral( "/wf_wskazniki.gpkg" ) );
  dane.insert( QStringLiteral( "wskazniki" ), maWskazniki );
  // [WF-FITO-ONLY] The species dictionary is part of the phytosociology module,
  // not of every project (Piotr 23.10).
  const bool fito = usesPhytosociology( projekt );
  dane.insert( QStringLiteral( "fitosocjologia" ), fito );
  if ( fito && !maWskazniki )
    ostrzez( QStringLiteral( "brak" ), QStringLiteral( "projekt" ),
             tr( "brak wf_wskazniki.gpkg — metadane gatunków i podpowiadanie nie zadziałają" ),
             tr( "Wyposażenie → Słownik gatunków → „Pobierz z sieci”. "
                 "Potrzebny internet, więc zrób to przed wyjazdem." ),
             QStringLiteral( "slownik" ) );

  if ( plik.isEmpty() )
    ostrzez( QStringLiteral( "brak" ), QStringLiteral( "projekt" ),
             tr( "projekt nie ma pliku z danymi — dziennik Nieba nie ma dokąd pisać" ),
             tr( "Ten projekt nie zapisuje niczego trwale. Złóż go od nowa "
                 "z szablonu albo dołóż warstwę w GeoPackage obok projekt.qgs "
                 "— ZANIM zaczniesz zbierać dane." ) );

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

// WorkField 8.10.2026 [WF-EKSPORT-DANYCH] — „Tylko dane”: to, czego nie da
// się odtworzyć (bazy z obiektami, zdjęcia, projekt, wyniki wtyczek), bez
// ortofotomap i kopii. Zakres ustalony z Piotrem 8.10.2026.
#include <QDirIterator>

namespace
{
  //! Co mówi gpkg_contents: "wektor", "raster" albo "" (nie GeoPackage / nie da się czytać).
  QString rodzajGeoPackage( const QString &plik )
  {
    QString rodzaj;
    sqlite3 *baza = nullptr;
    if ( sqlite3_open_v2( plik.toUtf8().constData(), &baza, SQLITE_OPEN_READONLY, nullptr ) == SQLITE_OK )
    {
      sqlite3_busy_timeout( baza, 5000 );
      sqlite3_stmt *zapytanie = nullptr;
      if ( sqlite3_prepare_v2( baza, "SELECT DISTINCT lower(data_type) FROM gpkg_contents", -1, &zapytanie, nullptr ) == SQLITE_OK )
      {
        bool wektor = false;
        bool raster = false;
        while ( sqlite3_step( zapytanie ) == SQLITE_ROW )
        {
          const QString typ = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( zapytanie, 0 ) ) );
          if ( typ == QLatin1String( "tiles" ) || typ == QLatin1String( "2d-gridded-coverage" ) )
            raster = true;
          else
            wektor = true; // features, attributes i wszystko inne — to dane
        }
        // baza z samymi kafelkami = podkład; mieszana albo pusta = dane
        rodzaj = ( raster && !wektor ) ? QStringLiteral( "raster" ) : QStringLiteral( "wektor" );
      }
      sqlite3_finalize( zapytanie );
    }
    if ( baza )
      sqlite3_close( baza );
    return rodzaj;
  }

  //! Czy plik zaczyna się nagłówkiem SQLite (GeoPackage, SpatiaLite…).
  bool toSqlite( const QString &plik )
  {
    QFile f( plik );
    if ( !f.open( QIODevice::ReadOnly ) )
      return false;
    return f.read( 16 ) == QByteArray( "SQLite format 3\0", 16 );
  }

  //! Kopia bazy przez API kopii zapasowej SQLite: czyta także to, co siedzi
  //! jeszcze w dzienniku WAL, więc ostatnie zapisy nie giną, nawet gdy
  //! QField trzyma bazę otwartą. Potem sprawdzenie quick_check.
  QString zapieczetujBaze( const QString &zrodlo, const QString &cel )
  {
    sqlite3 *wej = nullptr;
    sqlite3 *wyj = nullptr;
    QString blad;
    if ( sqlite3_open_v2( zrodlo.toUtf8().constData(), &wej, SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
      blad = QStringLiteral( "nie da się otworzyć" );
    else if ( sqlite3_open_v2( cel.toUtf8().constData(), &wyj, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr ) != SQLITE_OK )
      blad = QStringLiteral( "nie da się utworzyć kopii" );
    else
    {
      sqlite3_busy_timeout( wej, 5000 );
      sqlite3_backup *kopia = sqlite3_backup_init( wyj, "main", wej, "main" );
      if ( !kopia )
        blad = QString::fromUtf8( sqlite3_errmsg( wyj ) );
      else
      {
        int stan = SQLITE_OK;
        int proby = 0;
        do
        {
          stan = sqlite3_backup_step( kopia, -1 );
          if ( stan == SQLITE_BUSY || stan == SQLITE_LOCKED )
            sqlite3_sleep( 100 );
        } while ( ( stan == SQLITE_BUSY || stan == SQLITE_LOCKED ) && ++proby < 50 );
        sqlite3_backup_finish( kopia );
        if ( stan != SQLITE_DONE )
          blad = QStringLiteral( "kopia przerwana (%1)" ).arg( stan );
      }
    }

    if ( blad.isEmpty() )
    {
      // u odbiorcy jeden plik, bez dziennika obok
      sqlite3_exec( wyj, "PRAGMA journal_mode=DELETE", nullptr, nullptr, nullptr );
      bool zdrowa = false;
      sqlite3_stmt *zapytanie = nullptr;
      if ( sqlite3_prepare_v2( wyj, "PRAGMA quick_check", -1, &zapytanie, nullptr ) == SQLITE_OK
           && sqlite3_step( zapytanie ) == SQLITE_ROW )
      {
        const QString odpowiedz = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( zapytanie, 0 ) ) );
        zdrowa = odpowiedz.compare( QLatin1String( "ok" ), Qt::CaseInsensitive ) == 0;
      }
      sqlite3_finalize( zapytanie );
      if ( !zdrowa )
        blad = QStringLiteral( "kopia nie przeszła sprawdzenia" );
    }

    if ( wej )
      sqlite3_close( wej );
    if ( wyj )
      sqlite3_close( wyj );
    if ( !blad.isEmpty() )
      QFile::remove( cel );
    return blad;
  }
} // namespace

QVariantMap NarzedziaProjektu::eksportDanychProjektu( const QString &katalogProjektu, const QString &katalogDocelowy, bool proba ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );

  const QString zrodlo = QDir::cleanPath( katalogProjektu );
  if ( zrodlo.isEmpty() || !QFileInfo( zrodlo ).isDir() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma katalogu projektu." ) );
    return wynik;
  }

  const QString cel = QDir::cleanPath( katalogDocelowy );
  if ( !proba )
  {
    if ( cel.isEmpty() )
    {
      wynik.insert( QStringLiteral( "blad" ), tr( "Nie wskazano, dokąd kopiować." ) );
      return wynik;
    }
    if ( cel == zrodlo || cel.startsWith( zrodlo + QLatin1Char( '/' ) ) )
    {
      wynik.insert( QStringLiteral( "blad" ), tr( "Folder docelowy nie może leżeć wewnątrz projektu." ) );
      return wynik;
    }
    // Nie dokładamy do cudzego katalogu i niczego nie nadpisujemy.
    if ( QFileInfo::exists( cel ) && !QDir( cel ).isEmpty( QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden ) )
    {
      wynik.insert( QStringLiteral( "blad" ), tr( "Folder %1 już istnieje i nie jest pusty." ).arg( cel ) );
      return wynik;
    }
    if ( !QDir().mkpath( cel ) )
    {
      wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się utworzyć katalogu %1" ).arg( cel ) );
      return wynik;
    }
  }

  static const QStringList rastry = {
    QStringLiteral( "tif" ), QStringLiteral( "tiff" ), QStringLiteral( "vrt" ), QStringLiteral( "jp2" ),
    QStringLiteral( "j2k" ), QStringLiteral( "ecw" ), QStringLiteral( "sid" ), QStringLiteral( "mbtiles" ),
    QStringLiteral( "ovr" ), QStringLiteral( "img" )
  };
  static const QStringList bazy = { QStringLiteral( "gpkg" ), QStringLiteral( "sqlite" ), QStringLiteral( "db" ) };

  qint64 bajty = 0;
  qint64 bajtyPominiete = 0;
  int plikow = 0;
  int pominietych = 0;
  int zapieczetowanych = 0;
  QStringList pominiete; // „ścieżka — powód”, do pliku-opisu
  QStringList bledy;

  auto pomin = [&]( const QString &wzgledna, qint64 rozmiar, const QString &powod ) {
    bajtyPominiete += rozmiar;
    ++pominietych;
    pominiete << QStringLiteral( "%1 — %2" ).arg( wzgledna, powod );
  };
  auto rozmiarKatalogu = []( const QString &sciezka ) {
    qint64 suma = 0;
    QDirIterator it( sciezka, QDir::Files | QDir::Hidden | QDir::NoSymLinks, QDirIterator::Subdirectories );
    while ( it.hasNext() )
    {
      it.next();
      suma += it.fileInfo().size();
    }
    return suma;
  };

  QStringList doObejscia = { QString() }; // ścieżki względne katalogów
  while ( !doObejscia.isEmpty() )
  {
    const QString wzgKatalog = doObejscia.takeFirst();
    const QDir katalog( wzgKatalog.isEmpty() ? zrodlo : zrodlo + QLatin1Char( '/' ) + wzgKatalog );
    const QFileInfoList wpisy = katalog.entryInfoList( QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::NoSymLinks, QDir::Name );
    for ( const QFileInfo &wpis : wpisy )
    {
      const QString nazwa = wpis.fileName();
      const QString male = nazwa.toLower();
      const QString wzgledna = wzgKatalog.isEmpty() ? nazwa : wzgKatalog + QLatin1Char( '/' ) + nazwa;

      if ( wpis.isDir() )
      {
        if ( wzgKatalog.isEmpty() && male == QLatin1String( "in" ) )
          pomin( wzgledna + QLatin1Char( '/' ), rozmiarKatalogu( wpis.absoluteFilePath() ), QStringLiteral( "materiały wejściowe" ) );
        else if ( male == QLatin1String( "kopie" ) || male.contains( QLatin1String( ".przed_" ) ) )
          pomin( wzgledna + QLatin1Char( '/' ), rozmiarKatalogu( wpis.absoluteFilePath() ), QStringLiteral( "kopie" ) );
        else
          doObejscia << wzgledna;
        continue;
      }

      const QString rozszerzenie = wpis.suffix().toLower();
      const qint64 rozmiar = wpis.size();

      if ( male.contains( QLatin1String( ".przed_" ) ) || male.endsWith( QLatin1Char( '~' ) ) )
      {
        pomin( wzgledna, rozmiar, QStringLiteral( "kopia" ) );
        continue;
      }
      if ( male.endsWith( QLatin1String( ".qgz.png" ) ) || male.endsWith( QLatin1String( ".qgs.png" ) ) || male.endsWith( QLatin1String( ".aux.xml" ) ) )
      {
        pomin( wzgledna, rozmiar, QStringLiteral( "miniatura / plik pomocniczy" ) );
        continue;
      }
      if ( male.endsWith( QLatin1String( "-wal" ) ) || male.endsWith( QLatin1String( "-shm" ) ) || male.endsWith( QLatin1String( "-journal" ) ) )
      {
        if ( male.endsWith( QLatin1String( "-wal" ) ) )
          bajty += rozmiar; // zawartość dziennika trafia do kopii bazy
        continue;
      }
      if ( rastry.contains( rozszerzenie ) )
      {
        pomin( wzgledna, rozmiar, QStringLiteral( "raster" ) );
        continue;
      }
      if ( rozszerzenie == QLatin1String( "gpkg" ) && male.startsWith( QLatin1String( "wf_wskazniki" ) ) )
      {
        pomin( wzgledna, rozmiar, QStringLiteral( "wskaźniki (odtwarzalne)" ) );
        continue;
      }

      if ( rozszerzenie == QLatin1String( "gpkg" ) && rodzajGeoPackage( wpis.absoluteFilePath() ) == QLatin1String( "raster" ) )
      {
        pomin( wzgledna, rozmiar, QStringLiteral( "raster w GeoPackage" ) );
        continue;
      }

      ++plikow;
      bajty += rozmiar;
      if ( proba )
        continue;

      const QString docelowy = cel + QLatin1Char( '/' ) + wzgledna;
      QDir().mkpath( QFileInfo( docelowy ).absolutePath() );
      bool udane = false;
      if ( bazy.contains( rozszerzenie ) && toSqlite( wpis.absoluteFilePath() ) )
      {
        const QString problem = zapieczetujBaze( wpis.absoluteFilePath(), docelowy );
        udane = problem.isEmpty();
        if ( udane )
          ++zapieczetowanych;
        else
          bledy << QStringLiteral( "%1: %2" ).arg( wzgledna, problem );
      }
      else
      {
        udane = QFile::copy( wpis.absoluteFilePath(), docelowy );
        if ( !udane )
          bledy << QStringLiteral( "%1: kopiowanie nie powiodło się" ).arg( wzgledna );
      }
      // u odbiorcy pliki mają być czytelne (kopie z telefonu bywały 600)
      if ( udane )
        QFile::setPermissions( docelowy, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther );
    }
  }

  if ( !proba )
  {
    QFile opis( cel + QStringLiteral( "/_EKSPORT_DANYCH.txt" ) );
    if ( opis.open( QIODevice::WriteOnly | QIODevice::Text ) )
    {
      QStringList linie;
      linie << QStringLiteral( "WorkFieldGIS — eksport „Tylko dane”" )
            << QStringLiteral( "Projekt: %1" ).arg( zrodlo )
            << QStringLiteral( "Czas: %1" ).arg( QDateTime::currentDateTime().toString( QStringLiteral( "yyyy-MM-dd HH:mm" ) ) )
            << QStringLiteral( "Skopiowano plików: %1 (%2 MB), w tym zapieczętowanych baz: %3" ).arg( plikow ).arg( bajty / 1048576.0, 0, 'f', 1 ).arg( zapieczetowanych )
            << QString()
            << QStringLiteral( "Pominięte (warstwy z nich w projekcie będą puste, dopóki nie dołożysz plików):" );
      for ( const QString &p : std::as_const( pominiete ) )
        linie << QStringLiteral( "  " ) + p;
      if ( !bledy.isEmpty() )
      {
        linie << QString() << QStringLiteral( "BŁĘDY:" );
        for ( const QString &b : std::as_const( bledy ) )
          linie << QStringLiteral( "  " ) + b;
      }
      opis.write( ( linie.join( QLatin1Char( '\n' ) ) + QLatin1Char( '\n' ) ).toUtf8() );
      opis.close();
    }
  }

  wynik.insert( QStringLiteral( "ok" ), bledy.isEmpty() );
  wynik.insert( QStringLiteral( "katalog" ), cel );
  wynik.insert( QStringLiteral( "plikow" ), plikow );
  wynik.insert( QStringLiteral( "bajty" ), bajty );
  wynik.insert( QStringLiteral( "bazy" ), zapieczetowanych );
  wynik.insert( QStringLiteral( "pominietych" ), pominietych );
  wynik.insert( QStringLiteral( "bajtyPominiete" ), bajtyPominiete );
  wynik.insert( QStringLiteral( "calosc" ), bajty + bajtyPominiete );
  wynik.insert( QStringLiteral( "bledy" ), bledy );
  if ( !bledy.isEmpty() )
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie wszystko się skopiowało: %1" ).arg( bledy.first() ) );
  return wynik;
}

// WorkField 8.10.2026 [WF-EKSPORT-PACZKA-KOMPUTER] — paczka ZIP na komputerze.
// Na komputerze nie ma systemowego „udostępnij”, więc „Eksportuj paczkę”
// zapisuje plik .zip we wskazanym folderze. libzip — ta sama, której używa
// QfFileUtils::unzip. Ścieżki w archiwum zachowują katalogi (QgsZipUtils::zip
// je spłaszcza: zdjęcia z DCIM/ wylądowałyby w korzeniu).
#include <QTemporaryDir>
#include <zip.h>

QVariantMap NarzedziaProjektu::spakujProjekt( const QString &katalogProjektu, const QString &plikZip, bool tylkoDane ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );

  const QString zrodlo = QDir::cleanPath( katalogProjektu );
  if ( zrodlo.isEmpty() || !QFileInfo( zrodlo ).isDir() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma katalogu projektu." ) );
    return wynik;
  }
  if ( plikZip.isEmpty() || QFileInfo::exists( plikZip ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Plik %1 już istnieje — nie nadpisuję." ).arg( plikZip ) );
    return wynik;
  }
  if ( QDir::cleanPath( plikZip ).startsWith( zrodlo + QLatin1Char( '/' ) ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Paczka nie może powstać wewnątrz projektu." ) );
    return wynik;
  }

  // „Tylko dane”: najpierw składamy je w katalogu tymczasowym (sam się
  // sprząta po wyjściu z funkcji), dopiero ten katalog idzie do ZIP-a.
  const QString nazwa = QFileInfo( plikZip ).completeBaseName();
  // Jawny wzorzec: domyślny bierze nazwę aplikacji, a ta w WorkField
  // potrafi zepsuć ścieżkę (8.10.2026: „nie da się utworzyć katalogu
  // tymczasowego” na komputerze Piotra). Gdy /tmp zawiedzie — katalog
  // roboczy obok paczki, tworzony od zera i sprzątany na końcu.
  QTemporaryDir tymczasowy( QDir::tempPath() + QStringLiteral( "/wf_eksport-XXXXXX" ) );
  QString obokPaczki;
  QString doSpakowania = zrodlo;
  if ( tylkoDane )
  {
    QString roboczy;
    if ( tymczasowy.isValid() )
    {
      roboczy = tymczasowy.path();
    }
    else
    {
      obokPaczki = QFileInfo( plikZip ).absolutePath() + QStringLiteral( "/.wf_eksport_" ) + nazwa;
      if ( QFileInfo::exists( obokPaczki ) || !QDir().mkpath( obokPaczki ) )
      {
        wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się utworzyć katalogu roboczego (%1; %2)." ).arg( tymczasowy.errorString(), obokPaczki ) );
        return wynik;
      }
      roboczy = obokPaczki;
    }
    doSpakowania = roboczy + QLatin1Char( '/' ) + nazwa;
    const QVariantMap dane = eksportDanychProjektu( zrodlo, doSpakowania, false );
    if ( !dane.value( QStringLiteral( "ok" ) ).toBool() )
    {
      if ( !obokPaczki.isEmpty() )
        QDir( obokPaczki ).removeRecursively();
      return dane;
    }
  }
  // sprząta katalog roboczy obok paczki przy każdym wyjściu niżej
  struct Sprzatacz
  {
      QString sciezka;
      ~Sprzatacz()
      {
        if ( !sciezka.isEmpty() )
          QDir( sciezka ).removeRecursively();
      }
  } sprzatacz { obokPaczki };

  int kod = 0;
  zip_t *archiwum = zip_open( plikZip.toUtf8().constData(), ZIP_CREATE | ZIP_EXCL, &kod );
  if ( !archiwum )
  {
    zip_error_t blad;
    zip_error_init_with_code( &blad, kod );
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie da się utworzyć %1: %2" ).arg( plikZip, QString::fromUtf8( zip_error_strerror( &blad ) ) ) );
    zip_error_fini( &blad );
    return wynik;
  }

  // już skompresowane — szkoda czasu na ponowne ściskanie
  static const QStringList bezKompresji = {
    QStringLiteral( "jpg" ), QStringLiteral( "jpeg" ), QStringLiteral( "png" ), QStringLiteral( "heic" ),
    QStringLiteral( "mp4" ), QStringLiteral( "zip" ), QStringLiteral( "qgz" ), QStringLiteral( "jp2" ),
    QStringLiteral( "ecw" ), QStringLiteral( "sid" ), QStringLiteral( "mbtiles" )
  };

  const QDir baza( doSpakowania );
  const QString przedrostek = tylkoDane ? nazwa : QFileInfo( zrodlo ).fileName();
  int plikow = 0;
  qint64 bajty = 0;
  QString problem;
  QDirIterator it( doSpakowania, QDir::Files | QDir::Hidden | QDir::NoSymLinks, QDirIterator::Subdirectories );
  while ( it.hasNext() && problem.isEmpty() )
  {
    const QString sciezka = it.next();
    const QFileInfo info = it.fileInfo();
    const QString wArchiwum = przedrostek + QLatin1Char( '/' ) + baza.relativeFilePath( sciezka );
    zip_source_t *zrodloPliku = zip_source_file( archiwum, sciezka.toUtf8().constData(), 0, -1 );
    if ( !zrodloPliku )
    {
      problem = tr( "%1: %2" ).arg( wArchiwum, QString::fromUtf8( zip_strerror( archiwum ) ) );
      break;
    }
    const zip_int64_t indeks = zip_file_add( archiwum, wArchiwum.toUtf8().constData(), zrodloPliku, ZIP_FL_ENC_UTF_8 );
    if ( indeks < 0 )
    {
      zip_source_free( zrodloPliku );
      problem = tr( "%1: %2" ).arg( wArchiwum, QString::fromUtf8( zip_strerror( archiwum ) ) );
      break;
    }
    if ( bezKompresji.contains( info.suffix().toLower() ) )
      zip_set_file_compression( archiwum, static_cast<zip_uint64_t>( indeks ), ZIP_CM_STORE, 0 );
    ++plikow;
    bajty += info.size();
  }

  if ( problem.isEmpty() && plikow == 0 )
    problem = tr( "Nie ma czego spakować." );

  if ( !problem.isEmpty() )
  {
    zip_discard( archiwum );
    QFile::remove( plikZip );
    wynik.insert( QStringLiteral( "blad" ), problem );
    return wynik;
  }

  // Właściwe pakowanie dzieje się dopiero tutaj.
  if ( zip_close( archiwum ) != 0 )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Pakowanie nie powiodło się: %1" ).arg( QString::fromUtf8( zip_strerror( archiwum ) ) ) );
    zip_discard( archiwum );
    QFile::remove( plikZip );
    return wynik;
  }
  QFile::setPermissions( plikZip, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther );

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "sciezka" ), plikZip );
  wynik.insert( QStringLiteral( "plikow" ), plikow );
  wynik.insert( QStringLiteral( "bajty" ), bajty );
  wynik.insert( QStringLiteral( "rozmiarZip" ), QFileInfo( plikZip ).size() );
  return wynik;
}

QVariantMap NarzedziaProjektu::importujWarstwe( const QString &zrodloUri,
                                                const QString &celGpkg,
                                                const QString &nazwaDocelowa,
                                                bool bezObiektow ) const
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
  // WorkField 6.10.2026 [WF-DUPLIKAT-LIMIT] — sama budowa tabeli. Liczbe
  // obiektow i tak sprawdzamy nizej, po fakcie, wiec gdyby GDAL kiedys
  // potraktowal -limit 0 inaczej, wyjdzie to w wyniku, nie w danych.
  if ( bezObiektow )
  {
    argv = CSLAddString( argv, "-limit" );
    argv = CSLAddString( argv, "0" );
  }
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

// ---------------------------------------------------------------------------
// WorkField 6.10.2026 [WF-DUPLIKAT-FUNKCJA] — duplikat warstwy w bazie projektu.
// Opis przy deklaracji w naglowku.
// ---------------------------------------------------------------------------
QVariantMap NarzedziaProjektu::duplikujWarstwe( QgsProject *projekt, QgsVectorLayer *zrodlo,
                                                const QString &nowaNazwa, bool zObiektami ) const
{
  QVariantMap wynik;
  wynik.insert( QStringLiteral( "ok" ), false );

  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || !zrodlo || !zrodlo->isValid() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nie ma warstwy do zduplikowania." ) );
    return wynik;
  }

  // Nazwa TABELI. Spacje i polskie litery w nazwie tabeli psuja SQL
  // w QGIS-ie na komputerze i nazwy plikow przy eksporcie — w legendzie
  // mozna je potem nadac jako nazwe wyswietlana.
  const QString nazwa = nowaNazwa.trimmed();
  static const QRegularExpression wzor( QStringLiteral( "^[A-Za-z_][A-Za-z0-9_]*$" ) );
  if ( !wzor.match( nazwa ).hasMatch() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Nazwa tabeli: litery bez polskich znaków, cyfry i _, bez spacji, nie od cyfry." ) );
    return wynik;
  }

  const QVariantMap zr = zrodloWarstwy( zrodlo );
  const QString tabelaZrodla = zr.value( QStringLiteral( "warstwa" ) ).toString();
  if ( !zr.value( QStringLiteral( "wBazieProjektu" ) ).toBool() || tabelaZrodla.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "Duplikować można tylko warstwę z bazy projektu." ) );
    return wynik;
  }
  const QString gpkg = QDir::fromNativeSeparators( zr.value( QStringLiteral( "plik" ) ).toString() );

  // Zajeta w PROJEKCIE (po nazwie albo po tabeli — patrz znajdzWarstwe).
  // Zajeta w BAZIE sprawdza importujWarstwe i odmawia sama.
  if ( znajdzWarstwe( p, nazwa ) )
  {
    wynik.insert( QStringLiteral( "blad" ), tr( "W projekcie jest już warstwa „%1”." ).arg( nazwa ) );
    return wynik;
  }

  const qint64 oczekiwano = zObiektami ? zrodlo->featureCount() : 0;
  wynik.insert( QStringLiteral( "oczekiwano" ), oczekiwano );

  const QVariantMap imp = importujWarstwe( zrodlo->source(), gpkg, nazwa, !zObiektami );
  if ( !imp.value( QStringLiteral( "ok" ) ).toBool() )
  {
    wynik.insert( QStringLiteral( "blad" ), imp.value( QStringLiteral( "blad" ) ) );
    return wynik;
  }

  // LICZNIKI ROZSTRZYGAJA. Niezgodnosc = do projektu nic nie wchodzi;
  // tabela zostaje w bazie, zeby dalo sie obejrzec, co sie stalo.
  const qint64 obiektow = imp.value( QStringLiteral( "obiektow" ) ).toLongLong();
  wynik.insert( QStringLiteral( "obiektow" ), obiektow );
  if ( oczekiwano >= 0 && obiektow != oczekiwano )
  {
    wynik.insert( QStringLiteral( "blad" ),
                  tr( "Tabela %1 powstała, ale ma %2 obiektów zamiast %3. Nie dodaję jej do projektu." )
                    .arg( nazwa ).arg( obiektow ).arg( oczekiwano ) );
    return wynik;
  }

  QgsVectorLayer *nowa = new QgsVectorLayer( gpkg + QStringLiteral( "|layername=" ) + nazwa, nazwa, QStringLiteral( "ogr" ) );
  if ( !nowa->isValid() )
  {
    delete nowa;
    wynik.insert( QStringLiteral( "blad" ), tr( "Tabela %1 jest w bazie, ale nie daje się otworzyć jako warstwa." ).arg( nazwa ) );
    return wynik;
  }

  // Styl i formularz W CALOSCI: symbole, etykiety, aliasy, widzety,
  // wartosci domyslne, ograniczenia, wlasciwosci niestandardowe.
  QDomDocument dokument;
  QString komunikat;
  zrodlo->exportNamedStyle( dokument, komunikat );
  const bool styl = nowa->importNamedStyle( dokument, komunikat );
  wynik.insert( QStringLiteral( "styl" ), styl );

  // Zaraz pod oryginalem, w tej samej grupie.
  p->addMapLayer( nowa, false );
  QgsLayerTree *korzen = p->layerTreeRoot();
  QgsLayerTreeLayer *wezel = korzen->findLayer( zrodlo->id() );
  QgsLayerTreeGroup *rodzic = wezel ? qobject_cast<QgsLayerTreeGroup *>( wezel->parent() ) : nullptr;
  if ( !rodzic )
    rodzic = korzen;
  const int miejsce = wezel ? static_cast<int>( rodzic->children().indexOf( static_cast<QgsLayerTreeNode *>( wezel ) ) ) + 1 : 0;
  rodzic->insertLayer( miejsce, nowa );

  wynik.insert( QStringLiteral( "ok" ), true );
  wynik.insert( QStringLiteral( "nazwa" ), nazwa );
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
// WorkField 23.10.2026 [WF-NEW-LAYER] — layers in the project database.
// See the declarations in the header.
// ---------------------------------------------------------------------------
QString NarzedziaProjektu::tableNameFor( const QString &text ) const
{
  QString t = text.trimmed();
  t.replace( QChar( 0x0141 ), QLatin1Char( 'L' ) ); // Ł does not decompose in NFD
  t.replace( QChar( 0x0142 ), QLatin1Char( 'l' ) ); // ł
  t = t.normalized( QString::NormalizationForm_D );
  QString result;
  result.reserve( t.size() );
  for ( const QChar c : std::as_const( t ) )
  {
    if ( c.category() == QChar::Mark_NonSpacing )
      continue;
    if ( c.unicode() < 128 && ( c.isLetterOrNumber() || c == QLatin1Char( '_' ) ) )
      result.append( c );
    else
      result.append( QLatin1Char( '_' ) );
  }
  static const QRegularExpression repeated( QStringLiteral( "_+" ) );
  result.replace( repeated, QStringLiteral( "_" ) );
  while ( result.startsWith( QLatin1Char( '_' ) ) )
    result.remove( 0, 1 );
  while ( result.endsWith( QLatin1Char( '_' ) ) )
    result.chop( 1 );
  if ( result.isEmpty() )
    return QStringLiteral( "warstwa" );
  if ( result.at( 0 ).isDigit() )
    result.prepend( QStringLiteral( "w_" ) );
  return result;
}

bool NarzedziaProjektu::tableExists( const QString &gpkg, const QString &table ) const
{
  if ( gpkg.isEmpty() || table.isEmpty() || !QFile::exists( gpkg ) )
    return false;
  GDALAllRegister();
  GDALDatasetH dataset = GDALOpenEx( gpkg.toUtf8().constData(), GDAL_OF_VECTOR, nullptr, nullptr, nullptr );
  if ( !dataset )
    return false;
  const bool exists = GDALDatasetGetLayerByName( dataset, table.toUtf8().constData() ) != nullptr;
  GDALClose( dataset );
  return exists;
}

QVariantMap NarzedziaProjektu::setUpNewLayer( QgsProject *project, QgsVectorLayer *layer ) const
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );
  result.insert( QStringLiteral( "snapping" ), false );
  result.insert( QStringLiteral( "attachments" ), false );

  QgsProject *p = project ? project : QgsProject::instance();
  if ( !p || !layer || !layer->isValid() )
  {
    result.insert( QStringLiteral( "error" ), tr( "Nie ma warstwy." ) );
    return result;
  }

  // SNAPPING: the layer is enabled in the per-layer settings. Those matter
  // in the advanced mode; in the other modes this does no harm.
  if ( layer->isSpatial() )
  {
    QgsSnappingConfig config = p->snappingConfig();
    QgsSnappingConfig::IndividualLayerSettings settings = config.individualLayerSettings( layer );
    settings.setEnabled( true );
    config.setIndividualLayerSettings( layer, settings );
    p->setSnappingConfig( config );
    result.insert( QStringLiteral( "snapping" ), true );
  }

  // PHOTOS: ZAL_ table for this layer only.
  const ModulZalacznikow::Wynik attachments = ModulZalacznikow::setUp( p, layer );
  result.insert( QStringLiteral( "attachments" ), attachments.ok );
  result.insert( QStringLiteral( "attachmentsInfo" ), attachments.opis );
  qInfo() << "WFG new layer:" << layer->name() << "| attachments:" << attachments.ok << attachments.opis;

  // [WF-IDENTITY] 24.10.2026: a new layer and its photo table get uuid /
  // PARENT_UUID at once — nothing to "complete" later.
  {
    int fieldsAdded = 0;
    int valuesWritten = 0;
    int renewed = 0;
    QStringList skipped;
    QSet<QString> ambiguous;
    if ( carriesIdentity( layer ) )
      repairLayerIdentity( p, layer, fieldsAdded, valuesWritten, renewed, skipped, ambiguous );
    const QList<QgsRelation> children = p->relationManager()->referencedRelations( layer );
    for ( const QgsRelation &relation : children )
    {
      QgsVectorLayer *child = relation.referencingLayer();
      if ( child && child != layer && carriesIdentity( child ) )
        repairLayerIdentity( p, child, fieldsAdded, valuesWritten, renewed, skipped, ambiguous );
    }
    result.insert( QStringLiteral( "identityFields" ), fieldsAdded );
  }

  result.insert( QStringLiteral( "ok" ), true );
  return result;
}

QVariantMap NarzedziaProjektu::moveLayerToProjectDatabase( QgsProject *project, QgsVectorLayer *layer, const QString &tableName )
{
  QVariantMap result;
  result.insert( QStringLiteral( "ok" ), false );

  QgsProject *p = project ? project : QgsProject::instance();
  if ( !p || !layer || !layer->isValid() )
  {
    result.insert( QStringLiteral( "error" ), tr( "Nie ma warstwy do przeniesienia." ) );
    return result;
  }
  if ( layer->isEditable() )
  {
    result.insert( QStringLiteral( "error" ), tr( "Najpierw zakończ edycję warstwy „%1”." ).arg( layer->name() ) );
    return result;
  }

  const QVariantMap source = zrodloWarstwy( layer );
  if ( source.value( QStringLiteral( "wBazieProjektu" ) ).toBool() )
  {
    result.insert( QStringLiteral( "error" ), tr( "Warstwa już jest w bazie projektu." ) );
    return result;
  }
  if ( !source.value( QStringLiteral( "istnieje" ) ).toBool() )
  {
    result.insert( QStringLiteral( "error" ), tr( "Warstwa nie leży w pliku na tym urządzeniu — nie ma czego przenosić." ) );
    return result;
  }

  const QString database = plikDanych( p );
  if ( database.isEmpty() || !QFile::exists( database ) )
  {
    result.insert( QStringLiteral( "error" ), tr( "Projekt nie ma bazy danych (dane.gpkg)." ) );
    return result;
  }

  const QString table = tableName.trimmed();
  static const QRegularExpression pattern( QStringLiteral( "^[A-Za-z_][A-Za-z0-9_]*$" ) );
  if ( !pattern.match( table ).hasMatch() )
  {
    result.insert( QStringLiteral( "error" ), tr( "Nazwa tabeli: litery bez polskich znaków, cyfry i _, bez spacji, nie od cyfry." ) );
    return result;
  }
  QgsVectorLayer *other = znajdzWarstwe( p, table );
  if ( other && other != layer )
  {
    result.insert( QStringLiteral( "error" ), tr( "W projekcie jest już warstwa „%1”." ).arg( table ) );
    return result;
  }

  const qint64 expected = layer->featureCount();
  result.insert( QStringLiteral( "expected" ), expected );

  // Copy of the table. importujWarstwe NEVER OVERWRITES and counts afterwards.
  const QString oldSource = layer->source();
  const QVariantMap imported = importujWarstwe( oldSource, database, table, false );
  if ( !imported.value( QStringLiteral( "ok" ) ).toBool() )
  {
    result.insert( QStringLiteral( "error" ), imported.value( QStringLiteral( "blad" ) ) );
    return result;
  }
  const qint64 features = imported.value( QStringLiteral( "obiektow" ) ).toLongLong();
  result.insert( QStringLiteral( "features" ), features );
  if ( expected >= 0 && features != expected )
  {
    result.insert( QStringLiteral( "error" ),
                   tr( "Tabela %1 powstała w bazie, ale ma %2 obiektów zamiast %3. Warstwa zostaje przy starym pliku." )
                     .arg( table ).arg( features ).arg( expected ) );
    return result;
  }

  const QString uri = database + QStringLiteral( "|layername=" ) + table;
  {
    QgsVectorLayer probe( uri, table, QStringLiteral( "ogr" ) );
    if ( !probe.isValid() )
    {
      result.insert( QStringLiteral( "error" ), tr( "Tabela %1 jest w bazie, ale nie daje się otworzyć. Warstwa zostaje przy starym pliku." ).arg( table ) );
      return result;
    }
  }

  // RE-POINTING. Same layer (id, style, form, relations), new data source.
  // If it fails, the old source is restored.
  const QString layerName = layer->name();
  layer->setDataSource( uri, layerName, QStringLiteral( "ogr" ), false );
  if ( !layer->isValid() )
  {
    layer->setDataSource( oldSource, layerName, QStringLiteral( "ogr" ), false );
    result.insert( QStringLiteral( "error" ), tr( "Przepięcie warstwy nie wyszło — warstwa wróciła do starego pliku. Tabela %1 została w bazie." ).arg( table ) );
    return result;
  }
  layer->triggerRepaint();
  ++mDataSourcesRevision;
  emit dataSourcesRevisionChanged();

  const ModulZalacznikow::Wynik attachments = ModulZalacznikow::setUp( p, layer );
  result.insert( QStringLiteral( "attachments" ), attachments.ok );
  result.insert( QStringLiteral( "attachmentsInfo" ), attachments.opis );

  qInfo() << "WFG move to database:" << layerName << "from" << oldSource << "to" << uri
          << "features" << features << "| attachments:" << attachments.ok << attachments.opis;

  result.insert( QStringLiteral( "ok" ), true );
  result.insert( QStringLiteral( "table" ), table );
  result.insert( QStringLiteral( "previous" ), source.value( QStringLiteral( "plik" ) ) );
  return result;
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
#include "kodowaniedxf.h"
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

  // Tablica CP1250 mieszka w kodowaniedxf.h - wspolna z modulem inwentaryzacji.
  using KodowanieDxf::doCp1250;

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

// ---------------------------------------------------------------------------
// WorkFieldGIS 22.10.2026 [WF-EKSPORT-CAD] — eksport do CAD z danymi GIS.
// Rdzen: src/core/wfcad (kopia WorkFieldCAD, synchronizuje ja
// skrypty/synchronizuj_wfcad.sh). Tu tylko: kopia bazy, rysunek, wf.lsp,
// CZYTAJ.txt. Czesc bez QGIS, zeby dalo sie ja sprawdzic poza aplikacja.
// [WF-EKSPORT-CAD-RDZEN-POCZATEK]
namespace
{
  QString nazwaUkladu( int epsg )
  {
    switch ( epsg )
    {
      case 0:
        return QStringLiteral( "jak w danych (bez przeliczenia)" );
      case 2176:
        return QStringLiteral( "EPSG:2176 (PL-2000 strefa 5)" );
      case 2177:
        return QStringLiteral( "EPSG:2177 (PL-2000 strefa 6)" );
      case 2178:
        return QStringLiteral( "EPSG:2178 (PL-2000 strefa 7)" );
      case 2179:
        return QStringLiteral( "EPSG:2179 (PL-2000 strefa 8)" );
      default:
        return QStringLiteral( "EPSG:%1" ).arg( epsg );
    }
  }

  bool zapiszBajty( const QString &sciezka, const QByteArray &bajty )
  {
    QFile f( sciezka );
    if ( !f.open( QIODevice::WriteOnly | QIODevice::Truncate ) )
      return false;
    const bool ok = f.write( bajty ) == bajty.size();
    f.close();
    return ok;
  }

  //! Eksport z bazy \a baza do katalogu \a katalog (musi nie istniec albo byc pusty).
  QVariantMap eksportDoCadZBazy( const QString &baza, const QString &katalog, const QString &nazwaProjektu )
  {
    QVariantMap wynik;
    auto blad = [&wynik]( const QString &tekst ) {
      wynik.insert( QStringLiteral( "blad" ), tekst );
      return wynik;
    };
    if ( baza.isEmpty() || !QFileInfo::exists( baza ) )
      return blad( QStringLiteral( "Projekt nie ma bazy GeoPackage z danymi (data.gpkg albo dane.gpkg)" ) );
    QDir kat( katalog );
    if ( kat.exists() && !kat.isEmpty( QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System ) )
      return blad( QStringLiteral( "Katalog %1 już istnieje i nie jest pusty" ).arg( katalog ) );
    if ( !QDir().mkpath( katalog ) )
      return blad( QStringLiteral( "Nie da się utworzyć katalogu %1" ).arg( katalog ) );

    // Kopia przez API kopii SQLite: z ostatnimi zapisami z dziennika WAL,
    // sprawdzona quick_check, bez dziennika obok. Rdzen odmawia pracy na bazie
    // z niepustym -wal — i slusznie; kopia go nie ma.
    const QFileInfo zrodlo( baza );
    const QString kopia = QStringLiteral( "%1/%2" ).arg( katalog, zrodlo.fileName() );
    const QString bladKopii = zapieczetujBaze( baza, kopia );
    if ( !bladKopii.isEmpty() )
      return blad( QStringLiteral( "Kopia bazy %1: %2" ).arg( zrodlo.fileName(), bladKopii ) );

    const QString dxf = QStringLiteral( "%1/%2.dxf" ).arg( katalog, zrodlo.completeBaseName() );
    wfcad::Raport raport;
    wfcad::WynikEksportu w;
    try
    {
      w = wfcad::eksportuj( QFile::encodeName( kopia ).toStdString(), QFile::encodeName( dxf ).toStdString(), wfcad::UKLAD_AUTO, raport );
    }
    catch ( const std::exception &e )
    {
      QFile::remove( dxf );
      return blad( QStringLiteral( "Eksport do CAD: %1" ).arg( QString::fromUtf8( e.what() ) ) );
    }

    const QString lsp = QStringLiteral( "%1/wf.lsp" ).arg( katalog );
    if ( !zapiszBajty( lsp, QByteArray::fromStdString( wfcad::tekstWfLsp() ) ) )
      return blad( QStringLiteral( "Nie da się zapisać %1" ).arg( lsp ) );

    const QString nazwaDxf = QFileInfo( dxf ).fileName();
    const QString nazwaBazy = zrodlo.fileName();
    const QString md5 = QString::fromStdString( w.md5Zrodla );
    QStringList czytaj;
    czytaj << QStringLiteral( "Eksport do CAD — WorkFieldGIS, %1" ).arg( QDateTime::currentDateTime().toString( QStringLiteral( "yyyy-MM-dd HH:mm" ) ) )
           << QStringLiteral( "Projekt: %1" ).arg( nazwaProjektu )
           << QString()
           << QStringLiteral( "%1  — rysunek; układ: %2." ).arg( nazwaDxf, nazwaUkladu( w.uklad ) )
           << QStringLiteral( "    Każdy obiekt niesie swoje dane GIS. %1 obiektów z %2 warstw." ).arg( w.obiektow ).arg( w.warstw )
           << QStringLiteral( "%1  — kopia bazy, z której powstał rysunek (md5 %2)." ).arg( nazwaBazy, md5 )
           << QStringLiteral( "    Nie zmieniaj jej: do niej wraca rysunek z CAD-a." )
           << QStringLiteral( "wf.lsp  — polecenia w CAD-zie: APPLOAD, potem WFINFO, WFZNAJDZ, WFKOLOR," )
           << QStringLiteral( "    WFSKALA, WFODNOSNIK, WFIDZ." )
           << QString()
           << QStringLiteral( "Otwórz DXF w BricsCAD, AutoCAD, ZWCAD albo GstarCAD. Zapisuj jako DXF 2000" )
           << QStringLiteral( "lub nowszy (z DWG przed powrotem zapisz jako DXF). Kolory, okręgi i opisy" )
           << QStringLiteral( "z wf.lsp nie są danymi GIS — przy powrocie są pomijane." )
           << QString()
           << QStringLiteral( "Powrót zmian do bazy (komputer, WorkFieldCAD):" )
           << QStringLiteral( "  wfcad-obieg sprawdz %1" ).arg( nazwaDxf )
           << QStringLiteral( "  wfcad-obieg zapisz %1 %2 %3_z_cad.gpkg" ).arg( nazwaDxf, nazwaBazy, zrodlo.completeBaseName() );
    QStringList uwagi;
    for ( const std::string &t : raport.informacje )
      uwagi << QString::fromStdString( t );
    for ( const std::string &t : raport.ostrzezenia )
      uwagi << QStringLiteral( "UWAGA: " ) + QString::fromStdString( t );
    for ( const std::string &t : raport.straty )
      uwagi << QStringLiteral( "STRATA: " ) + QString::fromStdString( t );
    if ( !uwagi.isEmpty() )
      czytaj << QString() << QStringLiteral( "Raport eksportu:" ) << uwagi;
    zapiszBajty( QStringLiteral( "%1/CZYTAJ.txt" ).arg( katalog ), ( czytaj.join( QLatin1Char( '\n' ) ) + QLatin1Char( '\n' ) ).toUtf8() );

    wynik.insert( QStringLiteral( "katalog" ), katalog );
    wynik.insert( QStringLiteral( "plik" ), dxf );
    wynik.insert( QStringLiteral( "baza" ), kopia );
    wynik.insert( QStringLiteral( "md5" ), md5 );
    wynik.insert( QStringLiteral( "uklad" ), w.uklad );
    wynik.insert( QStringLiteral( "warstw" ), static_cast<int>( w.warstw ) );
    wynik.insert( QStringLiteral( "obiektow" ), static_cast<qlonglong>( w.obiektow ) );
    wynik.insert( QStringLiteral( "encji" ), static_cast<qlonglong>( w.encji ) );
    wynik.insert( QStringLiteral( "straty" ), static_cast<int>( raport.straty.size() ) );
    wynik.insert( QStringLiteral( "uwagi" ), uwagi.join( QLatin1Char( '\n' ) ) );
    return wynik;
  }
} // namespace
// [WF-EKSPORT-CAD-RDZEN-KONIEC]

QVariantMap NarzedziaProjektu::eksportujDoCad( QgsProject *projekt, const QString &katalog ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || p->homePath().isEmpty() )
  {
    QVariantMap wynik;
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }
  QString nazwa = p->title().trimmed();
  if ( nazwa.isEmpty() )
    nazwa = QFileInfo( p->homePath() ).fileName();
  if ( nazwa.isEmpty() )
    nazwa = QStringLiteral( "projekt" );
  QString bezpieczna = nazwa;
  bezpieczna.replace( QRegularExpression( QStringLiteral( "[\\\\/:*?\"<>|\\s]+" ) ), QStringLiteral( "_" ) );
  const QString kat = katalog.isEmpty()
                        ? QStringLiteral( "%1/export/%2_CAD_%3" ).arg( p->homePath(), bezpieczna, QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmmss" ) ) )
                        : katalog;
  return eksportDoCadZBazy( plikDanych( p ), kat, nazwa );
}

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
