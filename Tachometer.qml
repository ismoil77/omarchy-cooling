import QtQuick
import qs.Commons

// Compact 270-degree analog tachometer dial (arc track, redline zone,
// progress arc, and sweeping needle) scaled to bar or panel sizes.
Item {
  id: root

  property real fraction: 0
  property real redline: 0.85
  property color color: Color.foreground
  property color trackColor: Util.alpha(color, 0.24)
  property color accentColor: color
  property color dangerColor: Color.urgent
  property bool animations: true

  property real animatedFraction: Math.max(0, Math.min(1, fraction))
  Behavior on animatedFraction {
    NumberAnimation {
      duration: root.animations ? Style.duration(260) : 0
      easing.type: Easing.OutCubic
    }
  }

  onAnimatedFractionChanged: if (visible) canvas.requestPaint()
  onRedlineChanged: if (visible) canvas.requestPaint()
  onColorChanged: if (visible) canvas.requestPaint()
  onTrackColorChanged: if (visible) canvas.requestPaint()
  onAccentColorChanged: if (visible) canvas.requestPaint()
  onDangerColorChanged: if (visible) canvas.requestPaint()
  onVisibleChanged: if (visible) canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    onWidthChanged: if (root.visible) requestPaint()
    onHeightChanged: if (root.visible) requestPaint()

    onPaint: {
      var w = width, h = height
      var s = Math.min(w, h)
      if (s <= 0) return
      var ctx = getContext("2d")
      ctx.reset()

      var cx = w / 2
      var cy = h / 2
      var stroke = Math.max(1.5, s * 0.13)
      var r = (s - stroke) / 2 - 0.5
      if (r <= 1) return

      var frac = Math.max(0, Math.min(1, root.animatedFraction))
      var red = Math.max(0, Math.min(1, root.redline))
      var startAngle = 0.75 * Math.PI
      var sweep = 1.5 * Math.PI
      var endAngle = startAngle + sweep
      var redStart = startAngle + red * sweep
      var valAngle = startAngle + frac * sweep
      var inRed = frac >= red

      // Base track up to redline
      ctx.beginPath()
      ctx.arc(cx, cy, r, startAngle, redStart, false)
      ctx.strokeStyle = Qt.rgba(root.trackColor.r, root.trackColor.g, root.trackColor.b, root.trackColor.a)
      ctx.lineWidth = stroke
      ctx.lineCap = "round"
      ctx.stroke()

      // Redline zone on the high-RPM end
      ctx.beginPath()
      ctx.arc(cx, cy, r, redStart, endAngle, false)
      ctx.strokeStyle = Qt.rgba(root.dangerColor.r, root.dangerColor.g, root.dangerColor.b, 0.42)
      ctx.lineWidth = stroke
      ctx.lineCap = "round"
      ctx.stroke()

      // Subtle radial ticks when there is room
      if (s >= 24) {
        ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.35)
        ctx.lineWidth = Math.max(1, s * 0.05)
        for (var t = 0; t <= 4; t++) {
          var ta = startAngle + (t / 4) * sweep
          var rIn = r - stroke * 1.15
          var rOut = r - stroke * 0.65
          ctx.beginPath()
          ctx.moveTo(cx + Math.cos(ta) * rIn, cy + Math.sin(ta) * rIn)
          ctx.lineTo(cx + Math.cos(ta) * rOut, cy + Math.sin(ta) * rOut)
          ctx.stroke()
        }
      }

      // Active arc up to current RPM
      if (frac > 0.005) {
        var active = inRed ? root.dangerColor : root.accentColor
        ctx.beginPath()
        ctx.arc(cx, cy, r, startAngle, valAngle, false)
        ctx.strokeStyle = Qt.rgba(active.r, active.g, active.b, active.a)
        ctx.lineWidth = stroke
        ctx.lineCap = "round"
        ctx.stroke()
      }

      // Needle and center pivot hub
      var needleColor = inRed ? root.dangerColor : root.color
      var nx = cx + Math.cos(valAngle) * (r * 0.78)
      var ny = cy + Math.sin(valAngle) * (r * 0.78)
      ctx.beginPath()
      ctx.moveTo(cx, cy)
      ctx.lineTo(nx, ny)
      ctx.strokeStyle = Qt.rgba(needleColor.r, needleColor.g, needleColor.b, needleColor.a)
      ctx.lineWidth = Math.max(1.3, s * 0.10)
      ctx.lineCap = "round"
      ctx.stroke()

      ctx.beginPath()
      ctx.arc(cx, cy, Math.max(1.3, s * 0.11), 0, 2 * Math.PI, false)
      ctx.fillStyle = Qt.rgba(needleColor.r, needleColor.g, needleColor.b, needleColor.a)
      ctx.fill()
    }
  }
}
