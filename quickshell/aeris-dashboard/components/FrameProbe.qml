import QtQuick
import QtQuick.Window

// Opt-in frame-swap timing, disconnected completely during normal use.
Item {
    id: root
    property bool measuring: false
    property var intervals: []
    property double startedAt: 0
    property double previousAt: 0
    function start() {
        intervals = []
        previousAt = 0
        startedAt = Date.now()
        measuring = true
    }
    function stop() {
        measuring = false
        const sorted = intervals.slice().sort((a, b) => a - b)
        const count = sorted.length
        if (!count) return {intervals: 0}
        const mean = sorted.reduce((a, b) => a + b, 0) / count
        return {intervals: count, elapsedMs: Date.now() - startedAt,
            meanMs: mean, fps: 1000 / mean,
            p95Ms: sorted[Math.ceil(count * 0.95) - 1],
            p99Ms: sorted[Math.ceil(count * 0.99) - 1], maxMs: sorted[count - 1],
            over25Ms: sorted.filter(ms => ms > 25).length}
    }
    Connections {
        target: root.Window.window
        enabled: root.measuring
        function onFrameSwapped() {
            const now = Date.now()
            if (root.previousAt) root.intervals.push(now - root.previousAt)
            root.previousAt = now
        }
    }
    // Safety net if a profiling client disappears without stopping its probe.
    Timer { interval: 60000; running: root.measuring; onTriggered: root.measuring = false }
}
