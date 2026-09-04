import QtQuick

Rectangle {
    id: root

    signal clicked()

    property string symbol: "▶"
    property color accent: Theme.teal
    property bool primary: false
    property bool available: true
    property bool selected: false

    implicitWidth: 52
    implicitHeight: 52
    radius: width / 2
    color: root.primary ? (touch.pressed && root.available ? Qt.darker(Theme.green, 1.15) : Theme.green)
        : (touch.pressed && root.available ? "#4a344158" : "transparent")
    border.width: 0
    opacity: root.available ? 1 : 0.42

    Behavior on color { ColorAnimation { duration: 100 } }

    ThemeIcon {
        anchors.centerIn: parent
        name: root.symbol === "⏮" ? "skip-previous"
            : root.symbol === "⏭" ? "skip-next"
            : root.symbol === "⏸" ? "pause" : "play"
        color: root.primary ? Theme.surface : (root.available ? Theme.yellow : Theme.inactive)
        width: root.primary ? 32 : 30
        height: width
    }

    TapHandler {
        id: touch
        enabled: root.available
        gesturePolicy: TapHandler.ReleaseWithinBounds
        grabPermissions: PointerHandler.TakeOverForbidden
        onTapped: root.clicked()
    }
}
