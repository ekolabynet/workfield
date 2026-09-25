#!/bin/bash
# WorkFieldGIS 23.09.2026 - WYPOSAZENIE MOWI, DLACZEGO.
#
# CO BYLO ZLE
# -----------
# Wczoraj wieczorem na projekcie 3853_24_pin UKSW tapniecie „Zaloz” przy
# module tyczenia dalo:
#
#     Krok sie nie powiodl — projekt NIE zapisany, kopia: …przed_20260922_222939
#
# Trzy rzeczy naraz byly nie tak:
#
#   1. SIEDEM roznych przyczyn wychodzilo jako jedno zdanie. W kontroli kafli
#      jest siedem osobnych `return QString()` — brak pliku, plik nieczytelny,
#      zly JSON, pusta lista, kafel bez `etykieta`, kafel bez `warstwa`, kafel
#      wskazujacy na nieistniejaca warstwe. Wszystkie milczaly.
#
#   2. PRZYCISK OBIECYWAL, CZEGO KOD NIE ROBI. `tyczenie` i `klawisze` to
#      moduly KONTROLNE — sprawdzaja, czy cos jest, i nie zakladaja niczego
#      (komentarz w kodzie: „SPRAWDZENIE, nie zakladanie”).
#
#   3. KOPIA ZAPASOWA PRZED CZYNNOSCIA, KTORA NIC NIE PISZE. Kazde tapniecie
#      zostawialo `projekt.qgs.przed_<data>` obok projektu.
#
# CO WCHODZI
# ----------
#   src/core/wyposazenie.cpp     kazda odmowa z przyczyna; podpowiedz
#                                z modul.json; brak kopii przy samym
#                                sprawdzeniu; flaga `tylkoSprawdza`
#   src/app/qml/QfWyposazenie.qml  przycisk „Sprawdz” zamiast „Zaloz”,
#                                  sprawdzenie wolno powtorzyc zawsze
#
# PODPOWIEDZ, KTOREJ NIKT NIE WIDZIAL: kazdy modul niesie w `modul.json`
# pole `podpowiedz` — zdanie dla czlowieka, ktory wlasnie utknal. Przy
# kaflach brzmi „klucz to 'etykieta', NIE 'nazwa'”. Nie pokazywalismy go
# nigdy, choc to najuzyteczniejsze zdanie w calym opisie.
#
# SPRAWDZONE (piaskownica, QGIS 3.34.4, dziesiec sekcji):
#   brak warstwy · warstwa jest · brak pliku kafli · zepsuty JSON · pusta
#   lista · „nazwa” zamiast „etykieta” · kafel na nieistniejaca warstwe ·
#   poprawne kafle · trzy proby bez jednego smiecia · flaga dla QML.
#
# Podmienia DWA PLIKI W CALOSCI, sprawdzajac wczesniej ich sumy MD5.
# Jesli ktorys zostal w miedzyczasie zmieniony — odmawia i nic nie rusza.
set -e
cd "${1:-/DATA/SOFT/GIS/QFIELD_Pro/QField}"
echo "== repo: $(pwd)"

python3 - <<'KONIEC_PY'
# -*- coding: utf-8 -*-
import base64
import hashlib
import os
import sys
import zlib

# (plik, md5 PRZED, md5 PO, ladunek)
PLIKI = [
    ('src/core/wyposazenie.cpp', 'f5ef8d7ba3816a3ff508f293c4bcca18', '1e68cd14102b54316bff8c58232c2b5e', """\
eNrtfdty20iW4Lu+Is0J2VQVC7ZVPRszVMkdtERXy5ZEWaJabbUnxCSQokACSDYuZgHVjqjoiI39gX2Zh+nH/YF929ft+pH6
kj0nL0ACBEhKVs307o6ioizhcvLkyTz3kwfPv3q8ny1CFumcRzRjgcssez4n35Cr4gppX/Fw9sZlnrOzRR514K8IIcM7NyLz
kE9C6hP49TZkjET8Nl7QkO2RlCfEpgEJmeNGceiOk5gRNyY0cJ7zkPjccW9TQhQwuJEEDgtJfMdIzEI/IvxW/PH96SX5ngUs
pB45S8aea5Nj12ZBxAiF8fFKdMccMi6A4WtvEJsLhQ15wwE6jV0e7BHmwv2QfGJhBH+TXT2QgtohgB3+KGBtGuNcQsLn+P4O
TCAlHo0LEBZZ//PVoy7A861/cAPbSxxGWuYWuGttGXeAxImXPs+oR+0scGdu+f5379+4HntVvXAU3PLSxbcRD85oGLF+GPJw
6VYvDGm6dPWQ24nPgnjpxmA8ZTZcNq8fAjWHrs+aYBuX/zSJYMshCOvuVfl6FND53A0mNg9u3cnS7Zh7sIcCmy3d+QTQeOjR
lIV4z7gZ/clzY/atuGowVrdr/NEm7+WcyFdz2GpBTIDZSFdfbZP86o9bn7e2AuqzaE5tBn8S8vz5E/KaZpSISc3ipEtGDg2Y
NZnPJiPCx3xGRuqeBaiOLDKkJKI+JTMeLFhgT2lHwZnBJNiUzF0vSKaMjPjYZRNrno6IC4zoUeDEKIspCWiYMSdzLXjv/QVw
ZjAhY8DhTKEAE5pEZ5LIMCd5VUwKMQZWvSVt8sS8jj8hi5Mw0ADbO3viOqxFFOejONwn+3qq37y64z47o/GdflgAhmcsN+r7
8zht79wL+hxg4whf6yvHsHYgNdqk9TynaYuodzVEveW7XfYDyKkI1ovskN/C/7vl4T7j6iGdh+k8JbOQz/iiI4lOTo8Orvvf
D+DfPrk+OeqfHvXe9sgvP/13EqfejJMoXrgsdDI6hcWLaWABIPiPnCCHkszjGQehskglozKSkZjOXPtODUPw2pTBXH/56a8Z
nXkU5pP+8tO/dSR8BHVxdt67OrzunX6wyCk8DjvEztiEk4zO3YjasAkCeXmOyw83U5+EsEds2Elz10WUyCEnu99aL/7Z2n2x
+1/IjGbABDGdw4s2vAuDX1PAFQaGTSRQ9IkQMoAxh3ktXLgtNi0C01uazD23vIstgcLNdyCR6auRoBPiwArUgoBHtgtbG+Ag
iSmQxGG3buDaU5yInBpOCCaXMWsLRo9hKqUdcQzrmdPlbe+gDxvkx2LTF9sDVASsEL2B5wHklMEm6dQ9BywXh9yjN7ACCxg3
hQe3Pu/JbXGQpZIYJBILRCLA7urDce/gGrdFptcS5BddiK1gp/ZdjvmYc0+u5oV6oK1nU4hN8tQXcoSYt4SQFNBdmKBvfaJe
glJpCXt8AjAmO1bMxUtyYwu2EzeXGE8xyS31IoaP3oJqLKH1exyLPJ0Bs0gEqmLCJL8FL8bUDYDHZoCCko87jQjH6VyjqxmR
LImEHLfPW/m1OEzgErDr+9/T0KVBfELnpCS/o5j5c+Y1iDo5Q0FnE8Jib6sqc1BuAtHL4jOHk1MX7zcRF6DCn0rTkK+cMcAL
Es+bx2H+vrp7w+csuPm0qwDG/DK+/ScgoMAJlCht73TIU2fc2WoyQy7eHx8N+zeDs/7pzXm/dzg4Pf7Q0cPBxJ/s54+8q64l
YKZpr/GxPR4xeWevMidcEKGYyOuQzkBYjJnnklgy7RgYRIpHuLVIJ4JfNNkiKQUW8PeCOrhgVAISi+a5FnkHgkkz2yKdgi5j
ZBEzuDalIG1HYxhx1AGJF3lJhALVKih8E8U+rDVIxTKd5bradzQkX8GjcLN10T/uHwzlOB2yAGMPlC1BoUXenA9OyNWbm6sP
Z4OL3jUI/H5rabXmIUPdLxYMFgWvd8g3L2GJYHST6vv1VF/cgW4y4MH8522U56VXzgdXal1+VKtT3qK+68Bk1F/d7m3IfbFt
8j0SMjcAlgNs4xubRvF3JileFcPb3Ev84CZmP8QCiw55QQRD7ilQJV4Buayv4+9/XBa6gp7A4P8C6FXGAITUEC8L8PVgcDkU
kF9ljrvlOS7+CPTEwYoJflbCR6y9WJ0tk0dAaVHPzZi6t7fVyD4F8xiiSyixsuyS+mFz2SVALFLwAPYUS74Donl8AjaF5B3S
O3uHRgcqVTAu8R+b+74LO93moJsls4Y8mwLnIQf7PPPcRSpMSLSghI6vEeHd54Z78nwmh7WmoDlamqrKnIT3LRRvAORocMg+
gTPW7Z4z6gwCLyVVmSknQ2o0pBqD7IvnS76I3Bh4pS3wtUIA3/M8lMgWV9oIoYqbcnF2BMnUMMb+jnDTaiViCPw61Sz9MHhB
z79J4ckHa1R0k979BHpXQS/ExjJNcK/C8J8MpVtnQEtJgQ83Yug6VY1sAgIeIwu1t5J1oHL+F+COggakwAxk2Yyug6YeW8ZO
gIQtP0AaCFolYjMHNFtQ4nhoJnsczHMYw4UZAKl9il4VmUje4F6ARrSw6WxL7iqFm4Sxj4TbK93guXDQVwQweUlYeqYVCBBy
K0bzk3+7lpu2Xz4X89HsZNFw0s7plcsswV/+7QbMVdEfxgZCt62RlQB2EyPhT06kxrUTT1RWTmzGHAaXG7gZBD5QvzNr+HGy
EpRYqRoeNFZTCNSJp682cecPwJ2T3GYi8Ab57jvyQw2KcqvtwxPWlLtBDVYd0jLVUGX7VPwGv3gQFicXZFJZGTwmdqLwK0GY
Gda5QftlyYdseCEsMSpeU3QU78DU4JEaoSCNY1tMUgz4WxPOfWQE0PSF4upcRIBHbez1J2KA3FSFm4VtUIBGGzEPBjDgPvmy
gel3hixbBw2uh9IfXAHw1T0ABnxRhbfmjWzCnUC+sVW1xkJlnf+xXuUo+ykXYzXPaR7F58TvjU8qVsQHCzFY85zmM3zQkI41
TxYkVI8XF5rf6aESB0Hu6nc06RtfQcJqczTfUejZn0gHAOMQaTWgI5cDFQp4LantRjMMsfigUGyMlyiexFBNDi4oh1IsMhi7
LA5cm4KagWvo8MjYTdRRMRy0wERcSKqhApbY6hMOe48SeAY3dZJjklhNUy3JCz1nQ6Q00siwtjfhX/W43sXCbLPoHDSR0yYh
2an47cqsAxklJFPJ6rV5dOqy70O63u4tyywhrL1ighX/vCS81SvSsPKWbSpD4Ch7Soi7ZqtEbqkatSQdRYQDLvf7Yxq7wUut
+gpWrgY7ZGCjRDNlOaDHoLArkW3OnSiB7UhlpPoxKSem4DWFNeIQJoKByMTBoCAGw7hjZ2lMbW0HJ0b6ilpacpk6Fvdzh0jh
ysBjRqHI7r1qhiD0zWXba15a/wFLWgb0MLNnaXfsL+8OpbnyvYF/o2FhiOVC/TQBKRSWqYqQzPcGlauqHJJcpxKgz9WlBcEG
puqe8ke5x6YY8kUph+JrTp0ZbNouGUnoI+IKE+nsqH9+dXH9oQO2C8kCChsK6B5JKNxZhDwOZGQ40+kOEWbihCp9QKXMxBgT
ThiTYx0ZSFbx6dwllbNY2t8ScZyc2OK9s+Ojd72Dtz3ytn8xJBfD3vnFdU8goCB2yfZLi1zTWZxgICCZ5rjAlm7VhOpaGXCr
D8JeJAMiBERtoIZt5Va+wm21sWj617hJ1k1FRTB1nkCYBnwh0M8HFnA2H1btqXUjX4jHqIqx1Y+sQa0fXI8uB2kSUO9LPmIF
oWuVZAFKuESvnNg9CjfYbON0IYP8CzJ2E9hPVqsUx1HDN+Cr7XlgDExy7D/aD0K77r077h32MO9wMji8PB5ckSsy7J9jnPLR
R0OAvZy7Eh8oMjy//gCWUp4nIxkSyvFdzG8uPAp0WQC3j0R+x7hwIzMxImU50vnckUXOJSu3RyKMzG5EdlS9XMndjDpktJSn
wYuI4Q3mpkY7xOFxOkPbLUxgbcMUIY0pyBLqgVxZpD6dUOIwO82mrhEfQFHiylTXtFh2HSlAuSLyVWD2Yixh4Tqg64RNoxJb
izQCw4vm2T9cGtI7fj0gBz2Mw4tfr+D3PsoLnRUkcy4QAJBchsBRnQNpPeoDvgJ5ULALDjIDZbQLGFEUecIuZEIUCbZtTF8W
snGRAu2SKctJDka8g+bDigzb5clR/+RDY24tX9ymrNry8jc9qXeEuo+KQySdSjk+EdwxEoQZbEiwLzCiA0S0VUAH1w/nSm0J
CMUpriJY484sTGNGXv6j9eKfYbvGqS1sqZEy/ec0BgWFljmsjdx8YukVRhS2n9x18AY+I7KfM3rruUrzcLSmgtT61TKRNSus
0pEHgzenvQNjcWUOBYZC3Ult6iFejSsNr/cefaUl2rKoCHOotCxK1CqB9DoVc5K+FgcxjdJVqW4RtU59FDki2SOAlYSFzjxN
mcMCAUjlzsn54PD66LSnCNZFYPBQANACimBCjk6RTGB1MAYO/8F+ClL7jiwyHtrMF2ZOapErzLTjKEBI3H6ATgKyRiAjuWRE
xqnHxynh2ufrEGBRnKmfSvcvtfPEO6LfwZyWyxCGDm3Dnw5QxUOhhMIqjWBvIVmoBuRwVF9qvoGgyPNSolk+h9xTm2UWhC4l
mpVVCzPCODbcvk/WNrcHJBGMSBPCW3IcpI8jXhDjLZucxsq2qu+vRA4XLGP2Ulq5Zozr3vHNdlmjG76WQa2Sv4UhDxEvSNoV
0j2VvFZK0PwHpE4MzOXCrEihPFb6ZFX64kE5kYdlO2Q87n7pDXTP1cIV4WTYJ8mXRuuX7H5p5T4kyVGJ9T/ZKNjfvCEeNwFQ
DUCrUf1KGKOCRVM4w+cZu5ZScgP+qp+HyaLqnZyZ/JXhDOUYYeETineVTVrk8Yy6EEYe2mxiggnm8O6VjVCYSasTPJZJnah9
Im4bonZZULOQBcppWpqq1I3axG01pTZ/zaojgUduoCDhlTPhcGUVgBrWmN2nMqlWpT2wIMnkO1OpmvDq4niKMuRja/vlx1Zu
dyubBKnOc89XKMkqvxQINPGKpNFU4lMT+es0af7m8qHiR4/41ZwvuFPHdV9sMZThTMJkTtdBEg+thzXzEjtbB0s8VJtPvqdl
YpRQPcg2edJsm1QSt2IMtSD5GqoV2i9EmNineUpb2plqI9Ypplw3PQj7PBNZX8L72eBIIZSvdbU62OLdK+E841It3xPGciUk
rTkxs4T9ujlt4AWjYGkVqupe8cLndVui5BfVWy5SWC3WbUlwmmINZq9elF3JR1xV/0LWct6NAupWE/DLxlEQtyqmRmnA5Znr
NxQqeeH3IgSgffBg07bk605NyTa++bVkVfDc8/TvUoJ1DQ4OT8Yee0Q0DgXAB2CCjtcj4vEawJWxeBy4Vc4tM0PxJhi027uw
Y7e/zRWVGsQAplIv7WWRcA+2MYIFBvs8fw7qbgxqX94lZ+fX/bOji97pB3J11D+XNdejRQqOdpgVgcVF6czUPLU0sCElHhhs
InI252DUj3qfuOscYd1gBLrRBVZDi07Wq+++tF78kyyTB3jMC+A2I5nHNLgZj7KYLzD3BdCIg0ldYXElInfBx2zqy9sSNYxi
zMJ0gflXigGEVEMSbxFXRAVSjPzL6AHIvHHqqWRvgAFBsIsyWBzyun9N3g1OLk+P3vWGl/kEz1X5Hkh/J0tB7JPbJJhhoIWS
eRrfcQBNAebPfxmnMlTmhHziWk1uliD+OomFD2nJUnYySkYy4z6DP5VTtcpUFhCbDQAFiNabzKQYqc5wLiM1574bfClCAsiN
iA81oSQeqUfHKNMRhmHfScWegq2m5fvq4cVbNyx/TeMghIcItRT1IsbUXWeGoTXE2kSEJrHerql5kMen82M8PRVpvCW9xOMu
Fhepd2Sh+ms2cQN4Em89qdzrBw7e+fprN67obzBgfy/OaYmRyFeoLP8kXU1Z0Vt94FUbBlCEMcwQaSAsDCOg7NAv2Z1MHFoC
6Fez8RBYPep2HTeaezRVa5UDkgE2jY0LD6pXAJUFiGP5R7tUTyzWdk4jtP33i91Z+ES1RWba5cX9V+zoYkpiknjD8P8mIP3B
bT+gETsKIhZEbux+YoY+EntRY6KjcMaBL3mrmW5KmJe36dOnOPVQRR/aO+veF8xgYA0v44m5khNV8yrsV+QgeNp1yqWHqbou
oZiW3BfoSTHexvpRa6j29m92CgN7WWVqNYrQrQhLxncqT8s4c+Ev/3Z5WFBOiGpXPbtJqnatKjbyLmUFfCbUhjyDRXrD8w+v
L4cfyB9OjsXpDdipoJK+029/E7EYwE6iV1aRL9SQwLsHFrtQjx7II5zkhM5l6YpMncRJTKcd8rZ3hdpdJfbBxR3TEIMd01z3
hol9R2UCVsTip5gsi1KheY0qdkyLZAGdJToX4AZBrsAzat+pwaWOpRMMOIABIRSyKxNrOkLSVa/pt4VNFlCwFJ2KL/XNKwKE
6Mt75uM+d9iy6yUfP8nvvcR0dLoIKB5NwNKIKJ5hxu9bQJgCupFlwoQFbYSJwuiNRycgW+D/bhdAY1FbBtP22AzBcwcsC/z1
N2BxRBkNS6D1edo60Pqe+UISgFBvwOUS7kXi7xc6qfYctArFAyBzdxaJRMiuZlkTqmvYZ9/oraagmrab3loN1sza0AIF8TBO
4rTBmKnuXWLfTkwVGZXu1pkbhQNa1Z60Vm/SdRqzEvMAQKAPZyxdqoxWT3ySTyiN2WC8lyqyQbLWiL397d3cI4C986mie2d1
EkaxSqss5W8nVsEqbRHRl04gTP9FAbbwwGphI1/VAkamatdobb2SeP+VOezOxmMi39WOqZlu1bjCynjowJrz6kfXdyXwqiu7
FjqycC1gwb91cwIJPgQTB+8/cEa1DF6LRB27r9416tcfc0ggVE5dlgl3SnG80DPiYPf3vcPLt5i/JD3M+fCF66eyKtgqW17V
MFNdEA7G8EkiDk2Lgl+pY/72X6WS+eWnv26//OWnfysYqUC8KT6l7ZqKdQOEKYumtpBNa6wXQ+WxLpHGD/L8BucT1nv2y0UO
ZbNC1XNgtVLHrHtGj51cKXc55GNuZ1hog4dI1RMRlv2JsjkNC1dPHcvWNdsi5S5KNrCaB4/Hi8g7pjtkfU1irSjoXKklVtR0
buhCvU5P0VJVw5Uyl8pRqqZL9O7FGAaXhtJp7+3Bdf9iiJWIsn4HzZbUJ3wmS9qc0kF/dQLXowWkKdAUzAlQAJbqUiAtJF1q
I+iq52EsEfw+Q9c5M2DpAiqX+aoGZ8Z9ECUzGot0GkZIFq4ov7GV4WhtHtFeKCLawiITeSKNl+YiiwxZIHbBz3+pzKO+AhOL
MLF2R/Vc0DP927/iNH/+izzdD39p60/Vjem7YBNdqcVaGVAvrfFGYWc5Y1V1pHJHiGRRGFqAXMuHdUVEZUY8wHptEHJufjoA
JR76KsCIIzHWCCbtuyDwyYjFKaxxDJccrI8Dh5HNck/h8mL4AevSHFhq6gDDRZksChf70sH2DyE3jGtBddwQxcgaVlHdEnN9
QiLKkhm4ELfvE9eeHdA5UIu9pqHlceocisYRIoAHtkwTa5+BR5J8MX/nzUiw6qu210ltfxIpYAs8zOKCW1luUc5w3Oc8n5CC
f5VNQbB3BxYL/bVIBGFtoizMx5vAjQ4WG2KVE5PET7sEVwecDYOpVfE1QkIJioeHA4GnaEvihMlEaDG1eiQRRW9C1SFDbsTe
YvpGXxZBhDpu+q2RnucT4Et10uBv/41sv5RNdHQzkjKjyDWvhdktpfzn4sGNgG3CzZWeSqIfwlLphS61IM6q4guj9qJDnorG
CjoIVy68kI0o4L7FxJhP9qtodLunXOJz77QiUCb30nWBo0/eXgxOv2F+l2zvkjY62mT72531ElEQsmPgWmQOmt8UT/PbWzB3
7pNzNGsZ6K2HoS8nr2BZkRuWFZ61x0SlKYvAGlX15hSFvQdmjyzjw4NgAFbWIctcBXCYxgWZV9IfrUqpkaZsStRxkU1ovhnh
8ECnw8ch0uqF6bHiDVdchH++UySQcSzhoK49ZszFGXl8i8YArsbPlhb65Un/nByR/vDDu6P+sAfa2fHcRU4faTNG1OdIH5tH
4m+wEoFEXSlGsHa/ABiAWsJWIy6WlFJZrIu6SigV8S7C1msw54T71AZyoSkHKirjoVXvc4sTg/uEryrD0VqzRRr297KgAwSZ
h9KojRbOLkxrJxdFLuiRl2sBFavPGzd5CbFS/m4N8G4Zyypq5bDy5rTJx/3xft4W0GmBEkgXEaH5IjhHQ0fOEVXFaLCQhayh
lxaL1WQegoF4kP3tX5HT5txPf/7LjHalMgRmQoDaKiqP02QP5iUWuGM6tSy5zu3biKDKdPx16KmAl9zWL5lPmZkWgpFWlEbk
E6sJV8mJNTpbC3hpuencA+gSzWiGzmRAC5dB8yjW4v/v/4kt+qQvVnVbNtsai/tQ8OuvhaBuciSEoMNTVp0ikqzngH0CifLQ
KTg0RQ5eoiM1QMXRMEnUVHcky9LANENDO8l9NBnOBxsSnZXqEZvlUrjNy+Bsfhu4D6iC+8+atl+tgOlGrAmzXVotKFoAG14G
otMfc9b2f3zMgqIHlrnoaxV4j1HdcqCIxIStpw8bodEhbT9UUD113AmYK0oW6J1jAbksMUHDT8MSV0EBS9swr3PB9jfvvz+6
+Eb0ecLs14RbX0paI6mxOXnbiBnfaaBxTtLN2V5Uijsguv5e68Tzav3mpjb5maxS2UbDiKWn19ZE369ge+V5C14pn95rLLLm
D62slgfPGs4NLVdVJzo0VmgdlDjUXtYj95B8hXJ++nS1JVIj41bLtUqp+5xjAK2DUVoZ3VqE3Hbt1roq8KZul5nDpr47Xa3/
VhxTqvbAXNR0fZmptiDqjNSSftLWgMGXVaZ6Ip6pcJZqhbiyz0zea0JMFO0vlIrm4XFlmNQ1qaw2NP7znwvhd+t6TFiIO1+C
FYgCjm3IhRepY0dWq7FnZplwItCGZdCqo51ulg2WTRJiZ2l9ob2yejeFn5MTx7n53e98P4pyxVuxIsTZ5f06CtTFLVUjXyn+
NaKqp8P1ae+4f300OO2TK3J2Pnh91Ce7uzrn0CUjFd6zObaoHhye9K6OeniWWh2ZdbjNPL5IJbRpkqmUDS0oAoQNeYZ+uwdO
eGRLF31KwI1LAie1yOGC6v54mTxPzdRxXzA1p6LVoX46UzFnETdBOxRuYlSAhFSEObFFcWBnKYDCsHWewWC+hFjpdZIZrZWL
eKFuIjQOM981cizESaNZkp8gVrHVllwNPfWWRd6JC9kS8ikqc400Uq8rQQVmI2gZl3Op3ZFxoqwkXIq+F5Wwq0RiB4XeE2PJ
2nV7pJM/fW8maSCdOs1tnuT2m1indiyBkBpM/F49yLRe45tVGgI52EZ7v7J+NRoJAmKmD5PL7fIRI0OZiTxtU+hxg+UoDM9I
OaeYn+OOx/NW3bRrBnbUoleChwvT7dR0w5qR5ZMTT8rmZvvL9o9qeL6BpMVcs2ziCbYZZoHBgD4cYJOZAYb5EmyzLm0HpEei
08WyofB9O0GvbvH8pNIjGtjN7Pq8ruVzcxfhSn8j0dp4iaKH/eP+sF/X1phc/a5/3pfssP9s++Wz1sr4n9wQ7/MujpKLrJDN
PYplJ88+PnvWWbKznj1rmW129cTZD8zOWyc3zF3RcfmXKrBKs12x/qsMGV0Bu8H+A3uGxazEEnq/N9VL7JkFmLWNf5d7lmfg
TngsfqeytQ9oXr6B4bbKHCqSmP9x5lBzYrVpV9blWxc8nN3ih3F07pvpc9k5Beq+DCEykJvOWOEjWyvhm1qR5z57QB1ZfGKR
M6GcCapjIsr1jX5C9YLrSh64K8UcVXusXn6mZMHQ4MD6D01oLH4Zi2QX8yQgMH2oRz3sHwi2ToLt1TFwr+OAdoqQAd08GEhz
8KU8P37yIcFAhWxFoRP75XT/UqLf/AqJzjIXdumGJw4e7byBcVbzPocLKjpWz6NUUFkuQce2bYzOajqI65cfymKVLl4ZFSax
pqHeEGy6MceJTivLSkO82vrxYyAzJC0CTvdNsqAT+rHVhd/fidANrMgznf8AwY8K5ZnIBjyzyDMVtH9G/CRype6eUCcD3f2x
ZcAt/XxsZarIJZ9SEUnvEBdNZ/wKTk0u52OrU8JWsz7i+8fSeD/CXY21nM0ZvAz/KIzlNQwx4MUZ93goL/3Db2x6+48vPrbI
ZwPgv+S/49XcJ9W7RDUNWC72aCz1uEIrSdR6/Nm8PGQ/xORxbCfM1TTb2beWtNPk3sg1s+qoWer98cUqdisXohdKASosA3Dq
dKsekTX2i7QLTEWuj5nAa9UJ2Q4YemAC6jIjFNAZ7CAUhVbtUlXU9XKnUtWkK7lPvKUj2yTL9nfNiYdH+NxIEZ/Z/JMjGxif
j/ThkNLXXJbMwK3lHOx5vwd267D3+rhPjt6Q08GQ9P9wdDG8qJqx7eVEroq4Dft/GJKz86OT3vkH8q7/QX/qgxydDvvf988F
0NPL4+O6WkHR4laCKB4D4w+dJbzaEeVVmfh9p7U8g5Xmq1SqIwFhBPpZdp5SB0Kx3a+bhDRvPoxVl6igI5R/jksnAcegxlgU
VqqwB+hi7nPdsU7OX0VG+LJPU+ssSEF2dHrRPx8iiQZLlK75YIqmiSLHjqJk6/e948v+BWmjY9Eh27sd8mz7W/jtme5BtMj7
gbl4WUz9Wf764JQcDE7fHB8dDOWoO+C+kcuzQ9wUF/2hwmGf/SA+6OZYGif1PqJW3DQRLa6WEC8uiz+1L/SFXo8BQ4sAE+yG
Eb+42z26GOC9vA2mcX6Uz4zPrGzgWK0tIFmxc0uu6PoPnvDZmvC17PTw9xK81u2HfoXwtayh9v+fCF9vFlvTbTA75N1wAPJ3
+OH43cCozkaBcji4GPbe9sm7wdnRkVX3kToJqPFLdbqHYzKS4d2R8H5AqNyNqh+uyyeYy94HfLVu+ZN1OhxrtKWkhetHZq4n
+rbzMcWP/inZl39AD8/549cA52D9BFaZr7HMTXVyF3XT9R+D0G2W5+qkiSTbFEOqsmEonqEQFXMYlM4b2pa/Pak6I0hYPpvQ
MZ3Guq2mPKCpDq+g/zcGrYfqKHdElsLNfwd5jgr1tlaV3uXJtq1VpW//mTn5/zdzUuXF6scQHy2zcq9w/gbkXZNmqQ/pb5Zs
KQJWKL575HUPu7eLolrZTlcrFCHXdwu5Dq9jDwE38lNcnGV5PFL9mLGjqijFTbFFuC2+YMFEBUxR1JagnGOyE5yKeokW0J75
1VV9Gs/AqdxDVp5zx4auApfiQ71Ylif2p088Bi4a3hGbTfZ7UaykzmYd9QeHV+e9g97x6QdLfSKRyZ0pVyUC5uVLNR1ya4vm
sQEVm4xVG/eWU1UOx03v/mqZKlnn/tAPeT7ZsKtrtdnDclficW17MGznvdQdrLaJBn7pd1xXoP9EUdCoO5mXirTVfcxpzcuR
PBM/YSS8ptnSQpgIaFBNeRuQ6Bj/vJcqaRA7CKpO6HTUnXsImJwS6wSNaK6+/bJRzihPR4fcBaEtQ4OuFESawLgOMIWyXaxv
LsVDmsQXPJsaIky8u+7Q6793krjkl+w1541LLSBrE8cd2H6mc7E+gYyH+fBwMJi7FEWbOmuBdfCg8LEMvlVRnmBrYumVq6qA
cYcUsIqt0pJnz6g6epbbCSlpZzTCM5eZLqU76B3uWAY+g8OzwdVR//CaXBPQMheX0qm4LH8qFj+mIT7XMCo68Y5Er68C1GjO
HXUaVeqXTH4FIpAhR1b+YqC2SrBOTMwtngXUK6C1xfmc1XFwPL1RdWpkzh3olioNWIAEip4efX8IOtS+49rsLnVBIUmWxngI
mmnkF6KfmC/WVWZcag4s5vNe2c61eGzN5/YU2BDXbd+AXuyrrTVHXTaxt4vTJuBGqSF+/l/divOcz8w8RYSbWLWNj3KbLZGf
J0aLovz1dDyEpUwSW3o8xlFISWVYa517Ec3nVJC6owsmfvnpf6A/qhrA34GyipivnKUJhqKnHYMtkgkLRX+4cSrOq+MxJty9
8yjxeP0S8gkP7uXTPIjMq6bYXBOymRqpRFC2lk4+oSSrVqVY2y+NjiO44TqSFOb7XX1GY3vXqOQW43VK7/xfXcRi1K6A+Jx7
Ihiiuia7RkXLUhWLkX1Yxf0N32xVB4+KvEeuakqh4IelzuUnPlTDZ6ZLcOBXUD4eIxfD/slZ/5hcwH4UXTp62ATyWPCVGa5v
Fd+VkBFxzL5TT36qT3CY0i3iUynN1H6kkhGwhT5t73blsYKtDc/q3fNbYpsDLkWdN3j+wdUt/weKDX7E"""),
    ('src/app/qml/QfWyposazenie.qml', '54789795329bd4813c78b792e4ade2b1', '16f3a841dbc820431efed81e4a53f3a2', """\
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"""),
]

bledy = []
plan = []

for cel, przed, po, ladunek in PLIKI:
    if not os.path.exists(cel):
        bledy.append('brak pliku %s' % cel)
        continue
    teraz = hashlib.md5(open(cel, 'rb').read()).hexdigest()
    if teraz == po:
        print('  juz zrobione: %s' % cel)
        continue
    if teraz != przed:
        bledy.append('%s zostal zmieniony w miedzyczasie\n'
                     '     mam:       %s\n'
                     '     oczekuje:  %s\n'
                     '     Nie podmieniam calego pliku na slepo — powiedz mi o tym,\n'
                     '     przysle latke kotwiczona na fragmentach.' % (cel, teraz, przed))
        continue
    plan.append((cel, ladunek))

if bledy:
    print('NIC NIE ZAPISANO. Zarzuty:')
    for b in bledy:
        print(' -', b)
    sys.exit(1)

if not plan:
    print('  nic do roboty')
    sys.exit(0)

for cel, ladunek in plan:
    tresc = zlib.decompress(base64.b64decode(''.join(ladunek.split())))
    open(cel, 'wb').write(tresc)
    print('  %-34s podmieniony' % cel)

print()
print('  podmienionych plikow: %d' % len(plan))
KONIEC_PY

echo
echo "Sprawdzenie na oko:"
echo "  grep -n 'tylkoSprawdza' src/core/wyposazenie.cpp src/app/qml/QfWyposazenie.qml"
echo "  grep -n 'Sprawdź' src/app/qml/QfWyposazenie.qml"
echo
echo "Build (podbije numer na kolejny sam z siebie):"
echo "  triplet=arm64-android ./scripts/build.sh 2>&1 | head -3"
echo "  bash skrypty/przygotuj_apk.sh && bash skrypty/zainstaluj_apk.sh"
echo
echo "NA TELEFONIE — na tym samym projekcie 3853_24_pin UKSW:"
echo "  1. Wyposazenie: przy „Warstwa robocza tyczenia” i „Kafle paska”"
echo "     przycisk ma mowic SPRAWDZ, nie ZALOZ."
echo "  2. Tapnij go. Zamiast „Krok sie nie powiodl” ma paść konkret:"
echo "     „w projekcie nie ma warstwy tyczenie. Ten modul tylko SPRAWDZA…”"
echo "  3. W katalogu projektu NIE ma przybywac plikow .przed_* po takich"
echo "     probach. Stare mozesz skasowac."
