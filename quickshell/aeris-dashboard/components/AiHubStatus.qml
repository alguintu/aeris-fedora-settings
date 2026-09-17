import QtQuick
import Quickshell.Io

// One visible-page reader, not another permanent service or model controller.
Item {
    id: root
    property bool presentationActive: false
    property bool pollingEnabled: true
    property var state: ({})
    property bool healthy: false
    readonly property bool polling: presentationActive && pollingEnabled
    function refresh() { if (polling && !reader.running) reader.running = true }
    onPollingChanged: { if (polling) { healthy = false; refresh() } }
    Component.onCompleted: refresh()
    Process {
        id: reader
        command: [BackendService.binary, "ai", "status"]
        property bool received: false
        onStarted: { received = false; watchdog.restart() }
        stdout: SplitParser {
            onRead: data => {
                try {
                    const value = JSON.parse(data)
                    if (!Array.isArray(value.apis)) return
                    reader.received = true
                    if (root.polling) {
                        if (JSON.stringify(root.state) !== JSON.stringify(value)) root.state = value
                        root.healthy = true
                    }
                } catch (error) { console.warn("Invalid AI hub snapshot") }
            }
        }
        onExited: {
            watchdog.stop()
            if (root.polling && !received) root.healthy = false
        }
    }
    Timer { interval: 5000; repeat: true; running: root.polling; onTriggered: root.refresh() }
    Timer { id: watchdog; interval: 3000; onTriggered: reader.signal(9) }
}
