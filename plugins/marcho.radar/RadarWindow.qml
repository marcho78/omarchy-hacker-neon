import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// One screen's Agent Radar, in the desktop's top-left corner: under the bar and
// behind the windows, on Hyprland's bottom layer, like the Neon HUD. A hex cell
// per agent, rows offset like a honeycomb, under each workspace's name; a scan
// line passes down it. The agents that want attention are listed below.
PanelWindow {
  id: window

  property var radar: null

  readonly property int gap: Math.round(14 * Style.fontScale)
  readonly property int pad: Math.round(12 * Style.fontScale)
  readonly property int cell: Math.round(46 * Style.fontScale)
  readonly property int perRow: 6
  readonly property int panelWidth: pad * 2 + cell * perRow + cell / 2
  readonly property color dim: Util.alpha(Commons.Color.menu.text, 0.45)
  readonly property color cyan: radar ? radar.cyan : Commons.Color.accent
  readonly property color yellow: radar ? radar.yellow : Commons.Color.accent
  // The agent under the mouse, whose task shows at the foot of the cells.
  property var hovered: null

  // Flush with the screen's edge, so a hidden radar's tab sits on it; the
  // panel keeps its gap inside.
  visible: !(radar && radar.clean)
  anchors.top: true
  anchors.left: true
  margins.top: gap
  margins.left: 0
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.namespace: "agent-radar"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  color: "transparent"
  implicitWidth: panel.width + gap
  implicitHeight: panel.height
  // Only the panel takes clicks while it shows, only the tab while hidden.
  mask: Region { item: window.radar && window.radar.hidden ? tab : panel }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function tone(status) {
    if (status === "working") return window.cyan
    if (status === "blocked") return window.yellow
    if (status === "done") return Commons.Color.accent
    return window.dim
  }

  function mark(status) {
    return { working: "◉", blocked: "⚠", done: "✓" }[status] || "○"
  }

  function word(status) {
    return strings.t({ working: "working", blocked: "needsYou", done: "done", idle: "idle" }[status] || "unknown")
  }

  Rectangle {
    id: panel
    // Hidden, it slides off to the left.
    x: window.radar && window.radar.hidden ? -width : window.gap
    opacity: window.radar && window.radar.hidden ? 0 : 1
    Behavior on x { NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
    Behavior on opacity { NumberAnimation { duration: 350 } }
    width: window.panelWidth
    height: header.height + body.implicitHeight + window.pad * 2 + 2
    color: Util.alpha(Commons.Color.background, 0.62)
    border.width: 1
    border.color: Util.alpha(Commons.Color.accent, 0.26)
    clip: true

    Rectangle {
      id: header
      x: 1
      y: 1
      width: parent.width - 2
      height: Math.round(30 * Style.fontScale)
      color: Util.alpha(Commons.Color.accent, 0.07)

      Label {
        anchors.left: parent.left
        anchors.leftMargin: window.pad
        anchors.verticalCenter: parent.verticalCenter
        text: "// " + strings.t("title")
        color: Commons.Color.accent
        font.letterSpacing: Math.round(2 * Style.fontScale)
      }

      Label {
        id: hideButton
        anchors.right: parent.right
        anchors.rightMargin: window.pad
        anchors.verticalCenter: parent.verticalCenter
        text: "[ HIDE ]"
        color: hideMouse.containsMouse ? Commons.Color.accent : window.dim
        font.pixelSize: Style.font.caption

        MouseArea {
          id: hideMouse
          anchors.fill: parent
          anchors.margins: -4
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: window.radar.widgets(["hide", "radar"])
        }
      }

      Label {
        anchors.right: hideButton.left
        anchors.rightMargin: Math.round(10 * Style.fontScale)
        anchors.verticalCenter: parent.verticalCenter
        text: window.radar && window.radar.online
          ? window.radar.total + " · " + window.radar.working + " " + strings.t("active")
          : strings.t("offline")
        color: window.radar && window.radar.online ? window.dim : window.yellow
        font.pixelSize: Style.font.caption
        font.letterSpacing: Math.round(1 * Style.fontScale)
      }

      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Util.alpha(Commons.Color.accent, 0.24)
      }
    }

    Column {
      id: body
      x: window.pad
      y: header.y + header.height + window.pad
      width: parent.width - window.pad * 2
      spacing: Math.round(8 * Style.fontScale)

      Repeater {
        model: window.radar ? window.radar.workspaces : []

        delegate: Column {
          required property var modelData
          width: body.width
          spacing: Math.round(2 * Style.fontScale)

          Label {
            text: modelData.name.toUpperCase()
            color: Util.alpha(Commons.Color.accent, 0.6)
            font.pixelSize: Style.font.caption
            font.letterSpacing: Math.round(2 * Style.fontScale)
          }

          // The honeycomb: every other row shifted half a cell.
          Item {
            width: body.width
            height: Math.ceil(modelData.agents.length / window.perRow) * window.cell * 0.82 + window.cell * 0.18

            Repeater {
              model: modelData.agents

              delegate: HexCell {
                required property var modelData
                required property int index
                readonly property int row: Math.floor(index / window.perRow)
                agent: modelData
                x: (index % window.perRow) * window.cell + (row % 2) * window.cell / 2
                y: row * window.cell * 0.82
              }
            }
          }
        }
      }

      // The task under the mouse, or a hint.
      Label {
        width: body.width
        elide: Text.ElideRight
        text: window.hovered ? "> " + window.hovered.task : strings.t("hint")
        color: window.hovered ? Commons.Color.menu.text : window.dim
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        visible: window.radar && window.radar.urgent.length > 0
        width: body.width
        height: 1
        color: Util.alpha(Commons.Color.accent, 0.24)
      }

      // What wants attention: needing the user first, then working, then done.
      Repeater {
        model: window.radar ? window.radar.urgent.slice(0, 6) : []

        delegate: Rectangle {
          required property var modelData
          width: body.width
          height: Math.round(22 * Style.fontScale)
          color: modelData.status === "blocked" ? Util.alpha(window.yellow, 0.08) : "transparent"

          Rectangle {
            visible: modelData.status === "blocked"
            width: 2
            height: parent.height
            color: window.yellow
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Math.round(8 * Style.fontScale)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(8 * Style.fontScale)

            Label {
              id: markLabel
              text: window.mark(modelData.status)
              color: window.tone(modelData.status)
            }

            Label {
              id: workspaceLabel
              width: Math.round(52 * Style.fontScale)
              elide: Text.ElideRight
              text: modelData.workspace
              color: window.dim
              font.pixelSize: Style.font.caption
            }

            // The task takes what the others leave.
            Label {
              width: parent.width - markLabel.width - workspaceLabel.width - statusLabel.implicitWidth - parent.spacing * 3
              elide: Text.ElideRight
              text: modelData.task
              color: Commons.Color.menu.text
              font.pixelSize: Style.font.caption
            }

            Label {
              id: statusLabel
              text: window.word(modelData.status)
              color: window.tone(modelData.status)
              font.pixelSize: Style.font.caption
              font.letterSpacing: Math.round(1 * Style.fontScale)
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: window.radar.focusAgent(modelData.pane)
          }
        }
      }
    }

    // The scan line, passing down every few seconds.
    Rectangle {
      id: scan
      width: parent.width
      height: Math.round(26 * Style.fontScale)
      gradient: Gradient {
        GradientStop { position: 0; color: Util.alpha(window.cyan, 0) }
        GradientStop { position: 0.92; color: Util.alpha(window.cyan, 0.16) }
        GradientStop { position: 1; color: Util.alpha(window.cyan, 0.6) }
      }

      NumberAnimation on y {
        from: -scan.height
        to: panel.height
        duration: 5000
        loops: Animation.Infinite
      }
    }
  }

  // What a hidden radar leaves on the screen's left edge.
  EdgeTab {
    id: tab
    x: 0
    y: Math.round(110 * Style.fontScale)
    label: "RADAR"
    opacity: window.radar && window.radar.hidden ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300 } }
    onActivated: window.radar.widgets(["show", "radar"])
  }

  // One agent: a hexagon outlined in its status color, its mark inside and
  // which agent it is under that. Working ones breathe; ones that need the
  // user blink.
  component HexCell: Item {
    id: hexCell

    property var agent: null
    readonly property string status: agent ? agent.status : "unknown"
    readonly property color toneColor: window.tone(status)
    readonly property bool quiet: status !== "working" && status !== "blocked" && status !== "done"

    width: window.cell
    height: window.cell

    Canvas {
      id: hex
      anchors.fill: parent
      property color stroke: hexCell.toneColor
      property bool hot: mouse.containsMouse
      onStrokeChanged: requestPaint()
      onHotChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var r = width / 2 - 2
        ctx.beginPath()
        for (var s = 0; s < 6; s++) {
          var a = Math.PI / 6 + s * Math.PI / 3
          var px = width / 2 + Math.cos(a) * r
          var py = height / 2 + Math.sin(a) * r
          if (s === 0) ctx.moveTo(px, py)
          else ctx.lineTo(px, py)
        }
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(stroke.r, stroke.g, stroke.b, hexCell.quiet ? (hot ? 0.14 : 0.05) : (hot ? 0.32 : 0.18))
        ctx.fill()
        ctx.lineWidth = hexCell.quiet ? 1.2 : 2.2
        ctx.strokeStyle = Qt.rgba(stroke.r, stroke.g, stroke.b, hexCell.quiet ? 0.45 : 0.95)
        ctx.stroke()
      }
    }

    Column {
      anchors.centerIn: parent
      spacing: -2

      Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: window.mark(hexCell.status)
        color: hexCell.toneColor
      }

      Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: hexCell.agent && hexCell.agent.agent === "codex" ? "CDX" : "CLD"
        color: Util.alpha(hexCell.toneColor, 0.75)
        font.pixelSize: Math.round(Style.font.caption * 0.8)
        font.letterSpacing: 1
      }
    }

    SequentialAnimation on opacity {
      running: hexCell.status === "working"
      loops: Animation.Infinite
      onRunningChanged: if (!running) hexCell.opacity = 1
      NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
    }

    SequentialAnimation on scale {
      running: hexCell.status === "blocked"
      loops: Animation.Infinite
      onRunningChanged: if (!running) hexCell.scale = 1
      NumberAnimation { to: 1.12; duration: 350 }
      NumberAnimation { to: 1; duration: 350 }
      PauseAnimation { duration: 500 }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: window.hovered = containsMouse ? hexCell.agent : (window.hovered === hexCell.agent ? null : window.hovered)
      onClicked: window.radar.focusAgent(hexCell.agent.pane)
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
