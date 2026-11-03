import QtQuick
import qs.Commons
import qs.Commons as Commons

// The video's title, time and progress, and its buttons: under the panel, or
// over the bottom of the full screen and the pop-out window. A click on the
// progress line jumps there. compact: short buttons, for the small window.
Column {
  id: bar

  property var video: null
  property bool compact: false
  readonly property var current: video ? video.current : null
  readonly property string mode: video ? video.mode : "panel"
  readonly property color accent: Commons.Color.accent
  readonly property color cyan: video && video.trinity ? video.trinity.cyan : Commons.Color.accent
  readonly property color dim: Util.alpha(Commons.Color.menu.text, 0.6)
  // The mouse is on the bar, so it shouldn't fade away.
  readonly property alias hovered: barHover.hovered

  spacing: Math.round(8 * Style.fontScale)

  HoverHandler {
    id: barHover
  }

  Item {
    width: parent.width
    height: title.implicitHeight

    Text {
      id: tag
      visible: !bar.compact
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "[YOUTUBE]"
      color: bar.cyan
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }

    Text {
      id: title
      anchors.left: tag.visible ? tag.right : parent.left
      anchors.leftMargin: tag.visible ? Math.round(10 * Style.fontScale) : 0
      anchors.right: status.left
      anchors.rightMargin: Math.round(16 * Style.fontScale)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: bar.current ? bar.current.title + (bar.current.channel ? " · " + bar.current.channel : "") : ""
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: bar.compact ? Style.font.caption : Style.font.body
      style: Text.Outline
      styleColor: Qt.rgba(0, 0, 0, 0.6)
    }

    Text {
      id: status
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: !bar.video ? "" : (bar.video.problem ? "! CAN'T PLAY" : bar.video.loading ? "◌ LOADING" : bar.video.playing ? "▶ PLAYING" : "❚❚ PAUSED")
        + "  " + bar.video.clock(bar.video.position) + (bar.video.length > 0 ? " / " + bar.video.clock(bar.video.length) : "")
      color: bar.video && bar.video.problem ? bar.accent : bar.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }
  }

  // The progress line, glowing cyan to green.
  Item {
    width: parent.width
    height: Math.round(10 * Style.fontScale)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: 2
      color: Util.alpha(bar.accent, 0.18)
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: bar.video && bar.video.length > 0 ? parent.width * Math.min(1, bar.video.position / bar.video.length) : 0
      height: 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: bar.cyan }
        GradientStop { position: 1; color: bar.accent }
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: (mouse) => bar.video.seekTo(mouse.x / width)
    }
  }

  Row {
    spacing: Math.round((bar.compact ? 12 : 18) * Style.fontScale)

    TextButton {
      label: bar.video && bar.video.playing ? (bar.compact ? "[ ❚❚ ]" : "[ ❚❚ PAUSE ]") : (bar.compact ? "[ ▶ ]" : "[ ▶ PLAY ]")
      onActivated: bar.video.control("toggle")
    }

    TextButton {
      label: bar.mode === "full" ? (bar.compact ? "[ ⤡ ]" : "[ ⤡ EXIT FULL SCREEN ]") : (bar.compact ? "[ ⤢ ]" : "[ ⤢ FULL SCREEN ]")
      onActivated: bar.video.mode = bar.mode === "full" ? "panel" : "full"
    }

    TextButton {
      label: bar.mode === "window" ? (bar.compact ? "[ ↙ ]" : "[ ↙ BACK TO DESKTOP ]") : (bar.compact ? "[ ⧉ ]" : "[ ⧉ POP OUT ]")
      onActivated: bar.video.mode = bar.mode === "window" ? "panel" : "window"
    }

    TextButton {
      label: bar.compact ? "[ ■ ]" : "[ ■ STOP ]"
      onActivated: bar.video.stop()
    }

    TextButton {
      visible: bar.mode === "panel"
      label: "[ HIDE ]"
      onActivated: bar.video.trinity.widgets(["hide", "video"])
    }
  }

  component TextButton: Text {
    id: button
    property string label: ""
    signal activated()
    text: label
    textFormat: Text.PlainText
    color: buttonMouse.containsMouse ? bar.accent : bar.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
    style: Text.Outline
    styleColor: Qt.rgba(0, 0, 0, 0.6)

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      anchors.margins: -4
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.activated()
    }
  }
}
