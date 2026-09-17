import QtQuick

// Input only: the full tile's cropped half-dial or Home's circular ring.
// No timer or IPC per movement. Emit one guarded seek on a completed drag.
MouseArea {
    id: root
    property int duration: 1500
    property real progress: 0
    property string revision: ""
    property bool circular: false
    property real lastRingAngle: 0
    property real previewProgress: progress
    property bool adjusting: false
    property bool moved: false
    property point startPoint
    property string capturedRevision: ""
    property int capturedDuration: 0
    readonly property int previewElapsed: Math.min(Math.max(0, capturedDuration - 1),
        Math.max(0, Math.round(previewProgress * capturedDuration)))
    signal committed(int elapsedSeconds, string expectedRevision)
    preventStealing: true
    acceptedButtons: Qt.LeftButton
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    function designPoint(px, py) { return Qt.point(px * 296 / width, py * 424 / height) }
    function hit(px, py) {
        if (circular) {
            const radius = Math.min(width, height) / 2 - 3
            return Math.abs(Math.hypot(px - width / 2, py - height / 2) - radius) <= 22
        }
        const p = designPoint(px, py)
        return p.x >= 12 && Math.abs(Math.hypot(p.x - 24, p.y - 180) - 158) <= 26
    }
    function begin(px, py) {
        if (!enabled || duration <= 1 || !hit(px, py)) return false
        capturedRevision = revision
        capturedDuration = duration
        startPoint = Qt.point(px, py)
        previewProgress = progress
        lastRingAngle = Math.atan2(py - height / 2, px - width / 2)
        moved = false
        adjusting = true
        return true
    }
    function update(px, py) {
        if (!adjusting) return
        if (!moved && Math.hypot(px - startPoint.x, py - startPoint.y) < 8) return
        moved = true
        if (circular) {
            // Relative motion prevents a jump when grabbing away from the tip.
            // Unwrap the top seam and clamp; never wrap 0% straight to 100%.
            if (Math.hypot(px - width / 2, py - height / 2) < 8) return
            const angle = Math.atan2(py - height / 2, px - width / 2)
            let delta = angle - lastRingAngle
            if (delta > Math.PI) delta -= 2 * Math.PI
            if (delta < -Math.PI) delta += 2 * Math.PI
            lastRingAngle = angle
            // This ring displays remaining time, the inverse of elapsed.
            previewProgress = Math.max(0, Math.min(1, previewProgress - delta / (2 * Math.PI)))
            return
        }
        const p = designPoint(px, py)
        const angle = Math.atan2(p.y - 180, Math.max(0, p.x - 24))
        previewProgress = Math.max(0, Math.min(1, (angle + Math.PI / 2) / Math.PI))
    }
    function finish(cancelled) {
        if (!adjusting) return
        const apply = moved && !cancelled
        const elapsed = previewElapsed
        const expected = capturedRevision
        adjusting = false
        moved = false
        if (apply) committed(elapsed, expected)
    }
    onPressed: mouse => { mouse.accepted = begin(mouse.x, mouse.y) }
    onPositionChanged: mouse => update(mouse.x, mouse.y)
    onReleased: mouse => { update(mouse.x, mouse.y); finish(false) }
    onCanceled: finish(true)
    onEnabledChanged: if (!enabled) finish(true)
    Component.onDestruction: finish(true)
}
