import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Trinity's window: a HUD card in the screen's bottom-right corner (or where
// the user dragged it) with the orb, what she is doing, what was said, and a
// chat panel beside it when the orb is clicked. It floats above the windows,
// or stays behind them on the desktop if the user chose that. Only the card
// and the chat take clicks; the rest of the surface lets them through.
PanelWindow {
  id: window

  property var trinity: null

  readonly property int gap: Math.round(14 * Style.fontScale)
  readonly property int pad: Math.round(12 * Style.fontScale)
  readonly property int cardWidth: Math.round(300 * Style.fontScale)
  readonly property int chatWidth: Math.round(340 * Style.fontScale)
  readonly property color accent: Commons.Color.accent
  readonly property color cyan: trinity ? trinity.cyan : Commons.Color.accent
  readonly property color dim: Util.alpha(Commons.Color.menu.text, 0.45)
  readonly property bool chatOpen: !!trinity && trinity.chatOpen

  anchors.bottom: true
  anchors.right: true
  margins.bottom: trinity ? trinity.offsetBottom : 96
  margins.right: trinity ? trinity.offsetRight : 24
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: trinity && !trinity.front ? WlrLayer.Bottom : WlrLayer.Top
  WlrLayershell.namespace: "trinity"
  WlrLayershell.keyboardFocus: chatOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  color: "transparent"
  visible: !!trinity && trinity.shown
  implicitWidth: cardWidth + (chatOpen ? chatWidth + gap : 0)
  implicitHeight: Math.max(card.height, chatOpen ? chat.height : 0)
  // Clicks land on the orb, and on the chat while it is open; an empty region
  // standing in for a closed chat would empty the whole mask.
  mask: Region {
    item: dragArea
    regions: window.chatOpen ? [chatRegion] : []
  }

  property Region chatRegion: Region {
    item: chat
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // The chat, to the left of the card so it opens away from the corner.
  Rectangle {
    id: chat
    visible: window.chatOpen
    x: 0
    anchors.bottom: parent.bottom
    width: window.chatWidth
    height: Math.round(420 * Style.fontScale)
    color: Util.alpha(Commons.Color.background, 0.82)
    border.width: 1
    border.color: Util.alpha(window.accent, 0.3)

    Header {
      id: chatHeader
      title: "// " + strings.t("title") + " · CHAT"

      // Voice + text, or text only, for replies to typed messages.
      Text {
        anchors.right: parent.right
        anchors.rightMargin: window.pad
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "[" + (window.trinity && window.trinity.mode === "text" ? strings.t("textReplies") : strings.t("voiceReplies")) + "]"
        color: window.cyan
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1

        MouseArea {
          anchors.fill: parent
          anchors.margins: -6
          cursorShape: Qt.PointingHandCursor
          onClicked: window.trinity.setMode(window.trinity.mode === "text" ? "voice" : "text")
        }
      }
    }

    ListView {
      id: history
      anchors.top: chatHeader.bottom
      anchors.bottom: wakeToggle.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: window.pad
      clip: true
      spacing: Math.round(8 * Style.fontScale)
      model: window.trinity ? window.trinity.messages : []
      onCountChanged: Qt.callLater(positionViewAtEnd)

      delegate: Column {
        required property var modelData
        width: ListView.view.width
        spacing: 2

        Text {
          textFormat: Text.PlainText
          text: modelData.who === "you" ? strings.t("you") : "trinity"
          color: modelData.who === "you" ? window.dim : window.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: modelData.text
          wrapMode: Text.Wrap
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }

    // Listening for "Hey Trinity", on or off.
    Text {
      id: wakeToggle
      anchors.left: parent.left
      anchors.leftMargin: window.pad
      anchors.bottom: input.top
      anchors.bottomMargin: Math.round(6 * Style.fontScale)
      textFormat: Text.PlainText
      text: "[" + (window.trinity && window.trinity.wakeOn ? strings.t("wakeOn") : strings.t("wakeOff")) + "]"
      color: window.trinity && window.trinity.wakeOn ? window.cyan : window.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1

      MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: window.trinity.setWake(!window.trinity.wakeOn)
      }
    }

    // The message box: Enter sends, Escape closes the chat.
    Rectangle {
      id: input
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: window.pad
      height: Math.round(36 * Style.fontScale)
      color: Util.alpha(Commons.Color.background, 0.6)
      border.width: 1
      border.color: field.activeFocus ? Util.alpha(window.cyan, 0.7) : Util.alpha(window.accent, 0.3)

      Text {
        id: prompt
        anchors.left: parent.left
        anchors.leftMargin: window.pad
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: ">"
        color: window.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      TextInput {
        id: field
        anchors.left: prompt.right
        anchors.leftMargin: Math.round(8 * Style.fontScale)
        anchors.right: parent.right
        anchors.rightMargin: window.pad
        anchors.verticalCenter: parent.verticalCenter
        color: Commons.Color.foreground
        selectionColor: Util.alpha(window.accent, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        clip: true
        function submit() {
          window.trinity.sendTyped(text)
          text = ""
        }
        Keys.onReturnPressed: submit()
        Keys.onEnterPressed: submit()
        Keys.onEscapePressed: window.trinity.chatOpen = false

        Text {
          visible: !field.text
          textFormat: Text.PlainText
          text: strings.t("typeMessage")
          color: window.dim
          font: field.font
        }
      }
    }
  }

  onChatOpenChanged: if (chatOpen) Qt.callLater(function() { field.forceActiveFocus() })

  // The card: the orb, what she is doing, what was said.
  // No frame: the orb floats on its own, with what was said as captions under
  // it.
  Item {
    id: card
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: window.cardWidth
    height: cardColumn.height
    opacity: window.trinity && window.trinity.active ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 600 } }

    Column {
      id: cardColumn
      width: parent.width

      Item {
        width: parent.width
        height: Math.round(210 * Style.fontScale)

        Orb {
          id: orb
          anchors.centerIn: parent
          width: Math.round(210 * Style.fontScale)
          height: width
          phase: window.trinity ? window.trinity.phase : "idle"
          level: window.trinity ? window.trinity.level : 0
          tint: window.accent
          listenTint: window.cyan
          running: window.visible
        }

        // Click: open or close the chat. Drag: move Trinity; she remembers
        // where, and snaps to an edge or corner dropped near one.
        // Double-click: back to the corner.
        //
        // Positions inside this window can't be trusted mid-drag: the window
        // moves under the pointer, and events still arrive measured from where
        // it was. So the drag follows the pointer's place on the screen, read
        // from Hyprland, and sets the window's position from where it began.
        MouseArea {
          id: dragArea
          anchors.centerIn: orb
          width: orb.width * 0.75
          height: width
          cursorShape: moved ? Qt.ClosedHandCursor : Qt.PointingHandCursor
          property point pressAt
          property bool moved: false
          property bool released: false
          property point startCursor: Qt.point(-1, -1)
          property int startRight
          property int startBottom

          onPressed: (event) => {
            pressAt = Qt.point(event.x, event.y)
            moved = false
            released = false
            startCursor = Qt.point(-1, -1)
            startRight = window.trinity.offsetRight
            startBottom = window.trinity.offsetBottom
            cursor.ask()
          }
          onPositionChanged: (event) => {
            if (!moved && Math.hypot(event.x - pressAt.x, event.y - pressAt.y) < 6) return
            moved = true
            cursor.ask()
          }
          onReleased: {
            released = true
            if (moved) cursor.ask()
          }
          onClicked: if (!moved) window.trinity.chatOpen = !window.trinity.chatOpen
          onDoubleClicked: {
            window.trinity.chatOpen = false
            window.trinity.resetPlacement()
          }

          // Where the pointer is now, relative to where the drag began.
          function follow(x, y) {
            if (startCursor.x < 0) {
              startCursor = Qt.point(x, y)
              return
            }
            if (!moved) return
            var maxRight = Math.max(0, window.screen.width - window.width)
            var maxBottom = Math.max(0, window.screen.height - window.height)
            var right = Math.max(0, Math.min(maxRight, startRight - (x - startCursor.x)))
            var bottom = Math.max(0, Math.min(maxBottom, startBottom - (y - startCursor.y)))
            if (released) {
              // Dropped near an edge, she lines up with it.
              // At the bottom she keeps clear of the task bar, at the top of
              // the bar.
              var snap = Math.round(48 * Style.fontScale)
              var edge = window.trinity.defaultRight
              if (right < snap) right = edge
              else if (maxRight - right < snap) right = maxRight - edge
              if (bottom < window.trinity.defaultBottom + snap) bottom = window.trinity.defaultBottom
              else if (maxBottom - bottom < snap + 26) bottom = maxBottom - edge - 26
            }
            window.trinity.offsetRight = Math.round(right)
            window.trinity.offsetBottom = Math.round(bottom)
            if (released) window.trinity.savePlacement()
          }
        }

        // Asks Hyprland where the pointer is, one question at a time; a move
        // made while one is out is picked up by asking again when it returns.
        Process {
          id: cursor
          property bool again: false
          command: ["hyprctl", "cursorpos", "-j"]
          function ask() {
            if (running) again = true
            else running = true
          }
          stdout: StdioCollector {
            onStreamFinished: {
              try {
                var at = JSON.parse(text)
                dragArea.follow(at.x, at.y)
              } catch (e) {}
            }
          }
          onRunningChanged: if (!running && again) {
            again = false
            running = true
          }
        }
      }

      // Only when something is wrong; otherwise the orb's colour and face say
      // what she is doing.
      Caption {
        visible: !!window.trinity && !window.trinity.serviceUp
        text: strings.t("offline")
        color: "#ff3b6b"
        font.pixelSize: Style.font.caption
        font.letterSpacing: Math.round(3 * Style.fontScale)
      }

      // What was said: the user's words, then her reply as it streams in.
      // Only while the chat is open; talking by voice alone, it's just her.
      Column {
        x: window.pad
        width: parent.width - window.pad * 2
        spacing: 4
        bottomPadding: Math.round(6 * Style.fontScale)

        Caption {
          visible: window.chatOpen && text !== ""
          text: window.trinity && window.trinity.heard ? window.trinity.heard : ""
          color: window.dim
          maximumLineCount: 2
          font.pixelSize: Style.font.caption
        }

        Caption {
          visible: window.chatOpen && text !== ""
          text: window.trinity ? window.trinity.reply : ""
          color: Commons.Color.foreground
          maximumLineCount: 4
        }

        Caption {
          text: window.trinity ? window.trinity.error : ""
          color: "#ff3b6b"
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // Centred text with a dark outline, readable over any window or wallpaper.
  component Caption: Text {
    width: parent ? parent.width : 0
    visible: text !== ""
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    elide: Text.ElideRight
    style: Text.Outline
    styleColor: Util.alpha(Commons.Color.background, 0.9)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // A strip reading // TITLE, with room on the right for a control.
  component Header: Rectangle {
    property string title: ""

    width: parent ? parent.width : 0
    height: Math.round(30 * Style.fontScale)
    color: Util.alpha(window.accent, 0.07)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: window.pad
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.title
      color: window.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.letterSpacing: Math.round(2 * Style.fontScale)
    }

    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: Util.alpha(window.accent, 0.24)
    }
  }
}
