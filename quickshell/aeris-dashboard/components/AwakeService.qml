pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string mode: "normal"
    property bool healthy: false
    property bool pending: false
    property string requestedMode: "normal"
    property string errorText: ""
    readonly property bool supportsSystem: BackendService.useNative

    function applyStatus(data) {
        try {
            const status = typeof data === "string" ? JSON.parse(data) : data
            healthy = status.ok === true
            if (healthy) mode = status.mode || (status.active ? "full" : "normal")
            errorText = status.error || ""
        } catch (error) {
            healthy = false
            errorText = "Unable to read sleep inhibitor status"
        }
    }

    function select(next) {
        if (!healthy || pending || !["normal", "system", "full"].includes(next)
            || (next === "system" && !supportsSystem) || next === mode) return
        requestedMode = next
        pending = true
        errorText = ""
        const argument = BackendService.useNative ? next : next === "full" ? "on" : "off"
        commandProcess.command = BackendService.command("sleep", ["set", argument])
        commandProcess.running = true
    }

    Component.onCompleted: {
        if (BackendService.awakeState) applyStatus(BackendService.awakeState)
    }
    property Connections backendConnection: Connections {
        target: BackendService
        function onEventReceived(service, payload) {
            if (service === "awake" && !root.pending) root.applyStatus(payload)
        }
        function onConnectedChanged() {
            if (BackendService.useNative && !BackendService.connected) root.healthy = false
        }
    }
    property Process commandProcess: Process {
        id: commandProcess
        property bool replied: false
        onRunningChanged: { if (running) replied = false }
        stdout: SplitParser {
            onRead: data => { commandProcess.replied = true; root.applyStatus(data) }
        }
        onExited: {
            if (!replied) {
                root.healthy = false
                root.errorText = "The sleep controller did not respond"
            }
            root.pending = false
        }
    }
    // Historical rollback only. The new sleep-only mode is implemented in Rust.
    property Process legacyStatus: Process {
        id: legacyStatus
        running: !BackendService.useNative
        command: ["python3", Quickshell.shellPath("services/sleepctl.py"), "watch"]
        stdout: SplitParser { onRead: data => { if (!root.pending) root.applyStatus(data) } }
        onExited: { root.healthy = false; if (!BackendService.useNative) retry.start() }
    }
    property Timer retry: Timer {
        id: retry
        interval: 2000
        onTriggered: { if (!BackendService.useNative) legacyStatus.running = true }
    }
}
