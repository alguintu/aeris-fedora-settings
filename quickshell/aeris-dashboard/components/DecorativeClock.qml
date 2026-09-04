pragma Singleton
import QtQuick

// One demand-driven clock for decorative motion, never for input/drag handling.
Item {
    id: root
    property int framesPerSecond: 60
    property int users: 0
    property int ticks: 0
    property double lastAt: 0
    signal tick(real deltaMs)

    function attach() { users += 1 }
    function detach() { users = Math.max(0, users - 1) }

    Timer {
        // Qt Quick timers follow its animation driver. 32ms fits two 60Hz
        // frames; 33ms can overshoot that boundary and slip to three frames.
        interval: root.framesPerSecond === 60 ? 16 : 32
        repeat: true
        running: root.users > 0
        onRunningChanged: root.lastAt = Date.now()
        onTriggered: {
            const now = Date.now()
            // No wall-clock jumps or catch-up after suspend/stalls.
            const delta = Math.max(0, Math.min(100, now - root.lastAt))
            root.lastAt = now
            root.ticks += 1
            root.tick(delta)
        }
    }
}
