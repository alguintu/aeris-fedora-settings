import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls as Controls

Rectangle {
    id: root

    property bool awake: false
    property bool healthy: false
    property bool pending: false
    property bool requestedAwake: false
    // Position follows the tap; all colors continue to follow confirmed state.
    readonly property bool switchAwake: pending ? requestedAwake : awake
    property string errorText: ""
    readonly property color accent: Theme.yellow
    readonly property real contentScale: width / 72
    property real contentMargin: 18
    implicitWidth: 97
    implicitHeight: 206
    radius: Theme.radius
    color: awake ? Theme.tintedSurface(accent, Theme.controlTint) : Theme.surface
    border.width: 0
    opacity: healthy ? 1 : 0.5

    Accessible.name: "Prevent automatic sleep and screen locking"
    Accessible.role: Accessible.CheckBox
    Accessible.checked: awake
    Controls.ToolTip.visible: hover.hovered
    Controls.ToolTip.text: errorText || (awake
        ? "KDE prevent sleep and screen locking is ON. Tap to disable."
        : "KDE prevent sleep and screen locking is OFF. Tap to enable.")

    Behavior on color { ColorAnimation { duration: 220 } }

    function applyStatus(data) {
        try {
            const status = JSON.parse(data)
            root.healthy = status.ok === true
            if (root.healthy)
                root.awake = status.active === true
            root.errorText = status.error || ""
        } catch (error) {
            root.healthy = false
            root.errorText = "Unable to read sleep inhibitor status"
        }
    }

    function toggle() {
        if (!root.healthy || root.pending)
            return
        root.requestedAwake = !root.awake
        root.pending = true
        commandProcess.command = ["python3", Quickshell.shellPath("services/sleepctl.py"),
                                  "set", root.requestedAwake ? "on" : "off"]
        commandProcess.running = true
    }

    Process {
        id: statusProcess
        command: ["python3", Quickshell.shellPath("services/sleepctl.py"), "watch"]
        running: true
        stdout: SplitParser {
            onRead: data => { if (!root.pending) root.applyStatus(data) }
        }
        onExited: {
            root.healthy = false
            restartTimer.start()
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: statusProcess.running = true
    }

    Process {
        id: commandProcess
        stdout: SplitParser { onRead: data => root.applyStatus(data) }
        onExited: root.pending = false
    }

    Item {
        anchors.fill: parent
        anchors.margins: root.contentMargin

        ThemeIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: 42 * root.contentScale
            height: 46 * root.contentScale
            name: "coffee"
            color: root.awake ? root.accent : Theme.inactive
            Behavior on color { ColorAnimation { duration: 220 } }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 36 * root.contentScale
            height: 56 * root.contentScale
            radius: width / 2
            color: root.awake ? Theme.inset : Theme.inset
            border.width: 2
            border.color: root.awake ? root.accent : Theme.inactive
            Behavior on border.color { ColorAnimation { duration: 180 } }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: (root.switchAwake ? 4 : 24) * root.contentScale
                width: 28 * root.contentScale
                height: width
                radius: width / 2
                color: root.awake ? root.accent : Theme.inactive
                Behavior on y { NumberAnimation { duration: 180 } }
                Behavior on color { ColorAnimation { duration: 180 } }
            }
        }
    }

    HoverHandler { id: hover }
    TapHandler {
        enabled: root.healthy && !root.pending
        gesturePolicy: TapHandler.ReleaseWithinBounds
        grabPermissions: PointerHandler.TakeOverForbidden
        onTapped: root.toggle()
    }
}
