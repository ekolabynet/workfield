#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Latka 30 — wyjscie z pulapki geometrii wieloczesciowej.

DIAGNOZA (sprawdzona w kodzie, nie zgadnieta):
  VertexModel::editingAllowed() == !mIsMulti, a mIsMulti = partCount() > 1
  (vertexmodel.cpp:56 i :233). Edytor wierzcholkow NIE odmawia z powodu
  samoprzeciecia — odmawia wylacznie dlatego, ze obiekt ma dwie czesci.
  qgismobileapp.qml:4964 pokazuje wtedy toast "Editing of multipart
  geometry is not supported yet" i konczy sprawe.

  Toast jest prawdziwy i bezuzyteczny: mowi, ze sie nie da, i nie daje
  drogi wyjscia. Czlowiek w rekawicach zostaje z obiektem, ktorego nie
  moze poprawic ani porzucic.

CO ROBI TA LATKA:
  W miejsce toastu wchodzi okno z dwoma czasownikami i liczbami:

    "Obiekt ma 3 czesci. Edytor wierzcholkow obsluguje pojedyncze."
       [ Scal w jedna ]  [ Rozdziel na osobne ]  [ Anuluj ]

  Scal   — dziala, gdy czesci sie stykaja (unia). Liczba obiektow bez zmian.
  Rozdziel — z jednego obiektu robi N obiektow, atrybuty kopiowane.
             Decyzja Piotra 19.08: dostepne TEZ W TERENIE, bo w biurze
             jest QGIS, a w terenie nie ma nic.

  Obie drogi konczy toast; edycje wierzcholkow otwiera sie ponownie
  recznie. Swiadomie — automatyczne wskoczenie w edytor po zmianie
  geometrii to druga zmiana stanu w jednym gescie.

NOWE CZASOWNIKI (angielskie — konwencja od 19.08):
  mergeParts( layer, fid, write )  -> { ok, partsBefore, partsAfter, message }
  splitParts( layer, fid, write )  -> { ok, parts, created, message }

  Zalaczniki ZAL_ zostaja przy pierwotnym obiekcie — nowe czesci ida bez
  nich. Kopiowanie wierszy zalacznikow wskazywaloby dwa obiekty na ten sam
  plik; przepiecie zdjecia to decyzja czlowieka, nie skutek uboczny.

Uruchom w korzeniu repo:  python3 zastosuj_geometria_czesci.py
Wymaga latki 29. Idempotentna. Kopie: <plik>.przed_czesciami
"""
import os
import shutil
import sys

H = "src/core/utils/narzedziaprojektu.h"
C = "src/core/utils/narzedziaprojektu.cpp"
Q = "src/app/qml/qgismobileapp.qml"

MARKER = "mergeParts"

# ------------------------------------------------------------------ deklaracje

DECLARATIONS = '''    /**
     * Scala czesci obiektu wieloczesciowego w jedna (unia). Zwraca mape:
     *   ok           bool
     *   partsBefore  int
     *   partsAfter   int
     *   message      QString
     *
     * Gdy czesci sie nie stykaja, unia nadal ma wiecej niz jedna czesc —
     * wtedy nic nie zapisujemy i mowimy to wprost.
     */
    Q_INVOKABLE QVariantMap mergeParts( QgsVectorLayer *layer, QgsFeatureId fid, bool write = true ) const;

    /**
     * Rozdziela obiekt wieloczesciowy na osobne obiekty. Pierwsza czesc
     * zostaje na istniejacym fid, pozostale staja sie nowymi obiektami
     * z kopia atrybutow (klucze glowne wyzerowane). Zwraca mape:
     *   ok       bool
     *   parts    int           na ile czesci rozdzielono
     *   created  QVariantList  fid nowych obiektow
     *   message  QString
     *
     * Zalaczniki zostaja przy pierwotnym obiekcie.
     */
    Q_INVOKABLE QVariantMap splitParts( QgsVectorLayer *layer, QgsFeatureId fid, bool write = true ) const;

'''

# --------------------------------------------------------------- implementacje

IMPLEMENTATIONS = r'''
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

    if ( layer->addFeature( copy ) )
      created << QVariant::fromValue( static_cast<qlonglong>( copy.id() ) );
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
  result.insert( QStringLiteral( "message" ), done
                                                ? tr( "Rozdzielono na %1 obiektów. Załączniki zostały przy pierwszym." ).arg( parts.size() )
                                                : tr( "Rozdzielenie częściowe: powstało %1 z %2 obiektów." ).arg( created.size() + 1 ).arg( parts.size() ) );
  return result;
}
'''

# ------------------------------------------------------------------------ QML

QML_OLD = '''        displayToast(qsTr("Editing of multipart geometry is not supported yet."), 'warning');
        geometryEditingVertexModel.clear();'''

QML_NEW = '''        // WorkField: multipart nie jest slepa uliczka — okno daje dwie drogi
        multipartGeometryDialog.targetLayer = featureListForm.selection.focusedLayer;
        multipartGeometryDialog.targetFid = featureListForm.selection.focusedFeature.id;
        multipartGeometryDialog.partCount = NarzedziaProjektu.sprawdzGeometrie(featureListForm.selection.focusedLayer, featureListForm.selection.focusedFeature.id).czesci;
        multipartGeometryDialog.open();
        geometryEditingVertexModel.clear();'''

QML_ANCHOR = '''  QfDialog {
    id: importPermissionDialog'''

QML_DIALOG = '''  // WorkField: wyjscie z geometrii wieloczesciowej (patrz latka 30).
  // Edytor wierzcholkow obsluguje wylacznie obiekty jednoczesciowe
  // (VertexModel::editingAllowed == !mIsMulti), wiec zamiast komunikatu
  // bez wyjscia dajemy dwa czasowniki, ktore ten stan zdejmuja.
  QfDialog {
    id: multipartGeometryDialog
    parent: mainWindow.contentItem
    z: 10000

    width: Math.min(mainWindow.width - Theme.popupScreenEdgeVerticalMargin * 2, 400)

    property var targetLayer: null
    property var targetFid: -1
    property int partCount: 0

    title: qsTr("Geometria wieloczęściowa")

    Column {
      width: parent.width
      spacing: 12

      Label {
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.mainTextColor
        text: qsTr("Obiekt składa się z %1 części. Edytor wierzchołków obsługuje tylko obiekty jednoczęściowe.").arg(multipartGeometryDialog.partCount)
      }

      QfButton {
        width: parent.width
        text: qsTr("Scal w jedną część")
        onClicked: {
          const wynik = NarzedziaProjektu.mergeParts(multipartGeometryDialog.targetLayer, multipartGeometryDialog.targetFid, true);
          displayToast(wynik.message, wynik.ok ? 'info' : 'warning');
          multipartGeometryDialog.close();
        }
      }

      QfButton {
        width: parent.width
        text: qsTr("Rozdziel na osobne obiekty")
        onClicked: {
          const wynik = NarzedziaProjektu.splitParts(multipartGeometryDialog.targetLayer, multipartGeometryDialog.targetFid, true);
          displayToast(wynik.message, wynik.ok ? 'info' : 'warning');
          multipartGeometryDialog.close();
        }
      }

      Label {
        width: parent.width
        wrapMode: Text.WordWrap
        font: Theme.tipFont
        color: Theme.secondaryTextColor
        text: qsTr("Scalanie działa, gdy części się stykają. Rozdzielenie kopiuje atrybuty; załączniki zostają przy pierwszym obiekcie.")
      }
    }

    standardButtons: Dialog.Cancel
  }

'''

# ------------------------------------------------------------------- mechanika

ANCHOR_H = "    // -------------------------------------------------------------- geometria"


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


def save(path, text):
    backup = path + ".przed_czesciami"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("  zapisano %s (kopia: %s)" % (path, os.path.basename(backup)))


def main():
    h, c, q = read(H), read(C), read(Q)

    if "sprawdzGeometrie" not in h:
        sys.exit("STOP: brak latki 29 (czasowniki geometrii). Nalozy ja najpierw.")

    applied = [MARKER in h, MARKER in c, "multipartGeometryDialog" in q]
    if all(applied):
        print("Latka 30 juz jest — nic do zrobienia.")
        return
    if any(applied):
        sys.exit("STOP: latka nalozona polowicznie %s. Przywroc kopie .przed_czesciami." % applied)

    once(h, ANCHOR_H, H)
    once(q, QML_OLD, Q)
    once(q, QML_ANCHOR, Q)

    print("Kotwice policzone, nakladam:")

    # naglowek: nowe deklaracje na poczatku sekcji geometrii
    h = h.replace(ANCHOR_H, ANCHOR_H + "\n\n" + DECLARATIONS.rstrip("\n") + "\n", 1)
    save(H, h)

    if not c.endswith("\n"):
        c += "\n"
    c += IMPLEMENTATIONS
    save(C, c)

    q = q.replace(QML_OLD, QML_NEW, 1)
    q = q.replace(QML_ANCHOR, QML_DIALOG + QML_ANCHOR, 1)
    save(Q, q)

    print("\nGotowe. Toast o multipart zastapiony oknem z dwoma czasownikami.")
    print("Build desktop:")
    print("  cmake --build build-sys -j$(nproc) 2>&1 | tail -30")
    print("Po buildzie sprawdz w logu: 'Running rcc for resource' (zmiana w QML).")


if __name__ == "__main__":
    main()
