import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qfield.gui // [WF-WINDOW-FRAME] QfWindowFrame
import Theme

/**
 * \ingroup qml
 *
 * WorkField 21.09.2026 — NMT, NMPT i CHM w JEDNYM oknie.
 *
 * Wcześniej były trzy osobne pozycje menu i do tego osobne okno „Zakres
 * pobierania”, choć to jedna czynność w trzech odmianach: pobierz model
 * terenu, pobierz model pokrycia, odejmij jeden od drugiego. Wybór odmiany
 * stoi na górze, a niżej zmienia się tylko to, co dla niej istotne.
 *
 * Samo pobieranie zostaje tam, gdzie było (pobieracz w QfMainDrawer) — tutaj
 * jest wybór i jedno wywołanie: dashBoard.pobierzDemZakres().
 *
 * Nazwa obszaru wchodzi wstępnie z poprzedniego pobrania i to jest celowe:
 * CHM dobiera arkusze NMT i NMPT po TEJ SAMEJ nazwie obszaru. Zmiana nazwy
 * między jednym pobraniem a drugim rozrywa parę.
 */
// [WF-WINDOW-FRAME] 24.10.2026 — common frame: ✕/✓ in the title bar, scrolling body
QfWindowFrame {
  id: oknoDaneWysokosciowe

  title: oknoDaneWysokosciowe.rodzaj === "ORTO" ? qsTr("Ortofotomapa GUGiK") : qsTr("Dane wysokościowe")
  confirmText: oknoDaneWysokosciowe.rodzaj === "ORTO" ? (oknoDaneWysokosciowe.ortoPracuje ? qsTr("Pracuję…") : oknoDaneWysokosciowe.ortoWybrany >= 0 ? qsTr("Pobierz ortofoto (%1)").arg(oknoDaneWysokosciowe.ortoMb(oknoDaneWysokosciowe.ortoNaloty[oknoDaneWysokosciowe.ortoWybrany].mb)) : qsTr("Pobierz ortofoto")) : oknoDaneWysokosciowe.rodzaj === "CHM" ? qsTr("Policz CHM") : oknoDaneWysokosciowe.rodzaj === "WARSTWICE" ? qsTr("Policz warstwice") : qsTr("Pobierz %1").arg(oknoDaneWysokosciowe.rodzaj)
  confirmEnabled: oknoDaneWysokosciowe.rodzaj !== "ORTO" || (oknoDaneWysokosciowe.ortoWybrany >= 0 && !oknoDaneWysokosciowe.ortoPracuje && !oknoDaneWysokosciowe.ortoSzuka)
  preferredWidth: 460
  onConfirmed: confirm()

  // [WF-WINDOW-FRAME] ✓ in the title bar (was the download / compute button below)
  function confirm() {
    const rodzaj = oknoDaneWysokosciowe.rodzaj;
    const nazwa = poleObszaru.text.trim();
    const najnowsze = oknoDaneWysokosciowe.najnowsze;
    const odstep = parseFloat(String(poleOdstepu.text).replace(",", "."));
    if (rodzaj === "ORTO") {
      // Okno zostaje otwarte: pokazuje postęp. Praca idzie dalej
      // także po jego zamknięciu.
      oknoDaneWysokosciowe.ortoPobierz(nazwa);
      return;
    }
    oknoDaneWysokosciowe.close();
    if (rodzaj === "CHM")
      dashBoard.computeChmAction();
    else if (rodzaj === "WARSTWICE")
      oknoDaneWysokosciowe.policzWarstwice(isNaN(odstep) || odstep <= 0 ? 0.5 : odstep);
    else
      dashBoard.pobierzDemZakres(rodzaj, nazwa, najnowsze);
  }

  property var t: Theme

  //! "NMT", "NMPT" albo "CHM"
  property string rodzaj: "NMT"

  //! Skorowidze GUGiK dzielą arkusze na roczniki; domyślnie tylko najnowsze.
  property bool najnowsze: true

  // ══ WorkFieldGIS 16.10.2026 — ORTOFOTO ═══════════════════════════════
  //
  // Trzecia rzecz z GUGiK obok NMT i NMPT, w tym samym oknie („wejść wiele,
  // okno jedno”). Przebieg:
  //   1. skorowidz WFS (warstwa na rocznik, gugik:SkorowidzOrtofomapyRRRR)
  //      dla widoku mapy -> lista NALOTÓW: rok + kolor + piksel + układ;
  //   2. domyślnie najnowszy rok, RGB, najmniejszy piksel; do zmiany;
  //   3. arkusze pobierane PO JEDNYM (downloadFile trzyma cały plik w pamięci,
  //      arkusz 0,05 m waży ~1 GB); arkusz, który już leży w ORTO/, jest
  //      pomijany, więc przerwane pobieranie da się wznowić;
  //   4. iface.ortofotoDoGpkg składa w tle GPKG z kaflami i podglądami;
  //   5. podkład na dół projektu, metryczka .txt obok, arkusze usunięte.
  //
  // Pola skorowidza zobaczone w odpowiedzi usługi 16.10.2026 (sonda_orto_wfs.sh,
  // Nakło): godlo, akt_rok, piksel, kolor, uklad_xy, akt_data, url_do_pobrania,
  // wlk_pliku_mb. Stan pobierania żyje w tym obiekcie, nie w widoku — okno
  // można zamknąć, a praca idzie dalej.

  readonly property string ortoUsluga: "https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WFS/Skorowidze"
  //! Starsze roczniki to zdjęcia czarno-białe o pikselu 0,5–1 m; nie pytamy o nie.
  readonly property int ortoOdRoku: 2005

  property var ortoNaloty: []
  property int ortoWybrany: -1
  property string ortoStan: ""
  property bool ortoSzuka: false
  property var ortoBbox: null

  // praca w toku (pobieranie i składanie)
  property var ortoKolejka: []
  property int ortoIndeks: -1
  property var ortoPliki: []
  property var ortoNalot: null
  property string ortoObszar: ""
  property int ortoProby: 0
  property bool ortoPracuje: false

  function ortoMb(mb) {
    return mb >= 1024 ? (mb / 1024).toFixed(1).replace(".", ",") + " GB" : Math.round(mb) + " MB";
  }

  function ortoOpis(n) {
    return n.rok + " · " + n.kolor + " · " + String(n.piksel).replace(".", ",") + " m · " + n.arkusze.length + qsTr(" ark. · ") + ortoMb(n.mb);
  }

  function ortoPole(blok, nazwa) {
    const m = blok.match(new RegExp("<gugik:" + nazwa + "[^>]*>([\\s\\S]*?)</gugik:" + nazwa + ">"));
    return m ? m[1].replace(/<[^>]+>/g, "").trim() : "";
  }

  //! Krok 1: zasięg widoku mapy -> lista roczników z GetCapabilities.
  function ortoSzukaj() {
    if (ortoSzuka || ortoPracuje)
      return;
    const punkty = iface.visibleExtentPointsIn2180(dashBoard.mapSettings, 2);
    if (punkty.length === 0) {
      ortoStan = qsTr("Nie udało się wyznaczyć zasięgu mapy");
      return;
    }
    let x0 = punkty[0].x, y0 = punkty[0].y, x1 = punkty[0].x, y1 = punkty[0].y;
    for (const p of punkty) {
      x0 = Math.min(x0, p.x);
      y0 = Math.min(y0, p.y);
      x1 = Math.max(x1, p.x);
      y1 = Math.max(y1, p.y);
    }
    ortoBbox = { "xmin": x0, "ymin": y0, "xmax": x1, "ymax": y1 };
    ortoNaloty = [];
    ortoWybrany = -1;
    ortoSzuka = true;
    ortoStan = qsTr("Pytam GUGiK o roczniki…");
    const xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return;
      const lata = [];
      const nazwy = xhr.responseText.match(/gugik:SkorowidzOrtofomapy\d{4}/g) || [];
      for (const n of nazwy) {
        const rok = parseInt(n.slice(-4));
        if (rok >= ortoOdRoku && lata.indexOf(rok) === -1)
          lata.push(rok);
      }
      lata.sort(function (a, b) {
        return b - a;
      });
      console.log("WFG orto: roczniki " + lata.join(","));
      if (lata.length === 0) {
        ortoSzuka = false;
        ortoStan = qsTr("Usługa GUGiK nie odpowiedziała listą roczników (HTTP %1)").arg(xhr.status);
        return;
      }
      ortoPytajRok(lata, 0, {});
    };
    xhr.open("GET", ortoUsluga + "?SERVICE=WFS&REQUEST=GetCapabilities&VERSION=2.0.0");
    xhr.send();
  }

  //! Krok 1b: jeden rocznik = jedno zapytanie GetFeature w zasięgu.
  function ortoPytajRok(lata, i, grupy) {
    if (i >= lata.length) {
      ortoZamknijListe(grupy);
      return;
    }
    ortoStan = qsTr("Szukam nalotów: rocznik %1 (%2 z %3)…").arg(lata[i]).arg(i + 1).arg(lata.length);
    // WFS 2.0 z układem w zapisie urn: kolejność osi PÓŁNOC, WSCHÓD
    // (sprawdzone sondą 16.10 — tak odpowiada usługa).
    const b = ortoBbox;
    const bbox = b.ymin.toFixed(1) + "," + b.xmin.toFixed(1) + "," + b.ymax.toFixed(1) + "," + b.xmax.toFixed(1) + ",urn:ogc:def:crs:EPSG::2180";
    const url = ortoUsluga + "?SERVICE=WFS&REQUEST=GetFeature&VERSION=2.0.0&TYPENAMES=gugik:SkorowidzOrtofomapy" + lata[i] + "&COUNT=5000&SRSNAME=urn:ogc:def:crs:EPSG::2180&BBOX=" + bbox;
    const xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return;
      const bloki = xhr.responseText.split(/<wfs:member>/).slice(1);
      for (const blok of bloki) {
        const url = ortoPole(blok, "url_do_pobrania");
        if (url === "")
          continue;
        const a = {
          "godlo": ortoPole(blok, "godlo"),
          "data": ortoPole(blok, "akt_data"),
          "url": url,
          "plik": url.split("/").pop(),
          "mb": parseFloat(ortoPole(blok, "wlk_pliku_mb")) || 0
        };
        const kolor = ortoPole(blok, "kolor") || "?";
        const piksel = parseFloat(ortoPole(blok, "piksel")) || 0;
        const uklad = ortoPole(blok, "uklad_xy") || "?";
        const rok = ortoPole(blok, "akt_rok") || String(lata[i]);
        const klucz = rok + "|" + kolor + "|" + piksel + "|" + uklad;
        if (!grupy[klucz])
          grupy[klucz] = { "rok": rok, "kolor": kolor, "piksel": piksel, "uklad": uklad, "godla": {} };
        // To samo godło dwa razy w jednym nalocie (np. dwa dni lotu):
        // bierzemy nowszy arkusz — mozaika ma mieć jedno zdjęcie na miejsce.
        const dotad = grupy[klucz].godla[a.godlo];
        if (!dotad || a.data > dotad.data)
          grupy[klucz].godla[a.godlo] = a;
      }
      ortoPytajRok(lata, i + 1, grupy);
    };
    xhr.open("GET", url);
    xhr.send();
  }

  //! Krok 2: grupy -> lista, kolejność: rok malejąco, RGB przed CIR, piksel rosnąco.
  function ortoZamknijListe(grupy) {
    const lista = [];
    for (const k in grupy) {
      const g = grupy[k];
      const arkusze = [];
      let mb = 0, od = "", doo = "";
      for (const godlo in g.godla) {
        const a = g.godla[godlo];
        arkusze.push(a);
        mb += a.mb;
        if (a.data !== "" && (od === "" || a.data < od))
          od = a.data;
        if (a.data > doo)
          doo = a.data;
      }
      lista.push({ "rok": g.rok, "kolor": g.kolor, "piksel": g.piksel, "uklad": g.uklad, "arkusze": arkusze, "mb": mb, "od": od, "do": doo });
    }
    lista.sort(function (a, b) {
      if (a.rok !== b.rok)
        return a.rok < b.rok ? 1 : -1;
      if (a.kolor !== b.kolor)
        return a.kolor === "RGB" ? -1 : b.kolor === "RGB" ? 1 : (a.kolor < b.kolor ? -1 : 1);
      return a.piksel - b.piksel;
    });
    ortoNaloty = lista;
    ortoWybrany = -1;
    for (let i = 0; i < lista.length; i++) {
      if (lista[i].kolor === "RGB") {
        ortoWybrany = i;
        break;
      }
    }
    if (ortoWybrany < 0 && lista.length > 0)
      ortoWybrany = 0;
    ortoSzuka = false;
    ortoStan = lista.length === 0 ? qsTr("Brak ortofotomapy GUGiK dla widoku mapy (od %1 r.)").arg(ortoOdRoku) : qsTr("Nalotów: %1. Wybrany: najnowszy RGB o najmniejszym pikselu.").arg(lista.length);
  }

  //! Krok 3: sprawdzenie miejsca i start pobierania wybranego nalotu.
  function ortoPobierz(obszar) {
    if (ortoPracuje || ortoWybrany < 0)
      return;
    const n = ortoNaloty[ortoWybrany];
    const dom = qgisProject.homePath;
    if (!dom) {
      displayToast(qsTr("Najpierw otwórz projekt — ortofoto trafia do jego katalogu"), "warning");
      return;
    }
    // Arkusz trzymany w pamięci w całości: na telefonie ~1 GB to za dużo.
    let najwiekszy = 0;
    for (const a of n.arkusze)
      najwiekszy = Math.max(najwiekszy, a.mb);
    if ((Qt.platform.os === "android" || Qt.platform.os === "ios") && najwiekszy > 300) {
      displayToast(qsTr("Arkusze tego nalotu ważą do %1 — pobierz go na komputerze").arg(ortoMb(najwiekszy)), "warning");
      return;
    }
    // arkusze + GPKG (zwykle kilka razy mniejszy) + zapas
    const potrzeba = n.mb * 1.6 / 1024;
    const wolne = iface.storageFreeGb(dom);
    if (wolne > 0 && wolne < potrzeba) {
      displayToast(qsTr("Za mało miejsca: wolne %1 GB, potrzeba ok. %2 GB").arg(wolne.toFixed(1)).arg(potrzeba.toFixed(1)), "error");
      return;
    }
    const nazwa = ortoNazwaPliku(n, obszar);
    if (iface.listFiles(dom, nazwa).length > 0) {
      displayToast(qsTr("Plik %1 już jest w projekcie — nie pobieram drugi raz").arg(nazwa), "warning");
      return;
    }
    ortoNalot = n;
    ortoObszar = obszar;
    ortoKolejka = n.arkusze.slice();
    ortoPliki = [];
    ortoIndeks = -1;
    ortoPracuje = true;
    displayToast(qsTr("Ortofoto %1: %2 arkuszy, %3 — pobieram po kolei").arg(n.rok + " " + n.kolor).arg(n.arkusze.length).arg(ortoMb(n.mb)));
    ortoNastepny();
  }

  function ortoNazwaPliku(n, obszar) {
    let nazwa = "orto_" + n.kolor + "_" + n.rok + "_" + String(n.piksel).replace(".", "") + "m";
    if (obszar && obszar !== "")
      nazwa += "_" + obszar;
    return nazwa.toLowerCase().replace(/[^a-z0-9_]/g, "_") + ".gpkg";
  }

  function ortoNastepny() {
    ortoIndeks++;
    ortoProby = 0;
    const dom = qgisProject.homePath;
    while (ortoIndeks < ortoKolejka.length) {
      const a = ortoKolejka[ortoIndeks];
      const sciezka = dom + "/ORTO/" + a.plik;
      // Wznowienie: arkusz pobrany wcześniej (pełny, bo downloadFile zapisuje
      // plik dopiero po odebraniu całości) nie jest pobierany drugi raz.
      if (iface.listFiles(dom + "/ORTO", a.plik).length > 0) {
        ortoPliki = ortoPliki.concat([sciezka]);
        ortoIndeks++;
        continue;
      }
      ortoStan = qsTr("Pobieram arkusz %1 z %2 (%3)…").arg(ortoIndeks + 1).arg(ortoKolejka.length).arg(ortoMb(a.mb));
      iface.downloadFile(a.url, sciezka);
      return;
    }
    ortoZloz();
  }

  //! Krok 4: składanie w tle.
  function ortoZloz() {
    const n = ortoNalot;
    const wynik = qgisProject.homePath + "/" + ortoNazwaPliku(n, ortoObszar);
    const opis = "Ortofotomapa " + n.kolor + " " + (n.do !== "" ? n.do : n.rok) + ", piksel " + n.piksel + " m";
    ortoStan = qsTr("Składam kafle z %1 arkuszy…").arg(ortoPliki.length);
    displayToast(ortoStan);
    if (!iface.ortofotoDoGpkg(ortoPliki, wynik, opis, 85)) {
      ortoPracuje = false;
      displayToast(qsTr("Poprzednie składanie ortofoto jeszcze trwa — spróbuj za chwilę"), "warning");
    }
  }

  //! Krok 5: podkład do projektu, metryczka, sprzątanie arkuszy.
  function ortoGotowe(w) {
    ortoPracuje = false;
    const n = ortoNalot;
    ortoNalot = null;
    if (w.blad) {
      ortoStan = w.blad;
      displayToast(qsTr("Ortofoto: %1 — arkusze zostają w ORTO/").arg(w.blad), "error");
      return;
    }
    const nazwaWarstwy = (ortoObszar !== "" ? ortoObszar + " — " : "") + "Ortofotomapa " + n.kolor + " " + (n.do !== "" ? n.do : n.rok) + ", piksel " + String(n.piksel).replace(".", ",") + " m";
    const linie = ["plik: " + w.plik.split("/").pop(), "nalot: " + n.rok + " " + n.kolor + ", " + (n.od === n.do ? n.od : n.od + " – " + n.do), "piksel: " + n.piksel + " m, układ " + n.uklad + " (" + w.uklad + ")", "wymiary: " + w.szerokosc + " x " + w.wysokosc + " px", "podglądów: " + w.podgladow + ", kafli: " + w.kafli, "rozmiar: " + w.rozmiar + " B", "źródło: GUGiK, skorowidz WFS " + ortoUsluga, "utworzono: " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm"), "", "arkusze (" + n.arkusze.length + "):"];
    for (const a of n.arkusze)
      linie.push(a.godlo + "  " + a.data + "  " + a.plik);
    if (!FileUtils.writeFileContent(w.plik.replace(/\.gpkg$/, ".txt"), linie.join("\n") + "\n"))
      displayToast(qsTr("Nie udało się zapisać metryczki ortofoto"), "warning");
    if (!iface.dodajPodkladRastrowy(w.plik, nazwaWarstwy)) {
      displayToast(qsTr("Kafle gotowe (%1), ale warstwa się nie wczytała — arkusze zostają").arg(w.plik.split("/").pop()), "error");
      return;
    }
    if (typeof NarzedziaProjektu !== "undefined")
      NarzedziaProjektu.zapiszProjekt(qgisProject);
    // Sprzątamy DOPIERO po wczytaniu warstwy — jak przy NMT.
    const usuniete = iface.usunArkuszeDem("ORTO", ortoPliki.map(function (p) {
      return p.split("/").pop();
    }));
    ortoStan = qsTr("Gotowe: %1 (%2), usunięto %3 arkuszy").arg(nazwaWarstwy).arg(ortoMb(w.rozmiar / 1048576)).arg(usuniete);
    displayToast(ortoStan);
  }

  Connections {
    target: iface

    function onDownloadFinished(path) {
      if (!oknoDaneWysokosciowe.ortoPracuje || oknoDaneWysokosciowe.ortoIndeks < 0 || oknoDaneWysokosciowe.ortoIndeks >= oknoDaneWysokosciowe.ortoKolejka.length)
        return;
      if (path !== qgisProject.homePath + "/ORTO/" + oknoDaneWysokosciowe.ortoKolejka[oknoDaneWysokosciowe.ortoIndeks].plik)
        return;
      oknoDaneWysokosciowe.ortoPliki = oknoDaneWysokosciowe.ortoPliki.concat([path]);
      oknoDaneWysokosciowe.ortoNastepny();
    }

    function onDownloadFailed(error, path) {
      if (!oknoDaneWysokosciowe.ortoPracuje || oknoDaneWysokosciowe.ortoIndeks < 0 || oknoDaneWysokosciowe.ortoIndeks >= oknoDaneWysokosciowe.ortoKolejka.length)
        return;
      const a = oknoDaneWysokosciowe.ortoKolejka[oknoDaneWysokosciowe.ortoIndeks];
      if (path !== qgisProject.homePath + "/ORTO/" + a.plik)
        return;
      if (oknoDaneWysokosciowe.ortoProby < 2) {
        oknoDaneWysokosciowe.ortoProby++;
        console.log("WFG orto: ponawiam " + a.plik + " (" + error + ")");
        iface.downloadFile(a.url, path);
        return;
      }
      oknoDaneWysokosciowe.ortoPracuje = false;
      oknoDaneWysokosciowe.ortoStan = qsTr("Przerwane na arkuszu %1: %2. Pobrane zostają — „Pobierz” wznowi.").arg(a.godlo).arg(error);
      displayToast(oknoDaneWysokosciowe.ortoStan, "error");
    }

    function onOrtofotoPostep(etap, ile) {
      const nazwy = {
        "mozaika": qsTr("mozaika"),
        "kafle": qsTr("kafle"),
        "podglady": qsTr("podglądy"),
        "kontrola": qsTr("kontrola")
      };
      oknoDaneWysokosciowe.ortoStan = qsTr("Składam ortofoto: %1 %2%").arg(nazwy[etap] || etap).arg(Math.round(ile * 100));
    }

    function onOrtofotoGotowe(wynik) {
      if (oknoDaneWysokosciowe.ortoNalot)
        oknoDaneWysokosciowe.ortoGotowe(wynik);
    }
  }

  //! Otwarcie z szuflady — patrz QfPodklady.otworz().
  /**
   * Warstwice z arkuszy NMT, ktore JUZ sa w projekcie.
   *
   * Nie pobieramy tu niczego: pobieranie ma wlasna odmiane tego okna
   * i wlasny pasek postepu. Jesli nie ma z czego liczyc, mowimy to wprost,
   * zamiast po cichu nic nie zrobic.
   *
   * Rachunek jest wspolny z modulem CAD (utils/warstwice.h) - tam z rzednych
   * z rysunku, tu z modelu terenu.
   */
  function policzWarstwice(odstep) {
    const dom = qgisProject.homePath;
    const pliki = iface.listFiles(dom + "/NMT", "NMT_*.tif")
                    .concat(iface.listFiles(dom + "/NMT", "*.asc"))
                    .concat(iface.listFiles(dom + "/NMT", "*.tif").filter(function (f) {
                      return f.indexOf("NMT_") !== 0;
                    }));
    if (pliki.length === 0) {
      displayToast(qsTr("Najpierw pobierz NMT dla obszaru — nie ma z czego liczyć warstwic"), "warning");
      return;
    }
    displayToast(qsTr("Liczę warstwice z %1 arkuszy…").arg(pliki.length));
    Qt.callLater(function () {
      let linii = 0;
      let zrobione = 0;
      for (const plik of pliki) {
        const nazwa = plik.replace(/\.(tif|asc)$/i, "").replace("NMT_", "");
        const w = iface.warstwiceZRastra(dom + "/NMT/" + plik,
                                         dom + "/NMT/warstwice_" + nazwa + ".gpkg",
                                         odstep,
                                         qsTr("Warstwice %1").arg(nazwa));
        console.log("WFG warstwice NMT: " + plik + " -> " + JSON.stringify(w));
        if (w.blad)
          continue;
        linii += w.linie;
        zrobione++;
      }
      if (typeof NarzedziaProjektu !== "undefined")
        NarzedziaProjektu.zapiszProjekt(qgisProject);
      displayToast(zrobione > 0
                   ? qsTr("Warstwice co %1 m: %2 linii z %3 arkuszy").arg(odstep).arg(linii).arg(zrobione)
                   : qsTr("Nie udało się policzyć warstwic — szczegóły w logu"), zrobione > 0 ? "info" : "warning");
    });
  }

  function otworz(szuflada) {
    if (szuflada && szuflada.modal && szuflada.opened) {
      const potem = function () {
        szuflada.closed.disconnect(potem);
        oknoDaneWysokosciowe.open();
      };
      szuflada.closed.connect(potem);
      szuflada.close();
    } else {
      open();
    }
  }


  onOpened: poleObszaru.text = typeof dashBoard !== "undefined" ? dashBoard.nazwaObszaru() : ""



  // ── wybór odmiany ────────────────────────────────────────────────
  RowLayout {
    Layout.fillWidth: true
    spacing: 4

    Repeater {
      model: [
        {
          "klucz": "NMT",
          "etykieta": qsTr("NMT")
        },
        {
          "klucz": "NMPT",
          "etykieta": qsTr("NMPT")
        },
        {
          "klucz": "CHM",
          "etykieta": qsTr("CHM")
        },
        {
          "klucz": "WARSTWICE",
          "etykieta": qsTr("Warstwice")
        },
        {
          "klucz": "ORTO",
          "etykieta": qsTr("Ortofoto")
        }
      ]

      delegate: Button {
        required property var modelData

        Layout.fillWidth: true
        text: modelData.etykieta
        font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
        font.bold: oknoDaneWysokosciowe.rodzaj === modelData.klucz
        highlighted: oknoDaneWysokosciowe.rodzaj === modelData.klucz
        onClicked: oknoDaneWysokosciowe.rodzaj = modelData.klucz
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: oknoDaneWysokosciowe.rodzaj === "NMT" ? qsTr("Numeryczny model terenu: grunt bez drzew i budynków. Arkusze GUGiK dla widocznego zakresu mapy.") : oknoDaneWysokosciowe.rodzaj === "NMPT" ? qsTr("Numeryczny model pokrycia terenu: wierzchołki drzew i dachy. Arkusze GUGiK dla widocznego zakresu mapy.") : oknoDaneWysokosciowe.rodzaj === "CHM" ? qsTr("CHM to różnica NMPT − NMT, czyli wysokość samych drzew. Liczy się z arkuszy już pobranych dla tej samej nazwy obszaru.") : oknoDaneWysokosciowe.rodzaj === "ORTO" ? qsTr("Zdjęcia lotnicze GUGiK dla widoku mapy, złożone w jeden podkład z kaflami — działa bez internetu. Najpierw ustaw mapę na obszar (np. gminę), potem „Szukaj nalotów”.") : qsTr("Warstwice z pobranego NMT. Liczą się z arkuszy, które już są w projekcie — najpierw pobierz NMT dla obszaru.")
    font: oknoDaneWysokosciowe.t.tinyFont
    color: oknoDaneWysokosciowe.t.secondaryTextColor
    wrapMode: Text.WordWrap
  }

  // ── nazwa obszaru: wspólna dla NMT, NMPT i CHM ───────────────────
  RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Text {
      text: qsTr("Obszar")
      font: oknoDaneWysokosciowe.t.tipFont
      color: oknoDaneWysokosciowe.t.mainTextColor
    }

    TextField {
      id: poleObszaru

      Layout.fillWidth: true
      font: oknoDaneWysokosciowe.t.tipFont
      placeholderText: qsTr("np. Bruzdowa")
      enabled: oknoDaneWysokosciowe.rodzaj === "NMT" || oknoDaneWysokosciowe.rodzaj === "NMPT" || oknoDaneWysokosciowe.rodzaj === "ORTO"
    }
  }

  // ── ortofoto: naloty z skorowidza (WorkFieldGIS 16.10.2026) ──────
  ColumnLayout {
    Layout.fillWidth: true
    spacing: 4
    visible: oknoDaneWysokosciowe.rodzaj === "ORTO"

    Button {
      Layout.fillWidth: true
      text: oknoDaneWysokosciowe.ortoSzuka ? qsTr("Szukam…") : qsTr("Szukaj nalotów dla widoku mapy")
      enabled: !oknoDaneWysokosciowe.ortoSzuka && !oknoDaneWysokosciowe.ortoPracuje
      font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
      onClicked: oknoDaneWysokosciowe.ortoSzukaj()
    }

    Flickable {
      id: listaNalotow

      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(contentHeight, 200)
      visible: oknoDaneWysokosciowe.ortoNaloty.length > 0
      contentHeight: kolumnaNalotow.height
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: kolumnaNalotow

        width: listaNalotow.width

        Repeater {
          model: oknoDaneWysokosciowe.ortoNaloty

          delegate: RadioButton {
            required property var modelData
            required property int index

            width: kolumnaNalotow.width
            checked: oknoDaneWysokosciowe.ortoWybrany === index
            enabled: !oknoDaneWysokosciowe.ortoPracuje
            text: oknoDaneWysokosciowe.ortoOpis(modelData)
            font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
            onClicked: oknoDaneWysokosciowe.ortoWybrany = index
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: text !== ""
      text: oknoDaneWysokosciowe.ortoStan
      font: oknoDaneWysokosciowe.t.tinyFont
      color: oknoDaneWysokosciowe.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }
  }

  // ── odstęp warstwic: tylko przy warstwicach ─────────────────────
  RowLayout {
    Layout.fillWidth: true
    spacing: 6
    visible: oknoDaneWysokosciowe.rodzaj === "WARSTWICE"

    Text {
      text: qsTr("Co ile metrów")
      font: oknoDaneWysokosciowe.t.tipFont
      color: oknoDaneWysokosciowe.t.mainTextColor
    }

    TextField {
      id: poleOdstepu

      Layout.preferredWidth: 70
      text: "0,5"
      inputMethodHints: Qt.ImhFormattedNumbersOnly
      font.pointSize: oknoDaneWysokosciowe.t.tipFont.pointSize
    }

    Item {
      Layout.fillWidth: true
    }
  }

  // ── roczniki: tylko przy pobieraniu arkuszy ──────────────────────
  ColumnLayout {
    Layout.fillWidth: true
    spacing: 4
    visible: oknoDaneWysokosciowe.rodzaj === "NMT" || oknoDaneWysokosciowe.rodzaj === "NMPT"

    Text {
      Layout.fillWidth: true
      text: qsTr("Skorowidze GUGiK dzielą arkusze na roczniki.")
      font: oknoDaneWysokosciowe.t.tinyFont
      color: oknoDaneWysokosciowe.t.secondaryTextColor
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 4

      Button {
        Layout.fillWidth: true
        text: qsTr("Najnowsze arkusze")
        font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
        font.bold: oknoDaneWysokosciowe.najnowsze
        highlighted: oknoDaneWysokosciowe.najnowsze
        onClicked: oknoDaneWysokosciowe.najnowsze = true
      }

      Button {
        Layout.fillWidth: true
        text: qsTr("Wszystkie roczniki")
        font.pointSize: oknoDaneWysokosciowe.t.tinyFont.pointSize
        font.bold: !oknoDaneWysokosciowe.najnowsze
        highlighted: !oknoDaneWysokosciowe.najnowsze
        onClicked: oknoDaneWysokosciowe.najnowsze = false
      }
    }
  }

}
