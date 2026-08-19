#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 36 — rampy LOSOWE z lokalnym kontrastem + poprawka koloru nazw.

CZESC A: nazwy ramp niewidoczne na liscie
-----------------------------------------
Objaw ze zrzutu 19.08: nazwy ramp sa jasnoszare na jasnym tle listy.
Przyczyna jest w notatce z 18.08 i dotyczy calej rodziny: LISTE ROZWIJANA
RYSUJE STYL, NIE `Theme`. Tlo popupu bierze sie z `org/kde/desktop`, a ja
wpisalem `Theme.mainTextColor` — kolor tekstu z CIEMNEGO motywu aplikacji.
Jasne na jasnym.

Lek: w liscie brac kolor z palety kontrolki (`palette.text` /
`palette.highlightedText`), czyli z tego samego zrodla co tlo. W ZWINIETYM
polu zostaje `Theme`, bo ono siedzi na naszej powierzchni, nie na popupie
stylu. Dwa konteksty, dwa zrodla koloru — to nie niekonsekwencja, tylko
jedyny sposob, zeby oba byly czytelne.

CZESC B: rampy losowe
---------------------
Rampy ciagle (Viridis, Turbo, Blues) sa zrobione do WARTOSCI: sasiednie
klasy maja z zalozenia podobny kolor, bo blisko na skali = blisko w barwie.
Przy 84 kategoriach platow — czyli danych JAKOSCIOWYCH, gdzie sasiedztwo
na liscie nic nie znaczy — to jest wada, nie zaleta: pol mapy zlewa sie
w jeden odcien zieleni.

Dochodza trzy pozycje na poczatku listy:

  Kontrast (zloty kat)  — deterministyczny. Barwa i-tej kategorii to
      i * 137,507° na kole barw. Zloty kat ma te wlasnosc, ze zadne dwie
      kolejne pozycje nie trafiaja blisko siebie ANI teraz, ANI po
      dolozeniu kolejnych — tak samo jak liscie na lodydze. Do tego
      nasycenie i jasnosc krazy po czterech poziomach, wiec nawet przy
      powtorzeniu barwy odcien jest inny. Ten sam zbior danych da zawsze
      ten sam wynik, wiec mapa nie zmienia sie miedzy sesjami.

  Losowe (kontrast)     — losowe, ale kazdy kolejny kolor wybierany jest
      z 24 kandydatow tak, by byl NAJDALEJ od trzech poprzednich.
      To jest ten "lokalny kontrast": sasiedzi na liscie legendy nigdy
      nie wychodza podobni, a calosc nie wyglada jak gradient.

  Losowe                — czysty los, bez pilnowania sasiedztwa.

Wszystkie trzy dzialaja tez przy PRZEMALOWANIU (applyColorRamp), wiec
zmiana z Turbo na "Losowe (kontrast)" nie odtwarza klasyfikacji.

Uruchom w korzeniu repo:  python3 zastosuj_rampy_losowe.py
Wymaga latek 34 i 35. Idempotentna. Kopie: <plik>.przed_losowymi
"""
import os
import shutil
import sys

C = "src/core/utils/layerutils.cpp"
Q = "src/gui/qml/LayerTreeItemProperties.qml"

MARKER = "syntheticRampColors"

# ------------------------------------------------------------------- C++ czesc

CPP_HELPERS = r'''namespace
{
  const QString RAMPA_ZLOTY_KAT = QStringLiteral( "Kontrast (złoty kąt)" );
  const QString RAMPA_LOSOWA_KONTRAST = QStringLiteral( "Losowe (kontrast)" );
  const QString RAMPA_LOSOWA = QStringLiteral( "Losowe" );

  bool isSyntheticRamp( const QString &name )
  {
    return name == RAMPA_ZLOTY_KAT || name == RAMPA_LOSOWA_KONTRAST || name == RAMPA_LOSOWA;
  }

  //! Odleglosc barw — na tyle dobra, zeby odsiac "podobne", bez pretensji do CIE.
  double colorDistance( const QColor &a, const QColor &b )
  {
    const double dr = a.redF() - b.redF();
    const double dg = a.greenF() - b.greenF();
    const double db = a.blueF() - b.blueF();
    // oko jest najczulsze na zielen, najmniej na blekit
    return 2.0 * dr * dr + 4.0 * dg * dg + 3.0 * db * db;
  }

  /**
   * Kolory dla ramp syntetycznych.
   *
   * Zloty kat: barwa i-tej pozycji to i * 137,507 stopnia. Ta liczba ma
   * wlasnosc, ktorej nie ma zaden podzial rowny — kolejne pozycje nigdy
   * nie trafiaja blisko siebie, niezaleznie od tego, ile ich ostatecznie
   * bedzie. Nasycenie i jasnosc krazy po czterech poziomach, zeby powtorka
   * barwy po pelnym obrocie nie dala powtorki koloru.
   *
   * Losowe (kontrast): kazdy kolejny kolor to najlepszy z 24 kandydatow —
   * najdalszy od trzech poprzednich. Stad "lokalny kontrast": sasiedzi
   * w legendzie sa rozroznialni, a calosc nie uklada sie w gradient.
   */
  QList<QColor> syntheticRampColors( const QString &name, int count )
  {
    QList<QColor> colors;
    if ( count < 1 )
      return colors;

    if ( name == RAMPA_ZLOTY_KAT )
    {
      static const double kat = 137.507764;
      static const double nasycenie[4] = { 0.75, 0.55, 0.85, 0.65 };
      static const double jasnosc[4] = { 0.90, 0.75, 0.65, 0.95 };
      for ( int i = 0; i < count; ++i )
      {
        const double h = std::fmod( i * kat, 360.0 ) / 360.0;
        colors << QColor::fromHsvF( h, nasycenie[i % 4], jasnosc[i % 4] );
      }
      return colors;
    }

    QRandomGenerator *rng = QRandomGenerator::global();
    const bool kontrast = ( name == RAMPA_LOSOWA_KONTRAST );

    for ( int i = 0; i < count; ++i )
    {
      if ( !kontrast )
      {
        colors << QColor::fromHsvF( rng->generateDouble(),
                                    0.55 + rng->generateDouble() * 0.35,
                                    0.65 + rng->generateDouble() * 0.30 );
        continue;
      }

      QColor best;
      double bestScore = -1.0;
      for ( int proba = 0; proba < 24; ++proba )
      {
        const QColor kandydat = QColor::fromHsvF( rng->generateDouble(),
                                                  0.55 + rng->generateDouble() * 0.35,
                                                  0.65 + rng->generateDouble() * 0.30 );
        double score = 10.0;
        const int wstecz = colors.size() < 3 ? static_cast<int>( colors.size() ) : 3;
        for ( int k = 1; k <= wstecz; ++k )
          score = std::min( score, colorDistance( kandydat, colors.at( colors.size() - k ) ) );

        if ( score > bestScore )
        {
          bestScore = score;
          best = kandydat;
        }
      }
      colors << best;
    }
    return colors;
  }

  //! Maluje istniejaca klasyfikacje lista kolorow, bez ruszania podzialu.
  bool paintClassification( QgsVectorLayer *layer, const QString &name )
  {
    if ( QgsCategorizedSymbolRenderer *renderer = dynamic_cast<QgsCategorizedSymbolRenderer *>( layer->renderer() ) )
    {
      const int count = renderer->categories().size();
      const QList<QColor> colors = syntheticRampColors( name, count );
      for ( int i = 0; i < count && i < colors.size(); ++i )
      {
        if ( !renderer->categories().at( i ).symbol() )
          continue;
        std::unique_ptr<QgsSymbol> symbol( renderer->categories().at( i ).symbol()->clone() );
        symbol->setColor( colors.at( i ) );
        renderer->updateCategorySymbol( i, symbol.release() );
      }
      return true;
    }

    if ( QgsGraduatedSymbolRenderer *renderer = dynamic_cast<QgsGraduatedSymbolRenderer *>( layer->renderer() ) )
    {
      const int count = renderer->ranges().size();
      const QList<QColor> colors = syntheticRampColors( name, count );
      for ( int i = 0; i < count && i < colors.size(); ++i )
      {
        if ( !renderer->ranges().at( i ).symbol() )
          continue;
        std::unique_ptr<QgsSymbol> symbol( renderer->ranges().at( i ).symbol()->clone() );
        symbol->setColor( colors.at( i ) );
        renderer->updateRangeSymbol( i, symbol.release() );
      }
      return true;
    }

    return false;
  }
}

'''

CPP_NAMES_OLD = """QVariantList LayerUtils::colorRampNames()
{
  QVariantList result;
  QgsStyle *style = QgsStyle::defaultStyle();"""

CPP_NAMES_NEW = """QVariantList LayerUtils::colorRampNames()
{
  QVariantList result;

  // Rampy syntetyczne na poczatku listy: dane jakosciowe (kategorie) potrzebuja
  // kolorow ROZNYCH, a nie ulozonych w skale. Rampy ciagle robia z 84 kategorii
  // gradient, w ktorym sasiadow nie da sie odroznic.
  result.append( RAMPA_ZLOTY_KAT );
  result.append( RAMPA_LOSOWA_KONTRAST );
  result.append( RAMPA_LOSOWA );

  QgsStyle *style = QgsStyle::defaultStyle();"""

CPP_PREVIEW_OLD = """QVariantList LayerUtils::colorRampPreview( const QString &rampName, int count )
{
  QVariantList result;
  std::unique_ptr<QgsColorRamp> ramp( rampByName( rampName ) );"""

CPP_PREVIEW_NEW = """QVariantList LayerUtils::colorRampPreview( const QString &rampName, int count )
{
  QVariantList result;

  if ( isSyntheticRamp( rampName ) )
  {
    const QList<QColor> colors = syntheticRampColors( rampName, count );
    for ( int i = 0; i < colors.size(); ++i )
      result.append( colors.at( i ) );
    return result;
  }

  std::unique_ptr<QgsColorRamp> ramp( rampByName( rampName ) );"""

CPP_APPLY_OLD = """bool LayerUtils::applyColorRamp( QgsVectorLayer *layer, const QString &rampName )
{
  if ( !layer )
    return false;

  std::unique_ptr<QgsColorRamp> ramp( rampByName( rampName ) );"""

CPP_APPLY_NEW = """bool LayerUtils::applyColorRamp( QgsVectorLayer *layer, const QString &rampName )
{
  if ( !layer )
    return false;

  if ( isSyntheticRamp( rampName ) )
  {
    if ( !paintClassification( layer, rampName ) )
      return false;
    layer->triggerRepaint();
    emit layer->styleChanged();
    return true;
  }

  std::unique_ptr<QgsColorRamp> ramp( rampByName( rampName ) );"""

CPP_INCLUDE_OLD = "#include <qgscolorramp.h>"
CPP_INCLUDE_NEW = "#include <QRandomGenerator>\n#include <cmath>\n#include <qgscolorramp.h>"

# ------------------------------------------------------------------- QML czesc

QML_LABEL_OLD = """                  Text {
                    Layout.fillWidth: true
                    text: rampItem.modelData
                    font: Theme.defaultFont
                    color: Theme.mainTextColor
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                  }"""

QML_LABEL_NEW = """                  Text {
                    Layout.fillWidth: true
                    text: rampItem.modelData
                    font: Theme.defaultFont
                    // WorkField: liste rozwijana rysuje STYL, nie Theme — kolor
                    // tekstu musi pochodzic z tego samego zrodla co tlo popupu,
                    // inaczej wychodzi jasne na jasnym (notatka z 18.08).
                    color: rampItem.highlighted ? rampItem.palette.highlightedText : rampItem.palette.text
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                  }"""

QML_APPLY_OLD = """            symbologyVisible = LayerUtils.hasSimpleSymbology(vl);"""

QML_APPLY_NEW = """            // WorkField: rampy syntetyczne (losowe, zloty kat) nie przechodza
            // przez setCategorizedRenderer — malowanie trzeba dolozyc osobno.
            // Dla ramp zwyklych to powtorzenie tego samego, wiec nieszkodliwe.
            if (mode !== "single")
              LayerUtils.applyColorRamp(vl, pendingRamp);
            symbologyVisible = LayerUtils.hasSimpleSymbology(vl);"""

# ------------------------------------------------------------------ mechanika


def read(path):
    if not os.path.exists(path):
        sys.exit("STOP: brak pliku %s (uruchom w korzeniu repo)" % path)
    with open(path, encoding="utf-8") as f:
        return f.read()


def once(text, anchor, path):
    n = text.count(anchor)
    if n != 1:
        sys.exit("STOP: kotwica w %s wystepuje %d razy, oczekiwano 1:\n  %s"
                 % (path, n, anchor.strip().splitlines()[0]))


def save(path, text, sufiks):
    backup = path + sufiks
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("  zapisano %s (kopia: %s)" % (path, os.path.basename(backup)))


def main():
    c, q = read(C), read(Q)

    if "LayerUtils::colorRampNames" not in c:
        sys.exit("STOP: brak latki 34 (rampy). Naloz ja najpierw.")
    if "rampSwatch" not in q:
        sys.exit("STOP: brak latki 35 (miniatury). Naloz ja najpierw.")

    applied = [MARKER in c, "highlightedText" in q]
    if all(applied):
        print("Latka 36 juz jest — nic do zrobienia.")
        return
    if any(applied):
        sys.exit("STOP: latka nalozona polowicznie %s. Przywroc kopie .przed_losowymi." % applied)

    for anchor in (CPP_INCLUDE_OLD, CPP_NAMES_OLD, CPP_PREVIEW_OLD, CPP_APPLY_OLD):
        once(c, anchor, C)
    for anchor in (QML_LABEL_OLD, QML_APPLY_OLD):
        once(q, anchor, Q)

    print("Kotwice policzone (6/6), nakladam:")

    c = c.replace(CPP_INCLUDE_OLD, CPP_INCLUDE_NEW, 1)
    c = c.replace(CPP_NAMES_OLD, CPP_HELPERS + CPP_NAMES_NEW, 1)
    c = c.replace(CPP_PREVIEW_OLD, CPP_PREVIEW_NEW, 1)
    c = c.replace(CPP_APPLY_OLD, CPP_APPLY_NEW, 1)
    save(C, c, ".przed_losowymi")

    q = q.replace(QML_LABEL_OLD, QML_LABEL_NEW, 1)
    q = q.replace(QML_APPLY_OLD, QML_APPLY_NEW, 1)
    save(Q, q, ".przed_losowymi")

    print("\nGotowe. Trzy nowe pozycje na poczatku listy ramp:")
    print("  Kontrast (złoty kąt) · Losowe (kontrast) · Losowe")
    print("\nBuild:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'rcc|error' | head -20")


if __name__ == "__main__":
    main()
