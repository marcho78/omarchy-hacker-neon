import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// One screen's HUD, in the desktop's top-right corner: under the bar, clear of
// the space it reserves, and behind the windows, on Hyprland's bottom layer.
// It takes no input but its [ HIDE ] button, so clicks go on to the desktop;
// hidden, it slides off to the right and leaves a tab on the screen's edge.
PanelWindow {
  id: window

  property var hud: null

  readonly property int gap: Math.round(14 * Style.fontScale)
  readonly property int pad: Math.round(12 * Style.fontScale)
  readonly property int labelWidth: Math.round(38 * Style.fontScale)
  readonly property color dim: Util.alpha(Commons.Color.menu.text, 0.45)
  readonly property color cyan: hud ? hud.cyan : Commons.Color.accent

  visible: !(hud && hud.clean)
  anchors.top: true
  anchors.right: true
  margins.top: gap
  margins.right: 0
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.namespace: "neon-hud"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  color: "transparent"
  // Room on the right for the tabs, so a hidden panel's tab never covers the
  // one still showing.
  implicitWidth: panels.width + systemTab.width + Math.round(6 * Style.fontScale)
  // Tall enough for the tabs, even with both panels hidden.
  implicitHeight: Math.max(panels.height, usageTab.y + usageTab.height + Math.round(8 * Style.fontScale))
  // Only the [ HIDE ] buttons of the panels showing, and the tabs of the ones
  // hidden, take clicks.
  readonly property bool systemHidden: !!hud && hud.systemHidden
  readonly property bool usageHidden: !!hud && hud.usageHidden
  mask: Region {
    regions: [
      window.systemHidden ? systemTabRegion : systemHideRegion,
      window.usageHidden ? usageTabRegion : usageHideRegion,
    ]
  }

  Region { id: systemHideRegion; item: systemPanel.hideItem }
  Region { id: usageHideRegion; item: usagePanel.hideItem }
  Region { id: systemTabRegion; item: systemTab }
  Region { id: usageTabRegion; item: usageTab }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // A level's color: the accent, the theme's yellow from 75%, and its red from
  // 90%, where Omarchy's agents panel starts warning too.
  function levelColor(level) {
    if (!window.hud) return Commons.Color.accent
    if (level >= 0.9) return window.hud.red
    if (level >= 0.75) return window.hud.yellow
    return Commons.Color.accent
  }

  function percent(level) {
    return Commons.I18n.formatNumber(Math.round((Number(level) || 0) * 100)) + "%"
  }

  // Token counts the way Omarchy's agents panel writes them.
  // Voice time: seconds under a minute, minutes after.
  function minutes(seconds) {
    var s = Number(seconds) || 0
    if (s < 60) return Commons.I18n.formatNumber(Math.round(s)) + "s"
    return Commons.I18n.formatNumber(s / 60, 1) + " min"
  }

  // What the API use costs, by xAI's published prices, as an estimate.
  function cost(totals) {
    var dollars = (totals.voiceSeconds || 0) / 60 * 0.08 + (totals.textInputs || 0) * 0.004
    return "≈ $" + (dollars < 1 ? dollars.toFixed(3) : dollars.toFixed(2))
  }

  // Searches, with how many of them were on X.
  function searches(totals) {
    var all = (totals.webSearches || 0) + (totals.xSearches || 0)
    return Commons.I18n.formatNumber(all) + (totals.xSearches ? " (" + Commons.I18n.formatNumber(totals.xSearches) + " X)" : "")
  }

  function tokens(n) {
    n = Number(n) || 0
    if (n >= 1e9) return Commons.I18n.formatNumber(n / 1e9, 1) + "B"
    if (n >= 1e6) return Commons.I18n.formatNumber(n / 1e6, 1) + "M"
    if (n >= 1e3) return Commons.I18n.formatNumber(n / 1e3, 1) + "K"
    return Commons.I18n.formatNumber(n)
  }

  function speed(bytes) {
    if (bytes >= 1048576) return Commons.I18n.formatNumber(bytes / 1048576, 1) + "M/s"
    if (bytes >= 1024) return Commons.I18n.formatNumber(Math.round(bytes / 1024)) + "K/s"
    return Commons.I18n.formatNumber(Math.round(bytes)) + "B/s"
  }

  function gigabytes(bytes) {
    return Commons.I18n.formatNumber(bytes / 1073741824, 1) + "G"
  }

  // When a limit resets: the time if it is within a day, else the day too.
  function resetTime(iso) {
    var at = new Date(iso || "")
    if (isNaN(at.getTime())) return ""
    return Qt.formatDateTime(at, at.getTime() - Date.now() < 86400000 ? "HH:mm" : "ddd HH:mm")
  }

  // The last 7 days' tokens, which Omarchy records as each day's messageCount.
  function weekTokens(record) {
    var days = record && record.recentDays ? record.recentDays : []
    var sum = 0
    for (var i = 0; i < days.length; i++) sum += Number(days[i].messageCount) || 0
    return sum
  }

  Column {
    id: panels
    width: Math.round(332 * Style.fontScale)
    spacing: window.systemHidden || window.usageHidden ? 0 : window.gap

    HudPanel {
      id: systemPanel
      title: strings.t("system")
      live: true
      gone: window.systemHidden
      onHide: window.hud.widgets(["hide", "system"])

      Row {
        spacing: Math.round(10 * Style.fontScale)

        Label { text: strings.t("cpu"); width: window.labelWidth; color: window.dim }
        Meter { anchors.verticalCenter: parent.verticalCenter; level: window.hud ? window.hud.cpu : 0 }
        Label {
          text: window.percent(window.hud ? window.hud.cpu : 0)
          width: Math.round(42 * Style.fontScale)
          horizontalAlignment: Text.AlignRight
        }
      }

      Column {
        spacing: Math.round(3 * Style.fontScale)

        Row {
          spacing: Math.round(10 * Style.fontScale)

          Label { text: strings.t("memory"); width: window.labelWidth; color: window.dim }
          Meter { anchors.verticalCenter: parent.verticalCenter; level: window.hud ? window.hud.memory : 0 }
          Label {
            text: window.percent(window.hud ? window.hud.memory : 0)
            width: Math.round(42 * Style.fontScale)
            horizontalAlignment: Text.AlignRight
          }
        }

        Label {
          x: window.labelWidth + Math.round(10 * Style.fontScale)
          text: window.hud ? window.gigabytes(window.hud.memoryUsed) + " / " + window.gigabytes(window.hud.memoryTotal) : ""
          color: window.dim
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        spacing: Math.round(10 * Style.fontScale)

        Label { text: strings.t("network"); width: window.labelWidth; color: window.dim }
        Label { text: "▼ " + window.speed(window.hud ? window.hud.down : 0); color: window.cyan; width: Math.round(96 * Style.fontScale) }
        Label { text: "▲ " + window.speed(window.hud ? window.hud.up : 0) }
      }
    }

    HudPanel {
      id: usagePanel
      title: strings.t("aiUsage")
      visible: !!window.hud && (window.hud.shownAgents.length > 0 || !!window.hud.apiUsage)
      gone: window.usageHidden
      onHide: window.hud.widgets(["hide", "usage"])

      Repeater {
        model: window.hud ? window.hud.shownAgents : []

        delegate: Column {
          id: agent

          required property var modelData
          required property int index
          readonly property var record: modelData.record

          width: parent ? parent.width : 0
          spacing: Math.round(6 * Style.fontScale)

          DashedRule {
            visible: agent.index > 0
            width: agent.width
          }

          // The agent and its plan, and DEFAULT on Omarchy's default agent.
          Item {
            width: agent.width
            height: nameLabel.implicitHeight

            Label {
              id: nameLabel
              width: parent.width - (defaultTag.visible ? defaultTag.width + Math.round(8 * Style.fontScale) : 0)
              text: String(agent.record.name || agent.modelData.id).toUpperCase()
                + (agent.record.tierLabel ? " · " + String(agent.record.tierLabel).toUpperCase() : "")
              color: Commons.Color.accent
              font.letterSpacing: Math.round(1 * Style.fontScale)
              elide: Text.ElideRight
            }

            Rectangle {
              id: defaultTag
              visible: !!window.hud && agent.modelData.id === window.hud.defaultAgent
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: defaultText.implicitWidth + Math.round(10 * Style.fontScale)
              height: defaultText.implicitHeight + Math.round(2 * Style.fontScale)
              color: "transparent"
              border.width: 1
              border.color: window.cyan

              Label {
                id: defaultText
                anchors.centerIn: parent
                text: strings.t("default")
                color: window.cyan
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Tokens today and over the last 7 days, and a bar for each day.
          Item {
            width: agent.width
            height: Math.max(tokenRow.implicitHeight, days.height)

            Row {
              id: tokenRow
              anchors.verticalCenter: parent.verticalCenter
              spacing: Math.round(6 * Style.fontScale)

              Label { text: strings.t("today"); color: window.dim; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
              Label { text: window.tokens(agent.record.todayTotalTokens); width: Math.round(56 * Style.fontScale) }
              Label { text: strings.t("week"); color: window.dim; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
              Label { text: window.tokens(window.weekTokens(agent.record)) }
            }

            DayBars {
              id: days
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              days: agent.record.recentDays || []
            }
          }

          // Each limit: how much is used, and when it resets.
          Repeater {
            model: agent.record.limits || []

            delegate: Row {
              id: limit

              required property var modelData

              spacing: Math.round(8 * Style.fontScale)

              Label {
                width: Math.round(96 * Style.fontScale)
                text: String(limit.modelData.label || "").toUpperCase()
                color: window.dim
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }

              Meter {
                anchors.verticalCenter: parent.verticalCenter
                segments: 10
                level: Number(limit.modelData.percent) || 0
              }

              Label {
                width: Math.round(34 * Style.fontScale)
                text: window.percent(limit.modelData.percent)
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              Label {
                width: Math.round(56 * Style.fontScale)
                text: window.resetTime(limit.modelData.resetsAt)
                horizontalAlignment: Text.AlignRight
                color: window.dim
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }
      }

      // Trinity's own use of the xAI API: voice minutes, text tokens and
      // searches, today and over the last 7 days, with a bar of voice per day.
      Column {
        id: api

        readonly property var usage: window.hud ? window.hud.apiUsage : null

        visible: !!usage
        width: parent ? parent.width : 0
        spacing: Math.round(6 * Style.fontScale)

        DashedRule {
          visible: !!window.hud && window.hud.shownAgents.length > 0
          width: api.width
        }

        Item {
          width: api.width
          height: Math.max(apiName.implicitHeight, apiDays.height)

          Label {
            id: apiName
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("apiTitle")
            color: Commons.Color.accent
            font.letterSpacing: Math.round(1 * Style.fontScale)
          }

          DayBars {
            id: apiDays
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            days: api.usage ? api.usage.days : []
          }
        }

        ApiRow {
          label: strings.t("voice")
          today: api.usage ? window.minutes(api.usage.today.voiceSeconds) : ""
          week: api.usage ? window.minutes(api.usage.week.voiceSeconds) : ""
        }

        ApiRow {
          label: strings.t("text")
          today: api.usage ? window.tokens(api.usage.today.textTokens) : ""
          week: api.usage ? window.tokens(api.usage.week.textTokens) : ""
        }

        ApiRow {
          label: strings.t("search")
          today: api.usage ? window.searches(api.usage.today) : ""
          week: api.usage ? window.searches(api.usage.week) : ""
        }

        // An estimate from xAI's published prices: billable voice minutes at
        // $0.08, and $0.004 per text input. Searches aren't priced in: xAI
        // doesn't say whether its search fees apply in voice sessions.
        ApiRow {
          label: strings.t("cost")
          today: api.usage ? window.cost(api.usage.today) : ""
          week: api.usage ? window.cost(api.usage.week) : ""
        }
      }
    }
  }

  // One line of the API section: what, today, and the last 7 days.
  component ApiRow: Row {
    property string label: ""
    property string today: ""
    property string week: ""

    spacing: Math.round(6 * Style.fontScale)

    Label { width: Math.round(56 * Style.fontScale); text: parent.label; color: window.dim; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
    Label { text: strings.t("today"); color: window.dim; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
    Label { width: Math.round(96 * Style.fontScale); text: parent.today; elide: Text.ElideRight }
    Label { text: strings.t("week"); color: window.dim; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
    Label { text: parent.week }
  }

  // A panel: square, glassy, with a thin accent border and a header strip
  // reading // TITLE, over its rows.
  // What hidden panels leave on the screen's right edge: SYS, and AI under it.
  EdgeTab {
    id: systemTab
    x: window.width - width
    y: Math.round(110 * Style.fontScale)
    label: "SYS"
    downward: true
    opacity: window.systemHidden ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300 } }
    onActivated: window.hud.widgets(["show", "system"])
  }

  EdgeTab {
    id: usageTab
    x: window.width - width
    y: window.systemHidden ? systemTab.y + systemTab.height + Math.round(8 * Style.fontScale) : systemTab.y
    label: "AI"
    downward: true
    opacity: window.usageHidden ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300 } }
    onActivated: window.hud.widgets(["show", "usage"])
  }

  component HudPanel: Rectangle {
    id: hudPanel

    property string title: ""
    property bool live: false
    // Hidden: it slides off to the right and its space closes up.
    property bool gone: false
    readonly property alias hideItem: hideLabel
    signal hide()
    default property alias content: body.data

    width: parent ? parent.width : 0
    height: gone ? 0 : header.height + body.implicitHeight + window.pad * 2 + 2
    x: gone ? width + window.gap : 0
    opacity: gone ? 0 : 1
    clip: true
    Behavior on height { NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
    Behavior on x { NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
    Behavior on opacity { NumberAnimation { duration: 350 } }
    color: Util.alpha(Commons.Color.background, 0.62)
    border.width: 1
    border.color: Util.alpha(Commons.Color.accent, 0.26)

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
        text: "// " + hudPanel.title
        color: Commons.Color.accent
        font.letterSpacing: Math.round(2 * Style.fontScale)
      }

      Label {
        id: hideLabel
        anchors.right: liveMark.visible ? liveMark.left : parent.right
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
          onClicked: hudPanel.hide()
        }
      }

      // A live panel's mark: a small accent square and LIVE.
      Row {
        id: liveMark
        visible: hudPanel.live
        anchors.right: parent.right
        anchors.rightMargin: window.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(6 * Style.fontScale)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(6 * Style.fontScale)
          height: width
          color: Commons.Color.accent
        }

        Label {
          text: strings.t("live")
          color: window.dim
          font.pixelSize: Style.font.caption
          font.letterSpacing: Math.round(1 * Style.fontScale)
        }
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
      spacing: Math.round(9 * Style.fontScale)
    }
  }

  // A row of segments, lit up to a level from 0 to 1 in the level's color.
  component Meter: Row {
    id: meter

    property real level: 0
    property int segments: 20
    readonly property int lit: Math.round(Math.max(0, Math.min(1, level)) * segments)

    spacing: Math.max(1, Math.round(2 * Style.fontScale))

    Repeater {
      model: meter.segments

      delegate: Rectangle {
        required property int index

        width: Math.round(8 * Style.fontScale)
        height: Math.round(10 * Style.fontScale)
        color: index < meter.lit ? window.levelColor(meter.level) : Util.alpha(Commons.Color.accent, 0.14)
      }
    }
  }

  // A bar for each of the last 7 days, scaled to the busiest one; today's in cyan.
  component DayBars: Row {
    id: dayBars

    property var days: []
    readonly property real most: Math.max(1, Math.max.apply(null, days.map(function(day) { return Number(day.messageCount) || 0 })))

    height: Math.round(14 * Style.fontScale)
    spacing: Math.max(1, Math.round(2 * Style.fontScale))

    Repeater {
      model: dayBars.days

      delegate: Item {
        required property var modelData
        required property int index
        readonly property real value: Number(modelData.messageCount) || 0

        width: Math.round(6 * Style.fontScale)
        height: dayBars.height

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: parent.value > 0 ? Math.max(2, Math.round(parent.value / dayBars.most * parent.height)) : 1
          color: parent.index === dayBars.days.length - 1 ? window.cyan
            : parent.value > 0 ? Commons.Color.accent : Util.alpha(Commons.Color.accent, 0.3)
        }
      }
    }
  }

  // A dashed rule between agents.
  component DashedRule: Row {
    id: rule

    spacing: Math.round(4 * Style.fontScale)

    Repeater {
      model: Math.floor(rule.width / Math.round(8 * Style.fontScale))

      delegate: Rectangle {
        width: Math.round(4 * Style.fontScale)
        height: 1
        color: Util.alpha(Commons.Color.accent, 0.3)
      }
    }
  }

  // Text in the theme's monospace font.
  component Label: Text {
    textFormat: Text.PlainText
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
