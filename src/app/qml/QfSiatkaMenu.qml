import QtQuick
import QtQuick.Layouts
import Theme

/**
 * WorkField 21.09.2026 — RZĄD POZYCJI MENU w wybranym układzie.
 *
 * Lewa szuflada ma dziewięć osobnych ciągów `QfPozycjaMenu` — to nie jest
 * jeden model, tylko kod pisany ręcznie, z własną obsługą kliknięcia przy
 * każdej pozycji. Nie da się ich zamienić na `Repeater`, ale da się zdjąć
 * z nich WIEDZĘ O UKŁADZIE: pojemnik wie, który układ jest wybrany, i sam
 * rozdaje go dzieciom razem z szerokością.
 *
 * Dzięki temu dopisanie nowej pozycji do menu nie wymaga pamiętania o niczym
 * poza `text`, `ikona` i `onClicked` — układ przychodzi z pojemnika.
 *
 * Szerokość liczymy z SZEROKOŚCI SZUFLADY, nie z rzędu: liczona z `Flow`
 * zapętla układ („Flow called polish() inside updatePolish()", piaskownica
 * 21.09), bo szerokość dziecka zależałaby od szerokości rzędu, a ta od dzieci.
 */
Flow {
  id: siatka

  property var t: Theme

  //! Szerokość POJEMNIKA, w którym rząd stoi — zwykle `dashBoard.width`
  //! pomniejszone o własne marginesy rzędu.
  property real szerokosc: 0

  //! Wybór jest wspólny dla obu szuflad; tu tylko go czytamy.
  property string uklad: mainWindow.ukladPozycji

  Layout.fillWidth: true
  spacing: 4

  /**
   * FUNKCJA, a nie wiązanie: `rozdaj()` woła ją z `onUkladChanged`, a wtedy
   * wiązanie zależne od `uklad` mogło jeszcze nie zostać przeliczone —
   * kafelki dostawały szerokość poprzedniego układu (piaskownica 21.09).
   * Odejmujemy zapas na pasek przewijania (16) i odstępy między kolumnami.
   */
  function szerokoscPozycji() {
    const dostepna = Math.max(0, siatka.szerokosc - 16);
    if (siatka.uklad === "ikony")
      return 44;
    if (siatka.uklad === "kafelki")
      return Math.floor((dostepna - 2 * siatka.spacing) / 3);
    if (siatka.uklad === "dwie")
      return Math.floor((dostepna - siatka.spacing) / 2);
    return dostepna;
  }

  /**
   * Rozdanie układu dzieciom. Imperatywnie, a nie wiązaniem w każdej
   * pozycji, bo pozycji jest w lewej szufladzie trzydzieści parę i wiązanie
   * przy każdej z nich byłoby trzydziestoma paroma miejscami do zapomnienia.
   * Pomijamy dzieci, które o układzie nic nie wiedzą (separatory, `Repeater`).
   */
  function rozdaj() {
    for (var i = 0; i < siatka.children.length; i++) {
      var d = siatka.children[i];
      if (d.uklad === undefined)
        continue;
      d.uklad = siatka.uklad;
      // Wysokosci NIE ustawiamy: `QfPozycjaMenu` sama ja zna (84 dla kafelka,
      // 44 dla samej ikony). Przypisanie raz zerwaloby to wiazanie na stale.
      const w = siatka.szerokoscPozycji();
      if (w > 0)
        d.width = w;
    }
  }

  onUkladChanged: rozdaj()
  onSzerokoscChanged: rozdaj()
  onChildrenChanged: rozdaj()
  Component.onCompleted: rozdaj()
}
