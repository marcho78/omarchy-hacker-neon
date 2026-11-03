import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DockModel.js" as DockModel

// One screen's dock. It stays mapped and only hides its contents, so switching
// to a floating workspace does not wait on a fresh layer surface. While hidden the
// mask is empty and clicks fall through to the windows below.
PanelWindow {
  id: window
  // Right-to-left languages read this window mirrored.
  Binding { target: window.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: window.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }


  property var dock: null

  readonly property string position: dock ? dock.position : "bottom"
  readonly property bool vertical: dock ? dock.vertical : false
  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var workspace: monitor ? monitor.activeWorkspace : null
  readonly property int workspaceId: workspace ? workspace.id : -1
  // The most fullscreen window on the workspace, as Hyprland counts it: 1 is
  // maximized, and 2 or 3 fullscreen.
  readonly property int fullscreenMode: {
    var mode = 0
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel.workspace || toplevel.workspace.id !== workspaceId) continue
      var ipc = toplevel.lastIpcObject
      mode = Math.max(mode, ipc && ipc.fullscreen ? ipc.fullscreen : 0)
    }
    return mode
  }
  readonly property bool shown: !!dock && dock.isFloating(workspaceId) && fullscreenMode < 2
  // With auto-hide on, the dock waits off screen until the pointer reaches its
  // edge, and stays while the pointer, a menu, or a drag still needs it. A
  // maximized window hides the dock the same way, so it can still be called up.
  readonly property bool autohide: !!dock && (dock.autohide || fullscreenMode === 1)
  property bool revealed: false
  readonly property bool menuOpen: menuItem !== null || settingsMenu
  readonly property bool tucked: autohide && !(revealed || menuOpen || dragging || insertIndex >= 0)
  readonly property bool contentShown: shown && !tucked

  readonly property int gap: Style.spacing.xs
  readonly property int iconSize: Math.round(48 * Style.fontScale)
  // Each app has a square slot with its icon in the middle, and the slots run
  // straight to the edge of the dock.
  readonly property int iconInset: Style.spacing.md
  readonly property int slotSize: iconSize + iconInset * 2
  // A pinned app that is not running is drawn faded.
  readonly property real idleOpacity: 0.7

  // Neon Dock: the apps sit on frosted glass (Hyprland blurs what is behind the
  // dock's layer) between two glowing cyan curly braces. Icons wear the theme's
  // accent and magnify in a wave under the pointer; the hovered one shows its
  // own colors between cyan brackets, as in the app grid, and its name past it.
  // Running apps get a cyan dot.
  readonly property int dockPad: Math.round(9 * Style.fontScale)
  readonly property color cyan: dock ? dock.cyan : Commons.Color.accent
  readonly property real magnifyPeak: 0.38
  // Where the pointer is along the row of slots, or -1 while it is away, a drag
  // is on, or the slots have just moved under it.
  readonly property real pointerAlong: bodyHover.hovered && !window.dragging && !window.hoverStale && window.insertIndex < 0
    ? (window.vertical ? bodyHover.point.position.y - slots.y : bodyHover.point.position.x - slots.x)
    : -1
  // The slot under the pointer, whose name the label shows.
  property Item hoverSlot: null

  // The icon under the pointer grows most, its neighbours less, the rest not at
  // all. The slots keep their size, so drags and drops still count in slots.
  function magnify(slot) {
    if (window.pointerAlong < 0 || !slot) return 1
    var center = window.vertical ? slot.y + slot.height / 2 : slot.x + slot.width / 2
    var distance = (window.pointerAlong - center) / window.slotSize
    return 1 + window.magnifyPeak * Math.exp(-(distance * distance) / 1.06)
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  // Room inward of the dock for its menus: the tallest, the apps button's,
  // has five rows.
  readonly property int popupRoom: Style.spacing.popupRowHeight * 5 + Style.spacing.sm * 2 + Style.normalBorderWidth * 2 + gap * 2
  // Icons pop away from the screen edge.
  readonly property int popOrigin: position === "top" ? Item.Top
    : position === "left" ? Item.Left
    : position === "right" ? Item.Right
    : Item.Bottom

  // The app being dragged along the dock, how far the pointer has taken it,
  // and the slot it would land in.
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  readonly property bool dragging: dragIndex >= 0
  // Off while a drop resets the slots: they snap to where the reorder puts
  // them rather than sliding back from where they stepped aside. Set before
  // the drag state changes, so the slots never see the reset animated.
  property bool animateShifts: true
  // After a drop the slots have moved under a pointer that has not, so what
  // they think is hovered is stale until it moves again.
  property bool hoverStale: false
  property point dropPoint
  // Where an app dragged in from the app grid would land, or -1.
  property int insertIndex: -1

  // Where this window sits on its screen, which a point from the app grid's
  // fullscreen surface is given in: against its edge, clear of the space
  // other surfaces such as the bar reserve. Hyprland lists that space as
  // left, top, right, bottom.
  function origin() {
    var reserved = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
    var left = reserved[0] || 0, top = reserved[1] || 0, right = reserved[2] || 0, bottom = reserved[3] || 0
    var x = window.position === "right" ? screen.width - right - window.width : left
    var y = window.position === "bottom" ? screen.height - bottom - window.height : top
    return Qt.point(x, y)
  }

  // An app from the app grid lands where the pointer is, once it is over the
  // dock or close to it on the inward side.
  function moveExternalDrag(screenX, screenY) {
    var at = window.origin()
    var point = Qt.point(screenX - at.x - body.x, screenY - at.y - body.y)
    var reach = window.slotSize
    var along = window.vertical ? point.y : point.x
    var across = window.vertical ? point.x : point.y
    var length = window.vertical ? body.height : body.width
    var depth = window.vertical ? body.width : body.height
    var near = along >= -window.slotSize && along <= length + window.slotSize && across >= -reach && across <= depth + reach
    if (window.shown && window.autohide && near) window.revealed = true
    window.insertIndex = window.shown && near ? window.slotIndexAt(point) : -1
  }

  function dropExternalDrag(screenX, screenY, key) {
    window.moveExternalDrag(screenX, screenY)
    window.settleShifts()
    if (window.insertIndex >= 0 && key && window.dock) window.dock.pinAt(key, window.insertIndex)
    window.endExternalDrag()
  }

  function endExternalDrag() {
    window.insertIndex = -1
    if (window.autohide) hideTimer.restart()
  }

  // The slot a point along the dock falls before, counting from the first app.
  function slotIndexAt(point) {
    // Counted from the slots, inside the capsule's padding.
    var along = window.vertical ? point.y - slots.y : point.x - slots.x
    var first = window.slotSize
    var count = window.dock ? window.dock.itemModel.count : 0
    return Math.max(0, Math.min(count, Math.round((along - first) / window.slotSize)))
  }
  property var menuItem: null
  property Item menuSlot: null
  // The apps button's menu: where the dock sits and whether it hides.
  property bool settingsMenu: false

  onWorkspaceIdChanged: if (dock) dock.readMode(workspaceId)
  onShownChanged: {
    if (shown) return
    closeMenu()
    window.revealed = false
  }
  Component.onCompleted: if (dock) dock.readMode(workspaceId)

  function openMenu(item, slot) {
    window.settingsMenu = false
    window.menuItem = item
    window.menuSlot = slot
  }

  function openSettingsMenu(slot) {
    window.menuItem = null
    window.settingsMenu = true
    window.menuSlot = slot
  }

  function settleShifts() {
    window.animateShifts = false
    Qt.callLater(function() { window.animateShifts = true })
  }

  function endDrag() {
    window.settleShifts()
    window.hoverStale = true
    window.dragIndex = -1
    window.dropIndex = -1
    window.dragOffset = 0
  }

  function closeMenu() {
    window.menuItem = null
    window.settingsMenu = false
    window.menuSlot = null
    if (window.autohide) hideTimer.restart()
  }

  // Places the menu inward of the dock, centered on a slot.
  function popupX(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, slot.width / 2, 0).x
    if (window.position === "left") return body.x + body.width + window.gap
    if (window.position === "right") return body.x - window.gap - popup.width
    return Math.max(window.gap, Math.min(window.width - popup.width - window.gap, center - popup.width / 2))
  }

  function popupY(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, 0, slot.height / 2).y
    if (window.position === "top") return body.y + body.height + window.gap
    if (window.position === "bottom") return body.y - window.gap - popup.height
    return Math.max(window.gap, Math.min(window.height - popup.height - window.gap, center - popup.height / 2))
  }

  visible: !remapGuard.remapping
  color: "transparent"
  WlrLayershell.namespace: "omarchy-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Kept clear of the bar's reserved edge, without reserving one of its own:
  // floating windows go where they are put.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  anchors {
    top: window.position !== "bottom"
    bottom: window.position !== "top"
    left: window.position !== "right"
    right: window.position !== "left"
  }

  implicitWidth: window.vertical ? window.gap + window.slotSize + window.dockPad * 2 + window.popupRoom : 0
  implicitHeight: window.vertical ? 0 : window.gap + window.slotSize + window.dockPad * 2 + window.popupRoom

  mask: Region {
    item: window.contentShown ? body : null

    Region { item: window.shown && window.autohide ? edgeTrigger : null }
    Region { item: menu.visible ? menu : null }
  }

  onAutohideChanged: window.revealed = false

  Timer {
    id: hideTimer
    // Long enough to cross a gap between the edge and the icons, no longer.
    interval: 150
    onTriggered: {
      if (!bodyHover.hovered && !edgeHover.hovered && !window.menuOpen && !window.dragging) window.revealed = false
    }
  }

  // The strip along the screen edge that brings an auto-hidden dock back.
  Item {
    id: edgeTrigger

    readonly property int depth: window.gap + Style.spacing.xxs

    x: window.position === "left" ? 0 : window.position === "right" ? window.width - depth : body.x
    y: window.position === "top" ? 0 : window.position === "bottom" ? window.height - depth : body.y
    width: window.vertical ? depth : body.width
    height: window.vertical ? body.height : depth

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) window.revealed = true
        else hideTimer.restart()
      }
    }
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }

  HyprlandFocusGrab {
    active: window.menuOpen
    windows: [window]
    onCleared: window.closeMenu()
  }

  Item {
    id: body

    // The strip keeps its order in every language, like the bar: drags and
    // drops reckon slots along x from the first app. Only the menu mirrors.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // The slots, with the capsule's padding around them.
    width: slots.implicitWidth + window.dockPad * 2
    height: slots.implicitHeight + window.dockPad * 2
    // How far the dock is tucked past its edge. Auto-hide slides it, but only
    // while the dock is on screen: arriving on a floating workspace shows it
    // where it belongs at once.
    property real tuck: window.tucked ? (window.vertical ? width : height) + window.gap : 0

    Behavior on tuck {
      enabled: window.shown
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    x: window.position === "left" ? window.gap - tuck
      : window.position === "right" ? window.width - width - window.gap + tuck
      : Math.round((window.width - width) / 2)
    y: window.position === "top" ? window.gap - tuck
      : window.position === "bottom" ? window.height - height - window.gap + tuck
      : Math.round((window.height - height) / 2)
    // Switching between tiled and floating workspaces shows and hides the dock
    // at once, with nothing to watch in between. Hidden by opacity rather than
    // visibility, so the icons keep their textures and are drawn on the first
    // frame back instead of being uploaded again.
    opacity: window.shown ? 1 : 0

    // The glass: square, with a soft shadow and a cyan haze around it, and
    // frosted inside.
    RectangularShadow {
      anchors.fill: capsule
      offset: Qt.vector2d(0, Math.round(10 * Style.fontScale))
      blur: Math.round(34 * Style.fontScale)
      color: Qt.rgba(0, 0, 0, 0.55)
    }

    RectangularShadow {
      anchors.fill: capsule
      blur: Math.round(22 * Style.fontScale)
      color: Util.alpha(window.cyan, 0.14)
    }

    Rectangle {
      id: capsule
      anchors.fill: parent
      color: Util.alpha(Commons.Color.background, 0.55)
    }

    // A curly brace on each end of the glass, its stem on the glass's edge and
    // its point facing out, drawn through the glow below.
    Item {
      id: braces

      readonly property real depth: Math.round(14 * Style.fontScale)
      // Room past the strokes: a layer draws nothing outside its item.
      readonly property real margin: Math.round(4 * Style.fontScale)
      readonly property real reach: depth / 2 + margin

      x: window.vertical ? -margin : -reach
      y: window.vertical ? -reach : -margin
      width: capsule.width + (window.vertical ? margin : reach) * 2
      height: capsule.height + (window.vertical ? reach : margin) * 2
      visible: false
      layer.enabled: true

      Brace {
        x: braces.margin
        y: braces.margin
        width: window.vertical ? capsule.width : braces.depth
        height: window.vertical ? braces.depth : capsule.height
      }

      Brace {
        closing: true
        x: window.vertical ? braces.margin : braces.width - braces.margin - braces.depth
        y: window.vertical ? braces.height - braces.margin - braces.depth : braces.margin
        width: window.vertical ? capsule.width : braces.depth
        height: window.vertical ? braces.depth : capsule.height
      }
    }

    MultiEffect {
      anchors.fill: braces
      source: braces
      autoPaddingEnabled: true
      shadowEnabled: true
      shadowColor: window.cyan
      shadowBlur: 0.6
      shadowOpacity: 0.9
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
    }

    HoverHandler {
      id: bodyHover
      onHoveredChanged: if (!hovered && window.autohide) hideTimer.restart()
      // Only a real move clears it: the release itself reports the pointer too.
      onPointChanged: {
        if (!window.hoverStale || window.dragging) return
        var at = point.position
        if (Math.hypot(at.x - window.dropPoint.x, at.y - window.dropPoint.y) > Style.space(4)) window.hoverStale = false
      }
    }

    Grid {
      id: slots
      anchors.centerIn: parent
      columns: window.vertical ? 1 : appRepeater.count + 1

      AppsSlot {}

      Repeater {
        id: appRepeater
        model: window.dock ? window.dock.itemModel : null

        delegate: AppSlot {}
      }
    }
  }

  component Slot: Item {
    id: slot

    // Only the dragged icon is lifted while a drag is on; none of the others
    // pop as it passes over them.
    property bool hovered: mouse.containsMouse && !window.hoverStale && !window.dragging
    property bool pressed: mouse.pressed
    property alias mouse: mouse
    // What the label past the icon reads while the slot is hovered.
    property string name: ""

    width: window.slotSize
    height: window.slotSize

    onHoveredChanged: {
      if (hovered) window.hoverSlot = slot
      else if (window.hoverSlot === slot) window.hoverSlot = null
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    }
  }

  component AppsSlot: Slot {
    id: appsSlot

    name: strings.t("apps.label")
    property real displayedShift: window.insertIndex >= 0 ? -window.slotSize / 2 : 0

    Behavior on displayedShift {
      enabled: window.animateShifts
      NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    transform: Translate {
      x: window.vertical ? 0 : appsSlot.displayedShift
      y: window.vertical ? appsSlot.displayedShift : 0
    }

    mouse.onClicked: function(event) {
      if (event.button === Qt.RightButton) {
        window.openSettingsMenu(appsSlot)
        return
      }
      window.closeMenu()
      if (window.dock) window.dock.openApps()
    }

    // A grid of app squares reads as "all apps" in any icon theme. Drawn
    // rather than taken from a font, so its edges stay crisp on the
    // transparent dock and it fills its slot like the app icons beside it. It
    // wears the accent like the app icons, and cyan when hovered.
    Item {
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      scale: window.magnify(appsSlot)
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

      Grid {
        readonly property int square: Math.round(window.iconSize * 0.22)

        anchors.centerIn: parent
        columns: 3
        spacing: Math.round(window.iconSize * 0.1)

        Repeater {
          model: 9

          delegate: Rectangle {
            width: parent.square
            height: parent.square
            color: appsSlot.hovered ? window.cyan : Commons.Color.accent
          }
        }
      }

      IconBrackets { active: appsSlot.hovered }
    }
  }

  component AppSlot: Slot {
    id: appSlot

    required property int index
    required property string key
    readonly property var modelData: window.dock ? window.dock.itemFor(key) : null
    readonly property bool launching: !!window.dock && window.dock.isLaunching(key)
    readonly property bool lifted: window.dragIndex === index
    property point pressPoint
    property bool dragged: false
    readonly property int windowCount: modelData ? modelData.windows.length : 0
    property real pulse: 1

    name: {
      var entry = window.dock ? window.dock.entryFor(appSlot.modelData) : null
      var library = window.dock ? window.dock.appLibrary : null
      if (entry && library) return library.entryName(entry)
      return appSlot.modelData ? String(appSlot.modelData.key) : ""
    }

    // Slots between where the dragged app was and where it would land step
    // aside to make room; the dragged one follows the pointer.
    readonly property real shift: window.insertIndex >= 0 ? (index >= window.insertIndex ? 1 : -1) * window.slotSize / 2
      : !window.dragging ? 0
      : lifted ? window.dragOffset
      : (window.dragIndex < index && index <= window.dropIndex) ? -window.slotSize
      : (window.dropIndex <= index && index < window.dragIndex) ? window.slotSize
      : 0
    property real displayedShift: shift

    // Only while dragging: once the drop reorders the slots, they are already
    // where they were shown.
    Behavior on displayedShift {
      enabled: window.animateShifts && ((window.dragging && !appSlot.lifted) || window.insertIndex >= 0)
      NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    z: lifted ? 1 : 0

    // The slot, and the pointer handling in it, stays where it is; only the
    // icon moves. Reading the pointer through a slot that moves with it would
    // feed each move back into the next.
    function bodyPoint(event) {
      return appSlot.mapToItem(body, event.x, event.y)
    }

    mouse.onPressed: function(event) {
      appSlot.dragged = false
      if (event.button === Qt.LeftButton) appSlot.pressPoint = appSlot.bodyPoint(event)
    }

    mouse.onPositionChanged: function(event) {
      if (!(appSlot.mouse.pressedButtons & Qt.LeftButton)) return
      var point = appSlot.bodyPoint(event)
      var delta = window.vertical ? point.y - appSlot.pressPoint.y : point.x - appSlot.pressPoint.x
      // A press that wanders is a drag in the making, not a click.
      if (Math.hypot(point.x - appSlot.pressPoint.x, point.y - appSlot.pressPoint.y) > Style.space(4)) appSlot.dragged = true
      if (!window.dragging) {
        if (Math.abs(delta) < Style.space(6)) return
        window.closeMenu()
        // The landing slot first: with the dragged slot set and no landing
        // slot yet, every slot before it would count as in between and step
        // aside for a moment.
        window.dropIndex = appSlot.index
        window.dragIndex = appSlot.index
      }
      if (!appSlot.lifted) return
      window.dragOffset = delta
      window.dropIndex = DockModel.dropIndex(appSlot.index, delta, window.slotSize, appRepeater.count)
    }

    mouse.onReleased: function(event) {
      if (!appSlot.lifted) return
      window.dropPoint = appSlot.mapToItem(body, event.x, event.y)
      var from = window.dragIndex
      var to = window.dropIndex
      appSlot.dragged = true
      window.endDrag()
      window.dock.moveItem(from, to)
    }

    mouse.onCanceled: if (appSlot.lifted) window.endDrag()

    mouse.onClicked: function(event) {
      // A drag ends in a release over the app, which is not a click on it.
      if (appSlot.dragged) {
        appSlot.dragged = false
        return
      }
      if (event.button === Qt.RightButton) {
        window.openMenu(appSlot.modelData, appSlot)
        return
      }
      window.closeMenu()
      if (event.button === Qt.MiddleButton) window.dock.launch(appSlot.modelData)
      else window.dock.activate(appSlot.modelData)
    }

    Item {
      x: window.iconInset
      y: window.iconInset
      width: window.iconSize
      height: window.iconSize
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }
      scale: appSlot.lifted ? 1.15 : window.magnify(appSlot)
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

      // Running apps are drawn in full, pinned ones that are not running
      // faded, and one that is starting pulses between the two. The icon
      // wears the theme's accent, except while hovered.
      Image {
        anchors.fill: parent
        sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
        source: window.dock && appSlot.modelData ? window.dock.iconFor(appSlot.modelData) : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        opacity: appSlot.launching ? appSlot.pulse : (appSlot.windowCount > 0 ? 1 : window.idleOpacity)
        layer.enabled: !appSlot.hovered
        layer.effect: MultiEffect {
          colorization: 1.0
          colorizationColor: Commons.Color.accent
        }
      }

      IconBrackets { active: appSlot.hovered }
    }

    // A running app gets a glowing cyan dot between its icon and the screen
    // edge, in the capsule's padding.
    Item {
      id: runDot

      readonly property int size: Math.max(4, Math.round(5 * Style.fontScale))
      readonly property int gap: Math.round(2 * Style.fontScale)

      visible: appSlot.windowCount > 0
      width: size
      height: size
      x: window.position === "left" ? -size - gap
        : window.position === "right" ? appSlot.width + gap
        : (appSlot.width - size) / 2
      y: window.position === "top" ? -size - gap
        : window.position === "bottom" ? appSlot.height + gap
        : (appSlot.height - size) / 2
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }

      RectangularShadow {
        anchors.fill: parent
        radius: runDot.size / 2
        blur: Math.round(8 * Style.fontScale)
        color: Util.alpha(window.cyan, 0.8)
      }

      Rectangle {
        anchors.fill: parent
        radius: runDot.size / 2
        color: window.cyan
      }
    }

    SequentialAnimation {
      running: appSlot.launching
      loops: Animation.Infinite
      onRunningChanged: if (!running) appSlot.pulse = 1

      NumberAnimation { target: appSlot; property: "pulse"; from: 1; to: window.idleOpacity; duration: 500; easing.type: Easing.InOutSine }
      NumberAnimation { target: appSlot; property: "pulse"; to: 1; duration: 500; easing.type: Easing.InOutSine }
    }
  }

  // A curly brace across the dock's thickness, its point at the start of its
  // depth: { at the dock's start, and } (closing) at its end. Along x for a
  // dock across the screen, along y for one down its side.
  component Brace: Shape {
    id: brace

    property bool closing: false
    readonly property real depth: window.vertical ? height : width
    readonly property real span: window.vertical ? width : height
    readonly property real curl: depth / 2

    // The point d into the brace's depth and s across the dock.
    function px(d, s) { return window.vertical ? s : (brace.closing ? brace.depth - d : d) }
    function py(d, s) { return window.vertical ? (brace.closing ? brace.depth - d : d) : s }

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: window.cyan
      strokeWidth: Math.max(2, Math.round(2 * Style.fontScale))
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      startX: brace.px(brace.depth, 0)
      startY: brace.py(brace.depth, 0)
      PathQuad {
        controlX: brace.px(brace.curl, 0); controlY: brace.py(brace.curl, 0)
        x: brace.px(brace.curl, brace.curl); y: brace.py(brace.curl, brace.curl)
      }
      PathLine { x: brace.px(brace.curl, brace.span / 2 - brace.curl); y: brace.py(brace.curl, brace.span / 2 - brace.curl) }
      PathQuad {
        controlX: brace.px(brace.curl, brace.span / 2); controlY: brace.py(brace.curl, brace.span / 2)
        x: brace.px(0, brace.span / 2); y: brace.py(0, brace.span / 2)
      }
      PathQuad {
        controlX: brace.px(brace.curl, brace.span / 2); controlY: brace.py(brace.curl, brace.span / 2)
        x: brace.px(brace.curl, brace.span / 2 + brace.curl); y: brace.py(brace.curl, brace.span / 2 + brace.curl)
      }
      PathLine { x: brace.px(brace.curl, brace.span - brace.curl); y: brace.py(brace.curl, brace.span - brace.curl) }
      PathQuad {
        controlX: brace.px(brace.curl, brace.span); controlY: brace.py(brace.curl, brace.span)
        x: brace.px(brace.depth, brace.span); y: brace.py(brace.depth, brace.span)
      }
    }
  }

  // Cyan brackets either side of a hovered icon, [ like this ], with a soft
  // glow, the way the app grid marks its selected app. Built only while shown.
  component IconBrackets: Loader {
    anchors.fill: parent
    anchors.margins: -Math.round(6 * Style.fontScale)

    sourceComponent: Item {
      id: selection

      readonly property int line: Math.max(2, Math.round(2 * Style.fontScale))
      readonly property int arm: Math.round(8 * Style.fontScale)

      // Drawn through the glow below, not on its own.
      Item {
        id: brackets
        anchors.fill: parent
        visible: false
        layer.enabled: true

        // [
        Rectangle { width: selection.line; height: parent.height; color: window.cyan }
        Rectangle { width: selection.arm; height: selection.line; color: window.cyan }
        Rectangle { width: selection.arm; height: selection.line; y: parent.height - height; color: window.cyan }
        // ]
        Rectangle { width: selection.line; height: parent.height; x: parent.width - width; color: window.cyan }
        Rectangle { width: selection.arm; height: selection.line; x: parent.width - width; color: window.cyan }
        Rectangle { width: selection.arm; height: selection.line; x: parent.width - width; y: parent.height - height; color: window.cyan }
      }

      MultiEffect {
        anchors.fill: brackets
        source: brackets
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: window.cyan
        shadowBlur: 0.6
        shadowOpacity: 0.9
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
      }
    }
  }

  // The hovered app's name, in a square label just past its magnified icon.
  Rectangle {
    id: nameTip

    readonly property Item slot: window.hoverSlot
    readonly property real lift: window.iconSize * window.magnifyPeak + Math.round(8 * Style.fontScale)

    visible: window.contentShown && !!slot && slot.name !== "" && !window.menuOpen && !window.dragging
    width: nameText.implicitWidth + Math.round(24 * Style.fontScale)
    height: nameText.implicitHeight + Math.round(10 * Style.fontScale)
    color: Util.alpha(Commons.Color.background, 0.85)
    border.width: 1
    border.color: Util.alpha(window.cyan, 0.5)
    x: {
      if (!slot) return 0
      var at = slot.mapToItem(window.contentItem, 0, 0)
      if (window.position === "left") return at.x + slot.width + lift
      if (window.position === "right") return at.x - width - lift
      return Math.max(window.gap, Math.min(window.width - width - window.gap, at.x + slot.width / 2 - width / 2))
    }
    y: {
      if (!slot) return 0
      var at = slot.mapToItem(window.contentItem, 0, 0)
      if (window.position === "top") return at.y + slot.height + lift
      if (window.position === "bottom") return at.y - height - lift
      return at.y + slot.height / 2 - height / 2
    }

    Text {
      id: nameText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: nameTip.slot ? nameTip.slot.name : ""
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  BorderSurface {
    id: menu

    readonly property var item: window.menuItem
    readonly property bool hasEntry: !!item && !!window.dock && !!window.dock.entryFor(item)
    readonly property bool running: !!item && item.windows.length > 0

    visible: window.contentShown && (!!item || window.settingsMenu)
    width: Math.max(Style.space(140), menuColumn.implicitWidth) + padding * 2
    height: menuColumn.implicitHeight + padding * 2
    x: window.popupX(window.menuSlot, menu)
    y: window.popupY(window.menuSlot, menu)
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
    padding: Style.spacing.sm

    Column {
      id: menuColumn
      x: menu.contentLeftInset
      y: menu.contentTopInset
      width: menu.width - menu.contentLeftInset - menu.contentRightInset

      Repeater {
        model: [["top", Commons.I18n.t("dock.positionTop")], ["bottom", Commons.I18n.t("dock.positionBottom")], ["left", Commons.I18n.t("dock.positionLeft")], ["right", Commons.I18n.t("dock.positionRight")]]

        delegate: MenuRow {
          required property var modelData

          visible: window.settingsMenu
          text: modelData[1]
          checked: window.position === modelData[0]
          onTriggered: Util.execDetached("omarchy-dock position " + modelData[0])
        }
      }

      MenuRow {
        visible: window.settingsMenu
        text: Commons.I18n.t("dock.autoHide")
        checked: window.autohide
        onTriggered: Util.execDetached("omarchy-dock autohide " + (window.autohide ? "off" : "on"))
      }

      MenuRow {
        visible: menu.hasEntry && menu.running
        text: Commons.I18n.t("dock.newWindow")
        onTriggered: window.dock.launch(menu.item)
      }

      MenuRow {
        visible: menu.hasEntry
        text: menu.item && menu.item.pinned ? Commons.I18n.t("dock.removeFromDock") : Commons.I18n.t("dock.keepInDock")
        onTriggered: window.dock.setPinned(menu.item.key, !menu.item.pinned)
      }

      MenuRow {
        visible: menu.running
        text: Commons.I18n.t("dock.quit")
        onTriggered: window.dock.quit(menu.item)
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    property bool checked: false
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

    Text {
      visible: row.checked
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: "✓"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        row.triggered()
        window.closeMenu()
      }
    }
  }
}
