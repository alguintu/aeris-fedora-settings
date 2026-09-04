pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property var state: ({available: false, ok: false, description: "Loading weather"})
    property double now: Date.now() / 1000
    property string previewMode: ""
    // Session-only diagnostics: no persisted preference or live-weather mutation.
    property string renderingBackend: "accelerated"
    property real fixedAnimationTime: -1
    readonly property var previews: ({
        "clear": ["Clear", "white-balance-sunny"],
        "night": ["Clear night", "moon-waning-crescent"],
        "partly-cloudy": ["Clouds", "weather-partly-cloudy"],
        "fog": ["Fog", "weather-fog"],
        "rain": ["Rain", "weather-rainy"],
        "snow": ["Snow", "weather-snowy"],
        "storm": ["Storm", "weather-lightning-rainy"]
    })
    readonly property bool available: state.available === true && now - state.observedAt < 21600
    readonly property bool stale: !previewMode && available && (!state.ok || now - state.fetchedAt > 1800
                                               || now - state.observedAt > 3600)
    readonly property string temperature: previewMode ? "--°C" : available ? Math.round(state.temperature) + "°C" : "--°C"
    readonly property string description: previewMode ? previews[previewMode][0] + " · preview" : available ? state.description
        : state.description === "Set location" ? "Set location" : "Unavailable"
    readonly property string icon: previewMode ? previews[previewMode][1] : available ? state.icon : "weather-cloudy"
    readonly property string condition: previewMode || (available ? state.condition : "unknown")

    function preview(mode) {
        if (mode !== "" && !previews[mode]) return
        previewMode = mode
        if (mode) previewTimeout.restart()
        else previewTimeout.stop()
    }
    // Presentation-only, automatically cleared even if a demo is interrupted.
    Timer { id: previewTimeout; interval: 30000; onTriggered: root.previewMode = "" }

    function refresh(force) {
        if (fetcher.running) return
        // Limit repeated touch refreshes while still allowing quick offline recovery.
        if (force && now - lastRequest < 60) return
        lastRequest = now
        fetcher.command = BackendService.command("weather", [])
        if (force) fetcher.command = fetcher.command.concat(["--refresh"])
        fetcher.running = true
    }
    property double lastRequest: 0
    Component.onCompleted: refresh(false)
    Timer {
        interval: 30000; running: true; repeat: true
        onTriggered: root.now = Date.now() / 1000
    }
    Timer {
        id: refreshTimer
        interval: root.state.ok ? 600000 : 120000
        onTriggered: root.refresh(true)
    }
    Process {
        id: fetcher
        property bool received: false
        onStarted: { received = false; watchdog.restart() }
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.state = JSON.parse(data)
                    root.now = Date.now() / 1000
                    fetcher.received = true
                } catch (error) { console.warn("Invalid weather response") }
            }
        }
        onExited: {
            watchdog.stop()
            if (!received) root.state = Object.assign({}, root.state, {ok: false})
            refreshTimer.restart()
        }
    }
    Timer {
        id: watchdog
        interval: 20000
        onTriggered: fetcher.signal(9)
    }
    IpcHandler {
        target: "weather"
        function status(): string { return JSON.stringify(root.state) }
        function refresh(): void { root.refresh(true) }
        function preview(mode: string): void { root.preview(mode) }
        function renderer(mode: string): void {
            if (mode === "accelerated" || mode === "canvas") root.renderingBackend = mode
        }
        function freeze(seconds: real): void { root.fixedAnimationTime = Math.max(-1, seconds) }
    }
}
