import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "components" as Components

ShellRoot {
    id: root
    property var choices: []
    function check(ok, message) {
        if (!ok) { console.error("COMPACT_ROUTINE_TEST_FAILED: " + message); Qt.exit(1) }
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    function textFits(item) {
        if (!item.visible) return
        if (item.text !== undefined && item.text.length) {
            const p = item.mapToItem(picker, 0, 0)
            check(p.x >= 12 - 0.01 && p.y >= 12 - 0.01
                && p.x + item.width <= 293.01 && p.y + item.height <= 194.01,
                "text keeps 12px inset: " + item.text)
            check(!item.truncated && item.contentWidth <= item.width + 0.01, "curated text fits: " + item.text)
        }
        for (const child of item.children || []) textFits(child)
    }
    QtObject {
        id: fake
        property var state: ({phase: "Work", selectedId: "classic", activeId: "classic", templates: [
            {id: "classic", name: "Classic", work_minutes: 25, break_minutes: 5, long_break_minutes: 15},
            {id: "deep", name: "Deep Work", work_minutes: 45, break_minutes: 5, long_break_minutes: 15},
            {id: "light", name: "Light Work", work_minutes: 20, break_minutes: 5, long_break_minutes: 10}
        ]})
        property bool pickerOpen: true
        property bool healthy: true
        property bool pending: false
        property string commandError: ""
        property string errorText: ""
        signal commandCompleted(bool success)
        function chooseTemplate(id, mode) { root.choices = root.choices.concat([{id: id, mode: mode}]); pending = true }
    }
    Window {
        visible: true; width: 305; height: 206
        Components.CompactRoutinePicker {
            id: picker
            width: 305; height: 206
            timerService: fake
            visible: fake.pickerOpen
        }
    }
    TestCase { id: events; name: "CompactRoutineInput"; when: false }
    Timer {
        interval: 250; running: true
        onTriggered: {
            root.check(picker.candidate === "classic", "opens at selected template")
            const next = root.find(picker, "compact-routine-next")
            const previous = root.find(picker, "compact-routine-previous")
            const useNext = root.find(picker, "compact-routine-apply-next")
            const restart = root.find(picker, "compact-routine-apply-now")
            events.mouseClick(next, 22, 22, Qt.LeftButton)
            root.check(picker.candidate === "deep" && root.choices.length === 0, "browsing does not alter active timer")
            root.textFits(picker)
            events.mouseClick(previous, 22, 22, Qt.LeftButton)
            events.mouseClick(previous, 22, 22, Qt.LeftButton)
            root.check(picker.candidate === "light", "previous wraps through routines")
            root.textFits(picker)
            events.mouseClick(useNext, 30, 24, Qt.LeftButton)
            root.check(root.choices.length === 1 && root.choices[0].id === "light"
                && root.choices[0].mode === "next" && fake.state.activeId === "classic", "Use next queues without restarting")
            events.mouseClick(restart, 30, 24, Qt.LeftButton)
            root.check(root.choices.length === 1, "pending blocks duplicate submission")
            fake.pending = false
            fake.commandError = "Test failure"
            fake.commandCompleted(false)
            root.check(picker.visible && picker.warning === "Test failure", "failure keeps chooser open")
            root.textFits(picker)
            fake.commandError = ""
            const touch = events.touchEvent(restart)
            touch.press(0, restart, 30, 24).commit()
            touch.release(0, restart, 30, 24).commit()
            root.check(root.choices.length === 2 && root.choices[1].mode === "now", "explicit Restart requests replacement")
            fake.pending = false
            fake.state = Object.assign({}, fake.state, {selectedId: "light"})
            fake.commandCompleted(true)
            root.check(!picker.visible && !fake.pickerOpen, "confirmed selection closes chooser")
            fake.pickerOpen = true
            root.check(picker.candidate === "light", "reopening follows confirmed selection")
            events.mouseClick(root.find(picker, "compact-routine-close"), 21, 21, Qt.LeftButton)
            root.check(!fake.pickerOpen && root.choices.length === 2, "close is non-mutating")
            fake.state = Object.assign({}, fake.state, {phase: "Idle"})
            fake.pickerOpen = true
            root.textFits(picker)
            fake.state = Object.assign({}, fake.state, {templates: []})
            root.check(!picker.usable, "empty routine set disables apply")
            root.textFits(picker)
            fake.healthy = false
            picker.apply("next")
            root.check(root.choices.length === 2, "offline and empty cannot dispatch")
            console.info("COMPACT_ROUTINE_TEST_PASSED")
            Qt.quit()
        }
    }
}
