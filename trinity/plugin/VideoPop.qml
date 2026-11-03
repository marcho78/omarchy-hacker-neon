import QtQuick
import QtMultimedia
import Quickshell
import qs.Commons

// The video popped out: a normal window you can move and resize, in front of
// the apps on every workspace. Omarchy's apps/pip.lua does that for a window
// titled Picture-in-Picture: it floats, pins, starts at 600x338 in the top
// right and keeps 16:9, and floating workspaces leave it be. Hyprland matches
// the whole title, so it must be exactly that, as Firefox's is. The bar shows over the bottom while
// the mouse is on it. A click pauses, a double click goes full screen; closing
// the window (Super+W) puts the video back on the desktop.
FloatingWindow {
  id: window

  property var video: null
  readonly property alias output: picture
  readonly property bool wanted: !!video && !!video.current && video.mode === "window"

  title: "Picture-in-Picture"
  visible: wanted
  color: "black"
  implicitWidth: 600
  implicitHeight: 338

  // Closed by the compositor while wanted: back onto the desktop, and the
  // binding restored so it can pop out again.
  onVisibleChanged: if (!visible && video && video.mode === "window") {
    video.mode = "panel"
    visible = Qt.binding(function() { return window.wanted })
  }
  onWantedChanged: if (wanted) Qt.callLater(function() { keys.forceActiveFocus() })

  VideoOutput {
    id: picture
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectFit
  }

  // Whether the mouse is anywhere on the window, buttons included.
  HoverHandler {
    id: inside
  }

  MouseArea {
    anchors.fill: parent
    onClicked: clickTimer.restart()
    onDoubleClicked: {
      clickTimer.stop()
      window.video.mode = "full"
    }
  }

  Timer {
    id: clickTimer
    interval: 250
    onTriggered: window.video.control("toggle")
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: bar.height + Math.round(40 * Style.fontScale)
    opacity: inside.hovered ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 250 } }
    gradient: Gradient {
      GradientStop { position: 0; color: "transparent" }
      GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.85) }
    }
  }

  VideoBar {
    id: bar
    video: window.video
    compact: true
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Math.round(12 * Style.fontScale)
    opacity: inside.hovered ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 250 } }
  }

  Item {
    id: keys
    focus: true
    Keys.onEscapePressed: window.video.mode = "panel"
    Keys.onSpacePressed: window.video.control("toggle")
    Keys.onLeftPressed: window.video.control("back", 10)
    Keys.onRightPressed: window.video.control("forward", 10)
  }
}
