import QtQuick

Canvas {
    id: themeCanvas
    property string themeId: "aurora"
    property color primaryColor: "#081C24"
    property color secondaryColor: "#10B981"
    property color accentColor: "#38BDF8"

    onThemeIdChanged: requestPaint()
    onPrimaryColorChanged: requestPaint()
    onSecondaryColorChanged: requestPaint()
    onAccentColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        var w = width
        var h = height
        if (w <= 0 || h <= 0) return

        ctx.clearRect(0, 0, w, h)
        var grad = ctx.createLinearGradient(0, 0, w, h)
        grad.addColorStop(0, primaryColor.toString())
        grad.addColorStop(1, secondaryColor.toString())
        ctx.fillStyle = grad
        ctx.fillRect(0, 0, w, h)

        var minDim = Math.min(w, h)
        ctx.save()

        if (themeId === "aurora") {
            ctx.globalAlpha = 0.45
            ctx.fillStyle = accentColor.toString()
            ctx.beginPath()
            ctx.moveTo(0, h * 0.45)
            ctx.bezierCurveTo(w * 0.28, h * 0.15, w * 0.65, h * 0.65, w, h * 0.22)
            ctx.lineTo(w, h * 0.55)
            ctx.bezierCurveTo(w * 0.62, h * 0.85, w * 0.30, h * 0.36, 0, h * 0.70)
            ctx.closePath()
            ctx.fill()
        } else if (themeId === "sunset_peaks") {
            ctx.globalAlpha = 0.85
            ctx.fillStyle = accentColor.toString()
            ctx.beginPath()
            ctx.arc(w * 0.5, h * 0.34, minDim * 0.18, 0, Math.PI * 2)
            ctx.fill()

            ctx.globalAlpha = 0.36
            ctx.fillStyle = "#000000"
            ctx.beginPath()
            ctx.moveTo(0, h)
            ctx.lineTo(w * 0.34, h * 0.52)
            ctx.lineTo(w * 0.64, h * 0.76)
            ctx.lineTo(w * 0.86, h * 0.48)
            ctx.lineTo(w, h * 0.72)
            ctx.lineTo(w, h)
            ctx.closePath()
            ctx.fill()
        } else if (themeId === "starry_night") {
            ctx.fillStyle = "#FFFFFF"
            for (var s = 0; s < 22; ++s) {
                var sx = ((s * 73 + 19) % 100) / 100.0 * w
                var sy = ((s * 41 + 11) % 85) / 100.0 * h
                var sr = (s % 4 === 0) ? minDim * 0.015 : minDim * 0.008
                ctx.globalAlpha = (s % 3 === 0) ? 0.85 : 0.45
                ctx.beginPath()
                ctx.arc(sx, sy, sr, 0, Math.PI * 2)
                ctx.fill()
            }
        } else if (themeId === "ocean_waves" || themeId === "desert_dunes") {
            ctx.fillStyle = accentColor.toString()
            for (var r = 0; r < 3; ++r) {
                var base = h * (0.50 + r * 0.14)
                ctx.globalAlpha = 0.18 + r * 0.08
                ctx.beginPath()
                ctx.moveTo(0, base)
                ctx.bezierCurveTo(w * 0.30, base - h * 0.09, w * 0.65, base + h * 0.09, w, base - h * 0.03)
                ctx.lineTo(w, h)
                ctx.lineTo(0, h)
                ctx.closePath()
                ctx.fill()
            }
        } else if (themeId === "cyber_grid") {
            var horizon = h * 0.54
            ctx.globalAlpha = 0.75
            ctx.strokeStyle = accentColor.toString()
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.moveTo(0, horizon)
            ctx.lineTo(w, horizon)
            ctx.stroke()

            ctx.globalAlpha = 0.45
            ctx.strokeStyle = secondaryColor.toString()
            ctx.lineWidth = 1.5
            for (var i = -3; i <= 3; ++i) {
                ctx.beginPath()
                ctx.moveTo(w * 0.5 + i * w * 0.06, horizon)
                ctx.lineTo(w * 0.5 + i * w * 0.24, h)
                ctx.stroke()
            }
        } else if (themeId === "neon_horizon") {
            ctx.globalAlpha = 0.85
            ctx.fillStyle = accentColor.toString()
            ctx.beginPath()
            ctx.arc(w * 0.5, h * 0.46, minDim * 0.22, 0, Math.PI * 2)
            ctx.fill()
            ctx.globalAlpha = 0.78
            ctx.fillStyle = primaryColor.toString()
            ctx.fillRect(0, h * 0.56, w, h * 0.44)
        } else {
            ctx.fillStyle = accentColor.toString()
            for (var k = 0; k < 10; ++k) {
                var kx = (((k * 83 + 15) % 90) + 5) / 100.0 * w
                var ky = (((k * 47 + 21) % 86) + 6) / 100.0 * h
                var kr = minDim * (0.06 + (k % 4) * 0.03)
                ctx.globalAlpha = 0.24
                ctx.beginPath()
                ctx.arc(kx, ky, kr, 0, Math.PI * 2)
                ctx.fill()
            }
        }
        ctx.restore()
    }
}
