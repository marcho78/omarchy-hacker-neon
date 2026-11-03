import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Every app on one screen as HUD panels, over a blurred picture of it: the apps
// sorted by type into panels of numbered rows, laid out in columns. Type to
// narrow it, arrows to move, Enter to launch, scroll for more.
Item {
  id: root

  property var appLibrary: null
  property var dock: null

  property bool opened: false
  // While an app is dragged out toward the dock, the panels step aside so the
  // dock shows through, and the app's icon follows the pointer. The panels keep
  // the pointer for as long as the button is held, and tell the dock where it
  // is.
  property bool dragging: false
  property var dragEntry: null
  property point dragPoint
  // The app waiting on the user to confirm uninstalling it.
  property var uninstallEntry: null
  // The app whose menu is open, and where it opened.
  property var menuEntry: null
  property point menuPoint
  property string filterText: ""
  property int selectedIndex: 0
  // The panels, each with its apps and where they start in apps, and every
  // app in the order the panels show them.
  property var groups: []
  property var apps: []
  // The picture behind the panels is taken once per opening, while nothing of
  // them is drawn yet, so they never end up in their own background.
  property bool backdropReady: false

  readonly property int iconSize: Math.round(16 * Style.fontScale)
  readonly property int dragIconSize: Math.round(48 * Style.fontScale)
  readonly property int rowHeight: Math.round(28 * Style.fontScale)
  readonly property int rowPadding: Math.round(12 * Style.fontScale)
  readonly property int panelHeaderHeight: Math.round(30 * Style.fontScale)
  readonly property int panelGap: Math.round(20 * Style.fontScale)
  readonly property int columnGap: Math.round(22 * Style.fontScale)
  readonly property int minPanelWidth: Math.round(300 * Style.fontScale)
  readonly property int maxColumns: 4
  readonly property int promptHeight: Math.round(44 * Style.fontScale)
  readonly property int headerSpacing: Math.round(38 * Style.fontScale)
  readonly property int screenMargin: Style.space(40)
  readonly property int topMargin: Math.round(40 * Style.fontScale)
  readonly property int hintsHeight: Math.round(64 * Style.fontScale)
  readonly property color cyan: root.dock ? root.dock.cyan : Commons.Color.accent
  readonly property color dim: Util.alpha(Commons.Color.menu.text, 0.45)

  // As many columns as fit, up to maxColumns, centered on the screen.
  readonly property int contentWidth: Math.min(Math.round(1400 * Style.fontScale), panel.width - screenMargin * 2)
  readonly property int columns: Math.max(1, Math.min(maxColumns, Math.floor((contentWidth + columnGap) / (minPanelWidth + columnGap))))
  readonly property int panelWidth: Math.floor((contentWidth - columnGap * (columns - 1)) / columns)
  readonly property var layout: placePanels(groups, columns)

  // The panels, in the order they fill the columns.
  readonly property var groupOrder: ["web", "system", "office", "media", "other", "dev", "games"]

  // An app's panel: Omarchy's web apps are WEB, and the rest go by the
  // categories their launcher entry lists, the first rule that matches.
  function groupOf(entry) {
    if (String(entry.execString || "").indexOf("omarchy-launch-webapp") !== -1) return "web"
    var listed = entry.categories || []
    var categories = []
    for (var i = 0; i < listed.length; i++) categories.push(String(listed[i]))
    function has(names) {
      for (var j = 0; j < names.length; j++) {
        if (categories.indexOf(names[j]) !== -1) return true
      }
      return false
    }
    if (has(["Game"])) return "games"
    if (has(["Office", "Spreadsheet", "WordProcessor", "Presentation"])) return "office"
    if (has(["Development", "IDE", "TextEditor"])) return "dev"
    if (has(["AudioVideo", "Audio", "Video", "Player", "Graphics", "Photography", "2DGraphics", "RasterGraphics"])) return "media"
    if (has(["Network", "WebBrowser", "Email", "Chat", "InstantMessaging"])) return "web"
    if (has(["System", "Settings", "TerminalEmulator", "FileManager", "Utility", "Monitor"])) return "system"
    return "other"
  }

  // Lays the panels down the columns in order, like a newspaper: each column
  // takes panels until it would pass the shortest height that fits them all in
  // the columns there are. Returns each column's panels with their y, how tall
  // the tallest column is, and each app's column and y, which the arrow keys
  // and scrolling go by.
  function placePanels(groups, columns) {
    var heights = groups.map(function(group) {
      return root.panelHeaderHeight + group.entries.length * root.rowHeight
    })
    function fill(limit) {
      var filled = [[]]
      var used = 0
      for (var i = 0; i < heights.length; i++) {
        var current = filled[filled.length - 1]
        if (current.length > 0 && used + root.panelGap + heights[i] > limit) {
          filled.push([])
          used = 0
          current = filled[filled.length - 1]
        }
        used += (current.length > 0 ? root.panelGap : 0) + heights[i]
        current.push(i)
      }
      return filled
    }
    var limit = Math.max.apply(null, heights.concat([0]))
    var filled = fill(limit)
    while (filled.length > columns) {
      limit += root.rowHeight
      filled = fill(limit)
    }

    var placed = []
    var spots = []
    var tallest = 0
    for (var c = 0; c < filled.length; c++) {
      var y = 0
      var panels = []
      for (var p = 0; p < filled[c].length; p++) {
        var group = groups[filled[c][p]]
        if (p > 0) y += root.panelGap
        panels.push({ group: group, y: y })
        for (var r = 0; r < group.entries.length; r++)
          spots[group.start + r] = { column: c, y: y + root.panelHeaderHeight + r * root.rowHeight }
        y += heights[filled[c][p]]
      }
      placed.push(panels)
      tallest = Math.max(tallest, y)
    }
    return { columns: placed, spots: spots, height: tallest }
  }

  function open() {
    root.selectedIndex = 0
    if (root.appLibrary) root.appLibrary.refreshIcons()
    // The panels from last time are reused when nothing changed, so they open
    // with their icons already drawn.
    if (root.appsStale || root.filterText !== "" || root.apps.length === 0) {
      root.filterText = ""
      root.rebuild()
    } else {
      scroller.contentY = 0
    }
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (root.dragging && root.dock) root.dock.endExternalDrag()
    root.opened = false
    root.backdropReady = false
    root.uninstallEntry = null
    root.dragging = false
    root.dragEntry = null
    root.menuEntry = null
  }

  function dragTo(entry, point) {
    if (!root.dragging) {
      root.menuEntry = null
      root.dragEntry = entry
      root.dragging = true
    }
    root.dragPoint = point
    if (root.dock) root.dock.moveExternalDrag(panel.screen, point.x, point.y)
  }

  function dropDrag() {
    var entry = root.dragEntry
    if (entry && root.dock) root.dock.dropExternalDrag(panel.screen, root.dragPoint.x, root.dragPoint.y, String(entry.id || ""))
    root.close()
  }

  function requestUninstall(entry) {
    if (!entry) return
    root.menuEntry = null
    uninstallConfirm.selectedIndex = 1
    root.uninstallEntry = entry
  }

  function cancelUninstall() {
    root.uninstallEntry = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmUninstall() {
    var entry = root.uninstallEntry
    root.uninstallEntry = null
    root.close()
    if (entry && root.appLibrary) root.appLibrary.remove(entry.id, root.appLibrary.entryName(entry))
  }

  function openMenu(entry, point) {
    root.menuEntry = entry
    root.menuPoint = point
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function rebuild() {
    root.appsStale = false
    var rows = root.appLibrary ? root.appLibrary.sortedEntries(root.filterText) : []
    var byGroup = ({})
    for (var i = 0; i < rows.length; i++) {
      var key = root.groupOf(rows[i].entry)
      if (!byGroup[key]) byGroup[key] = []
      byGroup[key].push(rows[i].entry)
    }
    var groups = []
    var apps = []
    for (var g = 0; g < root.groupOrder.length; g++) {
      var entries = byGroup[root.groupOrder[g]]
      if (!entries) continue
      groups.push({ key: root.groupOrder[g], start: apps.length, entries: entries })
      apps = apps.concat(entries)
    }
    root.groups = groups
    root.apps = apps
    // While searching, the best match is the one Enter opens.
    var best = 0
    if (root.filterText && rows.length > 0) {
      for (var a = 0; a < apps.length; a++) {
        if (apps[a].id === rows[0].entry.id) { best = a; break }
      }
      root.selectedIndex = best
    } else {
      root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, apps.length - 1))
    }
    scroller.contentY = 0
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuild()
  }

  // Up and down go through the apps in order, panel by panel.
  function select(delta) {
    if (root.apps.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.apps.length - 1, root.selectedIndex + delta))
    root.reveal(root.selectedIndex)
  }

  // Left and right jump to the app nearest the same height in the next column.
  function selectColumn(delta) {
    var spots = root.layout.spots
    var here = spots[root.selectedIndex]
    if (!here) return
    var best = -1
    var bestDistance = Infinity
    for (var i = 0; i < spots.length; i++) {
      if (!spots[i] || spots[i].column !== here.column + delta) continue
      var distance = Math.abs(spots[i].y - here.y)
      if (distance < bestDistance) {
        best = i
        bestDistance = distance
      }
    }
    if (best < 0) return
    root.selectedIndex = best
    root.reveal(best)
  }

  // Scrolls just enough to show the app at index, and its panel's header when
  // it is the panel's first app.
  function reveal(index) {
    var spot = root.layout.spots[index]
    if (!spot) return
    var top = spot.y - root.panelHeaderHeight
    var bottom = spot.y + root.rowHeight
    if (top < scroller.contentY) scroller.contentY = Math.max(0, top)
    else if (bottom > scroller.contentY + scroller.height) scroller.contentY = bottom - scroller.height
  }

  function launch(index) {
    var entry = root.apps[index]
    if (!entry || !root.appLibrary) return
    root.close()
    if (root.dock) root.dock.launchEntry(entry)
    else root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // Apps installed or removed while the panels are closed are picked up when
  // they next open.
  property bool appsStale: false

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.opened) root.rebuild()
      else root.appsStale = true
    }
  }

  // If the screen can't be captured, the panels open over a plain dim rather
  // than waiting on a picture that never comes.
  Timer {
    interval: 400
    running: root.opened && !root.backdropReady
    onTriggered: root.backdropReady = true
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-dock-apps"

    // The screen as it was when the panels opened, blurred. Hidden while an
    // app is dragged out, so the dock shows through.
    Loader {
      anchors.fill: parent
      active: root.opened
      visible: !root.dragging

      sourceComponent: Item {
        ScreencopyView {
          id: shot
          anchors.fill: parent
          captureSource: panel.screen
          live: false
          onHasContentChanged: if (hasContent) root.backdropReady = true
        }

        MultiEffect {
          anchors.fill: parent
          source: shot
          visible: shot.hasContent
          blurEnabled: true
          blurMax: 64
          blur: 1.0
          saturation: 0.15
          autoPaddingEnabled: false
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Commons.Color.background, 0.5)
      opacity: root.dragging || !root.backdropReady ? 0 : 1

      Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    Item {
      id: card
      anchors.fill: parent
      opacity: root.dragging || !root.backdropReady ? 0 : 1

      Behavior on opacity { NumberAnimation { duration: 150 } }

      // A click on empty space closes an open menu, or else the panels.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
          if (root.menuEntry) root.menuEntry = null
          else root.close()
        }
      }

      ConfirmDialog {
        id: uninstallConfirm

        anchors.fill: parent
        opened: !!root.uninstallEntry
        z: 10
        message: Commons.I18n.t("common.uninstallConfirm").arg(root.uninstallEntry && root.appLibrary ? root.appLibrary.entryName(root.uninstallEntry) : "")
        confirmText: Commons.I18n.t("common.uninstall")
        background: Commons.Color.menu.background
        foreground: Commons.Color.menu.text
        scrim: Commons.Color.menu.scrim
        selectedBackground: Commons.Color.menu.selectedBackground
        selectedText: Commons.Color.menu.selectedText
        fontFamily: Style.font.menuFamily
        cornerRadius: Style.cornerRadius
        onCanceled: root.cancelUninstall()
        onConfirmed: root.confirmUninstall()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.uninstallEntry) {
            if (uninstallConfirm.handleKey(event)) event.accepted = true
            return
          }
          if (event.key === Qt.Key_Delete) {
            root.requestUninstall(root.apps[root.selectedIndex])
          } else if (event.key === Qt.Key_Escape) {
            if (root.menuEntry) root.menuEntry = null
            else if (root.filterText) root.setFilter("")
            else root.close()
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (Util.readingKey(event) === Qt.Key_Left) {
            root.selectColumn(-1)
          } else if (Util.readingKey(event) === Qt.Key_Right) {
            root.selectColumn(1)
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launch(root.selectedIndex)
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: root.topMargin
        anchors.bottomMargin: root.hintsHeight
        spacing: root.headerSpacing

        // The search line, as a terminal prompt: what was typed (or the
        // placeholder after a blinking block cursor), how many apps match, and
        // a dashed rule under it.
        Item {
          id: search
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.contentWidth
          height: root.promptHeight

          // Keeps clicks on the line from reaching the empty space behind it.
          MouseArea { anchors.fill: parent }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            Text {
              textFormat: Text.PlainText
              text: ">"
              color: Commons.Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              visible: !!root.filterText
              textFormat: Text.PlainText
              text: root.filterText
              color: Commons.Color.menu.text
              width: Math.min(implicitWidth, search.width - count.width - Style.font.heading * 6)
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.round(Style.font.heading * 0.55)
              height: Math.round(Style.font.heading * 1.15)
              color: Commons.Color.accent

              SequentialAnimation on opacity {
                running: root.opened
                loops: Animation.Infinite
                NumberAnimation { to: 0; duration: 0 }
                PauseAnimation { duration: 530 }
                NumberAnimation { to: 1; duration: 0 }
                PauseAnimation { duration: 530 }
              }
            }

            Text {
              visible: !root.filterText
              textFormat: Text.PlainText
              text: Commons.I18n.t("dock.searchApps")
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
            }
          }

          Text {
            id: count
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: strings.t("count.apps").arg(Commons.I18n.formatNumber(root.apps.length))
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Row {
            anchors.bottom: parent.bottom
            spacing: Math.round(4 * Style.fontScale)

            Repeater {
              model: Math.floor(search.width / Math.round(8 * Style.fontScale))

              Rectangle {
                width: Math.round(4 * Style.fontScale)
                height: 1
                color: Util.alpha(Commons.Color.accent, 0.35)
              }
            }
          }
        }

        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.contentWidth
          height: parent.height - root.promptHeight - parent.spacing

          Flickable {
            id: scroller
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: root.layout.height
            boundsBehavior: Flickable.StopAtBounds

            Repeater {
              model: root.layout.columns

              delegate: Item {
                id: column

                required property var modelData
                required property int index

                // Columns run in reading order, so right to left in a
                // right-to-left language.
                x: Commons.I18n.rightToLeft
                  ? root.contentWidth - (index + 1) * root.panelWidth - index * root.columnGap
                  : index * (root.panelWidth + root.columnGap)
                width: root.panelWidth
                height: root.layout.height

                Repeater {
                  model: column.modelData
                  delegate: AppPanel {}
                }
              }
            }
          }

          // More below: the last rows fade out, and a green bar shows how far
          // down the panels are scrolled.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.round(96 * Style.fontScale)
            visible: scroller.contentHeight > scroller.height && !scroller.atYEnd
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(Commons.Color.background, 0) }
              GradientStop { position: 1; color: Util.alpha(Commons.Color.background, 0.85) }
            }
          }

          Rectangle {
            id: track
            visible: scroller.contentHeight > scroller.height
            anchors.right: parent.right
            anchors.rightMargin: -Math.round(28 * Style.fontScale)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(2, Math.round(3 * Style.fontScale))
            color: Util.alpha(Commons.Color.foreground, 0.12)

            Rectangle {
              width: parent.width
              y: scroller.visibleArea.yPosition * track.height
              height: Math.max(width * 8, scroller.visibleArea.heightRatio * track.height)
              color: Commons.Color.accent
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.apps.length === 0
            textFormat: Text.PlainText
            text: Commons.I18n.t("dock.noAppsMatch").arg(root.filterText)
            color: Commons.Color.menu.text
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
          }
        }
      }

      // The keys, along the bottom.
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(22 * Style.fontScale)
        spacing: Style.spacing.xl
        visible: !root.uninstallEntry

        Repeater {
          model: [["↵", strings.t("hints.launch")], ["← ↑ ↓ →", strings.t("hints.move")], ["Esc", strings.t("hints.close")]]

          delegate: Row {
            required property var modelData
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              text: "[" + modelData[0] + "]"
              color: Commons.Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: modelData[1]
              color: Commons.Color.menu.text
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }

    // The dragged app's icon, under the pointer.
    Image {
      visible: root.dragging && !!root.dragEntry
      x: root.dragPoint.x - width / 2
      y: root.dragPoint.y - height / 2
      width: root.dragIconSize
      height: root.dragIconSize
      sourceSize: Qt.size(root.dragIconSize * 2, root.dragIconSize * 2)
      source: root.dragEntry && root.appLibrary ? root.appLibrary.iconSource(root.dragEntry.icon) : ""
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    // Right-click on an app: open it, or keep it in the dock or take it out.
    BorderSurface {
      id: menu

      readonly property var entry: root.menuEntry
      readonly property bool pinned: !!entry && !!root.dock && root.dock.isPinned(String(entry.id || ""))

      visible: !!entry && !root.dragging
      width: Math.max(Style.space(160), menuColumn.implicitWidth) + padding * 2
      height: menuColumn.implicitHeight + padding * 2
      // Opens along the reading direction from the pointer.
      x: LayoutMirroring.enabled
        ? Math.max(Style.gapsOut, root.menuPoint.x - width)
        : Math.min(root.menuPoint.x, panel.width - width - Style.gapsOut)
      y: Math.min(root.menuPoint.y, panel.height - height - Style.gapsOut)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
      padding: Style.spacing.sm

      Column {
        id: menuColumn
        x: menu.contentLeftInset
        y: menu.contentTopInset
        width: menu.width - menu.contentLeftInset - menu.contentRightInset

        MenuRow {
          text: Commons.I18n.t("dock.open")
          onTriggered: {
            var entry = menu.entry
            root.close()
            if (entry && root.dock) root.dock.launchEntry(entry)
            else if (entry && root.appLibrary) root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
          }
        }

        MenuRow {
          visible: !!root.dock
          text: menu.pinned ? Commons.I18n.t("dock.removeFromDock") : Commons.I18n.t("dock.keepInDock")
          onTriggered: {
            if (root.dock && menu.entry) root.dock.setPinned(String(menu.entry.id || ""), !menu.pinned)
            root.menuEntry = null
          }
        }

        MenuRow {
          text: Commons.I18n.t("dock.uninstall")
          onTriggered: root.requestUninstall(menu.entry)
        }
      }
    }
  }

  // One panel: a header strip with the panel's name and how many apps it
  // holds, over its apps' rows.
  component AppPanel: Rectangle {
    id: appPanel

    required property var modelData
    readonly property var group: modelData.group

    y: modelData.y
    width: root.panelWidth
    height: root.panelHeaderHeight + group.entries.length * root.rowHeight
    color: Util.alpha(Commons.Color.background, 0.45)
    border.width: 1
    border.color: Util.alpha(Commons.Color.accent, 0.24)

    Rectangle {
      x: 1
      y: 1
      width: parent.width - 2
      height: root.panelHeaderHeight - 1
      color: Util.alpha(Commons.Color.accent, 0.07)

      Text {
        anchors.left: parent.left
        anchors.leftMargin: root.rowPadding
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "// " + strings.t("group." + appPanel.group.key)
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.letterSpacing: Math.round(2 * Style.fontScale)
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: root.rowPadding
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "[" + (appPanel.group.entries.length < 10 ? "0" : "") + appPanel.group.entries.length + "]"
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Util.alpha(Commons.Color.accent, 0.24)
      }
    }

    Repeater {
      model: appPanel.group.entries

      delegate: AppRow {
        y: root.panelHeaderHeight + index * root.rowHeight
        appIndex: appPanel.group.start + index
      }
    }
  }

  // One app: its number in the panel, its icon in the theme's accent (in its
  // own colors when selected), and its name. Hover selects it, a click opens
  // it, a right-click opens its menu, and a drag takes it out to the dock.
  component AppRow: Item {
    id: appRow

    required property var modelData
    required property int index
    property int appIndex: 0
    readonly property bool selected: appIndex === root.selectedIndex
    property point pressPoint
    // A press that wanders is a drag in the making, not a click.
    property bool moved: false

    width: root.panelWidth
    height: root.rowHeight

    // The selected app: cyan brackets either side of the row, [ like this ],
    // with a soft glow. Only the selected row builds them.
    Loader {
      anchors.fill: parent
      active: appRow.selected

      sourceComponent: Item {
        id: selection

        readonly property int line: Math.max(2, Math.round(2 * Style.fontScale))
        readonly property int arm: Math.round(7 * Style.fontScale)

        // Drawn through the glow below, not on its own.
        Item {
          id: brackets
          anchors.fill: parent
          visible: false
          layer.enabled: true

          // [
          Rectangle { width: selection.line; height: parent.height; color: root.cyan }
          Rectangle { width: selection.arm; height: selection.line; color: root.cyan }
          Rectangle { width: selection.arm; height: selection.line; y: parent.height - height; color: root.cyan }
          // ]
          Rectangle { width: selection.line; height: parent.height; x: parent.width - width; color: root.cyan }
          Rectangle { width: selection.arm; height: selection.line; x: parent.width - width; color: root.cyan }
          Rectangle { width: selection.arm; height: selection.line; x: parent.width - width; y: parent.height - height; color: root.cyan }
        }

        MultiEffect {
          anchors.fill: brackets
          source: brackets
          autoPaddingEnabled: true
          shadowEnabled: true
          shadowColor: root.cyan
          shadowBlur: 0.6
          shadowOpacity: 0.9
          shadowHorizontalOffset: 0
          shadowVerticalOffset: 0
        }
      }
    }

    Row {
      anchors.left: parent.left
      anchors.leftMargin: root.rowPadding
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.round(10 * Style.fontScale)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(20 * Style.fontScale)
        textFormat: Text.PlainText
        text: (appRow.index < 9 ? "0" : "") + (appRow.index + 1)
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Image {
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconSize
        height: root.iconSize
        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
        source: root.appLibrary ? root.appLibrary.iconSource(appRow.modelData.icon) : ""
        fillMode: Image.PreserveAspectFit
        // Loaded with the row, from Qt's image cache after the first open, so
        // icons do not pop in after the panels have appeared.
        asynchronous: false
        smooth: true
        mipmap: true
        layer.enabled: !appRow.selected
        layer.effect: MultiEffect {
          colorization: 1.0
          colorizationColor: Commons.Color.accent
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: root.panelWidth - root.rowPadding * 2 - root.iconSize - Math.round(50 * Style.fontScale)
        textFormat: Text.PlainText
        text: root.appLibrary ? root.appLibrary.entryName(appRow.modelData) : ""
        color: appRow.selected ? root.cyan : Commons.Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      // The panels would otherwise take a dragging press for a scroll.
      preventStealing: true
      onContainsMouseChanged: if (containsMouse && !root.dragging) root.selectedIndex = appRow.appIndex
      onPressed: function(event) {
        appRow.moved = false
        appRow.pressPoint = Qt.point(event.x, event.y)
      }
      onPositionChanged: function(event) {
        if (!(pressedButtons & Qt.LeftButton)) return
        if (!appRow.moved && Math.hypot(event.x - appRow.pressPoint.x, event.y - appRow.pressPoint.y) > Style.space(4)) appRow.moved = true
        if (appRow.moved) root.dragTo(appRow.modelData, appRow.mapToItem(panel.contentItem, event.x, event.y))
      }
      onReleased: function(event) {
        if (root.dragging && event.button === Qt.LeftButton) root.dropDrag()
      }
      onCanceled: if (root.dragging) root.close()
      onClicked: function(event) {
        if (appRow.moved) return
        if (event.button === Qt.RightButton) {
          root.openMenu(appRow.modelData, appRow.mapToItem(panel.contentItem, event.x, event.y))
          return
        }
        root.menuEntry = null
        root.launch(appRow.appIndex)
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.triggered()
    }
  }
}
