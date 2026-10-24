import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.core // [WF-OBJECT-NUMBER-SETTING] LayerUtils, ProjectUtils, NarzedziaProjektu
import org.qgis
import Theme

/**
 * \ingroup qml
 *
 * WorkField 24.10.2026 — Settings → „Obiekty i zdjęcia” [WF-OBJECT-NUMBER-SETTING].
 *
 * Decisions of Piotr (claude/TOZSAMOSC_obiektow_i_dziennik_2026-10-24.md):
 * what "the number of an object" is — shown read only at the top of every
 * form — is chosen in Settings, on two levels:
 *   - the application default (the user gets used to it): QSettings
 *     WorkField/objectNumberDefault = "auto" | "fid";
 *   - per layer of the open project, when an order needs something else:
 *     layer custom property "workfield/objectNumberField" ("" = as the
 *     default, "fid", or a field name), saved with the project.
 * fid is the row number in one file — it changes when returns are merged —
 * and the page says so where the choice is made.
 *
 * [WF-PHOTO-NAMING] 24.10.2026 — the photo naming convention, the same
 * two levels: QSettings WorkField/photoNaming (application) and the project
 * variable workfield_photo_naming (this project only), both JSON — see
 * ZalacznikiUtils::photoNaming. The quick capture bar and the gallery in the
 * form use the same rule (ZalacznikiUtils::photoPath).
 *
 * Thumbnails and the view cone come to this page in the next steps.
 */
ColumnLayout {
  id: objectsSection

  property var settingsPage

  //! Application default; a property, because reading settings is not reactive.
  property string defaultChoice: settings.value("WorkField/objectNumberDefault", "auto")

  //! [WF-PHOTO-NAMING] The convention in force and the one being edited.
  property var photoNaming: ({})
  property var photoDraft: ({})

  function refreshPhotoNaming() {
    try {
      const naming = ZalacznikiUtils.photoNaming(qgisProject);
      photoNaming = naming;
      photoDraft = {
        "layer": naming.layer === true,
        "number": naming.number === true,
        "note": naming.note === true,
        "folder": String(naming.folder || "object"),
        "ascii": naming.ascii !== false
      };
    } catch (e) {
      console.log("WorkField [WF-PHOTO-NAMING]: refresh failed: " + e);
    }
  }

  function setPhotoDraft(key, value) {
    const draft = Object.assign({}, photoDraft);
    draft[key] = value;
    photoDraft = draft;
  }

  function savePhotoNaming(forProject) {
    const json = JSON.stringify(photoDraft);
    if (forProject) {
      iface.setProjectVariable("workfield_photo_naming", json);
      if (!ProjectUtils.saveProject(qgisProject))
        mainWindow.displayToast(qsTr("Ustawienie zapamiętane, ale projektu NIE zapisano."), "warning");
    } else {
      settings.setValue("WorkField/photoNaming", json);
    }
    console.log("WorkField [WF-PHOTO-NAMING]: saved " + (forProject ? "for the project" : "as the app default") + ": " + json);
    refreshPhotoNaming();
    mainWindow.displayToast(forProject ? qsTr("Nazwy zdjęć: zapisano dla tego projektu") : qsTr("Nazwy zdjęć: zapisano jako domyślne aplikacji"));
  }

  function clearProjectPhotoNaming() {
    iface.setProjectVariable("workfield_photo_naming", "");
    if (!ProjectUtils.saveProject(qgisProject))
      mainWindow.displayToast(qsTr("Ustawienie zdjęte, ale projektu NIE zapisano."), "warning");
    console.log("WorkField [WF-PHOTO-NAMING]: project setting removed");
    refreshPhotoNaming();
  }

  //! Layers people number objects in: vector, editable, not photo tables
  //! and not technical tables.
  property var numberedLayers: []

  function refresh() {
    refreshPhotoNaming();
    try {
      refreshLayers();
    } catch (e) {
      // 24.10.2026: on the desktop the list stayed empty with a project open —
      // an exception here was silent. Now it is in the log.
      console.log("WorkField [WF-OBJECT-NUMBER-SETTING]: refresh failed: " + e);
    }
  }

  function refreshLayers() {
    const result = [];
    const all = qgisProject ? ProjectUtils.mapLayers(qgisProject) : ({});
    for (const id in all) {
      const layer = all[id];
      if (!layer || layer.readOnly === true)
        continue;
      const name = String(layer.name);
      if (/^(zal_|wf_|niebo_|ref_)/i.test(name))
        continue;
      // Raster layers (base maps) are in the same list; layerFields() takes
      // only vector layers — skipped before the call (each failed call put
      // a warning with a stack trace into the log).
      if (layer.type !== Qgis.LayerType.Vector)
        continue;
      let fields = [];
      try {
        fields = LayerUtils.layerFields(layer);
      } catch (e) {
        continue;
      }
      if (!fields || fields.length === 0)
        continue;
      const options = [
        {
          "key": "",
          "text": qsTr("jak domyślnie")
        },
        {
          "key": "fid",
          "text": "fid"
        }
      ];
      for (let i = 0; i < fields.length; i++) {
        const fieldName = String(fields[i].name);
        if (/^(fid|uuid|parent_uuid|geom|geometry)$/i.test(fieldName))
          continue;
        options.push({
          "key": fieldName,
          "text": fieldName
        });
      }
      const current = String(layer.customProperty("workfield/objectNumberField", "") || "");
      let index = 0;
      for (let k = 0; k < options.length; k++) {
        if (options[k].key === current)
          index = k;
      }
      result.push({
        "layer": layer,
        "name": name,
        "options": options,
        "index": index
      });
    }
    result.sort((a, b) => a.name.localeCompare(b.name));
    numberedLayers = result;
    console.log("WorkField [WF-OBJECT-NUMBER-SETTING]: " + result.length + " layers listed");
  }

  // A category page can be created already visible (no change → no signal),
  // so the list is also built on creation and after every project load.
  Component.onCompleted: refresh()

  onVisibleChanged: {
    if (visible)
      refresh();
  }

  Connections {
    target: iface

    function onLoadProjectEnded(path, name) {
      objectsSection.refresh();
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 20
    Layout.rightMargin: 20
    spacing: 10

    Label {
      Layout.fillWidth: true
      Layout.topMargin: 5
      text: qsTr("Obiekty i zdjęcia")
      font: Theme.strongFont
      color: Theme.mainTextColor
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Numer obiektu")
      color: Theme.secondaryTextColor
      font: Theme.strongTipFont
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Numer stoi na samej górze formularza każdego zapisanego obiektu i nie da się go tam zmienić.")
      color: Theme.mainTextColor
      font: Theme.tipFont
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Domyślnie w aplikacji:")
      color: Theme.mainTextColor
      font: Theme.tipFont
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      Repeater {
        model: [
          {
            "key": "auto",
            "text": qsTr("Pole NR, a gdy go nie ma — fid")
          },
          {
            "key": "fid",
            "text": qsTr("Zawsze fid")
          }
        ]

        // Same chips as the size units ([WF-SIZE-UNITS]): the theme marks only
        // a CHECKED button — `highlighted` alone did not show which is chosen.
        delegate: Button {
          id: defaultChip
          required property var modelData
          text: modelData.text
          font: Theme.tipFont
          checkable: true
          highlighted: checked
          checked: objectsSection.defaultChoice === modelData.key
          onClicked: {
            settings.setValue("WorkField/objectNumberDefault", modelData.key);
            objectsSection.defaultChoice = modelData.key;
            // a click toggles `checked` and breaks the binding — restore it
            defaultChip.checked = Qt.binding(() => objectsSection.defaultChoice === defaultChip.modelData.key);
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("fid to numer wiersza w pliku: nadaje go baza przy zapisie i może się zmienić przy scalaniu zwrotów z kilku telefonów. Numer, który ma przetrwać scalanie, trzymaj w osobnym polu (np. NR) i wybierz je poniżej.")
      color: Theme.secondaryTextColor
      font: Theme.tinyFont
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 6
      visible: objectsSection.numberedLayers.length > 0
      text: qsTr("W tym projekcie — dla każdej warstwy osobno:")
      color: Theme.mainTextColor
      font: Theme.tipFont
    }

    Text {
      Layout.fillWidth: true
      visible: objectsSection.numberedLayers.length === 0
      text: qsTr("Otwórz projekt, żeby wybrać numer dla jego warstw.")
      color: Theme.secondaryTextColor
      font: Theme.tipFont
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: objectsSection.numberedLayers

      delegate: RowLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: modelData.name
          color: Theme.mainTextColor
          font: Theme.tipFont
          elide: Text.ElideRight
        }

        ComboBox {
          Layout.preferredWidth: 180
          model: modelData.options
          textRole: "text"
          currentIndex: modelData.index
          font: Theme.tipFont
          // 24.10.2026: the project file had two layers with an EMPTY
          // (type="invalid") value and the choice "stuck". Now the index is
          // taken from the box itself, the key is always text, the value is
          // read back from the layer and the list is rebuilt from what is
          // really stored — so the box never shows something else.
          onActivated: {
            const row = modelData;
            const option = row.options[currentIndex];
            const key = option && option.key !== undefined ? String(option.key) : "";
            NarzedziaProjektu.wlasciwoscWarstwy(row.layer, "workfield/objectNumberField", key);
            const stored = String(row.layer.customProperty("workfield/objectNumberField", "") || "");
            console.log("WorkField [WF-OBJECT-NUMBER-SETTING]: " + row.name + " → \"" + key + "\", stored \"" + stored + "\"");
            if (!ProjectUtils.saveProject(qgisProject))
              mainWindow.displayToast(qsTr("Wybór zapamiętany, ale projektu NIE zapisano."), "warning");
            Qt.callLater(objectsSection.refresh);
          }
        }
      }
    }
    // ---------------------------------------------------------------------
    // [WF-PHOTO-NAMING] Zdjęcia — the naming convention
    // ---------------------------------------------------------------------
    Text {
      Layout.fillWidth: true
      Layout.topMargin: 16
      text: qsTr("Nazwy zdjęć")
      color: Theme.secondaryTextColor
      font: Theme.strongTipFont
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Ta sama nazwa dla zdjęć z paska i z formularza. Zdjęcie jest powiązane z obiektem w tabeli zdjęć — nazwa pliku jest dla ludzi, więc można ją zmienić w każdej chwili.")
      color: Theme.mainTextColor
      font: Theme.tipFont
      wrapMode: Text.WordWrap
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Nazwa składa się z:")
      color: Theme.mainTextColor
      font: Theme.tipFont
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      Repeater {
        model: [
          {
            "key": "layer",
            "text": qsTr("Nazwa warstwy")
          },
          {
            "key": "number",
            "text": qsTr("Nr obiektu")
          },
          {
            "key": "note",
            "text": qsTr("Fragment uwag / opisu")
          }
        ]

        delegate: Button {
          id: partChip
          required property var modelData
          text: modelData.text
          font: Theme.tipFont
          checkable: true
          highlighted: checked
          checked: objectsSection.photoDraft[modelData.key] === true
          onClicked: {
            objectsSection.setPhotoDraft(modelData.key, objectsSection.photoDraft[modelData.key] !== true);
            partChip.checked = Qt.binding(() => objectsSection.photoDraft[partChip.modelData.key] === true);
          }
        }
      }

      Button {
        text: qsTr("Data i czas (zawsze)")
        font: Theme.tipFont
        checkable: true
        checked: true
        highlighted: true
        enabled: false
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Katalog w DCIM:")
      color: Theme.mainTextColor
      font: Theme.tipFont
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      Repeater {
        model: [
          {
            "key": "object",
            "text": qsTr("Osobny na obiekt")
          },
          {
            "key": "layer",
            "text": qsTr("Osobny na warstwę")
          },
          {
            "key": "day",
            "text": qsTr("Osobny na dzień")
          },
          {
            "key": "flat",
            "text": qsTr("Wszystkie razem")
          }
        ]

        delegate: Button {
          id: folderChip
          required property var modelData
          text: modelData.text
          font: Theme.tipFont
          checkable: true
          highlighted: checked
          checked: objectsSection.photoDraft.folder === modelData.key
          onClicked: {
            objectsSection.setPhotoDraft("folder", modelData.key);
            folderChip.checked = Qt.binding(() => objectsSection.photoDraft.folder === folderChip.modelData.key);
          }
        }
      }
    }

    CheckBox {
      id: asciiBox
      Layout.fillWidth: true
      text: qsTr("Bez polskich liter i spacji (bezpieczne dla Windows, ZIP i CAD)")
      font: Theme.tipFont
      checked: objectsSection.photoDraft.ascii !== false
      onClicked: {
        objectsSection.setPhotoDraft("ascii", asciiBox.checked);
        asciiBox.checked = Qt.binding(() => objectsSection.photoDraft.ascii !== false);
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Przykład:")
      color: Theme.mainTextColor
      font: Theme.tipFont
    }

    Text {
      Layout.fillWidth: true
      text: {
        try {
          return ZalacznikiUtils.photoPathExample(objectsSection.photoDraft);
        } catch (e) {
          return "";
        }
      }
      color: Theme.mainColor
      font: Theme.tipFont
      wrapMode: Text.WrapAnywhere
    }

    Text {
      Layout.fillWidth: true
      text: {
        const source = objectsSection.photoNaming.source;
        if (source === "project")
          return qsTr("Teraz obowiązuje: ustawienie tego projektu.");
        if (source === "app")
          return qsTr("Teraz obowiązuje: domyślne aplikacji.");
        return qsTr("Teraz obowiązuje: ustawienie wbudowane (katalog na obiekt, warstwa, nr, data i czas).");
      }
      color: Theme.secondaryTextColor
      font: Theme.tinyFont
      wrapMode: Text.WordWrap
    }

    Flow {
      Layout.fillWidth: true
      spacing: 6

      Button {
        text: qsTr("Zapisz jako domyślne aplikacji")
        font: Theme.tipFont
        onClicked: objectsSection.savePhotoNaming(false)
      }

      Button {
        text: qsTr("Tylko dla tego projektu")
        font: Theme.tipFont
        visible: qgisProject && qgisProject.fileName !== ""
        onClicked: objectsSection.savePhotoNaming(true)
      }

      Button {
        text: qsTr("Zdejmij ustawienie projektu")
        font: Theme.tipFont
        visible: objectsSection.photoNaming.source === "project"
        onClicked: objectsSection.clearProjectPhotoNaming()
      }
    }

    Text {
      Layout.fillWidth: true
      text: qsTr("Zdjęcia już zrobione zostają pod swoimi nazwami. Nr obiektu bierze się z ustawienia „Numer obiektu” powyżej; obiekt jeszcze niezapisany dostaje w nazwie początek swojego identyfikatora.")
      color: Theme.secondaryTextColor
      font: Theme.tinyFont
      wrapMode: Text.WordWrap
    }
  }
}
