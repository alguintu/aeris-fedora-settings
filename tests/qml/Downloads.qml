import QtQuick
import QtQuick.Window
import Quickshell
import "components" as Components

ShellRoot {
    id: root
    property int step: 0
    property real frozenPhase: 0
    function check(ok, message) {
        if (!ok) { console.error("DOWNLOADS_TEST_FAILED: " + message); Qt.exit(1) }
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) { const found = find(child, name); if (found) return found }
        return null
    }
    Window {
        id: window
        visible: true; width: 305; height: 97
        Components.DownloadMonitor { id: monitor; x: 12; y: 12; width: 281; height: 73 }
    }
    Timer {
        interval: 450; repeat: true; running: true
        onTriggered: {
            if (root.step++ === 0) {
                root.check(!monitor.ready && !monitor.animationRegistered, "unavailable is quiet")
                const header = root.find(monitor, "downloads-header")
                root.check(header && header.text === "DOWNLOADS" && header.x === 0 && header.y === 0,
                    "header pinned to top-left inset")
                root.check(header.font.pixelSize === Components.Theme.headerDetailSize, "matches network header size")
                const rate = root.find(monitor, "downloads-rate")
                root.check(rate.text === "—", "unavailable rate is not zero")
                root.check(!root.find(monitor, "downloads-completed").visible, "unknown completion count stays hidden")
                root.check(rate.formatRate(0) === "0KBs" && rate.formatRate(125000) === "125KBs"
                    && rate.formatRate(1250000) === "1.3MBs", "shared decimal byte units without slashes")
                root.check(rate.formatRate(999999) === "1.0MBs"
                    && rate.formatRate(NaN) === "—" && rate.formatRate(-1) === "—", "unit rollover and invalid values")
                for (let i = 0; i < 4; ++i) {
                    const track = root.find(monitor, "download-slot-" + i)
                    root.check(track && track.x === 0 && track.width === 281, "four full-width tracks")
                    root.check(track.height > 0 && track.height <= 8, "thin tracks beneath header")
                    if (i === 0) root.check(track.y === header.height + 6, "header-to-bars gap")
                    if (i === 3) root.check(track.y + track.height === 73, "bottom inset")
                    else root.check(root.find(monitor, "download-slot-" + (i+1)).y - track.y - track.height === 6, "uniform gaps")
                }
                monitor.sample = {ok: true, completedCount:3, downloadBytesPerSecond: 6250000, slots: [{id:"1", title:"test", progress:0.5}, null, {id:"3", title:"stream", indeterminate:true}, {id:"4", title:"waiting", progress:0, speed:0}]}
            } else if (root.step === 2) {
                const rate = root.find(monitor, "downloads-rate")
                const header = root.find(monitor, "downloads-header")
                root.check(rate.text === "6.3MBs", "combined live download speed")
                const completed = root.find(monitor, "downloads-completed")
                root.check(rate.visible && completed.visible && completed.text === "3", "positive speed and completed history shown")
                const separator = root.find(monitor, "downloads-separator")
                root.check(completed.x + completed.width === monitor.width
                    && completed.y + completed.baselineOffset === header.y + header.baselineOffset,
                    "completion count pins to the right inset on header baseline")
                root.check(separator.visible && separator.text === "·"
                    && rate.x + rate.width + 6 === separator.x
                    && separator.x + separator.width + 6 === completed.x, "speed dot count with uniform gaps")
                root.check(rate.x >= header.width + 6
                    && rate.y + rate.baselineOffset === header.y + header.baselineOffset, "right inset, header clearance and baseline")
                root.check(root.find(monitor, "download-fill-0").width === 140.5, "real progress")
                root.check(root.find(monitor, "download-fill-1").width === 0, "empty slot stays gray")
                const empty = root.find(monitor, "download-slot-1")
                const zero = root.find(monitor, "download-slot-3")
                root.check(zero.color.toString() !== empty.color.toString() && zero.color.r > empty.color.r,
                    "occupied zero-progress slot is lighter than empty")
                root.check(zero.color.toString() === root.find(monitor, "download-slot-0").color.toString()
                    && zero.color.toString() === root.find(monitor, "download-slot-2").color.toString(),
                    "all occupied tracks share a tint regardless of speed or known total")
                root.check(root.find(monitor, "download-fill-3").width === 0, "zero percent never fakes a progress fill")
                root.check(monitor.animationRegistered, "unknown total is visibly indeterminate")
                monitor.presentationActive = false
                root.frozenPhase = monitor.phase
                monitor.sample = {ok:false, slots:[null,null,null,null]}
            } else if (root.step === 3) {
                root.check(monitor.phase === root.frozenPhase && !monitor.animationRegistered, "offscreen pauses")
                root.check(monitor.ready, "offscreen freezes presentation")
                root.check(root.find(monitor, "downloads-rate").text === "6.3MBs", "offscreen speed freezes")
                root.check(root.find(monitor, "downloads-completed").text === "3", "offscreen count freezes")
                monitor.presentationActive = true
                root.check(!monitor.ready && monitor.slots.length === 0, "stale clears on return")
                root.check(root.find(monitor, "downloads-rate").text === "—", "disconnect clears rate")
                root.check(root.find(monitor, "download-slot-3").color.toString() === Components.Theme.raised.toString(),
                    "disconnected track returns to empty gray")
                root.check(!root.find(monitor, "downloads-completed").visible, "disconnect clears completed badge")
                monitor.sample = {ok:true, completedCount:3, downloadBytesPerSecond:0, slots:[]}
                root.check(!root.find(monitor, "downloads-rate").visible
                    && root.find(monitor, "downloads-completed").visible, "idle hides speed but retains completed history")
                root.check(!root.find(monitor, "downloads-separator").visible
                    && root.find(monitor, "downloads-completed").x + root.find(monitor, "downloads-completed").width === monitor.width,
                    "idle count remains right-pinned without a stray dot")
                monitor.sample = {ok:true, completedCount:0, downloadBytesPerSecond:0, slots:[]}
                root.check(!root.find(monitor, "downloads-completed").visible, "zero completion count stays hidden")
                monitor.sample = {ok:true, completedCount:0, downloadBytesPerSecond:1250000, slots:[]}
                const speedOnly = root.find(monitor, "downloads-rate")
                root.check(speedOnly.visible && speedOnly.x + speedOnly.width === monitor.width
                    && !root.find(monitor, "downloads-separator").visible, "speed alone pins right without a dot")
                monitor.sample = {ok:true, completedCount:1234, downloadBytesPerSecond:99900000, slots:[]}
                const capped = root.find(monitor, "downloads-completed")
                root.check(capped.text === "99+" && capped.x + capped.width === monitor.width
                    && root.find(monitor, "downloads-rate").x >= root.find(monitor, "downloads-header").width + 6,
                    "large histories preserve header spacing, exact count retained in tooltip")
                Components.BackendService.publish("fdm", {ok:true, slots:[]})
                root.check(Components.BackendService.fdmState.ok, "shared service caches FDM")
                Components.BackendService.disconnected()
                root.check(Components.BackendService.fdmState === null, "disconnect clears FDM cache")
                console.info("DOWNLOADS_TEST_PASSED"); Qt.quit()
            }
        }
    }
}
