import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// The video on the desktop: a 16:9 picture between the Agent Radar and the
// HUD, behind the windows, with a glowing green edge and its bar underneath.
// A click pauses, a double click goes full screen. Hidden, it leaves a tab at
// the bottom edge.
PanelWindow {
  id: window

  property var video: null
  readonly property alias output: picture
  readonly property bool hidden: !!video && !!video.trinity && video.trinity.videoHidden
  readonly property int videoWidth: Math.round(810 * Style.fontScale)
  readonly property int videoHeight: Math.round(videoWidth * 9 / 16)

  visible: !!video && !!video.current && video.mode === "panel" && !video.trinity.clean
  // Top and bottom only: centred across the screen, from under the bar down.
  anchors.top: true
  anchors.bottom: true
  margins.top: Math.round(14 * Style.fontScale)
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.namespace: "trinity-video"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  color: "transparent"
  implicitWidth: videoWidth + Math.round(24 * Style.fontScale)
  mask: Region { item: window.hidden ? tab : content }

  Item {
    id: content
    width: window.videoWidth
    height: frame.height + bar.anchors.topMargin + bar.height
    x: Math.round((window.width - width) / 2)
    y: Math.round(70 * Style.fontScale)
    opacity: window.hidden ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 350 } }

    // The glow round the edge: two faint bands outside it.
    Rectangle {
      anchors.fill: frame
      anchors.margins: -6
      color: "transparent"
      border.width: 4
      border.color: Util.alpha(Commons.Color.accent, 0.08)
    }

    Rectangle {
      anchors.fill: frame
      anchors.margins: -2
      color: "transparent"
      border.width: 2
      border.color: Util.alpha(Commons.Color.accent, 0.25)
    }

    Rectangle {
      id: frame
      width: parent.width
      height: window.videoHeight
      color: "black"
      border.width: 1
      border.color: Util.alpha(Commons.Color.accent, 0.9)

      VideoOutput {
        id: picture
        anchors.fill: parent
        anchors.margins: 1
        fillMode: VideoOutput.PreserveAspectFit
      }

      Text {
        anchors.centerIn: parent
        width: parent.width - Math.round(60 * Style.fontScale)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: !!window.video && (window.video.loading || !!window.video.problem)
        textFormat: Text.PlainText
        text: window.video ? (window.video.problem || "◌ LOADING") : ""
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.letterSpacing: 2
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: clickTimer.restart()
        onDoubleClicked: {
          clickTimer.stop()
          window.video.mode = "full"
        }
      }

      // A single click waits a moment, in case it becomes a double click.
      Timer {
        id: clickTimer
        interval: 250
        onTriggered: window.video.control("toggle")
      }
    }

    VideoBar {
      id: bar
      video: window.video
      width: parent.width
      anchors.top: frame.bottom
      anchors.topMargin: Math.round(16 * Style.fontScale)
    }
  }

  // What a hidden video leaves at the bottom edge.
  EdgeTab {
    id: tab
    x: Math.round((window.width - width) / 2)
    y: window.height - height
    vertical: false
    label: "▲ VIDEO"
    opacity: window.hidden ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300 } }
    onActivated: window.video.trinity.widgets(["show", "video"])
  }
}
