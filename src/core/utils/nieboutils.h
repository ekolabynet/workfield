/***************************************************************************
                            nieboutils.h - NieboUtils
                              -------------------
  WorkField, 22.08.2026

  Most miedzy lista satelitow w C++ a wykresem nieba w QML.

  Powod istnienia: QfGnssPositionInformation wystawia
  `QList<QgsSatelliteInfo> satellitesInView` jako Q_PROPERTY, ale ani QField,
  ani my nie czytamy z QML pojedynczego satelity — sprawdzone gitem po calym
  drzewie i po upstreamie. Czy QML dosiegnie pol QgsSatelliteInfo, zalezy od
  tego, czy QGIS zarejestrowal ten typ jako wartosciowy; nie budujemy panelu
  na takim zalozeniu. Tu zamieniamy liste na QVariantList map, ktory QML czyta
  zawsze i wszedzie.

 ***************************************************************************/

#ifndef NIEBOUTILS_H
#define NIEBOUTILS_H

#include <QObject>
#include <QVariantList>

/**
 * \ingroup core
 */
class NieboUtils : public QObject
{
    Q_OBJECT

  public:
    explicit NieboUtils( QObject *parent = nullptr );

    /**
     * Zamienia \a informacjaOPozycji (QfGnssPositionInformation z QML,
     * czyli `positionSource.positionInformation`) na liste map opisujacych
     * satelity. Kazda mapa ma klucze:
     *
     *   numer        int    — identyfikator satelity (PRN)
     *   azymut       double — stopnie od polnocy, zgodnie z ruchem wskazowek
     *   elewacja     double — stopnie nad horyzontem, 90 = zenit
     *   sygnal       int    — SNR w dB-Hz, 0 gdy nieznany
     *   uzyty        bool   — czy wchodzi do rozwiazania pozycji
     *   konstelacja  QString— "GPS", "GLONASS", "Galileo", "BeiDou",
     *                         "QZSS", "SBAS" albo "?" gdy odbiornik nie podaje
     *
     * Satelity bez sensownego azymutu albo elewacji sa pomijane — na niebie
     * nie ma dla nich miejsca, a zero-zero rysowaloby je wszystkie na polnocy
     * przy horyzoncie i sugerowalo przeszkode, ktorej nie ma.
     */
    Q_INVOKABLE QVariantList satelity( const QVariant &informacjaOPozycji ) const;

    /**
     * Podsumowanie tej samej listy: ile widocznych, ile uzytych, mediana SNR
     * satelitow uzytych i ile z nich stoi nisko (elewacja < \a progNiski).
     * Klucze: widoczne, uzyte, medianaSnr, nisko.
     */
    Q_INVOKABLE QVariantMap podsumowanie( const QVariant &informacjaOPozycji, double progNiski = 15.0 ) const;
};

#endif // NIEBOUTILS_H
