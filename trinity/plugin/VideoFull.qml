import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The video full screen: over everything, bar included, on black. The bar
// shows while the mouse moves and fades after a few seconds. A click pauses;
// a double click, Esc or F goes back onto the desktop; Space pauses, the
// arrows skip ten seconds and change the volume.
PanelWindow {
  id: window

  property var video: null
  readonly property alias output: picture
  property bool awake: true

  visible: !!video && !!video.current && video.mode === "full"
  anchors.top: true
  anchors.bottom: true
  anchors.left: true
  anchors.right: true
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "trinity-video-full"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  color: "black"

  onVisibleChanged: if (visible) {
    awake = true
    sleep.restart()
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  VideoOutput {
    id: picture
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectFit
  }

  Timer {
    id: sleep
    interval: 2500
    onTriggered: bar.hovered ? restart() : window.awake = false
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: window.awake ? Qt.ArrowCursor : Qt.BlankCursor
    onPositionChanged: {
      window.awake = true
      sleep.restart()
    }
    onClicked: clickTimer.restart()
    onDoubleClicked: {
      clickTimer.stop()
      window.video.mode = "panel"
    }
  }

  Timer {
    id: clickTimer
    interval: 250
    onTriggered: window.video.control("toggle")
  }

  // A dark fade behind the bar, so it reads over a bright picture.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: bar.height + Math.round(100 * Style.fontScale)
    opacity: window.awake ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400 } }
    gradient: Gradient {
      GradientStop { position: 0; color: "transparent" }
      GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.8) }
    }
  }

  VideoBar {
    id: bar
    video: window.video
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Math.round(40 * Style.fontScale)
    opacity: window.awake ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400 } }
  }

  Item {
    id: keys
    focus: true
    Keys.onEscapePressed: window.video.mode = "panel"
    Keys.onSpacePressed: window.video.control("toggle")
    Keys.onLeftPressed: window.video.control("back", 10)
    Keys.onRightPressed: window.video.control("forward", 10)
    Keys.onUpPressed: window.video.control("louder")
    Keys.onDownPressed: window.video.control("quieter")
    Keys.onPressed: (event) => {
      if (event.key === Qt.Key_F) {
        window.video.mode = "panel"
        event.accepted = true
      }
    }
  }
}
