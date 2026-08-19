import QtCore
import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
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

  readonly property bool naTelefonie: Qt.platform.os === "android" || Qt.platform.os === "ios"

  /**
   * Korzen, po ktorym szukamy zlecen.
   *
   * Komputer: ustawienie z „Zmien..." (domyslnie ~/WorkField).
   * Telefon: katalog danych aplikacji. Domyslne ~/WorkField na Androidzie
   * nie istnieje, a sekcja pokazujaca puste drzewo zamiast powiedziec „nie ma
   * takiego katalogu" jest gorsza niz brak sekcji.
   *
   * To samo zrodlo co QfNoweZadanie.korzenMagazynu() — kreator i drzewo musza
   * patrzec w to samo miejsce, inaczej wychodzi „utworzylem, a nie widze".
   *
   * WLASCIWOSC, NIE FUNKCJA: naglowek sekcji pokazuje te sciezke, a wiazanie
   * do wywolania funkcji nie przeliczyloby sie po zmianie katalogu w „Zmien...".
   */
  readonly property string korzen: naTelefonie ? iface.dataRoot()
                                               : ustawieniaStudia.korzenProjektow

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

    // WorkField 18.08.2026: wlasne tlo NIE jest kosmetyka. Styl pulpitowy
    // rysuje ramke RAZEM Z NAPISEM w delegacie `background`, wiec sam
    // `contentItem` nie zastepowal napisu, tylko dokladal drugi obok
    // (zrzut z 18.08: kazda pozycja menu widoczna dwa razy, z przesunieciem).
    // Pusty background zabiera stylowi miejsce na jego napis.
    background: Rectangle {
      color: pozycja.down ? Qt.rgba(1, 1, 1, 0.14) : pozycja.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
      radius: 4
    }

    property string ikona: ""

    flat: true
    Layout.fillWidth: true
    implicitHeight: 34
    font.pointSize: Theme.tinyFont.pointSize

    contentItem: RowLayout {
      spacing: 10

      Image {
        id: obrazIkony
        source: pozycja.ikona !== "" ? Theme.getThemeVectorIcon(pozycja.ikona) : ""
        sourceSize: Qt.size(22, 22)
        visible: false
      }
      ColorOverlay {
        // MultiEffect.colorization BARWI, ZACHOWUJAC JASNOSC — ciemna ikona
        // Breeze zostawala ciemna takze w ciemnym motywie (17.08.2026).
        // ColorOverlay zamienia piksele na podany kolor, zachowujac alfe.
        Layout.leftMargin: 6
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        source: obrazIkony
        visible: obrazIkony.status === Image.Ready
        color: pozycja.enabled ? Theme.mainTextColor : Theme.secondaryTextColor
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
  // WorkField 18.08.2026 (konsolidacja): stan zlecenia z dziennik/stan.json,
  // ten sam plik co dawne kafle. Klucz: zamawiajacy|obszar id|zadanie.
  //! WorkField 18.08.2026: cel operacji „Zamień na szablon" — {sciezka, nazwa}.
  //! Ustawiany z zewnątrz, bo czynność mieszka teraz w zakładce Projekt
  //! i dotyczy projektu OTWARTEGO, nie zaznaczonego w drzewie.
  property var celSzablonu: null

  //! Publiczne wejście dla zakładki Projekt.
  function zamienNaSzablonDla(sciezka, nazwa) {
    studio.celSzablonu = { "sciezka": sciezka, "nazwa": nazwa };
    poleNazwySzablonu.text = String(nazwa).replace(/_v[0-9]+$/, "") + "_szablon";
    dialogSzablonu.open();
  }

  function wczytajStan() {
    const mapa = {};
    const surowe = procesy.czytajTekst(studio.korzen + "/dziennik/stan.json");
    if (surowe === "")
      return mapa;
    try {
      const s = JSON.parse(surowe);
      const lista = s.zlecenia || [];
      for (const e of lista) {
        const klucz = e.zamawiajacy + "|" + e.obszar + " " + e.id + "|" + e.zadanie;
        mapa[klucz] = e;
      }
    } catch (err) {
      // zły stan.json — po prostu bez wzbogacenia
    }
    return mapa;
  }

  //! jednolinijkowy opis stanu do wiersza zlecenia
  function opisStanu(s) {
    if (!s)
      return "";
    const czesci = [];
    if (s.w_terenie > 0)
      czesci.push(qsTr("w terenie %1").arg(s.w_terenie));
    czesci.push(qsTr("ostatni zwrot: %1").arg(s.ostatni_zwrot && s.ostatni_zwrot !== "" ? s.ostatni_zwrot : "—"));
    if (s.master && s.master.liczniki) {
      const l = s.master.liczniki;
      czesci.push(qsTr("master: topo %1 · płaty %2 · spis %3 · zdj %4")
                  .arg(l.FITO_TOPOSEKTORY || 0).arg(l.FITO_PLATY || 0)
                  .arg(l.FITO_SPIS_GATUNKOWY || 0).arg(l.FITO_ZDJECIA || 0));
    }
    return czesci.join(" · ");
  }

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
    const plaska = procesy.znajdzProjekty(studio.korzen, 4);
    const stanMapa = studio.wczytajStan();

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
      // WorkField 18.08.2026: dokladamy stan z pierwszego projektu zlecenia.
      let stan = null;
      for (const st of STATUSY) {
        const g = statusy[st.klucz];
        if (g && g.length > 0) {
          const c = parsujCzlony(g[0]);
          if (c)
            stan = stanMapa[c.zam + "|" + c.obszar + "|" + c.zadanie] || null;
          break;
        }
      }
      wiersze.push({ rodzaj: "galaz", poziom: poziom, klucz: klucz,
                     nazwa: etykieta, licznik: policz(statusy), stan: stan });
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
      text: studio.korzen
      font: Theme.tinyFont
      color: Theme.secondaryTextColor
      elide: Text.ElideMiddle
    }
    // WorkField 18.08.2026: te dwa przyciski rysowaly ikone przez
    // `icon.source:`, czyli kanalem stylu Material — a nie naszym Theme.
    // Dlatego zostawaly ciemne mimo dwoch wczesniejszych latek na ikony:
    // tamte zmienialy komponenty z wlasnym contentItem, ten wiersz nie.
    // Teraz jedzie tym samym wzorcem co QfPozycjaMenu: ukryty Image +
    // ColorOverlay, kolor z Theme. Styl nie ma juz nic do powiedzenia.
    Button {
      id: przyciskZmien
      flat: true
      // WorkField 18.08.2026: na telefonie FolderDialog nie siega poza
      // katalog aplikacji, wiec ten przycisk obiecywalby cos, czego nie zrobi.
      visible: !studio.naTelefonie

      // WorkField 18.08.2026: patrz komentarz przy QfPozycjaMenu — styl
      // pulpitowy rysuje napis w `background`, wiec musi go tu nie byc.
      background: Rectangle {
        color: przyciskZmien.down ? Qt.rgba(1, 1, 1, 0.14) : przyciskZmien.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
        radius: 4
      }
      text: qsTr("Zmień…")
      font: Theme.tinyFont
      onClicked: wyborKorzenia.open()

      contentItem: RowLayout {
        spacing: 6
        Image {
          id: ikonaZmien
          source: Theme.getThemeVectorIcon("wfg_ustawienia")
          sourceSize: Qt.size(18, 18)
          visible: false
        }
        ColorOverlay {
          Layout.preferredWidth: 18
          Layout.preferredHeight: 18
          source: ikonaZmien
          visible: ikonaZmien.status === Image.Ready
          color: Theme.mainTextColor
        }
        Text {
          text: przyciskZmien.text
          font: przyciskZmien.font
          color: Theme.mainTextColor
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
    Button {
      id: przyciskOdswiez
      flat: true

      // WorkField 18.08.2026: patrz komentarz przy QfPozycjaMenu — styl
      // pulpitowy rysuje napis w `background`, wiec musi go tu nie byc.
      background: Rectangle {
        color: przyciskOdswiez.down ? Qt.rgba(1, 1, 1, 0.14) : przyciskOdswiez.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
        radius: 4
      }
      text: qsTr("Odśwież")
      font: Theme.tinyFont
      onClicked: studio.przeladuj()

      contentItem: RowLayout {
        spacing: 6
        Image {
          id: ikonaOdswiez
          source: Theme.getThemeVectorIcon("wfg_odswiez")
          sourceSize: Qt.size(18, 18)
          visible: false
        }
        ColorOverlay {
          Layout.preferredWidth: 18
          Layout.preferredHeight: 18
          source: ikonaOdswiez
          visible: ikonaOdswiez.status === Image.Ready
          color: Theme.mainTextColor
        }
        Text {
          text: przyciskOdswiez.text
          font: przyciskOdswiez.font
          color: Theme.mainTextColor
          verticalAlignment: Text.AlignVCenter
        }
      }
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
      // WorkField 18.08.2026 (zamiana, uwaga Piotra): zakladka Zlecen
      // zaklada ZLECENIA — od zera, pelne pola. Projekt w ramach zlecenia
      // zaklada sie z zakladki Projekt, gdzie jest kontekst otwartego
      // projektu do odziedziczenia.
      text: qsTr("Nowe zlecenie")
      ikona: "wfg_nowe"
      onClicked: {
        noweZadanie.dziedziczone = null;
        noweZadanie.open();
      }
    }
    // WorkField 17.08.2026: "Zbuduj projekt" USUNIETE. Uruchamialo
    // zbuduj_projekt.py z katalogu szablonu — drugi krok starego swiata,
    // wymagajacy QGIS-a z Pythonem. Projekt z przepisu powstaje kompletny
    // od razu, wiec ta czynnosc nie ma juz czego robic. docs/WYPOSAZENIE.md
    // WorkField 17.08.2026: "Wyslij na telefon" USUNIETE. Pakowalo zipem
    // przez powloke i wolalo adb — zalezne od zainstalowanego adb, wpietego
    // kabla i sciezki do karty. Dublowalo natywne "Wyslij w teren"
    // (QfWymianaLokalna), ktore dziala bez zadnego z tych trzech warunkow.
    // WorkField 18.08.2026: „Zamień na szablon" przeniesione do zakładki
    // Projekt — czynność dotyczy projektu otwartego, nie zaznaczenia w drzewie.
    // Dialog i silnik zostają tutaj; wejściem jest zamienNaSzablonDla().
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
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          Text {
            Layout.fillWidth: true
            text: wierszGalezi ? modelData.nazwa : ""
            font: (modelData.poziom || 0) === 0 ? Theme.strongTipFont : Theme.tipFont
            color: Theme.mainTextColor
            elide: Text.ElideRight
          }
          // WorkField 18.08.2026: stan zlecenia wtopiony w wiersz drzewa —
          // kafle „Stanu zleceń" zlikwidowane (konsolidacja, decyzja Piotra).
          Text {
            Layout.fillWidth: true
            visible: modelData.stan !== undefined && modelData.stan !== null
            text: studio.opisStanu(modelData.stan)
            font: Theme.tinyFont
            color: (modelData.stan && modelData.stan.w_terenie > 0) ? Theme.warningColor : Theme.secondaryTextColor
            elide: Text.ElideRight
          }
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


  // WorkField 18.08.2026: puste drzewo bez tego zdania jest nierozroznialne
  // od zepsutego drzewa. Mowimy WPROST, gdzie szukalismy.
  Text {
    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Layout.bottomMargin: 4
    visible: listaProjektow.count === 0
    text: qsTr("Nie znaleziono żadnych zleceń w:\n%1").arg(studio.korzen)
    font: Theme.tipFont
    color: Theme.secondaryTextColor
    wrapMode: Text.Wrap
  }

  // ── zapis operacji ─────────────────────────────────────────────
  Text {
    Layout.leftMargin: 8
    text: qsTr("Zapis operacji")
    font: Theme.tinyFont
    color: Theme.secondaryTextColor
    // WorkField 18.08.2026: puste pole zabieralo 110 px nalezacych sie drzewu.
    // Pokazuje sie dopiero, gdy cos w nim jest — pierwsza dopisana linia
    // przywoluje je z powrotem, wiec nic nie ginie.
    visible: zapis.length > 0
  }
  ScrollView {
    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Layout.bottomMargin: 8
    Layout.preferredHeight: 110
    clip: true
    visible: zapis.length > 0

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
        text: studio.celSzablonu
              ? qsTr("Kopia %1 trafi do szablonów bez części terenowej:\nbez DCIM, zdjęć i foto_tagi; tabele FITO_* zostaną wyczyszczone.\nOryginał pozostanie nietknięty.").arg(studio.celSzablonu.nazwa)
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
            const w = procesy.zamienNaSzablon(studio.celSzablonu.sciezka,
                                              studio.korzen,
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
