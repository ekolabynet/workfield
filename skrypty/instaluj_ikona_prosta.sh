#!/bin/bash
# WorkFieldGIS 23.09.2026 - IKONA BEZ PIERSCIENIA WOKOL LEWEGO WIERZCHOLKA.
#
# CO TO ZMIENIA
# -------------
# Pierscien mowil "ten wierzcholek jest biezacy". Prawda w rysunku na
# ekranie; zadna w ikonie wielkosci paznokcia - przy 48 px byl zielonkawa
# smuga przy rozowej kropce. To ten sam powod, dla ktorego 21.09 zniknela
# kreskowana linia, tylko o krok dalej.
#
# Zostaje plat o PIECIU ROWNYCH wierzcholkach i celownik w srodku.
#
# LOGO ZYJE W TRZECH PLIKACH i wszystkie trzeba ruszyc razem:
#
#   platform/android/res/drawable/ic_launcher_foreground.xml
#         ikona ADAPTACYJNA - TA, KTORA WIDAC na Androidzie 8+.
#         Sama podmiana SVG nie zmienilaby na telefonie ani piksela.
#   brand/workfieldgis.svg          zrodlo wektorowe marki
#   brand/WorlFieldLogo_2.0.svg     nowsza odslona tego samego rysunku
#
# CZEGO NIE RUSZAM: brand/android/drawable-*/workfieldgis.png - stare PNG-i
# z wlasnym tlem, nie pochodza z tego SVG (decyzja z 21.09.2026).
#
# PRZY OKAZJI, W KAZDYM PLIKU OSOBNO
# -----------------------------------
# * ic_launcher_foreground.xml - piaty wierzcholek mial juz ten sam kolor
#   co reszta (#F60054), wiec sam pierscien do usuniecia. Komentarz
#   "wierzcholek biezacy z poswiata" poprawiony, bo od teraz klamalby.
#
# * brand/workfieldgis.svg - pozostale cztery wierzcholki sa tu BIALE,
#   a lewy byl rozowy (#FF4081). Z pierscieniem czytalo sie to jako
#   wyroznienie; bez niego jako pomylka skladu. Wyrownany do bieli.
#
# * brand/WorlFieldLogo_2.0.svg - pozostale cztery sa tu rozowe (#f60054),
#   a lewy jasniejszy (#FF4081). Wyrownany do #f60054. Przy okazji
#   wyleciala ZABLAKANA KRZYWA `path1`, ktora zaczyna sie przy x = -102,
#   czyli POZA PLOTNEM (viewBox 0 0 1024 1024) - nie widac jej nigdzie,
#   a jechala w kazdym renderze. I nieuzywany gradient `bg`, i metadane
#   Inkscape'a. Plik z 4013 bajtow zrobil sie 2048.
#
# Uruchom w katalogu repo. Idempotentny; sprawdza sumy PRZED zapisem.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64, hashlib, os, sys, zlib

CALE = {}

CALE['platform/android/res/drawable/ic_launcher_foreground.xml'] = (['64283f1d42ee60f23a8234224ea0d0c9'], 'b41d97096b0e83f24dbbf0a9a2f1de4e', """\
eNq9Vdtu2zgQfc9XzGqxQALINHWXjSRFkE3RbNwE6AXG+o2W2JjWhYJERZWe+hH7vB/XL9mhpDg3F1n0oXlgwBnNzJk5Z+jj
N1+zFO54WQmZnxgWoQbwPJKxyG9PjFp9mYTGm9OD498mkwOAy0TmDJayTN4KnsZzKFKmoING8LKLNjJNWCZMKGTK8cgEK2v0
RjyVTS4SwTMTkxSCR1CipY02jyJlQw7Qe/Vh9fcKOszDKgVJKYtEQANVKeOkhkMrJHRGbGr7R/PByyCTjUgZxhpyLXiiDBM9
Xdv1DjAGIAZ8//YPMFASthwzS1BtBooBK1KRsGjLCGZY7uAIyHLBt1XH8VOb/mFCx9ctoA1wCEmNDbC0fdrd2MDFx6ub5dn1
GSwury/P4PPHz9eXF5/OwLbusfdYCsQIbgjFV1i3KSIrO56xsSkcI+ZKlCw5RF2rWCqhwtpblsC6rOO+1M2nm/PV1RksLy8+
rM7f3SyuHldzdtU6UPwW41mm/xWykXFtgh5EzHNdppQJxCzl2/ljVEhUWUWC5/jpbVmvJV7AMn2IC40YOtQAjoI1DKqsvtUM
9NGl7GTDt30nESewylnUcT25w+/f/lWYb8c6TwY2kLeORa1xpBPLPhFr4k40HLkv26rGiQNKjycl04kEKiTOtVMgG2jAjCgh
DbBgXS6TSPR8rmSl2JYPOpW99ES9R3wMb2JH5U5v5GAyQfHf8QiJANyUvJqzPC6liE+MjVLFfDqtog3SVpHRTiKZTVmRTEte
TUebgUgAxsu8EbHa4KrRMC6MnXXDxe1G3ZufBNwJ3hSyVMtdoPHC9+4h3DjV2tAbO7StW8B7wdRmF/ZFpOm5TGV5Yvx+Til1
rYeUlUI58HvvW59Szx0AwbNvRkA2sZzn4QuR87+kwCellHUeP4/XYP5kip0Y7x1KAst0KXFtWPgOCahpBySksAhQvo7puYTi
xfeI75ohRUXDwg5JEJiBQ1wLVgZMHzpuHi2w7r5+tf2xwX3QvBkJ7RENc0gYmvoAiktAISCBb+6xTwZHj+on6wYecbyx8V9Z
17d0imHGv7Ku7ZJwNtL5U3V3en/8w/Mq8f3fXkBOQDyqCXBnwCyfONTsz7G0YxOfakwvXZPRN8C6x7V7WPZherZvFo7JNn60
aejau4p6385Z8fq6uT6x3bG1BRLu+OPlvYfDpSb6Zw4shotvE+o9nbBgqn3yfg9bdpjypj36v8v2Y3i2R0J/fA0YysIz9TEO
d6YfB/rSPhkcPdDj6fBanx78BzVinus=""")
CALE['brand/workfieldgis.svg'] = (['cd854fc29ddd71c4405ad82c41c15267'], '022b644f3792402544f1addc9c717a93', """\
eNqtVl1zmzgUfc+v0NCXdmYNkgCDXTud2WayL+3Tdqcz+0aQjNlg5BEk2P31vRIIBIU026kzcdD9OPfq6OiS3YfLqUDPXFa5
KPcOcbGDeJkKlpfZ3vnny/0qdlBVJyVLClHyvVMK58Ptza56zm4QQs85b/4Ul72DEUYE00B/Odo1YBJtyNnegTTSuisocYbf
LRNpmZwA+auQxX3OC/ZJZOLvVHJeuhDf5paPVZqc+dZCDVwfvcWMhIcoxAH9A1FMwxWhKxq+00mws7LamtS9c6zr89bzmqZx
jdEVMvNU+eqcpLzyjN3KN432+cbgVuJJpvwAENwtee3dfbnrnSvsspoNMKPqja/rUoyxZ3bYFXvOXoy8hdBdT51qnKkjUAAt
wb2poxmhc5LxVBRC7p03B/3pHA9CMi6NK9WfkUsAJ3l9Ba47c38K1VE0Crc6Jkw0cPrTAOVcTtctHXn6yOWDSCSbAWC8ejSt
MaJ+phHfhDhBohtH0YZu1pupPwVVhgRk4uMg/sF5VU46NTd5CftZNTmrj9D3huKFiCPPs2MNIYTGCyGXmV11ruuy65Rc8lP+
jbMZ2tInKXlZr4rkyqW5S8jTmmD8UA0qUCuqxQKuIi95Iv+SCcshuw1qwx4yxywvZOgJoetodaFDM+DTq9tuuatqcTYuhMTh
UPHaToabDhErc5YYrzfhR8urpwJEkG4nL4CSZVD/zvdnQGkPuvPGNGjSPMWTfspuOlQpHmFSvLnXH8e2GlWYe9XLG7u41wDU
zSKbeJtfGq5fYHjkVRybQWqAFZy1oSn6IOc59JF3Cd1fRo/W8QvoI+8SerCMPlaezcRlinadUGXQw9ei20zMotsBBn39WnSb
iVl0O8CgR+YWe5n+c07qYxsDAZ+RjzHyY4w+oXWAEQ3VUwy2kGrbGqNoo54oxERg+7crcMiLYqplZVvZ0o2c10uf0rFZ9f6f
yOFtLMVTyaxLoHYwIF8LAFaVt+qqMt9/b7exxW4Yvm8ht90rqlv2IWY67NJcpkXHv57wgeFfj3TfrGAskJ7pnogAx2SBiP59
aRFhhY+JIKG117al6Bc67Pmca3CAjg10tnyuevKQfubbTbRtrINBqKoRkFG/hlb88X1t8ze9bXSG3RGNznAY3zO1Qayj2iH9
eW2Cf1NxuB+j4nBXfl6c/KbicCXHxV+zc/r/i5vJMRWfj23x+bElvr72kpy6btqXwk79+3l78x3fdxCZ""")
CALE['brand/WorlFieldLogo_2.0.svg'] = (['d14463e0193fd39c29fa3152ef765885'], 'ad3a467410983f6ab212e118759a7b68', """\
eNrNVclym0AQvfsrpsZXa5idxUKuysGn5JbkkBsFCEgIqIAI6+/Tw44W26nyIRxU9Jtm3rw33a3t08vvHB3jqs7KwseMUIzi
IiyjrEh8/O3r88bBqG6CIgrysoh9XJT4aXe3rY/JHULomMXtp/LFxxRRxCiX3Q/uluY9WQdkkY/hM9YvA21R+zhtmoNnWW3b
klaQskosTim1IG/O8iB6NXMHqdsqDhvzCYLjnnI46T7Lc++eUltq9miCTXkIwqw5eeyxbqryV2xWtVZ6CDdtFjWpx/gYn+dv
oqBOg6oKTl4BZuCezugy5IMwhLptfGwrm0gtHHuA0zhL0uYSB/eYcgHS1BmgE0CCEtdxXXeAKoNxRSijlGFkdZoPQZP2y3CG
L0hQioRD0WekJUVcmTcHMMU7TFNku+aNQ44N2I9hb2OOj++fu2eBjQbA9RI6Hre34jx96aCPOV/DeVbEP8sMiqEq/xTRwjij
YN55cW8hXK68eW97TamSF/c0+hJmVZjH/a4h+KvE6GwIYpSxUXA+WQvOaufcC0kddsOL6aYXXizS114wtZDbH+yq4H333BBs
yu2m2uT2LRrOhPGrfL2Fa76ulc4M7C2EisJTDC5AdU0xGCjkFM063Ql7B3Mv5io31PCKG+r5TW5GP4gc2mZFDi30Njn7IHLo
1DX5e5TzfyffWsnVxhGT84ZdTKdZcg91129/UetMXA6rsfHFui7nqh87QsEz9zxMPsXXs5pPM8CMmDA4eN2AuT6vLxtoMTuV
EERL5vAHCW+urZRA35HmjLjM1u4rIjb6P5KhBSe2zbR4UNwh8F+skRSSKMYBsImjHc07LVvzz7m7+wvxOh22""")


bledy = []
caleDoZapisu = []
juzZrobione = []
for cel, (przed, po, _b) in CALE.items():
    if not os.path.exists(cel):
        bledy.append('brak pliku %s' % cel)
        continue
    suma = hashlib.md5(open(cel, 'rb').read()).hexdigest()
    if suma == po:
        juzZrobione.append('%s juz podmieniony' % cel)
        continue
    if suma not in przed:
        bledy.append(
            '%s ma sume %s, a latka oczekuje jednej z: %s.\n'
            '       Ten plik zostal w miedzyczasie zmieniony. NIE nadpisuje go.\n'
            '       Przyslij go PELNA SCIEZKA, zlozymy latke na tym, co jest.'
            % (cel, suma, ', '.join(przed)))
        continue
    caleDoZapisu.append(cel)

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

for opis in juzZrobione:
    print('  juz zrobione:', opis)

for cel in caleDoZapisu:
    open(cel, 'wb').write(zlib.decompress(base64.b64decode(''.join(CALE[cel][2].split()))))
    print('  %-52s %s' % (cel, 'PODMIENIONY'))

print()
print('  zmienionych plikow: %d' % len(caleDoZapisu))
KONIEC_PY

echo
echo "Sprawdzenie na oko:"
echo "  grep -c '64FFDA' platform/android/res/drawable/ic_launcher_foreground.xml brand/workfieldgis.svg   # oba 0"
echo "  grep -c 'circle14' brand/workfieldgis.svg brand/WorlFieldLogo_2.0.svg                              # oba 0"
echo
echo "Build i instalacja:"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | tail -n 3"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh"
echo
echo "NA TELEFONIE: ikona na liscie aplikacji i na pulpicie ma byc bez"
echo "zielonkawej obwodki przy lewym wierzcholku. Jezeli stara zostala -"
echo "Android trzyma ikony w pamieci podrecznej: odinstaluj i zainstaluj"
echo "od nowa albo zrestartuj telefon."
