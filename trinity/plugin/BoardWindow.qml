import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// The desktop board: a list Trinity puts on the wallpaper (news, results, a
// to-do list), between the Agent Radar on the left and the HUD on the right,
// behind the windows. No frame: a header, a glowing rule, and the lines, each
// arriving as scrambled glyphs that resolve into its text, one after another.
// [ CLEAR ] takes it away; [ HIDE ] tucks it into a tab at the top, which
// brings it back.
PanelWindow {
  id: window

  property var trinity: null
  readonly property var board: trinity ? trinity.board : null

  readonly property color accent: Commons.Color.accent
  readonly property color cyan: trinity ? trinity.cyan : Commons.Color.accent
  readonly property color dim: Util.alpha(Commons.Color.menu.text, 0.45)
  readonly property int lineGap: Math.round(14 * Style.fontScale)

  // The decoding: `frame` counts ticks since the board arrived; each line
  // starts once the one before has settled. Per tick a line reveals one more
  // character, with SCRAMBLE scrambled glyphs running ahead of it.
  readonly property int scramble: 8
  readonly property int pause: 10
  property int frame: 0
  readonly property string glyphs: "アイウエオカキクケコｱｲｳｴｵ01<>/\\{}[]#$%&*+="

  readonly property bool hidden: trinity ? trinity.hidden : false
  visible: board !== null && !(trinity && trinity.clean)
  anchors.top: true
  anchors.left: true
  margins.top: Math.round(70 * Style.fontScale)
  margins.left: Math.round(380 * Style.fontScale)
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.namespace: "trinity-board"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  color: "transparent"
  implicitWidth: Math.round(760 * Style.fontScale)
  implicitHeight: Math.max(column.implicitHeight + 8, tab.height)
  // Only the buttons take clicks while it shows, only the tab while hidden.
  mask: Region {
    item: window.hidden ? tab : clearButton
    regions: window.hidden ? [] : [hideRegion]
  }

  Region {
    id: hideRegion
    item: hideButton
  }

  // A new list shows even if the last one was hidden (one already there when
  // the shell starts keeps its state).
  readonly property real started: Date.now()
  onBoardChanged: {
    frame = 0
    if (board && board.at > started && hidden) trinity.widgets(["show", "brief"])
  }

  Timer {
    interval: 22
    repeat: true
    running: window.board !== null && window.frame < window.finished()
    onTriggered: window.frame++
  }

  // The tick each line starts on, and the tick the last one settles.
  function startOf(index) {
    var t = 0
    for (var i = 0; i < index; i++) t += window.board.items[i].text.length + window.scramble + window.pause
    return t
  }

  function finished() {
    return window.board ? startOf(window.board.items.length) : 0
  }

  // A line as it stands at this tick, as rich text: the settled part, then the
  // scrambled glyphs in the accent.
  function decoded(index, text, tick) {
    var shown = Math.max(0, Math.min(text.length, tick - startOf(index) - window.scramble))
    var ahead = Math.max(0, Math.min(window.scramble, tick - startOf(index)))
    if (shown >= text.length) return escapeHtml(text)
    var noise = ""
    for (var i = shown; i < Math.min(text.length, shown + ahead); i++)
      noise += text[i] === " " ? " " : window.glyphs[Math.floor(Math.random() * window.glyphs.length)]
    return escapeHtml(text.slice(0, shown)) + "<font color='" + window.accent + "'>" + escapeHtml(noise) + "</font>"
  }

  function escapeHtml(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  function clock(at) {
    return Qt.formatTime(new Date(at), "HH:mm")
  }

  Column {
    id: column
    width: parent.width
    spacing: window.lineGap
    opacity: window.hidden ? 0 : 1
    y: window.hidden ? -Math.round(30 * Style.fontScale) : 0
    Behavior on opacity { NumberAnimation { duration: 350 } }
    Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.InOutCubic } }

    Row {
      spacing: Math.round(16 * Style.fontScale)

      Text {
        textFormat: Text.PlainText
        text: window.board
          ? "// TRINITY · " + window.board.title.toUpperCase() + " · " + window.clock(window.board.at) + " · " + window.board.items.length
            + (window.board.items.length === 1 ? " ITEM" : " ITEMS") + (window.board.pinned ? " · PINNED" : "")
          : ""
        color: window.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: Math.round(2 * Style.fontScale)
      }

      HeaderButton {
        id: clearButton
        label: "[ CLEAR ]"
        onActivated: window.trinity.command("board clear")
      }

      HeaderButton {
        id: hideButton
        label: "[ HIDE ]"
        onActivated: window.trinity.widgets(["hide", "brief"])
      }
    }

    // The glowing rule, fading out to the right.
    Rectangle {
      width: parent.width * 0.7
      height: 1
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: window.accent }
        GradientStop { position: 1; color: Util.alpha(window.accent, 0) }
      }
    }

    Repeater {
      model: window.board ? window.board.items : []

      delegate: Row {
        required property var modelData
        required property int index
        width: column.width
        spacing: Math.round(12 * Style.fontScale)
        visible: window.frame >= window.startOf(index)

        Text {
          id: tag
          width: Math.round(96 * Style.fontScale)
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: modelData.tag ? "[" + modelData.tag + "]" : ""
          color: window.cyan
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
          topPadding: 2
        }

        Text {
          width: parent.width - tag.width - parent.spacing
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: window.decoded(index, modelData.text, window.frame)
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          lineHeight: 1.2
          style: Text.Outline
          styleColor: Util.alpha(window.accent, 0.12)
        }
      }
    }
  }

  // What a hidden list leaves at the top.
  EdgeTab {
    id: tab
    x: Math.round((window.width - width) / 2)
    y: 0
    vertical: false
    label: "BRIEF"
    opacity: window.hidden ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300 } }
    onActivated: window.trinity.widgets(["show", "brief"])
  }

  component HeaderButton: Text {
    id: button
    property string label: ""
    signal activated()
    text: label
    textFormat: Text.PlainText
    color: buttonMouse.containsMouse ? window.cyan : Util.alpha(window.cyan, 0.6)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1

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
