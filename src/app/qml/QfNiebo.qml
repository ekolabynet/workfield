import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import Theme

/**
 * WorkField 22.08.2026 — panel "Niebo".
 *
 * Odpowiada na pytanie, na ktore liczba "±8 m" nie odpowiada: DLACZEGO tyle.
 * Kropka na kole to satelita: polozenie z azymutu i elewacji, kolor z SNR,
 * wypelnienie = uzyty w rozwiazaniu. Pusta polowa nieba od poludnia znaczy
 * sciana albo korona drzewa, a nie awarie odbiornika.
 *
 * Dane ida przez NieboUtils (C++), bo QML nie czyta pol QgsSatelliteInfo —
 * sprawdzone po naszym drzewie i po upstreamie, nikt tego nie robi.
 */
Popup {
  id: niebo

  property var posInfo: positionSource.positionInformation
  property var satelity: []
  property var podsumowanie: ({
      "widoczne": 0,
      "uzyte": 0,
      "medianaSnr": 0,
      "nisko": 0
    })
  property int maska: settings.valueInt('WorkField/maskaElewacji', 0)

  parent: mainWindow.contentItem
  width: Math.min(mainWindow.width - 24, 560)
  height: Math.min(mainWindow.height - mainWindow.sceneTopMargin - 24, 820)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  modal: true
  padding: 0

  background: Rectangle {
    color: Theme.mainBackgroundColor
    radius: 8
    border.color: Theme.controlBorderColor
    border.width: 1
  }

  function odswiez() {
    posInfo = positionSource.positionInformation;
    satelity = NieboUtils.satelity(posInfo);
    podsumowanie = NieboUtils.podsumowanie(posInfo, 15);
    kopula.requestPaint();
  }

  onOpened: odswiez()

  Timer {
    running: niebo.opened
    interval: 1000
    repeat: true
    onTriggered: niebo.odswiez()
  }

  // Skala barw taka sama jak przy dokladnosci w belce — zeby czerwony
  // wszedzie znaczyl to samo.
  function barwa(snr) {
    if (snr <= 0)
      return "#78909C";
    if (snr < 25)
      return "#EF5350";
    if (snr < 35)
      return "#FFEB3B";
    return "#00E676";
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      // WorkField 22.08: wyrazny Wstecz, nie sam krzyzyk w rogu — panel
      // otwiera sie z diagnostyki i trzeba miec dokad wrocic.
      Button {
        text: "\u2190  " + qsTr("Wstecz")
        font: Theme.defaultFont
        onClicked: niebo.close()
      }

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        text: qsTr("Niebo")
        font: Theme.strongFont
        color: Theme.mainTextColor
      }
    }

    // ── kopula ──────────────────────────────────────────────
    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(width, niebo.height * 0.52)

      Canvas {
        id: kopula
        anchors.fill: parent

        onPaint: {
          const ctx = getContext("2d");
          ctx.reset();

          const cx = width / 2;
          const cy = height / 2;
          const R = Math.min(width, height) / 2 - 18;

          // siatka: horyzont, 30 i 60 stopni
          ctx.strokeStyle = Theme.controlBorderColor;
          ctx.lineWidth = 1;
          for (const elew of [0, 30, 60]) {
            const r = R * (1 - elew / 90);
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
            ctx.stroke();
          }

          // krzyz N-S / E-W
          ctx.beginPath();
          ctx.moveTo(cx - R, cy);
          ctx.lineTo(cx + R, cy);
          ctx.moveTo(cx, cy - R);
          ctx.lineTo(cx, cy + R);
          ctx.stroke();

          // maska elewacji — przerywany okrag; ponizej niego odbiornik
          // satelitow nie uzywa, wiec puste miejsce tam nie jest problemem
          if (niebo.maska > 0) {
            const rm = R * (1 - niebo.maska / 90);
            ctx.save();
            ctx.setLineDash([4, 4]);
            ctx.strokeStyle = "#FFA726";
            ctx.beginPath();
            ctx.arc(cx, cy, rm, 0, 2 * Math.PI);
            ctx.stroke();
            ctx.restore();
          }

          // zenit — pogrubiony krzyz w srodku; bez niego oko gubi punkt
          // odniesienia, gdy satelitow jest malo
          ctx.strokeStyle = Theme.mainTextColor;
          ctx.lineWidth = 2.5;
          ctx.beginPath();
          ctx.moveTo(cx - 9, cy);
          ctx.lineTo(cx + 9, cy);
          ctx.moveTo(cx, cy - 9);
          ctx.lineTo(cx, cy + 9);
          ctx.stroke();
          ctx.lineWidth = 1;

          // strony swiata
          ctx.fillStyle = Theme.secondaryTextColor;
          ctx.font = "bold 12px sans-serif";
          ctx.textAlign = "center";
          ctx.textBaseline = "middle";
          ctx.fillText("N", cx, cy - R - 9);
          ctx.fillText("S", cx, cy + R + 9);
          ctx.fillText("E", cx + R + 9, cy);
          ctx.fillText("W", cx - R - 9, cy);

          // satelity
          for (const sat of niebo.satelity) {
            const r = R * (1 - sat.elewacja / 90);
            const kat = sat.azymut * Math.PI / 180;
            const x = cx + r * Math.sin(kat);
            const y = cy - r * Math.cos(kat);
            const kolor = niebo.barwa(sat.sygnal);

            ctx.beginPath();
            ctx.arc(x, y, 11, 0, 2 * Math.PI);
            if (sat.uzyty) {
              ctx.fillStyle = kolor;
              ctx.fill();
            } else {
              ctx.strokeStyle = kolor;
              ctx.lineWidth = 2;
              ctx.stroke();
            }

            ctx.fillStyle = sat.uzyty ? "#102027" : kolor;
            ctx.font = "bold 10px sans-serif";
            ctx.fillText(String(sat.numer), x, y);
          }
        }
      }
    }

    // ── maska elewacji ──────────────────────────────────────
    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        text: qsTr("Maska elewacji")
        font: Theme.tipFont
        color: Theme.secondaryTextColor
      }

      Repeater {
        model: [0, 10, 15, 20]

        Button {
          text: modelData === 0 ? qsTr("brak") : modelData + "°"
          font.pointSize: Theme.tinyFont.pointSize
          highlighted: niebo.maska === modelData
          enabled: modelData === 0 || (positionSource.active && positionSource.deviceId !== "")
          onClicked: {
            if (modelData > 0)
              positionSource.setGnssMinimumElevation(modelData);
            niebo.maska = modelData;
            settings.setValue('WorkField/maskaElewacji', modelData);
            kopula.requestPaint();
          }
        }
      }
    }
    // ── slupki SNR ──────────────────────────────────────────
    Text {
      Layout.fillWidth: true
      visible: niebo.satelity.length > 0
      text: qsTr("Siła sygnału (dB-Hz)")
      font: Theme.tipFont
      color: Theme.secondaryTextColor
    }

    ScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true

      Row {
        spacing: 3

        Repeater {
          // malejaco: pierwszy slupek to satelita, ktory trzyma fix
          model: niebo.satelity.slice().sort(function (a, b) {
            return b.sygnal - a.sygnal;
          })

          Column {
            spacing: 2

            Rectangle {
              width: 18
              height: Math.max(2, (modelData.sygnal / 55) * 90)
              y: 90 - height
              radius: 2
              color: niebo.barwa(modelData.sygnal)
              opacity: modelData.uzyty ? 1.0 : 0.45
            }

            Text {
              width: 18
              horizontalAlignment: Text.AlignHCenter
              text: modelData.numer
              font.pointSize: Theme.tinyFont.pointSize - 1
              color: Theme.secondaryTextColor
            }
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      text: {
        const p = niebo.podsumowanie;
        if (p.widoczne === 0)
          return qsTr("Odbiornik nie podaje pozycji satelitów. Panel ożyje, gdy przyjdzie pierwsza depesza GSV.");
        let s = qsTr("%1 widocznych · %2 w rozwiązaniu · mediana SNR %3 dB").arg(p.widoczne).arg(p.uzyte).arg(p.medianaSnr);
        if (p.nisko > 0)
          s += "  ·  " + qsTr("%1 nisko nad horyzontem").arg(p.nisko);
        return s;
      }
    }

    Text {
      Layout.fillWidth: true
      visible: niebo.satelity.length > 0
      wrapMode: Text.WordWrap
      font: Theme.tipFont
      color: Theme.secondaryTextColor
      text: {
        // ile satelitow z kazdej konstelacji jest w rozwiazaniu — mowi,
        // czy odbiornik korzysta z wszystkiego, co ma, czy tylko z GPS
        const licz = {};
        for (const sat of niebo.satelity) {
          if (!sat.uzyty)
            continue;
          licz[sat.konstelacja] = (licz[sat.konstelacja] || 0) + 1;
        }
        const czesci = [];
        for (const k in licz)
          czesci.push(k + " " + licz[k]);
        return czesci.length > 0 ? qsTr("W rozwiązaniu: ") + czesci.join("  ·  ") : qsTr("Żaden satelita nie wchodzi jeszcze do rozwiązania.");
      }
    }

  }
}
