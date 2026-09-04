pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property var state: ({phase: "Idle", paused: false, remaining: 1500,
                          duration: 1500, progress: 0, session: 1, sessions: 4})
    property bool healthy: false
    property bool pending: false
    property string errorText: ""
    property string commandError: ""
    property bool pickerOpen: false
    property bool scrubbing: false
    signal commandCompleted(bool success)
    readonly property bool idle: state.phase === "Idle"

    function apply(data) {
        try {
            const result = typeof data === "string" ? JSON.parse(data) : data
            healthy = result.ok === true
            errorText = result.error || ""
            if (healthy) state = result
        } catch (error) {
            healthy = false
            errorText = "Invalid Tomat response"
        }
    }

    function send(action) {
        if (!healthy || pending || ["toggle", "reset", "skip"].indexOf(action) < 0) return
        if (idle && action !== "toggle") return
        pending = true
        commandError = ""
        command.command = BackendService.command("tomat", [action])
        command.running = true
    }

    function chooseTemplate(identifier, mode) {
        if (!healthy || pending || ["next", "now"].indexOf(mode) < 0) return
        pending = true
        commandError = ""
        command.command = BackendService.command("tomat", ["select", identifier, mode])
        command.running = true
    }

    function seek(elapsedSeconds, revision) {
        if (!BackendService.useNative || !healthy || pending || idle || !state.canSeek) return
        if (!Number.isInteger(elapsedSeconds) || elapsedSeconds < 0 || elapsedSeconds >= state.duration) return
        pending = true
        commandError = ""
        command.command = BackendService.command("tomat", ["seek", String(elapsedSeconds), String(revision)])
        command.running = true
    }

    Component.onCompleted: {
        if (BackendService.useNative && BackendService.tomatState) apply(BackendService.tomatState)
    }
    Connections {
        target: BackendService
        function onEventReceived(service, payload) {
            if (service === "tomat" && !root.pending) root.apply(payload)
        }
        function onConnectedChanged() {
            if (BackendService.useNative && !BackendService.connected) root.healthy = false
        }
    }
    Process {
        id: watcher
        command: ["python3", Quickshell.shellPath("services/tomatctl.py"), "watch"]
        running: !BackendService.useNative
        stdout: SplitParser { onRead: data => { if (!root.pending) root.apply(data) } }
        onExited: {
            root.healthy = false
            if (!BackendService.useNative) reconnect.restart()
        }
    }
    Timer {
        id: reconnect
        interval: 2000
        onTriggered: { if (!BackendService.useNative) watcher.running = true }
    }
    Process {
        id: command
        stdout: SplitParser {
            onRead: data => {
                try {
                    const result = JSON.parse(data)
                    if (result.ok) root.apply(data)
                    else root.commandError = result.error || "Tomat command failed"
                } catch (error) { root.commandError = "Invalid Tomat response" }
            }
        }
        onExited: (code, status) => {
            root.pending = false
            if (code !== 0 && !root.commandError) root.commandError = "Tomat command failed"
            root.commandCompleted(code === 0 && !root.commandError)
        }
    }
    IpcHandler {
        target: "pomodoro"
        function toggle(): void { root.send("toggle") }
        function reset(): void { root.send("reset") }
        function skip(): void { root.send("skip") }
        function status(): string { return JSON.stringify(root.state) }
        function chooseTemplate(identifier: string, mode: string): void { root.chooseTemplate(identifier, mode) }
        function showTemplates(open: bool): void { root.pickerOpen = open }
    }
}
