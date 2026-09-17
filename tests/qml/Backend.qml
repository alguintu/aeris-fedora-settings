import QtQuick
import Quickshell
import "components" as Components

// Offscreen integration test. The shell's real streaming process is not loaded.
ShellRoot {
    id: root
    function check(ok, message) {
        if (!ok) { console.error("BACKEND_TEST_FAILED: " + message); Qt.exit(1) }
    }
    Components.KeepAwakeButton { id: awake }
    Component { id: lateAwake; Components.KeepAwakeButton {} }
    Timer {
        interval: 100; running: true
        onTriggered: {
            const backend = Components.BackendService
            root.check(backend.useNative, "native default")
            for (const service of ["rgb", "cooling", "sleep", "tomat", "weather", "artwork"]) {
                const cmd = backend.command(service, ["status"])
                root.check(cmd[0].endsWith("bin/aeris-dashboard-backend") && cmd[1] === service && cmd[2] === "status",
                    service + " command routed to Rust")
            }
            // Force the lazy singleton to exist before publishing its first state.
            root.check(!Components.TomatService.healthy, "timer awaits confirmed status")
            backend.publish("tomat", {ok: true, phase: "Break", paused: true, remaining: 300})
            root.check(Components.TomatService.healthy && Components.TomatService.state.remaining === 300, "timer event delivered")
            backend.publish("awake", {ok: true, active: false})
            const service = Components.AwakeService
            root.check(service.healthy && awake.mode === "normal", "awake event delivered")
            service.requestedMode = "system"; service.pending = true
            root.check(awake.switchMode === "system" && awake.mode === "normal", "position moves before confirmed color")
            backend.publish("awake", {ok: true, active: true})
            root.check(awake.mode === "normal", "pending request ignores racing watcher")
            service.pending = false
            backend.publish("awake", {ok: true, active: true, mode: "system"})
            root.check(awake.mode === "system", "confirmed state accepted")
            const late = lateAwake.createObject(root)
            root.check(late.sleepService === service && late.mode === "system", "late tile shares confirmed service")
            backend.disconnected()
            root.check(!service.healthy && !late.sleepService.healthy && !Components.TomatService.healthy, "disconnect invalidates every consumer")
            root.check(backend.awakeState === null && backend.tomatState === null, "disconnect clears stale cache")
            backend.publish("awake", {ok: true, active: true})
            root.check(service.healthy && late.sleepService.healthy && awake.mode === "full", "restart recovers existing consumers")
            late.destroy()
            console.warn("BACKEND_TEST_PASSED")
            finish.start()
        }
    }
    Timer { id: finish; interval: 100; onTriggered: Qt.quit() }
    Timer { interval: 5000; running: true; onTriggered: Qt.exit(2) }
}
