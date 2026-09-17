import QtQuick
import QtQuick.Controls as Controls

Rectangle {
    id: root
    property QtObject sleepService: AwakeService
    property real contentMargin: Theme.gridContentInset
    readonly property string mode: sleepService.mode
    readonly property string switchMode: sleepService.pending ? sleepService.requestedMode : mode
    readonly property bool usable: sleepService.healthy && !sleepService.pending
    readonly property color accent: mode === "full" ? Theme.yellow
        : mode === "system" ? Theme.teal : Theme.inactive
    readonly property var modes: ["full", "system", "normal"]
    readonly property var icons: ["monitor", "coffee", "reference-moon"]
    readonly property var descriptions: ["Fully awake — keep the computer and display on",
        "Computer awake — allow the display to turn off", "Normal — use regular power settings"]

    implicitWidth: 94
    implicitHeight: 206
    radius: Theme.radius
    color: mode !== "normal" ? Theme.tintedSurface(accent, Theme.controlTint) : Theme.surface
    border.width: 0
    opacity: sleepService.healthy ? 1 : 0.5
    Behavior on color { ColorAnimation { duration: 220 } }

    Rectangle {
        id: track
        objectName: "awake-track"
        anchors.fill: parent
        anchors.margins: root.contentMargin
        radius: Theme.radius
        color: Theme.raised
        border.width: 0
        readonly property real thumbSize: height / 3
        readonly property real endInset: 0
        readonly property real step: (height - 2 * endInset - thumbSize) / 2

        Rectangle {
            id: thumb
            objectName: "awake-thumb"
            anchors.horizontalCenter: parent.horizontalCenter
            width: track.width
            height: track.thumbSize
            radius: track.radius
            y: track.endInset + Math.max(0, root.modes.indexOf(root.switchMode)) * track.step
            color: root.accent
            Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        Repeater {
            model: 3
            Item {
                id: choice
                required property int index
                objectName: "awake-" + root.modes[index]
                width: track.width
                height: track.height / 3
                y: index * height
                readonly property real iconCenterY: track.endInset + track.thumbSize / 2 + index * track.step
                readonly property bool selected: root.switchMode === root.modes[index]
                readonly property bool enabledMode: root.usable && (index !== 1 || root.sleepService.supportsSystem)
                Accessible.role: Accessible.RadioButton
                Accessible.name: root.descriptions[index]
                Accessible.checkable: true
                Accessible.checked: root.mode === root.modes[index]
                Accessible.onPressAction: { if (enabledMode) root.sleepService.select(root.modes[index]) }

                ThemeIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: choice.iconCenterY - choice.y - height / 2
                    width: 28
                    height: width
                    name: root.icons[choice.index]
                    color: choice.selected ? Theme.surface : Theme.muted
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
                HoverHandler { id: hover }
                Controls.ToolTip.visible: hover.hovered
                Controls.ToolTip.text: root.sleepService.errorText || root.descriptions[index]
                TapHandler {
                    enabled: choice.enabledMode
                    // A horizontal page flick cancels selection rather than changing mode.
                    gesturePolicy: TapHandler.DragThreshold
                    onTapped: root.sleepService.select(root.modes[choice.index])
                }
            }
        }
    }
}
