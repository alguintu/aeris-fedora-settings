import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import "components" as Components

ShellRoot {
    id: root
    property int commits: 0
    property int elapsed: -1
    property string revision: ""
    function check(ok, message) {
        if (!ok) { console.error("TIMER_SEEK_TEST_FAILED: " + message); Qt.exit(1) }
    }
    Window {
        id: window
        visible: true; width: 296; height: 424
        Components.TimerScrubber {
            id: scrub
            anchors.fill: parent
            duration: 1500; revision: "7"; progress: 0.2
            onCommitted: (seconds, expected) => {
                root.commits++; root.elapsed = seconds; root.revision = expected
            }
        }
        DragHandler {
            id: pageSwipe
            enabled: !scrub.adjusting
            target: null
            xAxis.enabled: true; yAxis.enabled: false
            grabPermissions: PointerHandler.CanTakeOverFromItems
        }
    }
    TestCase { id: events; name: "DialInput"; when: false }
    Timer {
        interval: 100; running: true
        onTriggered: {
            root.check(!scrub.begin(85, 180), "body stays available for page swiping")
            root.check(scrub.begin(182, 180), "touch-friendly ring hit target")
            root.check(scrub.adjusting && scrub.previewProgress === 0.2, "press does not jump timer")
            scrub.update(184, 183)
            scrub.finish(false)
            root.check(root.commits === 0, "tap/jitter does not seek")
            scrub.begin(182, 180)
            scrub.update(24, 22)
            root.check(scrub.previewElapsed === 0, "top is start")
            scrub.update(24, 338)
            root.check(scrub.previewElapsed === 1499, "bottom stays within stage")
            scrub.update(182, 180)
            root.check(scrub.previewElapsed === 750, "middle is halfway")
            scrub.revision = "8"
            scrub.finish(false)
            root.check(root.commits === 1 && root.elapsed === 750 && root.revision === "7",
                "single release command uses revision captured at press")
            scrub.begin(182, 180)
            scrub.update(24, 22)
            scrub.finish(true)
            root.check(root.commits === 1 && !scrub.adjusting, "cancel discards preview")
            scrub.begin(182, 180)
            scrub.update(24, 22)
            scrub.enabled = false
            root.check(root.commits === 1 && !scrub.adjusting, "hidden/disabled cancels gesture")
            scrub.enabled = true
            events.mousePress(scrub, 182, 180, Qt.LeftButton)
            root.check(scrub.adjusting && !pageSwipe.enabled, "mouse press owns ring, not page")
            events.mouseMove(scrub, 140, 280, 30)
            root.check(scrub.moved && !pageSwipe.active, "mouse drag remains scrub")
            events.mouseRelease(scrub, 140, 280, Qt.LeftButton)
            root.check(root.commits === 2 && !scrub.adjusting && pageSwipe.enabled,
                "mouse release commits once and restores paging")
            const touch = events.touchEvent(scrub)
            touch.press(0, scrub, 182, 180).commit()
            root.check(scrub.adjusting && !pageSwipe.enabled, "touch press owns ring")
            touch.move(0, scrub, 140, 280).commit()
            touch.release(0, scrub, 140, 280).commit()
            root.check(root.commits === 3 && !scrub.adjusting, "touch release commits once")
            console.info("TIMER_SEEK_TEST_PASSED")
            Qt.quit()
        }
    }
}
