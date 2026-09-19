/***************************************************************************
  inwentaryzacjadrzew.cpp - WorkField

  Modul dziedzinowy "Inwentaryzacja drzew" - silnik (C++). Wydzielony
  19.09.2026 z NarzedziaProjektu (claude/MODULY_dziedzinowe.md, krok 2).

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "inwentaryzacjadrzew.h"

#include "dxfinwentaryzacja.h"
#include "kodowaniedxf.h"

#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>

#include <qgsgeometry.h>
#include <qgslayertree.h>
#include <qgslayertreelayer.h>
#include <qgsproject.h>
#include <qgsvectorlayer.h>

InwentaryzacjaDrzew::InwentaryzacjaDrzew( QObject *parent )
  : QObject( parent )
{
}

QVariantMap InwentaryzacjaDrzew::opis() const
{
  // Opis modulu = przyszly modul.json z paczki. Zakladka "Moduly" buduje
  // z niego karte i przyciski; nic w QML nie jest wpisane pod drzewa.
  static const QByteArray json = QByteArrayLiteral( R"WFG({
  "id": "inwentaryzacja_drzew",
  "nazwa": "Inwentaryzacja drzew",
  "wersja": "1.0",
  "silnik": "InwentaryzacjaDrzew",
  "opis": "Korony, strefa ochrony drzewa (SOD) i pnie liczone na żywo z obwodów; eksport do CAD (DXF z multiodnośnikami) i tabela inwentaryzacyjna ODS.",
  "wymaga_silnika": ["InwentaryzacjaDrzew.rozpoznaj", "InwentaryzacjaDrzew.styluj", "InwentaryzacjaDrzew.eksportuj"],
  "wymaga_modulow": [],
  "rozpoznanie": "InwentaryzacjaDrzew.rozpoznaj",
  "role": [
    { "klucz": "poleObwodow", "nazwa": "obwody pni" },
    { "klucz": "poleKorony", "nazwa": "korona" },
    { "klucz": "poleEtykiety", "nazwa": "etykieta" }
  ],
  "akcje": [
    {
      "etykieta": "Styl: korony, SOD, pnie",
      "czasownik": "InwentaryzacjaDrzew.styluj",
      "zapisz_projekt": true,
      "komunikat": "Styl drzew: korony, SOD i pnie — {warstwa}"
    },
    {
      "etykieta": "Eksport DXF + ODS",
      "czasownik": "InwentaryzacjaDrzew.eksportuj",
      "wyslij": "pliki",
      "komunikat": "Inwentaryzacja: {drzewa} drzew, plików: {pliki} (DXF + ODS)"
    }
  ]
})WFG" );
  static const QVariantMap opis = QJsonDocument::fromJson( json ).object().toVariantMap();
  return opis;
}

// ---------------------------------------------------------------------------
// Eksport inwentaryzacji drzew do DXF - WorkField 19.09.2026
// Rdzen (okregi, srednice, rozmieszczenie etykiet, zapis DXF) jest
// w moduly/dxfinwentaryzacja.cpp - bez QGIS, sprawdzany poza aplikacja.
// Tutaj tylko: ktora warstwa, ktore pola, jaki rysunek, dokad zapisac.
// ---------------------------------------------------------------------------

#include <qgscoordinatetransform.h>
#include <qgsexception.h>
#include <qgsproviderregistry.h>

#include <functional>

namespace
{
  QString bezOgonkow( QString s )
  {
    s = s.toLower();
    const QString z = QStringLiteral( "ąćęłńóśźż" );
    const QString na = QStringLiteral( "acelnoszz" );
    for ( int i = 0; i < z.size(); ++i )
      s.replace( z.at( i ), na.at( i ) );
    return s;
  }

  //! Pole wskazane w ustawieniach projektu, a bez niego - pierwsze pasujace.
  int poleWgNazwy( const QgsFields &pola, const QString &wskazane, const std::function<bool( const QString & )> &pasuje )
  {
    if ( !wskazane.isEmpty() )
      return pola.lookupField( wskazane );
    for ( int i = 0; i < pola.count(); ++i )
    {
      if ( pasuje( bezOgonkow( pola.at( i ).name() ) ) )
        return i;
    }
    return -1;
  }

  QString nazwaPliku( QString s )
  {
    static const QRegularExpression zle( QStringLiteral( "[\\\\/:*?\"<>|\\s]+" ) );
    s.replace( zle, QStringLiteral( "_" ) );
    return s;
  }

  // Warstwa drzew i jej pola - wspolne dla eksportu i stylu, zeby oba
  // widzialy te sama warstwe. Rozpoznanie po ROLI pola; wfg_inw/* nadpisuje.
  struct WarstwaDrzew
  {
      QgsVectorLayer *warstwa = nullptr;
      int obwody = -1;
      int korona = -1;
      int etykieta = -1;
  };

  WarstwaDrzew znajdzWarstweDrzew( QgsProject *p )
  {
    const QString zakres = QStringLiteral( "wfg_inw" );
    const QString wWarstwa = p->readEntry( zakres, QStringLiteral( "/warstwa" ) );
    const QString wObwody = p->readEntry( zakres, QStringLiteral( "/poleObwodow" ) );
    const QString wKorona = p->readEntry( zakres, QStringLiteral( "/poleKorony" ) );
    const QString wEtykieta = p->readEntry( zakres, QStringLiteral( "/poleEtykiety" ) );
    WarstwaDrzew w;
    auto dopasuj = [&]( QgsVectorLayer *vl ) -> bool {
      if ( !vl || !vl->isValid() || vl->geometryType() != Qgis::GeometryType::Point )
        return false;
      const QgsFields f = vl->fields();
      int o = poleWgNazwy( f, wObwody, []( const QString &n ) { return n.contains( QLatin1String( "obwod" ) ) && n.contains( QLatin1String( "130" ) ); } );
      if ( o < 0 && wObwody.isEmpty() )
        o = poleWgNazwy( f, QString(), []( const QString &n ) { return n.contains( QLatin1String( "obwod" ) ); } );
      const int k = poleWgNazwy( f, wKorona, []( const QString &n ) { return n.contains( QLatin1String( "koron" ) ); } );
      if ( o < 0 || k < 0 )
        return false;
      w.warstwa = vl;
      w.obwody = o;
      w.korona = k;
      w.etykieta = poleWgNazwy( f, wEtykieta, []( const QString &n ) {
        return n.startsWith( QLatin1String( "nr inw" ) ) || n.startsWith( QLatin1String( "nr_inw" ) ) || n == QLatin1String( "nr" );
      } );
      return true;
    };
    if ( !wWarstwa.isEmpty() )
    {
      const QList<QgsMapLayer *> poNazwie = p->mapLayersByName( wWarstwa );
      for ( QgsMapLayer *ml : poNazwie )
      {
        if ( dopasuj( qobject_cast<QgsVectorLayer *>( ml ) ) )
          return w;
      }
    }
    // Wsrod pasujacych: najpierw prawdziwe dane z obiektami, potem cokolwiek.
    // Projekt z QGIS potrafi miec warstwe tymczasowa (memory, np. "Warstwa ze
    // zlaczeniem") z tymi samymi polami - po wczytaniu jest pusta.
    const QList<QgsLayerTreeLayer *> wezly = p->layerTreeRoot()->findLayers();
    WarstwaDrzew zapas;
    for ( QgsLayerTreeLayer *wezel : wezly )
    {
      QgsVectorLayer *vl = qobject_cast<QgsVectorLayer *>( wezel->layer() );
      if ( !dopasuj( vl ) )
        continue;
      if ( vl->providerType() != QLatin1String( "memory" ) && vl->featureCount() > 0 )
        return w;
      if ( !zapas.warstwa || ( zapas.warstwa->featureCount() <= 0 && vl->featureCount() > 0 ) )
        zapas = w;
    }
    return zapas;
  }
} // namespace

QVariantMap InwentaryzacjaDrzew::rozpoznaj( QgsProject *projekt ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || !p->layerTreeRoot() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }
  const WarstwaDrzew wd = znajdzWarstweDrzew( p );
  if ( !wd.warstwa )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie znalazłem warstwy drzew (punkty z polami obwodów i korony)" ) );
    return wynik;
  }
  const QgsFields pola = wd.warstwa->fields();
  auto nazwa = [&pola]( int i ) { return i >= 0 ? pola.at( i ).name() : QString(); };
  wynik.insert( QStringLiteral( "warstwa" ), wd.warstwa->name() );
  wynik.insert( QStringLiteral( "warstwaId" ), wd.warstwa->id() );
  wynik.insert( QStringLiteral( "obiekty" ), wd.warstwa->featureCount() );
  wynik.insert( QStringLiteral( "poleObwodow" ), nazwa( wd.obwody ) );
  wynik.insert( QStringLiteral( "poleKorony" ), nazwa( wd.korona ) );
  wynik.insert( QStringLiteral( "poleEtykiety" ), nazwa( wd.etykieta ) );
  return wynik;
}

QVariantMap InwentaryzacjaDrzew::eksportuj( QgsProject *projekt ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || !p->layerTreeRoot() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }
  const QString zakres = QStringLiteral( "wfg_inw" );

  // --- warstwa drzew i pola -------------------------------------------------
  // Rozpoznanie po ROLI pola, nie po dokladnej nazwie: "Obwody pni [cm] na
  // wys. 130cm..." i "Szerokosc korony [m]" z szablonu Mapit, ale tez
  // krotsze nazwy z innych szablonow. Ustawienia projektu wfg_inw/* maja
  // pierwszenstwo, gdy ktos chce wskazac inaczej.
  const WarstwaDrzew wd = znajdzWarstweDrzew( p );
  QgsVectorLayer *drzewa = wd.warstwa;
  const int iObw = wd.obwody, iKor = wd.korona, iEty = wd.etykieta;
  if ( !drzewa )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie znalazłem warstwy drzew — potrzebna warstwa punktowa z polem obwodów i szerokości korony" ) );
    return wynik;
  }

  // --- drzewa we wspolrzednych projektu ---------------------------------------
  // DXF w stopniach jest bezuzyteczny, a zle wczytany projekt potrafi nie
  // miec ukladu - wtedy transformacja cicho nic nie robi.
  if ( !p->crs().isValid() || p->crs().isGeographic() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Projekt nie ma układu w metrach (%1) — ustaw np. EPSG:2178" ).arg( p->crs().isValid() ? p->crs().authid() : QStringLiteral( "brak" ) ) );
    return wynik;
  }
  const QgsCoordinateTransform ct( drzewa->crs(), p->crs(), p->transformContext() );
  QVector<DxfInwentaryzacja::Drzewo> lista;
  int zSrednicy = 0, zPowierzchni = 0, bezKorony = 0;
  // --- tabela ODS: pozostale pola po roli (brakujace zostaja puste) --------
  const QgsFields polaDrzew = drzewa->fields();
  auto poRoli = [&polaDrzew]( const std::function<bool( const QString & )> &pasuje ) { return poleWgNazwy( polaDrzew, QString(), pasuje ); };
  const int iGrupa = poRoli( []( const QString &n ) { return n == QLatin1String( "grupa" ); } );
  const int iKat = poRoli( []( const QString &n ) { return n.startsWith( QLatin1String( "kategori" ) ); } );
  const int iTech = poRoli( []( const QString &n ) { return n.contains( QLatin1String( "techniczn" ) ); } );
  const int iPol = poRoli( []( const QString &n ) { return n.contains( QLatin1String( "nazwa polsk" ) ); } );
  const int iObw5 = poRoli( []( const QString &n ) { return n.contains( QLatin1String( "obwod" ) ) && n.contains( QLatin1String( "5cm" ) ) && !n.contains( QLatin1String( "130" ) ); } );
  const int iWys = poRoli( []( const QString &n ) { return n.startsWith( QLatin1String( "wysokosc" ) ); } );
  const int iStan = poRoli( []( const QString &n ) { return n.startsWith( QLatin1String( "stan" ) ); } );
  const int iUwagi = poRoli( []( const QString &n ) { return n.startsWith( QLatin1String( "uwag" ) ); } );
  // Dzialki: warstwa poligonowa z numerem dzialki (np. "Zakres" z ULDK) -
  // obreb, nr i TERYT dzialki, w ktorej stoi drzewo.
  QgsVectorLayer *dzialki = nullptr;
  int iObreb = -1, iNrDz = -1, iTeryt = -1;
  {
    const QList<QgsLayerTreeLayer *> wezly = p->layerTreeRoot()->findLayers();
    for ( QgsLayerTreeLayer *wz : wezly )
    {
      QgsVectorLayer *vl = qobject_cast<QgsVectorLayer *>( wz->layer() );
      if ( !vl || !vl->isValid() || vl->geometryType() != Qgis::GeometryType::Polygon )
        continue;
      const int nr = poleWgNazwy( vl->fields(), QString(), []( const QString &n ) { return n == QLatin1String( "nr_dzialki" ) || n == QLatin1String( "nr dzialki" ) || n == QLatin1String( "numer_dzialki" ); } );
      if ( nr < 0 )
        continue;
      const int ter = poleWgNazwy( vl->fields(), QString(), []( const QString &n ) { return n == QLatin1String( "teryt" ) || n.startsWith( QLatin1String( "id_dzialki" ) ); } );
      if ( dzialki && ( iTeryt >= 0 || ter < 0 ) )
        continue;
      dzialki = vl;
      iNrDz = nr;
      iTeryt = ter;
      iObreb = poleWgNazwy( vl->fields(), QString(), []( const QString &n ) { return n.startsWith( QLatin1String( "obreb" ) ); } );
    }
  }
  const QgsCoordinateTransform doDzialek = dzialki ? QgsCoordinateTransform( drzewa->crs(), dzialki->crs(), p->transformContext() ) : QgsCoordinateTransform();
  QVector<DxfInwentaryzacja::Wiersz> wiersze;

  QgsFeature f;
  QgsFeatureIterator it = drzewa->getFeatures();
  while ( it.nextFeature( f ) )
  {
    if ( !f.hasGeometry() || f.geometry().isEmpty() )
      continue;
    QgsPointXY pt = f.geometry().centroid().asPoint();
    try
    {
      if ( ct.isValid() )
        pt = ct.transform( pt );
    }
    catch ( const QgsCsException & )
    {
      continue;
    }
    DxfInwentaryzacja::Drzewo d;
    d.x = pt.x();
    d.y = pt.y();
    QString uwaga;
    d.rPnia = DxfInwentaryzacja::srednicaZObwodow( f.attribute( iObw ).toString(), &uwaga ) / 2.0;
    if ( uwaga.startsWith( QLatin1String( "srednica" ) ) )
      ++zSrednicy;
    else if ( uwaga.startsWith( QLatin1String( "powierzchnia" ) ) )
      ++zPowierzchni;
    d.rKorony = DxfInwentaryzacja::liczba( f.attribute( iKor ).toString() ) / 2.0;
    if ( d.rKorony <= 0 )
      ++bezKorony;
    const QString nr = iEty >= 0 ? f.attribute( iEty ).toString().trimmed() : QString();
    d.etykieta = nr.isEmpty() || f.attribute( iEty ).isNull() ? QString::number( f.id() ) : nr;
    lista << d;
    {
      auto t = [&f]( int i ) { return i >= 0 && !f.attribute( i ).isNull() ? f.attribute( i ).toString() : QString(); };
      DxfInwentaryzacja::Wiersz w;
      w.fid = f.id();
      w.grupa = t( iGrupa );
      w.kategoria = t( iKat );
      w.nazwaTechniczna = t( iTech );
      w.nazwaPolska = t( iPol );
      w.obwody5 = t( iObw5 );
      w.obwody130 = t( iObw );
      w.korona = t( iKor );
      w.wysokosc = t( iWys );
      w.stan = t( iStan );
      w.uwagi = t( iUwagi );
      w.wkt = f.geometry().asWkt( 9 );
      if ( dzialki )
      {
        try
        {
          QgsPointXY pd = f.geometry().centroid().asPoint();
          if ( doDzialek.isValid() )
            pd = doDzialek.transform( pd );
          QgsFeatureRequest zapytanie;
          zapytanie.setFilterRect( QgsRectangle( pd.x() - 1e-6, pd.y() - 1e-6, pd.x() + 1e-6, pd.y() + 1e-6 ) );
          QgsFeature dz;
          QgsFeatureIterator di = dzialki->getFeatures( zapytanie );
          while ( di.nextFeature( dz ) )
          {
            if ( dz.geometry().contains( &pd ) )
            {
              auto td = [&dz]( int i ) { return i >= 0 && !dz.attribute( i ).isNull() ? dz.attribute( i ).toString() : QString(); };
              w.obreb = td( iObreb );
              w.dzialka = td( iNrDz );
              w.teryt = td( iTeryt );
              break;
            }
          }
        }
        catch ( const QgsCsException & )
        {
        }
      }
      wiersze << w;
    }
  }
  if ( lista.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Warstwa %1 nie ma drzew z geometrią" ).arg( drzewa->name() ) );
    return wynik;
  }

  DxfInwentaryzacja::Ustawienia ust;
  ust.wysokoscTekstu = p->readDoubleEntry( zakres, QStringLiteral( "/wysokoscTekstu" ), ust.wysokoscTekstu );
  ust.szerokoscZnaku = p->readDoubleEntry( zakres, QStringLiteral( "/szerokoscZnaku" ), ust.szerokoscZnaku );
  ust.odsylaczMin = p->readDoubleEntry( zakres, QStringLiteral( "/odsylaczMin" ), ust.odsylaczMin );
  ust.odsylaczMax = p->readDoubleEntry( zakres, QStringLiteral( "/odsylaczMax" ), ust.odsylaczMax );
  ust.margines = p->readDoubleEntry( zakres, QStringLiteral( "/margines" ), ust.margines );

  // --- rysunek zrodlowy: warstwa z pliku .dxf, najpierw z grupy "Rysunek CAD" ----
  QString rysunek;
  {
    const QList<QgsLayerTreeLayer *> wezly = p->layerTreeRoot()->findLayers();
    for ( int przebieg = 0; przebieg < 2 && rysunek.isEmpty(); ++przebieg )
    {
      for ( QgsLayerTreeLayer *w : wezly )
      {
        QgsVectorLayer *vl = qobject_cast<QgsVectorLayer *>( w->layer() );
        if ( !vl || vl->providerType() != QLatin1String( "ogr" ) )
          continue;
        const QString sciezka = QgsProviderRegistry::instance()->decodeUri( QStringLiteral( "ogr" ), vl->source() ).value( QStringLiteral( "path" ) ).toString();
        if ( !sciezka.endsWith( QLatin1String( ".dxf" ), Qt::CaseInsensitive ) || !QFileInfo::exists( sciezka ) )
          continue;
        bool wGrupie = vl->name().startsWith( QLatin1String( "Rysunek CAD" ) );
        for ( QgsLayerTreeNode *r = w->parent(); r && !wGrupie; r = r->parent() )
          wGrupie = QgsLayerTree::isGroup( r ) && QgsLayerTree::toGroup( r )->name() == QLatin1String( "Rysunek CAD" );
        if ( przebieg == 0 && !wGrupie )
          continue;
        rysunek = sciezka;
        break;
      }
    }
  }

  // --- zapis: oba pliki w jednym katalogu, zeby "Wyslij" wzielo je razem --------
  QString nazwa = p->title().trimmed();
  if ( nazwa.isEmpty() )
    nazwa = QFileInfo( p->homePath() ).fileName();
  nazwa = nazwaPliku( nazwa.isEmpty() ? QStringLiteral( "projekt" ) : nazwa );
  const QString znacznik = QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmm" ) );
  const QString katalog = QStringLiteral( "%1/export/inwentaryzacja_%2" ).arg( p->homePath(), znacznik );
  QDir().mkpath( katalog );

  QStringList pliki, uwagi;
  uwagi << QStringLiteral( "Warstwa: %1; pola: %2 / %3 / %4" )
             .arg( drzewa->name(), drzewa->fields().at( iObw ).name(), drzewa->fields().at( iKor ).name(),
                   iEty >= 0 ? drzewa->fields().at( iEty ).name() : QStringLiteral( "fid" ) );
  if ( zSrednicy || zPowierzchni || bezKorony )
    uwagi << QStringLiteral( "Średnica zamiast obwodu (sr/s): %1; powierzchnia (m2) bez pnia: %2; bez korony: %3" ).arg( zSrednicy ).arg( zPowierzchni ).arg( bezKorony );

  auto zapisz = [&]( const QString &sciezka, const QByteArray &bazowy ) -> bool {
    const DxfInwentaryzacja::Wynik w = DxfInwentaryzacja::dopisz( bazowy, lista, ust, bazowy.contains( "ANSI_1250" ) ? &KodowanieDxf::doCp1250 : nullptr );
    uwagi << w.uwagi;
    if ( w.dxf.isEmpty() )
      return false;
    QFile plik( sciezka );
    if ( !plik.open( QIODevice::WriteOnly | QIODevice::Truncate ) )
    {
      uwagi << QStringLiteral( "Nie mogę zapisać %1" ).arg( sciezka );
      return false;
    }
    plik.write( w.dxf );
    plik.close();
    pliki << sciezka;
    return true;
  };

  zapisz( QStringLiteral( "%1/%2_inwentaryzacja.dxf" ).arg( katalog, nazwa ), QByteArray() );
  if ( !rysunek.isEmpty() )
  {
    QFile r( rysunek );
    if ( r.open( QIODevice::ReadOnly ) )
    {
      const QByteArray bajty = r.readAll();
      r.close();
      zapisz( QStringLiteral( "%1/%2_z_inwentaryzacja.dxf" ).arg( katalog, nazwaPliku( QFileInfo( rysunek ).completeBaseName() ) ), bajty );
    }
  }
  else
  {
    uwagi << QStringLiteral( "Projekt nie ma rysunku DXF - tylko osobny plik" );
  }

  // --- tabela inwentaryzacyjna ODS (do dalszego uzupelnienia) -------------------
  {
    const QString ods = QStringLiteral( "%1/%2_tabela_inwentaryzacyjna.ods" ).arg( katalog, nazwa );
    const QString blad = DxfInwentaryzacja::zapiszOds( ods, wiersze );
    if ( blad.isEmpty() )
      pliki << ods;
    else
      uwagi << QStringLiteral( "ODS: %1" ).arg( blad );
    if ( !dzialki )
      uwagi << QStringLiteral( "ODS: brak warstwy dzialek (nr_dzialki) - obreb/dzialka/teryt puste" );
  }

  if ( pliki.isEmpty() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Eksport inwentaryzacji nie powiódł się: %1" ).arg( uwagi.join( QStringLiteral( "; " ) ) ) );
    return wynik;
  }
  wynik.insert( QStringLiteral( "pliki" ), pliki );
  wynik.insert( QStringLiteral( "katalog" ), katalog );
  wynik.insert( QStringLiteral( "drzewa" ), static_cast<int>( lista.size() ) );
  wynik.insert( QStringLiteral( "warstwa" ), drzewa->name() );
  wynik.insert( QStringLiteral( "rysunek" ), rysunek );
  wynik.insert( QStringLiteral( "uwagi" ), uwagi.join( QStringLiteral( "\n" ) ) );
  return wynik;
}

// ---------------------------------------------------------------------------
// Styl inwentaryzacji drzew - WorkField 19.09.2026
// Korona, strefa ochrony drzewa (SOD = korona + 1,5 m z kazdej strony)
// i pien jako okregi w METRACH wokol punktu. Liczone na zywo z pol:
// drzewo dodane w terenie od razu ma swoja korone na mapie.
// Wyrazenie pnia daje TE SAME wyniki co DxfInwentaryzacja::srednicaZObwodow
// (sprawdzone na 164 wartosciach, w tym 156 z Bruzdowej: 0 roznic).
// ---------------------------------------------------------------------------
#include <qgsmarkersymbol.h>
#include <qgsmarkersymbollayer.h>
#include <qgspallabeling.h>
#include <qgsproperty.h>
#include <qgssinglesymbolrenderer.h>
#include <qgstextbuffersettings.h>
#include <qgstextformat.h>
#include <qgsvectorlayerlabeling.h>

namespace
{
  QString wyrazeniePnia( const QString &pole )
  {
    // Srednica pnia [m] z opisu obwodow: najwiekszy + polowa pozostalych,
    // przez pi; sr/s/d/Ø = srednica; m2 = powierzchnia (0); minus jak plus.
    static const QString wzor = QString::fromUtf8( R"WFG(with_variable('t', lower(trim(coalesce(to_string(@pole_obwodow), ''))),
 CASE WHEN @t = '' OR regexp_match(@t, 'm2|²') THEN 0
 ELSE with_variable('cz',
  array_filter(
   array_foreach(
    string_to_array(
     regexp_replace(regexp_replace(@t, '(\\d)\\s*-\\s*(?=\\D*\\d)', '\\1+'), '(\\d)\\s*,\\s*(?=\\D*\\d{3}|\\D+\\d)', '\\1+'),
     '+'),
    with_variable('m', regexp_matches(@element, '^\\s*(śr|sr|s|ø|φ|d)?\\s*\\.?\\s*(?:ok\\.?\\s*)?(\\d+(?:[.,]\\d+)?)'),
     CASE
      WHEN @m IS NOT NULL AND array_length(@m) = 2
       THEN to_real(replace(@m[1], ',', '.')) * CASE WHEN @m[0] <> '' THEN pi() ELSE 1 END
      ELSE with_variable('n', regexp_substr(@element, '(\\d+(?:[.,]\\d+)?)'), CASE WHEN coalesce(@n, '') = '' THEN 0 ELSE to_real(replace(@n, ',', '.')) END)
     END)),
   @element > 0),
  CASE WHEN array_length(@cz) = 0 THEN 0
  ELSE (array_max(@cz) + 0.5 * (array_sum(@cz) - array_max(@cz))) / 100 / pi() END)
 END))WFG" );
    QString w = wzor;
    return w.replace( QLatin1String( "@pole_obwodow" ), pole );
  }

  QString wyrazenieKorony( const QString &pole )
  {
    // Pierwsza liczba z pola ("7", "7,5", "ok. 8 m"), jak DxfInwentaryzacja::liczba.
    return QStringLiteral( "with_variable('k', regexp_substr(to_string(%1), '(\\\\d+(?:[.,]\\\\d+)?)'), CASE WHEN coalesce(@k, '') = '' THEN 0 ELSE to_real(replace(@k, ',', '.')) END)" ).arg( pole );
  }

  QgsSimpleMarkerSymbolLayer *kolo( const QColor &wypelnienie, const QColor &obrys, double szerokosc, Qt::PenStyle styl,
                                   const QString &rozmiar, const QString &wlaczone = QString() )
  {
    QgsSimpleMarkerSymbolLayer *l = new QgsSimpleMarkerSymbolLayer( Qgis::MarkerShape::Circle, 1.0 );
    l->setSizeUnit( Qgis::RenderUnit::MapUnits );
    l->setColor( wypelnienie );
    l->setStrokeColor( obrys );
    l->setStrokeWidth( szerokosc );
    l->setStrokeWidthUnit( Qgis::RenderUnit::Millimeters );
    l->setStrokeStyle( styl );
#if _QGIS_VERSION_INT >= 33600
    l->setDataDefinedProperty( QgsSymbolLayer::Property::Size, QgsProperty::fromExpression( rozmiar ) );
    if ( !wlaczone.isEmpty() )
      l->setDataDefinedProperty( QgsSymbolLayer::Property::LayerEnabled, QgsProperty::fromExpression( wlaczone ) );
#else
    l->setDataDefinedProperty( QgsSymbolLayer::PropertySize, QgsProperty::fromExpression( rozmiar ) );
    if ( !wlaczone.isEmpty() )
      l->setDataDefinedProperty( QgsSymbolLayer::PropertyLayerEnabled, QgsProperty::fromExpression( wlaczone ) );
#endif
    return l;
  }
} // namespace

QVariantMap InwentaryzacjaDrzew::styluj( QgsProject *projekt ) const
{
  QVariantMap wynik;
  QgsProject *p = projekt ? projekt : QgsProject::instance();
  if ( !p || !p->layerTreeRoot() )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Brak otwartego projektu" ) );
    return wynik;
  }
  const WarstwaDrzew wd = znajdzWarstweDrzew( p );
  if ( !wd.warstwa )
  {
    wynik.insert( QStringLiteral( "blad" ), QStringLiteral( "Nie znalazłem warstwy drzew — potrzebna warstwa punktowa z polem obwodów i szerokości korony" ) );
    return wynik;
  }
  QgsVectorLayer *vl = wd.warstwa;
  const QgsFields pola = vl->fields();
  const QString pien = wyrazeniePnia( QgsExpression::quotedColumnRef( pola.at( wd.obwody ).name() ) );
  const QString korona = wyrazenieKorony( QgsExpression::quotedColumnRef( pola.at( wd.korona ).name() ) );

  QgsSymbolLayerList warstwy;
  // SOD: przerywany, bez wypelnienia; tylko gdy jest korona
  warstwy << kolo( QColor( 0, 0, 0, 0 ), QColor( 239, 108, 0 ), 0.3, Qt::DashLine,
                   QStringLiteral( "(%1) + 3" ).arg( korona ), QStringLiteral( "(%1) > 0" ).arg( korona ) );
  // korona: polprzezroczysta zielen
  warstwy << kolo( QColor( 76, 175, 80, 70 ), QColor( 46, 125, 50 ), 0.3, Qt::SolidLine,
                   korona, QStringLiteral( "(%1) > 0" ).arg( korona ) );
  // pien: brazowy, w prawdziwej srednicy; bez obwodow - 0,2 m, zeby bylo widac punkt
  warstwy << kolo( QColor( 121, 85, 72 ), QColor( 62, 39, 35 ), 0.1, Qt::SolidLine,
                   QStringLiteral( "CASE WHEN (%1) > 0 THEN (%1) ELSE 0.2 END" ).arg( pien ) );
  vl->setRenderer( new QgsSingleSymbolRenderer( new QgsMarkerSymbol( warstwy ) ) );

  // Etykieta: nr inw., a bez niego fid - jak w eksporcie DXF. Od 1:1500 w dol.
  QgsPalLayerSettings ust;
  ust.fieldName = wd.etykieta >= 0
                    ? QStringLiteral( "coalesce(nullif(trim(to_string(%1)), ''), to_string($id))" ).arg( QgsExpression::quotedColumnRef( pola.at( wd.etykieta ).name() ) )
                    : QStringLiteral( "to_string($id)" );
  ust.isExpression = true;
  QgsTextFormat format;
  format.setSize( 9 );
  format.setSizeUnit( Qgis::RenderUnit::Points );
  QgsTextBufferSettings bufor;
  bufor.setEnabled( true );
  bufor.setSize( 1 );
  format.setBuffer( bufor );
  ust.setFormat( format );
  ust.scaleVisibility = true;
  ust.minimumScale = 1500;
  ust.maximumScale = 0;
  vl->setLabeling( new QgsVectorLayerSimpleLabeling( ust ) );
  vl->setLabelsEnabled( true );
  vl->triggerRepaint();
  vl->emitStyleChanged();
  p->setDirty( true );

  wynik.insert( QStringLiteral( "warstwa" ), vl->name() );
  wynik.insert( QStringLiteral( "pola" ), QStringLiteral( "%1 / %2 / %3" ).arg( pola.at( wd.obwody ).name(), pola.at( wd.korona ).name(),
                                                                              wd.etykieta >= 0 ? pola.at( wd.etykieta ).name() : QStringLiteral( "fid" ) ) );
  return wynik;
}
