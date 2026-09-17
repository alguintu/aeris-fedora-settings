import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "components" as Components

ShellRoot {
    id: root
    property var requests: []
    function check(ok, message) {
        if (!ok) { console.error("AWAKE_TEST_FAILED: " + message); Qt.exit(1) }
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    QtObject {
        id: fake
        property string mode: "normal"
        property string requestedMode: "normal"
        property bool pending: false
        property bool healthy: true
        property bool supportsSystem: true
        property string errorText: ""
        function select(next) {
            if (next === mode) return
            root.requests = root.requests.concat([next])
            requestedMode = next
            pending = true
        }
    }
    Window {
        visible: true; width: 94; height: 206
        Components.KeepAwakeButton { id: tile; anchors.fill: parent; sleepService: fake }
    }
    TestCase { id: events; name: "AwakeInput"; when: false }
    Timer {
        interval: 250; running: true
        onTriggered: {
            const track = root.find(tile, "awake-track")
            const thumb = root.find(tile, "awake-thumb")
            const top = root.find(tile, "awake-full")
            const middle = root.find(tile, "awake-system")
            const bottom = root.find(tile, "awake-normal")
            root.check(track.x === 12 && track.y === 12 && track.width === 70 && track.height === 182,
                "same 1x2 bounds, uniform inset, top and bottom pinned")
            root.check(track.border.width === 0 && track.radius === Components.Theme.radius,
                "borderless rounded rectangular track")
            root.check(thumb.x === 0 && thumb.width === track.width && thumb.height === track.height / 3
                && thumb.radius === track.radius,
                "highlight fills its third of the track without extra padding")
            for (const choice of [top, middle, bottom])
                root.check(choice.width >= 44 && choice.height >= 44, "full-size touch targets")
            root.check(Math.abs(thumb.y + thumb.height - track.height) < 0.1, "normal flush with bottom stop")
            const normalColor = tile.accent.toString()
            events.mouseClick(middle, 35, 30, Qt.LeftButton)
            root.check(root.requests.length === 1 && root.requests[0] === "system", "middle selects sleep-only")
            root.check(tile.switchMode === "system" && tile.mode === "normal"
                && tile.accent.toString() === normalColor, "optimistic position, confirmed color")
            events.wait(220)
            root.check(Math.abs(thumb.y - (track.height - thumb.height) / 2) < 0.1, "thumb centers on middle icon")
            events.mouseClick(top, 35, 30, Qt.LeftButton)
            root.check(root.requests.length === 1, "pending prevents another request")
            fake.pending = false
            fake.errorText = "Failed"
            root.check(tile.switchMode === "normal", "failure rolls position back")
            fake.errorText = ""
            const touch = events.touchEvent(top)
            touch.press(0, top, 35, 30).commit()
            touch.release(0, top, 35, 30).commit()
            root.check(root.requests.length === 2 && root.requests[1] === "full", "touch selects full")
            fake.mode = "full"; fake.pending = false
            events.wait(220)
            root.check(thumb.y === 0 && tile.accent.toString() !== normalColor, "confirmed full flush with top")
            events.mousePress(middle, 35, 30, Qt.LeftButton)
            events.mouseMove(middle, 65, 30, 30)
            events.mouseRelease(middle, 65, 30, Qt.LeftButton)
            root.check(root.requests.length === 2, "horizontal swipe cancels tap")
            fake.healthy = false
            events.mouseClick(bottom, 35, 30, Qt.LeftButton)
            root.check(root.requests.length === 2, "offline input disabled")
            fake.healthy = true
            fake.supportsSystem = false
            events.mouseClick(middle, 35, 30, Qt.LeftButton)
            root.check(root.requests.length === 2, "legacy rollback never fakes middle mode")
            fake.mode = "normal"
            events.wait(220)
            root.check(Math.abs(thumb.y + thumb.height - track.height) < 0.1, "external changes return flush to bottom")
            console.info("AWAKE_TEST_PASSED")
            Qt.quit()
        }
    }
}
