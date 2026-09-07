#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — KOPIE ZAPASOWE bazy przy zapisie obiektu.

==========================================================================
PO CO
==========================================================================
07.09.2026 przepadly opisy kilkunastu platow PTR z calego dnia pracy.
Trzy zabezpieczenia zawiodly naraz, bo zadnego nie bylo.

Piotr, tego samego wieczoru: *„Nasza aplikacja musi mieć wewnętrzny backup
przynajmniej plików danych. Są to znikome objętości."*

Ma racje co do objetosci: `dane.gpkg` w PTR wazy 2,8 MB, w PZE 16 MB.
Dziesiec kopii to 30-160 MB przy 50 GB wolnego na telefonie.

==========================================================================
DLACZEGO `VACUUM INTO`, A NIE KOPIOWANIE PLIKU
==========================================================================
Zwykle skopiowanie `dane.gpkg` w trakcie pracy daje **kopie niespojna albo
niepelna**: SQLite trzyma ostatnie zmiany w dzienniku `-wal`, a nie w samym
pliku. Dokladnie to przepadlo 07.09 — dziennik zostal usuniety przed
pobraniem zwrotu.

`VACUUM INTO` to sposob SQLite na spojna kopie DZIALAJACEJ bazy: scala
dziennik, zapisuje jeden plik, nie wymaga zamykania polaczen. Dostepny
od SQLite 3.27.

Kopiowanie `-wal` i `-shm` obok bazy tez by dzialalo, ale trzeba pamietac
o wszystkich trzech plikach naraz — a to wlasnie zawiodlo.

==========================================================================
KIEDY, ILE, GDZIE
==========================================================================
**Kiedy:** po udanym zapisie obiektu, ale nie czesciej niz co 10 minut.
Bez ograniczenia piecdziesiat zapisow w godzine dawaloby piecdziesiat
kopii po 16 MB.

**Ile:** dziesiec ostatnich, rotacyjnie. Starsze kasowane.

**Gdzie:** `kopie/` obok bazy, w katalogu projektu — czyli w tym samym
miejscu, ktore i tak jedzie w zwrocie. Kopia, ktora zostaje na telefonie
po awarii telefonu, nie chroni.

Nazwa niesie date i godzine: `dane_20260907_1834.gpkg`.

==========================================================================
CZEGO TA LATKA NIE ROBI
==========================================================================
**Nie pokazuje kopii w interfejsie.** Przywrocenie wymaga na razie
komputera. To swiadome ograniczenie pierwszego kroku: mechanizm ma sie
najpierw sprawdzic w terenie, zanim dolozymy do niego ekran.

**Nie wysyla na Nextcloud.** Druga warstwa, osobna decyzja — ma inne
ryzyko (brak zasiegu w parku), wiec nie zastepuje kopii lokalnej.

Uruchom w korzeniu repo:  python3 zastosuj_kopie_zapasowe.py
Idempotentna. Kopie: <plik>.przed_kopiami
"""
import os
import shutil
import sys

H = "src/core/utils/qffileutils.h"
C = "src/core/utils/qffileutils.cpp"
FF = "src/gui/qml/QfFeatureForm.qml"

H_KOTWICA = "    Q_INVOKABLE static QString fileEtag( const QString &fileName, int partSize = 8 * 1024 * 1024 );"

H_NOWE = '''    Q_INVOKABLE static QString fileEtag( const QString &fileName, int partSize = 8 * 1024 * 1024 );

    /**
     * Robi spójną kopię bazy GeoPackage do podkatalogu `kopie/` obok niej.
     *
     * Używa `VACUUM INTO` — sposobu SQLite na kopię DZIAŁAJĄCEJ bazy.
     * Zwykłe skopiowanie pliku dałoby kopię bez ostatnich zmian, bo te
     * siedzą w dzienniku `-wal`. Dokładnie to przepadło 07.09.2026:
     * dziennik został usunięty przed pobraniem zwrotu i zniknęła praca
     * całego dnia w terenie.
     *
     * Nazwa kopii niesie datę i godzinę. Starsze niż `ileZachowac`
     * są kasowane — dziesięć kopii bazy PZE to 160 MB przy 50 GB wolnego.
     *
     * \\returns ścieżka do kopii, albo pusty napis gdy się nie udało.
     */
    Q_INVOKABLE static QString kopiaBazy( const QString &sciezkaBazy, int ileZachowac = 10 );'''

C_KOTWICA = "QString QfFileUtils::fileEtag( const QString &fileName, int partSize )"

C_NOWE = r'''QString QfFileUtils::kopiaBazy( const QString &sciezkaBazy, int ileZachowac )
{
  const QFileInfo info( sciezkaBazy );
  if ( !info.exists() )
    return QString();

  QDir katalog( info.absolutePath() );
  if ( !katalog.exists( QStringLiteral( "kopie" ) ) && !katalog.mkdir( QStringLiteral( "kopie" ) ) )
  {
    QgsMessageLog::logMessage( QStringLiteral( "Kopia: nie mogę założyć katalogu kopie/" ),
                               QStringLiteral( "WorkField" ), Qgis::Warning );
    return QString();
  }

  const QString znacznik = QDateTime::currentDateTime().toString( QStringLiteral( "yyyyMMdd_HHmm" ) );
  const QString cel = katalog.absoluteFilePath(
    QStringLiteral( "kopie/%1_%2.gpkg" ).arg( info.completeBaseName(), znacznik ) );

  // Kopia z tej samej minuty juz jest — nie powtarzamy.
  if ( QFile::exists( cel ) )
    return cel;

  sqlite3 *db = nullptr;
  if ( sqlite3_open_v2( sciezkaBazy.toUtf8().constData(), &db, SQLITE_OPEN_READWRITE, nullptr ) != SQLITE_OK )
  {
    if ( db )
      sqlite3_close( db );
    return QString();
  }

  // `VACUUM INTO` scala dziennik i zapisuje spojny plik — bez tego kopia
  // nie mialaby ostatnich zmian.
  const QString sql = QStringLiteral( "VACUUM INTO '%1'" ).arg( QString( cel ).replace( '\'', "''" ) );
  char *blad = nullptr;
  const int wynik = sqlite3_exec( db, sql.toUtf8().constData(), nullptr, nullptr, &blad );
  const QString tresc = blad ? QString::fromUtf8( blad ) : QString();
  if ( blad )
    sqlite3_free( blad );
  sqlite3_close( db );

  if ( wynik != SQLITE_OK )
  {
    QgsMessageLog::logMessage( QStringLiteral( "Kopia nie powiodła się: %1" ).arg( tresc ),
                               QStringLiteral( "WorkField" ), Qgis::Warning );
    QFile::remove( cel );
    return QString();
  }

  // Rotacja: zostawiamy `ileZachowac` najnowszych.
  QDir kopie( katalog.absoluteFilePath( QStringLiteral( "kopie" ) ) );
  QFileInfoList lista = kopie.entryInfoList( QStringList() << QStringLiteral( "*.gpkg" ),
                                             QDir::Files, QDir::Time );
  for ( int i = ileZachowac; i < lista.size(); ++i )
    QFile::remove( lista.at( i ).absoluteFilePath() );

  return cel;
}

'''

FF_KOTWICA = """  function save() {
    if (!model.constraintsHardValid) {
      return false;
    }"""

FF_NOWE = """  //! Kiedy ostatnio zrobiono kopie — zeby nie robic jej przy kazdym zapisie.
  property double ostatniaKopia: 0

  /**
   * Kopia bazy po udanym zapisie, nie czesciej niz co 10 minut.
   *
   * Bez ograniczenia piecdziesiat zapisow w godzine dawaloby piecdziesiat
   * kopii po 16 MB. Dziesiec minut to kompromis: przy awarii traci sie
   * najwyzej kilka obiektow, a nie caly dzien.
   */
  function zrobKopie() {
    const teraz = Date.now();
    const odstep = (settings ? settings.valueInt("WorkField/odstepKopii", 10) : 10) * 60000;
    if (teraz - ostatniaKopia < odstep)
      return;
    const w = model && model.featureModel ? model.featureModel.currentLayer : null;
    if (!w)
      return;
    const zrodlo = String(w.source).split("|")[0];
    if (!zrodlo.endsWith(".gpkg"))
      return;
    const c = QfFileUtils.kopiaBazy(zrodlo, settings ? settings.valueInt("WorkField/ileKopii", 10) : 10);
    if (c !== "")
      ostatniaKopia = teraz;
  }

  function save() {
    if (!model.constraintsHardValid) {
      return false;
    }"""

FF_KOTWICA2 = """    master.ignoreChanges = false;
    return isSuccess;"""

FF_NOWE2 = """    master.ignoreChanges = false;
    if (isSuccess)
      Qt.callLater(zrobKopie);
    return isSuccess;"""


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def zapisz(p, t, opis):
    kopia = p + ".przed_kopiami"
    if not os.path.exists(kopia):
        shutil.copy2(p, kopia)
    open(p, "w", encoding="utf-8").write(t)
    print("   %-30s %s" % (opis, os.path.basename(p)))


def main():
    h, c, f = czytaj(H), czytaj(C), czytaj(FF)

    if "kopiaBazy" in h and "kopiaBazy" in c and "zrobKopie" in f:
        print("Latka juz jest — nic do zrobienia.")
        return

    kotwice = [("naglowek", h, H_KOTWICA, H),
               ("implementacja", c, C_KOTWICA, C),
               ("funkcja save", f, FF_KOTWICA, FF),
               ("koniec save", f, FF_KOTWICA2, FF)]
    for nazwa, tresc, kot, plik in kotwice:
        n = tresc.count(kot)
        if n != 1:
            sys.exit("STOP: kotwica '%s' w %s wystepuje %d razy, oczekiwano 1"
                     % (nazwa, os.path.basename(plik), n))

    print("Kotwice policzone (4/4), nakladam:")

    # Naglowki: `QDir`, `QFileInfo` i `qgsmessagelog.h` juz sa
    # (sprawdzone w repo), brakuje sqlite3 i QDateTime.
    if "#include <sqlite3.h>" not in c:
        c = c.replace("#include <QDir>", "#include <QDateTime>\n#include <QDir>", 1)
        c = c.replace("#include <QStandardPaths>",
                      "#include <QStandardPaths>\n#include <sqlite3.h>", 1)
        print("   dolozone naglowki: QDateTime, sqlite3.h")

    h = h.replace(H_KOTWICA, H_NOWE, 1)
    c = c.replace(C_KOTWICA, C_NOWE + C_KOTWICA, 1)
    f = f.replace(FF_KOTWICA, FF_NOWE, 1)
    f = f.replace(FF_KOTWICA2, FF_NOWE2, 1)

    zapisz(H, h, "czasownik kopiaBazy")
    zapisz(C, c, "implementacja VACUUM INTO")
    zapisz(FF, f, "wolanie po zapisie")

    print("""
DO SPRAWDZENIA — naglowki w qffileutils.cpp:

  grep -n "#include" src/core/utils/qffileutils.cpp | head -20

Potrzebne: <sqlite3.h>, <QDateTime>, <QDir>, <QFileInfo>, qgsmessagelog.h.
Jesli ktoregos brakuje, dopisz — inaczej kompilacja padnie.

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error' | head -5

Sprawdzian:
  1. otworz projekt, zmien cos w obiekcie, zapisz
  2. sprawdz katalog `kopie/` obok dane.gpkg
  3. zapisz drugi obiekt od razu — kopia NIE ma przybyc (odstep 10 minut)

Ustawienia:
  WorkField/odstepKopii   co ile minut (domyslnie 10)
  WorkField/ileKopii      ile zachowac (domyslnie 10)
""")


if __name__ == "__main__":
    main()
