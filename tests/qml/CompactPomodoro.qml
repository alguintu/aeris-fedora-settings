import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "components" as Components

ShellRoot {
    id: root
    property var commands: []
    property var seeks: []
    function check(ok, message) {
        if (!ok) { console.error("COMPACT_POMODORO_TEST_FAILED: " + message); Qt.exit(1) }
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
        id: fakeService
        property var state: ({phase: "Idle", remaining: 1500, progress: 0, paused: false})
        property bool healthy: true
        property bool pending: false
        property string commandError: ""
        property string errorText: ""
        property bool pickerOpen: false
        property bool scrubbing: false
        signal commandCompleted(bool success)
        function send(action) { root.commands = root.commands.concat([action]) }
        function seek(seconds, revision) {
            root.seeks = root.seeks.concat([{seconds: seconds, revision: revision}])
            pending = true
        }
    }
    Window {
        visible: true
        width: 411; height: 206
        color: Components.Theme.surface
        Components.CompactPomodoro {
            id: timer
            x: 12; y: 12; width: 387; height: 182
            timerService: fakeService
        }
    }
    TestCase { id: events; name: "CompactTimerInput"; when: false }
    Timer {
        interval: 250; running: true
        onTriggered: {
            const toggle = root.find(timer, "compact-timer-toggle")
            const templates = root.find(timer, "compact-timer-templates")
            const reset = root.find(timer, "compact-timer-reset")
            const countdown = root.find(timer, "compact-timer-countdown")
            const status = root.find(timer, "compact-timer-status")
            const ring = root.find(timer, "compact-timer-ring")
            root.check(countdown.text === "25:00" && status.text === "FOCUS", "idle presentation")
            root.check(ring.width === ring.height && ring.width === 182, "ring stays round and fills height")
            const dots = root.find(timer, "compact-timer-stages")
            const dotPosition = dots.mapToItem(timer, 0, 0)
            root.check(Math.abs(ring.x + ring.width / 2 - timer.width / 2) <= 0.5,
                "ring centers between equal side rails with pixel-rounded anchors")
            root.check(dotPosition.x + dots.width < ring.x && dotPosition.y + dots.height / 2 === timer.height / 2,
                "vertical stage dots sit left of ring and center vertically")
            root.check(timer.stageCount === 4 && timer.currentStage === 0, "default cycle indicators")
            fakeService.state = {phase: "Work", remaining: 750, progress: 0.5, sessions: 6, session: 3}
            root.check(timer.stageCount === 6 && timer.currentStage === 2,
                "indicators follow real routine length and session")
            root.check(root.find(timer, "compact-timer-stage-2").color.toString() === timer.phaseColor.toString(),
                "current session is filled")
            fakeService.state = {phase: "Break", remaining: 300, progress: 0, paused: false, workout: {completed: 2, total: 6}}
            root.check(status.text === "2/6 SETS", "break progress uses shared workout log")
            fakeService.state = {phase: "Idle", remaining: 1500, progress: 0, paused: false}
            root.check(toggle.y - templates.y === reset.y - toggle.y, "three controls have symmetric spacing")
            events.mouseClick(templates, 26, 26, Qt.LeftButton)
            root.check(fakeService.pickerOpen && root.commands.length === 0, "template button opens shared chooser, not a timer command")
            fakeService.pickerOpen = false
            const resetPosition = reset.mapToItem(timer, 0, 0)
            root.check(resetPosition.x + reset.width === timer.width
                && resetPosition.y + reset.height === timer.height, "controls pin to inner bottom/right")
            events.mouseClick(reset, 26, 26, Qt.LeftButton)
            root.check(root.commands.length === 0, "reset disabled before start")
            events.mouseClick(toggle, 26, 26, Qt.LeftButton)
            root.check(root.commands.join() === "toggle", "start routes to service")
            fakeService.state = {phase: "Work", remaining: 750, progress: 0.5, paused: false}
            root.check(countdown.text === "12:30" && timer.remainingFraction === 0.5, "live countdown and remaining ring")
            const touch = events.touchEvent(toggle)
            touch.press(0, toggle, 26, 26).commit()
            touch.release(0, toggle, 26, 26).commit()
            root.check(root.commands.join() === "toggle,toggle", "pause touch routes to same service")
            fakeService.state = {phase: "Work", remaining: 750, progress: 0.5, paused: true}
            root.check(status.text === "PAUSED", "paused state")
            events.mouseClick(reset, 26, 26, Qt.LeftButton)
            root.check(root.commands.join() === "toggle,toggle,reset", "reset routes to service")
            events.mousePress(toggle, 26, 26, Qt.LeftButton)
            events.mouseMove(toggle, 100, 26, 30)
            events.mouseRelease(toggle, 100, 26, Qt.LeftButton)
            root.check(root.commands.length === 3, "drag cancels button tap")
            fakeService.pending = true
            events.mouseClick(toggle, 26, 26, Qt.LeftButton)
            root.check(root.commands.length === 3 && status.text === "UPDATING", "pending prevents duplicate command")
            fakeService.pending = false
            fakeService.state = {phase: "LongBreak", remaining: 5999, progress: 0.25, paused: false,
                sessions: 8, session: 8}
            root.check(timer.stageCount === 8 && timer.currentStage === 7 && dots.height <= timer.height,
                "longest supported routine fits the vertical rail")
            root.check(status.text === "LONG BREAK" && countdown.text === "99:59", "long break presentation")
            root.check(countdown.width <= ring.width - 24 && status.width <= ring.width - 24,
                "time and longest stage label fit within ring")
            timer.presentationActive = false
            fakeService.state = {phase: "Break", remaining: 300, progress: 0, paused: false}
            root.check(countdown.text === "99:59" && timer.stageCount === 8 && timer.currentStage === 7,
                "offscreen countdown and dots stay frozen")
            events.mouseClick(toggle, 26, 26, Qt.LeftButton)
            root.check(root.commands.length === 3, "inactive controls do not dispatch")
            timer.presentationActive = true
            root.check(countdown.text === "05:00" && status.text === "BREAK" && timer.stageCount === 4,
                "return catches up to shared state and session dots")
            fakeService.commandError = "Test error"
            root.check(status.text === "TRY AGAIN", "command failure remains visible")
            fakeService.healthy = false
            root.check(countdown.text === "--:--" && status.text === "OFFLINE", "offline does not show stale countdown")
            events.mouseClick(toggle, 26, 26, Qt.LeftButton)
            root.check(root.commands.length === 3, "offline controls disabled")

            fakeService.healthy = true
            fakeService.commandError = ""
            fakeService.state = {phase: "Work", remaining: 750, duration: 1500,
                progress: 0.5, paused: true, canSeek: true, revision: "r1"}
            const scrub = root.find(timer, "compact-timer-scrubber")
            root.check(!scrub.hit(91, 91), "ring center stays available for page swiping")
            events.mousePress(scrub, 91, 176, Qt.LeftButton)
            root.check(fakeService.scrubbing && countdown.text === "12:30", "ring grab blocks paging without jumping")
            events.mouseMove(scrub, 6, 91, 30)
            root.check(countdown.text === "18:45" && root.seeks.length === 0, "clockwise drag previews more time without IPC")
            fakeService.state = Object.assign({}, fakeService.state, {revision: "r2"})
            events.mouseRelease(scrub, 6, 91, Qt.LeftButton)
            root.check(root.seeks.length === 1 && root.seeks[0].seconds === 375
                && root.seeks[0].revision === "r1", "one seek uses revision captured at press")
            root.check(!fakeService.scrubbing && countdown.text === "18:45", "pending seek retains preview and releases page lock")
            fakeService.pending = false
            fakeService.commandError = "Seek rejected"
            fakeService.commandCompleted(false)
            root.check(countdown.text === "12:30", "failed seek restores confirmed time")
            fakeService.commandError = ""
            const ringTouch = events.touchEvent(scrub)
            ringTouch.press(0, scrub, 91, 176).commit()
            ringTouch.move(0, scrub, 176, 91).commit()
            ringTouch.release(0, scrub, 176, 91).commit()
            root.check(root.seeks.length === 2 && root.seeks[1].seconds === 1125,
                "counterclockwise touch reduces remaining time")
            fakeService.state = Object.assign({}, fakeService.state, {remaining: 375, progress: 0.75, revision: "r3"})
            fakeService.pending = false
            fakeService.commandCompleted(true)
            root.check(countdown.text === "06:15" && fakeService.state.paused, "seek confirmation preserves paused state")
            scrub.begin(176, 91)
            scrub.update(91, 6)
            timer.presentationActive = false
            root.check(!fakeService.scrubbing && root.seeks.length === 2, "hiding mid-drag cancels without seek")
            timer.presentationActive = true
            scrub.progress = 0.01
            scrub.begin(88, 6)
            scrub.update(110, 8)
            root.check(scrub.previewProgress === 0, "crossing the top clamps rather than wrapping to end")
            scrub.finish(true)
            root.check(root.seeks.length === 2, "cancel never sends a seek")
            console.info("COMPACT_POMODORO_TEST_PASSED")
            Qt.quit()
        }
    }
}
