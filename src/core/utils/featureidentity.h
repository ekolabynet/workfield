/***************************************************************************
  featureidentity.h - FeatureIdentity (WorkField)

 ---------------------
 [WF-IDENTITY] 24.10.2026 — identity of objects and of their attachments.

 `fid` is the row number inside one GeoPackage file, not the identity of the
 object: it changes when returns are merged into the master file, when
 a table is rebuilt, when a release keeps attachments in a separate file.
 The identity is the text field `uuid`, given once when the object is
 created, never typed by hand, and NEW whenever an operation produces
 a new object (duplicate, paste, split, splitting a multipart).
 Attachment tables (`ZAL_*`) keep `PARENT_UUID` next to `ID_RODZICA` — a
 second key that lets the link be rebuilt when `fid` has drifted.

 Decisions: claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md (Piotr).

 Header only, no Q_OBJECT: used from core, gui and app alike without
 touching the build files.
 ***************************************************************************/

/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#ifndef FEATUREIDENTITY_H
#define FEATUREIDENTITY_H

#include <QList>
#include <QString>
#include <QUuid>
#include <qgsfeature.h>
#include <qgsfeatureiterator.h>
#include <qgsfields.h>
#include <qgsproject.h>
#include <qgsrelation.h>
#include <qgsrelationmanager.h>
#include <qgsvectorlayer.h>

namespace FeatureIdentity
{
  //! Field with the identity of a row (objects and attachments alike).
  inline QString uuidFieldName()
  {
    return QStringLiteral( "uuid" );
  }

  //! Field in an attachment table pointing at the `uuid` of its parent.
  inline QString parentUuidFieldName()
  {
    return QStringLiteral( "PARENT_UUID" );
  }

  //! Index of a field by name, case-insensitive; -1 when there is none.
  inline int fieldIndex( const QgsFields &fields, const QString &name )
  {
    for ( int i = 0; i < fields.count(); ++i )
    {
      if ( fields.at( i ).name().compare( name, Qt::CaseInsensitive ) == 0 )
        return i;
    }
    return -1;
  }

  inline int uuidFieldIndex( const QgsFields &fields )
  {
    return fieldIndex( fields, uuidFieldName() );
  }

  //! Fields that are never shown in a form and never copied to another object.
  inline bool isIdentityField( const QString &name )
  {
    return name.compare( uuidFieldName(), Qt::CaseInsensitive ) == 0
           || name.compare( parentUuidFieldName(), Qt::CaseInsensitive ) == 0;
  }

  //! Same format as the QGIS expression uuid(): with braces.
  inline QString newUuid()
  {
    return QUuid::createUuid().toString();
  }

  //! Gives the feature a new identity, when its fields have `uuid`.
  inline bool assignNewUuid( QgsFeature &feature )
  {
    const int index = uuidFieldIndex( feature.fields() );
    if ( index < 0 )
      return false;
    feature.setAttribute( index, newUuid() );
    return true;
  }

  //! Same, on a feature already in the edit buffer of the layer.
  inline bool assignNewUuid( QgsVectorLayer *layer, QgsFeatureId fid )
  {
    if ( !layer )
      return false;
    const int index = uuidFieldIndex( layer->fields() );
    if ( index < 0 )
      return false;
    return layer->changeAttributeValue( fid, index, newUuid() );
  }

  /**
   * Moves the children of \a from (composition relations: attachment tables)
   * onto \a to: the relation keys and, when the child table has it,
   * PARENT_UUID. Changes are left in the edit buffers of the child layers,
   * which are returned so the caller commits or rolls them back.
   *
   * Why: merging objects deletes all but one of them, and the composition
   * relation deletes their attachments together with them — before
   * 24.10.2026 the photos of merged objects lost their link without a word.
   */
  inline QList<QgsVectorLayer *> moveCompositionChildren( QgsProject *project, QgsVectorLayer *layer, const QgsFeature &from, const QgsFeature &to )
  {
    QList<QgsVectorLayer *> touched;
    if ( !project || !layer )
      return touched;

    const int parentUuidIndex = uuidFieldIndex( layer->fields() );
    const QVariant parentUuid = parentUuidIndex >= 0 ? to.attribute( parentUuidIndex ) : QVariant();

    const QList<QgsRelation> relations = project->relationManager()->referencedRelations( layer );
    for ( const QgsRelation &relation : relations )
    {
      if ( relation.strength() != Qgis::RelationshipStrength::Composition )
        continue;
      QgsVectorLayer *child = relation.referencingLayer();
      if ( !child || child == layer )
        continue;

      QList<QgsFeatureId> childIds;
      QgsFeatureIterator it = relation.getRelatedFeatures( from );
      QgsFeature childFeature;
      while ( it.nextFeature( childFeature ) )
        childIds << childFeature.id();
      if ( childIds.isEmpty() )
        continue;

      if ( !child->isEditable() && !child->startEditing() )
        continue;

      const int childParentUuidIndex = fieldIndex( child->fields(), parentUuidFieldName() );
      const QList<QgsRelation::FieldPair> pairs = relation.fieldPairs();
      for ( const QgsFeatureId childId : std::as_const( childIds ) )
      {
        for ( const QgsRelation::FieldPair &pair : pairs )
        {
          const int childIndex = child->fields().lookupField( pair.referencingField() );
          if ( childIndex >= 0 )
            child->changeAttributeValue( childId, childIndex, to.attribute( pair.referencedField() ) );
        }
        if ( childParentUuidIndex >= 0 && parentUuid.isValid() )
          child->changeAttributeValue( childId, childParentUuidIndex, parentUuid );
      }
      if ( !touched.contains( child ) )
        touched << child;
    }
    return touched;
  }
} // namespace FeatureIdentity

#endif // FEATUREIDENTITY_H
