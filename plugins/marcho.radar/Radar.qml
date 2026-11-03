import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Agent Radar: the user's Herdr coding agents on the desktop, on the left under
// the bar and behind the windows. Every 2 seconds it reads Herdr's live
// snapshot (one quick `herdr api snapshot`) and shows each agent as a cell,
// grouped by workspace and lit by its status. Clicking one jumps to it.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  // Herdr comes through mise, whose shims the shell may not have on its PATH.
  readonly property string herdr: home + "/.local/share/mise/shims/herdr"

  // [{id, name, agents: [{pane, agent, status, task, folder}]}], in Herdr's
  // order; only workspaces with agents.
  property var workspaces: []
  property bool online: false

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
        root.hidden = !!(state.hidden && state.hidden.radar === true)
        root.clean = state.clean === true
      } catch (e) {}
    }
    onLoadFailed: {
      root.hidden = false
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

  // The theme's colors the shell's palette leaves out, read from its
  // colors.toml and again on every theme switch. The accent stands in.
  property color cyan: Color.accent
  property color yellow: Color.accent

  // Agents by how much they want attention: needing the user first.
  readonly property var urgent: {
    var rank = { blocked: 0, working: 1, done: 2 }
    var list = []
    for (var i = 0; i < root.workspaces.length; i++)
      for (var j = 0; j < root.workspaces[i].agents.length; j++) {
        var a = root.workspaces[i].agents[j]
        if (a.status in rank) list.push(Object.assign({ workspace: root.workspaces[i].name }, a))
      }
    return list.sort(function(p, q) { return rank[p.status] - rank[q.status] })
  }
  readonly property int total: workspaces.reduce(function(n, w) { return n + w.agents.length }, 0)
  readonly property int working: urgent.filter(function(a) { return a.status === "working" }).length

  function read(text) {
    var snap
    try {
      snap = JSON.parse(text).result.snapshot
    } catch (e) {
      root.online = false
      return
    }
    var byId = {}
    var list = (snap.workspaces || []).map(function(w) {
      var entry = { id: w.workspace_id, name: w.label, agents: [] }
      byId[w.workspace_id] = entry
      return entry
    })
    for (var i = 0; i < (snap.agents || []).length; i++) {
      var a = snap.agents[i]
      var w = byId[a.workspace_id]
      if (!w) continue
      w.agents.push({
        pane: a.pane_id,
        agent: a.agent,
        status: a.agent_status || "unknown",
        task: a.terminal_title_stripped || a.cwd || "",
        folder: String(a.cwd || "").replace(root.home, "~"),
      })
    }
    root.workspaces = list.filter(function(w) { return w.agents.length > 0 })
    root.online = true
  }

  function focusAgent(pane) {
    focusProcess.command = [Qt.resolvedUrl("focus.sh").toString().replace("file://", ""), pane]
    focusProcess.running = true
  }

  function themeColor(colors, name) {
    var match = String(colors || "").match(new RegExp("^\\s*" + name + "\\s*=\\s*\"(#[0-9a-fA-F]{6})\"", "m"))
    return match ? match[1] : Color.accent
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!snapshot.running) snapshot.running = true
  }

  Process {
    id: snapshot
    command: [root.herdr, "api", "snapshot"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.read(text)
    }
    onExited: (code) => { if (code !== 0) root.online = false }
  }

  Process {
    id: focusProcess
  }

  FileView {
    id: themeColors
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: {
      root.cyan = root.themeColor(text(), "cyan")
      root.yellow = root.themeColor(text(), "yellow")
    }
  }

  Connections {
    target: Color
    function onAccentChanged() { themeColors.reload() }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      RadarWindow {
        required property var modelData

        screen: modelData
        radar: root
      }
    }
  }
}
