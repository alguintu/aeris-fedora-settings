pragma Singleton
import QtQuick
import Quickshell

QtObject {
    id: root
    readonly property bool useNative: Quickshell.env("AERIS_DASHBOARD_BACKEND") !== "python"
    readonly property string binary: Quickshell.shellPath("bin/aeris-dashboard-backend")
    property bool connected: false
    // The shell owns the single streaming process. Remember infrequent events
    // so a tile created after the first reply doesn't wait for the next poll.
    property var awakeState: null
    property var tomatState: null
    signal eventReceived(string service, var payload)

    function publish(service, payload) {
        connected = true
        if (service === "awake") awakeState = payload
        if (service === "tomat") tomatState = payload
        eventReceived(service, payload)
    }

    function disconnected() {
        connected = false
        awakeState = null
        tomatState = null
    }

    function command(service, args) {
        if (useNative) return [binary, service].concat(args || [])
        const scripts = {rgb: "rgbctl.py", cooling: "coolingctl.py", sleep: "sleepctl.py",
            tomat: "tomatctl.py", weather: "weather.py", artwork: "media_art.py"}
        return ["python3", Quickshell.shellPath("services/" + scripts[service])].concat(args || [])
    }
}
