/***************************************************************************
  cad.cpp - WorkField
 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "cad.h"

#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QList>
#include <cmath>
#include <QRegularExpression>
#include <QSet>
#include <algorithm>

#include <qgsfeature.h>
#include <qgsfeatureiterator.h>
#include <qgsfeaturerequest.h>
#include <qgslayertree.h>
#include <qgsmaplayer.h>
#include <qgsproject.h>
#include <qgscategorizedsymbolrenderer.h>
#include <qgsrendercontext.h>
#include <qgsrenderer.h>
#include <qgsmarkersymbol.h>
#include <qgsmarkersymbollayer.h>
#include <qgsproperty.h>
#include <qgssymbol.h>
#include <qgssymbollayer.h>
#include <qgsvectorlayer.h>

#include <QDir>

#include <cpl_conv.h>
#include <gdal.h>
#include <ogr_api.h>

#include "kodowaniedxf.h"
#include "utils/qflayerutils.h"
#include "utils/narzedziaprojektu.h"
#include "utils/warstwice.h"
#include "utils/qfprojectutils.h"

namespace
{
  //! Znacznik projektu zalozonego z modulu - ten sam wzorzec co przy drzewach.
  bool zModulu( QgsProject *p )
  {
    return p && !p->readEntry( QStringLiteral( "wfg_moduly" ), QStringLiteral( "/cad" ) ).isEmpty();
  }

  //! Warstwa zapamietana w ustawieniach projektu (wfg_cad/<klucz> = id warstwy).
  QgsVectorLayer *warstwaZUstawien( QgsProject *p, const QString &klucz )
  {
    if ( !p )
      return nullptr;
    const QString id = p->readEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/" ) + klucz );
    if ( id.isEmpty() )
      return nullptr;
    return qobject_cast<QgsVectorLayer *>( p->mapLayer( id ) );
  }

  /**
   * Czy warstwa pochodzi z rysunku? Po ZRODLE, nie po nazwie: nazwy sa
   * tlumaczone i uzytkownik moze je zmienic, a sciezka do pliku .dxf nie.
   */
  bool zRysunku( QgsMapLayer *w )
  {
    if ( !w )
      return false;
    const QString zrodlo = w->source().section( '|', 0, 0 );
    return zrodlo.endsWith( QLatin1String( ".dxf" ), Qt::CaseInsensitive );
  }

  //! Nazwa warstwy rysunku po ludzku (naprawa krzakow z $DWGCODEPAGE).
  QString czytelna( const QString &surowa )
  {
    return KodowanieDxf::zKrzakow( surowa );
  }

  /**
   * Warunek subsetString ukrywajacy podane warstwy rysunku. Apostrof
   * w nazwie warstwy CAD-a jest legalny, wiec podwajamy go jak w SQL-u.
   */
  QString warunekUkrycia( const QStringList &ukryte )
  {
    if ( ukryte.isEmpty() )
      return QString();
    QStringList wartosci;
    for ( const QString &n : ukryte )
      wartosci << QStringLiteral( "'%1'" ).arg( QString( n ).replace( QLatin1Char( '\'' ), QLatin1String( "''" ) ) );
    return QStringLiteral( "\"Layer\" NOT IN (%1)" ).arg( wartosci.join( QStringLiteral( ", " ) ) );
  }

  QList<QgsVectorLayer *> warstwyCad( QgsProject *p )
  {
    QList<QgsVectorLayer *> lista;
    if ( !p )
      return lista;
    const QMap<QString, QgsMapLayer *> warstwy = p->mapLayers();
    for ( QgsMapLayer *w : warstwy )
    {
      if ( QgsVectorLayer *vl = qobject_cast<QgsVectorLayer *>( w ) )
      {
        if ( zRysunku( vl ) )
          lista << vl;
      }
    }
    return lista;
  }

  //! Warstwa robocza: z ustawien, a gdy ich nie ma - pierwsza pasujaca geometria
  //! sposrod warstw, ktore NIE sa rysunkiem.
  QgsVectorLayer *robocza( QgsProject *p, const QString &klucz, Qgis::GeometryType geometria )
  {
    if ( QgsVectorLayer *z = warstwaZUstawien( p, klucz ) )
      return z;
    if ( !p )
      return nullptr;
    const QMap<QString, QgsMapLayer *> warstwy = p->mapLayers();
    for ( QgsMapLayer *w : warstwy )
    {
      QgsVectorLayer *vl = qobject_cast<QgsVectorLayer *>( w );
      if ( !vl || zRysunku( vl ) || vl->geometryType() != geometria )
        continue;
      return vl;
    }
    return nullptr;
  }
} // namespace

namespace
{
  //! Sciezka do pliku rysunku - z pierwszej warstwy CAD w projekcie.
  QString plikRysunku( QgsProject *p )
  {
    const QList<QgsVectorLayer *> rysunek = warstwyCad( p );
    if ( rysunek.isEmpty() )
      return QString();
    // WYBRANY rysunek, gdy w projekcie jest ich kilka. Dotad bralo sie
    // `first()`, a kolejnosc `mapLayers()` jest kolejnoscia identyfikatorow,
    // czyli przypadkowa - przy dwoch rysunkach modul czytal raz z tego,
    // raz z tamtego, i nikt nie mial jak tego rozstrzygnac (21.09.2026).
    const QString wybrany = p ? p->readEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/wybranyRysunek" ) ) : QString();
    if ( !wybrany.isEmpty() )
    {
      for ( QgsVectorLayer *vl : rysunek )
        if ( vl->source().section( '|', 0, 0 ) == wybrany )
          return wybrany;
    }
    return rysunek.first()->source().section( '|', 0, 0 );
  }

  /**
   * Rysunek otwarty PONOWNIE, z blokami NIEROZWINIETYMI - przez GOLE GDAL.
   *
   * PIERWSZA WERSJA ROBILA TO PRZEZ QgsVectorLayer I NIE DZIALALA (telefon,
   * 21.09: "rysunek nie ma wstawionych blokow" na obu probnych projektach).
   * QGIS trzyma PULE OTWARTYCH ZBIOROW DANYCH kluczowana sciezka pliku, wiec
   * druga warstwa na tym samym rysunku nie otwiera go na nowo - dostaje
   * zbior otwarty wczesniej, przy skladaniu projektu, czyli
   * z DXF_INLINE_BLOCKS=TRUE. Przestawienie opcji nie mialo czego dotknac.
   *
   * GDALOpenEx otwiera WLASNY zbior, obok puli - ta sama droga, ktora
   * repozytorium idzie juz w narzedziaprojektu.cpp. Opcje ustawiamy WATKOWO:
   * wersja watkowa ma pierwszenstwo przed globalna i nie dotyka tego, co
   * w tej chwili robia watki renderowania.
   */
  struct RysunekZBlokami
  {
    GDALDatasetH zbior = nullptr;
    OGRLayerH warstwa = nullptr;
    QString blad;

    explicit RysunekZBlokami( const QString &plik )
    {
      if ( plik.isEmpty() )
      {
        blad = QStringLiteral( "Nie wiadomo, z jakiego pliku jest rysunek" );
        return;
      }
      CPLSetThreadLocalConfigOption( "DXF_INLINE_BLOCKS", "FALSE" );
      zbior = GDALOpenEx( plik.toUtf8().constData(), GDAL_OF_VECTOR | GDAL_OF_READONLY, nullptr, nullptr, nullptr );
      CPLSetThreadLocalConfigOption( "DXF_INLINE_BLOCKS", nullptr );
      if ( !zbior )
      {
        blad = QStringLiteral( "Nie udało się otworzyć rysunku: %1" ).arg( plik );
        return;
      }
      warstwa = GDALDatasetGetLayerByName( zbior, "entities" );
      if ( !warstwa )
        warstwa = GDALDatasetGetLayer( zbior, 0 );
      if ( !warstwa )
        blad = QStringLiteral( "Rysunek nie ma warstwy encji" );
    }

    RysunekZBlokami( const RysunekZBlokami & ) = delete;
    RysunekZBlokami &operator=( const RysunekZBlokami & ) = delete;

    ~RysunekZBlokami()
    {
      if ( zbior )
        GDALClose( zbior );
    }

    bool dobry() const { return warstwa && blad.isEmpty(); }

    int pole( const char *nazwa ) const
    {
      return warstwa ? OGR_FD_GetFieldIndex( OGR_L_GetLayerDefn( warstwa ), nazwa ) : -1;
    }
  };

  //! Pola, ktorych nazwa jest juz zajeta - atrybut o takiej nazwie dostaje "_B".
  bool nazwaZajeta( const QString &n )
  {
    static const QStringList nasze = { QStringLiteral( "fid" ), QStringLiteral( "BLOK" ), QStringLiteral( "WARSTWA" ), QStringLiteral( "KAT" ), QStringLiteral( "UCHWYT" ), QStringLiteral( "OPIS" ), QStringLiteral( "DATA" ), QStringLiteral( "ZDJECIE" ) };
    return nasze.contains( n, Qt::CaseInsensitive );
  }

  /**
   * Nazwa kolumny z nazwy znacznika ATTRIB. Znaczniki w DXF-ie bywaja
   * z myslnikami i polskimi literami, a nazwa kolumny w GPKG ma byc prosta.
   */
  QString kolumnaZnacznika( const QString &znacznik )
  {
    QString n;
    for ( const QChar z : znacznik )
      n += ( z.isLetterOrNumber() && z.unicode() < 128 ) ? z.toUpper() : QLatin1Char( '_' );
    while ( n.startsWith( QLatin1Char( '_' ) ) )
      n.remove( 0, 1 );
    if ( n.isEmpty() )
      return QString();
    // Nazwa nie moze zaczynac sie od cyfry.
    if ( n.at( 0 ).isDigit() )
      n.prepend( QLatin1Char( 'A' ) );
    if ( nazwaZajeta( n ) )
      n += QLatin1String( "_B" );
    return n.left( 30 );
  }

  /**
   * Atrybuty wstawienia: {kolumna -> wartosc}.
   *
   * GDAL oddaje je jako liste napisow "ZNACZNIK wartosc" - znacznik, spacja,
   * reszta. Znacznik w DXF-ie nie moze miec spacji, wiec dzielimy na
   * PIERWSZEJ; wartosc spacje miec moze i ma zostac w calosci.
   */
  QMap<QString, QString> atrybutyWstawienia( OGRFeatureH f, int idAtrybutow )
  {
    QMap<QString, QString> wynik;
    if ( idAtrybutow < 0 || !OGR_F_IsFieldSetAndNotNull( f, idAtrybutow ) )
      return wynik;
    char **lista = OGR_F_GetFieldAsStringList( f, idAtrybutow );
    for ( int i = 0; lista && lista[i]; i++ )
    {
      const QString wpis = QString::fromUtf8( lista[i] );
      const int spacja = wpis.indexOf( QLatin1Char( ' ' ) );
      const QString znacznik = spacja < 0 ? wpis : wpis.left( spacja );
      const QString wartosc = spacja < 0 ? QString() : wpis.mid( spacja + 1 );
      const QString kolumna = kolumnaZnacznika( znacznik );
      if ( !kolumna.isEmpty() )
        wynik.insert( kolumna, wartosc );
    }
    return wynik;
  }

  //! Ile najwyzej kolumn dokladamy - rysunek z setka znacznikow nie ma
  //! zrobic z warstwy tabeli, ktorej nie da sie otworzyc w formularzu.
  const int MAKS_KOLUMN_ATRYBUTOW = 20;

  /**
   * Geometria bloku -> sciezki SVG. Rekurencyjnie, bo blok bywa
   * GEOMETRYCOLLECTION z liniami i poligonami (drzewo lisciaste w probnym
   * rysunku ma piec linii i poligon).
   *
   * Os Y w SVG rosnie W DOL, w rysunku W GORE - stad minus przy y.
   * `polowa` zbiera najdalszy punkt od srodka: uklad bloku ma punkt
   * wstawienia w (0,0), a znacznik QGIS jest rysowany WOKOL punktu obiektu,
   * wiec pole widzenia musi byc symetryczne wzgledem zera. Liczone po
   * bezwzglednej wartosci, nie po prostokacie otaczajacym - inaczej symbol
   * przesunalby sie wzgledem punktu wstawienia.
   */
  void doSciezekSvg( OGRGeometryH g, QStringList &sciezki, double &polowa )
  {
    if ( !g )
      return;
    const int punktow = OGR_G_GetPointCount( g );
    if ( punktow > 0 )
    {
      QString d;
      for ( int i = 0; i < punktow; i++ )
      {
        const double x = OGR_G_GetX( g, i );
        const double y = OGR_G_GetY( g, i );
        polowa = std::max( polowa, std::max( std::abs( x ), std::abs( y ) ) );
        d += QStringLiteral( "%1%2,%3" ).arg( i == 0 ? QLatin1String( "M" ) : QLatin1String( "L" ) )
               .arg( x, 0, 'f', 4 ).arg( -y, 0, 'f', 4 );
      }
      if ( punktow == 1 )
        d += QStringLiteral( "l0.0001,0" ); // sam punkt - kropka, nie nic
      sciezki << d;
      return;
    }
    const int dzieci = OGR_G_GetGeometryCount( g );
    for ( int i = 0; i < dzieci; i++ )
      doSciezekSvg( OGR_G_GetGeometryRef( g, i ), sciezki, polowa );
  }

  /**
   * SVG dla blokow, ktore SA w warstwie symboli - nie dla wszystkich
   * z sekcji BLOCKS. Rysunek ma ich wiecej, niz sie wczytuje (Bruzdowa 23
   * definicje, 21 uzywanych), a klasa bez obiektow to smiec w legendzie.
   * Zwraca {nazwa bloku -> {sciezka, rozmiar}}; rozmiar to rzeczywista
   * wielkosc bloku w jednostkach rysunku, czyli mapy.
   *
   * Kolor i grubosc kreski zostaja PARAMETRAMI (`param(outline)`), zeby dalo
   * sie je zmienic w QGIS bez ruszania pliku.
   */
  QMap<QString, QPair<QString, double>> symboleBlokow( const QString &plik, const QString &katalog, const QSet<QString> &uzywane )
  {
    QMap<QString, QPair<QString, double>> wynik;
    RysunekZBlokami rysunek( plik );
    if ( !rysunek.dobry() || !rysunek.zbior )
      return wynik;
    OGRLayerH bloki = GDALDatasetGetLayerByName( rysunek.zbior, "blocks" );
    if ( !bloki )
      return wynik;
    const int idNazwy = OGR_FD_GetFieldIndex( OGR_L_GetLayerDefn( bloki ), "Block" );
    if ( idNazwy < 0 )
      return wynik;
    if ( !QDir().mkpath( katalog ) )
      return wynik;

    OGR_L_ResetReading( bloki );
    while ( OGRFeatureH f = OGR_L_GetNextFeature( bloki ) )
    {
      const QString nazwa = QString::fromUtf8( OGR_F_GetFieldAsString( f, idNazwy ) );
      QStringList sciezki;
      double polowa = 0;
      const bool chciany = !nazwa.isEmpty() && ( uzywane.isEmpty() || uzywane.contains( nazwa ) );
      if ( chciany )
        doSciezekSvg( OGR_F_GetGeometryRef( f ), sciezki, polowa );
      OGR_F_Destroy( f );
      if ( !chciany || sciezki.isEmpty() || polowa <= 0 )
        continue;

      // Nazwa bloku bywa dowolna - do nazwy pliku puszczamy tylko to, co bezpieczne.
      QString plikSvg = nazwa;
      plikSvg.replace( QRegularExpression( QStringLiteral( "[^A-Za-z0-9_.-]" ) ), QStringLiteral( "_" ) );
      const QString sciezkaSvg = katalog + QStringLiteral( "/" ) + plikSvg + QStringLiteral( ".svg" );

      QString svg = QStringLiteral( "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\" viewBox=\"%1 %1 %2 %2\">\n" )
                      .arg( -polowa, 0, 'f', 4 ).arg( 2 * polowa, 0, 'f', 4 );
      svg += QStringLiteral( "<g fill=\"none\" stroke=\"param(outline) #202020\" stroke-width=\"param(outline-width) %1\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n" )
               .arg( polowa / 12.0, 0, 'f', 4 );
      for ( const QString &d : std::as_const( sciezki ) )
        svg += QStringLiteral( "<path d=\"%1\"/>\n" ).arg( d );
      svg += QStringLiteral( "</g>\n</svg>\n" );

      QFile plikWy( sciezkaSvg );
      if ( !plikWy.open( QIODevice::WriteOnly | QIODevice::Truncate ) )
        continue;
      plikWy.write( svg.toUtf8() );
      plikWy.close();
      wynik.insert( nazwa, qMakePair( sciezkaSvg, 2 * polowa ) );
    }
    return wynik;
  }

  /**
   * Styl warstwy symboli: klasy po polu BLOK, kazda z wlasnym SVG.
   *
   * Rozmiar W JEDNOSTKACH MAPY i rowny rzeczywistej wielkosci bloku - obiekt
   * lezy wtedy dokladnie na symbolu narysowanym w rysunku, zamiast plywac
   * obok w stalej wielkosci ekranowej.
   *
   * Obrot: DXF liczy BlockAngle PRZECIWNIE do wskazowek zegara, QGIS -
   * zgodnie, stad minus.
   */
  void stylujSymbole( QgsVectorLayer *cel, const QMap<QString, QPair<QString, double>> &symbole )
  {
    if ( !cel || symbole.isEmpty() )
      return;
    QgsCategoryList kategorie;
    for ( auto i = symbole.constBegin(); i != symbole.constEnd(); ++i )
    {
      QgsSvgMarkerSymbolLayer *warstwaSymbolu = new QgsSvgMarkerSymbolLayer( i.value().first );
      warstwaSymbolu->setSize( i.value().second );
      warstwaSymbolu->setSizeUnit( Qgis::RenderUnit::MapUnits );
      warstwaSymbolu->setStrokeColor( QColor( 32, 32, 32 ) );
      warstwaSymbolu->setStrokeWidth( 0.3 );
      warstwaSymbolu->setStrokeWidthUnit( Qgis::RenderUnit::Millimeters );
      QgsMarkerSymbol *symbol = new QgsMarkerSymbol( QgsSymbolLayerList() << warstwaSymbolu );
      symbol->setDataDefinedAngle( QgsProperty::fromExpression( QStringLiteral( "-coalesce(\"KAT\", 0)" ) ) );
      kategorie << QgsRendererCategory( i.key(), symbol, i.key() );
    }
    // Klasa domyslna: blok, ktorego symbolu nie udalo sie zbudowac, ma byc
    // WIDOCZNY, a nie niewidzialny - inaczej obiekt jest w bazie i nie ma go
    // na mapie, czyli najgorszy mozliwy stan.
    QgsSimpleMarkerSymbolLayer *zapasowa = new QgsSimpleMarkerSymbolLayer( Qgis::MarkerShape::Circle, 2.0 );
    zapasowa->setColor( QColor( 255, 255, 255, 0 ) );
    zapasowa->setStrokeColor( QColor( 216, 27, 96 ) );
    kategorie << QgsRendererCategory( QVariant(), new QgsMarkerSymbol( QgsSymbolLayerList() << zapasowa ), QObject::tr( "inne" ) );

    cel->setRenderer( new QgsCategorizedSymbolRenderer( QStringLiteral( "BLOK" ), kategorie ) );
    cel->triggerRepaint();
  }

  //! Nazwy blokow, ktore SA w warstwie symboli - po nich robi sie legende.
  QSet<QString> blokiWWarstwie( QgsVectorLayer *cel )
  {
    QSet<QString> nazwy;
    if ( !cel )
      return nazwy;
    const int idBlok = cel->fields().lookupField( QStringLiteral( "BLOK" ) );
    if ( idBlok < 0 )
      return nazwy;
    QgsFeatureRequest zadanie;
    zadanie.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
    zadanie.setSubsetOfAttributes( QgsAttributeList() << idBlok );
    QgsFeatureIterator it = cel->getFeatures( zadanie );
    QgsFeature f;
    while ( it.nextFeature( f ) )
    {
      const QString n = f.attribute( idBlok ).toString();
      if ( !n.isEmpty() )
        nazwy.insert( n );
    }
    return nazwy;
  }

  //! Warstwa "Symbole z rysunku": z ustawien projektu (wfg_cad/warstwaSymboli).
  QgsVectorLayer *warstwaSymboli( QgsProject *p )
  {
    return warstwaZUstawien( p, QStringLiteral( "warstwaSymboli" ) );
  }
} // namespace

CAD::CAD( QObject *parent )
  : QObject( parent )
{
}

QVariantMap CAD::opis() const
{
  // Opis modulu = przyszly modul.json z paczki. Zakladka "Moduly" buduje
  // z niego karte i przyciski; nic w QML nie jest wpisane pod CAD.
  //
  // "start" to NOWE pole obok "przepis": modul, ktory nie zaklada pustych
  // warstw, tylko wychodzi od cudzego pliku. Panel ma z niego zrobic
  // przycisk otwierajacy wskazane okno.
  static const QByteArray json = QByteArrayLiteral( R"WFG({
  "id": "cad",
  "nazwa": "Inwentaryzacja CAD",
  "wersja": "1.0",
  "silnik": "CAD",
  "opis": "Rysunek DXF jako podkład, trzy warstwy robocze (punkty, linie, poligony) z opisem, datą i zdjęciem. Wynik wraca do CAD-a.",
  "wymaga_silnika": ["CAD.rozpoznaj", "CAD.wyczysc", "CAD.warstwyRysunku", "CAD.pokazWarstwy", "CAD.bloki", "CAD.zBlokow", "CAD.dociagnijOpisy", "CAD.eksportuj", "CAD.warstwiceZRzednych", "CAD.kropkiNapisow", "CAD.rysunki", "CAD.wybierzRysunek"],
  "wymaga_modulow": [],
  "rozpoznanie": "CAD.rozpoznaj",
  "role": [
    { "klucz": "rysunek", "nazwa": "rysunek" },
    { "klucz": "warstwaPunktow", "nazwa": "punkty" },
    { "klucz": "warstwaLinii", "nazwa": "linie" },
    { "klucz": "warstwaPoligonow", "nazwa": "poligony" }
  ],
  "start": {
    "rodzaj": "z_pliku",
    "etykieta": "Nowy projekt z rysunku CAD…",
    "okno": "kreatorCAD",
    "opis": "Wskaż rysunek DXF, wybierz układ — projekt powstanie z rysunkiem jako podkładem."
  },
  "akcje": [
    {
      "etykieta": "Import z rysunku DXF…",
      "ikona": "wfg_import",
      "okno": "oknoImportuCAD",
      "opis": "Wszystko z rysunku w jednym przejściu: co widać, bloki jako obiekty, opisy do obiektów, warstwice z rzędnych."
    },
    {
      "etykieta": "Podkłady i dane wysokościowe…",
      "ikona": "wfg_podklad",
      "okno": "podklady",
      "opis": "Ortofoto, mapy urzędowe, NMT i zdjęcie mapy bez georeferencji — wspólne okno podkładów."
    },
    {
      "etykieta": "Eksport do DXF",
      "ikona": "wfg_eksport",
      "czasownik": "CAD.eksportuj",
      "wyslij": "pliki",
      "komunikat": "DXF: {obiekty} obiektów z {warstwy} warstw"
    },
    {
      "etykieta": "Wyczyść dane terenowe",
      "czasownik": "CAD.wyczysc",
      "zapisz_projekt": true,
      "tylko_z_modulu": true,
      "potwierdz": "Usunąć wszystkie obiekty z warstw roboczych? Rysunek CAD zostaje.",
      "komunikat": "Wyczyszczone: {usuniete} obiektów z warstw {warstwy}"
    }
  ]
})WFG" );
  static const QVariantMap opis = QJsonDocument::fromJson( json ).object().toVariantMap();
  return opis;
}

QVariantMap CAD::rozpoznaj( QgsProject *projekt ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }

  const QList<QgsVectorLayer *> rysunek = warstwyCad( p );
  if ( rysunek.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Projekt nie ma rysunku CAD (warstwy z pliku .dxf)" ) );
    return wynik;
  }

  long long obiektyRysunku = 0;
  for ( QgsVectorLayer *vl : rysunek )
    obiektyRysunku += vl->featureCount() > 0 ? vl->featureCount() : 0;

  wynik.insert( QStringLiteral( "rysunek" ), QFileInfo( rysunek.first()->source().section( '|', 0, 0 ) ).fileName() );
  wynik.insert( QStringLiteral( "warstwyRysunku" ), rysunek.size() );
  wynik.insert( QStringLiteral( "obiektyRysunku" ), obiektyRysunku );

  long long obiekty = 0;
  const struct
  {
    const char *klucz;
    Qgis::GeometryType geometria;
  } robocze[] = {
    { "warstwaPunktow", Qgis::GeometryType::Point },
    { "warstwaLinii", Qgis::GeometryType::Line },
    { "warstwaPoligonow", Qgis::GeometryType::Polygon },
  };
  for ( const auto &r : robocze )
  {
    QgsVectorLayer *vl = robocza( p, QString::fromLatin1( r.klucz ), r.geometria );
    if ( !vl )
      continue;
    wynik.insert( QString::fromLatin1( r.klucz ), vl->name() );
    wynik.insert( QString::fromLatin1( r.klucz ) + QStringLiteral( "Id" ), vl->id() );
    if ( vl->featureCount() > 0 )
      obiekty += vl->featureCount();
  }
  wynik.insert( QStringLiteral( "obiekty" ), obiekty );
  wynik.insert( QStringLiteral( "zModulu" ), zModulu( p ) );
  return wynik;
}

QVariantMap CAD::wyczysc( QgsProject *projekt ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }
  // Tylko projekt zalozony z modulu - w cudzym projekcie jedno tapniecie
  // skasowaloby prace, ktorej nie da sie odtworzyc.
  if ( !zModulu( p ) )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Czyszczenie działa tylko w projekcie założonym z modułu" ) );
    return wynik;
  }

  QList<QgsVectorLayer *> warstwy;
  if ( QgsVectorLayer *vl = robocza( p, QStringLiteral( "warstwaPunktow" ), Qgis::GeometryType::Point ) )
    warstwy << vl;
  if ( QgsVectorLayer *vl = robocza( p, QStringLiteral( "warstwaLinii" ), Qgis::GeometryType::Line ) )
    warstwy << vl;
  if ( QgsVectorLayer *vl = robocza( p, QStringLiteral( "warstwaPoligonow" ), Qgis::GeometryType::Polygon ) )
    warstwy << vl;

  int usuniete = 0;
  QStringList nazwy, bledy;
  for ( QgsVectorLayer *vl : std::as_const( warstwy ) )
  {
    // Rysunek jest tylko do czytania i nie moze tu wpasc nawet przez pomylke.
    if ( zRysunku( vl ) )
      continue;
    const bool bylaEdycja = vl->isEditable();
    if ( !bylaEdycja && !vl->startEditing() )
    {
      bledy << QStringLiteral( "%1: nie da się edytować" ).arg( vl->name() );
      continue;
    }
    const QgsFeatureIds ids = vl->allFeatureIds();
    if ( ids.isEmpty() )
    {
      if ( !bylaEdycja )
        vl->rollBack();
      continue;
    }
    if ( !vl->deleteFeatures( ids ) )
    {
      if ( !bylaEdycja )
        vl->rollBack();
      bledy << QStringLiteral( "%1: usuwanie odrzucone" ).arg( vl->name() );
      continue;
    }
    if ( !bylaEdycja && !vl->commitChanges() )
    {
      bledy << QStringLiteral( "%1: %2" ).arg( vl->name(), vl->commitErrors().join( QStringLiteral( "; " ) ) );
      vl->rollBack();
      continue;
    }
    usuniete += ids.size();
    nazwy << vl->name();
    vl->triggerRepaint();
  }

  if ( !bledy.isEmpty() )
    wynik.insert( QStringLiteral( "blad" ), bledy.join( QStringLiteral( "; " ) ) );
  wynik.insert( QStringLiteral( "usuniete" ), usuniete );
  wynik.insert( QStringLiteral( "warstwy" ), nazwy.isEmpty() ? QStringLiteral( "—" ) : nazwy.join( QStringLiteral( ", " ) ) );
  return wynik;
}

QVariantList CAD::warstwyRysunku( QgsProject *projekt ) const
{
  // Warstwy rysunku siedza w ATRYBUCIE "Layer", bo GDAL zwraca z DXF-a jedna
  // warstwe na typ geometrii, a nie na warstwe CAD-a. CADowiec mysli
  // warstwami, wiec trzeba mu je wyjac (ImportDXF.md, "Czego NIE ma").
  QVariantList lista;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
    return lista;

  QMap<QString, int> ile;
  const QList<QgsVectorLayer *> rysunek = warstwyCad( p );
  for ( QgsVectorLayer *vl : rysunek )
  {
    const int idx = vl->fields().lookupField( QStringLiteral( "Layer" ) );
    if ( idx < 0 )
      continue;
    QgsFeatureRequest zadanie;
    zadanie.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
    zadanie.setSubsetOfAttributes( QgsAttributeList() << idx );
    QgsFeatureIterator it = vl->getFeatures( zadanie );
    QgsFeature f;
    while ( it.nextFeature( f ) )
    {
      const QString nazwa = f.attribute( idx ).toString();
      if ( nazwa.isEmpty() )
        continue;
      ile[nazwa] += 1;
    }
  }

  // Spis PELNY, lacznie z ukrytymi. Po zalozeniu filtra ukryte warstwy nie
  // wracaja juz z bazy (getFeatures respektuje subsetString), wiec bez
  // zapamietanego spisu filtr bylby droga w jedna strone.
  const QStringList ukryte = p->readListEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/ukryteWarstwy" ) );
  QStringList spis = ile.keys();
  if ( ukryte.isEmpty() )
  {
    // Nic nie jest ukryte, czyli to, co widac, JEST calym spisem - zapisz.
    p->writeEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/warstwyRysunku" ), spis );
  }
  else
  {
    const QStringList zapamietany = p->readListEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/warstwyRysunku" ) );
    for ( const QString &n : zapamietany )
    {
      if ( !spis.contains( n ) )
        spis << n;
    }
    spis.sort();
  }

  for ( const QString &nazwa : std::as_const( spis ) )
  {
    QVariantMap w;
    // "nazwa" jest DO POKAZANIA (naprawiona), "klucz" DO DOPASOWANIA
    // (surowy - tak, jak siedzi w bazie i w warunku subsetString).
    w.insert( QStringLiteral( "nazwa" ), czytelna( nazwa ) );
    w.insert( QStringLiteral( "klucz" ), nazwa );
    w.insert( QStringLiteral( "obiekty" ), ile.value( nazwa, 0 ) );
    w.insert( QStringLiteral( "widoczna" ), !ukryte.contains( nazwa ) );
    lista << w;
  }
  return lista;
}

QVariantList CAD::rysunki( QgsProject *projekt ) const
{
  QVariantList lista;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
    return lista;
  // Jeden rysunek to kilka warstw (punkty, linie, powierzchnie) o tym samym
  // pliku zrodlowym - liczymy je, bo to jest to, co widac w drzewie warstw.
  QMap<QString, int> ile;
  const QList<QgsVectorLayer *> warstwy = warstwyCad( p );
  for ( QgsVectorLayer *vl : warstwy )
    ile[vl->source().section( '|', 0, 0 )] += 1;
  const QString wybrany = plikRysunku( p );
  for ( auto i = ile.constBegin(); i != ile.constEnd(); ++i )
  {
    QVariantMap w;
    w.insert( QStringLiteral( "plik" ), i.key() );
    w.insert( QStringLiteral( "nazwa" ), QFileInfo( i.key() ).fileName() );
    w.insert( QStringLiteral( "warstwy" ), i.value() );
    w.insert( QStringLiteral( "wybrany" ), i.key() == wybrany );
    lista << w;
  }
  return lista;
}

QVariantMap CAD::wybierzRysunek( QgsProject *projekt, const QString &plik ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }
  bool jest = false;
  const QList<QgsVectorLayer *> warstwy = warstwyCad( p );
  for ( QgsVectorLayer *vl : warstwy )
  {
    if ( vl->source().section( '|', 0, 0 ) == plik )
    {
      jest = true;
      break;
    }
  }
  if ( !jest )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Tego rysunku nie ma w projekcie: %1" ).arg( QFileInfo( plik ).fileName() ) );
    return wynik;
  }
  p->writeEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/wybranyRysunek" ), plik );
  qInfo() << "WFG CAD.wybierzRysunek:" << plik;
  wynik.insert( QStringLiteral( "plik" ), plik );
  return wynik;
}

QVariantMap CAD::kropkiNapisow( QgsProject *projekt, bool pokaz ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }

  const QList<QgsVectorLayer *> rysunek = warstwyCad( p );
  if ( rysunek.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Projekt nie ma rysunku CAD (warstwy z pliku .dxf)" ) );
    return wynik;
  }

  // Warunek jest WLACZAJACY, a nie wylaczajacy: wlasciwosc nazywa sie
  // "warstwa wlaczona", wiec ma byc prawdziwa dla wszystkiego, co NIE
  // jest tekstem. Brak pola SubClasses = nie ruszamy niczego.
  const QString warunek = QStringLiteral( "coalesce(\"SubClasses\", '') NOT LIKE '%AcDbText%'" );

  int warstw = 0, symboli = 0;
  QgsRenderContext kontekst;
  for ( QgsVectorLayer *vl : rysunek )
  {
    if ( vl->fields().lookupField( QStringLiteral( "SubClasses" ) ) < 0 )
      continue;
    QgsFeatureRenderer *r = vl->renderer();
    if ( !r )
      continue;
    bool ruszone = false;
    const QgsSymbolList symbole = r->symbols( kontekst );
    for ( QgsSymbol *s : symbole )
    {
      if ( !s || s->type() != Qgis::SymbolType::Marker )
        continue;
      for ( int i = 0; i < s->symbolLayerCount(); i++ )
      {
        QgsSymbolLayer *sl = s->symbolLayer( i );
        if ( !sl )
          continue;
#if _QGIS_VERSION_INT >= 33600
        sl->setDataDefinedProperty( QgsSymbolLayer::Property::LayerEnabled,
                                    pokaz ? QgsProperty() : QgsProperty::fromExpression( warunek ) );
#else
        sl->setDataDefinedProperty( QgsSymbolLayer::PropertyLayerEnabled,
                                    pokaz ? QgsProperty() : QgsProperty::fromExpression( warunek ) );
#endif
        symboli++;
        ruszone = true;
      }
    }
    if ( ruszone )
    {
      warstw++;
      vl->triggerRepaint();
    }
  }

  p->writeEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/kropkiNapisow" ), pokaz ? 1 : 0 );
  qInfo() << "WFG CAD.kropkiNapisow:" << pokaz << "warstw" << warstw << "symboli" << symboli;
  wynik.insert( QStringLiteral( "warstwy" ), warstw );
  wynik.insert( QStringLiteral( "symbole" ), symboli );
  wynik.insert( QStringLiteral( "pokaz" ), pokaz );
  return wynik;
}

QVariantMap CAD::pokazWarstwy( QgsProject *projekt, const QStringList &ukryte ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }

  const QList<QgsVectorLayer *> rysunek = warstwyCad( p );
  if ( rysunek.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Projekt nie ma rysunku CAD (warstwy z pliku .dxf)" ) );
    return wynik;
  }

  const QString warunek = warunekUkrycia( ukryte );
  QStringList nazwy, bledy;
  for ( QgsVectorLayer *vl : rysunek )
  {
    // Warstwa rysunku bez pola "Layer" nie ma czego filtrowac - warunek
    // odrzucilby ja W CALOSCI, wiec zostawiamy ja w spokoju.
    if ( vl->fields().lookupField( QStringLiteral( "Layer" ) ) < 0 )
      continue;
    if ( vl->subsetString() == warunek )
    {
      nazwy << vl->name();
      continue;
    }
    if ( !vl->setSubsetString( warunek ) )
    {
      bledy << QStringLiteral( "%1: filtr odrzucony" ).arg( vl->name() );
      continue;
    }
    nazwy << vl->name();
    vl->triggerRepaint();
  }

  // Zapamietane osobno od samego warunku: warunek jest do czytania przez
  // bazę, a to - do czytania przez człowieka i przez `warstwyRysunku`.
  p->writeEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/ukryteWarstwy" ), ukryte );

  if ( !bledy.isEmpty() )
    wynik.insert( QStringLiteral( "blad" ), bledy.join( QStringLiteral( "; " ) ) );
  wynik.insert( QStringLiteral( "ukryte" ), ukryte.size() );
  wynik.insert( QStringLiteral( "warstwy" ), nazwy.isEmpty() ? QStringLiteral( "\u2014" ) : nazwy.join( QStringLiteral( ", " ) ) );
  return wynik;
}

QVariantMap CAD::bloki( QgsProject *projekt ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  const QString plik = plikRysunku( p );
  RysunekZBlokami rysunek( plik );
  if ( !rysunek.dobry() )
  {
    wynik.insert( QStringLiteral( "blad" ), rysunek.blad );
    qInfo() << "WFG CAD.bloki: " << rysunek.blad;
    return wynik;
  }

  const int idBlok = rysunek.pole( "BlockName" );
  const int idWarstwa = rysunek.pole( "Layer" );
  const int idAtrybutow = rysunek.pole( "BlockAttributes" );
  if ( idBlok < 0 )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Rysunek nie ma pola BlockName" ) );
    qInfo() << "WFG CAD.bloki: brak pola BlockName w " << plik;
    return wynik;
  }

  // Ile z kazdego bloku juz wczytano - zeby bylo widac, co zrobione.
  QMap<QString, int> juz;
  if ( QgsVectorLayer *cel = warstwaSymboli( p ) )
  {
    const int idNazwy = cel->fields().lookupField( QStringLiteral( "BLOK" ) );
    if ( idNazwy >= 0 )
    {
      QgsFeatureRequest zadanie;
      zadanie.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
      zadanie.setSubsetOfAttributes( QgsAttributeList() << idNazwy );
      QgsFeatureIterator it = cel->getFeatures( zadanie );
      QgsFeature f;
      while ( it.nextFeature( f ) )
        juz[f.attribute( idNazwy ).toString()] += 1;
    }
  }

  QMap<QString, int> ile;
  QMap<QString, QSet<QString>> warstwy;
  QMap<QString, QSet<QString>> znaczniki;
  long long encji = 0;
  OGR_L_ResetReading( rysunek.warstwa );
  while ( OGRFeatureH f = OGR_L_GetNextFeature( rysunek.warstwa ) )
  {
    encji++;
    const QString blok = QString::fromUtf8( OGR_F_GetFieldAsString( f, idBlok ) );
    if ( !blok.isEmpty() )
    {
      ile[blok] += 1;
      if ( idWarstwa >= 0 )
        warstwy[blok].insert( czytelna( QString::fromUtf8( OGR_F_GetFieldAsString( f, idWarstwa ) ) ) );
      const QMap<QString, QString> atrybuty = atrybutyWstawienia( f, idAtrybutow );
      for ( auto i = atrybuty.constBegin(); i != atrybuty.constEnd(); ++i )
        znaczniki[blok].insert( i.key() );
    }
    OGR_F_Destroy( f );
  }

  QVariantList lista;
  for ( auto i = ile.constBegin(); i != ile.constEnd(); ++i )
  {
    QVariantMap w;
    w.insert( QStringLiteral( "nazwa" ), i.key() );
    w.insert( QStringLiteral( "obiekty" ), i.value() );
    w.insert( QStringLiteral( "wczytane" ), juz.value( i.key(), 0 ) );
    QStringList nazwyWarstw( warstwy.value( i.key() ).values() );
    nazwyWarstw.sort();
    w.insert( QStringLiteral( "warstwy" ), nazwyWarstw.join( QStringLiteral( ", " ) ) );
    QStringList nazwyZnacznikow( znaczniki.value( i.key() ).values() );
    nazwyZnacznikow.sort();
    w.insert( QStringLiteral( "atrybuty" ), nazwyZnacznikow.join( QStringLiteral( ", " ) ) );
    lista << w;
  }

  // Najliczniejsze na gorze: w rysunku inwentaryzacyjnym to zwykle to,
  // po co sie w ogole idzie w teren.
  std::sort( lista.begin(), lista.end(), []( const QVariant &a, const QVariant &b ) {
    return a.toMap().value( QStringLiteral( "obiekty" ) ).toInt() > b.toMap().value( QStringLiteral( "obiekty" ) ).toInt();
  } );

  qInfo() << "WFG CAD.bloki: " << plik << " encji " << encji << ", rodzajow blokow " << lista.size();
  wynik.insert( QStringLiteral( "rysunek" ), QFileInfo( plik ).fileName() );
  wynik.insert( QStringLiteral( "bloki" ), lista );
  return wynik;
}

QVariantMap CAD::zBlokow( QgsProject *projekt, const QStringList &nazwy ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }
  if ( nazwy.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie wybrano żadnego bloku" ) );
    return wynik;
  }

  RysunekZBlokami rysunek( plikRysunku( p ) );
  if ( !rysunek.dobry() )
  {
    wynik.insert( QStringLiteral( "blad" ), rysunek.blad );
    return wynik;
  }
  const int idBlok = rysunek.pole( "BlockName" );
  const int idWarstwa = rysunek.pole( "Layer" );
  const int idKat = rysunek.pole( "BlockAngle" );
  const int idUchwyt = rysunek.pole( "EntityHandle" );
  const int idAtrybutow = rysunek.pole( "BlockAttributes" );
  if ( idBlok < 0 )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Rysunek nie ma pola BlockName" ) );
    return wynik;
  }

  QgsVectorLayer *cel = warstwaSymboli( p );
  if ( !cel )
  {
    // Pierwsze wczytanie: warstwa powstaje w tym samym dane.gpkg co robocze.
    // OPIS, DATA i ZDJECIE sa te same co tam - obiekt z rysunku ma byc
    // obiektem do UZUPELNIENIA w terenie, a nie osobnym gatunkiem.
    const QString baza = p->homePath() + QStringLiteral( "/dane.gpkg" );
    QVariantList pola;
    const char *opisy[][2] = {
      { "BLOK", "text" }, { "WARSTWA", "text" }, { "KAT", "real" }, { "UCHWYT", "text" }, { "OPIS", "text" }, { "DATA", "date" }, { "ZDJECIE", "text" }
    };
    for ( const auto &o : opisy )
    {
      QVariantMap pole;
      pole.insert( QStringLiteral( "name" ), QString::fromLatin1( o[0] ) );
      pole.insert( QStringLiteral( "type" ), QString::fromLatin1( o[1] ) );
      pola << pole;
    }
    cel = QfLayerUtils::createEmptyLayer( baza, QStringLiteral( "Symbole z rysunku" ),
                                          QStringLiteral( "Point" ), p->crs().authid(), pola );
    if ( !cel )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się założyć warstwy symboli" ) );
      return wynik;
    }
    QfLayerUtils::setAttachmentField( cel, QStringLiteral( "ZDJECIE" ) );
    QfLayerUtils::doprawCAD( cel, 0, 0, QStringLiteral( "OPIS" ), 0.5 );
    if ( !QfProjectUtils::addMapLayer( p, cel ) )
    {
      wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się dodać warstwy symboli do projektu" ) );
      return wynik;
    }
    p->writeEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/warstwaSymboli" ), cel->id() );
  }

  // UCHWYTY, ktore juz sa. Bez nich powtorzone wczytanie zrobiloby drugi
  // komplet obiektow na tych samych miejscach - a razem z nimi znikneloby
  // to, co ktos zdazyl dopisac w terenie.
  QSet<QString> mamy;
  const int idCelUchwyt = cel->fields().lookupField( QStringLiteral( "UCHWYT" ) );
  if ( idCelUchwyt >= 0 )
  {
    QgsFeatureRequest zadanie;
    zadanie.setFlags( Qgis::FeatureRequestFlag::NoGeometry );
    zadanie.setSubsetOfAttributes( QgsAttributeList() << idCelUchwyt );
    QgsFeatureIterator it = cel->getFeatures( zadanie );
    QgsFeature f;
    while ( it.nextFeature( f ) )
      mamy.insert( f.attribute( idCelUchwyt ).toString() );
  }

  const QSet<QString> chciane( nazwy.constBegin(), nazwy.constEnd() );
  // Obiekty skladamy DWUETAPOWO: najpierw czytamy z rysunku, potem dokladamy
  // brakujace kolumny, i dopiero wtedy budujemy QgsFeature - bo obiekt musi
  // znac komplet pol warstwy juz przy powstaniu.
  struct DoDodania
  {
    QgsPointXY punkt;
    QString blok, warstwa, uchwyt;
    double kat = 0;
    QMap<QString, QString> atrybuty;
  };
  QList<DoDodania> czekaja;
  QSet<QString> potrzebneKolumny;
  QgsFeatureList nowe;
  int pominiete = 0, bezGeometrii = 0;
  OGR_L_ResetReading( rysunek.warstwa );
  while ( OGRFeatureH f = OGR_L_GetNextFeature( rysunek.warstwa ) )
  {
    const QString blok = QString::fromUtf8( OGR_F_GetFieldAsString( f, idBlok ) );
    if ( blok.isEmpty() || !chciane.contains( blok ) )
    {
      OGR_F_Destroy( f );
      continue;
    }
    const QString uchwyt = idUchwyt >= 0 ? QString::fromUtf8( OGR_F_GetFieldAsString( f, idUchwyt ) ) : QString();
    if ( !uchwyt.isEmpty() && mamy.contains( uchwyt ) )
    {
      pominiete++;
      OGR_F_Destroy( f );
      continue;
    }
    OGRGeometryH geometria = OGR_F_GetGeometryRef( f );
    if ( !geometria || OGR_G_GetPointCount( geometria ) < 1 )
    {
      bezGeometrii++;
      OGR_F_Destroy( f );
      continue;
    }

    DoDodania d;
    // Punkt wstawienia bloku. Z rzutujemy na plask: warstwa robocza jest 2D,
    // a wysokosc z rysunku i tak nie jest pomiarem terenowym.
    d.punkt = QgsPointXY( OGR_G_GetX( geometria, 0 ), OGR_G_GetY( geometria, 0 ) );
    d.blok = blok;
    if ( idWarstwa >= 0 )
      d.warstwa = czytelna( QString::fromUtf8( OGR_F_GetFieldAsString( f, idWarstwa ) ) );
    if ( idKat >= 0 )
      d.kat = OGR_F_GetFieldAsDouble( f, idKat );
    d.uchwyt = uchwyt;
    d.atrybuty = atrybutyWstawienia( f, idAtrybutow );
    for ( auto i = d.atrybuty.constBegin(); i != d.atrybuty.constEnd(); ++i )
    {
      if ( cel->fields().lookupField( i.key() ) < 0 )
        potrzebneKolumny.insert( i.key() );
    }
    czekaja << d;
    OGR_F_Destroy( f );
  }

  // Brakujace kolumny - jednym zamachem, przed skladaniem obiektow.
  if ( !potrzebneKolumny.isEmpty() )
  {
    QStringList doDodania( potrzebneKolumny.values() );
    doDodania.sort();
    const int wolne = MAKS_KOLUMN_ATRYBUTOW - ( cel->fields().size() - 7 );
    if ( doDodania.size() > wolne )
    {
      qInfo() << "WFG CAD.zBlokow: kolumn atrybutow za duzo (" << doDodania.size() << "), biore pierwsze " << wolne;
      doDodania = doDodania.mid( 0, qMax( 0, wolne ) );
    }
    if ( !doDodania.isEmpty() )
    {
      const bool bylaEdycjaPol = cel->isEditable();
      if ( bylaEdycjaPol || cel->startEditing() )
      {
        for ( const QString &k : std::as_const( doDodania ) )
          cel->addAttribute( QgsField( k, QMetaType::QString ) );
        if ( !bylaEdycjaPol && !cel->commitChanges() )
        {
          qInfo() << "WFG CAD.zBlokow: nie udalo sie dolozyc kolumn: " << cel->commitErrors();
          cel->rollBack();
        }
        cel->updateFields();
      }
    }
  }

  for ( const DoDodania &d : std::as_const( czekaja ) )
  {
    QgsFeature nowa( cel->fields() );
    nowa.setGeometry( QgsGeometry::fromPointXY( d.punkt ) );
    nowa.setAttribute( QStringLiteral( "BLOK" ), d.blok );
    if ( !d.warstwa.isEmpty() )
      nowa.setAttribute( QStringLiteral( "WARSTWA" ), d.warstwa );
    if ( idKat >= 0 )
      nowa.setAttribute( QStringLiteral( "KAT" ), d.kat );
    if ( !d.uchwyt.isEmpty() )
      nowa.setAttribute( QStringLiteral( "UCHWYT" ), d.uchwyt );
    for ( auto i = d.atrybuty.constBegin(); i != d.atrybuty.constEnd(); ++i )
    {
      if ( cel->fields().lookupField( i.key() ) >= 0 )
        nowa.setAttribute( i.key(), i.value() );
    }
    nowe << nowa;
  }
  if ( bezGeometrii > 0 )
    qInfo() << "WFG CAD.zBlokow: bez geometrii pominietych " << bezGeometrii;

  if ( nowe.isEmpty() )
  {
    // Nic nowego, ale styl odswiezamy: to jedyna droga, zeby poprawic
    // symbole, gdyby za pierwszym razem sie nie zbudowaly.
    stylujSymbole( cel, symboleBlokow( plikRysunku( p ), p->homePath() + QStringLiteral( "/symbole" ), blokiWWarstwie( cel ) ) );
    wynik.insert( QStringLiteral( "dodane" ), 0 );
    wynik.insert( QStringLiteral( "pominiete" ), pominiete );
    wynik.insert( QStringLiteral( "warstwa" ), cel->name() );
    return wynik;
  }

  const bool bylaEdycja = cel->isEditable();
  if ( !bylaEdycja && !cel->startEditing() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Warstwy symboli nie da się edytować" ) );
    return wynik;
  }
  if ( !cel->addFeatures( nowe ) )
  {
    if ( !bylaEdycja )
      cel->rollBack();
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Dodawanie obiektów odrzucone" ) );
    return wynik;
  }
  if ( !bylaEdycja && !cel->commitChanges() )
  {
    const QString bledy = cel->commitErrors().join( QStringLiteral( "; " ) );
    cel->rollBack();
    wynik.insert( QStringLiteral( "blad" ), bledy );
    return wynik;
  }
  // Styl PO wczytaniu i za kazdym razem: blok, ktory doszedl teraz, musi
  // dostac swoj symbol, a te, ktore juz byly, nic nie traca.
  stylujSymbole( cel, symboleBlokow( plikRysunku( p ), p->homePath() + QStringLiteral( "/symbole" ), blokiWWarstwie( cel ) ) );
  cel->triggerRepaint();

  wynik.insert( QStringLiteral( "dodane" ), nowe.size() );
  wynik.insert( QStringLiteral( "pominiete" ), pominiete );
  wynik.insert( QStringLiteral( "warstwa" ), cel->name() );
  return wynik;
}

QVariantMap CAD::dociagnijOpisy( QgsProject *projekt, double promien, bool zapisz ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }
  QgsVectorLayer *cel = warstwaSymboli( p );
  if ( !cel )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Najpierw wczytaj bloki z rysunku" ) );
    return wynik;
  }
  if ( promien <= 0 )
    promien = 3.0;

  RysunekZBlokami rysunek( plikRysunku( p ) );
  if ( !rysunek.dobry() )
  {
    wynik.insert( QStringLiteral( "blad" ), rysunek.blad );
    return wynik;
  }
  const int idTekst = rysunek.pole( "Text" );
  const int idWarstwa = rysunek.pole( "Layer" );
  if ( idTekst < 0 || idWarstwa < 0 )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Rysunek nie ma pól Text i Layer" ) );
    return wynik;
  }

  // --- teksty rysunku, pogrupowane po warstwie -------------------------------
  struct Napis
  {
    QgsPointXY punkt;
    QString tresc;
    bool zajety = false;
  };
  QMap<QString, QList<Napis>> napisy;
  OGR_L_ResetReading( rysunek.warstwa );
  while ( OGRFeatureH f = OGR_L_GetNextFeature( rysunek.warstwa ) )
  {
    const QString tresc = QString::fromUtf8( OGR_F_GetFieldAsString( f, idTekst ) ).trimmed();
    OGRGeometryH g = OGR_F_GetGeometryRef( f );
    if ( !tresc.isEmpty() && g && OGR_G_GetPointCount( g ) >= 1 )
    {
      Napis n;
      n.punkt = QgsPointXY( OGR_G_GetX( g, 0 ), OGR_G_GetY( g, 0 ) );
      n.tresc = tresc;
      napisy[czytelna( QString::fromUtf8( OGR_F_GetFieldAsString( f, idWarstwa ) ) )] << n;
    }
    OGR_F_Destroy( f );
  }
  if ( napisy.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Rysunek nie ma tekstów" ) );
    return wynik;
  }

  // --- symbole z warstwy docelowej -------------------------------------------
  struct Symbol
  {
    QgsFeatureId id;
    QgsPointXY punkt;
    QString warstwa;
  };
  QMap<QString, QList<Symbol>> symbole;
  const int idPolaWarstwy = cel->fields().lookupField( QStringLiteral( "WARSTWA" ) );
  if ( idPolaWarstwy < 0 )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Warstwa symboli nie ma pola WARSTWA" ) );
    return wynik;
  }
  {
    QgsFeatureIterator it = cel->getFeatures();
    QgsFeature f;
    while ( it.nextFeature( f ) )
    {
      if ( !f.hasGeometry() )
        continue;
      Symbol s;
      s.id = f.id();
      s.punkt = f.geometry().asPoint();
      s.warstwa = f.attribute( idPolaWarstwy ).toString();
      if ( !s.warstwa.isEmpty() )
        symbole[s.warstwa] << s;
    }
  }

  /**
   * Warstwy tekstow nalezace do warstwy symbolu, w kolejnosci wazności:
   * najpierw rozbite atrybuty (-Atr1, -Atr2, …) po numerze, potem opis (_O).
   */
  auto warstwyWartosci = []( const QString &warstwaSymbolu, const QMap<QString, QList<Napis>> &napisy ) {
    QMap<int, QString> wgNumeru;
    QStringList opisy;
    const QString przedrostek = warstwaSymbolu + QStringLiteral( "-Atr" );
    for ( auto i = napisy.constBegin(); i != napisy.constEnd(); ++i )
    {
      if ( i.key() == warstwaSymbolu + QStringLiteral( "_O" ) )
      {
        opisy << i.key();
        continue;
      }
      if ( !i.key().startsWith( przedrostek ) )
        continue;
      bool ok = false;
      const int numer = i.key().mid( przedrostek.size() ).toInt( &ok );
      if ( ok )
        wgNumeru.insert( numer, i.key() );
    }
    QStringList kolejnosc( wgNumeru.values() );
    kolejnosc << opisy;
    return kolejnosc;
  };

  //! Nazwa kolumny z nazwy warstwy tekstow: "…-Atr2" -> ATR2, "…_O" -> OPIS_RYS.
  auto kolumnaZWarstwy = []( const QString &warstwaSymbolu, const QString &warstwaTekstu ) {
    if ( warstwaTekstu.endsWith( QLatin1String( "_O" ) ) )
      return QStringLiteral( "OPIS_RYS" );
    const QString ogon = warstwaTekstu.mid( warstwaSymbolu.size() + 4 );
    return QStringLiteral( "ATR" ) + ogon;
  };

  // --- dobieranie par ---------------------------------------------------------
  struct Para
  {
    double odleglosc;
    QgsFeatureId symbol;
    QString kolumna, wartosc;
    int indeksNapisu;
    QString warstwaTekstu;
  };
  QMap<QString, int> zliczenia;
  QSet<QString> potrzebne;
  QList<Para> przyjete;
  int bezWartosci = 0;

  for ( auto s = symbole.constBegin(); s != symbole.constEnd(); ++s )
  {
    const QStringList zrodla = warstwyWartosci( s.key(), napisy );
    if ( zrodla.isEmpty() )
    {
      bezWartosci += s.value().size();
      continue;
    }
    for ( const QString &zrodlo : zrodla )
    {
      QList<Napis> &lista = napisy[zrodlo];
      // Wszystkie pary w promieniu, od najkrotszej - i kazdy napis raz.
      QList<Para> kandydaci;
      for ( const Symbol &sym : s.value() )
      {
        for ( int i = 0; i < lista.size(); i++ )
        {
          const double d = std::hypot( sym.punkt.x() - lista[i].punkt.x(), sym.punkt.y() - lista[i].punkt.y() );
          if ( d > promien )
            continue;
          Para para;
          para.odleglosc = d;
          para.symbol = sym.id;
          para.kolumna = kolumnaZWarstwy( s.key(), zrodlo );
          para.wartosc = lista[i].tresc;
          para.indeksNapisu = i;
          para.warstwaTekstu = zrodlo;
          kandydaci << para;
        }
      }
      std::sort( kandydaci.begin(), kandydaci.end(), []( const Para &a, const Para &b ) {
        return a.odleglosc < b.odleglosc;
      } );
      QSet<QgsFeatureId> zajeteSymbole;
      for ( const Para &para : std::as_const( kandydaci ) )
      {
        if ( lista[para.indeksNapisu].zajety || zajeteSymbole.contains( para.symbol ) )
          continue;
        lista[para.indeksNapisu].zajety = true;
        zajeteSymbole.insert( para.symbol );
        przyjete << para;
        zliczenia[para.kolumna] += 1;
        potrzebne.insert( para.kolumna );
      }
    }
  }

  QStringList opisSzczegolow;
  for ( auto i = zliczenia.constBegin(); i != zliczenia.constEnd(); ++i )
    opisSzczegolow << QStringLiteral( "%1: %2" ).arg( i.key() ).arg( i.value() );

  wynik.insert( QStringLiteral( "dopasowane" ), przyjete.size() );
  wynik.insert( QStringLiteral( "bezWartosci" ), bezWartosci );
  wynik.insert( QStringLiteral( "kolumny" ), opisSzczegolow.join( QStringLiteral( ", " ) ) );
  qInfo() << "WFG CAD.dociagnijOpisy: promien" << promien << "dopasowanych" << przyjete.size()
          << "kolumny" << opisSzczegolow;
  if ( !zapisz || przyjete.isEmpty() )
    return wynik;

  // --- kolumny ----------------------------------------------------------------
  QStringList doDodania;
  for ( const QString &k : std::as_const( potrzebne ) )
  {
    if ( cel->fields().lookupField( k ) < 0 )
      doDodania << k;
  }
  doDodania.sort();
  if ( !doDodania.isEmpty() )
  {
    const int wolne = MAKS_KOLUMN_ATRYBUTOW - ( cel->fields().size() - 7 );
    if ( doDodania.size() > wolne )
      doDodania = doDodania.mid( 0, qMax( 0, wolne ) );
    if ( !doDodania.isEmpty() && cel->startEditing() )
    {
      for ( const QString &k : std::as_const( doDodania ) )
        cel->addAttribute( QgsField( k, QMetaType::QString ) );
      if ( !cel->commitChanges() )
      {
        qInfo() << "WFG CAD.dociagnijOpisy: kolumny odrzucone:" << cel->commitErrors();
        cel->rollBack();
      }
      cel->updateFields();
    }
  }

  // --- zapis ------------------------------------------------------------------
  const int idOpis = cel->fields().lookupField( QStringLiteral( "OPIS" ) );
  if ( !cel->startEditing() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Warstwy symboli nie da się edytować" ) );
    return wynik;
  }
  int wpisane = 0;
  QSet<QgsFeatureId> opisUstawiony;
  for ( const Para &para : std::as_const( przyjete ) )
  {
    const int idKolumny = cel->fields().lookupField( para.kolumna );
    if ( idKolumny < 0 )
      continue;
    QgsFeature f = cel->getFeature( para.symbol );
    if ( !f.isValid() )
      continue;
    // TYLKO puste komorki - powtorzenie nie nadpisuje tego, co ktos wpisal w terenie.
    if ( f.attribute( idKolumny ).toString().trimmed().isEmpty() )
    {
      cel->changeAttributeValue( para.symbol, idKolumny, para.wartosc );
      wpisane++;
    }
    // Pierwsza wartosc idzie takze do OPIS: to ON jest etykieta na mapie
    // i to on wychodzi w eksporcie DXF.
    if ( idOpis >= 0 && !opisUstawiony.contains( para.symbol )
         && f.attribute( idOpis ).toString().trimmed().isEmpty() )
    {
      cel->changeAttributeValue( para.symbol, idOpis, para.wartosc );
      opisUstawiony.insert( para.symbol );
    }
  }
  if ( !cel->commitChanges() )
  {
    const QString bledy = cel->commitErrors().join( QStringLiteral( "; " ) );
    cel->rollBack();
    wynik.insert( QStringLiteral( "blad" ), bledy );
    return wynik;
  }
  cel->triggerRepaint();
  wynik.insert( QStringLiteral( "wpisane" ), wpisane );
  return wynik;
}

QVariantMap CAD::eksportuj( QgsProject *projekt ) const
{
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
  {
    QVariantMap blad;
    blad.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return blad;
  }

  // Ten sam czasownik, ktory wola lewa szuflada - modul nie ma wlasnego
  // eksportu, tylko drugie wejscie do tego samego. `false` = bez rysunku
  // zrodlowego; projektant juz go ma.
  NarzedziaProjektu narzedzia;
  QVariantMap wynik = narzedzia.eksportujDxf( p, QString(), false );
  if ( wynik.contains( QStringLiteral( "blad" ) ) )
    return wynik;

  // Karta modulu wysyla LISTE plikow (akcja "wyslij"), a eksport zwraca
  // pojedyncza sciezke - bez tego "Wyslij" dostaloby napis zamiast listy.
  const QString plik = wynik.value( QStringLiteral( "plik" ) ).toString();
  if ( !plik.isEmpty() )
    wynik.insert( QStringLiteral( "pliki" ), QStringList() << plik );
  qInfo() << "WFG CAD.eksportuj:" << plik << "obiektow" << wynik.value( QStringLiteral( "obiekty" ) );
  return wynik;
}

namespace
{
  //! Liczba z tekstu rysunku: "84,8" i "84.8" to ta sama rzedna.
  bool wysokoscZTekstu( const QString &tekst, double *wartosc )
  {
    bool ok = false;
    const double v = QString( tekst ).trimmed().replace( QLatin1Char( ',' ), QLatin1Char( '.' ) ).toDouble( &ok );
    if ( !ok )
      return false;
    // Rzedna w Polsce miesci sie w tym zakresie; poza nim to nie wysokosc,
    // tylko numer, srednica albo cos jeszcze innego.
    if ( v < -20.0 || v > 2600.0 )
      return false;
    if ( wartosc )
      *wartosc = v;
    return true;
  }
} // namespace

QVariantList CAD::polaZWysokoscia( QgsProject *projekt ) const
{
  QVariantList lista;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  QgsVectorLayer *cel = warstwaSymboli( p );
  if ( !cel )
    return lista;

  QMap<QString, int> ile;
  QgsFeatureIterator it = cel->getFeatures();
  QgsFeature f;
  while ( it.nextFeature( f ) )
  {
    const QgsFields pola = cel->fields();
    for ( int i = 0; i < pola.size(); i++ )
    {
      const QString nazwa = pola.at( i ).name();
      // Tylko kolumny z rysunku - BLOK, WARSTWA i reszta nasza to nie wysokosci.
      if ( !nazwa.startsWith( QLatin1String( "ATR" ) ) && nazwa != QLatin1String( "OPIS" ) && nazwa != QLatin1String( "OPIS_RYS" ) )
        continue;
      if ( wysokoscZTekstu( f.attribute( i ).toString(), nullptr ) )
        ile[nazwa] += 1;
    }
  }
  for ( auto i = ile.constBegin(); i != ile.constEnd(); ++i )
  {
    QVariantMap w;
    w.insert( QStringLiteral( "pole" ), i.key() );
    w.insert( QStringLiteral( "ile" ), i.value() );
    lista << w;
  }
  std::sort( lista.begin(), lista.end(), []( const QVariant &a, const QVariant &b ) {
    return a.toMap().value( QStringLiteral( "ile" ) ).toInt() > b.toMap().value( QStringLiteral( "ile" ) ).toInt();
  } );
  return lista;
}

QVariantMap CAD::warstwiceZRzednych( QgsProject *projekt, const QString &pole, double odstep, const QString &metoda ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }
  QgsVectorLayer *cel = warstwaSymboli( p );
  if ( !cel )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Najpierw wczytaj bloki z rysunku" ) );
    return wynik;
  }
  const int idPola = cel->fields().lookupField( pole );
  if ( idPola < 0 )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Warstwa symboli nie ma pola %1" ).arg( pole ) );
    return wynik;
  }

  // --- punkty z liczbowa wysokoscia ------------------------------------------
  // Wysokosc przychodzi z rysunku jako TEKST, a GDALGrid potrzebuje liczby -
  // stad pomocnicza warstwa, a nie liczenie wprost z warstwy symboli.
  const QString katalog = p->homePath() + QStringLiteral( "/warstwice" );
  QDir().mkpath( katalog );
  const QString plikPunktow = katalog + QStringLiteral( "/rzedne.gpkg" );
  VSIUnlink( plikPunktow.toUtf8().constData() );

  QVariantList polaPunktow;
  {
    QVariantMap z;
    z.insert( QStringLiteral( "name" ), QStringLiteral( "Z" ) );
    z.insert( QStringLiteral( "type" ), QStringLiteral( "real" ) );
    polaPunktow << z;
  }
  QgsVectorLayer *punkty = QfLayerUtils::createEmptyLayer( plikPunktow, QStringLiteral( "rzedne" ),
                                                           QStringLiteral( "Point" ), p->crs().authid(), polaPunktow );
  if ( !punkty )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się przygotować punktów wysokościowych" ) );
    return wynik;
  }

  QgsFeatureList doDodania;
  {
    QgsFeatureIterator it = cel->getFeatures();
    QgsFeature f;
    while ( it.nextFeature( f ) )
    {
      double wysokosc = 0;
      if ( !f.hasGeometry() || !wysokoscZTekstu( f.attribute( idPola ).toString(), &wysokosc ) )
        continue;
      QgsFeature nowy( punkty->fields() );
      nowy.setGeometry( f.geometry() );
      nowy.setAttribute( QStringLiteral( "Z" ), wysokosc );
      doDodania << nowy;
    }
  }
  if ( doDodania.size() < 3 )
  {
    delete punkty;
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Za mało rzędnych w polu %1 (znaleziono %2)" ).arg( pole ).arg( doDodania.size() ) );
    return wynik;
  }
  if ( !punkty->startEditing() || !punkty->addFeatures( doDodania ) || !punkty->commitChanges() )
  {
    punkty->rollBack();
    delete punkty;
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się zapisać punktów wysokościowych" ) );
    return wynik;
  }
  const int ilePunktow = doDodania.size();
  delete punkty;

  // --- powierzchnia i warstwice ----------------------------------------------
  const QVariantMap p1 = Warstwice::powierzchnia( plikPunktow, QStringLiteral( "rzedne" ), QStringLiteral( "Z" ),
                                                  katalog + QStringLiteral( "/powierzchnia.tif" ), metoda, 0 );
  if ( p1.contains( QStringLiteral( "blad" ) ) )
    return p1;

  const QString plikWarstwic = katalog + QStringLiteral( "/warstwice.gpkg" );
  QVariantMap p2 = Warstwice::zRastra( p1.value( QStringLiteral( "plik" ) ).toString(), plikWarstwic, odstep );
  if ( p2.contains( QStringLiteral( "blad" ) ) )
    return p2;

  // --- warstwa w projekcie ----------------------------------------------------
  QgsVectorLayer *warstwa = new QgsVectorLayer( plikWarstwic + QStringLiteral( "|layername=warstwice" ),
                                                QObject::tr( "Warstwice z rzędnych" ), QStringLiteral( "ogr" ) );
  if ( !warstwa->isValid() )
  {
    delete warstwa;
    p2.insert( QStringLiteral( "blad" ), QStringLiteral( "Warstwice policzone, ale warstwa się nie wczytała" ) );
    return p2;
  }
  if ( !QfProjectUtils::addMapLayer( p, warstwa ) )
  {
    p2.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie udało się dodać warstwic do projektu" ) );
    return p2;
  }
  p->writeEntry( QStringLiteral( "wfg_cad" ), QStringLiteral( "/warstwiceRzednych" ), warstwa->id() );

  p2.insert( QStringLiteral( "punkty" ), ilePunktow );
  p2.insert( QStringLiteral( "warstwa" ), warstwa->name() );
  qInfo() << "WFG CAD.warstwiceZRzednych: punktow" << ilePunktow << "linii" << p2.value( QStringLiteral( "linie" ) )
          << "metoda" << metoda << "odstep" << odstep;
  return p2;
}
