import QtQuick
import QtQuick.Window
import Quickshell
import "components" as Components

ShellRoot {
    id: root
    property int step: 0
    function check(ok, message) {
        if (!ok) {
            console.error("SLIDE_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }
    Window {
        visible: true; width: 400; height: 100
        Components.SlideReveal {
            id: slide
            anchors.fill: parent
            Rectangle { id: tile; anchors.fill: parent; color: "teal" }
        }
    }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            root.step++
            if (root.step === 1) {
                root.check(slide.interactive && slide.presentationActive, "open panel is active")
                root.check(!tile.parent.layer.enabled, "no extra layer at rest")
                slide.collapsed = true
                root.check(!slide.interactive, "disable controls immediately on collapse")
            } else if (root.step === 2) {
                root.check(slide.moving && slide.reveal > 0 && slide.reveal < 1, "collapse animates")
                root.check(tile.visible && !slide.fullyHidden, "do not vanish before sliding out")
                root.check(tile.width === 400 && tile.height === 100, "never resize the content")
                root.check(slide.panelOffset > 0 && tile.parent.layer.enabled, "translate as one layer")
                // Reverse a live collapse, as with a quick second click on the handle/tray.
                const before = slide.reveal
                slide.collapsed = false
                root.check(Math.abs(slide.reveal - before) < 0.01, "reversal does not jump")
            } else if (root.step === 5) {
                root.check(slide.interactive && slide.reveal === 1, "restore settles fully open")
                root.check(!tile.parent.layer.enabled, "release temporary layer after restore")
                slide.collapsed = true
            } else if (root.step === 8) {
                root.check(slide.fullyHidden && !tile.visible, "hidden panel stops rendering")
                root.check(!slide.presentationActive && !tile.parent.layer.enabled, "hidden panel is dormant")
                slide.collapsed = false
                root.check(!slide.interactive, "restoring controls wait until panel is in place")
            } else if (root.step === 9) {
                root.check(slide.moving && tile.visible && slide.reveal > 0, "restore animates into view")
            } else if (root.step === 11) {
                root.check(slide.interactive && slide.panelOffset === 0, "restore retains original layout")
                console.info("SLIDE_TEST_PASSED")
                Qt.quit()
            }
        }
    }
}
