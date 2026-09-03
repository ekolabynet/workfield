#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# WorkField: metadane gatunkow — speciesMeta() w C++, linijka meta w panelu
# tagowania, panel METATAGOW. Bezpieczna: niezgodnosc = koniec BEZ zmian.
import io, os, sys

REPO = os.environ.get('WF_REPO', '/DATA/SOFT/GIS/QFIELD_Pro/QField')
os.chdir(REPO)
print("Repo:", REPO)

def wczytaj(p):
    return io.open(p, encoding='utf-8').read()

def zapisz(p, s):
    io.open(p, 'w', encoding='utf-8').write(s)

def podmien(s, stare, nowe, opis):
    n = s.count(stare)
    if n != 1:
        sys.exit("STOP: [%s] kotwica znaleziona %d razy (oczekiwano 1) - NIC nie zmieniono" % (opis, n))
    return s.replace(stare, nowe)

# ================= 1. phototagstore.h =================
p = 'src/core/phototagstore.h'
s = wczytaj(p)
if 'speciesMeta' in s:
    print("phototagstore.h: juz jest - pomijam")
else:
    s = podmien(s, "    Q_INVOKABLE QStringList formSpecies();\n",
"""    Q_INVOKABLE QStringList formSpecies();

    //! Metadane gatunku: wiersz SLOWNIK_GATUNKOW + wskazniki_polaczone
    //! (Tichy/Chytry EIV, Midolo) z GPKG projektu; pusta mapa gdy brak.
    Q_INVOKABLE QVariantMap speciesMeta( const QString &gatunek );
""", "naglowek: deklaracja")
    s = podmien(s, "    QStringList mProjectSpecies;",
"""    QStringList mProjectSpecies;
    QString mMetaGpkg;
    bool mMetaSearched = false;""", "naglowek: pola cache")
    zapisz(p, s)
    print("phototagstore.h: OK")

# ================= 2. phototagstore.cpp =================
p = 'src/core/phototagstore.cpp'
s = wczytaj(p)
if 'speciesMeta' in s:
    print("phototagstore.cpp: juz jest - pomijam")
else:
    s += """
QVariantMap PhotoTagStore::speciesMeta( const QString &gatunek )
{
  QVariantMap meta;
  if ( mProjectDir.isEmpty() )
    return meta;

  // klucz kanoniczny: czlon przed " - " i przed " [" — "Abies alba"
  QString klucz = gatunek;
  int p = klucz.indexOf( QLatin1String( " - " ) );
  if ( p > 0 )
    klucz = klucz.left( p );
  p = klucz.indexOf( QLatin1String( " [" ) );
  if ( p > 0 )
    klucz = klucz.left( p );
  klucz = klucz.trimmed().toLower();
  if ( klucz.isEmpty() )
    return meta;

  if ( !mMetaSearched )
  {
    mMetaSearched = true;
    const QStringList gpkgs = QDir( mProjectDir ).entryList( QStringList() << QStringLiteral( "*.gpkg" ), QDir::Files );
    for ( const QString &name : gpkgs )
    {
      if ( name == QLatin1String( "foto_tagi.gpkg" ) )
        continue;
      sqlite3 *db = nullptr;
      const QString path = QDir( mProjectDir ).filePath( name );
      if ( sqlite3_open_v2( path.toUtf8().constData(), &db, SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
      {
        if ( db )
          sqlite3_close( db );
        continue;
      }
      sqlite3_stmt *ts = nullptr;
      bool ma = false;
      if ( sqlite3_prepare_v2( db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='SLOWNIK_GATUNKOW'", -1, &ts, nullptr ) == SQLITE_OK )
      {
        ma = sqlite3_step( ts ) == SQLITE_ROW;
        sqlite3_finalize( ts );
      }
      sqlite3_close( db );
      if ( ma )
      {
        mMetaGpkg = path;
        break;
      }
    }
  }
  if ( mMetaGpkg.isEmpty() )
    return meta;

  sqlite3 *db = nullptr;
  if ( sqlite3_open_v2( mMetaGpkg.toUtf8().constData(), &db, SQLITE_OPEN_READONLY, nullptr ) != SQLITE_OK )
  {
    if ( db )
      sqlite3_close( db );
    return meta;
  }

  bool maWsk = false;
  sqlite3_stmt *ts = nullptr;
  if ( sqlite3_prepare_v2( db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='wskazniki_polaczone'", -1, &ts, nullptr ) == SQLITE_OK )
  {
    maWsk = sqlite3_step( ts ) == SQLITE_ROW;
    sqlite3_finalize( ts );
  }

  const char *sqlPelny = "SELECT s.*, w.zrodlo_eiv AS EIV_ZRODLO, w.L AS EIV_L, w.T AS EIV_T, w.M AS EIV_M, w.R AS EIV_R, w.N AS EIV_N, w.S AS EIV_S,"
                         " w.zrodlo_zab AS ZAB_ZRODLO, w.\\"Disturbance.Severity\\" AS ZAB_SEVERITY, w.\\"Disturbance.Frequency\\" AS ZAB_FREQUENCY,"
                         " w.\\"Mowing.Frequency\\" AS ZAB_MOWING, w.\\"Grazing.Pressure\\" AS ZAB_GRAZING, w.\\"Soil.Disturbance\\" AS ZAB_SOIL"
                         " FROM SLOWNIK_GATUNKOW s LEFT JOIN wskazniki_polaczone w ON lower(trim(w.takson)) = lower(trim(s.GATUNEK))"
                         " WHERE lower(trim(s.GATUNEK)) = ?1 OR lower(trim(s.ETYKIETA)) = lower(trim(?2)) LIMIT 1";
  const char *sqlProsty = "SELECT s.* FROM SLOWNIK_GATUNKOW s WHERE lower(trim(s.GATUNEK)) = ?1 LIMIT 1";

  sqlite3_stmt *st = nullptr;
  if ( sqlite3_prepare_v2( db, maWsk ? sqlPelny : sqlProsty, -1, &st, nullptr ) != SQLITE_OK )
  {
    // zapasowo (np. slownik bez kolumny ETYKIETA)
    if ( st )
      sqlite3_finalize( st );
    st = nullptr;
    if ( sqlite3_prepare_v2( db, sqlProsty, -1, &st, nullptr ) != SQLITE_OK )
    {
      if ( st )
        sqlite3_finalize( st );
      sqlite3_close( db );
      return meta;
    }
  }

  const QByteArray k = klucz.toUtf8();
  const QByteArray pelna = gatunek.trimmed().toUtf8();
  sqlite3_bind_text( st, 1, k.constData(), -1, SQLITE_TRANSIENT );
  if ( sqlite3_bind_parameter_count( st ) >= 2 )
    sqlite3_bind_text( st, 2, pelna.constData(), -1, SQLITE_TRANSIENT );
  if ( sqlite3_step( st ) == SQLITE_ROW )
  {
    const int n = sqlite3_column_count( st );
    for ( int i = 0; i < n; i++ )
    {
      const QString kol = QString::fromUtf8( sqlite3_column_name( st, i ) );
      const unsigned char *txt = sqlite3_column_text( st, i );
      meta.insert( kol, txt ? QString::fromUtf8( reinterpret_cast<const char *>( txt ) ) : QString() );
    }
  }
  sqlite3_finalize( st );
  sqlite3_close( db );
  return meta;
}
"""
    zapisz(p, s)
    print("phototagstore.cpp: OK")

# ================= 3. QfPhotoGallery.qml =================
p = 'src/app/qml/QfPhotoGallery.qml'
s = wczytaj(p)
if 'metaLinia' in s:
    sys.exit("Galeria: metatagi juz sa - nic do zrobienia.")

# 3a. linijka meta pod polem gatunku
s = podmien(s, """          onAccepted: addTagButton.clicked()
        }
""",
"""          onAccepted: addTagButton.clicked()
        }

        // WorkField: metadane gatunku — skrot; dotkniecie otwiera panel
        Label {
          id: metaLinia
          Layout.fillWidth: true
          visible: text !== ""
          font.pointSize: photoGallery.t.tinyFont.pointSize
          color: "#80DEEA"
          elide: Text.ElideRight

          property var meta: ({})

          text: {
            const m = metaLinia.meta;
            if (!m || m.GATUNEK === undefined)
              return "";
            const cz = [];
            if (m.L_N) cz.push("Ś" + m.L_N);
            if (m.W_N) cz.push("W" + m.W_N);
            if (m.TR_N) cz.push("Tr" + m.TR_N);
            if (m.R_N) cz.push("R" + m.R_N);
            let t = cz.join(" ");
            let zb = "";
            if (m.UP_ALL && String(m.UP_ALL).trim() !== "")
              zb = m.UP_ALL;
            else if (m.UP_O && String(m.UP_O).trim() !== "")
              zb = m.UP_O;
            else if (m.UP_CL && String(m.UP_CL).trim() !== "")
              zb = m.UP_CL;
            if (zb !== "")
              t += (t !== "" ? "  ·  " : "") + zb;
            return t === "" ? "" : "≡ " + t;
          }

          Timer {
            id: metaTimer
            interval: 350
            onTriggered: metaLinia.meta = tagInput.text.trim() !== "" ? tagStore.speciesMeta(tagInput.text) : ({})
          }

          Connections {
            target: tagInput
            function onTextChanged() {
              metaTimer.restart();
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: metaPanelOkno.pokaz(tagInput.text, metaLinia.meta)
          }
        }
""", "galeria: linijka meta")

# 3b. panel METATAGOW przed FolderListModel
s = podmien(s, """  FolderListModel {
    id: dcimModel""",
"""  // ---- WorkField: panel METATAGOW — pelna karta metadanych gatunku ----
  Popup {
    id: metaPanelOkno
    parent: Overlay.overlay
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width - 32, 520)
    height: Math.min(parent.height - 64, 620)
    padding: 14

    property var m: ({})
    property string nazwa: ""

    function pokaz(gatunek, meta) {
      nazwa = String(gatunek || "").trim();
      m = (meta && meta.GATUNEK !== undefined) ? meta : tagStore.speciesMeta(nazwa);
      open();
    }

    function w(v) {
      return (v === undefined || v === null || String(v).trim() === "") ? "—" : String(v).trim();
    }

    function z2(v) {
      const n = Number(v);
      return (v === undefined || v === null || String(v).trim() === "" || isNaN(n)) ? "—" : n.toFixed(2);
    }

    background: Rectangle {
      color: "#F0263238"
      radius: 10
    }

    contentItem: Flickable {
      contentHeight: metaKol.implicitHeight
      clip: true

      Column {
        id: metaKol
        width: parent.width
        spacing: 8

        Label {
          width: parent.width
          wrapMode: Text.WordWrap
          font.bold: true
          font.italic: true
          color: "#39ff14"
          text: metaPanelOkno.m.GATUNEK !== undefined ? metaPanelOkno.w(metaPanelOkno.m.GATUNEK) : (metaPanelOkno.nazwa + qsTr(" — brak w słowniku"))
        }

        Label {
          visible: metaPanelOkno.m.NAZWA_POLSKA !== undefined && metaPanelOkno.w(metaPanelOkno.m.NAZWA_POLSKA) !== "—"
          width: parent.width
          wrapMode: Text.WordWrap
          color: "#B0BEC5"
          text: metaPanelOkno.w(metaPanelOkno.m.NAZWA_POLSKA)
        }

        Label {
          visible: text !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          color: "#FFCC80"
          font.bold: true
          text: {
            const st = [];
            if (metaPanelOkno.m.CHRONIONY === "TAK")
              st.push(qsTr("CHRONIONY"));
            if (metaPanelOkno.m.CENNY === "TAK")
              st.push(qsTr("CENNY / RZADKI"));
            if (metaPanelOkno.m.IGO !== undefined && metaPanelOkno.w(metaPanelOkno.m.IGO) !== "—" && metaPanelOkno.m.IGO !== "NIE")
              st.push(String(metaPanelOkno.m.IGO));
            return st.join("  ·  ");
          }
        }

        Rectangle { width: parent.width; height: 1; color: "#455A64" }

        Label { color: "#80DEEA"; font.bold: true; text: qsTr("Zarzycki — liczby wskaźnikowe (PL)") }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "white"
          text: qsTr("światło Ś:") + metaPanelOkno.w(metaPanelOkno.m.L_N)
              + qsTr("   temp. T:") + metaPanelOkno.w(metaPanelOkno.m.T_N)
              + qsTr("   wilg. W:") + metaPanelOkno.w(metaPanelOkno.m.W_N)
              + qsTr("   trofizm Tr:") + metaPanelOkno.w(metaPanelOkno.m.TR_N)
              + qsTr("   odczyn R:") + metaPanelOkno.w(metaPanelOkno.m.R_N)
        }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "#B0BEC5"
          text: qsTr("granulom. D:") + metaPanelOkno.w(metaPanelOkno.m.D_N)
              + qsTr("   humus H:") + metaPanelOkno.w(metaPanelOkno.m.H_N)
              + qsTr("   mat.org. M:") + metaPanelOkno.w(metaPanelOkno.m.M_N)
              + qsTr("   kontynent. K:") + metaPanelOkno.w(metaPanelOkno.m.K_N)
              + qsTr("   zasol. S:") + metaPanelOkno.w(metaPanelOkno.m.S_N)
        }

        Rectangle { width: parent.width; height: 1; color: "#455A64" }

        Label { color: "#80DEEA"; font.bold: true; text: qsTr("Ellenberg EIV (Tichý/Chytrý 2023) — źródło: ") + metaPanelOkno.w(metaPanelOkno.m.EIV_ZRODLO) }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "white"
          text: qsTr("światło L:") + metaPanelOkno.w(metaPanelOkno.m.EIV_L)
              + qsTr("   temp. T:") + metaPanelOkno.w(metaPanelOkno.m.EIV_T)
              + qsTr("   wilg. M:") + metaPanelOkno.w(metaPanelOkno.m.EIV_M)
              + qsTr("   odczyn R:") + metaPanelOkno.w(metaPanelOkno.m.EIV_R)
              + qsTr("   żyzność N:") + metaPanelOkno.w(metaPanelOkno.m.EIV_N)
              + qsTr("   zasol. S:") + metaPanelOkno.w(metaPanelOkno.m.EIV_S)
        }

        Rectangle { width: parent.width; height: 1; color: "#455A64" }

        Label { color: "#80DEEA"; font.bold: true; text: qsTr("Zaburzenia (Midolo 2023)") }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "white"
          text: qsTr("nasilenie: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_SEVERITY)
              + qsTr("   częstość: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_FREQUENCY)
              + qsTr("   koszenie: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_MOWING)
              + qsTr("   wypas: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_GRAZING)
              + qsTr("   gleba: ") + metaPanelOkno.z2(metaPanelOkno.m.ZAB_SOIL)
        }

        Rectangle { width: parent.width; height: 1; color: "#455A64" }

        Label { color: "#80DEEA"; font.bold: true; text: qsTr("Fitosocjologia (atlas-roslin.pl)") }
        Label {
          width: parent.width; wrapMode: Text.WordWrap; color: "white"
          text: qsTr("Klasa: ") + metaPanelOkno.w(metaPanelOkno.m.UP_CL)
              + qsTr("\\nRząd: ") + metaPanelOkno.w(metaPanelOkno.m.UP_O)
              + qsTr("\\nZwiązek: ") + metaPanelOkno.w(metaPanelOkno.m.UP_ALL)
              + qsTr("\\nZespół: ") + metaPanelOkno.w(metaPanelOkno.m.UP_ASS)
        }
        Label {
          visible: metaPanelOkno.w(metaPanelOkno.m.NAWIAZANIE_FITOSOCJOLOGICZNE) !== "—"
          width: parent.width; wrapMode: Text.WordWrap; color: "#B0BEC5"
          text: metaPanelOkno.w(metaPanelOkno.m.NAWIAZANIE_FITOSOCJOLOGICZNE)
        }

        Button {
          text: qsTr("Zamknij")
          onClicked: metaPanelOkno.close()
        }
      }
    }
  }

  FolderListModel {
    id: dcimModel""", "galeria: panel METATAGOW")

assert s.count('{') == s.count('}'), "klamry QML sie rozjechaly"
zapisz(p, s)
print("QfPhotoGallery.qml: OK")
print("GOTOWE: wszystkie trzy czesci zastosowane.")
