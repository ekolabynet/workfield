# -*- coding: utf-8 -*-
"""
Sito nr 6 — MARTWE ODWOLANIA DO IDENTYFIKATOROW.

Uruchamianie: python3 skrypty/sito_identyfikatory.py   (z korzenia repo)

POWOD POWSTANIA, 23.08.2026
`ustawieniaStanu.korzenProjektow` w dwoch miejscach QfMainDrawer.qml. Obiekt
o tym id usunelismy sami w a39a64747 (17-18.08), odwolania zostaly. QML nie
mowi o tym przy budowaniu — dopiero przy KLIKNIECIU, komunikatem w dzienniku,
ktorego nikt nie czyta w terenie. Skutek: "Otworz projekt" i "Zapisz jako
szablon" nie robily NIC przez ponad tydzien.

Piec wczesniejszych sit sprawdzalo typy, naglowki, rejestracje QML i obiekty
dolaczane. Zadne nie patrzylo na identyfikatory. To byla ta luka.

CO ROBI
Zbiera z calego drzewa QML wszystkie `id:`, wszystkie wlasnosci, funkcje,
sygnaly, zmienne lokalne i parametry, dokłada wlasnosci kontekstowe z C++
oraz id z QgisMobileapp.qml (widoczne w dzieciach przez lancuch kontekstow),
po czym zglasza kazde `cos.pole`, gdzie `cos` nie jest zadeklarowane NIGDZIE.

CZEGO NIE ROBI
Nie rozumie zasiegu — nie powie, ze id istnieje, ale nie jest widoczne
z tego miejsca. Zglasza tez falszywe alarmy z prozy w komentarzach
wielolinijkowych i z wlasnosci grupowanych spoza listy GRUPOWANE.
Wynik jest LISTA DO PRZEJRZENIA, nie werdyktem.
"""
import re, os, glob

KATALOGI = ["src/app/qml", "src/gui/qml", "src/core/qml", "src/3d/qml"]
KORZEN = "src/app/qml/QgisMobileapp.qml"

KONTEKSTOWE = {"platformUtilities","qgisProject","iface","pluginManager","settings",
"flatLayerTree","focusstack","bookmarkModel","gpkgFlusher","layerObserver",
"featureHistory","clipboardManager","messageLogModel","drawingTemplateModel",
"qfieldAuthRequestHandler","trackingModel","cloudProjectsModel"}
WBUDOWANE = {"parent","modelData","model","index","console","undefined","displayToast",
"qsTr","styleData","item","target","event","link","layer","feature","fid","self","e","p"}
JS = {"Math","Qt","JSON","Date","Object","Array","String","Number","Boolean","RegExp",
"XMLHttpRequest","Promise","Map","Set","Error"}
GRUPOWANE = set("""anchors border font easing icon background contentItem
gradient palette shadow cursor selection handle indicator popup contentData
sourceSize origin scale rotation transform axis textFormat wrapMode elide
verticalCenter horizontalCenter fill margins padding inset
centroid translation point eventPoint position velocity
pinch drag hovered pressed active accepted key modifiers button buttons
polylines strokeColor fillColor normalizedData mapTerrainGeometry screen
org QtQuick QtCore Qt5Compat""".split())

def deklarowane(t):
    n = set()
    n |= set(re.findall(r'\bid\s*:\s*([a-zA-Z_][A-Za-z0-9_]*)', t))
    n |= set(re.findall(r'\bproperty\s+(?:alias\s+|var\s+|[A-Za-z0-9_<>.]+\s+)([a-zA-Z_][A-Za-z0-9_]*)', t))
    n |= set(re.findall(r'\bfunction\s+([a-zA-Z_][A-Za-z0-9_]*)', t))
    n |= set(re.findall(r'\bsignal\s+([a-zA-Z_][A-Za-z0-9_]*)', t))
    n |= set(re.findall(r'\b(?:const|let|var)\s+([a-zA-Z_][A-Za-z0-9_]*)', t))
    n |= set(w.strip() for g in re.findall(r'\bfunction[^(]*\(([^)]*)\)', t)
             for w in g.split(",") if w.strip().isidentifier())
    n |= set(w.strip() for g in re.findall(r'\(([^()]*)\)\s*=>', t)
             for w in g.split(",") if w.strip().isidentifier())
    n |= set(re.findall(r'\b([a-zA-Z_][A-Za-z0-9_]*)\s*=>', t))
    return n

pliki = []
for k in KATALOGI:
    pliki += sorted(glob.glob(os.path.join(k, "*.qml")))

wszystkie_id = set()
for p in pliki:
    wszystkie_id |= set(re.findall(r'\bid\s*:\s*([a-zA-Z_][A-Za-z0-9_]*)', open(p, encoding='utf-8').read()))
korzen_ids = set(re.findall(r'\bid\s*:\s*([a-zA-Z_][A-Za-z0-9_]*)', open(KORZEN, encoding='utf-8').read()))

ile = 0
for p in pliki:
    tresc = open(p, encoding='utf-8').read()
    c = re.sub(r'^\s*import[^\n]*$', '', tresc, flags=re.M)
    c = re.sub(r'//[^\n]*', '', c)
    c = re.sub(r'/\*.*?\*/', '', c, flags=re.S)
    c = re.sub(r'"(?:\\.|[^"\\])*"', '""', c)
    c = re.sub(r"'(?:\\.|[^'\\])*'", "''", c)
    znane = deklarowane(c) | KONTEKSTOWE | WBUDOWANE | JS | korzen_ids | GRUPOWANE | wszystkie_id
    for nazwa in sorted(set(re.findall(r'(?<![.\w])([a-z][A-Za-z0-9_]*)\s*\.', c))):
        if nazwa in znane:
            continue
        nr = next((i+1 for i,l in enumerate(tresc.split("\n"))
                   if re.search(r'(?<![.\w])'+re.escape(nazwa)+r'\s*\.', l)
                   and not l.strip().startswith("//")), 0)
        ile += 1
        print(f"  {p}:{nr}  ->  {nazwa}")
print(f"\nnazw uzywanych jak id, a niezadeklarowanych NIGDZIE: {ile}")
