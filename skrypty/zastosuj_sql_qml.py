#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — CZASOWNIK `zapytanieSql`: dostep do bazy projektu z QML.

==========================================================================
PO CO
==========================================================================
GeoPackage to plik SQLite, w ktorym poza warstwami siedza **tabele
techniczne**: `rtree_*` (indeks przestrzenny), `gpkg_contents` (rejestr
warstw), `gpkg_extensions`. Dla QML one nie istnieja — widzi warstwy mapy,
nie wewnetrzna kuchnie formatu.

A 07.09.2026 wszystkie trzy naprawy, po ktore trzeba bylo wracac do
komputera, dotyczyly wlasnie tej kuchni:

  * **indeks mial 78 wpisow przy 203 obiektach** — warstwa sie wczytywala,
    „Przybliz do warstwy" dzialalo, a na mapie bylo pusto,
  * **tabele ZAL_ nie byly zarejestrowane** w `gpkg_contents`, wiec QGIS
    ich nie widzial mimo ze istnialy,
  * **`gpkg_extensions` blokowalo** zalozenie nowego indeksu kluczem
    unikalnym po usunietej tabeli.

`LocalStorage` w QML tez jest SQLite, ale tworzy wlasne bazy w katalogu
aplikacji — nie otworzy nim naszego `dane.gpkg`.

==========================================================================
OSTROZNIE
==========================================================================
**To narzedzie ostrzejsze niz reszta.** Pozwala wykonac dowolne polecenie
na bazie, w tym `DELETE` i `DROP TABLE`.

Stad dwa zabezpieczenia wbudowane w sam czasownik:

  * **kopia bazy przed kazdym poleceniem zmieniajacym** — przez
    `kopiaBazy()`, ktora juz mamy; kopia w tej samej minucie nie powtarza
    sie, wiec seria polecen kosztuje jedna,
  * **odmowa dla `ATTACH`** — dolaczenie innej bazy pozwoliloby ominac
    ograniczenie sciezki i pisac gdzie indziej.

Trzecie zabezpieczenie jest po stronie wtyczki: konsola za ustawieniem,
domyslnie wylaczona.

Uruchom w korzeniu repo:  python3 zastosuj_sql_qml.py
Idempotentna. Kopie: <plik>.przed_sql
"""
import os
import shutil
import sys

H = "src/core/utils/qffileutils.h"
C = "src/core/utils/qffileutils.cpp"

H_KOTWICA = "    Q_INVOKABLE static QString kopiaBazy( const QString &sciezkaBazy, int ileZachowac = 10 );"

H_NOWE = H_KOTWICA + '''

    /**
     * Wykonuje polecenie SQL na bazie GeoPackage i zwraca wynik.
     *
     * Otwiera drzwi do tabel technicznych formatu (`rtree_*`,
     * `gpkg_contents`, `gpkg_extensions`), których QML nie widzi — bo to
     * nie są warstwy mapy. Bez tego naprawa indeksu przestrzennego czy
     * rejestracja tabeli wymaga komputera.
     *
     * **Robi kopię bazy przed każdym poleceniem zmieniającym.** Kopia
     * z tej samej minuty nie powtarza się, więc seria poleceń kosztuje
     * jedną.
     *
     * Odmawia `ATTACH` — dołączenie innej bazy pozwoliłoby pisać poza
     * wskazaną ścieżką.
     *
     * \\returns lista wierszy jako mapy nazwa→wartość. Przy błędzie
     *          jednoelementowa lista z kluczem `blad`.
     */
    Q_INVOKABLE static QVariantList zapytanieSql( const QString &sciezkaBazy, const QString &sql );'''

C_KOTWICA = "QString QfFileUtils::kopiaBazy( const QString &sciezkaBazy, int ileZachowac )"

C_NOWE = r'''QVariantList QfFileUtils::zapytanieSql( const QString &sciezkaBazy, const QString &sql )
{
  QVariantList wynik;
  auto blad = [&wynik]( const QString &tresc ) {
    QVariantMap m;
    m[QStringLiteral( "blad" )] = tresc;
    wynik.append( m );
    return wynik;
  };

  if ( !QFile::exists( sciezkaBazy ) )
    return blad( QStringLiteral( "Nie ma pliku: %1" ).arg( sciezkaBazy ) );

  const QString oczyszczony = sql.trimmed();
  if ( oczyszczony.isEmpty() )
    return blad( QStringLiteral( "Puste polecenie" ) );

  // ATTACH pozwolilby dolaczyc inna baze i pisac poza wskazana sciezka —
  // czyli ominac jedyne ograniczenie, jakie ten czasownik ma.
  if ( oczyszczony.contains( QRegularExpression( QStringLiteral( "\\\\bATTACH\\\\b" ),
                                                 QRegularExpression::CaseInsensitiveOption ) ) )
    return blad( QStringLiteral( "ATTACH nie jest dozwolone" ) );

  // Kopia przed kazdym poleceniem, ktore moze cokolwiek zmienic.
  // `kopiaBazy` sama pomija powtorke z tej samej minuty, wiec seria
  // polecen kosztuje jedna kopie.
  static const QRegularExpression zmieniajace(
    QStringLiteral( "^\\\\s*(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|REPLACE|VACUUM|PRAGMA)" ),
    QRegularExpression::CaseInsensitiveOption );
  if ( zmieniajace.match( oczyszczony ).hasMatch() )
  {
    const QString kopia = kopiaBazy( sciezkaBazy );
    if ( kopia.isEmpty() )
      QgsMessageLog::logMessage( QStringLiteral( "SQL: nie udalo sie zrobic kopii przed zmiana" ),
                                 QStringLiteral( "WorkField" ), Qgis::Warning );
  }

  sqlite3 *db = nullptr;
  if ( sqlite3_open_v2( sciezkaBazy.toUtf8().constData(), &db, SQLITE_OPEN_READWRITE, nullptr ) != SQLITE_OK )
  {
    const QString t = db ? QString::fromUtf8( sqlite3_errmsg( db ) ) : QStringLiteral( "?" );
    if ( db )
      sqlite3_close( db );
    return blad( QStringLiteral( "Nie moge otworzyc bazy: %1" ).arg( t ) );
  }

  sqlite3_stmt *stmt = nullptr;
  if ( sqlite3_prepare_v2( db, oczyszczony.toUtf8().constData(), -1, &stmt, nullptr ) != SQLITE_OK )
  {
    const QString t = QString::fromUtf8( sqlite3_errmsg( db ) );
    sqlite3_close( db );
    return blad( t );
  }

  int krok = 0;
  int wierszy = 0;
  while ( ( krok = sqlite3_step( stmt ) ) == SQLITE_ROW )
  {
    QVariantMap w;
    const int kolumn = sqlite3_column_count( stmt );
    for ( int i = 0; i < kolumn; ++i )
    {
      const QString nazwa = QString::fromUtf8( sqlite3_column_name( stmt, i ) );
      switch ( sqlite3_column_type( stmt, i ) )
      {
        case SQLITE_INTEGER:
          w[nazwa] = static_cast<qlonglong>( sqlite3_column_int64( stmt, i ) );
          break;
        case SQLITE_FLOAT:
          w[nazwa] = sqlite3_column_double( stmt, i );
          break;
        case SQLITE_NULL:
          w[nazwa] = QVariant();
          break;
        case SQLITE_BLOB:
          // Geometrie potrafia miec megabajty — pokazujemy rozmiar,
          // nie zawartosc. Konsola ma sluzyc do naprawy, nie do ogladania
          // wspolrzednych.
          w[nazwa] = QStringLiteral( "<%1 B>" ).arg( sqlite3_column_bytes( stmt, i ) );
          break;
        default:
          w[nazwa] = QString::fromUtf8( reinterpret_cast<const char *>( sqlite3_column_text( stmt, i ) ) );
      }
    }
    wynik.append( w );
    // Zabezpieczenie przed wypisaniem calej tabeli na telefonie.
    if ( ++wierszy >= 500 )
    {
      QVariantMap m;
      m[QStringLiteral( "uwaga" )] = QStringLiteral( "obcięte na 500 wierszach" );
      wynik.append( m );
      break;
    }
  }

  const bool ok = ( krok == SQLITE_DONE || krok == SQLITE_ROW );
  const QString tresc = ok ? QString() : QString::fromUtf8( sqlite3_errmsg( db ) );
  const int zmienione = sqlite3_changes( db );
  sqlite3_finalize( stmt );
  sqlite3_close( db );

  if ( !ok )
    return blad( tresc );

  // Polecenia bez wynikow (UPDATE, DELETE) nie zwracaja wierszy — bez tego
  // czlowiek nie wiedzialby, czy cokolwiek sie stalo.
  if ( wynik.isEmpty() )
  {
    QVariantMap m;
    m[QStringLiteral( "zmienionych" )] = zmienione;
    wynik.append( m );
  }
  return wynik;
}

'''


def main():
    for p in (H, C):
        if not os.path.exists(p):
            sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)

    h = open(H, encoding="utf-8").read()
    c = open(C, encoding="utf-8").read()

    if "zapytanieSql" in h:
        print("Latka juz jest — nic do zrobienia.")
        return
    if "kopiaBazy" not in h:
        sys.exit("STOP: najpierw zastosuj_kopie_zapasowe.py — ta latka na niej stoi")

    for nazwa, tresc, kot in (("naglowek", h, H_KOTWICA), ("implementacja", c, C_KOTWICA)):
        n = tresc.count(kot)
        if n != 1:
            sys.exit("STOP: kotwica '%s' wystepuje %d razy, oczekiwano 1" % (nazwa, n))

    print("Kotwice policzone (2/2), nakladam:")

    h = h.replace(H_KOTWICA, H_NOWE, 1)
    c = c.replace(C_KOTWICA, C_NOWE + C_KOTWICA, 1)

    if "#include <QRegularExpression>" not in c:
        c = c.replace("#include <QMimeDatabase>",
                      "#include <QMimeDatabase>\n#include <QRegularExpression>", 1)
        print("   dolozony QRegularExpression")

    for p, t in ((H, h), (C, c)):
        kopia = p + ".przed_sql"
        if not os.path.exists(kopia):
            shutil.copy2(p, kopia)
        open(p, "w", encoding="utf-8").write(t)
        print("   %s" % os.path.basename(p))

    print("""
Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error' | head -5

Do czego to sluzy — przyklady, ktore dzis wymagaly komputera:

  stan indeksu:
    FileUtils.zapytanieSql(baza,
      "SELECT count(*) AS w_indeksie FROM rtree_FITO_PLATY_geom")

  odbudowa (dwa kroki, bo wpis w gpkg_extensions blokuje):
    FileUtils.zapytanieSql(baza,
      "DELETE FROM gpkg_extensions WHERE table_name='FITO_PLATY'")

  rejestracja tabeli bez geometrii:
    FileUtils.zapytanieSql(baza,
      "INSERT OR REPLACE INTO gpkg_contents (table_name,data_type,identifier,"
      "last_change,srs_id) VALUES ('ZAL_PLATY','attributes','ZAL_PLATY',"
      "datetime('now'),NULL)")

Kopia robi sie SAMA przed kazdym poleceniem zmieniajacym.
""")


if __name__ == "__main__":
    main()
