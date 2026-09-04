import QtQuick

Rectangle {
    id: root
    radius: Theme.radius
    color: Theme.surface
    property string candidate: ""
    property bool submitting: false
    readonly property var routines: TomatService.state.templates || []
    readonly property string warning: TomatService.commandError || TomatService.errorText
        || (TomatService.state.templateErrors || []).join("\n")
    onVisibleChanged: {
        if (visible) {
            candidate = TomatService.state.selectedId || ""
            submitting = false
        }
    }
    // Cover the underlying controls while the chooser is open.
    MouseArea { anchors.fill: parent; onWheel: wheel => wheel.accepted = true }
    Connections {
        target: TomatService
        function onCommandCompleted(success) {
            if (root.submitting && success) TomatService.pickerOpen = false
            root.submitting = false
        }
    }
    function select(mode) {
        if (!candidate || TomatService.pending || !TomatService.healthy) return
        submitting = true
        TomatService.chooseTemplate(candidate, mode)
    }

    Item {
        anchors.fill: parent
        anchors.margins: 18
        Item {
            id: header
            anchors.top: parent.top
            width: parent.width
            height: 44
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "ROUTINES"
                color: Theme.teal
                font.family: Theme.fontFamily
                font.pixelSize: 20
            }
            Text {
                anchors.right: parent.right
                width: 44; height: 44
                text: "×"
                color: Theme.muted
                font.pixelSize: 30
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Accessible.role: Accessible.Button
                Accessible.name: "Close routines"
                Accessible.onPressAction: TomatService.pickerOpen = false
                TapHandler { onTapped: TomatService.pickerOpen = false }
            }
        }
        Text {
            id: current
            anchors.top: header.bottom
            width: parent.width
            height: 36
            text: TomatService.idle ? "Choose your next session"
                : "Running: " + (TomatService.state.activeName || "Tomat")
                    + "\nNext: " + (TomatService.state.selectedName || "—")
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: 13
            elide: Text.ElideRight
        }
        ListView {
            id: list
            anchors.top: current.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: feedback.top
            anchors.bottomMargin: 12
            spacing: 8
            clip: true
            model: root.routines
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                required property var modelData
                width: list.width
                height: 58
                radius: 8
                color: root.candidate === modelData.id ? Qt.alpha(Theme.teal, 0.17) : Theme.raised
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name
                Accessible.onPressAction: root.candidate = modelData.id
                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 3
                    Text {
                        width: parent.width
                        text: modelData.name
                        color: root.candidate === modelData.id ? Theme.teal : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        elide: Text.ElideRight
                    }
                    Text {
                        text: modelData.work_minutes + " / " + modelData.break_minutes + " / "
                            + modelData.long_break_minutes + " min · " + modelData.sessions + " rounds"
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }
                TapHandler {
                    enabled: !TomatService.pending
                    gesturePolicy: TapHandler.DragThreshold
                    onTapped: root.candidate = parent.modelData.id
                }
            }
        }
        Flickable {
            id: feedback
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: actions.top
            anchors.bottomMargin: 12
            height: root.warning ? 52 : 30
            contentHeight: feedbackText.height
            clip: true
            Text {
                id: feedbackText
                width: parent.width
                text: root.warning || (TomatService.idle ? "Edit routines in Obsidian."
                    : "Restart now replaces this timer.")
                wrapMode: Text.Wrap
                color: root.warning ? Theme.orange : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }
        Row {
            id: actions
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: 10
            Repeater {
                model: TomatService.idle ? ["next"] : ["next", "now"]
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool usable: !!root.candidate && TomatService.healthy && !TomatService.pending
                    width: TomatService.idle ? actions.width : (actions.width - 10) / 2
                    height: 48
                    radius: 8
                    color: modelData === "now" ? Qt.alpha(Theme.orange, 0.22) : Qt.alpha(Theme.green, 0.22)
                    opacity: usable ? 1 : 0.4
                    Accessible.role: Accessible.Button
                    Accessible.name: label.text
                    Accessible.onPressAction: { if (usable) root.select(modelData) }
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: TomatService.pending ? "…" : TomatService.idle ? "Use template"
                            : parent.modelData === "next" ? "Next session" : "Restart now"
                        color: parent.modelData === "now" ? Theme.orange : Theme.green
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                    }
                    TapHandler {
                        enabled: parent.usable
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        grabPermissions: PointerHandler.TakeOverForbidden
                        onTapped: root.select(parent.modelData)
                    }
                }
            }
        }
    }
}
