import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.qfield
import Theme

/**
 * WFG Studio — zakładka "Studio" szuflady (etap 1, tylko desktop).
 *
 * Rusztowanie świadomie płaskie: lista projektów z drzewa + czasowniki +
 * zapis operacji. Radykalne porządkowanie menu przyjdzie, gdy czasowniki
 * pomieszkają w ręce; wtedy będzie przestawianiem klocków, nie przebudową.
 * Ten sam plik ma kiedyś trafić — toutes proportions gardées — na telefon.
 */
ColumnLayout {
  id: studio
  spacing: 4

  property var wybrany: null

  Settings {
    id: ustawieniaStudia
    category: "WFGStudio"
    // desktop ma szeroki dostęp do dysku, więc korzeń jest ustawialny;
    // domyślnie ~/WorkField — decyzja projektowa z 2026-08-07
    property string korzenProjektow: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/WorkField"
    property string telefonKarta: "/storage/3263-3061/WorkField/data/"
    // drzewo projektów: zwinięte gałęzie (JSON: klucz bramy -> true)
    property string zwinieteJson: '{"archiwum":true,"inne":true}'
  }


  //! WorkField: pozycja menu panelu — ikona Breeze + etykieta z lewej.
  component QfPozycjaMenu: Button {
    id: pozycja

    property string ikona: ""

    flat: true
    Layout.fillWidth: true
    implicitHeight: 34
    font.pointSize: Theme.tinyFont.pointSize

    contentItem: RowLayout {
      spacing: 10

      Image {
        Layout.leftMargin: 6
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        source: pozycja.ikona !== "" ? Theme.getThemeVectorIcon(pozycja.ikona) : ""
        sourceSize: Qt.size(22, 22)
        opacity: pozycja.enabled ? 1.0 : 0.4
      }
      Text {
        Layout.fillWidth: true
        text: pozycja.text
        font: pozycja.font
        color: pozycja.enabled ? Theme.mainTextColor : Theme.secondaryTextColor
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  ProcesyStudio {
    id: procesy
    onLinia: tekst => zapis.dopisz(tekst)
    onZakonczono: kod => {
      zapis.dopisz(kod === 0 ? qsTr("✓ Gotowe") : qsTr("✗ Nie udało się (kod %1) — zapis wyżej").arg(kod));
      studio.przeladuj();
    }
  }

  FolderDialog {
    id: wyborKorzenia
    title: qsTr("Katalog z projektami")
    onAccepted: {
      ustawieniaStudia.korzenProjektow = selectedFolder.toString().replace("file://", "");
      studio.przeladuj();
    }
  }

  // drzewo magazynu: hierarchia Zamawiający → Rok → Obszar → Zlecenie,
  // statusy cyklu życia jako gałęzie w obrębie konaru zlecenia (MAGAZYN.md)
  property var zwiniete: ({})

  function przelaczGalaz(klucz) {
    const z = zwiniete;
    z[klucz] = !z[klucz];
    zwiniete = z;
    ustawieniaStudia.zwinieteJson = JSON.stringify(z);
    przeladuj();
  }

  // człony z konwencji nazw (docs/MAGAZYN.md); szuka w nazwie projektu,
  // a gdy trzeba — w segmentach ścieżki (master/zzw_2026/zzw_pze_2605_inw/projekt)
  function parsujCzlony(p) {
    const segmenty = String(p.gdzie || "").split("/").filter(x => x !== "");
    const kandydaci = [String(p.nazwa || "")].concat(segmenty.slice().reverse());
    let m = null;
    for (const k of kandydaci) {
      m = /^([a-z0-9]+)_([a-z]+)_([0-9]+)_([a-z0-9]+?)(?:_v[0-9]+)?$/.exec(k);
      if (m)
        break;
    }
    if (!m)
      return null;
    let rok = "";
    for (const seg of segmenty) {
      const r = /^[a-z0-9]+_([0-9]{4})$/.exec(seg);
      if (r) {
        rok = r[1];
        break;
      }
    }
    return { zam: m[1], rok: rok !== "" ? rok : qsTr("bez roku"),
             obszar: m[2] + " " + m[3], zadanie: m[4] };
  }

  function przeladuj() {
    const zaznaczona = wybrany ? wybrany.sciezka : "";
    const plaska = procesy.znajdzProjekty(ustawieniaStudia.korzenProjektow, 4);

    let nowyWybrany = null;
    for (const p of plaska)
      if (zaznaczona !== "" && p.sciezka === zaznaczona)
        nowyWybrany = p;

    const STATUSY = [
      { klucz: "wydania",  nazwa: qsTr("Wydane w teren") },
      { klucz: "zwroty",   nazwa: qsTr("Przyjęte z terenu") },
      { klucz: "master",   nazwa: qsTr("Master") },
      { klucz: "archiwum", nazwa: qsTr("Archiwum") }
    ];

    const szablony = [];
    const inne = [];
    const drzewo = {};

    for (const p of plaska) {
      const status = String(p.gdzie || "").split("/")[0];
      if (p.typ === "szablon" || status === "szablony") {
        szablony.push(p);
        continue;
      }
      const c = parsujCzlony(p);
      if (!c || !STATUSY.some(st => st.klucz === status)) {
        inne.push(p);
        continue;
      }
      const a = drzewo[c.zam] = drzewo[c.zam] || {};
      const b = a[c.rok] = a[c.rok] || {};
      const d = b[c.obszar] = b[c.obszar] || {};
      const e = d[c.zadanie] = d[c.zadanie] || {};
      (e[status] = e[status] || []).push(p);
    }

    function policz(wezel) {
      if (Array.isArray(wezel))
        return wezel.length;
      let n = 0;
      for (const k in wezel)
        n += policz(wezel[k]);
      return n;
    }

    function maks(wezel) {
      if (Array.isArray(wezel)) {
        let m = "";
        for (const p of wezel)
          if (String(p.zmodyfikowano) > m)
            m = String(p.zmodyfikowano);
        return m;
      }
      let m = "";
      for (const k in wezel) {
        const v = maks(wezel[k]);
        if (v > m)
          m = v;
      }
      return m;
    }

    const wiersze = [];

    function dodajProjekty(lista, poziom, sortDatami) {
      const posort = lista.slice().sort(function (x, y) {
        if (sortDatami)
          return String(x.zmodyfikowano) < String(y.zmodyfikowano) ? 1 : -1;
        return String(x.nazwa) > String(y.nazwa) ? 1 : -1;
      });
      for (const p of posort)
        wiersze.push(Object.assign({ rodzaj: "projekt", poziom: poziom }, p));
    }

    function dodajZlecenie(etykieta, statusy, poziom, klucz) {
      wiersze.push({ rodzaj: "galaz", poziom: poziom, klucz: klucz,
                     nazwa: etykieta, licznik: policz(statusy) });
      if (zwiniete[klucz])
        return;
      for (const st of STATUSY) {
        const grupa = statusy[st.klucz];
        if (!grupa)
          continue;
        const k2 = klucz + "|" + st.klucz;
        wiersze.push({ rodzaj: "galaz", poziom: poziom + 1, klucz: k2,
                       nazwa: st.nazwa, licznik: grupa.length });
        if (!zwiniete[k2])
          dodajProjekty(grupa, poziom + 2, true);
      }
    }

    // poziomy map: zam -> rok -> obszar -> zadanie (glebokosc 4..1);
    // lancuchy jedynaczek sklejane w JEDEN wspolny wezel-przodek
    function dodajPoziom(wezel, poziom, kluczRodzica, prefiks, glebokosc) {
      const klucze = Object.keys(wezel).sort(function (x, y) {
        return maks(wezel[x]) < maks(wezel[y]) ? 1 : -1;
      });

      if (klucze.length === 1) {
        const et = klucze[0];
        const pelna = prefiks === "" ? et : prefiks + " · " + et;
        const klucz = kluczRodzica === "" ? et : kluczRodzica + "|" + et;
        if (glebokosc === 1)
          dodajZlecenie(pelna, wezel[et], poziom, klucz);
        else
          dodajPoziom(wezel[et], poziom, klucz, pelna, glebokosc - 1);
        return;
      }

      if (prefiks !== "") {
        wiersze.push({ rodzaj: "galaz", poziom: poziom, klucz: kluczRodzica,
                       nazwa: prefiks, licznik: policz(wezel) });
        if (zwiniete[kluczRodzica])
          return;
        poziom = poziom + 1;
      }

      for (const et of klucze) {
        const klucz = kluczRodzica === "" ? et : kluczRodzica + "|" + et;
        if (glebokosc === 1)
          dodajZlecenie(et, wezel[et], poziom, klucz);
        else
          dodajPoziom(wezel[et], poziom, klucz, et, glebokosc - 1);
      }
    }

    if (szablony.length > 0) {
      wiersze.push({ rodzaj: "galaz", poziom: 0, klucz: "szablony",
                     nazwa: qsTr("Szablony"), licznik: szablony.length });
      if (!zwiniete["szablony"])
        dodajProjekty(szablony, 1, false);
    }

    dodajPoziom(drzewo, 0, "", "", 4);

    if (inne.length > 0) {
      wiersze.push({ rodzaj: "galaz", poziom: 0, klucz: "inne",
                     nazwa: qsTr("Inne"), licznik: inne.length });
      if (!zwiniete["inne"])
        dodajProjekty(inne, 1, true);
    }

    listaProjektow.model = wiersze;
    wybrany = nowyWybrany;
  }

  Component.onCompleted: {
    try {
      zwiniete = JSON.parse(ustawieniaStudia.zwinieteJson);
    } catch (e) {
      zwiniete = {};
    }
    przeladuj();
  }

  // ── korzeń drzewa ──────────────────────────────────────────────
  RowLayout {
    Layout.fillWidth: true
    Layout.margins: 8
    spacing: 4

    Text {
      Layout.fillWidth: true
      text: ustawieniaStudia.korzenProjektow
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      elide: Text.ElideMiddle
    }
    Button {
      flat: true
      text: qsTr("Zmień…")
      icon.source: Theme.getThemeVectorIcon("wfg_ustawienia")
      icon.width: 18
      icon.height: 18
      font: Theme.tinyFont
      onClicked: wyborKorzenia.open()
    }
    Button {
      flat: true
      text: qsTr("Odśwież")
      icon.source: Theme.getThemeVectorIcon("wfg_odswiez")
      icon.width: 18
      icon.height: 18
      font: Theme.tinyFont
      onClicked: studio.przeladuj()
    }
  }


  // ── czasowniki: menu akcji na górze sekcji (decyzja 2026-08-10) ──
  Settings {
    id: ustawieniaPaneluM
    category: "WFGPanel"
    property int ukladMenu: 0
  }
  GridLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    columns: ustawieniaPaneluM.ukladMenu === 0 ? 1 : 2
    columnSpacing: 4
    rowSpacing: 2

    QfPozycjaMenu {
      id: przyciskOtworz
      text: qsTr("Otwórz")
      ikona: "wfg_otworz"
      enabled: studio.wybrany && studio.wybrany.qgs !== ""
      onClicked: {
        dashBoard.close();
        iface.loadFile(studio.wybrany.qgs, studio.wybrany.nazwa);
      }
    }
    QfPozycjaMenu {
      text: qsTr("Nowy z szablonu")
      ikona: "wfg_nowe"
      onClicked: kreatorNowego.open()
    }
    QfPozycjaMenu {
      text: qsTr("Zbuduj projekt")
      ikona: "wfg_zbuduj"
      enabled: studio.wybrany && !procesy.dziala
      onClicked: {
        zapis.dopisz(qsTr("Buduję %1 ...").arg(studio.wybrany.nazwa));
        procesy.uruchomPyQgis(studio.wybrany.sciezka + "/zbuduj_projekt.py");
      }
    }
    QfPozycjaMenu {
      text: qsTr("Wyślij na telefon")
      ikona: "wfg_wyslij"
      enabled: studio.wybrany && !procesy.dziala
      onClicked: {
        // droga udowodniona na obecnym APK: zip -> karta -> import z przeglądarki
        const p = studio.wybrany.sciezka;
        const n = studio.wybrany.nazwa;
        zapis.dopisz(qsTr("Pakuję i wysyłam %1 ...").arg(n));
        procesy.uruchomPowloke("set -e; cd '" + p + "'"
          + " && zip -qr '/tmp/" + n + ".zip' . -x 'archiwum/*' '.kosz/*'"
          + " && adb push '/tmp/" + n + ".zip' '" + ustawieniaStudia.telefonKarta + "'"
          + " && echo 'Na telefonie: przeglądarka plików -> WorkField/data -> " + n + ".zip -> import.'");
      }
    }
    QfPozycjaMenu {
      text: qsTr("Zamień na szablon")
      ikona: "wfg_paczka"
      enabled: studio.wybrany && !procesy.dziala
      onClicked: {
        poleNazwySzablonu.text = studio.wybrany.nazwa.replace(/_v[0-9]+$/, "") + "_szablon";
        dialogSzablonu.open();
      }
    }
    QfPozycjaMenu {
      text: qsTr("Przerwij operację")
      ikona: "wfg_przerwij"
      visible: procesy.dziala
      onClicked: procesy.przerwij()
    }
  }

  // ── lista projektów ────────────────────────────────────────────
  ListView {
    id: listaProjektow

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    clip: true
    spacing: 2

    delegate: Rectangle {
      required property var modelData
      required property int index

      readonly property bool wierszGalezi: modelData.rodzaj === "galaz"
      readonly property int wciecie: (modelData.poziom || 0) * 14
      readonly property bool zaznaczony: !wierszGalezi && studio.wybrany
                                         && studio.wybrany.sciezka === modelData.sciezka

      width: listaProjektow.width
      height: (wierszGalezi ? naglowekGalezi.implicitHeight
                            : opisKol.implicitHeight) + 10
      radius: 4
      color: zaznaczony ? Theme.mainColor : "transparent"

      RowLayout {
        id: naglowekGalezi
        visible: wierszGalezi
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 6 + wciecie
        anchors.rightMargin: 6
        spacing: 6

        Text {
          text: wierszGalezi && studio.zwiniete[modelData.klucz] ? "▸" : "▾"
          font: Theme.tipFont
          color: Theme.secondaryTextColor
        }
        Text {
          Layout.fillWidth: true
          text: wierszGalezi ? modelData.nazwa : ""
          font: (modelData.poziom || 0) === 0 ? Theme.strongTipFont : Theme.tipFont
          color: Theme.mainTextColor
          elide: Text.ElideRight
        }
        Text {
          text: wierszGalezi ? modelData.licznik : ""
          font: Theme.tinyFont
          color: Theme.secondaryTextColor
        }
      }

      ColumnLayout {
        id: opisKol
        visible: !wierszGalezi
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 22 + wciecie
        anchors.rightMargin: 6
        spacing: 0

        Text {
          Layout.fillWidth: true
          text: modelData.nazwa || ""
          font: Theme.tipFont
          color: zaznaczony ? "white" : Theme.mainTextColor
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: wierszGalezi ? "" : modelData.typ + " · "
                + modelData.zmodyfikowano.replace("T", " ").substring(0, 16)
                + (modelData.gdzie !== "" ? " · " + modelData.gdzie : "")
          font: Theme.tinyFont
          color: zaznaczony ? "white" : Theme.secondaryTextColor
          elide: Text.ElideRight
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (wierszGalezi)
            studio.przelaczGalaz(modelData.klucz);
          else
            studio.wybrany = modelData;
        }
        onDoubleClicked: {
          if (wierszGalezi)
            return;
          studio.wybrany = modelData;
          przyciskOtworz.clicked();
        }
      }
    }
  }


  // ── zapis operacji ─────────────────────────────────────────────
  Text {
    Layout.leftMargin: 8
    text: qsTr("Zapis operacji")
    font: Theme.tinyFont
    color: Theme.secondaryTextColor
  }
  ScrollView {
    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Layout.bottomMargin: 8
    Layout.preferredHeight: 110
    clip: true

    TextArea {
      id: zapis
      readOnly: true
      wrapMode: TextEdit.Wrap
      font: Theme.tinyFont
      color: Theme.mainTextColor

      function dopisz(tekst) {
        append(tekst);
        cursorPosition = length;
      }
    }
  }

  // ── kreator: nowy projekt z szablonu ───────────────────────────
  Popup {
    id: kreatorNowego

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(420, mainWindow.width - 32)
    modal: true

    onAboutToShow: {
      const szablony = [];
      const wszystkie = procesy.znajdzProjekty(ustawieniaStudia.korzenProjektow, 4);
      for (const p of wszystkie)
        if (p.typ === "szablon")
          szablony.push(p);
      wyborSzablonu.model = szablony;
      poleNazwy.text = "";
    }

    ColumnLayout {
      width: parent.width
      spacing: 8

      Text {
        text: qsTr("Nowy projekt z szablonu")
        font: Theme.strongTipFont
        color: Theme.mainTextColor
      }
      ComboBox {
        id: wyborSzablonu
        Layout.fillWidth: true
        textRole: "nazwa"
      }
      TextField {
        id: poleNazwy
        Layout.fillWidth: true
        placeholderText: qsTr("nazwa, np. zzw_ptr_2603_inw")
      }
      RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        Button {
          flat: true
          text: qsTr("Anuluj")
          onClicked: kreatorNowego.close()
        }
        Button {
          text: qsTr("Utwórz")
          enabled: wyborSzablonu.currentIndex >= 0 && poleNazwy.text.trim() !== ""
          onClicked: {
            const szablon = wyborSzablonu.model[wyborSzablonu.currentIndex];
            const w = procesy.nowyZSzablonu(szablon.sciezka, "", poleNazwy.text,
                                            ustawieniaStudia.korzenProjektow);
            if (w.ok) {
              zapis.dopisz(qsTr("Utworzono %1 (z szablonu %2)").arg(w.sciezka).arg(szablon.nazwa));
              zapis.dopisz(qsTr("Teraz: Zbuduj projekt, potem Wyślij na telefon."));
              kreatorNowego.close();
              studio.przeladuj();
            } else {
              zapis.dopisz(qsTr("✗ %1").arg(w.blad));
            }
          }
        }
      }
    }
  }

  // ── dialog: Zamień na szablon ─────────────────────────────────
  Popup {
    id: dialogSzablonu

    parent: mainWindow.contentItem
    x: (mainWindow.width - width) / 2
    y: (mainWindow.height - height) / 2
    width: Math.min(420, mainWindow.width - 32)
    modal: true

    ColumnLayout {
      width: parent.width
      spacing: 8

      Text {
        text: qsTr("Zamień projekt na szablon")
        font: Theme.strongTipFont
        color: Theme.mainTextColor
      }
      Text {
        Layout.fillWidth: true
        text: studio.wybrany
              ? qsTr("Kopia %1 trafi do szablonów bez części terenowej:\nbez DCIM, zdjęć i foto_tagi; tabele FITO_* zostaną wyczyszczone.\nOryginał pozostanie nietknięty.").arg(studio.wybrany.nazwa)
              : ""
        font: Theme.tinyFont
        color: Theme.secondaryTextColor
        wrapMode: Text.WordWrap
      }
      TextField {
        id: poleNazwySzablonu
        Layout.fillWidth: true
        placeholderText: qsTr("nazwa szablonu")
      }
      RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        Button {
          flat: true
          text: qsTr("Anuluj")
          onClicked: dialogSzablonu.close()
        }
        Button {
          text: qsTr("Utwórz szablon")
          enabled: poleNazwySzablonu.text.trim() !== ""
          onClicked: {
            const w = procesy.zamienNaSzablon(studio.wybrany.sciezka,
                                              ustawieniaStudia.korzenProjektow,
                                              poleNazwySzablonu.text);
            if (w.ok) {
              zapis.dopisz(qsTr("Szablon utworzony: %1 (wyczyszczono tabel FITO: %2)").arg(w.sciezka).arg(w.wyczyszczono));
              dialogSzablonu.close();
              studio.przeladuj();
            } else {
              zapis.dopisz(qsTr("✗ %1").arg(w.blad));
            }
          }
        }
      }
    }
  }
}
