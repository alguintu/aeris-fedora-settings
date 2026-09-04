import QtQuick

// Input only: map the same cropped half-dial geometry as PomodoroTile's canvas.
// No timer or IPC per movement. Emit one guarded seek on a completed drag.
MouseArea {
    id: root
    property int duration: 1500
    property real progress: 0
    property string revision: ""
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
        const p = designPoint(px, py)
        return p.x >= 12 && Math.abs(Math.hypot(p.x - 24, p.y - 180) - 158) <= 26
    }
    function begin(px, py) {
        if (!enabled || duration <= 1 || !hit(px, py)) return false
        capturedRevision = revision
        capturedDuration = duration
        startPoint = Qt.point(px, py)
        previewProgress = progress
        moved = false
        adjusting = true
        return true
    }
    function update(px, py) {
        if (!adjusting) return
        if (!moved && Math.hypot(px - startPoint.x, py - startPoint.y) < 8) return
        moved = true
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
