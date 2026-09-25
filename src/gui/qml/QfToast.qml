import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.qfield.core
import org.qfield.gui

/**
 * \ingroup qml
 */
Popup {
  id: toast

  property string type: 'info'

  /**
   * WorkFieldGIS 23.09.2026 — DYMEK, KTÓRY CZEKA NA TAPNIĘCIE.
   *
   * Dymek przy otwarciu projektu wymienia, czego brakuje — bywa, że trzy
   * rzeczy. Trzy sekundy (pięć z przyciskiem) nie wystarczają, żeby to
   * przeczytać w rękawicach i w słońcu, a drugi raz ten komunikat już nie
   * przyjdzie: leci raz, półtorej sekundy po wczytaniu projektu.
   *
   * WŁĄCZANE OSOBNO, przez `pokazTrwaly()`. Zwykłe dymki („Przeglądanie",
   * „Autozapis projektu") mają nadal gasnąć same — dymek wiszący po każdej
   * drobnej czynności byłby gorszy od zbyt krótkiego.
   *
   * Trwały dymek jest SZERSZY (mniejszy margines), ma MNIEJSZĄ czcionkę
   * i przycisk pod tekstem, a nie obok — bo mieści więcej niż jedno zdanie.
   */
  property bool trwaly: false

  //! Nagłówek nad treścią — tylko przy trwałym. Dymek startowy wymienia
  //! kilka rzeczy naraz i bez nagłówka czyta się jak jedno długie zdanie.
  property string naglowek: ""

  /**
   * Odsyłacze pod treścią: lista map `{ etykieta, akcja }`.
   *
   * Zwykły dymek ma JEDEN przycisk („Pokaż") i to wystarcza. Dymek
   * startowy mówi o dwóch różnych rzeczach — ustawieniach i błędach
   * w danych — które naprawia się w dwóch różnych oknach. Jeden przycisk
   * musiałby zgadnąć, do którego prowadzić.
   */
  property var akcje: []

  property double edgeSpacing: trwaly ? 12 : 54
  property double bottomSpacing: 0
  property var act: undefined
  property var timeoutAct: undefined
  property bool timeoutFeedback: false

  property real virtualKeyboardHeight: {
    if (Qt.platform.os === "android") {
      const top = Qt.inputMethod.keyboardRectangle.top / Screen.devicePixelRatio;
      if (top > 0) {
        const height = Qt.inputMethod.keyboardRectangle.height / Screen.devicePixelRatio;
        return height - (top + height - mainWindow.height);
      }
    }
    return 0;
  }

  x: edgeSpacing
  y: mainWindow.height
  z: 10001

  width: mainWindow.width - edgeSpacing * 2
  // Przy trwalym dymku tekst ma kilka linii I przycisk pod soba — wysokosc
  // samego tekstu nie wystarcza, bo przycisk wyladowalby poza ramka.
  height: trwaly ? toastContent.height + 20 : toastMessage.contentHeight + 20
  topMargin: 0
  leftMargin: 0
  rightMargin: 0
  bottomMargin: 60 + Math.max(bottomSpacing, virtualKeyboardHeight)
  padding: 0
  closePolicy: Popup.NoAutoClose

  background: Item {}

  onClosed: {
    toastTimer.stop();
    animationTimer.stop();
    animationTimer.reset();
    toast.timeoutAct = undefined;
    timeoutFeedback = false;
    // `trwaly` NIE jest tu zerowane. Zamkniecie idzie w parze z gasnieciem
    // (250 ms), a zmiana `trwaly` w tej samej chwili przestawilaby szerokosc
    // i czcionke W TRAKCIE animacji — dymek skakalby w polowie znikania.
    // Zeruje to `show()`, czyli kazdy nastepny ZWYKLY dymek.
  }

  Rectangle {
    id: toastContent

    property int contentPadding: toast.trwaly ? 26 : 20
    property int topPadding: toastLayout.columns === 1 ? 8 : 10
    property int bottomPadding: toastLayout.columns === 1 ? 12 : 10
    property int actionWidth: toastAction.visible ? toastAction.width + 10 : 0
    property int absoluteMessageWidth: toastFontMetrics.boundingRect(toastMessage.text).width + actionWidth + 10
    property int unrestrainedWidth: contentPadding * 2 + toastFontMetrics.boundingRect(toastMessage.text).width + actionWidth + 10

    z: 1
    // Trwaly dymek bierze CALA dostepna szerokosc: ma do powiedzenia
    // wiecej niz jedno zdanie i lamanie go w waski slupek jest gorsze.
    width: toast.trwaly ? toast.width - 20
                        : Math.min(unrestrainedWidth, toast.width - 20)
    height: toastLayout.height + topPadding + bottomPadding
    anchors.centerIn: parent

    color: "#CC202020"
    border.color: "#CC404040"
    radius: 4
    opacity: 0

    Behavior on opacity {
      NumberAnimation {
        duration: 250
      }
    }

    onOpacityChanged: {
      if (opacity === 0.0) {
        toast.close();
      }
    }

    ProgressBar {
      id: animationProgressBar
      padding: 2
      anchors.fill: parent
      visible: timeoutFeedback
      z: toastLayout.z - 1
      value: animationTimer.position / toastTimer.interval

      background: Item {
        anchors.fill: parent
      }

      contentItem: Item {
        anchors.fill: parent

        Rectangle {
          width: animationProgressBar.visualPosition * parent.width
          height: parent.height
          radius: 2
          color: Qt.hsla(QfTheme.mainColor.hslHue, QfTheme.mainColor.hslSaturation, QfTheme.mainColor.hslLightness, 0.5)
          visible: !animationProgressBar.indeterminate
        }
      }
    }

    Rectangle {
      id: toastIndicator
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 5
      topLeftRadius: toastContent.radius
      bottomLeftRadius: toastContent.radius
      topRightRadius: 0
      bottomRightRadius: 0
      color: {
        switch (toast.type) {
        case 'attention':
          return QfTheme.mainColor;
        case 'error':
          return QfTheme.errorColor;
        case 'warning':
        default:
          return QfTheme.warningColor;
        }
      }
      visible: toast.type != 'info'
    }

    GridLayout {
      id: toastLayout
      width: parent.width - toastContent.contentPadding * 2
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.topMargin: toastContent.topPadding
      anchors.leftMargin: toastContent.contentPadding
      columnSpacing: 10
      rowSpacing: 12
      columns: toast.trwaly || toastContent.absoluteMessageWidth > mainWindow.width * 1.75 ? 1 : 2

      Text {
        id: toastNaglowek
        Layout.fillWidth: true
        visible: toast.trwaly && text !== ""
        wrapMode: Text.Wrap
        color: QfTheme.light
        // Pojedyncze wlasnosci, nie `font:` — grupy i jej skladowej nie
        // wolno przypisac na tym samym elemencie.
        font.pointSize: QfTheme.defaultFont.pointSize
        font.bold: true
        horizontalAlignment: Text.AlignLeft
      }

      Text {
        id: toastMessage
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: QfTheme.light

        // Mniejsza czcionka przy trwalym: tekst jest dluzszy, a dymek
        // i tak nie znika sam, wiec nie trzeba go czytac w biegu.
        font: toast.trwaly ? QfTheme.tipFont : QfTheme.defaultFont
        horizontalAlignment: Text.AlignLeft
      }

      QfButton {
        id: toastAction
        Layout.alignment: (toastLayout.columns === 1 ? Qt.AlignLeft : Qt.AlignHCenter) | Qt.AlignVCenter
        radius: 4
        bgcolor: "#00000000"
        color: QfTheme.mainColor
        font.pointSize: QfTheme.tipFont.pointSize
        // JEDEN `visible`, nie dwa. Przy trwalym dymku odsylacze rysuje
        // `toastAkcje` nizej, wiec ten przycisk ma zniknac — inaczej
        // wyszlyby dwa rzedy przyciskow, jeden pusty.
        visible: !toast.trwaly && text != ''

        onClicked: {
          if (toast.act !== undefined) {
            toast.act();
          }
          toast.close();
          toastContent.opacity = 0;
        }
      }

      // Odsylacze trwalego dymka. JASNOZIELONE TLO, nie sam tekst w kolorze:
      // na ciemnym dymku link rozniacy sie wylacznie barwa liter ginie
      // w sloncu, a to jedyne swiatlo, w jakim ten dymek bywa czytany.
      Flow {
        id: toastAkcje

        Layout.fillWidth: true
        visible: toast.trwaly && toast.akcje.length > 0
        spacing: 8

        Repeater {
          model: toast.akcje

          QfButton {
            text: modelData.etykieta
            radius: 4
            bgcolor: "#C8E6C9"
            color: "#1B5E20"
            font.pointSize: QfTheme.tipFont.pointSize

            onClicked: {
              if (modelData.akcja !== undefined) {
                modelData.akcja();
              }
              toast.close();
              toastContent.opacity = 0;
            }
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    onPressed: {
      if (toast.timeoutAct !== undefined) {
        toast.timeoutAct();
      }
      toast.close();
      toastContent.opacity = 0;
    }
  }

  FontMetrics {
    id: toastFontMetrics
    font: toastMessage.font
  }

  Timer {
    id: animationTimer
    interval: 50
    repeat: true

    property real position: 0

    onTriggered: {
      position += interval;
      if (animationProgressBar.value === 1) {
        animationTimer.stop();
      }
    }

    function reset() {
      position = 0;
    }
  }

  Timer {
    id: toastTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (toast.timeoutAct !== undefined) {
        toast.timeoutAct();
      }
      toastContent.opacity = 0;
    }
  }

  function show(text, type, action_text, action_function, timeout_feedback, timeout_function) {
    if (toastTimer.running) {
      if (toastMessage.text === text) {
        if (animationTimer.running) {
          animationTimer.reset();
          animationTimer.restart();
        }
        toastTimer.restart();
        return;
      } else {
        if (toast.timeoutAct !== undefined) {
          toast.timeoutAct();
        }
      }
    }

    toast.trwaly = false;
    toastNaglowek.text = '';
    toast.akcje = [];
    toastMessage.text = text;
    toast.type = type || 'info';
    if (timeout_feedback !== undefined) {
      toast.timeoutFeedback = timeout_feedback;
    } else {
      toast.timeoutFeedback = false;
    }
    if (timeout_function !== undefined) {
      toast.timeoutAct = timeout_function;
    } else {
      toast.timeoutAct = undefined;
    }
    if (action_text !== undefined && action_function !== undefined) {
      toastAction.text = action_text;
      toast.act = action_function;
      toastTimer.interval = 5000;
    } else {
      toastAction.text = '';
      toast.act = undefined;
      toastTimer.interval = 3000;
    }
    toastContent.opacity = 1;
    toast.open();
    toastTimer.restart();
    if (toast.timeoutFeedback) {
      animationTimer.reset();
      animationTimer.restart();
    }
  }

  /**
   * Dymek, ktory NIE GASNIE SAM — czeka na tapniecie.
   *
   * Celowo osobna funkcja, a nie kolejny argument `show()`: ta ma ich
   * juz szesc i siodmy byloby latwo wpisac przez pomylke w zwyklym
   * wywolaniu. Tu trzeba napisac inna nazwe, zeby dostac inne zachowanie.
   *
   * `toastTimer` NIE JEST uruchamiany. Zamyka to tapniecie w dymek
   * (MouseArea nizej) albo tapniecie w przycisk akcji.
   */
  function pokazTrwaly(naglowek, text, type, akcje) {
    if (toastTimer.running) {
      toastTimer.stop();
    }
    animationTimer.stop();
    animationTimer.reset();

    toast.trwaly = true;
    toastNaglowek.text = naglowek !== undefined ? naglowek : '';
    toastMessage.text = text;
    toast.type = type || 'info';
    toast.timeoutFeedback = false;
    toast.timeoutAct = undefined;
    toastAction.text = '';
    toast.act = undefined;
    toast.akcje = akcje !== undefined && akcje !== null ? akcje : [];
    toastContent.opacity = 1;
    toast.open();
  }
}
