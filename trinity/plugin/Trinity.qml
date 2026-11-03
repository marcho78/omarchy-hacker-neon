import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Trinity on screen: a holographic orb that appears while you talk to her, with
// what you said and what she answers, and a chat window when the orb is
// clicked. The voice, the session and the actions live in the Trinity service
// (trinity/service); this plugin follows it through `trinity watch`, which
// streams the service's events and passes commands back.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  // The node and service that run Trinity, as installed by
  // trinity/install-service.sh.
  readonly property string node: home + "/.local/share/mise/installs/node/latest/bin/node"
  readonly property string service: home + "/projects/o-interfaces/trinity/service/trinity.mjs"
  readonly property string settingsPath: home + "/.config/trinity/orb.json"

  // Shown or hidden, from the state o-widgets keeps (its keyboard
  // shortcuts, its menu, the tabs and Trinity all go through it). Hidden, the
  // widget leaves a tab at its edge; "clean" hides the tab too.
  readonly property string widgetsTool: root.home + "/.local/bin/o-widgets"
  property bool hidden: false
  property bool clean: false

  function widgets(args) {
    widgetsProcess.command = [root.widgetsTool].concat(args)
    widgetsProcess.running = true
  }

  Process {
    id: widgetsProcess
  }

  FileView {
    id: widgetState
    path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/o-interfaces/widgets.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var state = JSON.parse(text())
        root.hidden = !!(state.hidden && state.hidden.brief === true)
        root.videoHidden = !!(state.hidden && state.hidden.video === true)
        root.clean = state.clean === true
      } catch (e) {}
    }
    onLoadFailed: {
      root.hidden = false
      root.videoHidden = false
      root.clean = false
    }
  }

  // In case a watch ever loses the file.
  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: widgetState.reload()
  }

  // What the service reports.
  property bool serviceUp: false
  property string phase: "idle"
  property bool conversing: false
  property real level: 0
  property string mode: "voice"
  // Whether the service listens for "Hey Trinity".
  property bool wakeOn: true
  // The list on the desktop, {title, items: [{text, tag}], pinned, at}, or null.
  property var board: null
  // The video on the desktop, {id, title, channel, duration, at}, or null.
  property var video: null
  property bool videoHidden: false
  property string heard: ""
  property string reply: ""
  property string error: ""

  // The chat: each message is {who: "you"|"trinity", text}; the reply being
  // spoken streams into `reply` and joins the list when it is done.
  property var messages: []
  property bool chatOpen: false
  // The service holds a voice conversation open while the chat is.
  onChatOpenChanged: command(chatOpen ? "chat open" : "chat closed")

  // Where the orb sits, as its distance from the screen's bottom-right corner,
  // and whether it floats in front of the windows or stays behind them.
  readonly property int defaultRight: 24
  readonly property int defaultBottom: 96
  property int offsetRight: defaultRight
  property int offsetBottom: defaultBottom
  property bool front: true

  // Shown while there is something going on, and for a few seconds after, so
  // she fades out rather than vanishing mid-word.
  readonly property bool active: chatOpen || conversing || phase !== "idle"
  property bool lingering: false
  readonly property bool shown: active || lingering
  onActiveChanged: if (!active) lingerTimer.restart()

  Timer {
    id: lingerTimer
    interval: 4000
    onRunningChanged: if (running) root.lingering = true
    onTriggered: root.lingering = false
  }

  function command(line) {
    watcher.write(line + "\n")
  }

  function addMessage(who, text) {
    if (!text) return
    var next = root.messages.slice(-60)
    next.push({ who: who, text: text })
    root.messages = next
  }

  function handle(line) {
    var event
    try {
      event = JSON.parse(line)
    } catch (e) {
      return
    }
    switch (event.type) {
    case "service":
      root.serviceUp = event.up
      if (!event.up) root.phase = "idle"
      break
    case "state":
      root.phase = event.state
      root.conversing = event.conversing
      if (event.state === "listening") {
        root.heard = ""
        root.error = ""
      }
      if (event.state === "thinking") root.reply = ""
      break
    case "you":
      root.heard = event.text
      root.addMessage("you", event.text)
      break
    case "reply.delta":
      root.reply += event.text
      break
    case "reply":
      root.reply = event.text
      root.addMessage("trinity", event.text)
      break
    case "level":
      root.level = event.value
      break
    case "mode":
      root.mode = event.mode
      break
    case "wake":
      root.wakeOn = event.on
      break
    case "board":
      root.board = event.board
      break
    case "video":
      root.video = event.video
      break
    case "videoControl":
      videoPlayer.control(event.command, event.seconds)
      break
    case "error":
      root.error = event.text
      break
    }
  }

  // A typed message, shown at once and sent to the service.
  function sendTyped(text) {
    var trimmed = String(text || "").trim()
    if (!trimmed) return
    root.heard = trimmed
    root.addMessage("you", trimmed)
    root.command("say " + trimmed.replace(/\n/g, " "))
  }

  function setMode(next) {
    root.command("mode " + next)
  }

  function setWake(on) {
    root.command("wake " + (on ? "on" : "off"))
  }

  function savePlacement() {
    settingsFile.setText(JSON.stringify({ right: root.offsetRight, bottom: root.offsetBottom, front: root.front }, null, 2) + "\n")
  }

  function resetPlacement() {
    root.offsetRight = root.defaultRight
    root.offsetBottom = root.defaultBottom
    root.savePlacement()
  }

  Process {
    id: watcher
    command: [root.node, root.service, "watch"]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: (data) => root.handle(data)
    }
    // Back up if it ever stops (the service restarting is handled inside it).
    onRunningChanged: if (!running) restartTimer.start()
  }

  Timer {
    id: restartTimer
    interval: 3000
    onTriggered: watcher.running = true
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    printErrors: false
    atomicWrites: true
    // A saved spot that would leave her off the screen (a smaller screen, a
    // bad value) is ignored, and she starts in the corner.
    onLoaded: {
      try {
        var saved = JSON.parse(text())
        var screen = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        var fits = function(value, size) { return typeof value === "number" && value >= 0 && (!screen || value <= size - 200) }
        if (fits(saved.right, screen ? screen.width : 0)) root.offsetRight = saved.right
        if (fits(saved.bottom, screen ? screen.height : 0)) root.offsetBottom = saved.bottom
        if (typeof saved.front === "boolean") root.front = saved.front
      } catch (e) {}
    }
  }

  // The theme's cyan, which the shell's palette leaves out, read from its
  // colors.toml and again on every theme switch.
  property color cyan: Color.accent

  FileView {
    id: themeColors
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: {
      var match = text().match(/^\s*cyan\s*=\s*"(#[0-9a-fA-F]{6})"/m)
      root.cyan = match ? match[1] : Color.accent
    }
  }

  Connections {
    target: Color
    function onAccentChanged() { themeColors.reload() }
  }

  Video {
    id: videoPlayer
    trinity: root
  }

  BoardWindow {
    trinity: root
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  OrbWindow {
    trinity: root
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }
}
