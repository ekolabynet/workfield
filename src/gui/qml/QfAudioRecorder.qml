import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtMultimedia
import QtCore
import org.qfield.core
import org.qfield.gui

/**
 * \ingroup qml
 */
// [WF-WINDOW-FRAME] 24.10.2026 — common frame: ✕ / ✓ Zapisz in the title bar
QfWindowFrame {
  id: audioRecorder

  title: qsTr('Audio Recorder')
  confirmText: qsTr("Zapisz")
  confirmEnabled: audioRecorder.hasRecordedClip
  preferredWidth: 400
  onConfirmed: confirm()
  // ✕ = the former close button: users of this window listen to `canceled`
  onCancelled: audioRecorder.canceled()

  // [WF-WINDOW-FRAME] ✓ in the title bar (was the round ✓ next to the player)
  function confirm() {
    const path = recorder.actualLocation.toString();
    audioRecorder.finished(QfUrlUtils.toLocalFile(path));
    audioRecorder.close();
  }

  signal finished(string path)
  signal canceled

  property bool preRecording: true
  property bool hasRecordedClip: player.duration > 0
  property int popupWidth: Math.min(400, mainWindow.width <= mainWindow.height ? mainWindow.width - QfTheme.popupScreenEdgeVerticalMargin : mainWindow.height - QfTheme.popupScreenEdgeVerticalMargin)

  z: 10000 // 1000s are embedded feature forms, use a higher value to insure feature form popups always show above embedded feature formes


  onAboutToShow: {
    preRecording = true;
    player.source = '';
    if (microphonePermission.status === Qt.PermissionStatus.Undetermined) {
      microphonePermission.request();
    }
    recorder.mediaFormat.audioCodec = MediaFormat.AudioCodec.AAC;
    recorder.mediaFormat.fileFormat = MediaFormat.Mpeg4Audio;
  }

  QfMicrophonePermission {
    id: microphonePermission
  }

  QfAudioRecorder {
    id: recorder
  }

  Loader {
    id: captureSessionLoader
    active: microphonePermission.status !== Qt.PermissionStatus.Undetermined

    property QfAudioRecorder audioRecorder: recorder

    sourceComponent: Component {
      CaptureSession {
        audioInput: AudioInput {}
        recorder: audioRecorder
      }
    }
  }

  /**
   * Until QAudioRecorder reliably changes its status across all platforms after calling stop(),
   * use a timer as workaround and check for duration > 0 as condition for successful
   * saved audio recording.
   */
  Timer {
    id: playerLoader
    interval: 500
    repeat: true
    running: false

    onTriggered: {
      player.source = QfUrlUtils.fromString(recorder.actualLocation.toString());
    }
  }

  Page {
    Layout.fillWidth: true
    Layout.preferredHeight: audioRecorder.popupWidth // [WF-WINDOW-FRAME] the record / level area
    padding: 10
    background: null // the frame paints the background (Page's own Material one would differ)

    Video {
      id: player

      property bool loaded: false

      anchors.left: parent.left
      anchors.top: parent.top
      visible: false
      width: parent.width
      height: parent.height - 54

      muted: false
      volume: 1.0

      onDurationChanged: {
        if (duration > 0 && !loaded) {
          playerLoader.stop();
          loaded = true;
        }
        positionSlider.to = duration / 1000;
        positionSlider.value = 0;
      }

      onPositionChanged: {
        positionSlider.value = position / 1000;
      }
    }
    ColumnLayout {
      width: parent.width
      height: parent.height

      Rectangle {
        id: audioFeedback
        Layout.fillWidth: true
        Layout.fillHeight: true

        color: "transparent"

        Rectangle {
          id: levelFeedback
          anchors.centerIn: parent
          width: 120 + (Math.min(audioFeedback.width, audioFeedback.height) - 120) * Math.min(1.0, recorder.level * 2)
          height: width
          radius: width / 2
          color: "#44808080"

          Behavior on width {
            SmoothedAnimation {
              duration: 200
            }
          }

          SequentialAnimation {
            NumberAnimation {
              target: levelFeedback
              property: "width"
              to: 120 + (Math.min(audioFeedback.width, audioFeedback.height) - 120)
              duration: 2000
              easing.type: Easing.InOutQuad
            }
            NumberAnimation {
              target: levelFeedback
              property: "width"
              to: 120
              duration: 2000
              easing.type: Easing.InOutQuad
            }
            running: !recorder.hasLevel && recorder.recorderState === MediaRecorder.RecordingState
            loops: Animation.Infinite
          }

          QfToolButton {
            id: recordButton
            anchors.centerIn: parent
            width: 120
            height: 120
            iconSource: ''
            round: true
            bgcolor: recorder.recorderState === MediaRecorder.RecordingState ? "#99FF0000" : "#FF0000"

            Rectangle {
              anchors.centerIn: parent
              width: parent.width / 2
              height: width

              radius: recorder.recorderState === MediaRecorder.RecordingState ? 10 : width / 2
              color: "#FFFFFF"

              Behavior on radius {
                PropertyAnimation {
                  duration: 250
                  easing.type: Easing.InOutQuad
                }
              }
            }

            onClicked: {
              if (preRecording) {
                recorder.record();
                preRecording = false;
              } else {
                if (recorder.recorderState === MediaRecorder.RecordingState) {
                  // As of Qt5.15, Android doesn't support pausing a recording, revisit in Qt6
                  recorder.stop();
                  playerLoader.start();
                } else {
                  playerLoader.stop();
                  player.source = '';
                  recorder.record();
                }
              }
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true

        QfToolButton {
          id: playButton
          enabled: audioRecorder.hasRecordedClip
          opacity: enabled ? 1 : 0.25

          iconSource: player.playbackState == MediaPlayer.PlayingState ? QfTheme.getThemeVectorIcon('ic_pause_black_24dp') : QfTheme.getThemeVectorIcon('ic_play_black_24dp')
          iconColor: QfTheme.mainTextColor
          bgcolor: "transparent"

          onClicked: {
            if (player.playbackState == MediaPlayer.PlayingState) {
              player.pause();
            } else {
              player.play();
            }
          }
        }

        Slider {
          id: positionSlider
          Layout.fillWidth: true

          from: 0
          to: 0

          enabled: audioRecorder.hasRecordedClip
          opacity: enabled ? 1 : 0.25

          onMoved: {
            player.seek(value * 1000);
          }
        }

        Label {
          id: durationLabel
          Layout.preferredWidth: durationLabelMetrics.boundingRect('00:00:00').width
          Layout.rightMargin: 14

          color: player.playbackState == MediaPlayer.PlayingState ? QfTheme.mainTextColor : QfTheme.mainTextDisabledColor
          font: QfTheme.tipFont
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter

          text: {
            if (!preRecording && recorder.duration > 0) {
              var seconds = Math.ceil(recorder.duration / 1000);
              var hours = Math.floor(seconds / 60 / 60) + '';
              seconds -= hours * 60 * 60;
              var minutes = Math.floor(seconds / 60) + '';
              seconds = (seconds - minutes * 60) + '';
              return hours.padStart(2, '0') + ':' + minutes.padStart(2, '0') + ':' + seconds.padStart(2, '0');
            } else {
              return '-';
            }
          }
        }

        FontMetrics {
          id: durationLabelMetrics
          font: durationLabel.font
        }

      }
    }
  }
}
