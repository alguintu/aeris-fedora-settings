import QtQuick
import QtQuick.Window
import Quickshell
import "components" as Components

ShellRoot {
    id: root
    property int step: 0
    property real pausedAt: 0
    property var pulse: null
    function check(ok, message) {
        if (!ok) {
            console.error("MEDIA_VISIBILITY_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }
    function findPulse(item) {
        if (item.animationRegistered !== undefined && item.pixelMode !== undefined) return item
        for (const child of item.children) {
            const found = findPulse(child)
            if (found) return found
        }
        return null
    }
    Window {
        visible: true
        width: 540; height: 300
        Components.PageViewport {
            id: viewport
            anchors.fill: parent
            dragging: true
            Components.MediaControls {
                id: media
                width: viewport.pageWidth; height: viewport.pageHeight
                presentationActive: viewport.pageIsVisible(media)
            }
            Item { width: viewport.pageWidth; height: viewport.pageHeight }
        }
    }
    Timer {
        interval: 150; repeat: true; running: true
        onTriggered: {
            root.step++
            if (root.step === 1) {
                root.pulse = root.findPulse(media)
                root.check(root.pulse !== null, "real media placeholder exists")
                root.check(root.pulse.animationRegistered && root.pulse.elapsed > 0, "onscreen waves animate")
                viewport.dragOffset = -270
                root.check(root.pulse.animationRegistered, "partially visible waves keep animating")
                viewport.dragOffset = 0
                viewport.pageIndex = 1
                root.check(media.visible, "offscreen page remains in the QML row")
                root.check(!root.pulse.animationRegistered, "offscreen media releases the shared clock")
                root.pausedAt = root.pulse.elapsed
            } else if (root.step === 2) {
                root.check(root.pulse.elapsed === root.pausedAt, "offscreen waves do no ticking")
                root.check(Components.DecorativeClock.users === 0, "shared clock stops without consumers")
                viewport.pageIndex = 0
                root.check(root.pulse.elapsed === root.pausedAt, "return preserves wave phase")
                root.check(root.pulse.animationRegistered, "return registers waves again")
            } else {
                root.check(root.pulse.elapsed > root.pausedAt, "returned waves resume")
                console.info("MEDIA_VISIBILITY_TEST_PASSED")
                Qt.quit()
            }
        }
    }
}
