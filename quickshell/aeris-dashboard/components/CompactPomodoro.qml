import QtQuick
import QtQuick.Shapes
import QtQuick.Controls as Controls

// Home's small presentation of the same session used by the full Work tile.
// No local countdown clock or polling; controls share the existing service.
Item {
    id: root
    property bool presentationActive: true
    property QtObject timerService: TomatService
    property var state: ({phase: "Idle", remaining: 1500, progress: 0, paused: false})
    Binding on state {
        when: root.presentationActive
        value: root.timerService.state
        restoreMode: Binding.RestoreNone
    }
    readonly property bool idle: state.phase === "Idle"
    readonly property int stageCount: Math.max(1, Number(state.sessions) || 4)
    readonly property int currentStage: Math.max(0, Math.min(stageCount - 1, (Number(state.session) || 1) - 1))
    readonly property bool usable: presentationActive && timerService.healthy && !timerService.pending
    property bool seekAwaiting: false
    property int requestedElapsed: 0
    property int requestedDuration: 1500
    readonly property int remaining: scrub.adjusting ? scrub.capturedDuration - scrub.previewElapsed
        : seekAwaiting ? requestedDuration - requestedElapsed
        : Math.max(0, Math.floor(Number(state.remaining) || 0))
    readonly property color phaseColor: idle || state.phase === "Work" ? Theme.mauve : Theme.green
    readonly property real remainingFraction: timerService.healthy
        ? Math.max(0, Math.min(1, 1 - (scrub.adjusting ? scrub.previewProgress
            : seekAwaiting ? requestedElapsed / requestedDuration : Number(state.progress) || 0))) : 0
    Connections {
        target: root.timerService
        function onCommandCompleted(success) { root.seekAwaiting = false }
    }

    function activate(action) {
        if (!usable || timerService.pickerOpen) return
        if (action === "templates") timerService.pickerOpen = true
        else timerService.send(action)
    }

    Item {
        id: stageRail
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: controls.width

        Column {
            id: stageDots
            objectName: "compact-timer-stages"
            anchors.centerIn: parent
            readonly property real dotSize: Math.min(10, parent.height / (root.stageCount * 2 - 1))
            spacing: dotSize
            Repeater {
                model: root.stageCount
                Rectangle {
                    required property int index
                    objectName: "compact-timer-stage-" + index
                    width: stageDots.dotSize
                    height: width
                    radius: width / 2
                    color: root.timerService.healthy && index === root.currentStage ? root.phaseColor : "transparent"
                    border.width: 1.5
                    border.color: root.timerService.healthy && index === root.currentStage ? root.phaseColor : Theme.inactive
                }
            }
        }
    }

    Item {
        id: ring
        objectName: "compact-timer-ring"
        anchors.centerIn: parent
        width: Math.min(parent.height, parent.width - 2 * (controls.width + 2 * Theme.spacingUnit))
        height: width
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            antialiasing: true
            border.width: Theme.spacingUnit
            border.color: Theme.raised
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: root.remainingFraction > 0
            ShapePath {
                strokeWidth: Theme.spacingUnit
                strokeColor: root.phaseColor
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: (ring.width - Theme.spacingUnit) / 2
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: root.remainingFraction * 360
                }
            }
        }
        Rectangle {
            // A small grab marker on the remaining-time tip, within the inset.
            readonly property real angle: -Math.PI / 2 + root.remainingFraction * 2 * Math.PI
            readonly property real orbit: (ring.width - Theme.spacingUnit) / 2
            width: Theme.spacingUnit; height: width
            radius: width / 2
            antialiasing: true
            color: Theme.text
            visible: root.timerService.healthy && !root.idle && root.state.canSeek === true
            x: ring.width / 2 + Math.cos(angle) * orbit - width / 2
            y: ring.height / 2 + Math.sin(angle) * orbit - height / 2
        }
        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingUnit
            Text {
                objectName: "compact-timer-countdown"
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.timerService.healthy
                    ? String(Math.floor(root.remaining / 60)).padStart(2, "0") + ":"
                        + String(root.remaining % 60).padStart(2, "0") : "--:--"
                color: Theme.text
                font.family: Theme.clockBoldFontFamily
                font.weight: Font.Bold
                font.pixelSize: 48
            }
            Text {
                objectName: "compact-timer-status"
                anchors.horizontalCenter: parent.horizontalCenter
                text: !root.timerService.healthy ? "OFFLINE" : scrub.adjusting ? "RELEASE TO SET"
                    : root.timerService.pending ? "UPDATING"
                    : root.timerService.commandError ? "TRY AGAIN" : root.state.paused ? "PAUSED"
                    : root.state.workout && (root.state.phase === "Break" || root.state.phase === "LongBreak")
                        ? root.state.workout.completed + "/" + root.state.workout.total + " SETS"
                    : root.state.phase === "LongBreak" ? "LONG BREAK" : root.state.phase === "Break" ? "BREAK" : "FOCUS"
                color: root.phaseColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headerDetailSize
            }
        }
        TimerScrubber {
            id: scrub
            objectName: "compact-timer-scrubber"
            anchors.fill: parent
            circular: true
            enabled: root.usable && !root.idle && root.state.canSeek === true && !root.timerService.pickerOpen
            duration: root.state.duration || 1500
            progress: root.state.progress || 0
            revision: root.state.revision || ""
            onAdjustingChanged: root.timerService.scrubbing = adjusting
            onCommitted: (elapsedSeconds, expectedRevision) => {
                root.requestedElapsed = elapsedSeconds
                root.requestedDuration = capturedDuration
                root.seekAwaiting = true
                root.timerService.seek(elapsedSeconds, expectedRevision)
            }
        }
    }

    Column {
        id: controls
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 2 * Theme.spacingUnit
        Repeater {
            model: ["templates", "toggle", "reset"]
            delegate: Rectangle {
                id: control
                required property string modelData
                objectName: "compact-timer-" + modelData
                readonly property bool primary: modelData === "toggle"
                readonly property bool usable: root.usable && !root.timerService.pickerOpen
                    && (modelData !== "reset" || !root.idle)
                width: 52; height: 52
                radius: width / 2
                color: primary ? Theme.green : "transparent"
                opacity: usable ? (tap.pressed ? 0.7 : 1) : 0.4
                Accessible.role: Accessible.Button
                Accessible.name: modelData === "templates" ? "Choose timer routine"
                    : !primary ? "Reset session" : root.idle ? "Start"
                    : root.state.paused ? "Resume" : "Pause"
                Accessible.onPressAction: if (control.usable) root.activate(modelData)
                Controls.ToolTip.visible: hover.hovered
                Controls.ToolTip.text: root.timerService.commandError || root.timerService.errorText || Accessible.name
                HoverHandler { id: hover }
                TapHandler {
                    id: tap
                    enabled: control.usable
                    gesturePolicy: TapHandler.DragThreshold
                    onTapped: root.activate(control.modelData)
                }
                ThemeIcon {
                    anchors.centerIn: parent
                    width: control.primary ? 34 : 24
                    height: width
                    name: control.modelData === "templates" ? "folder"
                        : !control.primary ? "reset" : !root.idle && !root.state.paused ? "pause" : "play"
                    color: control.primary ? Theme.surface : Theme.muted
                }
            }
        }
    }
}
