import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Neon HUD: panels on the desktop, top right under the bar and behind the
// windows. They show live CPU, memory and network use, and the token use and
// limits of AI agents, read from the usage records Omarchy's Agents feature
// keeps in its state folder.
Item {
  id: root

  // The agents shown, in this order, when Omarchy has a usage record for them.
  // Omarchy refreshes the records every 15 minutes by default, and every 3
  // when an agent is close to a limit.
  readonly property var agentIds: ["claude", "grok", "codex"]
  readonly property string home: Quickshell.env("HOME")
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"

  // CPU and memory in use, from 0 to 1, memory in bytes, and network speed in
  // bytes a second over every interface but loopback.
  property real cpu: 0
  property real memory: 0
  property real memoryUsed: 0
  property real memoryTotal: 0
  property real down: 0
  property real up: 0

  // The previous readings, which each sample is measured against.
  property real lastIdle: 0
  property real lastTotal: 0
  property real lastRx: -1
  property real lastTx: -1
  property real lastNetAt: 0

  // Each agent's usage record, by id, and Omarchy's default agent.
  property var records: ({})
  property string defaultAgent: ""

  // Shown or hidden, from the state o-widgets keeps (its keyboard
  // shortcuts, its menu, the tabs and Trinity all go through it). Hidden, the
  // widget leaves a tab at its edge; "clean" hides the tab too.
  readonly property string widgetsTool: root.home + "/.local/bin/o-widgets"
  // The two panels hide on their own: SYSTEM, and AI USAGE.
  property bool systemHidden: false
  property bool usageHidden: false
  readonly property bool hidden: systemHidden && usageHidden
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
        root.systemHidden = !!(state.hidden && state.hidden.system === true)
        root.usageHidden = !!(state.hidden && state.hidden.usage === true)
        root.clean = state.clean === true
      } catch (e) {}
    }
    onLoadFailed: {
      root.systemHidden = false
      root.usageHidden = false
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
  property color red: Color.accent

  // The agents that have a record, in order, for the panel to list.
  readonly property var shownAgents: {
    var list = []
    for (var i = 0; i < root.agentIds.length; i++) {
      var record = root.records[root.agentIds[i]]
      if (record) list.push({ id: root.agentIds[i], record: record })
    }
    return list
  }

  // The first line of /proc/stat: time spent per state since boot. Use is the
  // share of the time since the last sample not spent idle or waiting on I/O.
  function readCpu(text) {
    var fields = String(text || "").split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number)
    if (fields.length < 5) return
    var idle = fields[3] + fields[4]
    var total = fields.reduce(function(sum, value) { return sum + (value || 0) }, 0)
    if (root.lastTotal > 0 && total > root.lastTotal)
      root.cpu = Math.max(0, Math.min(1, 1 - (idle - root.lastIdle) / (total - root.lastTotal)))
    root.lastIdle = idle
    root.lastTotal = total
  }

  function meminfoField(text, name) {
    var match = String(text || "").match(new RegExp("^" + name + ":\\s+(\\d+)", "m"))
    return match ? Number(match[1]) * 1024 : 0
  }

  // Memory in use is what is not available, as free and top count it.
  function readMemory(text) {
    var total = root.meminfoField(text, "MemTotal")
    var available = root.meminfoField(text, "MemAvailable")
    if (total <= 0) return
    root.memoryTotal = total
    root.memoryUsed = total - available
    root.memory = (total - available) / total
  }

  // /proc/net/dev lists bytes received and sent per interface since boot,
  // after two header lines.
  function readNetwork(text) {
    var rx = 0
    var tx = 0
    var lines = String(text || "").split("\n").slice(2)
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].replace(":", " ").trim().split(/\s+/)
      if (parts.length < 10 || parts[0] === "lo") continue
      rx += Number(parts[1]) || 0
      tx += Number(parts[9]) || 0
    }
    var now = Date.now()
    if (root.lastRx >= 0 && now > root.lastNetAt) {
      var seconds = (now - root.lastNetAt) / 1000
      root.down = Math.max(0, (rx - root.lastRx) / seconds)
      root.up = Math.max(0, (tx - root.lastTx) / seconds)
    }
    root.lastRx = rx
    root.lastTx = tx
    root.lastNetAt = now
  }

  function setRecord(id, text) {
    var record = null
    if (text) {
      try {
        record = JSON.parse(text)
      } catch (e) {
        console.warn("Neon HUD: ignoring bad usage record for", id, e)
      }
    }
    var next = Object.assign({}, root.records)
    if (record && typeof record === "object") next[id] = record
    else delete next[id]
    root.records = next
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
    onTriggered: {
      statFile.reload()
      memoryFile.reload()
      networkFile.reload()
    }
  }

  FileView {
    id: statFile
    path: "/proc/stat"
    printErrors: false
    onLoaded: root.readCpu(text())
  }

  FileView {
    id: memoryFile
    path: "/proc/meminfo"
    printErrors: false
    onLoaded: root.readMemory(text())
  }

  FileView {
    id: networkFile
    path: "/proc/net/dev"
    printErrors: false
    onLoaded: root.readNetwork(text())
  }

  Instantiator {
    id: recordFiles
    model: root.agentIds

    delegate: FileView {
      required property var modelData

      path: root.usageDir + "/" + modelData + ".json"
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoaded: root.setRecord(modelData, text())
      onLoadFailed: root.setRecord(modelData, "")
    }
  }

  // Trinity's own use of the xAI API (voice, text, searches), which her service
  // adds up per day. apiUsage has today's and the last 7 days' totals, and
  // each of those days for the bars; it is null until Trinity has been used.
  property var apiUsage: null

  function readApiUsage(text) {
    var days
    try {
      days = JSON.parse(text).days || {}
    } catch (e) {
      root.apiUsage = null
      return
    }
    var sum = function(list, key) {
      return list.reduce(function(total, day) { return total + (Number(day[key]) || 0) }, 0)
    }
    var week = []
    for (var i = 6; i >= 0; i--) {
      var d = new Date()
      d.setDate(d.getDate() - i)
      var key = Qt.formatDate(d, "yyyy-MM-dd")
      week.push(Object.assign({ date: key }, days[key] || {}))
    }
    var today = [week[6]]
    var totals = function(list) {
      return {
        voiceSeconds: sum(list, "voiceSeconds"),
        textTokens: sum(list, "textTokensIn") + sum(list, "textTokensOut"),
        webSearches: sum(list, "webSearches"),
        xSearches: sum(list, "xSearches"),
        textInputs: sum(list, "textInputs"),
      }
    }
    root.apiUsage = {
      today: totals(today),
      week: totals(week),
      // Shaped like the agents' recent days, for the same bars.
      days: week.map(function(day) { return { date: day.date, messageCount: Number(day.voiceSeconds) || 0 } }),
    }
  }

  FileView {
    id: apiUsageFile
    path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/trinity/usage.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readApiUsage(text())
    onLoadFailed: root.apiUsage = null
  }

  // The usage update replaces each record with an atomic move. Should a watch
  // lose its file, this picks the change up within a minute, and reads the
  // default agent again.
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      for (var i = 0; i < recordFiles.count; i++) {
        var file = recordFiles.objectAt(i)
        if (file) file.reload()
      }
      apiUsageFile.reload()
      if (!defaultAgentProcess.running) defaultAgentProcess.running = true
    }
  }

  Process {
    id: defaultAgentProcess
    command: ["omarchy-default-agent"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.defaultAgent = text.trim()
    }
  }

  FileView {
    id: themeColors
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: {
      var colors = text()
      root.cyan = root.themeColor(colors, "cyan")
      root.yellow = root.themeColor(colors, "yellow")
      root.red = root.themeColor(colors, "red")
    }
    onLoadFailed: {
      root.cyan = Color.accent
      root.yellow = Color.accent
      root.red = Color.accent
    }
  }

  Connections {
    target: Color
    function onAccentChanged() { themeColors.reload() }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      HudWindow {
        required property var modelData

        screen: modelData
        hud: root
      }
    }
  }
}
