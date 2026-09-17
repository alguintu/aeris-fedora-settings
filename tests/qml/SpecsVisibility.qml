import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import "components" as Components
import "pages" as Pages

ShellRoot {
    id: root
    property int step: 0
    property bool presented: true
    property real pausedAt: 0
    property var backdrop: null
    property bool sawDrag: false
    function check(ok, message) {
        if (!ok) {
            console.error("SPECS_VISIBILITY_TEST_FAILED: " + message)
            Qt.exit(1)
        }
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    Window {
        visible: true
        width: 1920; height: 480
        Components.PageViewport {
            id: viewport
            anchors.fill: parent
            dragging: true
            Pages.SpecsPage {
                id: specs
                width: viewport.pageWidth; height: viewport.pageHeight
                presentationActive: root.presented && viewport.pageIsVisible(specs)
            }
            Item { width: viewport.pageWidth; height: viewport.pageHeight }
        }
        DragHandler {
            target: null
            xAxis.enabled: true; yAxis.enabled: false
            grabPermissions: PointerHandler.CanTakeOverFromItems
            onActiveChanged: if (active) root.sawDrag = true
        }
    }
    TestCase { id: events; name: "SpecsAnimationInput"; when: false }
    Timer {
        interval: 300; repeat: true; running: true
        onTriggered: {
            root.step++
            if (root.step === 1) {
                root.backdrop = root.find(specs, "specs-case-backdrop")
                root.check(root.backdrop !== null, "CH260 backdrop exists on real Specs page")
                root.check(root.backdrop.backdropMode, "decorative mode uses shared pixel shader")
                root.check(root.backdrop.animationRegistered && root.backdrop.elapsed > 0, "onscreen grid animates")
                root.check(root.backdrop.elapsed % 250 === 0, "pixel motion advances only in held 250ms frames")
                root.check(Components.DecorativeClock.users === 0, "pixel grid does not wake the 60Hz clock")
                const cycle = root.backdrop.backdropCycleMs
                const card = root.find(specs, "specs-identity")
                root.backdrop.elapsed = 1250
                events.mouseClick(card, card.width / 2, card.height / 2, Qt.LeftButton)
                root.check(root.backdrop.backdropAnimationIndex === 1 && root.backdrop.elapsed === cycle,
                    "click selects chase and resets its cycle")
                const touch = events.touchEvent(card)
                touch.press(0, card, card.width / 2, card.height / 2).commit()
                touch.release(0, card, card.width / 2, card.height / 2).commit()
                root.check(root.backdrop.backdropAnimationIndex === 2, "touch selects stars")
                events.mouseClick(card, 5, 5, Qt.LeftButton)
                root.check(root.backdrop.backdropAnimationIndex === 0 && root.backdrop.elapsed === 0,
                    "tap in tile inset wraps to rain")
                events.mousePress(card, 30, 60, Qt.LeftButton)
                events.mouseMove(card, 130, 60, 30)
                events.mouseRelease(card, 130, 60, Qt.LeftButton)
                root.check(root.sawDrag && root.backdrop.backdropAnimationIndex === 0,
                    "page drag takes over without advancing animation")
                root.backdrop.elapsed = cycle - 250
                if (Quickshell.env("AERIS_TEST_RHI"))
                    root.check(root.backdrop.blendStatus !== ShaderEffect.Error, "backdrop shader loads")
                viewport.dragOffset = -viewport.width / 2
                root.check(root.backdrop.animationRegistered, "partial visibility keeps motion")
                viewport.dragOffset = 0
                viewport.pageIndex = 1
                root.check(specs.visible, "offscreen Specs keeps its layout slot")
                root.check(!root.backdrop.animationRegistered, "offscreen grid stops its pixel timer")
                root.pausedAt = root.backdrop.elapsed
            } else if (root.step === 2) {
                root.check(root.backdrop.elapsed === root.pausedAt, "offscreen phase is frozen")
                root.check(Components.DecorativeClock.users === 0, "no hidden decorative clock consumers")
                viewport.pageIndex = 0
                root.check(root.backdrop.animationRegistered, "onscreen grid resumes")
                root.check(root.backdrop.elapsed === root.pausedAt, "resume preserves phase")
                root.presented = false
                root.check(!root.backdrop.animationRegistered, "minimize pauses grid")
            } else if (root.step === 3) {
                root.check(root.backdrop.elapsed === root.pausedAt, "minimize does no ticking")
                root.presented = true
            } else {
                root.check(root.backdrop.elapsed > root.pausedAt, "restore resumes grid")
                root.check(root.backdrop.backdropAnimationIndex === 1, "automatic cycling still advances after manual selection")
                console.info("SPECS_VISIBILITY_TEST_PASSED")
                Qt.quit()
            }
        }
    }
}
