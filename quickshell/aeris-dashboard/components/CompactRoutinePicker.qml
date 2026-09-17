import QtQuick
import QtQuick.Controls as Controls

// Home-sized chooser; the full Work picker remains unchanged.
Rectangle {
    id: root
    radius: Theme.radius
    color: Theme.surface
    property real contentInset: Theme.gridContentInset
    property QtObject timerService: TomatService
    property string candidate: ""
    property bool submitting: false
    readonly property var routines: timerService.state.templates || []
    readonly property int candidateIndex: routines.findIndex(item => item.id === candidate)
    readonly property var selected: candidateIndex >= 0 ? routines[candidateIndex] : null
    readonly property string warning: timerService.commandError || timerService.errorText
        || (timerService.state.templateErrors || []).join("\n")
    readonly property bool usable: visible && timerService.healthy && !timerService.pending && !!selected

    function resetSelection() {
        const preferred = timerService.state.selectedId || ""
        candidate = routines.some(item => item.id === preferred) ? preferred : routines.length ? routines[0].id : ""
        submitting = false
    }
    function browse(delta) {
        if (!usable || routines.length < 2) return
        candidate = routines[(candidateIndex + delta + routines.length) % routines.length].id
    }
    function apply(mode) {
        if (!usable || (mode !== "next" && mode !== "now")) return
        submitting = true
        timerService.chooseTemplate(candidate, mode)
    }
    onVisibleChanged: if (visible) resetSelection()
    onRoutinesChanged: if (visible && candidateIndex < 0 && !submitting) resetSelection()
    Component.onCompleted: if (visible) resetSelection()
    Connections {
        target: root.timerService
        function onCommandCompleted(success) {
            if (root.submitting && success) root.timerService.pickerOpen = false
            root.submitting = false
        }
    }
    MouseArea { anchors.fill: parent; onWheel: wheel => wheel.accepted = true }

    Item {
        anchors.fill: parent
        anchors.margins: root.contentInset
        Item {
            id: header
            anchors.top: parent.top
            width: parent.width; height: 42
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "ROUTINE"
                color: Theme.teal
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sectionTitleSize
            }
            Item {
                objectName: "compact-routine-close"
                anchors.right: parent.right
                width: 42; height: 42
                Accessible.role: Accessible.Button
                Accessible.name: "Close routines"
                Accessible.onPressAction: root.timerService.pickerOpen = false
                Text { anchors.centerIn: parent; text: "×"; color: Theme.muted; font.pixelSize: 28 }
                TapHandler { onTapped: root.timerService.pickerOpen = false }
            }
        }
        Item {
            anchors.top: header.bottom
            anchors.topMargin: Theme.spacingUnit
            anchors.bottom: actions.top
            anchors.bottomMargin: Theme.spacingUnit
            width: parent.width
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: Theme.spacingUnit
                Item {
                    width: parent.width; height: 44
                    Text {
                        objectName: "compact-routine-name"
                        anchors.centerIn: parent
                        width: parent.width - 2 * (44 + Theme.spacingUnit)
                        text: root.selected ? root.selected.name : "No routines"
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        elide: Text.ElideRight
                    }
                    Repeater {
                        model: [-1, 1]
                        delegate: Item {
                            required property int modelData
                            objectName: modelData < 0 ? "compact-routine-previous" : "compact-routine-next"
                            x: modelData < 0 ? 0 : parent.width - width
                            width: 44; height: 44
                            opacity: root.usable && root.routines.length > 1 ? 1 : 0.35
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData < 0 ? "Previous routine" : "Next routine"
                            Accessible.onPressAction: root.browse(modelData)
                            ThemeIcon {
                                anchors.centerIn: parent
                                name: "chevron-up"
                                rotation: parent.modelData < 0 ? -90 : 90
                                width: 24; height: 24; color: Theme.muted
                            }
                            TapHandler { enabled: root.usable; onTapped: root.browse(parent.modelData) }
                        }
                    }
                }
                Text {
                    objectName: "compact-routine-detail"
                    width: parent.width
                    text: root.timerService.pending ? "APPLYING…" : root.warning ? "CHECK ROUTINES"
                        : root.selected ? root.selected.work_minutes + " / " + root.selected.break_minutes
                            + " / " + root.selected.long_break_minutes + " min" : "Add one in Obsidian"
                    horizontalAlignment: Text.AlignHCenter
                    color: root.warning ? Theme.red : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    Controls.ToolTip.visible: detailHover.hovered
                    Controls.ToolTip.text: root.warning || "Focus / short break / long break"
                    HoverHandler { id: detailHover }
                }
            }
        }
        Row {
            id: actions
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: 2 * Theme.spacingUnit
            Repeater {
                model: root.timerService.state.phase === "Idle" ? ["next"] : ["next", "now"]
                delegate: Rectangle {
                    required property string modelData
                    objectName: "compact-routine-apply-" + modelData
                    width: root.timerService.state.phase === "Idle" ? actions.width : (actions.width - actions.spacing) / 2
                    height: 48
                    radius: Theme.spacingUnit
                    color: modelData === "next" ? Theme.tintedSurface(Theme.teal, 0.18) : Theme.raised
                    opacity: root.usable ? 1 : 0.4
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData === "next" ? "Use routine for next session" : "Restart current timer with this routine"
                    Accessible.onPressAction: root.apply(modelData)
                    Text {
                        anchors.centerIn: parent
                        text: root.timerService.state.phase === "Idle" ? "Use template" : parent.modelData === "next" ? "Use next" : "Restart"
                        color: parent.modelData === "next" ? Theme.teal : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                    }
                    TapHandler { enabled: root.usable; gesturePolicy: TapHandler.DragThreshold; onTapped: root.apply(parent.modelData) }
                }
            }
        }
    }
}
