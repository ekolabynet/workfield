"""Instalator łatki [WF-QC-OPTIONS] 24.11.2026 — NOWY plik: okno ustawień paska szybkiego zapisu.
Plik: /DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfQuickCaptureOptions.qml
Miejsce w repo: skrypty/jednorazowe/2026-11-24_instaluj_pasek_qc_okno.py
Domyślnie PRÓBA; zapis: --zapisz. Opcja --plik <ścieżka> do testu.
"""
import base64, gzip, hashlib, os, sys

PLIK = '/DATA/SOFT/GIS/QFIELD_Pro/QField/src/app/qml/QfQuickCaptureOptions.qml'
MD5_PO = '16d5294b8e06ba36c10f638c9ac79531'
TRESC = gzip.decompress(base64.b64decode('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'))


def main():
    plik = PLIK
    if '--plik' in sys.argv:
        plik = sys.argv[sys.argv.index('--plik') + 1]
    print('plik:', plik)
    if hashlib.md5(TRESC).hexdigest() != MD5_PO:
        print('STOP — treść w instalatorze uszkodzona.')
        return 1
    if os.path.exists(plik):
        md5 = hashlib.md5(open(plik, 'rb').read()).hexdigest()
        if md5 == MD5_PO:
            print('JUŻ ZAINSTALOWANE — nic nie zmieniam.')
            return 0
        print('STOP — plik już istnieje i ma inną treść (md5 %s). Nie nadpisuję cudzej pracy.' % md5)
        return 1
    if '--zapisz' not in sys.argv:
        print('nowy plik, %d bajtów, md5 %s' % (len(TRESC), MD5_PO))
        print('PRÓBA — nic nie zapisano. Zapis: dopisz --zapisz')
        return 0
    with open(plik, 'wb') as f:
        f.write(TRESC)
    print('ZAPISANO nowy plik.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
