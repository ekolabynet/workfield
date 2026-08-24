.pragma library

/**
 * WorkField 23.08.2026 — gwiazdozbiory na kopule panelu "Niebo".
 *
 * DLACZEGO TO W OGOLE MA PRAWO DZIALAC BEZ KOMPASU:
 * wykres nieba jest rysowany w azymucie liczonym od POLNOCY GEOGRAFICZNEJ,
 * bo taki podaje odbiornik GNSS w depeszy GSV. Magnetometr telefonu myli sie
 * o 5-15 stopni i przy samochodzie wiecej; tutaj nie bierze udzialu wcale.
 * Gwiazdy licza sie z czasu i wspolrzednych, czyli z tego samego zrodla.
 *
 * DOKLADNOSC I JEJ GRANICE — zeby nikt nie wziat tego za efemerydy:
 *   - wspolrzedne rownikowe J2000, bez precesji, nutacji i ruchow wlasnych,
 *   - bez refrakcji atmosferycznej (przy horyzoncie realnie okolo 0.5 stopnia),
 *   - bez paralaksy dobowej (dla gwiazd nieistotna).
 * Sumaryczny blad rzedu pol stopnia. Kopula ma srednice okolo 300 px na 180
 * stopni, czyli **1,7 px na stopien** — polstopniowy blad to mniej niz jeden
 * piksel. Do rozpoznania Wielkiego Wozu wystarcza z ogromnym zapasem; do
 * pomiaru czegokolwiek NIE i nigdy nie bedzie.
 *
 * Zrodlo wspolrzednych: standardowe katalogowe pozycje J2000 jasnych gwiazd.
 */

// nazwa, rektascensja [stopnie], deklinacja [stopnie], wielkosc gwiazdowa
var GWIAZDY = [
  // Wielka Niedzwiedzica
  ["Dubhe", 165.93, 61.75, 1.79],       // 0
  ["Merak", 165.46, 56.38, 2.37],       // 1
  ["Phecda", 178.46, 53.69, 2.44],      // 2
  ["Megrez", 183.86, 57.03, 3.31],      // 3
  ["Alioth", 193.51, 55.96, 1.77],      // 4
  ["Mizar", 200.98, 54.93, 2.23],       // 5
  ["Alkaid", 206.89, 49.31, 1.86],      // 6
  // Mala Niedzwiedzica
  ["Polaris", 37.95, 89.26, 1.98],      // 7
  ["Kochab", 222.68, 74.16, 2.08],      // 8
  ["Pherkad", 230.18, 71.83, 3.05],     // 9
  // Kasjopeja
  ["Caph", 2.29, 59.15, 2.28],          // 10
  ["Schedar", 10.13, 56.54, 2.24],      // 11
  ["Cih", 14.18, 60.72, 2.15],          // 12
  ["Ruchbah", 21.45, 60.24, 2.68],      // 13
  ["Segin", 28.60, 63.67, 3.35],        // 14
  // Labedz
  ["Deneb", 310.36, 45.28, 1.25],       // 15
  ["Sadr", 305.56, 40.26, 2.23],        // 16
  ["Albireo", 292.68, 27.96, 3.05],     // 17
  ["Gienah", 311.55, 33.97, 2.46],      // 18
  ["Fawaris", 296.24, 45.13, 2.87],     // 19
  // Lutnia, Orzel, Wolarz
  ["Wega", 279.23, 38.78, 0.03],        // 20
  ["Altair", 297.70, 8.87, 0.77],       // 21
  ["Arktur", 213.92, 19.18, -0.05],     // 22
  // Lew
  ["Regulus", 152.09, 11.97, 1.36],     // 23
  ["Algieba", 154.99, 19.84, 2.08],     // 24
  ["Denebola", 177.26, 14.57, 2.14],    // 25
  // Orion
  ["Betelgeza", 88.79, 7.41, 0.50],     // 26
  ["Bellatrix", 81.28, 6.35, 1.64],     // 27
  ["Mintaka", 83.00, -0.30, 2.23],      // 28
  ["Alnilam", 84.05, -1.20, 1.69],      // 29
  ["Alnitak", 85.19, -1.94, 1.77],      // 30
  ["Rigel", 78.63, -8.20, 0.13],        // 31
  ["Saiph", 86.94, -9.67, 2.09],        // 32
  // Byk, Woznica, Bliznieta
  ["Aldebaran", 68.98, 16.51, 0.87],    // 33
  ["Elnath", 81.57, 28.61, 1.65],       // 34
  ["Kapella", 79.17, 46.00, 0.08],      // 35
  ["Kastor", 113.65, 31.89, 1.58],      // 36
  ["Polluks", 116.33, 28.03, 1.14],     // 37
  // Wielki i Maly Pies
  ["Syriusz", 101.29, -16.72, -1.46],   // 38
  ["Procjon", 114.83, 5.22, 0.34],      // 39
  // Perseusz
  ["Mirfak", 51.08, 49.86, 1.79],       // 40
  ["Algol", 47.04, 40.96, 2.09],        // 41
  // Andromeda i Pegaz
  ["Alpheratz", 2.10, 29.09, 2.06],     // 42
  ["Mirach", 17.43, 35.62, 2.06],       // 43
  ["Almach", 30.97, 42.33, 2.10],       // 44
  ["Markab", 346.19, 15.21, 2.48],      // 45
  ["Scheat", 345.94, 28.08, 2.42],      // 46
  ["Algenib", 3.31, 15.18, 2.83],       // 47
  // Skorpion i Panna
  ["Antares", 247.35, -26.43, 1.06],    // 48
  ["Spika", 201.30, -11.16, 0.98]       // 49
];

//! pary indeksow — linie gwiazdozbiorow
var LINIE = [
  [0, 1], [1, 2], [2, 3], [3, 0], [3, 4], [4, 5], [5, 6],           // Woz
  [7, 8], [8, 9],                                                     // Mala Niedzwiedzica
  [10, 11], [11, 12], [12, 13], [13, 14],                             // Kasjopeja
  [15, 16], [16, 17], [16, 18], [16, 19],                             // Labedz
  [23, 24], [24, 25],                                                 // Lew
  [26, 27], [27, 28], [28, 29], [29, 30], [30, 26], [28, 31], [30, 32], // Orion
  [31, 32],
  [33, 34],                                                           // Byk
  [36, 37],                                                           // Bliznieta
  [40, 41],                                                           // Perseusz
  [42, 43], [43, 44],                                                 // Andromeda
  [42, 45], [45, 46], [46, 47], [47, 42],                             // kwadrat Pegaza
  [20, 15], [20, 21]                                                  // trojkat letni
];

function stopnieNaRadiany(x) {
  return x * Math.PI / 180;
}

/**
 * Sredni czas gwiazdowy Greenwich w stopniach dla podanej daty (UTC).
 * Wzor IAU: wystarczajaco dokladny na stulecia wokol dzis.
 */
function gmstStopnie(data) {
  var jd = data.getTime() / 86400000.0 + 2440587.5;
  var d = jd - 2451545.0;
  var gmst = 280.46061837 + 360.98564736629 * d;
  return ((gmst % 360) + 360) % 360;
}

/**
 * Zamienia pozycje rownikowa na horyzontalna dla obserwatora.
 * Zwraca { wysokosc, azymut } w stopniach; azymut liczony OD POLNOCY,
 * zgodnie z ruchem wskazowek zegara — czyli tak samo jak azymut satelity.
 */
function naHoryzont(rektascensja, deklinacja, szerokosc, dlugosc, data) {
  var lst = gmstStopnie(data) + dlugosc;
  var kat = stopnieNaRadiany(((lst - rektascensja) % 360 + 360) % 360);

  var dek = stopnieNaRadiany(deklinacja);
  var sze = stopnieNaRadiany(szerokosc);

  var sinW = Math.sin(dek) * Math.sin(sze) + Math.cos(dek) * Math.cos(sze) * Math.cos(kat);
  sinW = Math.max(-1, Math.min(1, sinW));
  var wysokosc = Math.asin(sinW);

  var cosA = (Math.sin(dek) - Math.sin(wysokosc) * Math.sin(sze)) / (Math.cos(wysokosc) * Math.cos(sze));
  cosA = Math.max(-1, Math.min(1, cosA));
  var azymut = Math.acos(cosA) * 180 / Math.PI;
  if (Math.sin(kat) > 0) {
    azymut = 360 - azymut;
  }

  return {
    "wysokosc": wysokosc * 180 / Math.PI,
    "azymut": azymut
  };
}

/**
 * Liczy pozycje ekranowe wszystkich gwiazd. Zwraca tablice o dlugosci
 * GWIAZDY.length; pozycje pod horyzontem dostaja `null`, zeby indeksy
 * zgadzaly sie z tablica LINIE.
 */
function pozycje(szerokosc, dlugosc, data, cx, cy, promien) {
  var wynik = [];
  for (var i = 0; i < GWIAZDY.length; i++) {
    var g = GWIAZDY[i];
    var h = naHoryzont(g[1], g[2], szerokosc, dlugosc, data);
    if (h.wysokosc <= 0) {
      wynik.push(null);
      continue;
    }
    var r = promien * (1 - h.wysokosc / 90);
    var a = stopnieNaRadiany(h.azymut);
    wynik.push({
      "x": cx + r * Math.sin(a),
      "y": cy - r * Math.cos(a),
      "nazwa": g[0],
      "jasnosc": g[3]
    });
  }
  return wynik;
}
