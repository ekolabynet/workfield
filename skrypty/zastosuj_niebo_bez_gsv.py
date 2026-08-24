#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — dziennik Nieba pisze TAKZE, gdy odbiornik nie podaje satelitow.

==========================================================================
KARTA FAKTOW — z danych zwrotu 24.08.2026 i z kodu
==========================================================================

CO SIE STALO W TERENIE

NIEBO_SESJA: jeden wiersz, S_20260824_083319, START 08:33:19, KONIEC 08:33:43.
NIEBO_EPOKA: 205 wierszy, 6 roznych ID_POMIARU, wszystkie POWOD = 'rytm'.
Piotr byl w terenie od okolo 10:00 i logowania nie wylaczal.

Czyli: **24 sekundy zapisu, potem cisza na caly dzien.** Do tego ANI JEDNEGO
wpisu POWOD='obiekt', mimo 11 nowych platow — a zapis przy obiekcie
z zalozenia nie ma wylacznika (claude/NIEBO_dziennik_krok0.md).

CO MOWI KOD

`KONIEC_UTC` jest dopisywane przy KAZDYM udanym zapisie (niebodziennik.cpp:454,
komentarz: "Aplikacja terenowa bywa ubijana przez system"). Czyli 08:33:43 to
**ostatni udany zapis**, nie moment domkniecia sesji. Sesja nie zostala
zamknieta — po prostu przestala cokolwiek przyjmowac.

`zapisz()` ma trzy bramki, WSZYSTKIE PRZED `zapewnijSesje()`:

    1. !mZrodlo                  -> "Dziennik nie jest podpiety do odbiornika"
    2. brak positionInformation  -> "Odbiornik nie podaje pozycji"
    3. satelity.isEmpty()        -> "Odbiornik nie podaje satelitow (brak GSV)"
    4. dopiero teraz zapewnijSesje()

Gdy zamknie sie ktorakolwiek, zapis wychodzi po cichu i nowa sesja nigdy nie
powstaje. `naRytm()` woła `zapisz()` co 5 s przez caly dzien — i za kazdym
razem odbija sie od tej samej bramki.

CZEGO SZUKAMY W DANYCH — poszlaka wskazuje bramke 3

    ODBIORNIK   = 'wbudowany'      (nie Facet)
    KONSTELACJA = '?' we wszystkich 205 wierszach
    HDOP/PDOP   = 0 we wszystkich 205 wierszach

Wbudowany GPS telefonu podawal satelity bez typu konstelacji i bez DOP.
Po podlaczeniu odbiornika zewnetrznego `satellitesInView()` przestal
cokolwiek zwracac — i bramka 3 zamknela wszystko.

==========================================================================
CO ROBI TA LATKA
==========================================================================

1. **Brak GSV nie blokuje juz zapisu.** Zamiast wychodzic, zapisujemy JEDEN
   wiersz z pustymi polami satelitarnymi i `POWOD` z przyrostkiem
   `/bez_gsv`.

   Uzasadnienie: pozycja, DOKLADNOSC_H, N_UZYTYCH i czas nadal cos znacza.
   Bramka 3 blokowala takze zapis przy OBIEKCIE — czyli tracilismy odpowiedz
   na pytanie "dlaczego ten pomiar ma taka dokladnosc" DOKLADNIE WTEDY, gdy
   odbiornik ma klopot, a wiec gdy ta odpowiedz jest najcenniejsza.

   W danych widac wtedy roznice miedzy "nie mierzylem" a "mierzylem, ale nie
   wiem, co bylo na niebie". Dzis te dwa stany wygladaja identycznie: brak
   wierszy.

2. **Przeszkoda trafia takze do logu systemowego** (`qWarning`, prefiks
   "NIEBO:"). Dzis powod milczenia widac wylacznie w panelu Niebo, ktorego
   nikt nie oglada w trakcie pracy. Po lacie wystarczy:

       adb logcat | grep NIEBO:

   To jest ta sama zasada co "objaw niemy jest gorszy od bledu": narzedzie
   ma powiedziec, czego nie umie zrobic.

CZEGO LATKA NIE ROBI

Nie rusza bramek 1 i 2. Bez podpietego zrodla albo bez pozycji nie ma czego
zapisac — pusty wiersz bylby zapisem faktu "aplikacja dziala", a nie pomiaru.

Nie zgaduje, DLACZEGO odbiornik przestal podawac GSV. Po lacie bedzie to
widac: albo pojawia sie wiersze `/bez_gsv` (czyli GSV faktycznie znika), albo
wiersze normalne (czyli przyczyna byla inna i szukamy dalej).

Uruchom w korzeniu repo:  python3 zastosuj_niebo_bez_gsv.py
Idempotentna. Kopia: niebodziennik.cpp.przed_bez_gsv
"""
import os
import shutil
import sys

P = "src/core/utils/niebodziennik.cpp"
MARKER = "bez_gsv"

# ------------------------------------------------------------------ 1. bramka

BRAMKA_STARA = '''  const QList<QgsSatelliteInfo> satelity = info.satellitesInView();
  if ( satelity.isEmpty() )
  {
    ustawPrzeszkode( tr( "Odbiornik nie podaje satelitów (brak depeszy GSV)." ) );
    return 0;
  }
'''

BRAMKA_NOWA = '''  const QList<QgsSatelliteInfo> satelity = info.satellitesInView();

  // WorkField 24.08.2026 — brak GSV NIE blokuje juz zapisu.
  //
  // Do tej pory pusta lista satelitow konczyla metode, i to PRZED
  // zapewnijSesje(). Skutek w terenie: 24 sekundy zapisu z wbudowanego GPS-u,
  // potem cisza na caly dzien, bez jednego wpisu POWOD='obiekt' mimo
  // jedenastu nowych platow.
  //
  // Pozycja, DOKLADNOSC_H, N_UZYTYCH i czas nadal cos znacza. Zapisujemy
  // wiersz z pustymi polami satelitarnymi — wtedy w danych widac roznice
  // miedzy "nie mierzylem" a "mierzylem, ale nie wiem, co bylo na niebie".
  // Dzis oba stany wygladaja identycznie: brak wierszy.
  const bool bezGsv = satelity.isEmpty();
  if ( bezGsv )
    ustawPrzeszkode( tr( "Odbiornik nie podaje satelitów (brak depeszy GSV) — "
                         "zapisuję sam pomiar." ) );
'''

# ------------------------------------------------------------------ 2. powod

POWOD_STARY = '''    zwiazTekst( z, 3, czasZTelefonu ? powod + QStringLiteral( "/czas_telefonu" ) : powod );'''

POWOD_NOWY = '''    zwiazTekst( z, 3, powodPelny );'''

# przygotowanie powodu przed petla
PRZED_PETLA_STARE = '''  wykonaj( mBazaUchwyt, "BEGIN" );
  int zapisanych = 0;
  for ( const QgsSatelliteInfo &sat : satelity )
  {
    sqlite3_reset( z );
    sqlite3_clear_bindings( z );
'''

PRZED_PETLA_NOWE = '''  // Przyrostki POWODU sa skladane RAZ, przed petla: mowia o calym pomiarze,
  // nie o pojedynczym satelicie.
  QString powodPelny = powod;
  if ( czasZTelefonu )
    powodPelny += QStringLiteral( "/czas_telefonu" );
  if ( bezGsv )
    powodPelny += QStringLiteral( "/bez_gsv" );

  wykonaj( mBazaUchwyt, "BEGIN" );
  int zapisanych = 0;

  // Bez GSV robimy JEDEN obrot petli — wiersz opisuje pomiar, nie satelite.
  const int ile = bezGsv ? 1 : satelity.size();
  for ( int i = 0; i < ile; ++i )
  {
    sqlite3_reset( z );
    sqlite3_clear_bindings( z );
'''

# ------------------------------------------------------------- 3. pola satelity

SATELITA_STARE = '''    sqlite3_bind_int( z, 17, sat.id );
    zwiazTekst( z, 18, nazwaKonstelacji( sat.satType ) );
    zwiazDouble( z, 19, sat.azimuth );
    zwiazDouble( z, 20, sat.elevation );
    sqlite3_bind_int( z, 21, sat.signal < 0 ? 0 : sat.signal );
    sqlite3_bind_int( z, 22, sat.inUse ? 1 : 0 );'''

SATELITA_NOWE = '''    // Bez GSV pola 17-22 zostaja NULL. sqlite3_clear_bindings() ustawil je
    // wyzej, wiec wystarczy ich NIE wiazac — pusty wiersz jest wtedy jawny,
    // a nie udawany zerami.
    if ( !bezGsv )
    {
      const QgsSatelliteInfo &sat = satelity.at( i );
      sqlite3_bind_int( z, 17, sat.id );
      zwiazTekst( z, 18, nazwaKonstelacji( sat.satType ) );
      zwiazDouble( z, 19, sat.azimuth );
      zwiazDouble( z, 20, sat.elevation );
      sqlite3_bind_int( z, 21, sat.signal < 0 ? 0 : sat.signal );
      sqlite3_bind_int( z, 22, sat.inUse ? 1 : 0 );
    }'''

# --------------------------------------------------------- 4. przeszkoda do logu

PRZESZKODA_STARA = '''void NieboDziennik::ustawPrzeszkode( const QString &tekst )
{
  if ( mPrzeszkoda == tekst )
    return;
  mPrzeszkoda = tekst;
  emit stanZmieniony();
}'''

PRZESZKODA_NOWA = '''void NieboDziennik::ustawPrzeszkode( const QString &tekst )
{
  if ( mPrzeszkoda == tekst )
    return;
  mPrzeszkoda = tekst;

  // WorkField 24.08.2026 — przeszkoda trafia TAKZE do logu systemowego.
  // Do tej pory powod milczenia dziennika widac bylo wylacznie w panelu
  // Niebo, ktorego nikt nie oglada w trakcie pracy: dzien zbierania danych
  // przepadl, zanim ktokolwiek zauwazyl. Teraz wystarczy:
  //     adb logcat | grep NIEBO:
  if ( tekst.isEmpty() )
    qInfo() << "NIEBO: zapis wznowiony";
  else
    qWarning() << "NIEBO:" << tekst;

  emit stanZmieniony();
}'''


def main():
    if not os.path.exists(P):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % P)

    t = open(P, encoding="utf-8").read()

    if MARKER in t:
        print("Latka juz jest — nic do zrobienia.")
        return

    pary = [("bramka GSV", BRAMKA_STARA, BRAMKA_NOWA),
            ("przygotowanie petli", PRZED_PETLA_STARE, PRZED_PETLA_NOWE),
            ("wiazanie powodu", POWOD_STARY, POWOD_NOWY),
            ("pola satelity", SATELITA_STARE, SATELITA_NOWE),
            ("przeszkoda do logu", PRZESZKODA_STARA, PRZESZKODA_NOWA)]

    for nazwa, stare, _ in pary:
        n = t.count(stare)
        if n != 1:
            sys.exit("STOP: kotwica '%s' wystepuje %d razy, oczekiwano 1" % (nazwa, n))

    print("Kotwice policzone (5/5), nakladam:")
    for nazwa, stare, nowe in pary:
        t = t.replace(stare, nowe, 1)
        print("   %s" % nazwa)

    if "#include <QDebug>" not in t and "#include <QtDebug>" not in t:
        kotwica = "#include <QFileInfo>"
        if t.count(kotwica) == 1:
            t = t.replace(kotwica, "#include <QDebug>\n" + kotwica, 1)
            print("   dolozony #include <QDebug>")
        else:
            print("   UWAGA: dopisz recznie #include <QDebug>")

    kopia = P + ".przed_bez_gsv"
    if not os.path.exists(kopia):
        shutil.copy2(P, kopia)
    open(P, "w", encoding="utf-8").write(t)
    print("  zapisano %s (kopia: %s)" % (P, os.path.basename(kopia)))

    print("\nBuild:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|niebo' | head")
    print("\nSprawdzian w terenie — po dniu pracy:")
    print("  SELECT POWOD, COUNT(DISTINCT ID_POMIARU), COUNT(*)")
    print("    FROM NIEBO_EPOKA GROUP BY POWOD;")
    print("\nCo to znaczy:")
    print("  wiersze /bez_gsv       -> GSV faktycznie znika, przyczyna potwierdzona")
    print("  wiersze normalne       -> GSV jest, milczenie mialo inna przyczyne")
    print("  nadal nic po 08:33     -> bramka 1 albo 2; patrz adb logcat | grep NIEBO:")


if __name__ == "__main__":
    main()
