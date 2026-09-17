import QtQuick
import QtQuick.Window
import Quickshell
import "components" as Components

ShellRoot {
    id: root
    property int step: 0
    property real pausedTime: 0
    function check(ok, message) {
        if (!ok) { console.error("NETWORK_TEST_FAILED: " + message); Qt.exit(1) }
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) { const found = find(child, name); if (found) return found }
        return null
    }
    Window {
        id: window
        visible: true; width: 305; height: 97
        color: Components.Theme.surface
        Components.NetworkMonitor {
            id: network
            x: 12; y: 12; width: 281; height: 73
            healthy: true
            sample: ({ok: true, ready: true, rxBytesPerSecond: 0, txBytesPerSecond: 0, interfaces: ["eth0"]})
        }
    }
    Timer {
        interval: 150; repeat: true; running: true
        onTriggered: {
            if (root.step++ === 0) {
                root.check(!network.animationRegistered && Components.DecorativeClock.users === 0, "zero traffic does not animate")
                root.check(network.intensity(-100) === 0 && network.intensity(1e12) === 1, "activity scale is bounded")
                root.check(root.find(network, "network-receive-rate").text === "↓0KBs"
                    && root.find(network, "network-send-rate").text === "↑0KBs", "directional idle rates")
                network.sample = {ok: true, ready: true, rxBytesPerSecond: 5242880, txBytesPerSecond: 1048576}
                root.check(network.receiveTarget > network.sendTarget, "separate receive/send amplitude")
            } else if (root.step === 2) {
                root.check(root.find(network, "network-receive-rate").text === "↓5.2MBs"
                    && root.find(network, "network-send-rate").text === "↑1.0MBs", "live receive and send rates")
                root.check(network.animationRegistered && network.receiveLevel > 0
                    && network.receiveLevel < network.receiveTarget, "activity eases into motion")
                root.check(Components.DecorativeClock.users === 1, "reuse one shared clock subscription")
                if (Quickshell.env("AERIS_TEST_RHI")) root.check(network.shaderStatus !== ShaderEffect.Error, "GPU shader loads")
                network.presentationActive = false
                root.pausedTime = network.elapsed
                network.sample = {ok: true, ready: true, rxBytesPerSecond: 0, txBytesPerSecond: 0}
            } else if (root.step === 3) {
                root.check(!network.animationRegistered && network.elapsed === root.pausedTime,
                    "offscreen animation pauses")
                root.check(network.shownSample.rxBytesPerSecond === 5242880, "offscreen presentation freezes")
                root.check(root.find(network, "network-receive-rate").text === "↓5.2MBs", "offscreen rate freezes")
                network.presentationActive = true
                root.check(network.receiveTarget === 0, "return follows current telemetry")
                // Advance the existing clock to test decay without sleeping seconds.
                for (let i = 0; i < 100; ++i) Components.DecorativeClock.tick(100)
                root.check(network.receiveLevel === 0 && network.sendLevel === 0 && !network.animationRegistered,
                    "quiet wave settles and releases the clock")
                network.healthy = false
                network.sample = {ok: true, ready: true, rxBytesPerSecond: 1e9, txBytesPerSecond: 1e9}
                root.check(!network.ready && network.receiveTarget === 0, "offline never invents activity")
                root.check(root.find(network, "network-receive-rate").text === "↓—", "unavailable rate is not zero")
                network.healthy = true
                network.sample = {ok: true, ready: true, rxBytesPerSecond: 99900000, txBytesPerSecond: 99900000}
            } else if (root.step === 4) {
                const rates = root.find(network, "network-rates")
                const header = root.find(network, "network-header")
                root.check(rates.x + rates.width === network.width && rates.x >= header.width + 6,
                    "long receive/send rates fit without shrinking or overlapping: " + JSON.stringify({x:rates.x,width:rates.width,header:header.width,available:network.width}))
                root.check(rates.y + rates.baselineOffset === header.y + header.baselineOffset, "header baseline alignment")
            } else if (root.step === 6) {
                const output = Quickshell.env("AERIS_NETWORK_TEST_IMAGE")
                if (output) window.contentItem.grabToImage(result => {
                    root.check(result.saveToFile(output), "save activity preview")
                    console.info("NETWORK_TEST_PASSED"); Qt.quit()
                })
                else { console.info("NETWORK_TEST_PASSED"); Qt.quit() }
            }
        }
    }
}
