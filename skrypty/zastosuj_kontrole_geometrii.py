#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka — WYKRYCIE ZNISZCZONEJ GEOMETRII i dialog: popraw albo porzuc.

==========================================================================
DWIE AWARIE, JEDEN OBJAW: OBIEKT ZNIKA BEZ SLOWA
==========================================================================

**1. Unikanie nakladania przycina do zera** (21.08.2026, pol dnia terenu).
`AvoidIntersectionsList` obejmowal `platy` I `toposektory`. Toposektory
pokrywaja caly teren, wiec kazdy nowy obiekt byl przycinany do zera.
Piotr rysowal i nic sie nie pojawialo.

W kodzie widac dlaczego nikt sie nie dowiedzial — `qffeaturemodel.cpp:1118`:

    geometry.avoidIntersectionsV2( intersectionLayers, ignoredFeature );

**Wynik jest wyrzucany.** Sasiednie obiekty (l. 1084) maja kontrole
`GeometryOperationResult`, wlasny — nie. A i tak by nie wystarczyla: pusta
geometria NIE JEST bledem z punktu widzenia biblioteki. Ona poprawnie
przycieła do zera. Dlatego kontrola musi patrzec na WYNIKOWA GEOMETRIE,
nie na kod powrotu.

**2. Edycja topologiczna zlepia wierzcholki** (25.08.2026).
`qffeaturemodel.cpp:1489`: wszystkie wierzcholki w promieniu laduja
w jednym punkcie. Przy malym placie obrys zwija sie do zera. W zwrocie:
dwa platy 0,00 x 0,00 m, dwa po 10 cm, jeden 40 cm.

**Obie awarie daja ten sam objaw i zadna nie mowi ani slowa.**

==========================================================================
DLACZEGO ZAPIS, A NIE ODMOWA — decyzja Piotra 25.08
==========================================================================
`applyGeometry()` i `create()` stoja w tej samej galezi, jedno po drugim
(`QgisMobileapp.qml:3856` i `:3861`). Zapis nastepuje natychmiast; dialog
nie zdazy sie pokazac przed nim.

Wstrzymanie zapisu w C++ byloby czystsze, ale dotyka sciezki **wspolnej dla
trzynastu wywolan** `applyGeometry` z QML — a ta dziala. Wiec: obiekt
powstaje, dialog pyta, „porzuc" usuwa go razem z zalacznikami.

To nie pogarsza stanu: dzis takie obiekty **i tak powstaja** (407, 415 sa
w bazie). Dokladamy sprzatanie od razu, zamiast tygodnia pozniej.

==========================================================================
DLACZEGO SYGNAL, A NIE DIALOG PRZY KAZDYM WYWOLANIU
==========================================================================
Trzynascie miejsc wola `applyGeometry`. Podpiecie dialogu przy kazdym to
trzynascie miejsc do utrzymania i pewnosc, ze ktores sie rozjedzie.

C++ wykrywa i emituje; **jeden odbiorca** w QgisMobileapp pokazuje dialog.
Tracker (`QfTrackerSettings.qml:592`, `QfTrackerFeatureForm.qml:32`) moze
sygnal zignorowac — w trybie sledzenia pytanie o zdanie przy kazdym punkcie
byloby katastrofa.

PROG: **0,5 m** obwiedni. Z danych z 25.08 najmniejszy PRAWDZIWY plat ma
1,73 m, a wszystkie uszkodzone ponizej 0,5 — rozdziela je czysto. Jako
wlasciwosc projektu (`WorkField/progObwiedni`), bo przy tyczeniu albo
inwentaryzacji drzew sensowna wartosc jest inna.

Uruchom w korzeniu repo:  python3 zastosuj_kontrole_geometrii.py
Idempotentna. Kopie: <plik>.przed_kontrola_geom
"""
import os
import shutil
import sys

H = "src/core/qffeaturemodel.h"
C = "src/core/qffeaturemodel.cpp"
Q = "src/app/qml/QgisMobileapp.qml"
MARKER = "geometriaZniszczona"

# ------------------------------------------------------------------ naglowek

H_KOTWICA = "    void warning( const QString &text );"

H_NOWE = '''    void warning( const QString &text );

    /**
     * Geometria zapisanego obiektu wyszła pusta albo zwinięta do punktu.
     *
     * \\param powod  `nakladanie` — przycięte przez unikanie nakładania;
     *                `zlepek` — obwiednia poniżej progu (edycja topologiczna)
     * \\param opis   gotowy tekst dla człowieka, z nazwą winnej warstwy
     * \\param bok    dłuższy bok obwiedni w metrach (0 przy pustej geometrii)
     *
     * Sygnał, a nie dialog w miejscu wykrycia: `applyGeometry` jest wołana
     * z trzynastu miejsc w QML. Kto sygnał odbiera, ten decyduje — formularz
     * pokazuje pytanie, tracker zapisuje w dzienniku i jedzie dalej.
     */
    void geometriaZniszczona( const QString &powod, const QString &opis, double bok );'''

# --------------------------------------------------------------- pomocnicza

C_POMOC_KOTWICA = "void QfFeatureModel::applyGeometry( bool fromVertexModel, bool skipTopologicalEditing )"

C_POMOC = r'''namespace
{
  //! Dłuższy bok obwiedni; -1 gdy geometrii nie ma albo jest pusta.
  double bokObwiedni( const QgsGeometry &g )
  {
    if ( g.isNull() || g.isEmpty() )
      return -1.0;
    const QgsRectangle o = g.boundingBox();
    return std::max( o.width(), o.height() );
  }
}

'''

# --------------------------------------- kontrola po unikaniu nakladania

C_NAKL_STARE = '''          QHash<QgsVectorLayer *, QSet<QgsFeatureId>> ignoredFeature;
          ignoredFeature.insert( mLayer, QSet<QgsFeatureId>() << mFeature.id() );
          geometry.avoidIntersectionsV2( intersectionLayers, ignoredFeature );'''

C_NAKL_NOWE = '''          QHash<QgsVectorLayer *, QSet<QgsFeatureId>> ignoredFeature;
          ignoredFeature.insert( mLayer, QSet<QgsFeatureId>() << mFeature.id() );

          // WorkField 25.08.2026 — wynik przycinania BYL WYRZUCANY.
          // Obiekt przycięty do zera znikał bez słowa; 21.08 kosztowało to
          // pół dnia terenu, bo `AvoidIntersectionsList` obejmował warstwę
          // pokrywającą cały teren i NIC nie dawało się narysować.
          //
          // Kontrola patrzy na WYNIKOWĄ GEOMETRIĘ, nie na kod powrotu:
          // z punktu widzenia biblioteki przycięcie do zera to poprawna
          // operacja, nie błąd.
          const double przed = bokObwiedni( geometry );
          geometry.avoidIntersectionsV2( intersectionLayers, ignoredFeature );
          const double po = bokObwiedni( geometry );

          if ( przed > 0 && po < 0 )
          {
            QStringList nazwy;
            for ( QgsVectorLayer *w : std::as_const( intersectionLayers ) )
            {
              if ( w && w != mLayer )
                nazwy << w->name();
            }
            const QString gdzie = nazwy.isEmpty()
                                    ? tr( "innych obiektów tej warstwy" )
                                    : nazwy.join( QStringLiteral( ", " ) );
            emit geometriaZniszczona(
              QStringLiteral( "nakladanie" ),
              tr( "Unikanie nakładania przycięło obiekt DO ZERA — nachodzi "
                  "w całości na: %1.\\n\\nJeśli ta warstwa pokrywa cały teren, "
                  "nie powinna być w liście unikania nakładania." ).arg( gdzie ),
              0.0 );
          }'''

# ---------------------------------- kontrola zlepkow tuz przed zapisem

C_ZLEPEK_STARE = '''  if ( requiresEditing )
  {
    mLayer->commitChanges( !wasEditing );
  }

  mFeature.setGeometry( geometry );
}'''

C_ZLEPEK_NOWE = '''  if ( requiresEditing )
  {
    mLayer->commitChanges( !wasEditing );
  }

  // WorkField 25.08.2026 — obiekt zwinięty do punktu.
  //
  // Edycja topologiczna przesuwa WSZYSTKIE wierzchołki w promieniu na ten
  // sam punkt (l. 1489), więc przy małym obiekcie obrys zwija się do zera.
  // W zwrocie z 25.08: dwa płaty 0,00 × 0,00 m, dwa po 10 cm, jeden 40 cm.
  //
  // Sprawdzane NIEZALEŻNIE od unikania nakładania, bo to inna przyczyna
  // dająca ten sam objaw.
  if ( QgsWkbTypes::geometryType( geometry.wkbType() ) == Qgis::GeometryType::Polygon )
  {
    const double prog = mProject
                          ? mProject->readDoubleEntry( QStringLiteral( "WorkField" ),
                                                       QStringLiteral( "/progObwiedni" ), 0.5 )
                          : 0.5;
    const double bok = bokObwiedni( geometry );
    if ( bok >= 0 && bok < prog )
    {
      emit geometriaZniszczona(
        QStringLiteral( "zlepek" ),
        tr( "Obiekt ma obwiednię %1 m — to nie jest płat, tylko zlepione "
            "wierzchołki.\\n\\nNajczęstsza przyczyna: włączona EDYCJA "
            "TOPOLOGICZNA, która przy małych obiektach ściąga sąsiednie "
            "wierzchołki w jeden punkt." )
          .arg( bok, 0, 'f', 2 ),
        bok );
    }
  }

  mFeature.setGeometry( geometry );
}'''

# ------------------------------------------------------------------- dialog

Q_KOTWICA = '''    onWarning: message => {
      displayToast(message);
    }'''

Q_NOWE = '''    onWarning: message => {
      displayToast(message);
    }

    // WorkField 25.08.2026 — geometria wyszła pusta albo zwinięta do punktu.
    //
    // Toast tu nie wystarczy: znika po sekundzie, a obiekt zostaje w bazie
    // jako śmieć. 25.08 znaleźliśmy czternaście takich, najstarsze sprzed
    // pięciu dni — i cztery z nich miały załączniki, które zostałyby
    // sierotami po ręcznym usunięciu płatu.
    onGeometriaZniszczona: (powod, opis, bok) => {
      dialogZniszczonejGeometrii.powod = powod;
      dialogZniszczonejGeometrii.opis = opis;
      dialogZniszczonejGeometrii.model = overlayFeatureFormDrawer.featureModel;
      dialogZniszczonejGeometrii.open();
    }'''

Q_DIALOG = '''
  // Pytanie po wykryciu zniszczonej geometrii: poprawić czy porzucić.
  //
  // Zapis już nastąpił — `applyGeometry()` i `create()` stoją w tej samej
  // gałęzi, jedno po drugim (:3856 i :3861), więc dialog nie zdąży przed
  // nim. Decyzja Piotra 25.08: obiekt powstaje, a stąd da się go cofnąć.
  Dialog {
    id: dialogZniszczonejGeometrii

    property string powod: ""
    property string opis: ""
    property var model: null

    parent: mainWindow.contentItem
    modal: true
    closePolicy: Popup.NoAutoClose   // decyzja musi zapaść świadomie
    title: qsTr("Geometria nie do użycia")

    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(mainWindow.width - 40, 460)

    contentItem: Text {
      text: dialogZniszczonejGeometrii.opis
      wrapMode: Text.WordWrap
      color: Theme.mainTextColor
      font: Theme.tipFont
    }

    footer: DialogButtonBox {
      Button {
        text: qsTr("Popraw obrys")
        DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
      }
      Button {
        text: qsTr("Porzuć obiekt")
        DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
      }
    }

    onAccepted: {
      // Wracamy do rysowania tej samej warstwy — obrys trzeba nanieść
      // jeszcze raz, ale człowiek wie już, CZEMU poprzedni zniknął.
      close();
      if (stateMachine.state !== "digitize")
        dashBoard.przelaczRysowanie(dashBoard.activeLayer);
    }

    onDiscarded: {
      const m = dialogZniszczonejGeometrii.model;
      if (!m || !m.currentLayer || m.feature.id === undefined) {
        close();
        return;
      }
      const warstwa = m.currentLayer;
      const fid = m.feature.id;

      // Załączniki NAJPIERW — po usunięciu rodzica nie da się ich znaleźć,
      // a zostają w bazie jako sieroty. 25.08 takich było siedem, w tym
      // cztery ze zdjęciami z tego samego dnia.
      const rel = ZalacznikiUtils.relacjaZalacznikow(warstwa);
      let ileZal = 0;
      if (rel.istnieje && rel.warstwa) {
        const iter = LayerUtils.createFeatureIteratorFromExpression(
              rel.warstwa, '"' + rel.poleObce + '" = ' + fid);
        const doUsuniecia = [];
        while (iter.hasNext()) {
          const z = iter.next();
          doUsuniecia.push(z.id);
        }
        iter.close();
        for (let i = 0; i < doUsuniecia.length; i++) {
          // deleteFeature bierze NAJPIERW projekt (qflayerutils.h:400) —
          // sprawdzone w naglowku, bo wywolanie z dwoma argumentami
          // skompilowaloby sie w QML i cicho nic nie robilo.
          if (LayerUtils.deleteFeature(qgisProject, rel.warstwa, doUsuniecia[i]))
            ileZal++;
        }
      }

      const ok = LayerUtils.deleteFeature(qgisProject, warstwa, fid);
      close();
      displayToast(ok
        ? (ileZal > 0
           ? qsTr("Obiekt porzucony razem z %1 załącznikami").arg(ileZal)
           : qsTr("Obiekt porzucony"))
        : qsTr("Nie udało się usunąć obiektu — usuń go ręcznie"),
        ok ? "info" : "warning");
    }
  }
'''


def czytaj(p):
    if not os.path.exists(p):
        sys.exit("STOP: brak %s (uruchom w korzeniu repo)" % p)
    return open(p, encoding="utf-8").read()


def raz(t, kotwica, p, opis):
    n = t.count(kotwica)
    if n != 1:
        sys.exit("STOP: kotwica '%s' w %s wystepuje %d razy, oczekiwano 1"
                 % (opis, os.path.basename(p), n))


def zapisz(p, t, opis):
    kopia = p + ".przed_kontrola_geom"
    if not os.path.exists(kopia):
        shutil.copy2(p, kopia)
    open(p, "w", encoding="utf-8").write(t)
    print("   %-34s %s" % (opis, os.path.basename(p)))


def main():
    h, c, q = czytaj(H), czytaj(C), czytaj(Q)

    # W QML sygnal nazywa sie `onGeometriaZniszczona` — wielka litera po `on`.
    # Znacznik musi byc tym, co naprawde w pliku jest, inaczej druga probe
    # skrypt uzna za latke polowiczna i odmowi.
    stan = [MARKER in h, MARKER in c, "dialogZniszczonejGeometrii" in q]
    if all(stan):
        print("Latka juz jest — nic do zrobienia.")
        return
    if any(stan):
        sys.exit("STOP: latka polowiczna %s. Przywroc kopie .przed_kontrola_geom." % stan)

    raz(h, H_KOTWICA, H, "sygnaly")
    raz(c, C_POMOC_KOTWICA, C, "applyGeometry")
    raz(c, C_NAKL_STARE, C, "unikanie nakladania")
    raz(c, C_ZLEPEK_STARE, C, "koniec applyGeometry")
    raz(q, Q_KOTWICA, Q, "onWarning")

    print("Kotwice policzone (5/5), nakladam:")

    h = h.replace(H_KOTWICA, H_NOWE, 1)
    c = c.replace(C_POMOC_KOTWICA, C_POMOC + C_POMOC_KOTWICA, 1)
    c = c.replace(C_NAKL_STARE, C_NAKL_NOWE, 1)
    c = c.replace(C_ZLEPEK_STARE, C_ZLEPEK_NOWE, 1)
    q = q.replace(Q_KOTWICA, Q_NOWE, 1)

    i = q.rstrip().rfind("}")
    if i < 0:
        sys.exit("STOP: nie znalazlem konca %s" % Q)
    q = q[:i] + Q_DIALOG + q[i:]

    zapisz(H, h, "sygnal geometriaZniszczona")
    zapisz(C, c, "dwie kontrole + pomocnicza")
    zapisz(Q, q, "odbiornik i dialog")

    print("""
DO SPRAWDZENIA PRZED BUILDEM — czasowniki uzyte w dialogu:

  deleteFeature( QgsProject*, QgsVectorLayer*, fid )   — qflayerutils.h:400
  createFeatureIteratorFromExpression( layer, wyrazenie ) — :482

Obie SPRAWDZONE w naglowku przed napisaniem. QML nie kontroluje sygnatur
przy kompilacji, wiec zle wywolanie cicho nic by nie robilo — czyli
dokladnie ten trzeci stan, ktorego unikamy.

Build:
  cmake --build build-sys -j$(nproc) 2>&1 | grep -iE 'error|rcc' | head

Sprawdzian:
  1. wlacz edycje topologiczna, narysuj maly poligon -> dialog „zlepek"
  2. „Popraw obrys"  -> wraca tryb rysowania
  3. powtorz, „Porzuc obiekt" -> obiekt znika razem z zalacznikami
  4. dopisz warstwe pokrywajaca caly teren do unikania nakladania,
     narysuj cokolwiek -> dialog „nakladanie" Z NAZWA tej warstwy
""")


if __name__ == "__main__":
    main()
