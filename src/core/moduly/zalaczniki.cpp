/***************************************************************************
  zalaczniki.cpp - ModulZalacznikow (WorkFieldGIS)

 ***************************************************************************
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 ***************************************************************************/
#include "zalaczniki.h"

#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>

#include <qgis.h>
#include <qgsattributeeditorcontainer.h>
#include <qgsattributeeditorrelation.h>
#include <qgsdefaultvalue.h>
#include <qgseditformconfig.h>
#include <qgseditorwidgetsetup.h>
#include <qgslayertree.h>
#include <qgslayertreegroup.h>
#include <qgslayertreelayer.h>
#include <qgsproject.h>
#include <qgsrelation.h>
#include <qgsrelationmanager.h>
#include <qgsvectorlayer.h>

#include <cpl_string.h>
#include <gdal.h>
#include <ogr_api.h>
#include <sqlite3.h>

namespace
{
  // ========================================================================
  // NAZWY — jedno zrodlo prawdy, zgodne ze `skrypty/zaloz_zalaczniki.py`.
  // Zmiana ktorejkolwiek rozjezdza projekty zrobione w biurze i w terenie.
  // ========================================================================
  const QString PREFIKS_TABELI = QStringLiteral( "ZAL_" );
  const QString POLE_RODZIC = QStringLiteral( "ID_RODZICA" );
  const QString POLE_TYP = QStringLiteral( "TYP" );
  const QString POLE_SCIEZKA = QStringLiteral( "SCIEZKA" );
  const QString POLE_UJECIE = QStringLiteral( "UJECIE" );
  const QString POLE_CZAS = QStringLiteral( "CZAS" );
  const QString POLE_AUTOR = QStringLiteral( "AUTOR" );
  const QString POLE_UWAGI = QStringLiteral( "UWAGI" );
  const QString KLUCZ_RODZICA = QStringLiteral( "fid" );
  const QString NAZWA_GRUPY = QStringLiteral( "Załączniki" );
  const QString NAZWA_ZAKLADKI = QStringLiteral( "Załączniki" );
  const QString NAZWA_RELACJI = QStringLiteral( "Załączniki" );

  //! Warstwy, ktore nigdy nie dostaja zalacznikow.
  const QStringList POMIN_PREFIKSY = {
    QStringLiteral( "zal_" ), QStringLiteral( "ZAL_" ),
    QStringLiteral( "podklad_" ), QStringLiteral( "REF_" ), QStringLiteral( "ref_" )
  };
  const QStringList POMIN_NAZWY = {
    QStringLiteral( "slownik" ), QStringLiteral( "slownik_gatunkow" ),
    QStringLiteral( "taksony" ), QStringLiteral( "wskazniki" ),
    QStringLiteral( "wskazniki_polaczone" ), QStringLiteral( "SLOWNIK_GATUNKOW" )
  };

  /**
   * Pola tabeli zalacznikow, w kolejnosci.
   *
   * ZADNE nie moze dostac NOT NULL. Przy nowym, jeszcze niezapisanym
   * obiekcie rodzica QField wpisuje klucz obcy dopiero po zatwierdzeniu
   * (featuremodel.cpp), a NOT NULL na ID_RODZICA wylaczyloby wtedy galerie
   * (referencingfeaturelistmodel.cpp: checkParentPrimaries).
   */
  struct Pole
  {
      QString nazwa;
      OGRFieldType typ;
  };

  QVector<Pole> polaZalacznika()
  {
    return {
      { POLE_RODZIC, OFTInteger64 },
      { POLE_TYP, OFTString },
      { POLE_SCIEZKA, OFTString },
      { POLE_UJECIE, OFTString },
      { POLE_CZAS, OFTString },
      { POLE_AUTOR, OFTString },
      { POLE_UWAGI, OFTString },
    };
  }

  //! Polskie znaki w nazwie tabeli i pliku to proszenie sie o klopoty
  //! (karta SD, zip, transliteracja w chmurze) — sprowadzamy do ASCII.
  QString bezOgonkow( const QString &tekst )
  {
    static const QString zrodlo = QStringLiteral( "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ" );
    static const QString cel = QStringLiteral( "acelnoszzACELNOSZZ" );
    QString w;
    w.reserve( tekst.size() );
    for ( const QChar &z : tekst )
    {
      const int i = zrodlo.indexOf( z );
      w.append( i >= 0 ? cel.at( i ) : z );
    }
    return w;
  }

  /**
   * Nazwa warstwy sprowadzona do tego, co wolno wpisac w nazwe tabeli.
   *
   * ZNALEZIONE W PROBIE 22.09.2026: kreator "Projekt z DXF" zaklada warstwe
   * nazwana „Poligony (hatch)", a stara regula (sam `bezOgonkow` i `upper`)
   * dawala z niej tabele `ZAL_POLIGONY (HATCH)` — ze spacja i nawiasami.
   * SQLite to przelyka w cudzyslowach i wszystko dziala, ale taka nazwa
   * gryzie przy kazdym recznym SQL-u, przy eksporcie i w cudzych
   * narzedziach, a indeks nazywa sie wtedy `idx_ZAL_POLIGONY (HATCH)_rodzic`.
   *
   * Skrypt biurowy mial te sama wade i nigdy sie nie objawila, bo puszczano
   * go na warstwach dendro (drzewa, grupy, uwagi). Regula jest poprawiona
   * w OBU miejscach naraz — patrz `skrypty/zaloz_zalaczniki.py`.
   */
  QString czysteMiano( const QString &nazwa )
  {
    const QString bezOg = bezOgonkow( nazwa );
    QString w;
    w.reserve( bezOg.size() );
    for ( const QChar &z : bezOg )
    {
      if ( ( z >= 'a' && z <= 'z' ) || ( z >= 'A' && z <= 'Z' ) || ( z >= '0' && z <= '9' ) )
        w.append( z );
      else if ( !w.isEmpty() && !w.endsWith( '_' ) )
        w.append( '_' );
    }
    while ( w.endsWith( '_' ) )
      w.chop( 1 );
    // Nazwa zlozona z samych znakow do wyrzucenia — lepiej cokolwiek niz nic.
    return w.isEmpty() ? QStringLiteral( "WARSTWA" ) : w;
  }

  //! (plik.gpkg, nazwa_tabeli) dla warstwy OGR z GeoPackage; puste, gdy nie.
  bool gpkgWarstwy( const QgsVectorLayer *w, QString *plik, QString *tabela )
  {
    if ( !w || w->providerType() != QLatin1String( "ogr" ) )
      return false;
    const QStringList czesci = w->source().split( '|' );
    if ( czesci.isEmpty() )
      return false;
    const QString p = czesci.first();
    if ( !p.endsWith( QLatin1String( ".gpkg" ), Qt::CaseInsensitive ) )
      return false;
    QString t;
    for ( int i = 1; i < czesci.size(); ++i )
    {
      if ( czesci.at( i ).startsWith( QLatin1String( "layername=" ) ) )
        t = czesci.at( i ).mid( QStringLiteral( "layername=" ).size() );
    }
    if ( plik )
      *plik = p;
    if ( tabela )
      *tabela = t.isEmpty() ? w->name() : t;
    return true;
  }

  /**
   * Czy tabela juz jest — pytamy SQLite WPROST, nie przez GDAL.
   *
   * GDAL trzyma pule otwartych zbiorow danych kluczowana sciezka pliku
   * (ta sama pulapka co przy blokach CAD, docs/MODUL_CAD.md): zapytany
   * o swiezo zalozona tabele potrafi odpowiedziec ze swojego, starszego
   * obrazu pliku. Odczyt z pliku takiej pamieci nie ma.
   */
  bool tabelaIstnieje( const QString &gpkg, const QString &tabela )
  {
    sqlite3 *db = nullptr;
    if ( sqlite3_open_v2( gpkg.toUtf8().constData(), &db, SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
    {
      if ( db )
        sqlite3_close( db );
      return false;
    }
    bool jest = false;
    sqlite3_stmt *zap = nullptr;
    if ( sqlite3_prepare_v2( db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                             -1, &zap, nullptr ) == SQLITE_OK )
    {
      sqlite3_bind_text( zap, 1, tabela.toUtf8().constData(), -1, SQLITE_TRANSIENT );
      jest = sqlite3_step( zap ) == SQLITE_ROW;
      sqlite3_finalize( zap );
    }
    sqlite3_close( db );
    return jest;
  }

  //! Zaklada tabele zalacznikow przez GDAL. Pusty ciag = sukces, inaczej blad.
  QString utworzTabele( const QString &gpkg, const QString &tabela )
  {
    GDALDatasetH ds = GDALOpenEx( gpkg.toUtf8().constData(),
                                  GDAL_OF_VECTOR | GDAL_OF_UPDATE,
                                  nullptr, nullptr, nullptr );
    if ( !ds )
      return QObject::tr( "nie otwarto bazy do zapisu" );

    char **opcje = nullptr;
    opcje = CSLSetNameValue( opcje, "FID", "fid" );
    // Bez ukladu i bez geometrii: to tabela, nie warstwa mapy.
    OGRLayerH l = GDALDatasetCreateLayer( ds, tabela.toUtf8().constData(),
                                          nullptr, wkbNone, opcje );
    CSLDestroy( opcje );
    if ( !l )
    {
      GDALClose( ds );
      return QObject::tr( "nie utworzono tabeli %1" ).arg( tabela );
    }

    const QVector<Pole> pola = polaZalacznika();
    for ( const Pole &p : pola )
    {
      OGRFieldDefnH fd = OGR_Fld_Create( p.nazwa.toUtf8().constData(), p.typ );
      const OGRErr err = OGR_L_CreateField( l, fd, TRUE );
      OGR_Fld_Destroy( fd );
      if ( err != OGRERR_NONE )
      {
        GDALClose( ds );
        return QObject::tr( "nie utworzono pola %1 w %2" ).arg( p.nazwa, tabela );
      }
    }
    GDALClose( ds );
    return QString();
  }

  //! Indeks po ID_RODZICA — galeria pyta o dzieci przy KAZDYM formularzu.
  void indeksRodzica( const QString &gpkg, const QString &tabela )
  {
    sqlite3 *db = nullptr;
    if ( sqlite3_open( gpkg.toUtf8().constData(), &db ) != SQLITE_OK )
    {
      if ( db )
        sqlite3_close( db );
      return;
    }
    const QString sql = QStringLiteral( "CREATE INDEX IF NOT EXISTS \"idx_%1_rodzic\" ON \"%1\" (\"%2\")" )
                          .arg( tabela, POLE_RODZIC );
    sqlite3_exec( db, sql.toUtf8().constData(), nullptr, nullptr, nullptr );
    sqlite3_close( db );
  }

  /**
   * Wyrazenie liczace sciezke pliku zalacznika.
   *
   *     DCIM/<warstwa>_<klucz>/<warstwa>_<klucz>_RRRRMMDD_GGMMSS_mmm.<rozsz>
   *
   * Klucz rodzica podaje aplikacja w zmiennej @rodzic_fid. Aplikacja bez
   * tej zmiennej dostaje NULL — wtedy wyrazenie schodzi do starej, plaskiej
   * nazwy zamiast robic katalog o nazwie "NULL". Dzieki temu ten sam projekt
   * dziala na starym i nowym APK.
   */
  QString wyrazenieNazwy( const QString &warstwa )
  {
    const QString czas = QStringLiteral( "format_date(now(),'yyyyMMdd_HHmmss_zzz')" );
    const QString plaska = QStringLiteral( "'DCIM/%1_' || %2 || '.{extension}'" ).arg( warstwa, czas );
    const QString zKluczem = QStringLiteral(
                               "'DCIM/%1_' || @rodzic_fid || '/%1_' || @rodzic_fid || '_' || %2 || '.{extension}'" )
                               .arg( warstwa, czas );
    return QStringLiteral( "CASE WHEN @rodzic_fid IS NULL THEN %1 ELSE %2 END" ).arg( plaska, zKluczem );
  }

  //! Widgety, wartosci domyslne i konwencja nazw plikow w tabeli-dziecku.
  QString konfigurujDziecko( QgsVectorLayer *dziecko, const QString &nazwaRodzica )
  {
    auto idx = [dziecko]( const QString &pole ) {
      return dziecko->fields().indexOf( pole );
    };

    // Bez tych dwoch pol cala funkcja nie ma sensu: SCIEZKA nosi widget
    // ExternalResource (to ON przelacza edytor relacji na galerie),
    // ID_RODZICA trzyma klucz obcy. Lepiej zatrzymac sie glosno.
    for ( const QString &wymagane : { POLE_SCIEZKA, POLE_RODZIC } )
    {
      if ( idx( wymagane ) < 0 )
        return QObject::tr( "tabela %1 nie ma pola %2" ).arg( dziecko->name(), wymagane );
    }

    const QgsEditorWidgetSetup ukryty( QStringLiteral( "Hidden" ), QVariantMap() );

    QVariantMap zasobCfg;
    zasobCfg[QStringLiteral( "DocumentViewer" )] = 1; // podglad obrazu
    zasobCfg[QStringLiteral( "RelativeStorage" )] = 1; // sciezka wzgledem projektu
    zasobCfg[QStringLiteral( "StorageMode" )] = 0;
    zasobCfg[QStringLiteral( "FileWidget" )] = true;
    zasobCfg[QStringLiteral( "FileWidgetButton" )] = true;
    const QgsEditorWidgetSetup zasob( QStringLiteral( "ExternalResource" ), zasobCfg );

    QVariantList mapaTypow;
    const QList<QPair<QString, QString>> typy = {
      { QStringLiteral( "zdjęcie" ), QStringLiteral( "foto" ) },
      { QStringLiteral( "szkic" ), QStringLiteral( "szkic" ) },
      { QStringLiteral( "nagranie" ), QStringLiteral( "audio" ) },
      { QStringLiteral( "notatka" ), QStringLiteral( "notatka" ) },
    };
    for ( const auto &t : typy )
    {
      QVariantMap wpis;
      wpis[t.first] = t.second;
      mapaTypow << wpis;
    }
    QVariantMap listaCfg;
    listaCfg[QStringLiteral( "map" )] = mapaTypow;
    const QgsEditorWidgetSetup listaTypow( QStringLiteral( "ValueMap" ), listaCfg );

    if ( idx( KLUCZ_RODZICA ) >= 0 )
      dziecko->setEditorWidgetSetup( idx( KLUCZ_RODZICA ), ukryty );
    dziecko->setEditorWidgetSetup( idx( POLE_RODZIC ), ukryty );
    dziecko->setEditorWidgetSetup( idx( POLE_SCIEZKA ), zasob );
    if ( idx( POLE_TYP ) >= 0 )
    {
      dziecko->setEditorWidgetSetup( idx( POLE_TYP ), listaTypow );
      dziecko->setDefaultValueDefinition( idx( POLE_TYP ),
                                          QgsDefaultValue( QStringLiteral( "'foto'" ) ) );
    }
    if ( idx( POLE_CZAS ) >= 0 )
      dziecko->setDefaultValueDefinition(
        idx( POLE_CZAS ),
        QgsDefaultValue( QStringLiteral( "format_date(now(),'yyyy-MM-dd HH:mm:ss')" ) ) );
    if ( idx( POLE_AUTOR ) >= 0 )
      dziecko->setDefaultValueDefinition( idx( POLE_AUTOR ),
                                          QgsDefaultValue( QStringLiteral( "@wykonawca" ) ) );

    QJsonObject nazewnictwo;
    nazewnictwo[POLE_SCIEZKA] = wyrazenieNazwy( bezOgonkow( nazwaRodzica ) );
    dziecko->setCustomProperty(
      QStringLiteral( "QFieldSync/attachment_naming" ),
      QString::fromUtf8( QJsonDocument( nazewnictwo ).toJson( QJsonDocument::Compact ) ) );

    // Formularz dziecka pomijany: zdjecie z galerii zapisuje sie od razu,
    // bez pytania o atrybuty (gallery_relation_editor -> suppressFeatureForm).
    QgsEditFormConfig cfg = dziecko->editFormConfig();
    cfg.setSuppress( Qgis::AttributeFormSuppression::On );
    dziecko->setEditFormConfig( cfg );

    dziecko->setDisplayExpression(
      QStringLiteral( "coalesce(\"%1\", \"%2\", 'załącznik')" ).arg( POLE_SCIEZKA, POLE_TYP ) );
    return QString();
  }

  bool maRelacje( const QgsAttributeEditorContainer *element, const QString &relId )
  {
    const QList<QgsAttributeEditorElement *> dzieci = element->children();
    for ( QgsAttributeEditorElement *d : dzieci )
    {
      if ( const QgsAttributeEditorRelation *r = dynamic_cast<const QgsAttributeEditorRelation *>( d ) )
      {
        // Swiezo utworzony element zna tylko swoja nazwe (= id relacji);
        // relation() wypelnia sie dopiero przy wczytaniu projektu z XML,
        // wiec bez sprawdzenia nazwy drugie uruchomienie w tej samej sesji
        // dolozyloby druga zakladke.
        if ( r->name() == relId )
          return true;
        if ( r->relation().id() == relId )
          return true;
      }
      if ( const QgsAttributeEditorContainer *k = dynamic_cast<const QgsAttributeEditorContainer *>( d ) )
      {
        if ( maRelacje( k, relId ) )
          return true;
      }
    }
    return false;
  }

  //! Zakladka z galeria w formularzu rodzica. True = dolozono teraz.
  bool dodajZakladke( QgsVectorLayer *rodzic, const QString &relId )
  {
    QgsEditFormConfig cfg = rodzic->editFormConfig();
    // Formularz automatyczny: QGIS i WorkFieldGIS same dokladaja relacje
    // (qfattributeformmodelbase.cpp: generateRootContainer).
    if ( cfg.layout() != Qgis::AttributeFormLayout::DragAndDrop )
      return false;

    QgsAttributeEditorContainer *korzen = cfg.invisibleRootContainer();
    if ( !korzen || maRelacje( korzen, relId ) )
      return false;

    QgsAttributeEditorContainer *kontener = new QgsAttributeEditorContainer( NAZWA_ZAKLADKI, korzen );
    kontener->setType( Qgis::AttributeEditorContainerType::Tab );
    kontener->addChildElement( new QgsAttributeEditorRelation( relId, kontener ) );
    korzen->addChildElement( kontener );
    rodzic->setEditFormConfig( cfg );
    return true;
  }

  //! Warstwa techniczna: grupa „Załączniki", zwinieta, wylaczona na mapie.
  void doGrupy( QgsProject *projekt, QgsVectorLayer *warstwa )
  {
    QgsLayerTree *korzen = projekt->layerTreeRoot();
    if ( !korzen )
      return;
    QgsLayerTreeGroup *grupa = korzen->findGroup( NAZWA_GRUPY );
    if ( !grupa )
    {
      grupa = korzen->addGroup( NAZWA_GRUPY );
      grupa->setExpanded( false );
      grupa->setItemVisibilityChecked( false );
    }
    if ( !grupa->findLayer( warstwa->id() ) )
    {
      // Warstwa dodana przez `addMapLayer(l, false)` nie ma wezla w drzewie
      // wcale — wtedy `wezel` jest pusty i nie ma czego przenosic.
      QgsLayerTreeLayer *wezel = korzen->findLayer( warstwa->id() );
      grupa->addLayer( warstwa );
      if ( wezel )
      {
        // `removeChildNode` jest na GRUPIE, nie na wezle — rodzicem wezla
        // moze byc korzen albo inna grupa.
        if ( QgsLayerTreeGroup *rodzicWezla = qobject_cast<QgsLayerTreeGroup *>( wezel->parent() ) )
          rodzicWezla->removeChildNode( wezel );
      }
    }
    if ( QgsLayerTreeLayer *w = grupa->findLayer( warstwa->id() ) )
      w->setItemVisibilityChecked( false );
  }
} // namespace

namespace ModulZalacznikow
{
  QList<QgsVectorLayer *> kandydaci( QgsProject *projekt )
  {
    QList<QgsVectorLayer *> out;
    if ( !projekt )
      return out;

    const QMap<QString, QgsMapLayer *> warstwy = projekt->mapLayers();
    for ( QgsMapLayer *m : warstwy )
    {
      QgsVectorLayer *w = qobject_cast<QgsVectorLayer *>( m );
      if ( !w || !w->isValid() || w->readOnly() )
        continue;

      const QString nazwa = w->name();
      if ( POMIN_NAZWY.contains( nazwa ) )
        continue;
      bool pomin = false;
      for ( const QString &p : POMIN_PREFIKSY )
      {
        if ( nazwa.startsWith( p ) )
        {
          pomin = true;
          break;
        }
      }
      if ( pomin )
        continue;

      QString plik;
      if ( !gpkgWarstwy( w, &plik, nullptr ) )
        continue;
      // Bez `fid` nie ma do czego przypiac klucza obcego.
      if ( w->fields().indexOf( KLUCZ_RODZICA ) < 0 )
        continue;

      out << w;
    }

    // Kolejnosc z `mapLayers()` jest kolejnoscia mapy skrotow — dla
    // powtarzalnosci wynikow i czytelnosci dziennika sortujemy po nazwie.
    std::sort( out.begin(), out.end(), []( QgsVectorLayer *a, QgsVectorLayer *b ) {
      return a->name().localeAwareCompare( b->name() ) < 0;
    } );
    return out;
  }

  QStringList bazy( QgsProject *projekt )
  {
    QStringList out;
    const QList<QgsVectorLayer *> w = kandydaci( projekt );
    for ( QgsVectorLayer *l : w )
    {
      QString plik;
      if ( gpkgWarstwy( l, &plik, nullptr ) && !out.contains( plik ) )
        out << plik;
    }
    return out;
  }

  Wynik zaloz( QgsProject *projekt )
  {
    Wynik w;
    if ( !projekt )
    {
      w.opis = QObject::tr( "Nie ma otwartego projektu." );
      return w;
    }

    const QList<QgsVectorLayer *> wybrane = kandydaci( projekt );
    if ( wybrane.isEmpty() )
    {
      w.opis = QObject::tr( "Nie znalazłem warstw, którym można dołożyć załączniki." );
      return w;
    }

    // ODMOWA W CALOSCI, gdy ktorakolwiek warstwa jest w edycji. Dopisywanie
    // tabel do pliku, w ktorym ktos ma otwarty bufor edycji, konczy sie
    // w najlepszym razie utracona sesja. Skrypt biurowy prosi o to czlowieka
    // slowami; tutaj mozemy sprawdzic sami.
    QStringList wEdycji;
    for ( QgsVectorLayer *l : wybrane )
    {
      if ( l->isEditable() )
        wEdycji << l->name();
    }
    if ( !wEdycji.isEmpty() )
    {
      w.opis = QObject::tr( "Najpierw zakończ edycję warstw: %1." ).arg( wEdycji.join( QStringLiteral( ", " ) ) );
      return w;
    }

    int nowychTabel = 0;
    int nowychRelacji = 0;
    //! Dwie rozne nazwy warstw moga sprowadzic sie do jednej nazwy tabeli
    //! („Poligony (hatch)" i „Poligony hatch"). Wtedy druga warstwa
    //! podpielaby sie pod CUDZA tabele zalacznikow — zdjecia jednej
    //! wyswietlalyby sie przy drugiej. Lepiej odmowic i powiedziec czemu.
    QSet<QString> zajeteTabele;

    for ( QgsVectorLayer *rodzic : wybrane )
    {
      const QString nazwa = rodzic->name();
      QString gpkg;
      if ( !gpkgWarstwy( rodzic, &gpkg, nullptr ) )
        continue;

      QString tabela = PREFIKS_TABELI + czysteMiano( nazwa ).toUpper();

      // ZGODNOSC WSTECZ: projekt wyposazony starsza regula ma tabele pod
      // nazwa nieoczyszczona. Jesli taka jest, uzywamy JEJ — inaczej
      // powstalaby druga tabela obok pelnej zdjec.
      const QString tabelaStara = PREFIKS_TABELI + bezOgonkow( nazwa ).toUpper();
      if ( tabelaStara != tabela && !tabelaIstnieje( gpkg, tabela )
           && tabelaIstnieje( gpkg, tabelaStara ) )
        tabela = tabelaStara;

      if ( zajeteTabele.contains( tabela ) )
      {
        w.opis = QObject::tr( "Warstwy „%1\" nie da się wyposażyć: nazwa tabeli %2 "
                              "jest już zajęta przez inną warstwę. Zmień nazwę jednej z nich." )
                   .arg( nazwa, tabela );
        return w;
      }
      zajeteTabele.insert( tabela );

      // --- 1. tabela w GeoPackage ---------------------------------------
      bool nowa = false;
      if ( !tabelaIstnieje( gpkg, tabela ) )
      {
        const QString blad = utworzTabele( gpkg, tabela );
        if ( !blad.isEmpty() )
        {
          w.opis = QObject::tr( "Warstwa %1: %2." ).arg( nazwa, blad );
          return w;
        }
        nowa = true;
        ++nowychTabel;
      }
      indeksRodzica( gpkg, tabela );

      // --- 2. warstwa-dziecko w projekcie -------------------------------
      QgsVectorLayer *dziecko = nullptr;
      const QMap<QString, QgsMapLayer *> istniejace = projekt->mapLayers();
      for ( QgsMapLayer *m : istniejace )
      {
        QgsVectorLayer *l = qobject_cast<QgsVectorLayer *>( m );
        QString p, t;
        if ( l && gpkgWarstwy( l, &p, &t ) && p == gpkg && t == tabela )
        {
          dziecko = l;
          break;
        }
      }

      if ( !dziecko )
      {
        const QString uri = QStringLiteral( "%1|layername=%2" ).arg( gpkg, tabela );
        const QString nazwaDziecka = QStringLiteral( "zal_" ) + nazwa;
        dziecko = new QgsVectorLayer( uri, nazwaDziecka, QStringLiteral( "ogr" ) );
        if ( !dziecko->isValid() )
        {
          // GDAL bywa "przyzwyczajony" do starej zawartosci pliku, ktory
          // QGIS trzyma otwarty — swieza tabela potrafi nie byc widoczna
          // za pierwszym razem. Jedna ponowna proba zwykle wystarcza.
          delete dziecko;
          dziecko = new QgsVectorLayer( uri, nazwaDziecka, QStringLiteral( "ogr" ) );
        }
        if ( !dziecko->isValid() )
        {
          delete dziecko;
          w.opis = QObject::tr( "Nie wczytałem tabeli załączników %1. Tabela w pliku już jest, "
                                "więc ponowne uruchomienie jej nie zdubluje." )
                     .arg( tabela );
          return w;
        }
        projekt->addMapLayer( dziecko, false );
      }
      doGrupy( projekt, dziecko );

      // --- 3. widgety i konwencja nazw ----------------------------------
      const QString bladCfg = konfigurujDziecko( dziecko, nazwa );
      if ( !bladCfg.isEmpty() )
      {
        w.opis = QObject::tr( "Warstwa %1: %2." ).arg( nazwa, bladCfg );
        return w;
      }

      // --- 4. relacja ----------------------------------------------------
      // Identyfikator liczony TA SAMA regula co w skrypcie biurowym — dzieki
      // temu projekt wyposazony tamta droga nie dostanie tu drugiej relacji.
      // Dla nazw bez znakow specjalnych (drzewa, grupy, uwagi) wychodzi
      // dokladnie to, co dawala regula sprzed oczyszczania nazw.
      QString relId = QStringLiteral( "zal_" ) + czysteMiano( nazwa );
      const QString relIdStary = QStringLiteral( "zal_" ) + nazwa;
      if ( relIdStary != relId && !projekt->relationManager()->relation( relId ).isValid()
           && projekt->relationManager()->relation( relIdStary ).isValid() )
        relId = relIdStary;
      const QgsRelation istniejaca = projekt->relationManager()->relation( relId );
      if ( !istniejaca.isValid() )
      {
        QgsRelation rel;
        rel.setId( relId );
        rel.setName( NAZWA_RELACJI );
        rel.setReferencedLayer( rodzic->id() );
        rel.setReferencingLayer( dziecko->id() );
        rel.addFieldPair( POLE_RODZIC, KLUCZ_RODZICA );
        // Kompozycja: skasowanie obiektu kasuje jego zalaczniki.
        rel.setStrength( Qgis::RelationshipStrength::Composition );
        if ( !rel.isValid() )
        {
          w.opis = QObject::tr( "Relacja załączników dla warstwy %1 wyszła nieprawidłowa." ).arg( nazwa );
          return w;
        }
        projekt->relationManager()->addRelation( rel );
        ++nowychRelacji;
      }

      // --- 5. zakladka w formularzu rodzica ------------------------------
      const bool zakladka = dodajZakladke( rodzic, relId );

      w.szczegoly << QObject::tr( "%1 → %2%3%4" )
                       .arg( nazwa, tabela,
                             nowa ? QObject::tr( " (tabela nowa)" ) : QString(),
                             zakladka ? QObject::tr( ", zakładka" ) : QString() );
    }

    w.ok = true;
    w.opis = QObject::tr( "załączniki w %1 warstwach (nowych tabel: %2, relacji: %3)" )
               .arg( wybrane.size() )
               .arg( nowychTabel )
               .arg( nowychRelacji );
    return w;
  }
} // namespace ModulZalacznikow
