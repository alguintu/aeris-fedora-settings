import QtQuick

Item {
    id: root
    property bool running: false
    property bool ready: false
    property bool registered: false
    signal tick(real deltaMs)

    function sync() {
        if (!ready || running === registered) return
        registered = running
        if (registered) DecorativeClock.attach()
        else DecorativeClock.detach()
    }
    onRunningChanged: sync()
    Component.onCompleted: { ready = true; sync() }
    Component.onDestruction: if (registered) DecorativeClock.detach()
    Connections {
        target: DecorativeClock
        enabled: root.registered
        function onTick(deltaMs) { root.tick(deltaMs) }
    }
}
