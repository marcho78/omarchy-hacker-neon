import QtQuick

// Trinity's face: the round bot as a hologram. A see-through ball lit at the
// rim and toward the upper right, scan lines drifting through it, a glossy
// highlight, and two tilted capsule eyes that glow. It floats, blinks, squints
// while thinking, and while she speaks its glow brightens and it swells a
// little with the loudness of her voice.
Canvas {
  id: orb

  // "idle", "listening", "thinking" or "speaking".
  property string phase: "idle"
  // How loud her voice is right now, from 0 to 1.
  property real level: 0
  property color tint: "#00ff9c"
  property color listenTint: "#00e5ff"
  property bool running: visible

  // Animated values, eased toward their targets each frame.
  property real time: 0
  property real openness: 1
  // How strongly she is speaking, eased: drives the glow and the swell.
  property real pulse: 0
  property real lean: 0
  property real lookX: 0
  property real lookY: 0
  property real blink: 1
  property real nextBlink: 3

  readonly property color color: phase === "listening" ? listenTint : tint

  width: 200
  height: 200

  FrameAnimation {
    running: orb.running
    onTriggered: {
      var dt = Math.min(0.05, frameTime)
      orb.time += dt
      var ease = 1 - Math.pow(0.001, dt)
      var targetOpen = orb.phase === "thinking" ? 0.32 : 1
      var targetLean = orb.phase === "listening" ? -5 : orb.phase === "thinking" ? 6 : 0
      var targetLookX = orb.phase === "thinking" ? 7 : orb.phase === "listening" ? -3 : 0
      var targetLookY = orb.phase === "thinking" ? -7 : 0
      var targetPulse = orb.phase === "speaking" ? orb.level : 0
      orb.openness += (targetOpen - orb.openness) * ease
      orb.lean += (targetLean - orb.lean) * ease
      orb.lookX += (targetLookX - orb.lookX) * ease
      orb.lookY += (targetLookY - orb.lookY) * ease
      // Rises fast and settles a little slower, like a voice.
      var rate = targetPulse > orb.pulse ? 1 - Math.pow(0.00001, dt) : ease
      orb.pulse += (targetPulse - orb.pulse) * rate
      // A blink every few seconds.
      orb.nextBlink -= dt
      if (orb.nextBlink <= 0) {
        orb.blink = 0
        orb.nextBlink = 2.5 + Math.random() * 3.5
      }
      orb.blink = Math.min(1, orb.blink + dt * 9)
      orb.requestPaint()
    }
  }

  function rgba(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  function capsule(ctx, x, y, w, h, angle) {
    ctx.save()
    ctx.translate(x, y)
    ctx.rotate(angle * Math.PI / 180)
    var r = Math.min(w, h) / 2
    ctx.beginPath()
    ctx.moveTo(-w / 2 + r, -h / 2)
    ctx.lineTo(w / 2 - r, -h / 2)
    ctx.arc(w / 2 - r, -h / 2 + r, r, -Math.PI / 2, 0)
    ctx.lineTo(w / 2, h / 2 - r)
    ctx.arc(w / 2 - r, h / 2 - r, r, 0, Math.PI / 2)
    ctx.lineTo(-w / 2 + r, h / 2)
    ctx.arc(-w / 2 + r, h / 2 - r, r, Math.PI / 2, Math.PI)
    ctx.lineTo(-w / 2, -h / 2 + r)
    ctx.arc(-w / 2 + r, -h / 2 + r, r, Math.PI, Math.PI * 1.5)
    ctx.closePath()
    ctx.fill()
    ctx.restore()
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var s = Math.min(width, height) / 280
    var c = orb.color
    var cx = width / 2
    var cy = height / 2 + Math.sin(orb.time * 1.6) * 3 * s
    // A subtle swell with her voice: up to 3%.
    var r = 92 * s * (1 + 0.03 * orb.pulse)

    ctx.save()
    ctx.translate(cx, cy)
    ctx.rotate(orb.lean * Math.PI / 180)
    ctx.translate(-cx, -cy)

    // Glow around the ball.
    var glow = ctx.createRadialGradient(cx, cy, r * 0.8, cx, cy, r * 1.45)
    glow.addColorStop(0, rgba(c, 0.28 + 0.3 * orb.pulse))
    glow.addColorStop(1, rgba(c, 0))
    ctx.fillStyle = glow
    ctx.beginPath()
    ctx.arc(cx, cy, r * 1.45, 0, Math.PI * 2)
    ctx.fill()

    // The body: clear in the middle, bright at the rim.
    var body = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
    body.addColorStop(0.55, rgba(c, 0.06))
    body.addColorStop(0.86, rgba(c, 0.26))
    body.addColorStop(1, rgba(c, 0.7))
    ctx.fillStyle = body
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.fill()

    // Soft light toward the upper right, as on the solid bot.
    var lit = ctx.createRadialGradient(cx + r * 0.28, cy - r * 0.32, 0, cx + r * 0.28, cy - r * 0.32, r * 0.95)
    lit.addColorStop(0, Qt.rgba(0.96, 1, 0.98, 0.32))
    lit.addColorStop(0.5, rgba(c, 0.14))
    lit.addColorStop(1, rgba(c, 0))
    ctx.fillStyle = lit
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.fill()

    // Scan lines drifting down through the ball.
    ctx.save()
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.clip()
    ctx.fillStyle = rgba(c, 0.13)
    var gap = 4 * s
    var drift = (orb.time * 12 * s) % gap
    for (var y = cy - r + drift; y < cy + r; y += gap) ctx.fillRect(cx - r, y, r * 2, Math.max(1, 1.2 * s))
    ctx.restore()

    // The rim.
    ctx.strokeStyle = rgba(c, Math.min(1, 0.9 + 0.1 * orb.pulse))
    ctx.lineWidth = 1.6 * s
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.stroke()

    // A glossy highlight along the upper left.
    ctx.strokeStyle = Qt.rgba(0.96, 1, 0.98, 0.5)
    ctx.lineWidth = 3 * s
    ctx.lineCap = "round"
    ctx.beginPath()
    ctx.arc(cx, cy, r * 0.86, Math.PI * 1.08, Math.PI * 1.36)
    ctx.stroke()

    // The eyes: tall capsules, tilted and set up and to the right.
    var open = orb.openness * orb.blink
    var eyes = [[cx - 2 * s, cy - 22 * s, 38 * s], [cx + 46 * s, cy - 37 * s, 36 * s]]
    for (var i = 0; i < eyes.length; i++) {
      var ex = eyes[i][0] + orb.lookX * s
      var ey = eyes[i][1] + orb.lookY * s
      var eh = Math.max(4 * s, eyes[i][2] * open)
      ctx.fillStyle = rgba(c, 0.35)
      capsule(ctx, ex, ey, 23 * s, eh + 6 * s, -22)
      ctx.fillStyle = Qt.rgba(0.96, 1, 0.98, 1)
      capsule(ctx, ex, ey, 17 * s, eh, -22)
    }

    ctx.restore()

    // A few sparkles circling, more while she speaks.
    var count = orb.phase === "speaking" ? 14 : 7
    for (var k = 0; k < count; k++) {
      var a = k * 2.399 + orb.time * (0.15 + (k % 3) * 0.05)
      var d = r + (12 + (k * 13) % 34) * s
      var twinkle = 0.35 + 0.65 * Math.abs(Math.sin(orb.time * 1.7 + k))
      ctx.fillStyle = k % 3 === 0 ? Qt.rgba(0.96, 1, 0.98, twinkle) : rgba(c, twinkle)
      ctx.beginPath()
      ctx.arc(cx + Math.cos(a) * d, cy + Math.sin(a) * d, (0.8 + (k % 4) * 0.45) * s, 0, Math.PI * 2)
      ctx.fill()
    }
  }
}
