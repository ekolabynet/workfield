// Wygenerowane: narzedzia/zbuduj_lsp_inc.py z lisp/wf.lsp — nie edytować.
static const char* const WF_LSP[] = {
    R"WFLSP(;;; wf.lsp -- WorkFieldCAD w CAD-zie: podglad i styl wedlug atrybutow GIS.
;;;
;;; Ladowanie: APPLOAD (albo przeciagniecie pliku na okno), potem polecenia:
;;;   WFINFO    -- wskaz obiekt albo [Id] (warstwa z listy + numer): warstwa GIS,
;;;                fid i wszystkie atrybuty; obiekt zaznaczony i przyblizony
;;;   WFZNAJDZ  -- zaznacz i przybliz obiekty o danej wartosci atrybutu (albo ID)
;;;   WFKOLOR   -- kolor wedlug atrybutu: Kategorie / Zakresy / Przywroc;
;;;                palety jak w QGIS (Spectral, Viridis, Set1, Paired...), odwracanie
;;;   WFSKALA   -- rozmiar wedlug atrybutu: Okregi na punktach / Szerokosc linii / Usun
;;;   WFODNOSNIK -- opisy z wartoscia atrybutu (jak etykiety w QGIS): Tekst,
;;;                Odnosnik albo Multiodnosnik; Wskaz / Id / Cala warstwa / Usun;
;;;                rozmieszczenie automatyczne z unikaniem kolizji
;;;   WFIDZ     -- skok do wspolrzednych wklejonych z GIS (E N albo X Y geodezyjne),
;;;                najblizszy obiekt GIS zaznaczony
;;;   Na kazdej liscie pol jest tez "0. ID (fid)" -- numer obiektu.
;;;
;;; Skad dane: DXF z WorkFieldCAD (od 0.3.0) niesie przy kazdym obiekcie XRecord
;;; "WF" w slowniku rozszerzen. Za czescia binarna (dla powrotu do GIS) stoi
;;; sekcja czytelna:
;;;   (1 . "WF_CZYTELNE") (1 . "_warstwa") (1 . tabela) (1 . "_fid") (90 . fid)
;;;   i dla kazdej kolumny (1 . nazwa) + jedna para wartosci:
;;;   (40 . rzeczywista) (90 . calkowita) (1 . tekst) (70 . 0) = NULL
;;;
;;; Co jest bezpieczne: kolor i szerokosc obiektu WorkField NIE sa danymi GIS
;;; -- przy powrocie do GeoPackage sa pomijane. Okregi z WFSKALA leza na
;;; warstwach WF_WIDOK_* i sa tylko widokiem (wfcad-obieg zglasza je osobno),
;;; tak samo odnosniki z WFODNOSNIK i ich styl WF_ODNOSNIK_*.
;;; Rozmiar zmieniony recznie na okregu NIE zmienia atrybutu.
;;;
;;; Komunikaty bez polskich liter: plik .lsp czytany bywa w kodowaniu ANSI.
;;; Uzywane wylacznie funkcje AutoLISP-a (bez vl-*, vla-*), zeby dzialalo
;;; w BricsCAD na Linuksie, Windows i Macu oraz w AutoCAD. Wyjatek: WFODNOSNIK
;;; (wf:przestrzen-modelu, wf:odnosnik, wf:styl-odnosnika) -- opis nizej.

;;; ---------------------------------------------------------------- dane --

(defun wf:xrec (e / xd)
  (setq xd (cdr (assoc 360 (entget e))))
  (if xd (dictsearch xd "WF"))
)

;; Lista ((nazwa . wartosc) ...) z sekcji czytelnej; nil, gdy to nie obiekt WF.
;; NULL -> nil.
(defun wf:dane (e / x r out)
  (if (and (setq x (wf:xrec e))
           (setq r (cdr (member '(1 . "WF_CZYTELNE") x)))
      )
    (progn
      (while (and r (cdr r))
        (setq out (cons (cons (cdr (car r))
                              (if (= (car (cadr r)) 70) nil (cdr (cadr r)))
                        )
                        out
                  )
              r   (cddr r)
        )
      )
      (reverse out)
    )
  )
)

(defun wf:napis (v)
  (cond ((null v) "NULL")
        ((= (type v) 'STR) v)
        ((= (type v) 'INT) (itoa v))
        ((= (type v) 'REAL) (rtos v 2 6))
        (T "?")
  )
)

;; Wartosc jako liczba albo nil. Tekst "12.5" tez sie liczy; "60+36" nie.
(defun wf:liczba (v)
  (cond ((numberp v) (float v))
        ((= (type v) 'STR) (distof v 2))
        (T nil)
  )
)

;; Czy wszystkie kategorie (poza NULL) da sie odczytac jako liczby.
(defun wf:liczbowe (kat / tak)
  (setq tak T)
  (foreach c kat
    (if (and (/= (car c) "NULL") (not (distof (car c) 2))) (setq tak nil))
  )
  tak
)

(defun wf:pola (d / out)
  (foreach p d
    (if (not (member (car p) '("_warstwa" "_fid")))
      (setq out (cons (car p) out))
    )
  )
  (reverse out)
)

;; Wszystkie obiekty WF danej warstwy GIS (nil = wszystkie), bez WF_WIDOK_*.
;; Wynik: ((ename . dane) ...)
(defun wf:obiekty (warstwa / ss i e d out)
  (if (setq ss (ssget "_X" '((8 . "WF_*"))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i)
              i (1+ i)
        )
        (if (and (not (wcmatch (cdr (assoc 8 (entget e))) "WF_WIDOK_*"))
                 (setq d (wf:dane e))
                 (or (null warstwa) (= (cdr (assoc "_warstwa" d)) warstwa))
            )
          (setq out (cons (cons e d) out))
        )
      )
    )
  )
  (reverse out)
)

;; Warstwy GIS obecne w rysunku z liczba obiektow CAD: ((nazwa . n) ...).
(defun wf:warstwy-gis (/ l k x)
  (foreach o (wf:obiekty nil)
    (setq k (cdr (assoc "_warstwa" (cdr o))))
    (if (setq x (assoc k l))
      (setq l (subst (cons k (1+ (cdr x))) x l))
      (setq l (cons (cons k 1) l))
    )
  )
  (reverse l)
)

;; Wybor warstwy GIS z numerowanej listy. Wynik: nazwa albo nil.
(defun wf:wybierz-warstwe (/ l i n)
  (setq l (wf:warstwy-gis)
        i 1
  )
  (if (null l)
    (progn (princ "\nW rysunku nie ma obiektow WorkField (albo eksport starszy niz 0.3.0).") nil)
    (progn
      (foreach w l
        (princ (strcat "\n  " (itoa i) ". " (car w) "  (" (itoa (cdr w)) " w rysunku)"))
        (setq i (1+ i))
      )
      (initget 6)
      (setq n (getint (strcat "\nNumer warstwy [1-" (itoa (length l)) "]: ")))
      (if (and n (<= n (length l)))
        (car (nth (1- n) l))
        (progn (princ (strcat "\nNie ma warstwy nr " (if n (itoa n) "?") " -- polecenie przerwane.")) nil)
      )
    )
  )
)

;; Wybor pola z listy pol obiektu d (wartosci obiektu jako podpowiedz).
;; zFid: na liscie takze "0. ID (fid)" -- wynik wtedy "_fid".
;; Wynik: nazwa pola albo nil.
(defun wf:wybierz-pole-z (d zFid / pola i n)
  (setq pola (wf:pola d)
        i    1
  )
  (princ (strcat "\nWarstwa GIS: " (wf:napis (cdr (assoc "_warstwa" d)))))
  (if zFid (princ (strcat "\n  0. ID (fid)  (" (wf:napis (cdr (assoc "_fid" d))) ")")))
  (foreach p pola
    (princ (strcat "\n  " (itoa i) ". " p "  (" (wf:napis (cdr (assoc p d))) ")"))
    (setq i (1+ i))
  )
  (if (and (null pola) (not zFid))
    (progn (princ "\nWarstwa nie ma pol.") nil)
    (progn
      (initget (if zFid 4 6))
      (setq n (getint (strcat "\nNumer pola [" (if zFid "0" "1") "-" (itoa (length pola)) "]: ")))
      (cond
        ((and zFid (= n 0)) "_fid")
        ((and n (<= n (length pola))) (nth (1- n) pola))
        (T
         (princ (strcat "\nNie ma pola nr " (if n (itoa n) "?") " -- polecenie przerwane.")) nil)
      )
    )
  )
)

;; Dlaczego wskazany obiekt nie ma danych -- komunikat.
(defun wf:nie-obiekt (e / w)
  (setq w (cdr (assoc 8 (entget e))))
  (if (wcmatch w "WF_WIDOK_*")
    (strcat "\nTo obiekt widoku (okrag WFSKALA albo odnosnik) z warstwy " w
            " -- wskaz sam obiekt GIS.")
    "\nTo nie jest obiekt WorkField (albo eksport starszy niz 0.3.0)."
  )
)

;; "ID w warstwie: od 1 do 156" -- zeby bylo wiadomo, jakie numery wpisywac.
(defun wf:zakres-id (warstwa / mn mx v)
  (foreach o (wf:obiekty warstwa)
    (setq v (cdr (assoc "_fid" (cdr o))))
    (if (or (null mn) (< v mn)) (setq mn v))
    (if (or (null mx) (> v mx)) (setq mx v))
  )
  (if mn
    (strcat "\nID w warstwie " warstwa ": od " (itoa mn) " do " (itoa mx)
            " (numer obiektu pokazuje WFINFO)")
    ""
  )
)

;; Nazwa pola do komunikatow ("_fid" -> "ID").
(defun wf:nazwa-pola (p)
  (if (= p "_fid") "ID" p)
)

;; Obiekt po numerze: warstwa z listy, numer ID (fid). Wynik: (ename . dane) albo nil.
;; getstring, nie getint: getint nie przyjmie fid wiekszego niz 32767.
(defun wf:obiekt-z-id (/ w fid o)
  (if (setq w (wf:wybierz-warstwe))
    (progn
      (princ (wf:zakres-id w))
      (setq fid (getstring "\nNumer ID (fid): "))
      (if (not (setq o (wf:czesc w fid)))
        (princ (strcat "\nNie ma obiektu ID " fid " w warstwie " w "."))
      )
      o
    )
  )
)

;; Obiekt: wskazanie albo [Id] = warstwa z listy i numer. Wynik: (ename . dane) albo nil.
(defun wf:wskaz-obiekt (komunikat / s d)
  (initget "Id")
  (setq s (entsel (strcat komunikat " albo [Id]: ")))
  (cond
    ((= s "Id") (wf:obiekt-z-id))
    ((null s) nil)
    ((setq d (wf:dane (car s))) (cons (car s) d))
    (T (princ (wf:nie-obiekt (car s))) nil)
  )
)

;; Zaznacza i przybliza obiekty (ename albo zbior).
(defun wf:pokaz (ss / echo)
  (if (= (type ss) 'ENAME) (setq ss (ssadd ss)))
  (setq echo (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.ZOOM" "_Object" ss "")
  (setvar "CMDECHO" echo)
  (sssetfirst nil ss)
)

;; Warstwa: wskazanie obiektu albo wybor z listy [Warstwa]; potem pole.
;; Wynik: (warstwa pole) albo nil.
(defun wf:wybierz-pole (komunikat zFid / s w d p)
  (initget "Warstwa")
  (setq s (entsel (strcat komunikat " albo [Warstwa]: ")))
  (cond
    ((= s "Warstwa")
     (if (setq w (wf:wybierz-warstwe)) (setq d (cdr (car (wf:obiekty w)))))
    )
    ((null s) nil)
    ((not (setq d (wf:dane (car s))))
     (princ (wf:nie-obiekt (car s)))
    )
  )
  (if (and d (setq p (wf:wybierz-pole-z d zFid)))
    (list (cdr (assoc "_warstwa" d)) p)
  )
)

;;; ---------------------------------------------------------- narzedzia --

(defun wf:sortuj (l / wynik)
  ;; sortowanie przez wstawianie; wystarczy dla legend
  (foreach x l
    (setq wynik (wf:wstaw x wynik))
  )
  wynik
)

(defun wf:wstaw (x l)
  (cond ((null l) (list x))
        ((wf:mniejsze (car x) (car (car l))) (cons x l))
        (T (cons (car l) (wf:wstaw x (cdr l))))
  )
)

;; Porzadek legendy: liczby liczbowo (203 przed 1018), tekst alfabetycznie,
;; liczby przed tekstem, NULL na koncu. 22.10: sortowanie jak tekst dawalo
;; 1018 < 11449 < 203.
(defun wf:mniejsze (a b / la lb)
  (setq la (if (/= a "NULL") (distof a 2))
        lb (if (/= b "NULL") (distof b 2))
  )
  (cond ((= b "NULL") (/= a "NULL"))
        ((= a "NULL") nil)
        ((and la lb) (< la lb))
        (la T)
        (lb nil)
        (T (< a b))
  )
)

(defun wf:ustaw (e kod v / d)
  (setq d (entget e))
  (setq d (if (assoc kod d)
            (subst (cons kod v) (assoc kod d) d)
            (append d (list (cons kod v)))
          )
  )
  (entmod d)
  (entupd e)
)

;; Znaki niedozwolone w nazwie warstwy CAD. Lista, nie wcmatch: w wcmatch
;; lewy apostrof jest znakiem ucieczki i wzorzec z nim w nawiasie sie nie domyka.
(setq wf:zakazane '("<" ">" "/" "\\" "\"" ":" ";" "?" "*" "|" "," "=" "`"))

;; Wzorzec dla ssget/wcmatch dopasowujacy dokladnie dana nazwe: znaki
;; specjalne wcmatch poprzedzone lewym apostrofem (np. "Wysokosc [m]").
(defun wf:wzorzec (s / i c w)
  (setq i 1
        w ""
  )
  (while (<= i (strlen s))
    (setq c (substr s i 1)
          w (strcat w (if (member c '("#" "@" "." "*" "?" "~" "[" "]" "-" "," "`")) (strcat "`" c) c))
          i (1+ i)
    )
  )
  w
)

;; Nazwa warstwy CAD bez znakow niedozwolonych.
(defun wf:nazwa-warstwy (s / i c w)
  (setq i 1
        w ""
  )
  (while (<= i (strlen s))
    (setq c (substr s i 1)
          w (strcat w (if (member c wf:zakazane) "_" c))
          i (1+ i)
    )
  )
  w
)

(defun wf:warstwa-widoku (warstwa pole / nazwa)
  (setq nazwa (wf:nazwa-warstwy (strcat "WF_WIDOK_" warstwa "_" pole)))
  (if (not (tblsearch "LAYER" nazwa))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 nazwa)
                   '(70 . 0)
                   '(62 . 7)
                   '(6 . "Continuous")
             )
    )
  )
  nazwa
)

(defun wf:wyczysc-warstwe (nazwa / ss i n)
  (setq n 0)
  (if (setq ss (ssget "_X" (list (cons 8 (wf:wzorzec nazwa)))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (entdel (ssname ss i))
        (setq i (1+ i)
              n (1+ n)
        )
      )
    )
  )
  n
)

;; Barwy ACI dobrze rozroznialne na ekranie.
(setq wf:paleta '(1 3 5 2 6 4 30 140 210 50 90 170 240 110 190 20 70 130 230 150))
;; Rampa od niebieskiego do czerwonego dla zakresow.
(setq wf:rampa '(5 150 4 3 2 30 1))

;; <PALETY>
;; Palety jak w QGIS: ColorBrewer (Spectral ... Pastel1) i viridis/magma/plasma/inferno.
;; Barwy RGB z danych matplotlib (_cm.datad, _cm_listed) -- te same zrodla co w QGIS.
;; "G" = ciagla (ColorBrewer 9/11 klas, viridis 11 probek, miedzy nimi interpolacja RGB),
;; "K" = jakosciowa (barwy po kolei, w kolko).
)WFLSP",
    R"WFLSP(;; Wygenerowane: narzedzia/zbuduj_palety.py -- nie poprawiac recznie.
(setq wf:palety
  '(
    ("Spectral" "G"
     (158 1 66) (213 62 79) (244 109 67) (253 174 97) (254 224 139) (255 255 191)
     (230 245 152) (171 221 164) (102 194 165) (50 136 189) (94 79 162))
    ("RdYlGn" "G"
     (165 0 38) (215 48 39) (244 109 67) (253 174 97) (254 224 139) (255 255 191)
     (217 239 139) (166 217 106) (102 189 99) (26 152 80) (0 104 55))
    ("RdYlBu" "G"
     (165 0 38) (215 48 39) (244 109 67) (253 174 97) (254 224 144) (255 255 191)
     (224 243 248) (171 217 233) (116 173 209) (69 117 180) (49 54 149))
    ("Blues" "G"
     (247 251 255) (222 235 247) (198 219 239) (158 202 225) (107 174 214) (66 146 198)
     (33 113 181) (8 81 156) (8 48 107))
    ("Greens" "G"
     (247 252 245) (229 245 224) (199 233 192) (161 217 155) (116 196 118) (65 171 93)
     (35 139 69) (0 109 44) (0 68 27))
    ("Reds" "G"
     (255 245 240) (254 224 210) (252 187 161) (252 146 114) (251 106 74) (239 59 44)
     (203 24 29) (165 15 21) (103 0 13))
    ("YlGn" "G"
     (255 255 229) (247 252 185) (217 240 163) (173 221 142) (120 198 121) (65 171 93)
     (35 132 67) (0 104 55) (0 69 41))
    ("YlOrRd" "G"
     (255 255 204) (255 237 160) (254 217 118) (254 178 76) (253 141 60) (252 78 42)
     (227 26 28) (189 0 38) (128 0 38))
    ("Greys" "G"
     (255 255 255) (240 240 240) (217 217 217) (189 189 189) (150 150 150) (115 115 115)
     (82 82 82) (37 37 37) (0 0 0))
    ("Viridis" "G"
     (68 1 84) (72 37 118) (65 68 135) (53 95 141) (42 120 142) (33 145 140)
     (34 168 132) (66 190 113) (122 209 81) (189 223 38) (253 231 37))
    ("Magma" "G"
     (0 0 4) (21 14 56) (59 15 112) (100 26 128) (140 41 129) (183 55 121)
     (222 73 104) (246 110 92) (254 159 109) (254 207 146) (252 253 191))
    ("Plasma" "G"
     (13 8 135) (67 3 158) (106 0 168) (143 13 164) (177 42 144) (204 71 120)
     (225 100 98) (241 131 76) (252 166 54) (252 206 37) (240 249 33))
    ("Inferno" "G"
     (0 0 4) (24 12 60) (66 10 104) (106 23 110) (147 38 103) (188 55 84)
     (221 81 58) (243 118 27) (252 165 10) (246 215 70) (252 255 164))
    ("Set1" "K"
     (228 26 28) (55 126 184) (77 175 74) (152 78 163) (255 127 0) (255 255 51)
     (166 86 40) (247 129 191) (153 153 153))
    ("Set2" "K"
     (102 194 165) (252 141 98) (141 160 203) (231 138 195) (166 216 84) (255 217 47)
     (229 196 148) (179 179 179))
    ("Set3" "K"
     (141 211 199) (255 255 179) (190 186 218) (251 128 114) (128 177 211) (253 180 98)
     (179 222 105) (252 205 229) (217 217 217) (188 128 189) (204 235 197) (255 237 111))
    ("Paired" "K"
     (166 206 227) (31 120 180) (178 223 138) (51 160 44) (251 154 153) (227 26 28)
     (253 191 111) (255 127 0) (202 178 214) (106 61 154) (255 255 153) (177 89 40))
    ("Dark2" "K"
     (27 158 119) (217 95 2) (117 112 179) (231 41 138) (102 166 30) (230 171 2)
     (166 118 29) (102 102 102))
    ("Pastel1" "K"
     (251 180 174) (179 205 227) (204 235 197) (222 203 228) (254 217 166) (255 255 204)
     (229 216 189) (253 218 236) (242 242 242)))
)
;; Barwy ACI 1-255 jako RGB (standardowa tabela, z ezdxf.colors).
(setq wf:aci-rgb
  '(
    (255 0 0) (255 255 0) (0 255 0) (0 255 255) (0 0 255) (255 0 255) (255 255 255) (128 128 128)
    (192 192 192) (255 0 0) (255 127 127) (165 0 0) (165 82 82) (127 0 0) (127 63 63) (76 0 0)
    (76 38 38) (38 0 0) (38 19 19) (255 63 0) (255 159 127) (165 41 0) (165 103 82) (127 31 0)
    (127 79 63) (76 19 0) (76 47 38) (38 9 0) (38 23 19) (255 127 0) (255 191 127) (165 82 0)
    (165 124 82) (127 63 0) (127 95 63) (76 38 0) (76 57 38) (38 19 0) (38 28 19) (255 191 0)
    (255 223 127) (165 124 0) (165 145 82) (127 95 0) (127 111 63) (76 57 0) (76 66 38) (38 28 0)
    (38 33 19) (255 255 0) (255 255 127) (165 165 0) (165 165 82) (127 127 0) (127 127 63) (76 76 0)
    (76 76 38) (38 38 0) (38 38 19) (191 255 0) (223 255 127) (124 165 0) (145 165 82) (95 127 0)
    (111 127 63) (57 76 0) (66 76 38) (28 38 0) (33 38 19) (127 255 0) (191 255 127) (82 165 0)
    (124 165 82) (63 127 0) (95 127 63) (38 76 0) (57 76 38) (19 38 0) (28 38 19) (63 255 0)
    (159 255 127) (41 165 0) (103 165 82) (31 127 0) (79 127 63) (19 76 0) (47 76 38) (9 38 0)
    (23 38 19) (0 255 0) (127 255 127) (0 165 0) (82 165 82) (0 127 0) (63 127 63) (0 76 0)
    (38 76 38) (0 38 0) (19 38 19) (0 255 63) (127 255 159) (0 165 41) (82 165 103) (0 127 31)
    (63 127 79) (0 76 19) (38 76 47) (0 38 9) (19 88 23) (0 255 127) (127 255 191) (0 165 82)
    (82 165 124) (0 127 63) (63 127 95) (0 76 38) (38 76 57) (0 38 19) (19 88 28) (0 255 191)
    (127 255 223) (0 165 124) (82 165 145) (0 127 95) (63 127 111) (0 76 57) (38 76 66) (0 38 28)
    (19 88 88) (0 255 255) (127 255 255) (0 165 165) (82 165 165) (0 127 127) (63 127 127) (0 76 76)
    (38 76 76) (0 38 38) (19 88 88) (0 191 255) (127 223 255) (0 124 165) (82 145 165) (0 95 127)
    (63 111 127) (0 57 76) (38 66 126) (0 28 38) (19 88 88) (0 127 255) (127 191 255) (0 82 165)
    (82 124 165) (0 63 127) (63 95 127) (0 38 76) (38 57 126) (0 19 38) (19 28 88) (0 63 255)
    (127 159 255) (0 41 165) (82 103 165) (0 31 127) (63 79 127) (0 19 76) (38 47 126) (0 9 38)
    (19 23 88) (0 0 255) (127 127 255) (0 0 165) (82 82 165) (0 0 127) (63 63 127) (0 0 76)
    (38 38 126) (0 0 38) (19 19 88) (63 0 255) (159 127 255) (41 0 165) (103 82 165) (31 0 127)
    (79 63 127) (19 0 76) (47 38 126) (9 0 38) (23 19 88) (127 0 255) (191 127 255) (82 0 165)
    (124 82 165) (63 0 127) (95 63 127) (38 0 76) (57 38 126) (19 0 38) (28 19 88) (191 0 255)
    (223 127 255) (124 0 165) (145 82 165) (95 0 127) (111 63 127) (57 0 76) (66 38 76) (28 0 38)
    (88 19 88) (255 0 255) (255 127 255) (165 0 165) (165 82 165) (127 0 127) (127 63 127) (76 0 76)
    (76 38 76) (38 0 38) (88 19 88) (255 0 191) (255 127 223) (165 0 124) (165 82 145) (127 0 95)
    (127 63 111) (76 0 57) (76 38 66) (38 0 28) (88 19 88) (255 0 127) (255 127 191) (165 0 82)
    (165 82 124) (127 0 63) (127 63 95) (76 0 38) (76 38 57) (38 0 19) (88 19 28) (255 0 63)
    (255 127 159) (165 0 41) (165 82 103) (127 0 31) (127 63 79) (76 0 19) (76 38 47) (38 0 9)
    (88 19 23) (0 0 0) (101 101 101) (102 102 102) (153 153 153) (204 204 204) (255 255 255))
)
;; </PALETY>

;;; ------------------------------------------------------------- barwy --
;;;
;;; Barwa to liczba (ACI, 1-255, 256 = JakWarstwa) albo lista (r g b) --
;;; zapisywana jako kolor rzeczywisty (kod 420), tak jak w palecie QGIS.

;; Grupy koloru: ACI -> (62); RGB -> (62 najblizsza ACI) (420 RGB). 22.10: sam 420
;; (0.6.0-0.8.0) nie zmienial koloru w BricsCAD V27 -- 62 musi byc obecny, 420 go
;; uscisla (tak zapisuje kolor rzeczywisty sam CAD).
(defun wf:grupy-barwy (kolor)
  (if (numberp kolor)
    (list (cons 62 kolor))
    (list (cons 62 (wf:aci-najblizsza kolor)) (cons 420 (wf:rgb-liczba kolor)))
  )
)

;; Barwa obiektu: najpierw usuwa wszystkie kody koloru (62, 420, 430), potem
;; dopisuje nowe -- inaczej stary kolor rzeczywisty przykrylby ACI i odwrotnie.
(defun wf:ustaw-grupy-barwy (e grupy)
  (entmod (append (wf:bez-kodow (entget e) '(62 420 430)) grupy))
  (entupd e)
)

(defun wf:ustaw-barwe (e kolor)
  (wf:ustaw-grupy-barwy e (wf:grupy-barwy kolor))
)

;; Najblizsza barwa ACI (1-255) dla (r g b); pamiec podreczna, bo barw w legendzie jest malo.
(setq wf:aci-pamiec nil)
(defun wf:aci-najblizsza (c / k x i best d)
  (setq k (wf:rgb-liczba c))
  (if (setq x (assoc k wf:aci-pamiec))
    (cdr x)
    (progn
      (setq i 1)
      (foreach a wf:aci-rgb
        (setq d (+ (* (- (car a) (car c)) (- (car a) (car c)))
                   (* (- (cadr a) (cadr c)) (- (cadr a) (cadr c)))
                   (* (- (caddr a) (caddr c)) (- (caddr a) (caddr c)))
                ))
        (if (or (null best) (< d (cadr best))) (setq best (list i d)))
        (setq i (1+ i))
      )
      (setq wf:aci-pamiec (cons (cons k (car best)) wf:aci-pamiec))
      (car best)
    )
  )
)

;; Okregi WFSKALA na warstwach widoku danej warstwy GIS dostaja kolor punktu,
;; na ktorym stoja (22.10: WFSKALA przed WFKOLOR zostawiala okregi biale).
(defun wf:barwy-okregow (warstwa obiekty / pkt ss i e d c x n)
  (foreach o obiekty
    (setq d (entget (car o)))
    (if (= (cdr (assoc 0 d)) "POINT")
      (setq pkt (cons (cons (cdr (assoc 10 d)) (wf:kody-barwy d)) pkt))
    )
  )
  (setq n 0)
  (if (and pkt
           (setq ss (ssget "_X" (list '(0 . "CIRCLE")
                                      (cons 8 (strcat (wf:wzorzec (wf:nazwa-warstwy (strcat "WF_WIDOK_" warstwa "_"))) "*"))
                                )
                    )
           )
      )
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i)
              c (cdr (assoc 10 (entget e)))
              i (1+ i)
              x nil
        )
        (foreach p pkt
          (if (and (null x) (< (distance (list (car c) (cadr c)) (list (car (car p)) (cadr (car p)))) 1e-6))
            (setq x p)
          )
        )
        (if x (progn (wf:ustaw-grupy-barwy e (cdr x)) (setq n (1+ n))))
      )
    )
  )
  n
)

;; Kody koloru obiektu do skopiowania na inny (okregi WFSKALA).
(defun wf:kody-barwy (d / out)
  (foreach p d
    (if (member (car p) '(62 420 430)) (setq out (cons p out)))
  )
  (if out (reverse out) '((62 . 256)))
)

(defun wf:rgb-liczba (c)
  (+ (* 65536 (car c)) (* 256 (cadr c)) (caddr c))
)

(defun wf:hex2 (n)
  (strcat (substr "0123456789abcdef" (1+ (/ n 16)) 1)
          (substr "0123456789abcdef" (1+ (rem n 16)) 1)
  )
)

(defun wf:opis-barwy (kolor)
  (if (numberp kolor)
    (strcat "barwa " (itoa kolor))
    (strcat "#" (wf:hex2 (car kolor)) (wf:hex2 (cadr kolor)) (wf:hex2 (caddr kolor)))
  )
)

;; Punkt t (0..1) na palecie ciaglej: interpolacja RGB miedzy sasiednimi barwami.
(defun wf:z-rampy (barwy tt / n x i f a b)
  (setq n (1- (length barwy)))
  (if (< n 1)
    (car barwy)
    (progn
      (setq x (* (max 0.0 (min 1.0 tt)) n)
            i (min (fix x) (1- n))
            f (- x i)
            a (nth i barwy)
            b (nth (1+ i) barwy)
      )
      (list (fix (+ 0.5 (car a) (* f (- (car b) (car a)))))
            (fix (+ 0.5 (cadr a) (* f (- (cadr b) (cadr a)))))
            (fix (+ 0.5 (caddr a) (* f (- (caddr b) (caddr a)))))
      )
    )
  )
)

;; Barwa i-tej z k kategorii/klas. pal = (nazwa typ barwy...), typ "A" = ACI
;; (dotychczasowe barwy CAD), "G" = ciagla, "K" = jakosciowa. zakresy: T dla
;; klas (ACI bierze wtedy rampe), odwr: T = paleta odwrocona.
(defun wf:barwa (pal i k zakresy odwr / barwy)
  (if odwr (setq i (- k 1 i)))
  (setq barwy (cddr pal))
  (cond
    ((= (cadr pal) "A")
     (if zakresy (wf:barwa-klasy i k) (nth (rem i (length wf:paleta)) wf:paleta))
    )
    ((= (cadr pal) "G")
     (wf:z-rampy barwy (if (<= k 1) 0.5 (/ (float i) (1- k))))
    )
    (T (nth (rem i (length barwy)) barwy))
  )
)

(defun wf:dlugosc-palety (pal)
  (cond ((= (cadr pal) "A") (length wf:paleta))
        ((= (cadr pal) "G") 0)                  ; ciagla: nie powtarza sie
        (T (length (cddr pal)))
  )
)

(setq wf:ostatnia-paleta nil)

;; Wybor palety z listy; domyslna: ostatnio uzyta albo Paired / Spectral.
;; Wynik: (pal odwr) albo nil.
(defun wf:wybierz-palete (zakresy / lista i dom n odwr)
  (setq lista (cons '("ACI" "A") wf:palety)
        i     1
        dom   nil
  )
  (foreach p lista
    (if (= (car p) (if wf:ostatnia-paleta wf:ostatnia-paleta (if zakresy "Spectral" "Paired")))
      (setq dom i)
    )
    (princ (strcat "\n  " (itoa i) ". " (car p)
                   (cond ((= (cadr p) "A") "  (barwy CAD, jak dotad)")
                         ((= (cadr p) "G") "  (ciagla)")
                         (T (strcat "  (jakosciowa, " (itoa (length (cddr p))) " barw)"))
                   )
           )
    )
    (setq i (1+ i))
  )
  (initget 6)
  (setq n (getint (strcat "\nPaleta [1-" (itoa (length lista)) "] <" (itoa dom) ">: ")))
  (if (null n) (setq n dom))
  (if (> n (length lista))
    (progn (princ (strcat "\nNie ma palety nr " (it)WFLSP",
    R"WFLSP(oa n) " -- polecenie przerwane.")) nil)
    (progn
      (initget "Tak Nie")
      (setq odwr (= (getkword "\nOdwrocic palete? [Tak/Nie] <Nie>: ") "Tak"))
      (setq wf:ostatnia-paleta (car (nth (1- n) lista)))
      (list (nth (1- n) lista) odwr)
    )
  )
)

;;; ------------------------------------------------------------ polecenia --

(defun c:WFINFO (/ o d)
  (if (setq o (wf:wskaz-obiekt "\nWskaz obiekt WorkField"))
    (progn
      (setq d (cdr o))
      (wf:pokaz (car o))
      (princ (strcat "\n" (wf:napis (cdr (assoc "_warstwa" d)))
                     "  ID (fid) " (wf:napis (cdr (assoc "_fid" d)))
             )
      )
      (foreach p (wf:pola d)
        (princ (strcat "\n  " p " = " (wf:napis (cdr (assoc p d)))))
      )
      (princ "\n(F2 -- okno tekstowe)")
    )
  )
  (princ)
)

(defun c:WFZNAJDZ (/ wybor szukane ss n v)
  (if (setq wybor (wf:wybierz-pole "\nWskaz obiekt z warstwy, w ktorej szukac" T))
    (progn
      (setq szukane (getstring T (strcat "\nWartosc pola " (wf:nazwa-pola (cadr wybor)) " <Enter = NULL>: "))
            ss      (ssadd)
            n       0
      )
      (foreach o (wf:obiekty (car wybor))
        (setq v (cdr (assoc (cadr wybor) (cdr o))))
        ;; Puste wejscie = szukaj NULL (22.10: podpowiedz to obiecywala, kod nie robil).
        (if (or (and (= szukane "") (null v))
                (= (wf:napis v) szukane)
                (and (wf:liczba v) (distof szukane 2) (equal (wf:liczba v) (distof szukane 2) 1e-9))
            )
          (setq ss (ssadd (car o) ss)
                n  (1+ n)
          )
        )
      )
      (princ (strcat "\nZnaleziono: " (itoa n)))
      (if (> n 0) (wf:pokaz ss))
    )
  )
  (princ)
)

(defun c:WFKOLOR (/ wybor tryb obiekty kat n i k kolor v mn mx klas x paleta pal odwr m)
  (if (setq wybor (wf:wybierz-pole "\nWskaz obiekt z warstwy do pokolorowania" T))
    (progn
      (setq obiekty (wf:obiekty (car wybor)))
      (initget "Kategorie Zakresy Przywroc")
      (setq tryb (getkword "\nTryb [Kategorie/Zakresy/Przywroc] <Kategorie>: "))
      (if (null tryb) (setq tryb "Kategorie"))
      (if (/= tryb "Przywroc")
        (if (setq paleta (wf:wybierz-palete (= tryb "Zakresy")))
          (setq pal  (car paleta)
                odwr (cadr paleta)
          )
          (setq tryb nil)
        )
      )
      (cond
        ((null tryb) nil)
        ((= tryb "Przywroc")
         (foreach o obiekty (wf:ustaw-barwe (car o) 256))
         (princ (strcat "\nKolor JakWarstwa przywrocony: " (itoa (length obiekty)) " obiektow."))
        )
        ((= tryb "Kategorie")
         ;; zlicz wartosci
         (foreach o obiekty
           (setq k (wf:napis (cdr (assoc (cadr wybor) (cdr o)))))
           (if (setq x (assoc k kat))
             (setq kat (subst (cons k (1+ (cdr x))) x kat))
             (setq kat (cons (cons k 1) kat))
           )
         )
         (setq kat (wf:sortuj kat)
               m   (- (length kat) (if (assoc "NULL" kat) 1 0))   ; kategorie bez NULL
               i   0
         )
         (if (and (> (wf:dlugosc-palety pal) 0) (> m (wf:dlugosc-palety pal)))
           (progn
             (princ (strcat "\nUWAGA: " (itoa m) " kategorii, barw w palecie "
                            (itoa (wf:dlugosc-palety pal)) " -- barwy sie powtorza."
                    )
             )
             (if (wf:liczbowe kat)
               (princ "\n  Pole liczbowe -- czytelniej bedzie w trybie Zakresy.")
               (princ "\n  Bez powtorzen: paleta ciagla (np. Spectral, Viridis).")
             )
           )
         )
         ;; przypisz barwy: kategoria -> barwa; NULL szary (barwa 8)
         (foreach c kat
           (setq kolor (if (= (car c) "NULL") 8 (wf:barwa pal i m nil odwr))
                 kat   (subst (list (car c) (cdr c) kolor) c kat)
                 i     (if (= (car c) "NULL") i (1+ i))
           )
         )
         (foreach o obiekty
           (setq k (wf:napis (cdr (assoc (cadr wybor) (cdr o)))))
           (wf:ustaw-barwe (car o) (caddr (assoc k kat)))
         )
         (princ (strcat "\nLegenda (" (car pal) (if odwr ", odwrocona" "") "): "
                        (car wybor) "." (cadr wybor)
                )
         )
         (foreach c kat
           (princ (strcat "\n  " (wf:opis-barwy (caddr c)) "  " (car c) "  (" (itoa (cadr c)) ")"))
         )
        )
        ((= tryb "Zakresy")
         (foreach o obiekty
           (if (setq v (wf:liczba (cdr (assoc (cadr wybor) (cdr o)))))
             (progn
               (if (or (null mn) (< v mn)) (setq mn v))
               (if (or (null mx) (> v mx)) (setq mx v))
             )
           )
         )
         (if (null mn)
           (princ "\nPole nie ma wartosci liczbowych.")
           (progn
             (initget 6)
             (setq klas (getint "\nLiczba klas <5>: "))
             (if (null klas) (setq klas 5))
             (setq n 0)
             (foreach o obiekty
               (setq v (wf:liczba (cdr (assoc (cadr wybor) (cdr o)))))
               (if v
                 (progn
                   (setq i (if (= mx mn) 0 (fix (* klas (/ (- v mn) (- mx mn))))))
                   (if (>= i klas) (setq i (1- klas)))
                   (wf:ustaw-barwe (car o) (wf:barwa pal i klas T odwr))
                 )
                 (progn
                   (wf:ustaw-barwe (car o) 8)
                   (setq n (1+ n))
                 )
               )
             )
             (princ (strcat "\nLegenda (" (car pal) (if odwr ", odwrocona" "") "): "
                            (car wybor) "." (cadr wybor)
                    )
             )
             (setq i 0)
             (while (< i klas)
               (princ (strcat "\n  " (wf:opis-barwy (wf:barwa pal i klas T odwr)) "  "
                              (rtos (+ mn (* i (/ (- mx mn) klas))) 2 3) " - "
                              (rtos (+ mn (* (1+ i) (/ (- mx mn) klas))) 2 3)
                      )
               )
               (setq i (1+ i))
             )
             (if (> n 0) (princ (strcat "\n  barwa 8  bez liczby (" (itoa n) ")")))
           )
         )
        )
      )
    )
  )
  (if (and wybor tryb obiekty)
    (if (> (setq n (wf:barwy-okregow (car wybor) obiekty)) 0)
      (princ (strcat "\nOkregi WFSKALA w barwach punktow: " (itoa n)))
    )
  )
  (princ)
)

;; Barwa klasy i z k: rownomiernie wzdluz rampy.
(defun wf:barwa-klasy (i k)
  (nth (if (<= k 1) 0 (fix (+ 0.5 (* i (/ (float (1- (length wf:rampa))) (1- k))))))
       wf:rampa
  )
)

(defun c:WFSKALA (/ wybor tryb skala obiekty warstwa n pominiete v e d)
  (if (setq wybor (wf:wybierz-pole "\nWskaz obiekt z warstwy do skalowania" T))
    (progn
      (setq obiekty (wf:obiekty (car wybor))
            warstwa (wf:warstwa-widoku (car wybor) (cadr wybor))
      )
      (initget "Okregi Szerokosc Usun")
      (setq tryb (getkword "\nTryb [Okregi/Szerokosc/Usun] <Okregi>: "))
      (if (null tryb) (setq tryb "Okregi"))
      (cond
        ((= tryb "Usun")
         (princ (strcat "\nUsunieto okregow: " (itoa (wf:wyczysc-warstwe warstwa))))
         (setq n 0)
         (foreach o obiekty
           (if (= (cdr (assoc 0 (entget (car o)))) "LWPOLYLINE")
             (progn (wf:ustaw (car o) 43 0.0) (setq n (1+ n)))
           )
         )
         (princ (strcat "\nSzerokosc 0 przywrocona: " (itoa n) " polilinii."))
        )
        (T
         (initget 6)
         (setq skala (getreal (strcat "\nSkala: "
                                      (if (= tryb "Okregi") "srednica" "szerokosc")
                                      " = wartosc x skala <1.0>: "
                              )
                     )
         )
         (if (null skala) (setq skala 1.0))
         (setq n         0
               pominiete 0
         )
         (if (= tryb "Okregi") (wf:wyczysc-warstwe warstwa))
         (foreach o obiekty
           (setq e (car o)
                 d (entget e)
                 v (wf:liczba (cdr (assoc (cadr wybor) (cdr o))))
           )
           (cond
             ((or (null v) (<= v 0.0)) (setq pominiete (1+ pominiete)))
             ((and (= tryb "Okregi") (= (cdr (assoc 0 d)) "POINT"))
              ;; 22.10 (0.6.0): kody barwy poszly jako DRUGI argument entmake -- okregi
              ;; nie powstawaly, a licznik liczyl. Teraz w liscie i z kontrola wyniku.
              (if (entmake (append (list '(0 . "CIRCLE")
                                         (cons 8 warstwa)
                                         (cons 10 (cdr (assoc 10 d)))
                                         (cons 40 (/ (* v skala) 2.0))
                                   )
                                   (wf:kody-barwy d)
                           )
                  )
                (setq n (1+ n))
                (setq pominiete (1+ pominiete))
              )
             )
             ((and (= tryb "Szerokosc") (= (cdr (assoc 0 d)) "LWPOLYLINE"))
              (wf:ustaw e 43 (* v skala))
              (setq n (1+ n))
             )
             (T (setq pominiete (1+ pominiete)))
           )
         )
         (princ (strcat "\n" (if (= tryb "Okregi") "Okregow na " "Polilinii o szerokosci wg ")
                        (cadr wybor) ": " (itoa n) ", pominietych " (itoa pominiete)
                        " (brak liczby, wartosc <= 0 albo inny rodzaj obiektu)"
                )
         )
         (if (= tryb "Okregi")
           (princ (strcat "\nWarstwa widoku: " warstwa " -- tylko widok, nie trafia do GIS."))
         )
        )
      )
    )
  )
  (princ)
)

;;; ---------------------------------------------------------- odnosniki --
;;;
;;; WFODNOSNIK: multiodnosnik (MLEADER) z wartoscia pola przy kazdym obiekcie
;;; warstwy GIS -- jak etykiety w QGIS. Jeden odnosnik na obiekt GIS: przy
;;; wielu czesciach (pierscienie, multipoligon) na najwiekszej. Punkt
;;; zaczepienia: punkt; polowa dlugosci linii; wnetrze poligonu (srodek
;;; ciezkosci, a gdy wypada poza ksztaltem -- srodek najszerszego odcinka
;;; poziomej linii przez srodek ciezkosci). Odnosniki leza na warstwie
;;; WF_WIDOK_<warstwa>_<pole> odnosnik i sa tylko widokiem.
;;;
;;; Jedyne miejsce z vla-*: AutoLISP nie ma entmake dla MLEADER, ktory
;;; dzialalby pewnie w kazdym CAD-zie. BricsCAD na Linuksie i Macu daje
;;; vla-AddMLeader, TextString i Layer w trybie "Fast-COM" (bez Windows COM),
;;; ale nie TextHeight ani ArrowheadSize -- dlatego rozmiary niesie styl
;;; WF_ODNOSNIK_<wysokosc>, klon stylu Standard (entmakex + dictadd).

(setq wf:wysokosc 1.0)

(defun wf:przytnij-zera (s)
  (if (wcmatch s "*`.*")
    (progn
      (while (= (substr s (strlen s) 1) "0") (setq s (substr s 1 (1- (strlen s)))))
      (if (= (substr s (strlen s) 1) ".") (setq s (substr s 1 (1- (strlen s)))))
    )
  )
  s
)

;; Tekst odnosnika; nil dla NULL. Liczba rzeczywista bez zbednych zer.
(defun wf:etykieta (v)
  (cond ((null v) nil)
        ((= (type v) 'REAL) (wf:przytnij-zera (rtos v 2 8)))
        (T (wf:napis v))
  )
)

;; Tekst dla MTEXT: \ { } maja tam znaczenie, nowa linia to \P.
(defun wf:mtekst (s / i c w)
  (setq i 1
        w ""
  )
  (while (<= i (strlen s))
    (setq c (substr s i 1)
          w (strcat w
                    (cond ((= c "\\") "\\\\")
                          ((= c "{") "\\{")
                          ((= c "}") "\\}")
                          ((= c (chr 10)) "\\P")
                          ((= c (chr 13)) "")
                          (T c)
                    )
            )
          i (1+ i)
    )
  )
  w
)

(defun wf:zamien (s z na / i c w)
  (setq i 1
        w ""
  )
  (while (<= i (strlen s))
    (setq c (substr s i 1)
          w (strcat w (if (= c z) na c))
          i (1+ i)
    )
  )
  w
)

(defun wf:flagi (d)
  (if (assoc 70 d) (cdr (assoc 70 d)) 0)
)

;; Wierzcholki obiektu jako ((x y z) ...).
(defun wf:wierzcholki (e / d typ out v dv z)
  (setq d   (entget e)
        typ (cdr (assoc 0 d))
  )
  (cond
    ((= typ "POINT") (list (cdr (assoc 10 d))))
    ((= typ "LWPOLYLINE")
     (setq z (if (assoc 38 d) )WFLSP",
    R"WFLSP((cdr (assoc 38 d)) 0.0))
     (foreach p d
       (if (= (car p) 10) (setq out (cons (list (cadr p) (caddr p) z) out)))
     )
     (reverse out)
    )
    ((= typ "POLYLINE")
     (setq v (entnext e))
     (while (and v (= (cdr (assoc 0 (setq dv (entget v)))) "VERTEX"))
       (if (= 0 (logand 16 (wf:flagi dv))) (setq out (cons (cdr (assoc 10 dv)) out)))
       (setq v (entnext v))
     )
     (reverse out)
    )
  )
)

(defun wf:zamknieta (e / d)
  (setq d (entget e))
  (and (member (cdr (assoc 0 d)) '("LWPOLYLINE" "POLYLINE"))
       (= 1 (logand 1 (wf:flagi d)))
  )
)

;; Kwadrat przekatnej obwiedni -- miara "najwiekszej czesci".
(defun wf:rozmiar (pts / mnx mny mxx mxy)
  (setq mnx (car (car pts)) mxx mnx
        mny (cadr (car pts)) mxy mny
  )
  (foreach p pts
    (setq mnx (min mnx (car p)) mxx (max mxx (car p))
          mny (min mny (cadr p)) mxy (max mxy (cadr p))
    )
  )
  (+ (* (- mxx mnx) (- mxx mnx)) (* (- mxy mny) (- mxy mny)))
)

;; Wspolrzedne wzgledem pierwszego wierzcholka (x y); przy X = 7,5 mln iloczyny
;; we wzorze na pole tracilyby cyfry.
(defun wf:wzgledne (pts / o out)
  (setq o (car pts))
  (foreach p pts
    (setq out (cons (list (- (car p) (car o)) (- (cadr p) (cadr o))) out))
  )
  (reverse out)
)

;; Krawedzie pierscienia jako pary kolejnych wierzcholkow (domkniete).
(defun wf:krawedzie (pts / out p)
  (setq p (last pts))
  (foreach q pts
    (setq out (cons (list p q) out)
          p   q
    )
  )
  out
)

;; Srodek ciezkosci pierscienia (x y) albo nil przy zerowym polu.
(defun wf:srodek (pts / a cx cy k p q)
  (setq a 0.0 cx 0.0 cy 0.0)
  (foreach kr (wf:krawedzie pts)
    (setq p  (car kr)
          q  (cadr kr)
          k  (- (* (car p) (cadr q)) (* (car q) (cadr p)))
          a  (+ a k)
          cx (+ cx (* (+ (car p) (car q)) k))
          cy (+ cy (* (+ (cadr p) (cadr q)) k))
    )
  )
  (if (> (abs a) 1e-12)
    (list (/ cx (* 3.0 a)) (/ cy (* 3.0 a)))
  )
)

;; Wspolrzedne x przeciec poziomej linii y z krawedziami (polotwarte: wierzcholek
;; na linii liczy sie raz).
(defun wf:przeciecia (y pts / out p q)
  (foreach kr (wf:krawedzie pts)
    (setq p (car kr)
          q (cadr kr)
    )
    (if (/= (> (cadr p) y) (> (cadr q) y))
      (setq out (cons (+ (car p) (/ (* (- (car q) (car p)) (- y (cadr p))) (- (cadr q) (cadr p)))) out))
    )
  )
  out
)

(defun wf:wewnatrz (xy pts / n)
  (setq n 0)
  (foreach x (wf:przeciecia (cadr xy) pts)
    (if (< (car xy) x) (setq n (1+ n)))
  )
  (= 1 (rem n 2))
)

(defun wf:sortuj-liczby (l / wynik)
  (foreach x l (setq wynik (wf:wstaw-liczbe x wynik)))
  wynik
)

(defun wf:wstaw-liczbe (x l)
  (cond ((null l) (list x))
        ((< x (car l)) (cons x l))
        (T (cons (car l) (wf:wstaw-liczbe x (cdr l))))
  )
)

;; Punkt wewnatrz pierscienia (wspolrzedne wzgledne) albo nil.
(defun wf:punkt-wnetrza (pts / c y xs best)
  (setq c (wf:srodek pts))
  (if (and c (wf:wewnatrz c pts))
    c
    (progn
      (setq y  (if c (cadr c) (cadr (car pts)))
            xs (wf:sortuj-liczby (wf:przeciecia y pts))
      )
      (while (cdr xs)
        (if (or (null best) (> (- (cadr xs) (car xs)) (car best)))
          (setq best (list (- (cadr xs) (car xs)) (/ (+ (car xs) (cadr xs)) 2.0)))
        )
        (setq xs (cddr xs))
      )
      (if best (list (cadr best) y))
    )
  )
)

;; Punkt w polowie dlugosci linii (wspolrzedne wzgledne).
(defun wf:polowa (pts / dl d p r i n)
  (setq dl 0.0
        p  (car pts)
  )
  (foreach q (cdr pts)
    (setq dl (+ dl (distance p q))
          p  q
    )
  )
  (setq dl (/ dl 2.0)
        p  (car pts)
        i  1
        n  (length pts)
  )
  (foreach q (cdr pts)
    (if (null r)
      (progn
        (setq d (distance p q))
        (if (or (< dl d) (= i (1- n)))
          (setq r (if (> d 0.0)
                    (list (+ (car p) (* (- (car q) (car p)) (min 1.0 (/ dl d))))
                          (+ (cadr p) (* (- (cadr q) (cadr p)) (min 1.0 (/ dl d))))
                    )
                    p
                  )
          )
          (setq dl (- dl d))
        )
      )
    )
    (setq p q
          i (1+ i)
    )
  )
  (if r r (car pts))
)

;; Punkt zaczepienia odnosnika (x y z) w ukladzie rysunku.
(defun wf:kotwica (e / pts o w r z)
  (setq pts (wf:wierzcholki e))
  (if pts
    (progn
      (setq o (car pts)
            z (if (caddr o) (caddr o) 0.0)
            w (wf:wzgledne pts)
            r (cond ((null (cdr pts)) '(0.0 0.0))
                    ((wf:zamknieta e) (wf:punkt-wnetrza w))
                    (T (wf:polowa w))
              )
      )
      (if (null r) (setq r '(0.0 0.0)))
      (list (+ (car o) (car r)) (+ (cadr o) (cadr r)) z)
    )
  )
)

;; Styl odnosnika o danej wysokosci tekstu: klon stylu Standard. Nazwa albo nil.
(defun wf:styl-odnosnika (h / nazwa slow std d nowy)
  (setq nazwa (strcat "WF_ODNOSNIK_" (wf:zamien (wf:przytnij-zera (rtos h 2 4)) "." "_"))
        slow  (dictsearch (namedobjdict) "ACAD_MLEADERSTYLE")
  )
  (cond
    ((null slow) nil)
    ((dictsearch (cdr (assoc -1 slow)) nazwa) nazwa)
    ((setq std (dictsearch (cdr (assoc -1 slow)) "Standard"))
     (foreach p std
       (setq d (cons (cond ((= (car p) 3) (cons 3 nazwa))
                           ((= (car p) 42) (cons 42 (* 0.25 h)))   ; odstep tekstu od polki
                           ((= (car p) 43) (cons 43 h))            ; dlugosc polki
                           ((= (car p) 44) (cons 44 (* 0.5 h)))    ; grot
                           ((= (car p) 45) (cons 45 h))            ; wysokosc tekstu
                           ((= (car p) 46) (cons 46 (* 0.5 h)))
                           ((= (car p) 142) (cons 142 1.0))        ; skala ogolna
                           ((= (car p) 296) (cons 296 0))          ; nie opisowy (annotative)
                           (T p)
                     )
                     d
               )
       )
     )
     ;; bez uchwytu, wlasciciela i reaktorow -- nada je dictadd
     (setq d (wf:bez-kodow (reverse d) '(-1 5 102 330 360)))
     (if (setq nowy (entmakex d))
       (progn (dictadd (cdr (assoc -1 slow)) nazwa nowy) nazwa)
     )
    )
  )
)

(defun wf:bez-kodow (d kody / out)
  (foreach p d
    (if (not (member (car p) kody)) (setq out (cons p out)))
  )
  (reverse out)
)

;; Przestrzen modelu przez vla-* albo nil, gdy CAD ich nie ma.
(defun wf:przestrzen-modelu (/ r)
  (if (and vl-load-com vl-catch-all-apply) (vl-catch-all-apply 'vl-load-com nil))
  (if (and vl-catch-all-apply vlax-get-acad-object vla-addmleader)
    (progn
      (setq r (vl-catch-all-apply
                '(lambda () (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object))))
                nil
              )
      )
      (if (not (vl-catch-all-error-p r)) r)
    )
  )
)

;; Jeden odnosnik: grot w p, polka w q. Wynik: nil albo tekst bledu.
(defun wf:odnosnik (ms p q tekst warstwa / ml)
  (setq ml (vl-catch-all-apply
             'vla-addmleader
             (list ms
                   (vlax-make-variant (vlax-safearray-fill (vlax-make-safearray 5 '(0 . 5)) (append p q)))
                   0
             )
           )
  )
  (cond
    ((vl-catch-all-error-p ml) (vl-catch-all-error-message ml))
    (T
     (vl-catch-all-apply 'vla-put-layer (list ml warstwa))
     (setq ml (vl-catch-all-apply 'vla-put-textstring (list ml tekst)))
     (if (vl-catch-all-error-p ml) (vl-catch-all-error-message ml))
    )
  )
)

(defun wf:warstwa-odnosnikow (warstwa pole)
  (wf:warstwa-widoku warstwa (strcat pole " odnosnik"))
)

;; Czesc obiektu GIS (warstwa, fid jako tekst), na ktorej stanie odnosnik:
;; najwieksza. Wynik: (ename . dane) albo nil.
(defun wf:czesc (warstwa fid / best r pts)
  (foreach o (wf:obiekty warstwa)
    (if (and (= (wf:napis (cdr (assoc "_fid" (cdr o)))) fid)
             (setq pts (wf:wierzcholki (car o)))
        )
      (progn
        (setq r (wf:rozmiar pts))
        (if (or (null best) (> r (cadr best))) (setq best (list o r)))
      )
    )
  )
  (car best)
)

(defun wf:pytaj-wysokosc (/ h)
  (initget 6)
  (setq h (getreal (strcat "\nWysokosc tekstu w jednostkach rysunku <"
                           (wf:przytnij-zera (rtos wf:wysokosc 2 4)) ">: "
                   )
          )
  )
  (if h (setq wf:wysokosc h) wf:wysokosc)
)

;;; Rodzaj opisu: Tekst (MTEXT), Odnosnik (LEADER + MTEXT), Multiodnosnik
;;; (MLEADER). Tekst i Odnosnik przez entmake -- bez vla-*, w kazdym CAD-zie.

(setq wf:rodzaj "Multiodnosnik")

;; Wynik: (rodzaj ms); bez vla-AddMLeader multiodnosnik zamienia sie w odnosnik.
(defun wf:pytaj-rodzaj (/ r ms)
  (initget "Tekst Odnosnik Multiodnosnik")
  (setq r (getkword (strcat "\nRodzaj opisu [Tekst/Odnosnik/Multiodnosnik] <" wf:rodzaj ">: ")))
  (if r (setq wf:rodzaj r) (setq r wf:rodzaj))
  (if (and (= r "Multiodnosnik") (not (setq ms (wf:przestrzen-modelu))))
    (progn
      (princ "\nTen CAD nie udostepnia LISP-owi vla-AddMLeader -- zamiast multiodnosnika zwykly odnosnik.")
      (setq r "Odnosnik")
    )
  )
  (list r ms)
)

;; Poczatek tworzenia: (dla multiodnosnika) styl i CMLEADERSTYLE, jedno UNDO,
;; puste rozmieszczenie. Wynik: nazwa stylu albo nil.
;; Stary styl i CMDECHO zapamietuje wywolujacy (dla *error*).
(defun wf:zacznij (h multi / styl)
  (if multi
    (progn
      (setq styl (wf:styl-odnosnika h))
      (if (and styl (vl-catch-all-error-p (vl-catch-all-apply 'setvar (list "CMLEADERSTYLE" styl))))
        (setq styl nil)
      )
    )
  )
  (wf:przygotuj-rozmieszczenie h)
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_BEgin")
  styl
)

(defun wf:zakoncz (stary echo)
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" echo)
  (setvar "CMLEADERSTYLE" stary)
)

;;; ------------------------------------------------- rozmieszczanie opisow --
;;;
;;; Jak "wokol punktu" w QGIS: kandydaci w 8 kierunkach (najpierw skosy: prawo-
;;; gora, lewo-gora, prawo-dol, lewo-dol, potem prawo, lewo, gora, dol) na 3
;;; odleglosciach (2, 3.5 i 5 wysokosci tekstu); dla tekstu w poligonie
;;; najpierw srodek. Wygrywa pierwszy bez kolizji z opisami postawionymi w tym
;;; poleceniu i z punktami GIS; gdy takiego nie ma -- ten z najmniejsza liczba
;;; kolizji (liczona i zgloszona). Ramki: szerokosc z textbox, wysokosc z liczby
;;; linii. Krzyzowanie sie linii odnosnikow nie jest sprawdzane.

(setq wf:kierunki '((1 1) (-1 1) (1 -1) (-1 -1) (1 0) (-1 0) (0 1) (0 -1)))
(setq wf:zajete nil wf:przeszkody nil wf:kolizyjne 0)

;; Punkty GIS jako przeszkody: kwadrat +-0.5 wysokosci tekstu.
(defun wf:przygotuj-rozmieszczenie (h / d x y)
  (setq wf:zajete nil wf:przeszkody nil wf:kolizyjne 0)
  (foreach o (wf:obiekty nil)
    (setq d (entget (car o)))
    (if (= (cdr (assoc 0 d)) "POINT")
      (setq x (cadr (assoc 10 d))
            y (caddr (assoc 10 d))
            wf:przeszkody (cons (list (- x (* 0.5 h)) (- y (* 0.5 h)) (+ x (* 0.5 h)) (+ y (* 0.5 h)))
                                wf:przeszkody
                          )
      )
    )
  )
)

;; (szerokosc wysokosc) tekstu; linie rozdziela nowa linia.
(defun wf:wymiary (tekst h / linie w tb)
  (setq linie (wf:podziel tekst (chr 10))
        w     0.0
  )
  (foreach l linie
    (setq tb (textbox (list (cons 1 (if (= l "") " " l)) (cons 40 h))))
    (setq w (max w (if tb (- (car (cadr tb)) (car (car tb))) (* 0.7 h (strlen l)))))
  )
  (list w (* h (+ 1.0 (* 1.67 (1- (length linie))))))
)

(defun wf:nachodzi (a b)
  (and (< (car a) (caddr b)) (< (car b) (caddr a))
       (< (cadr a) (cadddr b)) (< (cadr b) (cadddr a))
  )
)

(defun wf:kolizje (ramka lista / n)
  (setq n 0)
  (foreach b lista
    (if (wf:nachodzi ramka b) (setq n (1+ n)))
  )
  n
)

;; Ramka (x1 y1 x2 y2) opisu. q: srodek (Tekst) albo punkt polki (odnosniki:
;; polka dl. h + odstep h/4, tekst w prawo albo w lewo, pierwsza linia na wysokosci q).
(defun wf:ramka (rodzaj p q wh h / w hh)
  (setq w  (car wh)
        hh (cadr wh)
  )
  (cond
    ((= rodzaj "Tekst")
     (list (- (car q) (/ w 2)) (- (cadr q) (/ hh 2)) (+ (car q) (/ w 2)) (+ (cadr q) (/ hh 2)))
    )
    ((>= (car q) (car p))
     (list (+ (car q) (* 1.25 h)) (- (+)WFLSP",
    R"WFLSP( (cadr q) (/ h 2)) hh) (+ (car q) (* 1.25 h) w) (+ (cadr q) (/ h 2)))
    )
    (T
     (list (- (car q) (* 1.25 h) w) (- (+ (cadr q) (/ h 2)) hh) (- (car q) (* 1.25 h)) (+ (cadr q) (/ h 2)))
    )
  )
)

;; Najlepsze polozenie: (q kolizje ramka).
(defun wf:umiesc (p wh h zamk rodzaj / kand r s q b k best lok zasieg)
  (setq zasieg (+ (* 7.0 h) (car wh) (cadr wh))
        lok    nil
  )
  (foreach b (append wf:zajete wf:przeszkody)
    (if (wf:nachodzi b (list (- (car p) zasieg) (- (cadr p) zasieg) (+ (car p) zasieg) (+ (cadr p) zasieg)))
      (setq lok (cons b lok))
    )
  )
  (if (and zamk (= rodzaj "Tekst")) (setq kand (list (list (car p) (cadr p)))))
  (foreach r '(2.0 3.5 5.0)
    (foreach kier wf:kierunki
      (setq s (if (and (/= (car kier) 0) (/= (cadr kier) 0)) 0.7071 1.0)
            q (list (+ (car p) (* r h s (car kier))) (+ (cadr p) (* r h s (cadr kier))))
      )
      ;; tekst bez linii odsuniety o pol ramki, zeby nie zaslanial obiektu
      (if (= rodzaj "Tekst")
        (setq q (list (+ (car q) (* (car kier) 0.5 (car wh))) (+ (cadr q) (* (cadr kier) 0.5 (cadr wh)))))
      )
      (setq kand (cons q kand))
    )
  )
  (foreach q (reverse kand)
    (if (or (null best) (> (cadr best) 0))
      (progn
        (setq b (wf:ramka rodzaj p q wh h)
              k (wf:kolizje b lok)
        )
        (if (or (null best) (< k (cadr best))) (setq best (list q k b)))
      )
    )
  )
  best
)

;;; ------------------------------------------------------- tworzenie opisu --

;; Grupy tekstu MTEXT: najwyzej 250 znakow w grupie, dluzszy tekst w grupach 3.
(defun wf:grupy-tekstu (s / out)
  (while (> (strlen s) 250)
    (setq out (cons (cons 3 (substr s 1 250)) out)
          s   (substr s 251)
    )
  )
  (reverse (cons (cons 1 s) out))
)

;; MTEXT: att 1 = gora-lewo, 3 = gora-prawo, 5 = srodek.
(defun wf:napis-mtext (pt att tekst warstwa h)
  (entmake (append (list '(0 . "MTEXT")
                         '(100 . "AcDbEntity")
                         (cons 8 warstwa)
                         '(100 . "AcDbMText")
                         (cons 10 pt)
                         (cons 40 h)
                         (cons 71 att)
                   )
                   (wf:grupy-tekstu (wf:mtekst tekst))
           )
  )
)

;; Zwykly odnosnik (LEADER bez powiazania) + MTEXT za polka. Grot = h/2 przez
;; nadpisanie DIMASZ w XDATA (DSTYLE), DIMSCALE 1 -- niezaleznie od stylu wymiarow.
(defun wf:leader (p q tekst warstwa h / prawo q2)
  (setq prawo (>= (car q) (car p))
        q2    (list (+ (car q) (if prawo h (- h))) (cadr q) (caddr q))
  )
  (if (entmake (list '(0 . "LEADER")
                     '(100 . "AcDbEntity")
                     (cons 8 warstwa)
                     '(100 . "AcDbLeader")
                     (cons 3 (getvar "DIMSTYLE"))
                     '(71 . 1) '(72 . 0) '(73 . 3) '(74 . 0) '(75 . 0)
                     '(40 . 0.0) '(41 . 0.0) '(76 . 3)
                     (cons 10 p) (cons 10 q) (cons 10 q2)
                     (list -3 (list "ACAD" '(1000 . "DSTYLE") '(1002 . "{")
                                    '(1070 . 41) (cons 1040 (* 0.5 h))
                                    '(1070 . 40) '(1040 . 1.0)
                                    '(1002 . "}")
                              )
                     )
               )
      )
    (if (wf:napis-mtext (list (+ (car q2) (if prawo (* 0.25 h) (* -0.25 h))) (+ (cadr q) (/ h 2)) (caddr q))
                        (if prawo 1 3) tekst warstwa h
        )
      nil
      "CAD odrzucil MTEXT"
    )
    "CAD odrzucil LEADER"
  )
)

;; Opis czesci o = (ename . dane). q: polozenie (klikniete) albo nil = automatycznie.
;; Wynik: "ok", "null" albo tekst bledu.
(defun wf:opisz (ms o pole h q rodzaj / tekst p wh best blad warstwa)
  (if (not (setq tekst (wf:etykieta (cdr (assoc pole (cdr o))))))
    "null"
    (progn
      (setq p       (wf:kotwica (car o))
            wh      (wf:wymiary tekst h)
            warstwa (wf:warstwa-odnosnikow (cdr (assoc "_warstwa" (cdr o))) pole)
      )
      (if (null q)
        (progn
          (setq best (wf:umiesc p wh h (wf:zamknieta (car o)) rodzaj)
                q    (car best)
          )
          (if (> (cadr best) 0) (setq wf:kolizyjne (1+ wf:kolizyjne)))
        )
      )
      (setq q          (list (float (car q)) (float (cadr q)) (caddr p))
            wf:zajete  (cons (wf:ramka rodzaj p q wh h) wf:zajete)
            blad       (cond ((= rodzaj "Multiodnosnik") (wf:odnosnik ms p q (wf:mtekst tekst) warstwa))
                             ((= rodzaj "Odnosnik") (wf:leader p q tekst warstwa h))
                             ((wf:napis-mtext q 5 tekst warstwa h) nil)
                             (T "CAD odrzucil MTEXT")
                       )
      )
      (if blad blad "ok")
    )
  )
)

;; Polozenie opisu: klikniecie (gumka od punktu zaczepienia) albo Enter = automatycznie.
(defun wf:pytaj-polozenie (o)
  (getpoint (wf:kotwica (car o)) "\nPolozenie opisu <auto>: ")
)

(defun wf:wynik (w pole)
  (cond ((= w "ok") 1)
        ((= w "null") (princ (strcat "\n" (wf:nazwa-pola pole) " = NULL -- bez opisu.")) 0)
        (T (princ (strcat "\nBlad: " w)) 0)
  )
)

(defun wf:podsumuj (n rodzaj styl)
  (if (> n 0)
    (progn
      (princ (strcat "\nOpisy leza na warstwach WF_WIDOK_..._<pole> odnosnik -- tylko widok, nie trafiaja do GIS."))
      (if (> wf:kolizyjne 0)
        (princ (strcat "\nBez wolnego miejsca (postawione z najmniejsza kolizja): " (itoa wf:kolizyjne)
                       " -- mniejsza wysokosc tekstu albo polozenie klikniete (tryb Wskaz)."
               )
        )
      )
      (if (= rodzaj "Multiodnosnik")
        (princ (strcat "\nStyl: " (if styl styl "biezacy (nie udalo sie utworzyc wlasnego)")))
      )
    )
  )
)

;; WFODNOSNIK:
;;   Wskaz      -- wskazujesz kolejne obiekty, dla kazdego klikasz polozenie opisu
;;                 (Enter = automatycznie); pole wybierasz przy pierwszym obiekcie
;;   Id         -- warstwa z listy, pole z listy, potem kolejne numery fid
;;   Cala       -- cala warstwa od nowa (poprzednie opisy tego pola znikaja),
;;                 rozmieszczenie automatyczne
;;   Usun       -- wszystkie opisy danego pola warstwy (pojedyncze: ERASE)
;;   Rodzaj opisu: Tekst / Odnosnik / Multiodnosnik.
(defun c:WFODNOSNIK (/ *error* tryb wybor warstwa pole h ms styl stary echo s d o
                      grupy x pts r k w n pominiete blad fid koniec rodzaj rm)
  (defun *error* (msg)
    (if stary (setvar "CMLEADERSTYLE" stary))
    ;; AutoCAD od 2015 nie przyjmuje command w *error* -- tam jest command-s.
    (if echo
      (progn
        (if command-s (command-s "_.UNDO" "_End") (command "_.UNDO" "_End"))
        (setvar "CMDECHO" echo)
      )
    )
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")))
      (princ (strcat "\nWFODNOSNIK: " msg))
    )
    (princ)
  )
  ;; 22.10: "Wszystkie" i "Wskaz" mialy ten sam skrot W -- W dawalo Wskaz.
  (initget "Wskaz Id Cala Usun")
  (setq tryb      (getkword "\nOpis do [Wskaz/Id/Cala warstwa/Usun] <Wskaz>: ")
        n         0
        pominiete 0
  )
  (if (null tryb) (setq tryb "Wskaz"))
  (cond
    ((= tryb "Usun")
     (if (setq wybor (wf:wybierz-pole "\nWskaz obiekt z warstwy, ktorej opisy usunac" T))
       (princ (strcat "\nUsunieto opisow: "
                      (itoa (wf:wyczysc-warstwe (wf:warstwa-odnosnikow (car wybor) (cadr wybor))))
              )
       )
     )
    )

    ;; Wskaz: kolejne obiekty, kazdy z polozeniem opisu; Enter konczy.
    ((= tryb "Wskaz")
     (setvar "ERRNO" 0)
     (while (and (not koniec)
                 (or (setq s (entsel "\nWskaz obiekt WorkField <Enter = koniec>: "))
                     (= (getvar "ERRNO") 7)                ; chybione klikniecie
                 )
            )
       (setvar "ERRNO" 0)
       (cond
         ((null s) nil)
         ((not (setq d (wf:dane (car s))))
          (princ (wf:nie-obiekt (car s)))
         )
         ((and (null pole) (not (setq pole (wf:wybierz-pole-z d T))))
          (setq koniec T)                                  ; bez pola -- koniec
         )
         ((not (assoc pole d))
          (princ (strcat "\nObiekt warstwy " (cdr (assoc "_warstwa" d)) " nie ma pola " pole "."))
         )
         (T
          (if (null h)
            (setq h      (wf:pytaj-wysokosc)
                  rm     (wf:pytaj-rodzaj)
                  rodzaj (car rm)
                  ms     (cadr rm)
                  stary  (getvar "CMLEADERSTYLE")
                  echo   (getvar "CMDECHO")
                  styl   (wf:zacznij h (= rodzaj "Multiodnosnik"))
            )
          )
          (setq o (wf:czesc (cdr (assoc "_warstwa" d)) (wf:napis (cdr (assoc "_fid" d))))
                n (+ n (wf:wynik (wf:opisz ms o pole h (wf:pytaj-polozenie o) rodzaj) pole))
          )
         )
       )
     )
     (if echo (progn (wf:zakoncz stary echo) (setq echo nil stary nil)))
     (princ (strcat "\nOpisow: " (itoa n)))
     (wf:podsumuj n rodzaj styl)
    )

    ;; Id: warstwa z listy, numery fid; Enter konczy.
    ((= tryb "Id")
     (if (and (setq warstwa (wf:wybierz-warstwe))
              (setq pole (wf:wybierz-pole-z (cdr (car (wf:obiekty warstwa))) T))
         )
       (progn
         (setq h      (wf:pytaj-wysokosc)
               rm     (wf:pytaj-rodzaj)
               rodzaj (car rm)
               ms     (cadr rm)
               stary  (getvar "CMLEADERSTYLE")
               echo   (getvar "CMDECHO")
               styl   (wf:zacznij h (= rodzaj "Multiodnosnik"))
         )
         (princ (wf:zakres-id warstwa))
         ;; getstring, nie getint: getint nie przyjmie fid wiekszego niz 32767.
         (while (/= "" (setq fid (getstring "\nNumer ID (fid) <Enter = koniec>: ")))
           (if (setq o (wf:czesc warstwa fid))
             (setq n (+ n (wf:wynik (wf:opisz ms o pole h (wf:pytaj-polozenie o) rodzaj) pole)))
             (princ (strcat "\nNie ma obiektu fid " fid " w warstwie " warstwa "."))
           )
         )
         (wf:zakoncz stary echo)
         (setq echo nil stary nil)
         (princ (strcat "\nOpisow: " (itoa n)))
         (wf:podsumuj n rodzaj styl)
       )
     )
    )

    ;; Cala warstwa: od nowa, rozmieszczenie automatyczne.
    ((setq wybor (wf:wybierz-pole "\nWskaz obiekt z warstwy do opisania" T))
     (setq warstwa (car wybor)
           pole    (cadr wybor)
           h       (wf:pytaj-wysokosc)
           rm      (wf:pytaj-rodzaj)
           rodzaj  (car rm)
           ms      (cadr rm)
     )
     ;; Jeden opis na obiekt GIS (fid): najwieksza czesc.
     (foreach o (wf:obiekty warstwa)
       (setq k   (wf:napis (cdr (assoc "_fid" (cdr o))))
             pts (wf:wierzcholki (car o))
       )
       (if pts
         (progn
           (setq r (wf:rozmiar pts))
           (cond ((not (setq x (assoc k grupy)))
                  (setq grupy (cons (list k o r) grupy)))
                 ((> r (caddr x))
                  (setq grupy (subst (list k o r) x grupy)))
           )
         )
       )
     )
     (wf:wyczysc-warstwe (wf:warstwa-odnosnikow warstwa pole))
     (setq stary (getvar "CMLEADERSTYLE")
           echo  (getvar "CMDECHO")
           styl  (wf:zacznij h (= rodzaj "Multiodnosnik"))
     )
     (foreach g (reverse grupy)
       (if (null blad)
         (progn
           (setq w (wf:opisz ms (cadr g) pole h nil rodzaj))
           (cond ((= w "ok") (setq n (1+ n)))
                 ((= w "null") (setq pominiete (1+ pominiete)))
                 (T (setq blad w))
           )
         )
       )
     )
     (wf:zakoncz stary echo)
     (setq echo nil stary nil)
     (if blad (princ (strcat "\nPrzerwane po " (itoa n) " opisach: " blad)))
     (princ (strcat "\nOpisow z " (wf:nazwa-pola pole) ": " (itoa n) ", pominietych (NULL): " (itoa pominiete)))
     (wf:podsumuj n rodzaj styl)
    )
  )
  (princ)
)

;;; ------------------------------------------------------------- WFIDZ --
;;;
;;; Skok do wspolrzednych wklejonych z GIS. Dane w PL-2000 maja 7)WFLSP",
    R"WFLSP( cyfr przed
;;; przecinkiem i leza miliony metrow od (0, 0) -- recznie nie da sie ich
;;; znalezc. Przyjmuje "E N" (QGIS: "7508131.920,5781259.990"), takze ze
;;; srednikiem, tabulatorem, opisem (X= Y=) i przecinkiem dziesietnym, oraz
;;; "X Y" geodezyjne (polnoc pierwsza) -- kolejnosc rozpoznaje po obwiedni
;;; rysunku. Stopni nie przelicza: wzor PL-2000 zyje w dwoch miejscach
;;; (core/src/uklad.cpp i skrypty/geom_gpkg.py) i trzeciego nie bedzie.

(defun wf:na-liczbe (s)
  ;; "7508131,92," -- przecinek albo kropka na koncu to rozdzielacz, nie czesc liczby
  (while (and (> (strlen s) 0) (member (substr s (strlen s) 1) '("," ".")))
    (setq s (substr s 1 (1- (strlen s))))
  )
  (distof (wf:zamien s "," ".") 2)
)

(defun wf:podziel (s z / i c tok out)
  (setq i 1 tok "")
  (while (<= i (strlen s))
    (setq c (substr s i 1)
          i (1+ i)
    )
    (if (= c z)
      (setq out (cons tok out) tok "")
      (setq tok (strcat tok c))
    )
  )
  (reverse (cons tok out))
)

;; Dwie liczby z tekstu albo nil.
(defun wf:liczby-z-tekstu (s / i c w tok out cz l)
  ;; zostaja cyfry, kropka, przecinek, minus; reszta (litery, ; = tab) to odstep
  (setq i 1 w "")
  (while (<= i (strlen s))
    (setq c (substr s i 1)
          w (strcat w (if (or (wcmatch c "#") (member c '("." "," "-"))) c " "))
          i (1+ i)
    )
  )
  (foreach tok (wf:podziel w " ")
    (if (/= tok "") (setq out (cons tok out)))
  )
  (setq out (reverse out))
  (cond
    ;; "E N" albo "E N Z" (przecinek w liczbie = dziesietny)
    ((member (length out) '(2 3))
     (setq l (list (wf:na-liczbe (car out)) (wf:na-liczbe (cadr out))))
    )
    ;; jeden ciag: "E,N" (QGIS) albo "E,ee,N,nn" (przecinki dziesietne i rozdzielajacy)
    ((= (length out) 1)
     (setq cz (wf:podziel (car out) ","))
     (cond ((= (length cz) 2) (setq l (list (wf:na-liczbe (car cz)) (wf:na-liczbe (cadr cz)))))
           ((= (length cz) 4)
            (setq l (list (wf:na-liczbe (strcat (car cz) "." (cadr cz)))
                          (wf:na-liczbe (strcat (caddr cz) "." (cadddr cz)))
                    )
            )
           )
     )
    )
  )
  (if (and l (car l) (cadr l)) l)
)

(defun wf:w-obwiedni (x y mn mx marg)
  (and (>= x (- (car mn) marg)) (<= x (+ (car mx) marg))
       (>= y (- (cadr mn) marg)) (<= y (+ (cadr mx) marg))
  )
)

;; Odleglosc punktu od odcinka a-b (2D).
(defun wf:odl-odcinka (px py a b / dx dy l tt)
  (setq dx (- (car b) (car a))
        dy (- (cadr b) (cadr a))
        l  (+ (* dx dx) (* dy dy))
        tt (if (> l 0.0) (/ (+ (* (- px (car a)) dx) (* (- py (cadr a)) dy)) l) 0.0)
        tt (max 0.0 (min 1.0 tt))
  )
  (distance (list px py) (list (+ (car a) (* tt dx)) (+ (cadr a) (* tt dy))))
)

;; Najblizszy obiekt WF: ((ename . dane) odleglosc) albo nil.
(defun wf:najblizszy (x y / best pts d p)
  (foreach o (wf:obiekty nil)
    (setq pts (wf:wierzcholki (car o)))
    (if pts
      (progn
        (if (null (cdr pts))
          (setq d (distance (list x y) (list (car (car pts)) (cadr (car pts)))))
          (progn
            (setq d nil
                  p (if (wf:zamknieta (car o)) (last pts) (car pts))
            )
            (foreach q (if (wf:zamknieta (car o)) pts (cdr pts))
              (setq d (if d (min d (wf:odl-odcinka x y p q)) (wf:odl-odcinka x y p q))
                    p q
              )
            )
          )
        )
        (if (or (null best) (< d (cadr best))) (setq best (list o d)))
      )
    )
  )
  best
)

(defun c:WFIDZ (/ s l x y mn mx marg zamiana r echo n d)
  (setq s (getstring T "\nWspolrzedne z GIS (E N, np. 7508131.92,5781259.99; albo X Y geodezyjne): "))
  (cond
    ((= s "") nil)
    ((not (setq l (wf:liczby-z-tekstu s)))
     (princ (strcat "\nNie odczytalem dwoch liczb z: " s))
    )
    ((and (< (abs (car l)) 1000.0) (< (abs (cadr l)) 1000.0))
     (princ "\nTo wyglada na stopnie. WFIDZ przyjmuje metry w ukladzie rysunku (PL-2000);")
     (princ "\nw QGIS skopiuj wspolrzedne w EPSG:2176-2179 (Kopiuj wspolrzedne -> uklad warstwy).")
    )
    (T
     (setq mn   (getvar "EXTMIN")
           mx   (getvar "EXTMAX")
           x    (car l)
           y    (cadr l)
     )
     (if (< (car mn) (car mx))
       (progn
         (setq marg (max 1000.0 (- (car mx) (car mn)) (- (cadr mx) (cadr mn))))
         (cond
           ((wf:w-obwiedni x y mn mx marg) nil)
           ((wf:w-obwiedni y x mn mx marg)
            (setq zamiana T x (cadr l) y (car l))
           )
           ;; poza danymi: kolejnosc blizsza srodkowi rysunku
           ((< (distance (list y x) (list (/ (+ (car mn) (car mx)) 2) (/ (+ (cadr mn) (cadr mx)) 2)))
               (distance (list x y) (list (/ (+ (car mn) (car mx)) 2) (/ (+ (cadr mn) (cadr mx)) 2)))
            )
            (setq zamiana T x (cadr l) y (car l))
           )
         )
       )
     )
     (if zamiana (princ "\nKolejnosc X Y (geodezyjna, polnoc pierwsza) -- zamienione na E N."))
     (initget 6)
     (setq r (getdist (list x y) "\nPromien widoku <50>: "))
     (if (null r) (setq r 50.0))
     (setq echo (getvar "CMDECHO"))
     (setvar "CMDECHO" 0)
     (command "_.ZOOM" "_W" (list (- x r) (- y r)) (list (+ x r) (+ y r)))
     (setvar "CMDECHO" echo)
     ;; znacznik tymczasowy (znika przy REGEN), nie obiekt rysunku
     (grdraw (list (- x (/ r 10)) y) (list (+ x (/ r 10)) y) 1)
     (grdraw (list x (- y (/ r 10))) (list x (+ y (/ r 10))) 1)
     (princ (strcat "\nE " (rtos x 2 3) "  N " (rtos y 2 3)))
     (if (and (< (car mn) (car mx)) (not (wf:w-obwiedni x y mn mx 0.0)))
       (princ (strcat "\nUWAGA: punkt poza obwiednia rysunku (o ok. "
                      (rtos (/ (wf:odl-obwiedni x y mn mx) 1000.0) 2 1) " km)."))
     )
     (if (setq n (wf:najblizszy x y))
       (progn
         (setq d (cdr (car n)))
         (princ (strcat "\nNajblizszy obiekt: " (cdr (assoc "_warstwa" d))
                        "  ID " (wf:napis (cdr (assoc "_fid" d)))
                        "  w odleglosci " (rtos (cadr n) 2 2) " m (zaznaczony; WFINFO pokaze dane)"
                )
         )
         (sssetfirst nil (ssadd (car (car n))))
       )
     )
    )
  )
  (princ)
)

(defun wf:odl-obwiedni (x y mn mx / dx dy)
  (setq dx (max 0.0 (- (car mn) x) (- x (car mx)))
        dy (max 0.0 (- (cadr mn) y) (- y (cadr mx)))
  )
  (sqrt (+ (* dx dx) (* dy dy)))
)

(princ "\nWorkFieldCAD wf.lsp: WFINFO, WFZNAJDZ, WFKOLOR, WFSKALA, WFODNOSNIK, WFIDZ")
(princ)
)WFLSP",
};
