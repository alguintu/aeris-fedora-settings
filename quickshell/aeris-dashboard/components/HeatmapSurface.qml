import QtQuick
import "HeatmapFrames.js" as Frames

// One draw per grid and a 3-row color/remaining-time texture. All grids share
// the decorative clock, including color uploads, instead of separate animations.
Item {
    id: root
    property var cellColors: []
    property int columns: 10
    property int rows: 8
    property real gapX: 4
    property real gapY: 3
    property bool cpuLayout: false
    property bool animationEnabled: true
    property real transitionMs: 220
    property var frames: []
    property real elapsedMs: 0
    property real longest: 0
    property bool ready: false
    property bool pendingColors: false
    readonly property bool fallback: GraphicsInfo.api === GraphicsInfo.Software || gridShader.status === ShaderEffect.Error
    onCellColorsChanged: if (ready) pendingColors = true
    Component.onCompleted: { ready = true; pendingColors = true }
    onElapsedMsChanged: if (fallback) software.requestPaint()
    onFallbackChanged: if (ready && fallback) software.requestPaint()

    DecorativeTick {
        running: root.ready && (root.pendingColors
            || (root.animationEnabled && root.elapsedMs < root.longest))
        onTick: deltaMs => {
            if (root.animationEnabled)
                root.elapsedMs = Math.min(root.longest, root.elapsedMs + deltaMs)
            if (!root.pendingColors) return
            const packet = Frames.retarget(root.frames, root.elapsedMs, root.cellColors,
                                           root.animationEnabled ? root.transitionMs : 0)
            if (packet) {
                root.frames = packet.frames
                root.longest = packet.longest
                root.elapsedMs = 0
                // Update the texture and interpolation time in the same tick.
                // onPainted must not request another off-cadence animation frame.
                if (root.fallback) software.requestPaint()
                else colors.requestPaint()
            }
            root.pendingColors = false
        }
    }
    Canvas {
        id: colors
        width: Math.max(1, root.cellColors.length)
        height: 3
        visible: false
        smooth: false
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            for (let i = 0; i < root.frames.length; ++i) {
                const f = root.frames[i]
                ctx.fillStyle = Qt.rgba(f.from[0], f.from[1], f.from[2], f.from[3])
                ctx.fillRect(i, 0, 1, 1)
                ctx.fillStyle = Qt.rgba(f.to[0], f.to[1], f.to[2], f.to[3])
                ctx.fillRect(i, 1, 1, 1)
                ctx.fillStyle = Qt.rgba(f.remaining / root.transitionMs, 0, 0, 1)
                ctx.fillRect(i, 2, 1, 1)
            }
        }
    }
    ShaderEffect {
        id: gridShader
        anchors.fill: parent
        visible: !root.fallback
        property var colorAtlas: colors
        property vector2d size: Qt.vector2d(width, height)
        property vector2d grid: Qt.vector2d(root.columns, root.rows)
        property vector2d gaps: Qt.vector2d(root.gapX, root.gapY)
        property real cellCount: Math.max(1, root.cellColors.length)
        property real cpuLayout: root.cpuLayout ? 1 : 0
        property real elapsedMs: root.elapsedMs
        property real transitionMs: root.transitionMs
        property real pixelRatio: Screen.devicePixelRatio
        property color borderColor: Theme.border
        property color surfaceColor: Theme.surface
        fragmentShader: Qt.resolvedUrl("../shaders/heatmap.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) console.warn("Heatmap shader:", log)
    }
    Canvas {
        id: software
        anchors.fill: parent
        visible: root.fallback
        onVisibleChanged: if (visible) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cells = Frames.cells(width, height, root.columns, root.rows, root.gapX, root.gapY, root.cpuLayout)
            function rounded(x, y, w, h, r) {
                ctx.beginPath(); ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y)
                ctx.quadraticCurveTo(x + w, y, x + w, y + r); ctx.lineTo(x + w, y + h - r)
                ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h); ctx.lineTo(x + r, y + h)
                ctx.quadraticCurveTo(x, y + h, x, y + h - r); ctx.lineTo(x, y + r)
                ctx.quadraticCurveTo(x, y, x + r, y); ctx.closePath()
            }
            for (let i = 0; i < Math.min(cells.length, root.frames.length); ++i) {
                const c = cells[i], rgb = Frames.sample(root.frames[i], root.elapsedMs)
                if (root.cpuLayout) {
                    if (i % 2 === 0) {
                        ctx.fillStyle = Theme.surface
                        rounded(c.x - 1, c.y - 1, c.w * 2 + 2, c.h + 2, 3); ctx.fill()
                    }
                    ctx.fillStyle = Qt.rgba(rgb[0], rgb[1], rgb[2], rgb[3])
                    ctx.beginPath(); ctx.moveTo(c.x + c.tl, c.y); ctx.lineTo(c.x + c.w - c.tr, c.y)
                    ctx.lineTo(c.x + c.w, c.y + c.tr); ctx.lineTo(c.x + c.w, c.y + c.h - c.br)
                    ctx.lineTo(c.x + c.w - c.br, c.y + c.h); ctx.lineTo(c.x + c.bl, c.y + c.h)
                    ctx.lineTo(c.x, c.y + c.h - c.bl); ctx.lineTo(c.x, c.y + c.tl); ctx.closePath(); ctx.fill()
                } else {
                    ctx.fillStyle = Theme.border
                    rounded(c.x, c.y, c.w, c.h, 2); ctx.fill()
                    ctx.fillStyle = Qt.rgba(rgb[0], rgb[1], rgb[2], rgb[3])
                    rounded(c.x + 1, c.y + 1, c.w - 2, c.h - 2, 1); ctx.fill()
                }
            }
        }
    }
}
